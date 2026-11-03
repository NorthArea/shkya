extends Node3D
## Original Quaternius male prefab and original animation keys, in place.
## Player owns physics; this provider owns only mesh, source AnimationTree and presentation.
const MODEL := preload("res://addons/quaternius_ik_rigged/Models_with_rigging/Master_Rigged.tscn")
const SOURCE_IDLE_FLOOR := 0.035
const WALK_NATIVE_SPEED := 1.00708753
const JOG_NATIVE_SPEED := 5.20758268
const RUN_NATIVE_SPEED := 9.11940099
const PREFIX := "UAL1_Standard/"
const BONE_ALIASES := {
	"root":"Root","hips":"Hips","pelvis":"Hips","spine":"Spine","chest":"Chest","head":"Head","neck":"Neck",
	"spine_01":"Spine","spine_02":"Chest","spine_03":"UpperChest","neck_01":"Neck",
	"clavicle_l":"LeftShoulder","upperarm_l":"LeftUpperArm","lowerarm_l":"LeftLowerArm","hand_l":"LeftHand","thigh_l":"LeftUpperLeg","calf_l":"LeftLowerLeg","foot_l":"LeftFoot","ball_l":"LeftToes",
	"clavicle_r":"RightShoulder","upperarm_r":"RightUpperArm","lowerarm_r":"RightLowerArm","hand_r":"RightHand","thigh_r":"RightUpperLeg","calf_r":"RightLowerLeg","foot_r":"RightFoot","ball_r":"RightToes",
}
const XRAY_SOURCE := """shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;
uniform vec4 tint : source_color = vec4(0.62, 0.86, 1.0, 1.0);
void fragment() { ALBEDO = tint.rgb; ALPHA = tint.a; }
"""
var model: Node3D
var skeleton: Skeleton3D
var uniform_mesh: MeshInstance3D
var visible_height := 1.765
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var _meshes: Array[MeshInstance3D] = []
var _playback: AnimationNodeStateMachinePlayback
var _speed := 0.0
var _walk_speed := -1.0
var _grounded := true
var _mode: StringName = &"locomotion"
var _occupant := false
var _requested: StringName = &"Grounded"
var _hand_targets: Array[Vector3] = []
var _grip_offsets: Dictionary = {}
var _final_bone_poses: Array[Transform3D] = []
var _skin_surface_cache: Dictionary = {}
var _skin_mesh_resources: Dictionary = {}
var _model_base_y := 0.0

func configure(height: float, color: Color) -> void:
	visible_height = height
	model = MODEL.instantiate() as Node3D
	add_child(model)
	skeleton = model.get_node("Armature/GeneralSkeleton")
	animation_player = model.get_node("AnimationPlayer")
	uniform_mesh = skeleton.get_node("SuperHero_Male")
	for node in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)
	for modifier in skeleton.get_children():
		if modifier is SkeletonModifier3D:
			assert(is_zero_approx(modifier.influence), "Source gait must start without IK overrides")
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var points := posed_vertices()
	assert(not points.is_empty())
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	model.scale = Vector3.ONE * height / bounds.size.y
	model.rotation.y = PI
	model.position.y = -SOURCE_IDLE_FLOOR * model.scale.y
	_model_base_y = model.position.y
	for mesh in _meshes:
		var instance := mesh.mesh.duplicate() as ArrayMesh
		for surface in instance.get_surface_count():
			var material := instance.surface_get_material(surface).duplicate() as StandardMaterial3D
			material.albedo_color *= color
			material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
			material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
			material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
			material.stencil_reference = 1
			instance.surface_set_material(surface, material)
		mesh.mesh = instance
	_invalidate_skin_arrays()
	for side: String in ["Left", "Right"]:
		var hand := skeleton.get_bone_global_rest(bone_index(side + "Hand"))
		var fingers := skeleton.get_bone_global_rest(bone_index(side + "MiddleProximal"))
		_grip_offsets[side] = hand.affine_inverse() * hand.origin.lerp(fingers.origin, 0.7)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.skeleton_updated.connect(_capture_final_bones)
	_build_tree()
	reset_pose()

func _build_tree() -> void:
	animation_tree = AnimationTree.new()
	animation_tree.name = "HeroAnimationTree"
	model.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.root_node = animation_player.root_node
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var grounded := AnimationNodeBlendTree.new()
	for pair: Array in [["Idle", "Idle"], ["Walk", "Walk"], ["Jog", "Jog_Fwd"], ["Run", "Sprint"]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = PREFIX + pair[1]
		grounded.add_node(pair[0], clip)
		grounded.add_node(pair[0] + "Rate", AnimationNodeTimeScale.new())
		grounded.connect_node(pair[0] + "Rate", 0, pair[0])
	for name_: String in ["WalkJog", "JogRun", "Locomotion"]:
		var blend := AnimationNodeBlend2.new()
		blend.sync = true
		grounded.add_node(name_, blend)
	grounded.connect_node("WalkJog", 0, "WalkRate")
	grounded.connect_node("WalkJog", 1, "JogRate")
	grounded.connect_node("JogRun", 0, "WalkJog")
	grounded.connect_node("JogRun", 1, "RunRate")
	grounded.connect_node("Locomotion", 0, "IdleRate")
	grounded.connect_node("Locomotion", 1, "JogRun")
	grounded.connect_node("output", 0, "Locomotion")
	var machine := AnimationNodeStateMachine.new()
	machine.add_node("Grounded", grounded)
	for pair: Array in [["JumpStart", "Jump_Start"], ["Jump", "Jump"], ["JumpLand", "Jump_Land"], ["Punch", "Punch_Jab"], ["Driving", "Driving"]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = PREFIX + pair[1]
		machine.add_node(pair[0], clip)
	var states := ["Grounded", "JumpStart", "Jump", "JumpLand", "Punch", "Driving"]
	for from: String in states:
		for to: String in states:
			if from == to: continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.12
			if (from == "JumpStart" and to == "Jump") or (from in ["JumpLand", "Punch"] and to == "Grounded"):
				transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
				transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			machine.add_transition(from, to, transition)
	animation_tree.tree_root = machine
	animation_tree.active = true
	_playback = animation_tree.get("parameters/playback")

func _ready() -> void:
	if animation_tree != null: reset_pose()

func _process(delta: float) -> void:
	if animation_tree != null and _mode != &"hidden": _sample(delta)

func supports_manual_bone_interpolation() -> bool:
	return false

func prepare_locomotion() -> void:
	pass

func update_locomotion(velocity: Vector3, grounded: bool, mode: StringName, _delta: float, vertical_speed := 0.0, _action_phase := 0.0) -> void:
	if _occupant: return
	_speed = Vector2(velocity.x, velocity.z).length() if _walk_speed < 0 else _walk_speed
	if grounded != _grounded:
		_requested = &"JumpLand" if grounded else &"JumpStart" if vertical_speed > 0.0 else &"Jump"
	if mode != _mode:
		if mode == &"punch": _requested = &"Punch"
		elif _mode == &"punch" or _mode == &"hidden": _requested = &"Grounded" if grounded else &"Jump"
	_grounded = grounded
	_mode = mode
	animation_tree.active = mode != &"hidden"

func _sample(delta: float) -> void:
	animation_tree.set("parameters/Grounded/IdleRate/scale", 1.0)
	animation_tree.set("parameters/Grounded/WalkRate/scale", _speed / WALK_NATIVE_SPEED)
	animation_tree.set("parameters/Grounded/JogRate/scale", _speed / JOG_NATIVE_SPEED)
	animation_tree.set("parameters/Grounded/RunRate/scale", _speed / RUN_NATIVE_SPEED)
	animation_tree.set("parameters/Grounded/WalkJog/blend_amount", smoothstep(1.3, 3.5, _speed))
	animation_tree.set("parameters/Grounded/JogRun/blend_amount", smoothstep(5.0, 7.5, _speed))
	animation_tree.set("parameters/Grounded/Locomotion/blend_amount", smoothstep(0.03, 0.45, _speed))
	if not _requested.is_empty():
		_playback.travel(_requested)
		_requested = &""
	_final_bone_poses.clear()
	animation_tree.advance(delta)
	if _occupant and _hand_targets.size() == 2: _apply_hand_targets()
	skeleton.advance(delta)

func reset_pose() -> void:
	if skeleton == null: return
	skeleton.reset_bone_poses()
	_final_bone_poses.clear()
	if animation_tree != null:
		animation_tree.active = true
		_playback.start(&"Driving" if _occupant else &"Grounded", true)
		_requested = &""
		_sample(0.0)
	skeleton.force_update_all_bone_transforms()

func set_walk_speed(speed: float) -> void:
	_walk_speed = speed
	_speed = maxf(0, speed)
	if speed == 0: reset_pose()

func set_lod(distance: float, margin := 4.0) -> void:
	for mesh in _meshes:
		mesh.visibility_range_end = distance
		mesh.visibility_range_end_margin = margin

func build_xray() -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = XRAY_SOURCE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 2
	var xray := MeshInstance3D.new()
	xray.name = "XRay"
	xray.mesh = uniform_mesh.mesh
	xray.skin = uniform_mesh.skin
	xray.transform = uniform_mesh.transform
	xray.skeleton = NodePath("..")
	xray.material_override = material
	xray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	xray.visible = false
	skeleton.add_child(xray)
	return xray

func bone_index(semantic: String) -> int:
	return skeleton.find_bone(BONE_ALIASES.get(semantic, semantic))

func bone_transform(semantic: String) -> Transform3D:
	var index := bone_index(semantic)
	assert(index >= 0, "Unknown source humanoid bone " + semantic)
	return _skeleton_to_model() * (_final_bone_poses[index] if _final_bone_poses.size() == skeleton.get_bone_count() else skeleton.get_bone_global_pose(index))

func _skeleton_to_model() -> Transform3D:
	var result := Transform3D.IDENTITY
	var node: Node3D = skeleton
	while node != model:
		result = node.transform * result
		node = node.get_parent() as Node3D
	return result

func _capture_final_bones() -> void:
	_final_bone_poses.resize(skeleton.get_bone_count())
	for bone in skeleton.get_bone_count(): _final_bone_poses[bone] = skeleton.get_bone_global_pose(bone)

func _skin_surface_arrays(surface: int, mesh: MeshInstance3D = null) -> Array:
	if mesh == null: mesh = uniform_mesh
	var instance := mesh.get_instance_id()
	var resource := mesh.mesh.get_instance_id()
	if _skin_mesh_resources.has(instance) and _skin_mesh_resources[instance] != resource:
		_invalidate_skin_arrays()
	_skin_mesh_resources[instance] = resource
	if not mesh.mesh.changed.is_connected(_invalidate_skin_arrays):
		mesh.mesh.changed.connect(_invalidate_skin_arrays)
	var key := Vector2i(instance, surface)
	if not _skin_surface_cache.has(key): _skin_surface_cache[key] = mesh.mesh.surface_get_arrays(surface)
	return _skin_surface_cache[key]

func _invalidate_skin_arrays() -> void:
	_skin_surface_cache.clear()

func _posed_mesh_surface(mesh: MeshInstance3D, surface: int, use_final := true) -> PackedVector3Array:
	var binds: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind)) if not mesh.skin.get_bind_name(bind).is_empty() else mesh.skin.get_bind_bone(bind)
		var pose := _final_bone_poses[bone] if use_final and _final_bone_poses.size() == skeleton.get_bone_count() else skeleton.get_bone_global_pose(bone)
		binds.append(pose * mesh.skin.get_bind_pose(bind))
	var arrays := _skin_surface_arrays(surface, mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences := 8 if mesh.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
	var result := PackedVector3Array()
	var to_model := _skeleton_to_model()
	for vertex in vertices.size():
		var point := Vector3.ZERO
		for influence in influences:
			var slot := vertex * influences + influence
			point += binds[bones[slot]] * vertices[vertex] * weights[slot]
		result.append(to_model * point)
	return result

func _posed_surface_vertices(surface: int, use_final := true) -> PackedVector3Array:
	return _posed_mesh_surface(uniform_mesh, surface, use_final)

func posed_vertices() -> PackedVector3Array:
	var result := PackedVector3Array()
	for mesh in _meshes:
		for surface in mesh.mesh.get_surface_count(): result.append_array(_posed_mesh_surface(mesh, surface))
	return result

func occupant_sole_height() -> float:
	var lowest := INF
	for point in posed_vertices(): lowest = minf(lowest, (model.transform * point).y)
	return lowest

func set_occupant_pose(_profile: StringName) -> void:
	_occupant = true
	_speed = 0.0
	for name_: String in ["L_ArmIK3D", "R_ArmIK3D"]: skeleton.get_node(name_).influence = 0.0
	reset_pose()

func reach_hands(left_target: Vector3, right_target: Vector3) -> void:
	_hand_targets.assign([left_target, right_target])
	_apply_hand_targets()
	skeleton.advance(0.0)

func _apply_hand_targets() -> void:
	for pair: Array in [["Left", "L", 0], ["Right", "R", 1]]:
		var hand := bone_transform(pair[0] + "Hand")
		var target: Vector3 = _hand_targets[pair[2]] - hand.basis * _grip_offsets[pair[0]]
		model.get_node(pair[1] + "_Hand_target").position = target
		skeleton.get_node(pair[1] + "_ArmIK3D").influence = 1.0

func hand_grip_position(side: String) -> Vector3:
	return bone_transform(side + "Hand") * _grip_offsets[side]

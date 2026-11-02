extends Node3D
## The imported mesh, skin and skeleton remain the only articulated hero body.
## Physics publishes motion; AnimationTree samples in render time, in place.
const MODEL := preload("res://assets/models/characters/ilyusha/ilyusha.glb")
const LIBRARY := preload("res://assets/animations/ilyusha/locomotion.tres")
const DrivingPose := preload("res://game/characters/imported_hero_driving.gd")
# Median contact velocity measured on the actual retargeted target skeleton.
# Shared normalized phase keeps the feet aligned throughout gait blends.
const WALK_SPEED := 0.92069055
const JOG_SPEED := 5.52777729
const RUN_SPEED := 7.94892718
const GAIT_HIPS_MEAN := Vector3(0.835, 0.80, 0.78)
const GAIT_STANCE := Vector3(0.58, 0.28, 0.22)
const MAX_CLAVICLE_REACH_ANGLE := deg_to_rad(20.0)
const BONE_ALIASES := {
	"root": "Root", "hips": "Hips", "pelvis": "Hips", "spine": "Spine", "chest": "Chest", "head": "Head", "neck": "Neck",
	"spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest", "neck_01": "Neck",
	"clavicle_l": "LeftShoulder", "upperarm_l": "LeftUpperArm", "lowerarm_l": "LeftLowerArm", "calf_l": "LeftLowerLeg", "ball_l": "LeftToes",
	"clavicle_r": "RightShoulder", "upperarm_r": "RightUpperArm", "lowerarm_r": "RightLowerArm", "calf_r": "RightLowerLeg", "ball_r": "RightToes",
	"upper_arm_l": "LeftUpperArm", "lower_arm_l": "LeftLowerArm", "hand_l": "LeftHand", "thigh_l": "LeftUpperLeg", "shin_l": "LeftLowerLeg", "foot_l": "LeftFoot", "toe_l": "LeftToes",
	"upper_arm_r": "RightUpperArm", "lower_arm_r": "RightLowerArm", "hand_r": "RightHand", "thigh_r": "RightUpperLeg", "shin_r": "RightLowerLeg", "foot_r": "RightFoot", "toe_r": "RightToes",
}
const XRAY_SOURCE := """shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;
uniform vec4 tint : source_color = vec4(0.62, 0.86, 1.0, 1.0);
void fragment() { ALBEDO = tint.rgb; ALPHA = 1.0; }
"""
var model: Node3D
var skeleton: Skeleton3D
var uniform_mesh: MeshInstance3D
var visible_height := 1.765
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var _speed := 0.0
var _walk_speed := -1.0
var _grounded := true
var _mode := &"locomotion"
var _vertical_speed := 0.0
var _action_phase := 0.0
var _occupant := false
var _action := &""
var _action_time := 0.0
var _hand_targets: Array[Vector3] = []
var _model_base_y := 0.0
var _sole_surfaces: Array[int] = []
var _landing := 0.0
var _leg_ik: TwoBoneIK3D
var _foot_sampler: FootTargetModifier
var _foot_orientation: FootOrientationModifier
var _foot_targets: Array[Node3D] = []
var _knee_poles: Array[Node3D] = []
var _foot_anchors: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _foot_world_rotations: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]
var _final_bone_poses: Array[Transform3D] = []
var _cycle_phase := 0.0
var _jog_weight := 0.0
var _run_weight := 0.0
var _cycle_stride := 1.0
var _hand_grip_offsets: Dictionary = {}

class FootTargetModifier extends SkeletonModifier3D:
	var controller: Node
	func _process_modification_with_delta(_delta: float) -> void:
		controller._update_foot_targets()

class FootOrientationModifier extends SkeletonModifier3D:
	var orientations: Dictionary = {}
	var toes: Dictionary = {}
	var controller: Node
	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		for index: int in orientations:
			var parent := sk.get_bone_parent(index)
			var parent_rotation := sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(index, parent_rotation.inverse() * orientations[index])
			for child: int in sk.get_bone_children(index):
				sk.set_bone_pose_rotation(child, toes.get(child, sk.get_bone_rest(child).basis.get_rotation_quaternion()))
		if controller == null or not controller._grounded or controller._occupant:
			return
		var lowest: Array[float] = [INF, INF]
		for surface: int in controller._sole_surfaces:
			var arrays: Array = controller.uniform_mesh.mesh.surface_get_arrays(surface)
			var rest_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var posed: PackedVector3Array = controller._posed_surface_vertices(surface, false)
			for vertex in rest_vertices.size():
				var side := 0 if rest_vertices[vertex].x > 0.0 else 1
				lowest[side] = minf(lowest[side], posed[vertex].y)
		for side in 2:
			if lowest[side] >= -0.0001:
				continue
			var foot := sk.find_bone("LeftFoot" if side == 0 else "RightFoot")
			var rest := sk.get_bone_global_rest(foot)
			var flat := rest.basis.get_rotation_quaternion()
			var parent_rotation := sk.get_bone_global_pose(sk.get_bone_parent(foot)).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(foot, parent_rotation.inverse() * flat)
			for child: int in sk.get_bone_children(foot):
				sk.set_bone_pose_rotation(child, sk.get_bone_rest(child).basis.get_rotation_quaternion())

func configure(height: float, color: Color) -> void:
	visible_height = height
	model = MODEL.instantiate() as Node3D
	add_child(model)
	skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert(skeleton != null and meshes.size() == 1, "Imported hero needs one real skinned mesh and skeleton")
	uniform_mesh = meshes[0] as MeshInstance3D
	assert(uniform_mesh.skin != null and uniform_mesh.get_node(uniform_mesh.skeleton) == skeleton)
	skeleton.reset_bone_poses()
	var bounds := uniform_mesh.mesh.get_aabb()
	model.scale = Vector3.ONE * height / bounds.size.y
	model.position.y = -bounds.position.y * model.scale.y
	_model_base_y = model.position.y
	model.rotation.y = PI # glTF +Z front to gameplay -Z.
	var mesh := uniform_mesh.mesh.duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
		material.albedo_color *= color
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.12
		material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
		material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
		material.stencil_reference = 1
		mesh.surface_set_material(surface, material)
		if material.resource_name.contains("Rubber_soles"):
			_sole_surfaces.append(surface)
	uniform_mesh.mesh = mesh
	_build_hand_grips()
	animation_player = AnimationPlayer.new()
	animation_player.name = "HeroAnimationPlayer"
	model.add_child(animation_player)
	animation_player.add_animation_library(&"", LIBRARY)
	_build_tree()
	_build_foot_ik()
	reset_pose()

func _ready() -> void:
	reset_pose()

func _build_tree() -> void:
	animation_tree = AnimationTree.new()
	animation_tree.name = "HeroAnimationTree"
	model.add_child(animation_tree)
	animation_tree.anim_player = NodePath("../HeroAnimationPlayer")
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var blend := AnimationNodeBlendTree.new()
	for pair: Array in [["Idle", "Idle"], ["Walk", "Walk"], ["Jog", "Jog_Fwd"], ["Run", "Sprint"]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = pair[1]
		blend.add_node(pair[0], clip)
		var seek_loop := AnimationNodeTimeSeek.new()
		blend.add_node(pair[0] + "Rate", seek_loop)
		blend.connect_node(pair[0] + "Rate", 0, pair[0])
	for name_: String in ["WalkJog", "JogRun", "Locomotion", "ActionBlend"]:
		blend.add_node(name_, AnimationNodeBlend2.new())
	blend.connect_node("WalkJog", 0, "WalkRate")
	blend.connect_node("WalkJog", 1, "JogRate")
	blend.connect_node("JogRun", 0, "WalkJog")
	blend.connect_node("JogRun", 1, "RunRate")
	blend.connect_node("Locomotion", 0, "IdleRate")
	blend.connect_node("Locomotion", 1, "JogRun")
	blend.add_node("LocomotionSeek", AnimationNodeTimeSeek.new())
	blend.connect_node("LocomotionSeek", 0, "Locomotion")
	var action := AnimationNodeAnimation.new()
	action.animation = &"Idle"
	blend.add_node("Action", action)
	var seek := AnimationNodeTimeSeek.new()
	blend.add_node("ActionSeek", seek)
	blend.connect_node("ActionSeek", 0, "Action")
	blend.connect_node("ActionBlend", 0, "LocomotionSeek")
	blend.connect_node("ActionBlend", 1, "ActionSeek")
	blend.connect_node("output", 0, "ActionBlend")
	animation_tree.tree_root = blend
	animation_tree.active = true

func _build_foot_ik() -> void:
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_foot_sampler = FootTargetModifier.new()
	_foot_sampler.name = "FootTargetSampling"
	_foot_sampler.controller = self
	skeleton.add_child(_foot_sampler)
	_leg_ik = TwoBoneIK3D.new()
	_leg_ik.name = "FootPlantIK"
	skeleton.add_child(_leg_ik)
	_leg_ik.setting_count = 2
	for index in 2:
		var side := "Left" if index == 0 else "Right"
		var helper_frame := skeleton.global_transform if skeleton.is_inside_tree() else model.transform * _skeleton_to_model()
		var target := Node3D.new()
		target.name = side + "FootContact"
		target.top_level = true
		target.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		target.position = helper_frame * skeleton.get_bone_global_rest(bone_index(side + "Foot")).origin
		skeleton.add_child(target)
		_foot_targets.append(target)
		var pole := Node3D.new()
		pole.name = side + "KneePole"
		pole.top_level = true
		pole.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		pole.position = helper_frame * (skeleton.get_bone_global_rest(bone_index(side + "LowerLeg")).origin + Vector3(0, 0, 1.0))
		skeleton.add_child(pole)
		_knee_poles.append(pole)
		_leg_ik.set_root_bone_name(index, side + "UpperLeg")
		_leg_ik.set_middle_bone_name(index, side + "LowerLeg")
		_leg_ik.set_end_bone_name(index, side + "Foot")
		_leg_ik.set_use_virtual_end(index, false)
		_leg_ik.set_target_node(index, _leg_ik.get_path_to(target))
		_leg_ik.set_pole_node(index, _leg_ik.get_path_to(pole))
	_foot_orientation = FootOrientationModifier.new()
	_foot_orientation.name = "FootContactOrientation"
	_foot_orientation.controller = self
	skeleton.add_child(_foot_orientation)
	skeleton.skeleton_updated.connect(_capture_final_bones)

func _capture_final_bones() -> void:
	_final_bone_poses.resize(skeleton.get_bone_count())
	for bone in skeleton.get_bone_count():
		_final_bone_poses[bone] = skeleton.get_bone_global_pose(bone)

func supports_manual_bone_interpolation() -> bool:
	return false

func prepare_locomotion() -> void:
	pass # Imported rest/skin is already the runtime rig.

func update_locomotion(velocity: Vector3, grounded: bool, mode: StringName, _delta: float, vertical_speed := 0.0, action_phase := 0.0) -> void:
	if _occupant:
		return
	_speed = Vector2(velocity.x, velocity.z).length() if _walk_speed < 0.0 else _walk_speed
	if grounded and not _grounded:
		_landing = 0.18
	_grounded = grounded
	_mode = mode
	_vertical_speed = vertical_speed
	_action_phase = action_phase

func _process(delta: float) -> void:
	if animation_tree == null or _mode == &"hidden":
		return
	_sample(delta)

func _sample(delta: float) -> void:
	var jog_weight := smoothstep(1.4, 3.2, _speed)
	var run_weight := smoothstep(5.0, 7.2, _speed)
	_jog_weight = jog_weight
	_run_weight = run_weight
	var stride := lerpf(WALK_SPEED * LIBRARY.get_animation("Walk").length, JOG_SPEED * LIBRARY.get_animation("Jog_Fwd").length, jog_weight)
	stride = lerpf(stride, RUN_SPEED * LIBRARY.get_animation("Sprint").length, run_weight)
	# Once vertical bounding is reduced, the authored five-metre running cycle
	# exceeds this body's stance reach. Derive distance per cycle from the real
	# leg, ankle, bounded pelvis and support fraction; never slide a planted foot
	# merely to retain the source mannequin's airborne stride.
	var mean_y := lerpf(lerpf(GAIT_HIPS_MEAN.x, GAIT_HIPS_MEAN.y, jog_weight), GAIT_HIPS_MEAN.z, run_weight)
	var stance := lerpf(lerpf(GAIT_STANCE.x, GAIT_STANCE.y, jog_weight), GAIT_STANCE.z, run_weight)
	var leg_length := skeleton.get_bone_rest(bone_index("LeftLowerLeg")).origin.length() + skeleton.get_bone_rest(bone_index("LeftFoot")).origin.length()
	var ankle_y := skeleton.get_bone_global_rest(bone_index("LeftFoot")).origin.y
	var vertical := mean_y + 0.009 + 0.008 - ankle_y
	var travel := 2.0 * sqrt(maxf(0.0, (leg_length - 0.002) * (leg_length - 0.002) - vertical * vertical))
	stride = minf(stride, travel * 0.90 / stance)
	_cycle_stride = stride
	_cycle_phase = fposmod(_cycle_phase + _speed * delta / maxf(stride, 0.01), 1.0)
	for pair: Array in [["Walk", "Walk"], ["Jog", "Jog_Fwd"], ["Run", "Sprint"]]:
		animation_tree.set("parameters/" + pair[0] + "Rate/seek_request", _cycle_phase * LIBRARY.get_animation(pair[1]).length)
	animation_tree.set("parameters/WalkJog/blend_amount", jog_weight)
	animation_tree.set("parameters/JogRun/blend_amount", run_weight)
	animation_tree.set("parameters/Locomotion/blend_amount", smoothstep(0.03, 0.35, _speed))
	var next := &""
	if _occupant:
		next = &"Driving"
	elif _mode == &"punch":
		next = &"Punch_Jab"
	elif _mode == &"knock":
		next = &"Idle"
	elif not _grounded:
		next = &"Jump_Start" if _vertical_speed > 0.15 else &"Jump"
	elif _landing > 0.0:
		next = &"Jump_Land"
	if next != _action:
		_action = next
		_action_time = 0.0
		if not _action.is_empty():
			((animation_tree.tree_root as AnimationNodeBlendTree).get_node("Action") as AnimationNodeAnimation).animation = _action
			animation_tree.set("parameters/ActionSeek/seek_request", 0.0)
	animation_tree.set("parameters/ActionBlend/blend_amount", 0.0 if _action.is_empty() else 1.0)
	if not _occupant and _mode == &"punch":
		animation_tree.set("parameters/ActionSeek/seek_request", clampf(_action_phase, 0.0, 1.0) * LIBRARY.get_animation("Punch_Jab").length)
	_final_bone_poses.clear()
	animation_tree.advance(delta)
	if _occupant:
		DrivingPose.apply_pose(skeleton)
	_action_time += delta
	_landing = maxf(0.0, _landing - delta)
	model.position.y = _model_base_y
	if _occupant and _hand_targets.size() == 2:
		_apply_hand_targets()
	_leg_ik.active = _grounded and not _occupant and _mode != &"hidden"
	skeleton.advance(delta)

func _update_foot_targets() -> void:
	_leg_ik.active = _grounded and not _occupant and _mode != &"hidden"
	_foot_orientation.orientations.clear()
	_foot_orientation.toes.clear()
	if not _leg_ik.active:
		_foot_anchors.assign([Vector3.INF, Vector3.INF])
		return
	var render_skeleton := skeleton.get_global_transform_interpolated()
	for index in 2:
		var side := "Left" if index == 0 else "Right"
		var foot := skeleton.find_bone(side + "Foot")
		var knee := skeleton.find_bone(side + "LowerLeg")
		var pose := skeleton.get_bone_global_pose(foot)
		var rest := skeleton.get_bone_global_rest(foot)
		# Source toe contact begins near phase zero for the left foot in all three
		# clips. Heel support extends it; the shorter target legs need explicit
		# contact goals rather than the source ankle's absolute altitude.
		var stance := lerpf(GAIT_STANCE.x, GAIT_STANCE.y, _jog_weight)
		stance = lerpf(stance, GAIT_STANCE.z, _run_weight)
		var phase := fposmod(_cycle_phase + (0.5 if index == 1 else 0.0), 1.0)
		var contact := phase < stance or _speed < 0.10
		var lift := lerpf(0.08, 0.10, _jog_weight)
		lift = lerpf(lift, 0.12, _run_weight)
		var target := pose.origin
		var swing := clampf((phase - stance) / maxf(1.0 - stance, 0.01), 0.0, 1.0)
		target.y = rest.origin.y + sin(swing * PI) * lift if not contact else rest.origin.y
		_foot_orientation.orientations[foot] = pose.basis.get_rotation_quaternion()
		for child: int in skeleton.get_bone_children(foot):
			_foot_orientation.toes[child] = skeleton.get_bone_pose_rotation(child)
		if contact:
			for child: int in skeleton.get_bone_children(foot):
				_foot_orientation.toes[child] = skeleton.get_bone_rest(child).basis.get_rotation_quaternion()
			target.y = rest.origin.y
			if _speed > 0.10:
				if _foot_anchors[index] == Vector3.INF:
					target = _reachable_leg_target(side, target)
					_foot_world_rotations[index] = render_skeleton.basis.get_rotation_quaternion() * rest.basis.get_rotation_quaternion()
				var world := render_skeleton * target
				if _foot_anchors[index] == Vector3.INF:
					_foot_anchors[index] = world
				var anchor := render_skeleton.affine_inverse() * _foot_anchors[index]
				target.x = anchor.x
				target.z = anchor.z
				_foot_orientation.orientations[foot] = render_skeleton.basis.get_rotation_quaternion().inverse() * _foot_world_rotations[index]
			else:
				_foot_anchors[index] = Vector3.INF
				_foot_orientation.orientations[foot] = rest.basis.get_rotation_quaternion()
		else:
			_foot_anchors[index] = Vector3.INF
		target = _reachable_leg_target(side, target)
		_foot_targets[index].global_position = render_skeleton * target
		_knee_poles[index].global_position = render_skeleton * (skeleton.get_bone_global_pose(knee).origin + Vector3(0, 0, 1.0))
		if is_inside_tree():
			_foot_targets[index].force_update_transform()
			_knee_poles[index].force_update_transform()

func _reachable_leg_target(side: String, target: Vector3) -> Vector3:
	var hip := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpperLeg")).origin
	var knee := skeleton.find_bone(side + "LowerLeg")
	var foot := skeleton.find_bone(side + "Foot")
	var length := skeleton.get_bone_rest(knee).origin.length() + skeleton.get_bone_rest(foot).origin.length()
	var vertical := target.y - hip.y
	var max_horizontal := sqrt(maxf(0.0, (length - 0.002) * (length - 0.002) - vertical * vertical))
	var horizontal := Vector2(target.x - hip.x, target.z - hip.z)
	if horizontal.length() > max_horizontal:
		horizontal = horizontal.normalized() * max_horizontal
		target.x = hip.x + horizontal.x
		target.z = hip.z + horizontal.y
	return target

func set_walk_speed(speed: float) -> void:
	_walk_speed = speed
	_speed = maxf(0.0, speed)
	if speed == 0.0:
		reset_pose()

func reset_pose() -> void:
	if skeleton == null:
		return
	skeleton.reset_bone_poses()
	_action = &""
	_action_time = 0.0
	_landing = 0.0
	_cycle_phase = 0.0
	_foot_anchors.assign([Vector3.INF, Vector3.INF])
	_foot_world_rotations.assign([Quaternion.IDENTITY, Quaternion.IDENTITY])
	_final_bone_poses.clear()
	if animation_tree != null:
		animation_tree.set("parameters/ActionSeek/seek_request", 0.0)
		animation_tree.set("parameters/LocomotionSeek/seek_request", 0.0)
		_sample(0.0)
	skeleton.force_update_all_bone_transforms()

func set_lod(distance: float, margin := 4.0) -> void:
	uniform_mesh.visibility_range_end = distance
	uniform_mesh.visibility_range_end_margin = margin

func build_xray() -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = XRAY_SOURCE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 2
	var result := MeshInstance3D.new()
	result.name = "XRay"
	result.mesh = uniform_mesh.mesh
	result.skin = uniform_mesh.skin
	result.transform = uniform_mesh.transform
	result.skeleton = uniform_mesh.skeleton
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.visible = false
	uniform_mesh.get_parent().add_child(result)
	return result

func bone_index(semantic: String) -> int:
	return skeleton.find_bone(BONE_ALIASES.get(semantic, semantic))

func bone_transform(semantic: String) -> Transform3D:
	var bone := bone_index(semantic)
	assert(bone >= 0, "Unknown imported hero bone: " + semantic)
	return _skeleton_to_model() * (_final_bone_poses[bone] if _final_bone_poses.size() == skeleton.get_bone_count() else skeleton.get_bone_global_pose(bone))

func _skeleton_to_model() -> Transform3D:
	var result := Transform3D.IDENTITY
	var node: Node3D = skeleton
	while node != model:
		result = node.transform * result
		node = node.get_parent() as Node3D
	return result

## Real skinning in model coordinates; supports indexed geometry and named binds.
func posed_vertices() -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in uniform_mesh.mesh.get_surface_count():
		result.append_array(_posed_surface_vertices(surface))
	return result

func _posed_surface_vertices(surface: int, use_final := true) -> PackedVector3Array:
	var result := PackedVector3Array()
	var skin := uniform_mesh.skin
	var to_model := _skeleton_to_model()
	var binds: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if not skin.get_bind_name(bind).is_empty():
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		assert(bone >= 0)
		var pose := _final_bone_poses[bone] if use_final and _final_bone_poses.size() == skeleton.get_bone_count() else skeleton.get_bone_global_pose(bone)
		binds.append(pose * skin.get_bind_pose(bind))
	var arrays := uniform_mesh.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences := 8 if uniform_mesh.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
	for vertex in vertices.size():
		var point := Vector3.ZERO
		for influence in influences:
			var slot := vertex * influences + influence
			if weights[slot] > 0.0:
				point += binds[bones[slot]] * vertices[vertex] * weights[slot]
		result.append(to_model * point)
	return result

func occupant_sole_height() -> float:
	var lowest := INF
	for point: Vector3 in posed_vertices():
		lowest = minf(lowest, (model.transform * point).y)
	return lowest

func set_occupant_pose(_profile: StringName) -> void:
	_occupant = true
	_speed = 0.0
	_mode = &"locomotion"
	reset_pose()

func reach_hands(left_target: Vector3, right_target: Vector3) -> void:
	_final_bone_poses.clear()
	_hand_targets.assign([left_target, right_target])
	_apply_hand_targets()

func _apply_hand_targets() -> void:
	_reach_hand("Left", _hand_targets[0])
	_reach_hand("Right", _hand_targets[1])
	skeleton.force_update_all_bone_transforms()

func _reach_hand(side: String, model_target: Vector3) -> void:
	var upper := skeleton.find_bone(side + "UpperArm")
	var lower := skeleton.find_bone(side + "LowerArm")
	var hand := skeleton.find_bone(side + "Hand")
	var palm_target := _skeleton_to_model().affine_inverse() * model_target
	var upper_length := skeleton.get_bone_rest(lower).origin.length()
	var lower_length := skeleton.get_bone_rest(hand).origin.length()
	var palm_offset: Vector3 = _hand_grip_offsets.get(side, Vector3.ZERO)
	if _occupant:
		_reach_clavicle(side, palm_target, upper_length + lower_length + palm_offset.length() - 0.005)
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	for iteration in 5:
		var target := palm_target - skeleton.get_bone_global_pose(hand).basis * palm_offset
		var reach := target - shoulder
		var distance := clampf(reach.length(), absf(upper_length - lower_length) + 0.0001, upper_length + lower_length - 0.0001)
		var toward := reach.normalized()
		var bend := Vector3.DOWN - toward * Vector3.DOWN.dot(toward)
		if bend.length_squared() < 0.0001:
			bend = Vector3.BACK
		bend = bend.normalized()
		var along := (distance * distance + upper_length * upper_length - lower_length * lower_length) / (2.0 * distance)
		var elbow := shoulder + toward * along + bend * sqrt(maxf(0.0, upper_length * upper_length - along * along))
		_aim_bone(upper, lower, elbow)
		_aim_bone(lower, hand, shoulder + toward * distance)

func _reach_clavicle(side: String, target: Vector3, arm_reach: float) -> void:
	var clavicle := skeleton.find_bone(side + "Shoulder")
	var upper := skeleton.find_bone(side + "UpperArm")
	var pose := skeleton.get_bone_global_pose(clavicle)
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	if shoulder.distance_to(target) <= arm_reach:
		return
	var offset := shoulder - pose.origin
	var rotation := Quaternion(offset.normalized(), (target - pose.origin).normalized())
	var angle := minf(rotation.get_angle(), MAX_CLAVICLE_REACH_ANGLE)
	if angle <= 0.0001:
		return
	var axis := rotation.get_axis()
	var low := 0.0
	var high := angle
	for iteration in 8:
		var middle := (low + high) * 0.5
		var candidate := pose.origin + Quaternion(axis, middle) * offset
		if candidate.distance_to(target) <= arm_reach:
			high = middle
		else:
			low = middle
	var parent := skeleton.get_bone_parent(clavicle)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var desired := Quaternion(axis, high) * pose.basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(clavicle, parent_rotation.inverse() * desired)
	skeleton.force_update_all_bone_transforms()

func hand_grip_position(side: String) -> Vector3:
	return bone_transform(side + "Hand") * _hand_grip_offsets.get(side, Vector3.ZERO)

func _build_hand_grips() -> void:
	var skin := uniform_mesh.skin
	var binds: Array[Transform3D] = []
	var bound_bones: Array[int] = []
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if not skin.get_bind_name(bind).is_empty():
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		bound_bones.append(bone)
		binds.append(skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(bind))
	for side: String in ["Left", "Right"]:
		var hand := skeleton.find_bone(side + "Hand")
		var inverse := skeleton.get_bone_global_rest(hand).affine_inverse()
		var bounds := AABB()
		var found := false
		for surface in uniform_mesh.mesh.get_surface_count():
			if not uniform_mesh.mesh.surface_get_material(surface).resource_name.contains("Warm_pale_skin"):
				continue
			var arrays := uniform_mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := 8 if uniform_mesh.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
			for vertex in vertices.size():
				var point := Vector3.ZERO
				var hand_weight := 0.0
				for influence in influences:
					var slot := vertex * influences + influence
					point += binds[bones[slot]] * vertices[vertex] * weights[slot]
					if bound_bones[bones[slot]] == hand:
						hand_weight += weights[slot]
				if hand_weight < 0.90:
					continue
				point = inverse * point
				bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
				found = true
		assert(found, "Imported hand needs real weighted palm vertices")
		_hand_grip_offsets[side] = bounds.get_center()

func _aim_bone(bone: int, child: int, target: Vector3) -> void:
	skeleton.force_update_all_bone_transforms()
	var pose := skeleton.get_bone_global_pose(bone)
	var child_at := skeleton.get_bone_global_pose(child).origin
	var direction := (target - pose.origin).normalized()
	var rotation := Quaternion((child_at - pose.origin).normalized(), direction) * pose.basis.get_rotation_quaternion()
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(bone, parent_rotation.inverse() * rotation)

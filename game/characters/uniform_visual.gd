extends Node3D
## Visual-only skinned adapter. Feet=0, local forward=-Z; no gameplay bodies.
const PoliceModel = preload("res://game/characters/models/police_model.gd")
const GuardModel = preload("res://game/characters/models/guard_model.gd")
const CivilianModel = preload("res://game/characters/models/civilian_model.gd")
const LocomotionRig = preload("res://game/characters/locomotion_rig.gd")
const LocomotionPose = preload("res://game/characters/locomotion_pose.gd")
const ActionPose = preload("res://game/characters/character_action_pose.gd")
const CIVILIANS_ENABLED_BY_DEFAULT := true
const ENABLED_BY_DEFAULT := true
const EMISSION_FLOOR := 0.12
const CLOTH_EMISSION_FLOOR := 0.18
const SKIN_EMISSION_FLOOR := 0.15
const INK_EMISSION_FLOOR := 0.06
const XRAY_SOURCE := """shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;
uniform vec4 tint : source_color = vec4(0.62, 0.86, 1.0, 1.0);
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = 1.0;
}
"""
static var _xray_shader: Shader
static var _tinted_meshes: Dictionary = {}
var model: Node3D
var skeleton: Skeleton3D
var uniform_mesh: MeshInstance3D
var visible_height := 1.0
var _kind := ""
var _walk_speed := -1.0
var _manual_distance := 0.0
var author_skeleton: Skeleton3D
var author_mesh: MeshInstance3D
var rig: LocomotionRig
var gait: LocomotionPose
var _occupant := false
var _legacy_distance := 0.0
var _xrays: Array[MeshInstance3D] = []
var _action_request: Dictionary = {}
var _action_roles: Dictionary = {}
var _palm_anchors: Dictionary = {}
var last_action_kind: StringName = &"none"
var last_action_valid := true

static func enabled() -> bool:
	return ENABLED_BY_DEFAULT or "--uniform3d" in OS.get_cmdline_user_args() or "--uniform3d" in OS.get_cmdline_args()

static func supports(drawing: String) -> bool:
	return drawing == "police" or drawing == "guard" or CivilianModel.supports(drawing)

static func civilians_enabled() -> bool:
	return CIVILIANS_ENABLED_BY_DEFAULT or "--civilian3d" in OS.get_cmdline_user_args() or "--civilian3d" in OS.get_cmdline_args()

static func use_for(drawing: String) -> bool:
	if drawing == "police" or drawing == "guard":
		return enabled()
	return civilians_enabled() and CivilianModel.supports(drawing)

func configure(drawing: String, height: float, color: Color) -> void:
	_kind = drawing
	visible_height = height
	if drawing == "police":
		model = PoliceModel.new().build_model()
	elif drawing == "guard":
		model = GuardModel.new().build_model()
	else:
		model = CivilianModel.new().build_model(drawing)
	add_child(model)
	skeleton = model.get_node("Skeleton3D") as Skeleton3D
	# Non-animated consumers need the authored bind pose before their first frame.
	skeleton.reset_bone_poses()
	uniform_mesh = skeleton.get_node("UniformMesh") as MeshInstance3D
	var bind_bounds := uniform_mesh.mesh.get_aabb()
	assert(bind_bounds.size.y > 0.0, "Character bind geometry must have positive height")
	model.scale = Vector3.ONE * (height / bind_bounds.size.y)
	model.position.y = -bind_bounds.position.y * model.scale.y
	uniform_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var key := drawing + ":" + color.to_html()
	if not _tinted_meshes.has(key):
		var tinted := uniform_mesh.mesh.duplicate() as ArrayMesh
		for surface in range(tinted.get_surface_count()):
			var material := tinted.surface_get_material(surface).duplicate() as StandardMaterial3D
			material.albedo_color *= color
			var colors: PackedColorArray = tinted.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			var mean_color := Color(0, 0, 0, 0)
			for vertex_color: Color in colors:
				mean_color += vertex_color
			mean_color /= float(colors.size())
			# Police navy is carried by vertex colours on a white base material.
			material.emission_enabled = true
			material.emission = material.albedo_color * mean_color * _emission_floor(tinted.surface_get_name(surface))
			# Write only where the ordinary opaque model passes depth. Its visible
			# pixels then mask every xray fragment, including hidden inner parts.
			material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
			material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
			material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
			material.stencil_reference = 1
			tinted.surface_set_material(surface, material)
		_tinted_meshes[key] = tinted
	uniform_mesh.mesh = _tinted_meshes[key]
	author_skeleton = skeleton
	author_mesh = uniform_mesh

static func _emission_floor(surface_name: String) -> float:
	# Keep black trim dark while the winter cloth and faces retain their local colour.
	match surface_name:
		"navy", "suit", "armour", "beret":
			return CLOTH_EMISSION_FLOOR
		"ochre_skin", "skin":
			return SKIN_EMISSION_FLOOR
		"fur_leather_ink", "ink":
			return INK_EMISSION_FLOOR
	return EMISSION_FLOOR

func update_walk(distance: float, walking: bool, delta: float, _stride: float) -> void:
	if _walk_speed >= 0.0:
		walking = _walk_speed > 0.0
		_manual_distance += _walk_speed * delta
		distance = _manual_distance
	var speed := maxf(0.0, distance - _legacy_distance) / maxf(delta, 0.0001) if walking else 0.0
	_legacy_distance = distance
	update_locomotion(-global_basis.z.normalized() * speed, true, &"locomotion", delta)

func update_locomotion(velocity: Vector3, grounded: bool, mode: StringName, delta: float, vertical_speed := 0.0, action_phase := 0.0) -> void:
	if _occupant:
		return
	if mode == &"hidden":
		reset_pose()
		return
	if delta <= 0.0:
		return
	prepare_locomotion()
	# Clear every prior action mask without resetting gait contact/phase state.
	skeleton.reset_bone_poses()
	if _walk_speed == 0.0:
		mode = &"knock"
	elif _walk_speed > 0.0:
		# Explicit inspection/capture override; gameplay consumers publish root motion.
		velocity = -global_basis.z.normalized() * _walk_speed
	gait.update(velocity, grounded, mode, delta, vertical_speed, action_phase)
	_apply_action(mode)

func prepare_locomotion() -> void:
	if rig != null or _occupant:
		return
	rig = LocomotionRig.new()
	rig.build(author_skeleton, author_mesh, _kind not in ["police", "guard", "police_long", "police_round", "guard_alt"])
	gait = LocomotionPose.new()
	gait.configure(rig, _kind == "ilyusha")
	author_mesh.visible = false
	skeleton = rig.skeleton
	uniform_mesh = rig.mesh
	_rebind_xrays()
	_resolve_action_roles()
	skeleton.force_update_all_bone_transforms()

## Only stores a snapshot. The gait update owns the single evaluation pass.
func submit_action(request: Dictionary) -> void:
	_action_request = request.duplicate(true) if not _occupant and request.get("kind", &"none") != &"none" else {}

func _resolve_action_roles() -> void:
	_action_roles.clear()
	for name: String in ["hips", "spine", "head", "upper_arm_l", "lower_arm_l", "hand_l", "upper_arm_r", "lower_arm_r", "hand_r"]:
		_action_roles[name] = skeleton.find_bone(name)
	for index in rig.legs.size():
		var suffix := "_l" if index == 0 else "_r"
		var leg: Dictionary = rig.legs[index]
		_action_roles["thigh" + suffix] = int(leg.hip)
		_action_roles["knee" + suffix] = int(leg.knee)
		_action_roles["ankle" + suffix] = int(leg.ankle)

func _apply_action(mode: StringName) -> void:
	last_action_kind = &"none"
	last_action_valid = true
	if mode == &"hidden" or _action_request.is_empty(): return
	var kind := StringName(_action_request.get("kind", &"none"))
	if mode == &"knock" and kind not in [&"flail", &"down", &"getup"]:
		_action_request.clear()
		return
	var pose: Dictionary = ActionPose.sample(_aimed_action_request(), _action_roles)
	last_action_valid = bool(pose.valid)
	if not pose.valid or not pose.active: return
	last_action_kind = pose.kind
	for bone: int in pose.bone_offsets:
		var base := skeleton.get_bone_pose(bone)
		var composed: Transform3D = base * pose.bone_offsets[bone]
		skeleton.set_bone_pose_position(bone, composed.origin)
		skeleton.set_bone_pose_rotation(bone, composed.basis.get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
	if pose.grips.is_empty(): return
	for suffix: String in pose.grips:
		var grip: Dictionary = pose.grips[suffix]
		var target: Transform3D = grip.target
		_reach_hand(suffix, skeleton.to_local(target.origin), float(grip.weight), _palm_anchor(suffix), skeleton.global_basis.orthonormalized().inverse() * target.basis.orthonormalized())
	skeleton.force_update_all_bone_transforms()

## Geometry-derived torso facing, not an AI turn or a new action clock.
## Resolve in the fresh spine parent's frame before applying this action mask.
func _aimed_action_request() -> Dictionary:
	if _action_request.get("kind", &"none") != &"dig": return _action_request
	var grips: Dictionary = _action_request.get("grips", {})
	if typeof(grips.get("_l")) != TYPE_TRANSFORM3D or typeof(grips.get("_r")) != TYPE_TRANSFORM3D: return _action_request
	var left: Transform3D = grips["_l"]
	var right: Transform3D = grips["_r"]
	var midpoint := skeleton.to_local((left.origin + right.origin) * 0.5)
	var spine := skeleton.find_bone("spine")
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(spine))
	var direction := parent.affine_inverse().basis * (midpoint - skeleton.get_bone_global_pose(spine).origin)
	var request := _action_request.duplicate()
	request["aim_yaw"] = clampf(atan2(-direction.x, -direction.z), -PI / 3.0, PI / 3.0)
	return request

func _rotate(bone_name: String, axis: Vector3, angle: float) -> void:
	skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), Quaternion(axis, angle))

func set_walk_speed(speed: float) -> void:
	_walk_speed = speed
	_manual_distance = 0.0
	if speed == 0.0:
		reset_pose()

func reset_pose() -> void:
	_action_request.clear()
	last_action_kind = &"none"
	last_action_valid = true
	skeleton.reset_bone_poses()
	if gait != null:
		gait.reset()

func build_xray() -> MeshInstance3D:
	if _xray_shader == null:
		_xray_shader = Shader.new()
		_xray_shader.code = XRAY_SOURCE
	var material := ShaderMaterial.new()
	material.shader = _xray_shader
	material.render_priority = 2
	var result := MeshInstance3D.new()
	result.name = "XRay"
	result.mesh = uniform_mesh.mesh
	result.skin = uniform_mesh.skin
	result.skeleton = NodePath("..")
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.visible = false
	skeleton.add_child(result)
	_xrays.append(result)
	return result

func _rebind_xrays() -> void:
	for xray: MeshInstance3D in _xrays:
		if not is_instance_valid(xray):
			continue
		xray.reparent(skeleton, false)
		xray.mesh = uniform_mesh.mesh
		xray.skin = uniform_mesh.skin
		xray.skeleton = NodePath("..")

## Occupants retain fresh skeletons while sharing immutable mesh/material resources.
## Lada uses a full model scaled to its cabin, never the legacy cropped-canvas height.
func set_occupant_pose(profile: StringName) -> void:
	_occupant = true
	if rig != null:
		rig.mesh.visible = false
		skeleton = author_skeleton
		uniform_mesh = author_mesh
		author_mesh.visible = true
		_rebind_xrays()
	reset_pose()
	if profile == &"trolley_standing":
		_rotate("upper_arm_r", Vector3.RIGHT, 1.70)
		_rotate("lower_arm_r", Vector3.RIGHT, 0.40)
		skeleton.force_update_all_bone_transforms()
		return
	if profile == &"lada":
		# The chin tuck clears the roof; Ilyusha sits back from the steering wheel.
		var head := skeleton.find_bone("head")
		var head_offset := Vector3(0, -0.075 if _kind == "ilyusha" else -0.018, 0.035 if _kind == "ilyusha" else 0.0)
		skeleton.set_bone_pose_position(head, skeleton.get_bone_rest(head).origin + head_offset)
	for suffix: String in ["_l", "_r"]:
		_rotate("leg" + suffix, Vector3.RIGHT, 1.65 if profile == &"lada" else 1.35)
		_rotate("foot" + suffix, Vector3.RIGHT, -0.17 if profile == &"lada" else -1.35)
		_rotate("upper_arm" + suffix, Vector3.RIGHT, 0.95 if profile in [&"lada", &"trolley_driver"] else 0.30)
		_rotate("lower_arm" + suffix, Vector3.RIGHT, 0.55)
	skeleton.force_update_all_bone_transforms()

func set_lod(distance: float, margin: float = 4.0) -> void:
	uniform_mesh.visibility_range_end = distance
	uniform_mesh.visibility_range_end_margin = margin

## A tilted boot rests on its heel, not its bind-space ankle projection.
## Use the real weighted mesh so raised pedals cannot push shoes below the floor.
func occupant_sole_height() -> float:
	var lowest := INF
	for surface in uniform_mesh.mesh.get_surface_count():
		var arrays := uniform_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var point := Vector3.ZERO
			for influence in 4:
				var slot := index * 4 + influence
				if weights[slot] <= 0.0:
					continue
				var bind := bones[slot]
				var bone := uniform_mesh.skin.get_bind_bone(bind)
				point += (skeleton.get_bone_global_pose(bone) * uniform_mesh.skin.get_bind_pose(bind) * vertices[index]) * weights[slot]
			lowest = minf(lowest, (model.transform * point).y)
	return lowest

## Two-bone arm reach in normalized model coordinates. Targets are authored by
## the vehicle consumer; no gameplay transforms or cached mesh resources change.
func reach_hands(left_target: Vector3, right_target: Vector3) -> void:
	_reach_hand("_l", left_target)
	_reach_hand("_r", right_target)
	skeleton.force_update_all_bone_transforms()

func _reach_hand(suffix: String, target: Vector3, weight := 1.0, palm_offset := Vector3(0, -0.034, -0.008), target_basis: Variant = null) -> void:
	var upper := skeleton.find_bone("upper_arm" + suffix)
	var lower := skeleton.find_bone("lower_arm" + suffix)
	var hand := skeleton.find_bone("hand" + suffix)
	var parent := skeleton.get_bone_parent(upper)
	var parent_pose := skeleton.get_bone_global_pose(parent)
	var inverse_parent := parent_pose.affine_inverse()
	var shoulder := inverse_parent * skeleton.get_bone_global_pose(upper).origin
	var local_target := inverse_parent * target
	var upper_rest := skeleton.get_bone_rest(lower).origin
	var lower_rest := skeleton.get_bone_rest(hand).origin
	var upper_length := upper_rest.length()
	var lower_length := lower_rest.length()
	var old_upper := skeleton.get_bone_pose_rotation(upper)
	var old_lower := skeleton.get_bone_pose_rotation(lower)
	var old_hand := skeleton.get_bone_pose_rotation(hand)
	var hand_goal: Quaternion = old_hand
	var upper_rotation := Quaternion.IDENTITY
	var lower_rotation := Quaternion.IDENTITY
	var wrist := local_target
	for iteration in 4:
		var reach := wrist - shoulder
		if reach.length_squared() < 0.00000001: reach = Vector3.DOWN * 0.0001
		var distance := clampf(reach.length(), absf(upper_length - lower_length) + 0.0001, upper_length + lower_length - 0.0001)
		var toward := reach.normalized()
		var bend := Vector3.DOWN - toward * Vector3.DOWN.dot(toward)
		if bend.length_squared() < 0.0001: bend = Vector3.FORWARD
		bend = bend.normalized()
		var along := (distance * distance + upper_length * upper_length - lower_length * lower_length) / (2.0 * distance)
		var elbow := shoulder + toward * along + bend * sqrt(maxf(0.0, upper_length * upper_length - along * along))
		upper_rotation = Quaternion(upper_rest.normalized(), (elbow - shoulder).normalized())
		lower_rotation = Quaternion(lower_rest.normalized(), (shoulder + toward * distance - elbow).normalized())
		var palm_rotation := lower_rotation * old_hand
		if target_basis != null:
			var desired: Basis = target_basis
			palm_rotation = (parent_pose.basis.orthonormalized().inverse() * desired.orthonormalized()).get_rotation_quaternion()
			hand_goal = lower_rotation.inverse() * palm_rotation
		wrist = local_target - palm_rotation * palm_offset
	skeleton.set_bone_pose_rotation(upper, old_upper.slerp(upper_rotation, weight))
	skeleton.set_bone_pose_rotation(lower, old_lower.slerp(upper_rotation.inverse() * lower_rotation, weight))
	skeleton.set_bone_pose_rotation(hand, old_hand.slerp(hand_goal, weight))

## A stable contact point on actual hand skin, expressed in hand-bone bind space.
## Skin-only filtering excludes bags/tools that share a hand's animation bone.
## This is lazy per-instance calibration; ordinary gait performs no mesh scans.
func _palm_anchor(suffix: String) -> Vector3:
	if _palm_anchors.has(suffix): return _palm_anchors[suffix]
	var hand := author_skeleton.find_bone("hand" + suffix)
	var inverse_hand := author_skeleton.get_bone_global_rest(hand).affine_inverse()
	var points: Array[Vector3] = []
	for surface in author_mesh.mesh.get_surface_count():
		if "skin" not in author_mesh.mesh.surface_get_name(surface): continue
		var arrays := author_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			for influence in 4:
				var slot := index * 4 + influence
				if weights[slot] >= 0.99 and author_mesh.skin.get_bind_bone(bones[slot]) == hand:
					points.append(inverse_hand * vertices[index])
					break
	var result := Vector3(0, -0.034, -0.008)
	if not points.is_empty():
		var bounds := AABB(points[0], Vector3.ZERO)
		for point: Vector3 in points: bounds = bounds.expand(point)
		var wanted := bounds.get_center()
		wanted.z = bounds.position.z
		var nearest := INF
		for point: Vector3 in points:
			var distance := point.distance_squared_to(wanted)
			if distance < nearest:
				nearest = distance
				result = point
	_palm_anchors[suffix] = result
	return result

## Inspection/attachment consumers receive the active hand skin point in world
## coordinates; no BoneAttachment remains bound to a hidden author skeleton.
func hand_contact_transform(suffix: String) -> Transform3D:
	var hand := skeleton.find_bone("hand" + suffix)
	return skeleton.global_transform * skeleton.get_bone_global_pose(hand) * Transform3D(Basis.IDENTITY, _palm_anchor(suffix))

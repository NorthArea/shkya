extends Node3D
## Visual-only skinned adapter. Feet=0, local forward=-Z; no gameplay bodies.
const PoliceModel = preload("res://game/characters/models/police_model.gd")
const GuardModel = preload("res://game/characters/models/guard_model.gd")
const CivilianModel = preload("res://game/characters/models/civilian_model.gd")
const LocomotionRig = preload("res://game/characters/locomotion_rig.gd")
const LocomotionPose = preload("res://game/characters/locomotion_pose.gd")
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
	prepare_locomotion()
	if _walk_speed == 0.0:
		mode = &"knock"
	elif _walk_speed > 0.0:
		# Explicit inspection/capture override; gameplay consumers publish root motion.
		velocity = -global_basis.z.normalized() * _walk_speed
	gait.update(velocity, grounded, mode, delta, vertical_speed, action_phase)

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
	skeleton.force_update_all_bone_transforms()

func _rotate(bone_name: String, axis: Vector3, angle: float) -> void:
	skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), Quaternion(axis, angle))

func set_walk_speed(speed: float) -> void:
	_walk_speed = speed
	_manual_distance = 0.0
	if speed == 0.0:
		reset_pose()

func reset_pose() -> void:
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

func _reach_hand(suffix: String, target: Vector3) -> void:
	var upper := skeleton.find_bone("upper_arm" + suffix)
	var lower := skeleton.find_bone("lower_arm" + suffix)
	var hand := skeleton.find_bone("hand" + suffix)
	var shoulder := skeleton.get_bone_global_rest(upper).origin
	var upper_rest := skeleton.get_bone_rest(lower).origin
	var lower_rest := skeleton.get_bone_rest(hand).origin
	var upper_length := upper_rest.length()
	var lower_length := lower_rest.length()
	# The authored hand's visible centre is below its joint; solve once more
	# after rotating that offset so the grip targets the palm, not the wrist.
	var palm_offset := Vector3(0, -0.034, -0.008)
	var wrist := target
	for iteration in 3:
		var reach := wrist - shoulder
		var distance := clampf(reach.length(), absf(upper_length - lower_length) + 0.0001, upper_length + lower_length - 0.0001)
		var toward := reach.normalized()
		var bend := Vector3.DOWN - toward * Vector3.DOWN.dot(toward)
		if bend.length_squared() < 0.0001:
			bend = Vector3.FORWARD
		bend = bend.normalized()
		var along := (distance * distance + upper_length * upper_length - lower_length * lower_length) / (2.0 * distance)
		var elbow := shoulder + toward * along + bend * sqrt(maxf(0.0, upper_length * upper_length - along * along))
		var upper_rotation := Quaternion(upper_rest.normalized(), (elbow - shoulder).normalized())
		var lower_rotation := Quaternion(lower_rest.normalized(), (shoulder + toward * distance - elbow).normalized())
		skeleton.set_bone_pose_rotation(upper, upper_rotation)
		skeleton.set_bone_pose_rotation(lower, upper_rotation.inverse() * lower_rotation)
		wrist = target - lower_rotation * palm_offset

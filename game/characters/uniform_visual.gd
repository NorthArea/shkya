extends Node3D
## Visual-only adapter for the two approved uniforms. Feet=0, local forward=-Z.
const PoliceModel = preload("res://game/characters/models/police_model.gd")
const GuardModel = preload("res://game/characters/models/guard_model.gd")
const ENABLED_BY_DEFAULT := true
const EMISSION_FLOOR := 0.12
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

static func enabled() -> bool:
	return ENABLED_BY_DEFAULT or "--uniform3d" in OS.get_cmdline_user_args() or "--uniform3d" in OS.get_cmdline_args()

static func supports(drawing: String) -> bool:
	return drawing == "police" or drawing == "guard"

func configure(drawing: String, height: float, color: Color) -> void:
	_kind = drawing
	visible_height = height
	model = PoliceModel.new().build_model() if drawing == "police" else GuardModel.new().build_model()
	model.scale = Vector3.ONE * height
	add_child(model)
	skeleton = model.get_node("Skeleton3D") as Skeleton3D
	uniform_mesh = skeleton.get_node("UniformMesh") as MeshInstance3D
	uniform_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
			material.emission = material.albedo_color * mean_color * EMISSION_FLOOR
			# Write only where the ordinary opaque model passes depth. Its visible
			# pixels then mask every xray fragment, including hidden inner parts.
			material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
			material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
			material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
			material.stencil_reference = 1
			tinted.surface_set_material(surface, material)
		_tinted_meshes[key] = tinted
	uniform_mesh.mesh = _tinted_meshes[key]

func update_walk(distance: float, walking: bool, delta: float, stride: float) -> void:
	if _walk_speed >= 0.0:
		walking = _walk_speed > 0.0
		_manual_distance += _walk_speed * delta
		distance = _manual_distance
	if not walking:
		reset_pose()
		return
	var phase := distance * TAU / (stride * 4.0)
	var step := sin(phase)
	_rotate("leg_l", Vector3.RIGHT, step * 0.25)
	_rotate("leg_r", Vector3.RIGHT, -step * 0.25)
	_rotate("foot_l", Vector3.RIGHT, -step * 0.09)
	_rotate("foot_r", Vector3.RIGHT, step * 0.09)
	_rotate("spine", Vector3.UP, step * 0.022)
	if _kind == "guard":
		_rotate("upper_arm_l", Vector3.RIGHT, -step * 0.13)
		_rotate("upper_arm_r", Vector3.RIGHT, step * 0.13)
	var hips := skeleton.find_bone("hips")
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_rest(hips).origin + Vector3(0, (1.0 - cos(phase * 2.0)) * 0.0025, 0))

func _rotate(bone_name: String, axis: Vector3, angle: float) -> void:
	skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), Quaternion(axis, angle))

func set_walk_speed(speed: float) -> void:
	_walk_speed = speed
	_manual_distance = 0.0
	if speed == 0.0:
		reset_pose()

func reset_pose() -> void:
	skeleton.reset_bone_poses()

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
	return result

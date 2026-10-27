extends Node3D
## LightingAndWeather (ART-02): сумерки, прохладный общий свет, тёплые фонари, подъезд и окно киоска,
## мокрый снег вокруг камеры. Свечение окон и фонарей даёт glow, мокрый асфальт — SSR.

const Layout = preload("res://game/world/layout.gd")

const WARM := Color(1.0, 0.74, 0.42)
const SNOW_BOX := Vector3(44.0, 2.0, 44.0)

var snow: CPUParticles3D

func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.07, 0.09, 0.20)
	sky_material.sky_horizon_color = Color(0.36, 0.33, 0.45)
	sky_material.ground_bottom_color = Color(0.10, 0.10, 0.12)
	sky_material.ground_horizon_color = Color(0.36, 0.33, 0.45)
	sky_material.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.32, 0.45)
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.35
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sky_light := DirectionalLight3D.new()
	sky_light.name = "CoolSky"
	sky_light.light_color = Color(0.62, 0.70, 0.95)
	sky_light.light_energy = 0.35
	sky_light.shadow_enabled = true
	sky_light.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	add_child(sky_light)

	var index := 0
	for spec in Layout.LAMPS:
		_lamp(spec[0], spec[1], index)
		index += 1
	for p in Layout.street_lamps():
		_lamp(Vector3(p.x, Layout.LAMP_HEIGHT - 0.4, p.y), 5.0, index)
		index += 1
	_build_snow()

func _lamp(at: Vector3, energy: float, index: int) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "WarmLamp%d" % index
	lamp.position = at
	lamp.light_color = WARM
	lamp.light_energy = energy
	lamp.omni_range = 16.0
	lamp.omni_attenuation = 1.4
	add_child(lamp)

## Мокрый снег: облако частиц над текущей камерой, слегка косо по ветру.
func _build_snow() -> void:
	var flake := SphereMesh.new()
	flake.radius = 0.03
	flake.height = 0.06
	flake.radial_segments = 6
	flake.rings = 3
	var flake_material := StandardMaterial3D.new()
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.albedo_color = Color(0.92, 0.94, 1.0, 0.7)
	flake.material = flake_material
	# CPU-частицы: снегу хватает, а вычислительный шейдер GPU-частиц в этой сцене оставлял утечку при выходе.
	snow = CPUParticles3D.new()
	snow.name = "WetSnow"
	snow.amount = 2500
	snow.lifetime = 4.0
	snow.preprocess = 4.0
	snow.mesh = flake
	snow.local_coords = false
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = SNOW_BOX * 0.5
	snow.direction = Vector3(0.25, -1.0, 0.1)
	snow.spread = 8.0
	snow.initial_velocity_min = 3.0
	snow.initial_velocity_max = 4.5
	snow.gravity = Vector3(0.6, -1.5, 0.2)
	snow.scale_amount_min = 0.6
	snow.scale_amount_max = 1.3
	add_child(snow)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and snow:
		snow.global_position = camera.global_position + Vector3(0, 12.0, 0)

extends Node3D
## LightingAndWeather (ART-02, ART-05): сумерки, прохладный общий свет, натриевые фонари, тёплые подъезд и окно киоска,
## мокрый снег вокруг камеры. Свечение окон и фонарей даёт glow, мокрый асфальт — SSR.
## Цвета по сверке ART-04 (черты 14, 21): тени на снегу голубые с уклоном в циан (G > R), без лавандового налёта;
## уличный свет — натриевый оранжевый (снег под фонарём #cb6312), окна и подъезд — теплее-белые.

const Layout = preload("res://game/world/layout.gd")

const WARM := Color(1.0, 0.74, 0.42)       # подъезд, окно киоска
# Повторная сверка ART-05 (Н1): чистый (1,0; 0,50; 0,12) в смеси с голубым общим светом давал розово-сиреневое;
# светлее и желтее, сильнее, а общий свет слабее — снег под фонарём уходит в оранжевый.
# Итоговая сверка ART-05 (И1): цвет света Godot переводит из sRGB в линейный — G 0,56 становился ≈0,28,
# и с голубым общим светом выходила маджента. Зелёного больше, синего меньше.
const SODIUM := Color(1.0, 0.68, 0.12)     # уличные фонари
const YARD_POOL := Color(1.0, 0.90, 0.78)  # пятно света на стоянке: белая «Лада» остаётся белой (Н3)
const SnowShader = preload("res://game/world/shaders/wet_snow.gdshader")
const SNOW_BOX := Vector3(32.0, 12.0, 32.0)      # объём хлопьев вокруг камеры
const SNOW_AMOUNT := 3000

var snow: MultiMeshInstance3D

func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.08, 0.12, 0.22)
	sky_material.sky_horizon_color = Color(0.36, 0.47, 0.58)
	sky_material.ground_bottom_color = Color(0.10, 0.11, 0.12)
	sky_material.ground_horizon_color = Color(0.36, 0.47, 0.58)
	sky_material.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.fog_enabled = true
	env.fog_light_color = Color(0.24, 0.30, 0.37)   # тот же оттенок, темнее: меньше синего в тёплом (И2)
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.35
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sky_light := DirectionalLight3D.new()
	sky_light.name = "CoolSky"
	sky_light.light_color = Color(0.62, 0.78, 1.0)
	sky_light.light_energy = 0.2   # голубой направленный свет с оранжевым давал сиреневое (повторная сверка ART-05, Н1)
	sky_light.shadow_enabled = true
	sky_light.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	add_child(sky_light)

	var index := 0
	for spec in Layout.LAMPS:
		# Дворовый фонарь над стоянкой — мягкий тёплый, как пятно под ним: «Лада» остаётся белой.
		_lamp(spec[0], spec[1], index, YARD_POOL if index == 1 else WARM, 16.0)
		index += 1
	# Светильник — на конце консоли, над проезжей частью (ART-05).
	for p in Layout.street_lamps():
		var tip: Vector2 = p + Layout.lamp_arm(p)
		_lamp(Vector3(tip.x, Layout.POLE_HEIGHT - 0.8, tip.y), 11.0, index, SODIUM, 19.0)
		index += 1
	# Контрастные пятна тёплого света на земле (раздел 2 канона): стоянка «Лады» под дворовым фонарём и площадка у окна киоска.
	# Пятно у стоянки — мягче натриевого: под ним белая «Лада» должна оставаться белой (канон, раздел 2).
	_pool(Layout.LAMPS[1][0] + Vector3(0.0, -0.3, 0.0), 3.0, 40.0, 12.0, YARD_POOL)   # Н6: Илюша не сливается с пятном
	_pool(Layout.LAMPS[2][0] + Vector3(0.6, 0.3, 0.0), 5.0, 55.0, 7.0, WARM)
	_build_snow()

## Конус света вниз: видимое пятно на снегу, без теней (дёшево).
func _pool(at: Vector3, energy: float, angle: float, reach: float, color: Color) -> void:
	var spot := SpotLight3D.new()
	spot.name = "WarmPool%d" % get_child_count()
	spot.position = at
	spot.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	spot.light_color = color
	spot.light_energy = energy
	spot.spot_range = reach
	spot.spot_angle = angle
	spot.spot_angle_attenuation = 0.6
	add_child(spot)

func _lamp(at: Vector3, energy: float, index: int, color: Color, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "WarmLamp%d" % index
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.4
	add_child(lamp)

## Мокрый снег: MultiMesh из плоских хлопьев, движение и обёртка вокруг камеры — в шейдере wet_snow.
## Без CPU-работы в кадре и без зависимости от телепортов: объём полон с первого кадра, пешком и в машине.
func _build_snow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SnowShader
	material.set_shader_parameter("box", SNOW_BOX)
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = SNOW_AMOUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 2610
	for i in SNOW_AMOUNT:
		var seed := Vector3(rng.randf(), rng.randf(), rng.randf()) * SNOW_BOX
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, seed))
	snow = MultiMeshInstance3D.new()
	snow.name = "WetSnow"
	snow.multimesh = multimesh
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Хлопья рисуются вокруг камеры, где бы она ни была: границы — весь квартал с запасом.
	snow.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
	add_child(snow)

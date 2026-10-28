extends Node3D
## LightingAndWeather (ART-02, ART-05, CITY-01 L): сумерки, прохладный общий свет, натриевые фонари, тёплые подъезд и
## окно киоска, мокрый снег вокруг камеры с порывами, позёмка, пар из люков, ореолы фонарей, мокрый асфальт у
## перекрёстков и остановок. Свечение окон, вывесок и фонарей даёт glow, мокрый асфальт — SSR.
## Цвета по сверке ART-04 (черты 14, 21): тени на снегу голубые с уклоном в циан (G > R), без лавандового налёта;
## уличный свет — натриевый оранжевый (снег под фонарём #cb6312), окна и подъезд — теплее-белые.
## CITY-01 L: все ручки света и погоды — константы этого файла (окна и мокрый асфальт читает materials.gd,
## вывески — level_geometry.gd).

const Layout = preload("res://game/world/layout.gd")

const WARM := Color(1.0, 0.74, 0.42)       # подъезд, окно киоска
# Повторная сверка ART-05 (Н1): чистый (1,0; 0,50; 0,12) в смеси с голубым общим светом давал розово-сиреневое;
# светлее и желтее, сильнее, а общий свет слабее — снег под фонарём уходит в оранжевый.
# Итоговая сверка ART-05 (И1): цвет света Godot переводит из sRGB в линейный — G 0,56 становился ≈0,28,
# и с голубым общим светом выходила маджента. Зелёного больше, синего меньше.
const SODIUM := Color(1.0, 0.74, 0.10)     # уличные фонари (итоговая сверка ART-06, С9: без сиреневого снега у киоска)
const YARD_POOL := Color(1.0, 0.90, 0.78)  # пятно света на стоянке: белая «Лада» остаётся белой (Н3)
const SnowShader = preload("res://game/world/shaders/wet_snow.gdshader")
const HaloShader = preload("res://game/world/shaders/lamp_halo.gdshader")
const DriftShader = preload("res://game/world/shaders/ground_drift.gdshader")
const SteamShader = preload("res://game/world/shaders/steam_puff.gdshader")
const SNOW_BOX := Vector3(32.0, 12.0, 32.0)      # объём хлопьев вокруг камеры
const SNOW_AMOUNT := 3000

# --- CITY-01 L: тонмаппинг, bloom, SSAO ---
const EXPOSURE := 1.1                  # filmic, как принято в ART-05/06
const GLOW_INTENSITY := 0.75
const GLOW_BLOOM := 0.05               # было 0,08: меньше общей дымки («мыла»); ореолы дают окна, вывески и лампы
const GLOW_THRESHOLD := 0.9
const SSAO_RADIUS := 1.2
const SSAO_INTENSITY := 1.1            # мягко: только контакт у валов, машин и стен
const SSAO_POWER := 1.4

# --- ветер и порывы снегопада ---
const WIND := Vector3(0.45, 0.0, 0.2)  # м/с, средний ветер (хлопья и позёмка)
const GUST_PERIOD := 9.0               # с, основной период порывов
const GUST_WIND := 2.2                 # в порыв ветер сильнее в (1 + GUST_WIND) раз
const GUST_TURN := 0.5                 # рад, поворот ветра в порыв
const SNOW_DENSITY_CALM := 0.55        # доля видимых хлопьев в затишье; в порыв — все

# --- позёмка: низкий слой снега, несомый ветром вдоль земли (shaders/ground_drift) ---
const DRIFT_AMOUNT := 700
const DRIFT_BOX := Vector3(36.0, 0.3, 36.0)   # объём вокруг камеры
const DRIFT_SPEED := 3.2                      # м/с в затишье; в порыв — в (1 + GUST_WIND) раз
const DRIFT_ALPHA := 0.11
const DRIFT_STREAK := Vector2(0.04, 1.0)       # м, ширина и длина штриха
const DRIFT_NEAR_FADE := 5.0                  # м: ближе к камере позёмка гаснет — не «дождь» в кадре
const DRIFT_COLOR := Color(0.86, 0.89, 0.96)

# --- пар из люков (ТЭЦ и вытяжки на крышах строит level_geometry; shaders/steam_puff) ---
const STEAM_VENTS: Array[Vector3] = [
	Vector3(-44.0, 0.0, 93.0),    # двор, у проезда к стоянке
	Vector3(12.0, 0.0, 30.5),     # улица A, середина
	Vector3(63.5, 0.0, 36.0),     # перекрёсток A∩B
	Vector3(72.5, 0.0, -50.0),    # улица B у площадки киоска
	Vector3(-57.5, 0.0, -24.0),   # улица D
]
const STEAM_PUFFS := 10                 # клубов на люк
const STEAM_ALPHA := 0.26
const STEAM_COLOR := Color(0.64, 0.67, 0.74)

# --- ореолы фонарей в снегопаде ---
const HALO_SIZE := 2.6                 # м, сторона спрайта у уличного фонаря
const HALO_ENERGY := 0.7
const HALO_SNOW_GAIN := 0.6            # в порыв ореол ярче: больше хлопьев в свете
const FLAKE_LAMP_RADIUS := 5.5         # м: хлопья ближе к лампе подсвечены её цветом
const FLAKE_LAMP_GAIN := 1.6

# --- мокрый асфальт: [центр x/z, радиус, сила]; читает Materials.road ---
const WET_SPOTS: Array[Vector4] = [
	Vector4(70.0, 32.0, 9.0, 1.0),     # A∩B
	Vector4(-60.0, 32.0, 9.0, 1.0),    # A∩D
	Vector4(70.0, -100.0, 8.0, 0.8),   # C∩B
	Vector4(-60.0, -100.0, 8.0, 0.8),  # C∩D
	Vector4(-30.0, 29.0, 7.0, 1.0),    # остановка на A
	Vector4(67.0, -62.0, 7.0, 1.0),    # остановка у киоска
]
const WET_GLOSS := 0.9                 # насколько каша в пятне становится глянцевой
const WET_DARKEN := 0.55               # во сколько раз темнеет мокрая каша
const WET_ROUGHNESS := 0.16            # шероховатость мокрого: блик фонаря — мягкая полоса, не точка

# --- окна: температура света и телевизоры; читает Materials.facade ---
const WINDOW_WARM := Color(1.0, 0.68, 0.32)     # лампа накаливания (принято ART-05)
const WINDOW_AMBER := Color(1.0, 0.56, 0.24)    # абажур, теплее
const WINDOW_COOL := Color(0.95, 0.91, 0.78)    # люминесцентная, белее
const WINDOW_COOL_RATIO := 0.12                 # доля горящих окон с холодным светом
const WINDOW_TV_RATIO := 0.10                   # доля горящих окон, где светит только телевизор
const WINDOW_TV := Color(0.22, 0.50, 1.0)    # голубой с G > R: без лавандового (сверка ART-04)
const WINDOW_TV_ENERGY := 0.8

# --- вывески: подсветка; читает level_geometry ---
const SIGN_GLOW := 1.7                 # множитель цвета букв (> 1 — попадает в glow); цвет сперва насыщается (pow)
const SIGN_LIGHT_ENERGY := 1.4         # цветной отсвет вывески на снег
const SIGN_LIGHT_RANGE := 6.0
const KIOSK_SIGN_GLOW := 0.5           # короб «ХЛЕБ» — световой, буквы остаются тёмно-красными

var snow: MultiMeshInstance3D
var gust := 0.0                        # 0 — затишье, 1 — порыв
var _snow_material: ShaderMaterial
var _halo_material: ShaderMaterial
var _drift_material: ShaderMaterial
var _steam_material: ShaderMaterial
var _wind_offset := Vector3.ZERO
var _drift_offset := Vector3.ZERO
var _time := 0.0
var _halos: Array = []                 # [позиция, размер, цвет]

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
	env.tonemap_exposure = EXPOSURE
	env.glow_enabled = true
	env.glow_intensity = GLOW_INTENSITY
	env.glow_bloom = GLOW_BLOOM
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssao_enabled = true
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_power = SSAO_POWER
	env.ssao_light_affect = 0.0
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
	_halos.append([Layout.LAMPS[0][0] + Vector3(0, 0.1, 0), HALO_SIZE * 0.45, WARM])         # подъезд
	_halos.append([Vector3(-52.0, 5.85, 100.0), HALO_SIZE * 0.8, YARD_POOL])                  # дворовый фонарь
	# Светильник — на конце консоли, над проезжей частью (ART-05).
	for p in Layout.street_lamps():
		var tip: Vector2 = p + Layout.lamp_arm(p)
		_lamp(Vector3(tip.x, Layout.POLE_HEIGHT - 0.8, tip.y), 11.0, index, SODIUM, 19.0)
		_halos.append([Vector3(tip.x, Layout.POLE_HEIGHT - 0.5, tip.y), HALO_SIZE, SODIUM])
		index += 1
	# Контрастные пятна тёплого света на земле (раздел 2 канона): стоянка «Лады» под дворовым фонарём и площадка у окна киоска.
	# Пятно у стоянки — мягче натриевого: под ним белая «Лада» должна оставаться белой (канон, раздел 2).
	_pool(Layout.LAMPS[1][0] + Vector3(0.0, -0.3, 0.0), 3.0, 40.0, 12.0, YARD_POOL)   # Н6: Илюша не сливается с пятном
	_pool(Layout.LAMPS[2][0] + Vector3(0.6, 0.3, 0.0), 5.0, 55.0, 7.0, WARM)
	_build_snow()
	_build_halos()
	_build_drift()
	_build_steam()
	_update_weather(0.0)

func _process(delta: float) -> void:
	_update_weather(delta)

## Порывы: ветер сильнее и поворачивает, хлопьев больше, позёмка быстрее и гуще, ореолы ярче.
func _update_weather(delta: float) -> void:
	_time += delta
	var wave := sin(_time * TAU / GUST_PERIOD) * (0.6 + 0.4 * sin(_time * TAU / (GUST_PERIOD * 0.37) + 1.1))
	gust = smoothstep(0.15, 0.9, 0.5 + 0.5 * wave)
	var wind := WIND.rotated(Vector3.UP, GUST_TURN * (gust - 0.3)) * (1.0 + GUST_WIND * gust)
	_wind_offset += wind * delta
	_wind_offset = Vector3(fposmod(_wind_offset.x, SNOW_BOX.x), 0.0, fposmod(_wind_offset.z, SNOW_BOX.z))
	var density := lerpf(SNOW_DENSITY_CALM, 1.0, gust)
	_snow_material.set_shader_parameter("drift", _wind_offset)
	_snow_material.set_shader_parameter("density", density)
	_halo_material.set_shader_parameter("energy", HALO_ENERGY * (1.0 + HALO_SNOW_GAIN * (density - SNOW_DENSITY_CALM)))
	_drift_offset += wind.normalized() * DRIFT_SPEED * (1.0 + GUST_WIND * gust) * delta
	_drift_offset = Vector3(fposmod(_drift_offset.x, DRIFT_BOX.x), 0.0, fposmod(_drift_offset.z, DRIFT_BOX.z))
	_drift_material.set_shader_parameter("drift", _drift_offset)
	_drift_material.set_shader_parameter("wind_dir", wind.normalized())
	_drift_material.set_shader_parameter("density", lerpf(0.35, 1.0, gust))
	_steam_material.set_shader_parameter("wind", wind)

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
## Хлопья у ламп подсвечены их цветом — ореол в снегопаде (CITY-01 L).
func _build_snow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_snow_material = ShaderMaterial.new()
	_snow_material.shader = SnowShader
	_snow_material.set_shader_parameter("box", SNOW_BOX)
	var lamps := PackedVector4Array()
	for halo in _halos:
		var at: Vector3 = halo[0]
		lamps.append(Vector4(at.x, at.y, at.z, FLAKE_LAMP_RADIUS * halo[1] / HALO_SIZE))
	_snow_material.set_shader_parameter("lamps", lamps)
	_snow_material.set_shader_parameter("lamp_count", lamps.size())
	_snow_material.set_shader_parameter("lamp_tint", SODIUM)
	_snow_material.set_shader_parameter("lamp_gain", FLAKE_LAMP_GAIN)
	quad.material = _snow_material
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

## Ореолы ламп: один MultiMesh спрайтов-«светящихся пятен» (additive, без тумана и глубины записи).
func _build_halos() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = HaloShader
	quad.material = _halo_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = _halos.size()
	for i in _halos.size():
		var size: float = _halos[i][1]
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), _halos[i][0]))
		multimesh.set_instance_color(i, _halos[i][2])
	var node := MultiMeshInstance3D.new()
	node.name = "LampHalos"
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

## Позёмка: штрихи снега у самой земли вокруг камеры, по ветру (движение — в шейдере ground_drift).
func _build_drift() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_drift_material = ShaderMaterial.new()
	_drift_material.shader = DriftShader
	_drift_material.set_shader_parameter("box", DRIFT_BOX)
	_drift_material.set_shader_parameter("color", Color(DRIFT_COLOR.r, DRIFT_COLOR.g, DRIFT_COLOR.b, DRIFT_ALPHA))
	_drift_material.set_shader_parameter("streak_width", DRIFT_STREAK.x)
	_drift_material.set_shader_parameter("streak_len", DRIFT_STREAK.y)
	_drift_material.set_shader_parameter("near_fade", DRIFT_NEAR_FADE)
	quad.material = _drift_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = DRIFT_AMOUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 2811
	for i in DRIFT_AMOUNT:
		var seed := Vector3(rng.randf(), rng.randf(), rng.randf()) * DRIFT_BOX
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, seed))
	var node := MultiMeshInstance3D.new()
	node.name = "GroundDrift"
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
	add_child(node)

## Пар из люков: чугунная крышка с протаявшим кругом и клубы, сносимые ветром (шейдер steam_puff).
func _build_steam() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_steam_material = ShaderMaterial.new()
	_steam_material.shader = SteamShader
	_steam_material.set_shader_parameter("color", Color(STEAM_COLOR.r, STEAM_COLOR.g, STEAM_COLOR.b, STEAM_ALPHA))
	quad.material = _steam_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = STEAM_VENTS.size() * STEAM_PUFFS
	var rng := RandomNumberGenerator.new()
	rng.seed = 2812
	var cover := CylinderMesh.new()
	cover.top_radius = 0.33
	cover.bottom_radius = 0.33
	cover.height = 0.02
	cover.radial_segments = 16
	cover.material = _plain(Color(0.05, 0.05, 0.055), 0.5)
	var index := 0
	for v in STEAM_VENTS.size():
		var at: Vector3 = STEAM_VENTS[v]
		var mesh := MeshInstance3D.new()
		mesh.name = "Manhole%d" % v
		mesh.mesh = cover
		mesh.position = at + Vector3(0, 0.04, 0)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		var shift := rng.randf()
		for k in STEAM_PUFFS:
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, at))
			multimesh.set_instance_custom_data(index, Color(fposmod(shift + float(k) / STEAM_PUFFS, 1.0), rng.randf(), rng.randf(), 0.0))
			index += 1
	var node := MultiMeshInstance3D.new()
	node.name = "ManholeSteam"
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
	add_child(node)

static func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

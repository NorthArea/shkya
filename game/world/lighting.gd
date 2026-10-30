extends Node3D
## LightingAndWeather (ART-02, ART-05, CITY-01 L): сумерки, прохладный общий свет, натриевые фонари, тёплые подъезд и
## окно киоска, мокрый снег вокруг камеры с порывами, позёмка, пар из люков, ореолы фонарей, мокрый асфальт у
## перекрёстков и остановок. Свечение окон, вывесок и фонарей даёт glow, мокрый асфальт — SSR.
## Цвета по сверке ART-04 (черты 14, 21): тени на снегу голубые с уклоном в циан (G > R), без лавандового налёта;
## уличный свет — натриевый оранжевый (снег под фонарём #cb6312), окна и подъезд — теплее-белые.
## CITY-01 L: все ручки света и погоды — константы этого файла (окна и мокрый асфальт читает materials.gd,
## вывески — level_geometry.gd).
## CITY-02 L: своё небо с облаками и заревом (shaders/city_sky), объёмный туман с рассеянием света фонарей, SSIL —
## отражённый свет от снега, SSR на лужах в колеях, блеск и холодная толща снега, колеи и следы с глубиной, ближние
## хлопья с боке; ручки поверхностей (снег, дорога, тропы) этот узел передаёт в материалы сам (_apply_surface_fx).
## Цветокоррекция 3D LUT есть, но выключена по замеру (GRADE_ENABLED). Комнаты за окнами рисует facade.gdshader (часть B).

const Layout = preload("res://game/world/layout.gd")

const WARM := Color(1.0, 0.74, 0.42)       # подъезд, окно киоска
# Повторная сверка ART-05 (Н1): чистый (1,0; 0,50; 0,12) в смеси с голубым общим светом давал розово-сиреневое;
# светлее и желтее, сильнее, а общий свет слабее — снег под фонарём уходит в оранжевый.
# Итоговая сверка ART-05 (И1): цвет света Godot переводит из sRGB в линейный — G 0,56 становился ≈0,28,
# и с голубым общим светом выходила маджента. Зелёного больше, синего меньше.
# POLISH-03 C (критик 30.10, концепты 05/06/e05): натрий теплее и оранжевее — G 0,74 → 0,64 (линейный 0,52 → 0,37),
# синий почти ноль, чтобы с голубым общим светом не уйти в сиреневое (И1).
const SODIUM := Color(1.0, 0.64, 0.06)     # уличные фонари (итоговая сверка ART-06, С9: без сиреневого снега у киоска)
const YARD_POOL := Color(1.0, 0.90, 0.78)  # пятно света на стоянке: белая «Лада» остаётся белой (Н3)
const SnowShader = preload("res://game/world/shaders/wet_snow.gdshader")
const HaloShader = preload("res://game/world/shaders/lamp_halo.gdshader")
const DriftShader = preload("res://game/world/shaders/ground_drift.gdshader")
const SteamShader = preload("res://game/world/shaders/steam_puff.gdshader")
const SkyShader = preload("res://game/world/shaders/city_sky.gdshader")
const BokehShader = preload("res://game/world/shaders/snow_bokeh.gdshader")
const SurfaceSnowShader = preload("res://game/world/shaders/snow.gdshader")
const RoadShader = preload("res://game/world/shaders/road.gdshader")
const TrailShader = preload("res://game/world/shaders/trail.gdshader")
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

# --- CITY-02 L: небо (shaders/city_sky). Градиент — цвета ART-05, как у прежнего ProceduralSkyMaterial ---
const SKY_TOP := Color(0.08, 0.12, 0.22)
const SKY_HORIZON := Color(0.36, 0.47, 0.58)       # ART-05: горизонт сумерек
const SKY_GROUND := Color(0.10, 0.11, 0.12)
const SKY_GLOW := Color(0.62, 0.46, 0.32)          # городское зарево: натрий в дымке, приглушённый
const SKY_GLOW_STRENGTH := 0.35                    # у самого горизонта; общий свет сцены зарево не меняет
const SKY_GLOW_HEIGHT := 0.10                      # высота полосы зарева (доля sin угла над горизонтом)
const CLOUD_COVER := 0.48                          # покрытие неба облаками 0…1
const CLOUD_ALPHA := 0.85
const CLOUD_SCALE := 2.2                           # крупность облаков (меньше — крупнее)
const CLOUD_LIT := Color(0.52, 0.47, 0.44)         # низ облаков у горизонта, в зареве
const CLOUD_DARK := Color(0.25, 0.28, 0.35)        # облака в зените: светлее неба (подсвечены городом), холодные
const CLOUD_DRIFT := 0.004                         # рад/с: поворот неба вокруг зенита (облака плывут)

# --- CITY-02 L: объёмный туман Forward+ — рассеяние света фонарей в снегопаде ---
const VFOG_DENSITY := 0.003            # общий слой; лица персонажей тумана не получают (fog_disabled у спрайтов)
const VFOG_ALBEDO := Color(0.80, 0.88, 0.98)
const VFOG_ANISOTROPY := 0.55          # вперёд: свет фонаря виден ореолом, если смотреть на лампу
const VFOG_LENGTH := 70.0              # м, дальность сетки тумана
const VFOG_AMBIENT := 0.9              # доля общего (небесного) света в тумане
const VFOG_SKY_LIGHT := 0.4            # доля голубого направленного света в тумане
const STREET_LAMP_ENERGY := 13.0       # CITY-02 F: конус вниз (было шаром 11 на 19 м)
const STREET_LAMP_RANGE := 14.0        # м
const STREET_LAMP_ANGLE := 64.0        # градусов от вертикали
const VFOG_LAMP := 2.0                 # уличные фонари: рассеяние в тумане
const VFOG_WARM := 0.8                 # подъезд и дворовый фонарь
const VFOG_OTHER := -1.0               # прочие лампы сцены (вывески, фары): −1 — не трогать (по умолчанию Godot 1,0)
const FOG_DENSITY := 0.0075            # обычный туман по дальности (как в ART-05)

# --- CITY-02 L: непрямой свет, отражения, цвет ---
const SSIL_ENABLED := true             # SDFGI: +4,3–4,6 мс на кадр (замер CITY-02 L) — не берём; SSIL ≈ +0,1–0,2 мс
const SSIL_RADIUS := 4.0
const SSIL_INTENSITY := 0.9
const SSIL_SHARPNESS := 0.98
const SSIL_NORMAL_REJECTION := 1.0
const SSR_STEPS := 48
const SSR_FADE_IN := 0.15
const SSR_FADE_OUT := 2.0
const SSR_DEPTH_TOLERANCE := 0.25
# Цветокоррекция 3D LUT (глубокие тени — в циан): выключена по замеру CITY-02 L — LUT Godot применяет не в той шкале,
# что задумано: лицо Илюши светлее на 0,6 % со сдвигом R, тени на снегу темнее на 6 %. Тонмаппинг — filmic, как в ART-05/06.
const GRADE_ENABLED := false
const GRADE_SHADOW_END := 0.28         # яркость (sRGB), выше которой цвет не меняется: лица, снег, натрий — как были
const GRADE_SHADOW_TINT := Vector3(-0.010, 0.004, 0.014)   # сдвиг в самых тёмных местах (циан, G > R)
const GRADE_LUT_SIZE := 33
const DOF_FAR_ENABLED := false         # дальний DOF: +1,2–1,8 мс на кадр (замер CITY-02 L) — выключен
const DOF_FAR_DISTANCE := 70.0
const DOF_FAR_TRANSITION := 40.0
const DOF_AMOUNT := 0.05

# --- CITY-02 L: поверхности (передаются в материалы snow / road / trail) ---
const SPARKLE_DENSITY := 0.10          # доля ячеек с искрой на чистом снегу
const SPARKLE_SCALE := 16.0            # ячеек на метр
const SPARKLE_SIZE := 0.35
const SPARKLE_TILT := 0.6              # разброс наклона граней: чем больше, тем больше углов, под которыми блеснёт
const SPARKLE_SHARP := 48.0            # острота блика: больше — искры реже и мельче
const SPARKLE_GAIN := 12.0             # яркость искры (выше порога glow — искра светится)
const SPARKLE_LAMP_REACH := 14.0       # м: искры от фонаря в этом радиусе
const SNOW_COLD := Color(0.80, 0.91, 1.0)   # холодная толща снега на краях
const SNOW_COLD_STRENGTH := 0.22
const RUT_DEPTH := 0.07                # м, накат каши над колеёй
const SLUSH_BUMP := 0.012              # м, комья каши
const PUDDLE_ROUGHNESS := 0.04         # вода в колеях мокрых пятен — зеркало для SSR
const PUDDLE_LEVEL := 0.45
const PRINT_DEPTH := 0.035             # м, отпечатки ботинок на тропах
const PRINT_STEP := 0.72
const PRINT_WALKERS := 3.0

# --- CITY-02 L: ближние хлопья с боке у камеры (shaders/snow_bokeh) ---
const BOKEH_AMOUNT := 110
const BOKEH_BOX := Vector3(6.0, 4.0, 6.0)
const BOKEH_SIZE := 0.05               # угловой диаметр диска, рад
const BOKEH_ALPHA := 0.05             # additive: диск только светлее фона
const BOKEH_CLEAR := Vector2(0.28, 0.42)   # «окно» без ближних хлопьев в середине кадра: лицо персонажа открыто
const FLAKE_BIG_SHARE := 0.12          # доля крупных хлопьев (слипшихся) в обычном снегопаде
const FLAKE_BIG_SCALE := 1.8

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
const DRIFT_ALPHA := 0.07                      # 0,11 читалось как дождь/царапины (проверка CITY-01, P3)
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
# POLISH-03 C: блеск мокрых колей под уличными фонарями (shaders/road: glint_*): отражение светильника полосой к камере.
const GLINT_GAIN := 1.6                # яркость отражения (≥ 1 — светится через glow)
const GLINT_WIDTH := 0.0025            # ширина полосы по азимуту (1 − cos угла)
const GLINT_STRETCH := 0.06            # длина полосы по высоте (квадрат разности синусов)
const GLINT_REACH := 26.0              # м от светильника до точки дороги
const GLINT_NEAR := 45.0               # м: в шейдер идут только фонари ближе к камере (дальние блики мельче пикселя)
const GLINT_MAX := 12                  # и не больше стольких — цикл в каждом фрагменте дороги короткий (бюджет C9)

# --- окна: температура света и телевизоры; читает Materials.facade ---
const WINDOW_WARM := Color(1.0, 0.68, 0.32)     # лампа накаливания (принято ART-05)
const WINDOW_AMBER := Color(1.0, 0.56, 0.24)    # абажур, теплее
const WINDOW_COOL := Color(0.95, 0.91, 0.78)    # люминесцентная, белее
const WINDOW_COOL_RATIO := 0.12                 # доля горящих окон с холодным светом
const WINDOW_TV_RATIO := 0.05                   # доля горящих окон, где светит только телевизор
const WINDOW_TV := Color(0.45, 0.62, 0.95)    # голубой с G > R: без лавандового (сверка ART-04)
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
var _bokeh_material: ShaderMaterial
var _env: Environment

func _ready() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SkyShader
	sky_material.set_shader_parameter("top_color", SKY_TOP)
	sky_material.set_shader_parameter("horizon_color", SKY_HORIZON)
	sky_material.set_shader_parameter("ground_bottom", SKY_GROUND)
	sky_material.set_shader_parameter("ground_horizon", SKY_HORIZON)
	sky_material.set_shader_parameter("glow_color", SKY_GLOW)
	sky_material.set_shader_parameter("glow_strength", SKY_GLOW_STRENGTH)
	sky_material.set_shader_parameter("glow_height", SKY_GLOW_HEIGHT)
	sky_material.set_shader_parameter("cloud_cover", CLOUD_COVER)
	sky_material.set_shader_parameter("cloud_alpha", CLOUD_ALPHA)
	sky_material.set_shader_parameter("cloud_scale", CLOUD_SCALE)
	sky_material.set_shader_parameter("cloud_lit", CLOUD_LIT)
	sky_material.set_shader_parameter("cloud_dark", CLOUD_DARK)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	_env = env
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
	env.ssr_max_steps = SSR_STEPS
	env.ssr_fade_in = SSR_FADE_IN
	env.ssr_fade_out = SSR_FADE_OUT
	env.ssr_depth_tolerance = SSR_DEPTH_TOLERANCE
	env.ssil_enabled = SSIL_ENABLED
	env.ssil_radius = SSIL_RADIUS
	env.ssil_intensity = SSIL_INTENSITY
	env.ssil_sharpness = SSIL_SHARPNESS
	env.ssil_normal_rejection = SSIL_NORMAL_REJECTION
	env.ssao_enabled = true
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_power = SSAO_POWER
	env.ssao_light_affect = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.24, 0.30, 0.37)   # тот же оттенок, темнее: меньше синего в тёплом (И2)
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.35
	env.volumetric_fog_enabled = VFOG_DENSITY > 0.0
	env.volumetric_fog_density = VFOG_DENSITY
	env.volumetric_fog_albedo = VFOG_ALBEDO
	env.volumetric_fog_anisotropy = VFOG_ANISOTROPY
	env.volumetric_fog_length = VFOG_LENGTH
	env.volumetric_fog_ambient_inject = VFOG_AMBIENT
	env.volumetric_fog_sky_affect = 0.0
	if GRADE_ENABLED:
		env.adjustment_enabled = true
		env.adjustment_color_correction = _grade_lut()
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	if DOF_FAR_ENABLED:
		var attributes := CameraAttributesPractical.new()
		attributes.dof_blur_far_enabled = true
		attributes.dof_blur_far_distance = DOF_FAR_DISTANCE
		attributes.dof_blur_far_transition = DOF_FAR_TRANSITION
		attributes.dof_blur_amount = DOF_AMOUNT
		world_env.camera_attributes = attributes
	add_child(world_env)

	var sky_light := DirectionalLight3D.new()
	sky_light.name = "CoolSky"
	sky_light.light_color = Color(0.62, 0.78, 1.0)
	sky_light.light_energy = 0.2   # голубой направленный свет с оранжевым давал сиреневое (повторная сверка ART-05, Н1)
	sky_light.shadow_enabled = true
	sky_light.light_volumetric_fog_energy = VFOG_SKY_LIGHT
	sky_light.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	add_child(sky_light)

	var index := 0
	for spec in Layout.LAMPS:
		# Дворовый фонарь над стоянкой — мягкий тёплый, как пятно под ним: «Лада» остаётся белой.
		_lamp(spec[0], spec[1], index, YARD_POOL if index == 1 else WARM, 16.0, VFOG_WARM)
		index += 1
	_halos.append([Layout.LAMPS[0][0] + Vector3(0, 0.1, 0), HALO_SIZE * 0.45, WARM])         # подъезд
	_halos.append([Vector3(-52.0, 5.85, 100.0), HALO_SIZE * 0.8, YARD_POOL])                  # дворовый фонарь
	# Светильник — на конце консоли, над проезжей частью (ART-05).
	for p in Layout.street_lamps():
		var tip: Vector2 = p + Layout.lamp_arm(p)
		_street_lamp(Vector3(tip.x, Layout.POLE_HEIGHT - 0.8, tip.y), index)
		_glint_lamps.append(Vector4(tip.x, Layout.POLE_HEIGHT - 0.8, tip.y, GLINT_REACH))
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
	_build_bokeh()
	_update_weather(0.0)
	_apply_surface_fx.call_deferred()

func _process(delta: float) -> void:
	_update_weather(delta)
	_update_glints()

## Блеск колей: в материалы дороги — до GLINT_MAX фонарей ближе GLINT_NEAR к камере.
func _update_glints() -> void:
	if _road_materials.is_empty() or GLINT_GAIN <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	var near: Array = []
	for lamp in _glint_lamps:
		var d := Vector2(lamp.x - at.x, lamp.z - at.z).length_squared()
		if d < GLINT_NEAR * GLINT_NEAR:
			near.append([d, lamp])
	near.sort_custom(func(a, b): return a[0] < b[0])
	_glint_near.resize(mini(near.size(), GLINT_MAX))
	for i in _glint_near.size():
		_glint_near[i] = near[i][1]
	var count := _glint_near.size()
	if _glint_near == _glint_sent:
		return   # тот же набор фонарей — материалы не трогать
	_glint_sent = _glint_near.duplicate()
	var padded := _glint_near.duplicate()
	padded.resize(16)
	for m in _road_materials:
		m.set_shader_parameter("glint_lamps", padded)
		m.set_shader_parameter("glint_count", count)

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
	_bokeh_material.set_shader_parameter("drift", _wind_offset)
	_bokeh_material.set_shader_parameter("density", density)
	# Облака плывут: поворот неба вокруг зенита (кубическая карта общего света от этого не пересчитывается).
	_env.sky_rotation = Vector3(0.0, fposmod(_time * CLOUD_DRIFT, TAU), 0.0)

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
	spot.light_volumetric_fog_energy = 0.0   # пятно на земле; в тумане светит сама лампа
	add_child(spot)

func _lamp(at: Vector3, energy: float, index: int, color: Color, reach: float, fog: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "WarmLamp%d" % index
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.4
	lamp.light_volumetric_fog_energy = fog
	add_child(lamp)

## Уличный фонарь (CITY-02 F): конус вниз вместо шара 19 м — шар заливал фасады жёлтым до 9-го этажа, и фасады
## становились светлее неба (черта 21 — наоборот). Конус STREET_LAMP_ANGLE от вертикали и радиус STREET_LAMP_RANGE:
## светит дорога, тротуар и низ первого этажа; выше светильника конус не достаёт.
func _street_lamp(at: Vector3, index: int) -> void:
	var lamp := SpotLight3D.new()
	lamp.name = "StreetLamp%d" % index
	lamp.position = at
	lamp.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	lamp.light_color = SODIUM
	lamp.light_energy = STREET_LAMP_ENERGY
	lamp.spot_range = STREET_LAMP_RANGE
	lamp.spot_angle = STREET_LAMP_ANGLE
	lamp.spot_attenuation = 1.4
	lamp.spot_angle_attenuation = 0.7
	lamp.light_volumetric_fog_energy = VFOG_LAMP
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
	_snow_material.set_shader_parameter("big_share", FLAKE_BIG_SHARE)
	_snow_material.set_shader_parameter("big_scale", FLAKE_BIG_SCALE)
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

## Ближние хлопья с боке: крупные мягкие диски в 0,45–3 м от камеры, кроме середины кадра (лицо персонажа).
func _build_bokeh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_bokeh_material = ShaderMaterial.new()
	_bokeh_material.shader = BokehShader
	_bokeh_material.set_shader_parameter("box", BOKEH_BOX)
	_bokeh_material.set_shader_parameter("size", BOKEH_SIZE)
	_bokeh_material.set_shader_parameter("color", Color(0.90, 0.93, 1.0, BOKEH_ALPHA))
	_bokeh_material.set_shader_parameter("center_clear", BOKEH_CLEAR)
	quad.material = _bokeh_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = BOKEH_AMOUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 2902
	for i in BOKEH_AMOUNT:
		var seed := Vector3(rng.randf(), rng.randf(), rng.randf()) * BOKEH_BOX
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, seed))
	var node := MultiMeshInstance3D.new()
	node.name = "SnowBokeh"
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
	add_child(node)

## Цветокоррекция: 3D LUT — тождество везде, кроме глубоких теней (яркость sRGB ниже GRADE_SHADOW_END): они чуть
## уходят в циан сумерек. Лица (яркость 0,6–0,8), снег и натрий не меняются.
func _grade_lut() -> ImageTexture3D:
	var n := GRADE_LUT_SIZE
	var images: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				var c := Vector3(r, g, b) / float(n - 1)
				var luma := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				var weight := 1.0 - smoothstep(0.0, GRADE_SHADOW_END, luma)
				c = (c + GRADE_SHADOW_TINT * weight).clamp(Vector3.ZERO, Vector3.ONE)
				img.set_pixel(r, g, Color(c.x, c.y, c.z))
		images.append(img)
	var lut := ImageTexture3D.new()
	lut.create(Image.FORMAT_RGB8, n, n, n, false, images)
	return lut

## Ручки поверхностей CITY-02 L — в материалы снега, дороги и троп (их создаёт materials.gd; значения по умолчанию
## в шейдерах совпадают с константами, обход только переносит правки констант). Плюс доля рассеяния прочих ламп.
func _apply_surface_fx() -> void:
	var root := get_parent()
	if root == null:
		return
	_sparkle_lamps()
	var seen := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Light3D and VFOG_OTHER >= 0.0 and not is_ancestor_of(node):
			(node as Light3D).light_volumetric_fog_energy = VFOG_OTHER
		if not node is GeometryInstance3D:
			continue
		var materials: Array = [(node as GeometryInstance3D).material_override]
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
			for i in (node as MeshInstance3D).get_surface_override_material_count():
				materials.append((node as MeshInstance3D).get_surface_override_material(i))
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for i in mesh.get_surface_count():
				materials.append(mesh.surface_get_material(i))
		for m in materials:
			if m is ShaderMaterial and not seen.has(m):
				seen[m] = true
				_surface_fx(m)

var _spark_lamps := PackedVector4Array()
var _glint_lamps := PackedVector4Array()
var _road_materials: Array[ShaderMaterial] = []
var _glint_near := PackedVector4Array()
var _glint_sent := PackedVector4Array([Vector4.INF])
var _spark_colors := PackedVector4Array()
var _spark_sky := Vector3.UP

## Лампы для искр снега: те же точки, что ореолы (подъезд, двор, уличные), цвет — линейный.
func _sparkle_lamps() -> void:
	_spark_lamps.clear()
	_spark_colors.clear()
	for halo in _halos:
		var at: Vector3 = halo[0]
		var color: Color = (halo[2] as Color).srgb_to_linear()
		_spark_lamps.append(Vector4(at.x, at.y, at.z, SPARKLE_LAMP_REACH * clampf(halo[1] / HALO_SIZE, 0.5, 1.0)))
		_spark_colors.append(Vector4(color.r, color.g, color.b, 1.0))
	var sky_light := get_node_or_null("CoolSky") as DirectionalLight3D
	if sky_light:
		_spark_sky = sky_light.global_transform.basis.z.normalized()

func _surface_fx(m: ShaderMaterial) -> void:
	if m.shader == SurfaceSnowShader:
		m.set_shader_parameter("sparkle_density", SPARKLE_DENSITY)
		m.set_shader_parameter("sparkle_scale", SPARKLE_SCALE)
		m.set_shader_parameter("sparkle_size", SPARKLE_SIZE)
		m.set_shader_parameter("sparkle_tilt", SPARKLE_TILT)
		m.set_shader_parameter("sparkle_sharp", SPARKLE_SHARP)
		m.set_shader_parameter("sparkle_gain", SPARKLE_GAIN)
		m.set_shader_parameter("sparkle_lamps", _spark_lamps)
		m.set_shader_parameter("sparkle_lamp_colors", _spark_colors)
		m.set_shader_parameter("sparkle_lamp_count", _spark_lamps.size())
		m.set_shader_parameter("sparkle_sky_dir", _spark_sky)
		m.set_shader_parameter("cold_tint", SNOW_COLD)
		m.set_shader_parameter("cold_strength", SNOW_COLD_STRENGTH)
	elif m.shader == RoadShader:
		m.set_shader_parameter("rut_depth", RUT_DEPTH)
		m.set_shader_parameter("slush_bump", SLUSH_BUMP)
		m.set_shader_parameter("puddle_roughness", PUDDLE_ROUGHNESS)
		m.set_shader_parameter("puddle_level", PUDDLE_LEVEL)
		var sodium := SODIUM.srgb_to_linear()
		_road_materials.append(m)
		m.set_shader_parameter("glint_count", 0)   # фонари у камеры задаёт _update_glints каждый кадр
		m.set_shader_parameter("glint_color", Vector3(sodium.r, sodium.g, sodium.b))
		m.set_shader_parameter("glint_gain", GLINT_GAIN)
		m.set_shader_parameter("glint_width", GLINT_WIDTH)
		m.set_shader_parameter("glint_stretch", GLINT_STRETCH)
	elif m.shader == TrailShader:
		m.set_shader_parameter("print_depth", PRINT_DEPTH)
		m.set_shader_parameter("print_step", PRINT_STEP)
		m.set_shader_parameter("print_walkers", PRINT_WALKERS)

static func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

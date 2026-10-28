extends RefCounted
## Материалы зимнего города (ART-02): процедурные шейдеры и простые StandardMaterial3D. Без внешних текстур.

const FacadeShader = preload("res://game/world/shaders/facade.gdshader")
const RoadShader = preload("res://game/world/shaders/road.gdshader")
const SnowShader = preload("res://game/world/shaders/snow.gdshader")
const BalconyGlassShader = preload("res://game/world/shaders/balcony_glass.gdshader")
const TrailShader = preload("res://game/world/shaders/trail.gdshader")
const Lighting = preload("res://game/world/lighting.gd")   # CITY-01 L: ручки окон и мокрого асфальта

# Палитры домов (ART-05 по сверке ART-04, черты 3–5): рядом стоят серые, белые, синие панельки и кирпичные
# или оштукатуренные старые дома. [стена, швы, акцент лестничной клетки].
const PANEL_PALETTES := [
	[Color(0.55, 0.56, 0.57), Color(0.36, 0.37, 0.38), Color(0.16, 0.24, 0.33)],   # серый бетон, синяя лестница
	[Color(0.72, 0.73, 0.71), Color(0.50, 0.51, 0.50), Color(0.62, 0.30, 0.20)],   # белая панель, терракота
	[Color(0.62, 0.60, 0.55), Color(0.44, 0.43, 0.40), Color(0.24, 0.36, 0.40)],   # бежево-серая
	[Color(0.30, 0.40, 0.50), Color(0.20, 0.27, 0.34), Color(0.70, 0.70, 0.68)],   # крашеная синяя
]
const LOW_PALETTES := [
	# Насыщеннее: в холодном свете жёлтое уходило в оливковое, розовое — в серо-голубое (повторная сверка ART-05, Н2).
	# Итоговая сверка (И2): ещё теплее — в кадре жёлтое было серо-оливковым (G/R 1,13).
	[Color(0.60, 0.24, 0.14), Color(0.46, 0.19, 0.12), Color(0.74, 0.68, 0.58)],   # красный кирпич
	[Color(0.90, 0.58, 0.16), Color(0.70, 0.45, 0.13), Color(0.86, 0.82, 0.72)],   # жёлтая штукатурка
	[Color(0.86, 0.44, 0.34), Color(0.66, 0.34, 0.27), Color(0.84, 0.80, 0.72)],   # розовая (теплее, С10)
]

static var _cache := {}

## Освободить общие материалы (вызывается, когда мир уходит из дерева), иначе они переживают рендер-сервер.
static func clear_cache() -> void:
	_cache.clear()

static func facade(seed: float, low := false, shops := false) -> ShaderMaterial:
	var key := "facade_%s_%s_%s" % [seed, low, shops]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = FacadeShader
		m.set_shader_parameter("seed", seed)
		m.set_shader_parameter("ground_floor_shops", 1.0 if shops else 0.0)
		_window_light(m)
		var palette: Array = _palette(seed, low)
		m.set_shader_parameter("wall_color", palette[0])
		m.set_shader_parameter("seam_color", palette[1])
		if low and posmod(int(seed), LOW_PALETTES.size()) != 0:
			m.set_shader_parameter("seams", 0.0)   # штукатурка — без швов (И7)
		if low:
			# Старый дом: этажи выше, окна уже.
			m.set_shader_parameter("floor_height", 3.3)
			m.set_shader_parameter("window_spacing", 2.6)
			m.set_shader_parameter("window_width", 1.1)
			m.set_shader_parameter("window_height", 1.8)
		_cache[key] = m
	return _cache[key]

static func _palette(seed: float, low: bool) -> Array:
	var list: Array = LOW_PALETTES if low else PANEL_PALETTES
	return list[posmod(int(seed), list.size())]

## Цвет полосы лестничной клетки этого дома.
static func facade_accent(seed: float, low: bool) -> Color:
	return _palette(seed, low)[2]

## Вал снега у дороги: светлый слежавшийся снег, грязь только у низа (сверка ART-04, черта 10; POLISH-02, п. 4).
static func snow_bank() -> ShaderMaterial:
	if not _cache.has("snow_bank"):
		var m := ShaderMaterial.new()
		m.shader = SnowShader
		m.set_shader_parameter("trodden", 0.35)
		m.set_shader_parameter("roadside", 1.0)
		_cache["snow_bank"] = m
	return _cache["snow_bank"]

## Цвет из экземпляра MultiMesh (ограждения лоджий, лестничные полосы).
static func instance_colored() -> StandardMaterial3D:
	if not _cache.has("instance_colored"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true   # цвета экземпляров заданы в sRGB (повторная сверка ART-05, Н8)
		m.roughness = 0.85
		_cache["instance_colored"] = m
	return _cache["instance_colored"]

static func balcony_glass() -> ShaderMaterial:
	if not _cache.has("balcony_glass"):
		var m := ShaderMaterial.new()
		m.shader = BalconyGlassShader
		_cache["balcony_glass"] = m
	return _cache["balcony_glass"]

## Пар (ART-06, Н4, Н9): полупрозрачный белёсый — шлейфы ТЭЦ и вытяжек на крышах.
static func steam() -> StandardMaterial3D:
	if not _cache.has("steam"):
		# Без освещения и светлее неба: иначе пар в ночном свете темнел и читался дымом (итоговая сверка ART-06, С3).
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.55, 0.58, 0.64, 0.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cache["steam"] = m
	return _cache["steam"]

## Пар и окраска труб ТЭЦ на горизонте: без тумана, дымка задана самим цветом (С2, С3).
static func far(color: Color) -> StandardMaterial3D:
	var key := "far_%s" % color
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
		m.albedo_color = color
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cache[key] = m
	return _cache[key]

static func road(along_x: bool, center: Vector2, width: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RoadShader
	m.set_shader_parameter("along_x", 1.0 if along_x else 0.0)
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("width", width)
	_wet(m)
	return m

## Окна (CITY-01 L): тёплые разных оттенков, часть холодных белых, часть — мерцающий телевизор.
static func _window_light(m: ShaderMaterial) -> void:
	m.set_shader_parameter("window_lit", Lighting.WINDOW_WARM)
	m.set_shader_parameter("window_amber", Lighting.WINDOW_AMBER)
	m.set_shader_parameter("window_cool", Lighting.WINDOW_COOL)
	m.set_shader_parameter("cool_ratio", Lighting.WINDOW_COOL_RATIO)
	m.set_shader_parameter("tv_ratio", Lighting.WINDOW_TV_RATIO)
	m.set_shader_parameter("tv_color", Lighting.WINDOW_TV)
	m.set_shader_parameter("tv_energy", Lighting.WINDOW_TV_ENERGY)

## Мокрые пятна асфальта у перекрёстков и остановок (CITY-01 L).
static func _wet(m: ShaderMaterial) -> void:
	var spots := PackedVector4Array()
	for spot in Lighting.WET_SPOTS:
		spots.append(spot)
	m.set_shader_parameter("wet_spots", spots)
	m.set_shader_parameter("wet_count", spots.size())
	m.set_shader_parameter("wet_gloss", Lighting.WET_GLOSS)
	m.set_shader_parameter("wet_darken", Lighting.WET_DARKEN)
	m.set_shader_parameter("wet_roughness", Lighting.WET_ROUGHNESS)

## Угол кольца (ARENA-01): колеи по дуге вокруг внутреннего угла corner; signs — знаки направления от угла к осям
## улицы вдоль x (по z) и улицы вдоль z (по x); width — ширина улиц (обе одинаковые).
static func road_corner(corner: Vector2, signs: Vector2, width: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RoadShader
	m.set_shader_parameter("corner", 1.0)
	m.set_shader_parameter("corner_point", corner)
	m.set_shader_parameter("corner_sign", signs)
	m.set_shader_parameter("width", width)
	_wet(m)
	return m

static func snow(trodden: float) -> ShaderMaterial:
	var key := "snow_%s" % trodden
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = SnowShader
		m.set_shader_parameter("trodden", trodden)
		_cache[key] = m
	return _cache[key]

static func plain(color: Color, roughness := 0.8, emission := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var key := "plain_%s_%s_%s_%s" % [color, roughness, emission, energy]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		if energy > 0.0:
			m.emission_enabled = true
			m.emission = emission
			m.emission_energy_multiplier = energy
		_cache[key] = m
	return _cache[key]

## Натоптанная тропинка с мягкими краями (POLISH-02, п. 19): ширина и длина — для кромки в метрах.
static func trail(width: float, length: float) -> ShaderMaterial:
	var key := "trail_%s_%s" % [width, length]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = TrailShader
		m.set_shader_parameter("width", width)
		m.set_shader_parameter("length_m", length)
		_cache[key] = m
	return _cache[key]

static func glass() -> StandardMaterial3D:
	if not _cache.has("glass"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.85, 0.6, 0.12)
		m.roughness = 0.05
		_cache["glass"] = m
	return _cache["glass"]

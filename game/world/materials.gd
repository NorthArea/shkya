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

# --- CITY-02 B: дома ---

## Цвет стены дома этой палитры (парапеты, фронтоны, цоколь под тон фасада).
static func facade_wall(seed: float, low: bool) -> Color:
	return _palette(seed, low)[0]

## Кирпичный фасад с рельефом кладки (CITY-02 B): красный кирпич, светлый раствор; belts — светлые пояса по
## перекрытиям, как у кирпичных башен (ART-06, Н11). Окна, свет и витрины — как у facade().
static func facade_brick(seed: float, low: bool, belts := false) -> ShaderMaterial:
	var key := "facade_brick_%s_%s_%s" % [seed, low, belts]
	if not _cache.has(key):
		var m := facade(seed, low).duplicate() as ShaderMaterial
		m.set_shader_parameter("brick", 1.0)
		m.set_shader_parameter("belts", 1.0 if belts else 0.0)
		m.set_shader_parameter("wall_color", LOW_PALETTES[0][0])
		m.set_shader_parameter("seam_color", LOW_PALETTES[0][1])
		m.set_shader_parameter("reveal_color", Color(0.72, 0.70, 0.66))
		_cache[key] = m
	return _cache[key]

## Мелкие детали домов одним материалом для MultiMesh (CITY-02 B): цвет экземпляра в sRGB; INSTANCE_CUSTOM:
## r — узор (0 гладкий, 1 профлист с вертикальными рёбрами, 2 решётка с прутьями, 3 оцинковка),
## g — шероховатость (0 — 0,85), b — свечение (лампы, светящиеся плафоны).
const DETAIL_CODE := """
shader_type spatial;
varying vec4 tint;
varying vec3 custom;
varying vec2 local;
varying vec2 extent;
void vertex() {
	tint = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);
	custom = INSTANCE_CUSTOM.rgb;
	// Узор идёт вдоль длинной горизонтальной оси экземпляра (у фасадов вдоль z коробка не повёрнута, а растянута).
	vec3 e = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	bool along_z = e.z > e.x;
	extent = vec2(along_z ? e.z : e.x, e.y);
	local = vec2(along_z ? VERTEX.z * e.z : VERTEX.x * e.x, VERTEX.y * e.y);
}
void fragment() {
	vec3 c = tint.rgb;
	float mode = custom.r;
	ROUGHNESS = custom.g > 0.0 ? custom.g : 0.85;
	if (mode > 0.5 && mode < 1.5) {
		// Профлист: трапеции с шагом 11,5 см.
		float ph = local.x / 0.115 * 6.2832;
		NORMAL_MAP = normalize(vec3(0.5 + 0.42 * sin(ph), 0.5, 1.0));
		c *= 0.9 + 0.1 * cos(ph);
	} else if (mode > 1.5 && mode < 2.5) {
		// Решётка: прутья 2,5 см с шагом 12 см, обвязка 4 см; вдали — сплошная тёмная (упрощённый облик).
		float px = fwidth(local.x);
		if (px < 0.03) {
			float bx = abs(fract(local.x / 0.12) - 0.5) * 0.12;
			float edge = min(extent.x * 0.5 - abs(local.x), extent.y * 0.5 - abs(local.y));
			if (bx > 0.0125 && edge > 0.04) {
				discard;
			}
		} else {
			c *= 0.45;
		}
		ROUGHNESS = 0.5;
	} else if (mode > 2.5) {
		METALLIC = 0.6;
		ROUGHNESS = 0.45;
	}
	ALBEDO = c;
	EMISSION = c * custom.b;
}
"""

static func detail() -> ShaderMaterial:
	if not _cache.has("detail"):
		var shader := Shader.new()
		shader.code = DETAIL_CODE
		var m := ShaderMaterial.new()
		m.shader = shader
		_cache["detail"] = m
	return _cache["detail"]

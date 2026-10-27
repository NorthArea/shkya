extends RefCounted
## Материалы зимнего города (ART-02): процедурные шейдеры и простые StandardMaterial3D. Без внешних текстур.

const FacadeShader = preload("res://game/world/shaders/facade.gdshader")
const RoadShader = preload("res://game/world/shaders/road.gdshader")
const SnowShader = preload("res://game/world/shaders/snow.gdshader")

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
		if low:
			# Старый кирпичный дом: теплее, этажи выше, окна уже.
			m.set_shader_parameter("wall_color", Color(0.55, 0.44, 0.38))
			m.set_shader_parameter("seam_color", Color(0.40, 0.32, 0.28))
			m.set_shader_parameter("floor_height", 3.3)
			m.set_shader_parameter("window_spacing", 2.6)
			m.set_shader_parameter("window_width", 1.1)
			m.set_shader_parameter("window_height", 1.8)
		_cache[key] = m
	return _cache[key]

static func road(along_x: bool, center: Vector2, width: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RoadShader
	m.set_shader_parameter("along_x", 1.0 if along_x else 0.0)
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("width", width)
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

static func glass() -> StandardMaterial3D:
	if not _cache.has("glass"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.85, 0.6, 0.12)
		m.roughness = 0.05
		_cache["glass"] = m
	return _cache["glass"]

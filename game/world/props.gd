extends Node3D
## PROPS-01: новые объекты арены (docs/workflow/tasks/ARENA-02.md, «План по зонам»; разрушаемые — C11). Ребёнок LevelGeometry.
## Объекты с коллизией (тип b) — коробки Layout.PROPS_SOLIDS в конце decor_solids(): коллизию и серую заглушку строит
## LevelGeometry._build_solid, здесь заглушка снимается и строится облик. Декор без коллизии (тип a), статичные части
## (оградка второй площадки), тропинки, гирлянды, пар вытяжки и свет — только здесь. Раскопка теплотрассы Z7
## целиком (яма, плиты, пар, ограждение) — Breakables (BREAK-01, запись Z7_dig).
## Вся геометрия своя (раздел 9 канона): коробки, цилиндры, сферы и торы, собранные в MultiMesh по слоям — у каждого
## объекта свой корень и свои пакеты: «body» с тенями, «low» без теней, «detail» без теней и дальше LOD_DISTANCE не
## рисуется (мелочь), «snow» — снег на горизонталях, «ice» — лёд, «glow»/«lit» — лампочки и световые короба (emission
## без источников света). Новых источников света — три (ларьки и коробка), лимит ARENA-02 «Свет».
## Разрушаемые объекты (Layout.PROPS_BREAKABLES) строит Breakables (BREAK-01), не этот узел.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const SteamShader = preload("res://game/world/shaders/steam_puff.gdshader")

const LOD_DISTANCE := 60.0
const WARM := Color(1.0, 0.75, 0.42)
const COLD := Color(0.80, 0.87, 1.0)
const FROST := Color(0.86, 0.87, 0.90)
const SNOW_WHITE := Color(1, 1, 1)
const PAPER := [Color(0.86, 0.85, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.72), Color(0.84, 0.78, 0.80)]
const BULBS := [Color(1.0, 0.25, 0.18), Color(1.0, 0.80, 0.25), Color(0.30, 0.90, 0.35), Color(0.30, 0.55, 1.0), Color(1.0, 0.62, 0.30)]

# Декор без коллизии: точки — здесь, рядом с обликом (как тропинки и вывески в level_geometry); коробки — в Layout.
const DOG_HOUSE := Vector3(38.6, 0.0, -88.0)          # Z16: будка дворняги CITY-01, входом на запад
const FEEDER_BIRCH := Vector2(-66, 98)                # Z2: кормушка на берёзе Layout.TREES[0]
const LAUNDRY_LINE := [Vector3(-66.0, 2.05, 98.0), Vector3(-70.0, 2.15, 102.0)]   # Z2: верёвка от берёзы к тополю
const BIKES := Vector3(14.0, 0.0, 107.35)             # Z5: велосипеды у Fence_Yard (z 107,85), под снегом
const PLAYGROUND2 := Rect2(-31.0, -59.0, 22.0, 20.0)  # Z15: вторая площадка — оградка из вкопанных покрышек
const PLAYGROUND2_GAPS := [[-46.5, -42.5], [-46.5, -42.5]]   # проходы 4 м в западной и восточной сторонах (по z)
const POPLAR_GARLAND := Vector2(90, 18)               # Z12: гирлянда на тополе у A∩B
# Тропинки (как level_geometry._build_trails): [от, до, ширина].
const TRAILS := [
	[Vector2(14, 101), Vector2(26, 106), 1.1], [Vector2(26, 106), Vector2(60, 107.6), 1.1],   # двор → южнее гаражей → коробка
	[Vector2(62, 108.2), Vector2(62, 105.6), 1.4],                                            # южный проход в коробку
	[Vector2(64, 107.6), Vector2(86, 108.2), 0.9], [Vector2(54.5, 107.8), Vector2(54.5, 119.2), 0.9],   # голубятня, ракушки
	[Vector2(35, 44.2), Vector2(36, 73.6), 1.2], [Vector2(36, 92.8), Vector2(28, 105.4), 1.0],   # A → горка, горка → двор
	[Vector2(-49, -25), Vector2(-31, -44.5), 1.1], [Vector2(-9, -44.5), Vector2(27.5, -38.5), 1.1],   # D → площадка → H7/H6
	[Vector2(27.5, -38.5), Vector2(27.5, -2), 1.2], [Vector2(60, 44.2), Vector2(60, 46.3), 1.4],     # проход H7/H6, окно шаурмы
]

# Слои пакетов: [материал, тени, LOD].
const LAYERS := {
	&"body": [&"colored", true, false], &"low": [&"colored", false, false], &"detail": [&"colored", false, true],
	&"snow": [&"snow", false, false], &"ice": [&"ice", false, false], &"glow": [&"glow", false, false],
	&"glowd": [&"glow", false, true], &"lit": [&"lit", false, false],
}
const GLOW_CODE := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform float energy = 3.0;
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * energy;
}
"""

var _meshes := {}
var _materials := {}
var _b := {}                 # пакет текущего объекта: слой → сетка → [преобразования, цвета]
var _root: Node3D
var _pigeons: Node3D

func _ready() -> void:
	name = "Props"
	_strip_placeholders()
	for spec in Layout.PROPS_SOLIDS:
		var xz: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		match spec[0]:
			"PropRinkBoard":
				pass   # все борта — одним объектом ниже
			"PropIceSlide":
				_ice_slide(xz, size)
			"PropDovecote":
				_dovecote(xz, size)
			"PropShells":
				_shells(xz, size)
			"PropShawarma":
				_shawarma(xz, size)
			"PropPress":
				_press(xz, size)
			"PropRowan":
				_rowan(xz, roundi(xz.x * 7.0 + xz.y * 3.0))
	_rink()
	_open_garage()
	_dog_house()
	_playground2()
	_kiosk_garland()
	_poplar_garland()
	_feeder_and_laundry()
	_bikes()
	_build_trails()
	_build_steam()

func _process(delta: float) -> void:
	if _pigeons:
		_pigeons.rotate_y(delta * 0.55)

## Серые коробки-заглушки, которые LevelGeometry._build_solid ставит неизвестному виду «props»: коллизия остаётся.
func _strip_placeholders() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child is StaticBody3D and String(child.name).begins_with("Prop"):
			for part in child.get_children():
				if part is MeshInstance3D:
					part.queue_free()

# --- пакеты MultiMesh ---

static func _rand(seed: int, k: int) -> float:
	return fposmod(sin(float(seed * 131 + k) * 12.9898) * 43758.5453, 1.0)

func _begin(node_name: String, at: Vector3, yaw := 0.0) -> Node3D:
	_root = Node3D.new()
	_root.name = node_name
	_root.position = at
	_root.rotation.y = yaw
	add_child(_root)
	_b = {}
	return _root

func _put(layer: StringName, mesh: StringName, xf: Transform3D, color: Color) -> void:
	if not _b.has(layer):
		_b[layer] = {}
	if not _b[layer].has(mesh):
		_b[layer][mesh] = [[], []]
	_b[layer][mesh][0].append(xf)
	_b[layer][mesh][1].append(color)

func _box(size: Vector3, at: Vector3, color: Color, layer := &"body", rot := Vector3.ZERO) -> void:
	_put(layer, &"box", Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), at), color)

func _cyl(radius: float, height: float, at: Vector3, color: Color, layer := &"body", rot := Vector3.ZERO, mesh := &"cyl") -> void:
	_put(layer, mesh, Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), at), color)

func _sph(size: Vector3, at: Vector3, color: Color, layer := &"detail", mesh := &"sph", rot := Vector3.ZERO) -> void:
	_put(layer, mesh, Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), at), color)

func _torus(radius: float, thick: float, at: Vector3, color: Color, layer := &"detail", rot := Vector3.ZERO) -> void:
	# Единичный тор: внешний радиус 0,5, сечение 0,08 — по толщине масштаб по y.
	_put(layer, &"torus", Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(radius * 2.0, thick / 0.08, radius * 2.0)), at), color)

## Цилиндр (или коробка, mesh = &"box") от a до b толщиной 2·radius.
func _seg(a: Vector3, b: Vector3, radius: float, color: Color, layer := &"body", mesh := &"cyl6") -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.05:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	_put(layer, mesh, Transform3D(Basis(x * radius * 2.0, y * length, z * radius * 2.0), (a + b) * 0.5), color)

## Плита от a до b (ширина — вдоль оси x корня, толщина — по нормали): скаты, крыши, жёлоб горки.
func _plank(a: Vector3, b: Vector3, width: float, thick: float, color: Color, layer := &"body") -> void:
	var d := b - a
	var length := d.length()
	var z := d / length
	var x := Vector3(z.z, 0.0, -z.x)
	x = x.normalized() if x.length() > 0.05 else Vector3.RIGHT
	var y := z.cross(x)
	_put(layer, &"box", Transform3D(Basis(x * width, y * thick, z * length), (a + b) * 0.5), color)

func _mesh(key: StringName) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	match key:
		&"box":
			mesh = BoxMesh.new()
		&"cyl", &"cyl6":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 12 if key == &"cyl" else 6
			c.rings = 1
			mesh = c
		&"sph", &"sph6":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 14 if key == &"sph" else 6
			s.rings = 7 if key == &"sph" else 3
			mesh = s
		&"torus":
			var t := TorusMesh.new()
			t.inner_radius = 0.42
			t.outer_radius = 0.5
			t.rings = 16
			t.ring_segments = 6
			mesh = t
	_meshes[key] = mesh
	return mesh

func _material(key: StringName) -> Material:
	if _materials.has(key):
		return _materials[key]
	var m: Material
	match key:
		&"colored":
			m = Materials.instance_colored()
		&"snow":
			m = Materials.snow(0.0)
		&"ice":
			var ice := StandardMaterial3D.new()
			ice.vertex_color_use_as_albedo = true
			ice.vertex_color_is_srgb = true
			ice.roughness = 0.1
			ice.metallic_specular = 0.9
			m = ice
		&"glow", &"lit":
			var shader := Shader.new()
			shader.code = GLOW_CODE
			var glow := ShaderMaterial.new()
			glow.shader = shader
			glow.set_shader_parameter("energy", 4.0 if key == &"glow" else 1.3)
			m = glow
	_materials[key] = m
	return m

## Собрать пакет текущего объекта в MultiMesh (по одному узлу на слой и сетку).
func _end(into: Node3D = null) -> void:
	var target := into if into else _root
	for layer in _b:
		var spec: Array = LAYERS[layer]
		for mesh_key in _b[layer]:
			var slot: Array = _b[layer][mesh_key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = _mesh(mesh_key)
			mm.instance_count = slot[0].size()
			for i in slot[0].size():
				mm.set_instance_transform(i, slot[0][i])
				mm.set_instance_color(i, slot[1][i])
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%s" % [layer, mesh_key]
			node.multimesh = mm
			node.material_override = _material(spec[0])
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec[1] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if spec[2]:
				node.visibility_range_end = LOD_DISTANCE
				node.visibility_range_end_margin = 4.0
			target.add_child(node)
	_b = {}

func _text(text: String, size: int, color: Color, at: Vector3, yaw: float, pixel := 0.005, glow := 0.0, lod := false) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = Color(pow(color.r, 1.6), pow(color.g, 1.6), pow(color.b, 1.6)) * glow if glow > 0.0 else color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.position = at
	label.rotation.y = yaw
	if lod:
		label.visibility_range_end = LOD_DISTANCE
	_root.add_child(label)
	return label

func _lamp(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 15.0
	light.position = at
	_root.add_child(light)

## Бумажки объявлений на грани (в координатах корня): n листков вдоль оси along от точки at, лицом по normal.
func _notices(at: Vector3, along: Vector3, normal: Vector3, n: int, seed: int) -> void:
	for i in n:
		var p := at + along * (i * 0.32) + Vector3(0, (_rand(seed, i) - 0.5) * 0.25, 0) + normal * 0.012
		var size := Vector3(0.21, 0.29, 0.21)
		var flat := Vector3(absf(along.x) * size.x + 0.01, size.y, absf(along.z) * size.z + 0.01)
		_box(flat, p, PAPER[(seed + i) % PAPER.size()], &"detail")

# --- Z6: хоккейная коробка ---

## Борта по коробкам Layout (видимые тоньше коллизии 0,3 м), лёд с разметкой, ворота, две мачты с прожекторами
## (один источник света — холодный пул над льдом), снег на кромке бортов, кучи счищенного снега за углами.
func _rink() -> void:
	var c: Vector2 = Layout.RINK[0]
	var size: Vector3 = Layout.RINK[1]
	_begin("HockeyRink", Vector3(c.x, 0, c.y))
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	for spec in Layout.PROPS_SOLIDS:
		if spec[0] != "PropRinkBoard":
			continue
		var bc: Vector2 = spec[2] - c
		var bs: Vector3 = spec[3]
		_board(bc, bs, int(absf(bc.x) * 3.0 + absf(bc.y) * 5.0))
	_box(Vector3(size.x - 0.6, 0.05, size.z - 0.6), Vector3(0, 0.025, 0), Color(0.74, 0.84, 0.92), &"ice")
	var red := Color(0.72, 0.12, 0.10)
	var blue := Color(0.14, 0.28, 0.68)
	_box(Vector3(0.3, 0.004, size.z - 0.7), Vector3(0, 0.052, 0), red, &"detail")
	for x in [-5.0, 5.0]:
		_box(Vector3(0.3, 0.004, size.z - 0.7), Vector3(x, 0.052, 0), blue, &"detail")
	for x in [-12.0, 12.0]:
		_box(Vector3(0.06, 0.004, size.z - 1.6), Vector3(x, 0.052, 0), red, &"detail")
		_cyl(0.3, 0.004, Vector3(x * 0.72, 0.053, -3.0), red, &"detail")
		_cyl(0.3, 0.004, Vector3(x * 0.72, 0.053, 3.0), red, &"detail")
	_torus(1.8, 0.01, Vector3(0, 0.054, 0), blue)
	_cyl(0.15, 0.004, Vector3(0, 0.055, 0), blue, &"detail")
	for side in [-1.0, 1.0]:
		_goal(Vector3(side * 12.6, 0.05, 0), side)
		_mast(Vector3(side * (hx - 0.15), 0, 0), side)
	# Счищенный снег у бортов изнутри и кучи за углами (низкие: коллизии нет).
	for k in 10:
		var along := -hx + 1.5 + (size.x - 3.0) * k / 9.0
		if absf(along) < 2.5:
			continue
		for zs in [-1.0, 1.0]:
			_sph(Vector3(1.6, 0.36, 0.7), Vector3(along, 0.0, zs * (hz - 0.55)), SNOW_WHITE, &"snow", &"sph")
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_sph(Vector3(2.4, 0.9, 1.8), Vector3(corner.x * (hx + 1.3), 0.0, corner.y * (hz + 1.0)), SNOW_WHITE, &"snow", &"sph")
	_notices(Vector3(-6.0, 0.75, hz + 0.08), Vector3.RIGHT, Vector3.BACK, 2, 5)
	_lamp(Vector3(0, 7.0, 0), COLD, 1.6, 17.0)
	_end()

## Борт: окрашенные щиты по 2 м, стойки, белый поручень и снег на кромке. bc/bs — центр и размер коллизии в корне.
func _board(bc: Vector2, bs: Vector3, seed: int) -> void:
	var long_x := bs.x > bs.z
	var length := bs.x if long_x else bs.z
	var n := maxi(1, ceili(length / 2.0))
	var step := length / n
	var greens := [Color(0.16, 0.38, 0.26), Color(0.14, 0.34, 0.24), Color(0.18, 0.40, 0.28)]
	for i in n:
		var u := -length * 0.5 + step * (i + 0.5)
		var at := Vector3(bc.x + (u if long_x else 0.0), 0.58, bc.y + (0.0 if long_x else u))
		var panel := Vector3(step - 0.04, 1.06, 0.1) if long_x else Vector3(0.1, 1.06, step - 0.04)
		_box(panel, at, greens[(seed + i) % greens.size()])
		var post_at := Vector3(bc.x + (u - step * 0.5 if long_x else 0.0), 0.62, bc.y + (0.0 if long_x else u - step * 0.5))
		_box(Vector3(0.12, 1.24, 0.14), post_at, Color(0.10, 0.18, 0.13))
	var end_at := Vector3(bc.x + (length * 0.5 if long_x else 0.0), 0.62, bc.y + (0.0 if long_x else length * 0.5))
	_box(Vector3(0.12, 1.24, 0.14), end_at, Color(0.10, 0.18, 0.13))
	var rail := Vector3(length, 0.08, 0.18) if long_x else Vector3(0.18, 0.08, length)
	_box(rail, Vector3(bc.x, 1.15, bc.y), Color(0.86, 0.87, 0.85))
	_box(Vector3(rail.x, 0.05, rail.z) * Vector3(1, 1, 1), Vector3(bc.x, 1.215, bc.y), SNOW_WHITE, &"snow")
	var kick := Vector3(length, 0.14, 0.12) if long_x else Vector3(0.12, 0.14, length)
	_box(kick, Vector3(bc.x, 0.12, bc.y), Color(0.85, 0.72, 0.18), &"low")   # жёлтая полоса внизу

## Ворота: красная рама 1,83 × 1,22, сетка из белых нитей; side — к какому борту, рот ворот — к центру.
func _goal(at: Vector3, side: float) -> void:
	var red := Color(0.78, 0.10, 0.08)
	var net := Color(0.88, 0.88, 0.86)
	var w := 0.915
	for z in [-w, w]:
		_cyl(0.03, 1.22, at + Vector3(0, 0.61, z), red, &"body", Vector3.ZERO, &"cyl6")
		_seg(at + Vector3(0, 1.22, z), at + Vector3(side * 0.6, 0.0, z), 0.02, red, &"detail")
		_seg(at + Vector3(0, 0.02, z), at + Vector3(side * 0.9, 0.02, z), 0.02, red, &"detail")
	_seg(at + Vector3(0, 1.22, -w), at + Vector3(0, 1.22, w), 0.03, red, &"body")
	_seg(at + Vector3(side * 0.9, 0.02, -w), at + Vector3(side * 0.9, 0.02, w), 0.02, red, &"detail")
	for k in 7:
		var z := -w + 2.0 * w * k / 6.0
		_seg(at + Vector3(0, 1.22, z), at + Vector3(side * 0.85, 0.03, z), 0.006, net, &"detail")
	for k in 4:
		var t := (k + 1) / 5.0
		var p := Vector3(side * 0.85 * t, 1.22 * (1.0 - t), 0)
		_seg(at + p + Vector3(0, 0, -w), at + p + Vector3(0, 0, w), 0.006, net, &"detail")

## Мачта прожекторов в линии короткого борта (внутри его коллизии): столб 8 м, перекладина, две фары к центру.
func _mast(at: Vector3, side: float) -> void:
	var metal := Color(0.20, 0.21, 0.22)
	_cyl(0.11, 8.0, at + Vector3(0, 4.0, 0), metal, &"body", Vector3.ZERO, &"cyl6")
	_box(Vector3(0.12, 0.1, 1.6), at + Vector3(-side * 0.25, 7.8, 0), metal)
	for z in [-0.6, 0.6]:
		var head := at + Vector3(-side * 0.45, 7.65, z)
		_box(Vector3(0.3, 0.42, 0.55), head, Color(0.16, 0.16, 0.17), &"body", Vector3(0, 0, side * 0.5))
		_box(Vector3(0.04, 0.34, 0.46), head + Vector3(-side * 0.16, -0.08, 0), COLD, &"glow", Vector3(0, 0, side * 0.5))

# --- Z6: ледяная горка ---

## Деревянная горка: площадка на четырёх столбах с перилами, лесенка с юга, ледяной жёлоб на снежной насыпи к северу
## и раскат по снегу (без коллизии). Корень — стык площадки и ската (z 88), скат к −z.
func _ice_slide(xz: Vector2, size: Vector3) -> void:
	var top_z := xz.y - size.z * 0.5   # северный край площадки — z 88
	_begin("IceSlide", Vector3(xz.x, 0, top_z))
	var blue := Color(0.28, 0.48, 0.80)
	var red := Color(0.82, 0.20, 0.12)
	var wood := Color(0.56, 0.40, 0.24)
	var h := 2.3
	for x in [-0.85, 0.85]:
		for z in [0.12, 1.45]:
			_box(Vector3(0.14, h + 0.95, 0.14), Vector3(x, (h + 0.95) * 0.5, z), blue)
		_box(Vector3(0.08, 0.08, 1.45), Vector3(x, h + 0.9, 0.78), red)   # перила по бокам площадки
		_box(Vector3(0.08, 0.08, 1.45), Vector3(x, h + 0.5, 0.78), red)
	_box(Vector3(1.85, 0.1, 1.5), Vector3(0, h, 0.78), wood)
	_box(Vector3(1.85, 0.06, 1.5), Vector3(0, h + 0.08, 0.78), SNOW_WHITE, &"snow")
	_box(Vector3(1.8, 0.8, 0.06), Vector3(0, h + 0.4, 1.5), red, &"low")   # бортик за спиной у входа на площадку
	# Лесенка с юга: 10 ступеней с тетивами и поручнями.
	var steps := 10
	for i in steps:
		var t := (i + 0.5) / steps
		_box(Vector3(0.95, 0.06, 0.3), Vector3(0, h * (1.0 - t), 1.5 + 2.85 * t), wood, &"low")
		_box(Vector3(0.9, 0.04, 0.26), Vector3(0, h * (1.0 - t) + 0.05, 1.5 + 2.85 * t), SNOW_WHITE, &"snow")
	for x in [-0.52, 0.52]:
		_seg(Vector3(x, h, 1.5), Vector3(x, 0.0, 4.4), 0.05, blue, &"body", &"box")
		_seg(Vector3(x, h + 0.9, 1.5), Vector3(x, 0.9, 4.4), 0.03, red, &"low", &"box")
		_box(Vector3(0.06, 0.9, 0.06), Vector3(x, 0.45, 4.35), blue, &"low")
	# Скат: жёлоб с бортиками от площадки до раската на снежной насыпи.
	var top := Vector3(0, h + 0.05, 0.0)
	var foot := Vector3(0, 0.06, -7.2)
	_plank(top, foot, 0.95, 0.08, Color(0.80, 0.88, 0.94), &"ice")
	for x in [-0.52, 0.52]:
		_plank(top + Vector3(x, 0.14, 0), foot + Vector3(x, 0.14, 0), 0.06, 0.26, red)
	# Снежная насыпь под скатом: клин из двух скатов-плит и боковых валов (внутри коллизии ската и площадки).
	# Две толстые наклонные плиты снега одна под другой: сбоку — сплошная насыпь до земли, низ уходит под землю.
	_plank(Vector3(0, h - 0.7, 0.2), Vector3(0, -0.66, -7.3), 2.2, 1.3, SNOW_WHITE, &"snow")
	_plank(Vector3(0, h - 1.7, 0.4), Vector3(0, -1.66, -7.1), 2.35, 1.4, SNOW_WHITE, &"snow")
	_sph(Vector3(2.4, 1.8, 2.2), Vector3(0, 0, 0.5), SNOW_WHITE, &"snow", &"sph")   # насыпь под площадкой
	_box(Vector3(1.1, 0.03, 10.0), Vector3(0, 0.015, -12.0), Color(0.76, 0.85, 0.92), &"ice")   # раскат
	for x in [-0.85, 0.85]:   # валики вдоль раската
		_sph(Vector3(0.6, 0.3, 9.5), Vector3(x, 0.0, -12.0), SNOW_WHITE, &"snow", &"sph")
	_end()

# --- Z6: голубятня ---

## Будка на сваях с двускатной крышей, выгул из сетки спереди, лесенка; голуби на коньке и в небе над пустырем.
func _dovecote(xz: Vector2, size: Vector3) -> void:
	_begin("Dovecote", Vector3(xz.x, 0, xz.y))
	var paint := Color(0.36, 0.56, 0.62)
	var trim := Color(0.88, 0.88, 0.84)
	var pole := Color(0.30, 0.24, 0.18)
	var base := 2.2
	for x in [-1.2, 1.2]:
		for z in [-0.8, 1.2]:
			_cyl(0.08, base, Vector3(x, base * 0.5, z), pole, &"body", Vector3.ZERO, &"cyl6")
	_box(Vector3(2.8, 0.12, 2.3), Vector3(0, base, 0.2), pole)
	_box(Vector3(2.7, 1.7, 2.2), Vector3(0, base + 0.9, 0.2), paint)
	for k in 9:   # швы досок
		_box(Vector3(0.02, 1.68, 0.02), Vector3(-1.2 + k * 0.3, base + 0.9, -0.91), trim * 0.8, &"detail")
	_box(Vector3(0.6, 0.9, 0.04), Vector3(0.6, base + 0.75, -0.92), Color(0.18, 0.20, 0.22))   # дверца
	_box(Vector3(2.9, 0.08, 0.08), Vector3(0, base + 1.75, -0.92), trim)
	# Двускатная крыша (конёк вдоль x) и снег на скатах.
	var ridge := base + 2.45
	for zs in [-1.0, 1.0]:
		var eave := Vector3(0, base + 1.75, 0.2 + zs * 1.3)
		var top := Vector3(0, ridge, 0.2)
		_plank(top, eave, 3.0, 0.08, Color(0.25, 0.25, 0.27))
		_plank(top + Vector3(0, 0.08, 0), eave + Vector3(0, 0.08, 0), 2.9, 0.08, SNOW_WHITE, &"snow")
	# Выгул из сетки перед дверцей (z −1,5…−0,9) и лесенка к нему.
	var cage := Vector3(0, base + 0.6, -1.2)
	for x in [-1.3, -0.4, 0.4, 1.3]:
		_box(Vector3(0.04, 1.2, 0.04), cage + Vector3(x, 0, -0.28), trim, &"low")
	for y in [-0.6, -0.2, 0.2, 0.6]:
		_box(Vector3(2.6, 0.02, 0.02), cage + Vector3(0, y, -0.28), trim, &"detail")
	_box(Vector3(2.6, 0.04, 0.6), cage + Vector3(0, 0.6, 0), trim, &"low")
	_box(Vector3(2.6, 0.04, 0.6), cage + Vector3(0, 0.64, 0), SNOW_WHITE, &"snow")
	for x in [-0.25, 0.25]:
		_seg(Vector3(x, 0, -1.45), Vector3(x, base, -0.95), 0.03, pole, &"low", &"box")
	for k in 7:
		var t := (k + 0.5) / 7.0
		_box(Vector3(0.5, 0.03, 0.04), Vector3(0, base * t, -1.45 + 0.5 * t), pole, &"detail")
	_notices(Vector3(-1.1, 1.3, -0.82), Vector3.RIGHT, Vector3.FORWARD, 2, 9)
	var grey := Color(0.48, 0.50, 0.55)
	for k in 4:   # голуби на коньке
		_sph(Vector3(0.18, 0.16, 0.26), Vector3(-1.0 + k * 0.6, ridge + 0.14, 0.2), grey, &"detail", &"sph6")
		_sph(Vector3(0.09, 0.09, 0.09), Vector3(-1.0 + k * 0.6, ridge + 0.25, 0.08), grey * 0.8, &"detail", &"sph6")
	_end()
	# Стая над голубятней: кружит (вращение корня в _process).
	_pigeons = Node3D.new()
	_pigeons.name = "Pigeons"
	_pigeons.position = Vector3(0, 7.0, 0)
	_root.add_child(_pigeons)
	for k in 7:
		var a := TAU * k / 7.0
		var r := 6.0 + 2.0 * _rand(17, k)
		var p := Vector3(cos(a) * r, (_rand(19, k) - 0.5) * 2.0, sin(a) * r)
		var yaw := -a   # клювом по касательной к кругу
		_sph(Vector3(0.18, 0.14, 0.32), p, grey, &"low", &"sph6", Vector3(0, yaw, 0))
		_box(Vector3(0.7, 0.02, 0.16), p + Vector3(0, 0.04, 0), grey * 1.1, &"low", Vector3(0.0, yaw, 0.25 * (1.0 if k % 2 == 0 else -1.0)))
	_end(_pigeons)

# --- Z6: «ракушки» ---

## Три железных гаража-«ракушки» носом на север: короб сзади, округлый «капот»-крышка спереди (цилиндр, нижняя
## половина — под землёй), замок и номер, снег на крыше и намётанный у носа.
func _shells(xz: Vector2, size: Vector3) -> void:
	_begin("Shells", Vector3(xz.x, 0, xz.y))
	var colors := [Color(0.40, 0.58, 0.40), Color(0.58, 0.64, 0.70), Color(0.70, 0.40, 0.20)]
	var n := 3
	var w := size.x / n
	var hz := size.z * 0.5
	var r := 2.05
	for i in n:
		var x := -size.x * 0.5 + w * (i + 0.5)
		var color: Color = colors[i]
		_box(Vector3(w - 0.12, r, hz + 0.4), Vector3(x, r * 0.5, (hz - 0.4) * 0.5 + 0.2), color)
		_cyl(r, w - 0.12, Vector3(x, 0, -0.4), color, &"body", Vector3(0, 0, PI * 0.5))
		_box(Vector3(w - 0.3, 0.06, 0.04), Vector3(x, 0.35, -0.4 - r + 0.02), color * 0.7, &"low")   # нижняя кромка крышки
		_box(Vector3(0.12, 0.16, 0.06), Vector3(x, 0.22, -0.4 - r - 0.02), Color(0.10, 0.10, 0.11), &"detail")   # замок
		for k in 3:   # потёки ржавчины
			_box(Vector3(0.08, 0.6 + 0.4 * _rand(i, k), 0.02), Vector3(x - 0.8 + k * 0.7, 1.6, hz - 0.01 + 0.02), Color(0.45, 0.22, 0.10), &"detail")
		var label := _text(str(11 + i * 4), 80, Color(0.95, 0.95, 0.90), Vector3(x, 1.05, -0.4 - r * 0.86 - 0.03), PI, 0.005, 0.0, true)
		label.rotation = Vector3(-0.52, PI, 0)   # по скату носа (нормаль ~30° над горизонтом)
		_box(Vector3(w - 0.1, 0.12, hz + 0.4), Vector3(x, r + 0.06, (hz - 0.4) * 0.5 + 0.2), SNOW_WHITE, &"snow")
		_sph(Vector3(w - 0.4, 0.36, 1.8), Vector3(x, r - 0.05, -0.75), SNOW_WHITE, &"snow", &"sph")
		_sph(Vector3(w + 0.1, 0.5, 1.0), Vector3(x, 0.0, -0.4 - r + 0.05), SNOW_WHITE, &"snow", &"sph")
	_end()

# --- Z8: ларёк «ШАУРМА» ---

## Ларёк окном на север (к тротуару A): стены вокруг ниши окна, внутри — тёплый свет и вертел, прилавок, меню,
## световой короб с вывеской, вытяжка с паром; лампа над окном — один из трёх новых источников света.
func _shawarma(xz: Vector2, size: Vector3) -> void:
	_begin("Shawarma", Vector3(xz.x, 0, xz.y))
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var wall := Color(0.88, 0.86, 0.80)
	var stripe := Color(0.70, 0.14, 0.08)
	var h := 2.35
	var win := Rect2(-1.0, 0.95, 1.6, 0.95)   # x, y, ширина, высота окна на северной грани
	_box(Vector3(size.x - 0.1, h, size.z - 0.6), Vector3(0, h * 0.5, 0.3), wall)   # задняя часть
	_box(Vector3(size.x - 0.1, win.position.y, 0.5), Vector3(0, win.position.y * 0.5, -hz + 0.3), wall)
	_box(Vector3(size.x - 0.1, h - win.end.y, 0.5), Vector3(0, (h + win.end.y) * 0.5, -hz + 0.3), wall)
	_box(Vector3(win.position.x + hx - 0.05, win.size.y, 0.5), Vector3((-hx + 0.05 + win.position.x) * 0.5, win.position.y + win.size.y * 0.5, -hz + 0.3), wall)
	_box(Vector3(hx - 0.05 - win.end.x, win.size.y, 0.5), Vector3((hx - 0.05 + win.end.x) * 0.5, win.position.y + win.size.y * 0.5, -hz + 0.3), wall)
	_box(Vector3(win.size.x, win.size.y, 0.02), Vector3(win.position.x + win.size.x * 0.5, win.position.y + win.size.y * 0.5, -hz + 0.56), WARM, &"lit")
	_cyl(0.13, 0.55, Vector3(win.position.x + 0.4, win.position.y + 0.42, -hz + 0.45), Color(0.55, 0.30, 0.12), &"detail")   # вертел
	_box(Vector3(0.03, 0.75, 0.03), Vector3(win.position.x + 0.4, win.position.y + 0.42, -hz + 0.45), Color(0.6, 0.6, 0.62), &"detail")
	_box(Vector3(win.size.x + 0.3, 0.05, 0.4), Vector3(win.position.x + win.size.x * 0.5, win.position.y, -hz - 0.05), Color(0.62, 0.62, 0.64), &"low")   # прилавок
	_box(Vector3(size.x - 0.06, 0.32, size.z - 0.06), Vector3(0, 0.16, 0), stripe, &"low")
	_box(Vector3(size.x + 0.3, 0.1, size.z + 0.3), Vector3(0, h + 0.05, 0), Color(0.30, 0.30, 0.32))
	_box(Vector3(size.x + 0.2, 0.1, size.z + 0.2), Vector3(0, h + 0.15, 0.1), SNOW_WHITE, &"snow")
	# Меню — картинки еды справа от окна.
	var food := [Color(0.85, 0.62, 0.30), Color(0.70, 0.45, 0.20), Color(0.92, 0.80, 0.45), Color(0.80, 0.30, 0.18)]
	for k in 4:
		_box(Vector3(0.26, 0.2, 0.01), Vector3(win.end.x + 0.25 + (k % 2) * 0.3, 1.25 + (k / 2) * 0.26, -hz - 0.005), food[k], &"detail")
	# Световой короб с вывеской на крыше, вдоль северной кромки.
	_box(Vector3(size.x - 0.2, 0.5, 0.18), Vector3(0, h + 0.45, -hz + 0.2), Color(0.95, 0.78, 0.25), &"lit")
	_text("ШАУРМА", 96, Color(0.62, 0.06, 0.03), Vector3(0, h + 0.45, -hz + 0.1), PI, 0.0048)
	_cyl(0.07, 0.8, Vector3(hx - 0.4, h + 0.5, 0.6), Color(0.55, 0.56, 0.58), &"body", Vector3.ZERO, &"cyl6")   # вытяжка
	_box(Vector3(0.9, 0.12, 0.5), Vector3(win.position.x + 0.8, 0.06, -hz - 0.45), Color(0.40, 0.30, 0.20), &"low")   # поддон-ступенька
	_notices(Vector3(hx + 0.012, 1.3, -0.6), Vector3.BACK, Vector3.RIGHT, 3, 3)
	_lamp(Vector3(win.position.x + win.size.x * 0.5, 2.2, -hz - 0.9), WARM, 1.3, 5.5)
	_end()
	_steam_points.append([Vector3(xz.x + hx - 0.4, h + 0.9, xz.y + 0.6), true])

# --- Z11: киоск «ПРЕССА» ---

## Киоск печати у торца H5_East окном на юг (к тротуару A): витрина с журналами в нише, окошко, световой короб
## «ПРЕССА», синий почтовый ящик без надписей на восточной стене, объявления; лампа над витриной — второй источник.
func _press(xz: Vector2, size: Vector3) -> void:
	_begin("PressKiosk", Vector3(xz.x, 0, xz.y), PI)   # перед корня (−z) — на юг
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var body := Color(0.70, 0.78, 0.84)
	var trim := Color(0.16, 0.30, 0.55)
	var h := 2.35
	var win := Rect2(-1.3, 0.85, 2.6, 1.2)
	_box(Vector3(size.x - 0.1, h, size.z - 0.5), Vector3(0, h * 0.5, 0.25), body)
	_box(Vector3(size.x - 0.1, win.position.y, 0.4), Vector3(0, win.position.y * 0.5, -hz + 0.25), body)
	_box(Vector3(size.x - 0.1, h - win.end.y, 0.4), Vector3(0, (h + win.end.y) * 0.5, -hz + 0.25), body)
	for x in [-hx + 0.1, hx - 0.1]:
		_box(Vector3(0.1, win.size.y, 0.4), Vector3(x, win.position.y + win.size.y * 0.5, -hz + 0.25), trim)
	_box(Vector3(win.size.x, win.size.y, 0.02), Vector3(0, win.position.y + win.size.y * 0.5, -hz + 0.46), Color(0.95, 0.92, 0.80), &"lit")
	var covers := [Color(0.85, 0.20, 0.20), Color(0.20, 0.45, 0.80), Color(0.95, 0.80, 0.25), Color(0.30, 0.65, 0.35),
		Color(0.90, 0.55, 0.70), Color(0.95, 0.95, 0.92), Color(0.55, 0.30, 0.70)]
	for row in 3:
		for col in 8:
			var k := row * 8 + col
			if col == 5 and row == 0:
				continue   # окошко продавца
			_box(Vector3(0.24, 0.32, 0.02), Vector3(-1.12 + col * 0.32, win.position.y + 0.2 + row * 0.38, -hz + 0.43), covers[(k * 3 + row) % covers.size()], &"detail")
	for k in 3:
		_box(Vector3(win.size.x, 0.03, 0.12), Vector3(0, win.position.y + 0.02 + k * 0.38, -hz + 0.38), Color(0.5, 0.5, 0.52), &"detail")
	_box(Vector3(0.4, 0.4, 0.03), Vector3(-1.12 + 5 * 0.32, win.position.y + 0.25, -hz + 0.05), Color(0.30, 0.28, 0.24), &"low")   # окошко
	_box(Vector3(size.x - 0.06, 0.25, size.z - 0.06), Vector3(0, 0.125, 0), trim, &"low")
	_box(Vector3(size.x + 0.4, 0.1, size.z + 0.4), Vector3(0, h + 0.05, -0.1), Color(0.86, 0.87, 0.88))
	_box(Vector3(size.x + 0.3, 0.12, size.z + 0.3), Vector3(0, h + 0.16, -0.05), SNOW_WHITE, &"snow")
	_box(Vector3(size.x - 0.3, 0.45, 0.16), Vector3(0, h + 0.45, -hz + 0.1), trim, &"lit")
	_text("ПРЕССА", 96, Color(0.98, 0.98, 0.95), Vector3(0, h + 0.45, -hz + 0.01), PI, 0.0048, 1.6)
	# Почтовый ящик — на стене к востоку (в корне повёрнутом на π это −x).
	var box_at := Vector3(-hx - 0.13, 1.35, 0.2)
	_box(Vector3(0.24, 0.5, 0.4), box_at, Color(0.10, 0.28, 0.62))
	_box(Vector3(0.26, 0.08, 0.42), box_at + Vector3(0, 0.27, 0), Color(0.08, 0.22, 0.50), &"low")
	_box(Vector3(0.02, 0.04, 0.22), box_at + Vector3(-0.125, 0.12, 0), Color(0.05, 0.05, 0.06), &"detail")
	_box(Vector3(0.24, 0.05, 0.4), box_at + Vector3(0, 0.33, 0), SNOW_WHITE, &"snow")
	_notices(Vector3(hx + 0.012, 1.2, -0.7), Vector3.BACK, Vector3.RIGHT, 3, 7)
	_lamp(Vector3(0, 2.25, -hz - 0.8), Color(1.0, 0.88, 0.70), 1.1, 5.0)
	_end()

# --- Z8, Z5: рябины ---

## Рябина: тонкий ствол, развилка на 1,6–1,9 м, раскидистые ветви с куржаком, гроздья ягод на концах веток (мелочь,
## LOD), снег на развилках и пара снегирей. Коллизия — ствол Layout.PROPS_SOLIDS.
func _rowan(xz: Vector2, seed: int) -> void:
	_begin("Rowan_%d_%d" % [roundi(xz.x), roundi(xz.y)], Vector3(xz.x, 0, xz.y))
	var bark := Color(0.32, 0.29, 0.26)
	var berry := Color(0.86, 0.22, 0.08)
	var berry2 := Color(0.72, 0.14, 0.06)
	var fork := 1.8 + 0.4 * _rand(seed, 0)
	_seg(Vector3.ZERO, Vector3(0, fork + 0.3, 0), 0.13, bark, &"body")
	var limbs := 5 + int(_rand(seed, 1) * 2.0)
	var perches: Array[Vector3] = []
	for i in limbs:
		var yaw := TAU * (i + _rand(seed, 10 + i) * 0.5) / limbs
		var tilt := deg_to_rad(24.0 + 22.0 * _rand(seed, 20 + i))
		var dir := Vector3(sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw))
		var start := Vector3(0, fork - 0.25 * _rand(seed, 30 + i), 0)
		var end := start + dir * (3.0 + 1.4 * _rand(seed, 40 + i))
		_seg(start, end, 0.065, bark, &"low")
		_sph(Vector3(0.22, 0.1, 0.22), start + Vector3(dir.x, 0, dir.z) * 0.1 + Vector3(0, 0.04, 0), SNOW_WHITE, &"snow", &"sph6")
		perches.append(start.lerp(end, 0.55))
		for j in 5:
			var t := 0.3 + 0.7 * j / 5.0
			var from := start.lerp(end, t)
			var byaw := yaw + (_rand(seed, 100 + i * 10 + j) - 0.5) * 2.2
			var btilt := deg_to_rad(30.0 + 40.0 * _rand(seed, 200 + i * 10 + j))
			var bdir := Vector3(sin(btilt) * cos(byaw), cos(btilt), sin(btilt) * sin(byaw))
			var bend := from + bdir * (0.6 + 0.7 * _rand(seed, 300 + i * 10 + j))
			_seg(from, bend, 0.022, bark, &"low")
			_seg(from.lerp(bend, 0.3), bend, 0.04, FROST, &"low")   # куржак
			if _rand(seed, 400 + i * 10 + j) < 0.8:
				var c := bend + Vector3(0, -0.1, 0)
				_sph(Vector3(0.26, 0.2, 0.26), c, berry, &"detail", &"sph6")
				_sph(Vector3(0.18, 0.15, 0.18), c + Vector3(0.1, -0.08, 0.06), berry2, &"detail", &"sph6")
				_sph(Vector3(0.16, 0.13, 0.16), c + Vector3(-0.09, -0.05, -0.07), berry, &"detail", &"sph6")
				_sph(Vector3(0.14, 0.04, 0.14), c + Vector3(0, 0.1, 0), SNOW_WHITE, &"snow", &"sph6")
	for k in 2:   # снегири: красная грудка, серая спина, чёрная шапочка
		var p: Vector3 = perches[(k * 2 + seed) % perches.size()] + Vector3(0, 0.1, 0)
		_sph(Vector3(0.14, 0.13, 0.17), p, Color(0.88, 0.30, 0.16), &"detail", &"sph6")
		_sph(Vector3(0.12, 0.1, 0.14), p + Vector3(0, 0.035, 0.03), Color(0.36, 0.38, 0.42), &"detail", &"sph6")
		_sph(Vector3(0.08, 0.08, 0.08), p + Vector3(0, 0.08, -0.06), Color(0.05, 0.05, 0.06), &"detail", &"sph6")
	_end()

# --- Z5: открытый гараж ---

## Ворота одного бокса дворовых гаражей (Garages_Yard, ворота на запад, к двору) распахнуты: тёмный проём с лампочкой,
## створки отведены к стене, у порога хлам — покрышки, ящики, канистра, лопата. Бокс — ближайший к «Жигулям» (17; 80).
func _open_garage() -> void:
	var row: Array = []
	for spec in Layout.SOLIDS:
		if spec[0] == "Garages_Yard":
			row = spec
	if row.is_empty():
		return
	var c: Vector2 = row[2]
	var size: Vector3 = row[3]
	var count := maxi(1, roundi(size.z / 3.6))   # как level_geometry._garage_row
	var unit := size.z / count
	var best := 0
	for i in count:
		if absf(c.y - size.z * 0.5 + unit * (i + 0.5) - 80.5) < absf(c.y - size.z * 0.5 + unit * (best + 0.5) - 80.5):
			best = i
	var z := c.y - size.z * 0.5 + unit * (best + 0.5)
	_begin("OpenGarage", Vector3(c.x - size.x * 0.5, 0, z), PI * 0.5)   # перед корня (−z) — на запад
	var dark := Color(0.05, 0.045, 0.04)
	var leaf_w := unit * 0.39
	_box(Vector3(leaf_w * 2.0 + 0.12, 2.2, 0.02), Vector3(0, 1.12, -0.075), dark)
	_box(Vector3(0.05, 0.3, 0.05), Vector3(0, 2.05, -0.1), Color(0.2, 0.2, 0.2), &"detail")
	_sph(Vector3(0.1, 0.12, 0.1), Vector3(0, 1.87, -0.1), WARM, &"glow", &"sph6")
	_box(Vector3(leaf_w * 2.0, 2.1, 0.01), Vector3(0, 1.1, -0.09), Color(0.13, 0.09, 0.05), &"lit")   # отсвет лампочки внутри
	var leaf := Color(0.18, 0.32, 0.58)
	for side in [-1.0, 1.0]:
		var hinge := Vector3(side * (leaf_w + 0.04), 1.14, -0.06)
		var yaw := deg_to_rad(20.0) if side > 0.0 else deg_to_rad(160.0)
		var dir := Vector3(cos(yaw), 0, -sin(yaw))
		_box(Vector3(leaf_w, 2.16, 0.05), hinge + dir * leaf_w * 0.5, leaf, &"body", Vector3(0, yaw, 0))
	for k in 3:
		_torus(0.32, 0.18, Vector3(-0.75, 0.1 + k * 0.19, -0.55), Color(0.08, 0.08, 0.09), &"detail")
	_box(Vector3(0.5, 0.4, 0.4), Vector3(0.5, 0.2, -0.45), Color(0.45, 0.33, 0.20), &"detail")
	_box(Vector3(0.4, 0.3, 0.35), Vector3(0.55, 0.55, -0.42), Color(0.55, 0.42, 0.26), &"detail", Vector3(0, 0.3, 0))
	_box(Vector3(0.2, 0.32, 0.12), Vector3(0.05, 0.16, -0.35), Color(0.70, 0.12, 0.08), &"detail")   # канистра
	_seg(Vector3(1.05, 0.0, -0.2), Vector3(1.1, 1.3, -0.05), 0.02, Color(0.40, 0.30, 0.18), &"detail")   # черенок лопаты
	_box(Vector3(0.25, 0.32, 0.03), Vector3(1.05, 0.12, -0.22), Color(0.30, 0.32, 0.34), &"detail", Vector3(0.1, 0, 0))
	_end()

# --- Z16: собачья будка ---

func _dog_house() -> void:
	_begin("DogHouse", DOG_HOUSE, PI * 0.5)   # входом на запад
	var wood := Color(0.66, 0.46, 0.26)
	_box(Vector3(1.0, 0.75, 1.15), Vector3(0, 0.375, 0), wood, &"low")
	_box(Vector3(0.02, 0.4, 1.15), Vector3(0, 0.95, 0), wood, &"low")   # фронтоны под коньком
	for xs in [-1.0, 1.0]:
		_plank(Vector3(0, 1.17, 0), Vector3(xs * 0.64, 0.7, 0), 1.3, 0.06, Color(0.42, 0.30, 0.20), &"low")
		_plank(Vector3(0, 1.22, 0), Vector3(xs * 0.6, 0.77, 0), 1.24, 0.06, SNOW_WHITE, &"snow")
	_cyl(0.24, 0.02, Vector3(0, 0.32, -0.585), Color(0.04, 0.04, 0.04), &"low", Vector3(PI * 0.5, 0, 0))   # лаз
	_box(Vector3(0.48, 0.5, 0.02), Vector3(0, 0.25, -0.585), Color(0.04, 0.04, 0.04), &"low")
	_cyl(0.13, 0.07, Vector3(0.45, 0.035, -0.8), Color(0.55, 0.56, 0.58), &"detail", Vector3.ZERO, &"cyl6")   # миска
	_text("ШАРИК", 40, Color(0.92, 0.90, 0.80), Vector3(0, 0.66, -0.59), PI, 0.004, 0.0, true)
	_end()

# --- Z15: вторая детская площадка, статичная часть ---

## Оградка из вкопанных наполовину крашеных покрышек по краю площадки с проходами 4 м с запада и востока
## и натоптанный снег внутри. Качели, карусель, горка, песочница, домик и лавки — Breakables (Layout.PROPS_BREAKABLES).
func _playground2() -> void:
	var r := PLAYGROUND2
	_begin("Playground2", Vector3(r.get_center().x, 0, r.get_center().y))
	var center := r.get_center()
	var paint := [Color(0.92, 0.75, 0.15), Color(0.80, 0.18, 0.12), Color(0.18, 0.40, 0.75), Color(0.25, 0.60, 0.25), Color(0.92, 0.92, 0.90)]
	var k := 0
	for edge in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.position.x, r.end.y), r.end],
			[r.position, Vector2(r.position.x, r.end.y)], [Vector2(r.end.x, r.position.y), r.end]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var n := int(a.distance_to(b) / 0.8)
		var along_x := absf(b.x - a.x) > absf(b.y - a.y)
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			if not along_x and p.y > PLAYGROUND2_GAPS[0][0] and p.y < PLAYGROUND2_GAPS[0][1]:
				continue
			var local := Vector3(p.x - center.x, 0.0, p.y - center.y)
			var rot := Vector3(PI * 0.5, 0, 0) if along_x else Vector3(PI * 0.5, PI * 0.5, 0)
			_torus(0.34, 0.16, local, paint[k % paint.size()], &"detail", rot)
			_sph(Vector3(0.22, 0.08, 0.16), local + Vector3(0, 0.33, 0), SNOW_WHITE, &"snow", &"sph6")
			k += 1
	var trodden := PlaneMesh.new()
	trodden.size = r.size - Vector2(1.0, 1.0)
	var mesh := MeshInstance3D.new()
	mesh.name = "Trodden"
	mesh.mesh = trodden
	mesh.material_override = Materials.snow(0.6)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(0, 0.012, 0)
	_root.add_child(mesh)
	_end()

# --- Z14, Z12: гирлянды (без коллизии, только emission) ---

## Гирлянда по кромке козырька киоска «ХЛЕБ» — с провисом между крючками, разноцветные лампочки. На площадке
## киоска — только она: новых объёмов там нет (ARENA-02, «Что не делать», 1).
func _kiosk_garland() -> void:
	var kiosk: Array = []
	for spec in Layout.SOLIDS:
		if spec[0] == "Kiosk":
			kiosk = spec
	if kiosk.is_empty():
		return
	var c: Vector2 = kiosk[2]
	var size: Vector3 = kiosk[3]
	_begin("KioskGarland", Vector3(c.x, 0, c.y))
	var x0 := -size.x * 0.5 + 0.3 - 0.3   # кромка крыши: +0,3 м козырька к востоку, ±0,3 м свеса
	var x1 := size.x * 0.5 + 0.6
	var z0 := -size.z * 0.5 - 0.32
	var z1 := size.z * 0.5 + 0.32
	var y := size.y + 0.02
	var corners := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	var k := 0
	for i in 3:   # север, восток (фасад с окном), юг; к гаражам — без гирлянды
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[i + 1]
		var hooks := maxi(2, ceili(a.distance_to(b) / 1.2))
		for h in hooks:
			var p0 := a.lerp(b, float(h) / hooks)
			var p1 := a.lerp(b, float(h + 1) / hooks)
			var prev := p0
			for s in 6:
				var t := (s + 1) / 6.0
				var p := p0.lerp(p1, t) - Vector3(0, 0.16 * sin(PI * t), 0)
				_seg(prev, p, 0.006, Color(0.05, 0.05, 0.05), &"detail")
				if s % 2 == 1:
					_sph(Vector3(0.08, 0.1, 0.08), p - Vector3(0, 0.04, 0), BULBS[k % BULBS.size()], &"glow", &"sph6")
					k += 1
				prev = p
	_end()

## Гирлянда спиралью по стволу тополя на углу A∩B.
func _poplar_garland() -> void:
	_begin("PoplarGarland", Vector3(POPLAR_GARLAND.x, 0, POPLAR_GARLAND.y))
	var prev := Vector3.INF
	for i in 110:
		var t := i / 109.0
		var a := t * TAU * 6.0
		var p := Vector3(cos(a) * 0.58, 1.4 + t * 4.2, sin(a) * 0.58)
		if prev != Vector3.INF:
			_seg(prev, p, 0.006, Color(0.05, 0.05, 0.05), &"detail")
		if i % 2 == 0:
			_sph(Vector3(0.09, 0.11, 0.09), p, BULBS[(i / 2) % BULBS.size()], &"glow", &"sph6")
		prev = p
	_end()

# --- Z2: кормушка, бельё; Z5: велосипеды ---

func _feeder_and_laundry() -> void:
	_begin("Feeder", Vector3(FEEDER_BIRCH.x, 0, FEEDER_BIRCH.y))
	_seg(Vector3(0.12, 2.1, 0.0), Vector3(0.25, 1.85, 0.0), 0.004, Color(0.8, 0.8, 0.8), &"detail")
	_box(Vector3(0.12, 0.24, 0.12), Vector3(0.25, 1.72, 0), Color(0.92, 0.92, 0.95), &"detail")   # пакет из-под молока
	_box(Vector3(0.122, 0.09, 0.08), Vector3(0.25, 1.7, 0), Color(0.15, 0.30, 0.65), &"detail")
	_box(Vector3(0.13, 0.08, 0.124), Vector3(0.25, 1.69, 0), Color(0.06, 0.06, 0.07), &"detail")   # окошко
	_box(Vector3(0.14, 0.03, 0.14), Vector3(0.25, 1.855, 0), SNOW_WHITE, &"snow")
	# Синицы — живые, у Ambient (PEOPLE-03): взлетают, когда рядом Илюша или «Лада».
	_end()
	# Бельё колом на морозе на верёвке от берёзы к тополю.
	var a: Vector3 = LAUNDRY_LINE[0]
	var b: Vector3 = LAUNDRY_LINE[1]
	_begin("Laundry", (a + b) * 0.5)
	var la := a - (a + b) * 0.5
	var lb := b - (a + b) * 0.5
	var prev := la
	for s in 8:
		var t := (s + 1) / 8.0
		var p := la.lerp(lb, t) - Vector3(0, 0.25 * sin(PI * t), 0)
		_seg(prev, p, 0.006, Color(0.85, 0.85, 0.80), &"detail")
		prev = p
	var cloth := [[0.9, 0.7, Color(0.92, 0.92, 0.95)], [0.5, 0.55, Color(0.55, 0.70, 0.88)], [0.42, 0.75, Color(0.30, 0.32, 0.45)],
		[0.9, 0.6, Color(0.95, 0.88, 0.80)], [0.35, 0.4, Color(0.85, 0.40, 0.45)], [0.6, 0.5, Color(0.92, 0.92, 0.95)]]
	var yaw := atan2(-(lb.z - la.z), lb.x - la.x)
	for i in cloth.size():
		var t := (i + 0.7) / (cloth.size() + 0.4)
		var top := la.lerp(lb, t) - Vector3(0, 0.25 * sin(PI * t), 0)
		var w: float = cloth[i][0]
		var hgt: float = cloth[i][1]
		_box(Vector3(w, hgt, 0.02), top - Vector3(0, hgt * 0.5, 0), cloth[i][2], &"low", Vector3(0, yaw, 0.03 * (i % 3 - 1)))
		_box(Vector3(w, 0.03, 0.04), top + Vector3(0, 0.01, 0), SNOW_WHITE, &"snow", Vector3(0, yaw, 0))
	_end()

func _bikes() -> void:
	_begin("Bikes", BIKES)
	var tones := [Color(0.18, 0.34, 0.62), Color(0.62, 0.14, 0.12)]
	for i in 2:
		var x := -0.5 + i * 1.0
		var z := -0.05 * i
		var color: Color = tones[i]
		var lean := Vector3(0.12, 0, 0)
		for w in [-0.5, 0.5]:
			_torus(0.33, 0.04, Vector3(x + w, 0.33, z), Color(0.08, 0.08, 0.08), &"detail", Vector3(PI * 0.5, 0, 0) + lean)
		var rear := Vector3(x - 0.5, 0.33, z)
		var front := Vector3(x + 0.5, 0.33, z)
		var seat := Vector3(x - 0.15, 0.85, z + 0.04)
		var bar := Vector3(x + 0.35, 0.9, z + 0.04)
		var crank := Vector3(x - 0.02, 0.32, z)
		for pair in [[rear, seat], [seat, crank], [crank, rear], [seat, bar], [crank, bar], [bar, front]]:
			_seg(pair[0], pair[1], 0.02, color, &"detail")
		_box(Vector3(0.24, 0.05, 0.12), seat + Vector3(0, 0.04, 0), Color(0.1, 0.1, 0.1), &"detail")
		_seg(bar + Vector3(0, 0, -0.25), bar + Vector3(0, 0, 0.25), 0.015, Color(0.6, 0.6, 0.62), &"detail")
		_box(Vector3(0.28, 0.07, 0.14), seat + Vector3(0, 0.1, 0), SNOW_WHITE, &"snow")
	_sph(Vector3(2.6, 0.7, 0.9), Vector3(0, 0, 0.05), SNOW_WHITE, &"snow", &"sph")   # колёса наполовину в снегу
	_end()

# --- тропинки и пар ---

func _build_trails() -> void:
	for p in TRAILS:
		var a: Vector2 = p[0]
		var b: Vector2 = p[1]
		var plane := PlaneMesh.new()
		plane.size = Vector2(p[2], a.distance_to(b))
		var mesh := MeshInstance3D.new()
		mesh.mesh = plane
		mesh.name = "PropsTrail"
		mesh.material_override = Materials.trail(p[2], a.distance_to(b))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = Vector3((a.x + b.x) * 0.5, 0.026, (a.y + b.y) * 0.5)
		mesh.rotation.y = atan2(b.x - a.x, b.y - a.y)
		add_child(mesh)

var _steam_points: Array = []   # [точка, малый клуб (вытяжка ларька)]

## Пар как у люков lighting.gd (шейдер steam_puff, клубы в MultiMesh): над раскопкой — крупный, из вытяжки — мелкий.
func _build_steam() -> void:
	for small in [false, true]:
		var points: Array[Vector3] = []
		for s in _steam_points:
			if s[1] == small:
				points.append(s[0])
		if points.is_empty():
			continue
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var material := ShaderMaterial.new()
		material.shader = SteamShader
		material.set_shader_parameter("color", Color(0.64, 0.67, 0.74, 0.24 if small else 0.3))
		if small:
			material.set_shader_parameter("size_start", 0.2)
			material.set_shader_parameter("size_end", 0.9)
			material.set_shader_parameter("rise", 1.6)
		quad.material = material
		var puffs := 8 if small else 12
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = points.size() * puffs
		var index := 0
		for v in points.size():
			for k in puffs:
				mm.set_instance_transform(index, Transform3D(Basis.IDENTITY, points[v]))
				mm.set_instance_custom_data(index, Color(fposmod(_rand(v + 3, 0) + float(k) / puffs, 1.0), _rand(v, k + 1), _rand(v, k + 40), 0.0))
				index += 1
		var node := MultiMeshInstance3D.new()
		node.name = "PropsSteamSmall" if small else "PropsSteam"
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
		add_child(node)

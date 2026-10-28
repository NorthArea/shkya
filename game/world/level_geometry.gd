extends Node3D
## LevelGeometry: земля, здания, декор и покрытия из Layout (C1). Коллизии — простые коробки;
## внешний вид зимнего Новосибирска — процедурный (ART-02, ART-05 по сверке с фото ART-04): фасады с окнами,
## лоджиями и лестничными клетками, крыши, гаражи, грязные валы, тополя, фонари на консолях, контактная сеть.

const Layout = preload("res://game/world/layout.gd")
const Greybox = preload("res://game/world/greybox.gd")
const Materials = preload("res://game/world/materials.gd")

const WALL_HEIGHT := 12.0
const WALL_THICKNESS := 2.0
const SHOP_FRONTS := ["H5_North", "H6_West", "H8_East"]
const GARAGE_DOOR_SIDE := {"Garages_Yard": -1.0, "Garages_Kiosk": 1.0}   # дверями к двору / к улице
# Ворота гаражей: синие, жёлтые, бурые, ржавые, розовые, зелёные (сверка ART-04, черта 17).
# Насыщеннее, чтобы в холодном сумеречном свете бурые и ржавые не уходили в серое (повторная сверка ART-05, Н2).
const GARAGE_COLORS := [Color(0.18, 0.32, 0.58), Color(0.78, 0.58, 0.12), Color(0.48, 0.28, 0.14), Color(0.58, 0.24, 0.10),
	Color(0.72, 0.40, 0.42), Color(0.20, 0.44, 0.28), Color(0.40, 0.42, 0.45)]
const GARAGE_WALL := Color(0.42, 0.36, 0.33)   # кирпичные боксы
const CAR_COLORS := [Color(0.18, 0.22, 0.30), Color(0.55, 0.48, 0.36), Color(0.35, 0.12, 0.10), Color(0.70, 0.70, 0.66),
	Color(0.22, 0.30, 0.22), Color(0.50, 0.18, 0.12)]
const WARM := Color(1.0, 0.75, 0.42)           # подъезд и окна
const SODIUM := Color(1.0, 0.56, 0.18)         # натриевые фонари, как в lighting.gd (повторная сверка ART-05, Н1)
const CONCRETE := Color(0.50, 0.51, 0.52)
# Лоджии: ограждения разного цвета, остекление разное у каждой (сверка ART-04, черты 1, 4).
const PARAPET_COLORS := [Color(0.55, 0.56, 0.57), Color(0.66, 0.64, 0.58), Color(0.40, 0.45, 0.52), Color(0.58, 0.44, 0.38),
	Color(0.72, 0.72, 0.70), Color(0.47, 0.49, 0.44)]
const FRAME_WHITE := Color(0.86, 0.87, 0.86)
const GLASS_DARK := Color(0.08, 0.10, 0.13)
const BARK := Color(0.16, 0.15, 0.14)
const ENTRANCE_WALL_Z := 107.98   # северный фасад H1 (центр 115, глубина 14) — z = 108
const ENTRANCE_DOOR_X := -40.0    # дверь по центру козырька

var _mound_mesh: SphereMesh       # одна сетка на все комки сугробов
# Экземпляры MultiMesh, которые собираются со всего квартала и строятся одним вызовом в конце:
# лоджии, рамы, стёкла, ветки. Тысячи деталей без тысяч узлов и draw call.
var _concrete: Array[Transform3D] = []
var _painted: Array = []          # [Transform3D, Color]
var _glass: Array = []            # [Transform3D, Color]; альфа 1 — окно светится
var _frames: Array[Transform3D] = []
var _branches: Array[Transform3D] = []
var _wires: Array[Transform3D] = []

# Надписи: [текст, позиция, поворот y, размер шрифта, цвет].
const SIGNS := [
	# Номер подъезда — слева от двери (если смотреть со двора), Бабка — справа у двери (кадры 01, 02, 09).
	["3", Vector3(-38.75, 2.5, 107.93), PI, 90, Color(0.92, 0.92, 0.9)],
	["кв. 36–60", Vector3(-38.75, 2.18, 107.93), PI, 36, Color(0.92, 0.92, 0.9)],
	["АПТЕКА", Vector3(-70, 3.3, 14.05), 0.0, 120, Color(0.35, 1.0, 0.55)],
	["ПРОДУКТЫ", Vector3(-40, 3.3, 14.05), 0.0, 120, Color(1.0, 0.35, 0.3)],
	["ПРОДУКТЫ 24", Vector3(56.05, 3.3, -20), PI * 0.5, 110, Color(1.0, 0.8, 0.35)],
	["ГАСТРОНОМ", Vector3(81.95, 3.3, -10), -PI * 0.5, 110, Color(1.0, 0.8, 0.35)],
	["ШКЯ", Vector3(21.9, 1.6, 88), -PI * 0.5, 120, Color(0.12, 0.12, 0.14)],
	["ШИНОМОНТАЖ", Vector3(50.1, 2.4, -95), PI * 0.5, 70, Color(0.95, 0.95, 0.9)],
]

func _ready() -> void:
	_build_ground()
	var solids := Layout.all_solids()
	for i in solids.size():
		_build_solid(i, solids[i])
	_build_canopy()
	_build_entrance()
	_build_surfaces()
	_build_bounds()
	_build_signs()
	_build_kiosk_sign()
	_build_wires()
	_build_trails()
	_build_house_plates()
	_build_bus_stop()
	_build_skyline()
	_build_instances()

func _exit_tree() -> void:
	Materials.clear_cache()

# --- коллизии + вид ---

func _build_ground() -> void:
	var b := Layout.BOUNDS
	var center := Vector3(b.position.x + b.size.x * 0.5, -0.5, b.position.y + b.size.y * 0.5)
	var ground := Greybox.solid_box("Ground", center, Vector3(b.size.x, 1.0, b.size.y), Greybox.COLORS["ground"])
	(ground.get_child(1) as MeshInstance3D).material_override = Materials.snow(0.0)
	add_child(ground)

func _build_solid(index: int, spec: Array) -> void:
	var kind: String = spec[1]
	var xz: Vector2 = spec[2]
	var size: Vector3 = spec[3]
	var body := Greybox.solid_box(spec[0] if index < Layout.SOLIDS.size() else "%s_%d" % [spec[0], index], Vector3(xz.x, size.y * 0.5, xz.y), size, Greybox.COLORS.get(kind, Color.GRAY))
	var mesh := body.get_child(1) as MeshInstance3D
	match kind:
		"panel", "panel_low":
			mesh.material_override = Materials.facade(float(index), kind == "panel_low", spec[0] in SHOP_FRONTS)
			_dress_house(spec[0], kind == "panel_low", xz, size, index, body)
		"garage":
			mesh.queue_free()
			_garage_row(body, spec[0], size)
		"snow", "snow_bank":
			mesh.queue_free()
			body.add_child(_lumpy_bank(size, Materials.snow(0.0) if kind == "snow" else Materials.snow_bank(), index))
		"prop":
			if spec[0] == "Bench":
				mesh.queue_free()
				body.add_child(_bench(size))
			else:
				mesh.material_override = Materials.snow(0.1) if spec[0] == "Playground" else Materials.plain(Color(0.35, 0.25, 0.18))
				if spec[0] == "Playground":
					_playground_fence(body, size)
		"parked_car":
			mesh.queue_free()
			body.add_child(_zhiguli(size, CAR_COLORS[index % CAR_COLORS.size()]))
		"kiosk":
			mesh.queue_free()
			body.add_child(_kiosk(size))
		"lamp":
			mesh.material_override = Materials.plain(Color(0.12, 0.12, 0.13), 0.6)
			if spec[0] == "StreetLamp" or spec[0] == "TrolleyPole":
				body.add_child(_street_pole(size.y, Layout.lamp_arm(xz) if spec[0] == "StreetLamp" else Vector2.ZERO))
			else:
				body.add_child(_lamp_head(size.y))
			if index % 5 == 2:
				_notices(body, size, index)
		"tree":
			mesh.queue_free()
			body.add_child(_birch(size.y, float(index)))
		"poplar":
			mesh.queue_free()
			_poplar(Vector3(xz.x, 0, xz.y), index)
		"sign_post":
			mesh.material_override = Materials.plain(Color(0.15, 0.15, 0.16), 0.6)
			body.add_child(_street_sign(size.y))
		"fence":
			mesh.material_override = Materials.plain(Color(0.16, 0.24, 0.18), 0.7)
	add_child(body)

func _build_canopy() -> void:
	var canopy := Greybox.solid_box("Canopy", Layout.CANOPY[0], Layout.CANOPY[1], Greybox.COLORS["canopy"])
	# Снеговая шапка 0,18 м с видимым передним краем (сверка ART-04, черта 7).
	canopy.add_child(_slab(Layout.CANOPY[1], Vector3(0, Layout.CANOPY[1].y * 0.5 + 0.09, 0), 0.18))
	add_child(canopy)

## Подъезд (кадры 01, 02, 09): коричневая металлическая дверь, круглая лампа под козырьком, опоры козырька,
## табличка с номером и объявления. Только вид, без коллизий: путь к Бабке не меняется.
func _build_entrance() -> void:
	var root := Node3D.new()
	root.name = "Entrance"
	add_child(root)
	var canopy_center: Vector3 = Layout.CANOPY[0]
	var canopy_size: Vector3 = Layout.CANOPY[1]
	var canopy_bottom := canopy_center.y - canopy_size.y * 0.5
	var z := ENTRANCE_WALL_Z
	# Дверь в тёмном проёме, ручка и домофон.
	_part(root, Vector3(1.5, 2.35, 0.04), Vector3(ENTRANCE_DOOR_X, 1.175, z - 0.01), Materials.plain(Color(0.10, 0.09, 0.08), 0.9))
	var door_metal := StandardMaterial3D.new()   # свой: общий кэш plain() без metallic
	door_metal.albedo_color = Color(0.32, 0.22, 0.15)
	door_metal.roughness = 0.45
	door_metal.metallic = 0.5
	_part(root, Vector3(1.25, 2.15, 0.06), Vector3(ENTRANCE_DOOR_X, 1.075, z - 0.04), door_metal)
	_part(root, Vector3(0.05, 0.3, 0.05), Vector3(ENTRANCE_DOOR_X + 0.45, 1.05, z - 0.1), Materials.plain(Color(0.6, 0.6, 0.58), 0.3))
	_part(root, Vector3(0.16, 0.24, 0.04), Vector3(ENTRANCE_DOOR_X + 0.85, 1.35, z - 0.02), Materials.plain(Color(0.25, 0.25, 0.27), 0.4))
	# Табличка подъезда — тёмная пластина под номером.
	_part(root, Vector3(0.62, 0.66, 0.025), Vector3(-38.75, 2.36, z - 0.02), Materials.plain(Color(0.16, 0.19, 0.24), 0.6))
	# Объявления между дверью и табличкой.
	var paper := [Color(0.85, 0.84, 0.78), Color(0.78, 0.82, 0.86), Color(0.86, 0.80, 0.70)]
	var notes := [[Vector2(-38.95, 1.55), Vector2(0.3, 0.42)], [Vector2(-38.55, 1.62), Vector2(0.26, 0.34)], [Vector2(-38.8, 1.12), Vector2(0.34, 0.3)]]
	for i in notes.size():
		var note: Array = notes[i]
		_part(root, Vector3(note[1].x, note[1].y, 0.01), Vector3(note[0].x, note[0].y, z - 0.03), Materials.plain(paper[i], 0.95))
	# Круглая лампа над дверью: тёплый светящийся плафон (сам свет — Layout.LAMPS, подъезд).
	var lamp := Greybox.mesh_sphere(0.14, Color.WHITE)
	lamp.material_override = Materials.plain(Color(1.0, 0.9, 0.7), 0.3, WARM, 6.0)
	lamp.position = Vector3(ENTRANCE_DOOR_X, canopy_bottom - 0.3, z - 0.16)
	root.add_child(lamp)
	_part(root, Vector3(0.06, 0.06, 0.12), Vector3(ENTRANCE_DOOR_X, canopy_bottom - 0.3, z - 0.05), Materials.plain(Color(0.2, 0.2, 0.2), 0.5))
	# Консольный козырёк: косые кронштейны от стены под краями, без опор у земли — опора закрывала край Бабки
	# (повторная сверка ART-05, Н7).
	var post_material := Materials.plain(Color(0.30, 0.31, 0.33), 0.6)
	for x in [canopy_center.x - canopy_size.x * 0.5 + 0.1, canopy_center.x + canopy_size.x * 0.5 - 0.1]:
		_wires.append(_segment(Vector3(x, canopy_bottom - 1.1, z - 0.05), Vector3(x, canopy_bottom - 0.02, canopy_center.z - canopy_size.z * 0.5 + 0.3), 3.0))
	# Две низкие бетонные ступени у двери и трубный поручень (сверка ART-04, черта 7). Без коллизий:
	# ступени по 0,08 м, Илюша проходит к двери как раньше.
	var step_material := Materials.plain(Color(0.46, 0.46, 0.45), 0.9)
	_part(root, Vector3(2.4, 0.08, 1.1), Vector3(ENTRANCE_DOOR_X, 0.04, z - 0.55), step_material)
	_part(root, Vector3(2.4, 0.08, 0.55), Vector3(ENTRANCE_DOOR_X, 0.12, z - 0.28), step_material)
	_part(root, Vector3(2.3, 0.02, 0.5), Vector3(ENTRANCE_DOOR_X, 0.17, z - 0.3), Materials.snow(0.6))
	var rail := Materials.plain(Color(0.20, 0.30, 0.42), 0.5)
	for x in [ENTRANCE_DOOR_X - 1.25, ENTRANCE_DOOR_X + 1.25]:
		_part(root, Vector3(0.05, 0.9, 0.05), Vector3(x, 0.45, z - 1.05), rail)
		_part(root, Vector3(0.05, 0.05, 1.05), Vector3(x, 0.9, z - 0.55), rail)
	# Сугробы по бокам входа, у стены: только вид.
	for i in 2:
		var x: float = [ENTRANCE_DOOR_X - 4.2, ENTRANCE_DOOR_X + 3.6][i]
		var heap := _lumpy_bank(Vector3(2.4, 0.75, 1.3), Materials.snow(0.15), 77 + i * 5)   # рваные, не полусферы (Н9)
		heap.position = Vector3(x, 0.375, z - 0.7)
		root.add_child(heap)

func _part(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := Greybox.mesh_box(size, Color.WHITE)
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)

func _build_surfaces() -> void:
	var lift := {"yard_road": 0.01, "sidewalk": 0.015, "road": 0.02}
	for spec in Layout.SURFACES:
		var xz: Vector2 = spec[2]
		var size: Vector2 = spec[3]
		var mesh := Greybox.mesh_box(Vector3(size.x, 0.01, size.y), Greybox.COLORS[spec[1]])
		mesh.name = spec[0]
		mesh.position = Vector3(xz.x, lift[spec[1]], xz.y)
		match spec[1]:
			"road":
				mesh.material_override = Materials.road(size.x > size.y, xz, minf(size.x, size.y))
			"sidewalk":
				mesh.material_override = Materials.snow(0.7)
			"yard_road":
				mesh.material_override = Materials.snow(0.9)
		add_child(mesh)

func _build_bounds() -> void:
	var b := Layout.BOUNDS
	var cx := b.position.x + b.size.x * 0.5
	var cz := b.position.y + b.size.y * 0.5
	var h := WALL_HEIGHT * 0.5
	var t := WALL_THICKNESS
	var walls := [
		["Bound_West", Vector3(b.position.x - t * 0.5, h, cz), Vector3(t, WALL_HEIGHT, b.size.y)],
		["Bound_East", Vector3(b.end.x + t * 0.5, h, cz), Vector3(t, WALL_HEIGHT, b.size.y)],
		["Bound_North", Vector3(cx, h, b.position.y - t * 0.5), Vector3(b.size.x, WALL_HEIGHT, t)],
		["Bound_South", Vector3(cx, h, b.end.y + t * 0.5), Vector3(b.size.x, WALL_HEIGHT, t)],
	]
	for spec in walls:
		var body := Greybox.solid_box(spec[0], spec[1], spec[2], Color.BLACK)
		body.get_child(1).queue_free()  # стена невидима
		add_child(body)

# --- детали ---

## Вал снега из перекрывающихся комков разной высоты, чтобы не было гладкой «трубы».
func _lumpy_bank(size: Vector3, material: Material, seed: int) -> Node3D:
	var root := Node3D.new()
	var long_x := size.x >= size.z
	var length := size.x if long_x else size.z
	var count := maxi(1, int(ceil(length / 2.2)))
	var step := length / count
	# Комки разной высоты (0,45–1,4 высоты вала) и мелкие глыбы сверху: вал рваный, как после уборки
	# (сверка ART-04, черта 10), а не ровная «гусеница».
	for i in count:
		var r1 := fposmod(sin(float(seed * 31 + i) * 12.9898) * 43758.5453, 1.0)
		var r2 := fposmod(sin(float(seed * 17 + i) * 78.233) * 43758.5453, 1.0)
		var h := 0.45 + 0.95 * r1
		var lump_size := Vector3(step * (1.2 + 0.8 * r2), size.y * h, size.z * (0.8 + 0.35 * h)) if long_x else Vector3(size.x * (0.8 + 0.35 * h), size.y * h, step * (1.2 + 0.8 * r2))
		var lump := _mound(lump_size, material)
		var offset := -length * 0.5 + step * (i + 0.5)
		var jitter := (r2 - 0.5) * 0.3 * (size.z if long_x else size.x)
		lump.position += Vector3(offset, -size.y * 0.5 + lump_size.y * 0.5, jitter) if long_x else Vector3(jitter, -size.y * 0.5 + lump_size.y * 0.5, offset)
		root.add_child(lump)
		if r1 > 0.35:
			var chunk_size := Vector3(0.5 + 0.5 * r2, 0.35 + 0.3 * r1, 0.45 + 0.4 * r1)
			var chunk := _mound(chunk_size, material)
			var top := -size.y * 0.5 + lump_size.y * 0.85
			var shift := offset + (r1 - 0.5) * step
			chunk.position += Vector3(shift, top, -jitter) if long_x else Vector3(-jitter, top, shift)
			chunk.rotation.y = r2 * TAU
			root.add_child(chunk)
	return root

## Округлый сугроб, вписанный в коллизионную коробку (центр коробки — начало координат).
func _mound(size: Vector3, material: Material) -> MeshInstance3D:
	if _mound_mesh == null:
		_mound_mesh = SphereMesh.new()
		_mound_mesh.radius = 0.5
		_mound_mesh.height = 1.0
		_mound_mesh.radial_segments = 24
		_mound_mesh.rings = 10
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mound_mesh
	mesh.material_override = material
	mesh.scale = Vector3(size.x * 1.05, size.y * 2.0, size.z * 1.05)
	mesh.position.y = -size.y * 0.5
	return mesh

## Снежная шапка (по умолчанию 8 см).
func _slab(size: Vector3, at: Vector3, thickness := 0.08) -> MeshInstance3D:
	var mesh := Greybox.mesh_box(Vector3(size.x + 0.08, thickness, size.z + 0.08), Color.WHITE)
	mesh.material_override = Materials.snow(0.0)
	mesh.position = at
	return mesh

func _garage_row(body: Node3D, name: String, size: Vector3) -> void:
	var long_z := size.z > size.x
	var length := size.z if long_z else size.x
	var count := maxi(1, int(round(length / 3.6)))
	var unit := length / count
	var side: float = GARAGE_DOOR_SIDE.get(name, 1.0)
	# Кирпичные боксы с распашными воротами разного цвета, номера краской, снег 0,25 м (сверка ART-04, черта 17).
	var wall := Materials.plain(GARAGE_WALL, 0.9)
	for i in count:
		var offset := -length * 0.5 + unit * (i + 0.5)
		var color: Color = GARAGE_COLORS[(i * 5 + name.length() * 3) % GARAGE_COLORS.size()]
		var tone := 0.85 + 0.3 * fposmod(sin(float(i) * 7.31 + name.length()) * 43758.5, 1.0)
		var box := Greybox.mesh_box(Vector3(size.x, size.y, unit - 0.12) if long_z else Vector3(unit - 0.12, size.y, size.z), Color.WHITE)
		box.material_override = wall
		box.position = Vector3(0, 0, offset) if long_z else Vector3(offset, 0, 0)
		body.add_child(box)
		# Ворота на длинной стороне ряда: две створки со швом посередине.
		var leaf_material := Materials.plain(Color(color.r * tone, color.g * tone, color.b * tone), 0.55)
		for half: float in [-1.0, 1.0]:
			var leaf_w := unit * 0.39
			var along := offset + half * (leaf_w * 0.5 + 0.02)
			var leaf_size := Vector3(0.05, size.y * 0.72, leaf_w) if long_z else Vector3(leaf_w, size.y * 0.72, 0.05)
			var leaf := Greybox.mesh_box(leaf_size, Color.WHITE)
			leaf.material_override = leaf_material
			leaf.position = Vector3(side * (size.x * 0.5 + 0.03), -size.y * 0.12, along) if long_z else Vector3(along, -size.y * 0.12, side * (size.z * 0.5 + 0.03))
			body.add_child(leaf)
		var number := _label(str(i * 3 + 11 + name.length()), 72, Color(0.92, 0.92, 0.88))
		number.pixel_size = 0.005
		var face := side * (size.x * 0.5 + 0.06) if long_z else side * (size.z * 0.5 + 0.06)
		number.position = Vector3(face, size.y * 0.3, offset) if long_z else Vector3(offset, size.y * 0.3, face)
		number.rotation.y = (PI * 0.5 if side > 0.0 else -PI * 0.5) if long_z else (0.0 if side > 0.0 else PI)
		body.add_child(number)
	body.add_child(_slab(size, Vector3(0, size.y * 0.5 + 0.125, 0), 0.25))

func _zhiguli(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var long_x := size.x > size.z
	var length := size.x if long_x else size.z
	var width := size.z if long_x else size.x
	var visual := Node3D.new()
	if long_x:
		visual.rotation.y = PI * 0.5
	root.add_child(visual)
	var lower := Greybox.mesh_box(Vector3(width, 0.7, length), color)
	lower.material_override = Materials.plain(color, 0.35)
	lower.position.y = -size.y * 0.5 + 0.55
	visual.add_child(lower)
	var cabin := Greybox.mesh_box(Vector3(width * 0.9, 0.5, length * 0.48), color)
	cabin.material_override = Materials.plain(color.darkened(0.1), 0.35)
	cabin.position = Vector3(0, -size.y * 0.5 + 1.15, 0.2)
	visual.add_child(cabin)
	var snow_top := Greybox.mesh_box(Vector3(width * 0.88, 0.1, length * 0.46), Color.WHITE)
	snow_top.material_override = Materials.snow(0.0)
	snow_top.position = Vector3(0, -size.y * 0.5 + 1.45, 0.2)
	visual.add_child(snow_top)
	var tyre := Materials.plain(Color(0.06, 0.06, 0.06), 0.9)
	for wx in [-width * 0.47, width * 0.47]:
		for wz in [-length * 0.32, length * 0.32]:
			var wheel := Greybox.mesh_cylinder(0.3, 0.3, 0.2, Color.BLACK)
			wheel.material_override = tyre
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(wx, -size.y * 0.5 + 0.3, wz)
			visual.add_child(wheel)
	return root

func _kiosk(size: Vector3) -> Node3D:
	# Пустая будка: окно на восток (к улице), внутри тёплый свет и продавщица.
	var root := Node3D.new()
	var green := Materials.plain(Color(0.22, 0.38, 0.28), 0.7)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var t := 0.1
	var parts := [
		[Vector3(t, size.y, size.z), Vector3(-hx + t * 0.5, 0, 0)],             # задняя стена
		[Vector3(size.x, size.y, t), Vector3(0, 0, -hz + t * 0.5)],             # северная
		[Vector3(size.x, size.y, t), Vector3(0, 0, hz - t * 0.5)],              # южная
		[Vector3(t, 1.0, size.z), Vector3(hx - t * 0.5, -hy + 0.5, 0)],         # прилавок под окном
		[Vector3(t, 0.7, size.z), Vector3(hx - t * 0.5, hy - 0.35, 0)],         # над окном
		[Vector3(size.x + 0.6, 0.12, size.z + 0.6), Vector3(0.3, hy + 0.06, 0)], # крыша с козырьком
	]
	for part in parts:
		var mesh := Greybox.mesh_box(part[0], Color.WHITE)
		mesh.material_override = green
		mesh.position = part[1]
		root.add_child(mesh)
	var glass := Greybox.mesh_box(Vector3(0.02, size.y - 1.7, size.z - 0.2), Color.WHITE)
	glass.material_override = Materials.glass()
	glass.position = Vector3(hx - 0.02, -hy + 1.0 + (size.y - 1.7) * 0.5, 0)
	root.add_child(glass)
	var shelves := Greybox.mesh_box(Vector3(0.4, 1.4, size.z - 0.4), Color.WHITE)
	shelves.material_override = Materials.plain(Color(0.75, 0.55, 0.30), 0.8, WARM, 0.6)   # полки с батонами
	shelves.position = Vector3(-hx + 0.35, -hy + 1.5, 0)
	root.add_child(shelves)
	root.add_child(_slab(Vector3(size.x + 0.6, 0.12, size.z + 0.6), Vector3(0.3, hy + 0.16, 0), 0.2))
	# Павильон из крашеного металла: рёбра на боковых стенах и короб рольставни над окном (сверка ART-04, черта 15).
	var rib := Materials.plain(Color(0.17, 0.30, 0.22), 0.6)
	for zs in [-1.0, 1.0]:
		var k := 0.4
		while k < size.x - 0.2:
			var r := Greybox.mesh_box(Vector3(0.06, size.y - 0.2, 0.05), Color.WHITE)
			r.material_override = rib
			r.position = Vector3(-hx + k, 0, zs * (hz + 0.02))
			root.add_child(r)
			k += 0.5
	var shutter := Greybox.mesh_box(Vector3(0.25, 0.2, size.z - 0.1), Color.WHITE)
	shutter.material_override = Materials.plain(Color(0.55, 0.56, 0.55), 0.5)
	shutter.position = Vector3(hx + 0.08, hy - 0.8, 0)
	root.add_child(shutter)
	var inside := OmniLight3D.new()
	inside.light_color = WARM
	inside.light_energy = 1.5
	inside.omni_range = 4.0
	inside.position = Vector3(0, hy - 0.5, 0)
	root.add_child(inside)
	return root

func _lamp_head(height: float) -> Node3D:
	var head := Greybox.mesh_box(Vector3(0.5, 0.18, 0.3), Color.WHITE)
	head.material_override = Materials.plain(Color(0.2, 0.2, 0.2), 0.5, SODIUM, 4.0)
	head.position = Vector3(0, height * 0.5 - 0.1, 0)
	return head

func _birch(height: float, seed: float) -> Node3D:
	var root := Node3D.new()
	var trunk := Greybox.mesh_cylinder(0.1, 0.16, height, Color.WHITE)
	trunk.material_override = Materials.plain(Color(0.85, 0.84, 0.80), 0.9)
	root.add_child(trunk)
	var bark := Materials.plain(Color(0.10, 0.09, 0.08), 0.9)
	for i in 6:
		var branch := Greybox.mesh_cylinder(0.02, 0.05, 2.2, Color.WHITE)
		branch.material_override = bark
		var angle := seed * 1.7 + i * 1.1
		branch.position = Vector3(cos(angle) * 0.6, height * (0.05 + i * 0.07), sin(angle) * 0.6)
		branch.rotation = Vector3(sin(angle) * 0.7, 0, -cos(angle) * 0.7)
		root.add_child(branch)
	return root

func _street_sign(height: float) -> Node3D:
	var root := Node3D.new()
	var plate := Greybox.mesh_box(Vector3(1.9, 0.5, 0.05), Color.WHITE)
	plate.material_override = Materials.plain(Color(0.10, 0.20, 0.42), 0.5)
	plate.position = Vector3(0, height * 0.5 - 0.3, 0)
	root.add_child(plate)
	for side in [1.0, -1.0]:
		var label := _label("УЛ. ЛЕНИНА", 64, Color(0.95, 0.95, 0.95))
		label.position = Vector3(0, height * 0.5 - 0.3, 0.035 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		root.add_child(label)
	return root

func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	return label

func _build_signs() -> void:
	for spec in SIGNS:
		var label := _label(spec[0], spec[3], spec[4])
		label.name = "Sign_%s" % spec[0]
		label.position = spec[1]
		label.rotation.y = spec[2]
		add_child(label)

## Вывеска-короб над окном киоска: светлый фон, простые красные буквы без обводки (сверка ART-04, черты 15, 16).
func _build_kiosk_sign() -> void:
	var board := Greybox.mesh_box(Vector3(0.22, 0.62, 3.7), Color.WHITE)
	board.name = "KioskSignBox"
	board.material_override = Materials.plain(Color(0.60, 0.58, 0.52), 0.6)   # не пересвечен окном (Н4)
	board.position = Layout.KIOSK + Vector3(2.62, 2.86, 0.0)
	add_child(board)
	var sign := Label3D.new()
	sign.name = "KioskSign"
	sign.text = "ХЛЕБ"
	sign.font_size = 120
	sign.pixel_size = 0.0045
	sign.modulate = Color(0.42, 0.03, 0.02)
	sign.outline_size = 0
	sign.shaded = false
	sign.position = Layout.KIOSK + Vector3(2.75, 2.86, 0.0)
	sign.rotation.y = PI * 0.5  # смотрит на улицу, на восток
	add_child(sign)

## Контактная сеть над улицами A и B (сверка ART-04, черта 13): поперечины между парами столбов через 24 м,
## два контактных провода с провисом; во двор — бытовые провода от дворового фонаря к домам.
const SPAN_Y := 7.85
const CONTACT_Y := 7.0
func _build_wires() -> void:
	var wire := Materials.plain(Color(0.05, 0.05, 0.05), 0.5)
	var spans_a: Array[float] = []
	for x in range(-90, 100, 24):
		spans_a.append(float(x))
		_sag_wire(Vector3(x, SPAN_Y, 22.0), Vector3(x, SPAN_Y, 42.0), 0.35, wire)
	var spans_b: Array[float] = []
	for z in range(10, -112, -24):
		spans_b.append(float(z))
		_sag_wire(Vector3(Layout.LAMP_B_WEST, SPAN_Y, z), Vector3(Layout.LAMP_B_EAST, SPAN_Y, z), 0.3, wire)
	for z in [30.5, 33.5]:
		var points: Array[float] = [-100.0]
		points.append_array(spans_a)
		points.append(100.0)
		for i in range(1, points.size()):
			_sag_wire(Vector3(points[i - 1], CONTACT_Y, z), Vector3(points[i], CONTACT_Y, z), 0.22, wire)
	for x in [68.5, 71.5]:
		var points: Array[float] = [25.0]
		points.append_array(spans_b)
		points.append(-118.0)
		for i in range(1, points.size()):
			_sag_wire(Vector3(x, CONTACT_Y, points[i - 1]), Vector3(x, CONTACT_Y, points[i]), 0.22, wire)
	# Подвесы контактных проводов к поперечинам.
	for x in spans_a:
		for z in [30.5, 33.5]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.33, z), wire)
	for z in spans_b:
		for x in [68.5, 71.5]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.28, z), wire)
	# Бытовые провода во дворе: от дворового фонаря к H1 и H2.
	var yard_top := Vector3(-52.0, 5.9, 100.0)
	for target in [Vector3(-52.0, 7.5, 108.0), Vector3(-78.0, 7.5, 92.0), Vector3(-78.0, 7.2, 93.0)]:
		_sag_wire(yard_top, target, 0.5, wire)

## Провод с провисом: ломаная из 8 отрезков по параболе.
func _sag_wire(from: Vector3, to: Vector3, sag: float, material: Material) -> void:
	var steps := 8
	var prev := from
	for i in range(1, steps + 1):
		var k := float(i) / steps
		var p := from.lerp(to, k) - Vector3.UP * sag * 4.0 * k * (1.0 - k)
		_wire(prev, p, material)
		prev = p

## Отрезок провода — экземпляр общего MultiMesh (единичный цилиндр толщиной 4 см, ось Y — вдоль провода).
func _wire(from: Vector3, to: Vector3, _material: Material) -> void:
	_wires.append(_segment(from, to, 1.0))

## Преобразование единичного цилиндра (высота 1, радиус 0,5) в отрезок from → to толщиной 2·radius_scale·0,5.
static func _segment(from: Vector3, to: Vector3, radius_scale: float) -> Transform3D:
	var axis := to - from
	var dir := axis.normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
	var other := side.cross(dir).normalized()
	return Transform3D(Basis(side * radius_scale, axis, other * radius_scale), (from + to) * 0.5)

## Город за границей карты: только вид, без коллизий; башня «ГОСТИНИЦА» в конце улицы B.
func _build_skyline() -> void:
	var b := Layout.BOUNDS
	var index := 100
	for x in range(-120, 140, 32):
		for z in [b.position.y - 28.0, b.end.y + 28.0]:
			_backdrop(Vector3(x, 0, z), Vector3(26, 21.0 + (index % 3) * 6.0, 16), index)
			index += 1
	for z in range(-110, 130, 34):
		for x in [b.position.x - 26.0, b.end.x + 26.0]:
			_backdrop(Vector3(x, 0, z), Vector3(16, 21.0 + (index % 3) * 6.0, 26), index)
			index += 1
	var tower := Greybox.mesh_box(Vector3(26, 58, 22), Color.WHITE)
	tower.material_override = Materials.facade(7.0, true)
	tower.position = Vector3(70, 29, -205)
	tower.name = "Landmark"
	add_child(tower)
	var spire := Greybox.mesh_cylinder(0.0, 4.0, 18.0, Color.WHITE)
	spire.material_override = Materials.plain(Color(0.45, 0.42, 0.38), 0.6)
	spire.position = Vector3(70, 67, -205)
	add_child(spire)
	# Буквы-короб на крыше башни, как в концепте 05 (сверка ART-04, P3 14): каркас и светящиеся буквы над парапетом.
	var frame := Greybox.mesh_box(Vector3(22, 0.3, 0.3), Color.WHITE)
	frame.material_override = Materials.plain(Color(0.15, 0.15, 0.16), 0.6)
	frame.position = Vector3(70, 58.4, -194.3)
	add_child(frame)
	var hotel := _label("ГОСТИНИЦА", 260, Color(1.0, 0.92, 0.75))
	hotel.pixel_size = 0.016
	hotel.position = Vector3(70, 60.6, -194.2)
	add_child(hotel)
	# Высокие башни 16–25 этажей и башенные краны на горизонте (черта 20).
	for spec in [[Vector3(-150, 0, -40), Vector3(20, 52, 20), 201], [Vector3(160, 0, 70), Vector3(20, 64, 20), 202],
			[Vector3(-60, 0, 175), Vector3(22, 48, 22), 203], [Vector3(150, 0, -150), Vector3(20, 70, 20), 204]]:
		_backdrop(spec[0], spec[1], spec[2])
	_crane(Vector3(-130, 0, -170), 62.0, 0.6)
	_crane(Vector3(175, 0, 10), 55.0, 2.4)

## Башенный кран силуэтом: решётчатая мачта, стрела и противовес, красный огонь наверху.
func _crane(at: Vector3, height: float, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "Crane"
	root.position = at
	root.rotation.y = yaw
	add_child(root)
	var steel := Materials.plain(Color(0.55, 0.45, 0.18), 0.7)
	var mast := Greybox.mesh_box(Vector3(1.6, height, 1.6), Color.WHITE)
	mast.material_override = steel
	mast.position.y = height * 0.5
	root.add_child(mast)
	var jib := Greybox.mesh_box(Vector3(38, 1.2, 1.2), Color.WHITE)
	jib.material_override = steel
	jib.position = Vector3(14, height + 0.6, 0)
	root.add_child(jib)
	var weight := Greybox.mesh_box(Vector3(4, 2.2, 2), Color.WHITE)
	weight.material_override = Materials.plain(Color(0.35, 0.35, 0.36), 0.8)
	weight.position = Vector3(-8, height + 0.2, 0)
	root.add_child(weight)
	var cab := Greybox.mesh_box(Vector3(2.4, 2.4, 2.4), Color.WHITE)
	cab.material_override = steel
	cab.position = Vector3(1.5, height - 1.6, 0)
	root.add_child(cab)
	var light := Greybox.mesh_sphere(0.5, Color.WHITE)
	light.material_override = Materials.plain(Color(1.0, 0.1, 0.05), 0.4, Color(1.0, 0.1, 0.05), 6.0)
	light.position = Vector3(0, height + 3.0, 0)
	root.add_child(light)

func _backdrop(at: Vector3, size: Vector3, seed: int) -> void:
	var mesh := Greybox.mesh_box(size, Color.WHITE)
	mesh.material_override = Materials.facade(float(seed), seed % 4 == 0)
	mesh.position = at + Vector3.UP * size.y * 0.5
	add_child(mesh)

# --- ART-05: приметы спального Новосибирска по сверке с фото (ART-04) ---

## Лоджии и балконы столбами по всей высоте, полоса лестничной клетки, крыша: лифтовые отделения и антенны
## у панелек, скатная крыша в снегу у старых домов (черты 1, 2, 4–6). Только вид, без коллизий.
func _dress_house(name: String, low: bool, xz: Vector2, size: Vector3, index: int, body: Node3D) -> void:
	var floor_h := 3.3 if low else 2.8
	var spacing := 2.6 if low else 3.0
	var long_x := size.x >= size.z
	var length := size.x if long_x else size.z
	var depth := size.z if long_x else size.x
	var along0 := (xz.x if long_x else xz.y) - length * 0.5
	var storeys := int(floor(size.y / floor_h + 0.01))
	var accent: Color = Materials.facade_accent(float(index), low)
	var first := int(ceil((along0 + 0.6) / spacing))
	var last := int(floor((along0 + length - 0.6) / spacing)) - 1
	for side: float in [-1.0, 1.0]:
		var wall := (xz.y if long_x else xz.x) + side * depth * 0.5
		for k in range(first, last + 1):
			var u := (k + 0.5) * spacing
			var m := posmod(k + index * 3, 10)
			var entrance := name == "H1_South" and side < 0.0 and absf(u - ENTRANCE_DOOR_X) < 4.6
			if entrance:
				if absf(u - ENTRANCE_DOOR_X) < spacing * 0.5:
					# Над подъездом: полоса начинается над козырьком, дверь и таблички остаются видны.
					_stair_strip(u, wall, side, long_x, spacing, floor_h, storeys, size.y, accent, k, Layout.CANOPY[0].y + 0.3)
				continue
			if not low and m == 5:
				_stair_strip(u, wall, side, long_x, spacing, floor_h, storeys, size.y, accent, k)
			elif m in ([1, 2, 7, 8] if not low else [2, 3, 7]):
				for s in range(1, storeys):
					_balcony(u, wall, side, long_x, spacing, floor_h, s, s == storeys - 1, k * 31 + s * 7 + index)
	if low:
		# Скатная крыша под снегом и вентиляционные стояки.
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(depth + 0.8, 3.2, length + 0.6)
		roof.mesh = prism
		roof.material_override = Materials.snow(0.05)
		roof.position = Vector3(0, size.y * 0.5 + 1.6, 0)
		if long_x:
			roof.rotation.y = PI * 0.5
		body.add_child(roof)
		var vent := Materials.plain(Color(0.42, 0.32, 0.28), 0.9)
		var n := maxi(1, int(length / 14.0))
		for i in n:
			var a := -length * 0.5 + length * (i + 0.5) / n
			var stack := Greybox.mesh_box(Vector3(0.6, 1.6, 0.6), Color.WHITE)
			stack.material_override = vent
			stack.position = Vector3(a, size.y * 0.5 + 2.2, depth * 0.18) if long_x else Vector3(depth * 0.18, size.y * 0.5 + 2.2, a)
			body.add_child(stack)
	else:
		# Машинные отделения лифтов над каждой секцией и телеантенны.
		var room := Materials.plain(CONCRETE, 0.9)
		var mast := Materials.plain(Color(0.25, 0.25, 0.26), 0.5)
		var sections := maxi(1, int(round(length / 26.0)))
		for i in sections:
			var a := -length * 0.5 + length * (i + 0.5) / sections
			var box := Greybox.mesh_box(Vector3(4.2, 2.4, 3.2) if long_x else Vector3(3.2, 2.4, 4.2), Color.WHITE)
			box.material_override = room
			box.position = Vector3(a, size.y * 0.5 + 1.2, 0) if long_x else Vector3(0, size.y * 0.5 + 1.2, a)
			body.add_child(box)
			body.add_child(_slab(Vector3(4.2, 0, 3.2) if long_x else Vector3(3.2, 0, 4.2), box.position + Vector3.UP * 1.24, 0.12))
			for j in 2:
				var off := (j - 0.5) * 6.0 + a + 4.0
				if absf(off) > length * 0.5 - 1.0:
					continue
				var base := Vector3(off, size.y * 0.5, depth * 0.25 * (1 - 2 * j)) if long_x else Vector3(depth * 0.25 * (1 - 2 * j), size.y * 0.5, off)
				var pole := Greybox.mesh_cylinder(0.03, 0.03, 3.0, Color.WHITE)
				pole.material_override = mast
				pole.position = base + Vector3.UP * 1.5
				body.add_child(pole)
				for b in 2:
					var bar := Greybox.mesh_box(Vector3(1.4 - b * 0.4, 0.03, 0.03), Color.WHITE)
					bar.material_override = mast
					bar.position = base + Vector3.UP * (2.4 + b * 0.4)
					bar.rotation.y = float(index + j) * 0.7
					body.add_child(bar)

## Одна лоджия: плита пола, ограждение (своё у каждой) и у части — остекление в белых рамах, иногда светится.
func _balcony(u: float, wall: float, side: float, long_x: bool, spacing: float, floor_h: float, storey: int, top: bool, seed: int) -> void:
	var w := spacing - 0.12
	var d := 1.1
	var y := storey * floor_h
	_concrete.append(_box_xf(Vector3(w, 0.12, d), u, y - 0.06, wall + side * d * 0.5, long_x))
	var color: Color = PARAPET_COLORS[int(_rand(seed * 13, 1) * PARAPET_COLORS.size()) % PARAPET_COLORS.size()]
	_painted.append([_box_xf(Vector3(w, 1.0, 0.07), u, y + 0.5, wall + side * (d - 0.035), long_x), color])
	for e: float in [-1.0, 1.0]:
		_painted.append([_box_xf(Vector3(0.07, 1.0, d), u + e * (w * 0.5 - 0.035), y + 0.5, wall + side * d * 0.5, long_x), color])
	if _rand(seed * 13, 2) < 0.6:
		var gh := floor_h - 1.12
		var lit := _rand(seed * 13, 3) < 0.3
		var glass := Color(1.0, 0.70, 0.36, 1.0) if lit else Color(GLASS_DARK.r, GLASS_DARK.g, GLASS_DARK.b, 0.0)
		_glass.append([_box_xf(Vector3(w - 0.06, gh, 0.03), u, y + 1.0 + gh * 0.5, wall + side * (d - 0.03), long_x), glass])
		var frame_white := _rand(seed * 13, 4) < 0.8
		var frames := 3 + int(_rand(seed * 13, 5) * 2.0)
		for i in frames + 1:
			var fu := u - w * 0.5 + w * float(i) / frames
			var xf := _box_xf(Vector3(0.05, gh, 0.06), fu, y + 1.0 + gh * 0.5, wall + side * (d - 0.02), long_x)
			if frame_white:
				_frames.append(xf)
			else:
				_painted.append([xf, Color(0.36, 0.26, 0.18)])
		_frames.append(_box_xf(Vector3(w, 0.06, 0.06), u, y + 1.0 + gh, wall + side * (d - 0.02), long_x))
	if top:
		_concrete.append(_box_xf(Vector3(w, 0.12, d), u, y + floor_h - 0.06, wall + side * d * 0.5, long_x))

## Полоса лестничной клетки: панель акцентного цвета поверх ряда окон, мелкие окна со сдвигом на полэтажа.
func _stair_strip(u: float, wall: float, side: float, long_x: bool, spacing: float, floor_h: float, storeys: int, height: float, accent: Color, seed: int, from_y := 0.0) -> void:
	var h := height - 0.1 - from_y
	_painted.append([_box_xf(Vector3(spacing - 0.2, h, 0.1), u, from_y + h * 0.5, wall + side * 0.06, long_x), accent])
	for s in range(0, storeys - 1):
		var lit := fposmod(sin(float(seed * 7 + s) * 12.9898) * 43758.5453, 1.0) < 0.55
		var glass := Color(0.95, 0.85, 0.62, 1.0) if lit else Color(GLASS_DARK.r, GLASS_DARK.g, GLASS_DARK.b, 0.0)
		var y := (s + 1) * floor_h + 0.15
		if y + 0.3 > height:
			break
		if y - 0.3 < from_y:
			continue
		_glass.append([_box_xf(Vector3(1.3, 0.55, 0.04), u, y, wall + side * 0.12, long_x), glass])
		_frames.append(_box_xf(Vector3(1.4, 0.06, 0.06), u, y - 0.3, wall + side * 0.13, long_x))

## Детерминированное псевдослучайное число 0..1 по seed и номеру.
static func _rand(seed: int, k: int) -> float:
	return fposmod(sin(float(seed + k) * 12.9898) * 43758.5453, 1.0)

## Коробка размера size (x — вдоль фасада, z — от стены) в точке (u вдоль, y, w поперёк) фасада, идущего вдоль x или z.
static func _box_xf(size: Vector3, u: float, y: float, w: float, long_x: bool) -> Transform3D:
	if long_x:
		return Transform3D(Basis.from_scale(size), Vector3(u, y, w))
	return Transform3D(Basis.from_scale(Vector3(size.z, size.y, size.x)), Vector3(w, y, u))

## Скамейка у подъезда: ножки, рейки сиденья и спинки, снег на сиденье (сверка ART-04, черты 7, 22).
func _bench(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var wood := Materials.plain(Color(0.36, 0.24, 0.15), 0.85)
	var iron := Materials.plain(Color(0.14, 0.14, 0.15), 0.6)
	var hy := size.y * 0.5
	for x in [-size.x * 0.4, size.x * 0.4]:
		_part(root, Vector3(0.08, size.y, size.z * 0.8), Vector3(x, 0, 0), iron)
		_part(root, Vector3(0.08, 0.5, 0.08), Vector3(x, hy + 0.25, size.z * 0.38), iron)
	for i in 3:
		_part(root, Vector3(size.x, 0.05, 0.2), Vector3(0, hy - 0.02, -size.z * 0.3 + i * size.z * 0.3), wood)
	for i in 2:
		_part(root, Vector3(size.x, 0.14, 0.05), Vector3(0, hy + 0.2 + i * 0.22, size.z * 0.4), wood)
	var cap := _mound(Vector3(size.x * 0.9, 0.12, size.z * 0.75), Materials.snow(0.0))
	cap.position += Vector3(0, hy + 0.06, -0.05)
	root.add_child(cap)
	return root

## Уличный столб: видимая высота POLE_HEIGHT; у фонаря — консоль к проезжей части и натриевый светильник
## на её конце (черта 14). У опоры контактной сети консоли нет.
func _street_pole(collision_height: float, arm: Vector2) -> Node3D:
	var root := Node3D.new()
	var metal := Materials.plain(Color(0.12, 0.12, 0.13), 0.6)
	var extra := Layout.POLE_HEIGHT - collision_height
	var top := Greybox.mesh_cylinder(0.09, 0.12, extra, Color.WHITE)
	top.material_override = metal
	top.position = Vector3(0, collision_height * 0.5 + extra * 0.5, 0)
	root.add_child(top)
	if arm != Vector2.ZERO:
		var y := collision_height * 0.5 + extra - 0.3
		var bar := Greybox.mesh_box(Vector3(absf(arm.x) + 0.06, 0.07, absf(arm.y) + 0.06), Color.WHITE)
		bar.material_override = metal
		bar.position = Vector3(arm.x * 0.5, y, arm.y * 0.5)
		root.add_child(bar)
		var head := Greybox.mesh_box(Vector3(0.7, 0.16, 0.32) if arm.x != 0.0 else Vector3(0.32, 0.16, 0.7), Color.WHITE)
		head.material_override = Materials.plain(Color(0.2, 0.2, 0.2), 0.5, SODIUM, 4.0)
		head.position = Vector3(arm.x, y - 0.1, arm.y)
		root.add_child(head)
	return root

## Бумажные объявления на столбе (черта 13).
func _notices(body: Node3D, size: Vector3, seed: int) -> void:
	var paper := [Color(0.86, 0.85, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.72)]
	for i in 2 + seed % 2:
		var note := Greybox.mesh_box(Vector3(0.22, 0.3, 0.01), Color.WHITE)
		note.material_override = Materials.plain(paper[(seed + i) % paper.size()], 0.95)
		var angle := float(seed + i * 2) * 1.3
		note.position = Vector3(sin(angle) * (size.x * 0.5 + 0.01), -size.y * 0.5 + 1.4 + i * 0.32, cos(angle) * (size.z * 0.5 + 0.01))
		note.rotation.y = angle
		body.add_child(note)

## Тополь: толстый тёмный ствол и широкая голая крона из сотен веток (черта 8); ветки — в общем MultiMesh.
func _poplar(base: Vector3, seed: int) -> void:
	var height := 15.0 + 4.0 * _rand(seed * 97, 0)
	var fork := height * (0.32 + 0.08 * _rand(seed * 97, 1))
	_branches.append(_segment(base, base + Vector3(0, fork + 0.5, 0), 0.95))
	var limbs := 5 + int(_rand(seed * 97, 2) * 3.0)
	for i in limbs:
		var yaw := TAU * (float(i) + _rand(seed * 97, 10 + i) * 0.6) / limbs
		var tilt := deg_to_rad(18.0 + 22.0 * _rand(seed * 97, 20 + i))
		var dir := Vector3(sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw))
		var start := base + Vector3(0, fork - 0.3 * _rand(seed * 97, 30 + i), 0)
		var limb_len := (height - fork) * (0.75 + 0.3 * _rand(seed * 97, 40 + i))
		var end := start + dir * limb_len
		_branches.append(_segment(start, end, 0.42))
		for j in 6:
			var t := 0.3 + 0.7 * float(j) / 6.0
			var from := start.lerp(end, t)
			var byaw := yaw + (_rand(seed * 97, 100 + i * 10 + j) - 0.5) * 2.4
			var btilt := deg_to_rad(25.0 + 35.0 * _rand(seed * 97, 200 + i * 10 + j))
			var bdir := Vector3(sin(btilt) * cos(byaw), cos(btilt), sin(btilt) * sin(byaw))
			var blen := 1.6 + 2.4 * _rand(seed * 97, 300 + i * 10 + j) * (1.0 - t * 0.5)
			var bend := from + bdir * blen
			_branches.append(_segment(from, bend, 0.14))
			for q in 3:
				var tw := from.lerp(bend, 0.4 + 0.3 * q)
				var tyaw := byaw + (_rand(seed * 97, 400 + i * 30 + j * 3 + q) - 0.5) * 3.0
				var tdir := Vector3(cos(tyaw) * 0.6, 0.8, sin(tyaw) * 0.6).normalized()
				_branches.append(_segment(tw, tw + tdir * (0.9 + 0.8 * _rand(seed * 97, 500 + q + j)), 0.05))

## Натоптанные тропинки в рыхлом снегу (черта 12): от подъезда к проезду, через двор по пути Илюши,
## от тротуара к окну киоска, по газонам улицы A.
func _build_trails() -> void:
	var paths := [
		[Vector2(-40, 106), Vector2(-40, 100), 1.6], [Vector2(-40, 101), Vector2(-20, 86), 1.3],
		[Vector2(-20, 86), Vector2(-5, 63), 1.3], [Vector2(-5, 58), Vector2(-2, 44), 1.4],
		[Vector2(-40, 106), Vector2(-70, 104), 1.1], [Vector2(-40, 106), Vector2(-12, 104), 1.1],
		[Vector2(-60, 86), Vector2(-48, 96), 1.0], [Vector2(64, -77), Vector2(59, -77), 2.2],
		[Vector2(58, -70), Vector2(58, -84), 1.2], [Vector2(-88, 17), Vector2(-10, 18), 1.0],
	]
	for p in paths:
		var a: Vector2 = p[0]
		var b: Vector2 = p[1]
		var mesh := Greybox.mesh_box(Vector3(p[2], 0.01, a.distance_to(b)), Color.WHITE)
		mesh.name = "Trail"
		mesh.material_override = Materials.snow(1.0)
		mesh.position = Vector3((a.x + b.x) * 0.5, 0.018, (a.y + b.y) * 0.5)
		mesh.rotation.y = atan2(b.x - a.x, b.y - a.y)
		add_child(mesh)

## Общие MultiMesh: лоджии, рамы, стёкла, ветки, провода. Тени отбрасывают только лоджии и ветки.
func _build_instances() -> void:
	var cube := BoxMesh.new()
	_multimesh("Balconies", cube, _concrete, [], Materials.plain(CONCRETE, 0.9), true)
	var painted_xf: Array[Transform3D] = []
	var painted_c: Array[Color] = []
	for item in _painted:
		painted_xf.append(item[0])
		painted_c.append(item[1])
	_multimesh("BalconyRails", cube, painted_xf, painted_c, Materials.instance_colored(), true)
	_multimesh("BalconyFrames", cube, _frames, [], Materials.plain(FRAME_WHITE, 0.6), false)
	var glass_xf: Array[Transform3D] = []
	var glass_c: Array[Color] = []
	for item in _glass:
		glass_xf.append(item[0])
		glass_c.append(item[1])
	_multimesh("BalconyGlass", cube, glass_xf, glass_c, Materials.balcony_glass(), false)
	var limb := CylinderMesh.new()
	limb.top_radius = 0.32
	limb.bottom_radius = 0.5
	limb.height = 1.0
	limb.radial_segments = 6
	limb.rings = 1
	_multimesh("PoplarBranches", limb, _branches, [], Materials.plain(BARK, 0.95), true)
	var wire := CylinderMesh.new()
	wire.top_radius = 0.02
	wire.bottom_radius = 0.02
	wire.height = 1.0
	wire.radial_segments = 4
	wire.rings = 1
	_multimesh("Wires", wire, _wires, [], Materials.plain(Color(0.05, 0.05, 0.05), 0.5), false)

func _multimesh(name: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], material: Material, shadows: bool) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)



## Низкая трубная оградка, крашенная в красный и синий, по краю площадки — по её коллизии (черта 19, P3 15).
func _playground_fence(body: Node3D, size: Vector3) -> void:
	var colors := [Materials.plain(Color(0.62, 0.14, 0.10), 0.5), Materials.plain(Color(0.18, 0.30, 0.55), 0.5)]
	var top := -size.y * 0.5 + 0.75
	var i := 0
	for edge in [[Vector3(size.x, 0, 0), Vector3(0, 0, size.z * 0.5)], [Vector3(size.x, 0, 0), Vector3(0, 0, -size.z * 0.5)],
			[Vector3(0, 0, size.z), Vector3(size.x * 0.5, 0, 0)], [Vector3(0, 0, size.z), Vector3(-size.x * 0.5, 0, 0)]]:
		var along: Vector3 = edge[0]
		var at: Vector3 = edge[1]
		var material: Material = colors[i % 2]
		var rail := Greybox.mesh_box(Vector3(maxf(along.x, 0.05), 0.05, maxf(along.z, 0.05)), Color.WHITE)
		rail.material_override = material
		rail.position = at + Vector3(0, top, 0)
		body.add_child(rail)
		var n := int(along.length() / 1.5)
		for k in n + 1:
			var post := Greybox.mesh_box(Vector3(0.05, 0.75, 0.05), Color.WHITE)
			post.material_override = material
			post.position = at - along * 0.5 + along * (float(k) / n) + Vector3(0, top - 0.375, 0)
			body.add_child(post)
		i += 1

## Синие таблички с номером дома на углах (черта 16, P3 16).
func _build_house_plates() -> void:
	for spec in [["ул. Ленина, 12", Vector3(-88.5, 3.0, 107.95), PI], ["ул. Ленина, 14", Vector3(41.5, 3.0, 59.95), PI],
			["ул. Ленина, 9", Vector3(56.05, 3.0, 8.0), PI * 0.5], ["ул. Ленина, 11", Vector3(81.95, 3.0, 10.0), -PI * 0.5]]:
		var plate := Greybox.mesh_box(Vector3(1.6, 0.42, 0.04), Color.WHITE)
		plate.material_override = Materials.plain(Color(0.10, 0.22, 0.50), 0.5)
		plate.position = spec[1]
		plate.rotation.y = spec[2]
		add_child(plate)
		var label := _label(spec[0], 44, Color(0.95, 0.95, 0.95))
		label.position = spec[1] + Basis(Vector3.UP, spec[2]) * Vector3(0, 0, 0.03)
		label.rotation.y = spec[2]
		add_child(label)

## Знак остановки у площадки киоска: синий квадрат с белым автобусом на опоре контактной сети (черта 18, P3 17).
func _build_bus_stop() -> void:
	var pole: Vector2 = Layout.TROLLEY_POLES[2]
	var root := Node3D.new()
	root.name = "BusStopSign"
	root.position = Vector3(pole.x + 0.16, 2.7, pole.y)
	root.rotation.y = PI * 0.5   # к улице, на восток
	add_child(root)
	var board := Greybox.mesh_box(Vector3(0.6, 0.6, 0.03), Color.WHITE)
	board.material_override = Materials.plain(Color(0.08, 0.30, 0.62), 0.5)
	root.add_child(board)
	var white := Materials.plain(Color(0.95, 0.95, 0.95), 0.6)
	for part in [[Vector3(0.4, 0.2, 0.01), Vector3(0, 0.04, 0.02)], [Vector3(0.08, 0.08, 0.01), Vector3(-0.12, -0.1, 0.02)],
			[Vector3(0.08, 0.08, 0.01), Vector3(0.12, -0.1, 0.02)]]:
		var piece := Greybox.mesh_box(part[0], Color.WHITE)
		piece.material_override = white
		piece.position = part[1]
		root.add_child(piece)

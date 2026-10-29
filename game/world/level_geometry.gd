extends Node3D
## LevelGeometry: земля, здания, декор и покрытия из Layout (C1). Коллизии — простые коробки;
## внешний вид зимнего Новосибирска — процедурный (ART-02, ART-05 по сверке с фото ART-04): фасады с окнами,
## лоджиями и лестничными клетками, крыши, гаражи, грязные валы, тополя, фонари на консолях, контактная сеть.

const Layout = preload("res://game/world/layout.gd")
const Greybox = preload("res://game/world/greybox.gd")
const Materials = preload("res://game/world/materials.gd")
const Lighting = preload("res://game/world/lighting.gd")   # CITY-01 L: подсветка вывесок
const Patrols = preload("res://game/world/patrols.gd")   # EXT-01 N: полицейский, «военком», микроавтобус ГСУМ
const Buildings = preload("res://game/world/buildings.gd")   # CITY-02 B: дома, подъезды, крыши

const WALL_HEIGHT := 12.0
const WALL_THICKNESS := 2.0
const SHOP_FRONTS := ["H5_West", "H5_East", "H6_West", "H8_East"]
const SERIES_97 := ["H2_West", "H10_NorthWest", "H4_SouthEast"]   # голубые и серые полосы панелей (ART-06, Н10)
const GARAGE_DOOR_SIDE := {"Garages_Yard": -1.0, "Garages_Kiosk": 1.0, "Garages_C": 1.0}   # дверями к двору / к улице
# Ворота гаражей: синие, жёлтые, бурые, ржавые, розовые, зелёные (сверка ART-04, черта 17).
# Насыщеннее, чтобы в холодном сумеречном свете бурые и ржавые не уходили в серое (повторная сверка ART-05, Н2).
const GARAGE_COLORS := [Color(0.18, 0.32, 0.58), Color(0.78, 0.58, 0.12), Color(0.50, 0.22, 0.10), Color(0.60, 0.20, 0.07),
	Color(0.72, 0.40, 0.42), Color(0.30, 0.45, 0.10), Color(0.40, 0.42, 0.45)]   # бурые, ржавые, зелёные — по итоговой сверке (И2, И8)
const GARAGE_WALL := Color(0.50, 0.30, 0.22)   # кирпичные боксы (И2)
const WARM := Color(1.0, 0.75, 0.42)           # подъезд и окна
const SODIUM := Color(1.0, 0.74, 0.10)         # натриевые фонари, как в lighting.gd (итоговая сверка ART-06, С9)
const CONCRETE := Color(0.50, 0.51, 0.52)
const BARK := Color(0.16, 0.15, 0.14)
# Куржак — толстая изморозь на ветках (ART-06, Н8: крона #b9b5b2, `Trees, Novosibirsk 1.jpg`). Канон говорит
# «мокрый снег»; куржак добавлен решением владельца 28.10.2026.
const FROST := Color(0.88, 0.88, 0.90)   # светлее замера (#b9b5b2 днём): ночью в слабом свете иначе не читается
const ENTRANCE_WALL_Z := Buildings.ENTRANCE_WALL_Z   # северный фасад H1 (центр 115, глубина 14) — z = 108
const ENTRANCE_DOOR_X := Buildings.ENTRANCE_DOOR_X   # дверь по центру козырька

var _mound_mesh: SphereMesh       # одна сетка на все комки сугробов
var _chunk_mesh: SphereMesh       # сетка 14×6 для валов у дорог: комки чуть гранёные, но без острых глыб (И4, POLISH-02 п. 4)
# Экземпляры MultiMesh, которые собираются со всего квартала и строятся одним вызовом в конце:
# ветки, провода. Тысячи деталей без тысяч узлов и draw call. Дома — свои пакеты в _buildings (CITY-02 B).
var _buildings: Buildings = null
var _branches: Array[Transform3D] = []
var _wires: Array[Transform3D] = []
var _frost: Array[Transform3D] = []   # ветки в куржаке (ART-06, Н8; решение владельца 28.10.2026)

# Надписи: [текст, позиция, поворот y, размер шрифта, цвет].
const SIGNS := [
	# Номер подъезда — слева от двери (если смотреть со двора), Бабка — справа у двери (кадры 01, 02, 09).
	["3", Vector3(-38.75, 2.5, 107.93), PI, 90, Color(0.92, 0.92, 0.9)],
	["кв. 36–60", Vector3(-38.75, 2.18, 107.93), PI, 36, Color(0.92, 0.92, 0.9)],
	["АПТЕКА", Vector3(-79, 3.3, 14.05), 0.0, 120, Color(0.35, 1.0, 0.55)],   # H5_West (ARENA-01: H5 разделён улицей D)
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
	_build_chimneys()
	_build_instances()
	add_child(Patrols.new())   # EXT-01 N: наблюдатели и автобус (точки — Layout, C1)
	add_child(preload("res://game/world/traffic.gd").new())   # ARENA-01: транспорт кольца (C8)
	add_child(preload("res://game/world/residents.gd").new())   # PEOPLE-01: жители города Н.
	add_child(preload("res://game/world/ambient.gd").new())   # CITY-01 (A): вороны, собака, кошка, мусор
	add_child(preload("res://game/stealth/hide_spots.gd").new())   # EXT-02: укрытия у киоска (C7а)
	add_child(preload("res://game/world/coins.gd").new())   # COINS-01: монеты, 35 ₽ до батона
	add_child(preload("res://game/world/drones.gd").new())   # PUNCH-01: мини-дроны ГСУМ (петли — Layout.DRONE_LOOPS)

func _exit_tree() -> void:
	Materials.clear_cache()

# --- коллизии + вид ---

func _build_ground() -> void:
	var b := Layout.BOUNDS
	var center := Vector3(b.position.x + b.size.x * 0.5, -0.5, b.position.y + b.size.y * 0.5)
	var ground := Greybox.solid_box("Ground", center, Vector3(b.size.x, 1.0, b.size.y), Greybox.COLORS["ground"])
	(ground.get_child(1) as MeshInstance3D).material_override = Materials.snow(0.0)
	# Коллизия земли — бесконечная плоскость y = 0, а не плита 200×1×250: о плиту капсула Илюши изредка «залипала»
	# на ровном месте (STUCK, Poplar@(-28.4,101.7): скорость 4 м/с, все шесть скольжений — о Ground с нормалью вверх,
	# смещение 0). За краем карты стоят невидимые стены Bound_*, так что бесконечность плоскости не видна.
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.5)   # в координатах тела: центр плиты на y = −0,5
	(ground.get_child(0) as CollisionShape3D).shape = plane
	add_child(ground)

func _build_solid(index: int, spec: Array) -> void:
	var kind: String = spec[1]
	var xz: Vector2 = spec[2]
	var size: Vector3 = spec[3]
	var body := Greybox.solid_box(spec[0] if index < Layout.SOLIDS.size() else "%s_%d" % [spec[0], index], Vector3(xz.x, size.y * 0.5, xz.y), size, Greybox.COLORS.get(kind, Color.GRAY))
	var mesh := body.get_child(1) as MeshInstance3D
	match kind:
		"panel", "panel_low":
			_dress_house(spec[0], kind == "panel_low", xz, size, index, body, mesh)
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
			elif spec[0] == "Playground":
				# Не короб снега, а площадка за оградкой: горка, качели, песочница (POLISH-02, п. 15).
				mesh.queue_free()
				_playground_fence(body, size)
				body.add_child(_playground(xz, size))
			else:
				mesh.material_override = Materials.plain(Color(0.35, 0.25, 0.18))
		"parked_car":
			mesh.queue_free()
			body.add_child(_zhiguli(size, index))
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
		"pavilion":
			mesh.queue_free()
			# Павильон вдоль z (остановка улицы B, EXT-01): строится как «вдоль x» и поворачивается спиной на запад.
			# Вдоль x — остановка улицы A на северном тротуаре (ARENA-01 fix P2-1): открытой стороной на юг, к дороге.
			if size.z > size.x:
				body.add_child(_turned(_pavilion(_along_x(size)), -PI * 0.5))
			else:
				body.add_child(_turned(_pavilion(size), PI) if xz.y < Layout.RING[0].z else _pavilion(size))
		"sign_post":
			mesh.material_override = Materials.plain(Color(0.15, 0.15, 0.16), 0.6)
			for sign in Layout.STREET_SIGNS:
				if (sign[0] as Vector2).is_equal_approx(xz):
					var corner := Vector2.INF   # ближайший угол кольца: таблички висят в его сторону
					for c in Layout.RING:
						if xz.distance_to(Vector2(c.x, c.z)) < xz.distance_to(corner):
							corner = Vector2(c.x, c.z)
					body.add_child(_street_sign(size.y, sign[1], sign[2], (corner - xz).sign()))
		"shop24":
			mesh.queue_free()
			body.add_child(_shop24(size))
		"billboard":
			mesh.queue_free()
			var to := Vector2(Layout.RING[2].x, Layout.RING[2].z) - xz   # полотном к углу C∩D
			body.add_child(_turned(_billboard(size), atan2(to.x, to.y)))
		"fence":
			mesh.material_override = Materials.plain(Color(0.16, 0.24, 0.18), 0.7)
		"carpet_bar":
			mesh.queue_free()
			body.add_child(_carpet_post(size, xz == Layout.CARPET_BAR[0]))
		"bins":
			mesh.queue_free()
			# Контейнеры вдоль z (у гаражей киоска, EXT-01): крышки к площадке (восток), сугроб — к гаражам.
			body.add_child(_turned(_trash_bins(_along_x(size)), PI * 0.5) if size.z > size.x else _trash_bins(size))
	add_child(body)

## Размер коробки вдоль z, пересчитанный «как вдоль x» — для сборок, нарисованных вдоль x (павильон, контейнеры).
static func _along_x(size: Vector3) -> Vector3:
	return Vector3(size.z, size.y, size.x)

static func _turned(node: Node3D, yaw: float) -> Node3D:
	node.rotation.y = yaw
	return node

func _build_canopy() -> void:
	var canopy := Greybox.solid_box("Canopy", Layout.CANOPY[0], Layout.CANOPY[1], Greybox.COLORS["canopy"])
	# Снеговая шапка 0,18 м с видимым передним краем (сверка ART-04, черта 7).
	canopy.add_child(_slab(Layout.CANOPY[1], Vector3(0, Layout.CANOPY[1].y * 0.5 + 0.09, 0), 0.18))
	add_child(canopy)
	_houses().dress_canopy()   # кромка, снежный напуск, сосульки (CITY-02 B)

## Подъезд Бабки (кадры 01, 02, 09) — buildings.gd (CITY-02 B). Только вид, без коллизий.
func _build_entrance() -> void:
	_houses().build_entrance()

## Дома (CITY-02 B): узел Buildings создаётся при первом обращении — до него _ready строит только землю.
func _houses() -> Buildings:
	if _buildings == null:
		_buildings = Buildings.new(self)
		add_child(_buildings)
	return _buildings

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
	_build_corners()

## Углы кольца (ARENA-01): где улица вдоль x и улица вдоль z обе кончаются (L-образный стык), поверх их общего
## квадрата — плитка с колеями по дуге вокруг внутреннего угла. На краях плитки колеи и каша совпадают с прямыми
## улицами (road.gdshader, corner) — без шва. Т-образные стыки (A с B и D) не перекрываются и плитки не получают.
func _build_corners() -> void:
	var roads := Layout.SURFACES.filter(func(spec): return spec[1] == "road")
	for a in roads:
		var a_size: Vector2 = a[3]
		if a_size.x <= a_size.y:
			continue
		var xr := Rect2(a[2] - a_size * 0.5, a_size)
		for b in roads:
			var b_size: Vector2 = b[3]
			if b_size.x >= b_size.y:
				continue
			var zr := Rect2(b[2] - b_size * 0.5, b_size)
			var sq := xr.intersection(zr)
			if sq.get_area() < 1.0:
				continue
			var west := sq.position.x > xr.position.x + 0.01    # улица вдоль x продолжается на запад
			var east := sq.end.x < xr.end.x - 0.01
			var north := sq.position.y > zr.position.y + 0.01  # улица вдоль z продолжается на север
			var south := sq.end.y < zr.end.y - 0.01
			if west == east or north == south:
				continue   # не L-образный угол
			var corner := Vector2(sq.position.x if west else sq.end.x, sq.position.y if north else sq.end.y)
			var signs := Vector2(signf(a[2].y - corner.y), signf(b[2].x - corner.x))
			var mesh := Greybox.mesh_box(Vector3(sq.size.x, 0.01, sq.size.y), Greybox.COLORS["road"])
			mesh.name = "Corner_%s_%s" % [a[0], b[0]]
			mesh.position = Vector3(sq.get_center().x, 0.025, sq.get_center().y)
			mesh.material_override = Materials.road_corner(corner, signs, a_size.y)
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
		var lump := _mound(lump_size, material, material == Materials.snow_bank())
		lump.rotation = Vector3((r2 - 0.5) * 0.25, r1 * TAU, (r1 - 0.5) * 0.25) if material == Materials.snow_bank() else Vector3.ZERO
		var offset := -length * 0.5 + step * (i + 0.5)
		var jitter := (r2 - 0.5) * 0.3 * (size.z if long_x else size.x)
		lump.position += Vector3(offset, -size.y * 0.5 + lump_size.y * 0.5, jitter) if long_x else Vector3(jitter, -size.y * 0.5 + lump_size.y * 0.5, offset)
		root.add_child(lump)
		if r1 > 0.35:
			var chunk_size := Vector3(0.5 + 0.5 * r2, 0.35 + 0.3 * r1, 0.45 + 0.4 * r1)
			var chunk := _mound(chunk_size, material, material == Materials.snow_bank())
			var top := -size.y * 0.5 + lump_size.y * 0.85
			var shift := offset + (r1 - 0.5) * step
			chunk.position += Vector3(shift, top, -jitter) if long_x else Vector3(-jitter, top, shift)
			chunk.rotation.y = r2 * TAU
			root.add_child(chunk)
	return root

## Округлый сугроб, вписанный в коллизионную коробку (центр коробки — начало координат).
func _mound(size: Vector3, material: Material, rough := false) -> MeshInstance3D:
	if _mound_mesh == null:
		_mound_mesh = SphereMesh.new()
		_mound_mesh.radius = 0.5
		_mound_mesh.height = 1.0
		_mound_mesh.radial_segments = 24
		_mound_mesh.rings = 10
		_chunk_mesh = SphereMesh.new()
		_chunk_mesh.radius = 0.5
		_chunk_mesh.height = 1.0
		_chunk_mesh.radial_segments = 14   # округлее: на 8×4 вал читался тёмными гранёными глыбами (POLISH-02, п. 4)
		_chunk_mesh.rings = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = _chunk_mesh if rough else _mound_mesh
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
	if name == "Garages_C" and not long_z:
		_graffiti(body, size, count, unit, side)

## Граффити на воротах гаражного ряда улицы C (ARENA-01): мазки баллончиком под углом и короткие надписи,
## не на каждом боксе. Только вид, ряд вдоль x.
const SPRAY := [Color(0.92, 0.30, 0.62), Color(0.55, 0.85, 0.20), Color(0.20, 0.70, 0.85), Color(0.95, 0.55, 0.12), Color(0.92, 0.92, 0.90)]
const TAGS := ["ГОРОД Н", "ЗИМА", "54", "ДИМА + ЛЕНА", "ШКЯ"]   # «НСК» убран ради «города Н.» (решение владельца 28.10, приёмка EXT-01)
func _graffiti(body: Node3D, size: Vector3, count: int, unit: float, side: float) -> void:
	var face := side * (size.z * 0.5 + 0.07)
	for i in count:
		if _rand(i * 13, 3) > 0.6:
			continue
		var offset := -size.x * 0.5 + unit * (i + 0.5)
		for j in 1 + int(_rand(i * 13, 4) * 3.0):
			var color: Color = SPRAY[int(_rand(i * 13 + j, 5) * SPRAY.size()) % SPRAY.size()]
			var strip := Greybox.mesh_box(Vector3(unit * (0.35 + 0.5 * _rand(i + j, 6)), 0.07 + 0.12 * _rand(i * 3 + j, 7), 0.02), Color.WHITE)
			strip.material_override = Materials.plain(color, 0.7)
			strip.position = Vector3(offset + (_rand(i * 5 + j, 8) - 0.5) * unit * 0.5, -size.y * 0.5 + 0.5 + 1.6 * _rand(i * 7 + j, 9), face)
			strip.rotation.z = (_rand(i * 11 + j, 10) - 0.5) * 0.7
			body.add_child(strip)
		if _rand(i * 13, 11) < 0.45:
			var tag := _label(TAGS[i % TAGS.size()], 90, SPRAY[(i + 2) % SPRAY.size()])
			tag.pixel_size = 0.005
			tag.position = Vector3(offset, -size.y * 0.5 + 1.3 + 0.6 * _rand(i, 12), face + side * 0.01)
			tag.rotation = Vector3(0, 0.0 if side > 0.0 else PI, (_rand(i, 13) - 0.5) * 0.3)
			body.add_child(tag)

const LadaVisual = preload("res://game/vehicles/lada_visual.gd")
## Припаркованные «Жигули» (POLISH-02, п. 7): облик LadaVisual в цветах советских «Жигулей» —
## белый, красный, вишнёвый, синий, зелёный, бежевый, морская волна, серебристый, охра.
const ZHIGULI_COLORS := [Color(0.80, 0.79, 0.74), Color(0.62, 0.12, 0.08), Color(0.40, 0.08, 0.10), Color(0.16, 0.26, 0.48),
	Color(0.26, 0.40, 0.24), Color(0.74, 0.62, 0.40), Color(0.08, 0.30, 0.34), Color(0.62, 0.66, 0.70), Color(0.55, 0.40, 0.14)]
const PLATE_LETTERS := "авекмнорстух"

## Облик на земле внутри коробки коллизии (размер коробки не меняется); перед — в случайную сторону.
func _zhiguli(size: Vector3, index: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = index * 7919 + 13
	var color: Color = ZHIGULI_COLORS[index * 4 % ZHIGULI_COLORS.size()]   # шаг 4 из 9: соседние машины разного цвета
	var plate := "%s%03d%s%s %s" % [PLATE_LETTERS[rng.randi() % PLATE_LETTERS.length()], rng.randi_range(1, 999),
		PLATE_LETTERS[rng.randi() % PLATE_LETTERS.length()], PLATE_LETTERS[rng.randi() % PLATE_LETTERS.length()],
		"54" if rng.randf() < 0.5 else "154"]
	var visual := LadaVisual.build(color, plate, false, rng.randf_range(0.4, 1.0), rng.randf_range(0.12, 0.2))
	visual.position.y = -size.y * 0.5
	visual.rotation.y = (PI * 0.5 if size.x > size.z else 0.0) + (PI if rng.randf() < 0.5 else 0.0)
	return visual

func _kiosk(size: Vector3) -> Node3D:
	# Будка: окно на восток (к улице), внутри тёплый свет, полки с хлебом и продавщица (POLISH-02, п. 2).
	var root := Node3D.new()
	root.name = "KioskDress"
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
	_kiosk_inside(root, size)
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
	var bark := Materials.plain(FROST, 0.95)   # ветки берёзы в куржаке (Н8)
	for i in 6:
		var branch := Greybox.mesh_cylinder(0.02, 0.05, 2.2, Color.WHITE)
		branch.material_override = bark
		var angle := seed * 1.7 + i * 1.1
		branch.position = Vector3(cos(angle) * 0.6, height * (0.05 + i * 0.07), sin(angle) * 0.6)
		branch.rotation = Vector3(sin(angle) * 0.7, 0, -cos(angle) * 0.7)
		root.add_child(branch)
	return root

## Указатель на углу: табличка улицы вдоль x и поперёк неё — улицы вдоль z (Layout.STREET_SIGNS). Таблички висят
## сбоку от столба, к перекрёстку (side: знаки направления по x и z), и шириной по надписи: столб не закрывает
## буквы, надпись не вылезает за табличку (ARENA-01; раньше «УЛ. ЛЕНИНА» пересекал столб).
const SIGN_PIXEL := 0.0045
const SIGN_CHAR := 0.6 * SIGN_PIXEL   # ширина буквы на единицу кегля
func _street_sign(height: float, x_name: String, z_name: String, side: Vector2) -> Node3D:
	var root := Node3D.new()
	var blue := Materials.plain(Color(0.10, 0.20, 0.42), 0.5)
	for spec in [[x_name, height * 0.5 - 0.3, true], [z_name, height * 0.5 - 0.9, false]]:
		var text: String = spec[0]
		var font := mini(64, 12 * 64 / text.length())
		var w := text.length() * font * SIGN_CHAR + 0.3
		var along_x: bool = spec[2]
		var shift := (side.x if along_x else side.y) * (w * 0.5 + 0.08)
		var at := Vector3(shift, spec[1], 0) if along_x else Vector3(0, spec[1], shift)
		var plate := Greybox.mesh_box(Vector3(w, 0.5, 0.05) if along_x else Vector3(0.05, 0.5, w), Color.WHITE)
		plate.material_override = blue
		plate.position = at
		root.add_child(plate)
		for face: float in [1.0, -1.0]:
			var label := _label(text, font, Color(0.95, 0.95, 0.95))
			label.pixel_size = SIGN_PIXEL
			label.position = at + (Vector3(0, 0, 0.035 * face) if along_x else Vector3(0.035 * face, 0, 0))
			if along_x:
				label.rotation.y = 0.0 if face > 0.0 else PI
			else:
				label.rotation.y = PI * 0.5 if face > 0.0 else -PI * 0.5
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
		if spec[0] in LIT_SIGNS:
			_light_sign(label, spec[4])

## Вывеска с подсветкой (CITY-01 L): буквы ярче единицы — их подхватывает glow, и цветной отсвет на снег перед домом.
const LIT_SIGNS := ["АПТЕКА", "ПРОДУКТЫ", "ПРОДУКТЫ 24", "ГАСТРОНОМ"]
func _light_sign(label: Label3D, color: Color) -> void:
	# Насыщение перед усилением: filmic выбеливает яркое, без pow красное «ПРОДУКТЫ» уходило в розово-белое.
	var lit := Color(pow(color.r, 1.6), pow(color.g, 1.6), pow(color.b, 1.6)) * Lighting.SIGN_GLOW
	label.modulate = Color(lit.r, lit.g, lit.b)
	var spill := OmniLight3D.new()
	spill.name = label.name + "_Light"
	spill.light_color = color
	spill.light_energy = Lighting.SIGN_LIGHT_ENERGY
	spill.omni_range = Lighting.SIGN_LIGHT_RANGE
	spill.omni_attenuation = 1.6
	var facing := Vector3(sin(label.rotation.y), 0.0, cos(label.rotation.y))
	spill.position = label.position + facing * 1.2 - Vector3(0, 0.6, 0)
	add_child(spill)

## Вывеска-короб над окном киоска: светлый фон, простые красные буквы без обводки (сверка ART-04, черты 15, 16).
func _build_kiosk_sign() -> void:
	var board := Greybox.mesh_box(Vector3(0.22, 0.62, 3.7), Color.WHITE)
	board.name = "KioskSignBox"
	board.material_override = Materials.plain(Color(0.60, 0.58, 0.52), 0.6, Color(1.0, 0.93, 0.80), Lighting.KIOSK_SIGN_GLOW)   # световой короб, не пересвечен окном (Н4)
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
const WIRE_PAIR := 1.5   # контактные провода — ±1,5 м от оси улицы
func _build_wires() -> void:
	var wire := Materials.plain(Color(0.05, 0.05, 0.05), 0.5)
	var spans_a := Layout.a_spans()
	for x in spans_a:
		_sag_wire(Vector3(x, SPAN_Y, 22.0), Vector3(x, SPAN_Y, 42.0), 0.35, wire)
	for z in Layout.B_SPANS:
		_sag_wire(Vector3(Layout.LAMP_B_WEST, SPAN_Y, z), Vector3(Layout.LAMP_B_EAST, SPAN_Y, z), 0.3, wire)
	for z in Layout.D_SPANS:
		_sag_wire(Vector3(Layout.LAMP_D_WEST, SPAN_Y, z), Vector3(Layout.POLE_D_EAST, SPAN_Y, z), 0.3, wire)
	for x in Layout.C_SPANS:
		_sag_wire(Vector3(x, SPAN_Y, Layout.LAMP_C_NORTH), Vector3(x, SPAN_Y, Layout.POLE_C_SOUTH), 0.3, wire)
	# Улица A — насквозь; B, C и D — кольцом (ARENA-01): внутренний провод пары поворачивает во внутреннем углу,
	# внешний — во внешнем, на углах C∩D и C∩B провода оттянуты к угловым опорам. D примыкает к северному проводу A.
	var a0 := Layout.RING[0]   # A∩B
	var d0 := Layout.RING[1]   # A∩D
	var d1 := Layout.RING[2]   # C∩D
	var b1 := Layout.RING[3]   # C∩B
	for z in [a0.z - WIRE_PAIR, a0.z + WIRE_PAIR]:
		var run: Array[Vector2] = [Vector2(-100, z)]
		for x in spans_a:
			run.append(Vector2(x, z))
		run.append(Vector2(100, z))
		_wire_run(run, wire)
	for k: float in [-1.0, 1.0]:   # −1 — внутренний провод кольца, +1 — внешний
		var off := k * WIRE_PAIR
		var b_x := b1.x + off
		var c_z := b1.z - off
		var d_x := d1.x - off
		var run: Array[Vector2] = [Vector2(b_x, 25.0)]
		for z in Layout.B_SPANS:
			run.append(Vector2(b_x, z))
		run.append(Vector2(b_x, c_z))
		for i in range(Layout.C_SPANS.size() - 1, -1, -1):
			run.append(Vector2(Layout.C_SPANS[i], c_z))
		run.append(Vector2(d_x, c_z))
		for i in range(Layout.D_SPANS.size() - 1, -1, -1):
			run.append(Vector2(d_x, Layout.D_SPANS[i]))
		run.append(Vector2(d_x, d0.z - WIRE_PAIR))
		_wire_run(run, wire)
		for pole in Layout.CORNER_POLES:
			var corner := Vector3(b_x if pole.x > 0.0 else d_x, CONTACT_Y, c_z)
			_wire(Vector3(pole.x, Layout.POLE_HEIGHT - 0.4, pole.y), corner, wire)
	# Подвесы контактных проводов к поперечинам.
	for x in spans_a:
		for z in [a0.z - WIRE_PAIR, a0.z + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.33, z), wire)
	for z in Layout.B_SPANS:
		for x in [b1.x - WIRE_PAIR, b1.x + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.28, z), wire)
	for z in Layout.D_SPANS:
		for x in [d1.x - WIRE_PAIR, d1.x + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.28, z), wire)
	for x in Layout.C_SPANS:
		for z in [b1.z - WIRE_PAIR, b1.z + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.28, z), wire)
	# Бытовые провода во дворе: от дворового фонаря к H1 и H2.
	var yard_top := Vector3(-52.0, 5.9, 100.0)
	for target in [Vector3(-52.0, 7.5, 108.0), Vector3(-78.0, 7.5, 92.0), Vector3(-78.0, 7.2, 93.0)]:
		_sag_wire(yard_top, target, 0.5, wire)

## Контактный провод по точкам (x, z) на высоте CONTACT_Y с провисом между соседними.
func _wire_run(points: Array[Vector2], material: Material) -> void:
	for i in range(1, points.size()):
		_sag_wire(Vector3(points[i - 1].x, CONTACT_Y, points[i - 1].y), Vector3(points[i].x, CONTACT_Y, points[i].y), 0.22, material)

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

## Лоджии и балконы, окна с отливами, подъезды, цоколь, парапеты и крыши — buildings.gd (CITY-02 B).
## Только вид, без коллизий.
func _dress_house(name: String, low: bool, xz: Vector2, size: Vector3, index: int, body: Node3D, mesh: MeshInstance3D) -> void:
	_houses().dress_house(name, low, xz, size, index, body, mesh, name in SHOP_FRONTS, name in SERIES_97)

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
			_frost.append(_segment(from.lerp(bend, 0.35), bend, 0.34))   # куржак: ветка «вдвое толще» и белёсая
			for q in 3:
				var tw := from.lerp(bend, 0.4 + 0.3 * q)
				var tyaw := byaw + (_rand(seed * 97, 400 + i * 30 + j * 3 + q) - 0.5) * 3.0
				var tdir := Vector3(cos(tyaw) * 0.6, 0.8, sin(tyaw) * 0.6).normalized()
				_frost.append(_segment(tw, tw + tdir * (0.9 + 0.8 * _rand(seed * 97, 500 + q + j)), 0.26))   # с расстояния камеры тоньше не видно

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
		# Плоскость с мягкой рваной кромкой (POLISH-02, п. 19), а не коробка с резкими краями.
		var plane := PlaneMesh.new()
		plane.size = Vector2(p[2], a.distance_to(b))
		var mesh := MeshInstance3D.new()
		mesh.mesh = plane
		mesh.name = "Trail"
		mesh.material_override = Materials.trail(p[2], a.distance_to(b))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = Vector3((a.x + b.x) * 0.5, 0.024, (a.y + b.y) * 0.5)
		mesh.rotation.y = atan2(b.x - a.x, b.y - a.y)
		add_child(mesh)

## Общие MultiMesh: ветки, провода (тени — только у веток); дома — пакеты buildings.gd (CITY-02 B).
func _build_instances() -> void:
	_houses().build()   # лоджии, рамы, стёкла, снег, крыши, мелочь домов (CITY-02 B)
	var limb := CylinderMesh.new()
	limb.top_radius = 0.32
	limb.bottom_radius = 0.5
	limb.height = 1.0
	limb.radial_segments = 6
	limb.rings = 1
	_multimesh("PoplarBranches", limb, _branches, [], Materials.plain(BARK, 0.95), true)
	_multimesh("PoplarFrost", limb, _frost, [], Materials.plain(FROST, 0.95), false)
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

## Таблички с номером дома — buildings.gd (CITY-02 B).
func _build_house_plates() -> void:
	_houses().build_house_plates()

func _build_bus_stop() -> void:
	var pole: Vector2 = Layout.TROLLEY_POLES[2]
	var root := _stop_sign("BusStopSign", Vector3(pole.x + 0.16, 2.7, pole.y), PI * 0.5)   # к улице, на восток
	var pav: Vector2 = Layout.BUS_PAVILION[0]
	var pav_size: Vector3 = Layout.BUS_PAVILION[1]
	var at := Vector3(pav.x - pav_size.x * 0.5 - 0.4, 0.0, pav.y + pav_size.z * 0.5 + 0.5)
	var post := Greybox.mesh_cylinder(0.04, 0.04, 3.3, Color.BLACK)
	post.name = "BusStopSignAPost"
	post.material_override = Materials.plain(Color(0.15, 0.15, 0.16), 0.6)
	post.position = at + Vector3(0, 1.65, 0)
	add_child(post)
	var sign_a := _stop_sign("BusStopSignA", at + Vector3(0, 3.0, 0.05), PI * 0.5)   # над крышей павильона, на восток
	var route_plate := Greybox.mesh_box(Vector3(0.6, 0.26, 0.03), Color.WHITE)
	route_plate.material_override = Materials.plain(Color(0.92, 0.92, 0.90), 0.6)
	route_plate.position = Vector3(0, -0.48, 0)
	sign_a.add_child(route_plate)
	var route := _label("Тб 13", 40, Color(0.06, 0.08, 0.18))
	route.pixel_size = 0.004
	route.position = route_plate.position + Vector3(0, 0, 0.02)
	sign_a.add_child(route)
	# EXT-01 (DIALOGUES_AND_JOKES «Надписи»): табличка под знаком остановки у киоска — «ОСТАНОВКА ПО ТРЕБОВАНИЮ»,
	# мелко «НЕ ОБЯЗАТЕЛЬНО ВАШЕМУ». Микроавтобус ГСУМ после покупки встаёт рядом, на площадке (Layout.VAN_PATH[-1]).
	var plate := Greybox.mesh_box(Vector3(1.3, 0.42, 0.03), Color.WHITE)
	plate.material_override = Materials.plain(Color(0.90, 0.90, 0.86), 0.6)
	plate.position = Vector3(0.35, 0.62, 0)   # над знаком: ниже табличку закрывал бы павильон KioskPavilion
	root.add_child(plate)
	var big := _label("ОСТАНОВКА ПО ТРЕБОВАНИЮ", 34, Color(0.12, 0.12, 0.14))
	big.pixel_size = 0.0032
	big.position = plate.position + Vector3(0, 0.07, 0.02)
	root.add_child(big)
	var small := _label("НЕ ОБЯЗАТЕЛЬНО ВАШЕМУ", 22, Color(0.30, 0.30, 0.32))
	small.pixel_size = 0.0032
	small.position = plate.position + Vector3(0, -0.1, 0.02)
	root.add_child(small)

## Синий квадратный знак остановки с белым автобусом; лицом — локальная +z, повёрнут на yaw.
func _stop_sign(sign_name: String, at: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = sign_name
	root.position = at
	root.rotation.y = yaw
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
	return root

# --- ART-06: приметы именно Новосибирска ---

## Павильон остановки из профлиста: три стенки, крыша, лавка, объявления, табличка маршрутов (ART-06, Н6).
## Открыт на −z; к улице его поворачивает _build_solid. Облик ездящего троллейбуса — game/vehicles/trolleybus.gd.
func _pavilion(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var base := -size.y * 0.5
	var sheet := Materials.plain(Color(0.62, 0.65, 0.70), 0.5)   # профлист #9ea5b2
	_part(root, Vector3(size.x, size.y - 0.2, 0.05), Vector3(0, base + (size.y - 0.2) * 0.5, hz - 0.03), sheet)
	for x in [-hx + 0.03, hx - 0.03]:
		_part(root, Vector3(0.05, size.y - 0.2, size.z), Vector3(x, base + (size.y - 0.2) * 0.5, 0), sheet)
	_part(root, Vector3(size.x + 0.3, 0.1, size.z + 0.4), Vector3(0, base + size.y - 0.05, -0.1), sheet)
	_part(root, Vector3(size.x + 0.3, 0.16, size.z + 0.4), Vector3(0, base + size.y + 0.08, -0.1), Materials.snow(0.0))
	_part(root, Vector3(size.x - 0.4, 0.06, 0.4), Vector3(0, base + 0.5, hz - 0.3), Materials.plain(Color(0.36, 0.24, 0.15), 0.85))
	var paper := [Color(0.86, 0.85, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.72), Color(0.84, 0.78, 0.80)]
	for i in 7:
		var note := Greybox.mesh_box(Vector3(0.22, 0.3, 0.01), Color.WHITE)
		note.material_override = Materials.plain(paper[i % paper.size()], 0.95)
		note.position = Vector3(-hx + 0.4 + i * 0.5, base + 1.1 + (i % 3) * 0.32, hz - 0.06)
		root.add_child(note)
	# Табличка маршрутов по видам транспорта.
	var board := Greybox.mesh_box(Vector3(1.0, 0.55, 0.03), Color.WHITE)
	board.material_override = Materials.plain(Color(0.92, 0.92, 0.88), 0.6)
	board.position = Vector3(hx - 0.7, base + size.y + 0.45, -hz + 0.1)
	root.add_child(board)
	var routes := _label("Тб 13\nАвт. 31, 68\nМ.т. 1219", 30, Color(0.08, 0.10, 0.20))
	routes.pixel_size = 0.004
	routes.position = board.position + Vector3(0, 0, -0.025)
	routes.rotation.y = PI
	root.add_child(routes)
	return root

## Трубы ТЭЦ: красно-белые, с неподвижным шлейфом пара, на горизонте к северу (ART-06, Н4: снимает «не подтверждено»
## из ART-04). Только вид.
func _build_chimneys() -> void:
	# Туман съедал полосы (итоговая сверка ART-06, С2): материалы без тумана, дымка — в самом цвете
	# (красный и белый, смешанные с цветом тумана на ~40 %).
	var red := Materials.far(Color(0.50, 0.21, 0.20))
	var white := Materials.far(Color(0.62, 0.64, 0.66))
	var steam := Materials.far(Color(0.66, 0.68, 0.72, 0.55))
	# Две в перспективе улицы B, левее башни «ГОСТИНИЦА» (x 57–83), и третья на западе — видна от киоска (С4).
	for spec in [[Vector3(15, 0, -185), 80.0], [Vector3(35, 0, -200), 90.0], [Vector3(-150, 0, -95), 85.0]]:
		var at: Vector3 = spec[0]
		var height: float = spec[1]
		var bands := 10
		for i in bands:
			var y0 := height * i / bands
			var r_low := lerpf(4.0, 2.4, float(i) / bands)
			var r_high := lerpf(4.0, 2.4, float(i + 1) / bands)
			var band := Greybox.mesh_cylinder(r_high, r_low, height / bands, Color.WHITE)
			band.material_override = red if i % 2 == 0 else white
			band.position = at + Vector3(0, y0 + height / bands * 0.5, 0)
			add_child(band)
		var light := Greybox.mesh_sphere(0.8, Color.WHITE)
		light.material_override = Materials.far(Color(1.0, 0.15, 0.08))
		light.position = at + Vector3(0, height + 0.8, 0)
		add_child(light)
		for k in 7:
			var puff := Greybox.mesh_sphere(1.0, Color.WHITE)
			puff.material_override = steam
			var r := 4.0 + k * 2.2
			puff.scale = Vector3(r, r * 0.8, r)
			puff.position = at + Vector3(-k * 6.5, height + 3.0 + k * 1.6, -k * 1.5)   # пологий шлейф на запад, от башни (С2)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(puff)

## Пар из вытяжки на крыше: несколько полупрозрачных клубов, сносимых ветром (ART-06, Н9: `minus-28`).
func _steam_puff(parent: Node3D, at: Vector3, seed: int) -> void:
	var drift := Vector3(cos(seed * 1.7), 0, sin(seed * 1.7))
	for k in 4:
		var puff := Greybox.mesh_sphere(1.0, Color.WHITE)
		puff.material_override = Materials.steam()
		var r := 0.6 + k * 0.45
		puff.scale = Vector3(r, r * 0.8, r)
		puff.position = at + Vector3.UP * (k * 0.9) + drift * (k * 0.7)
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(puff)


# --- POLISH-02, п. 15: двор — площадка, выбивалка, контейнеры ---

## Труба from → to: цилиндр радиуса radius (только вид).
func _rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var rod := Greybox.mesh_cylinder(radius, radius, from.distance_to(to), Color.WHITE)
	rod.material_override = material
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.99 else Vector3.RIGHT).normalized()
	rod.basis = Basis(side, axis, side.cross(axis))
	rod.position = (from + to) * 0.5
	parent.add_child(rod)

## Детская площадка за оградкой (внутри коллизии Playground): советская металлическая горка, качели на
## А-образных стойках, песочница под снегом и сугробы у оградки. Начало координат — центр площадки на земле.
func _playground(xz: Vector2, size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "PlaygroundDress"
	root.position.y = -size.y * 0.5
	var red := Materials.plain(Color(0.62, 0.14, 0.10), 0.5)
	var yellow := Materials.plain(Color(0.80, 0.60, 0.12), 0.5)
	var blue := Materials.plain(Color(0.18, 0.30, 0.55), 0.5)
	var steel := Materials.plain(Color(0.58, 0.60, 0.62), 0.35)
	var wood := Materials.plain(Color(0.40, 0.27, 0.16), 0.85)
	# Горка: лестница с запада, площадка 1,5 м, жёлоб на восток.
	var s := Vector3(Layout.PLAYGROUND_SLIDE.x - xz.x, 0, Layout.PLAYGROUND_SLIDE.y - xz.y)
	var top := 1.9
	for zs in [-0.35, 0.35]:
		_rod(root, s + Vector3(-1.9, 0, zs), s + Vector3(-1.0, top + 0.9, zs), 0.04, red)   # тетива лестницы
		_rod(root, s + Vector3(-0.6, 0, zs), s + Vector3(-0.6, top + 0.9, zs), 0.04, red)    # задние стойки
		_rod(root, s + Vector3(-1.0, top, zs), s + Vector3(-1.0, top + 0.9, zs), 0.04, red)  # перила
		_rod(root, s + Vector3(-1.0, top + 0.9, zs), s + Vector3(-0.6, top + 0.9, zs), 0.04, red)
	for k in 5:
		var t := (k + 1) / 6.0 * top / (top + 0.9)   # доля тетивы до площадки
		var a := s + Vector3(-1.9 + 0.9 * t, (top + 0.9) * t, 0)
		_rod(root, a + Vector3(0, 0, -0.35), a + Vector3(0, 0, 0.35), 0.025, yellow)        # ступени
	_part(root, Vector3(0.5, 0.06, 0.8), s + Vector3(-0.8, top, 0), yellow)                  # площадка
	_part(root, Vector3(0.5, 0.06, 0.74), s + Vector3(-0.8, top + 0.06, 0), Materials.snow(0.0))
	var chute_from := s + Vector3(-0.55, top, 0)
	var chute_to := s + Vector3(2.0, 0.25, 0)
	var chute := Greybox.mesh_box(Vector3(chute_from.distance_to(chute_to), 0.04, 0.6), Color.WHITE)
	chute.material_override = steel
	chute.position = (chute_from + chute_to) * 0.5
	chute.rotation.z = atan2(chute_to.y - chute_from.y, chute_to.x - chute_from.x)
	root.add_child(chute)
	for zs in [-0.31, 0.31]:
		_rod(root, chute_from + Vector3(0, 0.12, zs), chute_to + Vector3(0, 0.12, zs), 0.025, blue)   # бортики
	_rod(root, chute_to + Vector3(-0.1, 0, -0.25), chute_to + Vector3(-0.1, -0.25, -0.25), 0.03, blue)
	_rod(root, chute_to + Vector3(-0.1, 0, 0.25), chute_to + Vector3(-0.1, -0.25, 0.25), 0.03, blue)
	# Качели: две А-стойки, перекладина 2,2 м, два сиденья на цепях; под качелями снег вытоптан.
	var w := Vector3(Layout.PLAYGROUND_SWINGS.x - xz.x, 0, Layout.PLAYGROUND_SWINGS.y - xz.y)
	var bar_y := 2.2
	for xs in [-1.3, 1.3]:
		for zs in [-0.75, 0.75]:
			_rod(root, w + Vector3(xs, 0, zs), w + Vector3(xs, bar_y, 0), 0.05, red)
	_rod(root, w + Vector3(-1.4, bar_y, 0), w + Vector3(1.4, bar_y, 0), 0.05, red)
	var chain := Materials.plain(Color(0.25, 0.25, 0.26), 0.5)
	for xs in [-0.6, 0.6]:
		for zs in [-0.22, 0.22]:
			_rod(root, w + Vector3(xs + zs, bar_y, 0), w + Vector3(xs + zs, 0.48, 0), 0.012, chain)
		_part(root, Vector3(0.55, 0.05, 0.25), w + Vector3(xs, 0.46, 0), wood)
		_part(root, Vector3(0.5, 0.03, 0.2), w + Vector3(xs, 0.5, 0), Materials.snow(0.0))
	_part(root, Vector3(2.4, 0.01, 1.2), w + Vector3(0, 0.01, 0), Materials.snow(0.9))
	# Песочница под снегом: деревянная рамка и сугроб внутри.
	var b := Vector3(-3.2, 0, -2.6)
	for e in [[Vector3(2.0, 0.25, 0.1), Vector3(0, 0.125, 0.95)], [Vector3(2.0, 0.25, 0.1), Vector3(0, 0.125, -0.95)],
			[Vector3(0.1, 0.25, 2.0), Vector3(0.95, 0.125, 0)], [Vector3(0.1, 0.25, 2.0), Vector3(-0.95, 0.125, 0)]]:
		_part(root, e[0], b + e[1], wood)
	var heap := _mound(Vector3(1.8, 0.35, 1.8), Materials.snow(0.0))
	heap.position += b + Vector3(0, 0.175, 0)
	root.add_child(heap)
	# Сугробы вдоль оградки — снег сгребали с дорожек внутрь.
	for i in 4:
		var drift := _mound(Vector3(2.2 + 0.6 * _rand(i, 1), 0.3 + 0.2 * _rand(i, 2), 0.9), Materials.snow(0.0))
		drift.position += Vector3(-4.5 + i * 3.0, 0.2, size.z * 0.5 - 0.6)
		root.add_child(drift)
	return root

## Стойка турника-выбивалки для ковров (кадр двора по ART-04: «выбивалка» у каждого дома). Первая стойка несёт
## перекладину до второй и висящий на ней ковёр. Стойки — коллизия Layout.CARPET_BAR, между ними можно пройти.
func _carpet_post(size: Vector3, first: bool) -> Node3D:
	var root := Node3D.new()
	var paint := Materials.plain(Color(0.20, 0.34, 0.30), 0.6)
	var base := -size.y * 0.5
	_rod(root, Vector3(0, base, 0), Vector3(0, base + size.y, 0), 0.05, paint)
	if not first:
		return root
	var span: Vector2 = Layout.CARPET_BAR[1] - Layout.CARPET_BAR[0]
	var to := Vector3(span.x, 0, span.y)
	var bar_y := base + size.y - 0.12
	_rod(root, Vector3(0, bar_y, 0), to + Vector3(0, bar_y, 0), 0.035, paint)
	_rod(root, Vector3(0, base + 1.1, 0), to + Vector3(0, base + 1.1, 0), 0.03, paint)
	_part(root, Vector3(0.12, 0.05, span.length() + 0.1), to * 0.5 + Vector3(0, bar_y + 0.06, 0), Materials.snow(0.0))
	# Ковёр, перекинутый через перекладину: бордовый с узорной полосой, свисает на обе стороны.
	var rug := Materials.plain(Color(0.48, 0.10, 0.10), 0.95)
	var border := Materials.plain(Color(0.78, 0.62, 0.30), 0.9)
	for side in [-1.0, 1.0]:
		var panel := Node3D.new()
		panel.position = to * 0.5 + Vector3(0, bar_y, 0)
		panel.rotation.z = side * 0.12
		root.add_child(panel)
		_part(panel, Vector3(0.03, 1.15, 1.7), Vector3(side * 0.07, -0.58, 0), rug)
		_part(panel, Vector3(0.035, 0.08, 1.7), Vector3(side * 0.07, -0.95, 0), border)
		_part(panel, Vector3(0.035, 0.6, 0.08), Vector3(side * 0.07, -0.55, 0.6), border)
		_part(panel, Vector3(0.035, 0.6, 0.08), Vector3(side * 0.07, -0.55, -0.6), border)
	return root

## Три мусорных контейнера на бетонной площадке у проезда: крашеный металл, крышки с шапкой снега, ржавые пятна.
func _trash_bins(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var base := -size.y * 0.5
	_part(root, Vector3(size.x + 0.8, 0.08, size.z + 0.8), Vector3(0, base + 0.04, 0), Materials.plain(Color(0.42, 0.42, 0.41), 0.9))
	var colors := [Color(0.20, 0.36, 0.24), Color(0.28, 0.34, 0.42), Color(0.22, 0.38, 0.26)]
	var rust := Materials.plain(Color(0.42, 0.22, 0.10), 0.9)
	var unit := size.x / 3.0
	for i in 3:
		var x := -size.x * 0.5 + unit * (i + 0.5)
		var metal := Materials.plain(colors[i], 0.6)
		var h := size.y - 0.2
		_part(root, Vector3(unit - 0.15, h, size.z - 0.1), Vector3(x, base + 0.08 + h * 0.5, 0), metal)
		_part(root, Vector3(unit - 0.05, 0.05, 0.08), Vector3(x, base + 0.08 + h - 0.15, size.z * 0.5), metal)   # ручка-обвязка
		var lid := Greybox.mesh_box(Vector3(unit - 0.1, 0.06, size.z), Color.WHITE)
		lid.material_override = Materials.plain(colors[i].darkened(0.35), 0.6)
		lid.position = Vector3(x, base + 0.08 + h + 0.04, 0)
		lid.rotation.x = -0.12 if i == 1 else 0.0   # средняя крышка приоткрыта
		root.add_child(lid)
		var cap := _mound(Vector3(unit - 0.25, 0.1, size.z - 0.3), Materials.snow(0.0))
		cap.position += Vector3(x, base + 0.08 + h + 0.08, 0)
		cap.rotation.x = lid.rotation.x
		root.add_child(cap)
		_part(root, Vector3(0.35 + 0.2 * _rand(i, 7), 0.25, 0.02), Vector3(x + 0.2 * (i - 1), base + 0.4, size.z * 0.5 - 0.03), rust)
	# Сугроб у задней стенки и пакет мусора рядом.
	var heap := _lumpy_bank(Vector3(size.x, 0.5, 0.8), Materials.snow(0.3), 41)
	heap.position = Vector3(0, base + 0.25, -size.z * 0.5 - 0.5)
	root.add_child(heap)
	return root

# --- POLISH-02, п. 2: живой киоск (концепты 06–08) ---

## Внутри киоска: светлая задняя стенка, полки с батонами и буханками у задней и боковых стен, прилавок,
## лампочка в окне и ценник «Батон 35». Продавщица стоит посередине (Layout.VENDOR) — полки по краям и за ней.
## Снаружи: плакат «СВЕЖИЙ ХЛЕБ» и объявления на боковых стенах. Хлеб на полках — декор киоска; у Илюши руки
## пустые, покупка — только флаг has_bread (раздел 2 канона).
func _kiosk_inside(root: Node3D, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var floor_y := -hy
	_part(root, Vector3(0.02, size.y - 0.4, size.z - 0.25), Vector3(-hx + 0.11, floor_y + (size.y - 0.4) * 0.5 + 0.1, 0),
		Materials.plain(Color(0.86, 0.78, 0.62), 0.9, WARM, 0.18))   # тёплая светлая стенка за полками
	var wood := Materials.plain(Color(0.52, 0.36, 0.20), 0.8)
	var batons: Array[Transform3D] = []
	var baton_c: Array[Color] = []
	var bricks: Array[Transform3D] = []
	var brick_c: Array[Color] = []
	var golden := [Color(0.82, 0.55, 0.24), Color(0.76, 0.48, 0.20), Color(0.86, 0.62, 0.30)]
	var rye := [Color(0.40, 0.22, 0.12), Color(0.48, 0.28, 0.14)]
	var shelf_y := [1.0, 1.45, 1.9]   # от пола
	# Задний стеллаж: три полки по всей ширине.
	var back_x := -hx + 0.34
	for s in shelf_y.size():
		var y: float = floor_y + shelf_y[s]
		_part(root, Vector3(0.46, 0.04, size.z - 0.3), Vector3(back_x, y, 0), wood)
		var z := -hz + 0.35
		var k := 0
		while z < hz - (0.3 if s == 0 else 0.62):
			if s == 0:
				# Нижняя полка — буханки: чёрный и белый «кирпичик» вперемешку.
				bricks.append(Transform3D(Basis.from_scale(Vector3(0.24, 0.13, 0.12)), Vector3(back_x + 0.05, y + 0.085, z)))
				brick_c.append(rye[k % 2] if k % 3 != 2 else golden[1])
				z += 0.15
			else:
				# Батоны лежат вдоль полки боком к окну, в два ряда; задний ряд выше, со сдвигом.
				var along := Basis.from_euler(Vector3(PI * 0.5, 0, 0)) * Basis.from_scale(Vector3(1.0, 1.0, 0.8))
				batons.append(Transform3D(along, Vector3(back_x + 0.1, y + 0.065, z + 0.2)))
				baton_c.append(golden[(k + s) % golden.size()])
				batons.append(Transform3D(along, Vector3(back_x - 0.06, y + 0.11, z + 0.05)))
				baton_c.append(golden[(k + s + 1) % golden.size()])
				z += 0.42
			k += 1
	# Боковые стеллажи у северной и южной стен, ближе к окну: видны по краям окна, продавщица — между ними.
	for zs in [-1.0, 1.0]:
		var rack_z: float = zs * (hz - 0.33)
		for s in shelf_y.size():
			var y: float = floor_y + shelf_y[s]
			_part(root, Vector3(1.5, 0.04, 0.4), Vector3(0.55, y, rack_z), wood)
			var x := -0.1
			var k := 0
			while x < 1.25:
				if s == 1:
					bricks.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.13, 0.24)), Vector3(x, y + 0.085, rack_z)))
					brick_c.append(golden[k % 2] if k % 2 == 0 else rye[0])
					x += 0.15
				else:
					batons.append(Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)) * Basis.from_scale(Vector3(0.8, 0.9, 1.0)), Vector3(x, y + 0.055, rack_z)))   # торцом к окну
					baton_c.append(golden[(k + s + 1) % golden.size()])
					x += 0.13
				k += 1
		_part(root, Vector3(0.04, 1.2, 0.04), Vector3(-0.22, floor_y + 1.45, rack_z + zs * 0.18), wood)
		_part(root, Vector3(0.04, 1.2, 0.04), Vector3(1.32, floor_y + 1.45, rack_z + zs * 0.18), wood)
	var baton_mesh := CapsuleMesh.new()
	baton_mesh.radius = 0.055
	baton_mesh.height = 0.36
	baton_mesh.radial_segments = 8
	baton_mesh.rings = 2
	_kiosk_multimesh(root, "KioskBatons", baton_mesh, batons, baton_c)
	_kiosk_multimesh(root, "KioskLoaves", BoxMesh.new(), bricks, brick_c)
	# Прилавок изнутри: столешница под окном и весы.
	_part(root, Vector3(0.5, 0.04, size.z - 0.3), Vector3(hx - 0.32, floor_y + 1.0, 0), Materials.plain(Color(0.62, 0.58, 0.50), 0.6))
	_part(root, Vector3(0.22, 0.1, 0.3), Vector3(hx - 0.3, floor_y + 1.07, -1.25), Materials.plain(Color(0.85, 0.85, 0.82), 0.4))
	# Лампочка на шнуре в окне, правее продавщицы, если смотреть с улицы (кадр 07), и её тёплый свет.
	var bulb_at := Vector3(hx - 0.6, floor_y + 2.12, -0.95)   # ниже короба рольставни (2,3 м)
	_rod(root, Vector3(bulb_at.x, hy - 0.05, bulb_at.z), bulb_at + Vector3(0, 0.08, 0), 0.008, Materials.plain(Color(0.1, 0.1, 0.1), 0.6))
	var bulb := Greybox.mesh_sphere(0.07, Color.WHITE)
	bulb.material_override = Materials.plain(Color(1.0, 0.92, 0.7), 0.3, Color(1.0, 0.82, 0.5), 8.0)
	bulb.position = bulb_at
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)
	var bulb_light := OmniLight3D.new()
	bulb_light.light_color = Color(1.0, 0.78, 0.45)
	bulb_light.light_energy = 0.9
	bulb_light.omni_range = 3.0
	bulb_light.position = bulb_at + Vector3(0.15, -0.1, 0)
	root.add_child(bulb_light)
	# Ценник «Батон 35» за стеклом, в правом нижнем углу окна (если смотреть с улицы).
	var tag_at := Vector3(hx - 0.07, floor_y + 1.2, 1.35)
	_part(root, Vector3(0.01, 0.2, 0.32), tag_at, Materials.plain(Color(0.95, 0.94, 0.88), 0.9))
	var tag := _label("Батон\n35 р.", 40, Color(0.12, 0.10, 0.10))
	tag.pixel_size = 0.0028
	tag.alpha_cut = Label3D.ALPHA_CUT_DISCARD   # за прозрачным стеклом: без сортировки прозрачных
	tag.position = tag_at + Vector3(0.008, 0, 0)
	tag.rotation.y = PI * 0.5
	root.add_child(tag)
	_kiosk_walls(root, size)

func _kiosk_multimesh(root: Node3D, name: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = mm
	instance.material_override = Materials.instance_colored()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

## Снаружи на боковых стенах: плакат «СВЕЖИЙ ХЛЕБ КАЖДЫЙ ДЕНЬ» с батоном на южной стене (к подходу с улицы B)
## и россыпь бумажных объявлений на обеих стенах, как на столбах (_notices) и у подъезда.
func _kiosk_walls(root: Node3D, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var face := hz + 0.06
	# Плакат: светлая бумага, крупные тёмно-красные буквы, батон под надписью.
	var poster_at := Vector3(-0.55, -hy + 1.75, face)
	_part(root, Vector3(1.05, 1.3, 0.01), poster_at, Materials.plain(Color(0.90, 0.86, 0.74), 0.95))
	var text := _label("СВЕЖИЙ\nХЛЕБ", 80, Color(0.45, 0.06, 0.04))
	text.pixel_size = 0.0028
	text.shaded = true
	text.position = poster_at + Vector3(0, 0.3, 0.012)
	root.add_child(text)
	var daily := _label("каждый день", 40, Color(0.20, 0.14, 0.10))
	daily.pixel_size = 0.0028
	daily.shaded = true
	daily.position = poster_at + Vector3(0, -0.1, 0.012)
	root.add_child(daily)
	var loaf := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.5
	cap.height = 2.6
	loaf.mesh = cap
	loaf.material_override = Materials.plain(Color(0.80, 0.52, 0.22), 0.7)
	loaf.scale = Vector3(0.28, 0.1, 0.03)
	loaf.rotation.z = PI * 0.5
	loaf.position = poster_at + Vector3(0, -0.42, 0.012)
	root.add_child(loaf)
	# Объявления: [сторона z, x, y от пола, ширина, высота, наклон].
	var paper := [Color(0.86, 0.85, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.72), Color(0.92, 0.80, 0.78), Color(0.95, 0.95, 0.92)]
	var notes := [
		[1.0, 0.55, 1.95, 0.30, 0.40, 0.05], [1.0, 0.95, 1.55, 0.24, 0.32, -0.08], [1.0, 0.45, 1.25, 0.34, 0.24, 0.0],
		[1.0, 1.45, 1.9, 0.22, 0.30, 0.1], [1.0, -1.6, 1.3, 0.26, 0.36, -0.04], [1.0, -1.75, 1.95, 0.22, 0.22, 0.12],
		[-1.0, -1.2, 1.7, 0.36, 0.48, 0.03], [-1.0, -0.6, 1.95, 0.24, 0.30, -0.1], [-1.0, -0.2, 1.4, 0.30, 0.40, 0.06],
		[-1.0, 0.5, 1.8, 0.26, 0.34, 0.0], [-1.0, 1.1, 1.3, 0.22, 0.30, -0.06], [-1.0, 1.5, 2.0, 0.30, 0.22, 0.08],
	]
	for i in notes.size():
		var n: Array = notes[i]
		var note := Greybox.mesh_box(Vector3(n[3], n[4], 0.01), Color.WHITE)
		note.material_override = Materials.plain(paper[i % paper.size()], 0.95)
		note.position = Vector3(n[1], -hy + n[2], n[0] * (face + 0.002 * (i % 3)))
		note.rotation.z = n[5]
		root.add_child(note)
		# На части объявлений — строки «текста» тёмными полосками.
		if i % 2 == 0:
			for line in 3:
				var bar := Greybox.mesh_box(Vector3(n[3] * 0.7, 0.018, 0.004), Color.WHITE)
				bar.material_override = Materials.plain(Color(0.25, 0.25, 0.28), 0.9)
				bar.position = note.position + Vector3(0, n[4] * 0.25 - line * n[4] * 0.22, n[0] * 0.007)
				bar.rotation.z = n[5]
				root.add_child(bar)

# --- ARENA-01: детали вдоль улиц C и D ---

## Павильон «ПРОДУКТЫ 24» у улицы D (ART-04: ночной магазинчик у дороги): сэндвич-панели, витрина в решётке и дверь
## на запад, к улице, светящийся короб вывески, снег на крыше. Без интерактива; коллизия — коробка Layout.SHOP24.
func _shop24(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var base := -size.y * 0.5
	var wall_h := size.y - 0.15
	var panel := Materials.plain(Color(0.80, 0.82, 0.80), 0.7)
	var trim := Materials.plain(Color(0.20, 0.36, 0.30), 0.6)
	var iron := Materials.plain(Color(0.15, 0.15, 0.16), 0.5)
	_part(root, Vector3(size.x, wall_h, size.z), Vector3(0, base + wall_h * 0.5, 0), panel)
	_part(root, Vector3(size.x + 0.1, 0.3, size.z + 0.1), Vector3(0, base + 0.15, 0), trim)   # цоколь
	var glass_w := size.z - 1.7
	var glass_z := hz - 0.3 - glass_w * 0.5
	_part(root, Vector3(0.05, 1.4, glass_w), Vector3(-hx - 0.03, base + 1.5, glass_z), Materials.plain(Color(1.0, 0.86, 0.62), 0.3, WARM, 1.4))
	for k in 5:
		_part(root, Vector3(0.04, 1.4, 0.04), Vector3(-hx - 0.08, base + 1.5, glass_z - glass_w * 0.5 + glass_w * k / 4.0), iron)
	_part(root, Vector3(0.04, 0.04, glass_w), Vector3(-hx - 0.08, base + 1.5, glass_z), iron)
	_part(root, Vector3(0.06, 2.05, 0.9), Vector3(-hx - 0.03, base + 1.03, -hz + 0.65), Materials.plain(Color(0.30, 0.22, 0.16), 0.6))   # дверь
	_part(root, Vector3(0.9, 0.12, 1.4), Vector3(-hx - 0.45, base + 0.06, -hz + 0.65), Materials.plain(Color(0.46, 0.46, 0.45), 0.9))   # крыльцо
	var red := Color(0.50, 0.07, 0.05)
	_part(root, Vector3(0.22, 0.62, size.z + 0.2), Vector3(-hx - 0.11, base + wall_h + 0.2, 0), Materials.plain(red, 0.5, red, 0.5))
	var sign := _label("ПРОДУКТЫ 24", 90, Color(1.0, 0.85, 0.35))
	sign.pixel_size = 0.0042
	sign.position = Vector3(-hx - 0.23, base + wall_h + 0.2, 0)
	sign.rotation.y = -PI * 0.5
	root.add_child(sign)
	var paper := [Color(0.86, 0.85, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.72)]
	for i in 3:   # объявления на южной стене
		_part(root, Vector3(0.24, 0.32, 0.01), Vector3(-hx + 0.8 + i * 0.45, base + 1.3 + (i % 2) * 0.3, hz + 0.01), Materials.plain(paper[i], 0.95))
	_part(root, Vector3(size.x + 0.3, 0.06, size.z + 0.3), Vector3(0, base + wall_h + 0.03, 0), trim)
	root.add_child(_slab(Vector3(size.x + 0.2, 0, size.z + 0.2), Vector3(0, base + wall_h + 0.15, 0), 0.18))
	var heap := _lumpy_bank(Vector3(0.9, 0.6, size.z * 0.8), Materials.snow(0.15), 91)
	heap.position = Vector3(hx + 0.45, base + 0.3, 0)
	root.add_child(heap)
	return root

## Рекламный щит 6 × 3 м на одной опоре с пустым полотном: серо-белое полотно с обрывками старых плакатов, стальная
## рама, мостик расклейщика, снег на верхней кромке. Коллизия — только опора (Layout.BILLBOARD). Полотно лицом к +z.
func _billboard(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var base := -size.y * 0.5
	var steel := Materials.plain(Color(0.30, 0.31, 0.33), 0.5)
	var leg := Greybox.mesh_cylinder(0.22, 0.28, 7.2, Color.WHITE)
	leg.material_override = steel
	leg.position = Vector3(0, base + 3.6, 0)
	root.add_child(leg)
	var mid := base + 8.7
	_part(root, Vector3(6.3, 3.3, 0.35), Vector3(0, mid, 0), steel)
	var canvas := Materials.plain(Color(0.86, 0.86, 0.83), 0.9)
	var scrap := Materials.plain(Color(0.66, 0.64, 0.58), 0.95)
	for side: float in [-1.0, 1.0]:
		_part(root, Vector3(6.0, 3.0, 0.02), Vector3(0, mid, side * 0.19), canvas)
		for i in 4:
			var r := _rand(i * 7 + int(side + 1.0), 5)
			_part(root, Vector3(0.25 + 0.6 * r, 0.12 + 0.5 * _rand(i, 9), 0.01), Vector3(-2.4 + i * 1.5 + r * 0.5, mid - 1.0 + 1.8 * _rand(i * 3, 2), side * 0.205), scrap)
	_part(root, Vector3(6.3, 0.06, 0.9), Vector3(0, mid - 1.75, 0.45), steel)
	root.add_child(_slab(Vector3(6.3, 0, 0.35), Vector3(0, mid + 1.72, 0), 0.14))
	return root

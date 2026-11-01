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
const EnvDress = preload("res://game/world/environment_dress.gd")   # CITY-02 E: валы, деревья, тротуары, провода
const Skyline = preload("res://game/world/skyline.gd")   # CITY-02 E: панорама за краем карты
const Perimeter = preload("res://game/world/perimeter.gd")
const SnowField = preload("res://game/world/snow_field.gd")   # DRIVE-02 (C10): форма валов для вида и колёс

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
const ENTRANCE_WALL_Z := Buildings.ENTRANCE_WALL_Z   # северный фасад H1 (центр 115, глубина 14) — z = 108
const ENTRANCE_DOOR_X := Buildings.ENTRANCE_DOOR_X   # дверь по центру козырька

## Заставка меню сохраняет город и транспорт, но не создаёт персонажей и игровые награды.
var presentation_only := false

# Экземпляры MultiMesh, которые собираются со всего квартала и строятся одним вызовом в конце: провода.
# Тысячи деталей без тысяч узлов и draw call. Дома — свои пакеты в _buildings (CITY-02 B); деревья, бордюры,
# снег на проводах, столбы — пакеты _environment (CITY-02 E); панорама — _skyline.
var _buildings: Buildings = null
var _environment: EnvDress = null
var _skyline: Skyline = null
var _vent_steam: Array[Vector3] = []   # устья вытяжек на крышах (_steam_puff)
var _wires: Array[Transform3D] = []
var _wire_owners: Array = []           # BREAK-03: id столбов провода _wires[i] ([] — ничей)
var _wire_extra: Array = []            # BREAK-03: id, которым принадлежат следующие провода (подвесы пролёта)

## BREAK-03 (C11): облик окружения, которое ломается, — id (Layout.env_breakables) → {"nodes": узлы, которые падают
## вместе с объектом, "mm": [[MultiMesh, индекс, Transform3D экземпляра, узел MultiMeshInstance3D]], "cut": узлы,
## которые прячутся, пока объект сломан (бельё между деревьями), "wires": [[MultiMesh, индекс, Transform3D, [id]]] —
## провода, которые висят, только пока целы все их столбы}. Читает Breakables.
var break_visuals := {}
var _pole_ids := {}                    # Vector2i(x·10, z·10) столба → id

## Запись облика id в break_visuals (создаётся при первом обращении).
static func break_entry(registry: Dictionary, id: StringName) -> Dictionary:
	if not registry.has(id):
		registry[id] = {"nodes": [], "mm": [], "cut": [], "wires": []}
	return registry[id]

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
	add_child(Perimeter.new())
	_build_canopy()
	_build_entrance()
	_build_surfaces()
	add_child(preload("res://game/world/crosswalks.gd").new())
	_build_bounds()
	_build_signs()
	_build_kiosk_sign()
	_build_kiosk_roof_sign()
	_build_wires()
	_build_trails()
	_build_yard_piles()
	_build_house_plates()
	_build_bus_stop()
	_build_skyline()
	_build_chimneys()
	_houses().build_store_entrances()
	_build_instances()
	if not presentation_only:
		add_child(Patrols.new())   # EXT-01 N: наблюдатели и автобус (точки — Layout, C1)
	var traffic := preload("res://game/world/traffic.gd").new()
	traffic.occupants_enabled = not presentation_only
	add_child(traffic)   # ARENA-01: транспорт кольца (C8)
	if not presentation_only:
		add_child(preload("res://game/world/residents.gd").new())   # PEOPLE-01: жители города Н.
	add_child(preload("res://game/world/ambient.gd").new())   # CITY-01 (A): вороны, собака, кошка, мусор
	add_child(preload("res://game/world/wind_bags.gd").new())
	add_child(preload("res://game/world/winter_grime.gd").new())
	add_child(preload("res://game/stealth/hide_spots.gd").new())   # EXT-02: укрытия у киоска (C7а)
	if not presentation_only:
		add_child(preload("res://game/world/coins.gd").new())   # COINS-01: монеты, 35 ₽ до батона
		add_child(preload("res://game/world/drones.gd").new())   # PUNCH-01: мини-дроны ГСУМ (петли — Layout.DRONE_LOOPS)
	add_child(preload("res://game/world/props.gd").new())   # PROPS-01: новые объекты арены (ARENA-02)
	add_child(preload("res://game/world/breakables.gd").new())   # BREAK-01: разрушаемые объекты (Layout.BREAKABLES)

func _exit_tree() -> void:
	Materials.clear_cache()
	EnvDress.clear_cache()

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
	# These boxes are slices of continuous structures, even when one slice is small.
	if kind in ["perimeter_wall", "perimeter_shutter", "perimeter_train", "perimeter_gangway"]:
		body.set_meta(&"camera_occluder", true)
	# BREAK-03 (C11): окружение, которое ломается, — здесь только облик; коллизию слоя 6 строит Breakables, облик
	# (узел и экземпляры пакетов EnvDress) записан в break_visuals под id записи.
	var breakable: Array = Layout.env_break_at(index)
	if not breakable.is_empty():
		body.collision_layer = 0
		(body.get_child(0) as CollisionShape3D).disabled = true
		break_entry(break_visuals, breakable[0])["nodes"].append(body)
		_env().owners = [breakable[0]]
		if breakable[1] in [&"lamp", &"pole", &"lamp_yard"]:
			_pole_ids[_pole_key(xz)] = breakable[0]
	_build_solid_look(index, spec, body)
	_env().owners = []

## Ключ столба по центру (x/z с точностью 0,1 м) — для владельцев проводов.
static func _pole_key(xz: Vector2) -> Vector2i:
	return Vector2i(roundi(xz.x * 10.0), roundi(xz.y * 10.0))

func _build_solid_look(index: int, spec: Array, body: StaticBody3D) -> void:
	var kind: String = spec[1]
	var xz: Vector2 = spec[2]
	var size: Vector3 = spec[3]
	var mesh := body.get_child(1) as MeshInstance3D
	match kind:
		"perimeter_train", "perimeter_gangway", "perimeter_police", "perimeter_sign", "perimeter_pedestal":
			mesh.queue_free() # Rendered once by Perimeter; collision remains canonical.
		"perimeter_wall":
			mesh.material_override = Materials.plain(Color(0.41, 0.43, 0.42))
		"perimeter_shutter":
			mesh.material_override = Materials.plain(Color(0.19, 0.25, 0.25), 0.6)
		"perimeter_barrier":
			mesh.material_override = Materials.plain(Color(0.78, 0.78, 0.72))
		"panel", "panel_low":
			_dress_house(spec[0], kind == "panel_low", xz, size, index, body, mesh)
		"garage":
			mesh.queue_free()
			_garage_row(body, spec[0], size)
		"snow", "snow_bank":
			mesh.queue_free()
			body.collision_layer = 64   # DRIVE-02 (C10): слой 7 «SnowBank» — стена пешеходам, «Лада» едет по SnowField
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
			body.add_child(_zhiguli(size, index, xz))
		"kiosk":
			mesh.queue_free()
			body.add_child(_kiosk(size))
		"lamp":
			mesh.material_override = Materials.plain(Color(0.12, 0.12, 0.13), 0.6)
			if spec[0] == "StreetLamp" or spec[0] == "TrolleyPole":
				body.add_child(_street_pole(size.y, Layout.lamp_arm(xz) if spec[0] == "StreetLamp" else Vector2.ZERO))
			else:
				body.add_child(_lamp_head(size.y))
			if spec[0] != "Lamp_Yard":
				_notices(body, size, index)
		"tree":
			mesh.queue_free()
			body.add_child(_birch(size.y, float(index), Vector3(xz.x, 0, xz.y)))
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
	var lift := {"yard_road": 0.01, "sidewalk": 0.015}
	for spec in Layout.SURFACES:
		if spec[1] == "road":
			continue
		var xz: Vector2 = spec[2]
		var size: Vector2 = spec[3]
		var mesh := Greybox.mesh_box(Vector3(size.x, 0.01, size.y), Greybox.COLORS[spec[1]])
		mesh.name = spec[0]
		mesh.position = Vector3(xz.x, lift[spec[1]], xz.y)
		mesh.material_override = Materials.snow(0.7 if spec[1] == "sidewalk" else 0.9)
		add_child(mesh)
	add_child(preload("res://game/world/road_surface.gd").create())
	_env().street_dress()   # бордюры, наледь, проталины, люки (CITY-02 E)

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

## Вал снега у дороги или сугроб (CITY-02 E): одна сетка вместо комков-сфер — комья на гребне, крутой срез со
## стороны дороги, ступени лопаты со двора, корка сверху. Форма — SnowField.profile (DRIVE-02, C10): по ней же едут
## колёса «Лады». У дороги — брызги колёс и грязная кромка у низа (snow_bank_mesh.gdshader; ART-04, черта 10: серые
## и бурые валы, у проезжей части почти чёрные гребни). Коробка Layout (SnowField.boxes: тот же seed и размер) берёт
## оттуда сторону дороги; прочие кучи (у подъездов, контейнеров) — без неё. Начало координат — центр коробки.
func _lumpy_bank(size: Vector3, material: Material, seed: int) -> Node3D:
	var root := Node3D.new()
	var long_x := size.x >= size.z
	var toward := 0.0
	for b in SnowField.boxes():
		if b[3] == seed and (b[1] as Vector3).is_equal_approx(size):
			toward = b[4]
	var mesh := MeshInstance3D.new()
	mesh.name = "SnowMesh"
	mesh.mesh = EnvDress.bank_mesh(size.x if long_x else size.z, size.z if long_x else size.x, size.y, seed, toward)
	mesh.material_override = Materials.bank_snow(1.0) if (material == Materials.snow_bank() or toward != 0.0) else material
	mesh.position.y = -size.y * 0.5
	if not long_x:
		mesh.rotation.y = PI * 0.5   # +z сетки — к +x мира, x сетки — к −z (SnowField.box_height)
	root.add_child(mesh)
	return root

## Округлый сугроб, вписанный в коллизионную коробку (центр коробки — начало координат): купол с рваной кромкой
## и буграми (EnvDress.dome_mesh, CITY-02 E) вместо полусферы; вариант шума — по размеру. rough — другой вариант.
func _mound(size: Vector3, material: Material, rough := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var variant := int(absf(size.x * 7.0 + size.z * 13.0 + size.y * 31.0)) + (1 if rough else 0)
	mesh.mesh = EnvDress.dome_mesh(variant)
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
	# Кирпичные боксы с распашными воротами разного цвета, номера краской (сверка ART-04, черта 17).
	var wall := Materials.plain(GARAGE_WALL, 0.9)
	var k := EnvDress.kit()
	var near := EnvDress.kit()
	var depth := size.x if long_z else size.z
	var face := side * (depth * 0.5)
	# Бокс у «Жигулей» (17; 80) распахнут — его строит PROPS-01 (props.gd): там без замка и хлама.
	var open_box := -1
	if name == "Garages_Yard":
		var best := 0
		for i in count:
			if absf(-length * 0.5 + unit * (i + 0.5) + body.position.z - 80.5) < absf(-length * 0.5 + unit * (best + 0.5) + body.position.z - 80.5):
				best = i
		open_box = best
	var on_square := name == "Garages_Kiosk"   # ворота на площадку киоска: только плоское (ARENA-02, «Что не делать», 1)
	for i in count:
		var offset := -length * 0.5 + unit * (i + 0.5)
		var color: Color = GARAGE_COLORS[(i * 5 + name.length() * 3) % GARAGE_COLORS.size()]
		var tone := 0.85 + 0.3 * fposmod(sin(float(i) * 7.31 + name.length()) * 43758.5, 1.0)
		var box := Greybox.mesh_box(Vector3(size.x, size.y, unit - 0.12) if long_z else Vector3(unit - 0.12, size.y, size.z), Color.WHITE)
		box.material_override = wall
		box.position = Vector3(0, 0, offset) if long_z else Vector3(offset, 0, 0)
		body.add_child(box)
		var leaf_material := Materials.plain(Color(color.r * tone, color.g * tone, color.b * tone), 0.55)
		var leaf_w := unit * 0.39
		for half: float in [-1.0, 1.0]:
			var along := offset + half * (leaf_w * 0.5 + 0.02)
			var leaf := Greybox.mesh_box(Vector3(0.05, size.y * 0.72, leaf_w) if long_z else Vector3(leaf_w, size.y * 0.72, 0.05), Color.WHITE)
			leaf.material_override = leaf_material
			leaf.position = _gpos(long_z, along, -size.y * 0.12, side * (depth * 0.5 + 0.03))
			body.add_child(leaf)
		var gate_top := -size.y * 0.12 + size.y * 0.36
		# Номер краской на верху створок (LIFE-02: прежде — над воротами, под козырьком шифера, и кромка с сосульками
		# срезала верх цифр с игровой камеры).
		var number := _label(str(i * 3 + 11 + name.length()), 72, Color(0.92, 0.92, 0.88))
		number.pixel_size = 0.0045
		number.position = _gpos(long_z, offset, gate_top - 0.3, side * (depth * 0.5 + 0.075))
		number.rotation.y = (PI * 0.5 if side > 0.0 else -PI * 0.5) if long_z else (0.0 if side > 0.0 else PI)
		body.add_child(number)
		var r1 := _rand(i * 31 + name.length(), 1)
		var r2 := _rand(i * 31 + name.length(), 2)
		# Бетонная перемычка над воротами, стальная рама-уголок (CITY-02 E).
		EnvDress.kit_box(k, _gsize(long_z, unit - 0.1, 0.2, 0.1), _gpos(long_z, offset, gate_top + 0.12, face + side * 0.05), Color(0.55, 0.55, 0.53), Color(0, 0.95, 0, 0))
		for e: float in [-1.0, 1.0]:
			EnvDress.kit_box(k, _gsize(long_z, 0.05, size.y * 0.74, 0.04), _gpos(long_z, offset + e * (leaf_w + 0.06), -size.y * 0.12, face + side * 0.04), Color(0.16, 0.16, 0.17), Color(0, 0.6, 0, 0))
			# Петли и ржавые потёки под ними.
			for hy: float in [0.35, -0.55]:
				EnvDress.kit_box(near, _gsize(long_z, 0.12, 0.05, 0.03), _gpos(long_z, offset + e * (leaf_w - 0.02), -size.y * 0.12 + hy, face + side * 0.07), Color(0.18, 0.17, 0.16), Color(0, 0.6, 0, 0))
				if r1 > 0.4:
					EnvDress.kit_box(near, _gsize(long_z, 0.03, 0.35 + 0.3 * r2, 0.005), _gpos(long_z, offset + e * (leaf_w - 0.02), -size.y * 0.12 + hy - 0.22, face + side * 0.058), Color(0.40, 0.20, 0.08), Color(0, 0.95, 0, 0))
		if i != open_box:
			# Проушины и навесной замок на шве створок, поперечный засов.
			EnvDress.kit_box(near, _gsize(long_z, 0.14, 0.05, 0.03), _gpos(long_z, offset, -0.28, face + side * 0.07), Color(0.20, 0.20, 0.21), Color(0, 0.5, 0, 0))
			EnvDress.kit_box(near, _gsize(long_z, 0.065, 0.085, 0.035), _gpos(long_z, offset, -0.37, face + side * 0.09), Color(0.62, 0.52, 0.22) if r2 > 0.5 else Color(0.30, 0.31, 0.32), Color(3.0, 0.4, 0, 0))
			EnvDress.kit_box(near, _gsize(long_z, leaf_w * 1.1, 0.06, 0.03), _gpos(long_z, offset - leaf_w * 0.3, 0.1, face + side * 0.07), Color(0.17, 0.17, 0.18), Color(0, 0.5, 0, 0))
		# Шифер: листы с волной поверх плоской крыши, напуск 0,3 м над воротами, лёгкий уклон назад.
		var sheet := Color(0.56, 0.57, 0.55).darkened(0.25 * r1)
		EnvDress.kit_box(k, _gsize(long_z, unit + 0.04, 0.035, depth + 0.45), _gpos(long_z, offset, size.y * 0.5 + 0.03, side * 0.2), sheet,
			Color(1.0, 0.92, 0, 0), Vector3(0, 0, -side * 0.03) if long_z else Vector3(side * 0.03, 0, 0))
		# Снег на крыше: слой и бугры, карниз-напуск над воротами и сосульки.
		EnvDress.kit_snow(k, _gsize(long_z, unit, 0.16, depth + 0.2), _gpos(long_z, offset, size.y * 0.5 + 0.13, side * 0.15))
		EnvDress.kit_lump(k, _gsize(long_z, unit * 0.9, 0.12 + 0.12 * r2, depth * 0.7), _gpos(long_z, offset + (r1 - 0.5) * 0.6, size.y * 0.5 + 0.2, (r2 - 0.5) * depth * 0.4), r1 * TAU)
		EnvDress.kit_snow(k, _gsize(long_z, unit, 0.12, 0.25), _gpos(long_z, offset, size.y * 0.5 + 0.1, face + side * 0.33), Vector3(side * 0.25, 0, 0) if long_z else Vector3(-side * 0.25, 0, 0))
		var eave := face + side * 0.42
		var ia := _gpos(long_z, offset - unit * 0.48, size.y * 0.5 + 0.0, eave)
		var ib := _gpos(long_z, offset + unit * 0.48, size.y * 0.5 + 0.0, eave)
		EnvDress.kit_icicles(near, ia, ib, 0.45, i * 17 + name.length())
		# Снег у ворот: намело к створкам; часть боксов откопана — там утоптанная площадка.
		if r1 < 0.6 or on_square:
			EnvDress.kit_lump(k, _gsize(long_z, unit * 0.85, 0.22 + (0.0 if on_square else 0.2 * r2), 0.9), _gpos(long_z, offset, -size.y * 0.5, face + side * 0.35), r2 * 0.4)
		if not on_square and i != open_box and r2 < 0.38:
			_garage_clutter(near, long_z, offset, face, side, size.y, i * 13 + name.length())
	body.add_child(_slab(Vector3(size.x, 0.0, size.z), Vector3(0, size.y * 0.5 + 0.04, 0), 0.06))
	EnvDress.kit_emit(k, body, "GarageDress")
	EnvDress.kit_emit(near, body, "GarageNear", 60.0)
	if on_square and long_z and side > 0.0:
		# CROSS-01: краска на последнем южном боксе, ниже номера; существующая парковка остаётся прежней.
		var parking := _label(QuestLines.PARKING_SIGN, 56, Color(0.92, 0.90, 0.77))
		parking.name = "ParkingSign"
		parking.pixel_size = 0.0045
		parking.shaded = true
		parking.position = _gpos(long_z, length * 0.5 - unit * 0.5, -size.y * 0.17, face + side * 0.076)
		parking.rotation.y = PI * 0.5
		body.add_child(parking)
	if name == "Garages_C" and not long_z:
		_graffiti(body, size, count, unit, side)

## Граффити на воротах гаражного ряда улицы C (ARENA-01): мазки баллончиком под углом и короткие надписи,
## не на каждом боксе. Только вид, ряд вдоль x. LIFE-02 (сверка: «жёсткие цветные бруски читаются как парящие доски»):
## мазок — плоская полоса краски толщиной 4 мм прямо на створках (пакет EnvDress, без тени), не шире ворот и не выше
## их верха (номер — над мазками), под мазком — потёки краски.
const SPRAY := [Color(0.92, 0.30, 0.62), Color(0.55, 0.85, 0.20), Color(0.20, 0.70, 0.85), Color(0.95, 0.55, 0.12), Color(0.92, 0.92, 0.90)]
const TAGS := ["ГОРОД Н", "ЗИМА", "54", "ДИМА + ЛЕНА", "ШКЯ"]   # «НСК» убран ради «города Н.» (решение владельца 28.10, приёмка EXT-01)
const SPRAY_DEPTH := 0.004     # м: краска на створке
func _graffiti(body: Node3D, size: Vector3, count: int, unit: float, side: float) -> void:
	var face := side * (size.z * 0.5 + 0.055 + SPRAY_DEPTH * 0.5)   # лицевая сторона створок — side · (глубина/2 + 0,055)
	var gate_half := unit * 0.39                                      # створка — unit · 0,39, ворота — две створки
	var low := -size.y * 0.48 + 0.45                                  # над снегом, наметённым к воротам
	var high := size.y * 0.24 - 0.55                                  # ниже номера на верху створок
	var k := EnvDress.kit()
	for i in count:
		if _rand(i * 13, 3) > 0.6:
			continue
		var offset := -size.x * 0.5 + unit * (i + 0.5)
		for j in 1 + int(_rand(i * 13, 4) * 3.0):
			var color: Color = SPRAY[int(_rand(i * 13 + j, 5) * SPRAY.size()) % SPRAY.size()]
			var length := gate_half * (0.6 + 0.9 * _rand(i + j, 6))
			var thick := 0.05 + 0.07 * _rand(i * 3 + j, 7)
			var tilt := (_rand(i * 11 + j, 10) - 0.5) * 0.45
			var spread := maxf(gate_half * 0.95 - length * 0.5, 0.0)
			var at := Vector3(offset + (_rand(i * 5 + j, 8) - 0.5) * 2.0 * spread, lerpf(low, high, _rand(i * 7 + j, 9)), face)
			EnvDress.kit_box(k, Vector3(length, thick, SPRAY_DEPTH), at, color, Color(0, 0.75, 0, 0), Vector3(0, 0, tilt))
			for d in 2:   # потёки: тонкие струйки вниз от мазка
				var along := (_rand(i * 17 + j * 3 + d, 14) - 0.5) * length * 0.8
				var drip := 0.06 + 0.16 * _rand(i * 19 + j * 5 + d, 15)
				var from := at + Vector3(along * cos(tilt), along * sin(tilt) - thick * 0.5 - drip * 0.5, 0.0)
				EnvDress.kit_box(k, Vector3(0.012, drip, SPRAY_DEPTH), from, color, Color(0, 0.75, 0, 0))
		if _rand(i * 13, 11) < 0.45:
			var tag := _label(TAGS[i % TAGS.size()], 90, SPRAY[(i + 2) % SPRAY.size()])
			tag.pixel_size = 0.005
			tag.position = Vector3(offset, lerpf(low, high, 0.3 + 0.5 * _rand(i, 12)), face + side * 0.006)
			tag.rotation = Vector3(0, 0.0 if side > 0.0 else PI, (_rand(i, 13) - 0.5) * 0.3)
			body.add_child(tag)
	EnvDress.kit_emit(k, body, "Graffiti", 60.0)

const LadaVisual = preload("res://game/vehicles/lada_visual.gd")
## Припаркованные «Жигули» (POLISH-02, п. 7): облик LadaVisual в цветах советских «Жигулей» —
## белый, красный, вишнёвый, синий, зелёный, бежевый, морская волна, серебристый, охра.
const ZHIGULI_COLORS := [Color(0.80, 0.79, 0.74), Color(0.62, 0.12, 0.08), Color(0.40, 0.08, 0.10), Color(0.16, 0.26, 0.48),
	Color(0.26, 0.40, 0.24), Color(0.74, 0.62, 0.40), Color(0.08, 0.30, 0.34), Color(0.62, 0.66, 0.70), Color(0.55, 0.40, 0.14)]
const PLATE_LETTERS := "авекмнорстух"

## Облик на земле внутри коробки коллизии (размер коробки не меняется); перед — в случайную сторону. LIFE-02: машина
## «мужика под капотом» (Layout.LIFE_HOOD_CAR) — всегда передом (−z облика) на север, к месту hood: поднятый капот
## (Residents._build_life_props) над моторным отсеком, а не над багажником.
func _zhiguli(size: Vector3, index: int, xz := Vector2.INF) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = index * 7919 + 13
	var color: Color = ZHIGULI_COLORS[index * 4 % ZHIGULI_COLORS.size()]   # шаг 4 из 9: соседние машины разного цвета
	var plate := "%s%03d%s%s %s" % [PLATE_LETTERS[rng.randi() % PLATE_LETTERS.length()], rng.randi_range(1, 999),
		PLATE_LETTERS[rng.randi() % PLATE_LETTERS.length()], PLATE_LETTERS[rng.randi() % PLATE_LETTERS.length()],
		"54" if rng.randf() < 0.5 else "154"]
	var visual := LadaVisual.build(color, plate, false, rng.randf_range(0.4, 1.0), rng.randf_range(0.12, 0.2))
	visual.position.y = -size.y * 0.5
	visual.rotation.y = (PI * 0.5 if size.x > size.z else 0.0) + (PI if rng.randf() < 0.5 else 0.0)
	if xz.distance_to(Layout.LIFE_HOOD_CAR) < 0.1:
		visual.rotation.y = HOOD_CAR_YAW
	return visual

## Поворот облика машины под капотом: перед облика — −z, то есть на север, к мужику (Layout.LIFE_SPOTS, hood).
const HOOD_CAR_YAW := 0.0

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
	Lighting.configure_local_shadow(inside)
	root.add_child(inside)
	_kiosk_outside(root, size)
	return root

func _lamp_head(height: float) -> Node3D:
	var head := Greybox.mesh_box(Vector3(0.5, 0.18, 0.3), Color.WHITE)
	head.material_override = Materials.plain(Color(0.2, 0.2, 0.2), 0.5, SODIUM, 4.0)
	head.position = Vector3(0, height * 0.5 - 0.1, 0)
	return head

## Берёза (CITY-02 E): белый ствол с чечевичками и чёрным низом, подъёмистые сучья, свисающие ветки в куржаке —
## пакеты EnvDress (мировые координаты base). Узел-заглушка остаётся ребёнком коробки коллизии.
func _birch(height: float, seed: float, base := Vector3.ZERO) -> Node3D:
	_env().birch(base, height, seed)
	return Node3D.new()

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
	Lighting.configure_local_shadow(spill)
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

## POLISH-03 A: световой короб «ХЛЕБ» на крыше киоска (Layout.KIOSK_ROOF_SIGN) — ориентир с парковки и с юга, как
## на концепте 07: тёплый светящийся короб, тёмно-красные буквы; буквы и с северной стороны. Без коллизий — обзор
## постов (DetectionSensor, слой World) не меняется. Две стойки до крыши и тёплый отсвет на снег перед киоском.
const ROOF_SIGN_GLOW := 1.4
func _build_kiosk_roof_sign() -> void:
	var size := Layout.KIOSK_ROOF_SIGN_SIZE
	var at := Layout.KIOSK_ROOF_SIGN
	var board := Greybox.mesh_box(size, Color.WHITE)
	board.name = "KioskRoofSignBox"
	board.material_override = Materials.plain(Color(0.78, 0.70, 0.52), 0.6, Color(1.0, 0.82, 0.52), ROOF_SIGN_GLOW)
	board.position = at
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(board)
	var frame := Materials.plain(Color(0.16, 0.20, 0.17), 0.7)
	var rim := Greybox.mesh_box(Vector3(size.x + 0.12, 0.08, size.z + 0.06), Color.WHITE)
	rim.name = "KioskRoofSignRim"
	rim.material_override = frame
	rim.position = at + Vector3(0, size.y * 0.5 + 0.04, 0)
	add_child(rim)
	var roof_top := 3.32   # крыша с козырьком Layout «Kiosk» (высота 3,2) + 0,12
	for sx in [-1.0, 1.0]:
		var post := Greybox.mesh_box(Vector3(0.08, at.y - size.y * 0.5 - roof_top, 0.08), Color.WHITE)
		post.material_override = frame
		post.position = Vector3(at.x + sx * (size.x * 0.5 - 0.4), (at.y - size.y * 0.5 + roof_top) * 0.5, at.z)
		add_child(post)
	for side in [0.0, PI]:
		var sign := Label3D.new()
		sign.name = "KioskRoofSign" if side == 0.0 else "KioskRoofSignBack"
		sign.text = "ХЛЕБ"
		sign.font_size = 150
		sign.pixel_size = 0.0058
		sign.modulate = Color(0.45, 0.04, 0.02)
		sign.outline_size = 0
		sign.shaded = false
		sign.rotation.y = side   # 0 — лицом на юг (+z), к парковке
		sign.position = at + Vector3(0, 0, (size.z * 0.5 + 0.01) * (1.0 if side == 0.0 else -1.0))
		add_child(sign)
	var spill := OmniLight3D.new()
	spill.name = "KioskRoofSignLight"
	spill.light_color = Color(1.0, 0.78, 0.45)
	spill.light_energy = 1.2
	spill.omni_range = 5.5
	spill.omni_attenuation = 1.4
	spill.position = at + Vector3(0, -0.2, 1.1)
	Lighting.configure_local_shadow(spill)
	add_child(spill)

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
		var supports: Array = [[]]   # край карты; следующий узел держится на своей поперечине
		for x in spans_a:
			run.append(Vector2(x, z))
			supports.append(_wire_poles(Vector3(x, 0, 22.0), Vector3(x, 0, 42.0)))
		run.append(Vector2(100, z))
		supports.append([])
		_wire_run(run, wire, supports)
	for k: float in [-1.0, 1.0]:   # −1 — внутренний провод кольца, +1 — внешний
		var off := k * WIRE_PAIR
		var b_x := b1.x + off
		var c_z := b1.z - off
		var d_x := d1.x - off
		var run: Array[Vector2] = [Vector2(b_x, 25.0)]
		var supports: Array = [[]]
		for z in Layout.B_SPANS:
			run.append(Vector2(b_x, z))
			supports.append(_wire_poles(Vector3(Layout.LAMP_B_WEST, 0, z), Vector3(Layout.LAMP_B_EAST, 0, z)))
		run.append(Vector2(b_x, c_z))
		supports.append(_corner_wire_poles(true))
		for i in range(Layout.C_SPANS.size() - 1, -1, -1):
			var x: float = Layout.C_SPANS[i]
			run.append(Vector2(x, c_z))
			supports.append(_wire_poles(Vector3(x, 0, Layout.LAMP_C_NORTH), Vector3(x, 0, Layout.POLE_C_SOUTH)))
		run.append(Vector2(d_x, c_z))
		supports.append(_corner_wire_poles(false))
		for i in range(Layout.D_SPANS.size() - 1, -1, -1):
			var z: float = Layout.D_SPANS[i]
			run.append(Vector2(d_x, z))
			supports.append(_wire_poles(Vector3(Layout.LAMP_D_WEST, 0, z), Vector3(Layout.POLE_D_EAST, 0, z)))
		run.append(Vector2(d_x, d0.z - WIRE_PAIR))
		supports.append([])
		_wire_run(run, wire, supports)
		for pole in Layout.CORNER_POLES:
			var corner := Vector3(b_x if pole.x > 0.0 else d_x, CONTACT_Y, c_z)
			_wire(Vector3(pole.x, Layout.POLE_HEIGHT - 0.4, pole.y), corner, wire)
	# Подвесы контактных проводов к поперечинам (BREAK-03: висят, пока целы оба столба поперечины).
	for x in spans_a:
		_wire_extra = _wire_poles(Vector3(x, 0, 22.0), Vector3(x, 0, 42.0))
		for z in [a0.z - WIRE_PAIR, a0.z + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.33, z), wire)
		_wire_extra = []
	for z in Layout.B_SPANS:
		_wire_extra = _wire_poles(Vector3(Layout.LAMP_B_WEST, 0, z), Vector3(Layout.LAMP_B_EAST, 0, z))
		for x in [b1.x - WIRE_PAIR, b1.x + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.28, z), wire)
		_wire_extra = []
	for z in Layout.D_SPANS:
		_wire_extra = _wire_poles(Vector3(Layout.LAMP_D_WEST, 0, z), Vector3(Layout.POLE_D_EAST, 0, z))
		for x in [d1.x - WIRE_PAIR, d1.x + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.28, z), wire)
		_wire_extra = []
	for x in Layout.C_SPANS:
		_wire_extra = _wire_poles(Vector3(x, 0, Layout.LAMP_C_NORTH), Vector3(x, 0, Layout.POLE_C_SOUTH))
		for z in [b1.z - WIRE_PAIR, b1.z + WIRE_PAIR]:
			_wire(Vector3(x, CONTACT_Y, z), Vector3(x, SPAN_Y - 0.28, z), wire)
		_wire_extra = []
	# Бытовые провода во дворе: от дворового фонаря к H1 и H2.
	var yard_top := Vector3(-52.0, 5.9, 100.0)
	for target in [Vector3(-52.0, 7.5, 108.0), Vector3(-78.0, 7.5, 92.0), Vector3(-78.0, 7.2, 93.0)]:
		_sag_wire(yard_top, target, 0.5, wire)
	# Бытовые провода вдоль тротуаров (ART-04, черта 13: «по 4–5 проводов» с провисом; CITY-02 E): между соседними
	# фонарями одной стороны улицы — три провода на 5,4–6,0 м. Питание киоска — провод от опоры у площадки.
	var lamps := Layout.street_lamps()
	for i in lamps.size():
		for j in range(i + 1, lamps.size()):
			var a: Vector2 = lamps[i]
			var b: Vector2 = lamps[j]
			var d := a.distance_to(b)
			if (absf(a.x - b.x) > 0.1 and absf(a.y - b.y) > 0.1) or d < 10.0 or d > 30.0:
				continue
			for k in 3:
				var h := 5.4 + 0.3 * k
				_sag_wire(Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), 0.32 + 0.12 * _rand(i * 7 + k, 2), wire)
	_sag_wire(Layout.KIOSK + Vector3(2.3, 3.4, -1.8), Vector3(61.0, 6.2, -86.0), 0.6, wire)

## Контактный провод: опоры каждой точки — столбы её поперечины или угловой оттяжки.
## Сегмент держится только на опорах двух своих концов, включая снег и скрутки на нём.
func _wire_run(points: Array[Vector2], material: Material, supports: Array) -> void:
	for i in range(1, points.size()):
		var owners: Array = []
		for id: StringName in supports[i - 1] + supports[i]:
			if not owners.has(id): owners.append(id)
		_sag_wire(Vector3(points[i - 1].x, CONTACT_Y, points[i - 1].y), Vector3(points[i].x, CONTACT_Y, points[i].y), 0.22, material, owners)

## Та же угловая опора, к которой ниже проведена оттяжка каждого провода кольца.
func _corner_wire_poles(east: bool) -> Array:
	var owners: Array = []
	for pole: Vector2 in Layout.CORNER_POLES:
		if (pole.x > 0.0) != east: continue
		var id: StringName = _pole_ids.get(_pole_key(pole), &"")
		if id != &"": owners.append(id)
	return owners

## Провод с провисом: ломаная из 8 отрезков по параболе; на части пролётов — снежная «гирлянда» поверх провода,
## у пролётов с заметным провисом — скрутки и изоляторы на концах (CITY-02 E).
func _sag_wire(from: Vector3, to: Vector3, sag: float, material: Material, supports: Array = []) -> void:
	var steps := 8
	var prev := from
	var seed := int(absf(from.x * 13.0 + from.z * 7.0 + to.x * 3.0 + to.z * 5.0))
	var owners := _wire_poles(from, to)
	for id: StringName in supports:
		if not owners.has(id): owners.append(id)
	_env().wire_owners = owners
	for i in range(1, steps + 1):
		var k := float(i) / steps
		var p := from.lerp(to, k) - Vector3.UP * sag * 4.0 * k * (1.0 - k)
		_wire(prev, p, material, owners)
		_env().wire_snow(prev, p, seed + i)
		prev = p
	if sag >= 0.3:
		_env().wire_twist(from, to, seed)
		_env().wire_twist(to, from, seed + 1)
	_env().wire_owners = []

## Отрезок провода — экземпляр общего MultiMesh (единичный цилиндр толщиной 4 см, ось Y — вдоль провода).
## owners — id столбов (BREAK-03); не заданы — столбы на концах отрезка и _wire_extra.
func _wire(from: Vector3, to: Vector3, _material: Material, owners: Array = []) -> void:
	_wires.append(_segment(from, to, 1.0))
	_wire_owners.append(owners if not owners.is_empty() else _wire_poles(from, to))

## Разрушаемые столбы, на которых держится провод from → to: на его концах (по x/z) и _wire_extra.
func _wire_poles(from: Vector3, to: Vector3) -> Array:
	var out: Array = _wire_extra.duplicate()
	for p in [from, to]:
		var id: StringName = _pole_ids.get(_pole_key(Vector2(p.x, p.z)), &"")
		if id != &"" and not id in out:
			out.append(id)
	return out

## Преобразование единичного цилиндра (высота 1, радиус 0,5) в отрезок from → to толщиной 2·radius_scale·0,5.
static func _segment(from: Vector3, to: Vector3, radius_scale: float) -> Transform3D:
	var axis := to - from
	var dir := axis.normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
	var other := side.cross(dir).normalized()
	return Transform3D(Basis(side * radius_scale, axis, other * radius_scale), (from + to) * 0.5)

## Город за границей карты (CITY-02 E): ближний ряд домов, средний слой, силуэты горизонта, мост, краны —
## skyline.gd. Здесь — башня «ГОСТИНИЦА» в конце улицы B (концепт 05), как была.
func _build_skyline() -> void:
	_sky().build_city()
	var tower := Greybox.mesh_box(Vector3(26, 58, 22), Color.WHITE)
	tower.material_override = Materials.facade(7.0, true)
	tower.position = Vector3(70, 29, -205)
	tower.name = "Landmark"
	tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tower)
	# Верх как в концепте 05 (CITY-02 F, P3): уступ, часовая башня с подсвеченным циферблатом к арене, фонарь со шпилем
	# и красным огнём. Раньше — один конус на крыше.
	var tiers := [[Vector3(16, 8, 14), 62.0], [Vector3(9, 12, 9), 72.0]]
	for t in tiers:
		var tier := Greybox.mesh_box(t[0], Color.WHITE)
		tier.material_override = Materials.facade(8.0, true)
		tier.position = Vector3(70, float(t[1]), -205)
		tier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tier)
	var clock := Greybox.mesh_cylinder(2.7, 2.7, 0.2, Color.WHITE)
	clock.material_override = Materials.plain(Color(0.95, 0.90, 0.76), 0.5, Color(1.0, 0.88, 0.62), 1.4)
	clock.rotation.x = PI * 0.5
	clock.position = Vector3(70, 73.0, -200.4)
	add_child(clock)
	for hand in [[Vector3(0.25, 2.0, 0.08), 0.6], [Vector3(0.2, 1.4, 0.08), -1.9]]:
		var arm := Greybox.mesh_box(hand[0], Color.WHITE)
		arm.material_override = Materials.plain(Color(0.08, 0.08, 0.09), 0.6)
		arm.rotation.z = float(hand[1])
		arm.position = Vector3(70, 73.0, -200.25) + Vector3(-sin(float(hand[1])), cos(float(hand[1])), 0) * float((hand[0] as Vector3).y) * 0.45
		add_child(arm)
	var lantern := Greybox.mesh_box(Vector3(5, 5, 5), Color.WHITE)
	lantern.material_override = Materials.plain(Color(0.30, 0.28, 0.25), 0.6, Color(1.0, 0.8, 0.5), 0.35)
	lantern.position = Vector3(70, 80.5, -205)
	add_child(lantern)
	var spire := Greybox.mesh_cylinder(0.0, 2.0, 15.0, Color.WHITE)
	spire.material_override = Materials.plain(Color(0.45, 0.42, 0.38), 0.6)
	spire.position = Vector3(70, 90.5, -205)
	add_child(spire)
	_sky()._light(Vector3(70, 98.6, -205), Skyline.BEACON, 1.0, 1, 0.4, 0.8)
	# Буквы-короб на крыше башни, как в концепте 05 (сверка ART-04, P3 14): каркас и светящиеся буквы над парапетом.
	var frame := Greybox.mesh_box(Vector3(22, 0.3, 0.3), Color.WHITE)
	frame.material_override = Materials.plain(Color(0.15, 0.15, 0.16), 0.6)
	frame.position = Vector3(70, 58.4, -194.3)
	add_child(frame)
	var hotel := _label("ГОСТИНИЦА", 260, Color(1.0, 0.92, 0.75))
	hotel.pixel_size = 0.016
	hotel.position = Vector3(70, 60.6, -194.2)
	add_child(hotel)

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

## Бумажные объявления в несколько слоёв, распредкоробки и наклейки на столбах (черта 13; CITY-02 E).
func _notices(body: Node3D, size: Vector3, seed: int) -> void:
	_env().pole_dress(body.position, size, seed)

## Тополь (CITY-02 E): ствол с наплывом, изогнутые сучья, ветви второго и третьего порядка в куржаке, снег на
## развилках; каждый третий — кронированный, с волчками (EnvDress.poplar, ART-04, черта 8; ART-06, Н8).
func _poplar(base: Vector3, seed: int) -> void:
	_env().poplar(base, seed)

## Натоптанные тропинки в рыхлом снегу (черта 12): от подъезда к проезду, через двор по пути Илюши,
## от тротуара к окну киоска, по газонам улицы A.
func _build_trails() -> void:
	var paths := [
		[Vector2(-40, 106), Vector2(-40, 100), 1.6], [Vector2(-40, 101), Vector2(-20, 86), 1.3],
		[Vector2(-20, 86), Vector2(-5, 63), 1.3], [Vector2(-5, 58), Vector2(-2, 44), 1.4],
		[Vector2(-40, 106), Vector2(-70, 104), 1.1], [Vector2(-40, 106), Vector2(-12, 104), 1.1],
		[Vector2(-60, 86), Vector2(-48, 96), 1.0], [Vector2(64, -77), Vector2(59, -77), 2.2],
		[Vector2(58, -70), Vector2(58, -84), 1.2], [Vector2(-88, 17), Vector2(-10, 18), 1.0],
		# CITY-02 F (сверка: «двор — гладкая равнина»): от каждого подъезда двора (H1 −73,5 и −13,5; H2 z 67,5 и 97,5;
		# H3 −53,3 и −27,3) — к площадке, контейнерам, выезду на улицу A и к воротам гаражей.
		[Vector2(-73.5, 107.6), Vector2(-73.5, 101), 1.4], [Vector2(-73.5, 101), Vector2(-63, 86), 1.0],
		[Vector2(-13.5, 107.6), Vector2(-13.5, 101), 1.4], [Vector2(-13.5, 101), Vector2(-7, 79), 1.1], [Vector2(-7, 79), Vector2(-5, 62), 1.1],
		[Vector2(-77.6, 67.5), Vector2(-70, 67.5), 1.4], [Vector2(-70, 67.5), Vector2(-62, 75), 1.0], [Vector2(-70, 66.2), Vector2(-37, 66.6), 1.0],
		[Vector2(-77.6, 97.5), Vector2(-70, 97.5), 1.4], [Vector2(-70, 97.5), Vector2(-64, 86), 0.9],
		[Vector2(-53.3, 60), Vector2(-53.3, 66), 1.4], [Vector2(-53.3, 66), Vector2(-58, 75), 1.0],
		[Vector2(-27.3, 60), Vector2(-27.3, 63.5), 1.4], [Vector2(-27.3, 63), Vector2(-6, 60.5), 1.1],
		[Vector2(-5, 63), Vector2(21, 72), 1.0], [Vector2(-12, 104), Vector2(21, 96), 1.0], [Vector2(-54, 81), Vector2(-21, 86), 0.9],
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

## Отвалы снега у внутридворового проезда (CITY-02 F; черта 12): низкие (0,35 м), без коллизии — в стороне от путей
## жителей, Илюши и «Лады». Форма — та же сетка, что у валов (EnvDress.bank_mesh), без грязной кромки дороги.
func _build_yard_piles() -> void:
	for spec in [[Vector2(-20.5, 99.6), 10.0, true, -1.0, 51], [Vector2(-50.5, 92.0), 8.0, false, -1.0, 52], [Vector2(8.5, 81.0), 10.0, false, 1.0, 53]]:
		var xz: Vector2 = spec[0]
		var mesh := MeshInstance3D.new()
		mesh.name = "YardPile"
		mesh.mesh = EnvDress.bank_mesh(float(spec[1]), 0.9, 0.35, int(spec[4]), float(spec[3]))
		mesh.material_override = Materials.bank_snow(0.0)
		mesh.position = Vector3(xz.x, 0.0, xz.y)
		if not spec[2]:
			mesh.rotation.y = -PI * 0.5
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

## Общие MultiMesh: провода (без теней); дома — пакеты buildings.gd (CITY-02 B); среда и панорама — EnvDress
## и Skyline (CITY-02 E).
func _build_instances() -> void:
	_houses().build()   # лоджии, рамы, стёкла, снег, крыши, мелочь домов (CITY-02 B)
	_env().build()      # деревья, бордюры, пятна, люки, снег на проводах, столбы (CITY-02 E)
	_sky().finish()     # средний слой, огни, мост, краны (CITY-02 E)
	if not _vent_steam.is_empty():
		# Пар вытяжек: мелкие клубы, сносимые ветром; дымка по расстоянию — материал без тумана сцены (CITY-02 F).
		add_child(Skyline.plume("VentSteam", _vent_steam, 7, {"wind": Vector3(3.2, 0, 1.4), "life": 7.0, "rise": 4.0,
			"size_start": 0.7, "size_end": 3.6, "spread": 0.5, "color": Color(0.66, 0.69, 0.75, 0.42), "haze_dist": 140.0}, 5))
		_vent_steam.clear()
	var wire := CylinderMesh.new()
	wire.top_radius = 0.02
	wire.bottom_radius = 0.02
	wire.height = 1.0
	wire.radial_segments = 4
	wire.rings = 1
	var wires_node := _multimesh("Wires", wire, _wires, [], Materials.plain(Color(0.05, 0.05, 0.05), 0.5), false)
	if wires_node:
		var owned := []
		for i in _wire_owners.size():
			if not (_wire_owners[i] as Array).is_empty():
				owned.append([i, _wire_owners[i]])
		EnvDress.register(break_visuals, wires_node, owned, "wires")

func _multimesh(name: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], material: Material, shadows: bool) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
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
	return instance



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
	# BREAK-03: знак на опоре падает с опорой, знак «Тб 13» на стойке — с павильоном.
	_adopt(root, Layout.ENV_BREAK_KINDS.keys(), pole)
	_adopt(post, ["BusPavilion"], pav)
	_adopt(sign_a, ["BusPavilion"], pav)

## BREAK-03: узел node падает вместе с разрушаемым окружением, чья запись с именем из names стоит в xz (нет — ничего).
func _adopt(node: Node3D, names: Array, xz: Vector2, key := "nodes") -> void:
	var id := env_id_at(names, xz)
	if id != &"":
		break_entry(break_visuals, id)[key].append(node)
		var runtime := get_node_or_null("Breakables")
		if key == "cut" and runtime and runtime.has_method("register_cut"):
			runtime.register_cut(node, id)

## id записи Layout.env_breakables() с именем из names (пусто — любое) в точке xz; &"" — нет такой.
static func env_id_at(names: Array, xz: Vector2) -> StringName:
	var solids := Layout.all_solids()
	for spec: Array in Layout.env_breakables():
		var i: int = spec[6]
		if (spec[2] as Vector2).distance_to(xz) < 0.1 and (names.is_empty() or (i >= 0 and solids[i][0] in names)):
			return spec[0]
	return &""

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

## Павильон остановки из профлиста (ART-06, Н6; CITY-02 E): угловые стойки и обвязка, три стенки, крыша со снежным
## напуском и сосульками, лавка на ножках со спинкой, расписание и объявления внутри, световой короб с плакатом
## снаружи, табличка маршрутов. Открыт на −z; к улице его поворачивает _build_solid.
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
	var k := EnvDress.kit()
	var frame := Color(0.20, 0.26, 0.34)
	for cx: float in [-hx, hx]:
		for cz: float in [-hz, hz]:
			EnvDress.kit_box(k, Vector3(0.08, size.y - 0.1, 0.08), Vector3(cx, base + (size.y - 0.1) * 0.5, cz), frame, Color(0, 0.5, 0, 0))
	EnvDress.kit_box(k, Vector3(size.x + 0.1, 0.1, 0.1), Vector3(0, base + size.y - 0.15, -hz), frame, Color(0, 0.5, 0, 0))
	# Профлист стенок — рёбра узором (detail, режим 1) поверх гладких листов: видны вблизи.
	EnvDress.kit_box(k, Vector3(size.x - 0.1, size.y - 0.4, 0.01), Vector3(0, base + (size.y - 0.2) * 0.5, hz - 0.06), Color(0.62, 0.65, 0.70), Color(1.0, 0.5, 0, 0))
	EnvDress.kit_box(k, Vector3(size.x - 0.1, size.y - 0.4, 0.01), Vector3(0, base + (size.y - 0.2) * 0.5, hz), Color(0.60, 0.63, 0.68), Color(1.0, 0.5, 0, 0))
	# Снежный напуск над открытой стороной и сосульки.
	EnvDress.kit_snow(k, Vector3(size.x + 0.3, 0.12, 0.24), Vector3(0, base + size.y + 0.05, -hz - 0.36), Vector3(-0.3, 0, 0))
	EnvDress.kit_icicles(k, Vector3(-hx - 0.1, base + size.y - 0.08, -hz - 0.32), Vector3(hx + 0.1, base + size.y - 0.08, -hz - 0.32), 0.35, int(size.x * 13.0))
	# Лавка: доска на двух ножках со спинкой.
	_part(root, Vector3(size.x - 0.4, 0.06, 0.4), Vector3(0, base + 0.5, hz - 0.3), Materials.plain(Color(0.36, 0.24, 0.15), 0.85))
	for lx: float in [-hx + 0.5, hx - 0.5]:
		EnvDress.kit_box(k, Vector3(0.06, 0.48, 0.3), Vector3(lx, base + 0.24, hz - 0.3), Color(0.15, 0.15, 0.16), Color(0, 0.5, 0, 0))
	EnvDress.kit_box(k, Vector3(size.x - 0.4, 0.14, 0.04), Vector3(0, base + 0.85, hz - 0.1), Color(0.36, 0.24, 0.15), Color(0, 0.85, 0, 0))
	EnvDress.kit_snow(k, Vector3(size.x - 1.2, 0.03, 0.12), Vector3(-0.3, base + 0.545, hz - 0.42))
	var paper := [Color(0.86, 0.85, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.72), Color(0.84, 0.78, 0.80)]
	for i in 7:
		var tilt := (_rand(i, 21) - 0.5) * 0.2
		EnvDress.kit_box(k, Vector3(0.22, 0.18 if i % 3 == 2 else 0.3, 0.008), Vector3(-hx + 0.4 + i * 0.5, base + 1.1 + (i % 3) * 0.32, hz - 0.065), paper[i % paper.size()], Color(0, 0.95, 0, 0), Vector3(0, 0, tilt))
	# Расписание внутри на задней стенке.
	var timetable := Vector3(hx - 0.6, base + 1.55, hz - 0.07)
	EnvDress.kit_box(k, Vector3(0.62, 0.5, 0.01), timetable, Color(0.94, 0.94, 0.92), Color(0, 0.7, 0, 0))
	EnvDress.kit_box(k, Vector3(0.62, 0.08, 0.012), timetable + Vector3(0, 0.21, 0), Color(0.10, 0.25, 0.55), Color(0, 0.7, 0, 0))
	var tt := _label("РАСПИСАНИЕ\nТб 13   5:50 – 23:40\nинтервал 12 – 20 мин", 22, Color(0.10, 0.12, 0.20))
	tt.pixel_size = 0.003
	tt.position = timetable + Vector3(0, -0.02, -0.01)
	tt.rotation.y = PI
	root.add_child(tt)
	# Световой короб на наружной задней стенке: плакат без брендов — зимний пейзаж пятнами.
	var box_at := Vector3(-hx + 1.0, base + 1.35, hz + 0.08)
	EnvDress.kit_box(k, Vector3(1.2, 1.6, 0.12), box_at, Color(0.18, 0.18, 0.20), Color(0, 0.5, 0, 0))
	EnvDress.kit_box(k, Vector3(1.08, 1.48, 0.01), box_at + Vector3(0, 0, 0.065), Color(0.55, 0.70, 0.85), Color(0, 0.3, 0.9, 0))
	EnvDress.kit_box(k, Vector3(1.08, 0.5, 0.012), box_at + Vector3(0, -0.45, 0.067), Color(0.90, 0.92, 0.95), Color(0, 0.3, 0.9, 0))
	EnvDress.kit_box(k, Vector3(0.5, 0.18, 0.013), box_at + Vector3(0.1, 0.4, 0.068), Color(0.95, 0.75, 0.25), Color(0, 0.3, 0.9, 0))
	EnvDress.kit_emit(k, root, "PavilionDress")
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

## Трубы ТЭЦ (ART-06, Н7; места и высоты приняты в С2–С4) с огнями и паром — skyline.gd.
func _build_chimneys() -> void:
	_sky().chimneys()

## Пар из вытяжки на крыше (ART-06, Н9: `minus-28`): точка копится, клубы-билборды строит _build_instances одним
## MultiMesh (shaders/steam_plume, CITY-02 F) — раньше четыре полупрозрачные сферы с геометрическими краями.
func _steam_puff(parent: Node3D, at: Vector3, seed: int) -> void:
	_vent_steam.append(parent.position + at + Vector3(0, 0.1 * (seed % 3), 0))


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

## Детская площадка за оградкой (внутри коллизии Playground): советская металлическая горка с изогнутым жёлобом,
## качели на А-образных стойках (одно сиденье зимой закинуто на перекладину), песочница с бортиками-сиденьями
## и грибком в горошек, сугробы у оградки, снег на всех горизонталях (CITY-02 E). Только облик; реакции — BREAK-01.
## Начало координат — центр площадки на земле.
func _playground(xz: Vector2, size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "PlaygroundDress"
	root.position.y = -size.y * 0.5
	var red := Materials.plain(Color(0.62, 0.14, 0.10), 0.5)
	var yellow := Materials.plain(Color(0.80, 0.60, 0.12), 0.5)
	var blue := Materials.plain(Color(0.18, 0.30, 0.55), 0.5)
	var wood := Materials.plain(Color(0.40, 0.27, 0.16), 0.85)
	var k := EnvDress.kit()
	# Горка: лестница с запада, площадка 1,9 м с дугой-перилами, жёлоб на восток — круто сверху, полого внизу.
	var s := Vector3(Layout.PLAYGROUND_SLIDE.x - xz.x, 0, Layout.PLAYGROUND_SLIDE.y - xz.y)
	var top := 1.9
	for zs in [-0.35, 0.35]:
		_rod(root, s + Vector3(-1.9, 0, zs), s + Vector3(-1.0, top + 0.9, zs), 0.04, red)   # тетива лестницы
		_rod(root, s + Vector3(-0.6, 0, zs), s + Vector3(-0.6, top + 0.9, zs), 0.04, red)    # задние стойки
		_rod(root, s + Vector3(-1.0, top, zs), s + Vector3(-1.0, top + 0.9, zs), 0.04, red)  # перила
		_rod(root, s + Vector3(-1.0, top + 0.9, zs), s + Vector3(-0.6, top + 0.9, zs), 0.04, red)
	for i in 7:   # дуга над площадкой
		var a0 := PI * i / 7.0
		var a1 := PI * (i + 1) / 7.0
		_rod(root, s + Vector3(-0.8, top + 0.9 + sin(a0) * 0.35, -cos(a0) * 0.35), s + Vector3(-0.8, top + 0.9 + sin(a1) * 0.35, -cos(a1) * 0.35), 0.03, blue)
	for st in 5:
		var t := (st + 1) / 6.0 * top / (top + 0.9)
		var a := s + Vector3(-1.9 + 0.9 * t, (top + 0.9) * t, 0)
		_rod(root, a + Vector3(0, 0, -0.35), a + Vector3(0, 0, 0.35), 0.025, yellow)        # ступени
		EnvDress.kit_snow(k, Vector3(0.06, 0.03, 0.6), a + Vector3(0, 0.035, 0))
	_part(root, Vector3(0.5, 0.06, 0.8), s + Vector3(-0.8, top, 0), yellow)                  # площадка
	_part(root, Vector3(0.5, 0.06, 0.74), s + Vector3(-0.8, top + 0.06, 0), Materials.snow(0.0))
	var curve := [Vector3(-0.55, top, 0), Vector3(0.2, top - 0.75, 0), Vector3(1.0, 0.6, 0), Vector3(1.7, 0.3, 0), Vector3(2.25, 0.28, 0)]
	for i in curve.size() - 1:
		var a: Vector3 = s + curve[i]
		var b: Vector3 = s + curve[i + 1]
		var chute := Greybox.mesh_box(Vector3(a.distance_to(b) + 0.04, 0.04, 0.6), Color.WHITE)
		chute.material_override = Materials.plain(Color(0.66, 0.68, 0.70), 0.25)
		chute.position = (a + b) * 0.5
		chute.rotation.z = atan2(b.y - a.y, b.x - a.x)
		root.add_child(chute)
		for zs in [-0.31, 0.31]:
			_rod(root, a + Vector3(0, 0.12, zs), b + Vector3(0, 0.12, zs), 0.025, blue)   # бортики
		# Снег в жёлобе внизу — с горки давно не катались.
		if i >= 2:
			EnvDress.kit_snow(k, Vector3(a.distance_to(b), 0.05, 0.5), (a + b) * 0.5 + Vector3(0, 0.04, 0), Vector3(0, 0, atan2(b.y - a.y, b.x - a.x)))
	for zs in [-0.25, 0.25]:
		_rod(root, s + Vector3(0.2, top - 0.75, zs), s + Vector3(0.2, 0, zs), 0.03, blue)
		_rod(root, s + Vector3(1.0, 0.6, zs), s + Vector3(1.0, 0, zs), 0.03, blue)
		_rod(root, s + Vector3(2.15, 0.28, zs), s + Vector3(2.15, 0, zs), 0.03, blue)
	# Качели: две А-стойки, перекладина 2,8 м; одно сиденье на цепях, второе закинуто на перекладину.
	var w := Vector3(Layout.PLAYGROUND_SWINGS.x - xz.x, 0, Layout.PLAYGROUND_SWINGS.y - xz.y)
	var bar_y := 2.2
	for xs in [-1.3, 1.3]:
		for zs in [-0.75, 0.75]:
			_rod(root, w + Vector3(xs, 0, zs), w + Vector3(xs, bar_y, 0), 0.05, red)
		_rod(root, w + Vector3(xs, 0.7, -0.5), w + Vector3(xs, 0.7, 0.5), 0.035, red)   # распорка
	_rod(root, w + Vector3(-1.45, bar_y, 0), w + Vector3(1.45, bar_y, 0), 0.05, red)
	EnvDress.kit_snow(k, Vector3(2.8, 0.05, 0.08), w + Vector3(0, bar_y + 0.065, 0))
	var chain := Materials.plain(Color(0.25, 0.25, 0.26), 0.5)
	for zs in [-0.22, 0.22]:
		_rod(root, w + Vector3(-0.6 + zs, bar_y, 0), w + Vector3(-0.6 + zs, 0.48, 0), 0.012, chain)
	_part(root, Vector3(0.55, 0.05, 0.25), w + Vector3(-0.6, 0.46, 0), wood)
	_part(root, Vector3(0.5, 0.03, 0.2), w + Vector3(-0.6, 0.5, 0), Materials.snow(0.0))
	_part(root, Vector3(0.55, 0.05, 0.25), w + Vector3(0.6, bar_y + 0.12, -0.05), wood)   # закинутое сиденье
	for zs in [-0.2, 0.2]:
		for q in 3:
			var a := PI * q / 3.0
			var b := PI * (q + 1) / 3.0
			_rod(root, w + Vector3(0.6 + zs, bar_y + sin(a) * 0.1, -cos(a) * 0.1), w + Vector3(0.6 + zs, bar_y + sin(b) * 0.1, -cos(b) * 0.1), 0.012, chain)
		_rod(root, w + Vector3(0.6 + zs, bar_y - 0.1, 0.06), w + Vector3(0.6 + zs, bar_y - 0.7, 0.04), 0.012, chain)
	_part(root, Vector3(2.4, 0.01, 1.2), w + Vector3(0, 0.01, 0), Materials.snow(0.9))
	# Песочница под снегом: рамка с треугольными сиденьями по углам и грибок в красный горошек.
	var b := Vector3(-3.2, 0, -2.6)
	for e in [[Vector3(2.0, 0.25, 0.1), Vector3(0, 0.125, 0.95)], [Vector3(2.0, 0.25, 0.1), Vector3(0, 0.125, -0.95)],
			[Vector3(0.1, 0.25, 2.0), Vector3(0.95, 0.125, 0)], [Vector3(0.1, 0.25, 2.0), Vector3(-0.95, 0.125, 0)]]:
		_part(root, e[0], b + e[1], wood)
		EnvDress.kit_snow(k, Vector3((e[0] as Vector3).x, 0.04, (e[0] as Vector3).z), b + e[1] + Vector3(0, 0.145, 0))
	for cx in [-0.8, 0.8]:
		for cz in [-0.8, 0.8]:
			EnvDress.kit_box(k, Vector3(0.36, 0.04, 0.36), b + Vector3(cx, 0.27, cz), Color(0.62, 0.42, 0.20), Color(0, 0.9, 0, 0), Vector3(0, PI * 0.25, 0))
	var heap := _mound(Vector3(1.8, 0.35, 1.8), Materials.snow(0.0))
	heap.position += b + Vector3(0, 0.175, 0)
	root.add_child(heap)
	var post := b + Vector3(0.9, 0, 0.9)
	_rod(root, post, post + Vector3(0, 1.9, 0), 0.06, Materials.plain(Color(0.86, 0.84, 0.78), 0.6))
	var cap := Greybox.mesh_cylinder(0.06, 1.0, 0.55, Color.WHITE)
	cap.material_override = red
	cap.position = post + Vector3(0, 2.05, 0)
	root.add_child(cap)
	for d in 7:
		var a := TAU * d / 7.0 + 0.3
		var r := 0.62 if d % 2 == 0 else 0.4
		var y := 2.05 + (0.5 - r / 1.0) * 0.55 + 0.02
		EnvDress.kit_put(k, "sph", Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.05, 0.12, 0.12)), post + Vector3(cos(a) * r * 1.02, y, sin(a) * r * 1.02)), Color(0.95, 0.95, 0.92), Color(0, 0.6, 0, 0))
	var snowcap := Greybox.mesh_cylinder(0.02, 0.62, 0.22, Color.WHITE)
	snowcap.material_override = Materials.snow(0.0)
	snowcap.position = post + Vector3(0, 2.26, 0)
	root.add_child(snowcap)
	# Сугробы вдоль оградки — снег сгребали с дорожек внутрь.
	for i in 4:
		var drift := _mound(Vector3(2.2 + 0.6 * _rand(i, 1), 0.3 + 0.2 * _rand(i, 2), 0.9), Materials.snow(0.0))
		drift.position += Vector3(-4.5 + i * 3.0, 0.2, size.z * 0.5 - 0.6)
		root.add_child(drift)
	EnvDress.kit_emit(k, root, "PlaygroundSnow")
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
	for part in root.get_children().slice(1):
		_adopt(part, ["CarpetBar"], Layout.CARPET_BAR[1], "cut")
	return root

## Три мусорных контейнера на бетонной площадке у проезда: крашеный металл, ручки-цапфы и колёса, крышки с шапкой
## снега, ржавые пятна; вокруг — мусор: мешки, коробки, бутылки, газеты, у дворовых — старый стул (CITY-02 E).
## У киоска (короткий ряд) мусор только низкий, до 0,3 м: площадка — зона стелса (ARENA-02, «Что не делать», 1).
func _trash_bins(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var base := -size.y * 0.5
	_part(root, Vector3(size.x + 0.8, 0.08, size.z + 0.8), Vector3(0, base + 0.04, 0), Materials.plain(Color(0.42, 0.42, 0.41), 0.9))
	var colors := [Color(0.20, 0.36, 0.24), Color(0.28, 0.34, 0.42), Color(0.22, 0.38, 0.26)]
	var rust := Materials.plain(Color(0.42, 0.22, 0.10), 0.9)
	var unit := size.x / 3.0
	var k := EnvDress.kit()
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
		for sx: float in [-1.0, 1.0]:
			EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)) * Basis.from_scale(Vector3(0.14, 0.08, 0.14)), Vector3(x + sx * (unit * 0.5 - 0.05), base + h * 0.7, 0)), colors[i].darkened(0.4), Color(0, 0.6, 0, 0))   # цапфы
			for sz: float in [-1.0, 1.0]:
				EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)) * Basis.from_scale(Vector3(0.12, 0.05, 0.12)), Vector3(x + sx * (unit * 0.5 - 0.2), base + 0.1, sz * (size.z * 0.5 - 0.15))), Color(0.08, 0.08, 0.08), Color(0, 0.8, 0, 0))
		# Пакет, торчащий из-под приоткрытой крышки.
		if i == 1:
			EnvDress.kit_put(k, "sph", Transform3D(Basis.from_scale(Vector3(0.45, 0.25, 0.35)), Vector3(x, base + 0.08 + h + 0.02, size.z * 0.42)), Color(0.10, 0.10, 0.11), Color(0, 0.3, 0, 0))
	var low := size.x < 3.5
	var litter := 9 if low else 14
	for j in litter:
		var r1 := _rand(j * 7 + int(size.x * 10.0), 1)
		var r2 := _rand(j * 7 + int(size.x * 10.0), 2)
		var r3 := _rand(j * 7 + int(size.x * 10.0), 3)
		var x := -size.x * 0.5 - 0.3 + (size.x + 0.6) * r1
		var z := size.z * 0.5 + 0.15 + 0.5 * r2
		var kind := int(r3 * 5.0)
		match kind:
			0, 1:   # мешок: чёрный, синий или белый
				var c: Color = [Color(0.06, 0.06, 0.07), Color(0.14, 0.20, 0.36), Color(0.80, 0.80, 0.78)][j % 3]
				var hgt := 0.28 if low else 0.3 + 0.2 * r2
				EnvDress.kit_put(k, "sph", Transform3D(Basis(Vector3.UP, r1 * TAU) * Basis.from_scale(Vector3(0.5, hgt, 0.42)), Vector3(x, base + hgt * 0.45, z)), c, Color(0, 0.3, 0, 0))
			2:   # коробка, часто сплющенная
				var flat := r2 < 0.5 or low
				EnvDress.kit_box(k, Vector3(0.5, 0.04 if flat else 0.35, 0.4), Vector3(x, base + (0.03 if flat else 0.18), z), Color(0.55, 0.42, 0.28).darkened(0.2 * r1), Color(0, 0.95, 0, 0), Vector3(0, r2 * PI, 0.0 if flat else 0.1))
			3:   # бутылки
				for q in 3:
					EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_euler(Vector3(PI * 0.5, r2 * PI + q, 0)) * Basis.from_scale(Vector3(0.07, 0.26, 0.07)), Vector3(x + q * 0.12, base + 0.04, z + q * 0.05)), [Color(0.12, 0.30, 0.12), Color(0.35, 0.20, 0.08), Color(0.70, 0.78, 0.75)][q], Color(0, 0.15, 0, 0))
			_:   # газеты и снег
				EnvDress.kit_box(k, Vector3(0.4, 0.01, 0.3), Vector3(x, base + 0.015, z), Color(0.80, 0.78, 0.72), Color(0, 0.95, 0, 0), Vector3(0, r2 * PI, 0))
				EnvDress.kit_lump(k, Vector3(0.6, 0.12, 0.5), Vector3(x + 0.3, base, z - 0.1))
	if not low:
		# Старый стул у контейнеров.
		var at := Vector3(size.x * 0.5 + 0.5, base, 0.2)
		var c := Color(0.42, 0.28, 0.16)
		EnvDress.kit_box(k, Vector3(0.42, 0.04, 0.42), at + Vector3(0, 0.45, 0), c, Color(0, 0.85, 0, 0))
		for lx: float in [-0.18, 0.18]:
			for lz: float in [-0.18, 0.18]:
				EnvDress.kit_box(k, Vector3(0.035, 0.45, 0.035), at + Vector3(lx, 0.22, lz), c, Color(0, 0.85, 0, 0))
		EnvDress.kit_box(k, Vector3(0.42, 0.45, 0.035), at + Vector3(0, 0.7, -0.2), c, Color(0, 0.85, 0, 0), Vector3(-0.1, 0, 0))
		EnvDress.kit_snow(k, Vector3(0.38, 0.05, 0.38), at + Vector3(0, 0.49, 0))
	EnvDress.kit_emit(k, root, "BinsLitter")
	# Сугроб у задней стенки.
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
	Lighting.configure_local_shadow(bulb_light)
	root.add_child(bulb_light)
	# Ценник «Батон 35» за стеклом, в правом нижнем углу окна (если смотреть с улицы).
	# Маленький товар на большой подложке: уменьшение видно ещё до разговора с продавщицей.
	var tray_at := Vector3(hx - 0.31, floor_y + 1.05, 0.75)
	_part(root, Vector3(0.32, 0.025, 0.64), tray_at, Materials.plain(Color(0.80, 0.77, 0.68), 0.8))
	var sample := MeshInstance3D.new()
	sample.name = "SmallLoaf"
	var small_loaf := CapsuleMesh.new()
	small_loaf.radius = 0.055
	small_loaf.height = 0.23
	small_loaf.radial_segments = 12
	small_loaf.rings = 3
	sample.mesh = small_loaf
	sample.rotation.x = PI * 0.5
	sample.position = tray_at + Vector3(0, 0.065, 0)
	sample.material_override = Materials.plain(Color(0.83, 0.55, 0.25), 0.8)
	root.add_child(sample)
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

## Павильон «ПРОДУКТЫ 24» у улицы D (ART-04: ночной магазинчик у дороги; CITY-02 E): сэндвич-панели, витрина-ниша
## на запад с подсвеченными полками товара за стеклом и плакатами, решётка, дверь с ручкой и коробом рольставни,
## крыльцо, кондиционер, светящийся короб вывески, снег на крыше и отливе. Без интерактива; коллизия — коробка
## Layout.SHOP24 (ниша витрины — внутри неё).
func _shop24(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var base := -size.y * 0.5
	var wall_h := size.y - 0.15
	var panel := Materials.plain(Color(0.80, 0.82, 0.80), 0.7)
	var trim := Materials.plain(Color(0.20, 0.36, 0.30), 0.6)
	var iron := Materials.plain(Color(0.15, 0.15, 0.16), 0.5)
	var niche := 0.45
	var glass_w := size.z - 1.7
	var glass_z := hz - 0.3 - glass_w * 0.5
	var sill := 0.8
	var lintel := 2.2
	# Корпус: глубже ниши — сплошной; западная стена вокруг витрины — полосами.
	_part(root, Vector3(size.x - niche, wall_h, size.z), Vector3(niche * 0.5, base + wall_h * 0.5, 0), panel)
	_part(root, Vector3(niche, sill, size.z), Vector3(-hx + niche * 0.5, base + sill * 0.5, 0), panel)
	_part(root, Vector3(niche, wall_h - lintel, size.z), Vector3(-hx + niche * 0.5, base + (wall_h + lintel) * 0.5, 0), panel)
	var g0 := glass_z - glass_w * 0.5
	var g1 := glass_z + glass_w * 0.5
	_part(root, Vector3(niche, lintel - sill, g0 + hz), Vector3(-hx + niche * 0.5, base + (sill + lintel) * 0.5, (-hz + g0) * 0.5), panel)
	_part(root, Vector3(niche, lintel - sill, hz - g1), Vector3(-hx + niche * 0.5, base + (sill + lintel) * 0.5, (g1 + hz) * 0.5), panel)
	_part(root, Vector3(size.x + 0.1, 0.3, size.z + 0.1), Vector3(0, base + 0.15, 0), trim)   # цоколь
	# Витрина: светлая задняя стенка ниши, две полки с товаром, стекло, решётка снаружи.
	_part(root, Vector3(0.04, lintel - sill, glass_w), Vector3(-hx + niche - 0.02, base + (sill + lintel) * 0.5, glass_z), Materials.plain(Color(1.0, 0.86, 0.62), 0.3, WARM, 1.4))
	var k := EnvDress.kit()
	var goods := [Color(0.85, 0.20, 0.15), Color(0.95, 0.80, 0.20), Color(0.20, 0.45, 0.80), Color(0.92, 0.92, 0.88), Color(0.30, 0.60, 0.25), Color(0.75, 0.45, 0.15)]
	for shelf in 2:
		var y := base + sill + 0.12 + shelf * 0.55
		EnvDress.kit_box(k, Vector3(niche - 0.08, 0.03, glass_w - 0.1), Vector3(-hx + niche * 0.5, y, glass_z), Color(0.85, 0.85, 0.82), Color(3.0, 0.5, 0, 0))
		var z := g0 + 0.12
		var j := 0
		while z < g1 - 0.1:
			var c: Color = goods[(j * 5 + shelf * 3) % goods.size()]
			var tall := 0.18 + 0.2 * _rand(j + shelf * 40, 3)
			if j % 3 == 0:
				EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_scale(Vector3(0.08, tall + 0.08, 0.08)), Vector3(-hx + niche * 0.5, y + (tall + 0.08) * 0.5 + 0.015, z)), c, Color(0, 0.2, 0.25, 0))
			else:
				EnvDress.kit_box(k, Vector3(0.18, tall, 0.12), Vector3(-hx + niche * 0.5, y + tall * 0.5 + 0.015, z), c, Color(0, 0.6, 0.25, 0))
			z += 0.13 + 0.06 * _rand(j + shelf * 40, 4)
			j += 1
	_part(root, Vector3(0.02, lintel - sill, glass_w), Vector3(-hx - 0.01, base + (sill + lintel) * 0.5, glass_z), Materials.glass())
	for q in 5:
		_part(root, Vector3(0.04, 1.4, 0.04), Vector3(-hx - 0.08, base + 1.5, glass_z - glass_w * 0.5 + glass_w * q / 4.0), iron)
	_part(root, Vector3(0.04, 0.04, glass_w), Vector3(-hx - 0.08, base + 1.5, glass_z), iron)
	EnvDress.kit_box(k, Vector3(0.18, 0.04, glass_w + 0.1), Vector3(-hx - 0.08, base + sill - 0.02, glass_z), Color(0.60, 0.62, 0.64), Color(3.0, 0.5, 0, 0))   # отлив
	EnvDress.kit_snow(k, Vector3(0.16, 0.05, glass_w), Vector3(-hx - 0.09, base + sill + 0.02, glass_z))
	# Плакаты на стекле.
	for p in [["АКЦИЯ", Color(0.85, 0.12, 0.10), glass_z - glass_w * 0.3, 2.0], ["ХОЛОДНЫЕ\nНАПИТКИ", Color(0.10, 0.30, 0.65), glass_z + glass_w * 0.28, 1.95]]:
		var at := Vector3(-hx - 0.025, base + p[3], p[2])
		EnvDress.kit_box(k, Vector3(0.005, 0.26, 0.62), at, Color(0.95, 0.95, 0.90), Color(0, 0.9, 0, 0))
		var label := _label(p[0], 46, p[1])
		label.pixel_size = 0.004
		label.position = at + Vector3(-0.006, 0, 0)
		label.rotation.y = -PI * 0.5
		root.add_child(label)
	# Дверь с ручкой и коробом рольставни, крыльцо.
	_part(root, Vector3(0.06, 2.05, 0.9), Vector3(-hx - 0.03, base + 1.03, -hz + 0.65), Materials.plain(Color(0.30, 0.22, 0.16), 0.6))
	EnvDress.kit_box(k, Vector3(0.05, 0.3, 0.04), Vector3(-hx - 0.09, base + 1.0, -hz + 0.95), Color(0.75, 0.75, 0.72), Color(3.0, 0.3, 0, 0))
	EnvDress.kit_box(k, Vector3(0.28, 0.25, 1.0), Vector3(-hx - 0.14, base + 2.2, -hz + 0.65), Color(0.70, 0.71, 0.70), Color(1.0, 0.5, 0, 0))
	EnvDress.kit_snow(k, Vector3(0.28, 0.06, 1.0), Vector3(-hx - 0.14, base + 2.35, -hz + 0.65))
	_part(root, Vector3(0.9, 0.12, 1.4), Vector3(-hx - 0.45, base + 0.06, -hz + 0.65), Materials.plain(Color(0.46, 0.46, 0.45), 0.9))   # крыльцо
	EnvDress.kit_box(k, Vector3(0.6, 0.015, 0.9), Vector3(-hx - 0.4, base + 0.125, -hz + 0.65), Color(0.25, 0.18, 0.15), Color(0, 0.95, 0, 0))   # коврик
	# Кондиционер на южной стене, наледь под ним.
	var ac := Vector3(hx - 1.2, base + 2.2, hz + 0.16)
	EnvDress.kit_box(k, Vector3(0.8, 0.5, 0.3), ac, Color(0.82, 0.82, 0.80), Color(0, 0.5, 0, 0))
	EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)) * Basis.from_scale(Vector3(0.34, 0.02, 0.34)), ac + Vector3(0.12, 0, 0.16)), Color(0.2, 0.2, 0.21), Color(2.0, 0, 0, 0))
	EnvDress.kit_snow(k, Vector3(0.82, 0.06, 0.32), ac + Vector3(0, 0.28, 0))
	EnvDress.kit_lump(k, Vector3(0.6, 0.15, 0.5), Vector3(ac.x, base, hz + 0.3))
	var red := Color(0.50, 0.07, 0.05)
	_part(root, Vector3(0.22, 0.62, size.z + 0.2), Vector3(-hx - 0.11, base + wall_h + 0.2, 0), Materials.plain(red, 0.5, red, 0.5))
	EnvDress.kit_snow(k, Vector3(0.24, 0.07, size.z + 0.2), Vector3(-hx - 0.11, base + wall_h + 0.54, 0))
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
	EnvDress.kit_icicles(k, Vector3(-hx - 0.15, base + wall_h, -hz), Vector3(-hx - 0.15, base + wall_h, hz), 0.3, 24)
	EnvDress.kit_emit(k, root, "Shop24Dress")
	var heap := _lumpy_bank(Vector3(0.9, 0.6, size.z * 0.8), Materials.snow(0.15), 91)
	heap.position = Vector3(hx + 0.45, base + 0.3, 0)
	root.add_child(heap)
	return root

## Рекламный щит 6 × 3 м на одной опоре (CITY-02 E): опора с фланцем на бетонном фундаменте и лестницей в кольцах,
## консоль-траверса с подкосами, рама-швеллер с рёбрами по периметру, полотна с обрывками старых плакатов, мостик
## расклейщика с перилами, три прожектора на кронштейнах над каждым полотном (свечение без источника света),
## снег на верхней кромке и мостике. Коллизия — только опора (Layout.BILLBOARD). Полотно лицом к ±z.
func _billboard(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var base := -size.y * 0.5
	var steel := Materials.plain(Color(0.30, 0.31, 0.33), 0.5)
	var leg := Greybox.mesh_cylinder(0.22, 0.28, 7.2, Color.WHITE)
	leg.material_override = steel
	leg.position = Vector3(0, base + 3.6, 0)
	root.add_child(leg)
	var mid := base + 8.7
	var k := EnvDress.kit()
	var dark := Color(0.24, 0.25, 0.27)
	EnvDress.kit_box(k, Vector3(1.4, 0.35, 1.4), Vector3(0, base + 0.12, 0), Color(0.48, 0.48, 0.46), Color(0, 0.95, 0, 0))   # фундамент
	EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_scale(Vector3(0.9, 0.05, 0.9)), Vector3(0, base + 0.32, 0)), dark, Color(3.0, 0.5, 0, 0))   # фланец
	for b in 6:
		var a := TAU * b / 6.0
		EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_scale(Vector3(0.05, 0.08, 0.05)), Vector3(cos(a) * 0.38, base + 0.37, sin(a) * 0.38)), dark, Color(3.0, 0.5, 0, 0))
	EnvDress.kit_lump(k, Vector3(1.5, 0.25, 1.5), Vector3(0, base, 0))
	# Лестница по опоре с ограждением-кольцами.
	for rx: float in [-0.2, 0.2]:
		EnvDress.kit_seg(k, Vector3(rx, base + 2.2, 0.32), Vector3(rx, mid - 1.75, 0.32), 0.035, dark, Color(3.0, 0.5, 0, 0))
	var y := base + 2.4
	while y < mid - 1.8:
		EnvDress.kit_seg(k, Vector3(-0.2, y, 0.32), Vector3(0.2, y, 0.32), 0.025, dark, Color(3.0, 0.5, 0, 0))
		y += 0.3
	y = base + 4.0
	while y < mid - 1.8:
		for q in 8:
			var a0 := PI * q / 8.0
			var a1 := PI * (q + 1) / 8.0
			EnvDress.kit_seg(k, Vector3(cos(a0) * 0.4, y, 0.32 + sin(a0) * 0.4), Vector3(cos(a1) * 0.4, y, 0.32 + sin(a1) * 0.4), 0.025, dark)
		y += 0.9
	# Траверса под рамой и подкосы от опоры.
	EnvDress.kit_box(k, Vector3(4.6, 0.3, 0.3), Vector3(0, mid - 1.62, 0), dark, Color(0, 0.5, 0, 0))
	for sx: float in [-1.0, 1.0]:
		EnvDress.kit_seg(k, Vector3(0, base + 6.4, 0), Vector3(sx * 2.0, mid - 1.62, 0), 0.14, dark, Color(0, 0.5, 0, 0), "box")
	_part(root, Vector3(6.3, 3.3, 0.35), Vector3(0, mid, 0), steel)
	var canvas := Materials.plain(Color(0.86, 0.86, 0.83), 0.9, Color(1.0, 0.95, 0.85), 0.12)   # подсвечено прожекторами
	var scrap := Materials.plain(Color(0.66, 0.64, 0.58), 0.95)
	for side: float in [-1.0, 1.0]:
		_part(root, Vector3(6.0, 3.0, 0.02), Vector3(0, mid, side * 0.19), canvas)
		for i in 4:
			var r := _rand(i * 7 + int(side + 1.0), 5)
			_part(root, Vector3(0.25 + 0.6 * r, 0.12 + 0.5 * _rand(i, 9), 0.01), Vector3(-2.4 + i * 1.5 + r * 0.5, mid - 1.0 + 1.8 * _rand(i * 3, 2), side * 0.205), scrap)
		# Рама-швеллер по периметру полотна.
		for e in [[Vector3(6.3, 0.12, 0.08), Vector3(0, 1.56, 0)], [Vector3(6.3, 0.12, 0.08), Vector3(0, -1.56, 0)],
				[Vector3(0.12, 3.3, 0.08), Vector3(3.09, 0, 0)], [Vector3(0.12, 3.3, 0.08), Vector3(-3.09, 0, 0)]]:
			EnvDress.kit_box(k, e[0], Vector3(0, mid, side * 0.22) + e[1], dark, Color(3.0, 0.5, 0, 0))
		# Прожекторы: кронштейн от верхней кромки на 1,2 м и корпус-лампа, смотрящий на полотно.
		for px: float in [-2.0, 0.0, 2.0]:
			var from := Vector3(px, mid + 1.6, side * 0.2)
			var to := from + Vector3(0, 0.35, side * 1.15)
			EnvDress.kit_seg(k, from, to, 0.05, dark, Color(3.0, 0.5, 0, 0))
			EnvDress.kit_box(k, Vector3(0.36, 0.14, 0.26), to + Vector3(0, -0.05, 0), dark, Color(0, 0.5, 0, 0), Vector3(side * 0.6, 0, 0))
			EnvDress.kit_box(k, Vector3(0.3, 0.02, 0.2), to + Vector3(0, -0.13, -side * 0.04), Color(1.0, 0.93, 0.80), Color(0, 0.3, 3.0, 0), Vector3(side * 0.6, 0, 0))
	_part(root, Vector3(6.3, 0.06, 0.9), Vector3(0, mid - 1.75, 0.45), steel)
	for px in 7:
		EnvDress.kit_seg(k, Vector3(-3.0 + px, mid - 1.72, 0.88), Vector3(-3.0 + px, mid - 0.75, 0.88), 0.03, dark)
	EnvDress.kit_seg(k, Vector3(-3.1, mid - 0.75, 0.88), Vector3(3.1, mid - 0.75, 0.88), 0.035, dark)
	EnvDress.kit_snow(k, Vector3(6.2, 0.05, 0.6), Vector3(0, mid - 1.69, 0.5))
	EnvDress.kit_icicles(k, Vector3(-3.1, mid - 1.78, 0.9), Vector3(3.1, mid - 1.78, 0.9), 0.3, 77)
	EnvDress.kit_emit(k, root, "BillboardDress")
	root.add_child(_slab(Vector3(6.3, 0, 0.35), Vector3(0, mid + 1.72, 0), 0.14))
	return root


## Среда квартала (CITY-02 E): узел пакетов EnvDress создаётся при первом обращении.
func _env() -> EnvDress:
	if _environment == null:
		_environment = EnvDress.new()
		_environment.registry = break_visuals
		add_child(_environment)
	return _environment

## Панорама за краем карты (CITY-02 E): узел Skyline создаётся при первом обращении.
func _sky() -> Skyline:
	if _skyline == null:
		_skyline = Skyline.new()
		add_child(_skyline)
	return _skyline

## Позиция в осях гаражного ряда: along — вдоль ряда, y, out — от оси ряда к воротам.
static func _gpos(long_z: bool, along: float, y: float, out: float) -> Vector3:
	return Vector3(out, y, along) if long_z else Vector3(along, y, out)

static func _gsize(long_z: bool, along: float, y: float, out: float) -> Vector3:
	return Vector3(out, y, along) if long_z else Vector3(along, y, out)

## Хлам у ворот гаража: покрышки стопкой, доска у стены, канистра, ведро, поддон, сломанный стул — низко, у самых
## ворот (до 0,8 м от стены), без коллизий.
func _garage_clutter(k: Dictionary, long_z: bool, offset: float, face: float, side: float, height: float, seed: int) -> void:
	var base := -height * 0.5
	var x0 := offset + (_rand(seed, 1) - 0.5) * 1.6
	match int(_rand(seed, 2) * 4.0):
		0:
			for t in 2 + int(_rand(seed, 3) * 2.0):
				EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_scale(Vector3(0.62, 0.19, 0.62)), _gpos(long_z, x0, base + 0.1 + t * 0.19, face + side * 0.45)), Color(0.08, 0.08, 0.09), Color(0, 0.9, 0, 0))
			EnvDress.kit_lump(k, Vector3(0.5, 0.08, 0.5), _gpos(long_z, x0, base + 0.2 + 2 * 0.19, face + side * 0.45))
		1:
			EnvDress.kit_box(k, _gsize(long_z, 0.22, 1.7, 0.03), _gpos(long_z, x0, base + 0.82, face + side * 0.2), Color(0.42, 0.32, 0.20), Color(0, 0.95, 0, 0), Vector3(side * 0.18, 0, 0) if long_z else Vector3(0, 0, -side * 0.18))
			EnvDress.kit_box(k, _gsize(long_z, 0.2, 0.32, 0.12), _gpos(long_z, x0 + 0.4, base + 0.16, face + side * 0.3), Color(0.70, 0.12, 0.08), Color(0, 0.4, 0, 0))
		2:
			EnvDress.kit_box(k, _gsize(long_z, 1.1, 0.14, 0.75), _gpos(long_z, x0, base + 0.07, face + side * 0.5), Color(0.50, 0.40, 0.26), Color(1.0, 0.95, 0, 0))
			EnvDress.kit_lump(k, Vector3(1.0, 0.1, 0.7), _gpos(long_z, x0, base + 0.14, face + side * 0.5))
			EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_scale(Vector3(0.3, 0.32, 0.3)), _gpos(long_z, x0 + 0.75, base + 0.16, face + side * 0.35)), Color(0.30, 0.40, 0.55), Color(3.0, 0.5, 0, 0))
		3:
			var c := Color(0.35, 0.22, 0.14)
			EnvDress.kit_box(k, _gsize(long_z, 0.42, 0.04, 0.4), _gpos(long_z, x0, base + 0.42, face + side * 0.45), c, Color(0, 0.9, 0, 0), Vector3(0.0, 0.3, 0.25))
			for lx: float in [-0.18, 0.18]:
				EnvDress.kit_box(k, _gsize(long_z, 0.035, 0.42, 0.035), _gpos(long_z, x0 + lx, base + 0.21, face + side * 0.3), c, Color(0, 0.9, 0, 0))
			EnvDress.kit_box(k, _gsize(long_z, 0.4, 0.45, 0.03), _gpos(long_z, x0, base + 0.2, face + side * 0.68), c, Color(0, 0.9, 0, 0), Vector3(1.2, 0, 0) if not long_z else Vector3(0, 0, 1.2))

## Снаружи киоска (CITY-02 E): раздвижные решётки по краям окна, ступенька под окном, кондиционер с наледью на задней
## стене, телеантенна и кабель, наклейки и рукописный номер (ART-04, черта 15), снежный напуск и сосульки над окном,
## провод питания к опоре — в _build_wires. Всё на стенах или плоское: площадка киоска — зона стелса (ARENA-02, п. 1).
func _kiosk_outside(root: Node3D, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var k := EnvDress.kit()
	var floor_y := -hy
	var gh := size.y - 1.7
	for zs: float in [-1.0, 1.0]:
		EnvDress.kit_box(k, Vector3(0.04, gh + 0.1, 0.42), Vector3(hx + 0.06, floor_y + 1.0 + gh * 0.5, zs * (hz - 0.3)), Color(0.14, 0.15, 0.16), Color(2.0, 0, 0, 0))
		EnvDress.kit_box(k, Vector3(0.05, 0.05, 0.5), Vector3(hx + 0.06, floor_y + 1.0 + gh + 0.06, zs * (hz - 0.3)), Color(0.14, 0.15, 0.16), Color(0, 0.5, 0, 0))
	EnvDress.kit_box(k, Vector3(0.55, 0.14, size.z - 0.5), Vector3(hx + 0.28, floor_y + 0.07, 0), Color(0.46, 0.46, 0.45), Color(0, 0.95, 0, 0))   # ступенька
	EnvDress.kit_snow(k, Vector3(0.12, 0.05, size.z - 0.5), Vector3(hx + 0.5, floor_y + 0.16, 0))
	# Полка-прилавок снаружи под окном, со снегом по краю.
	EnvDress.kit_box(k, Vector3(0.3, 0.04, size.z - 0.3), Vector3(hx + 0.15, floor_y + 1.02, 0), Color(0.62, 0.58, 0.50), Color(3.0, 0.6, 0, 0))
	# Кондиционер на задней стене, решётка вентилятора, трубка конденсата и сосулька под ней.
	var ac := Vector3(-hx - 0.16, hy - 0.75, 0.9)
	EnvDress.kit_box(k, Vector3(0.3, 0.5, 0.8), ac, Color(0.80, 0.80, 0.78), Color(0, 0.5, 0, 0))
	EnvDress.kit_put(k, "cyl", Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)) * Basis.from_scale(Vector3(0.36, 0.02, 0.36)), ac + Vector3(-0.16, 0, 0.12)), Color(0.20, 0.20, 0.21), Color(2.0, 0, 0, 0))
	EnvDress.kit_snow(k, Vector3(0.32, 0.06, 0.82), ac + Vector3(0, 0.28, 0))
	EnvDress.kit_seg(k, ac + Vector3(0, -0.25, -0.3), ac + Vector3(-0.05, -1.2, -0.3), 0.02, Color(0.85, 0.85, 0.85))
	EnvDress.kit_put(k, "ice", Transform3D(Basis.from_scale(Vector3(0.08, 0.5, 0.08)), ac + Vector3(-0.05, -1.45, -0.3)))
	EnvDress.kit_lump(k, Vector3(0.5, 0.18, 0.5), Vector3(-hx - 0.35, floor_y, 0.6))   # наледь под капелью
	# Антенна на крыше: мачта, три перекладины, кабель по задней стене.
	var mast := Vector3(-hx + 0.4, hy + 0.12, -hz + 0.4)
	EnvDress.kit_seg(k, mast, mast + Vector3(0, 1.7, 0), 0.04, Color(0.55, 0.57, 0.58), Color(3.0, 0.5, 0, 0))
	for i in 3:
		var y := 1.0 + i * 0.28
		var l := 0.9 - i * 0.2
		EnvDress.kit_seg(k, mast + Vector3(-l * 0.5, y, 0.1 * i), mast + Vector3(l * 0.5, y, 0.1 * i), 0.02, Color(0.55, 0.57, 0.58), Color(3.0, 0.5, 0, 0))
	EnvDress.kit_seg(k, mast + Vector3(0, 0.3, 0), Vector3(-hx - 0.05, hy, -hz + 0.4), 0.015, Color(0.08, 0.08, 0.08))
	EnvDress.kit_seg(k, Vector3(-hx - 0.05, hy, -hz + 0.4), Vector3(-hx - 0.05, floor_y + 1.2, -hz + 0.4), 0.015, Color(0.08, 0.08, 0.08))
	# Наклейки: яркие полоски на боковых стенах и у окна.
	var stickers := [[1.0, 1.6, 0.6, 0.22, 0.12, Color(0.92, 0.80, 0.10)], [1.0, -0.2, 0.9, 0.16, 0.16, Color(0.15, 0.45, 0.80)],
		[-1.0, 0.9, 1.05, 0.3, 0.1, Color(0.85, 0.20, 0.15)], [-1.0, 1.8, 0.55, 0.12, 0.18, Color(0.20, 0.62, 0.30)],
		[1.0, 2.1, 1.2, 0.14, 0.09, Color(0.95, 0.95, 0.92)]]
	for st in stickers:
		EnvDress.kit_box(k, Vector3(st[3], st[4], 0.004), Vector3(-hx + st[1], floor_y + st[2], st[0] * (hz + 0.075)), st[5], Color(0, 0.5, 0, 0))
	var number := _label("№ 117", 64, Color(0.95, 0.95, 0.92))
	number.pixel_size = 0.004
	number.position = Vector3(-hx + 0.9, floor_y + 2.45, hz + 0.08)
	root.add_child(number)
	# Снег свисает с козырька над окном, сосульки по кромке.
	EnvDress.kit_snow(k, Vector3(0.22, 0.12, size.z + 0.5), Vector3(hx + 0.62, hy + 0.12, 0), Vector3(0, 0, -0.35))
	EnvDress.kit_icicles(k, Vector3(hx + 0.6, hy, -hz - 0.25), Vector3(hx + 0.6, hy, hz + 0.25), 0.4, 117)
	EnvDress.kit_icicles(k, Vector3(-hx - 0.0, hy, -hz - 0.3), Vector3(hx + 0.6, hy, -hz - 0.3), 0.25, 118, 0.22)
	EnvDress.kit_emit(k, root, "KioskOutside")
	# Ценники за стеклом рядом с «Батон 35» (там же, где он).
	var tags := [["Бородинский\n52 р.", -1.35], ["Кирпичик\n38 р.", 0.95]]
	for tg in tags:
		var at := Vector3(hx - 0.07, floor_y + 1.2, tg[1])
		_part(root, Vector3(0.01, 0.2, 0.36), at, Materials.plain(Color(0.95, 0.94, 0.88), 0.9))
		var label := _label(tg[0], 34, Color(0.12, 0.10, 0.10))
		label.pixel_size = 0.0028
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.position = at + Vector3(0.008, 0, 0)
		label.rotation.y = PI * 0.5
		root.add_child(label)

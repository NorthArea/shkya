extends Node3D
## CITY-02 B: дома города Н. как настоящие. Панельки серии 97 и девятиэтажки, кирпичные дома, старые дома со
## скатной крышей (ART-04, черты 1–7, 22; ART-06, Н10, Н11): лоджии и балконы разных эпох (плита, ограждение —
## бетон, решётка или профлист, остекление деревом, белым ПВХ, алюминием, обшивка) и хлам на них, подоконники
## с отливом и снегом, кондиционеры и тарелки, цоколь с отливом, парапет и крыша с лифтовыми будками,
## вентшахтами, грибками и антеннами; у старых домов — скатная крыша с фронтонами, трубами, слуховыми окнами,
## водостоками и сосульками; подъезды с козырьком, лампой, домофоном и доской объявлений.
##
## Только вид: коллизии — коробки Layout (C9), всё здесь без коллизий. Повторы — MultiMesh общими пакетами;
## мелочь (хлам, тарелки, сосульки, банки) — в ближних пакетах по клеткам NEAR_CELL, дальше NEAR_RANGE от камеры
## они скрыты. Раскладка — по seed дома (_rand), без случайностей. Формы — своя геометрия по описаниям ART-04/06.

const Layout = preload("res://game/world/layout.gd")
const Greybox = preload("res://game/world/greybox.gd")
const Materials = preload("res://game/world/materials.gd")

const WARM := Color(1.0, 0.75, 0.42)           # подъезд и окна
const CONCRETE := Color(0.50, 0.51, 0.52)
# Лоджии: ограждения разного цвета, остекление разное у каждой (сверка ART-04, черты 1, 4).
const PARAPET_COLORS := [Color(0.55, 0.56, 0.57), Color(0.66, 0.64, 0.58), Color(0.40, 0.45, 0.52), Color(0.58, 0.44, 0.38),
	Color(0.72, 0.72, 0.70), Color(0.47, 0.49, 0.44)]
const GRILLE_COLORS := [Color(0.13, 0.14, 0.15), Color(0.20, 0.30, 0.22), Color(0.18, 0.26, 0.40), Color(0.36, 0.22, 0.16)]
const PROF_COLORS := [Color(0.80, 0.76, 0.62), Color(0.84, 0.84, 0.82), Color(0.42, 0.26, 0.18), Color(0.30, 0.42, 0.55), Color(0.55, 0.62, 0.45)]
const FRAME_WHITE := Color(0.86, 0.87, 0.86)
const FRAME_WOOD := [Color(0.36, 0.26, 0.18), Color(0.78, 0.77, 0.72)]   # крашеное дерево: коричневое и старое белое
const FRAME_ALU := Color(0.72, 0.74, 0.76)
const GLASS_DARK := Color(0.08, 0.10, 0.13)
const GLASS_TINT := {"wood": Color(0.07, 0.09, 0.08), "pvc": Color(0.08, 0.10, 0.13), "alu": Color(0.09, 0.12, 0.17), "clad": Color(0.08, 0.10, 0.13)}
const GLASS_LIT := [Color(1.0, 0.70, 0.36), Color(0.95, 0.66, 0.40), Color(0.78, 0.78, 0.70)]   # без белых «прожекторов» в glow
const METAL := Color(0.60, 0.62, 0.64)          # оцинкованные отливы, водостоки, колпаки
const SILL_SNOW_GAP := 0.12                      # доля подоконников без снега (сдуло или растаяло)
const PLINTH_COLORS := [Color(0.33, 0.33, 0.34), Color(0.40, 0.31, 0.27), Color(0.30, 0.34, 0.32), Color(0.38, 0.37, 0.35)]
const DOOR_COLORS := [Color(0.32, 0.22, 0.15), Color(0.20, 0.28, 0.22), Color(0.25, 0.30, 0.38), Color(0.30, 0.30, 0.31)]
const CLOTH := [Color(0.92, 0.92, 0.90), Color(0.60, 0.75, 0.90), Color(0.90, 0.60, 0.70), Color(0.92, 0.82, 0.40), Color(0.75, 0.22, 0.20), Color(0.35, 0.55, 0.35)]
const SKIS := [Color(0.80, 0.15, 0.12), Color(0.15, 0.30, 0.65), Color(0.85, 0.75, 0.15), Color(0.20, 0.20, 0.22)]
const CARDBOARD := Color(0.55, 0.42, 0.28)
const BRICK_RED := Color(0.48, 0.26, 0.18)
const ICE := Color(0.80, 0.88, 0.95)
const ENTRANCE_WALL_Z := 107.98   # северный фасад H1 (центр 115, глубина 14) — z = 108
const ENTRANCE_DOOR_X := -40.0    # дверь по центру козырька
const ENTRY_TOP := 2.9            # верх козырька декоративного подъезда: от него идёт полоса лестничной клетки

# Кирпичные дома (ART-04, черта 4: хрущёвки панельные и кирпичные; ART-06, Н11: кирпичные башни с белыми поясами).
# Значение — пояса по перекрытиям.
const BRICK := {"H9_NorthEnd": false, "H11_West": true}
# Сторона подъездов: во двор или к тихой стороне; у домов с магазинами первого этажа подъездов на виду нет.
const ENTRANCE_SIDE := {"H1_South": -1.0, "H2_West": 1.0, "H3_North": 1.0, "H4_SouthEast": 1.0, "H7_Middle": -1.0,
	"H9_NorthEnd": 1.0, "H10_NorthWest": 1.0, "H11_West": 1.0}
# Столбы лоджий по номеру колонки (k + 3 × номер дома) mod 10: у каждого дома свой ритм (парами — ART-04, черта 1).
const PANEL_PATTERNS := [[1, 2, 7, 8], [1, 2, 3, 7, 8, 9], [0, 1, 8, 9], [2, 3, 7, 8], [1, 2, 6, 7, 8]]
const LOW_PATTERNS := [[2, 3, 7], [1, 2, 7, 8], [3, 4, 8]]

## LIFE-01: точки дверей подъездов на стене (x, 0, z), которые построил _entrance_kit — тест сверяет с ними двери жителей.
static var door_log: Array[Vector3] = []

## Входы магазинов строятся у тех же целей, к которым действительно подходят жители.
## Дверь «ПРОДУКТОВ 24» — часть собственного павильона LevelGeometry._shop24.
func build_store_entrances() -> void:
	for spot in Layout.LIFE_SPOTS:
		if spot[1] != &"shop" or spot[0] == &"shop24":
			continue
		var facing := Vector3(-sin(spot[4]), 0.0, -cos(spot[4]))
		var out := -facing
		var right := Vector3(out.z, 0.0, -out.x)
		var basis := Basis(right, Vector3.UP, out)
		var p: Vector2 = spot[3]
		var at := Vector3(p.x, 0.0, p.y) + facing * 0.58
		var entrance := Node3D.new()
		entrance.name = "StoreEntrance_%s" % spot[0]
		entrance.transform = Transform3D(basis, at)
		add_child(entrance)
		# Узел отмечает настоящий порог; детали входят в существующие общие пакеты.
		for item in [
			[Vector3(1.45, 2.35, 0.1), Vector3(0, 1.175, 0), Color(0.11, 0.14, 0.14)],
			[Vector3(1.12, 2.15, 0.05), Vector3(0, 1.075, 0.07), Color(0.23, 0.28, 0.25)],
			[Vector3(0.83, 1.2, 0.04), Vector3(0, 1.42, 0.11), Color(0.12, 0.14, 0.14)],
			[Vector3(0.045, 0.32, 0.08), Vector3(0.39, 1.03, 0.17), METAL],
			[Vector3(1.85, 0.14, 0.75), Vector3(0, 2.43, 0.3), CONCRETE],
			[Vector3(1.85, 0.10, 0.75), Vector3(0, 2.55, 0.3), Color(0.88, 0.90, 0.94)],
			[Vector3(1.35, 0.025, 0.58), Vector3(0, 0.035, 0.35), Color(0.27, 0.23, 0.20)]]:
			var size: Vector3 = item[0]
			var offset: Vector3 = item[1]
			_put("paint", Transform3D(basis * Basis.from_scale(size), at + basis * offset), item[2])

const NEAR_CELL := 30.0    # клетка ближних пакетов, м (меньше узлов и draw call)
const NEAR_RANGE := 60.0   # дальше — мелочь скрыта (C9: LOD по расстоянию)

# Пакеты: имя → [сетка, материал, тени].
const BATCHES := {
	"slab": ["box", "concrete", true],    # плиты лоджий и боковые стенки — отбрасывают тень, как раньше
	"paint": ["box", "detail", false],    # ограждения, рамы, цоколь, парапеты, будки, двери, кондиционеры
	"glass": ["box", "glass", false],
	"snow": ["box", "snow", false],
	"lump": ["lump", "snow", false],      # сугробы у подъездов, наледь у водостоков, снег на крыше
	"pipe": ["cyl", "detail", false],     # водостоки, мачты антенн, грибки
	"snow_disc": ["cyl", "snow", false],
	"prism": ["prism", "snow", false],    # крыши слуховых окон
	"clutter": ["box", "detail", false],  # ближние: хлам, бельё, авоськи
	"icicle": ["cone", "detail", false],  # ближние: сосульки
	"dish": ["dish", "detail", false],    # ближние: тарелки
	"rod": ["cyl", "detail", false],      # ближние: кронштейны, банки, покрышки, вентиляторы
}
const NEAR := ["clutter", "icicle", "dish", "rod"]

var _geo                    # LevelGeometry: пар (_steam_puff), надписи (_label), сугробы (_lumpy_bank)
var _batches := {}
var _near := {}
var _meshes := {}

func _init(geo) -> void:
	_geo = geo
	name = "Buildings"

# --- дом ---

## Одежда дома: материал фасада, лоджии и окна по колонкам, подъезды, цоколь, крыша. Коллизия — коробка body.
func dress_house(house_name: String, low: bool, xz: Vector2, size: Vector3, index: int, body: Node3D, mesh: MeshInstance3D, shops: bool, series_97: bool) -> void:
	var brick := BRICK.has(house_name)
	if brick:
		mesh.material_override = Materials.facade_brick(float(index), low, BRICK[house_name])
	else:
		mesh.material_override = Materials.facade(float(index), low, shops)
		if series_97:
			(mesh.material_override as ShaderMaterial).set_shader_parameter("stripes", 1.0)
	var seed := index * 101 + 7
	var long_x := size.x >= size.z
	var h := {
		"name": house_name, "low": low, "index": index, "xz": xz, "size": size, "shops": shops, "seed": seed, "long_x": long_x,
		"floor_h": 3.3 if low else 2.8, "spacing": 2.6 if low else 3.0, "ww": 1.1 if low else 1.4, "wh": 1.8 if low else 1.45,
		"wall": Materials.LOW_PALETTES[0][0] if brick else Materials.facade_wall(float(index), low),
		"accent": Materials.facade_accent(float(index), low),
		# «Эпоха» дома: у старых больше деревянных рам и открытых балконов, у новых — ПВХ, алюминий, обшивка.
		"era": 0.15 + 0.3 * _rand(seed, 1) if low else 0.35 + 0.6 * _rand(seed, 1),
		"loggia": 0.0 if low else 0.25 + 0.5 * _rand(seed, 2),
		"grille": 0.15 + 0.3 * _rand(seed, 3),
		"prof": 0.1 + 0.25 * _rand(seed, 4),
	}
	h["storeys"] = int(floor(size.y / h.floor_h + 0.01))
	var length: float = size.x if long_x else size.z
	var depth: float = size.z if long_x else size.x
	var along_c: float = xz.x if long_x else xz.y
	var along0 := along_c - length * 0.5
	var spacing: float = h.spacing
	var first := int(ceil((along0 + 0.6) / spacing))
	var last := int(floor((along0 + length - 0.6) / spacing)) - 1
	var patterns: Array = LOW_PATTERNS if low else PANEL_PATTERNS
	var pattern: Array = patterns[posmod(index, patterns.size())]
	var doors := {}   # сторона → центры дверей (цоколь их обходит)
	for f in _faces(xz, size, long_x):
		var side: float = f.side
		var wall: float = f.wall
		var entr: bool = f.long and ENTRANCE_SIDE.get(house_name, 0.0) == side
		var door_u: Array[float] = []
		var wx0: float = (spacing - h.ww) * 0.5
		for k in range(int(floor(f.u0 / spacing)) - 1, int(floor(f.u1 / spacing)) + 1):
			# Только целые окна: проём не заходит за угол дома.
			if k * spacing + wx0 < f.u0 + 0.05 or k * spacing + wx0 + h.ww > f.u1 - 0.05:
				continue
			var u := (k + 0.5) * spacing
			if not f.long or k < first or k > last:
				_window_column(h, f, u, k, 0)
				continue
			var m := posmod(k + index * 3, 10)
			if house_name == "H1_South" and side < 0.0 and absf(u - ENTRANCE_DOOR_X) < 4.6:
				# Подъезд Бабки (_build_entrance): полоса над козырьком, дверь и таблички остаются видны.
				if absf(u - ENTRANCE_DOOR_X) < spacing * 0.5:
					_stair_strip(h, f, u, k, Layout.CANOPY[0].y + 0.3)
				continue
			var door := m == 5 and entr
			if door:
				_entrance_kit(h, f, u, seed + k)
				door_u.append(u)
			if m == 5 and not low:
				_stair_strip(h, f, u, k, ENTRY_TOP + 0.2 if door else 0.0)
			elif m in pattern:
				var loggia := _rand(seed + int(floor(k / 2.0)) * 7, 9) < float(h.loggia)
				for s in range(1, h.storeys):
					_balcony(h, f, u, s, s == h.storeys - 1, loggia, k * 31 + s * 7 + index)
				if not door:
					_window_column(h, f, u, k, 0, 1)
			else:
				_window_column(h, f, u, k, 1 if door else 0)
		if house_name == "H1_South" and side < 0.0:
			door_u.append(ENTRANCE_DOOR_X)
		doors[f] = door_u
	_plinth(h, doors)
	if low:
		_pitched_roof(h, body)
	else:
		_flat_roof(h, body)

## Четыре фасада коробки: длинные (лоджии, подъезды) и торцы. u — координата вдоль фасада в мире.
static func _faces(xz: Vector2, size: Vector3, long_x: bool) -> Array:
	var length := size.x if long_x else size.z
	var depth := size.z if long_x else size.x
	var along_c := xz.x if long_x else xz.y
	var across_c := xz.y if long_x else xz.x
	var faces := []
	for side: float in [-1.0, 1.0]:
		faces.append({"long_x": long_x, "wall": across_c + side * depth * 0.5, "side": side, "u0": along_c - length * 0.5, "u1": along_c + length * 0.5, "long": true})
	for side: float in [-1.0, 1.0]:
		faces.append({"long_x": not long_x, "wall": along_c + side * length * 0.5, "side": side, "u0": across_c - depth * 0.5, "u1": across_c + depth * 0.5, "long": false})
	return faces

## Колонка обычных окон с этажа from_s до верха (to_s — не включая; −1 — до последнего целого этажа): отлив со
## снегом, у части — кондиционер под окном и авоська за окном (северный холодильник).
func _window_column(h: Dictionary, f: Dictionary, u: float, k: int, from_s: int, to_s := -1) -> void:
	var long_x: bool = f.long_x
	var wall: float = f.wall
	var side: float = f.side
	var floor_h: float = h.floor_h
	var ww: float = h.ww
	var size: Vector3 = h.size
	var top_s: int = h.storeys if to_s < 0 else to_s
	for s in range(from_s, top_s):
		if s == 0 and h.shops:
			continue
		var y := s * floor_h + 0.85
		if y + h.wh > size.y - 0.05:
			break
		var seed: int = int(h.seed) * 7 + k * 53 + s * 11 + (0 if side < 0.0 else 5) + (0 if f.long else 900)
		_put("paint", _box_xf(Vector3(ww + 0.1, 0.03, 0.13), u, y - 0.015, wall + side * 0.055, long_x), METAL, Color(3, 0, 0))
		if _rand(seed, 1) > SILL_SNOW_GAP:
			var t := 0.03 + 0.05 * _rand(seed, 2)
			_put("snow", _box_xf(Vector3(ww + 0.04, t, 0.11), u, y + t * 0.5, wall + side * 0.06, long_x))
		if s >= 1 and _rand(seed, 3) < 0.06:
			_air_conditioner(f, u + (0.45 if _rand(seed, 4) < 0.5 else -0.45), y - 0.55, 0.16, seed)
		elif s >= 1 and _rand(seed, 5) < 0.025:
			# Авоська с продуктами на гвозде за окном.
			_put_near("clutter", _box_xf(Vector3(0.28, 0.32, 0.14), u + 0.4, y + 0.3, wall + side * 0.09, long_x), CLOTH[int(_rand(seed, 6) * 2.0)])

## Внешний блок кондиционера: корпус, решётка вентилятора, снег сверху (cx — центр вдоль фасада, y — низ).
func _air_conditioner(f: Dictionary, u: float, y: float, out: float, seed: int) -> void:
	var long_x: bool = f.long_x
	var w: float = f.wall + f.side * out
	_put("paint", _box_xf(Vector3(0.8, 0.52, 0.28), u, y + 0.26, w, long_x), Color(0.86, 0.87, 0.86), Color(0, 0.5, 0))
	_put_near("rod", Transform3D(_face_basis(long_x, f.side) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.36, 0.02, 0.36)), _at(long_x, u - 0.12, y + 0.26, w + f.side * 0.14)), Color(0.22, 0.22, 0.24))
	_put("snow", _box_xf(Vector3(0.8, 0.04 + 0.03 * _rand(seed, 7), 0.26), u, y + 0.54, w, long_x))

## Полоса лестничной клетки: панель акцентного цвета поверх ряда окон, мелкие окна со сдвигом на полэтажа.
func _stair_strip(h: Dictionary, f: Dictionary, u: float, seed: int, from_y := 0.0) -> void:
	var long_x: bool = f.long_x
	var wall: float = f.wall
	var side: float = f.side
	var height: float = h.size.y
	var floor_h: float = h.floor_h
	var hh := height - 0.1 - from_y
	_put("paint", _box_xf(Vector3(h.spacing - 0.2, hh, 0.1), u, from_y + hh * 0.5, wall + side * 0.06, long_x), h.accent)
	for s in range(0, h.storeys - 1):
		var lit := fposmod(sin(float(seed * 7 + s) * 12.9898) * 43758.5453, 1.0) < 0.55
		var glass := Color(0.95, 0.85, 0.62, 1.0) if lit else Color(GLASS_DARK.r, GLASS_DARK.g, GLASS_DARK.b, 0.0)
		var y := (s + 1) * floor_h + 0.15
		if y + 0.3 > height:
			break
		if y - 0.3 < from_y:
			continue
		_put("glass", _box_xf(Vector3(1.3, 0.55, 0.04), u, y, wall + side * 0.12, long_x), glass)
		_put("paint", _box_xf(Vector3(1.4, 0.06, 0.06), u, y - 0.3, wall + side * 0.13, long_x), FRAME_WHITE, Color(0, 0.5, 0))
		_put("snow", _box_xf(Vector3(1.36, 0.04, 0.06), u, y - 0.25, wall + side * 0.14, long_x))

# --- лоджии и балконы ---

## Остекление по эпохе дома: открытый балкон, старое дерево, белый ПВХ, «холодный» алюминий, обшивка с ПВХ.
func _glazing(h: Dictionary, seed: int) -> String:
	var e: float = h.era
	var r := _rand(seed * 13, 2)
	var open := 0.16 + 0.14 * (1.0 - e)
	var wood := open + 0.08 + 0.22 * (1.0 - e)
	var alu := wood + 0.12
	var clad := alu + 0.04 + 0.14 * e
	if r < open:
		return "open"
	if r < wood:
		return "wood"
	if r < alu:
		return "alu"
	if r < clad:
		return "clad"
	return "pvc"

## Лоджия или балкон одного этажа: плита, ограждение, остекление своей эпохи, хлам, тарелка, кондиционер;
## у верхней — козырёк со снегом и сосульками. loggia — боковые бетонные стенки на всю высоту этажа.
func _balcony(h: Dictionary, f: Dictionary, u: float, storey: int, top: bool, loggia: bool, seed: int) -> void:
	var long_x: bool = f.long_x
	var wall: float = f.wall
	var side: float = f.side
	var floor_h: float = h.floor_h
	var w: float = h.spacing - 0.12
	var d := 1.2 if loggia else 1.1
	var y := storey * floor_h
	_put("slab", _box_xf(Vector3(w, 0.12, d), u, y - 0.06, wall + side * d * 0.5, long_x))
	if loggia:
		for e: float in [-1.0, 1.0]:
			_put("slab", _box_xf(Vector3(0.12, floor_h - 0.12, d), u + e * (w * 0.5 - 0.06), y + (floor_h - 0.12) * 0.5, wall + side * d * 0.5, long_x))
	var glazing := _glazing(h, seed)
	var kind := "panel"
	var color: Color = PARAPET_COLORS[int(_rand(seed * 13, 1) * PARAPET_COLORS.size()) % PARAPET_COLORS.size()]
	var r := _rand(seed * 13, 6)
	if glazing == "clad" or (glazing != "open" and r < h.prof * 0.5) or (glazing == "open" and r > 1.0 - h.prof):
		kind = "prof"
		color = PROF_COLORS[int(_rand(seed * 13, 7) * PROF_COLORS.size()) % PROF_COLORS.size()]
	elif r < h.grille:
		kind = "grille"
		color = GRILLE_COLORS[int(_rand(seed * 13, 7) * GRILLE_COLORS.size()) % GRILLE_COLORS.size()]
	var custom := Color({"panel": 0.0, "prof": 1.0, "grille": 2.0}[kind], 0, 0)
	var rh := 1.0
	var inner := 0.06 if loggia else 0.0   # у лоджии ограждение между стенками
	_put("paint", _box_xf(Vector3(w - inner * 2.0, rh, 0.05), u, y + rh * 0.5, wall + side * (d - 0.025), long_x), color, custom)
	if not loggia:
		for e: float in [-1.0, 1.0]:
			_put("paint", _box_xf(Vector3(0.05, rh, d - 0.05), u + e * (w * 0.5 - 0.025), y + rh * 0.5, wall + side * (d - 0.05) * 0.5, long_x), color, custom)
	if kind == "grille":
		# Поручень поверх прутьев.
		_put("paint", _box_xf(Vector3(w, 0.05, 0.07), u, y + rh + 0.025, wall + side * (d - 0.03), long_x), color)
		rh += 0.05
	if glazing == "open":
		if _rand(seed, 21) > 0.2:
			_put("snow", _box_xf(Vector3(w - inner * 2.0, 0.04 + 0.04 * _rand(seed, 22), 0.09), u, y + rh + 0.03, wall + side * (d - 0.03), long_x))
		_clutter_open(h, f, u, y, w, d, seed)
	else:
		_glass_frames(f, u, y + rh, w - inner * 2.0, floor_h - rh - 0.12, d, glazing, seed)
		_clutter_glazed(f, u, y, w, d, seed)
	if _rand(seed, 30) < 0.05:
		_dish(f, u + w * 0.3, y + rh + 0.15, d + 0.18, seed)
	elif _rand(seed, 31) < 0.05:
		_air_conditioner(f, u - w * 0.22, y + 0.35, d + 0.16, seed)
	if top:
		_put("slab", _box_xf(Vector3(w, 0.12, d), u, y + floor_h - 0.06, wall + side * d * 0.5, long_x))
		_put("snow", _box_xf(Vector3(w - 0.04, 0.08 + 0.08 * _rand(seed, 32), d - 0.06), u, y + floor_h + 0.06, wall + side * d * 0.5, long_x))
		_icicles(f, u - w * 0.5 + 0.1, u + w * 0.5 - 0.1, y + floor_h - 0.12, d - 0.05, 0.45, seed)

## Остекление лоджии над ограждением: стекло (горит у ~30 %) и импосты своей эпохи.
func _glass_frames(f: Dictionary, u: float, y0: float, w: float, gh: float, d: float, glazing: String, seed: int) -> void:
	var long_x: bool = f.long_x
	var wall: float = f.wall
	var side: float = f.side
	var lit := _rand(seed * 13, 3) < 0.3
	var tint: Color = GLASS_TINT[glazing]
	var glass := Color(tint.r, tint.g, tint.b, 0.0)
	if lit:
		var c: Color = GLASS_LIT[int(_rand(seed * 13, 8) * GLASS_LIT.size()) % GLASS_LIT.size()]
		glass = Color(c.r, c.g, c.b, 1.0)
	_put("glass", _box_xf(Vector3(w - 0.06, gh, 0.03), u, y0 + gh * 0.5, wall + side * (d - 0.03), long_x), glass)
	var frame := FRAME_WHITE
	var custom := Color(0, 0.5, 0)
	var sections := 3 + int(_rand(seed * 13, 5) * 2.0)
	var bar := 0.05
	match glazing:
		"wood":
			frame = FRAME_WOOD[int(_rand(seed * 13, 4) * 2.0)]
			custom = Color(0, 0.75, 0)
			sections = maxi(4, int(round(w / 0.55)))
			bar = 0.06
			# Фрамуги сверху — у старых рам горизонтальный импост.
			_put("paint", _box_xf(Vector3(w, 0.045, 0.06), u, y0 + gh * 0.7, wall + side * (d - 0.02), long_x), frame, custom)
		"alu":
			frame = FRAME_ALU
			custom = Color(3, 0, 0)
			sections = 5 + int(_rand(seed * 13, 5) * 2.0)
			bar = 0.035
	for i in sections + 1:
		var fu := u - w * 0.5 + w * float(i) / sections
		_put("paint", _box_xf(Vector3(bar, gh, 0.06), fu, y0 + gh * 0.5, wall + side * (d - 0.02), long_x), frame, custom)
	_put("paint", _box_xf(Vector3(w, 0.06, 0.06), u, y0 + gh, wall + side * (d - 0.02), long_x), frame, custom)
	_put("paint", _box_xf(Vector3(w, 0.05, 0.07), u, y0 + 0.025, wall + side * (d - 0.02), long_x), frame, custom)

## Хлам открытого балкона: бельё на верёвке (замёрзшее), лыжи, санки, коробки, покрышка, банки на перилах.
func _clutter_open(h: Dictionary, f: Dictionary, u: float, y: float, w: float, d: float, seed: int) -> void:
	var long_x: bool = f.long_x
	var wall: float = f.wall
	var side: float = f.side
	if _rand(seed, 40) < 0.45:
		var line_y: float = y + h.floor_h - 0.45
		_put_near("clutter", _box_xf(Vector3(w - 0.2, 0.012, 0.012), u, line_y, wall + side * (d - 0.3), long_x), Color(0.85, 0.85, 0.85))
		var n := 3 + int(_rand(seed, 41) * 3.0)
		for i in n:
			var cw := 0.22 + 0.3 * _rand(seed, 42 + i)
			var ch := 0.3 + 0.4 * _rand(seed, 50 + i)
			var cu := u - w * 0.5 + 0.25 + (w - 0.5) * (float(i) + 0.5) / n
			_put_near("clutter", _box_xf(Vector3(cw, ch, 0.012), cu, line_y - ch * 0.5, wall + side * (d - 0.3), long_x), CLOTH[int(_rand(seed, 60 + i) * CLOTH.size()) % CLOTH.size()])
	_skis_and_boxes(f, u, y, w, d, seed)
	if _rand(seed, 70) < 0.12:
		# Санки, прислонённые к ограждению.
		_put_near("clutter", Transform3D(_face_basis(long_x, side) * Basis(Vector3.RIGHT, -0.2) * Basis.from_scale(Vector3(0.38, 0.85, 0.05)), _at(long_x, u + w * 0.15, y + 0.43, wall + side * (d - 0.18))), SKIS[int(_rand(seed, 71) * 3.0)])
	if _rand(seed, 72) < 0.1:
		_put_near("rod", Transform3D(_face_basis(long_x, side) * Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(0.6, 0.2, 0.6)), _at(long_x, u - w * 0.2, y + 0.3, wall + side * 0.4)), Color(0.07, 0.07, 0.08))
	if _rand(seed, 73) < 0.15:
		for i in 2 + int(_rand(seed, 74) * 2.0):
			_put_near("rod", _box_xf(Vector3(0.1, 0.16, 0.1), u - w * 0.3 + i * 0.16, y + 1.13, wall + side * (d - 0.03), long_x), [Color(0.35, 0.50, 0.30), Color(0.70, 0.25, 0.18), Color(0.80, 0.70, 0.40)][i % 3])

## За стеклом: штабель коробок и лыжи — силуэты над ограждением.
func _clutter_glazed(f: Dictionary, u: float, y: float, w: float, d: float, seed: int) -> void:
	_skis_and_boxes(f, u, y, w, d, seed + 500)

func _skis_and_boxes(f: Dictionary, u: float, y: float, w: float, d: float, seed: int) -> void:
	var long_x: bool = f.long_x
	var wall: float = f.wall
	var side: float = f.side
	if _rand(seed, 80) < 0.14:
		var e := 1.0 if _rand(seed, 81) < 0.5 else -1.0
		var color: Color = SKIS[int(_rand(seed, 82) * SKIS.size()) % SKIS.size()]
		for i in 2:
			_put_near("clutter", Transform3D(_face_basis(long_x, side) * Basis(Vector3.BACK, e * 0.12) * Basis.from_scale(Vector3(0.075, 1.75, 0.02)), _at(long_x, u + e * (w * 0.5 - 0.3 - i * 0.1), y + 0.9, wall + side * (0.3 + i * 0.05))), color)
	if _rand(seed, 83) < 0.35:
		var n := 1 + int(_rand(seed, 84) * 3.0)
		var base := y
		for i in n:
			var bw := 0.4 + 0.25 * _rand(seed, 85 + i)
			var bh := 0.3 + 0.25 * _rand(seed, 90 + i)
			_put_near("clutter", _box_xf(Vector3(bw, bh, 0.4), u - w * 0.25 + 0.05 * i, base + bh * 0.5, wall + side * 0.35, long_x), CARDBOARD * (0.85 + 0.3 * _rand(seed, 95 + i)))
			base += bh

## Спутниковая тарелка на кронштейне: чаша смотрит наружу и вверх.
func _dish(f: Dictionary, u: float, y: float, out: float, seed: int) -> void:
	var long_x: bool = f.long_x
	var basis := _face_basis(long_x, f.side)
	var at := _at(long_x, u, y, f.wall + f.side * out)
	_put_near("dish", Transform3D(basis * Basis(Vector3.UP, (_rand(seed, 33) - 0.5) * 0.8) * Basis(Vector3.RIGHT, 0.95) * Basis.from_scale(Vector3(0.6, 0.1, 0.6)), at), Color(0.86, 0.87, 0.87), Color(0, 0.4, 0))
	_put_near("rod", Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.04, 0.35, 0.04)), _at(long_x, u, y - 0.1, f.wall + f.side * (out - 0.18))), Color(0.3, 0.3, 0.32))

## Сосульки вдоль кромки (u0…u1) на высоте y, вынос out от стены; max_len — самая длинная.
func _icicles(f: Dictionary, u0: float, u1: float, y: float, out: float, max_len: float, seed: int) -> void:
	var long_x: bool = f.long_x
	var w: float = f.wall + f.side * out
	var u := u0 + 0.2 * _rand(seed, 100)
	var i := 0
	while u < u1:
		var r := _rand(seed, 101 + i)
		if r < 0.75:
			var length := 0.08 + max_len * r * r * 1.6
			var radius := 0.02 + 0.03 * _rand(seed, 140 + i)
			_put_near("icicle", Transform3D(Basis.from_scale(Vector3(radius * 2.0, length, radius * 2.0)), _at(long_x, u, y - length * 0.5, w)), ICE, Color(0, 0.15, 0))
		u += 0.18 + 0.6 * _rand(seed, 180 + i)
		i += 1

# --- подъезды ---

## Подъезд другого дома (вид, без коллизий): дверь в проёме, ступени, козырёк со снегом и сосульками, лампа,
## домофон, доска объявлений, сугробы по бокам.
func _entrance_kit(h: Dictionary, f: Dictionary, u: float, seed: int) -> void:
	var long_x: bool = f.long_x
	var wall: float = f.wall
	var side: float = f.side
	door_log.append(Vector3(u, 0.0, wall) if long_x else Vector3(wall, 0.0, u))   # LIFE-01: сверка Layout.LIFE_SPOTS с дверями
	var basis := _face_basis(long_x, side)
	_put("paint", _box_xf(Vector3(1.6, 2.4, 0.03), u, 1.2, wall + side * 0.015, long_x), Color(0.09, 0.08, 0.08))
	_put("paint", _box_xf(Vector3(1.25, 2.15, 0.05), u, 1.075, wall + side * 0.04, long_x), DOOR_COLORS[int(_rand(seed, 1) * DOOR_COLORS.size()) % DOOR_COLORS.size()], Color(3, 0, 0))
	_put("paint", _box_xf(Vector3(1.7, 0.1, 0.07), u, 2.45, wall + side * 0.035, long_x), Color(0.30, 0.30, 0.31))
	var hand := 1.0 if _rand(seed, 2) < 0.5 else -1.0
	_put("paint", _box_xf(Vector3(0.05, 0.3, 0.06), u + hand * 0.45, 1.05, wall + side * 0.09, long_x), Color(0.6, 0.6, 0.58), Color(3, 0, 0))
	# Домофон с клавиатурой и красным огоньком — по другую сторону от ручки.
	_put("paint", _box_xf(Vector3(0.17, 0.27, 0.05), u - hand * 0.98, 1.35, wall + side * 0.025, long_x), Color(0.24, 0.24, 0.26), Color(3, 0, 0))
	_put("paint", _box_xf(Vector3(0.11, 0.12, 0.012), u - hand * 0.98, 1.3, wall + side * 0.055, long_x), Color(0.62, 0.62, 0.60))
	_put("paint", _box_xf(Vector3(0.025, 0.025, 0.012), u - hand * 0.98, 1.43, wall + side * 0.055, long_x), Color(1.0, 0.1, 0.05), Color(0, 0.4, 4.0))
	# Доска объявлений: рамка и листки.
	var bu := u + hand * 1.35
	_put("paint", _box_xf(Vector3(0.75, 0.6, 0.03), bu, 1.55, wall + side * 0.015, long_x), Color(0.22, 0.30, 0.24))
	for i in 3 + int(_rand(seed, 3) * 2.0):
		var pw := 0.16 + 0.1 * _rand(seed, 4 + i)
		var ph := 0.18 + 0.12 * _rand(seed, 10 + i)
		_put("paint", _box_xf(Vector3(pw, ph, 0.006), bu - 0.24 + 0.16 * i + 0.04 * _rand(seed, 16 + i), 1.5 + 0.12 * (_rand(seed, 20 + i) - 0.5), wall + side * 0.034, long_x),
			[Color(0.88, 0.87, 0.82), Color(0.82, 0.86, 0.90), Color(0.92, 0.88, 0.70)][i % 3])
	# Ступени, козырёк, кронштейны, лампа.
	_put("paint", _box_xf(Vector3(2.4, 0.15, 1.1), u, 0.075, wall + side * 0.55, long_x), Color(0.46, 0.46, 0.45))
	_put("snow", _box_xf(Vector3(2.4, 0.03, 0.3), u, 0.165, wall + side * 0.95, long_x))
	var cy := ENTRY_TOP - 0.17
	_put("paint", _box_xf(Vector3(2.8, 0.16, 1.5), u, cy, wall + side * 0.75, long_x), Color(0.44, 0.45, 0.46))
	_put("paint", _box_xf(Vector3(2.8, 0.28, 0.05), u, cy - 0.04, wall + side * 1.5, long_x), Color(0.30, 0.32, 0.36))
	var snow_t := 0.12 + 0.12 * _rand(seed, 30)
	_put("snow", _box_xf(Vector3(2.8, snow_t, 1.5), u, cy + 0.08 + snow_t * 0.5, wall + side * 0.75, long_x))
	_put("lump", _box_xf(Vector3(2.9, 0.22, 0.35), u, cy + 0.08 + snow_t, wall + side * 1.45, long_x))
	_icicles(f, u - 1.3, u + 1.3, cy - 0.18, 1.5, 0.35, seed)
	for e: float in [-1.0, 1.0]:
		_put_near("rod", _segment(_at(long_x, u + e * 1.25, cy - 0.7, wall), _at(long_x, u + e * 1.25, cy - 0.08, wall + side * 1.2), 0.05), Color(0.28, 0.29, 0.31))
	_put("paint", _box_xf(Vector3(0.26, 0.05, 0.26), u, cy - 0.105, wall + side * 0.4, long_x), Color(0.2, 0.2, 0.2))
	_put("paint", Transform3D(basis * Basis.from_scale(Vector3(0.2, 0.12, 0.2)), _at(long_x, u, cy - 0.19, wall + side * 0.4)), Color(1.0, 0.88, 0.65), Color(0, 0.3, 5.0))
	for e: float in [-1.0, 1.0]:
		_put("lump", _box_xf(Vector3(1.6 + 0.6 * _rand(seed, 40 + int(e)), 0.55 + 0.25 * _rand(seed, 44 + int(e)), 0.9), u + e * 2.3, 0.2, wall + side * 0.55, long_x))

## Подъезд Бабки (кадры 01, 02, 09): коричневая металлическая дверь, круглая лампа под козырьком, кронштейны
## козырька, табличка с номером, домофон, доска объявлений. Только вид, без коллизий: путь к Бабке не меняется.
func build_entrance() -> void:
	var root := Node3D.new()
	root.name = "Entrance"
	add_child(root)
	var canopy_center: Vector3 = Layout.CANOPY[0]
	var canopy_size: Vector3 = Layout.CANOPY[1]
	var canopy_bottom := canopy_center.y - canopy_size.y * 0.5
	var z := ENTRANCE_WALL_Z
	var x := ENTRANCE_DOOR_X
	# Дверь в тёмном проёме, наличник, ручка, доводчик.
	_part(root, Vector3(1.5, 2.35, 0.04), Vector3(x, 1.175, z - 0.01), Materials.plain(Color(0.10, 0.09, 0.08), 0.9))
	var door_metal := StandardMaterial3D.new()   # свой: общий кэш plain() без metallic
	door_metal.albedo_color = Color(0.32, 0.22, 0.15)
	door_metal.roughness = 0.45
	door_metal.metallic = 0.5
	_part(root, Vector3(1.25, 2.15, 0.06), Vector3(x, 1.075, z - 0.04), door_metal)
	_part(root, Vector3(0.05, 0.3, 0.05), Vector3(x + 0.45, 1.05, z - 0.1), Materials.plain(Color(0.6, 0.6, 0.58), 0.3))
	_put("paint", _box_xf(Vector3(1.62, 0.1, 0.07), x, 2.4, z - 0.035, true), Color(0.30, 0.30, 0.31))
	_put("paint", _box_xf(Vector3(0.3, 0.06, 0.08), x - 0.4, 2.27, z - 0.1, true), Color(0.25, 0.25, 0.26), Color(3, 0, 0))
	# Домофон с клавиатурой и огоньком.
	_part(root, Vector3(0.16, 0.24, 0.04), Vector3(x + 0.85, 1.35, z - 0.02), Materials.plain(Color(0.25, 0.25, 0.27), 0.4))
	_put("paint", _box_xf(Vector3(0.1, 0.11, 0.012), x + 0.85, 1.31, z - 0.045, true), Color(0.62, 0.62, 0.60))
	_put("paint", _box_xf(Vector3(0.025, 0.025, 0.012), x + 0.85, 1.43, z - 0.045, true), Color(1.0, 0.1, 0.05), Color(0, 0.4, 4.0))
	# Табличка подъезда — тёмная пластина под номером.
	_part(root, Vector3(0.62, 0.66, 0.025), Vector3(-38.75, 2.36, z - 0.02), Materials.plain(Color(0.16, 0.19, 0.24), 0.6))
	# Доска объявлений между дверью и табличкой: рамка, листки на ней.
	_put("paint", _box_xf(Vector3(0.72, 0.9, 0.02), -38.8, 1.42, z - 0.012, true), Color(0.22, 0.30, 0.24))
	var paper := [Color(0.85, 0.84, 0.78), Color(0.78, 0.82, 0.86), Color(0.86, 0.80, 0.70)]
	var notes := [[Vector2(-38.95, 1.55), Vector2(0.3, 0.42)], [Vector2(-38.55, 1.62), Vector2(0.26, 0.34)], [Vector2(-38.8, 1.12), Vector2(0.34, 0.3)]]
	for i in notes.size():
		var note: Array = notes[i]
		_part(root, Vector3(note[1].x, note[1].y, 0.01), Vector3(note[0].x, note[0].y, z - 0.03), Materials.plain(paper[i], 0.95))
	# Сибирская записка у двери (ART-06, P2.7).
	var warn: Label3D = _geo._label("Закрывайте двери!\nТрубы замёрзнут!", 28, Color(0.12, 0.12, 0.14))
	warn.pixel_size = 0.0011
	warn.position = Vector3(-38.8, 1.12, z - 0.045)
	warn.rotation.y = PI
	root.add_child(warn)
	# Круглая лампа над дверью: тёплый светящийся плафон (сам свет — Layout.LAMPS, подъезд).
	var lamp := Greybox.mesh_sphere(0.14, Color.WHITE)
	lamp.material_override = Materials.plain(Color(1.0, 0.9, 0.7), 0.3, WARM, 6.0)
	lamp.position = Vector3(x, canopy_bottom - 0.3, z - 0.16)
	root.add_child(lamp)
	_part(root, Vector3(0.06, 0.06, 0.12), Vector3(x, canopy_bottom - 0.3, z - 0.05), Materials.plain(Color(0.2, 0.2, 0.2), 0.5))
	# Консольный козырёк: косые кронштейны от стены под краями, без опор у земли — опора закрывала край Бабки
	# (повторная сверка ART-05, Н7).
	for bx in [canopy_center.x - canopy_size.x * 0.5 + 0.1, canopy_center.x + canopy_size.x * 0.5 - 0.1]:
		_put("pipe", _segment(Vector3(bx, canopy_bottom - 0.6, z - 0.05), Vector3(bx, canopy_bottom - 0.02, canopy_center.z - canopy_size.z * 0.5 + 0.3), 0.06), Color(0.05, 0.05, 0.05))
	# Две низкие бетонные ступени у двери и трубный поручень (сверка ART-04, черта 7). Без коллизий:
	# ступени по 0,08 м, Илюша проходит к двери как раньше.
	var step_material := Materials.plain(Color(0.46, 0.46, 0.45), 0.9)
	_part(root, Vector3(2.4, 0.08, 1.1), Vector3(x, 0.04, z - 0.55), step_material)
	_part(root, Vector3(2.4, 0.08, 0.55), Vector3(x, 0.12, z - 0.28), step_material)
	_part(root, Vector3(2.3, 0.02, 0.5), Vector3(x, 0.17, z - 0.3), Materials.snow(0.6))
	var rail := Materials.plain(Color(0.20, 0.30, 0.42), 0.5)
	for rx in [x - 1.25, x + 1.25]:
		_part(root, Vector3(0.05, 0.9, 0.05), Vector3(rx, 0.45, z - 1.05), rail)
		_part(root, Vector3(0.05, 0.05, 1.05), Vector3(rx, 0.9, z - 0.55), rail)
	# Сугробы по бокам входа, у стены: только вид.
	for i in 2:
		var hx: float = [x - 4.2, x + 3.6][i]
		var heap: Node3D = _geo._lumpy_bank(Vector3(2.4, 0.75, 1.3), Materials.snow(0.15), 77 + i * 5)   # рваные, не полусферы (Н9)
		heap.position = Vector3(hx, 0.375, z - 0.7)
		root.add_child(heap)

## Козырёк подъезда Бабки: кромка, снеговая шапка с напуском и сосульки по переднему краю (только вид).
func dress_canopy() -> void:
	var center: Vector3 = Layout.CANOPY[0]
	var size: Vector3 = Layout.CANOPY[1]
	var front := center.z - size.z * 0.5
	var bottom := center.y - size.y * 0.5
	_put("paint", _box_xf(Vector3(size.x + 0.04, 0.3, 0.05), center.x, center.y - 0.03, front - 0.02, true), Color(0.30, 0.32, 0.36))
	_put("lump", _box_xf(Vector3(size.x + 0.1, 0.24, 0.4), center.x, center.y + size.y * 0.5 + 0.17, front + 0.12, true))
	_icicles({"long_x": true, "wall": front, "side": 1.0}, center.x - size.x * 0.5 + 0.15, center.x + size.x * 0.5 - 0.15, bottom, 0.03, 0.3, 4242)

# --- цоколь и крыши ---

## Цоколь с отливом и снегом на отливе по всем фасадам; у дверей — разрыв. Продухи подвала — тёмные окошки.
func _plinth(h: Dictionary, doors: Dictionary) -> void:
	var seed: int = h.seed
	var ph := 0.3 if h.shops else (0.7 if h.low else 0.55)
	var color: Color = PLINTH_COLORS[posmod(int(h.index), PLINTH_COLORS.size())]
	for f in doors:
		var long_x: bool = f.long_x
		var side: float = f.side
		var wall: float = f.wall
		var cuts: Array = doors[f]
		var spans := [[f.u0 - 0.06, f.u1 + 0.06]]
		for c in cuts:
			var next := []
			for s in spans:
				if c - 0.9 > s[0] and c + 0.9 < s[1]:
					next.append([s[0], c - 0.9])
					next.append([c + 0.9, s[1]])
				else:
					next.append(s)
			spans = next
		for s in spans:
			var a: float = s[0]
			var b: float = s[1]
			var mid := (a + b) * 0.5
			_put("paint", _box_xf(Vector3(b - a, ph, 0.08), mid, ph * 0.5, wall + side * 0.03, long_x), color, Color(0, 0.95, 0))
			_put("paint", _box_xf(Vector3(b - a + 0.04, 0.025, 0.15), mid, ph + 0.012, wall + side * 0.06, long_x), METAL, Color(3, 0, 0))
			_put("snow", _box_xf(Vector3(b - a, 0.035, 0.12), mid, ph + 0.042, wall + side * 0.07, long_x))
			var n := int((b - a) / 6.5)
			for i in n:
				var vu := a + (b - a) * (float(i) + 0.5) / n
				_put("paint", _box_xf(Vector3(0.32, 0.18, 0.02), vu, ph * 0.45, wall + side * 0.075, long_x), Color(0.06, 0.06, 0.07))

## Плоская крыша панельки: парапет с колпаком и снегом, снег на крыше, лифтовые будки над секциями с дверью,
## вентшахты, грибки, люк выхода, телеантенны, тарелки у парапета; пар — у части будок (ART-04, черта 6).
func _flat_roof(h: Dictionary, body: Node3D) -> void:
	var size: Vector3 = h.size
	var xz: Vector2 = h.xz
	var seed: int = h.seed
	var index: int = h.index
	var long_x: bool = h.long_x
	var top := size.y
	var ph := 0.5 + 0.4 * _rand(seed, 50)
	var wall_color: Color = h.wall
	var pc := wall_color * 0.9
	pc.a = 1.0
	var c := Vector3(xz.x, 0, xz.y)
	for e: float in [-1.0, 1.0]:
		var z := xz.y + e * (size.z * 0.5 - 0.15)
		_put("paint", Transform3D(Basis.from_scale(Vector3(size.x, ph, 0.3)), Vector3(xz.x, top + ph * 0.5, z)), pc)
		_put("paint", Transform3D(Basis.from_scale(Vector3(size.x + 0.06, 0.04, 0.38)), Vector3(xz.x, top + ph + 0.02, z + e * 0.02)), METAL, Color(3, 0, 0))
		_put("snow", Transform3D(Basis.from_scale(Vector3(size.x, 0.06 + 0.05 * _rand(seed, 51), 0.28)), Vector3(xz.x, top + ph + 0.07, z)))
		var x := xz.x + e * (size.x * 0.5 - 0.15)
		_put("paint", Transform3D(Basis.from_scale(Vector3(0.3, ph, size.z - 0.6)), Vector3(x, top + ph * 0.5, xz.y)), pc)
		_put("paint", Transform3D(Basis.from_scale(Vector3(0.38, 0.04, size.z - 0.6)), Vector3(x + e * 0.02, top + ph + 0.02, xz.y)), METAL, Color(3, 0, 0))
		_put("snow", Transform3D(Basis.from_scale(Vector3(0.28, 0.06 + 0.05 * _rand(seed, 52), size.z - 0.6)), Vector3(x, top + ph + 0.07, xz.y)))
	_put("snow", Transform3D(Basis.from_scale(Vector3(size.x - 0.6, 0.2, size.z - 0.6)), Vector3(xz.x, top + 0.1, xz.y)))
	# Надувы снега у парапета.
	for i in 6:
		var a := (_rand(seed, 60 + i) - 0.5) * (size.x - 3.0)
		var b := (_rand(seed, 70 + i) - 0.5) * (size.z - 3.0)
		var along := _rand(seed, 80 + i) < 0.5
		var p := Vector3(a, 0, (size.z * 0.5 - 1.0) * signf(b)) if along else Vector3((size.x * 0.5 - 1.0) * signf(a), 0, b)
		_put("lump", Transform3D(Basis.from_scale(Vector3(3.0 + 2.0 * _rand(seed, 90 + i), 0.5, 1.4) if along else Vector3(1.4, 0.5, 3.0 + 2.0 * _rand(seed, 90 + i))), c + p + Vector3(0, top + 0.2, 0)))
	var length: float = size.x if long_x else size.z
	var depth: float = size.z if long_x else size.x
	var sections := maxi(1, int(round(length / 26.0)))
	for i in sections:
		var a := -length * 0.5 + length * (i + 0.5) / sections
		# Машинное отделение лифта: бетонная будка, дверь, жалюзи, снег на крыше будки.
		var room := c + _roof_at(long_x, a, 0.0, top + 1.2)
		var room_size := Vector3(4.2, 2.4, 3.2) if long_x else Vector3(3.2, 2.4, 4.2)
		_put("paint", Transform3D(Basis.from_scale(room_size), room), CONCRETE)
		_put("snow", Transform3D(Basis.from_scale(room_size * Vector3(1.0, 0.0, 1.0) + Vector3(0.1, 0.18, 0.1)), room + Vector3(0, 1.29, 0)))
		var door_at := room + (Vector3(0, -0.25, room_size.z * 0.5 + 0.02) if long_x else Vector3(room_size.x * 0.5 + 0.02, -0.25, 0))
		_put("paint", Transform3D(Basis.from_scale(Vector3(0.9, 1.8, 0.04) if long_x else Vector3(0.04, 1.8, 0.9)), door_at + (Vector3(1.0, 0, 0) if long_x else Vector3(0, 0, 1.0))), Color(0.26, 0.24, 0.22), Color(3, 0, 0))
		_put("paint", Transform3D(Basis.from_scale(Vector3(1.0, 0.4, 0.04) if long_x else Vector3(0.04, 0.4, 1.0)), door_at + Vector3(0, 0.6, 0) - (Vector3(0.8, 0, 0) if long_x else Vector3(0, 0, 0.8))), Color(0.12, 0.12, 0.13))
		if (i + index) % 2 == 1:
			_geo._steam_puff(body, room - body.position + Vector3.UP * 1.5, index + i)
		# Вентшахты: кирпич или бетон, бетонный колпак, щели жалюзи, снег на колпаке.
		for j in 2:
			var off := a + (j - 0.5) * (7.0 + 3.0 * _rand(seed, 100 + i * 3 + j))
			if absf(off) > length * 0.5 - 1.5:
				continue
			var across := depth * (0.22 if j == 0 else -0.18)
			var shaft := c + _roof_at(long_x, off, across, top + 0.6)
			var brick := _rand(seed, 110 + i * 3 + j) < 0.5
			var shaft_size := Vector3(1.4, 1.2, 0.7) if long_x else Vector3(0.7, 1.2, 1.4)
			_put("paint", Transform3D(Basis.from_scale(shaft_size), shaft), BRICK_RED if brick else CONCRETE * 0.9)
			_put("paint", Transform3D(Basis.from_scale(shaft_size + Vector3(0.2, -1.12, 0.2)), shaft + Vector3(0, 0.64, 0)), CONCRETE)
			_put("snow", Transform3D(Basis.from_scale(shaft_size + Vector3(0.1, -1.1, 0.1)), shaft + Vector3(0, 0.73, 0)))
			_put("paint", Transform3D(Basis.from_scale(shaft_size * Vector3(0.75, 0.0, 1.03) + Vector3(0, 0.22, 0) if long_x else shaft_size * Vector3(1.03, 0.0, 0.75) + Vector3(0, 0.22, 0)), shaft + Vector3(0, 0.3, 0)), Color(0.07, 0.07, 0.08))
		# Грибки вытяжек.
		for j in 3:
			var p := c + _roof_at(long_x, a + (_rand(seed, 120 + i * 5 + j) - 0.5) * 20.0, (_rand(seed, 130 + i * 5 + j) - 0.5) * (depth - 3.0), top + 0.35)
			if absf((p - c).x if long_x else (p - c).z) > length * 0.5 - 1.0:
				continue
			_put("pipe", Transform3D(Basis.from_scale(Vector3(0.22, 0.7, 0.22)), p), METAL, Color(3, 0, 0))
			_put("pipe", Transform3D(Basis.from_scale(Vector3(0.5, 0.06, 0.5)), p + Vector3(0, 0.38, 0)), METAL, Color(3, 0, 0))
			_put("snow_disc", Transform3D(Basis.from_scale(Vector3(0.46, 0.07, 0.46)), p + Vector3(0, 0.44, 0)))
		# Люк выхода на крышу.
		var hatch := c + _roof_at(long_x, a - 3.5, depth * 0.05, top + 0.3)
		_put("paint", Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), hatch), Color(0.35, 0.30, 0.26), Color(3, 0, 0))
		_put("snow", Transform3D(Basis.from_scale(Vector3(0.95, 0.08, 0.95)), hatch + Vector3(0, 0.29, 0)))
		# Телеантенны: мачта и две поперечины, повёрнутые по-разному.
		for j in 2:
			var off := (j - 0.5) * 6.0 + a + 4.0
			if absf(off) > length * 0.5 - 1.0:
				continue
			var base := c + _roof_at(long_x, off, depth * 0.25 * (1 - 2 * j), top)
			_put("pipe", Transform3D(Basis.from_scale(Vector3(0.06, 3.0, 0.06)), base + Vector3.UP * 1.5), Color(0.25, 0.25, 0.26))
			for b in 3:
				var yaw := float(index + j) * 0.7 + b * 0.05
				_put("paint", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.4 - b * 0.35, 0.03, 0.03)), base + Vector3.UP * (2.2 + b * 0.35)), Color(0.25, 0.25, 0.26))
			# Растяжки мачты.
			for g in 3:
				var ang := TAU * g / 3.0 + float(index)
				_put("pipe", _segment(base + Vector3.UP * 2.6, base + Vector3(cos(ang) * 1.6, 0.1, sin(ang) * 1.6), 0.012), Color(0.2, 0.2, 0.2))
	# Тарелки на крыше у парапета — по одной-три на дом.
	for i in 1 + int(_rand(seed, 140) * 3.0):
		var along := (_rand(seed, 141 + i) - 0.5) * (length - 4.0)
		var e := 1.0 if _rand(seed, 150 + i) < 0.5 else -1.0
		var f := {"long_x": long_x, "wall": (xz.y if long_x else xz.x) + e * (depth * 0.5 - 0.9), "side": e}
		_dish(f, along + (xz.x if long_x else xz.y), top + 0.8, 0.0, seed + i)
	# Редкие сосульки с парапета над подъездной стороной.
	var es: float = ENTRANCE_SIDE.get(h.name, 1.0)
	_icicles({"long_x": long_x, "wall": (xz.y if long_x else xz.x) + es * depth * 0.5, "side": es},
		(xz.x if long_x else xz.y) - length * 0.5 + 0.5, (xz.x if long_x else xz.y) + length * 0.5 - 0.5, top - 0.02, 0.12, 0.25, seed + 77)

## Точка на крыше: along — вдоль дома, across — поперёк (от оси), y — высота.
static func _roof_at(long_x: bool, along: float, across: float, y: float) -> Vector3:
	return Vector3(along, y, across) if long_x else Vector3(across, y, along)

## Скатная крыша старого дома: два ската под снегом с напуском, фронтоны цвета стены со слуховыми окошками,
## карниз, водосточные желоба и трубы, сосульки, кирпичные трубы и слуховые окна на скатах (ART-04, черты 5, 6).
func _pitched_roof(h: Dictionary, body: Node3D) -> void:
	var size: Vector3 = h.size
	var xz: Vector2 = h.xz
	var seed: int = h.seed
	var index: int = h.index
	var long_x: bool = h.long_x
	var top := size.y
	var length: float = size.x if long_x else size.z
	var depth: float = size.z if long_x else size.x
	var half := depth * 0.5
	var rise := clampf(depth * 0.27, 3.2, 5.0)
	var a := atan2(rise, half)
	var o := 0.5    # вынос карниза
	var tk := 0.3   # толщина ската со снегом
	var c := Vector3(xz.x, 0, xz.y)
	var wall_color: Color = h.wall
	# Фронтоны: треугольная призма цвета стены под скатами.
	var gable := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(depth, rise, length)
	gable.mesh = prism
	gable.material_override = Materials.plain(wall_color * 0.95, 0.9)
	gable.position = Vector3(0, size.y * 0.5 + rise * 0.5, 0)
	if long_x:
		gable.rotation.y = PI * 0.5
	body.add_child(gable)
	# Карниз по периметру под скатами.
	var cornice := wall_color * 1.08
	cornice.a = 1.0
	_put("paint", Transform3D(Basis.from_scale(Vector3(size.x + 0.4, 0.28, size.z + 0.4)), c + Vector3(0, top - 0.14, 0)), cornice)
	var slope_len := (half + o) / cos(a)
	for e: float in [-1.0, 1.0]:
		var ridge := Vector2(0.0, top + rise)
		var eave := Vector2(e * (half + o), top - o * tan(a))
		var mid := (ridge + eave) * 0.5 + Vector2(e * sin(a), cos(a)) * (tk * 0.5 + 0.02)
		var basis := Basis(Vector3.RIGHT, e * a) if long_x else Basis(Vector3.BACK, -e * a)
		var dims := Vector3(length + 0.6, tk, slope_len) if long_x else Vector3(slope_len, tk, length + 0.6)
		_put("snow", Transform3D(basis * Basis.from_scale(dims), c + _roof_at(long_x, 0.0, mid.x, mid.y)))
		# Лобовая доска, желоб, сосульки по кромке.
		var tip := eave + Vector2(e * sin(a), cos(a)) * 0.02
		_put("paint", Transform3D(Basis.from_scale(_roof_dims(long_x, length + 0.6, 0.22, 0.04)), c + _roof_at(long_x, 0.0, tip.x, tip.y - 0.05)), Color(0.24, 0.20, 0.17))
		_put("paint", Transform3D(Basis.from_scale(_roof_dims(long_x, length + 0.4, 0.1, 0.12)), c + _roof_at(long_x, 0.0, tip.x - e * 0.04, tip.y - 0.2)), METAL, Color(3, 0, 0))
		var face := {"long_x": long_x, "wall": (xz.y if long_x else xz.x), "side": e}
		var along_c: float = xz.x if long_x else xz.y
		_icicles(face, along_c - length * 0.5 - 0.2, along_c + length * 0.5 + 0.2, tip.y - 0.26, half + o - 0.04, 0.9, seed + int(e * 7.0) + 20)
		# Снежный навес по кромке ската.
		_put("lump", Transform3D(Basis.from_scale(_roof_dims(long_x, length + 0.4, 0.3, 0.45)), c + _roof_at(long_x, 0.0, eave.x - e * 0.1, eave.y + 0.12)))
		# Водосточные трубы: по углам и через ~12 м, с воронкой, отводом и наледью внизу.
		var n := maxi(2, int(length / 12.0) + 1)
		for i in n:
			var u := along_c - length * 0.5 + 0.35 + (length - 0.7) * float(i) / (n - 1)
			var w := (xz.y if long_x else xz.x) + e * (half + 0.12)
			var y_top := tip.y - 0.25
			_put("pipe", Transform3D(Basis.from_scale(Vector3(0.11, y_top - 0.35, 0.11)), _at(long_x, u, (y_top + 0.35) * 0.5, w)), METAL, Color(3, 0, 0))
			_put("pipe", Transform3D(Basis.from_scale(Vector3(0.24, 0.25, 0.24)), _at(long_x, u, y_top, w)), METAL, Color(3, 0, 0))
			_put("paint", _box_xf(Vector3(0.12, 0.12, 0.35), u, 0.32, w + e * 0.12, long_x), METAL, Color(3, 0, 0))
			_put("lump", _box_xf(Vector3(0.6, 0.12, 0.5), u, 0.04, w + e * 0.3, long_x))
			_put_near("icicle", Transform3D(Basis.from_scale(Vector3(0.12, 0.3, 0.12)), _at(long_x, u, 0.12, w + e * 0.22)), ICE, Color(0, 0.15, 0))
	# Конёк под снегом.
	var ridge_basis := Basis(Vector3.RIGHT, PI * 0.25) if long_x else Basis(Vector3.BACK, PI * 0.25)
	_put("lump", Transform3D(ridge_basis * Basis.from_scale(_roof_dims(long_x, length + 0.5, 0.42, 0.42)), c + Vector3(0, top + rise + 0.12, 0)))
	# Слуховые окошки на фронтонах.
	for e: float in [-1.0, 1.0]:
		var gf := {"long_x": not long_x, "wall": (xz.x if long_x else xz.y) + e * length * 0.5, "side": e}
		var gu: float = xz.y if long_x else xz.x
		_put("paint", _box_xf(Vector3(0.9, 0.7, 0.04), gu, top + rise * 0.38, gf.wall + e * 0.02, not long_x), Color(0.07, 0.07, 0.08))
		_put("paint", _box_xf(Vector3(1.0, 0.06, 0.08), gu, top + rise * 0.38 - 0.38, gf.wall + e * 0.04, not long_x), Color(0.85, 0.85, 0.82))
		_put("snow", _box_xf(Vector3(0.96, 0.04, 0.07), gu, top + rise * 0.38 - 0.33, gf.wall + e * 0.045, not long_x))
	# Кирпичные трубы у конька и слуховые окна на скатах.
	var along_c: float = xz.x if long_x else xz.y
	var chimneys := maxi(2, int(length / 11.0))
	for i in chimneys:
		var u := -length * 0.5 + length * (i + 0.5) / chimneys + (_rand(seed, 200 + i) - 0.5) * 2.0
		var off := (0.8 + 0.6 * _rand(seed, 210 + i)) * (1.0 if i % 2 == 0 else -1.0)
		var hgt := 1.3 + 0.6 * _rand(seed, 220 + i)
		var base_y := top + rise - absf(off) * tan(a) - 0.3
		var p := c + _roof_at(long_x, u, off, base_y + hgt * 0.5)
		_put("paint", Transform3D(Basis.from_scale(_roof_dims(long_x, 0.9, hgt, 0.6)), p), BRICK_RED * (0.9 + 0.2 * _rand(seed, 230 + i)))
		_put("paint", Transform3D(Basis.from_scale(_roof_dims(long_x, 1.1, 0.08, 0.8)), p + Vector3(0, hgt * 0.5 + 0.04, 0)), CONCRETE)
		_put("snow", Transform3D(Basis.from_scale(_roof_dims(long_x, 1.0, 0.1, 0.7)), p + Vector3(0, hgt * 0.5 + 0.13, 0)))
		if (i + index) % 2 == 0:
			_geo._steam_puff(body, p - body.position + Vector3.UP * (hgt * 0.5 + 0.3), index + i)
	var dormers := maxi(1, int(length / 15.0))
	for e: float in [-1.0, 1.0]:
		for i in dormers:
			var u := -length * 0.5 + length * (i + 0.5) / dormers + 2.5 * e
			var front := half * 0.55
			var y0 := top + rise * 0.45
			var p := c + _roof_at(long_x, u, e * (front - 0.6), y0 + 0.45)
			_put("paint", Transform3D(Basis.from_scale(_roof_dims(long_x, 1.3, 1.1, 1.2)), p), wall_color * 0.95)
			var roof_basis := Basis() if long_x else Basis(Vector3.UP, PI * 0.5)
			_put("prism", Transform3D(roof_basis * Basis.from_scale(Vector3(1.6, 0.6, 1.4)), p + Vector3(0, 0.85, 0)))
			var win := c + _roof_at(long_x, u, e * (front + 0.01), y0 + 0.5)
			_put("paint", Transform3D(Basis.from_scale(_roof_dims(long_x, 0.62, 0.55, 0.03)), win), Color(0.07, 0.07, 0.08))
			_put("snow", Transform3D(Basis.from_scale(_roof_dims(long_x, 0.7, 0.04, 0.08)), win + Vector3(0, -0.29, 0) + _roof_at(long_x, 0.0, e * 0.03, 0.0)))

## Размеры коробки вдоль конька (along), по высоте и поперёк.
static func _roof_dims(long_x: bool, along: float, height: float, across: float) -> Vector3:
	return Vector3(along, height, across) if long_x else Vector3(across, height, along)

# --- таблички ---

## Таблички с номером дома: тёмно-синие в белой рамке, сверху мелко «улица», под ним название, ниже крупный
## номер (ART-06, Н13: `Pisarev Street 53`). Названия — улицы спального Новосибирска по OSM (Н14),
## номера придуманные. Улица A по концепту 05 — «Ленина». Снег на верхней кромке рамки.
func build_house_plates() -> void:
	for spec in [["Татьяны Снежиной", "12", Vector3(-88.5, 3.0, 107.95), PI], ["Ленина", "14", Vector3(41.5, 3.0, 59.95), PI],
			["Троллейная", "9", Vector3(56.05, 3.0, 8.0), PI * 0.5], ["Троллейная", "11", Vector3(81.95, 3.0, 10.0), -PI * 0.5],
			# Улицы кольца (ARENA-01): D — Бориса Богаткова, C — Выборная (Н14).
			["Бориса Богаткова", "2", Vector3(-52.05, 3.0, 5.0), -PI * 0.5], ["Бориса Богаткова", "7", Vector3(-85.95, 3.0, -40.0), PI * 0.5],
			["Выборная", "3", Vector3(-38.0, 3.0, -87.05), PI], ["Выборная", "4", Vector3(36.0, 3.0, -111.95), 0.0]]:
		var yaw: float = spec[3]
		var face := Basis(Vector3.UP, yaw)
		var frame := Greybox.mesh_box(Vector3(1.24, 0.84, 0.03), Color.WHITE)
		frame.material_override = Materials.plain(Color(0.92, 0.92, 0.90), 0.6)
		frame.position = spec[2]
		frame.rotation.y = yaw
		add_child(frame)
		var plate := Greybox.mesh_box(Vector3(1.16, 0.76, 0.04), Color.WHITE)
		plate.material_override = Materials.plain(Color(0.16, 0.20, 0.36), 0.5)   # #2a335c
		plate.position = spec[2] + face * Vector3(0, 0, 0.005)
		plate.rotation.y = yaw
		add_child(plate)
		_put("snow", Transform3D(face * Basis.from_scale(Vector3(1.22, 0.035, 0.05)), spec[2] + face * Vector3(0, 0.437, 0.0)))
		for line in [["улица", 26, 0.27], [spec[0], 34, 0.14], [spec[1], 110, -0.14]]:
			var label: Label3D = _geo._label(line[0], line[1], Color(0.95, 0.95, 0.95))
			label.pixel_size = 0.0045
			label.position = spec[2] + face * Vector3(0, line[2], 0.03)
			label.rotation.y = yaw
			add_child(label)

# --- пакеты MultiMesh ---

func _put(batch: String, xf: Transform3D, color := Color.WHITE, custom := Color(0, 0, 0, 0)) -> void:
	if not _batches.has(batch):
		_batches[batch] = {"batch": batch, "xf": [], "color": [], "custom": []}
	_store(_batches[batch], xf, color, custom)

## Мелочь: в ближний пакет своей клетки NEAR_CELL × NEAR_CELL — дальше NEAR_RANGE от камеры не рисуется.
func _put_near(batch: String, xf: Transform3D, color := Color.WHITE, custom := Color(0, 0, 0, 0)) -> void:
	var cell := Vector2i(floori(xf.origin.x / NEAR_CELL), floori(xf.origin.z / NEAR_CELL))
	var key := "%s|%d|%d" % [batch, cell.x, cell.y]
	if not _near.has(key):
		_near[key] = {"batch": batch, "cell": cell, "xf": [], "color": [], "custom": []}
	_store(_near[key], xf, color, custom)

static func _store(store: Dictionary, xf: Transform3D, color: Color, custom: Color) -> void:
	(store.xf as Array).append(xf)
	(store.color as Array).append(color)
	(store.custom as Array).append(custom)

## Собрать все пакеты в узлы MultiMeshInstance3D (вызывается один раз после всех домов).
func build() -> void:
	for key in _batches:
		_emit(key, _batches[key], Vector3.ZERO, false)
	for key in _near:
		var store: Dictionary = _near[key]
		var cell: Vector2i = store.cell
		_emit("Near_%s_%d_%d" % [store.batch, cell.x, cell.y], store, Vector3((cell.x + 0.5) * NEAR_CELL, 0.0, (cell.y + 0.5) * NEAR_CELL), true)
	_batches.clear()
	_near.clear()

func _emit(node_name: String, store: Dictionary, origin: Vector3, near: bool) -> void:
	var spec: Array = BATCHES[store.batch]
	var transforms: Array = store.xf
	var colors: Array = store.color
	var customs: Array = store.custom
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = spec[1] == "detail" or spec[1] == "glass"
	mm.use_custom_data = spec[1] == "detail"
	mm.mesh = _mesh(spec[0])
	mm.instance_count = transforms.size()
	for i in transforms.size():
		var xf: Transform3D = transforms[i]
		xf.origin -= origin
		mm.set_instance_transform(i, xf)
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, customs[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = mm
	instance.material_override = _material(spec[1])
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = origin
	if near:
		instance.visibility_range_end = NEAR_RANGE
		instance.visibility_range_end_margin = 4.0
	add_child(instance)

func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"box":
			mesh = BoxMesh.new()
		"cyl", "cone", "dish":
			var cylinder := CylinderMesh.new()
			cylinder.height = 1.0
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = {"cyl": 0.5, "cone": 0.0, "dish": 0.28}[kind]
			cylinder.radial_segments = {"cyl": 8, "cone": 5, "dish": 12}[kind]
			cylinder.rings = 1
			mesh = cylinder
		"lump":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 10
			sphere.rings = 5
			mesh = sphere
		"prism":
			mesh = PrismMesh.new()
	_meshes[kind] = mesh
	return mesh

static func _material(kind: String) -> Material:
	match kind:
		"concrete":
			return Materials.plain(CONCRETE, 0.9)
		"detail":
			return Materials.detail()
		"glass":
			return Materials.balcony_glass()
		"snow":
			return Materials.snow(0.0)
	return null

# --- помощники ---

## Детерминированное псевдослучайное число 0..1 по seed и номеру (как level_geometry._rand).
static func _rand(seed: int, k: int) -> float:
	return fposmod(sin(float(seed + k) * 12.9898) * 43758.5453, 1.0)

## Коробка размера size (x — вдоль фасада, z — от стены) в точке (u вдоль, y, w поперёк) фасада, идущего вдоль x или z.
static func _box_xf(size: Vector3, u: float, y: float, w: float, long_x: bool) -> Transform3D:
	if long_x:
		return Transform3D(Basis.from_scale(size), Vector3(u, y, w))
	return Transform3D(Basis.from_scale(Vector3(size.z, size.y, size.x)), Vector3(w, y, u))

static func _at(long_x: bool, u: float, y: float, w: float) -> Vector3:
	return Vector3(u, y, w) if long_x else Vector3(w, y, u)

## Оси фасада без зеркала: x — вдоль, y — вверх, z — наружу (правая тройка, иначе MultiMesh выворачивает грани).
static func _face_basis(long_x: bool, side: float) -> Basis:
	var out := Vector3(0, 0, side) if long_x else Vector3(side, 0, 0)
	return Basis(Vector3.UP.cross(out), Vector3.UP, out)

## Цилиндр единичной высоты от from до to; radius_scale — диаметр (сетка «cyl» радиуса 0,5).
static func _segment(from: Vector3, to: Vector3, diameter: float) -> Transform3D:
	var axis := to - from
	var dir := axis.normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
	var other := side.cross(dir).normalized()
	return Transform3D(Basis(side * diameter, axis, other * diameter), (from + to) * 0.5)

func _part(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := Greybox.mesh_box(size, Color.WHITE)
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)

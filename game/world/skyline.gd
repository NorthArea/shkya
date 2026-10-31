extends Node3D
## CITY-02 E: панорама «масштабно» — большой Новосибирск за краем карты (ART-04, черты 20, 21; ART-06, Н7).
## Слои по глубине: ближний ряд (25–75 м за краем) — объёмы с фасадным шейдером и окнами; средний (90–270 м) —
## сотни домов одним MultiMesh (shaders/skyline_block); горизонт (520 и 850 м) — кольца-силуэты с окнами и
## натриевым заревом (shaders/skyline_far). ТЭЦ — трубы в полоску с паром, градирни; башенные краны; на западе —
## арочный мост через Обь с фонарями и потоком фар. Заградительные огни мигают.
## Часть F (сверка CITY-02): у ближнего ряда — цоколь, подъезды, лоджии лицом к арене; в полосе до него — тополя,
## гаражи, забор; улицы A и D уходят за край дорогой с валами, столбами, машинами; пар — клубы-билборды (steam_plume).
##
## Только вид, без коллизий и теней. Карта не расширяется (C9, п. 4): всё — за Layout.BOUNDS. Раскладка по seed.
## Дальние материалы без тумана сцены, дымка — в самом цвете (как Materials.far, ART-06, С2). Формы — свои.

const Layout = preload("res://game/world/layout.gd")
const Greybox = preload("res://game/world/greybox.gd")
const Materials = preload("res://game/world/materials.gd")
const EnvDress = preload("res://game/world/environment_dress.gd")

const HAZE := Color(0.24, 0.30, 0.37)    # = fog_light_color lighting.gd
const SODIUM := Color(1.0, 0.62, 0.18)
const BEACON := Color(1.0, 0.10, 0.05)
# Куда не ставить дома: [центр, радиус] — башня «ГОСТИНИЦА», трубы ТЭЦ, градирни, краны.
# Трубы ТЭЦ — вдвое дальше от края карты, чем в части E (сверка CITY-02: 60–75 м за краем нависали над киоском).
const CHIMNEYS := [[Vector3(15, 0, -250), 80.0], [Vector3(35, 0, -272), 90.0], [Vector3(-205, 0, -95), 85.0]]
const TOWERS := [[Vector3(-60, 0, -372), 1.0], [Vector3(-122, 0, -388), 0.9]]
const KEEP_OUT := [[Vector2(70, -205), 26.0], [Vector2(15, -250), 14.0], [Vector2(35, -272), 14.0], [Vector2(-205, -95), 14.0],
	[Vector2(-60, -372), 42.0], [Vector2(-122, -388), 42.0], [Vector2(25, -305), 45.0]]
# Продолжения улиц за краем карты: [сторона, от, до] — здесь ближний ряд разорван, видны дальние слои.
const STREET_GAPS := {"north": [[58.0, 82.0]], "west": [[18.0, 46.0]], "east": [[18.0, 46.0]], "south": [[-26.0, -6.0]]}
const RING_RADII := [520.0, 850.0]
# Улицы, уходящие за край (CITY-02 F, концепт 05): [начало на краю карты, направление, ширина проезжей части, длина].
# Ленина продолжается за закрытыми переездом и постом. Богаткова поворачивает в Выборную: отдельной дороги
# за северной стеной нет; прежний отрезок без связи с кольцом удалён (WORLD-02).
const STREETS_OUT := [[Vector2(100, 32), Vector2(1, 0), 14.0, 300.0], [Vector2(-100, 32), Vector2(-1, 0), 14.0, 300.0]]
const CAR_COLORS := [Color(0.80, 0.74, 0.58), Color(0.85, 0.85, 0.82), Color(0.45, 0.12, 0.10), Color(0.16, 0.24, 0.42),
	Color(0.22, 0.34, 0.24), Color(0.55, 0.52, 0.48), Color(0.62, 0.40, 0.16)]
const GARAGE_DOORS := [Color(0.20, 0.36, 0.24), Color(0.42, 0.18, 0.14), Color(0.20, 0.28, 0.42), Color(0.36, 0.36, 0.34), Color(0.50, 0.40, 0.18)]

var _far_box := []      # [преобразование, цвет] — мост, краны, ТЭЦ: без света, дымка в цвете
var _far_cyl := []
var _blocks := []       # [преобразование, custom] — средний слой
var _lights := []       # [преобразование, цвет, custom]
var _lit := []          # [преобразование, цвет] — ближний декор в свете сцены: лоджии, подъезды, столбы, машины, гаражи
var _glow := []         # [преобразование, цвет] — светящееся без света сцены, но в тумане: окна лоджий, лампы подъездов
var _pools := []        # [преобразование, цвет] — пятна фонарей на дорогах за краем
var _bark := []         # стволы и сучья деревьев полосы за краем
var _frost := []        # куржак на ветках
var _banks := {}        # вариант сетки вала → преобразования

func _init() -> void:
	name = "Skyline"

static func _rand(seed: int, k: int) -> float:
	return fposmod(sin(float(seed + k) * 12.9898) * 43758.5453, 1.0)

static func _haze(color: Color, k: float) -> Color:
	return color.lerp(HAZE, k)

static func _kept_out(p: Vector2, margin: float) -> bool:
	for z in KEEP_OUT:
		if p.distance_to(z[0]) < float(z[1]) + margin:
			return true
	return false

## Точка на продолжении улицы за краем (с полосой margin по бокам): там не ставим дома среднего слоя и деревья.
static func _on_street(p: Vector2, margin: float) -> bool:
	for st in STREETS_OUT:
		var a: Vector2 = st[0]
		var dir: Vector2 = st[1]
		var rel := p - a
		var along := rel.dot(dir)
		var across := absf(rel.dot(Vector2(-dir.y, dir.x)))
		if along > -margin and along < float(st[3]) + margin and across < float(st[2]) * 0.5 + margin:
			return true
	return false

## Весь город, кроме труб ТЭЦ (их строит chimneys() — отдельный вызов LevelGeometry._build_chimneys).
func build_city() -> void:
	_ground()
	_near_rows()
	_mid_blocks()
	_rings()
	_bridge()
	_streets_out()
	_belt()
	_cooling_towers()
	for spec in [[Vector3(-130, 0, -170), 62.0, 0.6], [Vector3(175, 0, 10), 55.0, 2.4], [Vector3(125, 0, 195), 58.0, 4.0],
			[Vector3(-195, 0, 95), 50.0, 1.2], [Vector3(120, 0, -250), 66.0, 5.3]]:
		crane(spec[0], spec[1], spec[2])

## Снежная равнина под панорамой: дома не висят над пустотой; под картой её закрывает плита Ground.
func _ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1900, 1900)
	var mesh := MeshInstance3D.new()
	mesh.name = "OuterGround"
	mesh.mesh = plane
	mesh.material_override = Materials.snow(0.5)
	mesh.position.y = -0.06
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

# --- ближний ряд ---

## Дома вдоль каждой стороны за краем карты: девятиэтажки-пластины, башни 12–16 этажей, пятиэтажки; второй ряд —
## башни выше, со сдвигом, чтобы выглядывали между первыми. Разрывы — продолжения улиц.
func _near_rows() -> void:
	var b := Layout.BOUNDS
	var seed := 300
	for side in ["north", "south", "west", "east"]:
		var along_x: bool = side == "north" or side == "south"
		var lo := (b.position.x if along_x else b.position.y) - 40.0
		var hi := (b.end.x if along_x else b.end.y) + 40.0
		for row in 2:
			var pos := lo + (14.0 if row == 1 else 0.0)
			while pos < hi:
				seed += 1
				var kind := _rand(seed, 1)
				var floors := 9
				var length := 30.0 + 26.0 * _rand(seed, 2)
				var depth := 13.0
				var low := false
				if row == 1:
					floors = 14 + int(_rand(seed, 3) * 7.0)
					length = 18.0 + 6.0 * _rand(seed, 4)
					depth = 18.0
				elif kind < 0.22:
					floors = 5
					length = 40.0 + 15.0 * _rand(seed, 2)
					depth = 12.0
					low = true
				elif kind < 0.42:
					floors = 12 + int(_rand(seed, 3) * 5.0)
					length = 18.0 + 4.0 * _rand(seed, 4)
					depth = 18.0
				elif kind < 0.55:
					floors = 10
				var gap_hit := false
				for g in STREET_GAPS[side]:
					if pos + length > g[0] and pos < g[1]:
						pos = g[1] + 2.0
						gap_hit = true
						break
				if gap_hit:
					continue
				var u := pos + length * 0.5
				var off := (24.0 + 8.0 * _rand(seed, 5)) if row == 0 else (52.0 + 18.0 * _rand(seed, 5))
				var height := floors * (3.3 if low else 2.8) + 1.4
				var center := Vector2.ZERO
				match side:
					"north":
						center = Vector2(u, b.position.y - off - depth * 0.5)
					"south":
						center = Vector2(u, b.end.y + off + depth * 0.5)
					"west":
						center = Vector2(b.position.x - off - depth * 0.5, u)
					"east":
						center = Vector2(b.end.x + off + depth * 0.5, u)
				if not _kept_out(center, maxf(length, depth) * 0.5):
					var size := Vector3(length, height, depth) if along_x else Vector3(depth, height, length)
					_house(center, size, seed, low)
					_house_front(center, size, seed, low, side, floors)
				pos += length + (8.0 + 12.0 * _rand(seed, 6)) * (2.2 if row == 1 else 1.0)

## Ближний дом: коробка с фасадным шейдером (окна, свет — как у домов квартала), машинное отделение лифта на крыше,
## у башен — красный огонь на крыше.
func _house(center: Vector2, size: Vector3, seed: int, low: bool) -> void:
	var mesh := Greybox.mesh_box(size, Color.WHITE)
	mesh.name = "Backdrop"
	mesh.material_override = Materials.facade(float(seed), low)
	mesh.position = Vector3(center.x, size.y * 0.5, center.y)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var roof := _haze(Color(0.20, 0.21, 0.23), 0.3)
	var long_x := size.x >= size.z
	var length := size.x if long_x else size.z
	if low:
		# Пятиэтажка: низкая скатная крыша.
		var ridge := Transform3D(Basis.from_scale(Vector3(size.x + 0.6, 1.6, size.z + 0.6)), Vector3(center.x, size.y + 0.8, center.y))
		_far_box.append([ridge, _haze(Color(0.30, 0.27, 0.25), 0.25)])
		return
	var rooms := maxi(1, int(length / 24.0))
	for k in rooms:
		var a := -length * 0.5 + length * (k + 0.5) / rooms
		var at := Vector3(center.x + (a if long_x else 0.0), size.y + 1.3, center.y + (0.0 if long_x else a))
		_far_box.append([Transform3D(Basis.from_scale(Vector3(4.5, 2.6, 3.5)), at), roof])
	if size.y > 34.0:
		_light(Vector3(center.x, size.y + 2.8, center.y), BEACON, 1.0, 1, _rand(seed, 9), 0.5)

# --- средний слой ---

## Дома 90–270 м за краем: сетка с разбросом, высоты 9–25 этажей, кварталы повёрнуты по-разному (микрорайоны).
## На западе — ниже и реже: берег Оби, через просветы виден мост.
func _mid_blocks() -> void:
	var b := Layout.BOUNDS
	var seed := 700
	var step := 30.0
	var x := -420.0
	while x <= 420.0:
		var z := -420.0
		while z <= 420.0:
			seed += 1
			var p := Vector2(x + (_rand(seed, 1) - 0.5) * step * 0.8, z + (_rand(seed, 2) - 0.5) * step * 0.8)
			z += step
			var dx := maxf(maxf(b.position.x - p.x, p.x - b.end.x), 0.0)
			var dz := maxf(maxf(b.position.y - p.y, p.y - b.end.y), 0.0)
			var out := Vector2(dx, dz).length()
			if out < 88.0 or out > 280.0 or _kept_out(p, 22.0) or _on_street(p, 22.0):
				continue
			var west := p.x < b.position.x - 150.0
			if _rand(seed, 3) < (0.72 if west else 0.42):
				continue
			var floors := 9 + int(pow(_rand(seed, 4), 1.6) * 17.0)
			if west:
				floors = mini(floors, 10)
			var h := floors * 2.8 + 1.5
			var tower := _rand(seed, 5) < 0.4
			var size := Vector3(16.0 + 4.0 * _rand(seed, 6), h, 16.0 + 4.0 * _rand(seed, 7)) if tower else Vector3(30.0 + 40.0 * _rand(seed, 6), h, 12.0 + 2.0 * _rand(seed, 7))
			var yaw := 0.0 if _rand(seed, 8) < 0.55 else (PI * 0.5 if _rand(seed, 9) < 0.5 else (_rand(seed, 10) - 0.5) * 0.9)
			var haze := clampf((out - 60.0) / 260.0, 0.15, 0.85)
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), Vector3(p.x, h * 0.5, p.y))
			_blocks.append([xf, Color(_rand(seed, 11), 0.16 + 0.22 * _rand(seed, 12), haze, _rand(seed, 13))])
			# Машинное отделение на крыше и огонь у высоких.
			_blocks.append([Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(5, 3, 4)), Vector3(p.x, h + 1.5, p.y)), Color(_rand(seed, 14), 0.0, haze, 0.2)])
			if floors >= 16:
				_light(Vector3(p.x, h + 3.4, p.y), BEACON, 0.9, 1, _rand(seed, 15), 0.9)
		x += step
	# Главный корпус ТЭЦ у труб: длинный, с редкими окнами; галерея конвейера к нему.
	_blocks.append([Transform3D(Basis.from_scale(Vector3(80, 34, 36)), Vector3(25, 17, -305)), Color(0.31, 0.08, 0.6, 0.6)])
	_blocks.append([Transform3D(Basis.from_scale(Vector3(40, 46, 24)), Vector3(-5, 23, -308)), Color(0.57, 0.05, 0.6, 0.45)])
	_far_box.append([Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.42)) * Basis.from_scale(Vector3(70, 4, 5)), Vector3(80, 20, -300)), _haze(Color(0.32, 0.33, 0.34), 0.6)])

# --- горизонт ---

func _rings() -> void:
	for i in RING_RADII.size():
		var ring := CylinderMesh.new()
		ring.top_radius = RING_RADII[i]
		ring.bottom_radius = RING_RADII[i]
		ring.height = 200.0
		ring.radial_segments = 160
		ring.rings = 1
		ring.cap_top = false
		ring.cap_bottom = false
		var mesh := MeshInstance3D.new()
		mesh.name = "Horizon%d" % i
		mesh.mesh = ring
		mesh.material_override = Materials.skyline_far(i)
		mesh.position.y = 100.0
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

# --- мост через Обь ---

## Арочный мост на западе (x −430, вдоль z): настил на опорах, белая арка над серединой с подвесками, фонари по краям
## и поток фар в обе стороны. Арка — по описанию большого арочного моста города (своя геометрия).
func _bridge() -> void:
	var x := -430.0
	var deck_y := 22.0
	var z0 := -520.0
	var z1 := 520.0
	var deck := _haze(Color(0.16, 0.17, 0.19), 0.45)
	_far_box.append([Transform3D(Basis.from_scale(Vector3(28, 2.4, z1 - z0)), Vector3(x, deck_y, 0)), deck])
	var z := z0 + 32.0
	while z < z1:
		if absf(z) > 200.0:
			_far_box.append([Transform3D(Basis.from_scale(Vector3(10, deck_y, 6)), Vector3(x, deck_y * 0.5, z)), _haze(Color(0.22, 0.22, 0.23), 0.5)])
		z += 64.0
	var arch := _haze(Color(0.80, 0.82, 0.86), 0.35)
	var span := 190.0
	var rise := 78.0
	for side: float in [-1.0, 1.0]:
		var prev := Vector3(x + side * 12.0, deck_y, -span)
		for k in range(1, 25):
			var t := -1.0 + 2.0 * k / 24.0
			var p := Vector3(x + side * 12.0 * (1.0 - 0.35 * (1.0 - t * t)), deck_y + rise * (1.0 - t * t), t * span)
			_far_box.append([_beam(prev, p, 3.2), arch])
			if k < 24 and k % 2 == 0:
				_far_box.append([_beam(p, Vector3(p.x, deck_y, p.z), 0.5), _haze(Color(0.62, 0.64, 0.68), 0.4)])
				_light(p + Vector3(0, 1.8, 0), Color(0.85, 0.92, 1.0), 0.7, 0, 0.0, 0.9)
			prev = p
	# Фонари по краям настила и фары: белые — к северу, красные — к югу.
	z = z0
	while z <= z1:
		for side: float in [-1.0, 1.0]:
			_light(Vector3(x + side * 13.5, deck_y + 9.0, z), SODIUM, 0.9, 0, 0.0, 1.1)
		z += 22.0
	for k in 26:
		var dir := 1.0 if k % 2 == 0 else -1.0
		var path := Vector3(0, 0, (z1 - z0) * dir)
		var xf := _path_xf(Vector3(x + dir * 4.0, deck_y + 2.0, 0), path, 0.7)
		_lights.append([xf, Color(1.0, 0.92, 0.75, 0.8) if dir > 0.0 else Color(1.0, 0.1, 0.05, 0.7), Color(2.0, _rand(k, 3), 0.012 + 0.006 * _rand(k, 4), 0)])

## Огонь, бегущий по пути: ось x экземпляра — весь путь (центр — середина), ось y — размер точки (skyline_lights).
static func _path_xf(center: Vector3, path: Vector3, size: float) -> Transform3D:
	return Transform3D(Basis(path, Vector3(0, size, 0), path.cross(Vector3.UP).normalized() * size), center)

static func _beam(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var axis := b - a
	var dir := axis.normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
	var other := side.cross(dir).normalized()
	return Transform3D(Basis(side * thick, axis, other * thick), (a + b) * 0.5)

## Продолжения улиц за краем (CITY-02 F; концепт 05): проезжая часть с колеями, валы по бокам, столбы с консолями
## и натриевыми светильниками цепочкой (пятна света на дороге — без источников), «Жигули» со снегом у обочин,
## тополя на тротуарах; по полосам бегут пары фар и стоп-сигналов. Только вид, без коллизий.
func _streets_out() -> void:
	for i in STREETS_OUT.size():
		var st: Array = STREETS_OUT[i]
		var a: Vector2 = st[0]
		var dir: Vector2 = st[1]
		var width: float = st[2]
		var length: float = st[3]
		var across := Vector2(-dir.y, dir.x)
		var along_x := absf(dir.x) > 0.5
		var mid := a + dir * length * 0.5
		var plane := PlaneMesh.new()
		plane.size = Vector2(length, width) if along_x else Vector2(width, length)
		var road := MeshInstance3D.new()
		road.name = "StreetOut%d" % i
		road.mesh = plane
		road.material_override = Materials.road(along_x, mid, width)
		road.position = Vector3(mid.x, 0.02, mid.y)
		road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(road)
		var a3 := Vector3(a.x, 0, a.y)
		var d3 := Vector3(dir.x, 0, dir.y)
		var c3 := Vector3(across.x, 0, across.y)
		var yaw := 0.0 if along_x else -PI * 0.5
		var v_axis := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
		# Валы у бордюров с разрывами (въезды во дворы); вариант сетки — по стороне дороги.
		for side: float in [-1.0, 1.0]:
			var d := 2.0
			var k := 0
			while d < length - 6.0:
				k += 1
				if _rand(i * 131 + int(side), k) < 0.12:
					d += 7.0   # въезд
					continue
				var at := a3 + d3 * (d + 4.5) + c3 * side * (width * 0.5 + 0.9)
				var toward := signf(v_axis.dot(-c3 * side))
				var variant := "%d_%d" % [int(toward), k % 3]
				if not _banks.has(variant):
					_banks[variant] = []
				(_banks[variant] as Array).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, 0.8 + 0.4 * _rand(i * 17 + k, int(side) + 3), 1.0)), at))
				d += 9.4
		# Столбы с консолями: через 28 м, по сторонам вразбежку; светильник над краем проезжей части.
		var d2 := 14.0
		while d2 < length:
			for side: float in [-1.0, 1.0]:
				var along := d2 + (14.0 if side > 0.0 else 0.0)
				if along > length:
					continue
				var base := a3 + d3 * along + c3 * side * (width * 0.5 + 2.2)
				_lit.append([_beam(base, base + Vector3(0, 8.0, 0), 0.22), Color(0.12, 0.12, 0.13)])
				var head := base + Vector3(0, 7.8, 0) - c3 * side * 2.0
				_lit.append([_beam(base + Vector3(0, 7.8, 0), head, 0.08), Color(0.12, 0.12, 0.13)])
				_light(head - Vector3(0, 0.15, 0), SODIUM, 0.9, 0, 0.0, 0.8)
				_pools.append([Transform3D(Basis.from_scale(Vector3(13.0, 1.0, 13.0)), Vector3(head.x, 0.06, head.z)), Color(1.0, 0.55, 0.18, 0.22)])
			d2 += 28.0
		# Припаркованные «Жигули» со снегом на крыше у обочин.
		for k in 9:
			var side := -1.0 if k % 2 == 0 else 1.0
			var dk := 18.0 + (length - 40.0) * (k + 0.4 * _rand(i * 7, k)) / 9.0
			_car(a3 + d3 * dk + c3 * side * (width * 0.5 - 1.1), yaw, CAR_COLORS[(i * 3 + k) % CAR_COLORS.size()])
		# Тополя на тротуарах за валами.
		var dt := 8.0
		var t := 0
		while dt < length - 5.0:
			t += 1
			for side: float in [-1.0, 1.0]:
				if _rand(i * 53 + t, int(side) + 5) < 0.3:
					continue
				var p := a3 + d3 * (dt + 4.0 * _rand(i + t, 9)) + c3 * side * (width * 0.5 + 4.2 + 1.5 * _rand(i + t, 11))
				_tree(p, i * 1000 + t * 2 + int(side > 0.0))
			dt += 11.0 + 6.0 * _rand(i * 3 + t, 13)
		# Машины на ходу: пары фар (белые — навстречу камере с края, красные — от неё), бегут по своей полосе.
		for k in 6:
			var way := 1.0 if k % 2 == 0 else -1.0
			var traffic_start := 22.0 if along_x else 0.0
			var traffic_length := length - traffic_start
			var path := d3 * traffic_length * way
			var lane := c3 * (-way) * width * 0.22
			var custom := Color(2.0, _rand(i * 7 + k, 1), 0.012 + 0.008 * _rand(i * 7 + k, 2), 0)
			var tint := Color(1.0, 0.92, 0.75, 0.8) if way < 0.0 else Color(1.0, 0.1, 0.05, 0.6)
			for pair: float in [-0.7, 0.7]:
				_lights.append([_path_xf(a3 + d3 * (traffic_start + traffic_length * 0.5) + lane + c3 * pair + Vector3(0, 0.75, 0), path, 0.35), tint, custom])

## «Жигули» силуэтом: кузов, кабина с тёмными стёклами, снег на крыше и капоте (дальше 30 м деталей не видно).
func _car(at: Vector3, yaw: float, color: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	_lit.append([Transform3D(b * Basis.from_scale(Vector3(4.1, 0.72, 1.62)), at + Vector3(0, 0.56, 0)), color])
	_lit.append([Transform3D(b * Basis.from_scale(Vector3(2.1, 0.52, 1.42)), at + Vector3(0, 1.16, 0) + b * Vector3(0.2, 0, 0)), Color(0.08, 0.09, 0.11)])
	_lit.append([Transform3D(b * Basis.from_scale(Vector3(1.9, 0.14, 1.34)), at + Vector3(0, 1.48, 0) + b * Vector3(0.2, 0, 0)), Color(0.86, 0.88, 0.92)])
	_lit.append([Transform3D(b * Basis.from_scale(Vector3(1.0, 0.1, 1.4)), at + Vector3(0, 0.96, 0) + b * Vector3(-1.4, 0, 0)), Color(0.86, 0.88, 0.92)])
	_lit.append([Transform3D(b * Basis.from_scale(Vector3(4.15, 0.2, 1.66)), at + Vector3(0, 0.24, 0)), Color(0.10, 0.10, 0.10)])

## Тополь полосы за краем — облегчённый (EnvDress.poplar дороже): ствол, 5–7 сучьев, ветви в куржаке; без теней.
func _tree(base: Vector3, seed: int) -> void:
	var h := 13.0 + 5.0 * _rand(seed, 1)
	var fork := h * (0.34 + 0.08 * _rand(seed, 2))
	var top := base + Vector3((_rand(seed, 3) - 0.5) * 0.8, fork, (_rand(seed, 4) - 0.5) * 0.8)
	_bark.append(_beam(base - Vector3(0, 0.1, 0), top, 0.8))
	var limbs := 5 + int(_rand(seed, 5) * 3.0)
	for i in limbs:
		var yaw := TAU * (i + _rand(seed, 10 + i) * 0.6) / limbs
		var tilt := deg_to_rad(20.0 + 25.0 * _rand(seed, 20 + i))
		var dir := Vector3(cos(yaw) * sin(tilt), cos(tilt), sin(yaw) * sin(tilt))
		var end := top + dir * (h - fork) * (0.7 + 0.3 * _rand(seed, 30 + i))
		_bark.append(_beam(top, end, 0.34))
		for j in 3:
			var from := top.lerp(end, 0.35 + 0.25 * j)
			var by := yaw + (_rand(seed, 40 + i * 3 + j) - 0.5) * 2.2
			var bd := Vector3(cos(by) * 0.55, 0.85, sin(by) * 0.55).normalized()
			var to := from + bd * (1.8 + 1.8 * _rand(seed, 60 + i * 3 + j))
			_bark.append(_beam(from, to, 0.12))
			_frost.append(_beam(from.lerp(to, 0.2), to, 0.3))
		_frost.append(_beam(top.lerp(end, 0.5), end, 0.36))

## Ближний ряд лицом к арене (CITY-02 F; сверка: «коробки-сетки окон»): цоколь, подъезды с козырьком под снегом,
## ступенями и лампой; у панельных — столбы лоджий с ограждением и остеклением (часть горит). Без коллизий.
func _house_front(center: Vector2, size: Vector3, seed: int, low: bool, side: String, floors: int) -> void:
	var long_x := size.x >= size.z
	var length := size.x if long_x else size.z
	var depth := size.z if long_x else size.x
	var out := {"north": Vector3(0, 0, 1), "south": Vector3(0, 0, -1), "west": Vector3(1, 0, 0), "east": Vector3(-1, 0, 0)}[side] as Vector3
	var u := Vector3(1, 0, 0) if long_x else Vector3(0, 0, 1)
	if absf(out.dot(u)) > 0.5:
		return   # торцом к арене (башни второго ряда) — без лоджий
	var face := Vector3(center.x, 0, center.y) + out * depth * 0.5
	var basis := Basis(u, Vector3.UP, out)
	var storey := 3.3 if low else 2.8
	_lit.append([Transform3D(basis * Basis.from_scale(Vector3(length + 0.2, 1.1, 0.5)), face + Vector3(0, 0.55, 0)), Color(0.24, 0.23, 0.22)])
	var entrances := maxi(1, int(length / (20.0 if low else 24.0)))
	for e in entrances:
		var p := face + u * (-length * 0.5 + length * (e + 0.5) / entrances)
		_lit.append([Transform3D(basis * Basis.from_scale(Vector3(1.5, 2.2, 0.14)), p + Vector3(0, 1.1, 0) + out * 0.05), Color(0.18, 0.13, 0.10)])
		_lit.append([Transform3D(basis * Basis.from_scale(Vector3(3.0, 0.16, 1.6)), p + Vector3(0, 2.75, 0) + out * 0.8), Color(0.42, 0.42, 0.40)])
		_lit.append([Transform3D(basis * Basis.from_scale(Vector3(3.0, 0.2, 1.6)), p + Vector3(0, 2.93, 0) + out * 0.8), Color(0.88, 0.90, 0.94)])
		_lit.append([Transform3D(basis * Basis.from_scale(Vector3(2.6, 0.45, 1.3)), p + Vector3(0, 0.22, 0) + out * 0.7), Color(0.36, 0.35, 0.34)])
		_glow.append([Transform3D(basis * Basis.from_scale(Vector3(0.3, 0.14, 0.14)), p + Vector3(0, 2.55, 0) + out * 0.35), Color(1.0, 0.82, 0.55)])
		_light(p + Vector3(0, 2.5, 0) + out * 0.4, Color(1.0, 0.75, 0.45), 0.6, 0, 0.0, 0.35)
	if low:
		return
	# Лоджии столбами со 2-го этажа до верха; простенки без лоджий; ограждение крашеное, остекление разное.
	var cols := maxi(2, int(length / 6.5))
	var paint: Color = [Color(0.62, 0.64, 0.66), Color(0.48, 0.56, 0.66), Color(0.66, 0.60, 0.52), Color(0.56, 0.58, 0.56)][seed % 4]
	for c in cols:
		if c % 3 == 1:
			continue
		var p := face + u * (-length * 0.5 + length * (c + 0.5) / cols)
		for f in range(1, floors):
			var y := f * storey + 0.2
			_lit.append([Transform3D(basis * Basis.from_scale(Vector3(3.0, 1.0, 0.1)), p + Vector3(0, y + 0.5, 0) + out * 1.2), paint * (0.85 + 0.25 * _rand(seed + c, f + 50))])
			_lit.append([Transform3D(basis * Basis.from_scale(Vector3(3.1, 0.12, 1.25)), p + Vector3(0, y, 0) + out * 0.62), Color(0.40, 0.40, 0.40)])
			_lit.append([Transform3D(basis * Basis.from_scale(Vector3(3.0, 0.08, 1.2)), p + Vector3(0, y + 1.05, 0) + out * 1.2), Color(0.88, 0.90, 0.94)])   # снег на ограждении
			if _rand(seed * 31 + c, f) < 0.55:
				var glass := Transform3D(basis * Basis.from_scale(Vector3(2.9, 1.25, 0.05)), p + Vector3(0, y + 1.7, 0) + out * 1.18)
				if _rand(seed * 7 + c, f + 90) < 0.3:
					_glow.append([glass, Color(1.0, 0.72, 0.38) * (0.55 + 0.3 * _rand(seed, f + c))])
				else:
					_lit.append([glass, Color(0.10, 0.12, 0.15)])
		var wall_h := (floors - 1) * storey
		for sgn: float in [-1.0, 1.0]:
			_lit.append([Transform3D(basis * Basis.from_scale(Vector3(0.14, wall_h, 1.25)), p + u * sgn * 1.55 + Vector3(0, storey + wall_h * 0.5, 0) + out * 0.62), paint * 0.8])

## Полоса между краем карты и ближним рядом (CITY-02 F): тополя в куржаке, ряды гаражей, бетонный забор.
func _belt() -> void:
	var b := Layout.BOUNDS
	var seed := 900
	for side in ["north", "south", "west", "east"]:
		var along_x: bool = side == "north" or side == "south"
		var pos := (b.position.x if along_x else b.position.y) - 20.0
		var hi := (b.end.x if along_x else b.end.y) + 20.0
		while pos < hi:
			seed += 1
			var off := 5.0 + 13.0 * _rand(seed, 1)
			var p: Vector2 = {"north": Vector2(pos, b.position.y - off), "south": Vector2(pos, b.end.y + off),
				"west": Vector2(b.position.x - off, pos), "east": Vector2(b.end.x + off, pos)}[side]
			var garage := Rect2(31, 127, 58, 11).has_point(p) or Rect2(-116, 45, 11, 50).has_point(p)
			if not _on_street(p, 3.0) and not _kept_out(p, 4.0) and not garage:
				_tree(Vector3(p.x, 0, p.y), seed)
			pos += 8.0 + 8.0 * _rand(seed, 2)
	# Гаражи: ряд за двором на юго-востоке и ряд за H2 на западе — воротами к арене.
	_garages(Vector3(34, 0, 133), Vector3(1, 0, 0), Vector3(0, 0, -1), 16, 31)
	_garages(Vector3(-122, 0, 48), Vector3(0, 0, 1), Vector3(1, 0, 0), 14, 47)
	# Бетонный забор плитами за H10 и гаражами улицы C; разрыв — проезд улицы D.
	var x := -98.0
	var k := 0
	while x < 28.0:
		k += 1
		if _on_street(Vector2(x + 1.25, b.position.y - 3.0), 1.0):
			x += 2.5
			continue
		var at := Vector3(x + 1.25, 1.2, b.position.y - 3.0)
		_lit.append([Transform3D(Basis.from_scale(Vector3(2.45, 2.4, 0.16)), at), Color(0.50, 0.50, 0.48) * (0.9 + 0.15 * _rand(k, 3))])
		_lit.append([Transform3D(Basis.from_scale(Vector3(2.5, 0.08, 0.22)), at + Vector3(0, 1.24, 0)), Color(0.88, 0.90, 0.94)])
		x += 2.5

## Ряд кирпичных гаражей: count боксов вдоль u, воротами к face; ворота крашеные, снег на крышах.
func _garages(start: Vector3, u: Vector3, face: Vector3, count: int, seed: int) -> void:
	var basis := Basis(u, Vector3.UP, face)
	for i in count:
		var c := start + u * (i * 3.3 + 1.65)
		_lit.append([Transform3D(basis * Basis.from_scale(Vector3(3.25, 2.5, 6.0)), c + Vector3(0, 1.25, 0)), Color(0.42, 0.26, 0.20) * (0.85 + 0.25 * _rand(seed, i))])
		_lit.append([Transform3D(basis * Basis.from_scale(Vector3(2.6, 2.05, 0.06)), c + Vector3(0, 1.05, 0) + face * 3.02), GARAGE_DOORS[(seed + i * 7) % GARAGE_DOORS.size()]])
		_lit.append([Transform3D(basis * Basis.from_scale(Vector3(3.3, 0.22, 6.2)), c + Vector3(0, 2.62, 0)), Color(0.88, 0.90, 0.94)])

# --- ТЭЦ ---

## Трубы ТЭЦ: красно-белые полосы, огни на трети, двух третях и на верху (мигают), шлейф пара на запад.
## Две в перспективе улицы B, третья на западе (ART-06, Н7, С2–С4); с части F — вдвое дальше от края карты.
## Шлейф — 26 мягких клубов-билбордов (shaders/steam_plume): белёсое облако, сносимое ветром (С3), без краёв сфер.
func chimneys() -> void:
	var red := Color(0.50, 0.21, 0.20)
	var white := Color(0.62, 0.64, 0.66)
	var tops: Array[Vector3] = []
	for spec in CHIMNEYS:
		var at: Vector3 = spec[0]
		var height: float = spec[1]
		var bands := 10
		for i in bands:
			var r := lerpf(4.0, 2.4, (i + 0.5) / bands) * 2.0
			var y0 := height * i / bands
			_far_cyl.append([Transform3D(Basis.from_scale(Vector3(r, height / bands, r)), at + Vector3(0, y0 + height / bands * 0.5, 0)), red if i % 2 == 0 else white])
		_far_cyl.append([Transform3D(Basis.from_scale(Vector3(5.6, 1.2, 5.6)), at + Vector3(0, height + 0.6, 0)), Color(0.18, 0.17, 0.17)])   # оголовок
		for k in 3:
			_light(at + Vector3(0, height * (k + 1) / 3.0 + 1.5, 2.6), BEACON, 1.0, 1, 0.33 * k, 0.9)
		tops.append(at + Vector3(0, height + 1.5, 0))
	add_child(plume("ChimneySteam", tops, 26, {"wind": Vector3(-150, 0, -35), "life": 42.0, "rise": 32.0,
		"size_start": 6.0, "size_end": 42.0, "spread": 0.55, "color": Color(0.70, 0.72, 0.77, 0.7)}, 11))

## Шлейф пара: puffs клубов на каждую точку, фазы равномерно по жизни клуба (непрерывный поток), разброс по seed.
static func plume(node_name: String, points: Array[Vector3], puffs: int, params: Dictionary, seed: int) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = points.size() * puffs
	var index := 0
	for v in points.size():
		var shift := _rand(seed + v * 13, 1)
		for k in puffs:
			mm.set_instance_transform(index, Transform3D(Basis.IDENTITY, points[v]))
			mm.set_instance_custom_data(index, Color(fposmod(shift + (k + 0.3 * _rand(seed + v, k + 7)) / puffs, 1.0),
				_rand(seed + v * 5, k + 20), _rand(seed + v * 3, k + 60), 0.0))
			index += 1
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = Materials.steam_plume(params)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1000, -20, -1000), Vector3(2000, 400, 2000))   # клубы уходят от точек в шейдере
	return node

## Градирни ТЭЦ (гиперболоиды) к северо-западу, за трубами; над ними — широкие столбы пара.
func _cooling_towers() -> void:
	var mesh := _hyperboloid()
	var tops: Array[Vector3] = []
	for spec in TOWERS:
		var tower := MeshInstance3D.new()
		tower.name = "CoolingTower"
		tower.mesh = mesh
		tower.material_override = Materials.far_vertex()
		tower.position = spec[0]
		tower.scale = Vector3.ONE * float(spec[1])
		tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tower)
		tops.append((spec[0] as Vector3) + Vector3(0, 72.0 * float(spec[1]) - 4.0, 0))
	add_child(plume("TowerSteam", tops, 16, {"wind": Vector3(-70, 0, -20), "life": 55.0, "rise": 85.0,
		"size_start": 30.0, "size_end": 70.0, "spread": 0.45, "color": Color(0.72, 0.74, 0.78, 0.5)}, 23))

## Гиперболоид 72 м: радиус 30 у земли, горло 17 на 0,78 высоты, 21 наверху; светотень запечена в цвет вершины.
static func _hyperboloid() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var sectors := 32
	var light := Vector3(-0.5, 0.3, 0.8).normalized()
	for r in rings + 1:
		var t := float(r) / rings
		var y := 72.0 * t
		var dy := (t - 0.78) / 0.78
		var radius := 17.0 * sqrt(1.0 + dy * dy * 2.1)
		for s in sectors + 1:
			var a := TAU * s / sectors
			var n := Vector3(cos(a), 0.15, sin(a)).normalized()
			var shade := 0.62 + 0.38 * maxf(0.0, n.dot(light))
			var base := Color(0.46, 0.47, 0.48) * shade
			if t > 0.9:
				base = base.darkened(0.25)   # копоть у кромки
			st.set_color(_haze(base, 0.5))
			st.add_vertex(Vector3(cos(a) * radius, y, sin(a) * radius))
	for r in rings:
		for s in sectors:
			var a := r * (sectors + 1) + s
			var c := a + sectors + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(c)
			st.add_index(a + 1)
			st.add_index(c + 1)
			st.add_index(c)
	return st.commit()

# --- краны ---

## Башенный кран: мачта, стрела-ферма из двух поясов с раскосами, противовесная консоль с грузом, кабина со светом,
## трос с крюком; красные огни на верху мачты и на концах стрелы (мигают). Цвета с дымкой (видно за туманом).
func crane(at: Vector3, height: float, yaw: float) -> void:
	var dist := Vector2(at.x, at.z).length()
	var k := clampf((dist - 100.0) / 300.0, 0.25, 0.65)
	var steel := _haze(Color(0.62, 0.50, 0.16), k)
	var dark := _haze(Color(0.25, 0.25, 0.26), k)
	var basis := Basis(Vector3.UP, yaw)
	var top := at + Vector3(0, height, 0)
	_far_box.append([Transform3D(Basis.from_scale(Vector3(1.8, height, 1.8)), at + Vector3(0, height * 0.5, 0)), steel])
	# Стрела вперёд 40 м, консоль назад 12 м: нижние пояса и верхний пояс к оголовку.
	var fwd := basis * Vector3(1, 0, 0)
	var tip := top + fwd * 40.0
	var tail := top - fwd * 12.0
	var apex := top + Vector3(0, 7.0, 0)
	_far_box.append([_beam(top + Vector3(0, 0.2, 0), tip, 1.0), steel])
	_far_box.append([_beam(top + Vector3(0, 1.8, 0), tip + Vector3(0, 0.6, 0), 0.5), steel])
	for i in 10:
		var a := top.lerp(tip, i / 10.0) + Vector3(0, 0.2, 0)
		var b := top.lerp(tip, (i + 0.5) / 10.0) + Vector3(0, 1.8 - 1.2 * (i + 0.5) / 10.0, 0)
		_far_box.append([_beam(a, b, 0.25), steel])
	_far_box.append([_beam(top, tail, 1.0), steel])
	_far_box.append([_beam(apex, tip + Vector3(0, 0.8, 0), 0.25), dark])   # ванты
	_far_box.append([_beam(apex, tail, 0.25), dark])
	_far_box.append([_beam(top, apex, 1.2), steel])
	_far_box.append([Transform3D(basis * Basis.from_scale(Vector3(4, 2.6, 2.4)), tail + Vector3(0, -0.8, 0) + fwd * 1.5), dark])   # груз
	_far_box.append([Transform3D(basis * Basis.from_scale(Vector3(2.4, 2.4, 2.4)), top + Vector3(0, -1.6, 0) + fwd * 1.8), steel])   # кабина
	_light(top + Vector3(0, -1.6, 0) + fwd * 3.1, Color(1.0, 0.8, 0.5), 0.5, 0, 0.0, 0.5)
	var hook := top + fwd * (14.0 + 18.0 * _rand(int(at.x), 3))
	_far_box.append([_beam(hook, hook - Vector3(0, height * 0.55, 0), 0.12), dark])
	_far_box.append([Transform3D(Basis.from_scale(Vector3(1.0, 1.4, 1.0)), hook - Vector3(0, height * 0.55 + 0.7, 0)), dark])
	_light(apex + Vector3(0, 0.6, 0), BEACON, 1.0, 1, _rand(int(at.z), 1), 0.8)
	_light(tip + Vector3(0, 0.6, 0), BEACON, 1.0, 1, _rand(int(at.z), 2), 0.8)
	_light(tail + Vector3(0, 0.6, 0), BEACON, 1.0, 1, _rand(int(at.z), 4), 0.8)

# --- огни и сборка ---

## Огонь-точка: mode 0 ровный, 1 мигает; size — диаметр вблизи (вдали — не меньше 3 пикселей).
func _light(at: Vector3, color: Color, energy: float, mode: int, phase: float, size: float) -> void:
	_lights.append([Transform3D(Basis.from_scale(Vector3(size, size, size)), at), Color(color.r, color.g, color.b, energy), Color(float(mode), phase, 0, 0)])

## Собрать пакеты (вызывается один раз, после труб ТЭЦ).
func finish() -> void:
	_emit("FarBoxes", BoxMesh.new(), _far_box, Materials.far_vertex(), false)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 1
	_emit("FarCylinders", cyl, _far_cyl, Materials.far_vertex(), false)
	var blocks := []
	for blk in _blocks:
		blocks.append([blk[0], Color.WHITE, blk[1]])
	_emit("MidBlocks", BoxMesh.new(), blocks, Materials.skyline_block(), true)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_emit("Lights", quad, _lights, Materials.skyline_lights(), true)
	_emit("NearDecor", BoxMesh.new(), _lit, Materials.instance_colored(), false)
	_emit("NearGlow", BoxMesh.new(), _glow, Materials.glow_vertex(), false)
	var pool := PlaneMesh.new()
	pool.size = Vector2.ONE
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = load("res://game/world/shaders/light_pool.gdshader")
	_emit("StreetPools", pool, _pools, pool_mat, false)
	var limb := CylinderMesh.new()
	limb.top_radius = 0.32
	limb.bottom_radius = 0.5
	limb.height = 1.0
	limb.radial_segments = 5
	limb.rings = 1
	limb.cap_top = false
	limb.cap_bottom = false
	var bark := []
	for xf in _bark:
		bark.append([xf, Color(0.16, 0.15, 0.14)])
	var frost := []
	for xf in _frost:
		frost.append([xf, Color(0.88, 0.88, 0.90)])
	_emit("BeltBark", limb, bark, Materials.instance_colored(), false)
	_emit("BeltFrost", limb, frost, Materials.instance_colored(), false)
	for variant in _banks:
		var parts := (variant as String).split("_")
		var mesh := EnvDress.bank_mesh(9.0, 1.4, 0.9, 400 + int(parts[1]) * 37, float(parts[0]))
		var items := []
		for xf in _banks[variant]:
			items.append([xf, Color.WHITE])
		_emit("StreetBanks_" + variant, mesh, items, Materials.bank_snow(1.0), false)
	_far_box.clear()
	_far_cyl.clear()
	_blocks.clear()
	_lights.clear()
	_lit.clear()
	_glow.clear()
	_pools.clear()
	_bark.clear()
	_frost.clear()
	_banks.clear()

func _emit(node_name: String, mesh: Mesh, items: Array, material: Material, custom: bool) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
		if custom:
			mm.set_instance_custom_data(i, items[i][2])
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node_name == "Lights":
		inst.custom_aabb = AABB(Vector3(-1000, -10, -1000), Vector3(2000, 300, 2000))   # фары бегут за пределы исходных точек
	add_child(inst)

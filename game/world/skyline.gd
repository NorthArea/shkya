extends Node3D
## CITY-02 E: панорама «масштабно» — большой Новосибирск за краем карты (ART-04, черты 20, 21; ART-06, Н7).
## Слои по глубине: ближний ряд (25–75 м за краем) — объёмы с фасадным шейдером и окнами; средний (90–270 м) —
## сотни домов одним MultiMesh (shaders/skyline_block); горизонт (520 и 850 м) — кольца-силуэты с окнами и
## натриевым заревом (shaders/skyline_far). ТЭЦ — трубы в полоску с паром, градирни; башенные краны; на западе —
## арочный мост через Обь с фонарями и потоком фар; продолжения улиц — цепочки фонарей. Заградительные огни мигают.
##
## Только вид, без коллизий и теней. Карта не расширяется (C9, п. 4): всё — за Layout.BOUNDS. Раскладка по seed.
## Дальние материалы без тумана сцены, дымка — в самом цвете (как Materials.far, ART-06, С2). Формы — свои.

const Layout = preload("res://game/world/layout.gd")
const Greybox = preload("res://game/world/greybox.gd")
const Materials = preload("res://game/world/materials.gd")

const HAZE := Color(0.24, 0.30, 0.37)    # = fog_light_color lighting.gd
const SODIUM := Color(1.0, 0.62, 0.18)
const BEACON := Color(1.0, 0.10, 0.05)
# Куда не ставить дома: [центр, радиус] — башня «ГОСТИНИЦА», трубы ТЭЦ, градирни, краны.
const KEEP_OUT := [[Vector2(70, -205), 26.0], [Vector2(15, -185), 14.0], [Vector2(35, -200), 14.0], [Vector2(-150, -95), 14.0],
	[Vector2(-55, -300), 42.0], [Vector2(-115, -315), 42.0], [Vector2(25, -235), 45.0]]
# Продолжения улиц за краем карты: [сторона, от, до] — здесь ближний ряд разорван, видны дальние слои.
const STREET_GAPS := {"north": [[58.0, 82.0], [-72.0, -48.0]], "west": [[18.0, 46.0]], "east": [[18.0, 46.0]], "south": [[-26.0, -6.0]]}
const RING_RADII := [520.0, 850.0]

var _far_box := []      # [преобразование, цвет] — мост, краны, ТЭЦ: без света, дымка в цвете
var _far_cyl := []
var _blocks := []       # [преобразование, custom] — средний слой
var _lights := []       # [преобразование, цвет, custom]

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

## Весь город, кроме труб ТЭЦ (их строит chimneys() — отдельный вызов LevelGeometry._build_chimneys).
func build_city() -> void:
	_ground()
	_near_rows()
	_mid_blocks()
	_rings()
	_bridge()
	_street_lights()
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
			if out < 88.0 or out > 280.0 or _kept_out(p, 22.0):
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
	_blocks.append([Transform3D(Basis.from_scale(Vector3(80, 34, 36)), Vector3(25, 17, -235)), Color(0.31, 0.08, 0.55, 0.6)])
	_blocks.append([Transform3D(Basis.from_scale(Vector3(40, 46, 24)), Vector3(-5, 23, -238)), Color(0.57, 0.05, 0.55, 0.45)])
	_far_box.append([Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.42)) * Basis.from_scale(Vector3(70, 4, 5)), Vector3(80, 20, -230)), _haze(Color(0.32, 0.33, 0.34), 0.55)])

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

## Продолжения улиц за краем: двойные цепочки натриевых фонарей уходят к горизонту, по ним бегут фары.
func _street_lights() -> void:
	var b := Layout.BOUNDS
	# [начало, направление, поперёк, длина]
	var streets := [[Vector3(64, 0, b.position.y - 6.0), Vector3(0, 0, -1), Vector3(1, 0, 0), 380.0, 12.0],
		[Vector3(-60, 0, b.position.y - 6.0), Vector3(0, 0, -1), Vector3(1, 0, 0), 380.0, 12.0],
		[Vector3(b.end.x + 6.0, 0, 32), Vector3(1, 0, 0), Vector3(0, 0, 1), 380.0, 18.0],
		[Vector3(b.position.x - 6.0, 0, 32), Vector3(-1, 0, 0), Vector3(0, 0, 1), 300.0, 18.0]]
	for i in streets.size():
		var s: Array = streets[i]
		var start: Vector3 = s[0]
		var dir: Vector3 = s[1]
		var across: Vector3 = s[2]
		var length: float = s[3]
		var width: float = s[4]
		var d := 30.0
		while d < length:
			for side: float in [-0.5, 0.5]:
				_light(start + dir * d + across * side * width + Vector3(0, 7.6, 0), SODIUM, 0.8, 0, 0.0, 0.8)
			d += 28.0
		for k in 6:
			var way := 1.0 if k % 2 == 0 else -1.0
			var path := dir * length * way
			var xf := _path_xf(start + dir * length * 0.5 + across * way * width * 0.2 + Vector3(0, 0.8, 0), path, 0.5)
			_lights.append([xf, Color(1.0, 0.92, 0.75, 0.7) if way < 0.0 else Color(1.0, 0.1, 0.05, 0.6), Color(2.0, _rand(i * 7 + k, 1), 0.02 + 0.01 * _rand(i * 7 + k, 2), 0)])

# --- ТЭЦ ---

## Трубы ТЭЦ: красно-белые полосы, огни на трети, двух третях и на верху (мигают), шлейф пара на запад.
## Места и высоты — как приняты в ART-06 (Н7, С2–С4): две в перспективе улицы B, третья на западе.
func chimneys() -> void:
	var red := Color(0.50, 0.21, 0.20)
	var white := Color(0.62, 0.64, 0.66)
	var steam := Materials.far(Color(0.66, 0.68, 0.72, 0.55))
	var steam_thin := Materials.far(Color(0.66, 0.68, 0.72, 0.32))
	for spec in [[Vector3(15, 0, -185), 80.0], [Vector3(35, 0, -200), 90.0], [Vector3(-150, 0, -95), 85.0]]:
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
		for k in 9:
			var puff := Greybox.mesh_sphere(1.0, Color.WHITE)
			puff.material_override = steam if k < 6 else steam_thin
			var r := 4.0 + k * 2.4
			puff.scale = Vector3(r, r * 0.8, r)
			puff.position = at + Vector3(-k * 6.8, height + 3.0 + k * 1.7, -k * 1.6)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(puff)

## Градирни ТЭЦ (гиперболоиды) к северо-западу, за трубами; над ними — столбы пара.
func _cooling_towers() -> void:
	var mesh := _hyperboloid()
	var steam := Materials.far(Color(0.70, 0.72, 0.76, 0.5))
	for spec in [[Vector3(-55, 0, -300), 1.0], [Vector3(-115, 0, -315), 0.9]]:
		var tower := MeshInstance3D.new()
		tower.name = "CoolingTower"
		tower.mesh = mesh
		tower.material_override = Materials.far_vertex()
		tower.position = spec[0]
		tower.scale = Vector3.ONE * float(spec[1])
		tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tower)
		for k in 7:
			var puff := Greybox.mesh_sphere(1.0, Color.WHITE)
			puff.material_override = steam
			var r := (16.0 + k * 4.5) * float(spec[1])
			puff.scale = Vector3(r, r * 0.75, r)
			puff.position = (spec[0] as Vector3) + Vector3(-k * 7.0, 72.0 * float(spec[1]) + 8.0 + k * 9.0, -k * 3.0)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(puff)

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
	_far_box.clear()
	_far_cyl.clear()
	_blocks.clear()
	_lights.clear()

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

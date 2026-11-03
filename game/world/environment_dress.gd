extends Node3D
## CITY-02 E: среда зимнего города Н. — то, что стоит между домами (ART-04, черты 8–19, 22; ART-05/06).
## Сетки валов и сугробов с шумом, коркой и срезом лопаты; бордюры, наледь, проталины и люки на тротуарах;
## тополя с ветвями второго-третьего порядка и кронированные «с волчками», берёзы с чечевичками; снег на развилках;
## провода со снежной «гирляндой» и скрутками; объявления и коробки на столбах.
##
## Только вид: коллизии — коробки Layout (C9), здесь их нет. Повторы — MultiMesh общими пакетами (как buildings.gd);
## мелочь — в ближних пакетах по клеткам NEAR_CELL, дальше NEAR_RANGE от камеры она не рисуется (C9: LOD).
## Раскладка — по seed (_rand), без случайностей. Формы — своя геометрия по описаниям ART-04/06, без чужих ассетов.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const SnowField = preload("res://game/world/snow_field.gd")   # DRIVE-02, C10: форма валов для вида и колёс

const NEAR_CELL := 30.0
const NEAR_RANGE := 60.0
const BARK := Color(0.16, 0.15, 0.14)
# Куржак — толстая изморозь на ветках (ART-06, Н8: крона #b9b5b2, `Trees, Novosibirsk 1.jpg`). Канон говорит
# «мокрый снег»; куржак добавлен решением владельца 28.10.2026.
const FROST := Color(0.88, 0.88, 0.90)   # светлее замера (#b9b5b2 днём): ночью в слабом свете иначе не читается
const BIRCH_WHITE := Color(0.86, 0.85, 0.81)
const BIRCH_DARK := Color(0.10, 0.10, 0.10)
const PAPER := [Color(0.86, 0.85, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.86, 0.72), Color(0.92, 0.80, 0.78), Color(0.95, 0.95, 0.92)]
const CURB := [Color(0.48, 0.48, 0.47), Color(0.55, 0.55, 0.54), Color(0.42, 0.42, 0.42), Color(0.60, 0.58, 0.55)]

# Пакеты: имя → [сетка, материал, тени]. Материал «detail» — цвет экземпляра и INSTANCE_CUSTOM (Materials.detail).
const BATCHES := {
	"bark": ["limb", "bark", true],      # стволы и ветви тополей
	"frost": ["limb", "frost", false],   # куржак
	"birch": ["limb", "detail", true],   # стволы берёз (цвет экземпляра — белый или тёмный низ)
	"twig": ["limb", "bark", false],     # тонкие ветки третьего порядка (ближние)
	"paint": ["box", "detail", false],
	"paint_sh": ["box", "detail", true],
	"rod": ["cyl", "detail", false],
	"snow": ["box", "snow", false],
	"lump": ["dome", "snow", false],
	"icicle": ["cone", "ice", false],
	"patch": ["plane", "patch", false],
	"wire_snow": ["cyl", "frost", false],
}

var _batches := {}
var _meshes := {}
static var _domes := []   # общие сетки сугробов-куполов (_mound): 4 варианта шума
## BREAK-03 (C11): экземпляры, поставленные при непустом owners, падают вместе с разрушаемым (id); при непустом
## wire_owners — висят, пока целы все эти столбы. Записи — в registry (LevelGeometry.break_visuals).
var owners: Array = []
var wire_owners: Array = []
var registry := {}

func _init() -> void:
	name = "Environment"

# --- пакеты ---

## Экземпляр в пакет; near — в ближний пакет своей клетки (дальше NEAR_RANGE не рисуется).
func put(batch: String, xf: Transform3D, color := Color.WHITE, custom := Color(0, 0, 0, 0), near := false) -> void:
	var key := batch
	var cell := Vector2i.ZERO
	if near:
		cell = Vector2i(floori(xf.origin.x / NEAR_CELL), floori(xf.origin.z / NEAR_CELL))
		key = "%s|%d|%d" % [batch, cell.x, cell.y]
	if not _batches.has(key):
		_batches[key] = {"batch": batch, "near": near, "cell": cell, "xf": [], "color": [], "custom": [], "owned": [], "wired": []}
	var store: Dictionary = _batches[key]
	if not owners.is_empty():
		(store.owned as Array).append([(store.xf as Array).size(), owners.duplicate()])
	elif not wire_owners.is_empty():
		(store.wired as Array).append([(store.xf as Array).size(), wire_owners.duplicate()])
	(store.xf as Array).append(xf)
	(store.color as Array).append(color)
	(store.custom as Array).append(custom)

func box(size: Vector3, at: Vector3, color: Color, custom := Color(0, 0, 0, 0), near := true, yaw := 0.0, batch := "paint") -> void:
	put(batch, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), at), color, custom, near)

func seg(batch: String, from: Vector3, to: Vector3, diameter: float, color := Color.WHITE, near := false, custom := Color(0, 0, 0, 0)) -> void:
	put(batch, segment(from, to, diameter), color, custom, near)

## Собрать все пакеты в узлы MultiMeshInstance3D (один раз в конце LevelGeometry._ready).
func build() -> void:
	for key in _batches:
		var store: Dictionary = _batches[key]
		var origin := Vector3.ZERO
		var node_name := "Env_%s" % store.batch
		if store.near:
			var cell: Vector2i = store.cell
			origin = Vector3((cell.x + 0.5) * NEAR_CELL, 0.0, (cell.y + 0.5) * NEAR_CELL)
			node_name = "EnvNear_%s_%d_%d" % [store.batch, cell.x, cell.y]
		_emit(node_name, store, origin)
	_batches.clear()

func _emit(node_name: String, store: Dictionary, origin: Vector3) -> void:
	var spec: Array = BATCHES[store.batch]
	var transforms: Array = store.xf
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = spec[1] == "detail"
	mm.use_custom_data = spec[1] == "detail" or spec[1] == "patch"
	mm.mesh = _mesh(spec[0])
	mm.instance_count = transforms.size()
	for i in transforms.size():
		var xf: Transform3D = transforms[i]
		xf.origin -= origin
		mm.set_instance_transform(i, xf)
		if mm.use_colors:
			mm.set_instance_color(i, store.color[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, store.custom[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = mm
	instance.material_override = material(spec[1])
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = origin
	if store.near:
		instance.visibility_range_end = NEAR_RANGE
		instance.visibility_range_end_margin = 4.0
	add_child(instance)
	register(registry, instance, store.get("owned", []), "mm")
	register(registry, instance, store.get("wired", []), "wires")

## BREAK-03: экземпляры узла node с владельцами owned ([[индекс, [id]]]) — в registry (формат LevelGeometry.break_visuals).
static func register(registry: Dictionary, node: MultiMeshInstance3D, owned: Array, key: String) -> void:
	var mm := node.multimesh
	for e: Array in owned:
		var i: int = e[0]
		for id: StringName in e[1]:
			if not registry.has(id):
				registry[id] = {"nodes": [], "mm": [], "cut": [], "wires": []}
			if key == "wires":
				registry[id]["wires"].append([mm, i, mm.get_instance_transform(i), e[1]])
			else:
				registry[id]["mm"].append([mm, i, mm.get_instance_transform(i), node])

func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"box":
			mesh = BoxMesh.new()
		"limb", "cyl", "cone":
			var c := CylinderMesh.new()
			c.height = 1.0
			c.top_radius = {"limb": 0.32, "cyl": 0.5, "cone": 0.5}[kind]
			c.bottom_radius = {"limb": 0.5, "cyl": 0.5, "cone": 0.0}[kind]
			c.radial_segments = {"limb": 6, "cyl": 8, "cone": 5}[kind]
			c.rings = 1
			c.cap_top = kind != "limb"
			c.cap_bottom = kind == "cyl"
			mesh = c
		"dome":
			mesh = dome_mesh(1)
		"plane":
			var p := PlaneMesh.new()
			p.size = Vector2.ONE
			mesh = p
	_meshes[kind] = mesh
	return mesh

static func material(kind: String) -> Material:
	match kind:
		"bark":
			return Materials.plain(BARK, 0.95)
		"frost":
			return Materials.plain(FROST, 0.95)
		"detail":
			return Materials.detail()
		"snow":
			return Materials.snow(0.0)
		"ice":
			return Materials.ice()
		"patch":
			return Materials.ground_patch()
	return null

# --- помощники ---

static func _rand(seed: int, k: int) -> float:
	return fposmod(sin(float(seed + k) * 12.9898) * 43758.5453, 1.0)

## Цилиндр единичной высоты от from до to (сетка радиуса 0,5 — diameter = толщина).
static func segment(from: Vector3, to: Vector3, diameter: float) -> Transform3D:
	var axis := to - from
	var dir := axis.normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).normalized()
	var other := side.cross(dir).normalized()
	return Transform3D(Basis(side * diameter, axis, other * diameter), (from + to) * 0.5)

static func _dir(yaw: float, tilt: float) -> Vector3:
	return Vector3(sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw))

static func _hash2(x: float, y: float) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7) * 43758.5453, 1.0)

static func _noise2(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := lerpf(_hash2(ix, iy), _hash2(ix + 1.0, iy), fx)
	var b := lerpf(_hash2(ix, iy + 1.0), _hash2(ix + 1.0, iy + 1.0), fx)
	return lerpf(a, b, fy)

static func _fbm(x: float, y: float) -> float:
	return _noise2(x, y) * 0.55 + _noise2(x * 2.3 + 5.1, y * 2.3 - 3.7) * 0.3 + _noise2(x * 5.7 - 1.3, y * 5.7 + 8.2) * 0.15

# --- сетки снега ---

## Вал или сугроб вдоль x: коробка length × height × width (по z), основание на y = 0, центр в начале. Поверхность —
## SnowField.profile (DRIVE-02, C10: та же форма, по которой едут колёса «Лады»), сетка шагом ≈0,2 × 0,15 м с запасом
## SnowField.MARGIN за кромкой. toward — знак стороны дороги по z. Цвет вершины для snow_bank_mesh.gdshader:
## r — брызги от колёс со стороны дороги, g — корка на гребне, b — срез (крутой склон к дороге, ступени лопаты).
const BankMeshCache = preload("res://game/world/bank_mesh_cache.gd")
const BANK_GEOMETRY_SOURCE_ID := "env:517f7255fe8df8f1e174df8743e19061cdb7caef48ed4e9ab66b6ab2f9ea91bb|snow:e6bcf2c966bb9010fa373a32cefaae489236b08be57bd3d9a68fc8a077e74f6b"

static func bank_mesh_cache_key(length: float, width: float, height: float, seed: int, toward: float) -> PackedByteArray:
	var key := PackedByteArray()
	key.resize(80)
	key.encode_double(0, length)
	key.encode_double(8, width)
	key.encode_double(16, height)
	key.encode_s64(24, seed)
	key.encode_double(32, toward)
	key.encode_double(40, SnowField.CLOD)
	key.encode_double(48, SnowField.RAG)
	key.encode_double(56, SnowField.MARGIN)
	key.encode_double(64, SnowField.STEP_U)
	key.encode_double(72, SnowField.STEP_V)
	key.append_array(BANK_GEOMETRY_SOURCE_ID.to_utf8_buffer())
	return key

static func bank_mesh(length: float, width: float, height: float, seed: int, toward: float) -> ArrayMesh:
	var lookup_started := Time.get_ticks_usec()
	var key := bank_mesh_cache_key(length, width, height, seed, toward)
	var cached: ArrayMesh = BankMeshCache.get_mesh(key)
	BankMeshCache.record_lookup(Time.get_ticks_usec() - lookup_started)
	if cached != null:
		return cached
	var mesh := _bank_mesh_uncached(length, width, height, seed, toward)
	BankMeshCache.store_mesh(key, mesh)
	return mesh

static func _bank_mesh_uncached(length: float, width: float, height: float, seed: int, toward: float) -> ArrayMesh:
	var g := SnowField.grid(length, width)
	var hl: float = g[0]
	var hw: float = g[1]
	var nu: int = g[2]
	var nv: int = g[3]
	var sx := float(seed % 97) * 3.17
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize(nu * nv)
	for i in nu:
		var u := -hl + hl * 2.0 * float(i) / (nu - 1)
		for j in nv:
			var v := -hw + hw * 2.0 * float(j) / (nv - 1)
			heights[i * nv + j] = SnowField.profile(u, v, length, width, height, seed, toward)
	for i in nu:
		var u := -hl + hl * 2.0 * float(i) / (nu - 1)
		for j in nv:
			var v := -hw + hw * 2.0 * float(j) / (nv - 1)
			var y := heights[i * nv + j]
			var t := v / hw
			var road := t * toward
			var slope := absf(heights[i * nv + mini(j + 1, nv - 1)] - heights[i * nv + maxi(j - 1, 0)]) / (4.0 * hw / (nv - 1))
			var dirt := clampf(road * 1.4, 0.0, 1.0)
			dirt = (dirt * dirt + 0.15 * _noise2(u * 0.6 + sx, 3.3)) * absf(toward)
			var crust := smoothstep(0.55, 0.85, y / maxf(height, 0.01)) * smoothstep(0.35, 0.75, _noise2(u * 0.45 + sx, 7.7))
			var cut := smoothstep(0.6, 1.4, slope) * (0.6 + 0.4 * clampf(road + 0.5, 0.0, 1.0))
			st.set_color(Color(clampf(dirt, 0.0, 1.0), crust, cut))
			st.add_vertex(Vector3(u, y if y > 0.0 else -0.02, v))
	for i in nu - 1:
		for j in nv - 1:
			var a := i * nv + j
			if heights[a] <= 0.0 and heights[a + 1] <= 0.0 and heights[a + nv] <= 0.0 and heights[a + nv + 1] <= 0.0:
				continue   # голая земля — не рисуем
			st.add_index(a)
			st.add_index(a + nv)
			st.add_index(a + 1)
			st.add_index(a + nv)
			st.add_index(a + nv + 1)
			st.add_index(a + 1)
	st.generate_normals()
	return st.commit()

## Купол сугроба: радиус 0,5 в плане, высота 0,5, основание y = 0 — как верхняя половина прежней SphereMesh,
## но с рваной кромкой и буграми. variant 0…3 — разный шум.
static func dome_mesh(variant: int) -> ArrayMesh:
	if _domes.is_empty():
		for v in 4:
			_domes.append(_make_dome(v))
	return _domes[variant % 4]

static func _make_dome(variant: int) -> ArrayMesh:
	var rings := 7
	var sectors := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := float(variant) * 7.3
	st.add_vertex(Vector3(0, 0.5 * (0.92 + 0.12 * _noise2(sx, 1.0)), 0))
	for r in range(1, rings + 1):
		var rho := float(r) / rings
		for s in sectors:
			var th := TAU * float(s) / sectors
			var wob := 1.0 + (_noise2(cos(th) * 1.6 + sx, sin(th) * 1.6) - 0.5) * 0.28
			var h := 0.5 * pow(maxf(0.0, 1.0 - rho * rho), 0.75)
			h *= 0.85 + 0.3 * _noise2(cos(th) * rho * 3.0 + sx, sin(th) * rho * 3.0 + 4.0)
			if r == rings:
				h = -0.01
			st.add_vertex(Vector3(cos(th) * 0.5 * rho * wob, h, sin(th) * 0.5 * rho * wob))
	for s in sectors:
		st.add_index(0)
		st.add_index(1 + s)
		st.add_index(1 + (s + 1) % sectors)
	for r in rings - 1:
		for s in sectors:
			var a := 1 + r * sectors + s
			var b := 1 + r * sectors + (s + 1) % sectors
			var c := a + sectors
			var d := b + sectors
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()

# --- деревья ---

## Тополь (ART-04, черта 8; ART-06, Н8): тёмный ствол с наплывом у земли, развилка на трети высоты, толстые изогнутые
## сучья, ветви второго и третьего порядка в куржаке, снег на развилках. Каждый третий — кронированный, как вдоль
## новосибирских улиц: короткие обрубленные сучья с «кулаками» и пучками прямых побегов-волчков.
func poplar(base: Vector3, seed: int) -> void:
	var rs := seed * 97
	var height := 15.0 + 4.0 * _rand(rs, 0)
	var pollard := _rand(rs, 3) < 0.34
	var fork := height * ((0.42 if pollard else 0.32) + 0.08 * _rand(rs, 1))
	var lean := Vector3((_rand(rs, 4) - 0.5) * 0.12, 1.0, (_rand(rs, 5) - 0.5) * 0.12).normalized()
	seg("bark", base - Vector3(0, 0.1, 0), base + Vector3(0, 0.7, 0), 1.35)   # наплыв у земли
	var top := base + lean * (fork + 0.5)
	var mid := base + lean * (fork * 0.5) + Vector3((_rand(rs, 6) - 0.5) * 0.25, 0, (_rand(rs, 7) - 0.5) * 0.25)
	seg("bark", base, mid, 1.0)
	seg("bark", mid, top, 0.88)
	var limbs := 4 + int(_rand(rs, 2) * 3.0)
	var crown_yaw := TAU * _rand(rs, 8)
	var frost_side := Vector3(cos(crown_yaw), 0, sin(crown_yaw))
	for i in limbs:
		# Не кольцо одинаковых сучьев: один лидер, остальные короче и расходятся с разных высот.
		var yaw := crown_yaw + float(i) * 2.399963 + (_rand(rs, 10 + i) - 0.5) * 1.1
		var tilt := deg_to_rad((22.0 if pollard else 16.0) + 28.0 * _rand(rs, 20 + i))
		var dir := _dir(yaw, tilt)
		var start := base + lean * (fork + 0.25 - 1.5 * _rand(rs, 30 + i))
		if _rand(rs, 60 + i) > 0.3:
			var snow_scale := 0.7 + 0.3 * _rand(rs, 70 + i)
			put("lump", Transform3D(Basis.from_scale(Vector3(0.55, 0.36, 0.55) * snow_scale), start + dir * 0.35 + Vector3(0, 0.12, 0)), Color.WHITE, Color(), true)
		if pollard:
			_pollard_limb(start, dir, yaw, rs + i * 41, height)
			continue
		var reach := 1.0 if i == 0 else 0.58 + 0.37 * _rand(rs, 40 + i)
		var limb_len := (height - fork) * reach
		var bend := (dir + Vector3(0, 0.2 + 0.35 * _rand(rs, 50 + i), 0) + frost_side * 0.12).normalized()
		var knee_t := 0.38 + 0.22 * _rand(rs, 80 + i)
		var knee := start + dir * limb_len * knee_t
		var end := knee + bend * limb_len * (1.0 - knee_t)
		seg("bark", start, knee, 0.46)
		seg("bark", knee, end, 0.32)
		var branches := 3 + int(_rand(rs, 90 + i) * 3.0)
		for j in branches:
			var t := 0.18 + 0.72 * (float(j) + _rand(rs, 600 + i * 10 + j) * 0.8) / branches
			var from := start.lerp(knee, t / knee_t) if t < knee_t else knee.lerp(end, (t - knee_t) / (1.0 - knee_t))
			var byaw := yaw + (_rand(rs, 100 + i * 10 + j) - 0.5) * 3.0
			var btilt := deg_to_rad(22.0 + 38.0 * _rand(rs, 200 + i * 10 + j))
			var bdir := _dir(byaw, btilt)
			var blen := (1.3 + 2.5 * _rand(rs, 300 + i * 10 + j)) * (1.0 - t * 0.45)
			var bmid := from + bdir * blen * 0.5
			var bend2 := bmid + (bdir + Vector3(0, 0.3, 0)).normalized() * blen * 0.5
			seg("bark", from, bmid, 0.15)
			seg("bark", bmid, bend2, 0.11)
			# Куржак собирается на одной стороне кроны, оставляя видимую тёмную древесину.
			var frost_load := 0.5 + 0.25 * bdir.dot(frost_side) + 0.25 * _rand(rs, 700 + i * 10 + j)
			if frost_load > 0.43:
				seg("frost", from.lerp(bmid, 0.25 + 0.5 * _rand(rs, 800 + i * 10 + j)), bmid, 0.24 + 0.06 * frost_load)
				seg("frost", bmid, bmid.lerp(bend2, 0.55 + 0.45 * frost_load), 0.21 + 0.05 * frost_load)
			var twigs := 1 + int(_rand(rs, 900 + i * 10 + j) * 3.0)
			for q in twigs:
				var tw := bmid.lerp(bend2, 0.15 + 0.65 * _rand(rs, 1000 + i * 30 + j * 3 + q)) if q > 0 else from.lerp(bmid, 0.6)
				var tyaw := byaw + (_rand(rs, 400 + i * 30 + j * 3 + q) - 0.5) * 3.0
				var tdir := Vector3(cos(tyaw) * 0.6, 0.8, sin(tyaw) * 0.6).normalized()
				var tend := tw + tdir * (0.7 + 0.8 * _rand(rs, 500 + q + j + i))
				seg("twig", tw, tend, 0.07, Color.WHITE, true)
				if frost_load > 0.5:
					seg("frost", tw.lerp(tend, 0.2 + 0.4 * _rand(rs, 1100 + i * 30 + j * 3 + q)), tend, 0.16 + 0.04 * frost_load, Color.WHITE, true)

## Кронированный сук: короткий и толстый, на конце наплыв-«кулак» в снегу и пучок прямых побегов вверх.
func _pollard_limb(start: Vector3, dir: Vector3, yaw: float, rs: int, height: float) -> void:
	var length := 2.2 + 1.8 * _rand(rs, 1)
	var end := start + dir * length
	seg("bark", start, end, 0.5)
	seg("bark", end - dir * 0.15, end + dir * 0.35, 0.75)   # кулак
	put("lump", Transform3D(Basis.from_scale(Vector3(0.6, 0.4, 0.6)), end + Vector3(0, 0.3, 0)), Color.WHITE, Color(), true)
	var shoots := 8 + int(_rand(rs, 2) * 6.0)
	var fan := yaw + (_rand(rs, 3) - 0.5) * 1.6
	var fan_dir := Vector3(cos(fan), 0, sin(fan))
	for k in shoots:
		var a := fan + (_rand(rs, 10 + k) - 0.5) * 3.8
		var r := 0.3 * _rand(rs, 20 + k)
		var from := end + Vector3(cos(a) * r, 0.2, sin(a) * r)
		var up := (Vector3(cos(a) * 0.28, 1.0, sin(a) * 0.28) + fan_dir * (0.08 + 0.2 * _rand(rs, 50 + k))).normalized()
		var l := (1.7 + 3.9 * _rand(rs, 30 + k)) * clampf(height / 17.0, 0.8, 1.2)
		var to := from + up * l
		seg("bark", from, to, 0.07)
		var frost_load := 0.65 + 0.35 * _rand(rs, 60 + k)
		if _rand(rs, 70 + k) > 0.2:
			seg("frost", from.lerp(to, 0.2 + 0.45 * _rand(rs, 80 + k)), to, 0.14 + 0.03 * frost_load)
		if _rand(rs, 90 + k) > 0.6:
			var side := from.lerp(to, 0.45 + 0.3 * _rand(rs, 100 + k))
			var sd := (up + Vector3(cos(a + 1.3), 0, sin(a + 1.3)) * 0.6).normalized()
			seg("twig", side, side + sd * 0.7, 0.05, Color.WHITE, true)
			if frost_load > 0.8:
				seg("frost", side, side + sd * 0.7, 0.13 + 0.03 * frost_load, Color.WHITE, true)

## Берёза (ART-04, черта 8): белый ствол с тёмными чечевичками и чёрным потрескавшимся низом, лёгкий наклон,
## подъёмистые сучья и свисающие тонкие ветки в куржаке. Ствол — по коллизии Layout.TREES (0,3 × 7 м), крона выше.
func birch(base: Vector3, height: float, seed: float) -> void:
	var rs := int(seed * 37.0) + 11
	var lean := Vector3((_rand(rs, 1) - 0.5) * 0.16, 1.0, (_rand(rs, 2) - 0.5) * 0.16).normalized()
	var crown := height * (1.25 + 0.2 * _rand(rs, 3))
	var pts: Array[Vector3] = [base]
	for k in 4:
		var y := crown * float(k + 1) / 4.0
		var sway := Vector3(sin(seed + k * 1.7), 0, cos(seed * 1.3 + k)) * 0.12 * k
		pts.append(base + lean * y + sway)
	var widths := [0.32, 0.27, 0.2, 0.12]
	for k in 4:
		seg("birch", pts[k], pts[k + 1], widths[k], BIRCH_WHITE)
	seg("birch", base - Vector3(0, 0.05, 0), base + lean * 0.9, 0.36, Color(0.20, 0.19, 0.18))   # чёрный низ
	# Чечевички и тёмные пятна: тонкие поперечные полоски вокруг ствола.
	for m in 26:
		var y := 0.9 + (crown * 0.62 - 0.9) * _rand(rs, 100 + m)
		var k := mini(3, int(y / (crown / 4.0)))
		var p: Vector3 = pts[k].lerp(pts[k + 1], fposmod(y / (crown / 4.0), 1.0))
		var a := TAU * _rand(rs, 200 + m)
		var r: float = widths[k] * 0.5 * 0.92
		var long := 0.05 + 0.16 * _rand(rs, 300 + m)
		var tall := 0.015 + 0.03 * _rand(rs, 400 + m) if m % 5 != 0 else 0.08 + 0.1 * _rand(rs, 400 + m)
		box(Vector3(long, tall, 0.02), p + Vector3(cos(a) * r, 0, sin(a) * r), BIRCH_DARK, Color(0, 0.9, 0, 0), true, -a + PI * 0.5)
	# Неравные подъёмистые сучья и редкие группы свисающих веток; общий перекос кроны — по seed.
	var limbs := 5 + int(_rand(rs, 5) * 3.0)
	var crown_yaw := TAU * _rand(rs, 6)
	var crown_side := Vector3(cos(crown_yaw), 0, sin(crown_yaw))
	for i in limbs:
		var level := (float(i) + 0.8 * _rand(rs, 1100 + i)) / limbs
		var y := crown * (0.36 + 0.54 * level)
		var k := mini(3, int(y / (crown / 4.0)))
		var from: Vector3 = pts[k].lerp(pts[k + 1], fposmod(y / (crown / 4.0), 1.0))
		var yaw := crown_yaw + i * 2.4 + (_rand(rs, 500 + i) - 0.5) * 1.6
		var dir := (_dir(yaw, deg_to_rad(24.0 + 34.0 * _rand(rs, 600 + i))) + crown_side * 0.16).normalized()
		var l := (2.8 - 1.5 * level) * (0.65 + 0.55 * _rand(rs, 700 + i))
		var to := from + dir * l
		seg("birch", from, to, 0.07, BIRCH_WHITE.darkened(0.25))
		var frost_load := 0.6 + 0.2 * dir.dot(crown_side) + 0.2 * _rand(rs, 1200 + i)
		if frost_load > 0.55:
			seg("frost", from.lerp(to, 0.2 + 0.4 * _rand(rs, 1300 + i)), to, 0.14 + 0.02 * frost_load)
		var twigs := 2 + int(_rand(rs, 1400 + i) * 3.0)
		for q in twigs:
			var at := from.lerp(to, 0.3 + 0.65 * (float(q) + 0.7 * _rand(rs, 1500 + i * 4 + q)) / twigs)
			var droop := (Vector3(dir.x, 0, dir.z).normalized() * 0.45 + Vector3(0, -1.0, 0) + Vector3(_rand(rs, 800 + i * 4 + q) - 0.5, 0, _rand(rs, 900 + i * 4 + q) - 0.5) * 0.5).normalized()
			var dl := 0.6 + 1.2 * _rand(rs, 1000 + i * 4 + q)
			var tip := at + Vector3(dir.x, 0.25, dir.z) * 0.35 + droop * dl
			seg("twig", at, tip, 0.035, Color.WHITE, true)
			if frost_load > 0.55 and _rand(rs, 1600 + i * 4 + q) > 0.2:
				seg("frost", at.lerp(tip, 0.35 * _rand(rs, 1700 + i * 4 + q)), tip, 0.10 + 0.02 * frost_load, Color.WHITE, true)

# --- тротуары ---

## Бордюры вдоль краёв проезжей части (гранитный камень 1 м, 15 см; где-то под снегом), наледь, проталины и каша на
## тротуарах, люки. Только вид: высота над тротуаром 9 см, коллизий нет (C9).
func street_dress() -> void:
	var roads := Layout.SURFACES.filter(func(spec): return spec[1] == "road")
	var rects := []
	for r in roads:
		rects.append(Rect2(r[2] - r[3] * 0.5, r[3]))
	for ri in roads.size():
		var rect: Rect2 = rects[ri]
		var along_x: bool = rect.size.x > rect.size.y
		for side: float in [-1.0, 1.0]:
			var line := (rect.get_center().y + side * rect.size.y * 0.5) if along_x else (rect.get_center().x + side * rect.size.x * 0.5)
			var from := rect.position.x if along_x else rect.position.y
			var to := rect.end.x if along_x else rect.end.y
			var n := int(to - from)
			for k in n:
				var a := from + k + 0.5
				var p := Vector2(a, line + side * 0.08) if along_x else Vector2(line + side * 0.08, a)
				var inside := false
				for oi in rects.size():
					if oi != ri and (rects[oi] as Rect2).grow(0.05).has_point(p):
						inside = true
						break
				if inside or not Layout.BOUNDS.has_point(p):
					continue
				var seed := int(a * 13.0 + line * 7.0)
				var tilt := (_rand(seed, 1) - 0.5) * 0.04
				var c: Color = CURB[int(_rand(seed, 2) * CURB.size()) % CURB.size()]
				var at := Vector3(p.x, 0.045, p.y)
				var size := Vector3(0.97, 0.13, 0.16) if along_x else Vector3(0.16, 0.13, 0.97)
				put("paint", Transform3D(Basis(Vector3.UP, tilt) * Basis.from_scale(size), at), c, Color(0, 0.92, 0, 0), true)
				if _rand(seed, 3) < 0.55:
					var cover := 0.4 + 0.6 * _rand(seed, 4)
					var snow_size := Vector3(0.97 * cover, 0.05, 0.2) if along_x else Vector3(0.2, 0.05, 0.97 * cover)
					put("snow", Transform3D(Basis.from_scale(snow_size), at + Vector3(0, 0.08, 0)), Color.WHITE, Color(), true)
	# Пятна на тротуарах: шаг 7 м, вид — по seed; у остановок и перекрёстков чаще наледь.
	for spec in Layout.SURFACES:
		if spec[1] != "sidewalk":
			continue
		var c: Vector2 = spec[2]
		var s: Vector2 = spec[3]
		var along_x: bool = s.x > s.y
		var length := s.x if along_x else s.y
		var n := int(length / 7.0)
		for k in n:
			var seed := int(c.x * 3.0 + c.y * 5.0) + k * 17
			if _rand(seed, 1) < 0.35:
				continue
			var u := -length * 0.5 + (k + 0.3 + 0.4 * _rand(seed, 2)) * 7.0
			var w := ((s.y if along_x else s.x) * 0.5 - 0.9) * (_rand(seed, 3) * 2.0 - 1.0)
			var p := Vector3(c.x + u, 0.031, c.y + w) if along_x else Vector3(c.x + w, 0.031, c.y + u)
			var kind := 0.0 if _rand(seed, 4) < 0.45 else (1.0 if _rand(seed, 5) < 0.5 else 2.0)
			var size := Vector3(1.2 + 2.2 * _rand(seed, 6), 1.0, 0.8 + 1.4 * _rand(seed, 7))
			put("patch", Transform3D(Basis(Vector3.UP, _rand(seed, 8) * PI) * Basis.from_scale(size), p), Color.WHITE, Color(kind, _rand(seed, 9), 0, 0), true)
	# Наледь у подъезда Бабки и у остановок — там всегда скользко.
	for p in [Vector3(-40, 0.032, 104.2), Vector3(-30, 0.032, 23.4), Vector3(65.8, 0.032, -62)]:
		put("patch", Transform3D(Basis.from_scale(Vector3(2.6, 1, 1.6)), p), Color.WHITE, Color(0.0, _rand(int(p.x), 3), 0, 0), true)
	_manholes()

## Люки: чугунная крышка с ободом и протаявший мокрый круг вокруг (тёплая канализация). Пар — у люков lighting.gd.
func _manholes() -> void:
	var points := [Vector3(-8, 0, 22.0), Vector3(30, 0, 41.8), Vector3(-70, 0, 41.2), Vector3(78.5, 0, -20), Vector3(61, 0, -30),
		Vector3(-68.5, 0, -60), Vector3(-51.5, 0, 4.0), Vector3(20, 0, -108.5), Vector3(-30, 0, -91.5), Vector3(-10, 0, 90),
		Vector3(-60, 0, 96), Vector3(4, 0, 60), Vector3(-25, 0, 73), Vector3(84, 0, 36)]
	for i in points.size():
		var p: Vector3 = points[i]
		put("patch", Transform3D(Basis.from_scale(Vector3(1.6, 1, 1.6)), p + Vector3(0, 0.033, 0)), Color.WHITE, Color(1.0, _rand(i, 4), 0, 0), true)
		put("rod", Transform3D(Basis.from_scale(Vector3(0.74, 0.03, 0.74)), p + Vector3(0, 0.035, 0)), Color(0.10, 0.10, 0.10), Color(3.0, 0.5, 0, 0), true)
		put("rod", Transform3D(Basis.from_scale(Vector3(0.62, 0.035, 0.62)), p + Vector3(0, 0.04, 0)), Color(0.07, 0.07, 0.075), Color(0, 0.45, 0, 0), true)
		for r in 3:   # рёбра крышки
			box(Vector3(0.5, 0.012, 0.025), p + Vector3(0, 0.06, 0), Color(0.12, 0.12, 0.12), Color(0, 0.4, 0, 0), true, r * PI / 3.0)

# --- провода и столбы ---

## Снег на проводе: «гирлянда» — пушистая белая муфта поверх провода на части пролёта (ART-06, Н8 — куржак).
func wire_snow(from: Vector3, to: Vector3, seed: int) -> void:
	if _rand(seed, 1) < 0.35:
		return
	var a := 0.1 + 0.3 * _rand(seed, 2)
	var b := minf(1.0, a + 0.3 + 0.5 * _rand(seed, 3))
	var p := from.lerp(to, a) + Vector3(0, 0.012, 0)
	var q := from.lerp(to, b) + Vector3(0, 0.012, 0)
	put("wire_snow", segment(p, q, 0.055 + 0.03 * _rand(seed, 4)), Color.WHITE, Color(), true)

## Проволочная скрутка и изолятор у точки крепления провода.
func wire_twist(at: Vector3, toward: Vector3, seed: int) -> void:
	var d := (toward - at).normalized()
	seg("rod", at, at + d * 0.28, 0.035, Color(0.12, 0.12, 0.12), true)
	seg("rod", at + d * 0.06, at + d * 0.16, 0.06, Color(0.22, 0.22, 0.21), true, Color(0, 0.5, 0, 0))
	seg("rod", at + Vector3(0, -0.02, 0), at + Vector3(0, -0.16, 0) + d * 0.05, 0.02, Color(0.15, 0.15, 0.15), true)
	if _rand(seed, 5) < 0.5:
		seg("rod", at - Vector3(0, 0.05, 0), at - Vector3(0, 0.15, 0), 0.07, Color(0.72, 0.74, 0.70), true, Color(0, 0.3, 0, 0))   # фарфоровый изолятор

## Объявления в несколько слоёв, рваные; на части столбов — серая распредкоробка и наклейки (ART-04, черта 13).
## origin — центр коллизии столба в мире, size — её размер.
func pole_dress(origin: Vector3, size: Vector3, seed: int) -> void:
	var base := origin - Vector3(0, size.y * 0.5, 0)
	var r := maxf(size.x, size.z) * 0.5 + 0.012
	var notes := 2 + int(_rand(seed, 1) * 6.0)
	var face := TAU * _rand(seed, 2)
	for i in notes:
		var a := face + (_rand(seed, 10 + i) - 0.5) * 1.6
		var y := 1.25 + 0.9 * _rand(seed, 20 + i)
		var w := 0.12 + 0.12 * _rand(seed, 30 + i)
		var h := 0.15 + 0.16 * _rand(seed, 40 + i)
		if _rand(seed, 50 + i) < 0.3:
			h *= 0.4   # оборванный край
		var c: Color = PAPER[int(_rand(seed, 60 + i) * PAPER.size()) % PAPER.size()]
		var at := base + Vector3(cos(a) * (r + i * 0.001), y, sin(a) * (r + i * 0.001))
		box(Vector3(w, h, 0.004), at, c.darkened(0.15 * _rand(seed, 70 + i)), Color(0, 0.95, 0, 0), true, -a + PI * 0.5)
		if h > 0.15 and i % 2 == 0:
			for line in 3:
				box(Vector3(w * 0.7, 0.012, 0.002), at + Vector3(cos(a), 0, sin(a)) * 0.004 + Vector3(0, h * 0.28 - line * h * 0.22, 0), Color(0.22, 0.22, 0.25), Color(0, 0.9, 0, 0), true, -a + PI * 0.5)
	if _rand(seed, 80) < 0.45:
		var a := face + PI
		box(Vector3(0.3, 0.42, 0.16), base + Vector3(cos(a) * (r + 0.08), 2.4, sin(a) * (r + 0.08)), Color(0.50, 0.52, 0.53), Color(3.0, 0.5, 0, 0), true, -a + PI * 0.5)
		seg("rod", base + Vector3(cos(a) * (r + 0.05), 2.18, sin(a) * (r + 0.05)), base + Vector3(cos(a) * (r + 0.05), 0.2, sin(a) * (r + 0.05)), 0.04, Color(0.12, 0.12, 0.12), true)
		put("snow", Transform3D(Basis(Vector3.UP, -a + PI * 0.5) * Basis.from_scale(Vector3(0.3, 0.05, 0.16)), base + Vector3(cos(a) * (r + 0.08), 2.64, sin(a) * (r + 0.08))), Color.WHITE, Color(), true)
	if _rand(seed, 81) < 0.35:
		# Кольца липкой ленты и наклейки «ремонт / вскрытие замков» — яркие полоски.
		for k in 2:
			var c: Color = [Color(0.85, 0.75, 0.12), Color(0.15, 0.45, 0.80), Color(0.85, 0.22, 0.15)][(seed + k) % 3]
			var a := face + 0.9 + k * 0.5
			box(Vector3(0.09, 0.05, 0.004), base + Vector3(cos(a) * r, 1.6 + k * 0.12, sin(a) * r), c, Color(0, 0.6, 0, 0), true, -a + PI * 0.5)

# --- сборщик мелочи в локальных координатах узла (киоск, павильон, гаражи, площадка, контейнеры, щит) ---
# Набор — словарь «вид» → [преобразования, цвета, custom]; kit_emit строит по MultiMesh на вид.
# Виды: box, cyl, cone — материал detail (цвет экземпляра, INSTANCE_CUSTOM: r узор, g шероховатость, b свечение);
# snow — коробка снега, lump — купол сугроба, ice — сосулька.

const KIT_KINDS := {
	"box": ["box", "detail"], "cyl": ["cyl", "detail"], "cone": ["cone", "detail"], "sph": ["sph", "detail"],
	"snow": ["box", "snow"], "lump": ["dome", "snow"], "ice": ["cone", "ice"],
}
static var _kit_meshes := {}

static func kit() -> Dictionary:
	return {}

static func kit_put(k: Dictionary, kind: String, xf: Transform3D, color := Color.WHITE, custom := Color(0, 0, 0, 0)) -> void:
	if not k.has(kind):
		k[kind] = [[], [], []]
	k[kind][0].append(xf)
	k[kind][1].append(color)
	k[kind][2].append(custom)

static func kit_box(k: Dictionary, size: Vector3, at: Vector3, color: Color, custom := Color(0, 0, 0, 0), rot := Vector3.ZERO) -> void:
	kit_put(k, "box", Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), at), color, custom)

static func kit_seg(k: Dictionary, from: Vector3, to: Vector3, diameter: float, color: Color, custom := Color(0, 0, 0, 0), kind := "cyl") -> void:
	kit_put(k, kind, segment(from, to, diameter), color, custom)

static func kit_snow(k: Dictionary, size: Vector3, at: Vector3, rot := Vector3.ZERO) -> void:
	kit_put(k, "snow", Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), at))

## Купол снега: size — ширина, высота, глубина; основание — at.
static func kit_lump(k: Dictionary, size: Vector3, at: Vector3, yaw := 0.0) -> void:
	kit_put(k, "lump", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size.x, size.y * 2.0, size.z)), at))

## Ряд сосулек под кромкой от a до b (остриём вниз), длина до max_len.
static func kit_icicles(k: Dictionary, a: Vector3, b: Vector3, max_len: float, seed: int, step := 0.18) -> void:
	var n := int(a.distance_to(b) / step)
	for i in n:
		var r := _rand(seed, i * 3)
		if r < 0.3:
			continue
		var l := max_len * (0.15 + 0.85 * _rand(seed, i * 3 + 1) * r)
		var p := a.lerp(b, (i + 0.5) / n)
		kit_put(k, "ice", Transform3D(Basis.from_scale(Vector3(0.035 + 0.03 * r, l, 0.035 + 0.03 * r)), p - Vector3(0, l * 0.5, 0)))

## Построить набор под parent. range_end > 0 — мелочь гаснет дальше этого расстояния (LOD).
static func kit_emit(k: Dictionary, parent: Node3D, prefix: String, range_end := 0.0) -> void:
	for kind in k:
		var spec: Array = KIT_KINDS[kind]
		var data: Array = k[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = spec[1] == "detail"
		mm.use_custom_data = spec[1] == "detail"
		mm.mesh = _kit_mesh(spec[0])
		mm.instance_count = data[0].size()
		for i in data[0].size():
			mm.set_instance_transform(i, data[0][i])
			if mm.use_colors:
				mm.set_instance_color(i, data[1][i])
				mm.set_instance_custom_data(i, data[2][i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "%s_%s" % [prefix, kind]
		inst.multimesh = mm
		inst.material_override = material(spec[1])
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			inst.visibility_range_end = range_end
			inst.visibility_range_end_margin = 4.0
		parent.add_child(inst)
	k.clear()

static func _kit_mesh(kind: String) -> Mesh:
	if _kit_meshes.has(kind):
		return _kit_meshes[kind]
	var mesh: Mesh
	match kind:
		"box":
			mesh = BoxMesh.new()
		"cyl", "cone":
			var c := CylinderMesh.new()
			c.height = 1.0
			c.top_radius = 0.5
			c.bottom_radius = 0.5 if kind == "cyl" else 0.0
			c.radial_segments = 10 if kind == "cyl" else 5
			c.rings = 1
			mesh = c
		"sph":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 10
			s.rings = 5
			mesh = s
		"dome":
			mesh = dome_mesh(2)
	_kit_meshes[kind] = mesh
	return mesh

static func clear_cache() -> void:
	_kit_meshes.clear()
	_domes.clear()

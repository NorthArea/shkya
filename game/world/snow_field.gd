extends RefCounted
## SnowField (DRIVE-02, контракт C10; сделано частью E CITY-02): высота снега над землёй по всем валам и сугробам
## Layout — коробкам kind snow/snow_bank из Layout.all_solids() (SOLIDS + snow_banks()). Одна форма для вида и
## физики: сетку валов строит EnvDress.bank_mesh по profile() (level_geometry._lumpy_bank), колёса «Лады» берут
## height_at() — поверхность совпадает в вершинах сетки, между ними — линейная интерполяция гладкого профиля.
##
## Профиль коробки (длина L, ширина W, высота H): скруглённый гребень H·(0,55…1,3) с буграми, комьями ±0,15 м
## и рваным верхом (CITY-02 F), шумом по seed
## индекса коробки в all_solids() (тот же seed, что у _build_solid); со стороны дороги склон круче (отвал грейдера),
## со двора — ступени лопаты по 12–15 см; к торцам сходит на нет; за кромкой коробки + MARGIN — 0.
## Только чтение и математика: без узлов, без случайностей.

const Layout = preload("res://game/world/layout.gd")

const CLOD := 0.3            # м: размах комьев (±CLOD/2), шаг ~1,3 м вдоль и ~0,9 м поперёк
const RAG := 0.16            # м: рваный гребень (мелкие зубцы по верху)
const MARGIN := 0.6          # м за кромкой коробки, где снег сходит на нет
const STEP_U := 0.2          # шаг сетки вдоль вала, м
const STEP_V := 0.15         # шаг поперёк
const KINDS := ["snow", "snow_bank"]

const DEPTH_MAX := 0.3       # м: глубина рыхлого слоя под колесом (≈ радиус колеса), DRIVE-02
const NORMAL_EPS := 0.1      # м: шаг разностей для нормали и уклона
const CELL := 8.0            # м: ячейка сетки поиска коробок

## [центр, размер, вдоль x, seed, сторона дороги, прямоугольник с MARGIN] — собирается при первом обращении.
static var _boxes := []
static var _cells := {}      # Vector2i → индексы _boxes, чьи прямоугольники задевают ячейку CELL × CELL

static func boxes() -> Array:
	if _boxes.is_empty():
		var solids := Layout.all_solids()
		for i in solids.size():
			var spec: Array = solids[i]
			if not (spec[1] in KINDS):
				continue
			var xz: Vector2 = spec[2]
			var size: Vector3 = spec[3]
			var rect := Rect2(xz - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)).grow(MARGIN)
			var k := _boxes.size()
			_boxes.append([xz, size, size.x >= size.z, i, road_side(xz, size), rect])
			for gx in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
				for gz in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
					var key := Vector2i(gx, gz)
					if not _cells.has(key):
						_cells[key] = []
					_cells[key].append(k)
	return _boxes

## Сбросить кэш (если Layout поменялся в процессе — только для тестов).
static func rebuild() -> void:
	_boxes.clear()
	_cells.clear()
	boxes()

## Высота снега над землёй в точке мира (0 — снега нет). Пересечения коробок — максимум.
static func height_at(x: float, z: float) -> float:
	var all := boxes()
	var h := 0.0
	var p := Vector2(x, z)
	for k in _cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), []):
		var b: Array = all[k]
		if (b[5] as Rect2).has_point(p):
			h = maxf(h, box_height(b, x, z))
	return h

## Глубина рыхлого слоя под колесом, м: min(height_at, DEPTH_MAX). Сопротивление «Лады» — SNOW_DRAG · depth.
static func depth_at(x: float, z: float) -> float:
	return minf(height_at(x, z), DEPTH_MAX)

## Нормаль поверхности снега (на земле — вверх).
static func normal_at(x: float, z: float) -> Vector3:
	var e := NORMAL_EPS
	var dx := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var dz := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

## Уклон снега по направлению dir (в плане): подъём на метр пути, > 0 — в гору.
static func slope_along(x: float, z: float, dir: Vector2) -> float:
	if dir.length_squared() < 0.000001:
		return 0.0
	var d := dir.normalized() * NORMAL_EPS
	return (height_at(x + d.x, z + d.y) - height_at(x - d.x, z - d.y)) / (2.0 * NORMAL_EPS)

## Высота над одной коробкой b (элемент boxes()). Оси сетки: u — вдоль (у коробки вдоль z — u = −dz, как поворот
## сетки на +90° в _lumpy_bank), v — поперёк (+v — к +z или +x мира).
static func box_height(b: Array, x: float, z: float) -> float:
	var c: Vector2 = b[0]
	var size: Vector3 = b[1]
	if b[2]:
		return surface(x - c.x, z - c.y, size.x, size.z, size.y, b[3], b[4])
	return surface(-(z - c.y), x - c.x, size.z, size.x, size.y, b[3], b[4])

## Сетка вала: [полудлина с MARGIN, полуширина с MARGIN, узлов вдоль, узлов поперёк].
static func grid(length: float, width: float) -> Array:
	var hl := length * 0.5 + MARGIN
	var hw := width * 0.5 + MARGIN
	return [hl, hw, maxi(6, int(ceil(hl * 2.0 / STEP_U))) + 1, maxi(12, int(ceil(hw * 2.0 / STEP_V))) + 1]

## Поверхность ровно как у сетки EnvDress.bank_mesh: профиль в узлах, внутри ячейки — те же два треугольника
## ((i,j),(i+1,j),(i,j+1)) и ((i+1,j),(i+1,j+1),(i,j+1)). Вид и колёса не расходятся (C10: ≤ 5 см — здесь 0).
static func surface(u: float, v: float, length: float, width: float, height: float, seed: int, toward: float) -> float:
	var g := grid(length, width)
	var hl: float = g[0]
	var hw: float = g[1]
	if absf(u) >= hl or absf(v) >= hw:
		return 0.0
	var du: float = hl * 2.0 / (int(g[2]) - 1)
	var dv: float = hw * 2.0 / (int(g[3]) - 1)
	var fi := (u + hl) / du
	var fj := (v + hw) / dv
	var i := clampi(floori(fi), 0, int(g[2]) - 2)
	var j := clampi(floori(fj), 0, int(g[3]) - 2)
	var a := fi - i
	var b := fj - j
	var u0 := -hl + du * i
	var v0 := -hw + dv * j
	var h10 := profile(u0 + du, v0, length, width, height, seed, toward)
	var h01 := profile(u0, v0 + dv, length, width, height, seed, toward)
	if a + b <= 1.0:
		var h00 := profile(u0, v0, length, width, height, seed, toward)
		return h00 + (h10 - h00) * a + (h01 - h00) * b
	var h11 := profile(u0 + du, v0 + dv, length, width, height, seed, toward)
	return h11 + (h01 - h11) * (1.0 - a) + (h10 - h11) * (1.0 - b)

## Профиль в осях вала: u вдоль (−L/2…L/2), v поперёк (−W/2…W/2), оба с MARGIN; toward — знак v стороны дороги.
static func profile(u: float, v: float, length: float, width: float, height: float, seed: int, toward: float) -> float:
	var hl := length * 0.5 + MARGIN
	var hw := width * 0.5 + MARGIN
	if absf(u) >= hl or absf(v) >= hw:
		return 0.0
	var sx := float(seed % 97) * 3.17
	var wob := 1.0 - noise2(u * 0.9 + sx, 2.0) * 0.22   # рваная кромка — только внутрь полосы MARGIN
	var t := v / (hw * wob)
	var at := absf(t)
	if at >= 1.0:
		return 0.0
	var road := t * toward
	var p := 2.4 + 3.2 * clampf(road * 1.6, 0.0, 1.0)   # к дороге — плоский верх и крутой срез
	var prof := pow(1.0 - pow(at, p), 0.8) * smoothstep(0.0, 0.18, 1.0 - at)   # подошва без излома
	var crest := height * (0.55 + 0.4 * fbm(u * 0.32 + sx, 1.7))
	var lumps := 0.0
	var n := maxi(1, int(length / 1.6))
	for k in n:
		var lu := (rand(seed * 7, k * 3) - 0.5) * length
		var lr := 0.35 + 0.5 * rand(seed * 7, k * 3 + 1)
		var lh := (0.1 + 0.2 * rand(seed * 7, k * 3 + 2)) * height
		var lv := (rand(seed * 11, k) - 0.5) * hw
		var du := (u - lu) / lr
		var dv := (v - lv) / (hw * 0.8)
		var q := du * du + dv * dv
		if q < 9.0:
			lumps += lh * exp(-q)
	var y := (crest + lumps) * prof + (noise2(u * 1.3 + sx, t * 1.6 + 11.0) - 0.5) * 0.14 * height * prof
	# Комья ±0,15 м с шагом 1–2 м и рваный гребень (сверка CITY-02 F: валы читались гладкими «колбасами»).
	y += (noise2(u * 0.75 + sx, v * 1.1 + 4.0) - 0.5) * CLOD * smoothstep(0.0, 0.35, prof)
	y += (absf(noise2(u * 2.1 + sx * 1.3, 9.0) - 0.5) - 0.25) * RAG * smoothstep(0.5, 0.9, prof)
	if toward != 0.0 and road < -0.2:
		# Ступени лопаты со двора, сглаженные (не рвут подвеску).
		var step := 0.12 + 0.03 * rand(seed, 5)
		var terr := floorf(y / step) * step + step * smoothstep(0.0, 1.0, fposmod(y, step) / step)
		y = lerpf(y, terr, 0.4 * clampf((-road - 0.2) * 2.0, 0.0, 1.0))
	var end := smoothstep(0.0, minf(1.2, hl * 0.45), hl - absf(u))
	return maxf(0.0, y * end)

## Знак стороны ближайшей проезжей части, идущей вдоль коробки (+1/−1 по короткой оси), 0 — дороги рядом нет.
static func road_side(xz: Vector2, size: Vector3) -> float:
	var long_x := size.x >= size.z
	for spec in Layout.SURFACES:
		var road_size: Vector2 = spec[3]
		if spec[1] != "road" or (road_size.x > road_size.y) != long_x:
			continue
		var c: Vector2 = spec[2]
		if Rect2(c - road_size * 0.5, road_size).grow(3.2).has_point(xz):
			return signf(c.y - xz.y) if long_x else signf(c.x - xz.x)
	return 0.0

# --- детерминированный шум (тот же, что у сетки) ---

static func rand(seed: int, k: int) -> float:
	return fposmod(sin(float(seed + k) * 12.9898) * 43758.5453, 1.0)

static func _hash2(x: float, y: float) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7) * 43758.5453, 1.0)

static func noise2(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_hash2(ix, iy), _hash2(ix + 1.0, iy), fx), lerpf(_hash2(ix, iy + 1.0), _hash2(ix + 1.0, iy + 1.0), fx), fy)

static func fbm(x: float, y: float) -> float:
	return noise2(x, y) * 0.55 + noise2(x * 2.3 + 5.1, y * 2.3 - 3.7) * 0.3 + noise2(x * 5.7 - 1.3, y * 5.7 + 8.2) * 0.15

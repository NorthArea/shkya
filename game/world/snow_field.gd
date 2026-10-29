class_name SnowField
extends RefCounted
## C10 (DRIVE-02): одна форма сугробов для вида и для физики «Лады». Высота снега над землёй (y = 0) по всем валам и
## сугробам Layout: SOLIDS kind snow и snow_bank (decor_solids из snow_banks()), номер коробки — её индекс в
## Layout.all_solids() (как seed у _lumpy_bank в level_geometry.gd).
##
## Профиль одной коробки (центр c, размер sx × sy × sz; длинная ось — большая из sx, sz):
##   u — координата вдоль длинной оси от центра, d — поперёк; hl, hw — половины длины и ширины;
##   reach = hw + MARGIN (снег выходит за коробку на MARGIN = 0,6 м);
##   core = max(hl − hw, 0) — полуотрезок оси гребня, вокруг него план — «стадион» (скруглённые торцы);
##   r = sqrt(d² + max(|u| − core, 0)²) — расстояние от оси гребня;
##   t = 1 − r / reach; t ≤ 0 → 0 (за коробкой + MARGIN снега нет);
##   h = sy · smoothstep(0, 1, t) · (1 + bumps(u)),
##   bumps(u) = NOISE_AMP · (2·v(u / NOISE_STEP) − 1) + NOISE_AMP2 · (2·v(u / NOISE_STEP2 + 17) − 1),
##   v — гладкий шум значений по узлам seed·31 + i (хэш как у _lumpy_bank), между узлами — smoothstep.
## По всем коробкам — максимум. Высота ≤ sy · (1 + NOISE_AMP + NOISE_AMP2) = 0,9 · 1,26 ≈ 1,13 м < ROOF_HEIGHT (1,5).
## Часть E строит меш валов по height_at — колёса «Лады» стоят на видимой поверхности.

const Layout = preload("res://game/world/layout.gd")

const MARGIN := 0.6          # м: снег выходит за коллизионную коробку
const NOISE_AMP := 0.18      # доля высоты: крупные комки вдоль вала
const NOISE_STEP := 2.2      # м: шаг крупных комков (как у _lumpy_bank)
const NOISE_AMP2 := 0.08     # доля высоты: мелкие глыбы
const NOISE_STEP2 := 0.9     # м
const DEPTH_MAX := 0.3       # м: глубина рыхлого слоя под колесом (≈ радиус колеса)
const NORMAL_EPS := 0.1      # м: шаг разностей для нормали и уклона
const CELL := 8.0            # м: ячейка сетки поиска коробок

## [cx, cz, hl, hw, sy, seed, long_x] на коробку.
static var _boxes: Array = []
static var _grid: Dictionary = {}   # Vector2i → Array[int]
static var _built := false

## Высота снега над землёй в точке (x, z), м; 0 — снега нет.
static func height_at(x: float, z: float) -> float:
	_build()
	var cell: Array = _grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])
	var best := 0.0
	for i in cell:
		best = maxf(best, _box_height(_boxes[i], x, z))
	return best

## Нормаль поверхности снега (на голой земле — Vector3.UP).
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

## Глубина рыхлого слоя под колесом в точке, м: min(height_at, DEPTH_MAX). Сопротивление «Лады» — SNOW_DRAG · depth.
static func depth_at(x: float, z: float) -> float:
	return minf(height_at(x, z), DEPTH_MAX)

## Коробки сугробов в плане: [центр x/z, размер x/z, высота sy, seed] — для меша части E и проверок.
static func boxes() -> Array:
	_build()
	var out := []
	for b in _boxes:
		var size := Vector2(b[2] * 2.0, b[3] * 2.0) if b[6] else Vector2(b[3] * 2.0, b[2] * 2.0)
		out.append([Vector2(b[0], b[1]), size, b[4], b[5]])
	return out

## Сбросить кэш (если Layout поменялся в процессе — только для тестов).
static func rebuild() -> void:
	_built = false
	_build()

static func _build() -> void:
	if _built:
		return
	_built = true
	_boxes.clear()
	_grid.clear()
	var solids: Array = Layout.all_solids()
	for index in solids.size():
		var spec: Array = solids[index]
		if spec[1] != "snow" and spec[1] != "snow_bank":
			continue
		var c: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		var long_x := size.x >= size.z
		var hl := (size.x if long_x else size.z) * 0.5
		var hw := (size.z if long_x else size.x) * 0.5
		var box := [c.x, c.y, hl, hw, size.y, index, long_x]
		var k := _boxes.size()
		_boxes.append(box)
		var reach := Vector2(hl, hw) + Vector2.ONE * MARGIN
		var ext := Vector2(reach.x, reach.y) if long_x else Vector2(reach.y, reach.x)
		for gx in range(floori((c.x - ext.x) / CELL), floori((c.x + ext.x) / CELL) + 1):
			for gz in range(floori((c.y - ext.y) / CELL), floori((c.y + ext.y) / CELL) + 1):
				var key := Vector2i(gx, gz)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(k)

static func _box_height(b: Array, x: float, z: float) -> float:
	var long_x: bool = b[6]
	var u: float = (x - b[0]) if long_x else (z - b[1])
	var d: float = (z - b[1]) if long_x else (x - b[0])
	var hl: float = b[2]
	var hw: float = b[3]
	var reach := hw + MARGIN
	var core := maxf(hl - hw, 0.0)
	var along := maxf(absf(u) - core, 0.0)
	var r2 := d * d + along * along
	if r2 >= reach * reach:
		return 0.0
	var t := 1.0 - sqrt(r2) / reach
	var s := t * t * (3.0 - 2.0 * t)
	var seed: int = b[5]
	var w := u + hl + MARGIN   # ≥ 0 по всей длине профиля
	var bumps := NOISE_AMP * (2.0 * _value_noise(seed, w / NOISE_STEP) - 1.0) \
		+ NOISE_AMP2 * (2.0 * _value_noise(seed + 7919, w / NOISE_STEP2) - 1.0)
	return float(b[4]) * s * (1.0 + bumps)

## Гладкий шум значений 0…1 по узлам целых p: значения — хэш как у _lumpy_bank, между узлами — smoothstep.
static func _value_noise(seed: int, p: float) -> float:
	var i := floori(p)
	var f := p - float(i)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash(seed, i), _hash(seed, i + 1), f)

static func _hash(seed: int, i: int) -> float:
	return fposmod(sin(float(seed * 31 + i) * 12.9898) * 43758.5453, 1.0)

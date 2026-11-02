extends Node3D
## CITY-03: один обычный белый пакет «ВСЕ ПО ПЛАНУ / ПРОДУКТЫ У ДОМА» у появления Илюши.
##
## Своя простая физика, без тел и коллизий (C2 не трогается, на игру не влияет — только облик):
## - ветер: направление Lighting.WIND, качается с периодом HEADING_PERIOD; сила и поворот — от порывов
##   LightingAndWeather.gust (те же, что у снегопада); турбулентность — гладкие синусы по месту и времени;
## - у стен домов (коробки Layout выше WALL_HEIGHT) ветер, бьющий в стену, уходит вверх и вдоль неё — вихрь;
##   с подветренной стороны — обратный завиток;
## - пакет тянет к ветру (DRAG), тянет вниз (SINK × вес) и поднимает сильным ветром (LIFT); на снегу и крышах
##   низких коробок он ложится (rest) и взлетает от порыва сильнее своего порога; цепляется за ветки деревьев, столбы
##   и заборы (snag) на SNAG_TIME, а также за одежду Илюши и жителей; трепещет и срывается порывом;
## - «Лада», транспорт кольца и Илюша пешком отбрасывают пакет (подброс по скорости, кувырок), за быстрой машиной
##   пакет затягивает следом;
## - местный завиток удерживает пакет низко во дворе; унесённый контактом возвращается к SOURCES вне кадра;
## Облик — сетка двух стенок со своим шейдером (shaders/bag.gdshader): раздув, трепет, вырез ручек; надпись —
## один раз отрисованная в SubViewport маска. Теней нет (C9: мелочь). Звук — шуршание у камеры (bag_rustle_loop.wav,
## tools/generate_audio.py). Всё детерминировано: SEED.

const Layout = preload("res://game/world/layout.gd")
const SnowField = preload("res://game/world/snow_field.gd")
const Lighting = preload("res://game/world/lighting.gd")
const BagShader = preload("res://game/world/shaders/bag.gdshader")
const RUSTLE := preload("res://assets/audio/bag_rustle_loop.wav")
const FONT := preload("res://assets/fonts/Pangolin-Regular.ttf")

const GROUP := &"wind_bags"
const SEED := 3003

## Единственный активный вид — plan_white; меню использует ту же сетку, материал и печать.
const BAGS: Array = Layout.WIND_BAGS
const SOURCES: Array[Vector2] = Layout.WIND_BAG_SOURCES

const BAG_SIZE := Vector2(0.44, 0.64)   # м, ширина и высота «майки» с ручками
const BAG_SCALE := 1.25                 # крупнее настоящего: читается с игровой камеры
const PLAN_WHITE_START_HEIGHT := 0.85   # м над снегом: низкий пролёт во дворе с начала игры
const PLAN_WHITE_CEILING := 1.7         # м над снегом: мягкое снижение, контакт может подбросить выше
const PLAN_WHITE_WIND_SHARE := 0.55     # доля общего ветра внутри защищённого двора
const PLAN_WHITE_RETURN := 0.75         # 1/с: обратная струя местного завитка
const PLAN_WHITE_SWIRL := 0.55          # 1/с: движение поперёк струи
const PLAN_WHITE_WIND_MAX := 5.0        # м/с: возврат издалека не создаёт ураган
const PLAN_WHITE_UPDRAFT_MAX := 0.6     # м/с: поток у стены не уносит пакет на крышу
const GRID := Vector2i(8, 12)

# --- ветер ---
const WIND_BASE := 1.7          # м/с в затишье
const GUST_GAIN := 2.0          # в порыв ветер сильнее в (1 + GUST_GAIN) раз
const HEADING_SWING := 1.1      # рад, медленное качание направления — пакеты гуляют по арене, а не копятся в углу
const HEADING_PERIOD := 83.0    # с
const TURB := 0.9               # м/с, горизонтальная турбулентность
const TURB_UP := 0.7            # м/с, вертикальная
const WALL_HEIGHT := 5.0        # м: коробка выше — стена дома (вихрь, пакет отталкивается); ниже — крыша, на неё ложатся
const VORTEX_RANGE := 4.5       # м от стены
const UPDRAFT := 1.1            # доля ветра в стену, уходящая вверх
const SWIRL := 0.8              # доля, уходящая вдоль стены

# --- полёт ---
const DRAG := 2.0               # 1/с, горизонталь
const DRAG_UP := 1.6            # 1/с, вертикаль
const SINK := 1.5               # м/с², «тяжесть» пакета (× вес вида)
const LIFT := 0.9               # м/с² на 1 м/с ветра сверх LIFT_MIN
const LIFT_MIN := 1.6           # м/с
const CEILING := 7.5            # м: выше пакет мягко прижимает вниз
const GROUND_LIFT := 0.035      # м над землёй, где пакет лежит

# --- лежит / цепляется ---
const LIFTOFF_GUST := Vector2(0.45, 0.8)   # порог порыва для взлёта, у каждого пакета свой
const MAX_LIFTOFF_GUST := 0.9              # порыв 0…1: даже тяжёлый пустой пакет может взлететь
const REST_MIN := Vector2(2.0, 6.0)         # с лежит не меньше
const REST_RECYCLE := 40.0                  # с: залежался вне кадра — к новому источнику
const SNAG_CHANCE := 0.55                   # доля «цепких» пар пакет × точка
const SNAG_TIME := Vector2(3.5, 11.0)       # с висит
const SNAG_MAX := 18.0                      # с: дольше не висит даже в затишье
const SNAG_RELEASE_GUST := 0.35             # после SNAG_TIME срывает порыв не слабее этого
const SNAG_COOLDOWN := 5.0                  # с: за ту же точку сразу снова не цепляется
const PERSON_SNAG_CHANCE := 0.55
const PERSON_SNAG_TIME := Vector2(1.2, 3.5)
const PERSON_SNAG_MAX := 6.0
const PERSON_SNAG_GUST := 0.55
const PERSON_RADIUS := 0.65

# --- реакции ---
const CAR_PAD := 0.5            # м к габариту машины
const CAR_MIN_SPEED := 1.5      # м/с: медленнее — не отбрасывает
const HIT_CARRY := 1.1          # доля скорости машины, которую получает пакет
const HIT_UP := Vector2(2.4, 0.16)       # м/с подброса: база + на 1 м/с скорости машины
const HIT_SIDE := Vector2(1.4, 0.07)     # в сторону от оси машины
const HIT_COOLDOWN := 0.7       # с
const WAKE_RANGE := 7.0         # м за быстрой машиной — затягивает следом
const WAKE_SPEED := 6.0         # м/с
const KICK_MIN_SPEED := 0.35    # м/с: стоящий Илюша пакет не пинает
const KICK_RADIUS := 0.9        # м от Илюши
const KICK_UP := 2.2            # м/с
const LADA_HALF := Vector2(Layout.LADA_SIZE.x, Layout.LADA_SIZE.z) * 0.5

# --- границы и возврат ---
const OUT_RESPAWN := 1.5        # с вне BOUNDS (или выше OUT_HEIGHT) — возврат
const OUT_HEIGHT := 14.0
const HIDDEN_DISTANCE := 38.0   # м: дальше — пакет не виден, даже если в кадре

# --- звук ---
const RUSTLE_RANGE := 8.0       # м от камеры
const RUSTLE_DB := -9.0         # RMS файла −24 → −33 дБ у источника: ниже сигналов квеста (−23…−25), около фона двора

var bags: Array = []
var hits := {&"car": 0, &"player": 0, &"traffic": 0}
var snags := 0
var releases := 0
var liftoffs := 0
var respawns := 0
var clock := 0.0
var rustle: AudioStreamPlayer3D

var _rng := RandomNumberGenerator.new()
var _world: Node
var _lighting: Node
var _player: Node3D
var _lada: Node3D
var _people: Array[Node3D] = []
var _breakables: Node
var _walls := []            # [Rect2 XZ, высота]
var _wall_cells := {}       # Vector2i → индексы _walls
var _snag_points := []      # [Vector3 (x, низ, z), радиус, верх]
var _snag_cells := {}
var _prev := {}             # Node3D → прошлая позиция транспорта кольца
var _vel := {}
var _materials := {}

const CELL := 10.0

func _init() -> void:
	name = "WindBags"

func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = SEED
	_world = _find_world()
	if _world:
		_player = _world.get_node_or_null("Ilyusha")
		_lada = _world.get_node_or_null("Car")
		_lighting = _world.get_node_or_null("LightingAndWeather")
	_collect_walls()
	_collect_snags()
	_collect_people()
	var mesh := bag_mesh()
	for i in BAGS.size():
		var spec: Array = BAGS[i]
		var bag := Bag.new()
		bag.name = "Bag%d_%s" % [i, spec[0]]
		bag.kind = spec[0]
		bag.index = i
		bag.weight = 1.6 if bag.kind == &"black" else (0.85 if bag.kind in [&"white", &"plan_white"] else 1.0)
		bag.liftoff_gust = _rng.randf_range(LIFTOFF_GUST.x, LIFTOFF_GUST.y)
		add_child(bag)
		bag.look = MeshInstance3D.new()
		bag.look.name = "Look"
		bag.look.mesh = mesh
		bag.look.material_override = _material(bag.kind)
		bag.look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bag.look.scale = Vector3.ONE * BAG_SCALE * (1.15 if bag.kind == &"black" else 1.0)
		bag.look.set_instance_shader_parameter("phase", float(i) * 1.9)
		bag.add_child(bag.look)
		var p: Vector2 = spec[1]
		_put_down(bag, Vector3(p.x, 0.0, p.y), _rng.randf_range(0.0, TAU))
		bag.rest_left = _rng.randf_range(0.0, REST_MIN.y)
		bags.append(bag)
		if bag.kind == &"plan_white":
			bag.position.y += PLAN_WHITE_START_HEIGHT
			_lift_off(bag, wind_mean(), 1.0)
	rustle = AudioStreamPlayer3D.new()
	rustle.name = "Rustle"
	rustle.stream = RUSTLE
	rustle.volume_db = RUSTLE_DB
	rustle.unit_size = 2.5
	rustle.max_distance = RUSTLE_RANGE + 4.0
	add_child(rustle)

func _find_world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:
			return node
		node = node.get_parent()
	return null

func _collect_people() -> void:
	if _world == null:
		return
	if _player:
		_people.append(_player)
	var residents := _world.get_node_or_null("LevelGeometry/Residents")
	if residents:
		for resident in residents.residents:
			_people.append(resident)

func _person_available(person: Node3D) -> bool:
	if not is_instance_valid(person) or not person.is_inside_tree() or not person.is_visible_in_tree():
		return false
	if person == _player and (_world.control_mode != &"on_foot" or _player.hide_mode != &"none"):
		return false
	if person is Resident and (person.hidden or person.state == &"knocked"):
		return false
	var visual: Node3D = person.get("visual")
	return is_instance_valid(visual) and visual.is_visible_in_tree()

# --- данные арены ---

func _collect_walls() -> void:
	var solids := Layout.all_solids()
	for index in solids.size():
		var spec: Array = solids[index]
		var size: Vector3 = spec[3]
		if size.y < 1.2 or minf(size.x, size.z) < 0.6 or spec[1] in ["snow", "snow_bank", "parked_car", "bins", "bench"]:
			continue
		var xz: Vector2 = spec[2]
		var rect := Rect2(xz - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
		var k := _walls.size()
		_walls.append([rect, size.y, index])
		_register(_wall_cells, rect.grow(VORTEX_RANGE), k)

func _collect_snags() -> void:
	for p in Layout.TREES:
		_add_snag(Vector3(p.x, 2.2, p.y), 1.1, 6.5, Layout.env_index_at(p))
	for p in Layout.POPLARS:
		_add_snag(Vector3(p.x, 3.0, p.y), 1.6, 9.5, Layout.env_index_at(p))
	for p in Layout.street_lamps() + Layout.trolley_poles():
		_add_snag(Vector3(p.x, 0.6, p.y), 0.32, 7.6, Layout.env_index_at(p))
	for spec in Layout.all_solids():
		if spec[1] != "fence" and spec[1] != "carpet_bar" and spec[1] != "sign_post":
			continue
		var xz: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		var along := Vector2(size.x, 0) if size.x >= size.z else Vector2(0, size.z)
		var n := maxi(1, int(along.length()))
		for k in n:
			var c := xz - along * 0.5 + along * ((k + 0.5) / float(n))
			_add_snag(Vector3(c.x, 0.05, c.y), 0.4, size.y + 0.15, Layout.env_index_at(xz))

func _add_snag(at: Vector3, radius: float, top: float, owner_index := -1) -> void:
	var k := _snag_points.size()
	_snag_points.append([at, radius, top, owner_index])
	_register(_snag_cells, Rect2(at.x - radius, at.z - radius, radius * 2.0, radius * 2.0), k)

## Статические spatial-индексы остаются прежними; состояние реальной опоры проверяется при использовании.
func _owner_present(index: int) -> bool:
	if index < 0: return true
	if not is_instance_valid(_breakables) and is_instance_valid(_world):
		_breakables = _world.get_node_or_null("LevelGeometry/Breakables")
	if not is_instance_valid(_breakables) or not _breakables.has_method("env_at_index"): return true
	var owner = _breakables.env_at_index(index)
	return owner == null or owner.is_intact() or (owner.mode == &"dent" and owner.blocks())

func _register(cells: Dictionary, rect: Rect2, k: int) -> void:
	for gx in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
		for gz in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
			var key := Vector2i(gx, gz)
			if not cells.has(key):
				cells[key] = []
			cells[key].append(k)

static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

## Высота, на которую ложится пакет: снег валов (C10) или крыша низкой коробки (гараж, киоск, павильон).
func ground_at(p: Vector3) -> float:
	var h := SnowField.height_at(p.x, p.z)
	for k in _wall_cells.get(_cell(p), []):
		var w: Array = _walls[k]
		if w.size() > 2 and not _owner_present(w[2]): continue
		if (w[0] as Rect2).has_point(Vector2(p.x, p.z)) and float(w[1]) < WALL_HEIGHT and p.y > float(w[1]) - 0.5:
			h = maxf(h, float(w[1]))
	return h + GROUND_LIFT

# --- ветер ---

func gust() -> float:
	if _lighting and is_instance_valid(_lighting):
		return float(_lighting.get("gust"))
	var wave := sin(clock * TAU / Lighting.GUST_PERIOD) * (0.6 + 0.4 * sin(clock * TAU / (Lighting.GUST_PERIOD * 0.37) + 1.1))
	return smoothstep(0.15, 0.9, 0.5 + 0.5 * wave)

## Средний ветер (без турбулентности и стен), м/с.
func wind_mean() -> Vector3:
	var g := gust()
	var base := Lighting.WIND.normalized()   # снег, позёмка и пакеты летят в одну сторону
	var turn := HEADING_SWING * (0.75 * sin(clock * TAU / HEADING_PERIOD) + 0.25 * sin(clock * TAU / (HEADING_PERIOD * 0.41) + 2.0))
	return base.rotated(Vector3.UP, turn + Lighting.GUST_TURN * (g - 0.3)) * WIND_BASE * (1.0 + GUST_GAIN * g)

func wind_at(p: Vector3, mean: Vector3) -> Vector3:
	var t := clock
	var w := mean
	w.x += TURB * (sin(p.z * 0.37 + t * 1.3) * 0.6 + sin(p.x * 0.21 - t * 0.7 + 1.3) * 0.4)
	w.z += TURB * (sin(p.x * 0.33 - t * 1.1 + 0.4) * 0.6 + sin(p.z * 0.17 + t * 0.9) * 0.4)
	w.y += TURB_UP * (sin(p.x * 0.29 + p.z * 0.23 + t * 1.7) * 0.7 + sin(t * 0.6 + p.x * 0.1) * 0.3)
	for k in _wall_cells.get(_cell(p), []):
		var wall: Array = _walls[k]
		if wall.size() > 2 and not _owner_present(wall[2]): continue
		if float(wall[1]) < WALL_HEIGHT or p.y > float(wall[1]) + 1.0:
			continue
		var rect: Rect2 = wall[0]
		var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.z, rect.position.y, rect.end.y))
		var off := Vector2(p.x, p.z) - q
		var d := off.length()
		if d > VORTEX_RANGE or d < 0.001:
			continue
		var n := Vector3(off.x, 0.0, off.y) / d   # наружу от стены
		var fall := 1.0 - d / VORTEX_RANGE
		var into := -(w.x * n.x + w.z * n.z)      # > 0 — ветер бьёт в стену
		var along := Vector3.UP.cross(n)
		if into > 0.0:
			w += n * into * fall                    # в стену не дует
			w.y += into * UPDRAFT * fall            # вверх по фасаду
			w += along * into * SWIRL * fall * sin(t * 0.7 + float(k))
		else:
			w += n * into * 0.5 * fall               # завиток за домом: тянет обратно к стене
			w.y += -into * 0.35 * fall
			w += along * into * 0.6 * fall * cos(t * 0.9 + float(k))
	return w

## Завиток у подъезда: тот же порыв и турбулентность, но обратная струя замыкает путь во дворе.
func _bag_wind(bag: Bag, p: Vector3, mean: Vector3) -> Vector3:
	var w := wind_at(p, mean)
	if bag.kind != &"plan_white":
		return w
	var offset := Vector2(p.x, p.z) - Layout.WIND_BAG_ORIGIN
	var cross_flow := Vector2(-offset.y, offset.x) * PLAN_WHITE_SWIRL
	var horizontal := (Vector2(w.x, w.z) * PLAN_WHITE_WIND_SHARE + cross_flow - offset * PLAN_WHITE_RETURN).limit_length(PLAN_WHITE_WIND_MAX)
	return Vector3(horizontal.x, minf(w.y, PLAN_WHITE_UPDRAFT_MAX), horizontal.y)

# --- шаг ---

func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	clock += delta
	_track_movers(delta)
	var mean := wind_mean()
	var g := gust()
	var movers := _movers()
	for bag: Bag in bags:
		bag.hit_cooldown = maxf(bag.hit_cooldown - delta, 0.0)
		if bag.hidden_wait > 0.0:
			bag.hidden_wait -= delta
			if bag.hidden_wait <= 0.0:
				_respawn(bag, mean)
			continue
		_react(bag, movers)
		match bag.state:
			&"fly": _fly(bag, mean, delta)
			&"rest": _rest(bag, mean, g, delta)
			&"snag": _snagged(bag, mean, g, delta)
		_bounds(bag, mean, delta)
		_animate(bag, mean, delta)
	_rustle()

func _fly(bag: Bag, mean: Vector3, delta: float) -> void:
	var p := bag.position
	var w := _bag_wind(bag, p, mean)
	var wh := Vector2(w.x, w.z).length()
	var v := bag.velocity
	v.x += (w.x - v.x) * DRAG * delta
	v.z += (w.z - v.z) * DRAG * delta
	v.y += (w.y - v.y) * DRAG_UP * delta
	v.y += (LIFT * maxf(wh - LIFT_MIN, 0.0) / bag.weight - SINK * bag.weight) * delta
	var ceiling := ground_at(p) + PLAN_WHITE_CEILING if bag.kind == &"plan_white" else CEILING
	if p.y > ceiling:
		v.y -= (p.y - ceiling) * 4.0 * delta
	p += v * delta
	# Стены домов: не сквозь, отскок мягкий.
	for k in _wall_cells.get(_cell(p), []):
		var wall: Array = _walls[k]
		if wall.size() > 2 and not _owner_present(wall[2]): continue
		var rect: Rect2 = (wall[0] as Rect2).grow(0.15)
		var top := float(wall[1])
		if p.y > top or not rect.has_point(Vector2(p.x, p.z)):
			continue
		if top < WALL_HEIGHT and p.y > top - 0.5:
			continue   # над низкой коробкой — ляжет на крышу
		var dx := minf(p.x - rect.position.x, rect.end.x - p.x)
		var dz := minf(p.z - rect.position.y, rect.end.y - p.z)
		if dx < dz:
			p.x = rect.position.x if p.x - rect.position.x < rect.end.x - p.x else rect.end.x
			v.x *= -0.3
		else:
			p.z = rect.position.y if p.z - rect.position.y < rect.end.y - p.z else rect.end.y
			v.z *= -0.3
		# При скольжении вдоль стены импульс не накапливается каждый кадр.
		v.y = maxf(v.y, 0.6)
	var ground := ground_at(p)
	if p.y <= ground:
		p.y = ground
		if v.y < 0.0:
			v.y = -v.y * 0.25
		v.x *= 0.6
		v.z *= 0.6
		if Vector2(v.x, v.z).length() < 1.2 and LIFT * maxf(wh - LIFT_MIN, 0.0) < SINK * bag.weight * bag.weight:
			bag.position = p
			_put_down(bag, p, bag.yaw)
			bag.rest_left = _rng.randf_range(REST_MIN.x, REST_MIN.y)
			return
	bag.velocity = v
	bag.position = p
	_try_snag(bag)

func _try_snag(bag: Bag) -> void:
	if _try_people_snag(bag):
		return
	var p := bag.position
	for k in _snag_cells.get(_cell(p), []):
		if k == bag.last_snag and clock - bag.snag_released < SNAG_COOLDOWN:
			continue
		var s: Array = _snag_points[k]
		if s.size() > 3 and not _owner_present(s[3]): continue
		var at: Vector3 = s[0]
		if p.y < at.y or p.y > float(s[2]) or Vector2(p.x - at.x, p.z - at.z).length() > float(s[1]):
			continue
		if _hash(bag.index * 131 + k * 7) > SNAG_CHANCE:
			continue
		bag.state = &"snag"
		bag.snag_point = p
		bag.last_snag = k
		bag.snag_left = _rng.randf_range(SNAG_TIME.x, SNAG_TIME.y)
		bag.snag_time = 0.0
		bag.velocity = Vector3.ZERO
		bag.snag_count += 1
		snags += 1
		return

func _try_people_snag(bag: Bag) -> bool:
	for i in _people.size():
		var person := _people[i]
		if not is_instance_valid(person) or not _person_available(person):
			continue
		if person == bag.last_person and clock - bag.snag_released < SNAG_COOLDOWN:
			continue
		if Vector2(bag.position.x - person.global_position.x, bag.position.z - person.global_position.z).length_squared() > 4.0:
			continue
		var visual: Node3D = person.visual
		var local := visual.to_local(bag.position)
		if absf(local.x) > PERSON_RADIUS or absf(local.z) > PERSON_RADIUS or local.y < 0.5 or local.y > 1.3:
			continue
		if _hash(bag.index * 131 + i * 59 + int(clock / 3.0) * 17) > PERSON_SNAG_CHANCE:
			continue
		bag.state = &"snag"
		bag.snag_target = person
		bag.snag_on_person = true
		bag.snag_local = Vector3(clampf(local.x, -0.32, 0.32), clampf(local.y, 0.7, 1.15), clampf(local.z, -0.12, 0.12))
		bag.snag_point = visual.to_global(bag.snag_local)
		bag.snag_left = _rng.randf_range(PERSON_SNAG_TIME.x, PERSON_SNAG_TIME.y)
		bag.snag_time = 0.0
		bag.velocity = Vector3.ZERO
		bag.snag_count += 1
		snags += 1
		return true
	return false

func _snagged(bag: Bag, mean: Vector3, g: float, delta: float) -> void:
	if bag.snag_on_person:
		if not is_instance_valid(bag.snag_target) or not _person_available(bag.snag_target):
			_release(bag, mean)
			return
		var visual: Node3D = bag.snag_target.visual
		bag.snag_point = visual.to_global(bag.snag_local)
	elif bag.last_snag >= 0 and bag.last_snag < _snag_points.size():
		var point: Array = _snag_points[bag.last_snag]
		if point.size() > 3 and not _owner_present(point[3]):
			_release(bag, mean)
			return
	bag.snag_left -= delta
	bag.snag_time += delta
	var w := _bag_wind(bag, bag.snag_point, mean)
	# Висит на ручках: тело вытянуто по ветру, в затишье опускается; качается.
	var flow := Vector3(w.x, 0.0, w.z) * 0.35
	var hang := (flow + Vector3.DOWN).normalized()
	var swing := Vector3(sin(clock * 3.1 + bag.index), 0.0, cos(clock * 2.3 + bag.index * 0.7)) * 0.12
	bag.hang_dir = (hang + swing).normalized()
	bag.position = bag.snag_point + bag.hang_dir * BAG_SIZE.y * 0.5 * BAG_SCALE
	var release_gust := PERSON_SNAG_GUST if bag.snag_on_person else SNAG_RELEASE_GUST
	var max_time := PERSON_SNAG_MAX if bag.snag_on_person else SNAG_MAX
	if (bag.snag_left <= 0.0 and g >= release_gust) or bag.snag_time >= max_time:
		_release(bag, w)

func _release(bag: Bag, w: Vector3) -> void:
	if bag.snag_on_person:
		bag.last_person = bag.snag_target
	bag.snag_on_person = false
	bag.snag_target = null
	bag.state = &"fly"
	bag.snag_released = clock
	bag.velocity = Vector3(w.x, 0.0, w.z) * 0.8 + Vector3.UP * 1.2
	bag.spin = Vector3(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-3.0, 3.0), _rng.randf_range(-6.0, 6.0))
	releases += 1

func _rest(bag: Bag, mean: Vector3, g: float, delta: float) -> void:
	if bag.position.y > ground_at(bag.position) + 0.15:
		_lift_off(bag, mean, 0.0)
		return
	bag.rest_left -= delta
	bag.rest_time += delta
	var p := bag.position
	var w := _bag_wind(bag, p, mean)
	# В порыв лежащий пакет ползёт по снегу.
	if g > 0.4:
		var crawl := Vector3(w.x, 0.0, w.z) * 0.12 * (g - 0.4) / bag.weight
		p += crawl * delta
		p.y = ground_at(p)
		bag.position = p
	if bag.rest_left <= 0.0 and g >= minf(bag.liftoff_gust * bag.weight, MAX_LIFTOFF_GUST):
		_lift_off(bag, w, 2.4)
	elif bag.rest_time > REST_RECYCLE and not _seen(p):
		bag.hidden_wait = 0.5
		bag.visible = false

func _lift_off(bag: Bag, w: Vector3, up: float) -> void:
	bag.state = &"fly"
	bag.rest_time = 0.0
	bag.velocity = Vector3(w.x * 0.6, up, w.z * 0.6)
	bag.spin = Vector3(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-2.0, 2.0), _rng.randf_range(-5.0, 5.0))
	liftoffs += 1

func _put_down(bag: Bag, p: Vector3, yaw: float) -> void:
	bag.snag_target = null
	bag.snag_on_person = false
	bag.state = &"rest"
	bag.yaw = yaw
	bag.rest_time = 0.0
	bag.velocity = Vector3.ZERO
	bag.spin = Vector3.ZERO
	p.y = ground_at(p)
	bag.position = p

func _bounds(bag: Bag, mean: Vector3, delta: float) -> void:
	var p := bag.position
	var out := not Layout.BOUNDS.grow(1.0).has_point(Vector2(p.x, p.z)) or p.y > OUT_HEIGHT
	if bag.kind == &"plan_white":
		out = out or Vector2(p.x, p.z).distance_to(Layout.WIND_BAG_ORIGIN) > Layout.WIND_BAG_RADIUS
	bag.out_time = bag.out_time + delta if out else 0.0
	bag.max_out_time = maxf(bag.max_out_time, bag.out_time)
	if bag.out_time > OUT_RESPAWN and not _seen(p):
		bag.visible = false
		_respawn(bag, mean)

## Вернуть пакет на землю у местного источника вне кадра; если все видны — ждать.
func _respawn(bag: Bag, mean: Vector3) -> void:
	var dir := mean.normalized()
	var best := -INF
	var pick := Vector2.INF
	for i in SOURCES.size():
		var s: Vector2 = SOURCES[i]
		var at := Vector3(s.x, 0.3, s.y)
		if _seen(at):
			continue
		var busy := false
		for other: Bag in bags:
			if other != bag and other.visible and Vector2(other.position.x, other.position.z).distance_to(s) < 4.0:
				busy = true
		if busy:
			continue
		var score := -(s.x * dir.x + s.y * dir.z) + _hash(i * 17 + respawns * 5) * 60.0
		if score > best:
			best = score
			pick = s
	if pick == Vector2.INF:
		bag.hidden_wait = 1.0
		bag.visible = false
		return
	bag.visible = true
	bag.hidden_wait = 0.0
	bag.out_time = 0.0
	_put_down(bag, Vector3(pick.x, 0.0, pick.y), _rng.randf_range(0.0, TAU))
	bag.rest_left = _rng.randf_range(REST_MIN.x, REST_MIN.y)
	respawns += 1

func _seen(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	return cam.global_position.distance_to(p) < HIDDEN_DISTANCE and cam.is_position_in_frustum(p)

# --- реакции на машины и Илюшу ---

func _track_movers(delta: float) -> void:
	for node in _movers_nodes():
		var p: Vector3 = node.global_position
		if node is CharacterBody3D:
			_vel[node] = node.velocity
		else:
			_vel[node] = (p - _prev[node]) / delta if _prev.has(node) else Vector3.ZERO
		_prev[node] = p

func _movers_nodes() -> Array:
	var out := []
	if _lada and is_instance_valid(_lada):
		out.append(_lada)
	if _player and is_instance_valid(_player):
		out.append(_player)
	for v in get_tree().get_nodes_in_group(&"traffic_vehicles"):
		out.append(v)
	return out

## [узел, вид, полугабарит x/z (Vector2.ZERO — Илюша), скорость].
func _movers() -> Array:
	var out := []
	if _lada and is_instance_valid(_lada):
		out.append([_lada, &"car", LADA_HALF, _vel.get(_lada, Vector3.ZERO)])
	var on_foot: bool = _world == null or _world.get("control_mode") != &"in_car"
	if _player and is_instance_valid(_player) and _player.visible and on_foot:
		out.append([_player, &"player", Vector2.ZERO, _vel.get(_player, Vector3.ZERO)])
	for v in get_tree().get_nodes_in_group(&"traffic_vehicles"):
		out.append([v, &"traffic", Vector2(v.size.x, v.size.z) * 0.5, _vel.get(v, Vector3.ZERO)])
	return out

func _react(bag: Bag, movers: Array) -> void:
	if bag.hit_cooldown > 0.0:
		return
	var p := bag.position
	for m in movers:
		var node: Node3D = m[0]
		if bag.snag_on_person and node == bag.snag_target:
			continue
		var v: Vector3 = m[3]
		var speed := Vector2(v.x, v.z).length()
		var half: Vector2 = m[2]
		if half == Vector2.ZERO:
			if speed < KICK_MIN_SPEED:
				continue
			var off := Vector3(p.x - node.global_position.x, 0.0, p.z - node.global_position.z)
			if off.length() > KICK_RADIUS or p.y > 1.4:
				continue
			var away := off.normalized() if off.length() > 0.01 else -node.global_basis.z
			_hit(bag, Vector3(v.x, 0, v.z) * 1.3 + away * 1.5 + Vector3.UP * KICK_UP, &"player")
			return
		if speed < CAR_MIN_SPEED:
			continue
		var local := node.global_transform.affine_inverse() * p
		var top: float = node.size.y if node is PathVehicle else Layout.LADA_SIZE.y
		if absf(local.x) < half.x + CAR_PAD and absf(local.z) < half.y + CAR_PAD and p.y < top:
			var side := node.global_basis.x * signf(local.x if absf(local.x) > 0.01 else 1.0)
			_hit(bag, Vector3(v.x, 0, v.z) * HIT_CARRY + side * (HIT_SIDE.x + HIT_SIDE.y * speed) + Vector3.UP * (HIT_UP.x + HIT_UP.y * speed), m[1])
			return
		# Затягивает за быстрой машиной.
		if speed > WAKE_SPEED and bag.state == &"fly" and p.y < 3.0:
			var behind := local.z - half.y   # вперёд у машины −z: позади — положительное local.z
			if behind > 0.0 and behind < WAKE_RANGE and absf(local.x) < half.x + 1.5:
				bag.velocity += (Vector3(v.x, 0, v.z) * 0.6 - bag.velocity) * 0.04

func _hit(bag: Bag, velocity: Vector3, by: StringName) -> void:
	if bag.snag_on_person:
		bag.last_person = bag.snag_target
	bag.snag_on_person = false
	bag.snag_target = null
	if bag.state == &"snag":
		bag.snag_released = clock
		releases += 1
	bag.state = &"fly"
	bag.rest_time = 0.0
	bag.velocity = velocity
	bag.position.y = maxf(bag.position.y, ground_at(bag.position) + 0.1)
	bag.spin = Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-6.0, 6.0), _rng.randf_range(-12.0, 12.0))
	bag.hit_cooldown = HIT_COOLDOWN
	bag.last_hit = clock
	hits[by] += 1

# --- облик ---

func _animate(bag: Bag, _mean: Vector3, delta: float) -> void:
	var look := bag.look
	match bag.state:
		&"fly":
			var v := bag.velocity
			var heading := atan2(-v.x, -v.z) if Vector2(v.x, v.z).length() > 0.3 else bag.yaw
			bag.yaw = lerp_angle(bag.yaw, heading, 1.0 - exp(-2.0 * delta))
			var target_spin := Vector3(sin(clock * 0.9 + bag.index) * 4.0, 0.0, cos(clock * 0.7 + bag.index * 1.3) * 3.0) * clampf(v.length() / 4.0, 0.3, 1.5)
			bag.spin = bag.spin.lerp(target_spin, 1.0 - exp(-1.2 * delta))
			bag.tumble += Vector3(bag.spin.x, 0.0, bag.spin.z) * delta
			bag.basis = Basis.from_euler(Vector3(bag.tumble.x, bag.yaw, bag.tumble.z))
			look.set_instance_shader_parameter("puff", 0.07 + 0.03 * sin(clock * 2.0 + bag.index))
			look.set_instance_shader_parameter("flutter", 0.035 + 0.01 * minf(v.length(), 4.0))
			look.set_instance_shader_parameter("flap_speed", 10.0 + v.length() * 2.0)
		&"snag":
			# Ручки — у точки зацепа (верх сетки), тело — по hang_dir.
			var down := bag.hang_dir
			var side := down.cross(Vector3.UP)
			if side.length() < 0.05:
				side = Vector3.RIGHT
			side = side.normalized()
			var face := side.cross(down).normalized()
			bag.basis = Basis(side, -down, face)
			look.set_instance_shader_parameter("puff", 0.09)
			look.set_instance_shader_parameter("flutter", 0.05)
			look.set_instance_shader_parameter("flap_speed", 16.0)
		&"rest":
			var lift := 0.012 + 0.03 * gust()
			bag.basis = Basis(Vector3.UP, bag.yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
			look.set_instance_shader_parameter("puff", 0.015 + 0.02 * gust())
			look.set_instance_shader_parameter("flutter", lift)
			look.set_instance_shader_parameter("flap_speed", 7.0)

# --- звук ---

func _rustle() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var best: Bag = null
	var best_d := RUSTLE_RANGE
	for bag: Bag in bags:
		if not bag.visible or (bag.state == &"rest" and clock - bag.last_hit > 1.0 and gust() < 0.6):
			continue
		var d := cam.global_position.distance_to(bag.position)
		if d < best_d:
			best_d = d
			best = bag
	if best == null:
		if rustle.playing:
			rustle.stop()
		return
	rustle.global_position = best.position
	rustle.pitch_scale = 0.9 + 0.04 * float(best.index % 5)
	if not rustle.playing:
		rustle.play(fposmod(clock * 0.37, 1.5))

# --- сетка и материалы ---

## Две стенки «майки» (COLOR.r 0/1), сшитые по краям: вершины краёв у стенок совпадают (раздув там 0).
static func bag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [1.0, -1.0]:
		for j in GRID.y:
			for i in GRID.x:
				var quad := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
				var order := [0, 1, 2, 0, 2, 3] if side > 0.0 else [0, 2, 1, 0, 3, 2]
				for o in order:
					var c: Vector2i = quad[o]
					var uv := Vector2(float(c.x) / GRID.x, float(c.y) / GRID.y)
					st.set_color(Color(1.0 if side > 0.0 else 0.0, 0, 0))
					st.set_normal(Vector3(0, 0, side))
					st.set_uv(uv)
					st.add_vertex(Vector3((uv.x - 0.5) * BAG_SIZE.x, (uv.y - 0.5) * BAG_SIZE.y, 0.0))
	var mesh := st.commit()
	mesh.custom_aabb = AABB(Vector3(-0.5, -0.5, -0.3), Vector3(1.0, 1.0, 0.6))   # раздув и трепет в шейдере
	return mesh

func _material(kind: StringName) -> ShaderMaterial:
	if _materials.has(kind):
		return _materials[kind]
	var m := ShaderMaterial.new()
	m.shader = BagShader
	m.set_shader_parameter("bag_size", BAG_SIZE)
	match kind:
		&"plan_white":
			m.set_shader_parameter("base_color", Color(0.96, 0.96, 0.94))
			m.set_shader_parameter("band_mode", 0.0)
			m.set_shader_parameter("ink_color", Color(0.12, 0.13, 0.12))
			m.set_shader_parameter("gloss", 0.27)
			m.set_shader_parameter("backlight_k", 0.6)
			_print(m, ["ВСЕ", "ПО ПЛАНУ"], "ПРОДУКТЫ У ДОМА")
		&"shop":
			m.set_shader_parameter("base_color", Color(0.93, 0.92, 0.88))
			m.set_shader_parameter("band_color", Color(0.80, 0.09, 0.07))
			m.set_shader_parameter("band2_color", Color(0.12, 0.55, 0.20))
			m.set_shader_parameter("band_mode", 1.0)
			m.set_shader_parameter("ink_color", Color(1.0, 0.97, 0.88))
			m.set_shader_parameter("gloss", 0.3)
			m.set_shader_parameter("backlight_k", 0.35)
			_print(m, ["ВСЁ", "ПО ПЛАНУ"], "продукты у дома")
		&"white":
			m.set_shader_parameter("base_color", Color(0.90, 0.90, 0.87))
			m.set_shader_parameter("band_color", Color(0.20, 0.38, 0.75))
			m.set_shader_parameter("band_mode", 2.0)
			m.set_shader_parameter("ink_color", Color(0.20, 0.38, 0.75))
			m.set_shader_parameter("gloss", 0.4)
			m.set_shader_parameter("backlight_k", 0.6)
			_print(m, ["СПАСИБО", "ЗА ПОКУПКУ!"], "приходите ещё")
		_:
			m.set_shader_parameter("base_color", Color(0.035, 0.035, 0.04))
			m.set_shader_parameter("band_mode", 0.0)
			m.set_shader_parameter("gloss", 0.18)
			m.set_shader_parameter("backlight_k", 0.05)
	_materials[kind] = m
	return m

## Надпись — маска (альфа) из SubViewport, отрисованная один раз (UPDATE_ONCE). Без рендера (headless) — без надписи.
func _print(m: ShaderMaterial, lines: Array, small: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := SubViewport.new()
	vp.name = "Print_%d" % _materials.size()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	add_child(vp)
	var box := VBoxContainer.new()
	var print_margin := 16.0
	var print_width := float(vp.size.x) - print_margin * 2.0
	box.position.x = print_margin
	box.size = Vector2(print_width, vp.size.y)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -10)
	vp.add_child(box)
	for k in lines.size():
		var label := Label.new()
		label.text = lines[k]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FONT)
		var font_size := 64 if lines[k].length() <= 8 else 44
		while font_size > 1 and FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > print_width:
			font_size -= 1
		label.add_theme_font_size_override("font_size", font_size)
		label.rotation = -0.04 + 0.05 * k   # от руки, чуть вкось
		box.add_child(label)
	var tag := Label.new()
	tag.text = small
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", FONT)
	tag.add_theme_font_size_override("font_size", 24)
	box.add_child(tag)
	m.set_shader_parameter("print_tex", vp.get_texture())
	m.set_shader_parameter("has_print", 1.0)

static func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + 78.233) * 43758.5453, 1.0)

## Один пакет: состояние полёта; облик — ребёнок Look.
class Bag:
	extends Node3D
	var kind: StringName = &"shop"
	var index := 0
	var look: MeshInstance3D
	var state: StringName = &"rest"   # fly, rest, snag
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var tumble := Vector3.ZERO
	var yaw := 0.0
	var weight := 1.0
	var liftoff_gust := 0.6
	var rest_left := 0.0
	var rest_time := 0.0
	var snag_point := Vector3.ZERO
	var snag_target: Node3D
	var snag_on_person := false
	var snag_local := Vector3.ZERO
	var last_person: Node3D
	var snag_left := 0.0
	var snag_time := 0.0
	var snag_released := -100.0
	var last_snag := -1
	var snag_count := 0
	var hang_dir := Vector3.DOWN
	var hit_cooldown := 0.0
	var last_hit := -100.0
	var out_time := 0.0
	var max_out_time := 0.0
	var hidden_wait := 0.0

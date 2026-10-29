extends RefCounted
## LIFE-01: планировщик жизни жителей (поручение владельца 29.10, вечер: «у каждого NPC цель и маршрут»). Один на мир,
## его держит Residents. Данные — Layout.LIFE_* (C1): граф дорожек (узлы, рёбра с флагами переходов), точки интереса
## («умные объекты»: вид занятия, место, взгляд, длительность, число мест, разрушаемый-якорь).
##
## Персона жителя (PERSONAS по индексу) — свой подъезд и цепочка шагов («дом → магазин → лавка → дом»); шаг — вид точки
## (&"window", &"bench"…), её id (&"shop24") или &"home". На шаге житель выбирает свободную точку этого вида: ближе —
## лучше, немного случайности (свой RandomNumberGenerator жителя) и прибавка точкам ближе PLAYER_NEAR к Илюше (жизнь там,
## где игрок). Занятые места бронируются (reserve/release), сломанный якорь точку закрывает.
##
## Путь — кратчайший по графу (Дейкстра от узла точки, деревья кэшируются: граф неизменен): от места жителя — к ближайшей
## точке обычного ребра (или от узла точки, где он стоит), по рёбрам к узлу цели и прямой к месту. Переходам (&"cross",
## &"route") — штраф CROSS_COST к длине: по тротуару, если можно. Почему граф, а не NavigationServer3D: улицы строятся
## кодом из коробок (навмеш пришлось бы печь на старте), переходы и запрет проезжей части на навмеше — области и веса, а
## граф — 90 узлов, которые тест целиком проверяет на тротуары, запасы от коробок, постов и путей стелса (life01_test).

const Layout = preload("res://game/world/layout.gd")

const CROSS_COST := 15.0     # м штрафа за ребро-переход
const PLAYER_NEAR := 50.0    # м: точки ближе к Илюше получают прибавку PLAYER_BONUS
const PLAYER_BONUS := 0.4
const DIST_SCALE := 80.0     # м: −1 к оценке за столько метров до точки
const RANDOM_WEIGHT := 0.6
const AT_SPOT := 0.5         # м: житель на месте точки — путь начинается от её узла

## Персоны по индексу жителя: подъезд и цепочка шагов. Пустая — второй в паре (его ведёт первый, Residents.PAIRS).
## Пары ходят только туда, где вдвоём уместно: магазин, окно, подъезд, контейнеры.
const PERSONAS := [
	{"home": &"door_h1e", "plan": [&"bins", &"press", &"bench", &"home", &"shop24", &"home"]},   # 0 бабка в шубе
	{"home": &"door_h1w", "plan": [&"carpet", &"home", &"bench", &"shop24", &"home"]},          # 1 фиолетовая: ковёр
	{"home": &"door_h3w", "plan": [&"stop", &"shaw", &"edge", &"press", &"home"]},             # 2 пассажир троллейбуса
	{"home": &"door_h1e", "plan": [&"press", &"slide", &"home", &"slide", &"shaw"]},            # 3 пацан
	{"home": &"door_h4", "plan": [&"shaw", &"home", &"bench", &"shop24", &"home"]},             # 4 бабка в берете
	{"home": &"door_h9b", "plan": [&"gastro", &"edge", &"home", &"gastro", &"bench"]},         # 5 с собачкой: выгул
	{"home": &"door_h10w", "plan": [&"shop24", &"home", &"press", &"bins", &"home"]},          # 6 турист, первый пары
	{"home": &"door_h9a", "plan": [&"shop24", &"home", &"gastro", &"home"]},                   # 7 пацан, первый пары
	{}, {},                                                                                     # 8, 9 — вторые в парах
	{"home": &"door_h1e", "plan": [&"smoke", &"domino", &"home", &"smoke", &"press"]},         # 10 курит, «козёл»
	{"home": &"door_h3e", "plan": [&"smoke", &"home", &"domino", &"bins", &"smoke"]},         # 11 курит, «козёл»
	{"home": &"door_h7", "plan": [&"apteka", &"bench", &"shop24", &"home"]},                   # 12 бабка в тюрбане
	{"home": &"door_h3w", "plan": [&"slide", &"home", &"press", &"slide"]},                   # 13 пацан
	{"home": &"door_h4", "plan": [&"slide", &"home", &"slide", &"shaw"]},                     # 14 пацан: горка
	{"home": &"door_h1e", "plan": [&"dig", &"shaw", &"dig", &"press"]},                       # 15 рабочий теплотрассы
	{"home": &"door_h1e", "plan": [&"sweep", &"bins", &"sweep", &"home"]},                    # 16 дворник
	{"home": &"door_h1e", "plan": [&"domino", &"home", &"domino", &"press"]},                 # 17 доминошник
	{"home": &"door_h1e", "plan": [&"hood", &"home", &"hood", &"shaw"]},                      # 18 мужик под капотом
	{"home": &"door_h4", "plan": [&"slide", &"shaw", &"slide", &"home"]},                     # 19 пацан: горка
]
const PAIR_KINDS: Array[StringName] = [&"door", &"shop", &"window", &"bins", &"edge"]

var nodes := {}      # id → Vector3
var edges: Array = []   # [a, b, флаг]
var spots := {}      # id → {id, kind, node, pos, yaw, dur, cap, anchor}
var reserved := {}   # id точки → Array жителей
var camera: Camera3D       # Residents обновляет каждый шаг физики (LOD, края карты)
var player: Node3D
var breakables: Node       # Breakables (BREAK-01): якоря точек
var props := {}            # имя → Node3D, видим, пока идёт занятие (ковёр)
var vehicles: Array = []   # машины кольца и автобус ГСУМ — для переходов
var _adj := {}       # id → Array [сосед, флаг, длина]
var _trees := {}     # узел-цель → [dist, next]

func _init() -> void:
	for id in Layout.LIFE_NODES:
		var p: Vector2 = Layout.LIFE_NODES[id]
		nodes[id] = Vector3(p.x, 0.0, p.y)
		_adj[id] = []
	for e in Layout.LIFE_EDGES:
		var flag: StringName = e[2] if e.size() > 2 else &""
		edges.append([e[0], e[1], flag])
		var length: float = nodes[e[0]].distance_to(nodes[e[1]]) + (CROSS_COST if flag != &"" else 0.0)
		_adj[e[0]].append([e[1], flag, length])
		_adj[e[1]].append([e[0], flag, length])
	for s in Layout.LIFE_SPOTS:
		var p: Vector2 = s[3]
		spots[s[0]] = {"id": s[0], "kind": s[1], "node": s[2], "pos": Vector3(p.x, 0.0, p.y), "yaw": s[4],
			"dur": s[5], "cap": s[6], "anchor": s[7]}

func reset() -> void:
	reserved.clear()
	for k in props:
		props[k].visible = false

# --- выбор точки ---

## Шаг цепочки step → id свободной точки (или &"", если подходящих нет). except — не эту (где житель уже стоит).
func choose(resident: Node3D, step: StringName, home: StringName, rng: RandomNumberGenerator, except := &"", pair := false) -> StringName:
	var best := &""
	var best_score := -INF
	var at := Vector3(resident.global_position.x, 0.0, resident.global_position.z)
	for id in spots:
		var s: Dictionary = spots[id]
		if id == except:
			continue
		if step == &"home":
			if id != home:
				continue
		elif id != step and s.kind != step:
			continue
		if pair and not PAIR_KINDS.has(s.kind):
			continue
		if not is_free(id, resident) or not anchor_intact(id):
			continue
		var score := -at.distance_to(s.pos) / DIST_SCALE + rng.randf() * RANDOM_WEIGHT
		if at.distance_to(s.pos) < AT_SPOT:
			score += 1.0   # уже стоит на месте точки (курящий у подъезда)
		if is_instance_valid(player) and player.is_visible_in_tree() and _flat(player.global_position).distance_to(s.pos) < PLAYER_NEAR:
			score += PLAYER_BONUS
		if score > best_score:
			best_score = score
			best = id
	return best

func is_free(id: StringName, resident: Node3D = null) -> bool:
	var cap: int = spots[id].cap
	if cap <= 0:
		return true
	var list: Array = reserved.get(id, [])
	return list.has(resident) or list.size() < cap

func reserve(id: StringName, resident: Node3D) -> void:
	if id == &"":
		return
	var list: Array = reserved.get(id, [])
	if not list.has(resident):
		list.append(resident)
	reserved[id] = list

func release(id: StringName, resident: Node3D) -> void:
	if reserved.has(id):
		reserved[id].erase(resident)

## Якорь точки цел (или его нет / разрушаемые не построены).
func anchor_intact(id: StringName) -> bool:
	var anchor: StringName = spots[id].anchor
	if anchor == &"" or not is_instance_valid(breakables) or not breakables.has_method(&"get_by_id"):
		return true
	var b = breakables.get_by_id(anchor)
	return b == null or b.is_intact()

## Место в кадре (для ухода за край карты и возвращения).
func on_screen(p: Vector3) -> bool:
	return is_instance_valid(camera) and camera.is_position_in_frustum(p + Vector3.UP)

func set_prop(name: StringName, on: bool) -> void:
	if props.has(name):
		props[name].visible = on

# --- путь ---

## Путь от from к месту точки spot_id: {"points": Array[Vector3], "flags": Array[StringName]} — флаг у каждого отрезка
## points[i] → points[i + 1]. from_spot — точка, на месте которой житель стоит: путь начинается от её узла.
func path(from: Vector3, spot_id: StringName, from_spot := &"") -> Dictionary:
	var s: Dictionary = spots[spot_id]
	var tree: Array = _tree(s.node)
	var dist: Dictionary = tree[0]
	var next: Dictionary = tree[1]
	var points: Array = []
	var flags: Array = []
	var here := _flat(from)
	_push(points, flags, here, &"")
	var start: StringName
	if from_spot != &"" and spots.has(from_spot) and here.distance_to(spots[from_spot].pos) <= AT_SPOT:
		start = spots[from_spot].node
	else:
		var hit := nearest_on_graph(here)
		var a: StringName = hit[1]
		var b: StringName = hit[2]
		var p: Vector3 = hit[0]
		var via_a: float = p.distance_to(nodes[a]) + dist.get(a, INF)
		var via_b: float = p.distance_to(nodes[b]) + dist.get(b, INF)
		start = a if via_a <= via_b else b
		_push(points, flags, p, &"")
	_push(points, flags, nodes[start], &"")
	var n := start
	var guard := 0
	while n != s.node and guard < 500:
		var step: Array = next.get(n, [])
		if step.is_empty():
			break
		_push(points, flags, nodes[step[0]], step[1])
		n = step[0]
		guard += 1
	_push(points, flags, s.pos, &"")
	flags.resize(maxi(points.size() - 1, 0))
	return {"points": points, "flags": flags}

## Ближайшая к p точка на обычном ребре (переходы — нет): [точка, узел a, узел b].
func nearest_on_graph(p: Vector3) -> Array:
	var best := INF
	var out := [nodes[edges[0][0]], edges[0][0], edges[0][1]]
	var q := Vector2(p.x, p.z)
	for e in edges:
		if e[2] != &"":
			continue
		var a: Vector3 = nodes[e[0]]
		var b: Vector3 = nodes[e[1]]
		var c := Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z))
		var d := c.distance_to(q)
		if d < best:
			best = d
			out = [Vector3(c.x, 0.0, c.y), e[0], e[1]]
	return out

## Связность: все узлы достижимы от первого.
func connected() -> bool:
	var tree: Array = _tree(nodes.keys()[0])
	return tree[0].size() == nodes.size()

func _push(points: Array, flags: Array, p: Vector3, flag: StringName) -> void:
	if not points.is_empty() and points[-1].distance_to(p) < 0.05:
		if flag != &"" and not flags.is_empty():
			flags[-1] = flag
		return
	if not points.is_empty():
		flags.append(flag)
	points.append(p)

## Дейкстра от узла goal: dist (до goal) и next (следующий узел к goal и флаг ребра).
func _tree(goal: StringName) -> Array:
	if _trees.has(goal):
		return _trees[goal]
	var dist := {goal: 0.0}
	var next := {}
	var open := [goal]
	var done := {}
	while not open.is_empty():
		var k := 0
		for i in open.size():
			if dist[open[i]] < dist[open[k]]:
				k = i
		var n: StringName = open[k]
		open.remove_at(k)
		if done.has(n):
			continue
		done[n] = true
		for link in _adj[n]:
			var m: StringName = link[0]
			var d: float = dist[n] + link[2]
			if d < dist.get(m, INF):
				dist[m] = d
				next[m] = [n, link[1]]
				open.append(m)
	_trees[goal] = [dist, next]
	return _trees[goal]

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

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
const SOCIAL_JOIN_BONUS := 0.8
const CHAT_DISTANCE := 2.8
const DOMINO_DISTANCE := 5.0   # места по сторонам одного стола; сидящие визуально придвинуты к нему
const CHAT_TURN_SECONDS := 8.0
const DOMINO_TURN_SECONDS := 1.45

## Персоны по индексу жителя: подъезд и цепочка шагов. Пустая — второй в паре (его ведёт первый, Residents.PAIRS).
## Пары ходят только туда, где вдвоём уместно: магазин, окно, подъезд, контейнеры.
const PERSONAS := [
	{"home": &"door_h1e", "plan": [&"bins", &"wait_a1", &"press", &"bench", &"home", &"shop24", &"home"]},   # 0 бабка в шубе
	{"home": &"door_h1w", "plan": [&"carpet", &"home", &"bench", &"shop24", &"home"]},          # 1 фиолетовая: ковёр
	{"home": &"door_h3w", "plan": [&"wait_a1", &"stop", &"shaw", &"edge", &"chat", &"press", &"home"]},    # 2 пассажир троллейбуса
	{"home": &"door_h1e", "plan": [&"press", &"slide", &"home", &"hockey", &"shaw"]},           # 3 пацан: горка, хоккей
	{"home": &"door_h4", "plan": [&"shaw", &"look_bw1", &"chat", &"gastro", &"wait_a2", &"home"]},          # 4 бабка в берете (LIFE-02: на B)
	{"home": &"door_h9b", "plan": [&"gastro", &"chat", &"look_bw2", &"edge", &"look_b3", &"home", &"gastro"]},   # 5 с собачкой: выгул по B (LIFE-02)
	{"home": &"door_h10w", "plan": [&"shop24", &"home", &"press", &"bins", &"home"]},          # 6 турист, первый пары
	{"home": &"door_h9a", "plan": [&"shop24", &"home", &"gastro", &"home"]},                   # 7 пацан, первый пары
	{}, {},                                                                                     # 8, 9 — вторые в парах
	{"home": &"door_h1e", "plan": [&"smoke", &"domino", &"smoke", &"domino", &"home"]},        # 10 курит, «козёл» (LIFE-02: чаще за столиком)
	{"home": &"door_h3e", "plan": [&"smoke", &"domino", &"home", &"domino", &"smoke"]},       # 11 курит, «козёл» (LIFE-02: домино сразу после перекура)
	{"home": &"door_h7", "plan": [&"apteka", &"chat", &"stop", &"bench", &"shop24", &"home"]},          # 12 бабка в тюрбане (LIFE-02: разговор у остановки)
	{"home": &"door_h3w", "plan": [&"snowball", &"home", &"press", &"slide"]},                # 13 пацан: снежки
	{"home": &"door_h4", "plan": [&"slide", &"home", &"slide", &"shaw"]},                     # 14 пацан: горка
	{"home": &"door_h1e", "plan": [&"dig", &"dig", &"shaw", &"dig", &"press"]},               # 15 рабочий теплотрассы
	{"home": &"door_h1e", "plan": [&"sweep", &"bins", &"sweep", &"home"]},                    # 16 дворник
	{"home": &"door_h1e", "plan": [&"domino", &"smoke", &"domino", &"home", &"domino"]},       # 17 доминошник
	{"home": &"door_h1e", "plan": [&"hood", &"home", &"hood", &"shaw"]},                      # 18 мужик под капотом
	{"home": &"door_h4", "plan": [&"slide", &"snowball", &"slide", &"home"]},                 # 19 пацан: горка, снежки
	# PEOPLE-03 (P2): хоккеисты, снежки, торговка соленьями, бабушка с санками (санки с внуком — всегда при ней, carry).
	{"home": &"door_h4", "plan": [&"hockey", &"home", &"hockey", &"shaw"]},                   # 20 пацан: хоккей
	{"home": &"door_h4", "plan": [&"hockey", &"shaw", &"hockey", &"home"]},                   # 21 пацан: хоккей
	{"home": &"door_h3w", "plan": [&"snowball", &"home", &"snowball", &"slide"]},             # 22 пацан: снежки
	{"home": &"door_h9a", "plan": [&"trade", &"home", &"trade"]},                             # 23 торговка
	{"home": &"door_h10w", "plan": [&"sled", &"shop24", &"sled", &"home"], "carry": &"sled"}, # 24 бабушка с санками
	# LIFE-02 (сверка main b4a4d13: «маршрут миссии почти пуст»): прохожие улиц A и B — остановка A (троллейбусом до B
	# и в «ГАСТРОНОМ»), витрины B, «ПРЕССА», «ШАУРМА», края карты; у киоска только тротуар B восток (мимо). Второй
	# доминошник и двое рабочих у раскопки (третье место dig_3 — «один копает, двое смотрят»).
	{"home": &"door_h7", "plan": [&"look_b2", &"chat", &"gastro", &"look_b3", &"stop", &"look_press", &"press", &"home"]},                    # 25 бабка в колпаке
	{"home": &"door_h9b", "plan": [&"look_press", &"chat", &"stop", &"look_bw1", &"shaw", &"edge", &"gastro", &"look_b1", &"home"]},  # 26 бабка с бантом
	{"home": &"door_h9a", "plan": [&"look_b1", &"gastro", &"chat", &"look_bw2", &"press", &"stop", &"home"]},     # 27 бабка в шубе
	{"home": &"door_h3e", "plan": [&"chat", &"stop", &"look_b2", &"chat", &"gastro", &"shaw", &"home"]},                   # 28 бабка с собачкой
	{"home": &"door_h1e", "plan": [&"domino", &"smoke", &"domino", &"bins", &"domino"]},                 # 29 доминошник в ушанке
	{"home": &"door_h1e", "plan": [&"dig", &"dig", &"shaw", &"dig", &"dig", &"home"]},                   # 30 рабочий
	{"home": &"door_h3e", "plan": [&"dig", &"dig", &"dig", &"press", &"dig"]},                           # 31 рабочий с сигаретой
	# ARENA-03: личные дела западной/северной сторон, внутреннего двора и торговых узлов.
	{"home": &"door_h11", "plan": [&"apteka", &"home", &"shop24", &"home"]}, # 32
	{"home": &"door_h11", "plan": [&"chat_h11a", &"notice_h11", &"home", &"chat_h11a", &"notice_h11", &"home", &"shop24", &"home"]}, # 33
	{"home": &"door_h11", "plan": [&"edge_d_n", &"home", &"gastro", &"home"]}, # 34
	{"home": &"door_h11", "plan": [&"notice_h11", &"chat_h11b", &"home", &"notice_h11", &"chat_h11b", &"home", &"apteka", &"home"], "phase": 1}, # 35
	{"home": &"door_h9a", "plan": [&"buy_pickles", &"home", &"edge_d_n", &"home"]}, # 36
	{"home": &"door_h10e", "plan": [&"buy_pickles", &"bench", &"home", &"shop24"]}, # 37
	{"home": &"door_h10w", "plan": [&"bench", &"bins_h10", &"home", &"press"]}, # 38
	{"home": &"door_h7", "plan": [&"chat_i1", &"bench", &"bins_h10", &"shop24", &"chat_i1", &"home"]}, # 39
	{"home": &"door_h10w", "plan": [&"chat_i2", &"watch_yard", &"bench", &"home", &"shop24", &"chat_i2"], "phase": 1}, # 40
	{"home": &"door_h7", "plan": [&"watch_yard", &"bins_h10", &"chat_i1", &"bench", &"home", &"shaw"]}, # 41
	{"home": &"door_h11", "plan": [&"edge_d_n", &"apteka", &"home", &"shop24"]}, # 42
	{"home": &"door_h9a", "plan": [&"edge_d_n", &"buy_pickles", &"home", &"gastro"]}, # 43
	{"home": &"door_h11", "plan": [&"apteka", &"press", &"home", &"edge_a_w"]}, # 44
	{"home": &"door_h11", "plan": [&"notice_h11", &"home", &"chat_h11b", &"notice_h11", &"chat_h11b", &"home", &"shop24", &"home"]}, # 45
	{"home": &"door_h7", "plan": [&"press", &"home", &"shop24", &"bench"]}, # 46
	{"home": &"door_h10w", "plan": [&"press", &"bench", &"home", &"bins_h10"]}, # 47
	{"home": &"door_h4", "plan": [&"shaw", &"wait_a1", &"home", &"edge_ase"]}, # 48
	{"home": &"door_h9b", "plan": [&"shaw", &"gastro", &"home", &"edge_ane"]}, # 49
	{"home": &"door_h9a", "plan": [&"gastro", &"home", &"stop", &"look_b2"]}, # 50
	{"home": &"door_h9b", "plan": [&"look_b2", &"gastro", &"edge_ane", &"home"]}, # 51
	{"home": &"door_h9a", "plan": [&"chat_b1", &"gastro", &"home", &"look_b3"]}, # 52
	{"home": &"door_h3e", "plan": [&"press", &"home", &"bins_yard", &"edge_a_w"]}, # 53
	{"home": &"door_h7", "plan": [&"bench", &"chat_i2", &"bins_h10", &"home", &"shop24"], "phase": 2}, # 54
	{"home": &"door_h9b", "plan": [&"buy_pickles", &"edge_d_n", &"home", &"gastro"]}, # 55
	{"home": &"door_h11", "plan": [&"home", &"notice_h11", &"chat_h11a", &"home", &"chat_h11a", &"notice_h11", &"home", &"edge_a_w"]}, # 56
	{"home": &"door_h10e", "plan": [&"shop24", &"bench", &"bins_h10", &"home", &"shop24", &"home"]}, # 57
	{"home": &"door_h11", "plan": [&"buy_pickles", &"home", &"apteka", &"chat_h11b"]}, # 58
	{"home": &"door_h9b", "plan": [&"buy_pickles", &"home", &"gastro", &"edge_d_n"]}, # 59
	{"home": &"door_h10w", "plan": [&"watch_yard", &"bench", &"bins_h10", &"chat_i2", &"home", &"shop24"], "phase": 1}, # 60
	{"home": &"door_h7", "plan": [&"bins_h10", &"notice_h7", &"chat_i1", &"bench", &"home", &"press"], "phase": 1}, # 61
	{"home": &"door_h7", "plan": [&"look_bw1", &"chat_bw1", &"press", &"home"]}, # 62
	{"home": &"door_h4", "plan": [&"shaw", &"edge_ase", &"home", &"stop", &"gastro", &"home"]}, # 63

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
# PEOPLE-03 (P2): шайба хоккейной коробки — одна на всех (узел props[&"puck"]). У кого она (holder) — ведёт её клюшкой;
# в полёте (pass, бросок по воротам, отскок) её двигает тот, кто отдал, и по прилёту отдаёт адресату.
var puck_holder: Node3D
var puck_flight := {}        # {"from", "to", "t", "time", "to_who" (житель или null — ворота), "by"}
var hockey_passes := 0
var hockey_shots := 0
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
		if s[1] == &"queue":
			spots[s[0]]["service"] = s[8]
			spots[s[0]]["rank"] = s[9]

func reset() -> void:
	reserved.clear()
	for k in props:
		props[k].visible = false
	puck_holder = null
	puck_flight = {}
	hockey_passes = 0
	hockey_shots = 0
	if props.has(&"puck"):
		props[&"puck"].visible = true
		props[&"puck"].global_position = Vector3(Layout.RINK[0].x, PUCK_Y, Layout.RINK[0].y)

# --- выбор точки ---

## Шаг цепочки step → id свободной точки (или &"", если подходящих нет). except — не эту (где житель уже стоит).
func choose(resident: Node3D, step: StringName, home: StringName, rng: RandomNumberGenerator, except := &"", pair := false) -> StringName:
	var best := &""
	var best_score := -INF
	var at := Vector3(resident.global_position.x, 0.0, resident.global_position.z)
	for id in spots:
		var s: Dictionary = spots[id]
		if id == except or s.kind == &"queue":
			continue
		if step == &"home":
			if id != home:
				continue
		elif id != step and s.kind != step:
			continue
		if pair and not PAIR_KINDS.has(s.kind):
			continue
		if not anchor_intact(id):
			continue
		var candidate: StringName = id
		if not is_free(id, resident) or not _queue_members(id).is_empty():
			candidate = _queue_tail(id, resident)
			if candidate == &"" or candidate == except:
				continue
		var score := -at.distance_to(s.pos) / DIST_SCALE + rng.randf() * RANDOM_WEIGHT
		if at.distance_to(s.pos) < AT_SPOT:
			score += 1.0   # уже стоит на месте точки (курящий у подъезда)
		if is_instance_valid(player) and player.is_visible_in_tree() and _flat(player.global_position).distance_to(s.pos) < PLAYER_NEAR:
			score += PLAYER_BONUS
		if s.kind in [&"chat", &"domino"] and _social_waiter(s, resident):
			score += SOCIAL_JOIN_BONUS
		if score > best_score:
			best_score = score
			best = candidate
	return best

## Бронь места задаёт очередь ещё на подходе. Новые покупатели занимают только хвост;
## передние места освобождаются по мере реального движения, а не отдельным таймером.
func _queue_members(service: StringName) -> Array:
	var out: Array = []
	for id in reserved:
		var spot: Dictionary = spots[id]
		if spot.kind != &"queue" or spot.service != service:
			continue
		for resident in reserved[id]:
			if is_instance_valid(resident) and resident.state != &"knocked" and not resident.hidden:
				out.append([spot.rank, resident])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out

func _queue_tail(service: StringName, resident: Node3D) -> StringName:
	var tail := 0
	for entry in _queue_members(service):
		tail = maxi(tail, entry[0])
	var best := &""
	var rank := 2147483647
	for id in spots:
		var spot: Dictionary = spots[id]
		if spot.kind == &"queue" and spot.service == service and spot.rank > tail \
				and spot.rank < rank and is_free(id, resident):
			best = id
			rank = spot.rank
	return best

## Доступное следующее место уже прибывшего покупателя. Сбитый не держит всю очередь;
## сама бронь остаётся его безопасной точкой возвращения по контракту KNOCK-02.
func queue_next(resident: Node3D) -> StringName:
	if not spots.has(resident.spot_id):
		return &""
	var spot: Dictionary = spots[resident.spot_id]
	if spot.kind != &"queue" or not anchor_intact(spot.service):
		return &""
	var members := _queue_members(spot.service)
	if not members.is_empty() and members[0][1] == resident and is_free(spot.service, resident):
		return spot.service
	var best := &""
	var rank: int = spot.rank
	for id in spots:
		var candidate: Dictionary = spots[id]
		if candidate.kind == &"queue" and candidate.service == spot.service \
				and candidate.rank < rank and is_free(id, resident):
			best = id
			rank = candidate.rank
	return best

## Дальний путь — намерение. У окна/в очереди место выдаётся по настоящему приходу;
## уже стоящий в очереди обслуживается раньше нового прохожего у свободного окна.
func window_arrival(resident: Node3D) -> StringName:
	var spot: Dictionary = spots[resident.spot_id]
	var service: StringName = spot.service if spot.kind == &"queue" else spot.id
	if not anchor_intact(service):
		return &""
	if reserved.get(spot.id, []).has(resident):
		return spot.id
	if spot.kind == &"window" and is_free(service, resident) and _queue_members(service).is_empty():
		return service
	return _queue_tail(service, resident)

func is_free(id: StringName, resident: Node3D = null) -> bool:
	var cap: int = spots[id].cap
	if cap <= 0:
		return true
	var list: Array = reserved.get(id, [])
	return list.has(resident) or list.size() < cap

func reserve(id: StringName, resident: Node3D) -> bool:
	if id == &"":
		return false
	var list: Array = reserved.get(id, [])
	if list.has(resident):
		return true
	var spot: Dictionary = spots[id]
	if spot.kind in [&"window", &"queue"]:
		var from: Dictionary = spots.get(resident.spot_id, {})
		var advancing: bool = from.get("kind", &"") == &"queue" \
				and reserved.get(resident.spot_id, []).has(resident) and queue_next(resident) == id
		if not advancing:
			if _flat(resident.global_position).distance_to(spot.pos) > AT_SPOT:
				return false
			if spot.kind == &"window" and not _queue_members(id).is_empty():
				return false
			if spot.kind == &"queue" and _queue_tail(spot.service, resident) != id:
				return false
		if not is_free(id, resident):
			return false
	list.append(resident)
	reserved[id] = list
	return true

func release(id: StringName, resident: Node3D) -> void:
	if reserved.has(id):
		reserved[id].erase(resident)

func _same_social_group(a: Dictionary, b: Dictionary) -> bool:
	if a.kind != b.kind:
		return false
	if a.kind == &"chat":
		return a.node == b.node
	return a.kind == &"domino" and a.anchor != &"" and a.anchor == b.anchor

func _social_waiter(spot: Dictionary, visitor: Node3D) -> bool:
	for id in reserved:
		if not _same_social_group(spot, spots[id]):
			continue
		for resident in reserved[id]:
			if is_instance_valid(resident) and resident != visitor and _social_present(resident, spot.kind):
				return true
	return false

func _social_present(resident: Node3D, kind: StringName) -> bool:
	if not is_instance_valid(resident) or not resident.is_inside_tree() or not resident.is_visible_in_tree():
		return false
	if not resident.is_playing(kind) or not spots.has(resident.spot_id) or not anchor_intact(resident.spot_id):
		return false
	return resident.global_position.distance_to(spots[resident.spot_id].pos) <= AT_SPOT

## Участники выводятся из броней и реального присутствия; ушедший, скрытый или сбитый сразу исключается.
func social_members(resident: Node3D) -> Array:
	if not spots.has(resident.spot_id):
		return []
	var spot: Dictionary = spots[resident.spot_id]
	if not spot.kind in [&"chat", &"domino"] or not _social_present(resident, spot.kind):
		return []
	var members: Array = [resident]
	for id in reserved:
		if not _same_social_group(spot, spots[id]):
			continue
		for other in reserved[id]:
			if not is_instance_valid(other) or other == resident or not _social_present(other, spot.kind):
				continue
			var reach := CHAT_DISTANCE if spot.kind == &"chat" else DOMINO_DISTANCE
			if resident.global_position.distance_to(other.global_position) > reach:
				continue
			var ray := PhysicsRayQueryParameters3D.create(resident.global_position + Vector3.UP * 1.1,
				other.global_position + Vector3.UP * 1.1, 1 | 64)
			if not resident.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			members.append(other)
	members.sort_custom(func(a, b): return a.index < b.index)
	return members

## Общие часы ведущего дают очередь без второго таймера или отдельного владельца группы.
func social_turn(resident: Node3D) -> Dictionary:
	var members := social_members(resident)
	if members.size() < 2:
		return {}
	var period := CHAT_TURN_SECONDS if spots[resident.spot_id].kind == &"chat" else DOMINO_TURN_SECONDS
	var elapsed: float = members[0].clock
	var beat := int(floor(elapsed / period))
	var ids: Array = members.map(func(member): return member.get_instance_id())
	return {"members": members, "speaker": members[beat % members.size()], "phase": fposmod(elapsed, period),
		"token": "%s:%d" % [str(ids), beat]}

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

# --- PEOPLE-03 (P2): хоккей ---

const PUCK_Y := 0.07          # м: шайба на льду (лёд — 0,05)
const PUCK_SPEED := 9.0       # м/с: пас и бросок
const PUCK_LEAD := 0.65       # м впереди игрока — у крюка клюшки
const PASS_SECONDS := Vector2(1.6, 3.4)   # с: столько ведёт, потом пас или бросок
const SHOT_SHARE := 0.3       # доля бросков по воротам, когда есть кому отдать

## Кто сейчас занят kind (на месте точки этого вида, не уходит, не скрыт, не сбит): хоккеисты, снежки.
func players(kind: StringName) -> Array:
	var out := []
	for id in reserved:
		if spots[id].kind != kind:
			continue
		for r in reserved[id]:
			if is_instance_valid(r) and r.is_playing(kind):
				out.append(r)
	return out

func hockey_players() -> Array:
	return players(&"hockey")

## Шаг шайбы от лица игрока r. Возвращает звук события: &"stick" — пас или бросок, &"board" — шайба в борт/ворота,
## &"" — ничего. Шайба ничья — летит к первому, кто спросил; у r — едет у крюка, а когда пора (r.puck_timer), r отдаёт
## пас другому игроку или бросает по ближним воротам (один в коробке — только броски).
func hockey_step(r: Node3D, delta: float, rng: RandomNumberGenerator) -> StringName:
	if not props.has(&"puck"):
		return &""
	var puck: Node3D = props[&"puck"]
	if not puck_flight.is_empty():
		if puck_flight.by != r and is_instance_valid(puck_flight.by) and puck_flight.by.is_playing(&"hockey"):
			return &""
		puck_flight.by = r   # отдавший ушёл — шайбу ведёт тот, кто спросил
		puck_flight.t += delta
		var target: Vector3 = puck_flight.to
		var who = puck_flight.to_who
		if who != null and is_instance_valid(who):
			target = who.stick_point()
			puck_flight.to = target
		var k := clampf(puck_flight.t / maxf(puck_flight.time, 0.01), 0.0, 1.0)
		var at: Vector3 = puck_flight.from.lerp(target, k)
		puck.global_position = Vector3(at.x, PUCK_Y, at.z)
		if k < 1.0:
			return &""
		puck_flight = {}
		if who != null and is_instance_valid(who) and who.is_hockey_active():
			puck_holder = who
			return &""
		if who == null:
			_puck_fly(puck, puck.global_position, r, r)   # отскок от ворот обратно бросавшему
			return &"board"
		puck_holder = null
		return &""
	if puck_holder == null or not is_instance_valid(puck_holder) or not puck_holder.is_hockey_active():
		puck_holder = null
		_puck_fly(puck, puck.global_position, r, r)
		return &""
	if puck_holder != r:
		return &""
	var p: Vector3 = r.stick_point()
	puck.global_position = Vector3(p.x, PUCK_Y, p.z)
	r.puck_timer -= delta
	if r.puck_timer > 0.0:
		return &""
	r.puck_timer = rng.randf_range(PASS_SECONDS.x, PASS_SECONDS.y)
	var mates := hockey_players().filter(func(m): return m != r)
	puck_holder = null
	if mates.is_empty() or rng.randf() < SHOT_SHARE:
		var goal: Vector2 = Layout.LIFE_RINK_GOALS[0] if p.x < Layout.RINK[0].x else Layout.LIFE_RINK_GOALS[1]
		_puck_fly(puck, p, null, r, Vector3(goal.x, PUCK_Y, goal.y + rng.randf_range(-0.6, 0.6)))
		hockey_shots += 1
	else:
		_puck_fly(puck, p, mates[rng.randi_range(0, mates.size() - 1)], r)
		hockey_passes += 1
	return &"stick"

## Игрок r ушёл из коробки: шайба у него — остаётся лежать на льду.
func hockey_leave(r: Node3D) -> void:
	if puck_holder == r:
		puck_holder = null
	if not puck_flight.is_empty() and puck_flight.to_who == r:
		puck_flight = {}

func _puck_fly(puck: Node3D, from: Vector3, to_who, by: Node3D, to := Vector3.INF) -> void:
	var target: Vector3 = to if to_who == null else to_who.stick_point()
	var time := maxf(Vector2(from.x, from.z).distance_to(Vector2(target.x, target.z)) / PUCK_SPEED, 0.12)
	puck_flight = {"from": Vector3(from.x, PUCK_Y, from.z), "to": target, "t": 0.0, "time": time, "to_who": to_who, "by": by}
	puck.global_position = Vector3(from.x, PUCK_Y, from.z)

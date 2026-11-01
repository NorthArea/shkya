extends Node3D
## POLISH-03 B — событие на возврате: «ПРОЕЗД ЗАКРЫТ — НИЧЕГО НЕОБЫЧНОГО». Критик 30.10: обратный путь пустой, проход
## короткий. Пока MissionDirector.road_closed (покупка → Илюша дома или сдача), ГСУМ перекрывает улицу Б (Троллейную)
## между киоском и улицей A от стены до стены (Layout.CLOSURE_*): второй микроавтобус поперёк проезжей части, секции
## красно-белого ограждения, конусы, щит и сотрудник ГСУМ без диалога. На «Ладе» домой — в объезд по Выборной и Богаткова
## (Layout.ROUTE_DETOUR, мини-карта); пешеходам — проходы на тротуарах. Радио объявляет объезд, у ограждения — реплика
## ГСУМ, рой дронов на это время «активнее» (Drones.set_agitated). Без насилия: никого не ловят, ничего не наказывают.
## Транспорт кольца встаёт у перекрытия и ждёт (C8: без объезда) — «пробка»; когда Илюша во дворе, перекрытие снимают.
## Ставится, только когда на линии перекрытия никого нет (машины, троллейбус, «Лада», Илюша); проём на полосе x 73,5
## закрывается, когда автобус ГСУМ этапа 7 проехал к киоску (VAN_PATH) и проём свободен.
## Финал (этап 10): при сдаче микроавтобус перекрытия ставится у соседнего подъезда (Layout.FINALE_VAN) — Бабка смотрит
## на него и говорит «Или не сходишь» (Finale). Владелец состояния — MissionDirector; здесь только мир и подсказки.
## Узел создаёт Patrols (DemoWorld/LevelGeometry/Patrols/RoadClosure).

const Layout = preload("res://game/world/layout.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
const CityVanScript = preload("res://game/vehicles/city_van.gd")
const NpcScript = preload("res://game/npc/npc.gd")
const Materials = preload("res://game/world/materials.gd")

const FENCE_HEIGHT := 1.1          # видимая высота секции ограждения
const FENCE_BODY_HEIGHT := 2.0     # коллизия выше: «Лада» на валу снега (0,9 м) не перескакивает
const FENCE_THICK := 0.35
const SECTION := 2.0               # м: длина секции ограждения
const RED := Color(0.78, 0.12, 0.10)
const WHITE := Color(0.94, 0.93, 0.90)
const FRAME := Color(0.22, 0.23, 0.25)
const CONE := Color(0.98, 0.42, 0.08)
const RADIO_DELAY := 2.2           # с после покупки: тост «ХЛЕБ +1» дочитан
const RADIO_SECONDS := 3.5
const GAG_DISTANCE := 22.0         # м от середины перекрытия: «Лада» с севера — реплика ГСУМ (один раз за перекрытие)
const GAG_SECONDS := 3.0
const GAP_FORCE_SECONDS := 40.0    # автобус этапа 7 так и не проехал — проём закрывается, если свободен
const CLEAR_MASK := 1 | 2 | 4      # транспорт кольца (World), Илюша, «Лада»
## Перекрытие стоит не дольше: потом его снимают и пробка кольца (C8: транспорт ждёт без объезда) рассасывается, даже
## если Илюша домой не спешит. Объезд с покупки до двора на «Ладе» — 60–75 с, пешком через проход — меньше.
const MAX_SECONDS := 150.0

var van: CityVan
var guard: Node3D
var active := false                # перекрытие стоит
var gap_closed := false
var finale_parked := false
## Для проверок: сколько раз ставили и снимали, показано реплик радио и ГСУМ.
var activations := 0
var lifts := 0
var radio_shown := 0
var gags_shown := 0

var _world: Node
var _mission: MissionDirector
var _fence: AnimatableBody3D
var _gap: AnimatableBody3D
var _decor: Node3D
var _pending := false              # road_closed, но линия занята — ждём
var _radio_left := -1.0
var _gag_done := false
var _gap_wait := 0.0
var _active_seconds := 0.0
## Для проверок: сколько раз перекрытие сняли по сроку MAX_SECONDS.
var timeouts := 0
var _query := PhysicsShapeQueryParameters3D.new()

func _init() -> void:
	name = "RoadClosure"

func _ready() -> void:
	_world = _find_world()
	_mission = _world.get_node_or_null("MissionDirector") if _world else null
	_build()
	_show(false)
	if _mission:
		_mission.road_closed_changed.connect(_on_road_closed_changed)
		_mission.state_changed.connect(_on_state_changed)

func _find_world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:
			return node
		node = node.get_parent()
	return null

# --- сборка ---

func _build() -> void:
	van = CityVanScript.new()
	van.name = "ClosureVan"
	add_child(van)
	van.park(Layout.CLOSURE_VAN, Layout.CLOSURE_VAN_YAW)
	_sensor_off()
	guard = NpcScript.new()
	guard.name = "ClosureGuard"
	guard.interaction_id = &"closure_guard"
	guard.character = "officer"
	guard.height_m = Catalog.canvas_height_for("officer", Catalog.RF_ADULT_MALE_REFERENCE_M)
	guard.tint = Color(1, 1, 1)
	guard.body_radius = 0.45
	guard.facing_yaw = 0.0   # лицом на север, к киоску
	guard.position = Layout.CLOSURE_GUARD
	add_child(guard)
	guard.interactable.prompt = ""
	guard.interactable.enabled = false
	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)
	var spans := _spans()
	_fence = _make_body("Fence", spans["fixed"])
	_gap = _make_body("GapSection", [spans["gap"]])
	_build_cones()
	_build_sign()

## Отрезки ограждения по x: постоянные (между стенами, проходами и автобусом) и проём на полосе автобуса этапа 7.
func _spans() -> Dictionary:
	var half := CityVanScript.SIZE.z * 0.5
	var van_x := Vector2(Layout.CLOSURE_VAN.x - half, Layout.CLOSURE_VAN.x + half)
	var cuts: Array = [Layout.CLOSURE_GAPS[0], van_x, Layout.CLOSURE_VAN_GAP, Layout.CLOSURE_GAPS[1]]
	var fixed: Array = []
	var from := Layout.CLOSURE_X.x
	for cut: Vector2 in cuts:
		if cut.x - from > 0.05:
			fixed.append(Vector2(from, cut.x))
		from = cut.y
	if Layout.CLOSURE_X.y - from > 0.05:
		fixed.append(Vector2(from, Layout.CLOSURE_X.y))
	return {"fixed": fixed, "gap": Layout.CLOSURE_VAN_GAP}

func _make_body(node_name: String, spans: Array) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = node_name
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var parts: Array = []   # [центр, размер, цвет]
	for span: Vector2 in spans:
		var length := span.y - span.x
		var shape := BoxShape3D.new()
		shape.size = Vector3(length, FENCE_BODY_HEIGHT, FENCE_THICK)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3((span.x + span.y) * 0.5, FENCE_BODY_HEIGHT * 0.5, Layout.CLOSURE_Z)
		body.add_child(collider)
		var n := maxi(1, int(round(length / SECTION)))
		var step := length / n
		for k in n:
			var x0 := span.x + step * k
			var cx := x0 + step * 0.5
			# Секция: две стойки с опорами, верхняя и нижняя трубы, пять полос красное-белое.
			for leg_x in [x0 + 0.08, x0 + step - 0.08]:
				parts.append([Vector3(leg_x, FENCE_HEIGHT * 0.5, Layout.CLOSURE_Z), Vector3(0.05, FENCE_HEIGHT, 0.05), FRAME])
				parts.append([Vector3(leg_x, 0.03, Layout.CLOSURE_Z), Vector3(0.08, 0.06, 0.7), FRAME])
			parts.append([Vector3(cx, FENCE_HEIGHT - 0.03, Layout.CLOSURE_Z), Vector3(step - 0.1, 0.05, 0.05), FRAME])
			parts.append([Vector3(cx, 0.22, Layout.CLOSURE_Z), Vector3(step - 0.1, 0.05, 0.05), FRAME])
			var stripes := 5
			var w := (step - 0.2) / stripes
			for s in stripes:
				parts.append([Vector3(x0 + 0.1 + w * (s + 0.5), 0.62, Layout.CLOSURE_Z), Vector3(w, 0.62, 0.03), RED if s % 2 == 0 else WHITE])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = parts.size()
	for i in parts.size():
		var p: Array = parts[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(p[1]), p[0]))
		mm.set_instance_color(i, p[2])
	var view := MultiMeshInstance3D.new()
	view.name = "View"
	view.multimesh = mm
	view.material_override = Materials.instance_colored()
	body.add_child(view)
	return body

## Конусы: у торцов автобуса и вдоль проёма, с белой полосой.
func _build_cones() -> void:
	var half := CityVanScript.SIZE.z * 0.5
	var z := Layout.CLOSURE_Z - 0.9
	var xs := [Layout.CLOSURE_VAN.x - half - 0.6, Layout.CLOSURE_VAN.x + half + 0.6, Layout.CLOSURE_VAN_GAP.x + 0.7,
		Layout.CLOSURE_VAN_GAP.y - 0.7, (Layout.CLOSURE_VAN_GAP.x + Layout.CLOSURE_VAN_GAP.y) * 0.5]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.17
	cone.height = 0.7
	cone.radial_segments = 10
	mm.mesh = cone
	mm.instance_count = xs.size() * 2
	for i in xs.size():
		mm.set_instance_transform(i * 2, Transform3D(Basis.IDENTITY, Vector3(xs[i], 0.35, z)))
		mm.set_instance_color(i * 2, CONE)
		mm.set_instance_transform(i * 2 + 1, Transform3D(Basis.from_scale(Vector3(0.62, 0.12, 0.62)), Vector3(xs[i], 0.42, z)))
		mm.set_instance_color(i * 2 + 1, WHITE)
	var view := MultiMeshInstance3D.new()
	view.name = "Cones"
	view.multimesh = mm
	view.material_override = Materials.instance_colored()
	_decor.add_child(view)

## Щит на двух ногах лицом к киоску (на север) и обратной стороной к A: «ПРОЕЗД ЗАКРЫТ», мелко «НИЧЕГО НЕОБЫЧНОГО»,
## стрелка объезда на север, к Выборной.
func _build_sign() -> void:
	var sign := Node3D.new()
	sign.name = "Sign"
	sign.position = Layout.CLOSURE_SIGN
	_decor.add_child(sign)
	var board := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.6, 1.3, 0.06)
	board.mesh = mesh
	board.position = Vector3(0, 1.55, 0)
	board.material_override = Materials.plain(WHITE)
	sign.add_child(board)
	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(2.7, 1.4, 0.04)
	rim.mesh = rim_mesh
	rim.position = Vector3(0, 1.55, 0)
	rim.material_override = Materials.plain(RED)
	sign.add_child(rim)
	for x in [-1.1, 1.1]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.06, 0.9, 0.06)
		leg.mesh = leg_mesh
		leg.position = Vector3(x, 0.45, 0)
		leg.material_override = Materials.plain(FRAME)
		sign.add_child(leg)
	for side in [0.0, PI]:
		var face := Node3D.new()
		face.rotation.y = side
		sign.add_child(face)
		var dz := -0.04 if side == 0.0 else -0.04
		face.add_child(_label(QuestLines.CLOSURE_SIGN, 86, RED, Vector3(0, 1.85, dz)))
		face.add_child(_label(QuestLines.CLOSURE_SIGN_SMALL, 50, Color(0.12, 0.10, 0.08), Vector3(0, 1.45, dz)))
		face.add_child(_label(QuestLines.CLOSURE_SIGN_DETOUR, 50, Color(0.12, 0.10, 0.08), Vector3(0, 1.15, dz)))

## Подпись щита: лицом в −Z узла (на север для лицевой стороны).
func _label(text: String, size: int, color: Color, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.0042
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.rotation.y = PI   # Label3D читается с +Z — разворачиваем к северу
	label.position = at
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

# --- состояние ---

func _on_road_closed_changed(closed: bool) -> void:
	if closed:
		_pending = true
		_radio_left = RADIO_DELAY
		_gag_done = false
		_gap_wait = 0.0
	else:
		_pending = false
		_radio_left = -1.0
		if active:
			lifts += 1
		active = false
		if not finale_parked:
			_show(false)
	_set_drones(closed)

func _on_state_changed(_old: StringName, new_state: StringName) -> void:
	if new_state == MissionDirector.COMPLETE:
		park_finale()
	elif new_state == MissionDirector.NOT_STARTED and finale_parked:
		finale_parked = false
		_show(false)

## Финал: микроавтобус перекрытия — у соседнего подъезда, ограждение и сотрудник убраны. Ставится за кадром при сдаче.
func park_finale() -> void:
	finale_parked = true
	active = false
	_pending = false
	_show(false)
	van.park(Layout.FINALE_VAN, Layout.FINALE_VAN_YAW)
	_sensor_off()
	_set_visible(van, true)

func _physics_process(delta: float) -> void:
	if _mission == null:
		return
	if _radio_left >= 0.0:
		var sound: Node = _world.get_node_or_null("SoundDirector")
		if sound and sound.car_radio and sound.car_radio.music.news_enabled():
			_radio_left = maxf(0.0, _radio_left - delta)
			if _radio_left == 0.0:
				var text: String = "\n".join(PackedStringArray(QuestLines.RADIO_DETOUR))
				if sound.urgent_radio_line(text, maxf(RADIO_SECONDS, QuestLines.read_seconds(text.replace("\n", " ")))):
					_radio_left = -1.0
					radio_shown += 1
	if not _mission.road_closed:
		return
	if _pending and _line_clear(Vector2(Layout.CLOSURE_X.x, Layout.CLOSURE_X.y)):
		_pending = false
		_activate()
	if active and not gap_closed:
		_gap_wait += delta
		if _stage7_van_passed() and _line_clear(Layout.CLOSURE_VAN_GAP):
			gap_closed = true
			_set_body(_gap, true)
	if active:
		_check_gag()
		_active_seconds += delta
		if _active_seconds >= MAX_SECONDS:
			timeouts += 1
			_mission.notify_home_reached()
			return
	_check_home()

func _activate() -> void:
	active = true
	activations += 1
	_active_seconds = 0.0
	gap_closed = false
	van.park(Layout.CLOSURE_VAN, Layout.CLOSURE_VAN_YAW)
	_sensor_off()
	_set_visible(van, true)
	_set_visible(guard, true)
	_decor.visible = true
	_set_body(_fence, true)
	_set_body(_gap, false)

## Автобус ГСУМ этапа 7 (Patrols.van) проехал перекрытие на север к киоску, стоит или ждёт слишком долго.
func _stage7_van_passed() -> bool:
	var patrols := get_parent()
	var stage7: Node3D = patrols.get("van") if patrols else null
	if stage7 == null or stage7 == van:
		return true
	if stage7.global_position.z < Layout.CLOSURE_Z - 4.0 or not stage7.is_driving():
		return true
	return _gap_wait >= GAP_FORCE_SECONDS

## На линии перекрытия (x from…to, ±1 м по z от оси) нет тел транспорта, Илюши и «Лады», кроме своих.
func _line_clear(x: Vector2) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(x.y - x.x, 2.0, CityVanScript.SIZE.x + 1.0)
	_query.shape = box
	_query.collision_mask = CLEAR_MASK
	_query.exclude = [van.get_rid(), _fence.get_rid(), _gap.get_rid()]
	var guard_body: CollisionObject3D = guard.get_node_or_null("Body")
	if guard_body:
		_query.exclude.append(guard_body.get_rid())
	_query.transform = Transform3D(Basis.IDENTITY, Vector3((x.x + x.y) * 0.5, 1.0, Layout.CLOSURE_Z))
	for hit in get_world_3d().direct_space_state.intersect_shape(_query, 8):
		var body: Object = hit["collider"]
		if body is StaticBody3D and not (body is AnimatableBody3D):
			continue   # дома, столбы, валы — не помеха
		return false
	return true

func _check_gag() -> void:
	if _gag_done or _world == null or _world.get("control_mode") != &"in_car":
		return
	var car: Node3D = _world.get("car")
	if car == null:
		return
	var mid := Vector3((Layout.CLOSURE_X.x + Layout.CLOSURE_X.y) * 0.5, 0.0, Layout.CLOSURE_Z)
	var p := car.global_position
	if p.z < Layout.CLOSURE_Z and Vector2(p.x - mid.x, p.z - mid.z).length() < GAG_DISTANCE:
		_gag_done = true
		gags_shown += 1
		_say(QuestLines.CLOSURE_GAG, GAG_SECONDS)

## Илюша (или «Лада» с ним) во дворе — перекрытие снимают (MissionDirector.notify_home_reached).
func _check_home() -> void:
	if _world == null:
		return
	var who: Node3D = _world.get("car") if _world.get("control_mode") == &"in_car" else _world.get("player")
	if who and Layout.YARD_HOME.has_point(Vector2(who.global_position.x, who.global_position.z)):
		_mission.notify_home_reached()

func _say(lines: Array, seconds: float) -> void:
	var sound: Node = _world.get_node_or_null("SoundDirector") if _world else null
	if sound and sound.has_method("show_gag"):
		sound.show_gag(lines, seconds)

func _set_drones(on: bool) -> void:
	var drones: Node = _world.get_node_or_null("LevelGeometry/Drones") if _world else null
	if drones and drones.has_method("set_agitated"):
		drones.set_agitated(on)

# --- видимость и коллизии ---

func _show(on: bool) -> void:
	_set_visible(van, on)
	_set_visible(guard, on)
	_decor.visible = on
	_set_body(_fence, on)
	_set_body(_gap, on and gap_closed)
	if not on:
		gap_closed = false

func _set_body(body: CollisionObject3D, on: bool) -> void:
	body.visible = on
	body.collision_layer = 1 if on else 0

func _set_visible(node: Node3D, on: bool) -> void:
	node.visible = on
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 1 if on else 0
	var body: CollisionObject3D = node.get_node_or_null("Body")
	if body:
		body.collision_layer = 1 if on else 0
	var zone: Node = node.get_node_or_null("Interactable")
	if zone == null and node == van:
		zone = van.interactable
	if zone and zone is Area3D:
		(zone as Area3D).monitorable = on
		if zone is Interactable:
			(zone as Interactable).enabled = on and node == van

func _sensor_off() -> void:
	van.sensor.enabled = false
	van.sensor.show_cone = false

## Для проверок: стоит ли перекрытие и закрыт ли проём (вместе — улица перекрыта от стены до стены).
func is_blocking() -> bool:
	return active and gap_closed

extends Node
## QuestFlow (QUEST-01): связывает зоны Бабки и продавщицы, KioskZone, диалоги и маркеры с MissionDirector.
## Состояния и проверки — только в MissionDirector (C5); здесь команды, диалоги, `!`/`?` и тост.
## Мир читает отсюда toast_text() для HUD (C6). Владелец файла — QUEST-01.
##
## Вход в машину сюда не входит: его сообщает мир через mission.notify_entered_car() (DRIVE-01).
## POLISH-02: сообщает директору, с кем Илюша рядом (текст задачи по ситуации), поворачивает собеседника
## к Илюше, после панели финала открывает карточку «Конец демо» (HUD), играет короткий сигнал на «ПРИНЯТЬ».
## EXT-01 (L): реплики — только QuestLines (game/mission/lines.gd); цепочки реплик продавщицы и Бабки
## при возврате; полицейский (&"officer") и «военком» (&"account_officer") — зоны Interactable исполнителя N,
## подключаются по id после сборки мира; миссию они не меняют. Сдача — после цепочки, кнопкой «СДАТЬ ХЛЕБ».
## Финал — два пузыря над Бабкой подряд с паузой QuestLines.THANKS_PAUSE: второй встаёт на место первого (с хвостиком
## к Бабке), первый поднимается над ним без хвостика — читается сверху вниз (EXT-01 fix2, P3).
## EXT-01 fix2 (P2-3): по закрытию разговора с полицейским — StealthDirector.grant_grace(OFFICER_GRACE) и
## PatrolNpc.turn_away_from(Илюша): он сразу отворачивается на угол без Илюши; задержался рядом — провал через ~7 с
## (fix3, P3: защита 5 с — уйти от поста на юг к парковке через его второй угол успевают без провала).

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const CoinLines = preload("res://game/mission/coin_lines.gd")   # COINS-01: отказ продавщицы при нехватке денег
const ACCEPT_SOUND := preload("res://assets/audio/quest_accept.wav")
const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const POP_SECONDS := 0.15

const TOAST_SECONDS := 2.0
const MARKER_Y := 2.62   # над шапкой Бабки: верх облика 2,07 м при height_m 2,17 (ART-01, PLAY-02)
const DIALOG_SHOULDER := 1.3  # м: камера вбок на время диалога, собеседник виден из-за Илюши (кадр 07)
const TOAST_TEXT := "ХЛЕБ +1"
## Зоны наблюдателей расширения (исполнитель N): подключаются по id, если узлы есть в мире.
const OBSERVER_IDS: Array[StringName] = [&"officer", &"account_officer"]
## Защита после разговора с полицейским, с (этап 5: «может спокойно уйти, если быстро завершит диалог»).
const OFFICER_GRACE := 5.0

## Пузырь финала: размер шрифта и пикселя текста, поля и хвостик (в пикселях текста), высота над Бабкой.
const BUBBLE_FONT := 80
const BUBBLE_PIXEL := 0.0035
const BUBBLE_PAD := 34.0
const BUBBLE_TAIL := 56.0
const BUBBLE_DOWNSCALE := 2.0
const BUBBLE_Y := 2.55
const BUBBLE_GAP := 0.06  # м между первым и вторым пузырём

var world: Node
var mission: MissionDirector
var dialog: DialogPanel
var marker: Label3D
var thanks_bubble: Label3D
## Подложка пузыря финала (кадр 10): бумажный пузырь с хвостиком, текст поверх.
var thanks_back: Sprite3D
## Второй пузырь финала: появляется на месте первого (с хвостиком), первый — выше него, без хвостика.
var thanks_after_bubble: Label3D
var thanks_after_back: Sprite3D
var _thanks_tail_texture: Texture2D     # первый пузырь с хвостиком (пока один)
var _thanks_plain_texture: Texture2D    # первый пузырь без хвостика (над вторым)
var _thanks_low_y := 0.0                # центр подложки с хвостиком: кончик хвостика на BUBBLE_Y
var _thanks_high_y := 0.0               # центр первого пузыря без хвостика над вторым
var hud: Node
var accept_player: AudioStreamPlayer

## Что QuestFlow попросил у мыши (в headless Input.mouse_mode не отражает запрос).
var wants_mouse_captured := true
## Цепочка продавщицы показана один раз за мир; дальше — короткая реплика.
var vendor_chain_shown := false
var _toast_left := 0.0
var _kind: StringName = &""
var _marker_time := 0.0
var _marker_symbol := ""
var _thanks_left := 0.0
## Зоны наблюдателей по id и их владельцы (для поворота к Илюше).
var _observer_zones: Dictionary = {}

func _ready() -> void:
	world = get_parent()
	mission = world.get_node("MissionDirector")
	dialog = DialogPanelScript.new()
	dialog.name = "DialogPanel"
	dialog.choice.connect(_on_choice)
	add_child(dialog)
	world.get_node("Babka").interactable.interacted.connect(_on_interacted.bind(&"babka"))
	world.get_node("Vendor").interactable.interacted.connect(_on_interacted.bind(&"vendor"))
	mission.bread_received.connect(_on_bread_received)
	_build_marker()
	hud = world.get_node_or_null("GameHUD")
	if hud:
		hud.completion_closed.connect(_on_completion_closed)
		if hud.has_signal("end_closed"):
			hud.end_closed.connect(_on_end_closed)
	accept_player = AudioStreamPlayer.new()
	accept_player.name = "AcceptSound"
	accept_player.stream = ACCEPT_SOUND
	accept_player.volume_db = -6.0  # в ряду сигналов квеста: итог ≈ −23 дБ (микс PLAY-03)
	add_child(accept_player)
	# Зоны наблюдателей создаются миром позже QuestFlow (дети готовы раньше родителя) — искать после сборки.
	call_deferred(&"connect_observer_zones")

func toast_text() -> String:
	return TOAST_TEXT if _toast_left > 0.0 else ""

## Открыт диалог или панель сдачи: ввод Илюши остановлен.
func is_dialog_open() -> bool:
	return _kind != &""

## Подключить зоны полицейского и «военкома» по id (повторный вызов безопасен; зоны могут появиться позже).
func connect_observer_zones() -> void:
	for node in world.find_children("*", "Area3D", true, false):
		if not (node is Interactable):
			continue
		var zone: Interactable = node
		if zone.interaction_id in OBSERVER_IDS and not _observer_zones.has(zone.interaction_id):
			_observer_zones[zone.interaction_id] = zone
			zone.interacted.connect(_on_interacted.bind(zone.interaction_id))

func _process(delta: float) -> void:
	_toast_left = maxf(0.0, _toast_left - delta)
	var symbol := mission.babka_marker()
	marker.visible = symbol != ""
	marker.text = symbol
	if symbol != _marker_symbol:
		_marker_symbol = symbol
		if symbol != "":
			_pop_3d(marker)
	_marker_time += delta
	marker.position.y = MARKER_Y + sin(_marker_time * 3.0) * 0.08
	# Второй пузырь финала — через паузу после первого (этап 10 расширения).
	if _thanks_left > 0.0:
		_thanks_left -= delta
		if _thanks_left <= 0.0 and _kind == &"thanks":
			_stack_thanks(true)
			thanks_after_back.visible = true
			thanks_after_bubble.visible = true
			_pop_3d(thanks_after_back)

func _physics_process(_delta: float) -> void:
	# Прибытие: Илюша или машина на площадке киоска, пока миссия ждёт прибытия.
	if mission.state == MissionDirector.DRIVE_TO_KIOSK and world.kiosk_zone.is_occupied():
		mission.notify_arrived_kiosk()
	mission.set_nearby(_nearby())
	# Подсказки зон наблюдателей — из MissionDirector, как у остальных зон (C3).
	for id in _observer_zones:
		var zone: Interactable = _observer_zones[id]
		zone.prompt = mission.prompt_for(id)
		var npc: Node = zone.get_parent()
		# Полицейский со спины не отвечает (P3): подсказки и E нет, пока Илюша за спиной.
		zone.enabled = zone.prompt != "" and (npc == null or not npc.has_method("can_talk_to") or npc.can_talk_to(world.player))

## С кем Илюша рядом: собеседник открытого диалога или ближайшая доступная зона E пешком.
func _nearby() -> StringName:
	match _kind:
		&"offer", &"idle", &"return", &"thanks":
			return &"babka"
		&"vendor":
			return &"vendor"
		&"end", &"officer", &"ride":
			return &""
	if world.control_mode != &"on_foot":
		return &""
	var zone: Interactable = world.player.current_interactable()
	if zone and (zone.interaction_id == &"babka" or zone.interaction_id == &"vendor"):
		return zone.interaction_id
	return &""

# --- взаимодействие ---

func _on_interacted(_actor: Node, id: StringName) -> void:
	if _kind != &"":
		return
	if world.has_method(&"refuse_in_hide") and world.refuse_in_hide(id):
		return  # EXT-02: в укрытии диалог и покупка не открываются — подсказка-отказ (DemoWorld)
	match id:
		&"officer":
			# Этап 5 расширения: короткий разговор, выход свободный; миссию не трогает.
			_kind = &"officer"
			_open_chain(QuestLines.OFFICER_CHAIN, [
				{"id": &"close", "text": QuestLines.BUTTON_OFFICER_LEAVE, "primary": true},
			], id)
			return
		&"account_officer":
			# «Военком» у автобуса (e01): два ответа, итог один.
			_kind = &"ride"
			_open_chain([QuestLines.ACCOUNT_OFFICER_ASK], [
				{"id": &"ride_no", "text": QuestLines.BUTTON_RIDE_NO, "primary": true},
				{"id": &"ride_near", "text": QuestLines.BUTTON_RIDE_NEAR},
			], id)
			return
		&"babka":
			if mission.can_turn_in():
				# Этап 9: цепочка при возврате; сама сдача — кнопкой на последней реплике.
				_kind = &"return"
				_open_chain(QuestLines.RETURN_CHAIN, [
					{"id": &"turn_in", "text": QuestLines.BUTTON_TURN_IN, "primary": true},
				], id)
				return
	var result := mission.interact(id)
	match result:
		MissionDirector.R_OFFER_DIALOG:
			_kind = &"offer"
			_open(QuestLines.BABKA, QuestLines.OFFER, [
				{"id": &"accept", "text": QuestLines.BUTTON_ACCEPT, "primary": true},
				{"id": &"decline", "text": QuestLines.BUTTON_DECLINE},
			], &"babka")
		MissionDirector.R_VENDOR_DIALOG:
			_kind = &"vendor"
			var specs := [
				{"id": &"buy", "text": QuestLines.BUTTON_BUY, "primary": true, "enabled": mission.can_buy_bread()},
				{"id": &"leave", "text": QuestLines.BUTTON_LEAVE},
			]
			var lines: Array = [{"speaker": QuestLines.VENDOR, "text": QuestLines.VENDOR_AGAIN, "portrait": &"vendor"}]
			if not vendor_chain_shown:
				vendor_chain_shown = true
				lines = QuestLines.VENDOR_CHAIN.duplicate()
			# COINS-01: денег меньше цены — последняя реплика продавщицы — отказ с подсказкой, «КУПИТЬ ХЛЕБ» выключена.
			if mission.money_missing() > 0:
				lines.append({"speaker": QuestLines.VENDOR, "text": CoinLines.vendor_short(mission.money_missing()), "portrait": &"vendor"})
			_open_chain(lines, specs, &"vendor")
		MissionDirector.R_TURN_IN:
			_turn_in_shown()
		MissionDirector.R_BABKA_IDLE:
			_kind = &"idle"
			var line := QuestLines.IDLE_DONE if mission.state == MissionDirector.COMPLETE else QuestLines.IDLE
			_open(QuestLines.BABKA, line, [{"id": &"close", "text": QuestLines.BUTTON_CLOSE, "primary": true}], &"babka")

func _on_choice(id: StringName) -> void:
	match id:
		&"accept":
			if mission.accept():
				accept_player.play()
		&"decline":
			mission.decline()
		&"buy":
			if not mission.buy_bread():
				return  # покупка недоступна — диалог остаётся открытым
		&"ride_no", &"ride_near":
			# Любой ответ — один итог; диалог остаётся открытым до «Я ПЕШКОМ».
			dialog.open_chain([QuestLines.ACCOUNT_OFFICER_REPLY], [
				{"id": &"close", "text": QuestLines.BUTTON_RIDE_LEAVE, "primary": true},
			])
			return
		&"turn_in":
			# Единственная команда сдачи — interact(&"babka") директора (C5); результат решает он.
			if mission.interact(&"babka") == MissionDirector.R_TURN_IN:
				dialog.close()
				_turn_in_shown()
				return
		&"close":
			pass
	_close()

func _on_bread_received() -> void:
	_toast_left = TOAST_SECONDS

## Одна композиция как на кадре 10: реплика над Бабкой + панель финала внизу (HUD), без второй панели.
func _turn_in_shown() -> void:
	_kind = &"thanks"
	world.camera_rig.shoulder = 0.0
	_show_thanks(true)
	_pop_3d(thanks_back)
	_thanks_left = QuestLines.THANKS_PAUSE
	dialog.play_voice(&"babka")
	_face(&"babka")
	_block()

# --- блокировка ввода ---

func _open(speaker: String, text: String, specs: Array, portrait: StringName) -> void:
	_open_chain([{"speaker": speaker, "text": text, "portrait": portrait}], specs, portrait)

func _open_chain(lines: Array, specs: Array, partner: StringName) -> void:
	dialog.open_chain(lines, specs)
	world.camera_rig.shoulder = DIALOG_SHOULDER
	_face(partner)
	_block()

## Собеседник поворачивается к Илюше на время диалога (POLISH-02, п. 21).
func _face(id: StringName) -> void:
	var npc: Node = _npc_for(id)
	if npc and npc.has_method("look_at_target"):
		npc.look_at_target(world.player)

func _unface() -> void:
	var npcs: Array = [world.babka, world.vendor]
	for id in _observer_zones:
		npcs.append(_npc_for(id))
	for npc in npcs:
		if npc and npc.has_method("stop_looking"):
			npc.stop_looking()

## P2-3: после разговора — защита OFFICER_GRACE с, полицейский сразу отворачивается на угол без Илюши.
func _release_officer() -> void:
	if world.get("stealth") != null and world.stealth.has_method("grant_grace"):
		world.stealth.grant_grace(OFFICER_GRACE)
	var npc: Node = _npc_for(&"officer")
	if npc and npc.has_method("turn_away_from"):
		npc.turn_away_from(world.player, OFFICER_GRACE)

func _npc_for(id: StringName) -> Node:
	match id:
		&"babka":
			return world.babka
		&"vendor":
			return world.vendor
	var zone: Interactable = _observer_zones.get(id)
	return zone.get_parent() if zone else null

func _block() -> void:
	world.ui_blocking = true
	world.player.input_enabled = false
	wants_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## «ЗАКРЫТЬ» на панели финала: пузыри гаснут, открывается карточка «Конец демо» (HUD).
## Ввод остаётся заблокирован, пока игрок не выберет «ЕЩЁ РАЗ», «В МЕНЮ» или «ПОГУЛЯТЬ».
func _on_completion_closed() -> void:
	if _kind != &"thanks":
		return
	if hud == null or not hud.has_method("show_end_card"):
		_close()
		return
	_kind = &"end"
	_show_thanks(false)
	world.camera_rig.shoulder = 0.0
	_unface()
	hud.show_end_card()

## «ПОГУЛЯТЬ» на карточке «Конец демо»: вернуть управление.
func _on_end_closed() -> void:
	if _kind == &"end":
		_close()

func _close() -> void:
	var was: StringName = _kind
	dialog.close()
	world.camera_rig.shoulder = 0.0
	_show_thanks(false)
	_unface()
	_kind = &""
	if was == &"officer":
		_release_officer()
	world.ui_blocking = false
	if world.control_mode == &"on_foot":
		world.player.input_enabled = true
	wants_mouse_captured = not get_tree().paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED

# --- маркер над Бабкой ---

func _build_marker() -> void:
	marker = Label3D.new()
	marker.name = "BabkaMarker"
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = false
	marker.pixel_size = 0.006
	marker.font_size = 128
	marker.outline_size = 24
	marker.modulate = Color(1.0, 0.85, 0.1)
	marker.outline_modulate = Color(0.12, 0.10, 0.08)
	marker.position = Vector3(0, MARKER_Y, 0)
	marker.visible = false
	world.get_node("Babka").add_child(marker)
	# Пузыри реплики (кадр 10): бумажная подложка с хвостиком к Бабке, текст поверх неё. Второй — тоже с хвостиком, на
	# месте первого; первый тогда поднимается над ним и теряет хвостик (_stack_thanks).
	var first := _build_bubble("ThanksBubble", QuestLines.THANKS, true)
	thanks_back = first[0]
	thanks_bubble = first[1]
	_thanks_tail_texture = thanks_back.texture
	var font := DialogPanelScript.ui_font()
	_thanks_plain_texture = _bubble_texture(font.get_string_size(QuestLines.THANKS, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT), 0.0)
	var second := _build_bubble("ThanksAfterBubble", QuestLines.THANKS_AFTER, true)
	thanks_after_back = second[0]
	thanks_after_bubble = second[1]
	# Кончик хвостика — на высоте BUBBLE_Y, над шапкой Бабки.
	thanks_after_back.position = Vector3(0, BUBBLE_Y + _bubble_height(thanks_after_back) * 0.5, 0)
	_thanks_low_y = BUBBLE_Y + _bubble_height(thanks_back) * 0.5
	_thanks_high_y = thanks_after_back.position.y + _bubble_height(thanks_after_back) * 0.5 + BUBBLE_GAP \
		+ _thanks_plain_texture.get_height() * thanks_back.pixel_size * 0.5
	_stack_thanks(false)

## Первый пузырь: один — на месте с хвостиком; под ним второй — выше второго, без хвостика (текст по центру подложки).
func _stack_thanks(stacked: bool) -> void:
	thanks_back.texture = _thanks_plain_texture if stacked else _thanks_tail_texture
	thanks_back.position = Vector3(0, _thanks_high_y if stacked else _thanks_low_y, 0)
	thanks_bubble.position = Vector3(0, 0.0 if stacked else BUBBLE_TAIL * 0.5 * BUBBLE_PIXEL, 0)

func _bubble_height(back: Sprite3D) -> float:
	return back.texture.get_height() * back.pixel_size

## Подложка и текст пузыря над Бабкой. Шрифт — тот же, что у интерфейса (gui/theme/custom_font).
func _build_bubble(node_name: String, text: String, with_tail: bool) -> Array:
	var font := DialogPanelScript.ui_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT)
	var tail := BUBBLE_TAIL if with_tail else 0.0
	var back := Sprite3D.new()
	back.name = node_name + "Back"
	back.texture = _bubble_texture(text_size, tail)
	back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	back.no_depth_test = true
	back.shaded = false
	back.fixed_size = false
	back.pixel_size = BUBBLE_PIXEL * BUBBLE_DOWNSCALE
	back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	back.render_priority = 1
	back.visible = false
	world.get_node("Babka").add_child(back)
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = BUBBLE_PIXEL
	label.font = font
	label.font_size = BUBBLE_FONT
	label.outline_size = 0
	label.modulate = INK
	label.render_priority = 2
	# Текст — в середине тела пузыря: оно выше центра подложки на половину хвостика.
	label.position = Vector3(0, tail * 0.5 * BUBBLE_PIXEL, 0)
	label.visible = false
	back.add_child(label)
	return [back, label]

func _show_thanks(on: bool) -> void:
	thanks_back.visible = on
	thanks_bubble.visible = on
	if not on:
		thanks_after_back.visible = false
		thanks_after_bubble.visible = false
		_thanks_left = 0.0
		_stack_thanks(false)

## Бумажный пузырь: скруглённый прямоугольник с чернильной каймой и хвостиком вниз-влево (tail 0 — без хвостика).
## Рисуется один раз по пикселям в уменьшенном разрешении (BUBBLE_DOWNSCALE), фильтр сглаживает край.
func _bubble_texture(text_size: Vector2, tail_px: float) -> ImageTexture:
	var k := 1.0 / BUBBLE_DOWNSCALE
	var body := Vector2(text_size.x + 2.0 * BUBBLE_PAD, text_size.y + 2.0 * BUBBLE_PAD) * k
	var tail := tail_px * k
	var w := int(ceil(body.x)) + 4
	var h := int(ceil(body.y + tail)) + 4
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var radius := 14.0 * k
	var border := 7.0 * k
	var half := body * 0.5
	var center := Vector2(w * 0.5, 2.0 + half.y)
	# Хвостик — треугольник от низа пузыря вниз-влево.
	var t0 := Vector2(center.x - body.x * 0.16, center.y + half.y - border)
	var t1 := Vector2(center.x - body.x * 0.02, center.y + half.y - border)
	var t2 := Vector2(center.x - body.x * 0.22, center.y + half.y + tail - 1.0)
	var tri := PackedVector2Array([t0, t1, t2])
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - center).abs() - half + Vector2(radius, radius)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var in_tail := tail > 0.0 and Geometry2D.is_point_in_polygon(p, tri)
			if d <= -border or (in_tail and d > -border and _tail_inner(p, tri, border)):
				image.set_pixel(x, y, PAPER)
			elif d <= 0.0 or in_tail:
				image.set_pixel(x, y, INK)
	return ImageTexture.create_from_image(image)

## Внутренняя часть хвостика: точка дальше border от двух его боковых сторон.
func _tail_inner(p: Vector2, tri: PackedVector2Array, border: float) -> bool:
	for edge in [[tri[1], tri[2]], [tri[2], tri[0]]]:
		var closest := Geometry2D.get_closest_point_to_segment(p, edge[0], edge[1])
		if closest.distance_to(p) < border:
			return false
	return true

## «Выпрыгивание» 3D-маркера: масштаб от 0,3 до 1 с перелётом (POLISH-02, п. 10).
func _pop_3d(node: Node3D) -> void:
	node.scale = Vector3.ONE * 0.3
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

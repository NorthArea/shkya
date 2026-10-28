extends Node
## QuestFlow (QUEST-01): связывает зоны Бабки и продавщицы, KioskZone, диалоги и маркеры с MissionDirector.
## Состояния и проверки — только в MissionDirector (C5); здесь команды, диалоги, `!`/`?` и тост.
## Мир читает отсюда toast_text() для HUD (C6). Владелец файла — QUEST-01.
##
## Вход в машину сюда не входит: его сообщает мир через mission.notify_entered_car() (DRIVE-01).
## POLISH-02: сообщает директору, с кем Илюша рядом (текст задачи по ситуации), поворачивает собеседника
## к Илюше, после панели финала открывает карточку «Конец демо» (HUD), играет короткий сигнал на «ПРИНЯТЬ».

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const ACCEPT_SOUND := preload("res://assets/audio/quest_accept.wav")
const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const POP_SECONDS := 0.15

const TOAST_SECONDS := 2.0
const MARKER_Y := 2.62   # над шапкой Бабки: верх облика 2,07 м при height_m 2,17 (ART-01, PLAY-02)
const DIALOG_SHOULDER := 1.3  # м: камера вбок на время диалога, собеседник виден из-за Илюши (кадр 07)
const TOAST_TEXT := "ХЛЕБ +1"

const LINE_OFFER := "Илюша, сходи за хлебом в киоск"
const LINE_VENDOR := "Батон? 35 рублей"
const LINE_THANKS := "Спасибо, Илюша"
## Обычная реплика Бабки (babka_idle): пока хлеба нет — напоминание, после сдачи — прощание.
const LINE_IDLE := "Хлеб не забудь, Илюша"
const LINE_IDLE_DONE := "Иди погрейся, Илюша"
## Пузырь «Спасибо, Илюша»: размер шрифта и пикселя текста, поля и хвостик (в пикселях текста), высота над Бабкой.
const BUBBLE_FONT := 80
const BUBBLE_PIXEL := 0.0035
const BUBBLE_PAD := 34.0
const BUBBLE_TAIL := 56.0
const BUBBLE_DOWNSCALE := 2.0
const BUBBLE_Y := 2.55

var world: Node
var mission: MissionDirector
var dialog: DialogPanel
var marker: Label3D
var thanks_bubble: Label3D
## Подложка пузыря «Спасибо, Илюша» (кадр 10): бумажный пузырь с хвостиком, текст поверх.
var thanks_back: Sprite3D
var hud: Node
var accept_player: AudioStreamPlayer

## Что QuestFlow попросил у мыши (в headless Input.mouse_mode не отражает запрос).
var wants_mouse_captured := true
var _toast_left := 0.0
var _kind: StringName = &""
var _marker_time := 0.0
var _marker_symbol := ""

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

func toast_text() -> String:
	return TOAST_TEXT if _toast_left > 0.0 else ""

## Открыт диалог или панель сдачи: ввод Илюши остановлен.
func is_dialog_open() -> bool:
	return _kind != &""

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

func _physics_process(_delta: float) -> void:
	# Прибытие: Илюша или машина на площадке киоска, пока миссия ждёт прибытия.
	if mission.state == MissionDirector.DRIVE_TO_KIOSK and world.kiosk_zone.is_occupied():
		mission.notify_arrived_kiosk()
	mission.set_nearby(_nearby())

## С кем Илюша рядом: собеседник открытого диалога или ближайшая доступная зона E пешком.
func _nearby() -> StringName:
	match _kind:
		&"offer", &"idle", &"thanks":
			return &"babka"
		&"vendor":
			return &"vendor"
		&"end":
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
	var result := mission.interact(id)
	match result:
		MissionDirector.R_OFFER_DIALOG:
			_kind = &"offer"
			_open("БАБКА", LINE_OFFER, [
				{"id": &"accept", "text": "ПРИНЯТЬ", "primary": true},
				{"id": &"decline", "text": "ОТКАЗАТЬСЯ"},
			], &"babka")
		MissionDirector.R_VENDOR_DIALOG:
			_kind = &"vendor"
			_open("ПРОДАВЩИЦА", LINE_VENDOR, [
				{"id": &"buy", "text": "КУПИТЬ ХЛЕБ", "primary": true, "enabled": mission.can_buy_bread()},
				{"id": &"leave", "text": "УЙТИ"},
			], &"vendor")
		MissionDirector.R_TURN_IN:
			# Одна композиция как на кадре 10: реплика над Бабкой + панель финала внизу (HUD), без второй панели.
			_kind = &"thanks"
			_show_thanks(true)
			_pop_3d(thanks_back)
			dialog.play_voice(&"babka")
			_face(&"babka")
			_block()
		MissionDirector.R_BABKA_IDLE:
			_kind = &"idle"
			var line := LINE_IDLE_DONE if mission.state == MissionDirector.COMPLETE else LINE_IDLE
			_open("БАБКА", line, [{"id": &"close", "text": "ЗАКРЫТЬ", "primary": true}], &"babka")

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
		&"close":
			pass
	_close()

func _on_bread_received() -> void:
	_toast_left = TOAST_SECONDS

# --- блокировка ввода ---

func _open(speaker: String, text: String, specs: Array, portrait: StringName) -> void:
	dialog.open(speaker, text, specs, portrait)
	world.camera_rig.shoulder = DIALOG_SHOULDER
	_face(portrait)
	_block()

## Собеседник поворачивается к Илюше на время диалога (POLISH-02, п. 21).
func _face(id: StringName) -> void:
	var npc: Node = world.babka if id == &"babka" else world.vendor
	if npc.has_method("look_at_target"):
		npc.look_at_target(world.player)

func _unface() -> void:
	for npc in [world.babka, world.vendor]:
		if npc.has_method("stop_looking"):
			npc.stop_looking()

func _block() -> void:
	world.ui_blocking = true
	world.player.input_enabled = false
	wants_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## «ЗАКРЫТЬ» на панели финала: пузырь гаснет, открывается карточка «Конец демо» (HUD).
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
	dialog.close()
	world.camera_rig.shoulder = 0.0
	_show_thanks(false)
	_unface()
	_kind = &""
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
	# Пузырь реплики (кадр 10): бумажная подложка с хвостиком к Бабке, текст поверх неё.
	# Шрифт — тот же, что у интерфейса (gui/theme/custom_font), по нему считается подложка.
	var font := DialogPanelScript.ui_font()
	var text_size := font.get_string_size(LINE_THANKS, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT)
	thanks_back = Sprite3D.new()
	thanks_back.name = "ThanksBubbleBack"
	thanks_back.texture = _bubble_texture(text_size)
	thanks_back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	thanks_back.no_depth_test = true
	thanks_back.shaded = false
	thanks_back.fixed_size = false
	thanks_back.pixel_size = BUBBLE_PIXEL * BUBBLE_DOWNSCALE
	thanks_back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	thanks_back.render_priority = 1
	# Кончик хвостика — на высоте BUBBLE_Y, над шапкой Бабки.
	thanks_back.position = Vector3(0, BUBBLE_Y + thanks_back.texture.get_height() * thanks_back.pixel_size * 0.5, 0)
	thanks_back.visible = false
	world.get_node("Babka").add_child(thanks_back)
	thanks_bubble = Label3D.new()
	thanks_bubble.name = "ThanksBubble"
	thanks_bubble.text = LINE_THANKS
	thanks_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	thanks_bubble.no_depth_test = true
	thanks_bubble.pixel_size = BUBBLE_PIXEL
	thanks_bubble.font = font
	thanks_bubble.font_size = BUBBLE_FONT
	thanks_bubble.outline_size = 0
	thanks_bubble.modulate = INK
	thanks_bubble.render_priority = 2
	# Текст — в середине тела пузыря: оно выше центра подложки на половину хвостика.
	thanks_bubble.position = Vector3(0, BUBBLE_TAIL * 0.5 * BUBBLE_PIXEL, 0)
	thanks_bubble.visible = false
	thanks_back.add_child(thanks_bubble)

func _show_thanks(on: bool) -> void:
	thanks_back.visible = on
	thanks_bubble.visible = on

## Бумажный пузырь: скруглённый прямоугольник с чернильной каймой и хвостиком вниз-влево.
## Рисуется один раз по пикселям в уменьшенном разрешении (BUBBLE_DOWNSCALE), фильтр сглаживает край.
func _bubble_texture(text_size: Vector2) -> ImageTexture:
	var k := 1.0 / BUBBLE_DOWNSCALE
	var body := Vector2(text_size.x + 2.0 * BUBBLE_PAD, text_size.y + 2.0 * BUBBLE_PAD) * k
	var tail := BUBBLE_TAIL * k
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
			var in_tail := Geometry2D.is_point_in_polygon(p, tri)
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

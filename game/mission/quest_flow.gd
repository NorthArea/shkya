extends Node
## QuestFlow (QUEST-01): связывает зоны Бабки и продавщицы, KioskZone, диалоги и маркеры с MissionDirector.
## Состояния и проверки — только в MissionDirector (C5); здесь команды, диалоги, `!`/`?` и тост.
## Мир читает отсюда toast_text() для HUD (C6). Владелец файла — QUEST-01.
##
## Вход в машину сюда не входит: его сообщает мир через mission.notify_entered_car() (DRIVE-01).

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")

const TOAST_SECONDS := 2.0
const TOAST_TEXT := "ХЛЕБ +1"

const LINE_OFFER := "Илюша, сходи за хлебом в киоск"
const LINE_VENDOR := "Батон? 35 рублей"
const LINE_THANKS := "Спасибо, Илюша"
## Обычная реплика Бабки (babka_idle): пока хлеба нет — напоминание, после сдачи — прощание.
const LINE_IDLE := "Хлеб не забудь, Илюша"
const LINE_IDLE_DONE := "Иди погрейся, Илюша"

var world: Node
var mission: MissionDirector
var dialog: DialogPanel
var marker: Label3D
var thanks_bubble: Label3D
var hud: Node

## Что QuestFlow попросил у мыши (в headless Input.mouse_mode не отражает запрос).
var wants_mouse_captured := true
var _toast_left := 0.0
var _kind: StringName = &""
var _marker_time := 0.0

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
	_marker_time += delta
	marker.position.y = 2.75 + sin(_marker_time * 3.0) * 0.08

func _physics_process(_delta: float) -> void:
	# Прибытие: Илюша или машина на площадке киоска, пока миссия ждёт прибытия.
	if mission.state == MissionDirector.DRIVE_TO_KIOSK and world.kiosk_zone.is_occupied():
		mission.notify_arrived_kiosk()

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
			thanks_bubble.visible = true
			_block()
		MissionDirector.R_BABKA_IDLE:
			_kind = &"idle"
			var line := LINE_IDLE_DONE if mission.state == MissionDirector.COMPLETE else LINE_IDLE
			_open("БАБКА", line, [{"id": &"close", "text": "ЗАКРЫТЬ", "primary": true}], &"babka")

func _on_choice(id: StringName) -> void:
	match id:
		&"accept":
			mission.accept()
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
	_block()

func _block() -> void:
	world.ui_blocking = true
	world.player.input_enabled = false
	wants_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_completion_closed() -> void:
	if _kind == &"thanks":
		_close()

func _close() -> void:
	dialog.close()
	thanks_bubble.visible = false
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
	marker.position = Vector3(0, 2.75, 0)
	marker.visible = false
	world.get_node("Babka").add_child(marker)
	thanks_bubble = Label3D.new()
	thanks_bubble.name = "ThanksBubble"
	thanks_bubble.text = LINE_THANKS
	thanks_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	thanks_bubble.no_depth_test = true
	thanks_bubble.pixel_size = 0.0035
	thanks_bubble.font_size = 96
	thanks_bubble.outline_size = 20
	thanks_bubble.outline_modulate = Color(0.12, 0.10, 0.08)
	thanks_bubble.position = Vector3(0, 3.1, 0)
	thanks_bubble.visible = false
	world.get_node("Babka").add_child(thanks_bubble)

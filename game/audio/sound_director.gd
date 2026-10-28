extends Node
## SoundDirector (POLISH-01): шаги по снегу, мотор и каша под колёсами «Лады», двери, интерфейс, звон хлеба,
## финал и фон двора. Только слушает мир, машину, миссию и диалоги — ничем не управляет.
## Звуки синтезированы tools/generate_audio.py (собственная генерация, см. assets/README.md).
## Мотор, каша и фон двора зациклены при импорте (`edit/loop_mode=2` в .import).
## EXT-01 (L): радио при первой посадке в «Жигули» за мир — приглушённый «радийный» бубнёж из машины
## и строка субтитра внизу экрана (QuestLines.RADIO); управление не блокирует.

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const STEP_DISTANCE := 0.75
const STEPS: Array[AudioStream] = [
	preload("res://assets/audio/step_snow_1.wav"), preload("res://assets/audio/step_snow_2.wav"),
	preload("res://assets/audio/step_snow_3.wav"), preload("res://assets/audio/step_snow_4.wav"),
]
const ENGINE := preload("res://assets/audio/engine_idle_loop.wav")
const SKID := preload("res://assets/audio/slush_skid_loop.wav")
const DOOR_OPEN := preload("res://assets/audio/door_open.wav")
const DOOR_CLOSE := preload("res://assets/audio/door_close.wav")
const UI_CLICK := preload("res://assets/audio/ui_click.wav")
const BREAD := preload("res://assets/audio/bread_get.wav")
const COMPLETE := preload("res://assets/audio/quest_complete.wav")
const AMBIENCE := preload("res://assets/audio/yard_ambience_loop.wav")
const RADIO := preload("res://assets/audio/radio_mumble.wav")
const RADIO_DELAY := 0.6  # с после хлопка двери, прежде чем «поймается» волна

## Счётчики для проверок: сколько раз сыграл каждый звук.
var played := {"step": 0, "door_open": 0, "door_close": 0, "ui": 0, "bread": 0, "complete": 0, "radio": 0}

var world: Node
var step_player: AudioStreamPlayer3D
var engine: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
var door: AudioStreamPlayer3D
var ui: AudioStreamPlayer
var chime: AudioStreamPlayer  # хлеб и финал — отдельно от щелчка, иначе щелчок кнопки обрывает звон
var ambience: AudioStreamPlayer
var radio: AudioStreamPlayer3D
var subtitle_layer: CanvasLayer
var subtitle_card: PanelContainer
var subtitle_label: Label
var _walked := 0.0
var _last_position := Vector3.INF
var _rng := RandomNumberGenerator.new()
var _radio_delay := -1.0
var _subtitle_left := 0.0

func _ready() -> void:
	world = get_parent()
	# Ссылки DemoWorld (player, car, mission) готовы только после его собственного _ready.
	world.ready.connect(_setup, CONNECT_ONE_SHOT)

func _setup() -> void:
	step_player = _player_3d(world.player, -6.0)
	engine = _player_3d(world.car, -4.0, ENGINE)
	skid = _player_3d(world.car, -80.0, SKID)
	door = _player_3d(world.car, -2.0)
	radio = _player_3d(world.car, -9.0, RADIO)  # тише мотора: радио «из-под панели»
	ui = AudioStreamPlayer.new()
	ui.volume_db = -6.0
	add_child(ui)
	chime = AudioStreamPlayer.new()
	chime.volume_db = -6.0
	add_child(chime)
	ambience = AudioStreamPlayer.new()
	ambience.stream = AMBIENCE
	ambience.volume_db = -12.0
	add_child(ambience)
	ambience.play()
	_build_subtitle()
	world.car.driver_entered.connect(func(_d):
		_one_shot(door, DOOR_CLOSE, "door_close")
		if played["radio"] == 0 and _radio_delay < 0.0:
			_radio_delay = RADIO_DELAY)
	world.car.driver_exited.connect(func(_d):
		_one_shot(door, DOOR_OPEN, "door_open")
		# Радио в машине: с выходом водителя бубнёж и субтитр гаснут, второго раза за мир нет.
		radio.stop()
		_radio_delay = -1.0
		_subtitle_left = 0.0
		subtitle_card.visible = false)
	world.mission.bread_received.connect(func(): _one_shot(chime, BREAD, "bread"))
	world.mission.quest_completed.connect(func(_xp): _one_shot(chime, COMPLETE, "complete"))
	var flow := world.get_node_or_null("QuestFlow")
	if flow and flow.get("dialog") and flow.dialog.has_signal("choice"):
		flow.dialog.choice.connect(func(_id): _one_shot(ui, UI_CLICK, "ui"))
		if flow.dialog.has_signal("advanced"):
			flow.dialog.advanced.connect(func(_i): _one_shot(ui, UI_CLICK, "ui"))

## Текст субтитра радио, пока он на экране ("" — нет).
func radio_text() -> String:
	return subtitle_label.text if _subtitle_left > 0.0 else ""

func _physics_process(delta: float) -> void:
	if not engine:
		return
	_footsteps()
	_car_sounds(delta)
	_radio(delta)

## Радио один раз за мир: бубнёж из машины и субтитр, пока звучит (плюс хвост на дочитать).
func _radio(delta: float) -> void:
	if _radio_delay >= 0.0:
		_radio_delay -= delta
		if _radio_delay < 0.0 and world.car.driver:
			_one_shot(radio, RADIO, "radio")
			subtitle_label.text = QuestLines.RADIO
			_subtitle_left = QuestLines.RADIO_SECONDS
			subtitle_card.visible = true
			DialogPanelScript.pop(subtitle_card, 0.6)
	if _subtitle_left > 0.0:
		_subtitle_left -= delta
		if _subtitle_left <= 0.0:
			subtitle_card.visible = false

## Строка субтитра внизу экрана, над подсказкой: тёмная плашка, светлый текст в одну-две строки.
func _build_subtitle() -> void:
	subtitle_layer = CanvasLayer.new()
	subtitle_layer.name = "RadioSubtitle"
	subtitle_layer.layer = 7
	add_child(subtitle_layer)
	subtitle_card = PanelContainer.new()
	subtitle_card.name = "SubtitleCard"
	subtitle_card.visible = false
	subtitle_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.72)
	style.set_corner_radius_all(4)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	subtitle_card.add_theme_stylebox_override("panel", style)
	subtitle_card.anchor_left = 0.5
	subtitle_card.anchor_right = 0.5
	subtitle_card.anchor_top = 1.0
	subtitle_card.anchor_bottom = 1.0
	subtitle_card.offset_left = -620
	subtitle_card.offset_right = 620
	subtitle_card.offset_top = -190
	subtitle_card.offset_bottom = -110
	subtitle_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle_layer.add_child(subtitle_card)
	subtitle_label = Label.new()
	subtitle_label.name = "Subtitle"
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 30)
	subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_card.add_child(subtitle_label)

func _footsteps() -> void:
	var player: CharacterBody3D = world.player
	var position := player.global_position
	if world.control_mode == &"on_foot" and player.is_on_floor() and _last_position != Vector3.INF:
		var moved := Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
		if moved < 1.0:  # телепорт не считается шагами
			_walked += moved
	else:
		_walked = 0.0
	_last_position = position
	if _walked >= STEP_DISTANCE:
		_walked = 0.0
		step_player.stream = STEPS[_rng.randi() % STEPS.size()]
		step_player.pitch_scale = _rng.randf_range(0.9, 1.1)
		step_player.play()
		played["step"] += 1

func _car_sounds(_delta: float) -> void:
	var car = world.car
	var ratio := clampf(car.speed_kmh() / 80.0, 0.0, 1.0)
	if car.driver:
		if not engine.playing:
			engine.play()
		engine.pitch_scale = 0.8 + ratio * 1.6
		engine.volume_db = lerpf(-8.0, -1.0, ratio)
	elif engine.playing:
		engine.stop()
	var slide := clampf((car.lateral_speed - 1.0) / 5.0, 0.0, 1.0)
	if slide > 0.02:
		skid.volume_db = linear_to_db(slide) - 4.0
		if not skid.playing:
			skid.play()
	elif skid.playing:
		skid.stop()

func _player_3d(parent: Node3D, volume: float, stream: AudioStream = null) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.volume_db = volume
	player.unit_size = 6.0
	player.stream = stream
	parent.add_child(player)
	return player

func _one_shot(player: Node, stream: AudioStream, key: String) -> void:
	player.stream = stream
	player.play()
	played[key] += 1

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
	_setup_ambient()   # CITY-01 (A): слои фона, живность, сигналы машин

## Текст субтитра радио, пока он на экране ("" — нет).
func radio_text() -> String:
	return subtitle_label.text if _subtitle_left > 0.0 else ""

func _physics_process(delta: float) -> void:
	if not engine:
		return
	_footsteps()
	_car_sounds(delta)
	_radio(delta)
	_traffic_sounds()
	_ambient_sounds(delta)   # CITY-01 (A)

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

## EXT-02 (HIDE_SPOTS.md раздел 11): гэг укрытия строкой субтитра — по две строки на экран, каждая пара seconds,
## затем плашка гаснет. Управление не блокирует; радио, если звучит, уступает строку. Повторный вызов заменяет
## текущий гэг. Состояние — твин в метаданных узла (метод добавлен без новых полей).
func show_gag(lines: Array, seconds := 2.5) -> void:
	if subtitle_card == null or lines.is_empty():
		return
	var old: Variant = get_meta(&"gag_tween") if has_meta(&"gag_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	_subtitle_left = 0.0
	var tween := create_tween()
	set_meta(&"gag_tween", tween)
	for i in range(0, lines.size(), 2):
		var page := "\n".join(PackedStringArray(lines.slice(i, i + 2)))
		tween.tween_callback(func():
			subtitle_label.text = page
			subtitle_card.visible = true
			DialogPanelScript.pop(subtitle_card, 0.6))
		tween.tween_interval(seconds)
	tween.tween_callback(func():
		subtitle_card.visible = false
		subtitle_label.text = "")

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

## Звук шагов выключен по решению владельца 28.10.2026 (вечер): счётчик шагов остаётся для тестов, звук не играет.
const FOOTSTEP_SOUND := false

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
		played["step"] += 1
		if FOOTSTEP_SOUND:
			step_player.stream = STEPS[_rng.randi() % STEPS.size()]
			step_player.pitch_scale = _rng.randf_range(0.9, 1.1)
			step_player.play()

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

# --- ARENA-01 (T): транспорт кольца ---
## Мотор машин и тихий гул троллейбуса — AudioStreamPlayer3D на корпусе, затухание по удалению, как у «Лады»;
## высота и громкость — от скорости. Двери троллейбуса на остановках — сигналы doors_opened / doors_closed.
## Транспорт находится по группе PathVehicle.GROUP и подключается при первом появлении (Traffic может прийти
## позже _setup). Звуки синтезированы tools/generate_audio.py.
const TROLLEY_HUM := preload("res://assets/audio/trolley_hum_loop.wav")
const TROLLEY_DOORS := preload("res://assets/audio/trolley_doors.wav")
const TRAFFIC_MAX_DISTANCE := 70.0

var _traffic_engines := {}   # PathVehicle → AudioStreamPlayer3D

func _traffic_sounds() -> void:
	for vehicle in get_tree().get_nodes_in_group(&"traffic_vehicles"):
		var player: AudioStreamPlayer3D = _traffic_engines.get(vehicle)
		if player == null:
			player = _attach_traffic(vehicle)
		var moving := clampf(float(vehicle.speed) / 9.0, 0.0, 1.0)
		if vehicle is Trolleybus:
			player.pitch_scale = 0.85 + 0.35 * moving
			player.volume_db = lerpf(-22.0, -15.0, moving)
		else:
			player.pitch_scale = 0.75 + 0.9 * moving
			player.volume_db = lerpf(-16.0, -9.0, moving)

func _attach_traffic(vehicle: Node3D) -> AudioStreamPlayer3D:
	var trolley := vehicle is Trolleybus
	var player := _player_3d(vehicle, -14.0, TROLLEY_HUM if trolley else ENGINE)
	player.name = "TrafficEngine"
	player.max_distance = TRAFFIC_MAX_DISTANCE
	player.play()
	_traffic_engines[vehicle] = player
	vehicle.tree_exiting.connect(func(): _traffic_engines.erase(vehicle), CONNECT_ONE_SHOT)
	if trolley:
		if not played.has("trolley_doors"):
			played["trolley_doors"] = 0
		var doors := _player_3d(vehicle, -6.0)
		doors.name = "TrolleyDoors"
		doors.max_distance = TRAFFIC_MAX_DISTANCE
		doors.position = Vector3(1.3, 1.5, 0.0)   # правый борт, к тротуару
		vehicle.doors_opened.connect(func(_i): _one_shot(doors, TROLLEY_DOORS, "trolley_doors"))
		vehicle.doors_closed.connect(func(_i): _one_shot(doors, TROLLEY_DOORS, "trolley_doors"))
	return player

# --- CITY-01 (A): фон живого города и живность ---
## Слои фона без затухания (2D): ветер с порывами и далёкий трафик — циклы под фоном двора и тише него.
## Музыка из окна — 3D-цикл у окна второго этажа H1 (двор), слышна только рядом. Хлопок двери подъезда — 3D у двери,
## раз в DOOR_SLAM_INTERVAL с (свой RandomNumberGenerator с фиксированным AMBIENT_SEED). Вороны и собака — 3D на их
## узлах по сигналам Ambient (crow_cawed, dog_barked). Сигнал машины кольца — 3D на корпусе: стоит перед препятствием
## (PathVehicle.blocked_time) дольше HORN_WAIT — короткий гудок, не чаще раза в HORN_COOLDOWN на машину; сигнал
## horn_sounded — для тех, кто хочет оглянуться (жители). Звуки — tools/generate_audio.py (синтез).
## Уровни, RMS файла + volume_db (3D — у источника, до затухания): ветер −24 − 14 = −38 дБ, трафик −26 − 14 = −40,
## музыка −24 − 12 = −36, вороны и собака −18 − 10 = −28, дверь подъезда −18 − 8 = −26, гудок −16 − 10 = −26.
## Для сравнения (PLAY-03): фон двора −32, сигналы квеста −23 … −25, мотор −18 … −11.
const WIND := preload("res://assets/audio/wind_gust_loop.wav")
const CITY_TRAFFIC := preload("res://assets/audio/distant_traffic_loop.wav")
const WINDOW_MUSIC := preload("res://assets/audio/window_music_loop.wav")
const CROW_CAWS: Array[AudioStream] = [preload("res://assets/audio/crow_caw_1.wav"), preload("res://assets/audio/crow_caw_2.wav")]
const DOG_BARK := preload("res://assets/audio/dog_bark.wav")
const DOOR_SLAM := preload("res://assets/audio/door_slam.wav")
const CAR_HORN := preload("res://assets/audio/car_horn_short.wav")
const WIND_DB := -14.0
const CITY_TRAFFIC_DB := -14.0
const MUSIC_DB := -12.0
const CROW_DB := -10.0
const DOG_DB := -10.0
const DOOR_SLAM_DB := -8.0
const HORN_DB := -10.0
const HORN_WAIT := 3.0
const HORN_COOLDOWN := 10.0
const DOOR_SLAM_INTERVAL := Vector2(60.0, 120.0)
const ENTRANCE_DOOR := Vector3(-40.0, 1.2, 107.8)   # дверь подъезда H1 (level_geometry: ENTRANCE_DOOR_X, ENTRANCE_WALL_Z)
const MUSIC_WINDOW := Vector3(-22.5, 4.4, 107.9)    # окно второго этажа H1 по сетке фасада (шаг 3 м, этаж 2,8 м)
const AMBIENT_SEED := 2911

signal horn_sounded(vehicle: Node3D)

var wind: AudioStreamPlayer
var city_traffic: AudioStreamPlayer
var window_music: AudioStreamPlayer3D
var door_slam: AudioStreamPlayer3D
var door_slam_times: Array[float] = []
var horn_times: Array = []   # [время, машина, blocked_time в момент гудка]
var _ambient_rng := RandomNumberGenerator.new()
var _ambient_clock := 0.0
var _next_door_slam := 0.0
var _ambient_node: Node
var _crow_players := {}   # ворона → AudioStreamPlayer3D
var _dog_player: AudioStreamPlayer3D
var _horn_players := {}   # PathVehicle → AudioStreamPlayer3D
var _last_horn := {}      # PathVehicle → время последнего гудка

func _setup_ambient() -> void:
	for key in ["crow", "dog", "door_slam", "horn"]:
		played[key] = 0
	_ambient_rng.seed = AMBIENT_SEED
	wind = _bed(WIND, WIND_DB, "WindBed")
	city_traffic = _bed(CITY_TRAFFIC, CITY_TRAFFIC_DB, "CityTrafficBed")
	window_music = AudioStreamPlayer3D.new()
	window_music.name = "WindowMusic"
	window_music.stream = WINDOW_MUSIC
	window_music.volume_db = MUSIC_DB
	window_music.unit_size = 3.0
	window_music.max_distance = 30.0
	window_music.position = MUSIC_WINDOW
	add_child(window_music)
	window_music.play()
	door_slam = AudioStreamPlayer3D.new()
	door_slam.name = "EntranceDoor"
	door_slam.volume_db = DOOR_SLAM_DB
	door_slam.unit_size = 6.0
	door_slam.max_distance = 50.0
	door_slam.position = ENTRANCE_DOOR
	add_child(door_slam)
	_next_door_slam = _ambient_rng.randf_range(DOOR_SLAM_INTERVAL.x, DOOR_SLAM_INTERVAL.y)
	_connect_ambient()

func _bed(stream: AudioStream, volume: float, node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	player.play()
	return player

## Ambient (LevelGeometry/Ambient) — по группе; может появиться позже, тогда подключится в _ambient_sounds.
func _connect_ambient() -> void:
	if _ambient_node and is_instance_valid(_ambient_node):
		return
	_ambient_node = get_tree().get_first_node_in_group(&"ambient")
	if _ambient_node == null:
		return
	_ambient_node.crow_cawed.connect(_on_crow_cawed)
	_ambient_node.dog_barked.connect(_on_dog_barked)

func _on_crow_cawed(crow: Node3D) -> void:
	var player: AudioStreamPlayer3D = _crow_players.get(crow)
	if player == null:
		player = _player_3d(crow, CROW_DB)
		player.name = "Caw"
		player.max_distance = 60.0
		_crow_players[crow] = player
	player.pitch_scale = 0.94 + 0.03 * float(crow.get_index() % 4)
	_one_shot(player, CROW_CAWS[played["crow"] % CROW_CAWS.size()], "crow")

func _on_dog_barked(dog: Node3D) -> void:
	if _dog_player == null:
		_dog_player = _player_3d(dog, DOG_DB)
		_dog_player.name = "Bark"
		_dog_player.max_distance = 45.0
		_dog_player.position = Vector3(0, 0.6, -0.4)
	_one_shot(_dog_player, DOG_BARK, "dog")

func _ambient_sounds(delta: float) -> void:
	if wind == null:
		return
	_ambient_clock += delta
	_connect_ambient()
	if _ambient_clock >= _next_door_slam:
		_next_door_slam = _ambient_clock + _ambient_rng.randf_range(DOOR_SLAM_INTERVAL.x, DOOR_SLAM_INTERVAL.y)
		door_slam.pitch_scale = _ambient_rng.randf_range(0.92, 1.05)
		door_slam_times.append(_ambient_clock)
		_one_shot(door_slam, DOOR_SLAM, "door_slam")
	for vehicle in get_tree().get_nodes_in_group(&"traffic_vehicles"):
		var waited: float = vehicle.blocked_time
		if waited <= HORN_WAIT:
			continue
		if _last_horn.has(vehicle) and _ambient_clock - float(_last_horn[vehicle]) < HORN_COOLDOWN:
			continue
		var player: AudioStreamPlayer3D = _horn_players.get(vehicle)
		if player == null:
			player = _player_3d(vehicle, HORN_DB)
			player.name = "Horn"
			player.max_distance = TRAFFIC_MAX_DISTANCE
			player.position = Vector3(0, 0.8, -1.5)
			player.pitch_scale = 0.8 if vehicle is Trolleybus else 1.0
			_horn_players[vehicle] = player
			vehicle.tree_exiting.connect(func():
				_horn_players.erase(vehicle)
				_last_horn.erase(vehicle), CONNECT_ONE_SHOT)
		_last_horn[vehicle] = _ambient_clock
		horn_times.append([_ambient_clock, vehicle, waited])
		_one_shot(player, CAR_HORN, "horn")
		horn_sounded.emit(vehicle)

# --- EXT-02 (E): бочка ---
## Дребезжание качения — 3D-цикл на Илюше, громкость и высота по скорости (стоя — тишина, плеер остановлен),
## как мотор «Лады»; «БУМ» удара о стену — разовый 3D на Илюше. Вызывает BarrelHideSpot: barrel_roll(ratio) каждый
## физический кадр, пока бочка занята (0 — остановить), barrel_bump() — при ударе (пауза ≥ 4 с — на стороне бочки).
## Гэги C05/C06 — общим show_gag(). Звуки — tools/generate_audio.py.
## Уровни, RMS файла + volume_db: качение −20 − 6 = −26 дБ на пределе 2,6 м/с, удар −16 − 2 = −18.
const BARREL_ROLL := preload("res://assets/audio/barrel_roll_loop.wav")
const BARREL_BUMP := preload("res://assets/audio/barrel_bump.wav")
const BARREL_ROLL_DB := -6.0
const BARREL_BUMP_DB := -2.0

var barrel_roll_player: AudioStreamPlayer3D
var barrel_bump_player: AudioStreamPlayer3D

## ratio 0…1 — скорость бочки к пределу; ≤ 0,02 — тишина.
func barrel_roll(ratio: float) -> void:
	if world == null or world.get("player") == null:
		return
	if barrel_roll_player == null:
		# Под DemoWorld (Node3D), не под Илюшей: к нему ничего не прикрепляется (инвариант DEMO_ACCEPTANCE 3, C2).
		barrel_roll_player = _player_3d(world, -80.0, BARREL_ROLL)
		barrel_roll_player.name = "BarrelRoll"
	barrel_roll_player.global_position = world.player.global_position + Vector3.UP * 0.45
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio > 0.02:
		barrel_roll_player.volume_db = BARREL_ROLL_DB + linear_to_db(ratio)
		barrel_roll_player.pitch_scale = 0.75 + 0.35 * ratio
		if not barrel_roll_player.playing:
			barrel_roll_player.play()
	elif barrel_roll_player.playing:
		barrel_roll_player.stop()

func barrel_bump() -> void:
	if world == null or world.get("player") == null:
		return
	if barrel_bump_player == null:
		barrel_bump_player = _player_3d(world, BARREL_BUMP_DB)   # под DemoWorld, не под Илюшей (инвариант DEMO 3)
		barrel_bump_player.name = "BarrelBump"
	barrel_bump_player.global_position = world.player.global_position + Vector3.UP * 0.45
	if not played.has("barrel_bump"):
		played["barrel_bump"] = 0
	_one_shot(barrel_bump_player, BARREL_BUMP, "barrel_bump")

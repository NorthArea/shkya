extends Node
## SoundDirector (POLISH-01): шаги по снегу, мотор и каша под колёсами «Лады», двери, интерфейс, звон хлеба,
## финал и фон двора. Только слушает мир, машину, миссию и диалоги — ничем не управляет.
## Звуки синтезированы tools/generate_audio.py (собственная генерация, см. assets/README.md).
## Мотор, каша и фон двора зациклены при импорте (`edit/loop_mode=2` в .import).
## RADIO-02: единый диктор новостей; уступает диалогам и гэгам,
## управление не блокируют. Полицейская рация и звуковой фон города независимы.

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const Layout = preload("res://game/world/layout.gd")
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
var _subtitle_left := 0.0
var _radio_caption := ""
var _radio_urgent := false
var _interrupted_radio_caption := ""
var _interrupted_radio_left := 0.0
## Первая погода звучит один раз за мир; played считает настоящие запуски голоса.
var radio_shown := 0

func _ready() -> void:
	world = get_parent()
	# Ссылки DemoWorld (player, car, mission) готовы только после его собственного _ready.
	world.ready.connect(_setup, CONNECT_ONE_SHOT)

func _setup() -> void:
	step_player = _player_3d(world.player, -6.0)
	engine = _player_3d(world.car, -4.0, ENGINE)
	skid = _player_3d(world.car, -80.0, SKID)
	door = _player_3d(world.car, -2.0)
	radio = _player_3d(world.car, -9.0, narrator_stream())  # тише мотора: радио «из-под панели»
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
		_one_shot(door, DOOR_CLOSE, "door_close"))
	world.car.driver_exited.connect(func(_d):
		_one_shot(door, DOOR_OPEN, "door_open")
		# При возвращении в машину дочитать остаток передачи.
		suspend_radio_voice())
	world.mission.bread_received.connect(func(): _one_shot(chime, BREAD, "bread"))
	world.mission.quest_completed.connect(func(_xp): _one_shot(chime, COMPLETE, "complete"))
	var flow := world.get_node_or_null("QuestFlow")
	if flow and flow.get("dialog") and flow.dialog.has_signal("choice"):
		flow.dialog.choice.connect(func(_id): _one_shot(ui, UI_CLICK, "ui"))
		if flow.dialog.has_signal("advanced"):
			flow.dialog.advanced.connect(func(_i): _one_shot(ui, UI_CLICK, "ui"))
	_setup_ambient()   # CITY-01 (A): слои фона, живность, сигналы машин
	_setup_coins()   # COINS-01: звон монеты
	_setup_punch()   # PUNCH-01: удар и дроны
	_setup_knock()   # KNOCK-01: сбитые «Ладой» жители
	_setup_break()   # BREAK-01: разрушаемые объекты, сигнализация, крышки
	_setup_drive02()   # DRIVE-02: колёса в снегу, скрип при заносе
	_setup_life()   # PEOPLE-03: занятия жителей и птицы
	_setup_car_radio()   # POLISH-03 C: радио «Лады» при езде

## Текст субтитра радио, пока он на экране ("" — нет).
func radio_text() -> String:
	return _radio_caption if _subtitle_left > 0.0 and subtitle_card.visible and not gag_playing() else ""

func _physics_process(delta: float) -> void:
	if not engine:
		return
	_footsteps()
	_car_sounds(delta)
	_radio(delta)
	_traffic_sounds()
	_ambient_sounds(delta)   # CITY-01 (A)
	_drone_sounds()   # PUNCH-01
	_knock_sounds()   # KNOCK-01
	_break_sounds()   # BREAK-01
	_drive02_sounds()   # DRIVE-02
	_life_sounds()   # PEOPLE-03

## Сначала предупреждение/диалог, затем радио. Управление остаётся у водителя.
func radio_available() -> bool:
	if world.ui_blocking or gag_playing() or get_tree().paused:
		return false
	var flow: Node = world.get_node_or_null("QuestFlow")
	return not (flow and flow.is_dialog_open())

func _radio(delta: float) -> void:
	if world.is_stealth_failing() or world.mission.state == MissionDirector.COMPLETE:
		suspend_radio_voice()
		_subtitle_left = 0.0
		return
	if not car_radio or not car_radio.music.news_enabled() or not radio_available():
		suspend_radio_voice()
		return
	if _subtitle_left > 0.0:
		if not subtitle_card.visible:
			subtitle_label.text = _radio_caption
			_subtitle_slot(false)
			subtitle_card.visible = true
		_subtitle_left = maxf(0.0, _subtitle_left - delta)
		if _subtitle_left <= 0.0:
			subtitle_card.visible = false
			if _radio_urgent and _interrupted_radio_left > 0.0:
				var caption := _interrupted_radio_caption
				var remaining := _interrupted_radio_left
				_interrupted_radio_caption = ""
				_interrupted_radio_left = 0.0
				_radio_urgent = false
				if _begin_radio_line(caption, remaining):
					_subtitle_left = remaining
			else:
				_radio_urgent = false
	if radio_text() != "":
		if not radio.playing:
			radio.play()
			played["radio"] += 1
	else:
		radio.stop()

## Собственная копия позволяет держать диктора на всём времени чтения субтитра,
## не меняя импортированный ресурс, который используют остальные звуки.
func narrator_stream() -> AudioStreamWAV:
	var stream := RADIO.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream

## Смена станции прячет эфир, сохраняя оставшееся время/порядок новостей.
func suspend_radio_voice() -> void:
	if radio:
		radio.stop()
	if car_radio:
		car_radio.suspend_voice()
	if subtitle_card and not gag_playing():
		subtitle_card.visible = false

## EXT-02 (HIDE_SPOTS.md раздел 11): гэг укрытия строкой субтитра — по две строки на экран, каждая пара seconds,
## затем плашка гаснет. Управление не блокирует; радио, если звучит, уступает строку. Приёмка P2-1: идущий гэг
## не перебивается — новый встаёт в очередь (не длиннее GAG_QUEUE_MAX, лишний старейший отбрасывается) и
## начинается после него. P3-7: гэг — в верхней полосе экрана (GAG_SLOT_TOP), не на укрытии у Илюши.
const GAG_QUEUE_MAX := 2
const GAG_SLOT_TOP := 320.0   # ниже тостов (стелс-тост до y 305, «ХЛЕБ +1» до 260) и карточки задачи (до ≈ 190)
var _gag_tween: Tween
var _gag_queue: Array = []   # [[lines, seconds], …]
## Для тестов: сколько гэгов начато показом и сколько выброшено из переполненной очереди.
var gags_started := 0
var gags_dropped := 0

func show_gag(lines: Array, seconds := 2.5) -> void:
	if subtitle_card == null or lines.is_empty():
		return
	if gag_playing():
		_gag_queue.append([lines, seconds])
		while _gag_queue.size() > GAG_QUEUE_MAX:
			_gag_queue.pop_front()
			gags_dropped += 1
		return
	_play_gag(lines, seconds)

## Гэг на экране (идёт его твин).
func gag_playing() -> bool:
	return _gag_tween != null and _gag_tween.is_valid()

func gag_queue_size() -> int:
	return _gag_queue.size()

## Сбросить непоказанные гэги (новая попытка); идущий дочитывается.
func clear_gag_queue() -> void:
	_gag_queue.clear()

func _play_gag(lines: Array, seconds: float) -> void:
	gags_started += 1
	_subtitle_slot(true)
	var tween := create_tween()
	_gag_tween = tween
	for i in range(0, lines.size(), 2):
		var page := "\n".join(PackedStringArray(lines.slice(i, i + 2)))
		tween.tween_callback(func():
			subtitle_label.text = page
			subtitle_card.visible = true
			DialogPanelScript.pop(subtitle_card, 0.6))
		tween.tween_interval(page_seconds(page, seconds))
	tween.tween_callback(_gag_finished)

## TEXT-01: страница гэга висит не меньше времени чтения (QuestLines.read_seconds), даже если просили меньше.
static func page_seconds(page: String, seconds: float) -> float:
	return maxf(seconds, QuestLines.read_seconds(page.replace("\n", " ")))

func _gag_finished() -> void:
	_gag_tween = null
	subtitle_card.visible = false
	subtitle_label.text = ""
	_subtitle_slot(false)
	if not _gag_queue.is_empty():
		var next: Array = _gag_queue.pop_front()
		_play_gag(next[0], next[1])

## Место плашки: гэг — сверху по центру (растёт вниз), радио — внизу над подсказкой E (растёт вверх).
func _subtitle_slot(top: bool) -> void:
	subtitle_card.anchor_top = 0.0 if top else 1.0
	subtitle_card.anchor_bottom = subtitle_card.anchor_top
	subtitle_card.offset_top = GAG_SLOT_TOP if top else -190.0
	subtitle_card.offset_bottom = GAG_SLOT_TOP + 80.0 if top else -110.0
	subtitle_card.grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN

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
## Музыка из окна — 3D-цикл у окна второго этажа H1 (двор), слышна только рядом. Двери звучат только по
## Resident.entrance_used и по адресу события; ветер следует LightingAndWeather.gust, во дворе H1 тише. Вороны и собака — 3D на их
## узлах по сигналам Ambient (crow_cawed, dog_barked). Сигнал машины кольца — 3D на корпусе: стоит перед препятствием
## (PathVehicle.blocked_time) дольше HORN_WAIT — короткий гудок, не чаще раза в HORN_COOLDOWN на машину; сигнал
## horn_sounded — для тех, кто хочет оглянуться (жители). Звуки — tools/generate_audio.py (синтез).
## Уровни, RMS файла + volume_db (3D — у источника, до затухания): ветер −24 − 14 = −38 дБ, трафик −26 − 14 = −40,
## музыка −24 − 12 = −36, вороны и собака −18 − 10 = −28, дверь подъезда −18 − 14 = −32, гудок −16 − 10 = −26.
## Для сравнения (PLAY-03): фон двора −32, сигналы квеста −23 … −25, мотор −18 … −11.
const WIND := preload("res://assets/audio/wind_gust_loop.wav")
const CITY_TRAFFIC := preload("res://assets/audio/distant_traffic_loop.wav")
const WINDOW_MUSIC := preload("res://assets/audio/window_music_loop.wav")
const CROW_CAWS: Array[AudioStream] = [preload("res://assets/audio/crow_caw_1.wav"), preload("res://assets/audio/crow_caw_2.wav")]
const DOG_BARK := preload("res://assets/audio/dog_bark.wav")
const DOOR_SLAM := preload("res://assets/audio/door_slam.wav")
const CAR_HORN := preload("res://assets/audio/car_horn_short.wav")
const WIND_DB := -14.0
const WIND_CALM_DROP := 6.0
const WIND_YARD_DROP := 5.0
const WIND_RESPONSE := 5.0
const CITY_TRAFFIC_DB := -14.0
const MUSIC_DB := -12.0
const CROW_DB := -10.0
const DOG_DB := -10.0
const DOOR_SLAM_DB := -14.0   # −8 равнялось пику звона квеста (проверка CITY-01, P3)
const HORN_DB := -10.0
const HORN_WAIT := 3.0
const HORN_COOLDOWN := 10.0
const DOOR_POOL_SIZE := 4
const DOOR_LOCATION_COOLDOWN := 2.0
const DOOR_HEARING_DISTANCE := 50.0
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
var _wind_weather: Node
var _entrance_residents: Node
var _door_players: Array[AudioStreamPlayer3D] = []
var _door_last := {}
var _ambient_node: Node
var _crow_players := {}   # ворона → AudioStreamPlayer3D
var _dog_player: AudioStreamPlayer3D
var _horn_players := {}   # PathVehicle → AudioStreamPlayer3D
var _last_horn := {}      # PathVehicle → время последнего гудка

func _setup_ambient() -> void:
	for key in ["crow", "dog", "door_slam", "horn"]:
		played[key] = 0
	_ambient_rng.seed = AMBIENT_SEED
	wind = _bed(WIND, WIND_DB - WIND_CALM_DROP, "WindBed")
	_wind_weather = world.get_node("LightingAndWeather")
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
	for i in DOOR_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "EntranceDoor%d" % i
		player.volume_db = DOOR_SLAM_DB
		player.unit_size = 6.0
		player.max_distance = DOOR_HEARING_DISTANCE
		player.stream = DOOR_SLAM
		add_child(player)
		_door_players.append(player)
	door_slam = _door_players[0]
	_connect_entrances()
	_connect_ambient()

func _connect_entrances() -> void:
	if is_instance_valid(_entrance_residents):
		return
	_entrance_residents = get_tree().get_first_node_in_group(&"residents")
	if _entrance_residents:
		for resident: Resident in _entrance_residents.residents:
			resident.entrance_used.connect(_on_entrance_used)

func _on_entrance_used(_resident: Resident, at: Vector3, _entering: bool) -> void:
	if get_tree().paused:
		return
	var source := at + Vector3.UP * 1.2
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(source) > DOOR_HEARING_DISTANCE:
		return
	var location := Vector2(at.x, at.z).snapped(Vector2.ONE * 0.1)
	if _ambient_clock - float(_door_last.get(location, -INF)) < DOOR_LOCATION_COOLDOWN:
		return
	for player in _door_players:
		if player.playing:
			continue
		player.global_position = source
		player.pitch_scale = _ambient_rng.randf_range(0.92, 1.05)
		_one_shot(player, DOOR_SLAM, "door_slam")
		_door_last[location] = _ambient_clock
		door_slam_times.append(_ambient_clock)
		return

func _wind_sound(delta: float) -> void:
	var gust := clampf(float(_wind_weather.gust), 0.0, 1.0)
	var target := WIND_DB - WIND_CALM_DROP * (1.0 - gust)
	var listener: Node3D = world.car if world.control_mode == &"in_car" else world.player
	var p := listener.global_position
	if Layout.YARD_HOME.has_point(Vector2(p.x, p.z)):
		target -= WIND_YARD_DROP
	wind.volume_db = lerpf(wind.volume_db, target, 1.0 - exp(-WIND_RESPONSE * delta))

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
	_connect_entrances()
	_wind_sound(delta)
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

# --- COINS-01: звон подобранной монеты ---
## Один синтез coin_pickup.wav (tools/generate_audio.py) с чередованием высоты, как три звона подряд в аркадах:
## монеты подряд (не реже COIN_RUN_GAP) идут вверх по COIN_PITCHES, после паузы — снова с первой. Без 3D: звон
## «в интерфейсе», как счётчик. Полифония — быстрые подборы не обрывают друг друга.
const COIN_PICKUP := preload("res://assets/audio/coin_pickup.wav")
const COIN_PITCHES: Array[float] = [1.0, 1.122, 1.26, 1.335, 1.498]   # 0, +2, +4, +5, +7 полутонов
const COIN_RUN_GAP := 0.7   # с
var coin_player: AudioStreamPlayer
## Для проверок: высота последнего звона.
var coin_pitch := 1.0
var _coin_step := 0
var _coin_last := -100.0

func _setup_coins() -> void:
	played["coin"] = 0
	coin_player = AudioStreamPlayer.new()
	coin_player.name = "CoinSound"
	coin_player.stream = COIN_PICKUP
	coin_player.volume_db = -10.0
	coin_player.max_polyphony = 4
	add_child(coin_player)
	var coins := world.get_node_or_null("LevelGeometry/Coins")
	if coins and coins.has_signal("collected"):
		coins.collected.connect(_on_coin_collected)

func _on_coin_collected(_position: Vector3, _total: int) -> void:
	var now := float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second   # время игры, не часы
	_coin_step = (_coin_step + 1) % COIN_PITCHES.size() if now - _coin_last <= COIN_RUN_GAP else 0
	_coin_last = now
	coin_pitch = COIN_PITCHES[_coin_step]
	coin_player.pitch_scale = coin_pitch
	coin_player.play()
	played["coin"] += 1

# --- PUNCH-01: удар и дроны ГСУМ ---
## Взмах — разовый 3D у Илюши (плеер под DemoWorld, не под Илюшей: инвариант DEMO 3) по сигналу Ilyusha.punched.
## Жужжание — 3D-цикл на каждом дроне (затухание по удалению, до DRONE_BUZZ_DISTANCE), высота чуть разная у дронов и
## выше при подлёте и осмотре; сбитый дрон молчит. Хлопок — разовый 3D в точке сбитого дрона (Drones.drone_broken).
## Уровни, RMS файла + volume_db (у источника): жужжание −20 − 12 = −32 дБ, взмах −20 − 4 = −24, хлопок −16 − 2 = −18,
## «бип-бип» −20 − 6 = −26. Звуки — tools/generate_audio.py (синтез).
## PUNCH-02: жужжание слышно раньше — радиус 22 → 33 м и unit_size 2 → 3 (+50 %: громкость на 33 м — как была на 22);
## при подлёте к Илюше (patrol → approach) — короткий «бип-бип» 3D на дроне.
const PUNCH_WHOOSH := preload("res://assets/audio/punch_whoosh.wav")
const DRONE_BUZZ := preload("res://assets/audio/drone_buzz_loop.wav")
const DRONE_POP := preload("res://assets/audio/drone_pop.wav")
const DRONE_BEEP := preload("res://assets/audio/drone_beep.wav")
const DRONE_BEEP_DB := -6.0
const PUNCH_WHOOSH_DB := -4.0
const DRONE_BUZZ_DB := -12.0
const DRONE_POP_DB := -2.0
const DRONE_BUZZ_DISTANCE := 33.0
const DRONE_BUZZ_UNIT := 3.0

var punch_player: AudioStreamPlayer3D
var drone_pop_player: AudioStreamPlayer3D
var drone_buzz := {}   # Drone → AudioStreamPlayer3D
var drone_beep := {}   # Drone → AudioStreamPlayer3D (PUNCH-02)
var _drone_state := {} # Drone → состояние в прошлом кадре: «бип» на переходе в approach
var _drones_node: Node

func _setup_punch() -> void:
	played["punch"] = 0
	played["drone_pop"] = 0
	played["drone_beep"] = 0
	punch_player = _player_3d(world, PUNCH_WHOOSH_DB, PUNCH_WHOOSH)
	punch_player.name = "PunchWhoosh"
	drone_pop_player = _player_3d(world, DRONE_POP_DB, DRONE_POP)
	drone_pop_player.name = "DronePop"
	drone_pop_player.max_distance = 40.0
	if world.player.has_signal("punched"):
		world.player.punched.connect(func():
			punch_player.global_position = world.player.global_position + Vector3.UP * 1.3
			_one_shot(punch_player, PUNCH_WHOOSH, "punch"))

## Drones (LevelGeometry/Drones) — по группе; подключается при первом появлении.
func _drone_sounds() -> void:
	if punch_player == null:
		return
	if _drones_node == null or not is_instance_valid(_drones_node):
		_drones_node = get_tree().get_first_node_in_group(&"drones")
		if _drones_node == null:
			return
		_drones_node.drone_broken.connect(func(drone: Node3D):
			drone_pop_player.global_position = drone.global_position
			_one_shot(drone_pop_player, DRONE_POP, "drone_pop"))
	for drone in _drones_node.drones:
		var player: AudioStreamPlayer3D = drone_buzz.get(drone)
		if player == null:
			player = _player_3d(drone, DRONE_BUZZ_DB, DRONE_BUZZ)
			player.name = "Buzz"
			player.unit_size = DRONE_BUZZ_UNIT
			player.max_distance = DRONE_BUZZ_DISTANCE
			drone_buzz[drone] = player
		var flying: bool = drone.is_flying()
		if flying and not player.playing:
			player.play(fmod(float(drone.index) * 0.37, 1.9))
		elif not flying and player.playing:
			player.stop()
		var excited: bool = drone.state == &"approach" or drone.state == &"hover"
		player.pitch_scale = (0.96 + 0.025 * float(drone.index % 4)) * (1.12 if excited else 1.0)
		if drone.state == &"approach" and _drone_state.get(drone, &"") != &"approach":
			var beep: AudioStreamPlayer3D = drone_beep.get(drone)
			if beep == null:
				beep = _player_3d(drone, DRONE_BEEP_DB, DRONE_BEEP)
				beep.name = "Beep"
				beep.unit_size = DRONE_BUZZ_UNIT
				beep.max_distance = DRONE_BUZZ_DISTANCE
				drone_beep[drone] = beep
			_one_shot(beep, DRONE_BEEP, "drone_beep")
		_drone_state[drone] = drone.state

# --- KNOCK-01: сбитые «Ладой» жители ---
## «Вжух» — разовый 3D в точке удара (Residents.resident_knocked), глухой «пуф» в снег — в точке падения
## (Residents.resident_landed). Плееры под DemoWorld; полифония — пара сбитых разом не обрывает друг друга.
## Уровни, RMS файла + volume_db (у источника): вжух −20 − 4 = −24 дБ, пуф −16 − 2 = −18. Звуки — tools/generate_audio.py.
## played["knock"] — взлёты, played["knock_thud"] — падения.
const KNOCK_WHOOSH := preload("res://assets/audio/knock_whoosh.wav")
const KNOCK_THUD := preload("res://assets/audio/knock_thud.wav")
const KNOCK_WHOOSH_DB := -4.0
const KNOCK_THUD_DB := -2.0

var knock_whoosh_player: AudioStreamPlayer3D
var knock_thud_player: AudioStreamPlayer3D
var _residents_node: Node

func _setup_knock() -> void:
	played["knock"] = 0
	played["knock_thud"] = 0
	knock_whoosh_player = _player_3d(world, KNOCK_WHOOSH_DB, KNOCK_WHOOSH)
	knock_whoosh_player.name = "KnockWhoosh"
	knock_whoosh_player.max_polyphony = 3
	knock_thud_player = _player_3d(world, KNOCK_THUD_DB, KNOCK_THUD)
	knock_thud_player.name = "KnockThud"
	knock_thud_player.max_polyphony = 3

## Residents (LevelGeometry/Residents) — по группе; подключается при первом появлении.
func _knock_sounds() -> void:
	if knock_whoosh_player == null or (_residents_node != null and is_instance_valid(_residents_node)):
		return
	_residents_node = get_tree().get_first_node_in_group(&"residents")
	if _residents_node == null or not _residents_node.has_signal(&"resident_knocked"):
		_residents_node = null
		return
	_residents_node.resident_knocked.connect(func(resident: Node3D):
		knock_whoosh_player.global_position = resident.global_position + Vector3.UP * 1.0
		_one_shot(knock_whoosh_player, KNOCK_WHOOSH, "knock"))
	_residents_node.resident_landed.connect(func(resident: Node3D):
		knock_thud_player.global_position = resident.global_position + Vector3.UP * 0.3
		_one_shot(knock_thud_player, KNOCK_THUD, "knock_thud"))

# --- BREAK-01: разрушаемые объекты ---
## Поломка — разовый 3D в точке объекта по Breakables.broken: break_<материал> по Breakables.SOUND (дерево, металл,
## пластик, снег); удар по тяжёлому, который его ещё не сломал (Breakables.wobbled), — тот же звук тише и ниже.
## Реакции без разрушения: сигнализация машины (Breakables.car_alarm, 6 с) и хлопок крышек контейнера (bin_lid).
## Не чаще одного звука одного вида за BREAK_MIN_GAP. Уровни, RMS файла + volume_db (у источника): поломка
## −18 − 4 = −22 дБ, сигнализация −22 − 6 = −28, крышки −18 − 4 = −22 — ниже звона квеста. Звуки — tools/generate_audio.py.
## played["break"] — поломки, played["break_<материал>"], ["car_alarm"], ["bin_lid"], ["break_wobble"].
const BREAK_STREAMS := {
	&"wood": preload("res://assets/audio/break_wood.wav"),
	&"metal": preload("res://assets/audio/break_metal.wav"),
	&"plastic": preload("res://assets/audio/break_plastic.wav"),
	&"snow": preload("res://assets/audio/break_snow.wav"),
}
const CAR_ALARM := preload("res://assets/audio/car_alarm.wav")
const BIN_LID := preload("res://assets/audio/bin_lid.wav")
const BREAK_DB := -4.0
const BREAK_WOBBLE_DB := -10.0
const CAR_ALARM_DB := -6.0
const BIN_LID_DB := -4.0
const BREAK_MIN_GAP := 0.2   # с

var break_players := {}    # вид звука → AudioStreamPlayer3D
var _break_last := {}      # вид звука → время, с
var _breakables_node: Node

func _setup_break() -> void:
	played["break"] = 0
	played["break_wobble"] = 0
	played["car_alarm"] = 0
	played["bin_lid"] = 0
	for material: StringName in BREAK_STREAMS:
		played["break_%s" % material] = 0
		break_players[material] = _break_player("Break_%s" % material, BREAK_DB, BREAK_STREAMS[material])
	break_players[&"car_alarm"] = _break_player("CarAlarm", CAR_ALARM_DB, CAR_ALARM)
	break_players[&"bin_lid"] = _break_player("BinLid", BIN_LID_DB, BIN_LID)

func _break_player(node_name: String, volume: float, stream: AudioStream) -> AudioStreamPlayer3D:
	var player := _player_3d(world, volume, stream)
	player.name = node_name
	player.max_polyphony = 3
	player.max_distance = 50.0
	return player

## Breakables (LevelGeometry/Breakables) — по группе; подключается при первом появлении.
func _break_sounds() -> void:
	if break_players.is_empty() or (_breakables_node != null and is_instance_valid(_breakables_node)):
		return
	_breakables_node = get_tree().get_first_node_in_group(&"breakables_root")
	if _breakables_node == null or not _breakables_node.has_signal(&"broken"):
		_breakables_node = null
		return
	_breakables_node.broken.connect(func(b: Node3D, by: StringName):
		if car_radio:
			car_radio.report_break(b.kind, by)
		var material: StringName = _breakables_node.SOUND.get(b.kind, &"wood")
		if _break_play(material, b.global_position + Vector3.UP * 0.5, 1.0, BREAK_DB):
			played["break"] += 1
			played["break_%s" % material] += 1)
	_breakables_node.wobbled.connect(func(b: Node3D):
		var material: StringName = _breakables_node.SOUND.get(b.kind, &"wood")
		if _break_play(material, b.global_position + Vector3.UP * 0.5, 0.8, BREAK_WOBBLE_DB):
			played["break_wobble"] += 1)
	_breakables_node.car_alarm.connect(func(at: Vector3):
		if car_radio:
			car_radio.report_event(&"car_alarm", "Во дворе сработала сигнализация. Автомобиль требует внимания и немного личного пространства")
		if _break_play(&"car_alarm", at, 1.0, CAR_ALARM_DB):
			played["car_alarm"] += 1)
	_breakables_node.bin_lid.connect(func(at: Vector3):
		if car_radio:
			car_radio.report_event(&"bin_lid", "Мусорный бак хлопнул крышкой. Коммунальщики назвали это открытым диалогом с населением")
		if _break_play(&"bin_lid", at, 1.0, BIN_LID_DB):
			played["bin_lid"] += 1)

## Разовый звук вида kind в точке at; false — тот же вид звучал меньше BREAK_MIN_GAP назад.
func _break_play(kind: StringName, at: Vector3, pitch: float, volume: float) -> bool:
	var now := Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
	if now - float(_break_last.get(kind, -INF)) < BREAK_MIN_GAP:
		return false
	_break_last[kind] = now
	var player: AudioStreamPlayer3D = break_players[kind]
	player.global_position = at
	player.pitch_scale = pitch
	player.volume_db = volume
	player.play()
	return true

# --- DRIVE-02: колёса в рыхлом снегу и скрип шин при заносе ---
## Шуршание снега — 3D-цикл на «Ладе»: громкость по средней глубине рыхлого снега под колёсами (Lada.snow_depth,
## полная от DRIVE02_DEPTH_FULL) и скорости (полная от 6 м/с; при буксовании — не ниже 0,7), высота чуть растёт со
## скоростью. Скрип шин — 3D-цикл на «Ладе» при заносе (Lada.skidding), громкость по боковой скорости 2…6 м/с.
## Плееры под машиной, как мотор и каша. Уровни, RMS файла + volume_db: снег −18 + 0 = −18 дБ, скрип −20 − 4 = −24.
## Звуки — tools/generate_audio.py (синтез).
const SNOW_DRIVE := preload("res://assets/audio/snow_drive_loop.wav")
const SKID_SQUEAK := preload("res://assets/audio/skid_squeak_loop.wav")
const SNOW_DRIVE_DB := 0.0
const SKID_SQUEAK_DB := -4.0
const DRIVE02_DEPTH_FULL := 0.2

var snow_drive_player: AudioStreamPlayer3D
var skid_squeak_player: AudioStreamPlayer3D

func _setup_drive02() -> void:
	played["snow_drive"] = 0
	played["skid_squeak"] = 0
	snow_drive_player = _player_3d(world.car, -80.0, SNOW_DRIVE)
	snow_drive_player.name = "SnowDrive"
	skid_squeak_player = _player_3d(world.car, -80.0, SKID_SQUEAK)
	skid_squeak_player.name = "SkidSqueak"

func _drive02_sounds() -> void:
	if snow_drive_player == null:
		return
	var car = world.car
	var speed := Vector2(car.velocity.x, car.velocity.z).length()
	var depth := clampf(float(car.get("snow_depth")) / DRIVE02_DEPTH_FULL, 0.0, 1.0)
	var motion := clampf(speed / 6.0, 0.0, 1.0)
	if car.get("spinning"):
		motion = maxf(motion, 0.7)
	_drive02_loop(snow_drive_player, depth * motion, SNOW_DRIVE_DB, 0.85 + 0.3 * motion, "snow_drive")
	var squeak := clampf((float(car.lateral_speed) - 2.0) / 4.0, 0.0, 1.0) if car.get("skidding") else 0.0
	if car.get("skidding"):
		squeak = maxf(squeak, 0.3)   # ручник на скорости — скрип и без большого бокового сноса
	_drive02_loop(skid_squeak_player, squeak, SKID_SQUEAK_DB, 0.95 + 0.1 * squeak, "skid_squeak")

func _drive02_loop(player: AudioStreamPlayer3D, level: float, db: float, pitch: float, key: String) -> void:
	if level > 0.02:
		player.volume_db = db + linear_to_db(level)
		player.pitch_scale = pitch
		if not player.playing:
			player.play()
			played[key] += 1
	elif player.playing:
		player.stop()

# --- PEOPLE-03: звуки занятий жителей и птиц ---
## Занятия (Residents.activity_sounded): стук костяшки домино, взмах метлы, скрип санок и ската горки, клюшка и шайба
## о борт; птицы (Ambient): воркование голубя (pigeon_cooed) и хлопанье крыльев взлетевшей стайки (birds_flushed).
## Разовый 3D в точке источника: тихо, затухание unit_size, дальше max_distance не слышно — и не запускается, если
## камера дальше (played["life_far"]); один вид не чаще LIFE_MIN_GAP. Уровни, RMS файла + volume_db (у источника):
## домино −22 − 8 = −30 дБ, метла и санки −24 − 8 = −32, клюшка −25 − 6 = −31, голубь −24 − 8 = −32, крылья
## −20 − 8 = −28 — тише сигналов квеста (−23 … −25). Звуки — tools/generate_audio.py. played["life_<вид>"].
const LIFE_SOUNDS := {
	# вид: [поток, volume_db, unit_size, max_distance, высота тона]
	&"domino": [preload("res://assets/audio/domino_clack.wav"), -8.0, 3.0, 22.0, 1.0],
	&"sweep": [preload("res://assets/audio/broom_swish.wav"), -8.0, 3.0, 18.0, 1.0],
	&"dig": [preload("res://assets/audio/broom_swish.wav"), -10.0, 3.0, 18.0, 0.7],
	&"carpet": [preload("res://assets/audio/hockey_stick.wav"), -10.0, 3.0, 22.0, 0.6],
	&"hood": [preload("res://assets/audio/domino_clack.wav"), -10.0, 3.0, 18.0, 0.8],
	&"sled": [preload("res://assets/audio/sled_creak.wav"), -8.0, 3.0, 18.0, 1.0],
	&"slide": [preload("res://assets/audio/sled_creak.wav"), -6.0, 3.0, 25.0, 0.8],
	&"stick": [preload("res://assets/audio/hockey_stick.wav"), -6.0, 3.0, 30.0, 1.0],
	&"board": [preload("res://assets/audio/hockey_stick.wav"), -6.0, 3.0, 30.0, 0.55],
	&"coo": [preload("res://assets/audio/pigeon_coo.wav"), -8.0, 3.0, 25.0, 1.0],
	&"wings": [preload("res://assets/audio/wings_flap.wav"), -8.0, 4.0, 35.0, 1.0],
}
const LIFE_MIN_GAP := 0.15   # с

var life_players := {}   # вид → AudioStreamPlayer3D
var _life_last := {}     # вид → время, с
var _life_residents: Node
var _life_ambient: Node

func _setup_life() -> void:
	played["life_far"] = 0
	for kind: StringName in LIFE_SOUNDS:
		var spec: Array = LIFE_SOUNDS[kind]
		played["life_%s" % kind] = 0
		var player := _player_3d(world, spec[1], spec[0])
		player.name = "Life_%s" % kind
		player.unit_size = spec[2]
		player.max_distance = spec[3]
		player.pitch_scale = spec[4]
		player.max_polyphony = 3
		life_players[kind] = player

## Residents и Ambient — по группам; подключаются при первом появлении.
func _life_sounds() -> void:
	if life_players.is_empty():
		return
	if _life_residents == null or not is_instance_valid(_life_residents):
		_life_residents = get_tree().get_first_node_in_group(&"residents")
		if _life_residents and _life_residents.has_signal(&"activity_sounded"):
			_life_residents.activity_sounded.connect(func(r: Node3D, kind: StringName): life_play(kind, r.global_position + Vector3.UP * 0.6))
		else:
			_life_residents = null
	if _life_ambient == null or not is_instance_valid(_life_ambient):
		_life_ambient = get_tree().get_first_node_in_group(&"ambient")
		if _life_ambient and _life_ambient.has_signal(&"pigeon_cooed"):
			_life_ambient.pigeon_cooed.connect(func(b: Node3D): life_play(&"coo", b.global_position))
			_life_ambient.birds_flushed.connect(func(b: Node3D): life_play(&"wings", b.global_position))
		else:
			_life_ambient = null

## Разовый звук занятия kind в точке at; false — камера дальше его max_distance или тот же вид только что звучал.
func life_play(kind: StringName, at: Vector3) -> bool:
	var player: AudioStreamPlayer3D = life_players.get(kind)
	if player == null:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera and camera.global_position.distance_to(at) > player.max_distance:
		played["life_far"] += 1
		return false
	var now := Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
	if now - float(_life_last.get(kind, -INF)) < LIFE_MIN_GAP:
		return false
	_life_last[kind] = now
	player.global_position = at
	player.play()
	played["life_%s" % kind] += 1
	return true

# --- POLISH-03 C: радио «Лады» при езде — позывные «ничего необычного» и объявления (game/audio/car_radio.gd) ---
const CarRadioScript = preload("res://game/audio/car_radio.gd")
var car_radio: Node

func _setup_car_radio() -> void:
	car_radio = CarRadioScript.new()
	car_radio.name = "CarRadio"
	add_child(car_radio)
	car_radio.setup(self)

## Первая погода ещё ожидает музыки или дочитывается.
func story_radio_pending() -> bool:
	return radio_shown == 0 or (_subtitle_left > 0.0 and _radio_caption == QuestLines.RADIO)

## Обычная строка допускается только на естественной границе треков.
func show_radio_line(text: String, seconds: float) -> bool:
	if not car_radio or not car_radio.music.between_tracks():
		return false
	return _begin_radio_line(text, seconds)

## Реальный объезд может перебить трек и несрочную передачу; повторный вызов остаётся у источника.
func urgent_radio_line(text: String, seconds: float) -> bool:
	if not car_radio or not car_radio.music.news_enabled() or not radio_available():
		return false
	# Уже принятая срочная передача не перезапускается при повторной доставке.
	if _subtitle_left > 0.0 and _radio_caption == text:
		return false
	if _subtitle_left > 0.0 and not _radio_urgent:
		_interrupted_radio_caption = _radio_caption
		_interrupted_radio_left = _subtitle_left
	_subtitle_left = 0.0
	var started := _begin_radio_line(text, seconds)
	_radio_urgent = started
	return started

func _begin_radio_line(text: String, seconds: float) -> bool:
	if subtitle_card == null or not radio_available() or _subtitle_left > 0.0 or not car_radio.music.news_enabled():
		return false
	_subtitle_slot(false)
	_radio_urgent = false
	_radio_caption = text
	subtitle_label.text = text
	_subtitle_left = maxf(seconds, QuestLines.read_seconds(text.replace("\n", " ")))
	subtitle_card.visible = true
	if not radio.playing:
		radio.play()
		played["radio"] += 1
	DialogPanelScript.pop(subtitle_card, 0.6)
	return true

func hide_radio_line() -> void:
	if subtitle_card == null or gag_playing():
		return
	_subtitle_left = 0.0
	_interrupted_radio_caption = ""
	_interrupted_radio_left = 0.0
	_radio_urgent = false
	subtitle_card.visible = false

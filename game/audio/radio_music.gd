extends Node
## Две станции приёмника: музыка принадлежит водителю, новости — только «Радио Н.».
## Отдельные плееры музыки и настройки не занимают короткий канал диктора CarRadio.

const PadInput = preload("res://game/ui/pad_input.gd")
const LIVE_PATH := "res://assets/audio/radio/cold_funk.ogg"
const LIVE_PATHS: Array[String] = [
	LIVE_PATH,
	"res://assets/audio/radio/local_forecast_elevator.ogg",
	"res://assets/audio/radio/monkeys_spinning_monkeys.ogg",
	"res://assets/audio/radio/sneaky_snitch.ogg",
]
const TUNE_PATH := "res://assets/audio/radio/radio_tune.wav"
const CLASSICAL_PATHS: Array[String] = [
	"res://assets/audio/radio/beethoven_moonlight_1.ogg",
	"res://assets/audio/radio/chopin_nocturne_1.ogg",
]
const BASE_DB := -5.0
const DUCK_DB := -15.0
const PRIORITY_DB := -23.0
const TUNE_DB := -1.0
const DUCK_SECONDS := 0.35
const RESTORE_SECONDS := 0.8
const STATION_SECONDS := 4.0
const STATION_NAMES := ["Радио Н. · 101,4 FM", "Классика · 104,2 FM"]

enum Station { LIVE, CLASSICAL }

var station := Station.LIVE
var player: AudioStreamPlayer
var tuning: AudioStreamPlayer
var station_label: Label
var resume_position := 0.0
var sound: Node
var world: Node
var _live: Array[AudioStream] = []
var _live_index := 0
var _classical: Array[AudioStream] = []
var _classical_index := 0
var _positions := [0.0, 0.0]
var _tune_pending := false
var _tuned := false
var _station_left := 0.0
# Естественный конец живого трека открывает ровно одно окно для передачи.
var _between_tracks := false
var _gap_claimed := false

func setup(director: Node) -> void:
	sound = director
	world = sound.world
	# Узел следит за паузой, но сами плееры замирают вместе с миром.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for path in LIVE_PATHS:
		var track := load(path).duplicate() as AudioStreamOggVorbis
		track.loop = false
		_live.append(track)
	for path in CLASSICAL_PATHS:
		if ResourceLoader.exists(path):
			var track: AudioStream = load(path).duplicate() as AudioStream
			if track is AudioStreamOggVorbis:
				track.loop = false
			_classical.append(track)
	player = AudioStreamPlayer.new()
	player.name = "RadioBed"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.bus = &"Master"
	player.volume_db = BASE_DB
	player.stream = _live[_live_index]
	add_child(player)
	player.finished.connect(_track_finished)
	tuning = AudioStreamPlayer.new()
	tuning.name = "RadioTune"
	tuning.process_mode = Node.PROCESS_MODE_PAUSABLE
	tuning.stream = load(TUNE_PATH)
	tuning.volume_db = TUNE_DB
	add_child(tuning)
	tuning.finished.connect(_tune_finished)
	_build_station_display()
	world.car.driver_entered.connect(func(_driver):
		if driver_active():
			_begin_tune())
	world.car.driver_exited.connect(func(_driver): stop())

func driver_active() -> bool:
	return world.car.driver == world.player and world.control_mode == &"in_car" and not world.is_stealth_failing() and world.mission.state != MissionDirector.COMPLETE

func news_enabled() -> bool:
	return station == Station.LIVE and _tuned and driver_active()

func switch_station() -> bool:
	if not driver_active() or get_tree().paused or world.ui_blocking:
		return false
	_save_position()
	station = Station.CLASSICAL if station == Station.LIVE else Station.LIVE
	resume_position = _positions[station]
	_begin_tune()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"radio_station") and not event.is_echo() and switch_station():
		get_viewport().set_input_as_handled()

func _begin_tune() -> void:
	player.stop()
	tuning.stop()
	_tuned = false
	_tune_pending = true
	sound.suspend_radio_voice()
	_station_left = STATION_SECONDS
	tuning.play()

func _tune_finished() -> void:
	# Устаревшее завершение после выхода/новой настройки ничего не запускает.
	if not _tune_pending or tuning.playing or not driver_active():
		return
	_tune_pending = false
	_tuned = true
	_start_track()

func _start_track() -> void:
	if not _tuned or not driver_active() or get_tree().paused or _theme_playing() or (station == Station.LIVE and _between_tracks):
		return
	player.stream = _live[_live_index] if station == Station.LIVE else _classical[_classical_index]
	player.volume_db = target_db()
	player.stream_paused = false
	player.play(_positions[station])

func between_tracks() -> bool:
	return station == Station.LIVE and _between_tracks

func claim_gap() -> void:
	_gap_claimed = true

func finish_gap() -> void:
	if not between_tracks():
		return
	_live_index = (_live_index + 1) % _live.size()
	_positions[Station.LIVE] = 0.0
	_between_tracks = false
	_gap_claimed = false
	_start_track()

func _track_finished() -> void:
	if station == Station.LIVE and driver_active() and _tuned and not _between_tracks:
		_positions[station] = 0.0
		_between_tracks = true
		_gap_claimed = false
	elif station == Station.CLASSICAL and driver_active() and _tuned:
		_classical_index = (_classical_index + 1) % _classical.size()
		_positions[station] = 0.0
		_start_track()

func _save_position() -> void:
	if player.playing:
		_positions[station] = player.get_playback_position()
	resume_position = _positions[station]

func stop() -> void:
	_save_position()
	player.stop()
	tuning.stop()
	_tune_pending = false
	_tuned = false
	_station_left = 0.0
	station_label.visible = false

func target_db() -> float:
	var flow: Node = world.get_node_or_null("QuestFlow")
	if world.ui_blocking or sound.gag_playing() or sound.chime.playing or (flow and flow.is_dialog_open()):
		return PRIORITY_DB
	return DUCK_DB if news_enabled() and sound.radio_text() != "" else BASE_DB

func _theme_playing() -> bool:
	var owner_node: Node = world.get_parent()
	var theme: Node = owner_node.get("music") if owner_node else null
	return theme != null and theme.player.playing

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if not driver_active():
		if player.playing or tuning.playing or _tuned:
			stop()
		return
	var suspended: bool = get_tree().paused or _theme_playing()
	player.stream_paused = suspended
	if not suspended:
		# AudioServer may stop before main-thread finished delivery; retain that playback.
		if _tuned and not player.playing and not player.has_stream_playback():
			_start_track()
		var target: float = target_db()
		var seconds: float = DUCK_SECONDS if target < player.volume_db else RESTORE_SECONDS
		player.volume_db = move_toward(player.volume_db, target, (BASE_DB - PRIORITY_DB) * delta / seconds)
		_station_left = maxf(0.0, _station_left - delta)
	station_label.visible = _station_left > 0.0 and not suspended and not world.ui_blocking
	station_label.text = "%s\n%s — сменить станцию" % [STATION_NAMES[station], "→ крестовина" if PadInput.pad_active else "R"]

func _build_station_display() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "RadioStationHUD"
	layer.layer = 6
	add_child(layer)
	station_label = Label.new()
	station_label.name = "Station"
	station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	station_label.add_theme_font_size_override("font_size", 24)
	station_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.75))
	station_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.04, 0.03, 0.95))
	station_label.add_theme_constant_override("shadow_offset_x", 2)
	station_label.add_theme_constant_override("shadow_offset_y", 2)
	station_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	station_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	station_label.offset_left = -550
	station_label.offset_right = -60
	station_label.offset_top = 32
	station_label.offset_bottom = 100
	station_label.visible = false
	layer.add_child(station_label)

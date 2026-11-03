extends Node
## Две станции приёмника: музыка принадлежит водителю, новости — только «Радио Н.».
## Отдельные плееры музыки и настройки не занимают короткий канал диктора CarRadio.

const AudioSettings = preload("res://game/audio/audio_settings.gd")
const PadInput = preload("res://game/ui/pad_input.gd")
const RadioTimeline = preload("res://game/audio/radio_timeline.gd")
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
	"res://assets/audio/radio/ride_of_the_valkyries.ogg",
]
const BASE_DB := -5.0
const DUCK_DB := -15.0
const PRIORITY_DB := -23.0
const TUNE_DB := -1.0
const DUCK_SECONDS := 0.35
const RESTORE_SECONDS := 0.8
const STATION_SECONDS := 4.0
const SEEK_DRIFT_SECONDS := 0.5
const STATION_NAMES := ["Радио Н. · 101,4 FM", "Классика · 104,2 FM", "Без радио"]

enum Station { LIVE, CLASSICAL, OFF }

var station := Station.LIVE
var player: AudioStreamPlayer
var tuning: AudioStreamPlayer
var station_label: Label
var resume_position: float:
	get:
		return _timelines[station].position if station != Station.OFF else 0.0
var sound: Node
var world: Node
var _live: Array[AudioStream] = []
var _live_index: int:
	get:
		return _timelines[Station.LIVE].index
var _classical: Array[AudioStream] = []
var _classical_index: int:
	get:
		return _timelines[Station.CLASSICAL].index
var _timelines: Array = []
var _playback_station := -1
var _playback_revision := -1
var _awaiting_boundary := false
var _tune_pending := false
var _tuned := false
var _station_left := 0.0
# Естественный конец живого трека открывает ровно одно окно для передачи.
var _between_tracks := false
var _gap_claimed := false

func setup(director: Node) -> void:
	AudioSettings.ensure_buses()
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
	for tracks: Array in [_live, _classical]:
		var lengths: Array[float] = []
		for track: AudioStream in tracks:
			lengths.append(track.get_length())
		_timelines.append(RadioTimeline.new(lengths))
	player = AudioStreamPlayer.new()
	player.name = "RadioBed"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.bus = AudioSettings.MUSIC_BUS
	player.volume_db = BASE_DB
	player.stream = _live[_live_index]
	add_child(player)
	player.finished.connect(_track_finished)
	tuning = AudioStreamPlayer.new()
	tuning.name = "RadioTune"
	tuning.bus = AudioSettings.EFFECTS_BUS
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
	station = (station + 1) % STATION_NAMES.size()
	_begin_tune()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"radio_station") and not event.is_echo() and switch_station():
		get_viewport().set_input_as_handled()

func _begin_tune() -> void:
	player.stop()
	tuning.stop()
	_tuned = false
	_tune_pending = station != Station.OFF
	_awaiting_boundary = false
	sound.suspend_radio_voice()
	_station_left = STATION_SECONDS
	if _tune_pending:
		tuning.play()

func _tune_finished() -> void:
	# Устаревшее завершение после выхода/новой настройки ничего не запускает.
	if not _tune_pending or tuning.playing or not driver_active():
		return
	_tune_pending = false
	_tuned = true
	_start_track()

func _start_track() -> void:
	if station == Station.OFF or not _tuned or not driver_active() or get_tree().paused or _theme_playing() or (station == Station.LIVE and _between_tracks):
		return
	_playback_station = station
	_playback_revision = _timelines[station].revision
	_awaiting_boundary = false
	player.stream = _live[_live_index] if station == Station.LIVE else _classical[_classical_index]
	player.volume_db = target_db()
	player.stream_paused = false
	player.play(_timelines[station].position)

func broadcast_state(which: int) -> Dictionary:
	assert(which == Station.LIVE or which == Station.CLASSICAL)
	return {"index": _timelines[which].index, "position": _timelines[which].position}

func between_tracks() -> bool:
	return station == Station.LIVE and _between_tracks

func claim_gap() -> void:
	if between_tracks():
		_gap_claimed = true

func finish_gap() -> void:
	if not between_tracks():
		return
	_between_tracks = false
	_gap_claimed = false
	_start_track()

func _track_finished() -> void:
	# AudioServer can finish before the world-time boundary, or deliver an old end
	# after a new stream has started. Neither notification owns the station clock.
	if station == Station.OFF or not _tuned or not driver_active() or player.playing or player.has_stream_playback():
		return
	if _playback_station == station and _playback_revision == _timelines[station].revision:
		_awaiting_boundary = true

func stop() -> void:
	player.stop()
	tuning.stop()
	_tune_pending = false
	_tuned = false
	_awaiting_boundary = false
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
	var suspended: bool = get_tree().paused or _theme_playing()
	var boundaries := [0, 0]
	if not suspended:
		for which in _timelines.size():
			boundaries[which] = _timelines[which].advance(delta)
	if not driver_active():
		if player.playing or tuning.playing or _tuned:
			stop()
		return
	player.stream_paused = suspended
	if not suspended:
		if _tuned and station != Station.OFF:
			if boundaries[station] > 0:
				player.stop()
				_awaiting_boundary = false
				if station == Station.LIVE:
					if not _between_tracks:
						_between_tracks = true
						_gap_claimed = false
				else:
					_start_track()
			# Retain an ended playback until AudioServer delivers its finished event.
			if not player.playing and not player.has_stream_playback() and not _awaiting_boundary:
				_start_track()
			elif player.playing and absf(player.get_playback_position() - _timelines[station].position) > SEEK_DRIFT_SECONDS:
				player.seek(_timelines[station].position)
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

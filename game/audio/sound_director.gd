extends Node
## SoundDirector (POLISH-01): шаги по снегу, мотор и каша под колёсами «Лады», двери, интерфейс, звон хлеба,
## финал и фон двора. Только слушает мир, машину, миссию и диалоги — ничем не управляет.
## Звуки синтезированы tools/generate_audio.py (собственная генерация, см. assets/README.md).

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

## Счётчики для проверок: сколько раз сыграл каждый звук.
var played := {"step": 0, "door_open": 0, "door_close": 0, "ui": 0, "bread": 0, "complete": 0}

var world: Node
var step_player: AudioStreamPlayer3D
var engine: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
var door: AudioStreamPlayer3D
var ui: AudioStreamPlayer
var ambience: AudioStreamPlayer
var _walked := 0.0
var _last_position := Vector3.INF
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	world = get_parent()
	# Ссылки DemoWorld (player, car, mission) готовы только после его собственного _ready.
	world.ready.connect(_setup, CONNECT_ONE_SHOT)

func _setup() -> void:
	for stream in [ENGINE, SKID, AMBIENCE]:
		_make_loop(stream)
	step_player = _player_3d(world.player, -6.0)
	engine = _player_3d(world.car, -4.0, ENGINE)
	skid = _player_3d(world.car, -80.0, SKID)
	door = _player_3d(world.car, -2.0)
	ui = AudioStreamPlayer.new()
	ui.volume_db = -6.0
	add_child(ui)
	ambience = AudioStreamPlayer.new()
	ambience.stream = AMBIENCE
	ambience.volume_db = -12.0
	add_child(ambience)
	ambience.play()
	world.car.driver_entered.connect(func(_d): _one_shot(door, DOOR_CLOSE, "door_close"))
	world.car.driver_exited.connect(func(_d): _one_shot(door, DOOR_OPEN, "door_open"))
	world.mission.bread_received.connect(func(): _one_shot(ui, BREAD, "bread"))
	world.mission.quest_completed.connect(func(_xp): _one_shot(ui, COMPLETE, "complete"))
	var flow := world.get_node_or_null("QuestFlow")
	if flow and flow.get("dialog") and flow.dialog.has_signal("choice"):
		flow.dialog.choice.connect(func(_id): _one_shot(ui, UI_CLICK, "ui"))

func _physics_process(delta: float) -> void:
	if not engine:
		return
	_footsteps()
	_car_sounds(delta)

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

func _make_loop(stream: AudioStreamWAV) -> void:
	if stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)

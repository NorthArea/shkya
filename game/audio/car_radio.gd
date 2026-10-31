extends Node
## POLISH-03 C / RADIO-01: периодический диктор станции «Радио Н.» с субтитром.
## Первые две передачи принадлежат SoundDirector; последующие — только на ходу (≥ MIN_SPEED_KMH),
## через FIRST_DELAY и INTERVAL секунд езды. Диалог/гэг важнее. Музыкальный bed и настройка
## живут отдельно в RadioMusic: играют и на стоянке, пока за рулём Илюша.
## Тексты — оригинальные черновики на согласование с правообладателем ШКЯ (TEXT-01: ≤ 8 слов, время ≥ read_seconds).

const JINGLES: Array[AudioStream] = [
	preload("res://assets/audio/radio_jingle_1.wav"),
	preload("res://assets/audio/radio_jingle_2.wav"),
	preload("res://assets/audio/radio_jingle_3.wav"),
]
const LINES: Array[String] = [
	"Радио Н.: в городе ничего необычного",
	"Погода: снег. Обычный снег, как всегда",
	"Происшествий нет. Не было и не будет",
	"Пробок нет. Все едут куда надо",
	"Всё идёт по плану. Слушайте дальше",
]
const VOLUME_DB := -10.0        # тише мотора (−4) и двух сюжетных передач (−9): «из-под панели»
const MIN_SPEED_KMH := 10.0
const FIRST_DELAY := 8.0        # с езды после двух сюжетных передач до первого позывного
const INTERVAL := 40.0          # с езды между позывными (N из POLISH-03)
const FADE := 0.4               # с: гаснет, когда начинается квестовая реплика
const RadioMusicScript = preload("res://game/audio/radio_music.gd")

var sound: Node                 # SoundDirector
var world: Node
var player: AudioStreamPlayer3D
var plays := 0
## Секунды езды до следующего позывного (считаются только на ходу).
var wait := FIRST_DELAY
var line_index := 0
var _fading := false
var _fade_tween: Tween
var _announcing := false
var music: Node

func setup(director: Node) -> void:
	sound = director
	world = director.world
	player = AudioStreamPlayer3D.new()
	player.name = "RadioJingle"
	player.volume_db = VOLUME_DB
	player.unit_size = 6.0
	player.position = Vector3(0.0, 0.9, -0.9)   # приборная панель «пятёрки»
	world.car.add_child(player)
	world.car.driver_exited.connect(func(_d): stop())
	# Один общий тембр диктора; старые позывные содержат второй голос и потому
	# остаются только эталоном прежней длительности объявления.
	player.stream = sound.narrator_stream()
	music = RadioMusicScript.new()
	music.name = "RadioMusic"
	add_child(music)
	music.setup(sound)

## Текущая строка объявления на экране ("" — нет).
func line_text() -> String:
	return LINES[(line_index - 1 + LINES.size()) % LINES.size()] if player and player.playing else ""

func stop() -> void:
	suspend_voice()
	_announcing = false
	if music:
		music.stop()

func suspend_voice() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if player:
		player.stop()
		player.volume_db = VOLUME_DB
	_fading = false

func _physics_process(delta: float) -> void:
	if sound == null or player == null:
		return
	var car: Node = world.car
	if not music.driver_active():
		stop()
		return
	if not music.news_enabled():
		suspend_voice()
		return
	var busy: bool = _quest_busy()
	if _announcing and not player.playing and not busy and sound.radio_text() != "":
		player.play()
	if player.playing:
		if car.driver == null:
			stop()
		elif not busy and sound.radio_text() == "":
			suspend_voice()
			_announcing = false
		elif busy and not _fading:
			_fading = true
			_fade_tween = create_tween()
			_fade_tween.tween_property(player, "volume_db", -60.0, FADE)
			_fade_tween.tween_callback(func():
				player.stop()
				player.volume_db = VOLUME_DB
				_fading = false
				_announcing = false
				sound.hide_radio_line())
		return
	if car.driver == null or sound.story_radio_pending() or sound.radio.playing:
		return
	if car.speed_kmh() < MIN_SPEED_KMH:
		return
	wait -= delta
	if wait > 0.0 or busy:
		return
	_play()

## Квестовая реплика на экране: диалог, гэг (show_gag) или строка двух сюжетных передач.
func _quest_busy() -> bool:
	if world.ui_blocking:
		return true
	var flow: Node = world.get_node_or_null("QuestFlow")
	if flow and flow.has_method("is_dialog_open") and flow.is_dialog_open():
		return true
	if sound.gag_playing():
		return true
	return sound.radio_text() != "" and not player.playing and not _announcing

func _play() -> void:
	var stream: AudioStream = JINGLES[plays % JINGLES.size()]
	var text: String = LINES[line_index % LINES.size()]
	var seconds: float = maxf((stream as AudioStreamWAV).get_length() if stream is AudioStreamWAV else 4.0, QuestLines.read_seconds(text))
	if not sound.show_radio_line(text, seconds):
		return
	line_index += 1
	player.volume_db = VOLUME_DB
	_announcing = true
	player.play()
	plays += 1
	sound.played["radio_jingle"] = sound.played.get("radio_jingle", 0) + 1
	wait = INTERVAL

extends Node
## POLISH-03 C: радио «Лады» при езде. Позывной «ничего необычного» (assets/audio/radio_jingle_*.wav, синтез
## tools/generate_audio.py) из-под панели — AudioStreamPlayer3D на машине — и объявление строкой субтитра внизу, как
## разовое радио EXT-01. Играет только с водителем на ходу (≥ MIN_SPEED_KMH): первый раз через FIRST_DELAY с езды после
## двух сюжетных передач, дальше не чаще раза в INTERVAL с езды. Квестовое важнее: в диалоге, при гэге и пока висит строка
## двух сюжетных передач — молчит; начался диалог или гэг — позывной гаснет. Пешком молчит, с выходом из машины — стоп.
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

var sound: Node                 # SoundDirector
var world: Node
var player: AudioStreamPlayer3D
var plays := 0
## Секунды езды до следующего позывного (считаются только на ходу).
var wait := FIRST_DELAY
var line_index := 0
var _fading := false

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

## Текущая строка объявления на экране ("" — нет).
func line_text() -> String:
	return LINES[(line_index - 1 + LINES.size()) % LINES.size()] if player and player.playing else ""

func stop() -> void:
	if player:
		player.stop()
		player.volume_db = VOLUME_DB
	_fading = false

func _physics_process(delta: float) -> void:
	if sound == null or player == null:
		return
	var car: Node = world.car
	var busy := _quest_busy()
	if player.playing:
		if car.driver == null:
			stop()
		elif busy and not _fading:
			_fading = true
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -60.0, FADE)
			tween.tween_callback(func():
				stop()
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
	var flow := world.get_node_or_null("QuestFlow")
	if flow and flow.has_method("is_dialog_open") and flow.is_dialog_open():
		return true
	if sound.gag_playing():
		return true
	return sound.radio_text() != "" and not player.playing

func _play() -> void:
	var stream: AudioStream = JINGLES[plays % JINGLES.size()]
	var text: String = LINES[line_index % LINES.size()]
	var seconds := maxf((stream as AudioStreamWAV).get_length() if stream is AudioStreamWAV else 4.0, QuestLines.read_seconds(text))
	if not sound.show_radio_line(text, seconds):
		return
	line_index += 1
	player.volume_db = VOLUME_DB
	player.stream = stream
	player.play()
	plays += 1
	sound.played["radio_jingle"] = sound.played.get("radio_jingle", 0) + 1
	wait = INTERVAL

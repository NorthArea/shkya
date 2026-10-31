extends Node
## RADIO-02: первая погода после музыки; обычные передачи — только между треками.
## Очередь пополняют подтверждённые события мира. Срочный объезд принадлежит RoadClosure.

const RadioMusicScript = preload("res://game/audio/radio_music.gd")
const FIRST_MUSIC_SECONDS := 5.0
const EVENT_COOLDOWN := 90.0
const QUEUE_MAX := 6
const LINES: Array[String] = [
	"Реклама: покупайте снег местного производства. Доставка самовывозом",
	"Погода: снег продолжится. Просим не раскачивать сугробы",
	"Город Н. напоминает: завтра наступит по расписанию",
]
const BREAK_NEWS := {
	&"shawarma": "Нанятый евроатлантическими кукловодами провокатор снёс палатку с шаурмой. Подозреваемый разыскивается",
	&"snowman": "Неизвестный снёс снеговика. Следствие проверяет версию преждевременной весны",
	&"billboard": "Водитель снёс рекламный щит. Реклама наконец дошла до потребителя",
	&"bins": "Автомобиль снёс мусорные баки. Раздельный сбор вышел на новый уровень",
	&"fence": "Автомобиль снёс ограду. Доступность городской среды выросла",
}
var sound: Node
var world: Node
var music: Node
# Сохраняем прежний диагностический player: единственный звучащий диктор — SoundDirector.radio.
var player: AudioStreamPlayer3D
var plays := 0
var line_index := 0
var _first_music := 0.0
var _clock := 0.0
var _queue: Array[Dictionary] = []
var _last_event := {}

func setup(director: Node) -> void:
	sound = director
	world = director.world
	player = AudioStreamPlayer3D.new()
	player.name = "RadioJingle"
	world.car.add_child(player)
	music = RadioMusicScript.new()
	music.name = "RadioMusic"
	add_child(music)
	music.setup(sound)

func line_text() -> String:
	return sound.radio_text()

func stop() -> void:
	suspend_voice()
	if music:
		music.stop()

func suspend_voice() -> void:
	if player:
		player.stop()

func queue_size() -> int:
	return _queue.size()

## false означает неподдержанное/подавленное повторение; никаких происшествий до сигнала.
func report_break(kind: StringName, by: StringName) -> bool:
	if by != &"car" or not BREAK_NEWS.has(kind):
		return false
	return report_event(kind, BREAK_NEWS[kind])

func report_event(kind: StringName, text: String) -> bool:
	if _clock - float(_last_event.get(kind, -INF)) < EVENT_COOLDOWN:
		return false
	if _queue.any(func(item): return item.kind == kind):
		return false
	if _queue.size() >= QUEUE_MAX:
		return false
	_last_event[kind] = _clock
	_queue.append({"kind": kind, "text": text})
	return true

func _physics_process(delta: float) -> void:
	_clock += delta
	if not music.news_enabled() or not sound.radio_available():
		return
	if sound.radio_shown == 0:
		# Только действительно звучащая музыка: пауза/классика/диалог сюда не попадают.
		if music.player.playing and not music.player.stream_paused and sound._subtitle_left <= 0.0:
			_first_music += delta
		if _first_music >= FIRST_MUSIC_SECONDS and music.player.get_playback_position() >= FIRST_MUSIC_SECONDS and sound._subtitle_left <= 0.0:
			if sound._begin_radio_line(QuestLines.RADIO, QuestLines.RADIO_SECONDS):
				sound.radio_shown = 1
		return
	if not music.between_tracks():
		return
	if music._gap_claimed:
		if sound._subtitle_left <= 0.0:
			music.finish_gap()
		return
	if sound._subtitle_left > 0.0:
		return
	var text: String = _queue[0].text if not _queue.is_empty() else LINES[line_index % LINES.size()]
	if sound.show_radio_line(text, QuestLines.read_seconds(text)):
		if not _queue.is_empty():
			_queue.pop_front()
		else:
			line_index += 1
		plays += 1
		music.claim_gap()

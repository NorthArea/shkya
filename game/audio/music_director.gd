extends Node
## MusicDirector (MUSIC-03): Шопен, ноктюрн Op. 9 № 2, Frank Lévy / Musopen.
## Свободная фонограмма Set Chopin Free; источник/условия — assets/audio/LICENSE-chopin.txt.
## Полное исполнение со стерео и естественным затуханием; повтор при импорте. Играет в главном меню и на его экране НАСТРОЙКИ,
## затухает за FADE_OUT при старте игры и молчит в игре; при выходе в главное меню начинается с начала.
## На паузе — та же тема тише и «из-за стены» (ФНЧ шины Music): иначе пауза мёртвая — звук мира на ней замирает,
## а приглушённая тема связывает паузу с меню и не спорит с игрой; после паузы гаснет за PAUSE_FADE_OUT.
## Своя шина Music (создаётся при первом запуске) — отдельная громкость и фильтр паузы, мир не задевает.
## Состоянием владеет main.gd: to_menu() / to_game() / set_paused().

const AudioSettings = preload("res://game/audio/audio_settings.gd")
const THEME := preload("res://assets/audio/chopin_op9_no2_frank_levy.ogg")
const BUS := &"Music"
## Измеренный RMS после декодирования Ogg; динамика исполнения сохранена без компрессора.
## Голоса/звоны — −17 дБ RMS, тема мягче; на паузе ещё тише и без верхов.
const THEME_RMS_DB := -25.1
const MENU_DB := 0.0
const PAUSE_DB := -9.0
const PAUSE_CUTOFF_HZ := 900.0
const SILENT_DB := -40.0
const FADE_IN := 1.2
const FADE_OUT := 1.0
const PAUSE_FADE_IN := 0.6
const PAUSE_FADE_OUT := 0.4

enum State { MENU, GAME, PAUSE }

var state := State.GAME
var player: AudioStreamPlayer
var _tween: Tween
var _pause_from := 0.0   # с какого места продолжить тему на следующей паузе

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_bus()
	player = AudioStreamPlayer.new()
	player.name = "MenuTheme"
	player.stream = THEME
	player.bus = BUS
	player.volume_db = SILENT_DB
	add_child(player)

## Шина Music → SettingsMusic с выключенным ФНЧ паузы; общая на процесс (AudioServer), повторный вызов её находит.
static func ensure_bus() -> int:
	AudioSettings.ensure_buses()
	var index := AudioServer.get_bus_index(BUS)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, AudioSettings.MUSIC_BUS)
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = PAUSE_CUTOFF_HZ
		AudioServer.add_bus_effect(index, lowpass, 0)
	AudioServer.set_bus_effect_enabled(index, 0, false)
	return index

## Освобождение main (тесты, выход): тема останавливается, шина Music с её ФНЧ убирается из AudioServer —
## иначе при выходе Godot пишет «ObjectDB instances were leaked / resources still in use» (SMOKE: 2 и 1).
func _exit_tree() -> void:
	_kill_tween()
	player.stop()
	var index := AudioServer.get_bus_index(BUS)
	if index != -1:
		AudioServer.remove_bus(index)

func muffled() -> bool:
	return AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(BUS), 0)

## Целевая громкость текущего состояния (без учёта идущего затухания).
func target_db() -> float:
	match state:
		State.MENU:
			return MENU_DB
		State.PAUSE:
			return PAUSE_DB
	return SILENT_DB

## Итоговый RMS темы на выходе, дБ полной шкалы, при целевой громкости состояния.
func level_db() -> float:
	return THEME_RMS_DB + target_db() + AudioServer.get_bus_volume_db(AudioServer.get_bus_index(BUS))

func to_menu() -> void:
	if state == State.MENU and player.playing:
		return
	var from_top := state == State.GAME or not player.playing
	state = State.MENU
	_set_muffled(false)
	_fade_in(MENU_DB, FADE_IN, 0.0 if from_top else -1.0)

func to_game() -> void:
	if state == State.GAME:
		return
	state = State.GAME
	_fade_out(FADE_OUT)

func set_paused(paused: bool) -> void:
	if paused and state == State.GAME:
		state = State.PAUSE
		_set_muffled(true)
		_fade_in(PAUSE_DB, PAUSE_FADE_IN, _pause_from)
	elif not paused and state == State.PAUSE:
		state = State.GAME
		_fade_out(PAUSE_FADE_OUT)

## from: с какой секунды начать, если тема молчит (−1 — продолжить играющую).
func _fade_in(volume: float, seconds: float, from: float) -> void:
	_kill_tween()
	if not player.playing:
		player.volume_db = SILENT_DB
		player.play(maxf(from, 0.0))
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", volume, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _fade_out(seconds: float) -> void:
	_kill_tween()
	if not player.playing:
		return
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", SILENT_DB, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_stop)

func _stop() -> void:
	_pause_from = fmod(player.get_playback_position(), THEME.get_length())
	player.stop()
	_set_muffled(false)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null

func _set_muffled(on: bool) -> void:
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(BUS), 0, on)

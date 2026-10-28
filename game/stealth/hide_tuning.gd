extends RefCounted
## EXT-02: константы баланса укрытий в одном месте (docs/extension/HIDE_SPOTS.md, разделы 5.3, 6–9).
## Числа — начальные значения для плейтестов. Подключение: `const HideTuning = preload("res://game/stealth/hide_tuning.gd")`.

const NONE := &"none"
const BOX := &"box"
const SNOWDRIFT := &"snowdrift"
const BARREL := &"barrel"
const MODES: Array[StringName] = [NONE, BOX, SNOWDRIFT, BARREL]

## Предел скорости в режиме, м/с (обычный — Ilyusha.WALK_SPEED 4,0; сугроб — движения нет).
const HIDE_SPEED_BOX := 1.2
const HIDE_SPEED_BARREL := 2.6
const HIDE_SPEED_SNOWDRIFT := 0.0

## «Стоит» — горизонтальная скорость меньше этого порога, м/с.
const STILL_SPEED := 0.1
## Радиус «вплотную» от глаз наблюдателя (в плоскости XZ), м.
const CLOSE_RADIUS := 1.5

## Коэффициенты заметности (раздел 5.3): вдали стоя / вблизи стоя / в движении (вдали и вблизи одинаково).
const EXPOSURE_NONE := 1.0
const EXPOSURE_BOX_STILL := 0.0
const EXPOSURE_BOX_STILL_CLOSE := 0.5
const EXPOSURE_BOX_MOVING := 0.75
const EXPOSURE_SNOWDRIFT := 0.0
const EXPOSURE_BARREL_STILL := 0.0
const EXPOSURE_BARREL_STILL_CLOSE := 0.5
const EXPOSURE_BARREL_MOVING := 1.0

## Гэги C02–C06 (раздел 11, приёмка P2-1): не больше GAG_LIMIT за попытку (между респавнами и reset()) на все укрытия
## вместе; каждый — не чаще раза за попытку (флаг в укрытии). SoundDirector.show_gag не перебивает идущий гэг:
## очередь до GAG_QUEUE, лишний старейший отбрасывается; страницы по две строки через GAG_PAGE_SECONDS.
const GAG_LIMIT := 3
const GAG_QUEUE := 2
const GAG_PAGE_SECONDS := 2.5

## Подсказка-отказ (вход в машину, диалог, покупка в укрытии) держится столько секунд.
const HINT_SECONDS := 2.0
const HINT_BOX := "СНАЧАЛА СНЯТЬ КОРОБКУ"
const HINT_BARREL := "СНАЧАЛА ВЫЛЕЗТИ ИЗ БОЧКИ"
const HINT_SNOWDRIFT := "СНАЧАЛА ВЫЛЕЗТИ"
const HINT_EXIT_BLOCKED := "ВЫХОД ЗАНЯТ"

## Подсказки зон укрытий (выставляет сам HideSpot).
const PROMPT_BOX_ENTER := "E — НАДЕТЬ КОРОБКУ"
const PROMPT_BOX_EXIT := "E — СНЯТЬ КОРОБКУ"
const PROMPT_SNOWDRIFT_ENTER := "E — ЗАРЫТЬСЯ"
const PROMPT_SNOWDRIFT_EXIT := "E — ВЫЛЕЗТИ"
const PROMPT_BARREL_ENTER := "E — ЗАЛЕЗТЬ В БОЧКУ"
const PROMPT_BARREL_EXIT := "E — ВЫЛЕЗТИ ИЗ БОЧКИ"

## Предел скорости режима (м/с); для &"none" — walk_speed.
static func speed_for(mode: StringName, walk_speed: float) -> float:
	match mode:
		BOX: return HIDE_SPEED_BOX
		BARREL: return HIDE_SPEED_BARREL
		SNOWDRIFT: return HIDE_SPEED_SNOWDRIFT
	return walk_speed

## Коэффициент заметности по таблице 5.3.
static func exposure_for(mode: StringName, still: bool, close: bool) -> float:
	match mode:
		BOX:
			if not still:
				return EXPOSURE_BOX_MOVING
			return EXPOSURE_BOX_STILL_CLOSE if close else EXPOSURE_BOX_STILL
		SNOWDRIFT:
			return EXPOSURE_SNOWDRIFT
		BARREL:
			if not still:
				return EXPOSURE_BARREL_MOVING
			return EXPOSURE_BARREL_STILL_CLOSE if close else EXPOSURE_BARREL_STILL
	return EXPOSURE_NONE

## Текст отказа для режима ("" для &"none"). interaction_id — чья зона отказала: у окна продавщицы в коробке —
## её реплика (EXT-02 C, HIDE_SPOTS.md раздел 6).
static func refusal_for(mode: StringName, interaction_id: StringName = &"") -> String:
	match mode:
		BOX: return QuestLines.HIDE_BOX_VENDOR if interaction_id == &"vendor" else HINT_BOX
		BARREL: return HINT_BARREL
		SNOWDRIFT: return HINT_SNOWDRIFT
	return ""

extends RefCounted
## Строки монет (COINS-01, решение владельца 29.10: 35 рублей собрать до батона, стартовых денег нет).
## Отдельно от QuestLines (game/mission/lines.gd): реплики квеста ведёт сценарист, здесь — только подсказки сбора.

## Источники заработка после принятия поручения; числовой прогресс находится только в кошельке HUD.
const TASK := "Ищи монеты. Дроны и хлам тоже платят"
## Отказ продавщицы при нехватке денег — последняя реплика её диалога, «КУПИТЬ ХЛЕБ» выключена.
const VENDOR_SHORT := "Не хватает %d ₽"


static func task(_money: int, _goal: int) -> String:
	return TASK

static func earn_hint(pad: bool) -> String:
	return "%s — сбей дрон, получи монеты" % ("B" if pad else "F / ЛКМ")


static func vendor_short(missing: int) -> String:
	return VENDOR_SHORT % missing

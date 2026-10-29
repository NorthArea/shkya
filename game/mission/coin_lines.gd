extends RefCounted
## Строки монет (COINS-01, решение владельца 29.10: 35 рублей собрать до батона, стартовых денег нет).
## Отдельно от QuestLines (game/mission/lines.gd): реплики квеста ведёт сценарист, здесь — только подсказки сбора.

## Вторая строка карточки задачи HUD, пока денег меньше цены батона (MissionDirector.objective()["coins_task"]).
const TASK := "Собери монеты: %d/%d"
## Отказ продавщицы при нехватке денег — последняя реплика её диалога, «КУПИТЬ ХЛЕБ» выключена.
const VENDOR_SHORT := "Не хватает: ещё %d ₽"


static func task(money: int, goal: int) -> String:
	return TASK % [mini(money, goal), goal]


static func vendor_short(missing: int) -> String:
	return VENDOR_SHORT % missing

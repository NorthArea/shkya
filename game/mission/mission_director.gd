class_name MissionDirector
extends Node
## FSM миссии «За хлебом» (канон DEMO.md, разделы 5–6; контракт C5).
## Чистая логика без сцены: единственный владелец state, has_bread, xp, money.
## Недопустимая команда ничего не меняет, не шлёт сигналов и возвращает отказ.
##
## Результаты interact(id):
##   &"offer_dialog"  — Бабка: диалог выдачи («ПРИНЯТЬ» / «ОТКАЗАТЬСЯ»); NOT_STARTED → OFFERED,
##                      в OFFERED повторный вызов возвращает то же без изменений
##   &"turn_in"       — Бабка: сдача задания; RETURN_HOME + has_bread → COMPLETE, +50 XP
##   &"babka_idle"    — Бабка: обычная реплика, без изменений
##   &"vendor_dialog" — продавщица: диалог «Батон? 35 рублей» (только в BUY_BREAD); покупка — buy_bread()
##   &"none"          — взаимодействие недоступно или id не обрабатывается директором

signal state_changed(old: StringName, new: StringName)
signal bread_received
signal quest_completed(xp: int)

const NOT_STARTED := &"NOT_STARTED"
const OFFERED := &"OFFERED"
const GO_TO_CAR := &"GO_TO_CAR"
const DRIVE_TO_KIOSK := &"DRIVE_TO_KIOSK"
const BUY_BREAD := &"BUY_BREAD"
const RETURN_HOME := &"RETURN_HOME"
const COMPLETE := &"COMPLETE"

const R_OFFER_DIALOG := &"offer_dialog"
const R_VENDOR_DIALOG := &"vendor_dialog"
const R_TURN_IN := &"turn_in"
const R_BABKA_IDLE := &"babka_idle"
const R_NONE := &"none"

const BREAD_PRICE := 35
const START_MONEY := 100
const REWARD_XP := 50

const PROMPT_TALK := "E — ПОГОВОРИТЬ"
const PROMPT_TURN_IN := "E — СДАТЬ ЗАДАНИЕ"
const PROMPT_CAR := "E — СЕСТЬ В МАШИНУ"

const TITLE_CITY := "НОВОСИБИРСК"
const TITLE_QUEST := "ЗА ХЛЕБОМ"

var state: StringName = NOT_STARTED
var has_bread := false
var xp := 0
var money := START_MONEY


func interact(id: StringName) -> StringName:
	match id:
		&"babka":
			match state:
				NOT_STARTED:
					_set_state(OFFERED)
					return R_OFFER_DIALOG
				OFFERED:
					return R_OFFER_DIALOG
				RETURN_HOME:
					if has_bread:
						has_bread = false
						xp += REWARD_XP
						_set_state(COMPLETE)
						quest_completed.emit(REWARD_XP)
						return R_TURN_IN
					return R_BABKA_IDLE
				_:
					return R_BABKA_IDLE
		&"vendor":
			return R_VENDOR_DIALOG if state == BUY_BREAD else R_NONE
	return R_NONE


func accept() -> bool:
	if state != OFFERED:
		return false
	_set_state(GO_TO_CAR)
	return true


func decline() -> bool:
	if state != OFFERED:
		return false
	_set_state(NOT_STARTED)
	return true


func notify_entered_car() -> bool:
	if state != GO_TO_CAR:
		return false
	_set_state(DRIVE_TO_KIOSK)
	return true


func notify_arrived_kiosk() -> bool:
	if state != DRIVE_TO_KIOSK:
		return false
	_set_state(BUY_BREAD)
	return true


func can_buy_bread() -> bool:
	return state == BUY_BREAD and money >= BREAD_PRICE


func buy_bread() -> bool:
	if not can_buy_bread():
		return false
	money -= BREAD_PRICE
	has_bread = true
	_set_state(RETURN_HOME)
	bread_received.emit()
	return true


func reset() -> void:
	var old := state
	state = NOT_STARTED
	has_bread = false
	xp = 0
	money = START_MONEY
	if old != NOT_STARTED:
		state_changed.emit(old, NOT_STARTED)


func babka_marker() -> String:
	if state == NOT_STARTED or state == OFFERED:
		return "!"
	if state == RETURN_HOME and has_bread:
		return "?"
	return ""


## Тексты HUD по кадрам концептов (см. карточку MISSION-01, раздел «Реализация»).
func objective() -> Dictionary:
	match state:
		NOT_STARTED:
			return {"title": TITLE_CITY, "task": "Подойди к Бабке", "target_id": &"babka"}
		OFFERED:
			return {"title": TITLE_QUEST, "task": "Прими задание", "target_id": &"babka"}
		GO_TO_CAR:
			return {"title": TITLE_QUEST, "task": "Сядь в машину", "target_id": &"car"}
		DRIVE_TO_KIOSK:
			return {"title": TITLE_QUEST, "task": "Доедь до киоска", "target_id": &"kiosk"}
		BUY_BREAD:
			return {"title": TITLE_QUEST, "task": "Поговори с продавщицей", "target_id": &"vendor"}
		RETURN_HOME:
			return {"title": TITLE_QUEST, "task": "Вернись к Бабке", "target_id": &"babka"}
		_:
			return {"title": TITLE_QUEST, "task": "Задание выполнено", "target_id": &""}


## Подсказка зоны; "" — взаимодействие сейчас недоступно (зона отключается).
func prompt_for(id: StringName) -> String:
	match id:
		&"babka":
			if state == RETURN_HOME and has_bread:
				return PROMPT_TURN_IN
			return PROMPT_TALK
		&"vendor":
			return PROMPT_TALK if state == BUY_BREAD else ""
		&"car":
			return PROMPT_CAR
	return ""


func _set_state(new_state: StringName) -> void:
	var old := state
	state = new_state
	state_changed.emit(old, new_state)

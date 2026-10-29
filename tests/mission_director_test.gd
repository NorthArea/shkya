extends SceneTree
## Проверка логики миссии «За хлебом». Ожидания взяты из канона DEMO.md (разделы 5–6),
## а не из кода MissionDirector.

const Director = preload("res://game/mission/mission_director.gd")

const ORDER: Array[StringName] = [
	&"NOT_STARTED", &"OFFERED", &"GO_TO_CAR", &"DRIVE_TO_KIOSK",
	&"BUY_BREAD", &"RETURN_HOME", &"COMPLETE",
]
const COMMANDS: Array[StringName] = [
	&"interact_babka", &"interact_vendor", &"accept", &"decline",
	&"entered_car", &"arrived_kiosk", &"buy_bread",
]
## Раздел 6 канона: единственные допустимые переходы (состояние → команда → новое состояние).
const TRANSITIONS := {
	&"NOT_STARTED": {&"interact_babka": &"OFFERED"},
	&"OFFERED": {&"accept": &"GO_TO_CAR", &"decline": &"NOT_STARTED"},
	&"GO_TO_CAR": {&"entered_car": &"DRIVE_TO_KIOSK"},
	&"DRIVE_TO_KIOSK": {&"arrived_kiosk": &"BUY_BREAD"},
	&"BUY_BREAD": {&"buy_bread": &"RETURN_HOME"},
	&"RETURN_HOME": {&"interact_babka": &"COMPLETE"},
}

var failures: Array[String] = []
var checks := 0
var log_state_changes: Array = []
var log_bread := 0
var log_completed: Array = []
var made: Array[Node] = []
## COINS-01: деньги директора в проверках — собранные монетами 35 ₽ (сбор и подбор — tests/coins_test.gd, набор COINS).
const MONEY := 35


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("FAIL: test exceeded 30 simulated seconds")
		quit(2)
	)
	test_matrix()
	test_happy_path()
	test_decline_reaccept()
	test_refusals()
	test_markers()
	test_complete_irreversible()
	test_reset()
	test_objective_and_prompts()
	test_signals()
	test_insufficient_money()
	test_vendor_interact()
	test_babka_interact_results()
	_finish()


# --- помощники ---

func make() -> Node:
	var d: Node = Director.new()
	made.append(d)
	log_state_changes = []
	log_bread = 0
	log_completed = []
	d.state_changed.connect(func(o, n): log_state_changes.append([o, n]))
	d.bread_received.connect(func(): log_bread += 1)
	d.quest_completed.connect(func(x): log_completed.append(x))
	d.add_money(MONEY)   # монеты — COINS: 35 ₽ собраны по дороге (START_MONEY 0, решение владельца 29.10)
	return d


func cmd(d: Node, c: StringName):
	match c:
		&"interact_babka": return d.interact(&"babka")
		&"interact_vendor": return d.interact(&"vendor")
		&"accept": return d.accept()
		&"decline": return d.decline()
		&"entered_car": return d.notify_entered_car()
		&"arrived_kiosk": return d.notify_arrived_kiosk()
		&"buy_bread": return d.buy_bread()


## Ведёт директора по каноническому пути до состояния target.
func advance_to(d: Node, target: StringName) -> void:
	var path: Array[StringName] = [
		&"interact_babka", &"accept", &"entered_car", &"arrived_kiosk", &"buy_bread", &"interact_babka",
	]
	var i := 0
	while d.state != target and i < path.size():
		cmd(d, path[i])
		i += 1


func snap(d: Node) -> Array:
	return [d.state, d.has_bread, d.xp, d.money]


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)


# --- тесты ---

func test_matrix() -> void:
	for s in ORDER:
		for c in COMMANDS:
			var d := make()
			advance_to(d, s)
			check(d.state == s, "matrix setup: reached %s" % s)
			var before := snap(d)
			var changes_before := log_state_changes.size()
			var res = cmd(d, c)
			var allowed: Dictionary = TRANSITIONS.get(s, {})
			var label := "%s x %s" % [s, c]
			if allowed.has(c):
				check(d.state == allowed[c], label + " -> " + allowed[c])
				check(log_state_changes.size() == changes_before + 1, label + " emits one state_changed")
				if c != &"interact_babka":
					check(res == true, label + " returns true")
			else:
				check(snap(d) == before, label + " refused: nothing changed")
				check(log_state_changes.size() == changes_before, label + " refused: no state_changed")
				if c not in [&"interact_babka", &"interact_vendor"]:
					check(res == false, label + " returns false")
			check(log_bread == (1 if (s == &"RETURN_HOME" or s == &"COMPLETE") else 0) + (1 if (s == &"BUY_BREAD" and c == &"buy_bread") else 0),
				label + " bread_received count")


func test_happy_path() -> void:
	var d := make()
	check(d.state == &"NOT_STARTED" and not d.has_bread and d.xp == 0, "happy: initial state")
	check(Director.START_MONEY == 0, "happy: no starting money (COINS-01)")
	check(d.money >= 35, "happy: collected money covers price 35")
	var money0: int = d.money
	d.interact(&"babka")
	check(d.state == &"OFFERED", "happy: E at babka -> OFFERED")
	check(d.accept() and d.state == &"GO_TO_CAR", "happy: accept -> GO_TO_CAR")
	check(d.notify_entered_car() and d.state == &"DRIVE_TO_KIOSK", "happy: car -> DRIVE_TO_KIOSK")
	check(d.notify_arrived_kiosk() and d.state == &"BUY_BREAD", "happy: kiosk -> BUY_BREAD")
	check(d.can_buy_bread(), "happy: can buy bread at kiosk")
	check(d.buy_bread(), "happy: buy_bread succeeds")
	check(d.state == &"RETURN_HOME" and d.has_bread, "happy: RETURN_HOME with bread")
	check(d.money == money0 - 35, "happy: bread costs exactly 35")
	check(d.xp == 0, "happy: no XP before turn-in")
	check(d.interact(&"babka") == &"turn_in", "happy: E at babka returns turn_in")
	check(d.state == &"COMPLETE" and not d.has_bread and d.xp == 50, "happy: COMPLETE, bread removed, +50 XP")
	check(log_completed == [50], "happy: quest_completed(50) once")


func test_decline_reaccept() -> void:
	var d := make()
	d.interact(&"babka")
	check(d.decline() and d.state == &"NOT_STARTED", "decline: back to NOT_STARTED")
	check(d.babka_marker() == "!", "decline: ! visible again")
	check(d.interact(&"babka") == &"offer_dialog" and d.state == &"OFFERED", "decline: babka offers again")
	check(d.accept() and d.state == &"GO_TO_CAR", "decline: re-accept -> GO_TO_CAR")
	check(not d.accept() and not d.decline(), "decline: accept/decline refused after acceptance")


func test_refusals() -> void:
	# покупка без квеста (приехали к киоску, не взяв задание)
	var d := make()
	d.notify_arrived_kiosk()
	check(not d.can_buy_bread() and not d.buy_bread(), "refuse: buy without quest")
	check(not d.has_bread and d.money == MONEY and d.state == &"NOT_STARTED", "refuse: no-quest buy changes nothing")
	for s in [&"NOT_STARTED", &"OFFERED", &"GO_TO_CAR", &"DRIVE_TO_KIOSK"]:
		var e := make()
		advance_to(e, s)
		check(not e.buy_bread() and not e.has_bread, "refuse: buy in %s" % s)
	# повторная покупка
	d = make()
	advance_to(d, &"RETURN_HOME")
	var money: int = d.money
	check(not d.buy_bread(), "refuse: repeat buy")
	check(d.money == money and d.has_bread and log_bread == 1, "refuse: repeat buy keeps money, bread, one signal")
	# покупка после завершения
	d.interact(&"babka")
	check(not d.buy_bread() and not d.can_buy_bread(), "refuse: buy after COMPLETE")
	# сдача без хлеба: невозможна в любом состоянии, кроме RETURN_HOME (где хлеб всегда есть)
	for s in [&"NOT_STARTED", &"OFFERED", &"GO_TO_CAR", &"DRIVE_TO_KIOSK", &"BUY_BREAD"]:
		var e := make()
		advance_to(e, s)
		var r = e.interact(&"babka")
		check(r != &"turn_in" and e.xp == 0 and e.state != &"COMPLETE", "refuse: turn-in in %s" % s)
	# повторная награда
	d = make()
	advance_to(d, &"COMPLETE")
	check(d.interact(&"babka") != &"turn_in", "refuse: second turn-in result")
	d.interact(&"babka")
	check(d.xp == 50 and log_completed == [50], "refuse: XP awarded once")
	# несуществующий id
	check(d.interact(&"nobody") == &"none", "refuse: unknown id gives none")


func test_markers() -> void:
	var seen_question := false
	for s in ORDER:
		var d := make()
		advance_to(d, s)
		var m: String = d.babka_marker()
		var expect_bang: bool = s in [&"NOT_STARTED", &"OFFERED"]
		var expect_q: bool = s == &"RETURN_HOME"
		check((m == "!") == expect_bang, "marker ! only before acceptance (%s)" % s)
		check((m == "?") == expect_q, "marker ? only after purchase and before turn-in (%s)" % s)
		if not expect_bang and not expect_q:
			check(m == "", "marker empty in %s" % s)
		if m == "?":
			seen_question = true
			check(d.has_bread, "marker ? implies has_bread")
	check(seen_question, "marker ? appears at RETURN_HOME")


func test_complete_irreversible() -> void:
	var d := make()
	advance_to(d, &"COMPLETE")
	for c in COMMANDS:
		cmd(d, c)
	check(d.state == &"COMPLETE" and d.xp == 50 and not d.has_bread, "complete: all commands leave COMPLETE intact")
	check(d.babka_marker() == "", "complete: no marker")
	check(d.objective().target_id == &"", "complete: no target")


func test_reset() -> void:
	var d := make()
	advance_to(d, &"COMPLETE")
	d.reset()
	check(d.state == &"NOT_STARTED" and not d.has_bread and d.xp == 0 and d.money == Director.START_MONEY, "reset: from COMPLETE to initial values")
	check(d.babka_marker() == "!", "reset: ! back")
	check(d.interact(&"babka") == &"offer_dialog", "reset: mission playable again")
	advance_to(d, &"RETURN_HOME")
	d.reset()
	check(d.state == &"NOT_STARTED" and not d.has_bread and d.money == Director.START_MONEY, "reset: mid-mission clears bread and money")
	check(d.babka_marker() == "!", "reset: no ? after reset with bread")


func test_objective_and_prompts() -> void:
	# [состояние, заголовок, задача, цель] — тексты кадров 01–10 концептов
	var expected := [
		[&"NOT_STARTED", "ГОРОД Н.", "Подойди к Бабке", &"babka"],
		[&"OFFERED", "ЗА ХЛЕБОМ", "Прими задание", &"babka"],
		[&"GO_TO_CAR", "ЗА ХЛЕБОМ", "Сядь в машину", &"car"],
		[&"DRIVE_TO_KIOSK", "ЗА ХЛЕБОМ", "Доедь до киоска", &"kiosk"],
		[&"BUY_BREAD", "ЗА ХЛЕБОМ", "Поговори с продавщицей", &"vendor"],
		[&"RETURN_HOME", "ЗА ХЛЕБОМ", "Вернись к Бабке (самостоятельно)", &"babka"],
	]
	for row in expected:
		var d := make()
		advance_to(d, row[0])
		var o: Dictionary = d.objective()
		check(o.title == row[1] and o.task == row[2] and o.target_id == row[3], "objective in %s" % row[0])
	# по ситуации (POLISH-02, п. 16): рядом с Бабкой — кадры 02 и 09, у окна киоска — кадр 07
	var near := [
		[&"NOT_STARTED", &"babka", "Поговори с Бабкой"],
		[&"NOT_STARTED", &"vendor", "Подойди к Бабке"],
		[&"OFFERED", &"babka", "Прими задание"],
		[&"GO_TO_CAR", &"babka", "Сядь в машину"],
		[&"BUY_BREAD", &"vendor", "Купи хлеб"],
		[&"BUY_BREAD", &"babka", "Поговори с продавщицей"],
		[&"RETURN_HOME", &"babka", "Сдай хлеб Бабке"],
		[&"RETURN_HOME", &"vendor", "Вернись к Бабке (самостоятельно)"],
	]
	for row in near:
		var d := make()
		advance_to(d, row[0])
		var before := snap(d)
		d.set_nearby(row[1])
		check(d.objective().task == row[2], "objective in %s near %s: '%s'" % [row[0], row[1], d.objective().task])
		check(snap(d) == before, "set_nearby in %s changes no mission state" % row[0])
	var r := make()
	r.set_nearby(&"babka")
	r.reset()
	check(r.nearby == &"" and r.objective().task == "Подойди к Бабке", "reset clears nearby")
	var c := make()
	advance_to(c, &"COMPLETE")
	check(c.objective().title == "ЗА ХЛЕБОМ" and c.objective().task == "Сдай хлеб Бабке" and c.objective().target_id == &"", "objective in COMPLETE keeps the done task (struck out on the card)")
	# подсказки раздела 4 канона
	var d := make()
	check(d.prompt_for(&"babka") == "E — ПОГОВОРИТЬ", "prompt: babka talk")
	check(d.prompt_for(&"vendor") == "", "prompt: vendor unavailable before kiosk")
	check(d.prompt_for(&"car") == "E — СЕСТЬ В МАШИНУ", "prompt: car")
	advance_to(d, &"BUY_BREAD")
	check(d.prompt_for(&"vendor") != "", "prompt: vendor available in BUY_BREAD")
	advance_to(d, &"RETURN_HOME")
	check(d.prompt_for(&"babka") == "E — СДАТЬ ЗАДАНИЕ", "prompt: babka turn-in with bread")
	check(d.prompt_for(&"vendor") == "", "prompt: vendor unavailable after purchase")
	advance_to(d, &"COMPLETE")
	check(d.prompt_for(&"babka") != "E — СДАТЬ ЗАДАНИЕ", "prompt: no turn-in after COMPLETE")
	check(d.prompt_for(&"nobody") == "", "prompt: unknown id empty")
	# EXT-01: полицейский и «военком» — разговор доступен в любом состоянии, миссию не меняет
	for s in ORDER:
		var e := make()
		advance_to(e, s)
		var before := snap(e)
		check(e.prompt_for(&"officer") == "E — ПОГОВОРИТЬ" and e.prompt_for(&"account_officer") == "E — ПОГОВОРИТЬ", "prompt: observers talkable in %s" % s)
		check(e.interact(&"officer") == &"none" and e.interact(&"account_officer") == &"none" and snap(e) == before, "observers: interact changes nothing in %s" % s)
		check(e.can_turn_in() == (s == &"RETURN_HOME"), "can_turn_in only in RETURN_HOME (%s)" % s)
	var t := make()
	advance_to(t, &"RETURN_HOME")
	t.has_bread = false
	check(not t.can_turn_in() and t.prompt_for(&"babka") == "E — ПОГОВОРИТЬ", "can_turn_in needs bread")


func test_signals() -> void:
	var d := make()
	advance_to(d, &"COMPLETE")
	var expected_changes := [
		[&"NOT_STARTED", &"OFFERED"], [&"OFFERED", &"GO_TO_CAR"], [&"GO_TO_CAR", &"DRIVE_TO_KIOSK"],
		[&"DRIVE_TO_KIOSK", &"BUY_BREAD"], [&"BUY_BREAD", &"RETURN_HOME"], [&"RETURN_HOME", &"COMPLETE"],
	]
	check(log_state_changes == expected_changes, "signals: state_changed once per transition, in order")
	check(log_bread == 1, "signals: bread_received exactly once")
	check(log_completed == [50], "signals: quest_completed exactly once with 50")
	# повторные и недопустимые команды сигналов не шлют
	for c in COMMANDS:
		cmd(d, c)
	check(log_state_changes.size() == 6 and log_bread == 1 and log_completed.size() == 1, "signals: nothing after COMPLETE")
	# повторный вход в машину не шлёт сигнал
	var e := make()
	advance_to(e, &"DRIVE_TO_KIOSK")
	var n := log_state_changes.size()
	e.notify_entered_car()
	e.notify_entered_car()
	check(log_state_changes.size() == n, "signals: re-entering car is silent")
	# reset: один сигнал при смене, ни одного из NOT_STARTED
	e.reset()
	check(log_state_changes.size() == n + 1 and log_state_changes[-1] == [&"DRIVE_TO_KIOSK", &"NOT_STARTED"], "signals: reset emits once")
	e.reset()
	check(log_state_changes.size() == n + 1, "signals: reset at NOT_STARTED is silent")


## Канон разд. 5: покупка только если хватает денег (цена 35).
func test_insufficient_money() -> void:
	var d := make()
	advance_to(d, &"BUY_BREAD")
	d.money = 34
	var before := snap(d)
	var changes := log_state_changes.size()
	check(not d.can_buy_bread(), "money 34: can_buy_bread is false")
	check(not d.buy_bread(), "money 34: buy_bread refused")
	check(snap(d) == before and not d.has_bread, "money 34: state, bread, money unchanged")
	check(log_state_changes.size() == changes and log_bread == 0, "money 34: no signals")
	d.money = 35
	check(d.can_buy_bread() and d.buy_bread() and d.money == 0, "money 35: purchase allowed, money 0")


## Продавщица даёт диалог только в BUY_BREAD, состояние не меняется.
func test_vendor_interact() -> void:
	for s in ORDER:
		var d := make()
		advance_to(d, s)
		var before := snap(d)
		var changes := log_state_changes.size()
		var bread := log_bread
		var done := log_completed.size()
		var r: StringName = d.interact(&"vendor")
		var expect: StringName = &"vendor_dialog" if s == &"BUY_BREAD" else &"none"
		check(r == expect, "vendor interact in %s -> %s" % [s, expect])
		check(snap(d) == before, "vendor interact in %s: state unchanged" % s)
		check(log_state_changes.size() == changes and log_bread == bread and log_completed.size() == done,
			"vendor interact in %s: no signals" % s)


## Бабка: точный результат в каждом состоянии, лишних state_changed нет.
func test_babka_interact_results() -> void:
	var expected := {
		&"NOT_STARTED": &"offer_dialog", &"OFFERED": &"offer_dialog", &"GO_TO_CAR": &"babka_idle",
		&"DRIVE_TO_KIOSK": &"babka_idle", &"BUY_BREAD": &"babka_idle", &"RETURN_HOME": &"turn_in",
		&"COMPLETE": &"babka_idle",
	}
	for s in ORDER:
		var d := make()
		advance_to(d, s)
		var changes := log_state_changes.size()
		var r: StringName = d.interact(&"babka")
		check(r == expected[s], "babka interact in %s -> %s" % [s, expected[s]])
		var allowed: Dictionary = TRANSITIONS.get(s, {})
		var expect_changes := 1 if allowed.has(&"interact_babka") else 0
		check(log_state_changes.size() == changes + expect_changes, "babka interact in %s: %d state_changed" % [s, expect_changes])
	var o := make()
	o.interact(&"babka")
	var n := log_state_changes.size()
	check(o.interact(&"babka") == &"offer_dialog" and o.state == &"OFFERED", "OFFERED: repeat babka keeps OFFERED")
	check(log_state_changes.size() == n, "OFFERED: repeat babka sends no state_changed")


func _finish() -> void:
	for n in made:
		n.free()
	made.clear()
	print("MISSION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

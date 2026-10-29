extends SceneTree
## QUEST-01: квест «За хлебом» на настоящем main.tscn: кадры 01–10, диалоги, HUD, блокировка ввода, перезапуск.
## Вход в машину — DRIVE-01; здесь его имитирует прямой вызов mission.notify_entered_car().

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/quest01_driver.gd")
const CoinLines = preload("res://game/mission/coin_lines.gd")

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var flow: Node
var hud: CanvasLayer
var hands_before: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(600.0, true, false, true).timeout.connect(func():
		push_error("FAIL: quest01 exceeded 600 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.menu.start_button.pressed.emit()
	await _frames(10)
	_bind()
	check(world != null and flow != null and hud != null, "world, QuestFlow and GameHUD exist")
	if world == null or flow == null:
		_finish()
		return
	await _step01_spawn()
	await _step_kiosk_without_quest()
	await _step02_offer_and_blocking()
	await _step_esc_with_dialog()
	await _step_decline()
	await _step03_accept()
	await _step_observers()
	await _step_idle_babka()
	await _step04_05_car_and_drive()
	await _step06_arrive()
	await _step07_vendor_dialog()
	await _step08_09_bread_and_return()
	await _step10_complete()
	await _step_restart()
	await _real_car_pass()
	_finish()

func _bind() -> void:
	world = main.world
	flow = world.get_node("QuestFlow") if world else null
	hud = world.get_node("GameHUD") if world else null

# --- 01: появление ---

func _step01_spawn() -> void:
	var mission := world.mission
	hands_before = _hands()
	check(mission.state == MissionDirector.NOT_STARTED, "01: mission starts at NOT_STARTED")
	check(flow.marker.visible and flow.marker.text == "!", "01: ! above Babka before acceptance")
	check(flow.marker.get_parent() == world.babka, "01: marker is attached to Babka")
	check(flow.toast_text() == "" and not flow.is_dialog_open(), "01: no toast, no dialog at start")
	check(not hud.completion_panel.visible and not hud.speed_gauge.visible, "01: no completion panel, no speed gauge on foot")
	check(hud.title_label.text == "ГОРОД Н." and hud.task_label.text == "Подойди к Бабке", "01: card shows city title and task")
	check(hud.minimap != null and hud.minimap.size.x > 200.0, "01: minimap exists")
	# NPC «дышат» ±1,5 % и на время диалога поворачиваются к Илюше (POLISH-02, п. 21).
	var breath := []
	for i in 4:
		breath.append(world.babka.visual.scale.y)
		await _frames(25)
	check(breath.max() - breath.min() > 0.005 and breath.max() <= 1.0151 and breath.min() >= 0.9849, "01: Babka breathes within ±1.5%% %s" % [breath])
	world.player.place(Layout.BABKA + Vector3(2.0, 0, -0.5), 0.0)
	world.babka.look_at_target(world.player)
	await _frames(60)
	var to_player := world.player.global_position - world.babka.global_position
	var wanted := atan2(-to_player.x, -to_player.z)
	check(absf(angle_difference(world.babka.visual.global_rotation.y, wanted)) < 0.1, "01: Babka turns to Ilyusha (%.2f vs %.2f)" % [world.babka.visual.global_rotation.y, wanted])
	world.babka.stop_looking()
	await _frames(60)
	check(absf(angle_difference(world.babka.visual.rotation.y, 0.0)) < 0.1, "01: Babka turns back after the talk")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _frames(3)
	# Ромб: камера смотрит на Бабку — проекция у центра экрана; камера отвернулась — ромб прижат к краю.
	var to_babka := Layout.BABKA - world.player.global_position
	var babka_yaw := atan2(-to_babka.x, -to_babka.z)  # yaw 0 — север, PI — юг (Layout)
	world.camera_rig.yaw = babka_yaw
	await _frames(3)
	var canvas: Vector2 = hud._canvas_size()
	# Бабка в кадре и ближе 15 м: ромб спрятан, над ней уже «!» (POLISH-02, п. 17); проекция всё равно считается.
	check(not hud.diamond_clamped and hud.diamond_near_hidden and not hud.diamond_visible and not hud.diamond.visible, "01: diamond hidden when Babka is in frame and near")
	check(absf(hud.diamond_position.x - canvas.x * 0.5) < canvas.x * 0.1, "01: diamond projection near the screen centre (%s of %s)" % [hud.diamond_position, canvas])
	check(hud.minimap.route_points.size() >= 2 and hud.minimap.route_points[-1].distance_to(Vector2(Layout.BABKA.x, Layout.BABKA.z)) < 0.01, "01: minimap route line ends at Babka")
	world.camera_rig.yaw = babka_yaw + PI
	await _frames(3)
	check(hud.diamond_visible and hud.diamond_clamped, "01: diamond clamps to the edge when Babka is behind")
	var rect := Rect2(Vector2.ZERO, canvas)
	check(rect.has_point(hud.diamond_position), "01: clamped diamond stays inside the screen %s" % hud.diamond_position)
	_check_target(Layout.BABKA, "01")
	world.camera_rig.yaw = PI
	await _frames(2)

func _step_kiosk_without_quest() -> void:
	var mission := world.mission
	world.player.place(Layout.VENDOR_WINDOW, 0.0)
	await _frames(4)
	await _press_interact()
	check(not flow.is_dialog_open() and mission.state == MissionDirector.NOT_STARTED and not mission.has_bread, "buying without the quest is blocked at the kiosk")
	check(mission.money == MissionDirector.START_MONEY and flow.toast_text() == "", "no money spent, no toast without the quest")
	world.player.place(Layout.SPAWN, 0.0)
	await _frames(4)

# --- 02: диалог выдачи и блокировка ---

func _step02_offer_and_blocking() -> void:
	var mission := world.mission
	var player := world.player
	player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	check(hud.prompt_label.visible and hud.prompt_label.text == "E — ПОГОВОРИТЬ", "02: E prompt next to Babka")
	check(hud.prompt_plate.visible, "02: E prompt is on its plate")
	check(hud.task_label.text == "Поговори с Бабкой", "02: task 'Поговори с Бабкой' next to Babka (frame 02)")
	await _press_interact()
	check(flow.dialog.is_typing() and flow.dialog.text_label.visible_characters < flow.dialog.text_label.text.length(), "02: offer line is being typed")
	await _frames(120)
	check(not flow.dialog.is_typing(), "02: offer line (%d chars) typed out within ~2 s" % QuestLines.OFFER.length())
	check(flow.is_dialog_open() and mission.state == MissionDirector.OFFERED, "02: E opens the offer dialog, mission OFFERED")
	check(flow.dialog.text_label.text == QuestLines.OFFER and QuestLines.OFFER.contains("ты за хлебом"), "02: Babka offer text '%s'" % flow.dialog.text_label.text)
	check(flow.dialog.line_count() == 1 and flow.dialog.is_last_line(), "02: offer is a single line with choices")
	check(flow.dialog.buttons.has(&"accept") and flow.dialog.buttons[&"accept"].text == "ПРИНЯТЬ", "02: button ПРИНЯТЬ")
	check(flow.dialog.buttons.has(&"decline") and flow.dialog.buttons[&"decline"].text == "ОТКАЗАТЬСЯ", "02: button ОТКАЗАТЬСЯ")
	check(flow.marker.visible and flow.marker.text == "!", "02: marker is still ! while the offer is open")
	check(world.ui_blocking and not player.input_enabled, "02: dialog sets ui_blocking and stops Ilyusha input")
	check(not _mouse_captured(), "02: mouse is visible while the dialog is open")
	check(player.current_interactable() == null, "02: no interactable is served while the dialog is open")
	var before := player.global_position
	Input.action_press(&"move_forward")
	await _frames(30)
	Input.action_release(&"move_forward")
	check(player.global_position.distance_to(before) < 0.05, "02: Ilyusha does not walk while the dialog is open")
	await _press_interact()
	check(mission.state == MissionDirector.OFFERED and flow.is_dialog_open(), "02: E during the dialog changes nothing")
	var visible_texts := [flow.dialog.speaker_label.text, flow.dialog.text_label.text]
	check(visible_texts == ["БАБКА", QuestLines.OFFER], "02: dialog speaker and text are intact %s" % [visible_texts])

# --- отказ ---

func _step_decline() -> void:
	var mission := world.mission
	var player := world.player
	flow.dialog.buttons[&"decline"].pressed.emit()
	await _frames(3)
	check(mission.state == MissionDirector.NOT_STARTED, "decline: back to NOT_STARTED")
	check(not flow.is_dialog_open() and not world.ui_blocking and player.input_enabled, "decline: dialog closed, input restored")
	check(_mouse_captured(), "decline: mouse is captured again")
	check(flow.marker.visible and flow.marker.text == "!", "decline: marker is ! again")
	check(world.get_hud_state()["task"] == "Поговори с Бабкой", "decline: task next to Babka is 'Поговори с Бабкой' (frame 02)")
	await _frames(3)
	var before := player.global_position
	world.camera_rig.yaw = 0.0
	Input.action_press(&"move_back")
	await _frames(20)
	Input.action_release(&"move_back")
	check(player.global_position.distance_to(before) > 0.3, "decline: Ilyusha walks again")
	player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)

# --- 03: принять ---

func _step03_accept() -> void:
	var mission := world.mission
	await _press_interact()
	check(flow.is_dialog_open() and mission.state == MissionDirector.OFFERED, "03: E again re-opens the offer")
	flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(3)
	check(mission.state == MissionDirector.GO_TO_CAR, "03: ПРИНЯТЬ starts the quest (GO_TO_CAR)")
	check(not flow.is_dialog_open() and not world.ui_blocking and world.player.input_enabled, "03: dialog closed, input restored")
	check(not flow.marker.visible and flow.marker.text == "", "03: no marker above Babka after acceptance")
	check(hud.title_label.text == "ЗА ХЛЕБОМ" and hud.task_label.text == "Сядь в машину", "03: card is 'ЗА ХЛЕБОМ' / 'Сядь в машину'")
	_check_target(world.car.global_position, "03")

func _step_idle_babka() -> void:
	var mission := world.mission
	await _press_interact()
	check(flow.is_dialog_open() and flow.dialog.text_label.text == QuestLines.IDLE, "babka_idle: short line '%s'" % flow.dialog.text_label.text)
	check(flow.dialog.buttons.size() == 1 and flow.dialog.buttons.has(&"close"), "babka_idle: single close button")
	flow.dialog.buttons[&"close"].pressed.emit()
	await _frames(3)
	check(not flow.is_dialog_open() and mission.state == MissionDirector.GO_TO_CAR and mission.xp == 0, "babka_idle: state and XP unchanged")

# --- EXT-01: полицейский и «военком» (зоны исполнителя N; здесь — обработчик QuestFlow по id) ---

func _step_observers() -> void:
	var mission := world.mission
	var player := world.player
	check(mission.prompt_for(&"officer") == "E — ПОГОВОРИТЬ" and mission.prompt_for(&"account_officer") == "E — ПОГОВОРИТЬ", "ext: observers have the talk prompt")
	var before := [mission.state, mission.has_bread, mission.xp, mission.money]
	# Полицейский (TEXT-01): одна реплика, ответ Илюши — кнопкой выхода «ЗА ХЛЕБОМ».
	flow._on_interacted(player, &"officer")
	await _frames(2)
	check(flow.is_dialog_open() and world.ui_blocking and not player.input_enabled, "ext officer: dialog opens and blocks input")
	check(flow.dialog.line_count() == QuestLines.OFFICER_CHAIN.size() and QuestLines.OFFICER_CHAIN.size() == 1, "ext officer: one line (TEXT-01)")
	check(flow.dialog.speaker_label.text == "ПОЛИЦЕЙСКИЙ" and flow.dialog.text_label.text == QuestLines.OFFICER_CHAIN[0]["text"], "ext officer: line '%s'" % flow.dialog.text_label.text)
	check(flow.dialog.is_last_line() and flow.dialog.buttons.size() == 1 and flow.dialog.buttons[&"close"].text == QuestLines.BUTTON_OFFICER_LEAVE, "ext officer: exit button %s" % QuestLines.BUTTON_OFFICER_LEAVE)
	check(flow.dialog.is_typing(), "ext officer: line is being typed")
	await _press_interact()
	check(not flow.dialog.is_typing() and flow.dialog.line_index() == 0, "ext officer: E while typing only finishes the line")
	await _press_interact()
	check(flow.is_dialog_open() and flow.dialog.line_index() == 0, "ext officer: E on the last line changes nothing")
	flow.dialog.buttons[&"close"].pressed.emit()
	await _frames(3)
	check(not flow.is_dialog_open() and player.input_enabled and not world.ui_blocking, "ext officer: exit button closes, input restored")
	# «Военком»: оба ответа ведут к одной реплике, затем выход.
	for variant in [&"ride_no", &"ride_near"]:
		flow._on_interacted(player, &"account_officer")
		await _frames(2)
		check(flow.is_dialog_open() and flow.dialog.text_label.text == QuestLines.ACCOUNT_OFFICER_ASK["text"] and flow.dialog.speaker_label.text == "СОТРУДНИК ГСУМ", "ext ride (%s): question" % variant)
		check(flow.dialog.buttons.size() == 2 and flow.dialog.buttons[&"ride_no"].text == "НЕТ, СПАСИБО" and flow.dialog.buttons[&"ride_near"].text == "Я УЖЕ РЯДОМ", "ext ride (%s): two answers" % variant)
		flow.dialog.finish_typing()
		flow.dialog.buttons[variant].pressed.emit()
		await _frames(2)
		check(flow.is_dialog_open() and flow.dialog.text_label.text == QuestLines.ACCOUNT_OFFICER_REPLY["text"], "ext ride (%s): same reply to either answer" % variant)
		check(flow.dialog.buttons.size() == 1 and flow.dialog.buttons.has(&"close"), "ext ride (%s): one exit button" % variant)
		flow.dialog.buttons[&"close"].pressed.emit()
		await _frames(3)
		check(not flow.is_dialog_open() and player.input_enabled, "ext ride (%s): closed" % variant)
	check([mission.state, mission.has_bread, mission.xp, mission.money] == before, "ext: observers change no mission state")
	# Редакторский контроль: реплик наблюдателей и радио за миссию не больше 7.
	var observer_lines: int = QuestLines.OFFICER_CHAIN.size() + 2 + 1
	check(observer_lines <= 7, "ext: observers + radio lines per mission = %d (<= 7)" % observer_lines)
	var all_texts: Array = [QuestLines.OFFER, QuestLines.IDLE, QuestLines.IDLE_DONE, QuestLines.RADIO,
		QuestLines.ACCOUNT_OFFICER_ASK["text"], QuestLines.ACCOUNT_OFFICER_REPLY["text"], QuestLines.VENDOR_AGAIN,
		QuestLines.THANKS, QuestLines.THANKS_AFTER]
	for chain in [QuestLines.OFFICER_CHAIN, QuestLines.VENDOR_CHAIN, QuestLines.RETURN_CHAIN]:
		for line in chain:
			all_texts.append(line["text"])
	for text in all_texts:
		check(not text.to_lower().contains("мобилизац") and not text.to_lower().contains("бусификац"), "ext: forbidden words absent in '%s'" % text)

# --- 04/05: машина и дорога (вход в машину имитируется) ---

func _step04_05_car_and_drive() -> void:
	var mission := world.mission
	world.player.place(Layout.SPAWN, 0.0)
	await _frames(3)
	check(mission.notify_entered_car(), "04: entered car simulated via notify_entered_car()")
	await _frames(2)
	check(mission.state == MissionDirector.DRIVE_TO_KIOSK, "05: state DRIVE_TO_KIOSK")
	check(hud.task_label.text == "Доедь до киоска", "05: task 'Доедь до киоска'")
	_check_target(Layout.KIOSK, "05")
	await _frames(30)
	check(mission.state == MissionDirector.DRIVE_TO_KIOSK, "05: no arrival away from the kiosk zone")
	check(not flow.marker.visible, "05: no marker during the drive")

# --- 06: прибытие ---

func _step06_arrive() -> void:
	var mission := world.mission
	world.player.place(Layout.ROUTE_DRIVE[-1], 0.0)
	await _frames(6)
	check(mission.state == MissionDirector.BUY_BREAD, "06: arriving in the kiosk zone switches to BUY_BREAD")
	check(hud.task_label.text == "Поговори с продавщицей", "06: task 'Поговори с продавщицей'")
	check(world.mission.babka_marker() == "" and flow.marker.text == "" and not flow.marker.visible, "06: no ? (and no !) above Babka in BUY_BREAD")
	_check_target(Layout.VENDOR_WINDOW, "06")

# --- 07: диалог продавщицы ---

func _step07_vendor_dialog() -> void:
	var mission := world.mission
	var player := world.player
	player.place(Layout.VENDOR_WINDOW, 0.0)
	await _frames(4)
	check(hud.prompt_label.visible and hud.prompt_label.text == "E — ПОГОВОРИТЬ", "07: E prompt at the kiosk window")
	mission.money = 10  # условно не хватает денег (монеты — COINS: не хватает 25 ₽)
	await _press_interact()
	check(flow.is_dialog_open() and flow.dialog.text_label.text == QuestLines.VENDOR_CHAIN[0]["text"], "07: vendor chain starts with its first line ('%s')" % flow.dialog.text_label.text)
	check(flow.dialog.line_count() == QuestLines.VENDOR_CHAIN.size() + 1 and flow.dialog.line_index() == 0 and flow.dialog.buttons.has(&"next"), "07: vendor chain + refusal «Не хватает» (COINS-01), ДАЛЬШЕ first")
	check(hud.task_label.text == "Купи хлеб", "07: task 'Купи хлеб' at the window (frame 07)")
	check(flow.dialog.is_typing(), "07: vendor line is being typed")
	await _press_interact()
	check(not flow.dialog.is_typing() and flow.is_dialog_open() and flow.dialog.line_index() == 0, "07: E while typing completes the line and keeps the dialog")
	check(flow.dialog.speaker_label.text == "ПРОДАВЩИЦА", "07: speaker ПРОДАВЩИЦА")
	var expected_chain := []
	for line in QuestLines.VENDOR_CHAIN.slice(1):
		expected_chain.append([line["speaker"], line["text"]])
	expected_chain.append(["ПРОДАВЩИЦА", CoinLines.vendor_short(25)])   # COINS-01: при 10 ₽ — отказ с подсказкой последней репликой
	for i in expected_chain.size():
		flow.dialog.finish_typing()
		await _press_interact()  # E после допечатки — следующая реплика
		check(flow.dialog.line_index() == i + 1 and [flow.dialog.speaker_label.text, flow.dialog.text_label.text] == expected_chain[i], "07: line %d is %s" % [i + 1, expected_chain[i]])
		check(mission.state == MissionDirector.BUY_BREAD and not mission.has_bread, "07: chain line %d changes no state" % (i + 1))
	flow.dialog.finish_typing()
	check(flow.dialog.is_last_line() and not flow.dialog.buttons.has(&"next"), "07: last line has the choices, no ДАЛЬШЕ")
	var buy: Button = flow.dialog.buttons[&"buy"]
	check(buy.text == "КУПИТЬ ХЛЕБ" and buy.disabled, "07: КУПИТЬ ХЛЕБ is disabled when can_buy_bread() is false")
	check(flow.dialog.buttons[&"leave"].text == "УЙТИ", "07: button УЙТИ")
	buy.pressed.emit()
	await _frames(3)
	check(mission.state == MissionDirector.BUY_BREAD and not mission.has_bread and flow.toast_text() == "", "07: forced press on the disabled button buys nothing")
	check(flow.is_dialog_open(), "07: dialog stays open after a rejected purchase")
	flow.dialog.buttons[&"leave"].pressed.emit()
	await _frames(3)
	check(not flow.is_dialog_open() and mission.state == MissionDirector.BUY_BREAD and player.input_enabled, "07: УЙТИ closes the dialog, state unchanged")
	mission.money = MissionDirector.BREAD_PRICE   # монеты — COINS: собрано ровно на батон
	await _press_interact()
	check(flow.is_dialog_open() and flow.dialog.text_label.text == QuestLines.VENDOR_AGAIN and flow.dialog.line_count() == 1, "07: second approach is the short line, chain not repeated ('%s')" % flow.dialog.text_label.text)
	buy = flow.dialog.buttons[&"buy"]
	check(flow.is_dialog_open() and not buy.disabled, "07: КУПИТЬ ХЛЕБ is enabled when money is enough")

# --- 08/09: хлеб и возвращение ---

func _step08_09_bread_and_return() -> void:
	var mission := world.mission
	var player := world.player
	flow.dialog.buttons[&"buy"].pressed.emit()
	await _frames(2)
	check(mission.state == MissionDirector.RETURN_HOME and mission.has_bread, "08: purchase gives bread (RETURN_HOME, has_bread)")
	check(mission.money == 0, "08: 35 rubles spent (35 → 0)")
	check(not flow.is_dialog_open() and player.input_enabled and not world.ui_blocking, "08: dialog closed, input restored")
	check(flow.toast_text() == "ХЛЕБ +1" and hud.toast_label.visible and hud.toast_label.text == "ХЛЕБ +1", "08: toast ХЛЕБ +1 in the HUD")
	check(world.get_hud_state()["toast"] == "ХЛЕБ +1", "08: toast comes through get_hud_state() (C6)")
	check(_hands() == hands_before, "08: nothing appears in Ilyusha's hands (hands empty)")
	await _frames(60)
	check(flow.toast_text() == "ХЛЕБ +1", "08: toast still visible after ~1 s")
	await _frames(54)
	check(flow.toast_text() == "ХЛЕБ +1", "08: toast still visible after ~1.9 s")
	await _frames(12)
	check(flow.toast_text() == "" and not hud.toast_label.visible, "08: toast gone after ~2 s")
	check(flow.marker.visible and flow.marker.text == "?", "09: ? above Babka after the purchase")
	check(hud.task_label.text == MissionDirector.TASK_RETURN, "09: task '%s' (EXT-01)" % MissionDirector.TASK_RETURN)
	_check_target(Layout.BABKA, "09")
	await _press_interact()
	check(not flow.is_dialog_open() and mission.money == 0, "09: E at the kiosk after buying does nothing, no second purchase")
	player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	check(hud.prompt_label.text == "E — СДАТЬ ЗАДАНИЕ", "09: prompt 'E — СДАТЬ ЗАДАНИЕ' at Babka")
	check(hud.task_label.text == "Сдай хлеб Бабке", "09: task 'Сдай хлеб Бабке' next to Babka (frame 09)")

# --- 10: сдача ---

func _step10_complete() -> void:
	var mission := world.mission
	await _press_interact()
	# EXT-01, этап 9: сначала цепочка при возврате, сдача — кнопкой на последней реплике.
	check(flow.is_dialog_open() and flow.dialog.line_count() == QuestLines.RETURN_CHAIN.size() and flow.dialog.text_label.text == QuestLines.RETURN_CHAIN[0]["text"], "09: return chain opens with its first line ('%s')" % flow.dialog.text_label.text)
	check(mission.state == MissionDirector.RETURN_HOME and mission.has_bread and flow.marker.text == "?", "09: no turn-in before the chain ends")
	var expected_chain := []
	for line in QuestLines.RETURN_CHAIN.slice(1):
		expected_chain.append([line["speaker"], line["text"]])
	for i in expected_chain.size():
		flow.dialog.finish_typing()
		flow.dialog.buttons[&"next"].pressed.emit()
		await _frames(2)
		check([flow.dialog.speaker_label.text, flow.dialog.text_label.text] == expected_chain[i], "09: return line %d is %s" % [i + 1, expected_chain[i]])
	check(flow.dialog.is_last_line() and flow.dialog.buttons.size() == 1 and flow.dialog.buttons[&"turn_in"].text == "СДАТЬ ХЛЕБ", "09: last line offers СДАТЬ ХЛЕБ")
	check(mission.state == MissionDirector.RETURN_HOME and mission.xp == 0, "09: still RETURN_HOME before СДАТЬ ХЛЕБ")
	flow.dialog.buttons[&"turn_in"].pressed.emit()
	await _frames(1)
	check(mission.state == MissionDirector.COMPLETE and mission.xp == 50 and not mission.has_bread, "10: turn-in completes, +50 XP, bread consumed")
	check(flow.is_dialog_open() and flow.thanks_bubble.visible and flow.thanks_bubble.text == QuestLines.THANKS, "10: Babka says '%s' (bubble above her)" % QuestLines.THANKS)
	check(not flow.thanks_after_bubble.visible, "10: second bubble waits for the pause")
	check(not flow.dialog.is_open(), "10: only one panel - no dialog panel next to the completion panel")
	check(world.ui_blocking and not world.player.input_enabled, "10: input is blocked while the completion panel is open")
	await _frames(3)
	check(hud.completion_panel.visible, "10: completion panel is shown")
	check(_all_text(hud.completion_panel).has("ЗАДАНИЕ ВЫПОЛНЕНО") and _all_text(hud.completion_panel).has("+50 опыта"), "10: panel shows ЗАДАНИЕ ВЫПОЛНЕНО and +50 опыта")
	check(not flow.marker.visible, "10: no marker after completion")
	check(hud.strike.visible and hud.task_label.text == "Сдай хлеб Бабке", "10: the done task (not 'Задание выполнено') is struck out on the card")
	check(not hud.diamond_visible and not hud.diamond.visible and not hud.minimap.has_target, "10: no diamond and no minimap target after completion")
	check(_hands() == hands_before, "10: hands are empty")
	check(hud.completion_close.has_focus(), "10: ЗАКРЫТЬ has keyboard focus (closable without the mouse)")
	await _frames(60)
	check(flow.thanks_after_bubble.visible and flow.thanks_after_bubble.text == QuestLines.THANKS_AFTER and flow.thanks_bubble.visible, "10: second bubble '%s' after ~%.1f s, first stays" % [QuestLines.THANKS_AFTER, QuestLines.THANKS_PAUSE])
	# EXT-01 fix2 (P3): второй пузырь — на месте первого, у головы Бабки; первый поднимается над ним (читается сверху вниз).
	check(flow.thanks_after_back.global_position.y < flow.thanks_back.global_position.y, "10: second bubble sits below the first")
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	accept = accept.duplicate()
	accept.pressed = false
	Input.parse_input_event(accept)
	await _frames(3)
	check(not hud.completion_panel.visible and hud.is_end_card_open(), "10: ЗАКРЫТЬ (ui_accept) opens the «Конец демо» card")
	check(world.ui_blocking and flow.is_dialog_open() and not world.player.input_enabled, "10: input stays blocked under the «Конец демо» card")
	check(not flow.thanks_bubble.is_visible_in_tree() and not flow.thanks_after_bubble.is_visible_in_tree(), "10: thanks bubbles gone with the completion panel")
	await _frames(2)
	check(hud.end_buttons[&"again"].has_focus(), "10: ЕЩЁ РАЗ has keyboard focus")
	hud.end_buttons[&"stay"].pressed.emit()
	await _frames(3)
	check(not flow.is_dialog_open() and not hud.is_end_card_open() and not world.ui_blocking and world.player.input_enabled, "10: ПОГУЛЯТЬ closes the card, input restored")
	check(_mouse_captured(), "10: mouse captured after closing")
	var money_before := mission.money   # монеты у Бабки (COINS-01) подобраны раньше
	for i in 3:
		await _press_interact()
		check(flow.is_dialog_open() and flow.dialog.text_label.text == QuestLines.IDLE_DONE, "10: repeated talk %d is a plain line" % (i + 1))
		flow.dialog.buttons[&"close"].pressed.emit()
		await _frames(3)
	check(mission.xp == 50 and mission.state == MissionDirector.COMPLETE and not hud.completion_panel.visible, "10: XP is not awarded twice, panel does not return")
	check(mission.money == money_before, "10: money unchanged by repeated talks")

# --- перезапуск ---

func _step_restart() -> void:
	var old: DemoWorld = world
	await _press_interact()  # открытый диалог на момент перезапуска
	check(flow.is_dialog_open() and world.ui_blocking, "restart: a dialog is open before restarting")
	main.set_paused(true)
	main.pause_menu.restart_requested.emit()
	await _frames(6)
	check(not is_instance_valid(old), "restart: old world freed")
	_bind()
	_check_clean_start("restart from pause")
	var minimap_target: Vector2 = hud.minimap.target_world
	check(minimap_target.distance_to(Vector2(Layout.BABKA.x, Layout.BABKA.z)) < 0.01, "restart: minimap target is Babka again")
	# Через главное меню: сначала пройти до OFFERED, чтобы было что чистить.
	await _press_at_babka_open_offer()
	main.set_paused(true)
	main.pause_menu.menu_requested.emit()
	await _frames(3)
	check(main.world == null and main.menu.visible, "restart: back to the main menu")
	main.menu.start_button.pressed.emit()
	await _frames(6)
	_bind()
	_check_clean_start("start from menu")

func _press_at_babka_open_offer() -> void:
	world.player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	await _press_interact()
	check(flow.is_dialog_open() and world.mission.state == MissionDirector.OFFERED, "restart: new world offer dialog opens")

func _check_clean_start(label: String) -> void:
	var mission := world.mission
	check(mission.state == MissionDirector.NOT_STARTED and not mission.has_bread and mission.xp == 0 and mission.money == MissionDirector.START_MONEY, "%s: mission at NOT_STARTED, no bread, no XP, full money" % label)
	check(flow != null and not flow.is_dialog_open() and not world.ui_blocking and world.player.input_enabled, "%s: no dialog, input enabled" % label)
	check(flow.toast_text() == "" and not hud.toast_label.visible, "%s: no toast left over" % label)
	check(not hud.completion_panel.visible and not hud.completion_dismissed, "%s: no completion panel left over" % label)
	check(flow.marker.text == "!" and flow.marker.visible, "%s: marker is ! again" % label)
	check(_mouse_captured(), "%s: mouse is captured" % label)

# --- служебное ---

## Цель HUD: C6 target_position, ромб и мини-карта следуют за целью цели миссии.
func _check_target(expected: Vector3, label: String) -> void:
	var state := world.get_hud_state()
	var target = state["target_position"]
	check(target is Vector3 and target.distance_to(expected) < 0.01, "%s: C6 target_position follows the objective %s" % [label, expected])
	await_frame_sync()
	check(hud.minimap.has_target and hud.minimap.target_world.distance_to(Vector2(expected.x, expected.z)) < 0.5, "%s: minimap target follows the objective (%s)" % [label, hud.minimap.target_world])
	# Ромб виден, если цель не рядом в кадре; рядом и в кадре — спрятан (POLISH-02, п. 17).
	check(hud.diamond_visible == hud.diamond.visible and (hud.diamond_visible or hud.diamond_near_hidden), "%s: yellow diamond is visible or hidden only near and in frame" % label)
	check(hud.minimap.route_points.size() >= 2 and hud.minimap.route_points[-1].distance_to(Vector2(expected.x, expected.z)) < 0.5, "%s: minimap route line ends at the target" % label)

func await_frame_sync() -> void:
	# HUD обновляется в _process; достаточно вызвать его вручную для текущего снимка.
	hud._process(0.0)

## В headless DisplayServer не хранит режим мыши, поэтому читаем запрос QuestFlow.
func _mouse_captured() -> bool:
	if DisplayServer.get_name() == "headless":
		return flow.wants_mouse_captured
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _hands() -> Array:
	var names := []
	for node in world.player.find_children("*", "", true, false):
		names.append(String(node.name))
	return names

func _all_text(node: Node) -> Array:
	var out := []
	for child in node.find_children("*", "Label", true, false):
		out.append((child as Label).text)
	return out

func _press_interact() -> void:
	var down := InputEventAction.new()
	down.action = &"interact"
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

## Долистать цепочку реплик до последней (кнопки выбора — только на ней).
func _to_last_line() -> void:
	while flow.is_dialog_open() and not flow.dialog.is_last_line():
		flow.dialog.finish_typing()
		flow.dialog.advance()
	flow.dialog.finish_typing()

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("QUEST01: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

# --- Esc при открытом диалоге ---

func _step_esc_with_dialog() -> void:
	var player := world.player
	check(flow.is_dialog_open(), "esc: the offer dialog is open before Esc")
	var pause := InputEventAction.new()
	pause.action = &"pause"
	pause.pressed = true
	Input.parse_input_event(pause)
	await _frames(3)
	check(paused and main.pause_menu.visible, "esc: Esc over the dialog opens the pause menu")
	check(flow.is_dialog_open(), "esc: the dialog stays open under the pause menu")
	main.pause_menu.resume_requested.emit()
	await _frames(3)
	check(not paused and flow.is_dialog_open() and world.ui_blocking and not player.input_enabled, "esc: after resume the dialog is still open and input still blocked")
	check(not flow.wants_mouse_captured, "esc: after resume the mouse is still wanted visible")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _frames(3)
	check(world.ui_blocking and flow.is_dialog_open() and not player.input_enabled, "esc: a click on the world does not unblock input")
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN: esc: real Input.mouse_mode stays VISIBLE after resume and click (headless DisplayServer has no mouse mode); checked in tools/capture/quest01_capture.gd")
	else:
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "esc: Input.mouse_mode stays VISIBLE after resume and click")

# --- полный проход с настоящей машиной ---

func _real_car_pass() -> void:
	# Новый мир после перезапуска из меню. Вход в машину, езда, выход и повторный вход — только настоящие E и WASD.
	var mission := world.mission
	var player := world.player
	var car: Lada = world.car
	var driver := Driver.new(self, world)
	var near_babka := Layout.BABKA + Vector3(0, 0, -2.2)
	check(mission.state == MissionDirector.NOT_STARTED, "real: fresh world")
	player.place(near_babka, PI)
	await _frames(4)
	await _press_interact()
	flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(3)
	check(mission.state == MissionDirector.GO_TO_CAR, "real: quest accepted")
	player.place(car.global_position + Vector3(2.2, 0, 0), 0.0)
	await _frames(4)
	check(hud.prompt_label.visible and hud.prompt_label.text == "E — СЕСТЬ В МАШИНУ", "real: E prompt at the car")
	await _press_interact()
	await _frames(4)
	check(world.control_mode == &"in_car" and mission.state == MissionDirector.DRIVE_TO_KIOSK, "real: E enters the Lada, mission DRIVE_TO_KIOSK")
	check(hud.task_label.text == "Доедь до киоска", "real: task 'Доедь до киоска' in the car")
	var route: Array = Layout.ROUTE_DRIVE.slice(1)
	var drove: bool = await driver.drive(route, 12.0, 6.0)
	check(drove, "real: Lada drove along ROUTE_DRIVE to the kiosk by WASD input")
	var max_kmh := 0.0
	check(mission.state == MissionDirector.BUY_BREAD, "real: arrival switched the mission to BUY_BREAD (state %s)" % mission.state)
	check(await driver.stop(), "real: Lada stopped at the kiosk")
	check(world.get_hud_state()["speed_kmh"] >= 0.0 and hud.speed_gauge.visible, "real: speed gauge is shown in the car")
	await _press_interact()
	await _frames(6)
	check(world.control_mode == &"on_foot", "real: E exits the Lada at the kiosk")
	var parked := car.global_transform
	# COINS-01: деньги — монеты, подобранные «Ладой» по ROUTE_DRIVE и Илюшей во дворе (без add_money).
	check(mission.money >= MissionDirector.BREAD_PRICE, "real: coins collected on the way cover the bread (%d ₽)" % mission.money)
	player.place(Layout.VENDOR_WINDOW, PI * 0.5)
	await _frames(4)
	await _press_interact()
	_to_last_line()
	check(flow.is_dialog_open() and flow.dialog.buttons.has(&"buy") and not flow.dialog.buttons[&"buy"].disabled, "real: vendor dialog with enabled КУПИТЬ ХЛЕБ")
	flow.dialog.buttons[&"buy"].pressed.emit()
	await _frames(3)
	check(mission.state == MissionDirector.RETURN_HOME and mission.has_bread and flow.toast_text() == "ХЛЕБ +1", "real: bread bought, toast shown")
	# Повторный вход в машину: игрок рядом с дверью.
	player.place(car.global_position + car.global_basis.x * 2.2, 0.0)
	await _frames(4)
	await _press_interact()
	await _frames(4)
	check(world.control_mode == &"in_car" and mission.state == MissionDirector.RETURN_HOME, "real: re-entered the Lada, state stays RETURN_HOME")
	check(flow.marker.text == "?" and flow.marker.visible, "real: ? above Babka while returning")
	# Разворот (EXT-01): машина стоит на парковке южнее павильона носом на запад-северо-запад. Разворот налево по
	# свободному пустырю западнее тротуара и выезд через разрыв западного вала на улицу Б (Layout.ROUTE_LEAVE_KIOSK),
	# потом — маршрут в обратном порядке без двух последних точек, настоящей ездой. Никаких телепортов машины.
	var turned: bool = await driver.drive(Layout.ROUTE_LEAVE_KIOSK, 8.0, 3.0)
	check(turned, "real: Lada turned around on the lot by the parking and left through the bank gap onto street B")
	var back: Array = Layout.ROUTE_DRIVE.slice(0, Layout.ROUTE_DRIVE.size() - 2)
	back.reverse()
	var returned: bool = await driver.drive(back, 12.0, 6.0)
	check(returned, "real: Lada drove back to the yard along the route in reverse order")
	check(await driver.stop(), "real: Lada stopped in the yard")
	await _press_interact()
	await _frames(6)
	check(world.control_mode == &"on_foot", "real: E exits the Lada in the yard")
	player.place(near_babka, PI)
	await _frames(4)
	check(hud.prompt_label.text == "E — СДАТЬ ЗАДАНИЕ", "real: prompt 'E — СДАТЬ ЗАДАНИЕ' at Babka")
	await _press_interact()
	_to_last_line()
	check(flow.is_dialog_open() and flow.dialog.buttons.has(&"turn_in"), "real: return chain ends with СДАТЬ ХЛЕБ")
	flow.dialog.buttons[&"turn_in"].pressed.emit()
	await _frames(3)
	check(mission.state == MissionDirector.COMPLETE and mission.xp == 50 and hud.completion_panel.visible, "real: turn-in completes, +50 XP, panel shown")
	hud.completion_close.pressed.emit()
	await _frames(3)
	check(hud.is_end_card_open() and world.ui_blocking, "real: «Конец демо» card after ЗАКРЫТЬ")
	if parked.origin.distance_to(car.global_position) < 1.0:
		check(false, "real: the car actually left the kiosk")
	driver.world = null
	driver.tree = null
	# «ЕЩЁ РАЗ»: новый мир с NOT_STARTED, как из меню (POLISH-02, п. 11).
	var old: DemoWorld = world
	hud.end_buttons[&"again"].pressed.emit()
	await _frames(6)
	check(not is_instance_valid(old) and main.world != null, "again: ЕЩЁ РАЗ replaces the world")
	_bind()
	_check_clean_start("again")
	check(not main.menu.visible and not hud.is_end_card_open(), "again: no menu and no end card in the new world")

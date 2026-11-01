extends SceneTree
## QA-01: независимая приёмка демо по разделу 8 канона (docs/DEMO.md) и FSM раздела 6.
## Ожидания взяты из канона и контрактов C1–C6 (docs/workflow/README.md), не из кода авторов.
##
## Проход 1 (кадры 01→10) и проход 2 после перезапуска из главного меню. Всё действие — ввод
## (tests/playthrough_driver.gd): никаких телепортов и прямых команд миссии. Тест только читает состояние.
## Отклонения: отказ, сдача без хлеба, выход из машины посреди пути и повторный вход, неудачная парковка
## и «Сбросить автомобиль» из паузы, повторная покупка, повторное E у Бабки после награды, покупка после
## завершения, покупка без квеста, «Начать заново» из паузы.
## Каждый физический кадр монитор проверяет инварианты сценариев 2, 3, 4, 7.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/demo_acceptance.gd
## Кадры (сценарий 4): tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/demo_acceptance.gd -- --capture
##   → builds/screenshots/qa01/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const Uniform = preload("res://game/characters/uniform_visual.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
const SeatedVisual = preload("res://game/vehicles/lada_driver.gd")
const OUT := "res://builds/screenshots/qa01"

const SCENARIOS := {
	1: "Полный проход 01→10 без перезапуска, зависаний и ручных команд; повторный запуск",
	2: "Жёлтый ! только до принятия, ? только когда хлеб куплен и квест готов к сдаче",
	3: "Покупка даёт ровно +1 в логический инвентарь; физического батона или пакета нет",
	4: "Одинаковый зимний костюм всю игру, в том числе при входе и выходе из машины",
	5: "«Сбросить автомобиль» из паузы возвращает машину в доступное положение",
	6: "Повторное E у Бабки не даёт награды; покупка недоступна после её завершения",
	7: "Мини-карта и маркеры указывают на текущую цель",
	8: "FPS на выбранной тестовой конфигурации",
}

var main: Node
var drv
var capture := false
var results := {}         # сценарий -> [pass, fail]
var failures: Array[String] = []
var started_usec := 0

# Монитор
var _world: DemoWorld
var transitions: Array = []      # [old, new] текущего мира
var bread_edges := 0             # has_bread false → true за мир
var _had_bread := false
var completed_signals := 0
var _player_signature := ""
var _kiosk_goods: Array = []    # хлеб-декор на витрине киоска при создании мира
var mon := {}                    # имя инварианта -> {frames, bad, first}
var _lag := {}                   # подряд идущие нарушения (допуск 1 кадр отставания _process от физики)
var textures_seen := {}
var toast_frames := 0
var sim_frames := 0
var _outfit_heights := Vector2.ZERO
var _outfit_meshes: Array[Mesh] = []
var _seated_leg_poses: Array[Quaternion] = []
var _player_capsule := Vector2.ZERO
var _player_collider_transform := Transform3D.IDENTITY
var _ram_trace_active := false
var _ram_trace_hits: Dictionary = {}
var _ram_max_snow_depth := 0.0
var _ram_max_snow_lift := 0.0
var pass_frames := {}            # проход -> кадров

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	create_timer(1500.0, true, false, true).timeout.connect(func():
		_fail_check(1, "whole run finished within 1500 simulated seconds (hang)")
		_report()
		quit(2))
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	drv.on_frame = _monitor
	await drv.frames(5)
	var ok := await _pass_one()
	if ok:
		await _pass_two()
	_report()
	drv.release_all()
	drv.on_frame = Callable()
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	_outfit_meshes.clear()
	main.queue_free()
	main = null
	_world = null
	drv = null
	for i in 10:
		await process_frame
	# The mixer releases stopped playbacks on its wall clock.
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)

# =====================================================================================
# Проход 1: 01 → 10 с отклонениями
# =====================================================================================

func _pass_one() -> bool:
	var start_frame := sim_frames
	print("--- PASS 1 ---")
	# Главное меню → НАЧАТЬ (клавиатурой: фокус на кнопке, ui_accept)
	check(1, main.world == null and _visible_texts(main).has("НАЧАТЬ"), "menu: main menu with НАЧАТЬ is shown at launch")
	if not check(1, await drv.press_button("НАЧАТЬ", &"ui_down"), "menu: НАЧАТЬ pressed from keyboard (%s)" % drv.last_error):
		return false
	await drv.frames(10)
	if not check(1, main.world != null, "menu: НАЧАТЬ creates the world"):
		return false
	var w: DemoWorld = main.world
	var m := w.mission
	await drv.frames(5)

	# 01 — появление во дворе
	check(1, m.state == &"NOT_STARTED", "01: mission starts at NOT_STARTED (got %s)" % m.state)
	check(1, _near2(w.player.global_position, Layout.SPAWN, 0.5), "01: Ilyusha spawns at Layout.SPAWN")
	check(1, _hud_has(w, "Подойди к Бабке"), "01: HUD task «Подойди к Бабке»")
	check(2, _babka_symbol(w) == "!", "01: yellow ! above Babka")
	await _shot("01_spawn", true)

	# 02 — к Бабке, «E — ПОГОВОРИТЬ»
	if not check(1, await drv.walk_to(_babka_stand()), "02: walked to Babka (%s)" % drv.last_error):
		return false
	check(1, _hud_has(w, "E — ПОГОВОРИТЬ"), "02: prompt «E — ПОГОВОРИТЬ» near Babka")
	check(6, not _hud_has(w, "E — СДАТЬ ЗАДАНИЕ"), "02: no turn-in prompt before the quest")
	await _shot("02_talk_prompt", true)

	# 03 — диалог выдачи: сначала отказ, потом принятие
	await drv.interact()
	await drv.frames(5)
	check(1, m.state == &"OFFERED", "03: E at Babka → OFFERED (got %s)" % m.state)
	check(1, _hud_has(w, QuestLines.OFFER), "03: offer line from the extension canon (stage 1)")
	check(1, _hud_has(w, "ПРИНЯТЬ") and _hud_has(w, "ОТКАЗАТЬСЯ"), "03: buttons ПРИНЯТЬ and ОТКАЗАТЬСЯ")
	check(2, _babka_symbol(w) == "!", "03: ! stays while the offer is open")
	if not check(1, await drv.press_button("ОТКАЗАТЬСЯ"), "03: ОТКАЗАТЬСЯ pressed (%s)" % drv.last_error):
		return false
	await drv.frames(3)
	check(1, m.state == &"NOT_STARTED", "decline: ОТКАЗАТЬСЯ → NOT_STARTED (got %s)" % m.state)
	check(1, not _hud_has(w, QuestLines.OFFER), "decline: dialog closed")
	check(2, _babka_symbol(w) == "!", "decline: ! is back above Babka")
	check(1, await _can_walk(w), "decline: Ilyusha can move after the dialog")
	await drv.walk_to(_babka_stand())
	await drv.interact()
	await drv.frames(5)
	check(1, m.state == &"OFFERED", "03: second E → OFFERED")
	await _shot("03_offer_dialog", false)
	if not check(1, await drv.press_button("ПРИНЯТЬ"), "03: ПРИНЯТЬ pressed (%s)" % drv.last_error):
		return false
	await drv.frames(3)
	check(1, m.state == &"GO_TO_CAR", "03: ПРИНЯТЬ → GO_TO_CAR (got %s)" % m.state)
	check(1, _hud_has(w, "ЗА ХЛЕБОМ"), "03: quest «За хлебом» started in the HUD")
	check(2, _babka_symbol(w) == "", "03: ! gone after acceptance")

	# Сдача без хлеба: E у Бабки до покупки
	await drv.interact()
	await drv.frames(5)
	check(6, m.state == &"GO_TO_CAR" and m.xp == 0 and not m.has_bread, "no bread: E at Babka changes nothing (state %s, xp %d)" % [m.state, m.xp])
	check(6, not _hud_has(w, "ЗАДАНИЕ ВЫПОЛНЕНО") and not _hud_has(w, "+50 опыта"), "no bread: no completion panel")
	check(2, _babka_symbol(w) == "", "no bread: no ? above Babka")
	await _close_any_dialog(w)

	# 04 — к машине, «E — СЕСТЬ В МАШИНУ»
	if not check(1, await drv.walk_to(_car_stand(w)), "04: walked to the Lada (%s)" % drv.last_error):
		return false
	check(1, _hud_has(w, "E — СЕСТЬ В МАШИНУ"), "04: prompt «E — СЕСТЬ В МАШИНУ»")
	await _shot("04_at_car", true)
	await drv.interact()
	await drv.frames(10)
	check(1, w.control_mode == &"in_car", "04: E → in the car")
	check(1, m.state == &"DRIVE_TO_KIOSK", "04: entering the car → DRIVE_TO_KIOSK (got %s)" % m.state)
	check(4, not w.player.visible, "04: Ilyusha is hidden in the car (C4)")
	await _shot("04b_entered_car", false)

	# 05 — поездка по route_drive (C1), выход посреди пути и повторный вход
	var route: Array = Layout.ROUTE_DRIVE.slice(1)
	if not check(1, await drv.drive_path(route.slice(0, 3)), "05: drove the yard part of route_drive (%s)" % drv.last_error):
		return false
	check(1, _hud_speed_visible(w), "05: speed gauge in the car")
	await _shot("05_drive", false)
	var car: Lada = w.car
	if not check(1, await drv.drive_path([route[3]], 13.0, 5.0, func(): return car.global_position.x > 15.0), "05: drove onto street A (%s)" % drv.last_error):
		return false
	var speed_at_exit := car.speed_kmh()
	await drv.interact()   # на ходу
	var exited := false
	for i in 300:
		await drv.frames(1)
		if w.control_mode == &"on_foot":
			exited = true
			break
	drv.release_all()
	check(1, exited, "midway: E at %.0f km/h → car brakes and Ilyusha gets out" % speed_at_exit)
	check(1, m.state == &"DRIVE_TO_KIOSK", "midway: exit keeps DRIVE_TO_KIOSK (got %s)" % m.state)
	check(4, w.player.visible and w.player.global_position.distance_to(car.global_position) < 5.0, "midway: Ilyusha stands next to the car, visible")
	check(1, not _hud_speed_visible(w), "midway: no speed gauge on foot")
	await _shot("05b_exit_midway", true)
	var away := w.player.global_position + (w.player.global_position - car.global_position).normalized() * 2.5
	# Точка выбрана вслепую и может лечь в вал у бордюра: отойти хотя бы на ~1,7 м (допуск 0,8).
	check(1, await drv.walk_to(away, 0.8), "midway: walked away from the car (%s)" % drv.last_error)
	if not check(1, await drv.walk_to(_car_stand(w)), "midway: walked back to the car (%s)" % drv.last_error):
		return false
	var n_before := transitions.size()
	await drv.interact()
	await drv.frames(10)
	check(1, w.control_mode == &"in_car" and m.state == &"DRIVE_TO_KIOSK" and transitions.size() == n_before, "midway: re-entering changes no mission state")

	# Неудачная парковка у настоящей стены: снег на северной обочине проезжаем
	# по C10, поэтому он не может служить неподвижным упором для этой проверки.
	var ram_wall: Array = []
	for solid: Array in Layout.SOLIDS:
		if solid[0] == "H7_Middle":
			ram_wall = solid
			break
	if ram_wall.is_empty():
		check(5, false, "reset: canonical H7_Middle wall fixture is present")
		return false
	var ram_centre: Vector2 = ram_wall[2]
	var ram_target := Vector3(ram_centre.x, 0, ram_centre.y)
	print("DEMO_RAM_BEGIN: ", JSON.stringify({"car": str(car.global_transform), "target": str(ram_target), "wall": String(ram_wall[0]), "scope": "input-only approach across traversable snow to the canonical solid wall"}))
	_ram_trace_hits.clear()
	_ram_max_snow_depth = 0.0
	_ram_max_snow_lift = 0.0
	_ram_trace_active = true
	var pinned: int = await drv.ram(ram_target)
	_ram_trace_active = false
	print("DEMO_RAM_TRACE: ", JSON.stringify({"target": str(ram_target), "final": str(car.global_transform), "low_speed_frames": pinned, "maximum_snow_depth": _ram_max_snow_depth, "maximum_snow_lift": _ram_max_snow_lift, "collider_contacts": _ram_trace_hits}))
	var parked_at := car.global_position
	check(5, pinned >= 60, "reset: car reaches the real wall across traversable snow and is pinned (%d frames) at %s" % [pinned, parked_at])
	check(5, int(_ram_trace_hits.get("LevelGeometry/" + String(ram_wall[0]), 0)) > 0, "reset: actual Lada slide contacts identify the canonical H7_Middle wall")
	await drv.pause_key()
	await drv.frames(3)
	check(5, paused and _visible_texts(main).has("СБРОСИТЬ АВТОМОБИЛЬ"), "reset: Esc opens pause with «СБРОСИТЬ АВТОМОБИЛЬ»")
	await _shot("05c_pause_menu", false)
	if not check(5, await drv.press_button("СБРОСИТЬ АВТОМОБИЛЬ", &"ui_down"), "reset: «СБРОСИТЬ АВТОМОБИЛЬ» pressed (%s)" % drv.last_error):
		return false
	await drv.frames(10)
	check(5, not paused, "reset: game resumes after reset")
	check(5, w.control_mode == &"in_car", "reset: still in the car")
	check(5, car.speed_kmh() < 1.0, "reset: car stands still (%.1f km/h)" % car.speed_kmh())
	var on_route := _distance_to_route(car.global_position)
	check(5, on_route < 1.5, "reset: car is on route_drive (%.2f m off, at %s)" % [on_route, car.global_position])
	check(5, _car_clear(car), "reset: car footprint overlaps no solid box of Layout")
	check(5, absf(car.global_position.y) < 0.3, "reset: car on the ground (y %.2f)" % car.global_position.y)
	check(5, m.state == &"DRIVE_TO_KIOSK", "reset: mission state unchanged (%s)" % m.state)
	print("INFO: reset moved the car %s → %s" % [parked_at, car.global_position])
	# POLISH-03 B: прямой путь не набирает 35 ₽ — дальше с вылазкой за гаражи двора (ROUTE_DRIVE_HUNT с улицы A).
	if not check(5, await drv.drive_path(Layout.ROUTE_DRIVE_HUNT.slice(4)), "reset: from the reset spot the car drives on to the kiosk with one detour behind the yard garages (%s)" % drv.last_error):
		return false

	# 06 — прибытие, выход
	check(1, m.state == &"BUY_BREAD", "06: arriving in the kiosk zone → BUY_BREAD (got %s)" % m.state)
	await drv.brake()
	await drv.interact()
	await drv.frames(15)
	check(1, w.control_mode == &"on_foot", "06: E → out of the car at the kiosk")
	check(4, w.player.visible, "06: Ilyusha visible after exit")
	await _shot("06_arrive_kiosk", true)

	# 07 — продавщица: цепочка реплик (EXT-01, этап 6) с «ДАЛЬШЕ», сначала УЙТИ, потом КУПИТЬ ХЛЕБ
	# EXT-01, этап 4: от парковки к окну — честный путь «за остановкой» с ожиданием разворота полицейского.
	if not check(1, await _sneak(Layout.SNEAK_EAST), "07: sneaked from the parking to the kiosk window behind the stop (%s)" % drv.last_error):
		return false
	if not check(1, w.stealth.detections == 0, "07: not detected on the way to the window (%d)" % w.stealth.detections):
		return false
	check(1, _hud_has(w, "E — ПОГОВОРИТЬ"), "07: prompt at the vendor")
	await drv.interact()
	await drv.frames(5)
	check(1, _hud_has(w, QuestLines.VENDOR_CHAIN[0]["text"]) and _hud_has(w, "ДАЛЬШЕ"), "07: vendor chain starts «%s» with ДАЛЬШЕ" % QuestLines.VENDOR_CHAIN[0]["text"])
	check(1, not _hud_has(w, "КУПИТЬ ХЛЕБ"), "07: no purchase button before the chain ends")
	var chain := QuestLines.VENDOR_CHAIN.slice(1).map(func(l): return l["text"])
	for line in chain:
		await drv.frames(40)  # дождаться допечатки: первое нажатие во время печати лишь дописывает
		if not check(1, await drv.press_button("ДАЛЬШЕ"), "07: ДАЛЬШЕ pressed before «%s» (%s)" % [line, drv.last_error]):
			return false
		await drv.frames(3)
		check(1, _hud_has(w, line), "07: chain line «%s»" % line)
		check(3, m.state == &"BUY_BREAD" and not m.has_bread, "07: chain line «%s» changes nothing" % line)
	await _shot("07_vendor_chain", false)
	check(1, _hud_has(w, "КУПИТЬ ХЛЕБ") and _hud_has(w, "УЙТИ") and not _hud_has(w, "ДАЛЬШЕ"), "07: buttons КУПИТЬ ХЛЕБ and УЙТИ on the last line")
	if not check(1, await drv.press_button("УЙТИ"), "07: УЙТИ pressed (%s)" % drv.last_error):
		return false
	await drv.frames(3)
	check(3, m.state == &"BUY_BREAD" and not m.has_bread and _spent(w) == 0, "07: УЙТИ buys nothing (state %s, money %d)" % [m.state, m.money])
	await drv.interact()
	await drv.frames(5)
	check(1, _hud_has(w, "Батон? 35 рублей") and not _hud_has(w, QuestLines.VENDOR_CHAIN[0]["text"]), "07: second approach is the short line, chain not repeated")
	await _shot("07_vendor_dialog", false)
	var money_before: int = m.money
	# COINS-01 / POLISH-03 B: стартовых денег нет — 35 ₽ собраны монетами (двор, «Лада» с вылазкой за гаражи, путь к окну).
	check(1, money_before >= 35, "07: coins collected on the way cover the bread (%d ₽, %d coins)" % [money_before, _coins(w).collected_count])
	if not check(1, await drv.press_button("КУПИТЬ ХЛЕБ", &"ui_left"), "07: КУПИТЬ ХЛЕБ pressed (%s)" % drv.last_error):
		return false
	await drv.frames(2)

	# 08 — хлеб в логическом инвентаре
	check(1, m.state == &"RETURN_HOME", "08: purchase → RETURN_HOME (got %s)" % m.state)
	check(3, m.has_bread and bread_edges == 1, "08: has_bread set exactly once (edges %d)" % bread_edges)
	check(3, money_before - m.money == 35, "08: 35 рублей paid (%d → %d)" % [money_before, m.money])
	check(3, _hud_has(w, "ХЛЕБ +1"), "08: toast «ХЛЕБ +1» shown")
	check(2, _babka_symbol(w) == "?", "08: ? above Babka once the bread is bought")
	check(1, _hud_has(w, MissionDirector.TASK_RETURN), "08: HUD task «%s» (EXT-01)" % MissionDirector.TASK_RETURN)
	await _shot("08_bread_toast", true)
	await drv.frames(150)
	check(3, toast_frames >= 108 and toast_frames <= 132, "08: toast shown ≈2 s (%d frames at 60)" % toast_frames)
	check(3, not _hud_has(w, "ХЛЕБ +1"), "08: toast gone after 2 s")
	# Повторная покупка
	await drv.walk_to(_vendor_stand() + Vector3(3.0, 0, 0))
	await drv.walk_to(_vendor_stand())
	check(6, not _hud_has(w, "E — ПОГОВОРИТЬ"), "08: no vendor prompt after the purchase")
	await drv.interact()
	await drv.frames(5)
	check(6, not _hud_has(w, "Батон? 35 рублей") and _spent(w) == 35 and bread_edges == 1, "08: second purchase impossible (money %d)" % m.money)
	await _close_any_dialog(w)

	# 09 — назад к машине и во двор
	# EXT-01, этап 8: обратно — между постом полицейского и автобусом ГСУМ, пока он смотрит на запад.
	if not check(1, await _sneak(Layout.SNEAK_BACK) and await drv.walk_to(_car_stand(w)), "09: sneaked back to the car (%s)" % drv.last_error):
		return false
	if not check(1, w.stealth.detections == 0, "09: not detected on the way back (%d)" % w.stealth.detections):
		return false
	await _shot("08b_before_enter_kiosk", true)
	await drv.interact()
	await drv.frames(10)
	check(1, w.control_mode == &"in_car" and m.state == &"RETURN_HOME", "09: in the car, still RETURN_HOME")
	# POLISH-03 B: улица Б перекрыта ГСУМ — радио объявило объезд, мини-карта ведёт на север, домой по ROUTE_DETOUR.
	var closure = w.get_node("LevelGeometry/Patrols/RoadClosure")
	await _wait_detour_radio(closure)
	check(1, m.road_closed and closure.active and closure.radio_shown == 1, "09: street B closed after the purchase, radio announced the detour")
	await drv.frames(2)
	var mm = w.get_node("GameHUD").minimap
	check(1, Array(mm.route_points).any(func(p: Vector2) -> bool: return p.y < -90.0), "09: minimap route goes north to the detour (%s)" % [mm.route_points.slice(0, 3)])
	if not check(1, await drv.drive_path(_detour_route()), "09: drove home along the detour (%s)" % drv.last_error):
		return false
	check(1, not m.road_closed and not closure.active and closure.lifts == 1, "09: back in the yard — the closure is lifted")
	await drv.brake()
	await drv.interact()
	await drv.frames(15)
	check(1, w.control_mode == &"on_foot", "09: out of the car in the yard")
	await _shot("09b_exit_yard", true)
	if not check(1, await drv.walk_to(_babka_stand()), "09: walked to Babka (%s)" % drv.last_error):
		return false
	check(2, _babka_symbol(w) == "?", "09: yellow ? above Babka")
	check(1, _hud_has(w, "E — СДАТЬ ЗАДАНИЕ"), "09: prompt «E — СДАТЬ ЗАДАНИЕ»")
	await _shot("09_return_babka", true)

	# 10 — возвращение (EXT-01, этап 9: цепочка «Ты где был?»), сдача кнопкой СДАТЬ ХЛЕБ
	await drv.interact()
	await drv.frames(10)
	check(1, m.state == &"RETURN_HOME" and m.has_bread and _hud_has(w, QuestLines.RETURN_CHAIN[0]["text"]), "09: E at Babka opens the return chain, no turn-in yet (got %s)" % m.state)
	for line in QuestLines.RETURN_CHAIN.slice(1).map(func(l): return l["text"]):
		await drv.frames(40)
		if not check(1, await drv.press_button("ДАЛЬШЕ"), "09: ДАЛЬШЕ pressed before «%s» (%s)" % [line, drv.last_error]):
			return false
		await drv.frames(3)
		check(1, _hud_has(w, line), "09: return line «%s»" % line)
	await _shot("09b_return_chain", false)
	await drv.frames(40)
	if not check(1, await drv.press_button("СДАТЬ ХЛЕБ"), "10: СДАТЬ ХЛЕБ pressed (%s)" % drv.last_error):
		return false
	await drv.frames(10)
	check(1, m.state == &"COMPLETE", "10: СДАТЬ ХЛЕБ → COMPLETE (got %s)" % m.state)
	check(1, m.xp == 50 and completed_signals == 1, "10: +50 XP once (xp %d)" % m.xp)
	check(3, not m.has_bread, "10: has_bread cleared on turn-in")
	check(1, _hud_has(w, QuestLines.THANKS), "10: line «%s»" % QuestLines.THANKS)
	check(1, not _hud_has(w, "ЗАДАНИЕ ВЫПОЛНЕНО"), "10: conversation is readable before the protocol")
	await drv.frames(ceili((QuestLines.read_seconds(QuestLines.THANKS) + QuestLines.read_seconds(QuestLines.THANKS_AFTER)) * 60.0) + 3)
	check(1, _hud_has(w, "ЗАДАНИЕ ВЫПОЛНЕНО") and _hud_has(w, "+50 опыта"), "10: «ЗАДАНИЕ ВЫПОЛНЕНО» and «+50 опыта»")
	check(2, _babka_symbol(w) == "", "10: no marker above Babka after completion")
	await drv.frames(50)
	check(1, _hud_has(w, QuestLines.THANKS_AFTER) and _hud_has(w, QuestLines.THANKS), "10: second bubble «%s» after the pause" % QuestLines.THANKS_AFTER)
	await _shot("10_complete", false)
	await _front_shot("10_complete")
	pass_frames[1] = sim_frames - start_frame
	print("INFO: pass 1 reached COMPLETE after %d physics frames = %.1f s at 60 fps" % [pass_frames[1], pass_frames[1] / 60.0])
	# Закрыть панель финала (POLISH-03 B: протокол прохода, кнопка «НЕ ПОДПИСЫВАТЬ»)
	check(1, _hud_has(w, QuestLines.PROTOCOL_TITLE) and _hud_has(w, QuestLines.PROTOCOL_SUBTITLE), "10: protocol «%s — %s»" % [QuestLines.PROTOCOL_TITLE, QuestLines.PROTOCOL_SUBTITLE])
	var st: Dictionary = w.quest_flow.finale.stats()
	check(1, st["coins"] == _coins(w).collected_count and st["spent"] == 35 and st["left"] == m.money and st["detections"] == w.stealth.detections and float(st["seconds"]) > 60.0, "10: protocol counts the pass (%s)" % st)
	var focus_close := drv.focused() is Button and (drv.focused() as Button).text == QuestLines.PROTOCOL_BUTTON
	print("INFO: completion panel close button has keyboard focus: %s" % focus_close)
	var close := _visible_button(w, QuestLines.PROTOCOL_BUTTON)
	check(1, close != null, "10: completion panel has «%s»" % QuestLines.PROTOCOL_BUTTON)
	if close:
		await drv.click(close)
		await drv.frames(5)
	check(1, not _hud_has(w, "ЗАДАНИЕ ВЫПОЛНЕНО"), "10: completion panel closed by mouse click")
	# POLISH-03 B, этап 10: пауза, Бабка смотрит на микроавтобус ГСУМ у соседнего подъезда — «Или не сходишь».
	check(1, not _hud_has(w, "КОНЕЦ ДЕМО") and w.quest_flow.finale.playing, "10: the stage-10 scene plays before «Конец демо»")
	await drv.frames(int((QuestLines.FINALE_LOOK_PAUSE + 0.3) * 60.0))
	check(1, w.quest_flow.finale.is_bubble_visible(), "10: Babka says «%s»" % QuestLines.FINALE_LOOK)
	await _shot("10b_finale_look", false)
	await drv.frames(int(QuestLines.FINALE_LOOK_SECONDS * 60.0))
	# POLISH-02: после финала — карточка «Конец демо»; «ПОГУЛЯТЬ» оставляет в мире (сценарий 6 ниже).
	check(1, _hud_has(w, "КОНЕЦ ДЕМО") and _visible_button(w, "ЕЩЁ РАЗ") != null and _visible_button(w, "В МЕНЮ") != null, "10: «Конец демо» card with ЕЩЁ РАЗ and В МЕНЮ")
	check(1, await drv.press_button("ПОГУЛЯТЬ", &"ui_right"), "10: ПОГУЛЯТЬ pressed from keyboard (%s)" % drv.last_error)
	await drv.frames(5)
	check(1, not _hud_has(w, "КОНЕЦ ДЕМО"), "10: «Конец демо» card closed")
	check(1, await _can_walk(w), "10: Ilyusha can move after closing the panel")

	# Повторное E у Бабки
	await drv.walk_to(_babka_stand())
	await drv.interact()
	await drv.frames(5)
	check(6, m.state == &"COMPLETE" and m.xp == 50 and completed_signals == 1, "repeat: second E at Babka gives no reward (xp %d)" % m.xp)
	check(6, not _hud_has(w, "+50 опыта"), "repeat: no second reward panel")
	await _close_any_dialog(w)
	await drv.interact()
	await drv.frames(5)
	check(6, m.xp == 50 and completed_signals == 1, "repeat: third E at Babka gives no reward")
	await _close_any_dialog(w)

	# Покупка после завершения: снова к киоску
	if not check(6, await drv.walk_to(_car_stand(w)), "after: walked to the car (%s)" % drv.last_error):
		return false
	await drv.interact()
	await drv.frames(10)
	if not check(6, await drv.drive_path(Layout.ROUTE_DRIVE.slice(1)), "after: drove to the kiosk again (%s)" % drv.last_error):
		return false
	await drv.brake()
	await drv.interact()
	await drv.frames(15)
	if not check(6, await _sneak(Layout.SNEAK_AGAIN), "after: sneaked to the kiosk window past the moved patrol (%s)" % drv.last_error):
		return false
	check(6, not _hud_has(w, "E — ПОГОВОРИТЬ"), "after: no vendor prompt after completion")
	await drv.interact()
	await drv.frames(5)
	check(6, not _hud_has(w, "Батон? 35 рублей") and not m.has_bread and _spent(w) == 35 and m.state == &"COMPLETE", "after: purchase unavailable after completion")
	await _close_any_dialog(w)
	check(3, bread_edges == 1, "pass 1: has_bread was set exactly once in the whole pass (%d)" % bread_edges)
	_print_transitions("pass 1")
	check(1, _transitions_are([
		[&"NOT_STARTED", &"OFFERED"], [&"OFFERED", &"NOT_STARTED"], [&"NOT_STARTED", &"OFFERED"], [&"OFFERED", &"GO_TO_CAR"],
		[&"GO_TO_CAR", &"DRIVE_TO_KIOSK"], [&"DRIVE_TO_KIOSK", &"BUY_BREAD"], [&"BUY_BREAD", &"RETURN_HOME"], [&"RETURN_HOME", &"COMPLETE"],
	]), "pass 1: FSM went exactly by section 6 of the canon")

	# Повторный запуск: пауза → В ГЛАВНОЕ МЕНЮ → НАЧАТЬ
	await drv.pause_key()
	await drv.frames(3)
	if not check(1, await drv.press_button("В ГЛАВНОЕ МЕНЮ", &"ui_down"), "restart: «В ГЛАВНОЕ МЕНЮ» pressed (%s)" % drv.last_error):
		return false
	await drv.frames(10)
	check(1, main.world == null and _visible_texts(main).has("НАЧАТЬ"), "restart: back in the main menu")
	if not check(1, await drv.press_button("НАЧАТЬ", &"ui_down"), "restart: НАЧАТЬ pressed again (%s)" % drv.last_error):
		return false
	await drv.frames(10)
	return check(1, main.world != null and main.world != w, "restart: a fresh world is created")

# =====================================================================================
# Проход 2: чистое состояние, покупка без квеста, принятие, «Начать заново»
# =====================================================================================

func _pass_two() -> void:
	print("--- PASS 2 ---")
	var w: DemoWorld = main.world
	var m := w.mission
	await drv.frames(5)
	_check_clean(w, "restart")
	await _shot("p2_01_spawn", true)
	# Покупка без квеста
	if not check(1, await drv.walk_to(_car_stand(w)), "no quest: walked to the car (%s)" % drv.last_error):
		return
	await drv.interact()
	await drv.frames(10)
	check(1, w.control_mode == &"in_car" and m.state == &"NOT_STARTED", "no quest: entering the car keeps NOT_STARTED (got %s)" % m.state)
	if not check(1, await drv.drive_path(Layout.ROUTE_DRIVE.slice(1)), "no quest: drove to the kiosk (%s)" % drv.last_error):
		return
	check(1, m.state == &"NOT_STARTED", "no quest: arriving at the kiosk keeps NOT_STARTED (got %s)" % m.state)
	await drv.brake()
	await drv.interact()
	await drv.frames(15)
	if not check(1, await _sneak(Layout.SNEAK_EAST), "no quest: sneaked to the window (%s)" % drv.last_error):
		return
	check(3, not _hud_has(w, "E — ПОГОВОРИТЬ"), "no quest: no vendor prompt without the quest")
	await drv.interact()
	await drv.frames(5)
	check(3, not _hud_has(w, "Батон? 35 рублей") and not m.has_bread and _spent(w) == 0, "no quest: bread cannot be bought without the quest")
	await _close_any_dialog(w)
	check(2, _babka_symbol(w) == "!", "no quest: ! still above Babka")
	# Назад во двор и принять
	# Обратно до покупки — путь «за остановкой» в обратную сторону, пока полицейский смотрит на запад.
	var east_back: Array = Layout.SNEAK_EAST[2].slice(0, Layout.SNEAK_EAST[2].size() - 1)
	east_back.reverse()
	east_back.append(Layout.SNEAK_EAST[0][2])
	if not check(1, await drv.wait_officer_turn(Layout.SNEAK_EAST[1]) and await drv.walk_path(east_back) and await drv.walk_to(_car_stand(w)), "pass 2: back to the car (%s)" % drv.last_error):
		return
	check(1, w.stealth.detections == 0, "pass 2: not detected at the kiosk (%d)" % w.stealth.detections)
	await drv.interact()
	await drv.frames(10)
	if not check(1, await drv.drive_path(_back_route()), "pass 2: drove back to the yard (%s)" % drv.last_error):
		return
	await drv.brake()
	await drv.interact()
	await drv.frames(15)
	if not check(1, await drv.walk_to(_babka_stand()), "pass 2: walked to Babka (%s)" % drv.last_error):
		return
	await drv.interact()
	await drv.frames(5)
	check(1, m.state == &"OFFERED", "pass 2: E at Babka → OFFERED")
	check(1, await drv.press_button("ПРИНЯТЬ"), "pass 2: ПРИНЯТЬ pressed (%s)" % drv.last_error)
	await drv.frames(3)
	check(1, m.state == &"GO_TO_CAR" and m.xp == 0 and not m.has_bread, "pass 2: quest accepted in a clean state (state %s)" % m.state)
	check(2, _babka_symbol(w) == "", "pass 2: ! gone after acceptance")
	_print_transitions("pass 2")
	# «Начать заново» из паузы
	await drv.pause_key()
	await drv.frames(3)
	if check(1, await drv.press_button("НАЧАТЬ ЗАНОВО", &"ui_down"), "restart 2: «НАЧАТЬ ЗАНОВО» pressed (%s)" % drv.last_error):
		await drv.frames(10)
		check(1, main.world != null and main.world != w, "restart 2: a fresh world")
		if main.world:
			_check_clean(main.world, "restart 2")

func _check_clean(w: DemoWorld, label: String) -> void:
	var m := w.mission
	check(1, m.state == &"NOT_STARTED" and not m.has_bread and m.xp == 0 and m.money == MissionDirector.START_MONEY,
		"%s: NOT_STARTED, has_bread false, xp 0, money %d (got %s, %s, %d, %d)" % [label, MissionDirector.START_MONEY, m.state, m.has_bread, m.xp, m.money])
	check(1, _near2(w.player.global_position, Layout.SPAWN, 0.5) and _near2(w.car.global_position, Layout.CAR_SPAWN, 0.5), "%s: Ilyusha and the Lada at their spawn points" % label)
	check(1, w.control_mode == &"on_foot" and w.player.visible and not paused, "%s: on foot, not paused" % label)
	check(1, not _hud_has(w, "ЗАДАНИЕ ВЫПОЛНЕНО") and not _hud_has(w, "ХЛЕБ +1") and _hud_has(w, "Подойди к Бабке"), "%s: HUD is back to frame 01" % label)
	check(2, _babka_symbol(w) == "!", "%s: ! above Babka again" % label)
	check(1, transitions.is_empty() and bread_edges == 0 and completed_signals == 0, "%s: no transitions carried over" % label)

# =====================================================================================
# Монитор инвариантов (каждый физический кадр)
# =====================================================================================

func _monitor() -> void:
	sim_frames += 1
	var w: DemoWorld = main.world if is_instance_valid(main) else null
	if w == null or not is_instance_valid(w) or not w.is_inside_tree() or not w.is_node_ready():
		return
	if w != _world:
		_bind(w)
	if _ram_trace_active:
		_record_ram(w)
	var m := w.mission
	# Сценарий 2: маркер над Бабкой
	var expected := ""
	if m.state == &"NOT_STARTED" or m.state == &"OFFERED":
		expected = "!"
	elif m.state == &"RETURN_HOME" and m.has_bread:
		expected = "?"
	var shown := _babka_symbol(w)
	_inv("2: marker above Babka matches the state", shown == expected, "state %s, shown '%s', expected '%s'" % [m.state, shown, expected])
	_inv("2: HUD babka_marker matches the state", w.get_hud_state().get("babka_marker", "") == expected, "state %s" % m.state)
	# Сценарий 3: инвентарь логический, в руках пусто
	if m.has_bread and not _had_bread:
		bread_edges += 1
	_had_bread = m.has_bread
	var toast_on := _hud_has(w, "ХЛЕБ +1")
	if toast_on:
		toast_frames += 1
	if sim_frames % 30 == 0:
		_inv("3: Ilyusha's node tree never changes (nothing attached to him)", _signature(w.player) == _player_signature, _signature(w.player))
		# Канон, раздел 2 и 3: нельзя хлеба в руках и 3D-батона как предмета. Витрина киоска «ХЛЕБ» — декор
		# (POLISH-02): хлеб-подобные узлы допустимы только под LevelGeometry/Kiosk, и их набор за игру не меняется,
		# то есть покупка и сдача не порождают в мире ни батона, ни пакета.
		var props := _bread_props(w)
		var outside := props.filter(func(path: String) -> bool: return not path.begins_with("LevelGeometry/Kiosk/"))
		_inv("3: no 3D bread, loaf or bag in the world outside the kiosk display", outside.is_empty(), str(outside))
		_inv("3: kiosk display never changes (purchase spawns nothing)", props == _kiosk_goods, str(props))
	# Сценарий 4: тот же облик Илюши
	if Uniform.civilians_enabled():
		_monitor_3d_outfit(w)
	else:
		var look := _ilyusha_sprite(w)
		var texture_path: String = look.texture.resource_path if look and look.texture else ""
		if texture_path != "":
			textures_seen[texture_path.get_file()] = true
		_inv("4: Ilyusha is drawn only with his own ilyusha_* winter costume pictures", texture_path.get_file().begins_with("ilyusha_"), texture_path)
	_inv("4: Ilyusha visible on foot, hidden in the car", w.player.visible == (w.control_mode == &"on_foot"), "mode %s, visible %s" % [w.control_mode, w.player.visible])
	# Сценарий 7: мини-карта и ромб
	_check_navigation(w)

func _bind(w: DemoWorld) -> void:
	_world = w
	transitions.clear()
	bread_edges = 0
	_had_bread = false
	completed_signals = 0
	toast_frames = 0
	w.mission.state_changed.connect(func(old, new): transitions.append([old, new]))
	w.mission.quest_completed.connect(func(_xp): completed_signals += 1)
	_player_signature = _signature(w.player)
	_kiosk_goods = _bread_props(w)
	var look: Node = w.player.get_node("Visual/Look")
	_outfit_heights = Vector2(look.height_m * Catalog.visible_height_ratio("ilyusha"), SeatedVisual.LADA_VISIBLE_HEIGHT)
	_outfit_meshes.clear()
	_seated_leg_poses.clear()
	if Uniform.civilians_enabled():
		var seated: Node = w.car.visual.get_node("Body/Driver")
		_outfit_meshes.assign([look.uniform_visual.uniform_mesh.mesh, seated.uniform_visual.uniform_mesh.mesh])
		var seated_rig: Skeleton3D = seated.uniform_visual.skeleton
		for bone_name: String in ["leg_l", "leg_r"]:
			var bone := seated_rig.find_bone(bone_name)
			if bone >= 0:
				_seated_leg_poses.append(seated_rig.get_bone_pose_rotation(bone))
	var collider: CollisionShape3D = w.player.get_node("CollisionShape3D")
	var capsule := collider.shape as CapsuleShape3D
	_player_capsule = Vector2(capsule.radius, capsule.height)
	_player_collider_transform = collider.transform

func _monitor_3d_outfit(w: DemoWorld) -> void:
	var on_foot: Node = w.player.get_node("Visual/Look")
	var seated: Node = w.car.visual.get_node("Body/Driver")
	var matches: bool = on_foot.uses_uniform_3d() and seated.uses_uniform_3d() and on_foot.sprite == null and seated.sprite == null
	if matches:
		var a: Node = on_foot.uniform_visual
		var b: Node = seated.uniform_visual
		matches = on_foot.resolved_character() == "ilyusha" and seated.resolved_character() == "ilyusha" and a.model.get_meta("drawing", "") == "ilyusha" and b.model.get_meta("drawing", "") == "ilyusha" and a.author_mesh.mesh == b.author_mesh.mesh and a.skeleton != b.skeleton
		matches = matches and _outfit_meshes.size() == 2 and a.uniform_mesh.mesh == _outfit_meshes[0] and b.uniform_mesh.mesh == _outfit_meshes[1]
		matches = matches and is_equal_approx(a.visible_height, _outfit_heights.x) and is_equal_approx(b.visible_height, _outfit_heights.y) and a.model.scale.is_equal_approx(Vector3.ONE * _outfit_heights.x) and b.model.scale.is_equal_approx(Vector3.ONE * _outfit_heights.y)
		var legs: Skeleton3D = b.skeleton
		matches = matches and _seated_leg_poses.size() == 2
		for index in _seated_leg_poses.size():
			var bone := legs.find_bone("leg_l" if index == 0 else "leg_r")
			matches = matches and bone >= 0 and _seated_leg_poses[index].angle_to(Quaternion.IDENTITY) > 0.01
			if bone >= 0:
				matches = matches and legs.get_bone_pose_rotation(bone).angle_to(_seated_leg_poses[index]) < 0.0001
	var collider: CollisionShape3D = w.player.get_node("CollisionShape3D")
	var capsule := collider.shape as CapsuleShape3D
	matches = matches and capsule != null and Vector2(capsule.radius, capsule.height).is_equal_approx(_player_capsule) and collider.transform.is_equal_approx(_player_collider_transform)
	_inv("4: Ilyusha keeps the same original 3D winter outfit on foot and at the wheel, with fixed profile heights and gameplay body", matches, "mode=%s drawings=%s/%s heights=%s" % [w.control_mode, on_foot.resolved_character(), seated.resolved_character(), _outfit_heights])

func _wait_detour_radio(closure: Node) -> void:
	# Radio tuning finishes on the audio server's real clock. Await the actual
	# producer result while supplying frames; never set tuning/caption internals.
	var deadline := Time.get_ticks_msec() + 6000
	while closure.radio_shown == 0 and Time.get_ticks_msec() < deadline:
		await drv.frames(1)
		OS.delay_msec(5)

func _record_ram(w: DemoWorld) -> void:
	var car: Lada = w.car
	_ram_max_snow_depth = maxf(_ram_max_snow_depth, car.snow_depth)
	_ram_max_snow_lift = maxf(_ram_max_snow_lift, car.snow_lift)
	for index in car.get_slide_collision_count():
		var hit := car.get_slide_collision(index)
		var collider := hit.get_collider() as Node
		var path := String(w.get_path_to(collider)) if collider != null else "null"
		_ram_trace_hits[path] = int(_ram_trace_hits.get(path, 0)) + 1

## Цель по канону: до принятия — Бабка, после — машина, в пути — киоск, у киоска — окно, с хлебом — Бабка.
func _expected_target(w: DemoWorld) -> Variant:
	match w.mission.state:
		&"NOT_STARTED", &"OFFERED", &"RETURN_HOME":
			return Layout.BABKA
		&"GO_TO_CAR":
			return w.car.global_position
		&"DRIVE_TO_KIOSK", &"BUY_BREAD":
			return Layout.KIOSK
	return null

func _check_navigation(w: DemoWorld) -> void:
	var hud := w.get_node_or_null("GameHUD")
	var minimap: Control = hud.get("minimap") if hud else null
	_inv("7: minimap is on screen", minimap != null and minimap.is_visible_in_tree(), "")
	var target: Variant = _expected_target(w)
	if target == null or minimap == null:
		return
	var tol := 6.0 if w.mission.state == &"BUY_BREAD" or w.mission.state == &"DRIVE_TO_KIOSK" else 1.0
	var t2 := Vector2(target.x, target.z)
	var has_target: bool = minimap.get("has_target")
	var on_map: Vector2 = minimap.get("target_world")
	_inv("7: minimap marker is on the current target", has_target and on_map.distance_to(t2) <= tol, "state %s, map %s, expected %s" % [w.mission.state, on_map, t2])
	var followed: Node3D = w.player if w.control_mode == &"on_foot" else w.car
	var centre: Vector2 = minimap.get("center_world")
	_inv("7: minimap is centred on Ilyusha or the car", centre.distance_to(Vector2(followed.global_position.x, followed.global_position.z)) < 1.0, "centre %s" % centre)
	var marker: Vector2 = minimap.get("target_marker")
	var real := on_map - centre
	if marker.length() > 2.0 and real.length() > 2.0:
		_inv("7: minimap marker points from the hero toward the target (north up)", absf(marker.angle_to(real)) < 0.05, "marker %s, real %s" % [marker, real])
	# Ромб на экране: цель впереди — на её стороне экрана, сзади — прижат к краю.
	var diamond_visible: bool = hud.get("diamond_visible")
	# POLISH-02: ромб прячется, только когда цель в кадре и ближе 15 м (над Бабкой есть !/?, машина и киоск видны).
	var near_hidden: bool = hud.get("diamond_near_hidden")
	var hero_xz := Vector2(followed.global_position.x, followed.global_position.z)
	_inv("7: yellow diamond is shown while there is a target (or the target is near and in frame)", diamond_visible or near_hidden, "state %s" % w.mission.state)
	if near_hidden:
		_inv("7: diamond hides only for a near target in frame", hero_xz.distance_to(t2) < 15.0 + tol and not hud.get("diamond_clamped"), "distance %.1f" % hero_xz.distance_to(t2))
	var camera: Camera3D = w.camera_rig.camera
	# EXT-01 fix6: сторона экрана — по точке, на которую ромб и указывает (target_position HUD: у киоска — окно продавщицы,
	# в 4 м от центра Layout.KIOSK); честный путь SNEAK_EAST идёт между ними, и стороны по центру и по окну расходятся.
	var aim: Variant = w.get_hud_state().get("target_position", null)
	var side_target: Vector3 = aim if aim is Vector3 else target
	var local := camera.global_transform.affine_inverse() * Vector3(side_target.x, 2.0, side_target.z)
	var position: Vector2 = hud.get("diamond_position")
	var clamped: bool = hud.get("diamond_clamped")
	if local.z < -3.0 and absf(local.x / -local.z) > 0.2 and absf(local.x / -local.z) < 0.8:
		_inv("7: diamond is on the target's side of the screen", signf(position.x - 960.0) == signf(local.x), "local %s, diamond %s" % [local, position])
	elif local.z > 3.0:
		_inv("7: diamond is clamped to the edge when the target is behind", clamped, "local %s" % local)

func _inv(name: String, ok: bool, detail: String) -> void:
	if not mon.has(name):
		mon[name] = {"frames": 0, "bad": 0, "first": ""}
	var entry: Dictionary = mon[name]
	entry["frames"] += 1
	if ok:
		_lag[name] = 0
		return
	_lag[name] = _lag.get(name, 0) + 1
	if _lag[name] >= 3:  # _process HUD и маркера отстаёт от физики на кадр; держится 3 кадра — нарушение
		entry["bad"] += 1
		if entry["first"] == "":
			entry["first"] = "frame %d: %s" % [sim_frames, detail]

# =====================================================================================
# Чтение сцены
# =====================================================================================

func _babka_stand() -> Vector3:
	return Layout.BABKA + Vector3(0.6, 0.0, -2.0)

func _vendor_stand() -> Vector3:
	return Layout.VENDOR_WINDOW + Vector3(0.6, 0.0, 0.0)

## Честный путь у киоска (Layout.SNEAK_*): до укрытия, выждать разворот полицейского, дальше.
func _sneak(route: Array) -> bool:
	return await drv.sneak(route[0], route[1], route[2])

## POLISH-03 B: после покупки улица Б перекрыта — разворот по пустырю (ROUTE_LEAVE_KIOSK) и объезд ROUTE_DETOUR;
## конец — рядом со стоянкой во дворе.
func _detour_route() -> Array:
	var out: Array = Layout.ROUTE_LEAVE_KIOSK.duplicate()
	out.append_array(Layout.ROUTE_DETOUR.slice(1))
	out[out.size() - 1] = Layout.CAR_SPAWN + Vector3(3.0, 0, -6.0)
	return out

## Отъезд с парковки киоска во двор: разворот по пустырю и выезд на улицу B (ROUTE_LEAVE_KIOSK), затем ROUTE_DRIVE
## в обратном порядке без двух последних точек; конец — рядом со стоянкой во дворе.
func _back_route() -> Array:
	var back: Array = Layout.ROUTE_DRIVE.slice(0, Layout.ROUTE_DRIVE.size() - 2)
	back.reverse()
	back[back.size() - 1] = Layout.CAR_SPAWN + Vector3(3.0, 0, -6.0)
	var out: Array = []
	out.append_array(Layout.ROUTE_LEAVE_KIOSK)
	out.append_array(back)
	return out

## Встать сбоку от машины, с ближней к Илюше стороны.
func _car_stand(w: DemoWorld) -> Vector3:
	var best := Vector3.INF
	for offset in [Vector3(-2.2, 0, 0), Vector3(2.2, 0, 0)]:
		var p: Vector3 = w.car.global_transform * offset
		p.y = 0.0
		if best == Vector3.INF or p.distance_to(w.player.global_position) < best.distance_to(w.player.global_position):
			best = p
	return best

func _near2(a: Vector3, b: Vector3, tol: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= tol

## Символ, видимый над Бабкой: «!», «?» или "".
func _babka_symbol(w: DemoWorld) -> String:
	for label: Label3D in w.babka.find_children("*", "Label3D", true, false):
		if label.is_visible_in_tree() and label.text.strip_edges() in ["!", "?"]:
			return label.text.strip_edges()
	return ""

## Видимые тексты интерфейса: Label, Button, Label3D. В мире — только HUD, диалоги и NPC (геометрию не обходить).
func _visible_texts(node: Node) -> Array:
	var roots: Array = [node]
	if node is DemoWorld:
		roots = []
		for n in ["GameHUD", "QuestFlow", "Babka", "Vendor"]:
			if node.has_node(n):
				roots.append(node.get_node(n))
	var out := []
	for r in roots:
		for child in r.find_children("*", "", true, false):
			if (child is Label or child is Button) and (child as CanvasItem).is_visible_in_tree():
				out.append(child.text)
			elif child is Label3D and (child as Node3D).is_visible_in_tree():
				out.append(child.text)
	return out

## COINS-01: монеты мира (LevelGeometry/Coins) и сколько потрачено: деньги — только монеты по 1 ₽ (старт 0),
## поэтому потрачено = подобрано − деньги (0 до покупки, 35 после).
func _coins(w: DemoWorld) -> Node:
	return w.get_node("LevelGeometry/Coins")

func _spent(w: DemoWorld) -> int:
	return _coins(w).collected_count - w.mission.money

func _hud_has(w: DemoWorld, text: String) -> bool:
	return _visible_texts(w).has(text)

func _hud_speed_visible(w: DemoWorld) -> bool:
	return _visible_texts(w).has("КМ/Ч")

func _visible_button(w: DemoWorld, text: String) -> Button:
	for child in w.find_children("*", "Button", true, false):
		if child.text == text and child.is_visible_in_tree():
			return child
	return null

func _signature(node: Node) -> String:
	var parts := []
	for child in node.find_children("*", "", true, false):
		parts.append("%s:%s" % [node.get_path_to(child), child.get_class()])
	return ",".join(parts)

func _ilyusha_sprite(w: DemoWorld) -> SpriteBase3D:
	for child in w.player.find_children("*", "Sprite3D", true, false):
		return child
	return null

## 3D-узлы, похожие на хлеб или пакет (по имени, мешу или текстуре). Иконки HUD — 2D и сюда не попадают.
func _bread_props(w: DemoWorld) -> Array:
	var found := []
	var pattern := RegEx.create_from_string("(?i)(bread|loaf|baton|bag|bun|хлеб|батон|пакет)")
	for child in w.find_children("*", "VisualInstance3D", true, false):
		var names := [String(child.name)]
		if child is MeshInstance3D and child.mesh:
			names.append(child.mesh.resource_path)
		if child is SpriteBase3D and child.get("texture"):
			names.append(child.texture.resource_path)
		for n in names:
			if pattern.search(n):
				found.append(str(w.get_path_to(child)))
				break
	return found

func _distance_to_route(p: Vector3) -> float:
	var best := INF
	for i in range(1, Layout.ROUTE_DRIVE.size()):
		var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), Layout.ROUTE_DRIVE[i - 1], Layout.ROUTE_DRIVE[i])
		best = minf(best, q.distance_to(Vector3(p.x, 0, p.z)))
	return best

## Прямоугольник машины (Lada.SIZE, C4) не пересекает ни одной коробки Layout (C1).
func _car_clear(car: Lada) -> bool:
	var half := Vector2(Lada.SIZE.x, Lada.SIZE.z) * 0.5
	var corners := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var local := Vector3(half.x * s.x, 0, half.y * s.y)
		var g := car.global_transform * local
		corners.append(Vector2(g.x, g.z))
	for solid in Layout.all_solids():
		var c: Vector2 = solid[2]
		var size: Vector3 = solid[3]
		var box := PackedVector2Array([c + Vector2(-size.x, -size.z) * 0.5, c + Vector2(size.x, -size.z) * 0.5,
			c + Vector2(size.x, size.z) * 0.5, c + Vector2(-size.x, size.z) * 0.5])
		if not Geometry2D.intersect_polygons(corners, box).is_empty():
			print("INFO: reset spot overlaps ", solid[0])
			return false
	return true

func _can_walk(w: DemoWorld) -> bool:
	var from := w.player.global_position
	var to := from + Vector3(0.0, 0.0, -1.0)
	await drv.walk_to(to, 0.3, 120)
	return w.player.global_position.distance_to(from) > 0.6

## Закрыть открытую реплику (кнопка ЗАКРЫТЬ или УЙТИ), если она есть.
func _close_any_dialog(w: DemoWorld) -> void:
	for text in ["ЗАКРЫТЬ", "ЛАДНО", "УЙТИ"]:
		if _visible_button(w, text):
			await drv.press_button(text)
			await drv.frames(3)
			return

func _transitions_are(expected: Array) -> bool:
	if transitions.size() != expected.size():
		return false
	for i in expected.size():
		if transitions[i][0] != expected[i][0] or transitions[i][1] != expected[i][1]:
			return false
	return true

func _print_transitions(label: String) -> void:
	var parts := []
	for t in transitions:
		parts.append("%s→%s" % t)
	print("INFO: %s transitions: %s" % [label, ", ".join(parts)])

# =====================================================================================
# Кадры
# =====================================================================================

func _shot(label: String, front := false) -> void:
	if not capture:
		return
	await drv.frames(20)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())
	if front:
		await _front_shot(label)

## Тот же момент с камерой спереди Илюши (поворот камеры, как мышью), чтобы были видны руки.
func _front_shot(label: String) -> void:
	if not capture:
		return
	var w: DemoWorld = main.world
	if w.control_mode != &"on_foot":
		return
	var rig := w.camera_rig
	var yaw := rig.yaw
	var pitch := rig.pitch
	rig.yaw = w.player.get_node("Visual").global_rotation.y + PI
	rig.pitch = -0.12
	await drv.frames(30)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s_front.png" % [OUT, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())
	rig.yaw = yaw
	rig.pitch = pitch
	await drv.frames(10)

# =====================================================================================
# Проверки и отчёт
# =====================================================================================

func check(scenario: int, ok: bool, label: String) -> bool:
	if not results.has(scenario):
		results[scenario] = [0, 0]
	if ok:
		results[scenario][0] += 1
		print("PASS [%d] %s" % [scenario, label])
	else:
		results[scenario][1] += 1
		failures.append("[%d] %s" % [scenario, label])
		push_error("FAIL [%d] %s" % [scenario, label])
	return ok

func _fail_check(scenario: int, label: String) -> void:
	check(scenario, false, label)

func _report() -> void:
	print("--- INVARIANTS (every physics frame) ---")
	var names := mon.keys()
	names.sort()
	for name in names:
		var entry: Dictionary = mon[name]
		var scenario := int(String(name).get_slice(":", 0))
		check(scenario, entry["bad"] == 0, "invariant %s — %d frames, %d bad%s" % [name, entry["frames"], entry["bad"], (", first " + entry["first"]) if entry["first"] != "" else ""])
	var used := textures_seen.keys()
	used.sort()
	print("INFO: Ilyusha textures used: %d — %s" % [used.size(), ", ".join(used)])
	print("INFO: simulated physics frames %d = %.1f s; wall time %.1f s" % [sim_frames, sim_frames / 60.0, (Time.get_ticks_usec() - started_usec) / 1e6])
	print("--- SCENARIOS ---")
	for s in SCENARIOS:
		var r: Array = results.get(s, [0, 0])
		var verdict := "PASS" if r[1] == 0 and r[0] > 0 else ("FAIL" if r[1] > 0 else "NOT_RUN")
		var note := ""
		if s == 4:
			note = " (structural; visual review of builds/screenshots/qa01/ %s)" % ("captured" if capture else "needs --capture")
		if s == 8:
			verdict = "NOT_RUN"
			note = " (native FPS is measured separately on the target Mac with make fps)"
		print("SCENARIO %d %s — %d passed, %d failed — %s%s" % [s, verdict, r[0], r[1], SCENARIOS[s], note])
	print("DEMO_ACCEPTANCE: %d checks, %d failures" % [_total(), failures.size()])
	for f in failures:
		print("FAILED ", f)

func _total() -> int:
	var n := 0
	for s in results:
		n += results[s][0] + results[s][1]
	return n

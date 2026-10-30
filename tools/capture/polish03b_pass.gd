extends SceneTree
## POLISH-03 B: замер прямого прохода (по образцу прохода критика 30.10, tools/capture/critic.gd в его worktree): заставка,
## Бабка, «Лада», ROUTE_DRIVE_HUNT (одна вылазка за гаражи двора — без неё 35 ₽ не набрать), парковка, честный проход к
## окну, покупка, обратно к машине, объезд перекрытия (ROUTE_LEAVE_KIOSK + ROUTE_DETOUR), сдача, протокол, сцена
## «Или не сходишь», «Конец демо». Только ввод (tests/playthrough_driver.gd), без телепортов.
## Режимы (после --): pass — новый проход; direct — старый прямой маршрут ROUTE_DRIVE (сколько монет без вылазки).
## Кадры — builds/screenshots/POLISH-03/b/ (не в headless). Время — по физическим кадрам (--fixed-fps 60).

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const IntroScript = preload("res://game/ui/intro.gd")

var main: Node
var drv
var out := ""
var frame := 0
var w: DemoWorld
var last_state := ""
var marks := {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "pass"
	out = ProjectSettings.globalize_path("res://builds/screenshots/POLISH-03/b/")
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(700.0, true, false, true).timeout.connect(func():
		print("PASS TIMEOUT")
		quit(3))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	drv.on_frame = _tick
	for i in 30: await process_frame
	IntroScript.force_enabled = true
	if not await drv.press_button("НАЧАТЬ", &"ui_down"):
		print("FAIL menu ", drv.last_error)
		quit(1)
		return
	for i in 3: await process_frame
	w = main.world
	await _pass(mode)
	_log("END")
	drv.release_all()
	drv.on_frame = Callable()
	quit(0)

func _tick() -> void:
	frame += 1
	if w == null or not is_instance_valid(w):
		return
	if str(w.mission.state) != last_state:
		last_state = str(w.mission.state)
		_log("STATE %s money %d" % [last_state, w.mission.money])

func _log(s: String) -> void:
	print("[t=%6.1f] %s" % [frame / 60.0, s])

func _save(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + label + ".png")
	_log("SHOT " + label)

func _babka_stand() -> Vector3:
	return Layout.BABKA + Vector3(0.6, 0.0, -2.0)

func _car_stand() -> Vector3:
	var best := Vector3.INF
	for offset in [Vector3(-2.2, 0, 0), Vector3(2.2, 0, 0)]:
		var p: Vector3 = w.car.global_transform * offset
		p.y = 0.0
		if best == Vector3.INF or p.distance_to(w.player.global_position) < best.distance_to(w.player.global_position):
			best = p
	return best

func _hud_texts() -> String:
	var acc: Array = []
	var hud := w.get_node_or_null("GameHUD")
	if hud:
		for n in hud.find_children("*", "", true, false):
			if (n is Label or n is Button) and n.is_visible_in_tree() and str(n.text).strip_edges() != "":
				acc.append(str(n.text).strip_edges().replace("\n", " / "))
	return " | ".join(acc)

## Сколько монет каждой группы Layout.COIN_GROUPS подобрано: «группа собрано/всего».
func _groups() -> String:
	var coins = w.get_node("LevelGeometry/Coins")
	var acc: Array = []
	for g in Layout.COIN_GROUPS:
		var spec: Array = Layout.COIN_GROUPS[g]
		var taken := 0
		var missed: Array = []
		for k in spec[1]:
			if coins.is_available(spec[0] + k):
				missed.append(spec[0] + k)
			else:
				taken += 1
		acc.append("%s %d/%d%s" % [g, taken, spec[1], (" miss %s" % [missed]) if taken > 0 and not missed.is_empty() else ""])
	return ", ".join(acc)

## Кадры перекрытия (здесь можно ставить миссию и героя — смотрим вид, не проход): с севера (от киоска) и с юга.
func _views() -> void:
	var intro = w.get_node_or_null("Intro")
	while is_instance_valid(intro) and intro.is_running():
		await drv.frames(1)
	var m := w.mission
	m.interact(&"babka")
	m.accept()
	m.notify_entered_car()
	m.notify_arrived_kiosk()
	m.add_money(m.money_missing())
	m.buy_bread()
	w.player.place(Vector3(-20, 0, -88), 0.0)
	var closure = w.get_node("LevelGeometry/Patrols/RoadClosure")
	for i in 60 * 40:
		await drv.frames(1)
		if closure.is_blocking():
			break
	_log("closure blocking %s" % closure.is_blocking())
	for spec in [["09_closure_from_north", Vector3(66, 0, -15), PI], ["10_closure_from_south", Vector3(63, 0, 13), 0.0],
			["11_closure_wide_north", Vector3(70, 0, -26), PI]]:
		w.player.place(spec[1], spec[2])
		w.camera_rig.yaw = spec[2]
		w.camera_rig.pitch = -0.12
		w.camera_rig.snap()
		await drv.frames(90)
		await _save(spec[0])

func _pass(mode: String) -> void:
	if mode == "views":
		await _views()
		return
	var intro = w.get_node_or_null("Intro")
	while is_instance_valid(intro) and intro.is_running():
		await drv.frames(1)
	_log("INTRO done")
	await drv.frames(30)
	await drv.frames(180)   # игрок осматривается 3 с (как у критика)
	if not await drv.walk_to(_babka_stand()):
		_log("FAIL walk babka " + drv.last_error)
	await drv.interact()
	await drv.frames(60)
	await drv.press_button("ПРИНЯТЬ")
	await drv.frames(90)
	if not await drv.walk_to(_car_stand()):
		_log("FAIL walk car " + drv.last_error)
	await drv.interact()
	await drv.frames(30)
	var route: Array = (Layout.ROUTE_DRIVE if mode == "direct" else Layout.ROUTE_DRIVE_HUNT).slice(1)
	for i in route.size():
		if not await drv.drive_path([route[i]]):
			_log("FAIL drive %d %s" % [i, drv.last_error])
		if i == 7:
			await _save("01_hunt_behind_garages")
	await drv.brake()
	_log("MONEY at kiosk %d (coins %d)" % [w.mission.money, w.get_node("LevelGeometry/Coins").collected_count])
	await drv.interact()
	await drv.frames(30)
	if not await drv.sneak(Layout.SNEAK_EAST[0], Layout.SNEAK_EAST[1], Layout.SNEAK_EAST[2]):
		_log("FAIL sneak " + drv.last_error)
	_log("MONEY at window %d" % w.mission.money)
	_log("COIN GROUPS " + _groups())
	if mode == "direct":
		marks["direct_money"] = w.mission.money
		return
	await drv.interact()
	await drv.frames(60)
	for i in 8:
		await drv.frames(50)
		if not await drv.press_button("ДАЛЬШЕ"):
			break
		await drv.frames(20)
	await drv.press_button("КУПИТЬ ХЛЕБ", &"ui_left")
	await drv.frames(20)
	_log("HUD: " + _hud_texts())
	await drv.frames(150)
	if not await drv.sneak(Layout.SNEAK_BACK[0], Layout.SNEAK_BACK[1], Layout.SNEAK_BACK[2]):
		_log("FAIL sneak back " + drv.last_error)
	await drv.walk_to(_car_stand())
	await drv.interact()
	await drv.frames(30)
	var closure = w.get_node("LevelGeometry/Patrols/RoadClosure")
	_log("closure active %s gap %s" % [closure.active, closure.gap_closed])
	await _save("02_closure_from_parking")
	var back: Array = Layout.ROUTE_LEAVE_KIOSK.duplicate()
	back.append_array(Layout.ROUTE_DETOUR.slice(1))
	back[back.size() - 1] = Layout.CAR_SPAWN + Vector3(3.0, 0, -6.0)
	for i in back.size():
		if not await drv.drive_path([back[i]]):
			_log("FAIL drive back %d %s" % [i, drv.last_error])
		if i == 2:
			await _save("03_detour_minimap")
		if i == 6:
			await _save("04_detour_c")
	await drv.brake()
	_log("road_closed %s, closure lifts %d" % [w.mission.road_closed, closure.lifts])
	await drv.interact()
	await drv.frames(20)
	await drv.walk_to(_babka_stand())
	await drv.interact()
	await drv.frames(60)
	for i in 8:
		await drv.frames(50)
		if not await drv.press_button("ДАЛЬШЕ"):
			break
		await drv.frames(20)
	await drv.frames(40)
	await drv.press_button("СДАТЬ ХЛЕБ")
	await drv.frames(150)
	await _save("05_protocol")
	_log("HUD: " + _hud_texts())
	var hud := w.get_node("GameHUD")
	await drv.frames(240)   # протокол читают ~4 с
	await drv.click(hud.completion_close)
	await drv.frames(40)
	await _save("06_finale_look_a")
	await drv.frames(90)
	await _save("07_finale_look_b")
	var flow = w.quest_flow
	while flow.finale.playing:
		await drv.frames(1)
	await drv.frames(30)
	await _save("08_end_card")
	_log("HUD: " + _hud_texts())
	_log("TOTAL play seconds %.1f (intro incl.), protocol %s" % [frame / 60.0, flow.finale.stats()])

extends SceneTree
## EXT-02 C (docs/extension/HIDE_SPOTS.md, разделы 6, 11, 14 C): коробка «БАТОНЫ» на настоящей сцене main.tscn.
## Узел LevelGeometry/HideSpots/BreadBox на Layout.BREAD_BOX: облик (короб, «БАТОНЫ» на боках, снег), подсказки
## HideTuning.PROMPT_BOX_ENTER/EXIT; E — надеть/снять (короб на Илюше, в мире скрыт; снятый — рядом, без дубликатов);
## заметность через сенсор полицейского: стоя вдали 0, на ходу 0,75, стоя в 1,5 м 0,5; в коробке E у «Лады», Бабки
## и окна продавщицы — отказ (у окна — реплика QuestLines.HIDE_BOX_VENDOR); после провала и reset_hide — одна коробка
## на home, Илюша без режима; 20 входов/выходов по E без утечки узлов; гэги C02/C03 субтитрами — по разу за попытку;
## честный проход участка в коробке (свежий мир, настоящий патруль): за контейнерами выждать разворот на юг, надеть
## коробку, переждать «запад» стоя, на «юге» дойти до окна — без провала; снять коробку и купить хлеб.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/hide_box_test.gd
## Кадры:    tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/hide_box_test.gd -- --capture
##   → builds/screenshots/EXT-02/c/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")
const BoxSpot = preload("res://game/stealth/box_hide_spot.gd")
const OUT := "res://builds/screenshots/EXT-02/c"

var failures: Array[String] = []
var checks := 0
var capture := false
var main: Node
var drv
var world: DemoWorld
var player: Ilyusha
var box   # BoxSpot (HideSpot)
var officer   # PatrolNpc
var detections := 0

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: hide box test exceeded 900 simulated seconds")
		_finish(2))
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	if not await _fresh_world():
		_finish()
		return
	await _part_spot()
	await _part_wear()
	await _part_exposure()
	await _part_refusals()
	await _part_fail_reset()
	await _part_toggles()
	await _part_gags()
	await _part_honest_pass()
	drv.release_all()
	_finish()

func _fresh_world() -> bool:
	drv.on_frame = Callable()
	main.start_game()
	await drv.frames(10)
	world = main.world
	if not check(world != null and world.player != null, "world and Ilyusha are up"):
		return false
	player = world.player
	box = world.get_node_or_null("LevelGeometry/HideSpots/BreadBox")
	officer = world.get_node_or_null("LevelGeometry/Patrols/Officer")
	detections = 0
	world.stealth.player_detected.connect(func(): detections += 1)
	return check(box != null and officer != null, "LevelGeometry/HideSpots/BreadBox and Patrols/Officer exist")

# =====================================================================================
# 1. Узел и облик
# =====================================================================================

func _part_spot() -> void:
	print("--- spot ---")
	check(box is HideSpot and box.mode == &"box" and box.interaction_id == &"bread_box", "BreadBox is a HideSpot, mode box, id bread_box")
	check(box.is_in_group(&"hide_spots") and box.has_method(&"reset"), "BreadBox is in group hide_spots with reset()")
	check(_near2(box.global_position, Layout.BREAD_BOX, 0.01) and box.home == Layout.BREAD_BOX, "BreadBox at Layout.BREAD_BOX %s" % box.global_position)
	check(box.prompt == HideTuning.PROMPT_BOX_ENTER, "prompt «%s» (%s)" % [HideTuning.PROMPT_BOX_ENTER, box.prompt])
	check(box.look != null and box.look.visible, "crate look is visible in the world")
	var labels: Array = box.look.find_children("*", "Label3D", true, false)
	check(labels.size() == 4 and labels.all(func(l): return l.text == "БАТОНЫ"), "«БАТОНЫ» on four sides (%d)" % labels.size())
	check(box.look.get_node_or_null("Snow") != null, "snow cap on the lid")
	var body: MeshInstance3D = box.look.get_node("Body")
	var size: Vector3 = (body.mesh as BoxMesh).size
	check(size.is_equal_approx(Vector3(1.0, 1.2, 0.8)), "crate ≈ 1.0 × 1.2 × 0.8 m (%s)" % size)
	check(box.find_children("*", "CollisionObject3D", true, false).is_empty(), "crate has no solid body (rays and paths unchanged)")
	await _shot_box_at_kiosk()

# =====================================================================================
# 2. Надеть и снять по E
# =====================================================================================

func _part_wear() -> void:
	print("--- wear ---")
	_sensors(false)
	await _place(_box_stand(), 0.0)
	check(player.current_interactable() == box, "next to the crate: E target is the crate")
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_BOX_ENTER, "HUD prompt «%s»" % HideTuning.PROMPT_BOX_ENTER)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"box" and player.hide_owner == box, "E → hide_mode box, owner BreadBox")
	check(player.hide_visual.get_child_count() == 1 and is_instance_valid(box.worn) and box.worn.get_parent() == player.hide_visual, "one crate in player.hide_visual")
	check(box.worn.find_children("*", "Label3D", true, false).size() == 4, "worn crate has the same «БАТОНЫ» sides")
	check(not box.look.visible and not player.get_node("Visual/Look").visible, "world crate and Ilyusha's sprite hidden")
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_BOX_EXIT, "HUD prompt «%s» (%s)" % [HideTuning.PROMPT_BOX_EXIT, world.get_hud_state()["prompt"]])
	# Отойти на 4 м: снять можно где угодно.
	check(await drv.walk_to(_away()), "walked off the crate's spot in the box (%s)" % drv.last_error)
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_BOX_EXIT, "away from the spot: prompt still «%s» (%s)" % [HideTuning.PROMPT_BOX_EXIT, world.get_hud_state()["prompt"]])
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"none" and player.hide_visual.get_child_count() == 0, "E → hide_mode none, hide_visual empty")
	check(box.look.visible and player.get_node("Visual/Look").visible, "crate and sprite visible again")
	var d := _flat(box.global_position, player.global_position)
	check(d > 0.5 and d < 1.3, "crate left next to Ilyusha (%.2f m)" % d)
	check(_crates() == 1, "exactly one crate in the scene (%d)" % _crates())
	check(box.prompt == HideTuning.PROMPT_BOX_ENTER and player.current_interactable() == box, "dropped crate can be put on again")
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"box" and _crates() == 1, "E → on again from the new place, one crate (%d)" % _crates())
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"none" and _crates() == 1, "E → off again, one crate")
	world.reset_hide()
	await drv.frames(2)
	check(_near2(box.global_position, Layout.BREAD_BOX, 0.01) and box.look.visible, "reset_hide() → crate back at Layout.BREAD_BOX")

# =====================================================================================
# 3. Заметность через сенсор полицейского
# =====================================================================================

func _part_exposure() -> void:
	print("--- exposure via the officer sensor ---")
	_sensors(false)
	var sensor: DetectionSensor = officer.sensor
	sensor.enabled = true
	world.stealth.set_frozen(true, &"test")
	officer.place_at(Layout.OFFICER_POST)   # лицом на запад, 7–9 с до разворота
	var far := Layout.OFFICER_POST + Vector3(-6.0, 0, 0)
	var near := Layout.OFFICER_POST + Vector3(-1.3, 0, 0)
	check(_free(far) and _free(near), "test spots west of the post are free")
	await _place(far, PI * 0.5)
	check(sensor.poll() == 1.0, "no box, 6 m in the west cone → 1.0")
	check(box.enter(), "enter() from afar")
	await drv.frames(5)
	var v := sensor.poll()
	check(v == 0.0 and sensor.in_view, "box standing, 6 m → 0.0, in_view (%.2f)" % v)
	drv._walk_axes(Vector3(-1, 0, 0))
	await drv.frames(12)
	v = sensor.poll()
	check(is_equal_approx(v, 0.75) and not player.is_still(), "box walking, 6 m → 0.75 (%.2f)" % v)
	drv.release_all()
	await drv.frames(20)
	await _place(near, PI * 0.5)
	v = sensor.poll()
	check(is_equal_approx(v, 0.5), "box standing, 1.3 m → 0.5 (%.2f)" % v)
	await _place(Layout.OFFICER_POST + Vector3(-1.6, 0, 0), PI * 0.5)
	v = sensor.poll()
	check(v == 0.0, "box standing, 1.6 m → 0.0 (%.2f)" % v)
	check(box.exit(), "exit()")
	world.reset_hide()
	world.stealth.set_frozen(false, &"test")
	await _wait_clear()

# =====================================================================================
# 4. Отказы в коробке: «Лада», Бабка, продавщица
# =====================================================================================

func _part_refusals() -> void:
	print("--- refusals ---")
	_sensors(false)
	var m := world.mission
	# «Лада»
	await _place(_car_stand(), 0.0)
	check(box.enter(), "box on at the Lada")
	await drv.frames(3)
	check(world.get_hud_state()["prompt"] == HideTuning.HINT_BOX, "Lada door in the box: prompt «%s» (%s)" % [HideTuning.HINT_BOX, world.get_hud_state()["prompt"]])
	await drv.interact()
	await drv.frames(3)
	check(world.control_mode == &"on_foot" and world.get_hud_state()["hide_hint"] == HideTuning.HINT_BOX, "E at the Lada → still on foot, hint «%s»" % HideTuning.HINT_BOX)
	# Бабка
	await _place(_babka_stand(), 0.0)
	var state_before: StringName = m.state
	await drv.interact()
	await drv.frames(5)
	check(not world.quest_flow.is_dialog_open() and m.state == state_before, "E at Babka in the box → no dialog (%s)" % m.state)
	check(world.get_hud_state()["hide_hint"] == HideTuning.HINT_BOX, "Babka: hint «%s» (%s)" % [HideTuning.HINT_BOX, world.get_hud_state()["hide_hint"]])
	world.reset_hide()
	# Продавщица: этап покупки, окно.
	m.interact(&"babka")
	m.accept()
	m.notify_entered_car()
	m.notify_arrived_kiosk()
	check(m.state == &"BUY_BREAD", "mission at BUY_BREAD (%s)" % m.state)
	await _place(_vendor_stand(), -PI * 0.5)
	check(box.enter(), "box on at the window")
	await drv.frames(3)
	check(world.get_hud_state()["prompt"] == QuestLines.HIDE_BOX_VENDOR, "window in the box: prompt «%s» (%s)" % [QuestLines.HIDE_BOX_VENDOR, world.get_hud_state()["prompt"]])
	await drv.interact()
	await drv.frames(5)
	check(not world.quest_flow.is_dialog_open() and m.state == &"BUY_BREAD" and not m.has_bread, "E at the window in the box → no dialog, no purchase")
	check(world.get_hud_state()["hide_hint"] == QuestLines.HIDE_BOX_VENDOR, "window: hint «%s»" % QuestLines.HIDE_BOX_VENDOR)
	check(QuestLines.HIDE_BOX_VENDOR.contains("Оптовикам не продаю. Вылезайте"), "vendor line text")
	world.reset_hide()
	await drv.frames(int(HideTuning.HINT_SECONDS * 60) + 5)

# =====================================================================================
# 5. Провал в коробке → респавн: одна коробка на home, Илюша без режима
# =====================================================================================

func _part_fail_reset() -> void:
	print("--- fail and reset ---")
	_sensors(false)
	officer.sensor.enabled = true
	officer.place_at(Layout.OFFICER_POST)
	await _place(Layout.OFFICER_POST + Vector3(-4.5, 0, 0), PI * 0.5)
	box.enter()
	await drv.frames(2)
	var before := detections
	var frames := 0
	while not world.is_stealth_failing() and frames < 480:
		drv._walk_axes(Vector3(-1, 0, 0))
		await drv.frames(1)
		frames += 1
	drv.release_all()
	check(world.is_stealth_failing() and detections == before + 1, "walking in the box in the cone → detected (%.2f s)" % (frames / 60.0))
	var waited := 0
	while world.is_stealth_failing() and waited < 300:
		await drv.frames(1)
		waited += 1
	await drv.frames(3)
	check(_near2(player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "respawned at the checkpoint")
	check(player.hide_mode == &"none" and player.hide_visual.get_child_count() == 0 and player.get_node("Visual/Look").visible, "after the fail: no mode, no worn crate, sprite visible")
	check(_near2(box.global_position, Layout.BREAD_BOX, 0.01) and box.look.visible and box.prompt == HideTuning.PROMPT_BOX_ENTER, "after the fail: crate at Layout.BREAD_BOX, visible, prompt enter")
	check(_crates() == 1, "after the fail: one crate (%d)" % _crates())
	check(is_equal_approx(player.speed_limit(), Ilyusha.WALK_SPEED) and player.input_enabled, "after the fail: WALK_SPEED, input on")
	# Коробку унесли и сбросили миром.
	await _place(_box_stand(), 0.0)
	officer.sensor.enabled = false
	await drv.interact()
	await drv.walk_to(_away())
	world.reset_car()
	await drv.frames(3)
	check(player.hide_mode == &"none" and _near2(box.global_position, Layout.BREAD_BOX, 0.01) and _crates() == 1, "reset_car() (reset_hide) → crate home, one crate, no mode")
	# reset() без reset_hide: короб не остаётся на Илюше.
	box.enter()
	box.reset()
	await drv.frames(2)
	check(player.hide_mode == &"none" and player.hide_visual.get_child_count() == 0 and _crates() == 1, "reset() while worn → mode none, one crate")
	await _wait_clear()

# =====================================================================================
# 6. 20 входов и выходов по E
# =====================================================================================

func _part_toggles() -> void:
	print("--- 20 toggles ---")
	_sensors(false)
	await _place(_box_stand(), 0.0)
	await drv.frames(5)
	var player_nodes := player.find_children("*", "", true, false).size()
	var spot_nodes: int = box.find_children("*", "", true, false).size()
	var ok := true
	for i in 20:
		await drv.interact()
		await drv.frames(2)
		ok = ok and player.hide_mode == &"box" and player.hide_visual.get_child_count() == 1
		await drv.interact()
		await drv.frames(2)
		ok = ok and player.hide_mode == &"none" and player.hide_visual.get_child_count() == 0
	await drv.frames(5)
	check(ok, "20 enter/exit cycles by E all worked")
	var p_after := player.find_children("*", "", true, false).size()
	var s_after: int = box.find_children("*", "", true, false).size()
	check(p_after == player_nodes and s_after == spot_nodes, "no node leak (Ilyusha %d → %d, crate %d → %d)" % [player_nodes, p_after, spot_nodes, s_after])
	check(_crates() == 1 and box.look.visible, "one crate after 20 cycles")
	check(is_equal_approx(player.speed_limit(), Ilyusha.WALK_SPEED), "WALK_SPEED after 20 cycles")
	world.reset_hide()

# =====================================================================================
# 7. Гэги C02 и C03: по разу за попытку
# =====================================================================================

func _part_gags() -> void:
	print("--- gags ---")
	_sensors(false)
	world.reset_hide()
	await _wait_clear()
	var sound := world.get_node("SoundDirector")
	var c02: int = box.gag_counts[&"C02"]
	var c03: int = box.gag_counts[&"C03"]
	officer.sensor.enabled = true
	officer.place_at(Layout.OFFICER_POST)
	# C02: в коробке у её места, патруль смотрит на запад (≈ 8 м, в конусе).
	await _place(_box_stand(), 0.0)
	await drv.interact()
	await drv.frames(10)
	check(player.hide_mode == &"box" and officer.sensor.in_view, "box on at its spot, in the officer's view (%.1f m)" % officer.sensor.distance_to_player())
	await drv.frames(int(BoxSpot.GAG_STILL_SECONDS * 60) - 30)
	check(box.gag_counts[&"C02"] == c02, "C02 not before 3 s")
	await drv.frames(60)
	check(box.gag_counts[&"C02"] == c02 + 1, "C02 after 3 s standing in view (%d)" % (box.gag_counts[&"C02"] - c02))
	check(sound.subtitle_card.visible and sound.subtitle_label.text.contains("Почему коробка стоит без сопровождения?"), "C02 subtitle on screen: «%s»" % sound.subtitle_label.text)
	check(sound.subtitle_label.text.split("\n").size() == 2, "two lines per screen")
	await _shot("gag_c02_on_screen")
	await drv.frames(160)
	check(sound.subtitle_label.text.contains("К товару вопросов нет"), "C02 second page after 2.5 s («%s»)" % sound.subtitle_label.text)
	officer.place_at(Layout.OFFICER_POST)
	await drv.frames(300)
	check(box.gag_counts[&"C02"] == c02 + 1 and not world.is_stealth_failing(), "C02 once per attempt, standing box not detected")
	check(not sound.subtitle_card.visible, "subtitle gone after the gag")
	# C03: идти в конусе до шкалы > 0,3, остановиться, снова идти — второй раз не показывается.
	officer.place_at(Layout.OFFICER_POST)
	await _place(Layout.OFFICER_POST + Vector3(-5.0, 0, 0), PI * 0.5)
	box.reset()
	box.enter()
	for k in 2:
		var frames := 0
		while world.stealth.suspicion <= 0.4 and frames < 240:
			drv._walk_axes(Vector3(-1, 0, 0) if k == 0 else Vector3(1, 0, 0))
			await drv.frames(1)
			frames += 1
		drv.release_all()
		await drv.frames(2)
		check(box.gag_counts[&"C03"] == c03 + 1, "walk %d in the cone, suspicion %.2f > 0.3 → C03 shown once (%d)" % [k + 1, world.stealth.suspicion, box.gag_counts[&"C03"] - c03])
		if k == 0:
			check(sound.subtitle_card.visible and sound.subtitle_label.text.contains("Товар пошёл"), "C03 subtitle on screen: «%s»" % sound.subtitle_label.text)
			await drv.frames(150)   # стоя — шкала спадает
	check(not world.is_stealth_failing(), "C03 walks stopped in time, no fail")
	# Новая попытка (reset) — гэги снова доступны.
	box.reset()
	await _wait_clear()
	officer.place_at(Layout.OFFICER_POST)
	await _place(Layout.OFFICER_POST + Vector3(-5.0, 0, 0), PI * 0.5)
	box.enter()
	var n := 0
	while box.gag_counts[&"C03"] == c03 + 1 and n < 240:
		drv._walk_axes(Vector3(-1, 0, 0))
		await drv.frames(1)
		n += 1
	drv.release_all()
	check(box.gag_counts[&"C03"] == c03 + 2, "after reset() C03 shows again (new attempt)")
	world.reset_hide()
	officer.sensor.enabled = false
	await _wait_clear()

# =====================================================================================
# 8. Честный проход участка в коробке (свежий мир, настоящий патруль)
# =====================================================================================

func _part_honest_pass() -> void:
	print("--- honest pass in the box ---")
	if not await _fresh_world():
		return
	var m := world.mission
	m.interact(&"babka")
	m.accept()
	m.notify_entered_car()
	m.notify_arrived_kiosk()
	check(m.state == &"BUY_BREAD", "fresh world at BUY_BREAD")
	await _place(Layout.KIOSK_STAGING, PI)
	await drv.frames(30)
	var c02: int = box.gag_counts[&"C02"]
	var start := detections
	var track := [0.0, 0]   # максимум шкалы, кадры (лямбда меняет массив, не локальные)
	drv.on_frame = func():
		track[0] = maxf(track[0], world.stealth.suspicion)
		track[1] += 1
	# За контейнеры; дождаться «юга»; вдоль гаражей к коробке.
	var ok: bool = await drv.walk_path(Layout.SNEAK_WEST[0])
	ok = ok and await drv.wait_officer_turn(1)
	ok = ok and await drv.walk_path([Vector3(51.2, 0, -64.5), Vector3(51.2, 0, -72.4), _box_stand()])
	check(ok and detections == start, "parking → behind the bins → to the crate without a fail (%s)" % drv.last_error)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"box", "crate on")
	await _shot("ilyusha_in_box_game_camera")
	# Стоять, пока патруль смотрит на запад; на «юге» — к окну.
	ok = await drv.wait_officer_turn(1)
	check(ok and detections == start and not world.is_stealth_failing(), "standing in the box through the west facing — not detected (max %.2f)" % track[0])
	ok = await drv.walk_path([Vector3(58.3, 0, -73.6), _vendor_stand()])
	print("INFO: honest box pass parking → window %.1f s, max suspicion %.2f, C02 shown %d" % [track[1] / 60.0, track[0], box.gag_counts[&"C02"] - c02])
	check(ok and detections == start and not world.is_stealth_failing(), "in the box to the window without a fail (%s)" % drv.last_error)
	check(_near2(player.global_position, _vendor_stand(), 0.6) and player.hide_mode == &"box", "at the window in the box")
	# Отойти из зоны продавщицы, снять коробку, купить хлеб.
	ok = await drv.walk_to(Layout.VENDOR_WINDOW + Vector3(0.8, 0, -3.8))
	await drv.interact()
	await drv.frames(3)
	check(ok and player.hide_mode == &"none", "box off 3.8 m north of the window")
	ok = await drv.walk_to(_vendor_stand())
	await drv.interact()
	await drv.frames(10)
	check(world.quest_flow.is_dialog_open(), "E at the window without the box → vendor dialog")
	for i in 10:
		if m.has_bread:
			break
		if not await _press_any(["КУПИТЬ ХЛЕБ", "ДАЛЬШЕ"]):
			break
	check(m.has_bread and m.state == &"RETURN_HOME" and detections == start, "bread bought after the box pass, no fail (%s)" % m.state)
	drv.on_frame = Callable()

## Кадр коробки у киоска с отдельной камеры (только --capture), затем снова игровая камера.
func _shot_box_at_kiosk() -> void:
	if not capture:
		return
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Layout.BREAD_BOX + Vector3(-2.6, 1.7, 3.6)
	cam.look_at(Layout.BREAD_BOX + Vector3(0.6, 0.7, -0.6))
	cam.make_current()
	await _shot("box_at_kiosk")
	cam.global_position = Layout.BREAD_BOX + Vector3(-6.0, 3.2, 9.0)
	cam.look_at(Layout.KIOSK + Vector3(1.0, 1.0, 0.0))
	await _shot("box_at_kiosk_wide")
	world.camera_rig.camera.make_current()
	cam.queue_free()
	await drv.frames(2)

# =====================================================================================
# Помощники
# =====================================================================================

## Место рядом с коробкой (южнее неё), в зоне E.
func _box_stand() -> Vector3:
	return Layout.BREAD_BOX + Vector3(0.0, 0.0, 1.2)

## В стороне от зоны коробки (2,7 м от её места) и от других укрытий, у прохода вдоль гаражей.
func _away() -> Vector3:
	return Layout.BREAD_BOX + Vector3(-2.7, 0.0, 0.4)

func _vendor_stand() -> Vector3:
	return Layout.VENDOR_WINDOW + Vector3(0.6, 0.0, 0.0)

func _babka_stand() -> Vector3:
	return Layout.BABKA + Vector3(0.6, 0.0, -2.0)

func _car_stand() -> Vector3:
	var p: Vector3 = world.car.global_transform * Vector3(-2.2, 0, 0)
	p.y = 0.0
	return p

## Все короба «БАТОНЫ» в сцене: в мире видимый облик + надетый.
func _crates() -> int:
	var n := 0
	for node in world.find_children("*", "Label3D", true, false):
		if node.text == "БАТОНЫ" and (node as Node3D).is_visible_in_tree():
			n += 1
	return n / 4

func _sensors(on: bool) -> void:
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = on

func _place(p: Vector3, yaw: float) -> void:
	drv.release_all()
	player.place(p, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await drv.frames(3)

func _wait_clear() -> void:
	for i in 900:
		if world.stealth.suspicion == 0.0 and world.stealth.protection_left() == 0.0 and not world.is_stealth_failing():
			return
		await drv.frames(1)

func _press_any(texts: Array) -> bool:
	for text in texts:
		if _visible_button(text):
			var ok: bool = await drv.press_button(text, &"ui_left")
			if not ok:
				ok = await drv.press_button(text, &"ui_right")
			await drv.frames(3)
			return ok
	return false

func _visible_button(text: String) -> Button:
	for child in world.find_children("*", "Button", true, false):
		if child.text == text and child.is_visible_in_tree():
			return child
	return null

func _free(p: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.8)
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _near2(a: Vector3, b: Vector3, tol: float) -> bool:
	return _flat(a, b) <= tol

func _shot(label: String) -> void:
	if not capture:
		return
	await drv.frames(20)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish(code := -1) -> void:
	drv.release_all()
	print("HIDE_BOX: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

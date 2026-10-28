extends SceneTree
## EXT-01 S: стелс-ядро по C7 на настоящей сцене main.tscn (docs/extension/STEALTH_DESIGN.md, ACCEPTANCE_TESTS.md).
## Тестовый DetectionSensor ставится в мир; точки — только из Layout (C1) или относительно Илюши.
## Чужие сенсоры (наблюдатели части N) на время прогона выключены, кроме проверки чекпоинта.
## Проверки: видимость по расстоянию и углу; луч — стена дома, гаражи и KioskPavilion укрывают, тропинка
## и низкий снег — нет; спад и сброс при выходе из конуса; frozen в диалоге и на паузе; в машине не видят;
## провал до покупки (has_bread false) и после (has_bread true, FSM не меняется); чекпоинт вне конусов;
## после провалов квест завершается однократно. Диалоги, покупка, ходьба и пауза — вводом (playthrough_driver).
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/stealth_test.gd
## Кадры: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/stealth_test.gd -- --capture
##   → builds/screenshots/ext01/s/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const SensorScript = preload("res://game/stealth/detection_sensor.gd")
const OUT := "res://builds/screenshots/ext01/s"
const FAIL_TEXT := "ВАШ МАРШРУТ УТОЧНЁН"
const TOAST_TEXT := "МАРШРУТ УТОЧНЁН. ПОПРОБУЙТЕ ЕЩЁ РАЗ"
const HINT_TEXT := "Тебя заметили? Уйди из вида"

var failures: Array[String] = []
var checks := 0
var capture := false
var main: Node
var drv
var world: DemoWorld
var sensor: DetectionSensor
var detected_signals := 0
var completed_signals := 0
var _foreign: Array = []

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: stealth test exceeded 900 simulated seconds")
		_finish(2))
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	world = main.world
	if not check(world != null and world.get_node_or_null("StealthDirector") is StealthDirector, "DemoWorld has the StealthDirector node (C7)"):
		_finish()
		return
	check(world.stealth.process_mode == Node.PROCESS_MODE_PAUSABLE, "StealthDirector is PAUSABLE (no ticking on pause)")
	world.stealth.player_detected.connect(func(): detected_signals += 1)
	world.mission.quest_completed.connect(func(_xp): completed_signals += 1)
	for s in get_nodes_in_group(&"detection_sensors"):
		_foreign.append(s)
		s.enabled = false
	print("INFO: foreign sensors in the world: %d" % _foreign.size())
	sensor = SensorScript.new()
	sensor.name = "TestSensor"
	world.add_child(sensor)
	check(sensor.is_in_group(&"detection_sensors"), "sensor joins group detection_sensors")
	await _part_geometry()
	await _part_cover()
	await _part_decay()
	if await _part_dialog_and_pause():
		if await _part_car():
			await _part_fail_before()
			if await _part_buy_and_fail_after():
				await _part_checkpoint()
				await _part_complete()
	check(detected_signals == 2, "player_detected fired exactly twice in the run (%d)" % detected_signals)
	drv.release_all()
	_finish()

# =====================================================================================
# 1. Расстояние и угол (открытая площадка двора, относительно SPAWN)
# =====================================================================================

func _part_geometry() -> void:
	print("--- geometry ---")
	var p := Layout.SPAWN + Vector3(10.0, 0.0, -12.0)
	check(_free(p), "yard spot for the geometry checks is free (%s)" % p)
	await _place_player(p, 0.0)
	sensor.range_m = 9.0
	sensor.fov_deg = 75.0
	sensor.enabled = true
	_aim(p + Vector3(0, 0, -5), p)
	check(_vis() == 1.0, "5 m in front, facing Ilyusha → 1")
	_aim(p + Vector3(0, 0, -8.5), p)
	check(_vis() == 1.0, "8.5 m (inside range 9) → 1")
	_aim(p + Vector3(0, 0, -12), p)
	check(_vis() == 0.0, "12 m (outside range 9) → 0")
	_aim(p + Vector3(0, 0, -5), p + Vector3(0, 0, -20))
	check(_vis() == 0.0, "5 m but facing away → 0")
	_aim(p + Vector3(0, 0, -5), p)
	sensor.rotation.y += deg_to_rad(30.0)
	check(_vis() == 1.0, "30° off axis (fov 75) → 1")
	sensor.rotation.y += deg_to_rad(16.0)
	check(_vis() == 0.0, "46° off axis (fov 75) → 0")
	_aim(p + Vector3(0, 0, -5), p)
	sensor.enabled = false
	check(_vis() == 0.0, "enabled = false → 0")
	sensor.enabled = true
	# Кэш: visibility() обновляется опросом раз в 0,15 с, а не каждый кадр.
	_aim(p + Vector3(0, 0, -5), p)
	await drv.frames(12)
	check(sensor.visibility() == 1.0, "cached visibility() is 1 after the poll")
	sensor.enabled = false
	await drv.frames(60)
	check(world.stealth.suspicion == 0.0 or world.stealth.state != &"alert", "no alert from the geometry checks")

# =====================================================================================
# 2. Луч: укрытия и декор (точки от коробок Layout)
# =====================================================================================

func _part_cover() -> void:
	print("--- cover ---")
	sensor.range_m = 30.0
	sensor.fov_deg = 90.0
	sensor.enabled = true
	# Стена дома H8_East: Илюша у западной стены, сенсор за восточной.
	var h8 := _solid("H8_East")
	var west_x: float = h8[0].x - h8[1].x * 0.5
	var east_x: float = h8[0].x + h8[1].x * 0.5
	var z := -80.0
	var p := Vector3(west_x - 3.0, 0, z)
	check(_free(p), "spot west of H8_East is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(east_x + 3.0, 0, z), p)
	check(_vis() == 0.0, "house wall (H8_East) covers Ilyusha → 0")
	_aim(Vector3(west_x - 8.0, 0, z), p)
	check(_vis() == 1.0, "same distance, nothing between (snow bank 0.9 m is below the ray) → 1")
	# Гаражи у киоска: Илюша западнее ряда, сенсор восточнее.
	var garages := _solid("Garages_Kiosk")
	var gz: float = garages[0].y
	p = Vector3(garages[0].x - garages[1].x * 0.5 - 4.0, 0, gz)
	check(_free(p), "spot west of Garages_Kiosk is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(garages[0].x + garages[1].x * 0.5 + 2.0, 0, gz - 2.0), p)
	check(_vis() == 0.0, "garage row covers Ilyusha → 0")
	# Павильон у киоска (KioskPavilion): Илюша западнее, сенсор восточнее; контроль — рядом, мимо павильона.
	var pav := _solid("KioskPavilion")
	var pz: float = pav[0].y
	p = Vector3(pav[0].x - pav[1].x * 0.5 - 2.2, 0, pz)
	check(_free(p), "spot west of KioskPavilion is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(pav[0].x + pav[1].x * 0.5 + 3.0, 0, pz), p)
	check(_vis() == 0.0, "KioskPavilion covers Ilyusha → 0")
	var dz: float = pav[1].z * 0.5 + 2.5
	p = Vector3(p.x, 0, pz - dz)
	check(_free(p), "control spot past the pavilion is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(pav[0].x + pav[1].x * 0.5 + 3.0, 0, pz - dz), p)
	check(_vis() == 1.0, "control: same offset past the pavilion end → 1")
	# Тропинка у киоска — плоский декор без коллизии: Илюша на ней, сенсор на другом её конце.
	var trail := _trail_near(Layout.KIOSK)
	check(trail != null, "a Trail decor mesh exists near the kiosk and has no collision")
	if trail:
		var a: Vector3 = trail.global_position + Vector3(0, 0, -4.0)
		var b: Vector3 = trail.global_position + Vector3(0, 0, 5.0)
		a.y = 0.0
		b.y = 0.0
		await _place_player(a, 0.0)
		_aim(b, a)
		check(_vis() == 1.0, "snow trail (no collision) does not cover → 1 (blocker '%s', trail %s)" % [sensor.last_blocker, trail.global_position])
	# Низкий снег Snow_StreetA (коробка 0,8 м): луч к центру Илюши проходит над ним.
	var snow := _solid("Snow_StreetA")
	p = Vector3(snow[0].x, 0, snow[0].y + snow[1].z * 0.5 + 2.5)
	check(_free(p), "spot south of Snow_StreetA is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(snow[0].x, 0, snow[0].y - snow[1].z * 0.5 - 2.5), p)
	check(_vis() == 1.0, "low snow mound (0.8 m) does not cover → 1")
	sensor.enabled = false
	sensor.range_m = 9.0
	sensor.fov_deg = 75.0
	await drv.frames(60)

# =====================================================================================
# 3. Рост, индикатор, спад и сброс
# =====================================================================================

func _part_decay() -> void:
	print("--- decay ---")
	var p := Layout.SPAWN + Vector3(10.0, 0.0, -12.0)
	await _place_player(p, 0.0)
	_aim(p + Vector3(0, 0, -5), p)
	sensor.enabled = true
	await drv.frames(60)
	var s0: float = world.stealth.suspicion
	check(s0 >= 0.3 and s0 <= 0.6, "after 1.0 s in view suspicion ≈ 0.5 (%.2f; rise 1/2.0 s, poll 0.15 s)" % s0)
	check(world.stealth.state == &"suspicious", "state is suspicious while filling (%s)" % world.stealth.state)
	var hud := world.get_node("GameHUD")
	check(hud.suspicion_meter.is_showing(), "HUD: suspicion meter (eye + !) is showing")
	check(_hud_has(HINT_TEXT), "HUD: hint «%s» on first appearance" % HINT_TEXT)
	check(hud.suspicion_meter.plate.position.x > 1500 and hud.suspicion_meter.plate.position.y < 100, "HUD: meter sits top-right")
	await _shot("indicator_suspicious")
	s0 = world.stealth.suspicion   # в режиме кадров шкала успела вырасти за время снимка
	# Вышли из конуса: Илюша за спиной сенсора.
	await _place_player(p + Vector3(0, 0, -10), 0.0)
	await drv.frames(30)
	var s1: float = world.stealth.suspicion
	check(s1 < s0 - 0.15, "0.5 s out of view: suspicion decays (%.2f → %.2f)" % [s0, s1])
	await drv.frames(60)
	check(world.stealth.suspicion == 0.0 and world.stealth.state == &"safe", "suspicion resets to 0 and safe out of view (%.2f, %s)" % [world.stealth.suspicion, world.stealth.state])
	await drv.frames(40)
	check(not hud.suspicion_meter.is_showing(), "HUD: meter hidden again at 0")
	check(not _hud_has(HINT_TEXT), "HUD: hint gone after 3 s")
	sensor.enabled = false

# =====================================================================================
# 4. frozen: диалог Бабки (вводом) и пауза
# =====================================================================================

func _part_dialog_and_pause() -> bool:
	print("--- dialog & pause ---")
	await _place_player(Layout.SPAWN, Layout.SPAWN_YAW)
	if not check(await drv.walk_to(_babka_stand()), "walked to Babka (%s)" % drv.last_error):
		return false
	await drv.interact()
	await drv.frames(5)
	if not check(world.mission.state == &"OFFERED", "E at Babka opens the offer dialog (%s)" % world.mission.state):
		return false
	check(world.stealth.frozen and world.stealth.snap()["reasons"].has(&"dialog"), "frozen while the dialog is open (reasons %s)" % [world.stealth.snap()["reasons"]])
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(0, 0, -4), p)
	sensor.enabled = true
	await drv.frames(60)
	check(_vis() == 1.0, "sensor does see Ilyusha during the dialog (visibility 1)")
	check(world.stealth.suspicion == 0.0, "…but suspicion stays 0 in the dialog (%.2f)" % world.stealth.suspicion)
	if not check(await drv.press_button("ПРИНЯТЬ"), "ПРИНЯТЬ pressed (%s)" % drv.last_error):
		return false
	await drv.frames(3)
	check(world.mission.state == &"GO_TO_CAR", "quest accepted → GO_TO_CAR")
	check(not world.stealth.frozen, "not frozen after the dialog closes")
	await drv.frames(30)
	check(world.stealth.suspicion > 0.0, "suspicion rises again after the dialog (%.2f)" % world.stealth.suspicion)
	# Пауза: директор не тикает, frozen читается как true.
	await drv.pause_key()
	await drv.frames(3)
	check(paused, "Esc pauses the game")
	check(world.stealth.frozen, "frozen on pause")
	var before: float = world.stealth.suspicion
	await drv.frames(60)
	check(is_equal_approx(world.stealth.suspicion, before), "suspicion unchanged during pause (%.2f vs %.2f)" % [before, world.stealth.suspicion])
	await drv.pause_key()
	await drv.frames(3)
	check(not paused and not world.stealth.frozen, "resume → not frozen")
	sensor.enabled = false
	await drv.frames(90)
	check(world.stealth.suspicion == 0.0, "decayed to 0 before the car checks")
	return true

# =====================================================================================
# 5. В машине не видят; respawn_at_checkpoint() в машине не применяется
# =====================================================================================

func _part_car() -> bool:
	print("--- car ---")
	if not check(await drv.walk_to(_car_stand()), "walked to the Lada (%s)" % drv.last_error):
		return false
	await drv.interact()
	await drv.frames(10)
	if not check(world.control_mode == &"in_car", "E → in the car"):
		return false
	var car_pos: Vector3 = world.car.global_position
	_aim(car_pos + Vector3(0, 0, -5), car_pos)
	sensor.enabled = true
	check(_vis() == 0.0, "sensor 5 m in front of the car: Ilyusha in the car → 0")
	await drv.frames(30)
	check(world.stealth.suspicion == 0.0, "no suspicion in the car")
	check(not world.respawn_at_checkpoint(), "respawn_at_checkpoint() refuses in the car")
	check(world.car.global_position.distance_to(car_pos) < 0.01, "car untouched by the refused respawn")
	await drv.interact()
	await drv.frames(15)
	if not check(world.control_mode == &"on_foot", "E → out of the car"):
		return false
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(0, 0, -4.0), p)   # не вдоль машины: там столб фонаря двора (Lamp_Yard)
	check(_vis() == 1.0, "on foot next to the car → 1 (blocker '%s')" % sensor.last_blocker)
	sensor.enabled = false
	await drv.frames(30)
	return true

# =====================================================================================
# 6. Провал до покупки
# =====================================================================================

func _part_fail_before() -> void:
	print("--- fail before purchase ---")
	var m := world.mission
	var state_before: StringName = m.state
	var car_pos: Vector3 = world.car.global_position
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(0, 0, -4.0), p)
	sensor.enabled = true
	var fail_frame := await _wait_until(func(): return world.is_stealth_failing(), 240)
	check(fail_frame >= 0 and fail_frame >= 100, "≈2 s in view → detection and fail screen (frame %d, blocker '%s')" % [fail_frame, sensor.last_blocker])
	check(detected_signals == 1, "player_detected emitted once (%d)" % detected_signals)
	check(world.stealth.state == &"alert" and world.stealth.suspicion >= 1.0, "state alert at detection")
	check(not world.player.input_enabled, "Ilyusha's input is off during the fail screen")
	await drv.frames(25)
	check(_hud_has(FAIL_TEXT), "HUD: «%s» shown" % FAIL_TEXT)
	await _shot("fail_screen")
	var respawn_frame := await _wait_until(func(): return not world.is_stealth_failing(), 240)
	check(respawn_frame >= 0 and respawn_frame + 25 <= 180, "fail screen ≤ 3 s (%d frames)" % (respawn_frame + 25))
	await drv.frames(2)
	check(_near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "Ilyusha respawned at Layout.STEALTH_CHECKPOINT (%s)" % world.player.global_position)
	check(absf(world.player.global_position.y) < 0.3, "respawn on the ground (y %.2f)" % world.player.global_position.y)
	check(not m.has_bread, "before purchase: has_bread stays false")
	check(m.state == state_before, "mission state unchanged by the fail (%s)" % m.state)
	check(world.car.global_position.distance_to(car_pos) < 0.01, "car not moved by the respawn")
	check(world.stealth.suspicion == 0.0 and world.stealth.state == &"safe", "suspicion reset to 0 / safe after respawn")
	check(world.stealth.frozen and world.stealth.protection_left() > 3.5, "4 s protection after respawn (%.1f s)" % world.stealth.protection_left())
	check(_hud_has(TOAST_TEXT), "HUD: toast «%s»" % TOAST_TEXT)
	check(world.player.input_enabled, "Ilyusha can move after the respawn")
	await _shot("toast_after_respawn")
	# Защита: сенсор видит, шкала не растёт.
	var c := Layout.STEALTH_CHECKPOINT
	_aim(c + Vector3(0, 0, -5), c)
	await drv.frames(60)
	check(_vis() == 1.0 and world.stealth.suspicion == 0.0, "during protection: seen but suspicion stays 0 (%.2f)" % world.stealth.suspicion)
	await drv.frames(90)
	check(not _hud_has(TOAST_TEXT), "toast gone after 2 s")
	await drv.frames(100)
	check(not world.stealth.frozen, "protection over after 4 s")
	check(world.stealth.suspicion > 0.0, "after protection the meter fills again (%.2f)" % world.stealth.suspicion)
	sensor.enabled = false
	await drv.frames(90)
	check(world.stealth.suspicion == 0.0, "decayed to 0 before the purchase")

# =====================================================================================
# 7. Покупка (вводом) и провал после покупки
# =====================================================================================

func _part_buy_and_fail_after() -> bool:
	print("--- purchase & fail after ---")
	var m := world.mission
	if not check(await drv.walk_to(_vendor_stand()), "walked from the checkpoint to the kiosk window (%s)" % drv.last_error):
		return false
	check(m.state == &"BUY_BREAD", "entering the kiosk square on foot → BUY_BREAD (%s)" % m.state)
	await drv.interact()
	await drv.frames(5)
	for i in 8:
		if m.has_bread:
			break
		if not await _press_any(["КУПИТЬ ХЛЕБ", "ДАЛЬШЕ"]):
			break
	if not check(m.has_bread and m.state == &"RETURN_HOME", "bread bought → RETURN_HOME, has_bread true (%s)" % m.state):
		return false
	await drv.frames(10)
	var car_pos: Vector3 = world.car.global_position
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(4.0, 0, 0), p)
	sensor.enabled = true
	var fail_frame := await _wait_until(func(): return world.is_stealth_failing(), 240)
	check(fail_frame >= 0 and detected_signals == 2, "second detection after the purchase (frame %d, signals %d)" % [fail_frame, detected_signals])
	var respawn_frame := await _wait_until(func(): return not world.is_stealth_failing(), 240)
	check(respawn_frame >= 0, "fail screen closes again")
	await drv.frames(2)
	check(_near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "respawned at the checkpoint again")
	check(m.has_bread, "after purchase: has_bread is kept")
	check(m.state == &"RETURN_HOME", "FSM stays RETURN_HOME after the fail (%s)" % m.state)
	check(world.car.global_position.distance_to(car_pos) < 0.01, "car still untouched")
	sensor.enabled = false
	return true

# =====================================================================================
# 8. Чекпоинт вне любого конуса (все сенсоры мира включены на один опрос)
# =====================================================================================

func _part_checkpoint() -> void:
	print("--- checkpoint ---")
	await _place_player(Layout.STEALTH_CHECKPOINT, Layout.STEALTH_CHECKPOINT_YAW)
	await drv.frames(200)   # защита после респавна прошла
	var seen := []
	for s in _foreign:
		s.enabled = true
		if s.poll() > 0.0:
			seen.append("%s@%s" % [s.name, s.global_position])
		s.enabled = false
	print("INFO: checkpoint %s checked against %d world sensors" % [Layout.STEALTH_CHECKPOINT, _foreign.size()])
	check(seen.is_empty(), "no world sensor sees Ilyusha at the checkpoint (%s)" % [seen])
	check(_free(Layout.STEALTH_CHECKPOINT), "checkpoint spot is free of solids")
	check(world.stealth.suspicion == 0.0, "suspicion 0 at the checkpoint")

# =====================================================================================
# 9. Возвращение пешком и однократное завершение квеста
# =====================================================================================

func _part_complete() -> void:
	print("--- complete ---")
	var m := world.mission
	var path := [Vector3(70, 0, -80), Vector3(70, 0, 30), Layout.ROUTE_WALK[3], Layout.ROUTE_WALK[2], Layout.ROUTE_WALK[1], _babka_stand()]
	if not check(await drv.walk_path(path), "walked back to Babka on foot (%s)" % drv.last_error):
		return
	check(m.has_bread and m.state == &"RETURN_HOME", "arrived with the bread (%s)" % m.state)
	await drv.interact()
	await drv.frames(10)
	# Цепочка реплик при возврате (EXT-01 L): «ДАЛЬШЕ» до кнопки «СДАТЬ ХЛЕБ».
	for i in 10:
		if m.state == &"COMPLETE":
			break
		if not await _press_any(["СДАТЬ ХЛЕБ", "ДАЛЬШЕ"]):
			break
	check(m.state == &"COMPLETE" and m.xp == 50, "E at Babka (+ chain) → COMPLETE, +50 (%s, xp %d)" % [m.state, m.xp])
	check(completed_signals == 1, "quest_completed emitted exactly once (%d)" % completed_signals)
	await drv.frames(60)
	check(completed_signals == 1 and m.state == &"COMPLETE", "still one completion a second later")
	check(world.stealth.state == &"safe", "stealth safe at the end")

# =====================================================================================
# Помощники
# =====================================================================================

func _place_player(p: Vector3, yaw: float) -> void:
	world.player.place(p, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await drv.frames(2)

## Сенсор в точку at, «лицом» (−Z) на look_at.
func _aim(at: Vector3, look_at: Vector3) -> void:
	sensor.global_position = Vector3(at.x, 0.0, at.z)
	var d := look_at - at
	sensor.rotation.y = atan2(-d.x, -d.z)

func _vis() -> float:
	return sensor.poll()

func _solid(name: String) -> Array:
	for s in Layout.all_solids():
		if s[0] == name:
			return [s[2], s[3]]
	push_error("no solid " + name)
	return [Vector2.ZERO, Vector3.ZERO]

## Ближайшая к точке тропинка: плоскость PlaneMesh на y = 0,024 прямо в LevelGeometry, без коллизии
## (дубли имени «Trail» Godot переименовывает в @MeshInstance3D@N, поэтому ищем по признакам, не по имени).
func _trail_near(p: Vector3) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_d := INF
	for mesh in world.get_node("LevelGeometry").get_children():
		if not (mesh is MeshInstance3D) or not (mesh.mesh is PlaneMesh) or absf(mesh.position.y - 0.024) > 0.002:
			continue
		if mesh.find_children("*", "CollisionObject3D", true, false).size() > 0:
			continue
		var d: float = Vector2(mesh.global_position.x - p.x, mesh.global_position.z - p.z).length()
		if d < best_d:
			best = mesh
			best_d = d
	return best

func _free(p: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.8)
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Ждать условие не дольше max_frames; возвращает номер кадра или −1.
func _wait_until(condition: Callable, max_frames: int) -> int:
	for i in max_frames:
		if condition.call():
			return i
		await drv.frames(1)
	return -1

## Нажать первую видимую кнопку из списка (цепочки реплик). false — ни одной нет.
func _press_any(texts: Array) -> bool:
	for text in texts:
		if _visible_button(text):
			var ok: bool = await drv.press_button(text, &"ui_left")
			if not ok:
				ok = await drv.press_button(text, &"ui_right")
			await drv.frames(3)
			return ok
	return false

func _babka_stand() -> Vector3:
	return Layout.BABKA + Vector3(0.6, 0.0, -2.0)

func _vendor_stand() -> Vector3:
	return Layout.VENDOR_WINDOW + Vector3(0.6, 0.0, 0.0)

func _car_stand() -> Vector3:
	var best := Vector3.INF
	for offset in [Vector3(-2.2, 0, 0), Vector3(2.2, 0, 0)]:
		var p: Vector3 = world.car.global_transform * offset
		p.y = 0.0
		if best == Vector3.INF or p.distance_to(world.player.global_position) < best.distance_to(world.player.global_position):
			best = p
	return best

func _near2(a: Vector3, b: Vector3, tol: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= tol

func _visible_texts() -> Array:
	var out := []
	for n in ["GameHUD", "QuestFlow", "Babka", "Vendor"]:
		if not world.has_node(n):
			continue
		for child in world.get_node(n).find_children("*", "", true, false):
			if (child is Label or child is Button) and (child as CanvasItem).is_visible_in_tree():
				out.append(child.text)
			elif child is Label3D and (child as Node3D).is_visible_in_tree():
				out.append(child.text)
	return out

func _hud_has(text: String) -> bool:
	return _visible_texts().has(text)

func _visible_button(text: String) -> Button:
	for child in world.find_children("*", "Button", true, false):
		if child.text == text and child.is_visible_in_tree():
			return child
	return null

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
	print("STEALTH: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

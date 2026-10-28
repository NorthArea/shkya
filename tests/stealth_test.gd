extends SceneTree
## EXT-01 S: стелс-ядро по C7 на настоящей сцене main.tscn (docs/extension/STEALTH_DESIGN.md, ACCEPTANCE_TESTS.md).
## Тестовый DetectionSensor ставится в мир; точки — только из Layout (C1) или относительно Илюши.
## Чужие сенсоры (наблюдатели части N) на время прогона выключены, кроме проверки чекпоинта.
## Проверки: видимость по расстоянию и углу; луч — стена дома, гаражи и KioskPavilion укрывают, тропинка
## и низкий снег — нет; спад и сброс при выходе из конуса; frozen в диалоге и на паузе; в машине не видят;
## провал до покупки (has_bread false) и после (has_bread true, FSM не меняется); чекпоинт вне конусов;
## после провалов квест завершается однократно. Диалоги, покупка, ходьба и пауза — вводом (playthrough_driver).
## Часть 10 (приёмка EXT-01 28.10) — свежий мир с настоящими наблюдателями: учебный автобус на улице A (индикатор
## без провала, в машине не видят), парковка южнее павильона, конус при приближении, «в лоб» к полицейскому —
## провал за ≤ 6 с, оба честных пути (Layout.SNEAK_EAST/WEST) — без провала только с ожиданием разворота и за
## 20…90 с, без ожидания — провал или индикатор; после покупки у окна 10 с шкала ≤ 0,3 (идущий патруль не смотрит),
## автобус ГСУМ ждёт за «Ладой» и не сдвигает её, встаёт на площадке носом на север; чекпоинт вне всех конусов;
## обратный путь Layout.SNEAK_BACK к машине без провала.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/stealth_test.gd
## Кадры: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/stealth_test.gd -- --capture
##   → builds/screenshots/ext01/s/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const SensorScript = preload("res://game/stealth/detection_sensor.gd")
const OUT := "res://builds/screenshots/ext01/s"
const FAIL_TEXT := "ВАШ МАРШРУТ УТОЧНЁН"
const TOAST_TEXT := "МАРШРУТ УТОЧНЁН: ВЫ ВСЁ ЕЩЁ ЗА ХЛЕБОМ"   # до покупки; после — «ВЫ ОСТАЛИСЬ ПЕШЕХОДОМ. ХЛЕБ ПРИ ВАС»
const HINT_TEXT := "Тебя заметили. Отойди, пока это ни к чему не обязывает"
## Начало прямой «в лоб» к окну: перед машиной на парковке, вне конусов (дальше 12 м от поста).
const DIRECT_FROM := Vector3(59.5, 0, -57.3)

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
# Монитор части 10 (drv.on_frame): максимум шкалы, кадры, первый кадр экрана провала.
var _track_max := 0.0
var _track_frames := 0
var _track_fail := -1
var _kiosk_detections := 0

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
	await _part_kiosk_section()
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
# 10. Участок у киоска: свежий мир, настоящие наблюдатели (приёмка EXT-01 28.10)
# =====================================================================================

func _part_kiosk_section() -> void:
	print("--- kiosk section: fresh world, real observers ---")
	drv.on_frame = Callable()
	main.start_game()
	await drv.frames(10)
	world = main.world
	var m := world.mission
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	var van: CityVan = patrols.van
	world.stealth.player_detected.connect(func(): _kiosk_detections += 1)
	drv.on_frame = _track
	check(officer.sensor.show_cone and van.sensor.show_cone, "officer and van sensors draw a cone (show_cone)")
	check(Layout.OFFICER_FACING.size() == 2 and is_equal_approx(Layout.OFFICER_FACING[0], PI * 0.5) and absf(Layout.OFFICER_FACING[1] - PI) <= 0.35, "officer turns west and south (%s)" % [Layout.OFFICER_FACING])
	# Окно вне обоих конусов полицейского: по углу и дальности и настоящим опросом сенсора.
	var o_sensor: DetectionSensor = officer.sensor
	await _place_player(_vendor_stand(), 0.0)
	var window_seen := []
	for yaw in Layout.OFFICER_FACING:
		var to := _vendor_stand() - Layout.OFFICER_POST
		var forward := Vector2(-sin(yaw), -cos(yaw))
		var angle := rad_to_deg(absf(forward.angle_to(Vector2(to.x, to.z))))
		o_sensor.rotation.y = yaw
		var seen := o_sensor.poll()
		print("INFO: window from the officer post at yaw %.2f: %.1f°, %.1f m, seen %.0f" % [yaw, angle, Vector2(to.x, to.z).length(), seen])
		if seen > 0.0 or angle <= o_sensor.fov_deg * 0.5:
			window_seen.append(yaw)
	check(window_seen.is_empty(), "kiosk window is outside both officer cones (%.0f m, %.0f°) %s" % [o_sensor.range_m, o_sensor.fov_deg, window_seen])
	await drv.frames(30)

	# --- этап 3: учебный автобус на улице A ---
	m.interact(&"babka")
	m.accept()
	await _place_player(Vector3(16, 0, 32), -PI * 0.5)
	await drv.frames(20)
	check(not _cone_visible(o_sensor), "officer cone hidden while Ilyusha is far (%.0f m)" % o_sensor.distance_to_player())
	_reset_track()
	var walked: bool = await drv.walk_to(Vector3(44, 0, 32))
	var van_cone_seen := _cone_visible(van.sensor)
	check(walked, "stage 3: walked along street A past the van (%s)" % drv.last_error)
	check(_track_max > 0.15 and _track_max <= CityVan.TUTORIAL_CAP + 0.01 and _kiosk_detections == 0, "stage 3: on foot past the van the meter lights up (max %.2f ≤ cap %.2f), no fail" % [_track_max, CityVan.TUTORIAL_CAP])
	await _place_player(Layout.ACCOUNT_OFFICER + Vector3(1.5, 0, -0.5), PI * 0.5)
	await drv.frames(300)
	var hud := world.get_node("GameHUD")
	check(world.stealth.state == &"suspicious" and world.stealth.suspicion <= CityVan.TUTORIAL_CAP + 0.01 and world.stealth.suspicion >= CityVan.TUTORIAL_CAP - 0.05, "stage 3: 5 s next to the «военком» — meter holds at the cap (%.2f, %s)" % [world.stealth.suspicion, world.stealth.state])
	check(hud.suspicion_meter.is_showing() and _kiosk_detections == 0 and not world.is_stealth_failing(), "stage 3: indicator shown, no fail")
	check(van_cone_seen or _cone_visible(van.sensor), "stage 3: van cone shows on foot near the van")
	await _shot("k_stage3_van_cone")
	world.car.reset_to(Vector3(22, 0, 32), -PI * 0.5)
	await drv.frames(5)
	world.enter_car()
	await drv.frames(150)
	check(world.control_mode == &"in_car" and world.stealth.suspicion == 0.0 and van.sensor.poll() == 0.0, "stage 3: in the car next to the van — not seen, meter back to 0 (%.2f)" % world.stealth.suspicion)
	check(not _cone_visible(van.sensor), "stage 3: no cone while in the car")
	check(m.state == &"DRIVE_TO_KIOSK", "quest: in the car → DRIVE_TO_KIOSK (%s)" % m.state)

	# --- этап 4: парковка южнее павильона ---
	var park: Vector3 = Layout.ROUTE_DRIVE[-1]
	var d: Vector3 = park - Layout.ROUTE_DRIVE[-2]
	var park_yaw := atan2(-d.x, -d.z)
	world.car.reset_to(park, park_yaw)
	await drv.frames(10)
	check(m.state == &"BUY_BREAD", "car at the new parking → arrival, BUY_BREAD (%s)" % m.state)
	check(world.exit_car(), "E → out of the car at the parking")
	await drv.frames(30)
	var exit_spot: Vector3 = world.player.global_position
	print("INFO: exit spot at the kiosk parking %s, %.1f m to the window, %.1f m to the officer" % [exit_spot, _flat_d(exit_spot, Layout.VENDOR_WINDOW), _flat_d(exit_spot, Layout.OFFICER_POST)])
	check(_flat_d(exit_spot, Layout.VENDOR_WINDOW) > 20.0, "exit spot is > 20 m from the window")
	check(o_sensor.cone_wanted and _cone_visible(o_sensor), "officer cone shows when Ilyusha comes near (%.1f m < 25)" % o_sensor.distance_to_player())
	check(o_sensor.poll() == 0.0 and world.stealth.suspicion == 0.0, "exit spot is not seen by the officer")
	await _shot("k_parking_view")

	# «В лоб»: обойти машину спереди, дождаться, пока полицейский повернётся к парковке, и идти прямо к окну.
	check(await drv.walk_path([Layout.KIOSK_STAGING, Layout.SNEAK_EAST[0][1], DIRECT_FROM]), "walked round the car to the start of the straight line (%s)" % drv.last_error)
	check(o_sensor.poll() == 0.0, "start of the straight line is not seen")
	check(await drv.wait_officer_turn(1), "officer turned south, towards the parking (%s)" % drv.last_error)
	_reset_track()
	await _walk_path_until_fail([Vector3(DIRECT_FROM.x, 0, Layout.VENDOR_WINDOW.z + 4.0), _vendor_stand()], 480)
	check(_track_fail >= 0 and _track_fail <= 360, "straight at the officer facing the parking: detected within 6 s (%.1f s)" % (_track_fail / 60.0 if _track_fail >= 0 else -1.0))
	var respawned: int = await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(3)
	check(respawned >= 0 and _near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "respawned at the checkpoint (%s)" % world.player.global_position)
	check(absf(wrapf(world.camera_rig.yaw - PI, -PI, PI)) < 0.05 and absf(wrapf(Layout.STEALTH_CHECKPOINT_YAW - PI, -PI, PI)) < 0.01, "after the respawn the camera looks south, at the kiosk (yaw %.2f)" % world.camera_rig.yaw)
	check(not m.has_bread and m.state == &"BUY_BREAD", "fail before the purchase: no bread, BUY_BREAD kept")
	await _shot("k_respawn_view")

	# Честные пути: от места выхода, выждать разворот за укрытием.
	for route_name in ["east", "west"]:
		var route: Array = Layout.SNEAK_EAST if route_name == "east" else Layout.SNEAK_WEST
		await _place_player(exit_spot, 0.0)
		await drv.frames(260)   # защита после респавна прошла, шкала на нуле
		var before := _kiosk_detections
		_reset_track()
		var ok: bool = await drv.walk_path(route[0])
		var t_cover := _track_frames / 60.0
		ok = ok and await drv.wait_officer_turn(route[1])
		var t_wait := _track_frames / 60.0 - t_cover
		ok = ok and await drv.walk_path(route[2])
		var seconds := _track_frames / 60.0
		print("INFO: honest %s path parking → window %.1f s (to cover %.1f, wait %.1f, open part %.1f), max suspicion %.2f" % [route_name, seconds, t_cover, t_wait, seconds - t_cover - t_wait, _track_max])
		check(ok and _kiosk_detections == before and not world.is_stealth_failing(), "honest %s path: parking → window without a fail (%s)" % [route_name, drv.last_error])
		check(seconds >= 20.0 and seconds <= 90.0, "honest %s path takes 20…90 s (%.1f s)" % [route_name, seconds])
		check(_near2(world.player.global_position, _vendor_stand(), 0.6), "honest %s path ends at the window" % route_name)
		if route_name == "east":
			await _shot("k_east_path_window")
	# Тот же путь без ожидания — в неудобный угол: через гаражи, пока смотрит на запад, — провал.
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	_reset_track()
	var west_wrong := 1 - int(Layout.SNEAK_WEST[1])
	if await drv.walk_path(Layout.SNEAK_WEST[0]) and await drv.wait_officer_turn(west_wrong):
		await _walk_path_until_fail(Layout.SNEAK_WEST[2], 900)
	check(_track_fail >= 0, "west path while the officer looks west: detected (%.1f s)" % (_track_fail / 60.0 if _track_fail >= 0 else -1.0))
	await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(260)
	# Путь «за остановкой», пока смотрит на юг, — шкала растёт (индикатор), путь требует ожидания.
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	_reset_track()
	if await drv.walk_path(Layout.SNEAK_EAST[0]) and await drv.wait_officer_turn(1 - int(Layout.SNEAK_EAST[1])):
		await _walk_path_until_fail(Layout.SNEAK_EAST[2], 900)
	print("INFO: east path while the officer looks south: max suspicion %.2f, fail frame %d" % [_track_max, _track_fail])
	check(_track_max >= 0.4 or _track_fail >= 0, "east path while the officer looks south: seen (max %.2f)" % _track_max)
	if _track_fail >= 0:
		await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(260)
	# Обратно к окну честно (для покупки).
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	check(await drv.sneak(Layout.SNEAK_EAST[0], Layout.SNEAK_EAST[1], Layout.SNEAK_EAST[2]), "back at the window by the east path (%s)" % drv.last_error)

	# --- этап 7: покупка; «Лада» на пути автобуса ---
	var block_at := Vector3(73.5, 0, -20)
	world.car.reset_to(block_at, 0.0)
	await drv.frames(5)
	var lada_before: Vector3 = world.car.global_position
	var before_buy := _kiosk_detections
	await drv.interact()
	await drv.frames(5)
	for i in 8:
		if m.has_bread:
			break
		if not await _press_any(["КУПИТЬ ХЛЕБ", "ДАЛЬШЕ"]):
			break
	if not check(m.has_bread and m.state == &"RETURN_HOME", "bread bought at the window (%s)" % m.state):
		return
	_reset_track()
	var sensor_while_moving := false
	var cone_while_moving := false
	var moved := false
	for i in 600:
		await drv.frames(1)
		if officer.is_moving():
			moved = true
			sensor_while_moving = sensor_while_moving or o_sensor.enabled
			cone_while_moving = cone_while_moving or _cone_visible(o_sensor)
	check(moved and not sensor_while_moving and not cone_while_moving, "patrol walks to the new post with the sensor off and no cone")
	check(not officer.is_moving() and _near2(officer.global_position, Layout.OFFICER_POST_AFTER, 0.1) and o_sensor.enabled, "patrol at OFFICER_POST_AFTER, sensor on again (%s)" % officer.global_position)
	check(_track_max <= 0.3 and _kiosk_detections == before_buy, "10 s at the window after the purchase: suspicion ≤ 0.3 (max %.2f)" % _track_max)
	# Автобус догоняет «Ладу» на своей полосе и ждёт, не сдвигая её.
	var waited: int = await _wait_until(func(): return van.blocked_by == world.car, 2400)
	await drv.frames(180)
	var van_front: Vector3 = van.global_position - van.global_basis.z * CityVan.SIZE.z * 0.5
	check(waited >= 0 and van.is_driving(), "van stops behind the Lada on its path and waits (%s)" % van.global_position)
	check(world.car.global_position.distance_to(lada_before) <= 0.2, "van does not push the Lada (moved %.2f m)" % world.car.global_position.distance_to(lada_before))
	var gap := _flat_d(van_front, world.car.global_position) - Lada.SIZE.z * 0.5
	check(gap >= 1.0, "van keeps a gap to the Lada (%.1f m bumper to bumper)" % gap)
	world.car.reset_to(park, park_yaw)
	var arrived: int = await _wait_until(func(): return not van.is_driving(), 2400)
	await drv.frames(10)
	var stop: Vector3 = Layout.VAN_PATH[-1]
	check(arrived >= 0 and _near2(van.global_position, stop, 0.3), "van stops on the kiosk square at VAN_PATH end (%s)" % van.global_position)
	check(absf(wrapf(van.global_rotation.y - Layout.VAN_STOP_YAW, -PI, PI)) < 0.05 and absf(Layout.VAN_STOP_YAW) < 0.01, "van stands nose north, door east (yaw %.2f)" % van.global_rotation.y)
	check(van.sensor.enabled and is_equal_approx(van.sensor.range_m, CityVan.SENSOR_RANGE) and is_equal_approx(van.sensor.suspicion_cap, 1.0), "van door sensor on at the stop (14 m, full scale)")
	check(_van_clear(van), "van body at the stop overlaps no solid (pavilion, pole, kiosk)")
	check(world.car.global_position.distance_to(park) < 0.3, "Lada still at the parking")
	await _place_player(_vendor_stand(), PI)
	await drv.frames(30)
	await _shot("k_van_after_purchase")

	# Чекпоинт вне всех конусов (посты после покупки, автобус на площадке).
	await _place_player(Layout.STEALTH_CHECKPOINT, Layout.STEALTH_CHECKPOINT_YAW)
	var seen := []
	for s in get_nodes_in_group(&"detection_sensors"):
		if s.enabled and s.poll() > 0.0:
			seen.append("%s@%s" % [s.get_parent().name, s.global_position])
	check(seen.is_empty(), "checkpoint is outside every cone after the purchase (%s)" % [seen])

	# --- этап 8: обратно к машине между постом и автобусом ---
	await _place_player(_vendor_stand(), PI)
	await drv.frames(30)
	var before_back := _kiosk_detections
	_reset_track()
	var back_ok: bool = await drv.sneak(Layout.SNEAK_BACK[0], Layout.SNEAK_BACK[1], Layout.SNEAK_BACK[2])
	back_ok = back_ok and await drv.walk_to(_car_stand())
	print("INFO: honest way back window → car %.1f s, max suspicion %.2f" % [_track_frames / 60.0, _track_max])
	check(back_ok and _kiosk_detections == before_back, "honest way back to the car without a fail (%s)" % drv.last_error)
	await _shot("k_way_back")
	await drv.interact()
	await drv.frames(10)
	check(world.control_mode == &"in_car" and m.has_bread, "second entry into the car with the bread")
	drv.on_frame = Callable()

func _track() -> void:
	_track_frames += 1
	if world and is_instance_valid(world):
		_track_max = maxf(_track_max, world.stealth.suspicion)
		if _track_fail < 0 and world.is_stealth_failing():
			_track_fail = _track_frames

func _reset_track() -> void:
	_track_max = 0.0
	_track_frames = 0
	_track_fail = -1

## Идти к точке, пока не начнётся экран провала (или не дойдёт / не кончатся кадры).
func _walk_until_fail(target: Vector3, max_frames: int) -> void:
	for i in max_frames:
		if world.is_stealth_failing():
			break
		var to := target - world.player.global_position
		to.y = 0.0
		if to.length() < 0.4:
			break
		drv._walk_axes(to.normalized())
		await drv.frames(1)
	drv.release_all()

func _walk_path_until_fail(points: Array, max_frames: int) -> void:
	for p in points:
		if world.is_stealth_failing() or max_frames <= 0:
			break
		var start := _track_frames
		await _walk_until_fail(p, max_frames)
		max_frames -= _track_frames - start

func _cone_visible(s: DetectionSensor) -> bool:
	var cone := s.get_node_or_null("VisionCone")
	return cone != null and (cone as Node3D).visible

func _van_clear(van: Node3D) -> bool:
	var box := BoxShape3D.new()
	box.size = CityVan.SIZE - Vector3(0.05, 0.4, 0.05)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	query.exclude = [van.get_rid()]
	query.transform = Transform3D(van.global_basis, van.global_position + Vector3.UP * (CityVan.SIZE.y * 0.5 + 0.1))
	var hits := world.get_world_3d().direct_space_state.intersect_shape(query, 4)
	for h in hits:
		print("INFO: van overlaps ", h["collider"].name)
	return hits.is_empty()

func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

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

extends SceneTree
## EXT-02 B (docs/extension/HIDE_SPOTS.md, разделы 5, 9, 13 B): ядро укрытий без самих укрытий на настоящей сцене main.tscn.
## Ilyusha.hide_mode / set_hide_mode / force_hide_mode / speed_limit / is_still / exposure_factor / hide_visual;
## DetectionSensor.visibility() = геометрия × exposure (0…1), in_view; StealthDirector — рост × видимость,
## время до обнаружения при 1,0 и 0,75 на 30 и 60 физ. к/с; запреты переходов (машина, диалог, провал, ui_blocking,
## укрытие → укрытие); отказ машины и диалога в режиме + hide_hint в HUD; сброс режима при респавне; прыжок в режиме;
## 20 входов/выходов без утечки узлов и с возвратом WALK_SPEED. Приёмка с правками: E у квестовой зоны в укрытии
## снимает укрытие и показывает отказ, следующий E — действие (P2-2); луч сенсора: «Лада» укрывает, житель и собака
## (тоже слой Car) — нет (P3-1).
## Тестовый DetectionSensor ставится в мир; чужие сенсоры (наблюдатели EXT-01) на время прогона выключены.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/hide_core_test.gd

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const SensorScript = preload("res://game/stealth/detection_sensor.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")

const SPOT_SOURCE := "extends Interactable\nvar resets := 0\nfunc reset() -> void:\n\tresets += 1\n"

var failures: Array[String] = []
var checks := 0
var main: Node
var drv
var world: DemoWorld
var player: Ilyusha
var sensor: DetectionSensor
## Открытая площадка двора (как в stealth_test) и путь на 5 м к северу от неё.
var yard := Vector3.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(600.0, true, false, true).timeout.connect(func():
		push_error("FAIL: hide core test exceeded 600 simulated seconds")
		_finish(2))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	world = main.world
	if not check(world != null and world.player != null, "world and Ilyusha are up"):
		_finish()
		return
	player = world.player
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	sensor = SensorScript.new()
	sensor.name = "HideTestSensor"
	sensor.enabled = false
	world.add_child(sensor)
	yard = Layout.SPAWN + Vector3(10.0, 0.0, -12.0)
	var path_free := true
	for k in 7:
		path_free = path_free and _free(yard + Vector3(0, 0, -k)) and _free(yard + Vector3(0, 0, 3.0))
	check(path_free, "yard strip %s … 6 m north is free" % yard)
	await _part_api()
	await _part_speed()
	await _part_exposure()
	await _part_sensor()
	await _part_sight_blockers()
	await _part_detection_time(60)
	await _part_detection_time(30)
	Engine.physics_ticks_per_second = 60
	await _part_prohibitions()
	await _part_refusals()
	await _part_respawn_reset()
	await _part_jump()
	await _part_toggles()
	drv.release_all()
	_finish()

# =====================================================================================
# 1. API и значения по умолчанию
# =====================================================================================

func _part_api() -> void:
	print("--- api ---")
	check(player.hide_mode == &"none", "default hide_mode is &\"none\"")
	check(is_equal_approx(player.speed_limit(), Ilyusha.WALK_SPEED), "speed_limit() = WALK_SPEED in none (%.2f)" % player.speed_limit())
	check(player.hide_visual != null and player.hide_visual.get_parent() == player.visual, "hide_visual is a child of visual")
	check(player.hide_visual.get_child_count() == 0, "hide_visual is empty at start")
	check(is_equal_approx(HideTuning.HIDE_SPEED_BOX, 1.2) and is_equal_approx(HideTuning.HIDE_SPEED_BARREL, 2.6), "tuning: box 1.2 m/s, barrel 2.6 m/s")
	check(not player.set_hide_mode(&"bogus") and player.hide_mode == &"none", "unknown mode is refused")
	var hud: Dictionary = world.get_hud_state()
	check(hud.get("hide_mode", &"?") == &"none" and hud.get("hide_hint", "?") == "", "get_hud_state(): hide_mode none, hide_hint empty")

# =====================================================================================
# 2. Предел скорости: фактическая скорость ходьбы в каждом режиме
# =====================================================================================

func _part_speed() -> void:
	print("--- speed ---")
	for mode in [&"none", &"box", &"barrel", &"snowdrift"]:
		await _place(yard, 0.0)
		check(player.set_hide_mode(mode), "set_hide_mode(%s) on foot → true" % mode)
		var start := player.global_position
		var top := await _hold_forward(40)
		var expect: float = {&"none": Ilyusha.WALK_SPEED, &"box": 1.2, &"barrel": 2.6, &"snowdrift": 0.0}[mode]
		check(is_equal_approx(player.speed_limit(), expect), "%s: speed_limit() = %.1f (%.2f)" % [mode, expect, player.speed_limit()])
		check(top <= expect + 0.02 and top >= expect - 0.1, "%s: top walking speed ≈ %.1f m/s (%.2f)" % [mode, expect, top])
		if mode == &"snowdrift":
			check(_flat(player.global_position, start) < 0.01, "snowdrift: no movement with input held (%.3f m)" % _flat(player.global_position, start))
		drv.release_all()
		await drv.frames(20)
		check(player.set_hide_mode(&"none"), "%s → none" % mode)

# =====================================================================================
# 3. exposure_factor: таблица 5.3 — стоя вдали, стоя вплотную, в движении
# =====================================================================================

func _part_exposure() -> void:
	print("--- exposure table ---")
	# [режим, стоя вдали, стоя ≤ 1,5 м, в движении вдали, в движении вплотную]
	var table := [
		[&"none", 1.0, 1.0, 1.0, 1.0],
		[&"box", 0.0, 0.5, 0.75, 0.75],
		[&"snowdrift", 0.0, 0.0, 0.0, 0.0],
		[&"barrel", 0.0, 0.5, 1.0, 1.0],
	]
	for row in table:
		var mode: StringName = row[0]
		await _place(yard, 0.0)
		player.set_hide_mode(mode)
		await drv.frames(5)
		var p := player.global_position
		var far := p + Vector3(0, 1.5, 5.0)
		var near := p + Vector3(0, 1.5, 1.2)
		check(player.is_still(), "%s: standing → is_still()" % mode)
		check(is_equal_approx(player.exposure_factor(far), row[1]), "%s standing far: %.2f (%.2f)" % [mode, row[1], player.exposure_factor(far)])
		check(is_equal_approx(player.exposure_factor(near), row[2]), "%s standing ≤ 1.5 m: %.2f (%.2f)" % [mode, row[2], player.exposure_factor(near)])
		Input.action_press(&"move_forward")
		await drv.frames(12)
		p = player.global_position
		far = p + Vector3(0, 1.5, 5.0)
		near = p + Vector3(0, 1.5, 1.2)
		check(mode == &"snowdrift" or not player.is_still(), "%s: walking → not still (%.2f m/s)" % [mode, Vector2(player.velocity.x, player.velocity.z).length()])
		check(is_equal_approx(player.exposure_factor(far), row[3]), "%s moving far: %.2f (%.2f)" % [mode, row[3], player.exposure_factor(far)])
		check(is_equal_approx(player.exposure_factor(near), row[4]), "%s moving ≤ 1.5 m: %.2f (%.2f)" % [mode, row[4], player.exposure_factor(near)])
		drv.release_all()
		await drv.frames(20)
		player.set_hide_mode(&"none")
	# Граница «вплотную»: 1,5 м — ещё вплотную, 1,6 м — уже нет.
	await _place(yard, 0.0)
	player.set_hide_mode(&"box")
	await drv.frames(3)
	var q := player.global_position
	check(is_equal_approx(player.exposure_factor(q + Vector3(0, 1.5, 1.5)), 0.5), "box standing exactly 1.5 m → 0.5")
	check(is_equal_approx(player.exposure_factor(q + Vector3(0, 1.5, 1.6)), 0.0), "box standing 1.6 m → 0.0")
	player.set_hide_mode(&"none")

# =====================================================================================
# 4. DetectionSensor: видимость 0…1 с множителем, in_view — геометрия
# =====================================================================================

func _part_sensor() -> void:
	print("--- sensor ---")
	sensor.range_m = 30.0
	sensor.fov_deg = 90.0
	sensor.enabled = true
	await _place(yard, 0.0)
	_aim(yard + Vector3(0, 0, 5.0), yard)
	check(sensor.poll() == 1.0 and sensor.in_view, "none, 5 m in view → 1.0")
	player.set_hide_mode(&"box")
	await drv.frames(3)
	var v := sensor.poll()
	check(v == 0.0 and sensor.in_view and sensor.last_blocker == "", "box standing, 5 m → 0.0 but in_view (%.2f)" % v)
	_aim(yard + Vector3(0, 0, 1.2), yard)
	check(is_equal_approx(sensor.poll(), 0.5), "box standing, 1.2 m → 0.5 (%.2f)" % sensor.visibility())
	_aim(yard + Vector3(0, 0, 5.0), yard)
	Input.action_press(&"move_forward")
	await drv.frames(10)
	_aim(player.global_position + Vector3(0, 0, 5.0), player.global_position)
	check(is_equal_approx(sensor.poll(), 0.75), "box walking, 5 m → 0.75 (%.2f)" % sensor.visibility())
	drv.release_all()
	await drv.frames(20)
	player.set_hide_mode(&"none")
	player.set_hide_mode(&"barrel")
	await _place(yard, 0.0)
	_aim(yard + Vector3(0, 0, 1.0), yard)
	check(is_equal_approx(sensor.poll(), 0.5), "barrel standing, 1.0 m → 0.5")
	_aim(yard + Vector3(0, 0, 5.0), yard)
	check(sensor.poll() == 0.0, "barrel standing, 5 m → 0.0")
	Input.action_press(&"move_forward")
	await drv.frames(10)
	_aim(player.global_position + Vector3(0, 0, 5.0), player.global_position)
	check(sensor.poll() == 1.0, "barrel rolling, 5 m → 1.0")
	drv.release_all()
	await drv.frames(20)
	player.set_hide_mode(&"none")
	player.set_hide_mode(&"snowdrift")
	await _place(yard, 0.0)
	_aim(yard + Vector3(0, 0, 1.0), yard)
	check(sensor.poll() == 0.0 and sensor.in_view, "snowdrift, 1.0 m, ray clear → 0.0")
	player.set_hide_mode(&"none")
	# Стена перекрывает при любом режиме: дом H8_East между сенсором и Илюшей.
	var h8 := _solid("H8_East")
	var p := Vector3(h8[0].x - h8[1].x * 0.5 - 3.0, 0, -80.0)
	await _place(p, 0.0)
	_aim(Vector3(h8[0].x + h8[1].x * 0.5 + 3.0, 0, -80.0), p)
	check(sensor.poll() == 0.0 and not sensor.in_view and sensor.last_blocker != "", "wall covers → 0, not in_view (blocker '%s')" % sensor.last_blocker)
	# Шкала: рост пропорционален видимости (0,5 → вдвое медленнее).
	await _place(yard, 0.0)
	player.set_hide_mode(&"box")
	_aim(yard + Vector3(0, 0, 1.0), yard)
	await drv.frames(60)
	var s: float = world.stealth.suspicion
	# EXT-01 fix6: 1 м — внутри радиуса близости 3 м (DetectionSensor.NEAR_RADIUS): рост ×3 → 1 с × 0,5 × 3 / 2 ≈ 0,75.
	check(s > 0.6 and s < 0.85 and world.stealth.snap().get("near_rise_factor", -1.0) == 3.0, "box standing 1 m (0.5, proximity ×3): 1 s → suspicion ≈ 0.75 (%.2f)" % s)
	check(world.stealth.snap().get("visibility", -1.0) == 0.5, "StealthDirector snap visibility = 0.5")
	sensor.enabled = false
	player.set_hide_mode(&"none")
	await _wait_clear()

# =====================================================================================
# 4а. Луч: «Лада» (слой Car) укрывает, житель и собака (тоже Car) — нет (приёмка P3-1)
# =====================================================================================

func _part_sight_blockers() -> void:
	print("--- sight blockers: Lada yes, resident and dog no ---")
	# Свой сенсор под отдельным узлом: тестовый HideTestSensor — сосед «Лады» (оба дети DemoWorld), а сенсор
	# исключает из луча тела соседей (своё тело наблюдателя).
	var main_sensor := sensor
	main_sensor.enabled = false
	var holder := Node3D.new()
	holder.name = "SightTestHolder"
	world.add_child(holder)
	sensor = SensorScript.new()
	sensor.name = "SightTestSensor"
	sensor.enabled = false
	holder.add_child(sensor)
	sensor.range_m = 30.0
	sensor.fov_deg = 90.0
	var car: Node3D = world.car
	var car_pos := car.global_position
	var car_yaw := car.global_rotation.y
	var c := yard + Vector3(0, 0, -3.0)
	car.reset_to(c, PI * 0.5)   # бортом к лучу: 4,1 м вдоль x
	await drv.frames(10)
	var behind := c + Vector3(0, 0, -2.0)
	await _place(behind, 0.0)
	_aim(c + Vector3(0, 0, 6.0), behind)
	sensor.enabled = true
	var v := sensor.poll()
	check(v == 0.0 and not sensor.in_view and sensor.last_blocker == String(car.name), "Ilyusha behind the Lada → 0, blocker '%s' (%.2f, '%s')" % [car.name, v, sensor.last_blocker])
	car.reset_to(car_pos, car_yaw)
	await drv.frames(10)
	check(sensor.poll() == 1.0 and sensor.in_view, "Lada back at its place → seen again")
	# Житель (тело AnimatableBody3D на слое Car) между сенсором и Илюшей.
	var resident: Node3D = world.get_node("LevelGeometry/Residents").residents[0]
	var resident_saved := resident.global_transform
	resident.set_physics_process(false)
	await _place(yard, 0.0)
	_aim(yard + Vector3(0, 0, 5.0), yard)
	resident.global_position = yard + Vector3(0, 0, 2.5)
	await drv.frames(3)
	var space := world.get_world_3d().direct_space_state
	var eye := sensor.global_position + Vector3.UP * DetectionSensor.EYE_HEIGHT
	var tgt := player.global_position + Vector3.UP * DetectionSensor.TARGET_HEIGHT
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, tgt, 4))
	check(not hit.is_empty() and (hit["collider"] as Node).get_parent() == resident, "resident body is on the line of sight (%s)" % [hit.get("collider")])
	v = sensor.poll()
	check(v == 1.0 and sensor.in_view and sensor.last_blocker == "", "resident between the sensor and Ilyusha → visibility 1 (%.2f, '%s')" % [v, sensor.last_blocker])
	resident.global_transform = resident_saved
	resident.set_physics_process(true)
	# Собака (Ambient.dog_body, слой Car): глаза сенсора ниже (0,3 м), чтобы луч шёл через её тело 0,7 м.
	var ambient := world.get_node("LevelGeometry/Ambient")
	ambient.set_physics_process(false)
	ambient.set_process(false)
	var dog: Node3D = ambient.dog_body.get_parent()
	var dog_saved := dog.global_transform
	dog.global_position = yard + Vector3(0, 0, 2.5)
	sensor.global_position.y = -1.2
	await drv.frames(3)
	eye = sensor.global_position + Vector3.UP * DetectionSensor.EYE_HEIGHT
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, tgt, 4))
	check(not hit.is_empty() and hit["collider"] == ambient.dog_body, "dog body is on the (low) line of sight (%s)" % [hit.get("collider")])
	v = sensor.poll()
	check(v == 1.0 and sensor.in_view, "dog between the sensor and Ilyusha → visibility 1 (%.2f, '%s')" % [v, sensor.last_blocker])
	dog.global_transform = dog_saved
	ambient.set_physics_process(true)
	ambient.set_process(true)
	sensor.enabled = false
	holder.queue_free()
	sensor = main_sensor
	await _wait_clear()

# =====================================================================================
# 5. Время до обнаружения: 1,0 → 2,0 с; коробка на ходу 0,75 → 2,67 с (30 и 60 физ. к/с)
# =====================================================================================

func _part_detection_time(ticks: int) -> void:
	print("--- detection time @ %d ticks ---" % ticks)
	Engine.physics_ticks_per_second = ticks
	await drv.frames(5)
	for exposure in [1.0, 0.75]:
		await _place(yard, 0.0)
		sensor.range_m = 30.0
		sensor.fov_deg = 90.0
		_aim(yard + Vector3(0, 0, 4.5), yard)   # fix6: вне радиуса близости 3 м (там рост ×3)
		if exposure < 1.0:
			player.set_hide_mode(&"box")
			Input.action_press(&"move_forward")
			await drv.frames(3)
		sensor.enabled = true
		var frames := 0
		var seen_mid := -1.0
		while not world.is_stealth_failing() and frames < ticks * 6:
			await drv.frames(1)
			frames += 1
			if frames == ticks:
				seen_mid = sensor.visibility()
		var t := float(frames) / ticks
		var expect: float = 2.0 / exposure
		check(is_equal_approx(seen_mid, exposure), "@%d: visibility %.2f while %s (%.2f)" % [ticks, exposure, "walking in the box" if exposure < 1.0 else "standing", seen_mid])
		check(t >= expect - 0.05 and t <= expect + 0.35, "@%d: exposure %.2f → detected in %.2f s (expected ≈ %.2f)" % [ticks, exposure, t, expect])
		drv.release_all()
		# Во время экрана провала режим не меняется.
		if world.is_stealth_failing():
			var before := player.hide_mode
			check(not player.set_hide_mode(&"barrel" if before == &"none" else &"none") and player.hide_mode == before, "@%d: set_hide_mode refused during the fail screen" % ticks)
		sensor.enabled = false
		var wait := 0
		while world.is_stealth_failing() and wait < ticks * 4:
			await drv.frames(1)
			wait += 1
		await drv.frames(2)
		check(player.hide_mode == &"none", "@%d: after respawn hide_mode is none (%s)" % [ticks, player.hide_mode])
		await _wait_clear()

# =====================================================================================
# 6. Запреты переходов: машина, диалог, ui_blocking, укрытие → укрытие
# =====================================================================================

func _part_prohibitions() -> void:
	print("--- prohibitions ---")
	await _place(_car_stand(), 0.0)
	world.enter_car()
	await drv.frames(5)
	if check(world.control_mode == &"in_car", "entered the car (none mode)"):
		check(not player.set_hide_mode(&"box") and player.hide_mode == &"none", "in the car: set_hide_mode(box) → false")
		check(world.exit_car(), "exit the car")
		await drv.frames(5)
	await _place(_babka_stand(), 0.0)
	await drv.interact()
	await drv.frames(5)
	if check(world.quest_flow.is_dialog_open(), "E at Babka opens a dialog (none mode)"):
		check(not player.set_hide_mode(&"box") and player.hide_mode == &"none", "dialog open: set_hide_mode(box) → false")
		check(await drv.press_button(QuestLines.BUTTON_DECLINE), "dialog closed by ОТКАЗАТЬСЯ (%s)" % drv.last_error)
		await drv.frames(5)
		check(not world.quest_flow.is_dialog_open(), "dialog is closed")
	world.ui_blocking = true
	check(not player.set_hide_mode(&"box") and player.hide_mode == &"none", "ui_blocking: set_hide_mode(box) → false")
	world.ui_blocking = false
	check(player.set_hide_mode(&"box"), "on foot, free: none → box")
	check(not player.set_hide_mode(&"barrel") and player.hide_mode == &"box", "box → barrel directly is refused")
	check(player.set_hide_mode(&"box"), "box → box is a no-op true")
	player.force_hide_mode(&"barrel")
	check(player.hide_mode == &"barrel", "force_hide_mode bypasses the rules")
	check(player.set_hide_mode(&"none"), "barrel → none")

# =====================================================================================
# 7. В режиме: машина и диалог отказывают, hide_hint в HUD
# =====================================================================================

func _part_refusals() -> void:
	print("--- refusals ---")
	var hud := world.get_node("GameHUD")
	for row in [[&"box", HideTuning.HINT_BOX], [&"barrel", HideTuning.HINT_BARREL], [&"snowdrift", HideTuning.HINT_SNOWDRIFT]]:
		var mode: StringName = row[0]
		var hint: String = row[1]
		# «Лада»: E у двери — подсказка, не посадка.
		await _place(_car_stand(), 0.0)
		player.set_hide_mode(mode)
		await drv.frames(3)
		check(world.get_hud_state()["prompt"] == hint, "%s at the Lada door: prompt «%s» (%s)" % [mode, hint, world.get_hud_state()["prompt"]])
		await drv.interact()
		await drv.frames(3)
		check(world.control_mode == &"on_foot", "%s: E at the Lada → still on foot" % mode)
		check(world.get_hud_state()["hide_hint"] == hint, "%s: hide_hint «%s» after E at the Lada" % [mode, hint])
		check(hud.prompt_label.text == hint and hud.prompt_label.is_visible_in_tree(), "%s: HUD prompt line shows «%s» (%s)" % [mode, hint, hud.prompt_label.text])
		check(player.hide_mode == &"none", "%s: E at the Lada took the hide off (P2-2)" % mode)
		await drv.interact()
		await drv.frames(5)
		check(world.control_mode == &"in_car", "%s: next E at the Lada → boards" % mode)
		world.exit_car()
		await drv.frames(5)
		await _place(_car_stand(), 0.0)
		player.set_hide_mode(mode)
		world.enter_car()
		check(world.control_mode == &"on_foot" and player.hide_mode == &"none", "%s: enter_car() refused, hide off" % mode)
		# Бабка: E — подсказка, диалог не открывается, миссия не меняется.
		await drv.frames(int(HideTuning.HINT_SECONDS * 60) + 5)
		check(world.get_hud_state()["hide_hint"] == "", "%s: hide_hint clears after %.0f s" % [mode, HideTuning.HINT_SECONDS])
		await _place(_babka_stand(), 0.0)
		player.set_hide_mode(mode)
		await drv.frames(3)
		var state_before: StringName = world.mission.state
		await drv.interact()
		await drv.frames(5)
		check(not world.quest_flow.is_dialog_open() and world.mission.state == state_before, "%s: E at Babka opens no dialog (state %s)" % [mode, world.mission.state])
		check(world.get_hud_state()["hide_hint"] == hint, "%s: hide_hint «%s» after E at Babka" % [mode, hint])
		check(player.hide_mode == &"none", "%s: E at Babka took the hide off" % mode)
		player.set_hide_mode(mode)
		world.quest_flow._on_interacted(player, &"vendor")
		check(not world.quest_flow.is_dialog_open() and player.hide_mode == &"none", "%s: vendor dialog refused, hide off" % mode)
		check(player.set_hide_mode(&"none"), "%s → none" % mode)
		await drv.frames(3)
		check(world.get_hud_state()["prompt"] != hint, "%s: none → Babka prompt back to normal (%s)" % [mode, world.get_hud_state()["prompt"]])
	await drv.frames(int(HideTuning.HINT_SECONDS * 60) + 5)

# =====================================================================================
# 8. Сброс при респавне: режим none, облик убран, укрытия reset(), E без зон — укрытию
# =====================================================================================

func _part_respawn_reset() -> void:
	print("--- respawn reset ---")
	var script := GDScript.new()
	script.source_code = SPOT_SOURCE
	script.reload()
	var spot: Interactable = script.new()
	spot.name = "FakeHideSpot"
	spot.interaction_id = &"bread_box"
	spot.prompt = HideTuning.PROMPT_BOX_EXIT
	spot.add_to_group(&"hide_spots")
	world.add_child(spot)
	spot.global_position = Layout.SPAWN + Vector3(0, -50, 0)   # далеко: перекрытия зоны нет
	await _place(yard, 0.0)
	check(player.set_hide_mode(&"box", spot), "set_hide_mode(box, spot)")
	var look: Node3D = player.get_node("Visual/Look")
	check(not look.visible, "box: Ilyusha's sprite hidden")
	check(player.visible and not player.get_node("CollisionShape3D").disabled, "box: body and collision stay")
	var shell := MeshInstance3D.new()
	shell.mesh = BoxMesh.new()
	player.hide_visual.add_child(shell)
	await drv.frames(3)
	check(player.current_interactable() == spot, "box, no zones nearby: current_interactable() is the hide owner")
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_BOX_EXIT, "prompt shows the hide spot's own text (%s)" % world.get_hud_state()["prompt"])
	var bread: bool = world.mission.has_bread
	var mstate: StringName = world.mission.state
	check(world.respawn_at_checkpoint(), "respawn_at_checkpoint() on foot")
	await drv.frames(3)
	check(player.hide_mode == &"none", "respawn → hide_mode none")
	check(player.hide_visual.get_child_count() == 0 and not is_instance_valid(shell), "respawn → hide_visual emptied")
	check(look.visible, "respawn → sprite visible")
	check(spot.resets == 1, "respawn → hide spot reset() called once (%d)" % spot.resets)
	check(is_equal_approx(player.speed_limit(), Ilyusha.WALK_SPEED), "respawn → WALK_SPEED")
	check(world.mission.has_bread == bread and world.mission.state == mstate, "respawn → mission untouched")
	player.set_hide_mode(&"barrel", spot)
	world.reset_car()
	await drv.frames(3)
	check(player.hide_mode == &"none" and spot.resets == 2, "reset_car() → hide_mode none, reset() called (%d)" % spot.resets)
	world.remove_child(spot)
	spot.free()

# =====================================================================================
# 9. Прыжок запрещён в режиме
# =====================================================================================

func _part_jump() -> void:
	print("--- jump ---")
	await _place(yard, 0.0)
	await drv.frames(5)
	var top := await _jump_height()
	check(top > 0.8, "none: jump lifts Ilyusha (%.2f m)" % top)
	await drv.frames(60)
	for mode in [&"box", &"snowdrift", &"barrel"]:
		player.set_hide_mode(mode)
		await drv.frames(3)
		top = await _jump_height()
		check(top < 0.05, "%s: jump does nothing (%.2f m)" % [mode, top])
		player.set_hide_mode(&"none")
		await drv.frames(3)

# =====================================================================================
# 10. 20 входов и выходов: без утечки узлов, WALK_SPEED и облик вернулись
# =====================================================================================

func _part_toggles() -> void:
	print("--- 20 toggles ---")
	await _place(yard, 0.0)
	await drv.frames(5)
	var nodes_before := player.find_children("*", "", true, false).size()
	var all_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var modes := [&"box", &"snowdrift", &"barrel"]
	var ok := true
	var shells: Array[int] = []
	for i in 20:
		var mode: StringName = modes[i % modes.size()]
		ok = player.set_hide_mode(mode) and ok
		var shell := MeshInstance3D.new()
		shell.mesh = BoxMesh.new()
		player.hide_visual.add_child(shell)
		shells.append(shell.get_instance_id())
		await drv.frames(2)
		ok = player.set_hide_mode(&"none") and ok
		await drv.frames(2)
	await drv.frames(5)
	var nodes_after := player.find_children("*", "", true, false).size()
	var alive := shells.filter(func(id): return is_instance_id_valid(id)).size()
	print("INFO: scene node count %d → %d (traffic and residents also spawn)" % [all_before, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	check(ok, "20 enter/exit cycles all accepted")
	check(nodes_after == nodes_before, "no node leak under Ilyusha (%d → %d)" % [nodes_before, nodes_after])
	check(alive == 0, "all 20 hide visuals freed (%d alive)" % alive)
	check(player.hide_visual.get_child_count() == 0 and player.get_node("Visual/Look").visible, "hide_visual empty, sprite visible")
	check(is_equal_approx(player.speed_limit(), Ilyusha.WALK_SPEED), "speed_limit() back to WALK_SPEED")
	var top := await _hold_forward(40)
	check(absf(top - Ilyusha.WALK_SPEED) < 0.05, "walking speed back to %.1f m/s (%.2f)" % [Ilyusha.WALK_SPEED, top])
	drv.release_all()
	await drv.frames(20)

# =====================================================================================
# Помощники
# =====================================================================================

func _place(p: Vector3, yaw: float) -> void:
	drv.release_all()
	player.place(p, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await drv.frames(3)

## Держать «вперёд» frames кадров; максимальная горизонтальная скорость.
func _hold_forward(count: int) -> float:
	Input.action_press(&"move_forward")
	var top := 0.0
	for i in count:
		await drv.frames(1)
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
	drv.release_all()
	return top

## Нажать прыжок; максимальный подъём над стартом за 40 кадров.
func _jump_height() -> float:
	var y0 := player.global_position.y
	var top := 0.0
	var down := InputEventAction.new()
	down.action = &"jump"
	down.pressed = true
	Input.parse_input_event(down)
	for i in 40:
		await drv.frames(1)
		if i == 2:
			var up := InputEventAction.new()
			up.action = &"jump"
			up.pressed = false
			Input.parse_input_event(up)
		top = maxf(top, player.global_position.y - y0)
	return top

## Дождаться: шкала 0, защита после респавна кончилась.
func _wait_clear() -> void:
	for i in 900:
		if world.stealth.suspicion == 0.0 and world.stealth.protection_left() == 0.0 and not world.is_stealth_failing():
			return
		await drv.frames(1)

func _aim(at: Vector3, look_at: Vector3) -> void:
	sensor.global_position = Vector3(at.x, 0.0, at.z)
	var d := look_at - at
	sensor.rotation.y = atan2(-d.x, -d.z)

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _solid(name: String) -> Array:
	for s in Layout.all_solids():
		if s[0] == name:
			return [s[2], s[3]]
	push_error("no solid " + name)
	return [Vector2.ZERO, Vector3.ZERO]

func _free(p: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.8)
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _babka_stand() -> Vector3:
	return Layout.BABKA + Vector3(0.6, 0.0, -2.0)

func _car_stand() -> Vector3:
	var p: Vector3 = world.car.global_transform * Vector3(-2.2, 0, 0)
	p.y = 0.0
	return p

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
	Engine.physics_ticks_per_second = 60
	print("HIDE_CORE: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

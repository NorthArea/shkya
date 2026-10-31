extends SceneTree
## EXT-02 D (docs/extension/HIDE_SPOTS.md, разделы 5.1, 7, 11, 14 D): сугроб-укрытие у киоска на настоящей сцене main.tscn.
## Облик и коллизия (World, на месте после выхода и сброса); вход/выход по E; внутри движения нет; exposure 0 и шкала
## спадает, а не обнуляется; сугроб перекрывает луч сенсора для Илюши за ним (тестовый сенсор и сенсор полицейского);
## выход в занятую точку — «ВЫХОД ЗАНЯТ», Илюша внутри; провал, «Сбросить автомобиль», принудительный сброс при
## занятом выходе, перезапуск мира — Илюша снаружи, видим, управляем; гэг C04 — раз за попытку, только когда
## полицейский смотрит на сугроб; тост при выходе 2,5 с; 20 входов-выходов без утечки; запрещённых слов нет.
## Чужие сенсоры (наблюдатели EXT-01) на время прогона выключены (кроме проверки луча полицейского).
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/hide_snow_test.gd
## Кадры:    tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/hide_snow_test.gd -- --capture
##   → builds/screenshots/EXT-02/d/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const SensorScript = preload("res://game/stealth/detection_sensor.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")
const OUT := "res://builds/screenshots/EXT-02/d"

var failures: Array[String] = []
var checks := 0
var _finishing := false
var capture := false
var main: Node
var drv
var world: DemoWorld
var player: Ilyusha
var spot: Node3D
var sensor: DetectionSensor
var center := Layout.HIDE_SNOWDRIFT

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: hide snow test exceeded 900 simulated seconds")
		_finish(2))
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	if not _bind():
		_finish()
		return
	await _part_geometry()
	await _part_enter_exit()
	await _part_decay()
	await _part_occlusion()
	await _part_exit_blocked()
	await _part_fail_and_resets()
	await _part_gag()
	await _part_toggles()
	await _part_texts()
	await _part_restart()
	drv.release_all()
	_finish()

func _bind() -> bool:
	world = main.world
	if not check(world != null and world.player != null, "world and Ilyusha are up"):
		return false
	player = world.player
	spot = world.get_node_or_null("LevelGeometry/HideSpots/Snowdrift")
	if not check(spot != null and spot.get("mode") == &"snowdrift", "LevelGeometry/HideSpots/Snowdrift exists, mode snowdrift"):
		return false
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	sensor = SensorScript.new()
	sensor.name = "SnowTestSensor"
	sensor.enabled = false
	world.add_child(sensor)
	return true

# =====================================================================================
# 1. Облик, коллизия, зона, точки
# =====================================================================================

func _part_geometry() -> void:
	print("--- geometry ---")
	var body: StaticBody3D = spot.drift
	check(body != null and body.collision_layer == 1, "drift body on layer World (1)")
	var shape: BoxShape3D = (body.get_child(0) as CollisionShape3D).shape
	check(shape.size.is_equal_approx(Vector3(2.4, 1.4, 1.6)), "drift collision 2.4 × 1.4 × 1.6 m (%s)" % shape.size)
	check(_flat(spot.global_position, center) < 0.01, "drift at Layout.HIDE_SNOWDRIFT %s" % center)
	check(spot.radius == 2.5 and spot.prompt == HideTuning.PROMPT_SNOWDRIFT_ENTER, "E zone radius 2.5, prompt «%s»" % spot.prompt)
	check(spot.is_in_group(&"hide_spots"), "drift is in group hide_spots")
	check(_inside_box(Layout.HIDE_SNOWDRIFT_ANCHOR), "anchor is inside the drift box")
	check(not _inside_box(Layout.HIDE_SNOWDRIFT_EXIT) and spot._exit_free(Layout.HIDE_SNOWDRIFT_EXIT), "exit point is outside the drift and free")
	# Честные пути SNEAK_* — не ближе 1,5 м к коробке сугроба.
	var nearest := INF
	for sneak in [Layout.SNEAK_EAST, Layout.SNEAK_WEST, Layout.SNEAK_BACK, Layout.SNEAK_AGAIN]:
		var points: Array = sneak[0] + sneak[2]
		for i in range(1, points.size()):
			nearest = minf(nearest, _segment_to_box(points[i - 1], points[i]))
	check(nearest >= 1.5, "honest paths SNEAK_* ≥ 1.5 m from the drift box (%.2f m)" % nearest)
	# Выход и конус полицейского: при каком угле OFFICER_FACING точка выхода видна с поста (луч, дальность, угол).
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, 0.0)
	sensor.range_m = 12.0
	sensor.fov_deg = 80.0
	sensor.enabled = true
	var seen := []
	for post in [Layout.OFFICER_POST, Layout.OFFICER_POST_AFTER]:
		for facing in Layout.OFFICER_FACING:
			sensor.global_position = post
			sensor.rotation.y = facing
			seen.append(sensor.poll() > 0.0)
	sensor.enabled = false
	var n_f := Layout.OFFICER_FACING.size()
	print("INFO: exit point seen from OFFICER_POST by facing: %s, from OFFICER_POST_AFTER: %s" % [seen.slice(0, n_f), seen.slice(n_f)])
	check(not seen[0] or not seen[1], "exit point is out of the officer's view at one of OFFICER_FACING (post)")
	await _shot("01_snowdrift", Layout.HIDE_SNOWDRIFT + Vector3(-1.5, 0, 4.2), 0.35, -0.22)

# =====================================================================================
# 2. Вход и выход по E; внутри движения нет; exposure 0; тост при выходе
# =====================================================================================

func _part_enter_exit() -> void:
	print("--- enter / exit ---")
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_SNOWDRIFT_ENTER, "near the drift: prompt «%s» (%s)" % [HideTuning.PROMPT_SNOWDRIFT_ENTER, world.get_hud_state()["prompt"]])
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"snowdrift" and player.hide_owner == spot, "E → hide_mode snowdrift, owner is the drift")
	check(_flat(player.global_position, Layout.HIDE_SNOWDRIFT_ANCHOR) < 0.05, "Ilyusha on the anchor (%.3f m)" % _flat(player.global_position, Layout.HIDE_SNOWDRIFT_ANCHOR))
	check(not player.get_node("Visual/Look").visible, "sprite hidden")
	check(spot.drift.visible, "drift stays visible")
	var boot: Node3D = player.hide_visual.get_node_or_null("SnowdriftBoot")
	check(boot != null and boot.is_visible_in_tree(), "boot sticks out (hide_visual/SnowdriftBoot)")
	if boot:
		var top: float = boot.global_position.y + 0.4
		check(top > 1.4, "boot sole above the drift top (%.2f m)" % top)
	check(spot.dust.emitting, "snow dust burst on enter")
	check(spot.drift in player.get_collision_exceptions(), "collision exception Ilyusha ↔ drift while inside")
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_SNOWDRIFT_EXIT, "inside: prompt «%s» (%s)" % [HideTuning.PROMPT_SNOWDRIFT_EXIT, world.get_hud_state()["prompt"]])
	# Внутри движения нет: ввод в любую сторону, прыжок.
	var start := player.global_position
	for action in [&"move_forward", &"move_left", &"move_back", &"move_right"]:
		Input.action_press(action)
		await drv.frames(30)
		drv.release_all()
	await drv.frames(10)
	check(start.distance_to(player.global_position) < 0.01, "input does not move Ilyusha inside (%.3f m)" % start.distance_to(player.global_position))
	check(player.speed_limit() == 0.0, "speed_limit() = 0 inside")
	# exposure 0 при прямом взгляде вплотную и вдали; сенсор видит 0.
	var p := player.global_position
	check(player.exposure_factor(p + Vector3(0, 1.5, 1.0)) == 0.0 and player.exposure_factor(p + Vector3(0, 1.5, 6.0)) == 0.0, "exposure_factor = 0 at 1 m and 6 m")
	sensor.range_m = 30.0
	sensor.fov_deg = 90.0
	sensor.enabled = true
	_aim(p + Vector3(0, 0, 4.0), p)
	check(sensor.poll() == 0.0, "sensor looking straight at the drift from 4 m: visibility 0 (blocker '%s')" % sensor.last_blocker)
	_aim(p + Vector3(0, 3.0, 1.2), p)   # глаза над сугробом (y 4,5) — всё равно 0
	check(sensor.poll() == 0.0, "sensor above the drift, 1.2 m: visibility 0 (in_view %s)" % sensor.in_view)
	sensor.enabled = false
	await _shot("02_ilyusha_in_snowdrift", Vector3.INF, 0.6, -0.30)
	# Выход.
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"none", "E → out (hide_mode none)")
	check(_flat(player.global_position, Layout.HIDE_SNOWDRIFT_EXIT) < 0.05, "Ilyusha on the exit point (%.3f m)" % _flat(player.global_position, Layout.HIDE_SNOWDRIFT_EXIT))
	check(not _inside_box(player.global_position), "Ilyusha outside the drift box")
	check(player.get_node("Visual/Look").visible and player.hide_visual.get_child_count() == 0, "sprite visible, boot gone")
	check(player.get_collision_exceptions().is_empty(), "no collision exceptions after exit")
	check(spot.toast_count == 1, "exit toast fired once (%d)" % spot.toast_count)
	check(world.get_hud_state()["hide_hint"] == QuestLines.HIDE_SNOW_TOAST, "HUD hide_hint shows «%s»" % QuestLines.HIDE_SNOW_TOAST)
	var hud := world.get_node("GameHUD")
	check(hud.prompt_label.text == QuestLines.HIDE_SNOW_TOAST and hud.prompt_label.is_visible_in_tree(), "HUD prompt line shows the toast (%s)" % hud.prompt_label.text)
	await drv.frames(int(2.3 * 60))
	check(world.get_hud_state()["hide_hint"] == QuestLines.HIDE_SNOW_TOAST, "toast still on at 2.3 s")
	await drv.frames(int(0.4 * 60))
	check(world.get_hud_state()["hide_hint"] == "", "toast gone after 2.5 s")
	check(_flat(spot.global_position, center) < 0.01 and spot.drift.visible, "drift did not move after exit")
	# Управляем: идёт от сугроба.
	var before := player.global_position
	await _walk_forward(40)
	check(_flat(before, player.global_position) > 1.0, "after exit Ilyusha walks (%.2f m)" % _flat(before, player.global_position))

# =====================================================================================
# 3. Шкала спадает по общим правилам, а не обнуляется
# =====================================================================================

func _part_decay() -> void:
	print("--- suspicion decay ---")
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	world.stealth.suspicion = 0.6
	check(spot.enter(), "spot.enter() with suspicion 0.6")
	await drv.frames(2)
	var s1: float = world.stealth.suspicion
	await drv.frames(10)
	var s2: float = world.stealth.suspicion
	check(s1 > 0.5, "suspicion not zeroed on entering (%.2f)" % s1)
	check(s2 < s1 and s2 > 0.0, "suspicion decays inside, not reset (%.2f → %.2f in 10 frames)" % [s1, s2])
	check(spot.exit(), "spot.exit()")
	await _wait_clear()

# =====================================================================================
# 4. Сугроб перекрывает луч для Илюши за ним (тестовый сенсор и полицейский)
# =====================================================================================

func _part_occlusion() -> void:
	print("--- occlusion ---")
	var behind := center + Vector3(0, 0, -1.6)
	await _place(behind, 0.0)
	check(not _inside_box(player.global_position) and player.hide_mode == &"none", "Ilyusha stands outside behind the drift %s" % behind)
	sensor.range_m = 30.0
	sensor.fov_deg = 90.0
	sensor.enabled = true
	_aim(center + Vector3(0, 0, 5.0), behind)
	check(sensor.poll() == 0.0 and not sensor.in_view and sensor.last_blocker == "SnowdriftBody", "drift covers Ilyusha behind it (blocker '%s')" % sensor.last_blocker)
	_aim(center + Vector3(3.5, 0, 5.0), center + Vector3(3.5, 0, -1.6))
	await _place(center + Vector3(3.5, 0, -1.6), 0.0)
	check(sensor.poll() == 1.0, "control: same distance beside the drift → 1.0 (blocker '%s')" % sensor.last_blocker)
	sensor.enabled = false
	# Полицейский на посту, смотрит на запад (на сугроб): западнее сугроба Илюшу не видно, в сугробе — тоже.
	var patrols := world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	officer.place_at(Layout.OFFICER_POST)
	await drv.frames(3)
	var cop: DetectionSensor = officer.sensor
	cop.enabled = true
	var shadow := center + Vector3(-2.1, 0, 0)
	await _place(shadow, 0.0)
	var v := cop.poll()
	check(v == 0.0 and cop.last_blocker == "SnowdriftBody", "officer (west): Ilyusha west of the drift covered (%.1f, blocker '%s')" % [v, cop.last_blocker])
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(3)
	check(cop.poll() == 0.0, "officer (west): Ilyusha inside → 0")
	spot.exit()
	cop.enabled = false
	await _wait_clear()

# =====================================================================================
# 5. Выход занят: «ВЫХОД ЗАНЯТ», Илюша внутри
# =====================================================================================

func _part_exit_blocked() -> void:
	print("--- exit blocked ---")
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	var toasts: int = spot.toast_count
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"snowdrift", "entered by E")
	for layer in [1, 4]:
		var block := _blocker(Layout.HIDE_SNOWDRIFT_EXIT, layer)
		await drv.frames(2)
		await drv.interact()
		await drv.frames(3)
		check(player.hide_mode == &"snowdrift" and _flat(player.global_position, Layout.HIDE_SNOWDRIFT_ANCHOR) < 0.05, "layer %d body on the exit: E → still inside, on the anchor" % layer)
		check(world.get_hud_state()["hide_hint"] == HideTuning.HINT_EXIT_BLOCKED, "layer %d: hide_hint «%s» (%s)" % [layer, HideTuning.HINT_EXIT_BLOCKED, world.get_hud_state()["hide_hint"]])
		check(spot.toast_count == toasts, "no exit toast while blocked (%d)" % (spot.toast_count - toasts))
		block.queue_free()
		await drv.frames(int(HideTuning.HINT_SECONDS * 60) + 5)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"none" and _flat(player.global_position, Layout.HIDE_SNOWDRIFT_EXIT) < 0.05, "exit freed: E → out on the exit point")
	await drv.frames(int(2.5 * 60) + 5)

# =====================================================================================
# 6. Провал, «Сбросить автомобиль», принудительный сброс при занятом выходе
# =====================================================================================

func _part_fail_and_resets() -> void:
	print("--- fail / resets ---")
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(3)
	world._on_player_detected()   # провал в сугробе (вручную: в сугробе exposure 0, сенсоры его не дают)
	var wait := 0
	while (world.is_stealth_failing() or wait < 3) and wait < 600:
		await drv.frames(1)
		wait += 1
	await drv.frames(3)
	_expect_out("after fail/respawn", Layout.STEALTH_CHECKPOINT)
	check(player.input_enabled, "after fail: input enabled")
	var before := player.global_position
	world.camera_rig.yaw = Layout.STEALTH_CHECKPOINT_YAW
	await _walk_forward(40)
	check(_flat(before, player.global_position) > 1.0, "after fail: Ilyusha walks (%.2f m)" % _flat(before, player.global_position))
	await _wait_clear()
	# «Сбросить автомобиль» из паузы: Илюша извлечён на выход, не остаётся в меше.
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(3)
	world.reset_car()
	await drv.frames(3)
	_expect_out("after reset_car", Layout.HIDE_SNOWDRIFT_EXIT)
	before = player.global_position
	world.camera_rig.yaw = 0.0
	await _walk_forward(30)
	check(_flat(before, player.global_position) > 0.8, "after reset_car: Ilyusha walks (%.2f m)" % _flat(before, player.global_position))
	# Принудительный сброс при занятом выходе — на соседнюю свободную точку.
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(3)
	var block := _blocker(Layout.HIDE_SNOWDRIFT_EXIT, 1)
	await drv.frames(2)
	world.reset_hide()
	await drv.frames(3)
	check(player.hide_mode == &"none" and not _inside_box(player.global_position), "reset_hide with blocked exit: out of the drift (%s)" % player.global_position)
	check(_flat(player.global_position, Layout.HIDE_SNOWDRIFT_EXIT) > 0.5, "reset_hide with blocked exit: placed beside, not on the blocker")
	block.queue_free()
	await drv.frames(3)

# =====================================================================================
# 7. Гэг C04: полицейский смотрит на сугроб, Илюша внутри — раз за попытку
# =====================================================================================

func _part_gag() -> void:
	print("--- gag C04 ---")
	var officer: Node3D = world.get_node("LevelGeometry/Patrols").officer
	var sound := world.get_node("SoundDirector")
	world.respawn_at_checkpoint()   # новая попытка: флаг гэга сброшен
	await drv.frames(3)
	var count0: int = spot.gag_count
	# Полицейский на юг — на сугроб не смотрит, гэга нет.
	check(await drv.wait_officer_turn(1), "officer turned south (%s)" % drv.last_error)
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(60)
	check(not spot.officer_looks_at_drift() and spot.gag_count == count0, "officer south: no C04 (%d)" % spot.gag_count)
	# Разворот на запад, к сугробу — гэг.
	check(await drv.wait_officer_turn(0), "officer turned west (%s)" % drv.last_error)
	await drv.frames(5)
	check(spot.officer_looks_at_drift(), "officer west looks at the drift")
	check(spot.gag_count == count0 + 1, "C04 fired once when the officer turned to the drift (%d)" % (spot.gag_count - count0))
	await drv.frames(10)
	check(sound.subtitle_card.visible and sound.subtitle_label.text == QuestLines.HIDE_SNOW_LOOK[0], "subtitle shows the officer's one line (%s)" % sound.subtitle_label.text.replace("\n", " / "))
	await _shot("03_gag_c04", Vector3.INF, 0.9, -0.28)
	await drv.frames(int(2.5 * 60))
	check(not sound.gag_playing() and not sound.subtitle_card.visible, "one line only: gone after 2.5 s (TEXT-01), no radio-style second pair")
	# В той же попытке: выйти, снова войти под взглядом — второго раза нет.
	spot.exit()
	await drv.frames(3)
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(30)
	check(spot.gag_count == count0 + 1, "same attempt: re-entering does not repeat C04 (%d)" % (spot.gag_count - count0))
	# Новая попытка (респавн) — снова можно.
	world.respawn_at_checkpoint()
	await drv.frames(3)
	officer.place_at(Layout.OFFICER_POST)
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(10)
	check(spot.gag_count == count0 + 2, "after respawn C04 can fire again (%d)" % (spot.gag_count - count0))
	spot.exit()
	await drv.frames(int(5.5 * 60))

# =====================================================================================
# 8. 20 входов и выходов
# =====================================================================================

func _part_toggles() -> void:
	print("--- 20 toggles ---")
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	await drv.frames(5)
	var player_nodes := player.find_children("*", "", true, false).size()
	var spot_nodes := spot.find_children("*", "", true, false).size()
	var ok := true
	for i in 20:
		await drv.interact()
		await drv.frames(2)
		ok = ok and player.hide_mode == &"snowdrift" and _flat(player.global_position, Layout.HIDE_SNOWDRIFT_ANCHOR) < 0.05
		await drv.interact()
		await drv.frames(2)
		ok = ok and player.hide_mode == &"none" and _flat(player.global_position, Layout.HIDE_SNOWDRIFT_EXIT) < 0.05
	await drv.frames(5)
	check(ok, "20 enter/exit cycles by E: anchor in, exit point out")
	check(player.find_children("*", "", true, false).size() == player_nodes, "no node leak under Ilyusha (%d → %d)" % [player_nodes, player.find_children("*", "", true, false).size()])
	check(spot.find_children("*", "", true, false).size() == spot_nodes, "no node leak under the drift (%d → %d)" % [spot_nodes, spot.find_children("*", "", true, false).size()])
	check(player.get_collision_exceptions().is_empty() and player.get_node("Visual/Look").visible, "no exceptions left, sprite visible")
	check(is_equal_approx(player.speed_limit(), Ilyusha.WALK_SPEED), "speed_limit() back to WALK_SPEED")
	world.camera_rig.yaw = 0.0
	var top := 0.0
	Input.action_press(&"move_forward")
	for i in 40:
		await drv.frames(1)
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
	drv.release_all()
	check(absf(top - Ilyusha.WALK_SPEED) < 0.05, "walking speed %.1f m/s (%.2f)" % [Ilyusha.WALK_SPEED, top])
	await drv.frames(int(2.5 * 60) + 5)

# =====================================================================================
# 9. Тексты: запрещённых слов нет
# =====================================================================================

func _part_texts() -> void:
	print("--- texts ---")
	var texts: Array = QuestLines.HIDE_SNOW_LOOK.duplicate()
	texts.append(QuestLines.HIDE_SNOW_TOAST)
	for text in texts:
		var low: String = String(text).to_lower()
		check(not low.contains("мобилизац") and not low.contains("бусификац"), "forbidden words absent in '%s'" % text)

# =====================================================================================
# 10. Перезапуск мира из сугроба
# =====================================================================================

func _part_restart() -> void:
	print("--- restart ---")
	await _place(Layout.HIDE_SNOWDRIFT_EXIT, PI)
	spot.enter()
	await drv.frames(3)
	main.start_game()
	await drv.frames(15)
	if not _bind():
		return
	check(player.hide_mode == &"none" and player.get_node("Visual/Look").visible and player.input_enabled, "new world: Ilyusha out, visible, input on")
	check(_flat(player.global_position, Layout.SPAWN) < 0.5, "new world: Ilyusha at SPAWN")
	check(not spot.is_inside() and spot.prompt == HideTuning.PROMPT_SNOWDRIFT_ENTER, "new world: drift empty, prompt enter")

# =====================================================================================
# Помощники
# =====================================================================================

func _expect_out(label: String, where: Vector3) -> void:
	check(player.hide_mode == &"none" and not spot.is_inside(), "%s: hide_mode none, drift empty" % label)
	check(_flat(player.global_position, where) < 0.1, "%s: Ilyusha at %s (%s)" % [label, where, player.global_position])
	check(not _inside_box(player.global_position), "%s: not inside the drift mesh" % label)
	check(player.visible and player.get_node("Visual/Look").visible and player.hide_visual.get_child_count() == 0, "%s: visible, boot gone" % label)
	check(not player.get_node("CollisionShape3D").disabled and player.get_collision_exceptions().is_empty(), "%s: collision on, no exceptions" % label)
	check(_flat(spot.global_position, center) < 0.01 and spot.drift.visible and spot.prompt == HideTuning.PROMPT_SNOWDRIFT_ENTER, "%s: drift in place, prompt enter" % label)

func _blocker(at: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ExitBlocker"
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.2, 0.6)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	body.global_position = at + Vector3.UP * 0.6
	return body

func _place(p: Vector3, yaw: float) -> void:
	drv.release_all()
	player.place(p, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await drv.frames(3)

func _walk_forward(count: int) -> void:
	Input.action_press(&"move_forward")
	await drv.frames(count)
	drv.release_all()
	await drv.frames(15)

## Дождаться: шкала 0, защита после респавна кончилась.
func _wait_clear() -> void:
	for i in 900:
		if world.stealth.suspicion == 0.0 and world.stealth.protection_left() == 0.0 and not world.is_stealth_failing():
			return
		await drv.frames(1)

func _aim(at: Vector3, look_at: Vector3) -> void:
	sensor.global_position = Vector3(at.x, at.y, at.z)
	var d := look_at - at
	sensor.rotation.y = atan2(-d.x, -d.z)

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Точка внутри коробки сугроба (в плоскости XZ, с запасом радиуса капсулы Илюши 0,35).
func _inside_box(p: Vector3, margin := 0.0) -> bool:
	var half := Vector2(1.2 + margin, 0.8 + margin)
	return absf(p.x - center.x) < half.x and absf(p.z - center.z) < half.y

## Расстояние от отрезка a–b до прямоугольника сугроба в плоскости XZ (выборкой по 5 см).
func _segment_to_box(a: Vector3, b: Vector3) -> float:
	var best := INF
	var steps := maxi(1, int(a.distance_to(b) / 0.05))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var dx := maxf(absf(p.x - center.x) - 1.2, 0.0)
		var dz := maxf(absf(p.z - center.z) - 0.8, 0.0)
		best = minf(best, Vector2(dx, dz).length())
	return best

## Кадр с игровой камеры: at — куда поставить Илюшу (INF — не трогать), yaw и pitch камеры.
func _shot(label: String, at: Vector3, yaw: float, pitch: float) -> void:
	if not capture:
		return
	var restore := player.global_position
	var restore_yaw: float = player.visual.rotation.y
	if at != Vector3.INF:
		player.place(at, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.pitch = pitch
	world.camera_rig.snap()
	await drv.frames(20)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())
	if at != Vector3.INF:
		player.place(restore, restore_yaw)
	world.camera_rig.pitch = -0.17
	await drv.frames(3)

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish(code := -1) -> void:
	if _finishing:
		return
	_finishing = true
	if drv:
		drv.release_all()
	if is_instance_valid(main):
		for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
		main.queue_free()
	for i in 5:
		await physics_frame
	main = null
	world = null
	player = null
	spot = null
	sensor = null
	drv = null
	preload("res://game/world/materials.gd").clear_cache()
	preload("res://game/world/environment_dress.gd").clear_cache()
	preload("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("HIDE_SNOW: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

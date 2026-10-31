extends SceneTree
## EXT-02 E (docs/extension/HIDE_SPOTS.md, разделы 5.3, 8, 11, 14 E): бочка на настоящей сцене main.tscn.
## Облик у Layout.BARREL; вход/выход по E; облик на Илюше лежит поперёк хода и вращается по фактическому пути;
## капсула 0,45 в бочке и 0,35 после; скорость ≤ 2,6; заметность стоя вдали 0, катясь 1,0; стена: нет туннелинга,
## провала под карту и разгона, вращение у стены стоит; «БУМ» не чаще раза в 4 с, тост «БОЧКА ПРИБЫЛА» и «Ну всё»
## один раз за попытку; дребезжание по скорости; торцы бочки в проходе гаражей у киоска (замер); отказ посадки в «Ладу»;
## «ВЫХОД ЗАНЯТ»; после выхода WALK_SPEED и прыжок; reset() и сброс при респавне; гэг C05 в конусе Officer раз
## за попытку; 20 входов-выходов без утечки узлов.
## Наблюдатели на время прогона выключены (кроме части C05).
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/hide_barrel_test.gd

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")
const BarrelScript = preload("res://game/stealth/barrel_hide_spot.gd")

var failures: Array[String] = []
var checks := 0
var _finishing := false
var main: Node
var drv
var world: DemoWorld
var player: Ilyusha
var barrel: Node3D
var sound: Node
var yard := Vector3.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(600.0, true, false, true).timeout.connect(func():
		push_error("FAIL: hide barrel test exceeded 600 simulated seconds")
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
	sound = world.get_node_or_null("SoundDirector")
	barrel = world.get_node_or_null("LevelGeometry/HideSpots/Barrel")
	if not check(barrel != null and barrel.get_script() == BarrelScript, "LevelGeometry/HideSpots/Barrel uses barrel_hide_spot.gd"):
		_finish()
		return
	_sensors(false)
	yard = Layout.SPAWN + Vector3(10.0, 0.0, -12.0)
	await _part_look()
	await _part_enter()
	await _part_roll()
	await _part_wall()
	await _part_passage()
	await _part_car_refusal()
	await _part_exit()
	await _part_exit_blocked()
	await _part_reset()
	await _part_roll_gag()
	await _part_toggles()
	drv.release_all()
	_finish()

# =====================================================================================
# 1. Облик в мире
# =====================================================================================

func _part_look() -> void:
	print("--- look ---")
	check(barrel.global_position.distance_to(Layout.BARREL) < 0.01, "barrel stands at Layout.BARREL %s" % barrel.global_position)
	check(barrel.mode == &"barrel" and barrel.prompt == HideTuning.PROMPT_BARREL_ENTER, "mode barrel, prompt '%s'" % barrel.prompt)
	check(barrel.is_in_group(&"hide_spots") and barrel.has_method(&"reset"), "in group hide_spots with reset()")
	var box := _mesh_aabb(barrel.look)
	print("INFO: standing barrel AABB size %s" % box.size)
	check(absf(box.size.x - 0.93) < 0.02 and absf(box.size.z - 0.93) < 0.02, "diameter 0.9 m (+hoops 0.93) (%.2f × %.2f)" % [box.size.x, box.size.z])
	check(box.size.y >= 1.2 and box.size.y <= 1.45 and absf(box.position.y) < 0.02, "height 1.2 m + snow cap ≤ 0.25 m, on the ground (%.2f from %.2f)" % [box.size.y, box.position.y])
	check(barrel.look.visible, "standing barrel visible")
	var body := barrel.find_children("*", "CollisionObject3D", true, false)
	check(body.is_empty(), "standing barrel has no collision (does not block routes)")

# =====================================================================================
# 2. Вход по E у бочки
# =====================================================================================

func _part_enter() -> void:
	print("--- enter ---")
	var stand := Layout.BARREL + Vector3(-1.4, 0.0, 0.0)
	check(_free(stand, 0.4), "stand next to barrel %s is free" % stand)
	await _place(stand, -PI * 0.5)
	check(player.current_interactable() == barrel, "E zone next to barrel is the barrel (%s)" % player.current_interactable())
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_BARREL_ENTER, "HUD prompt '%s'" % world.get_hud_state()["prompt"])
	var before := player.global_position
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"barrel" and player.hide_owner == barrel, "E → hide_mode barrel, owner barrel")
	check(not barrel.look.visible, "standing barrel hidden")
	check(barrel.shell != null and barrel.shell.get_parent() == player.hide_visual, "barrel shell under player.hide_visual")
	check(not player.get_node("Visual/Look").visible, "Ilyusha sprite hidden")
	check(is_equal_approx(barrel.player_collider_radius(), BarrelScript.COLLIDER_RADIUS), "capsule radius 0.45 in barrel (%.2f)" % barrel.player_collider_radius())
	check(_flat(player.global_position, before) < 0.15, "entering does not move Ilyusha (%.2f m)" % _flat(player.global_position, before))
	check(barrel.prompt == HideTuning.PROMPT_BARREL_EXIT, "prompt '%s'" % barrel.prompt)
	var shell_box := _mesh_aabb(barrel.shell, player.hide_visual)
	print("INFO: lying barrel AABB size %s (in visual space)" % shell_box.size)
	check(absf(shell_box.size.y - 0.93) < 0.02 and absf(shell_box.position.y + 0.015) < 0.02, "lying barrel: Ø 0.9 (+hoops) high, on the ground (%.2f from %.2f)" % [shell_box.size.y, shell_box.position.y])
	check(absf(shell_box.size.x - 1.24) < 0.03 and absf(shell_box.size.z - 0.93) < 0.02, "lying barrel: 1.2 m across, Ø 0.9 along the motion (%.2f × %.2f)" % [shell_box.size.x, shell_box.size.z])

# =====================================================================================
# 3. Качение: скорость, заметность, вращение по ходу
# =====================================================================================

func _part_roll() -> void:
	print("--- roll ---")
	var path_free := true
	for k in 8:
		path_free = path_free and _free(yard + Vector3(0, 0, -k), 0.5)
	check(path_free, "yard strip %s … 7 m north is free" % yard)
	await _place(yard, 0.0)
	await drv.frames(5)
	var p := player.global_position
	check(player.is_still() and is_equal_approx(player.exposure_factor(p + Vector3(0, 1.5, 5.0)), 0.0), "standing far: exposure 0")
	check(is_equal_approx(player.exposure_factor(p + Vector3(0, 1.5, 1.2)), 0.5), "standing ≤ 1.5 m: exposure 0.5")
	var angle0: float = barrel.roll_angle
	var travel0 := player.hide_travel
	Input.action_press(&"move_forward")
	var top := 0.0
	var up_dot := -2.0
	var axis_dot := 2.0
	var ratio_max := 0.0
	for i in 70:
		await drv.frames(1)
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
		if i == 9:
			# Чуть меньше четверти оборота: верх бочки ушёл по ходу (на север, −Z).
			up_dot = barrel.roller.global_basis.y.normalized().dot(Vector3(0, 0, -1))
		if i == 40:
			var axis: Vector3 = barrel.shell.get_child(0).get_child(0).global_basis.y.normalized()
			axis_dot = absf(axis.dot(Vector3(0, 0, -1)))
			p = player.global_position
			check(is_equal_approx(player.exposure_factor(p + Vector3(0, 1.5, 5.0)), 1.0), "rolling far: exposure 1.0")
			check(is_equal_approx(player.exposure_factor(p + Vector3(0, 1.5, 1.2)), 1.0), "rolling ≤ 1.5 m: exposure 1.0")
		if sound and sound.barrel_roll_player:
			ratio_max = maxf(ratio_max, db_to_linear(sound.barrel_roll_player.volume_db - sound.BARREL_ROLL_DB) if sound.barrel_roll_player.playing else 0.0)
	drv.release_all()
	check(top <= HideTuning.HIDE_SPEED_BARREL + 0.02 and top >= HideTuning.HIDE_SPEED_BARREL - 0.1, "top rolling speed ≈ 2.6 m/s (%.2f)" % top)
	check(up_dot > 0.3, "barrel top rolls forward with the motion (dot %.2f)" % up_dot)
	check(axis_dot < 0.1, "barrel lies across the motion (axis·dir %.2f)" % axis_dot)
	var travelled := player.hide_travel - travel0
	check(absf((barrel.roll_angle - angle0) + travelled / BarrelScript.RADIUS) < 0.01, "roll angle = −travel / 0.45 (%.2f rad for %.2f m)" % [barrel.roll_angle - angle0, travelled])
	check(ratio_max > 0.9, "roll rattle at full volume at full speed (ratio %.2f)" % ratio_max)
	check(sound == null or (sound.BARREL_ROLL.loop_mode == AudioStreamWAV.LOOP_FORWARD and sound.BARREL_BUMP.loop_mode == AudioStreamWAV.LOOP_DISABLED), "rattle stream loops, БУМ does not")
	await drv.frames(30)
	check(player.is_still(), "stops sharply after release")
	check(sound == null or not sound.barrel_roll_player.playing, "roll rattle silent when standing")
	check(player.hide_mode == &"barrel", "still in barrel")

# =====================================================================================
# 4. Стена: удар, без туннелинга и разгона, вращение стоит, звук и тост
# =====================================================================================

func _part_wall() -> void:
	print("--- wall ---")
	var garages := _solid("Garages_Yard")
	var face_x: float = garages[0].x + garages[1].x * 0.5
	# Полоса у фасада: центр гаражей, иначе ближайшая свободная по z (у центра — скат горки PROPS-01).
	var z: float = garages[0].y
	var lane := false
	for dz in [0.0, -5.0, 5.0, -10.0, 10.0, -14.0, 14.0]:
		z = garages[0].y + dz
		lane = true
		for k in 6:
			lane = lane and _free(Vector3(face_x + 1.0 + k, 0.0, z), 0.5)
		if lane:
			break
	var start := Vector3(face_x + 6.0, 0.0, z)
	check(lane, "6 m east of Garages_Yard face x=%.1f at z=%.1f is free" % [face_x, z])
	await _place(start, PI * 0.5)   # курс на запад
	var bumps0: int = barrel.bump_count
	var toasts0: int = barrel.toast_count
	var played0: int = sound.played.get("barrel_bump", 0) if sound else 0
	var hit_frame := -1
	var min_x := INF
	var min_y := INF
	Input.action_press(&"move_forward")
	for i in 240:
		await drv.frames(1)
		min_x = minf(min_x, player.global_position.x)
		min_y = minf(min_y, player.global_position.y)
		if hit_frame < 0 and barrel.bump_count > bumps0:
			hit_frame = i
		if hit_frame >= 0 and i >= hit_frame + 30:
			break
	check(hit_frame >= 0, "bump registered at the wall (frame %d)" % hit_frame)
	check(barrel.bump_count == bumps0 + 1 and (sound == null or sound.played.get("barrel_bump", 0) == played0 + 1), "one БУМ on impact (%d)" % (barrel.bump_count - bumps0))
	check(barrel.toast_count == toasts0 + 1 and barrel.toast_text() == QuestLines.HIDE_BARREL_BUMP_TOAST, "toast БОЧКА ПРИБЫЛА (%s)" % barrel.toast_text())
	check(world.get_hud_state()["hide_hint"] == QuestLines.HIDE_BARREL_BUMP_TOAST, "toast shown in HUD hint line ('%s')" % world.get_hud_state()["hide_hint"])
	check(sound == null or sound.subtitle_label.text == QuestLines.HIDE_BARREL_BUMP_ILYUSHA, "subtitle '%s'" % (sound.subtitle_label.text if sound else ""))
	check(min_x >= face_x + BarrelScript.COLLIDER_RADIUS - 0.02, "no tunnelling: centre x ≥ face + 0.45 (%.3f vs %.3f)" % [min_x, face_x])
	check(min_y > -0.05 and player.global_position.y > -0.05, "no fall under the map (min y %.3f)" % min_y)
	var pen := _barrel_penetration()
	print("INFO: lying barrel vs World head-on: overlap %s" % pen)
	check(not pen, "lying barrel Ø 0.9 does not enter the wall head-on")
	# Держим клавишу в стену ещё 1 с: ни пути, ни вращения, ни скорости.
	var p0 := player.global_position
	var a0: float = barrel.roll_angle
	var vmax := 0.0
	var rattle := false
	for i in 60:
		await drv.frames(1)
		var real := player.get_real_velocity()
		vmax = maxf(vmax, Vector2(real.x, real.z).length())
		rattle = rattle or (sound != null and sound.barrel_roll_player.playing)
	check(_flat(player.global_position, p0) < 0.02, "pressing into the wall: no movement (%.3f m)" % _flat(player.global_position, p0))
	check(absf(barrel.roll_angle - a0) < 0.03, "pressing into the wall: rotation stays (%.3f rad)" % absf(barrel.roll_angle - a0))
	check(vmax < 0.1, "pressing into the wall: speed 0, no build-up (%.3f m/s)" % vmax)
	check(not rattle, "pressing into the wall: rattle silent")
	check(barrel.bump_count == bumps0 + 1, "pressing into the wall: no repeated БУМ")
	drv.release_all()
	# Отъехать и снова в стену раньше 4 с — без звука; позже 4 с — звук, но тоста нет (раз за попытку).
	await _back_off_and_ram(1.6)
	check(barrel.bump_count == bumps0 + 1, "second ram within 4 s: no БУМ (%d)" % (barrel.bump_count - bumps0))
	var wait_until: float = barrel.bump_times.back() + BarrelScript.BUMP_COOLDOWN + 0.2
	while barrel._clock < wait_until:
		await drv.frames(1)
	await _back_off_and_ram(1.6)
	check(barrel.bump_count == bumps0 + 2, "ram after 4 s: БУМ again (%d)" % (barrel.bump_count - bumps0))
	var times: Array = barrel.bump_times
	check(times.size() >= 2 and times[-1] - times[-2] >= BarrelScript.BUMP_COOLDOWN, "БУМ interval ≥ 4 s (%.2f s)" % (times[-1] - times[-2] if times.size() >= 2 else 0.0))
	check(barrel.toast_count == toasts0 + 1, "toast БОЧКА ПРИБЫЛА once per attempt (%d)" % (barrel.toast_count - toasts0))
	drv.release_all()
	await drv.frames(20)

func _back_off_and_ram(distance: float) -> void:
	var x0 := player.global_position.x
	Input.action_press(&"move_back")
	for i in 120:
		await drv.frames(1)
		if player.global_position.x - x0 >= distance:
			break
	drv.release_all()
	await drv.frames(10)
	world.camera_rig.yaw = PI * 0.5
	Input.action_press(&"move_forward")
	for i in 120:
		await drv.frames(1)
		if i > 10 and player.get_real_velocity().length() < 0.05:
			break
	drv.release_all()
	await drv.frames(5)

# =====================================================================================
# 5. Проход у гаражей киоска: бочка вдоль стены — торцы (замер), без застревания
# =====================================================================================

func _part_passage() -> void:
	print("--- passage at kiosk garages ---")
	var garages := _solid("Garages_Kiosk")
	var face_x: float = garages[0].x + garages[1].x * 0.5
	var bins := _solid("KioskBins")
	var gap: float = bins[0].x - bins[1].x * 0.5 - face_x
	print("INFO: passage Garages_Kiosk (x=%.2f) — KioskBins (x=%.2f): %.2f m" % [face_x, face_x + gap, gap])
	# Южный торец гаражей z = −62, контейнеры z −63,5…−60,5: старт в проходе между ними.
	var start := Vector3(face_x + gap * 0.5, 0.0, -62.3)
	check(_free(start, BarrelScript.COLLIDER_RADIUS), "passage start %s fits the 0.45 capsule" % start)
	await _place(start, 0.0)
	# На север (−Z) вдоль гаражей, прижимаясь к ним (северо-запад): бочка поперёк хода — торцом к стене.
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left", 0.35)
	var worst := 0.0
	var min_x := INF
	for i in 240:
		await drv.frames(1)
		min_x = minf(min_x, player.global_position.x)
		if barrel.shell:
			worst = maxf(worst, face_x - _barrel_min_x())
		if player.global_position.z < -66.0:
			break
	drv.release_all()
	print("INFO: rolling along garages wall: centre min x %.3f (face %.2f), barrel end into wall %.3f m" % [min_x, face_x, worst])
	check(min_x >= face_x + BarrelScript.COLLIDER_RADIUS - 0.02, "passage: capsule keeps 0.45 from the garages (%.3f)" % (min_x - face_x))
	check(player.global_position.z < -66.0, "passage: barrel rolls through between garages and bins (z %.2f)" % player.global_position.z)
	# Капсула 0,45 круглая, лежащая бочка — прямоугольник 1,2 × 0,9: торец у стены входит в неё на 0,6 − 0,45 = 0,15 м
	# при оси поперёк стены и до √(0,6² + 0,45²) − 0,45 = 0,30 м при косом ходе. Замер — в лог, предел — геометрия.
	check(worst <= 0.30, "passage: barrel end into the garages wall within the capsule bound 0.30 m (%.3f m)" % worst)
	await drv.frames(20)

# =====================================================================================
# 6. В бочке нельзя сесть в машину
# =====================================================================================

func _part_car_refusal() -> void:
	print("--- car refusal ---")
	await _place(_car_stand(), 0.0)
	await drv.frames(3)
	var zone := player.current_interactable()
	check(zone == world.car.enter_zone, "at the Lada door the car zone is current (%s)" % zone)
	check(world.get_hud_state()["prompt"] == HideTuning.HINT_BARREL, "HUD at the car: '%s'" % world.get_hud_state()["prompt"])
	await drv.interact()
	await drv.frames(3)
	check(world.control_mode == &"on_foot" and player.hide_mode == &"none", "E at the car in barrel: no boarding, out of the barrel (P2-2)")
	check(world.get_hud_state()["hide_hint"] == HideTuning.HINT_BARREL, "hint '%s'" % world.get_hud_state()["hide_hint"])
	await drv.frames(int(HideTuning.HINT_SECONDS * 60) + 5)
	# В бочке у сугроба: ближайшая чужая зона — другое укрытие, E — выход из бочки, не в сугроб (P2-2).
	var snow: Node3D = world.get_node("LevelGeometry/HideSpots/Snowdrift")
	await _place(Layout.HIDE_SNOWDRIFT_EXIT + Vector3(0.0, 0.0, -0.4), PI)
	check(barrel.enter(), "barrel on next to the snowdrift")
	await drv.frames(3)
	var in_drift_zone := false
	for area in player.probe.get_overlapping_areas():
		in_drift_zone = in_drift_zone or area == snow
	check(in_drift_zone, "Ilyusha stands in the snowdrift E zone")
	check(player.current_interactable() == barrel, "barrel at the snowdrift: E target is the own barrel (%s)" % player.current_interactable())
	check(world.get_hud_state()["prompt"] == HideTuning.PROMPT_BARREL_EXIT, "barrel at the snowdrift: prompt '%s'" % world.get_hud_state()["prompt"])
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"none" and not snow.is_occupied(), "barrel at the snowdrift: E gets out of the barrel, not into the drift (%s)" % player.hide_mode)
	# Дальше — снова в бочке (часть «выход» ждёт Илюшу внутри).
	check(barrel.enter(), "back into the barrel")
	await drv.frames(3)

# =====================================================================================
# 7. Выход: свободная точка рядом, бочка стоит где была, скорость и прыжок вернулись
# =====================================================================================

func _part_exit() -> void:
	print("--- exit ---")
	var spot := yard + Vector3(0, 0, -3.0)
	await _place(spot, 0.0)
	await drv.frames(5)
	check(player.current_interactable() == barrel, "far from the barrel home E is still the barrel")
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"none", "E → out of the barrel")
	var out := _flat(player.global_position, spot)
	check(out >= 0.9 and out <= 1.5, "Ilyusha steps out 1.0–1.4 m from the barrel (%.2f m)" % out)
	check(_free(player.global_position, 0.35), "exit point is free")
	check(_flat(barrel.global_position, spot) < 0.05 and barrel.look.visible, "barrel stands where it was ridden (%s)" % barrel.global_position)
	check(is_equal_approx(barrel.player_collider_radius(), 0.35), "capsule radius back to 0.35 (%.2f)" % barrel.player_collider_radius())
	check(player.get_node("Visual/Look").visible and player.hide_visual.get_child_count() == 0, "sprite visible, shell removed")
	check(barrel.prompt == HideTuning.PROMPT_BARREL_ENTER, "prompt back to '%s'" % barrel.prompt)
	await drv.frames(5)
	var top := await _hold_forward(40)
	check(absf(top - Ilyusha.WALK_SPEED) < 0.05, "walking speed back to %.1f m/s (%.2f)" % [Ilyusha.WALK_SPEED, top])
	await drv.frames(30)
	var h := await _jump_height()
	check(h > 1.0, "jump back after the barrel (%.2f m)" % h)
	await drv.frames(30)

# =====================================================================================
# 8. Выход занят: со всех сторон стенки — «ВЫХОД ЗАНЯТ», Илюша остаётся в бочке
# =====================================================================================

func _part_exit_blocked() -> void:
	print("--- exit blocked ---")
	var spot := yard + Vector3(0, 0, -5.0)
	await _place(spot, 0.0)
	barrel.global_position = spot + Vector3(1.0, 0, 0)
	await drv.frames(3)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"barrel", "in the barrel again")
	var pen := StaticBody3D.new()
	pen.collision_layer = 1
	pen.collision_mask = 0
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.5, 2.0, 4.2) if side.x != 0.0 else Vector3(4.2, 2.0, 1.5)
		shape.shape = box
		shape.position = player.global_position + side * 1.3 + Vector3.UP
		pen.add_child(shape)
	world.add_child(pen)
	await drv.frames(3)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"barrel", "walled in: stays in the barrel")
	check(world.get_hud_state()["hide_hint"] == HideTuning.HINT_EXIT_BLOCKED, "hint '%s'" % world.get_hud_state()["hide_hint"])
	pen.queue_free()
	await drv.frames(int(HideTuning.HINT_SECONDS * 60) + 5)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"none", "walls gone: exit works")

# =====================================================================================
# 9. reset(): бочка на Layout.BARREL; сброс при респавне изнутри
# =====================================================================================

func _part_reset() -> void:
	print("--- reset ---")
	check(barrel.global_position.distance_to(Layout.BARREL) > 5.0, "barrel was left away from home")
	barrel.reset()
	await drv.frames(2)
	check(barrel.global_position.distance_to(Layout.BARREL) < 0.01 and barrel.look.visible, "reset() → barrel back at Layout.BARREL")
	# Изнутри: респавн (DemoWorld.reset_hide) — режим снят, капсула и облик вернулись, бочка дома, попытка заново.
	var stand := Layout.BARREL + Vector3(-1.4, 0.0, 0.0)
	await _place(stand, 0.0)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"barrel", "in the barrel at home")
	await _place(yard, 0.0)
	world.reset_hide()
	await drv.frames(3)
	check(player.hide_mode == &"none" and is_equal_approx(barrel.player_collider_radius(), 0.35), "reset_hide(): mode none, capsule 0.35")
	check(player.hide_visual.get_child_count() == 0 and player.get_node("Visual/Look").visible, "reset_hide(): shell gone, sprite visible")
	check(barrel.global_position.distance_to(Layout.BARREL) < 0.01 and barrel.look.visible, "reset_hide(): barrel at home")
	check(not barrel._bumped_attempt and not barrel._rolled_attempt, "reset_hide(): gag and toast flags cleared for a new attempt")
	check(sound == null or not sound.barrel_roll_player.playing, "reset_hide(): rattle silent")

# =====================================================================================
# 10. C05: бочка катится в конусе полицейского — субтитры раз за попытку
# =====================================================================================

func _part_roll_gag() -> void:
	print("--- C05 roll gag ---")
	var sensor := _officer_sensor()
	if not check(sensor != null, "Officer has a DetectionSensor"):
		return
	# Встать в бочке у дома и подкатить к полицейскому на расстояние, где он видит (в конусе, луч свободен).
	var stand := Layout.BARREL + Vector3(-1.4, 0.0, 0.0)
	await _place(stand, 0.0)
	await drv.interact()
	await drv.frames(3)
	check(player.hide_mode == &"barrel", "in the barrel for C05")
	var forward := -sensor.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var eye := sensor.global_position
	var found := Vector3.INF
	sensor.enabled = true
	for d in [5.0, 6.0, 4.0, 7.0, 8.0, 3.0]:
		for side in [0.0, 1.0, -1.0, 2.0, -2.0]:
			var p: Vector3 = eye + forward * d + forward.cross(Vector3.UP) * side
			p.y = 0.0
			if not _free(p, 0.5) or not _free(p + forward.cross(Vector3.UP) * 1.0, 0.5):
				continue
			player.place(p, 0.0)
			await drv.frames(2)
			sensor.poll()
			if sensor.in_view:
				found = p
				break
		if found != Vector3.INF:
			break
	check(found != Vector3.INF, "found a spot in the officer's cone with free line of sight (%s)" % found)
	if found == Vector3.INF:
		sensor.enabled = false
		return
	var gags0: int = barrel.roll_gag_count
	var side_yaw := atan2(-forward.cross(Vector3.UP).x, -forward.cross(Vector3.UP).z)
	world.camera_rig.yaw = side_yaw
	Input.action_press(&"move_forward")
	await drv.frames(12)
	drv.release_all()
	await drv.frames(4)
	check(barrel.roll_gag_count == gags0 + 1, "rolling in the officer's cone → C05 once (%d)" % (barrel.roll_gag_count - gags0))
	check(sound == null or sound.subtitle_label.text.begins_with(QuestLines.HIDE_BARREL_ROLL[0]), "subtitle page 1: '%s'" % (sound.subtitle_label.text if sound else ""))
	# Ещё раз в той же попытке — без повтора (шкалу сбрасываем, чтобы не довести до провала).
	world.stealth.suspicion = 0.0
	world.camera_rig.yaw = side_yaw + PI
	Input.action_press(&"move_forward")
	await drv.frames(12)
	drv.release_all()
	await drv.frames(4)
	check(barrel.roll_gag_count == gags0 + 1, "second roll in the cone, same attempt: no repeat")
	sensor.enabled = false
	_sensors(false)
	world.stealth.suspicion = 0.0
	await drv.frames(int(GAG_WAIT * 60))
	check(sound == null or not sound.subtitle_card.visible, "C05 subtitles end after two pages")
	world.reset_hide()
	await drv.frames(3)
	check(not barrel._rolled_attempt, "after respawn reset C05 may play again (new attempt)")
	await _wait_clear()

const GAG_WAIT := 5.5

# =====================================================================================
# 11. 20 входов и выходов: без утечки узлов, скорость прежняя
# =====================================================================================

func _part_toggles() -> void:
	print("--- 20 enter/exit ---")
	var spot := yard + Vector3(0, 0, -3.0)
	await _place(spot, 0.0)
	barrel.global_position = spot + Vector3(1.0, 0, 0)
	await drv.frames(3)
	# Первый цикл — прогрев (SoundDirector лениво заводит плееры бочки на Илюше).
	await drv.interact()
	await drv.frames(3)
	await drv.interact()
	await drv.frames(5)
	var nodes_before := player.find_children("*", "", true, false).size()
	var spot_nodes_before := barrel.find_children("*", "", true, false).size()
	var ok := true
	for i in 20:
		if player.current_interactable() != barrel:
			ok = false
			print("INFO: cycle %d: barrel zone not current (%s)" % [i, player.current_interactable()])
			break
		await drv.interact()
		await drv.frames(2)
		ok = ok and player.hide_mode == &"barrel" and is_equal_approx(barrel.player_collider_radius(), 0.45)
		await drv.interact()
		await drv.frames(2)
		ok = ok and player.hide_mode == &"none" and is_equal_approx(barrel.player_collider_radius(), 0.35)
	await drv.frames(5)
	check(ok, "20 enter/exit cycles by E all accepted")
	var nodes_after := player.find_children("*", "", true, false).size()
	check(nodes_after == nodes_before, "no node leak under Ilyusha (%d → %d)" % [nodes_before, nodes_after])
	check(barrel.find_children("*", "", true, false).size() == spot_nodes_before, "no node leak under the barrel spot")
	check(player.hide_visual.get_child_count() == 0 and player.get_node("Visual/Look").visible, "hide_visual empty, sprite visible")
	var top := await _hold_forward(40)
	check(absf(top - Ilyusha.WALK_SPEED) < 0.05, "walking speed after 20 cycles %.1f m/s (%.2f)" % [Ilyusha.WALK_SPEED, top])
	drv.release_all()
	await drv.frames(20)
	world.reset_hide()

# =====================================================================================
# Помощники
# =====================================================================================

func _sensors(on: bool) -> void:
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = on

func _officer_sensor() -> DetectionSensor:
	var officer := world.get_node_or_null("LevelGeometry/Patrols/Officer")
	return officer.get("sensor") if officer else null

func _place(p: Vector3, yaw: float) -> void:
	drv.release_all()
	player.place(p, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await drv.frames(3)

func _hold_forward(count: int) -> float:
	Input.action_press(&"move_forward")
	var top := 0.0
	for i in count:
		await drv.frames(1)
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
	drv.release_all()
	return top

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

func _wait_clear() -> void:
	for i in 900:
		if world.stealth.suspicion == 0.0 and world.stealth.protection_left() == 0.0 and not world.is_stealth_failing():
			return
		await drv.frames(1)

## Лежащая бочка (цилиндр облика на Илюше) пересекает World глубже 1 см?
func _barrel_penetration() -> bool:
	var body: Node3D = barrel.shell.get_child(0).get_child(0)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = BarrelScript.RADIUS - 0.01
	cylinder.height = BarrelScript.LENGTH - 0.02
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cylinder
	query.collision_mask = 1
	query.transform = Transform3D(body.global_basis.orthonormalized(), body.global_position)
	return not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Наименьший x лежащей бочки (торцы и бока) — для замера входа в стену гаражей.
func _barrel_min_x() -> float:
	var body: Node3D = barrel.shell.get_child(0).get_child(0)
	var axis := body.global_basis.y.normalized()
	var extent := BarrelScript.LENGTH * 0.5 * absf(axis.x) + BarrelScript.RADIUS * sqrt(maxf(0.0, 1.0 - axis.x * axis.x))
	return body.global_position.x - extent

## Габарит облика в осях space (по умолчанию — самого узла); пятна ржавчины (без тени) не считаются: их AABB —
## повёрнутый куб и завышает габарит.
func _mesh_aabb(node: Node3D, space: Node3D = null) -> AABB:
	var box := AABB()
	var first := true
	var inv := (space if space else node).global_transform.affine_inverse()
	for m in node.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var b: AABB = (inv * (m as MeshInstance3D).global_transform) * (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _solid(name: String) -> Array:
	for s in Layout.all_solids():
		if s[0] == name:
			return [s[2], s[3]]
	push_error("no solid " + name)
	return [Vector2.ZERO, Vector3.ZERO]

func _free(p: Vector3, r: float) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = r
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | 4
	query.exclude = [player.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.8)
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

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
	if _finishing:
		return
	_finishing = true
	if drv:
		drv.release_all()
	Engine.physics_ticks_per_second = 60
	if is_instance_valid(main):
		for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
		main.queue_free()
	for i in 5:
		await physics_frame
	main = null
	world = null
	player = null
	barrel = null
	sound = null
	drv = null
	preload("res://game/world/materials.gd").clear_cache()
	preload("res://game/world/environment_dress.gd").clear_cache()
	preload("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	OS.delay_msec(100)
	await process_frame
	print("HIDE_BARREL: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

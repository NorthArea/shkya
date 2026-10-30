extends SceneTree
## KNOCK-01: сбивание жителей «Ладой» без вреда на настоящей сцене main.tscn (набор KNOCK).
## Проверки: константы (порог 3 м/с, потолок полёта 9 м/с, высота 1,5–3 м, лежит 1,5–2,5 с, встаёт 0,8 с, между
## ударами ≤ 0,3 с); наезд на 5 м/с — state knocked, фазы fly → down → getup → back → маршрут, взлёт ≥ 1,5 м и ≤ 3 м,
## дальность ≥ 3 м по ходу машины, кувырок 1–2 оборота (угол облика и наклон Visual), billboard спрайта выключен в
## полёте и включён после, тело включено и на fly/down/getup (лёжа — капсула вдоль земли), приземление на y = 0,
## пыль и звуки «вжух»/«пуф»
## (played["knock"], ["knock_thud"]), снежинки кружат над головой лежащего, getup с репликой HIT, обратно на маршрут
## и дальше по нему; траектория не входит в коробки Layout.all_solids() (в том числе наезд к стене дома — полёт
## укорочен) и flight_distance режет луч перед коробкой; на 2 м/с — прежний отход (lada_bumps), без полёта; повторный
## KNOCK-02: один удар — один подлёт (машина на жителе 8 кадров подряд); повторный удар в полёте, лёжа, вставая и
## сразу после подъёма — новый подлёт; лежащего медленная «Лада» не проезжает насквозь — толкает и притормаживает;
## на 8 м/с сбивается житель в каждом состоянии: идёт, стоит, на занятии, сидит, курит, ждёт троллейбус, в LOD, на
## переходе, у двери троллейбуса (посадка), вышедший на B (у двери и на пути к «ГАСТРОНОМУ») — и потом продолжает своё;
## пара — сбит один, второй ждёт на месте и смотрит на него, после — прежний сдвиг пары; Бабка, продавщица, патрули — не
## Resident, Бабка от наезда не сдвигается и не сбивается; денег и состояния миссии сбивание не меняет;
## reset_positions() посреди полёта — все на стартах, облик и тело как до удара, счётчики с нуля.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/knock_test.gd
## Кадры: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/knock_test.gd -- --capture
##   → builds/screenshots/KNOCK-01/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const OUT := "res://builds/screenshots/KNOCK-01"

var failures: Array[String] = []
var checks := 0
var main: Node
var drv
var world: DemoWorld
var residents_node: Node
var residents: Array = []
var sound: Node
var capture := false
var _rects: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: knock test exceeded 900 simulated seconds")
		_finish(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	world = main.world
	if not check(world != null, "DemoWorld exists"):
		_finish()
		return
	residents_node = world.get_node_or_null("LevelGeometry/Residents")
	if not check(residents_node != null, "LevelGeometry/Residents attached"):
		_finish()
		return
	residents = residents_node.residents
	sound = world.get_node("SoundDirector")
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false   # «Лада» ездит где угодно — наблюдатели не мешают
	for spec in Layout.all_solids():
		var c: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		_rects.append([spec[0], Rect2(c - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)).grow(Resident.BODY_RADIUS)])
	world.enter_car()
	await drv.frames(5)
	_part_constants()
	_part_flight_distance()
	await _part_knock()
	await _part_slow()
	await _part_repeat()
	await _part_lying_push()
	await _part_states()
	await _part_trolley()
	await _part_wall()
	await _part_pair()
	await _part_not_residents()
	await _part_reset()
	_finish()

# --- 1. Константы ---

func _part_constants() -> void:
	print("--- constants ---")
	check(Resident.KNOCK_MIN_SPEED == 3.0, "knock threshold 3 m/s (%.1f)" % Resident.KNOCK_MIN_SPEED)
	check(Resident.KNOCK_FLY_MAX == 9.0, "flight speed capped at 9 m/s (%.1f)" % Resident.KNOCK_FLY_MAX)
	check(Resident.KNOCK_HEIGHT == Vector2(1.5, 3.0), "flight height 1.5–3 m by speed %s" % Resident.KNOCK_HEIGHT)
	check(Resident.KNOCK_DOWN_SECONDS.x >= 1.5 and Resident.KNOCK_DOWN_SECONDS.y <= 2.5, "lies 1.5–2.5 s %s" % Resident.KNOCK_DOWN_SECONDS)
	check(Resident.KNOCK_RISE_SECONDS == 0.8, "gets up in 0.8 s")
	check(Resident.KNOCK_REHIT_SECONDS > 0.0 and Resident.KNOCK_REHIT_SECONDS <= 0.3, "re-hit guard %.2f s (≤ 0.3: one hit — one flight)" % Resident.KNOCK_REHIT_SECONDS)
	check(Resident.KNOCK_TURNS.x >= 1.0 and Resident.KNOCK_TURNS.y + 0.25 <= 2.0, "1–2 turns in flight %s (+¼ to lie down)" % Resident.KNOCK_TURNS)

# --- 2. flight_distance режет луч перед коробкой ---

func _part_flight_distance() -> void:
	print("--- flight_distance ---")
	# H1_South: x −90…10, z 108…122. Из (−20, 103,4) на север 9 м — упрётся в стену.
	var from := Vector3(-20.0, 0.0, 103.4)
	var cut := Resident.flight_distance(from, Vector3(0, 0, 1), 9.0)
	var wall := 108.0 - Resident.BODY_RADIUS - Resident.KNOCK_SOLID_PAD
	check(cut < wall - from.z and cut > wall - from.z - 0.2, "flight toward H1 cut before the wall (%.2f m, wall pad at %.2f m)" % [cut, wall - from.z])
	check(is_equal_approx(Resident.flight_distance(from, Vector3(1, 0, 0), 5.0), 5.0), "open flight along the yard not cut")
	check(not Resident.segment_clear(from, Vector3(-20, 0, 112)) and Resident.segment_clear(from, Vector3(-16, 0, 103.4)), "segment_clear: through the house — no, along the yard — yes")

# --- 3. Наезд на 5 м/с: полёт, кувырок, лежит, встаёт, реплика, обратно на маршрут ---

func _part_knock() -> void:
	print("--- knock at 5 m/s ---")
	residents_node.reset_positions()
	var r: Resident = residents[3]   # улица A, северный тротуар z 20,6, идёт на запад от x = 48
	await _wait_until(func(): return r.global_position.x < 38.0 and r.state == &"walk", 30 * 60)
	var money: int = world.mission.money
	var mission_state = world.mission.state
	var played: int = sound.played["knock"]
	var thuds: int = sound.played["knock_thud"]
	var dir := Vector3(-1, 0, 0)
	var hit := await _ram(r, dir, 5.0)
	var lines := r.bubble_log.size()   # PASS при подъезде «Лады» — до удара
	check(hit >= 0 and r.state == &"knocked" and r.knock_phase == &"fly", "Lada at 5 m/s knocks %s (state %s, phase %s, after %d frames)" % [r.name, r.state, r.knock_phase, hit])
	check(r.knocks == 1 and residents_node.knocks() == 1, "knock counted (%d, total %d)" % [r.knocks, residents_node.knocks()])
	check(r.knock_car_speed > 4.8 and r.knock_car_speed < 5.1, "car speed at the hit %.2f m/s" % r.knock_car_speed)
	check(r.body.collision_layer == Resident.BODY_LAYER, "body on in flight (KNOCK-02)")
	var sprite := r._look_sprite()
	if sprite:
		check(sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED and r._look().look_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "sprite billboard off in flight")
	await _shot("01_impact")
	_stop_car()
	await physics_frame
	check(sound.played["knock"] == played + 1, "whoosh at take-off (played[knock] %d → %d)" % [played, sound.played["knock"]])
	var from := r.knock_from
	var peak := 0.0
	var max_roll := 0.0
	var min_up := 1.0
	var inside := []
	var layers_ok := true
	var lying_ok := true
	var shot_fly := false
	var down_at := -1.0
	var down_frame := -1
	var getup_frame := -1
	var getup_at := -1.0
	var back_at := -1.0
	var route_at := -1.0
	var land_y := INF
	var dust := false
	var stars_seen := false
	var stars_moved := false
	var stars_above := true
	var star_before := Vector3.INF
	var hit_line := false
	var t := 0.0
	var phases := []
	for frame in 20 * 60:
		await physics_frame
		t += 1.0 / 60.0
		if phases.is_empty() or phases[-1] != r.knock_phase:
			phases.append(r.knock_phase)
		match r.knock_phase:
			&"fly":
				peak = maxf(peak, r.global_position.y)
				max_roll = maxf(max_roll, absf(r.knock_roll))
				min_up = minf(min_up, r.visual.global_basis.y.normalized().dot(Vector3.UP))
				for e in _rects:
					if e[1].has_point(Vector2(r.global_position.x, r.global_position.z)):
						inside.append(e[0])
				if not shot_fly and r._knock_t > r._knock_time * 0.45:
					shot_fly = true
					await _shot("02_flight")
			&"down":
				if down_at < 0.0:
					down_at = t
					down_frame = frame
					if capture:   # кадры лежит/встаёт — камерой пешехода сбоку, «Лада» не заслоняет
						world.camera_rig.yaw = world.car.rotation.y + 0.6
						world.camera_rig.follow(r, &"on_foot", true)
					land_y = r.global_position.y
					dust = r.knock_dust != null and r.knock_dust.emitting
				if r._knock_stars and r._knock_stars.visible:
					stars_seen = true
					var p: Vector3 = r._knock_stars.get_child(0).global_position
					if star_before != Vector3.INF and p.distance_to(star_before) > 0.001:
						stars_moved = true
					star_before = p
					stars_above = stars_above and p.y > r._knock_center + 0.15
				if frame - down_frame == 48:
					await _shot("03_down_stars")
			&"getup":
				if getup_at < 0.0:
					getup_at = t
					getup_frame = frame
					hit_line = r.bubble_kind == &"hit" and r.bubble_visible() and QuestLines.street_lines(r.voice, &"hit").has(r.bubble_text)
				if frame - getup_frame == 30:
					await _shot("04_getup_line")
					if capture:
						world.camera_rig.yaw = world.car.rotation.y
						world.camera_rig.follow(world.car, &"in_car", true)
			&"back":
				if back_at < 0.0:
					back_at = t
			&"":
				route_at = t
				break
		if r.knock_phase in Resident.KNOCK_PHASES:
			layers_ok = layers_ok and r.body.collision_layer == Resident.BODY_LAYER
		if r.knock_phase == &"down":
			lying_ok = lying_ok and absf(r.body.get_child(0).transform.basis.y.normalized().dot(Vector3.UP)) < 0.01
	print("INFO: phases %s, peak %.2f m, distance %.2f m, roll %.2f rad, down %.2f s, getup %.2f s, back %.2f s" % [phases, peak,
		Vector2(r.knock_to.x - from.x, r.knock_to.z - from.z).length(), max_roll, getup_at - down_at, back_at - getup_at, route_at - back_at])
	check(phases == [&"fly", &"down", &"getup", &"back", &""], "phases fly → down → getup → back → route (%s)" % [phases])
	check(peak >= 1.5 and peak <= 3.0, "flies up %.2f m (1.5–3)" % peak)
	var far := Vector2(r.knock_to.x - from.x, r.knock_to.z - from.z)
	check(far.length() >= 3.0, "flies %.2f m away (≥ 3)" % far.length())
	check(far.normalized().dot(Vector2(dir.x, dir.z)) > 0.9, "flies the way the Lada drove (dot %.2f)" % far.normalized().dot(Vector2(dir.x, dir.z)))
	check(max_roll >= TAU * 1.25 - 0.01 and max_roll <= TAU * 2.0 + 0.01, "tumbles %.2f turns in flight (1–2, ends lying)" % (max_roll / TAU))
	check(min_up < 0.0, "the look itself turns over (min up·UP %.2f)" % min_up)
	check(inside.is_empty(), "trajectory stays out of all_solids() boxes %s" % [inside.slice(0, 4)])
	check(land_y == 0.0, "lands on y = 0 (%.4f)" % land_y)
	check(dust, "snow dust puff on landing")
	check(sound.played["knock_thud"] == thuds + 1, "thud on landing (played[knock_thud] %d → %d)" % [thuds, sound.played["knock_thud"]])
	check(getup_at - down_at >= 1.5 - 0.02 and getup_at - down_at <= 2.5 + 0.02, "lies %.2f s (1.5–2.5)" % (getup_at - down_at))
	check(stars_seen and stars_moved and stars_above and r._knock_stars.get_child_count() == Resident.KNOCK_STARS, "snowflakes circle above the head while lying (seen %s, moved %s, above %s)" % [stars_seen, stars_moved, stars_above])
	check(absf(back_at - getup_at - Resident.KNOCK_RISE_SECONDS - Resident.KNOCK_SHAKE_SECONDS) < 0.05, "gets up 0.8 s and shakes off (%.2f s)" % (back_at - getup_at))
	check(hit_line, "says a HIT line getting up ('%s')" % r.bubble_text)
	check(r.bubble_log.size() == lines + 1 and r.bubble_log[-1][1] == &"hit", "one bubble per knock, HIT")
	check(layers_ok and r.body.collision_layer == Resident.BODY_LAYER, "body on while flying, lying and getting up, and after")
	check(lying_ok and r.body.get_child(0).transform.basis.y.dot(Vector3.UP) > 0.999, "lying — capsule along the ground; upright again after")
	check(not r._knock_stars.visible and not r._knock_shadow.visible, "snowflakes and flight shadow gone")
	if sprite:
		check(sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and r._look().look_material.billboard_mode == BaseMaterial3D.BILLBOARD_FIXED_Y and sprite.rotation == Vector3.ZERO, "sprite billboard back to fixed-Y")
	check(r.visual.basis.y.normalized().dot(Vector3.UP) > 0.999, "look upright again")
	var off := _route_distance(r)
	check(route_at > 0.0 and r.state == &"walk" and off < 0.01, "back on the route, walking (%.3f m off, %.1f s)" % [off, route_at - back_at])
	check(not r._lada_touches(r.global_position, 0.0), "back on a point clear of the stopped Lada")
	var walked := r.distance_walked
	await drv.frames(120)
	check(r.distance_walked > walked + 2.0 and _route_distance(r) < 0.01, "walks on along the route (%.1f m in 2 s)" % (r.distance_walked - walked))
	check(world.mission.money == money and world.mission.state == mission_state, "no money, score or mission change (money %d, state %s)" % [world.mission.money, world.mission.state])
	_park()

# --- 4. На 2 м/с — прежний отход, без полёта ---

func _part_slow() -> void:
	print("--- 2 m/s: step aside ---")
	residents_node.reset_positions()
	var r: Resident = residents[3]
	await _wait_until(func(): return r.global_position.x < 40.0 and r.state == &"walk", 30 * 60)
	var bumps := r.lada_bumps
	var touched := await _ram(r, Vector3(-1, 0, 0), 2.0, 180, func(): return r.lada_bumps > bumps)
	check(touched >= 0 and r.lada_bumps == bumps + 1, "Lada at 2 m/s: %s steps aside (bumps %d → %d)" % [r.name, bumps, r.lada_bumps])
	check(r.knocks == 0 and r.state != &"knocked" and r.global_position.y == 0.0, "no flight at 2 m/s (knocks %d, state %s)" % [r.knocks, r.state])
	_park()

# --- 5. KNOCK-02: один удар — один подлёт; снова сбит в полёте, лёжа, вставая и сразу после ---

func _part_repeat() -> void:
	print("--- repeat hits (KNOCK-02) ---")
	residents_node.reset_positions()
	var r: Resident = residents[4]   # улица A, южный тротуар z 43,3, идёт на восток от x = 44
	await _wait_until(func(): return r.global_position.x > 47.0, 10 * 60)
	var dir := Vector3(1, 0, 0)
	check(await _ram(r, dir, 5.0) >= 0 and r.knocks == 1, "first knock (%d)" % r.knocks)
	await _run_over(r, dir, 5.0, 8)   # 0,13 с машина на нём — тот же удар
	check(r.knocks == 1, "one hit — one flight: car on him for 8 frames, knocks %d" % r.knocks)
	_park()
	var n := 1
	for phase in [&"fly", &"down", &"getup", &"back"]:
		if phase == &"fly":   # снижается ниже крыши «Лады»
			await _wait_until(func(): return r.knock_phase == &"fly" and r._knock_t > r._knock_time * 0.6 and r.global_position.y < 1.2, 6 * 60)
		else:
			await _wait_until(func(): return r.knock_phase == phase, 8 * 60)
		var y0 := r.global_position.y
		var was := r.knock_phase
		var ok := await _strike(r, 8.0)
		_park()
		n += 1
		check(ok and r.knocks == n and r.knock_phase == &"fly", "hit again while %s (%.2f m up) — new flight (knocks %d, phase %s)" % [was, y0, r.knocks, r.knock_phase])
		var peak := 0.0
		var inside := []
		while r.knock_phase == &"fly":
			await physics_frame
			peak = maxf(peak, r.global_position.y)
			for e in _rects:
				if e[1].has_point(Vector2(r.global_position.x, r.global_position.z)):
					inside.append(e[0])
		check(peak >= y0 + Resident.KNOCK_REHIT_POP * 0.9 and peak <= Resident.KNOCK_HEIGHT.y + 0.01 and r.global_position.y == 0.0 and inside.is_empty(),
			"…flies up to %.2f m, lands on the ground, no box on the way %s" % [peak, inside.slice(0, 3)])
	await _wait_until(func(): return r.knock_phase == &"", 60 * 60)   # пять полётов унесли его на ~40 м — идёт назад
	check(r.state != &"knocked" and r.body.collision_layer == Resident.BODY_LAYER, "after the series — up and on the way (%s)" % r.state)
	_park()

# --- 5b. KNOCK-02: лежащего «Лада» не проезжает насквозь — толкает бампером, притормаживает, не застревает ---

func _part_lying_push() -> void:
	print("--- lying: no pass-through (KNOCK-02) ---")
	residents_node.reset_positions()
	var r: Resident = residents[3]
	await _wait_until(func(): return r.global_position.x < 38.0 and r.state == &"walk", 30 * 60)
	var dir := Vector3(-1, 0, 0)
	check(await _ram(r, dir, 5.0) >= 0, "knocked %s" % r.name)
	_park()
	await _wait_until(func(): return r.knock_phase == &"down", 4 * 60)
	var lie := _flat3(r.global_position)
	var car: Lada = world.car
	car.reset_to(lie - dir * (Lada.SIZE.z * 0.5 + Resident.KNOCK_LIE_RADIUS + 0.8), atan2(-dir.x, -dir.z))
	var pushes := r.car_pushes
	var overlap := 0
	var slowed := false
	var frames := 0
	var phases := {}
	while r.knock_phase in [&"down", &"getup"] and frames < 4 * 60:
		car.velocity = dir * 2.0
		await physics_frame
		frames += 1
		phases[r.knock_phase] = true
		var local := car.global_transform.affine_inverse() * Vector3(r.global_position.x, car.global_position.y, r.global_position.z)
		if absf(local.x) < Lada.SIZE.x * 0.5 + Resident.BODY_RADIUS and absf(local.z) < Lada.SIZE.z * 0.5 + Resident.BODY_RADIUS:
			overlap += 1
		if r.car_pushes > pushes and Vector2(car.velocity.x, car.velocity.z).length() < 1.98:
			slowed = true
	var moved := _flat(r.global_position).distance_to(_flat(lie))
	print("INFO: pushed %d frames, moved %.2f m, phases %s" % [r.car_pushes - pushes, moved, phases.keys()])
	check(r.car_pushes > pushes and moved > 1.0 and phases.has(&"down") and phases.has(&"getup"), "Lada at 2 m/s pushes the lying and getting-up %s ahead (%.2f m)" % [r.name, moved])
	check(overlap == 0, "never drives through him (%d frames inside the car)" % overlap)
	check(slowed, "the car loses speed against him")
	check(r.knocks == 1, "slow push does not launch him (knocks %d)" % r.knocks)
	var at := car.global_position
	for frame in 30:
		car.velocity = -dir * 3.0
		await physics_frame
	check(car.global_position.distance_to(at) > 1.0, "car backs off freely (%.2f m) — not stuck" % car.global_position.distance_to(at))
	_park()
	await _wait_until(func(): return r.knock_phase == &"", 20 * 60)
	check(r.state != &"knocked", "%s back on the way after the push (%s)" % [r.name, r.state])

# --- 5c. KNOCK-02: сбивается в любом состоянии и потом продолжает своё ---

func _part_states() -> void:
	print("--- every state (KNOCK-02) ---")
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	residents_node.reset_positions()
	_park()
	var kinds := {
		"standing at an activity": func(x: Resident): return x.state == &"activity" and x._act_sit == 0.0 and x.global_position.y < 0.1,
		"sitting": func(x: Resident): return x.state == &"activity" and x._act_sit != 0.0 and x._acting,
		"smoking": func(x: Resident): return x.state == &"smoke",
		"waiting for the trolleybus": func(x: Resident): return x.state == &"wait_trolley",
		"in LOD far away": func(x: Resident): return x._lod_n > 0 and x.state in [&"walk", &"activity", &"smoke", &"wait_trolley", &"pause"] and x.global_position.y < 0.1,
		"on a crossing": func(x: Resident): return x.state == &"walk" and x.leader == null and x.on_crossing() and x.target_point >= 1 \
			and _flat(x.global_position).distance_to(_flat(x.route[x.target_point - 1])) > 1.5 and _flat(x.global_position).distance_to(_flat(x.route[x.target_point])) > 1.5,
	}
	for label in kinds:
		var pick: Callable = kinds[label]
		var found: Resident = null
		for frame in 240 * 60:
			for x: Resident in residents:
				if not x.hidden and x.state != &"knocked" and x.knock_phase == &"" and pick.call(x):
					found = x
					break
			if found:
				break
			await physics_frame
		if not check(found != null, "found a resident %s" % label):
			continue
		var was := found.state
		var spot := found.spot_id
		var ok := await _strike(found, 8.0)
		_park()
		check(ok and found.state == &"knocked" and found.knock_phase == &"fly", "Lada at 8 m/s knocks %s %s (was %s)" % [found.name, label, was])
		await _wait_until(func(): return found.knock_phase == &"", 20 * 60)
		check(found.state != &"knocked" and found.spot_id == spot, "…gets up and keeps the goal %s (%s, %s)" % [spot, found.spot_id, found.state])

# --- 5d. KNOCK-02: троллейбус — у двери на посадке, вышедший на B у двери и по пути в «ГАСТРОНОМ» ---

func _part_trolley() -> void:
	print("--- trolleybus passengers (KNOCK-02) ---")
	var traffic: Node = world.get_node_or_null("LevelGeometry/Traffic")
	var bus: Trolleybus = traffic.trolleybus if traffic else null
	if not check(bus != null, "trolleybus 13 exists"):
		return
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	residents_node.reset_positions()
	traffic.reset_positions()
	_park()
	await drv.frames(2)
	var life = residents_node.life
	var r: Resident = residents[25]   # LIFE-02: прохожий улиц, не в паре
	# Едет: троллейбус у остановки B открывает двери — выходит из передней двери.
	life.release(r.spot_id, r)
	r._act_stop()
	r._hide(&"ride")
	bus.setup(bus.path, bus.stop_offsets[1] - 0.05)
	bus.next_stop = 1
	bus.dwell_left = 0.0
	var out := await _wait_until(func(): return r.state == &"alight" and not r.hidden, 10 * 60)
	if not check(out >= 0, "%s steps out at stop B (%s)" % [r.name, r.state]):
		return
	check(r.body.collision_layer == 0, "at the door on B the body is off as before (KIOSK_ZONE)")
	# у самой двери, троллейбус ещё стоит: «Лада» вдоль борта
	var fwd := -_flat3(bus.global_basis.z).normalized()
	var side := _flat3(bus.global_basis.x).normalized()
	var at := _flat3(r.global_position)
	var car: Lada = world.car
	car.reset_to(at + side * 1.1 - fwd * (Lada.SIZE.z * 0.5 + 1.2), atan2(-fwd.x, -fwd.z))
	var hit := -1
	for frame in 60:
		car.velocity = fwd * 8.0
		await physics_frame
		if r.state == &"knocked":
			hit = frame
			break
	_park()
	check(hit >= 0 and bus.doors_open, "Lada at 8 m/s along the trolleybus knocks %s right at the door on B (frame %d, doors open %s)" % [r.name, hit, bus.doors_open])
	await _wait_until(func(): return r.knock_phase == &"", 20 * 60)
	check(r.state in [&"alight", &"transit"], "…gets up and goes on from the door (%s)" % r.state)
	await _wait_until(func(): return r.state == &"transit" and r._transit_i >= 1 and r._transit_i < r._transit.size(), 30 * 60)
	await drv.frames(30)
	var on_way := r.state == &"transit"
	var ok := on_way and await _strike(r, 8.0)
	_park()
	check(ok and r.state == &"knocked", "knocked on the way from stop B to the shop (was transit %s)" % on_way)
	await _wait_until(func(): return r.knock_phase == &"", 20 * 60)
	check(r.state == &"transit", "…gets up and walks on to the shop (%s)" % r.state)
	var inside := await _wait_until(func(): return r.hidden and r.state == &"inside", 90 * 60)
	check(inside >= 0 and r.spot_id == &"gastro", "…and goes into the shop (%s, %s)" % [r.state, r.spot_id])
	# Посадка на A: ждёт на остановке, троллейбус открывает двери, по пути к двери — удар.
	residents_node.reset_positions()
	traffic.reset_positions()
	await drv.frames(2)
	var q: Resident = residents[26]
	life.release(q.spot_id, q)
	q._act_stop()
	q.spot_id = &"stop_a2"
	life.reserve(&"stop_a2", q)
	q._arrive()
	check(q.state == &"wait_trolley", "%s waits at stop A (%s)" % [q.name, q.state])
	bus.setup(bus.path, bus.stop_offsets[0] - 0.05)
	bus.next_stop = 0
	bus.dwell_left = 0.0
	var boarding := await _wait_until(func(): return q.state == &"board", 10 * 60)
	if not check(boarding >= 0, "%s walks to the door (%s)" % [q.name, q.state]):
		return
	await drv.frames(20)
	ok = q.state == &"board" and await _strike(q, 8.0)
	_park()
	check(ok and q.state == &"knocked", "knocked on the way to the trolleybus door")
	var boards := q.events.filter(func(e): return e[1] == &"board").size()
	var sneaked := false
	for frame in 40 * 60:
		await physics_frame
		# сел в салон — только пока троллейбус у остановки A с открытыми дверями (или в шаг их закрытия)
		if q.events.filter(func(e): return e[1] == &"board").size() > boards:
			boards += 1
			if _flat(bus.global_position).distance_to(_flat(Layout.TROLLEY_STOPS[0])) > 3.0:
				sneaked = true
		if q.knock_phase == &"" and frame > 60 and (q.hidden or q.state in [&"wait_trolley", &"walk", &"board"]):
			break
	check(not sneaked and q.state != &"knocked", "…then boards if the doors are still open, else back to the stop (%s, hidden %s)" % [q.state, q.hidden])
	residents_node.reset_positions()
	traffic.reset_positions()

# --- 6. К стене дома: полёт укорочен, обратно на точку удара ---

func _part_wall() -> void:
	print("--- toward a wall ---")
	residents_node.reset_positions()
	var r: Resident = residents[0]   # двор, z 103,4 вдоль H1 (стена z = 108)
	await _wait_until(func(): return r.global_position.x > -24.0 and r.global_position.x < -16.0 and r.state == &"walk", 40 * 60)
	var dir := Vector3(0, 0, 1)
	check(await _ram(r, dir, 8.0) >= 0, "Lada at 8 m/s toward the house knocks %s" % r.name)
	world.car.reset_to(world.car.global_position - dir * 6.0, world.car.rotation.y)   # отъехала: точка удара свободна
	var uncut := minf(Resident.KNOCK_FLY_BASE + Resident.KNOCK_FLY_GAIN * r.knock_car_speed, Resident.KNOCK_FLY_MAX) * r._knock_time
	var inside := []
	var peak := 0.0
	while r.knock_phase == &"fly":
		await physics_frame
		peak = maxf(peak, r.global_position.y)
		for e in _rects:
			if e[1].has_point(Vector2(r.global_position.x, r.global_position.z)):
				inside.append(e[0])
	var dist := Vector2(r.knock_to.x - r.knock_from.x, r.knock_to.z - r.knock_from.z).length()
	check(dist < uncut - 1.0 and r.knock_to.z < 108.0 - Resident.BODY_RADIUS, "flight cut before the wall (%.2f of %.2f m, lands z %.2f)" % [dist, uncut, r.knock_to.z])
	check(peak > 2.0 and peak <= 3.0, "faster car — higher (%.2f m at %.1f m/s)" % [peak, r.knock_car_speed])
	check(inside.is_empty(), "no box on the way %s" % [inside.slice(0, 4)])
	await _wait_until(func(): return r.knock_phase == &"", 20 * 60)
	check(_flat(r.global_position).distance_to(_flat(r.knock_from)) < 0.01 and r.state == &"walk", "walked back to the hit point (%.3f m)" % _flat(r.global_position).distance_to(_flat(r.knock_from)))
	_park()

# --- 7. Пара: сбит один, второй ждёт ---

func _part_pair() -> void:
	print("--- pair ---")
	residents_node.reset_positions()
	var lead: Resident = residents[6]
	var second: Resident = lead.follower
	if not check(second != null, "resident 6 leads a pair"):
		return
	await drv.frames(90)
	var dir3 := _flat3(lead.route[lead.target_point]) - _flat3(lead.global_position)
	var dir := dir3.normalized()
	var behind: Resident = second if second.global_position.dot(dir) < lead.global_position.dot(dir) else lead
	var other: Resident = lead if behind == second else second
	var hit := await _ram(behind, dir, 5.0)
	_park()
	check(hit >= 0 and behind.state == &"knocked" and other.state != &"knocked", "only %s knocked (other %s)" % [behind.name, other.state])
	var held := _flat(other.global_position)
	var still := true
	var looked := false
	while behind.knock_phase != &"":
		await physics_frame
		still = still and _flat(other.global_position).distance_to(held) < 0.01
		looked = looked or other._look_target == behind
	check(still, "%s waits on the spot" % other.name)
	check(looked, "%s looks at the knocked partner" % other.name)
	await drv.frames(2)
	var gap := _flat(second.global_position) - _flat(lead.global_position)
	check(gap.distance_to(Vector2(second.follow_offset.x, second.follow_offset.z)) < 0.02, "pair offset restored (%s vs %s)" % [gap, second.follow_offset])
	var walked := lead.distance_walked
	var seen := []
	for frame in 240:
		await physics_frame
		if seen.is_empty() or seen[-1] != lead.state:
			seen.append(lead.state)
	print("INFO: pair leader states after the return %s" % [seen])
	check(lead.distance_walked > walked + 1.5 and lead.state != &"knocked" and second.state == lead.state, "the pair walks on (%.1f m)" % (lead.distance_walked - walked) + " in 4 s")

# --- 8. Не жители: Бабка, продавщица, патрули ---

func _part_not_residents() -> void:
	print("--- not residents ---")
	var others: Array = [world.babka, world.vendor]
	var patrols := world.get_node_or_null("LevelGeometry/Patrols")
	if patrols:
		for n in patrols.get_children():
			if n is Node3D:
				others.append(n)
	var bad := []
	for n in others:
		if n is Resident or n.get("knocks") != null:
			bad.append(n.name)
	check(others.size() >= 4 and bad.is_empty(), "Babka, vendor and patrols are not Residents (%d, bad %s)" % [others.size(), bad])
	var babka: Node3D = world.babka
	var at := babka.global_position
	var total: int = residents_node.knocks()
	var dir := Vector3(0, 0, 1)
	world.car.reset_to(at - dir * (Lada.SIZE.z * 0.5 + 1.5), atan2(-dir.x, -dir.z))
	for frame in 90:
		world.car.velocity = dir * 5.0
		await physics_frame
	check(babka.global_position.distance_to(at) < 0.001, "Babka not moved by the Lada at 5 m/s")
	check(residents_node.knocks() == total, "nobody knocked at Babka (%d)" % residents_node.knocks())
	_park()

# --- 9. reset_positions() посреди полёта ---

func _part_reset() -> void:
	print("--- reset mid-flight ---")
	residents_node.reset_positions()
	var r: Resident = residents[3]
	await _wait_until(func(): return r.global_position.x < 40.0 and r.state == &"walk", 30 * 60)
	await _ram(r, Vector3(-1, 0, 0), 6.0)
	_park()
	await drv.frames(20)
	check(r.knock_phase == &"fly" and r.global_position.y > 0.3, "in flight before reset (%.2f m)" % r.global_position.y)
	residents_node.reset_positions()
	var worst := 0.0
	var ok := true
	for x: Resident in residents:
		var start: Vector3 = Layout.RESIDENT_ROUTES[x.index][Layout.RESIDENT_STARTS[x.index]]
		worst = maxf(worst, x.global_position.distance_to(Vector3(start.x, 0.0, start.z)))
		ok = ok and x.knock_phase == &"" and x.knocks == 0 and x.state != &"knocked" and x.body.collision_layer == Resident.BODY_LAYER
	check(worst < 0.001, "reset_positions(): everyone on the start, on the ground (worst %.4f m)" % worst)
	check(ok and residents_node.knocks() == 0, "reset_positions(): no knock state, counters zero, bodies on")
	await process_frame
	await process_frame
	var sprite := r._look_sprite()
	if sprite:
		check(sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and sprite.rotation == Vector3.ZERO, "reset: sprite billboard back")
	check(r.visual.basis.y.normalized().dot(Vector3.UP) > 0.999 and not r._knock_shadow.visible, "reset: look upright, flight shadow off")

# =====================================================================================
# Служебное
# =====================================================================================

## Разогнать «Ладу» на житель сзади по dir со скоростью speed: до сбивания (или until), кадров до события или −1.
func _ram(r: Resident, dir: Vector3, speed: float, max_frames := 120, until := Callable()) -> int:
	var at := _flat3(r.global_position)
	world.car.reset_to(at - dir * (Lada.SIZE.z * 0.5 + 1.2), atan2(-dir.x, -dir.z))
	world.camera_rig.yaw = world.car.rotation.y
	world.camera_rig.snap()
	var knocks := r.knocks
	for i in max_frames:
		world.car.velocity = dir * speed
		await physics_frame
		if (until.is_valid() and until.call()) or (not until.is_valid() and r.knocks > knocks):
			return i
	return -1

## Проехать по жителю frames кадров (машина ставится на него каждый кадр, скорость speed).
func _run_over(r: Resident, dir: Vector3, speed: float, frames: int) -> void:
	for i in frames:
		world.car.reset_to(_flat3(r.global_position), atan2(-dir.x, -dir.z))
		world.car.velocity = dir * speed
		await physics_frame

## KNOCK-02: «Лада» вплотную к облику жителя (у сидящего — на сиденье) со свободной стороны — без коробок
## all_solids() и целых разрушаемых под габаритом — едет на него со скоростью speed; true — сбит.
func _strike(r: Resident, speed: float, frames := 6) -> bool:
	var dir := _clear_dir(r._hit_point())
	var knocks := r.knocks
	for i in frames:
		var at := r._hit_point()
		world.car.reset_to(at - dir * (Lada.SIZE.z * 0.5 + 0.3), atan2(-dir.x, -dir.z))
		world.car.velocity = dir * speed
		await physics_frame
		if r.knocks > knocks:
			return true
	return false

## Направление удара в точку hit, при котором габарит «Лады» перед ней не задевает коробок и разрушаемых.
func _clear_dir(hit: Vector3) -> Vector3:
	var boxes: Array = []
	for e in _rects:
		boxes.append(e[1].grow(-Resident.BODY_RADIUS))
	boxes.append_array(Breakables.intact_rects(0.05))
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var center := hit - dir * (Lada.SIZE.z * 0.5 + 0.3)
		var clear := true
		for u in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			for w in [-0.5, 0.0, 0.5]:
				var p: Vector3 = center + dir * Lada.SIZE.z * u + side * Lada.SIZE.x * w
				for rect: Rect2 in boxes:
					if rect.has_point(Vector2(p.x, p.z)):
						clear = false
		if clear:
			return dir
	return Vector3(1, 0, 0)

## Остановить «Ладу» на месте.
func _stop_car() -> void:
	world.car.reset_to(world.car.global_position, world.car.rotation.y)

## Отогнать «Ладу» на стоянку во дворе.
func _park() -> void:
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)

func _route_distance(r: Resident) -> float:
	var best := INF
	var q := _flat(r.global_position)
	for i in r.route.size():
		var a := _flat(r.route[i])
		var b := _flat(r.route[(i + 1) % r.route.size()])
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best

func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

func _flat3(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

func _wait_until(condition: Callable, max_frames: int) -> int:
	for i in max_frames:
		if condition.call():
			return i
		await physics_frame
	return -1

func _shot(label: String) -> void:
	if not capture:
		return
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + "/" + label + ".png"))
	print("SHOT: ", label)

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		print("FAIL: ", label)
	return condition

func _finish(code := -1) -> void:
	print("KNOCK: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

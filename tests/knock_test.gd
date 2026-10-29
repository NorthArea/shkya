extends SceneTree
## KNOCK-01: сбивание жителей «Ладой» без вреда на настоящей сцене main.tscn (набор KNOCK).
## Проверки: константы (порог 3 м/с, потолок полёта 9 м/с, высота 1,5–3 м, лежит 1,5–2,5 с, встаёт 0,8 с, 3 с
## неуязвимости); наезд на 5 м/с — state knocked, фазы fly → down → getup → back → маршрут, взлёт ≥ 1,5 м и ≤ 3 м,
## дальность ≥ 3 м по ходу машины, кувырок 1–2 оборота (угол облика и наклон Visual), billboard спрайта выключен в
## полёте и включён после, тело выключено на fly/down/getup, приземление на y = 0, пыль и звуки «вжух»/«пуф»
## (played["knock"], ["knock_thud"]), снежинки кружат над головой лежащего, getup с репликой HIT, обратно на маршрут
## и дальше по нему; траектория не входит в коробки Layout.all_solids() (в том числе наезд к стене дома — полёт
## укорочен) и flight_distance режет луч перед коробкой; на 2 м/с — прежний отход (lada_bumps), без полёта; повторный
## наезд в полёте, лёжа и вставая — без эффекта, сразу после getup — тоже (неуязвимость), через 3 с — снова сбивает;
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
	check(Resident.KNOCK_IMMUNE_SECONDS == 3.0, "3 s immunity after getup")
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
	check(r.body.collision_layer == 0, "body off in flight")
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
					hit_line = r.bubble_kind == &"hit" and r.bubble_visible() and QuestLines.RESIDENT_LINES_HIT.has(r.bubble_text)
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
			layers_ok = layers_ok and r.body.collision_layer == 0
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
	check(layers_ok and r.body.collision_layer == Resident.BODY_LAYER, "body off while flying, lying and getting up; back on after")
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

# --- 5. Повторный наезд в полёте, лёжа, вставая и сразу после — без эффекта; через 3 с — снова ---

func _part_repeat() -> void:
	print("--- repeat hits ---")
	residents_node.reset_positions()
	var r: Resident = residents[4]   # улица A, южный тротуар z 43,3, идёт на восток от x = 44
	await _wait_until(func(): return r.global_position.x > 47.0, 10 * 60)
	var dir := Vector3(1, 0, 0)
	check(await _ram(r, dir, 5.0) >= 0 and r.knocks == 1, "first knock (%d)" % r.knocks)
	_stop_car()
	var thuds: int = sound.played["knock_thud"]
	for phase in [&"fly", &"down", &"getup"]:
		await _wait_until(func(): return r.knock_phase == phase, 6 * 60)
		var before := r.knock_phase
		await _run_over(r, dir, 5.0, 8)
		check(r.knocks == 1 and r.knock_phase == before, "second hit while %s — no effect (knocks %d, phase %s)" % [phase, r.knocks, r.knock_phase])
		_park()
	await _wait_until(func(): return r.knock_phase == &"back", 4 * 60)
	await _run_over(r, dir, 5.0, 8)
	check(r.knocks == 1, "hit right after getting up — immune (knocks %d)" % r.knocks)
	_park()
	check(sound.played["knock_thud"] == thuds + 1, "one landing for one knock (%d → %d)" % [thuds, sound.played["knock_thud"]])
	await drv.frames(int(Resident.KNOCK_IMMUNE_SECONDS * 60) + 10)
	if r.state != &"walk":
		await _wait_until(func(): return r.state == &"walk", 20 * 60)
	var ahead := (_flat3(r.route[r.target_point]) - _flat3(r.global_position)).normalized()
	check(await _ram(r, ahead, 5.0) >= 0 and r.knocks == 2, "after 3 s — knocked again (%d)" % r.knocks)
	_stop_car()
	await _wait_until(func(): return r.knock_phase == &"", 20 * 60)
	check(r.state == &"walk" and _route_distance(r) < 0.01, "back on the route after the second knock")
	_park()

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

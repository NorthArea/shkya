extends SceneTree
## PUNCH-01: удар Илюши и мини-дроны ГСУМ на настоящей сцене main.tscn (набор PUNCH).
## Проверки: раскладка (6–8 дронов на 6–8 петлях, высота 1,6–2,2 м, петли не в коробках, не у стволов и столбов,
## не над проезжей частью, далеко от SPAWN и Бабки); коллизии — только Area3D слоя 16 (не тела, не сенсоры, лучи
## наблюдателя дроны не укрывают); полёт по петле 2–3 м/с; подлёт к Илюше ближе 6 м и зависание в 2 м перед ним на
## высоте лица на 5 с, затем отлёт и пауза; не подлетает к Илюше в укрытии и в машине; действие punch (F, ЛКМ,
## геймпад B); замах 0,35 с с рывком облика, кулдаун 0,5 с, звук взмаха; удар мимо и выше полосы — без цели; удар в
## укрытии и в машине не работает; удар по дрону — распад на 4–6 обломков (исчезают за 1,5 с), хлопок, 5 монет
## (Coins.spawn_burst, если узел Coins есть), возрождение через 60–90 с на другой петле; удар по полицейскому — субтитр
## не чаще раза в 20 с, без провала; по Бабке — ничего; узлы Илюши не меняются; цена кадра дронов.
## Детерминизм: фиксированные seed в Drones, --fixed-fps 60.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/punch_test.gd

const Layout = preload("res://game/world/layout.gd")
const DroneLayout = preload("res://game/world/drone_layout.gd")
const DronesScript = preload("res://game/world/drones.gd")
const DetectionSensorScript = preload("res://game/stealth/detection_sensor.gd")

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var drones: Node3D
var player: Ilyusha
var sound: Node
var coins: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: punch test exceeded 900 simulated seconds")
		_finish(2))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	if not check(world != null, "DemoWorld exists"):
		_finish()
		return
	drones = world.get_node_or_null("LevelGeometry/Drones")
	player = world.player
	sound = world.get_node("SoundDirector")
	coins = world.get_node_or_null("LevelGeometry/Coins")
	if not check(drones != null, "LevelGeometry/Drones attached"):
		_finish()
		return
	_sensors(false)   # наблюдатели не мешают: Илюша ходит у патруля и дорог
	var signature := _signature(player)
	_part_layout()
	_part_collisions()
	await _part_sight()
	await _part_patrol()
	_part_input_map()
	await _part_swing()
	await _part_hover()
	await _part_no_watch()
	await _part_blocked()
	await _part_miss()
	await _part_officer_and_babka()
	await _part_break_and_respawn()
	_part_cost()
	check(_signature(player) == signature, "Ilyusha's node tree is unchanged (nothing attached to him, DEMO invariant 3)")
	_finish()

# --- 1. Раскладка ---

func _part_layout() -> void:
	print("--- layout ---")
	var list: Array = drones.drones
	check(list.size() >= 6 and list.size() <= 8, "6–8 drones (%d)" % list.size())
	check(DroneLayout.LOOPS.size() >= 6 and DroneLayout.LOOPS.size() <= 8, "6–8 loops (%d)" % DroneLayout.LOOPS.size())
	check(DroneLayout.LOOPS.size() > list.size(), "free loops exist for respawn (%d loops, %d drones)" % [DroneLayout.LOOPS.size(), list.size()])
	var bad_height := []
	var bad_speed := []
	var bad_clear := []
	var trunks: Array[Vector2] = []
	trunks.append_array(Layout.TREES)
	trunks.append_array(Layout.POPLARS)
	trunks.append_array(Layout.street_lamps())
	trunks.append_array(Layout.trolley_poles())
	for sign in Layout.STREET_SIGNS:
		trunks.append(sign[0])
	var roads := []
	for s in Layout.SURFACES:
		if s[1] == "road":
			roads.append(Rect2(s[2] - s[3] * 0.5, s[3]))
	var solids: Array = Layout.all_solids()
	for li in DroneLayout.LOOPS.size():
		var spec: Array = DroneLayout.LOOPS[li]
		var h: float = spec[1]
		if h - DroneLayout.BOB < 1.6 or h + DroneLayout.BOB > 2.2:
			bad_height.append(li)
		var v: float = spec[2]
		if v < 2.0 or v > 3.0:
			bad_speed.append(li)
		var pts: Array = spec[0]
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var steps := maxi(1, int(a.distance_to(b) / 0.5))
			for k in steps + 1:
				var p := a.lerp(b, float(k) / float(steps))
				var why := ""
				for t: Vector2 in trunks:
					if p.distance_to(t) < 1.5:
						why = "trunk %s" % t
				for r: Rect2 in roads:
					if r.grow(-0.5).has_point(p):
						why = "road"
				for solid in solids:
					var c: Vector2 = solid[2]
					var size: Vector3 = solid[3]
					if size.y >= h - 0.3 and Rect2(c - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)).grow(0.5).has_point(p):
						why = "box %s" % solid[0]
				if p.distance_to(Vector2(Layout.SPAWN.x, Layout.SPAWN.z)) < 10.0 or p.distance_to(Vector2(Layout.BABKA.x, Layout.BABKA.z)) < 10.0:
					why = "near spawn/Babka"
				if why != "":
					bad_clear.append("%d %s: %s" % [li, p, why])
					break
	check(bad_height.is_empty(), "loop heights with bob within 1.6–2.2 m %s" % [bad_height])
	check(bad_speed.is_empty(), "loop speeds 2–3 m/s %s" % [bad_speed])
	check(bad_clear.is_empty(), "loops ≥ 1.5 m from trunks/poles, off the carriageway, outside boxes, ≥ 10 m from SPAWN and Babka %s" % [bad_clear.slice(0, 6)])
	var labels := 0
	for d in list:
		for l: Label3D in d.find_children("*", "Label3D", true, false):
			if l.text == "ГСУМ":
				labels += 1
	check(labels == list.size(), "each drone carries a small «ГСУМ» mark (%d)" % labels)

# --- 2. Коллизии, сенсоры, лучи ---

func _part_collisions() -> void:
	print("--- collisions ---")
	var objects := drones.find_children("*", "CollisionObject3D", true, false)
	var bad := []
	for o: CollisionObject3D in objects:
		if not o is Area3D or o.collision_layer != DronesScript.HIT_LAYER or o.collision_mask != 0 or (o as Area3D).monitoring:
			bad.append(String(o.name))
	check(objects.size() == drones.drones.size() and bad.is_empty(), "only one hit Area3D per drone, layer 16, mask 0, not monitoring (%d objects, bad %s)" % [objects.size(), bad])
	check(DronesScript.HIT_LAYER & (DetectionSensorScript.WORLD_MASK | DetectionSensorScript.SIGHT_CAR_MASK) == 0, "drone layer is outside the observers' sight mask")
	check(DronesScript.HIT_LAYER & world.camera_rig.arm.collision_mask == 0 and not world.camera_rig.arm.collide_with_areas if "collide_with_areas" in world.camera_rig.arm else DronesScript.HIT_LAYER & world.camera_rig.arm.collision_mask == 0, "camera spring arm ignores drones")
	check(DronesScript.HIT_LAYER & (player.collision_mask | world.car.collision_mask) == 0, "Ilyusha and the Lada do not collide with drones")
	var in_sensors := 0
	for s in get_nodes_in_group(&"detection_sensors"):
		if drones.is_ancestor_of(s):
			in_sensors += 1
	check(in_sensors == 0 and not drones.is_in_group(&"detection_sensors"), "drones are not stealth sensors")

## Дрон между глазом полицейского и Илюшей не укрывает его (луч World|Car, области не учитываются).
func _part_sight() -> void:
	print("--- drones do not block sight ---")
	var officer: Node3D = world.get_node("LevelGeometry/Patrols/Officer")
	var sensor: Node3D = officer.sensor
	drones.set_physics_process(false)
	sensor.enabled = true
	var forward := -sensor.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spot := officer.global_position + forward * 8.0
	player.place(spot, 0.0)
	await _frames(2)
	var clear: float = sensor._line_of_sight()
	var drone: Node3D = drones.drones[0]
	var keep := drone.global_position
	var eye := sensor.global_position + Vector3.UP * DetectionSensorScript.EYE_HEIGHT
	var target := player.global_position + Vector3.UP * DetectionSensorScript.TARGET_HEIGHT
	drone.global_position = eye.lerp(target, 0.5)
	await _frames(2)
	var with_drone: float = sensor._line_of_sight()
	check(clear > 0.0 and with_drone > 0.0, "a drone on the officer's sight line does not hide Ilyusha (%.1f → %.1f, blocker '%s')" % [clear, with_drone, sensor.last_blocker])
	drone.global_position = keep
	sensor.enabled = false
	drones.set_physics_process(true)
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _frames(2)

# --- 3. Полёт по петле ---

func _part_patrol() -> void:
	print("--- patrol ---")
	var list: Array = drones.drones
	var start := []
	for d in list:
		start.append(d.global_position)
	var low := INF
	var high := -INF
	var frames := 120
	var path := []
	for d in list:
		path.append(0.0)
	var last := start.duplicate()
	for f in frames:
		await physics_frame
		for i in list.size():
			var p: Vector3 = list[i].global_position
			path[i] += Vector2(p.x - last[i].x, p.z - last[i].z).length()
			last[i] = p
			low = minf(low, p.y)
			high = maxf(high, p.y)
	var bad := []
	for i in list.size():
		var d: Node3D = list[i]
		var speed: float = path[i] / (float(frames) / 60.0)
		var wanted: float = DroneLayout.LOOPS[d.loop][2]
		if d.state != &"patrol" or absf(speed - wanted) > 0.15:
			bad.append("%s %s %.2f/%.2f" % [d.name, d.state, speed, wanted])
	check(bad.is_empty(), "drones fly their loops at 2–3 m/s %s" % [bad])
	check(low >= 1.6 - 0.05 and high <= 2.2 + 0.05, "patrol height within 1.6–2.2 m (%.2f…%.2f)" % [low, high])

# --- 4. Управление ---

func _part_input_map() -> void:
	print("--- input map ---")
	var key := false
	var mouse := false
	var pad := false
	for e in InputMap.action_get_events(&"punch"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_F:
			key = true
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			mouse = true
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			pad = true
	check(key and mouse and pad, "punch: F, left mouse button, gamepad B (%s %s %s)" % [key, mouse, pad])
	var handbrake_b := false
	for e in InputMap.action_get_events(&"handbrake"):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			handbrake_b = true
	check(handbrake_b, "gamepad B stays the handbrake in the car")
	var hint := false
	for item in preload("res://game/ui/dialog_panel.gd").CONTROLS:
		if String(item[0]).contains("F") and String(item[1]).contains("удар"):
			hint = true
	check(hint, "controls line shows «F / ЛКМ — удар»")
	check(sound.DRONE_BUZZ.loop_mode == AudioStreamWAV.LOOP_FORWARD, "drone buzz loops")
	var buzzing := 0
	for d in drones.drones:
		var b: AudioStreamPlayer3D = sound.drone_buzz.get(d)
		if b and b.playing and b.max_distance <= 25.0:
			buzzing += 1
	check(buzzing == drones.drones.size(), "every flying drone buzzes in 3D, fading out by 22 m (%d)" % buzzing)

# --- 5. Замах, рывок, кулдаун, звук ---

func _part_swing() -> void:
	print("--- swing and cooldown ---")
	player.place(Vector3(-36.5, 0, 90.0), PI)   # двор, рядом никого: лицом на юг
	await _frames(3)
	var look: Node3D = player.visual.get_node("Look")
	var whoosh: int = sound.played["punch"]
	var punches := player.punches
	_press_key(KEY_F)
	await physics_frame
	check(player.punches == punches + 1 and player.is_punching(), "F starts a punch on foot")
	check(sound.played["punch"] == whoosh + 1 and sound.punch_player.stream == sound.PUNCH_WHOOSH, "punch whoosh sound")
	check(not player.punch(), "no second punch during the swing")
	var lunge := 0.0
	for f in 9:
		await physics_frame
		lunge = minf(lunge, look.position.z)
	check(lunge < -0.25, "Ilyusha's figure lunges forward on the swing (%.2f m)" % lunge)
	await _frames(13)   # 0,35 с от нажатия
	check(not player.is_punching(), "the swing lasts 0.35 s")
	check(not player.punch(), "cooldown: no punch at 0.38 s")
	await _frames(9)    # 0,53 с от нажатия
	check(absf(look.position.z) < 0.03, "the figure springs back after the swing (%.3f)" % look.position.z)
	check(player.punch(), "cooldown 0.5 s: punch again at 0.53 s")
	await _frames(40)
	var before := player.punches
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	Input.parse_input_event(b)
	await physics_frame
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_B
	rb.pressed = false
	Input.parse_input_event(rb)
	check(player.punches == before + 1, "gamepad B punches on foot")
	await _frames(40)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		Input.parse_input_event(click)
		await physics_frame
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		Input.parse_input_event(up)
		check(player.punches == before + 1, "left click with a free mouse only captures it (no punch)")
	await _frames(40)

# --- 6. Подлёт и зависание ---

func _part_hover() -> void:
	print("--- approach and hover ---")
	var d0: Node3D = drones.drones[0]   # петля 0 — двор, проезд
	var spot := Vector3(-16.0, 0, 85.0)
	player.place(spot, PI * 0.5)        # лицом на запад
	var engaged: Node3D = null
	for f in 600:
		await physics_frame
		for d in drones.drones:
			if d.state == &"approach" or d.state == &"hover":
				engaged = d
		if engaged:
			break
	check(engaged != null, "a drone flies up to Ilyusha within 6 m")
	if engaged == null:
		return
	var near := 0
	for d in drones.drones:
		if d.state == &"approach" or d.state == &"hover":
			near += 1
	check(near == 1, "only one drone watches at a time (%d)" % near)
	var waited := 0
	while engaged.state == &"approach" and waited < 300:
		await physics_frame
		waited += 1
	check(engaged.state == &"hover", "the drone hovers after the approach (%.1f s)" % (waited / 60.0))
	await _frames(30)
	var p: Vector3 = engaged.global_position
	var flat := Vector2(p.x - spot.x, p.z - spot.z)
	var facing := Vector2(-1, 0)
	var ahead := flat.dot(facing)
	check(ahead > 1.7 and ahead < 2.3 and absf(flat.length() - 2.09) < 0.3, "hovers 2 m in front of Ilyusha (ahead %.2f, distance %.2f)" % [ahead, flat.length()])
	check(p.y > 1.7 and p.y < 2.1, "hovers at face height (%.2f m)" % p.y)
	var to := Vector3(spot.x - p.x, 0, spot.z - p.z).normalized()
	var nose := -engaged.global_basis.z
	nose.y = 0.0
	check(nose.normalized().dot(to) > 0.9, "the drone looks at Ilyusha (dot %.2f)" % nose.normalized().dot(to))
	# Илюша поворачивается — дрон перелетает, оставаясь перед ним.
	player.place(spot, 0.0)   # лицом на север
	await _frames(90)
	p = engaged.global_position
	check(Vector2(p.x - spot.x, p.z - spot.z).dot(Vector2(0, -1)) > 1.5, "the drone moves to stay in front when Ilyusha turns")
	var hover_frames := 0
	while engaged.state == &"hover" and hover_frames < 600:
		await physics_frame
		hover_frames += 1
	var total := (30.0 + 90.0 + hover_frames) / 60.0
	check(engaged.state == &"leave" and absf(total - DronesScript.HOVER_SECONDS) < 0.25, "the drone flies away after 5 s of watching (%.2f s)" % total)
	var back := false
	for f in 600:
		await physics_frame
		if engaged.state == &"approach" or engaged.state == &"hover":
			break
		if engaged.state == &"patrol":
			back = true
	check(back, "the drone returns to its loop")
	check(engaged.state != &"approach" and engaged.state != &"hover", "and does not come back right away (ignore %.0f s)" % DronesScript.IGNORE_SECONDS)
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _frames(400)   # дрон петли 0 снова готов замечать (пауза IGNORE_SECONDS)

## В укрытии и в машине дроны не подлетают.
func _part_no_watch() -> void:
	print("--- no watching in hide or in the car ---")
	var spot := Vector3(-16.0, 0, 85.0)
	player.place(spot, PI * 0.5)
	player.force_hide_mode(&"box")
	var bad := false
	for f in 360:
		await physics_frame
		for d in drones.drones:
			bad = bad or d.state == &"approach" or d.state == &"hover"
	check(not bad, "no drone watches Ilyusha in a box")
	player.force_hide_mode(&"none")
	await _frames(2)

# --- 7. Удар в укрытии и в машине ---

func _part_blocked() -> void:
	print("--- punch blocked in hide and car ---")
	player.place(Vector3(-36.5, 0, 90.0), PI)
	await _frames(40)
	player.force_hide_mode(&"box")
	var before := player.punches
	check(not player.punch(), "no punch in a box")
	_press_key(KEY_F)
	await _frames(2)
	check(player.punches == before, "F does nothing in a box")
	player.force_hide_mode(&"none")
	await _frames(40)
	world.car.reset_to(Vector3(-36.5, 0, 84.0), 0.0)
	await _frames(5)
	world.enter_car()
	await _frames(5)
	check(world.control_mode == &"in_car", "in the car")
	check(not player.punch(), "no punch in the car")
	_press_key(KEY_F)
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	Input.parse_input_event(b)
	await _frames(2)
	check(Input.is_action_pressed(&"handbrake"), "gamepad B is the handbrake in the car")
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_B
	rb.pressed = false
	Input.parse_input_event(rb)
	await _frames(2)
	check(player.punches == before, "F and B do not punch in the car")
	world.exit_car()
	await _frames(5)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	await _frames(5)

# --- 8. Удар мимо ---

func _part_miss() -> void:
	print("--- miss ---")
	player.place(Vector3(-36.5, 0, 90.0), PI)
	await _frames(40)
	var hits := player.punch_hits
	check(player.punch(), "punch into the air")
	await _frames(25)
	check(player.punch_hits == hits and player.last_punch_targets.is_empty(), "a miss hits nothing")
	# Дрон выше полосы удара (2,3 м) прямо перед Илюшей — не задет; в полосе — задет (проверяем без распада).
	drones.set_physics_process(false)
	var d: Node3D = drones.drones[1]
	var keep: Vector3 = d.global_position
	var front := player.global_position + player.facing_dir() * 1.2
	d.global_position = front + Vector3.UP * 2.75
	await _frames(40)
	var breaks: int = drones.breaks
	player.punch()
	await _frames(25)
	check(player.punch_hits == hits and drones.breaks == breaks, "a drone above 2.3 m is out of reach")
	d.global_position = keep
	drones.set_physics_process(true)
	await _frames(5)

# --- 9. Полицейский и Бабка ---

func _part_officer_and_babka() -> void:
	print("--- officer and Babka ---")
	var officer: Node3D = world.get_node("LevelGeometry/Patrols/Officer")
	var mission_state: StringName = world.mission.state
	var gags: int = drones.gags
	var started: int = sound.gags_started
	var o := officer.global_position
	var spot := o + Vector3(0, 0, 1.4)
	player.place(spot, 0.0)   # лицом на север, к полицейскому
	await _frames(40)
	check(player.punch(), "punch at the officer")
	await _frames(25)
	check(officer in player.last_punch_targets, "the punch reaches the officer")
	check(drones.gags == gags + 1 and sound.gags_started == started + 1, "officer: subtitle gag")
	check(sound.subtitle_label.text.contains(DronesScript.PATROL_GAG), "subtitle «%s» (%s)" % [DronesScript.PATROL_GAG, sound.subtitle_label.text])
	check(not world.is_stealth_failing() and world.mission.state == mission_state and player.input_enabled, "no fail, mission unchanged, Ilyusha keeps control")
	await _frames(40)
	player.punch()
	await _frames(25)
	check(drones.gags == gags + 1, "no second officer gag within 20 s")
	await _frames(60 * 20)
	player.punch()
	await _frames(25)
	check(drones.gags == gags + 2, "officer gag again after 20 s")
	# Бабка: удар — ничего.
	var harmless: int = drones.harmless_hits
	# Перед Бабкой с юга (z меньше), лицом к ней: облик смотрит по −Z, поворот PI — на +Z.
	player.place(world.babka.global_position + Vector3(0, 0, -1.6), PI)
	await _frames(40)
	player.punch()
	await _frames(25)
	check(world.babka in player.last_punch_targets and drones.harmless_hits > harmless, "the punch reaches Babka and does nothing")
	check(not world.is_stealth_failing() and world.mission.state == mission_state, "Babka: no fail, mission unchanged")

# --- 10. Удар по дрону, монеты, возрождение ---

func _part_break_and_respawn() -> void:
	print("--- break, coins, respawn ---")
	var spot := Vector3(-6.0, 0, 42.0)   # южный тротуар A, петля 7
	player.place(spot, PI * 0.5)
	var engaged: Node3D = null
	for f in 900:
		await physics_frame
		for d in drones.drones:
			if d.state == &"hover":
				engaged = d
		if engaged:
			break
	check(engaged != null, "a drone hovers in front of Ilyusha on street A")
	if engaged == null:
		return
	await _frames(20)
	var pops: int = sound.played["drone_pop"]
	var before_coins: int = coins.remaining() if coins and coins.has_method("remaining") else -1
	var old_loop: int = engaged.loop
	var at: Vector3 = engaged.global_position
	check(player.punch(), "punch the hovering drone")
	await _frames(10)
	check(engaged.state == &"broken" and not engaged.visible, "the drone breaks apart")
	check(engaged in player.last_punch_targets, "punch_landed carried the drone")
	var pieces: int = drones.debris.size()
	check(pieces >= 4 and pieces <= 6, "4–6 debris pieces (%d)" % pieces)
	check(sound.played["drone_pop"] == pops + 1 and _flat(sound.drone_pop_player.global_position).distance_to(_flat(at)) < 0.5, "pop sound at the drone")
	check(not sound.drone_buzz[engaged].playing, "a broken drone is silent")
	if coins and coins.has_method("spawn_burst"):
		check(drones.coin_bursts == 1 and drones.bursts[0][1] == 5, "Coins.spawn_burst(position, 5) called once")
		if before_coins >= 0:
			check(coins.remaining() - before_coins == 5, "5 coins scatter from the drone (%d)" % (coins.remaining() - before_coins))
	else:
		print("INFO: no Coins node yet — coin burst skipped")
	await _frames(90)
	check(drones.debris.is_empty(), "debris gone within 1.5 s")
	check(drones.find_children("DroneDebris*", "", true, false).size() == 0, "debris nodes freed")
	# Сбитый не задевается повторно.
	var breaks: int = drones.breaks
	await _frames(40)
	player.punch()
	await _frames(25)
	check(drones.breaks == breaks, "a broken drone cannot be hit again")
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var respawns: int = drones.respawns
	var waited := 0.0
	while drones.respawns == respawns and waited < 95.0:
		await physics_frame
		waited += 1.0 / 60.0
	var delay: float = engaged.last_respawn_delay
	check(drones.respawns == respawns + 1 and engaged.visible and engaged.state == &"patrol", "the drone respawns (%.1f s)" % (waited + 125.0 / 60.0))
	check(delay >= 60.0 and delay <= 90.0, "respawn delay 60–90 s (%.1f)" % delay)
	check(engaged.loop != old_loop, "respawns on another loop (%d → %d)" % [old_loop, engaged.loop])
	var others := 0
	for d in drones.drones:
		if d != engaged and d.loop == engaged.loop and d.state != &"broken":
			others += 1
	check(others == 0, "the new loop is free")
	await _frames(10)
	check(sound.drone_buzz[engaged].playing, "the respawned drone buzzes again")

# --- 11. Цена кадра ---

func _part_cost() -> void:
	print("--- cost ---")
	var t0 := Time.get_ticks_usec()
	for i in 600:
		drones._physics_process(1.0 / 60.0)
	var per := float(Time.get_ticks_usec() - t0) / 600.0
	print("INFO: Drones._physics_process %.1f µs per frame" % per)
	check(per < 300.0, "drones cost < 0.3 ms per physics frame (%.1f µs)" % per)
	var meshes := drones.find_children("*", "MeshInstance3D", true, false).size()
	print("INFO: drone meshes %d" % meshes)
	check(meshes <= 30 * drones.drones.size(), "≤ 30 meshes per drone (%d)" % meshes)

# --- общее ---

func _press_key(code: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)

func _sensors(on: bool) -> void:
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = on

func _signature(node: Node) -> String:
	var parts := []
	for child in node.find_children("*", "", true, false):
		parts.append("%s:%s" % [node.get_path_to(child), child.get_class()])
	return ",".join(parts)

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish(code := -1) -> void:
	print("PUNCH: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

extends SceneTree
## Independent CHARACTER-02 acceptance: real Ilyusha, InputMap and collisions.
## No calls to the air helper's step/resolve methods or replacement motion clock.
## World/target staging is fixture setup; effects use actual registered consumers.
const InputSetup = preload("res://game/input_setup.gd")
const PlayerScene = preload("res://game/player/ilyusha.tscn")
const Hide = preload("res://game/stealth/hide_tuning.gd")
const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const RELEASE := [&"jump", &"punch", &"sprint", &"move_left", &"move_right", &"move_forward", &"move_back"]

class PostPhysics:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var checks := 0
var failures: Array[String] = []
var observer: PostPhysics
var arena: Node3D
var player: Ilyusha
var main: Node
var world: DemoWorld
var hit_batches: Array = []
var accepted_attacks := 0
var saved_hz := 60
var profiles: Array = []
var watchdog: SceneTreeTimer
var finishing := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("CHARACTER02_INTEGRATION: " + label)
	return ok

func _run() -> void:
	watchdog = create_timer(180.0, true, false, true)
	watchdog.timeout.connect(_watchdog_timeout)
	saved_hz = Engine.physics_ticks_per_second
	InputSetup.install()
	observer = PostPhysics.new()
	observer.process_mode = Node.PROCESS_MODE_ALWAYS
	observer.process_physics_priority = 10000
	root.add_child(observer)
	print("CHARACTER02_INTEGRATION_INPUTS ", JSON.stringify({
		"shar_pin": "c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6",
		"engine": Engine.get_version_info(),
		"test_sha256": FileAccess.get_sha256(get_script().resource_path),
		"actor_sha256": FileAccess.get_sha256("res://game/player/ilyusha.gd"),
		"air_sha256": FileAccess.get_sha256("res://game/player/character_air_motion.gd")}))
	arena = Node3D.new()
	root.add_child(arena)
	_box(arena, Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	player = PlayerScene.instantiate()
	arena.add_child(player)
	_watch_player()
	if not check(player.get("air_motion") != null, "real controller owns the integrated air state"):
		await _finish()
		return
	await _trajectory_rates()
	Engine.physics_ticks_per_second = 60
	await _jump_windows()
	await _momentum_and_contacts()
	await _cancel_and_input_lock()
	_release()
	_unwatch_player()
	player = null
	hit_batches.clear()
	arena.queue_free()
	await _ticks(3)
	arena = null
	await _main_composition()
	await _finish()

func _watch_player() -> void:
	player.punched.connect(_on_accepted_attack)
	player.punch_landed.connect(_on_hit)

func _unwatch_player() -> void:
	if not is_instance_valid(player): return
	if player.punched.is_connected(_on_accepted_attack):
		player.punched.disconnect(_on_accepted_attack)
	if player.punch_landed.is_connected(_on_hit):
		player.punch_landed.disconnect(_on_hit)

func _on_accepted_attack() -> void:
	accepted_attacks += 1

func _on_hit(targets: Array) -> void:
	hit_batches.append(targets.duplicate())

func _watchdog_timeout() -> void:
	push_error("CHARACTER02_INTEGRATION: watchdog expired")
	quit(2)

func _box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func _reset(at: Vector3 = Vector3(0, 0.02, 0)) -> void:
	_release()
	player.input_enabled = true
	player.visible = true
	player.set_physics_process(true)
	player.force_hide_mode(Hide.NONE)
	player.place(at, 0.0)
	await _ground(90)
	# Existing attacks retain their documented cooldown across place().
	await _ticks(ceili(0.55 * Engine.physics_ticks_per_second))
	await _ground(12)

func _trajectory_rates() -> void:
	for hz: int in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		await _reset()
		var base := player.global_position.y
		var start := player.global_position
		var max_y := base
		var departed := false
		var landings := 0
		var previous_floor := player.is_on_floor()
		# Hold the real mapped control: holding cannot grant an extra jump.
		_input(KEY_SPACE, true)
		for frame in hz * 2:
			await _ticks(1)
			max_y = maxf(max_y, player.global_position.y)
			var floor_now := player.is_on_floor()
			if not floor_now and player.global_position.y > base + 0.05:
				departed = true
			if departed and floor_now and not previous_floor:
				landings += 1
				break
			previous_floor = floor_now
		_input(KEY_SPACE, false)
		check(departed and landings == 1, "Space produces one complete physical flight at %d Hz" % hz)
		var height := max_y - base
		# The chosen 1.9 m is a physical apex, not an impulse label. At 30 Hz
		# discrete sampling alone loses less than 4 mm for this gravity, so a
		# systematic 8-17 cm overshoot cannot be hidden by the fixture budget.
		check(absf(height - 1.9) <= 0.04, "first jump reaches the chosen 1.9 m within 4 cm at %d Hz (%.3f m)" % [hz, height])
		check(Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() < 0.025,
			"idle jump creates no horizontal root motion at %d Hz" % hz)
		check(absf(player.global_position.y - base) < 0.06, "flight returns the actual capsule to its floor at %d Hz" % hz)
		await _reset()
		await _tap(KEY_SPACE)
		var second_gain := 0.0
		if await _apex_window():
			var second_base := player.global_position.y
			await _tap(KEY_SPACE)
			var accepted: bool = _state().jump_count == 2 and player.velocity.y > 0.0
			var second_peak := player.global_position.y
			var landed := false
			for frame in hz * 2:
				await _ticks(1)
				second_peak = maxf(second_peak, player.global_position.y)
				if player.is_on_floor():
					landed = true
					break
			second_gain = second_peak - second_base
			check(accepted and landed, "second-jump height witness completes a real accepted flight at %d Hz" % hz)
			check(absf(second_gain - 1.0) <= 0.04,
				"second jump adds the chosen 1.0 m within 4 cm at %d Hz (%.3f m)" % [hz, second_gain])
		profiles.append({"hz": hz, "height": height, "second_height": second_gain})
	var lowest := INF
	var highest := -INF
	var lowest_second := INF
	var highest_second := -INF
	for profile: Dictionary in profiles:
		lowest = minf(lowest, profile.height)
		highest = maxf(highest, profile.height)
		lowest_second = minf(lowest_second, profile.second_height)
		highest_second = maxf(highest_second, profile.second_height)
	check(highest - lowest <= 0.03, "actual first-jump apex varies by at most 3 cm across 30/60/120 physics Hz")
	check(highest_second - lowest_second <= 0.03, "actual second-jump height varies by at most 3 cm across 30/60/120 physics Hz")

func _jump_windows() -> void:
	await _reset()
	await _tap(JOY_BUTTON_A, true)
	check(not player.is_on_floor() and player.velocity.y > 0, "mapped pad A launches the real controller")
	var before := player.velocity.y
	await _tap(JOY_BUTTON_A, true)
	check(player.velocity.y < before and _state().jump_count == 1, "a fresh early A press cannot reset upward velocity")
	var second_seen := false
	for frame in 100:
		await _ticks(1)
		second_seen = second_seen or _state().jump_count == 2
		if player.is_on_floor(): break
	check(not second_seen, "the rejected early press is never buffered until the apex")
	await _reset()
	await _tap(KEY_SPACE)
	if await _apex_window():
		var second_from := player.global_position.y
		await _tap(KEY_SPACE)
		check(_state().jump_count == 2 and player.velocity.y > 5.0, "fresh Space in the apex window starts one second jump")
		var second_peak := player.global_position.y
		var attempted_third := false
		for frame in 110:
			await _ticks(1)
			second_peak = maxf(second_peak, player.global_position.y)
			if not attempted_third and absf(player.velocity.y) < 1.0:
				attempted_third = true
				var prior := player.velocity.y
				await _tap(JOY_BUTTON_A, true)
				check(_state().jump_count == 2 and player.velocity.y < prior + 0.1, "a third pad A press cannot add another impulse")
			if player.is_on_floor(): break
		check(attempted_third, "third-jump negative reaches the second apex while airborne")
		check(absf(second_peak - second_from - 1.0) <= 0.04,
			"second jump adds a bounded roughly one metre (%.3f m)" % (second_peak - second_from))
	# An elevated physical launch platform makes the late window reachable before landing.
	var platform := _box(arena, Vector3(12, 2.75, 0), Vector3(4, 0.5, 4))
	await _reset(Vector3(12.7, 3.02, 0))
	Input.action_press(&"move_right")
	Input.action_press(&"sprint")
	await _ticks(8)
	await _ground(4)
	await _tap(KEY_SPACE)
	var late_reached := false
	for frame in 100:
		await _ticks(1)
		if not player.is_on_floor() and player.velocity.y < -12.2:
			late_reached = true
			var prior := player.velocity.y
			await _tap(KEY_SPACE)
			check(_state().jump_count == 1 and player.velocity.y < prior, "late Space below the downward window adds no impulse")
			break
		if player.is_on_floor(): break
	check(late_reached, "late-jump negative reaches fast descent after a real first jump")
	_release()
	platform.queue_free()
	await _ticks(2)
	player.place(Vector3(0, 3, 0), 0.0)
	await _ticks(2)
	var falling_speed := player.velocity.y
	var attacks := accepted_attacks
	await _tap(KEY_SPACE)
	await _tap(JOY_BUTTON_B, true)
	check(_state().natural_fall and _state().jump_count == 0 and player.velocity.y < falling_speed,
		"natural fall grants no free midair jump")
	check(accepted_attacks == attacks, "pad B cannot grant an attack to a natural fall")
	await _ground(120)

func _momentum_and_contacts() -> void:
	await _reset()
	Input.action_press(&"move_right")
	Input.action_press(&"sprint")
	await _ticks(25)
	check(player.velocity.x > 7.5, "real sprint establishes takeoff momentum")
	await _tap(KEY_SPACE)
	_release()
	var speed := player.velocity.x
	var x := player.global_position.x
	await _ticks(12)
	check(absf(player.velocity.x - speed) < 0.1 and player.global_position.x > x + 1.2,
		"releasing run and movement in flight preserves physical XZ momentum")
	await _reset()
	var wall := _box(arena, Vector3(1.1, 2.5, 0), Vector3(0.3, 5, 8))
	Input.action_press(&"move_right")
	await _tap(KEY_SPACE)
	var max_x := player.global_position.x
	for frame in 80:
		await _ticks(1)
		max_x = maxf(max_x, player.global_position.x)
	check(max_x < 0.66, "jump/air steering cannot cross a real vertical wall")
	_release()
	wall.queue_free()
	await _ticks(2)
	await _reset()
	var ceiling := _box(arena, Vector3(0, 1.74, 0), Vector3(6, 0.4, 6))
	await _ticks(2)
	var base := player.global_position.y
	await _tap(KEY_SPACE)
	var peak := player.global_position.y
	for frame in 35:
		await _ticks(1)
		peak = maxf(peak, player.global_position.y)
	check(peak - base < 0.13, "low ceiling bounds actual departure rather than merely resetting an animation")
	check(_state().jump_count == 0 and player.is_on_floor(), "low-ceiling landing releases all airborne credits")
	ceiling.queue_free()
	await _ticks(2)

func _cancel_and_input_lock() -> void:
	for reason: String in ["place", "hide", "input_lock", "visibility"]:
		await _reset()
		await _tap(KEY_SPACE)
		await _tap(KEY_F)
		var before_hits := hit_batches.size()
		match reason:
			"place": player.place(Vector3(0, 0.02, 0), 0.0)
			"hide": player.force_hide_mode(Hide.BOX)
			"input_lock": player.input_enabled = false
			"visibility": player.visible = false
		check(_state().jump_count == 0 and _state().action == &"", reason + " cancels airborne action immediately")
		await _ticks(20)
		check(hit_batches.size() == before_hits, reason + " leaves no delayed hit callback")
	await _reset()
	player.input_enabled = false
	await _tap(KEY_SPACE)
	await _tap(KEY_F)
	player.input_enabled = true
	await _ticks(20)
	check(player.global_position.y < 0.08 and _state().jump_count == 0, "input lock consumes jump/attack without replay on unlock")

func _main_composition() -> void:
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/CHARACTER-02/integration-profile-%d.json" % OS.get_process_id()
	root.add_child(main)
	await _ticks(3)
	main.start_game()
	await _ticks(15)
	world = main.world
	player = world.player
	_watch_player()
	var stage := Vector3(0, 30, 0)
	_box(world, stage + Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	await _reset(stage + Vector3.UP * 0.02)
	await _pause_and_car(stage)
	await _real_kick(stage)
	await _landing_cancels_kick(stage)
	await _real_stomp(stage + Vector3(12, 0, 0))
	await _perimeter_witness()

func _pause_and_car(stage: Vector3) -> void:
	await _tap(KEY_SPACE)
	await _ticks(4)
	var phone: Node = world.get_node("Phone")
	check(phone.open_phone(), "the actual phone opens during a physical jump")
	var at := player.global_position
	var velocity := player.velocity
	var state := _state()
	var attacks := accepted_attacks
	await _tap(KEY_F)
	await _ticks(15)
	check(player.global_position == at and player.velocity == velocity and _state() == state and accepted_attacks == attacks,
		"phone pause freezes the real body, velocity and action state")
	phone.close_phone()
	await _ticks(2)
	check(player.global_position != at and accepted_attacks == attacks, "closing the phone resumes the same flight without a queued attack")
	main.set_paused(true)
	at = player.global_position
	state = _state()
	await _ticks(10)
	check(player.global_position == at and _state() == state, "world pause freezes the physical actor and action state")
	main.set_paused(false)
	await _reset(stage + Vector3.UP * 0.02)
	await _tap(KEY_SPACE)
	await _tap(KEY_F)
	var before_hits := hit_batches.size()
	world.enter_car()
	check(world.control_mode == &"in_car" and not player.visible and _state().jump_count == 0 and _state().action == &"",
		"actual enter-car cancels pending airborne mechanics before handing over control")
	await _ticks(20)
	check(hit_batches.size() == before_hits, "seated player cannot deliver a stale air hit")
	check(world.exit_car(), "the actual car exit restores the player")
	await _reset(stage + Vector3.UP * 0.02)
	world.ui_blocking = true
	await _tap(KEY_SPACE)
	await _tap(KEY_F)
	world.ui_blocking = false
	await _ticks(15)
	check(player.global_position.y < stage.y + 0.08 and _state().jump_count == 0,
		"real world UI gating rejects air controls without replay")

func _real_kick(stage: Vector3) -> void:
	var swarm: Node = world.get_node("LevelGeometry/Drones")
	swarm.set_physics_process(false)
	await _reset(stage + Vector3.UP * 0.02)
	await _tap(JOY_BUTTON_A, true)
	if not await _apex_window(): return
	var drone: Node3D = swarm.drones[0]
	drone.global_position = player.global_position + Vector3(0, 1.55, -1.0)
	await _ticks(1)
	var drone_breaks: int = drone.breaks
	var bursts: int = swarm.coin_bursts
	var before_hits := hit_batches.size()
	var attacks := accepted_attacks
	await _tap(JOY_BUTTON_B, true)
	await _tap(JOY_BUTTON_B, true)
	await _ground(100)
	await _ticks(15)
	check(accepted_attacks == attacks + 1, "repeated pad B produces one accepted airborne kick")
	check(drone.breaks == drone_breaks + 1 and drone.state == &"broken", "real airborne kick reaches the registered drone consumer")
	check(swarm.coin_bursts == bursts + 1, "one kick causes one actual drone coin burst")
	check(hit_batches.size() == before_hits + 1 and hit_batches[before_hits].has(drone),
		"one phase crossing dispatches one actual target batch")

func _landing_cancels_kick(stage: Vector3) -> void:
	await _reset(stage + Vector3.UP * 0.02)
	var swarm: Node = world.get_node("LevelGeometry/Drones")
	var drone: Node3D = swarm.drones[2]
	drone.global_position = stage + Vector3(0, 1.55, -1.0)
	await _tap(KEY_SPACE)
	var near_contact := false
	for frame in 100:
		await _ticks(1)
		if not player.is_on_floor() and player.velocity.y < -3.0 and player.global_position.y < stage.y + 0.22:
			near_contact = true
			break
		if player.is_on_floor(): break
	if not check(near_contact, "landing-first negative reaches the floor before the kick marker is due"): return
	var breaks: int = drone.breaks
	var before_hits := hit_batches.size()
	var attacks := accepted_attacks
	await _tap(KEY_F)
	await _ground(30)
	await _ticks(15)
	check(accepted_attacks == attacks + 1, "near-floor kick was accepted before contact, rather than rejected by a setup guard")
	check(hit_batches.size() == before_hits and drone.breaks == breaks,
		"landing before the kick phase cancels the pending hit against an otherwise hittable drone")

func _real_stomp(stage: Vector3) -> void:
	var residents: Node = world.get_node("LevelGeometry/Residents")
	var visible_residents: Array = []
	for person: Node in residents.residents:
		person.set_physics_process(false)
		if not person.hidden and person.state != &"knocked" and person.body.collision_layer == 4:
			visible_residents.append(person)
	if not check(visible_residents.size() >= 2, "stomp fixture uses two actual visible physical residents"): return
	var resident: Node3D = visible_residents[0]
	var high_resident: Node3D = visible_residents[1]
	resident.global_position = stage + Vector3(-1.1, 0, 0)
	high_resident.global_position = stage + Vector3(0.8, 0.6, 0)
	var objects: Node = world.get_node("LevelGeometry/Breakables")
	objects.set_physics_process(false)
	var target: Node3D
	for item: Node3D in objects.objects:
		if not item.heavy and item.state == &"intact" and item.size.x <= 1.5 and item.size.z <= 1.5:
			target = item
			break
	if not check(target != null, "actual light breakable supplies the stomp consumer fixture"): return
	target.rotation = Vector3.ZERO
	target.global_position = stage + Vector3(0, 0, -1.3)
	world.babka.global_position = stage + Vector3(1.2, 0, 0.8)
	var patrol: Node3D = world.get_node("LevelGeometry/Patrols/Officer")
	patrol.set_process(false)
	patrol.set_physics_process(false)
	# Isolate target filtering from the sensor's independent three-metre hearing
	# rule: moving a real patrol into this fixture would otherwise create a threat.
	# Existing stealth qualification remains separate; no detection PASS is claimed.
	var sensor_was_enabled: bool = patrol.sensor.enabled
	patrol.sensor.enabled = false
	patrol.global_position = stage + Vector3(-1.2, 0, 0.8)
	world.car.set_physics_process(false)
	world.car.global_position = stage + Vector3(0, 0, 1.6)
	world.car.rotation.y = PI * 0.5
	var swarm: Node = world.get_node("LevelGeometry/Drones")
	var excluded_drone: Node3D = swarm.drones[1]
	excluded_drone.global_position = stage + Vector3(0, 0.45, -0.7)
	await _reset(stage + Vector3.UP * 0.02)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.8
	cylinder.height = 0.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cylinder
	query.transform = Transform3D(Basis.IDENTITY, stage + Vector3.UP * 0.4)
	query.collision_mask = 4 | 32
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var nearby: Array = []
	for contact: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(query, 64):
		nearby.append(contact.collider)
	check(nearby.has(resident.body) and nearby.has(target.body), "actual positive bodies intersect the chosen low landing neighbourhood")
	check(nearby.has(high_resident.body) and nearby.has(world.car),
		"elevated-resident and live-car negatives reach the body query before semantic filtering")
	var pushes: int = resident.pushes
	var high_pushes: int = high_resident.pushes
	var breaks: int = target.breaks
	var drone_breaks: int = excluded_drone.breaks
	var mission_state: StringName = world.mission.state
	var before_hits := hit_batches.size()
	await _tap(KEY_SPACE)
	if not await _apex_window(): return
	await _tap(KEY_SPACE)
	check(_state().jump_count == 2, "stomp witness reaches a real second jump")
	await _tap(KEY_F)
	var held_at := player.global_position
	await _ticks(3)
	check(player.global_position.distance_to(held_at) < 0.025 and not player.is_on_floor(), "stomp anticipation briefly holds actual root motion in the air")
	await _ticks(10)
	check(player.global_position.y < held_at.y - 0.04, "stomp transitions from hold into real downward movement")
	await _ground(120)
	check(hit_batches.size() == before_hits + 1, "one physical stomp landing produces one target dispatch")
	check(resident.pushes == pushes + 1 and target.breaks == breaks + 1, "stomp uses actual resident push and light-breakable consumers")
	check(high_resident.pushes == high_pushes and excluded_drone.breaks == drone_breaks,
		"stomp excludes elevated residents and areas even when they intersect its broad neighbourhood")
	if hit_batches.size() > before_hits:
		var hit: Array = hit_batches[before_hits]
		check(not hit.has(world.babka) and not hit.has(patrol) and not hit.has(world.car), "stomp excludes quest NPCs, patrols and the live player car")
	check(world.mission.state == mission_state, "target dispatch does not alter the mission")
	var landed_at := player.global_position
	Input.action_press(&"move_right")
	await _ticks(3)
	check(Vector2(player.global_position.x - landed_at.x, player.global_position.z - landed_at.z).length() < 0.025,
		"ordinary movement cannot escape the short stomp landing recovery")
	await _tap(KEY_SPACE)
	check(not player.is_on_floor() and player.velocity.y > 0, "a fresh jump can deliberately leave stomp recovery")
	_release()
	await _ticks(40)
	check(hit_batches.size() == before_hits + 1 and resident.pushes == pushes + 1, "ground contacts and recovery do not repeat the stomp effect")
	# Clear staged blockers before the canonical geometry witness.
	for node: Node3D in [resident, high_resident, target, world.babka, patrol, world.car, excluded_drone]:
		node.global_position += Vector3(0, 100, 0)
	patrol.sensor.enabled = sensor_was_enabled

func _perimeter_witness() -> void:
	# A1: the canonical northern wall is 3.6 m high at z=-124.2.
	# This is a bounded new double-jump witness, not full perimeter qualification.
	var wall_z := -124.2
	var declared := false
	for wall: Array in Layout.PERIMETER_WALLS:
		if is_equal_approx((wall[0] as Vector2).y, wall_z) and is_equal_approx((wall[1] as Vector2).y, wall_z):
			declared = true
	if not check(declared, "bounded double-jump witness uses the actual canonical north wall"): return
	player.camera_rig = null
	await _reset(Vector3(0, 0.02, -120.5))
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _tap(KEY_SPACE)
	if await _apex_window(): await _tap(KEY_SPACE)
	var closest_z := player.global_position.z
	var visible_wall_contact := false
	for frame in 100:
		await _ticks(1)
		closest_z = minf(closest_z, player.global_position.z)
		for index in player.get_slide_collision_count():
			var collider := player.get_slide_collision(index).get_collider() as Node
			if collider != null and String(collider.name).begins_with("PerimeterWall"):
				visible_wall_contact = true
	check(visible_wall_contact, "the double-jump witness reaches the actual visible perimeter collider")
	check(closest_z > wall_z + 0.65, "actual running double jump cannot cross the visible northern perimeter wall")
	_release()

func _apex_window() -> bool:
	for frame in 100:
		if not player.is_on_floor() and absf(player.velocity.y) <= 1.0:
			return true
		await _ticks(1)
		if player.is_on_floor(): break
	return check(false, "fixture reaches an airborne apex through the real controller")

func _ground(limit: int) -> bool:
	for frame in limit:
		await _ticks(1)
		if player.is_on_floor(): return true
	return check(false, "real capsule reaches a physical floor within its bounded flight")

func _state() -> Dictionary:
	return player.air_motion.snapshot()

func _input(code: int, down: bool, pad := false) -> void:
	if pad:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
	else:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)

func _tap(code: int, pad := false) -> void:
	_input(code, true, pad)
	await _ticks(1)
	_input(code, false, pad)
	await _ticks(1)

func _release() -> void:
	for action: StringName in RELEASE:
		Input.action_release(action)
	for code: int in [KEY_SPACE, KEY_F]: _input(code, false)
	for code: int in [JOY_BUTTON_A, JOY_BUTTON_B]: _input(code, false, true)

func _ticks(count: int) -> void:
	for frame in count: await observer.stepped

func _finish() -> void:
	if finishing: return
	finishing = true
	_release()
	paused = false
	Engine.physics_ticks_per_second = saved_hz
	if watchdog != null:
		if watchdog.timeout.is_connected(_watchdog_timeout):
			watchdog.timeout.disconnect(_watchdog_timeout)
		watchdog = null
	_unwatch_player()
	player = null
	hit_batches.clear()
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in root.find_children("*", kind, true, false):
			audio.stop()
	if is_instance_valid(world):
		var people := world.get_node_or_null("LevelGeometry/Residents")
		if people != null and people.life != null:
			people.life.reset()
	world = null
	if is_instance_valid(main):
		main.queue_free()
	main = null
	if is_instance_valid(arena): arena.queue_free()
	arena = null
	await _ticks(5)
	# AudioServer's stopped playback drains on its mixer clock, as in the
	# independently qualified Main composition fixture.
	OS.delay_msec(100)
	await process_frame
	Materials.clear_cache()
	VehicleMesh.cache().clear()
	observer.queue_free()
	observer = null
	await process_frame
	print("CHARACTER02_INTEGRATION_PROFILE ", JSON.stringify(profiles))
	print("CHARACTER02_INTEGRATION: %d checks, %d failures; GPU/art/palms/full perimeter/stealth qualification NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## PLAY-04 regression: real Ilyusha + real Input + physics contacts, no controller replacement.
## Standalone fixture, not the mission/C7 oracle. No driver/camera coordinate conversion.
## Run: tools/godot.sh --path . --headless --fixed-fps 60 --script tests/play04_wall_slide_test.gd
## Two distinct contracts, frozen before executing the candidate:
## q=.5: preserved old vector baseline, 4m/s * .5 = 2m/s along the contact plane.
## q=.2: intended ordinary-ground slide boundary, 4m/s * .2 = .8m/s; the old controller
## stops here under its 15-degree threshold (six expected baseline assertion failures).
## Neither case may penetrate or create an unrequested tangent; hide rules are out of scope.
## After 1s contact settling the projection tolerance is .1m/s, above numerical noise.
## Qualified matrix: baseline95/6 (q=.2 only), scalar-WIP95/10, corrected candidate95/0.
## Thus the complete suite is NOT a claim of preservation of every old collision behavior.

const PlayerScript = preload("res://game/player/ilyusha.gd")
const InputSetup = preload("res://game/input_setup.gd")
const ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump"]
const PRESERVED_WALK_MPS := 4.0
const PRESERVED_DECEL_MPS2 := 11.0
const CONTACT_SETTLE_S := 1.0
const MEASURE_S := 1.0
const STOP_S := 0.45 # original full-speed 4/11s + 2 ticks, rounded upward
const TANGENT_TOLERANCE_MPS := 0.1
const STOP_EPS_MPS := 0.01
const POSITION_EPS_M := 0.02
const LADA_PARK_YAW := 0.896055384571344 # atan2(10,8), original parking's last segment

class PostPhysics:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var observer: PostPhysics
var fixture: Node3D
var player: Ilyusha
var wall: StaticBody3D
var checks := 0
var failures: Array[String] = []
var dt := 0.0
var trace := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Main._ready normally owns this initialization; the isolated fixture uses the same installer.
	InputSetup.install()
	var input_ready := true
	for action in InputSetup.KEYS:
		var present := InputMap.has_action(action)
		check(present, "fixture preflight: actual InputMap action exists: " + action)
		input_ready = input_ready and present
	if not input_ready:
		push_error("PLAY04_WALL_SLIDE: INVALID fixture, production input actions unavailable")
		quit(2)
		return
	dt = 1.0 / Engine.physics_ticks_per_second
	trace = "--trace" in OS.get_cmdline_user_args()
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("PLAY04_WALL_SLIDE: watchdog exceeded 30 simulated seconds")
		quit(2))
	observer = PostPhysics.new()
	observer.process_physics_priority = 1000
	root.add_child(observer)
	print("PLAY04_WALL_SLIDE_PROFILE ", JSON.stringify({
		"engine": Engine.get_version_info(), "physics_hz": Engine.physics_ticks_per_second,
		"player_sha256": FileAccess.get_sha256("res://game/player/ilyusha.gd"),
		"test_sha256": FileAccess.get_sha256(get_script().resource_path),
		"scope": "planar contact tangent, release brake, place reset",
		"input": "constant raw Input actions; no driver or camera",
		"expected_tangent_mps": [2.0, 0.8],
		"contract_kind": {"q0.5":"preserved old baseline", "q0.2":"intended ordinary-ground boundary"},
		"tolerance_mps": TANGENT_TOLERANCE_MPS,
		"fixture": "floor World1; 1x3x40m wall World1 and rotated Car4"}))
	check(Engine.physics_ticks_per_second == 60, "regression profile uses original 60 Hz")
	await _contact_case("World-axis-q0.5", 1, 0.0, 0.5)
	await _contact_case("World-axis-q0.2", 1, 0.0, 0.2)
	await _contact_case("Car-rotated-q0.5", 4, LADA_PARK_YAW, 0.5)
	await _contact_case("Car-rotated-q0.2", 4, LADA_PARK_YAW, 0.2)
	_release()
	observer.queue_free()
	await process_frame
	print("PLAY04_WALL_SLIDE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _contact_case(label: String, layer: int, yaw: float, tangent_fraction: float) -> void:
	_build_fixture(layer, yaw)
	await _ticks(12)
	check(player.input_enabled and player.camera_rig == null, label + ": real player enabled without camera/driver")
	check(player.is_on_floor(), label + ": actual floor contact before input")
	var direction := Vector3(sqrt(1.0 - tangent_fraction * tangent_fraction), 0.0, -tangent_fraction).rotated(Vector3.UP, yaw)
	var tangent := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var outward := Vector3.LEFT.rotated(Vector3.UP, yaw)
	_press_direction(direction)
	var actual := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	check(actual.distance_to(Vector2(direction.x, direction.z)) < 0.00001, label + ": Input delivers the full intended oblique direction")
	await _ticks(_count(CONTACT_SETTLE_S))
	var from := player.global_position
	var contact_frames := 0
	var floor_frames := 0
	var speed_sum := 0.0
	var stalled_frames := 0
	var max_stalled_frames := 0
	var minimum_tangent_speed := INF
	var maximum_speed := 0.0
	var maximum_penetration := 0.0
	var n := _count(MEASURE_S)
	for i in n:
		await observer.stepped
		var velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
		var along := velocity.dot(tangent)
		speed_sum += along
		minimum_tangent_speed = minf(minimum_tangent_speed, along)
		maximum_speed = maxf(maximum_speed, velocity.length())
		maximum_penetration = maxf(maximum_penetration, 0.35 - player.global_position.dot(outward))
		if _touches_wall():
			contact_frames += 1
		if player.is_on_floor():
			floor_frames += 1
		stalled_frames = stalled_frames + 1 if along <= STOP_EPS_MPS else 0
		max_stalled_frames = maxi(max_stalled_frames, stalled_frames)
		if trace and i % 10 == 0:
			print("WALL_TRACE ", JSON.stringify({"case":label,"sample":i,"position":str(player.global_position),"velocity":str(player.velocity),"tangent_mps":along,"contact":_touches_wall(),"floor":player.is_on_floor()}))
	var distance := (player.global_position - from).dot(tangent)
	var duration := n * dt
	var expected := PRESERVED_WALK_MPS * tangent_fraction
	print("WALL_RESULT ", JSON.stringify({"case":label,"contacts":contact_frames,"floor_frames":floor_frames,"samples":n,"distance_m":distance,"duration_s":duration,"mean_velocity_tangent_mps":speed_sum/n,"min_tangent_mps":minimum_tangent_speed,"max_speed_mps":maximum_speed,"max_stall_s":max_stalled_frames*dt,"max_penetration_m":maximum_penetration}))
	check(contact_frames >= n - 2, label + ": scenario reaches and stays on the intended wall boundary")
	check(floor_frames >= n - 2, label + ": contact scenario remains grounded")
	check(maximum_penetration <= POSITION_EPS_M, label + ": capsule never passes through the wall")
	var slide_contract := "preserved baseline" if tangent_fraction >= 0.5 else "ordinary-ground boundary"
	check(distance >= (expected - TANGENT_TOLERANCE_MPS) * duration, label + ": " + slide_contract + " projects %.1fm/s into actual tangent displacement" % expected)
	check(speed_sum / n >= expected - TANGENT_TOLERANCE_MPS, label + ": sustained contact does not collapse actual tangent velocity")
	check(max_stalled_frames <= 2, label + ": no multi-frame stall while tangent input is held")
	check(maximum_speed <= PRESERVED_WALK_MPS + STOP_EPS_MPS, label + ": contact preserves the existing speed cap")
	_release()
	var release_position := player.global_position
	await _ticks(_count(STOP_S))
	var stopped := player.global_position
	check(_horizontal_speed() <= STOP_EPS_MPS, label + ": released input stops within the existing brake budget")
	var maximum_stop_distance := PRESERVED_WALK_MPS * PRESERVED_WALK_MPS / (2.0 * PRESERVED_DECEL_MPS2) + 2.0 * dt * PRESERVED_WALK_MPS
	check((stopped - release_position).length() <= maximum_stop_distance + POSITION_EPS_M, label + ": release adds no hidden stored-speed travel")
	await _ticks(12)
	check(player.global_position.distance_to(stopped) <= POSITION_EPS_M, label + ": released grounded player stays stopped")
	# A zero minimum slide angle must not permit penetration or invented tangent motion.
	var frontal_start := player.global_position
	_press_direction(-outward)
	await _ticks(30)
	check(_touches_wall() and player.is_on_wall(), label + ": pure frontal input reaches the same wall")
	check(player.global_position.dot(outward) >= 0.35 - POSITION_EPS_M, label + ": pure frontal input never penetrates")
	check(absf((player.global_position - frontal_start).dot(tangent)) <= POSITION_EPS_M and _horizontal_speed() <= STOP_EPS_MPS, label + ": pure frontal input creates neither tangent motion nor drift")
	_release()
	await _ticks(12)
	check(_horizontal_speed() <= STOP_EPS_MPS, label + ": release after frontal block remains stopped")
	# place() must clear any new controller state, not just CharacterBody3D.velocity.
	var reset_point := Vector3(-6.0, 0.0, 0.0).rotated(Vector3.UP, yaw)
	player.place(reset_point + Vector3.BACK.rotated(Vector3.UP, yaw) * 3.0, 0.0)
	_press_direction(tangent)
	await _ticks(30)
	check(_horizontal_speed() >= PRESERVED_WALK_MPS - TANGENT_TOLERANCE_MPS, label + ": reset control begins with actual free motion")
	player.place(reset_point, 0.0)
	check(player.velocity == Vector3.ZERO and player.global_position == reset_point, label + ": place immediately resets position and physical velocity")
	_release()
	await _ticks(12)
	check(_horizontal_speed() <= STOP_EPS_MPS and player.global_position.distance_to(reset_point) <= POSITION_EPS_M, label + ": place leaves no latent movement after input release")
	fixture.queue_free()
	await _ticks(2)

func _build_fixture(layer: int, yaw: float) -> void:
	fixture = Node3D.new()
	fixture.name = "WallSlideFixture"
	root.add_child(fixture)
	var ground := _box_body("Ground", Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0), 1)
	fixture.add_child(ground)
	wall = _box_body("ContactWall", Vector3(1.0, 3.0, 40.0), Vector3(0.5, 1.5, 0.0), layer)
	wall.rotation.y = yaw
	# Rotate the body's offset too, keeping the near face on the origin plane.
	wall.position = wall.position.rotated(Vector3.UP, yaw)
	fixture.add_child(wall)
	player = PlayerScript.new()
	player.name = "Ilyusha"
	fixture.add_child(player)
	player.place(Vector3(-0.65, 0.0, 4.0).rotated(Vector3.UP, yaw), 0.0)

func _box_body(label: String, size: Vector3, at: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body

func _touches_wall() -> bool:
	for i in player.get_slide_collision_count():
		if player.get_slide_collision(i).get_collider() == wall:
			return true
	return false

func _press_direction(direction: Vector3) -> void:
	_release()
	Input.action_press(&"move_right" if direction.x > 0.0 else &"move_left", absf(direction.x))
	Input.action_press(&"move_back" if direction.z > 0.0 else &"move_forward", absf(direction.z))

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func _horizontal_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()

func _count(seconds: float) -> int:
	return ceili(seconds / dt)

func _ticks(count: int) -> void:
	for i in count:
		await observer.stepped

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

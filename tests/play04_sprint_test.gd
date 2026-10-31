extends SceneTree
## PLAY-04: independent run/walk responsiveness through real Input, player and camera.
## Targets 4/8m/s and response budgets are OUR proposal, not effective original tuning.
## Run: tools/godot.sh --headless --path . --script tests/play04_sprint_test.gd

const PlayerScript = preload("res://game/player/ilyusha.gd")
const CameraScript = preload("res://game/camera/camera_rig.gd")
const InputSetup = preload("res://game/input_setup.gd")
const ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump"]
const WALK_MPS := 4.0
const RUN_MPS := 8.0
const SPEED_EPS_MPS := 0.05
const RUN_RESPONSE_S := 0.35
const WALK_RETURN_S := 0.3
const AIR_COAST_S := 0.2
const JUMP_APEX_M := 1.8877
const JUMP_FLIGHT_S := 1.25
const HEIGHT_EPS_M := 0.03

class PostPhysics:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var observer: PostPhysics
var fixture: Node3D
var player: Ilyusha
var rig: CameraRig
var dt := 0.0
var maximum_speed := 0.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	InputSetup.install()
	dt = 1.0 / Engine.physics_ticks_per_second
	create_timer(35.0, true, false, true).timeout.connect(func():
		push_error("PLAY04_SPRINT: watchdog exceeded 35 simulated seconds")
		quit(2))
	observer = PostPhysics.new()
	observer.process_physics_priority = 1000
	root.add_child(observer)
	_build_fixture()
	print("PLAY04_SPRINT_PROFILE ", JSON.stringify({
		"bounds": "own proposal; no claim of original effective tuning",
		"physics_hz": Engine.physics_ticks_per_second,
		"player_sha256": FileAccess.get_sha256("res://game/player/ilyusha.gd"),
		"input_sha256": FileAccess.get_sha256("res://game/input_setup.gd"),
		"test_sha256": FileAccess.get_sha256(get_script().resource_path),
		"walk_mps": WALK_MPS, "run_mps": RUN_MPS,
		"run_response_s": RUN_RESPONSE_S, "walk_return_s": WALK_RETURN_S}))
	await _bindings()
	await _walk_run_return()
	await _blocked_and_hidden()
	await _run_jump_release()
	await _hide_transition_air()
	await _reset_and_standing_jump()
	check(maximum_speed <= RUN_MPS + SPEED_EPS_MPS, "all scenarios remain within the run speed cap")
	_release()
	fixture.queue_free()
	observer.queue_free()
	await process_frame
	print("PLAY04_SPRINT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _bindings() -> void:
	await _reset()
	check(InputMap.has_action(&"sprint"), "production InputMap defines the sprint action")
	_shift(true)
	await _ticks(1)
	check(_sprint_pressed(), "a real physical Shift press activates sprint")
	_shift(false)
	await _ticks(1)
	check(not _sprint_pressed(), "releasing Shift releases sprint")
	_shoulder(true)
	await _ticks(1)
	check(_sprint_pressed(), "a real left-shoulder joypad press activates sprint")
	_shoulder(false)
	await _ticks(1)
	check(not _sprint_pressed(), "releasing the left shoulder releases sprint")

func _walk_run_return() -> void:
	await _reset()
	Input.action_press(&"move_forward")
	await _ticks(_count(RUN_RESPONSE_S))
	check(absf(_speed() - WALK_MPS) <= SPEED_EPS_MPS, "ordinary full input walks at 4m/s")
	var walk_from := player.global_position
	await _ticks(_count(0.3))
	var walk_distance := _flat(player.global_position - walk_from).length()
	_shift(true)
	await _ticks(1)
	check(_speed() > WALK_MPS + SPEED_EPS_MPS and _speed() < RUN_MPS,
		"run input starts accelerating immediately without snapping to top speed")
	await _ticks(_count(RUN_RESPONSE_S) - 1)
	check(absf(_speed() - RUN_MPS) <= SPEED_EPS_MPS, "Shift reaches 8m/s within 0.35s")
	var run_from := player.global_position
	await _ticks(_count(0.3))
	var run_distance := _flat(player.global_position - run_from).length()
	check(run_distance > walk_distance * 1.5, "running produces substantially more actual travel than walking")
	_shift(false)
	await _ticks(1)
	var first_return_speed := _speed()
	check(first_return_speed > WALK_MPS + SPEED_EPS_MPS and first_return_speed < RUN_MPS,
		"run release brakes toward walking instead of instantly clamping speed")
	await _ticks(_count(WALK_RETURN_S) - 1)
	check(absf(_speed() - WALK_MPS) <= SPEED_EPS_MPS, "run release settles to walking within 0.3s")
	print("PLAY04_SPRINT_TRAVEL ", JSON.stringify({"walk_distance_m": walk_distance,
		"run_distance_m": run_distance, "first_release_speed_mps": first_return_speed}))
	# Test the other binding as actual movement, not merely InputMap membership.
	_shoulder(true)
	await _ticks(_count(RUN_RESPONSE_S))
	check(absf(_speed() - RUN_MPS) <= SPEED_EPS_MPS, "left shoulder produces the same 8m/s run")

func _blocked_and_hidden() -> void:
	await _reset()
	player.input_enabled = false
	Input.action_press(&"move_forward")
	_shift(true)
	var from := player.global_position
	await _ticks(_count(0.4))
	check(_speed() <= SPEED_EPS_MPS and _flat(player.global_position - from).length() <= 0.01,
		"sprint and movement cannot move a player whose input is disabled")
	await _reset()
	Input.action_press(&"move_forward")
	_shift(true)
	await _ticks(_count(RUN_RESPONSE_S))
	check(absf(_speed() - RUN_MPS) <= SPEED_EPS_MPS, "blocking-from-run scenario reaches real running speed")
	var blocked_at := player.global_position
	player.input_enabled = false
	await _ticks(1)
	check(_speed() <= SPEED_EPS_MPS and _flat(player.global_position - blocked_at).length() <= 0.01,
		"dialogue-style input blocking immediately stops running momentum")
	await _ticks(_count(0.3))
	check(_flat(player.global_position - blocked_at).length() <= 0.01,
		"held movement and sprint add no travel while input is blocked")
	player.input_enabled = true
	for sample in [[&"box", 1.2], [&"barrel", 2.6]]:
		await _reset()
		player.force_hide_mode(sample[0])
		Input.action_press(&"move_forward")
		_shift(true)
		await _ticks(_count(0.4))
		check(absf(_speed() - sample[1]) <= SPEED_EPS_MPS,
			"%s keeps its own movement cap while sprint is held" % sample[0])
		Input.action_press(&"jump")
		await _ticks(1)
		Input.action_release(&"jump")
		check(player.is_on_floor() and absf(player.velocity.y) <= SPEED_EPS_MPS,
			"%s still forbids jumping while sprint is held" % sample[0])
	player.force_hide_mode(&"none")

func _run_jump_release() -> void:
	await _reset()
	Input.action_press(&"move_forward")
	_shift(true)
	await _ticks(_count(RUN_RESPONSE_S))
	check(absf(_speed() - RUN_MPS) <= SPEED_EPS_MPS, "run-jump scenario reaches the agreed takeoff speed")
	var took_off := await _jump_takeoff()
	check(took_off, "run-jump scenario actually leaves the floor")
	if not took_off:
		return
	check(absf(_speed() - RUN_MPS) <= SPEED_EPS_MPS, "jump takeoff retains 8m/s horizontal momentum")
	_shift(false)
	Input.action_release(&"move_forward")
	await _ticks(1)
	check(absf(_speed() - RUN_MPS) <= SPEED_EPS_MPS,
		"releasing sprint in the air does not instantly clamp momentum to walking")
	var air_from := player.global_position
	await _ticks(_count(AIR_COAST_S))
	check(not player.is_on_floor() and absf(_speed() - RUN_MPS) <= SPEED_EPS_MPS,
		"released run jump keeps its horizontal drift while airborne")
	check(_flat(player.global_position - air_from).length() >= RUN_MPS * AIR_COAST_S * 0.95,
		"airborne run momentum produces real displacement")
	var landed := await _wait_for_landing(2.0)
	check(landed, "released run jump lands within the jump budget")
	Input.action_press(&"move_forward")
	await _ticks(_count(WALK_RETURN_S))
	check(absf(_speed() - WALK_MPS) <= SPEED_EPS_MPS,
		"after landing without sprint, held movement returns to walking")

func _hide_transition_air() -> void:
	await _reset()
	Input.action_press(&"move_forward")
	_shift(true)
	await _ticks(_count(RUN_RESPONSE_S))
	check(await _jump_takeoff(), "hide-transition scenario starts in a real running jump")
	_shift(false)
	player.force_hide_mode(&"box")
	check(absf(player.speed_limit() - 1.2) <= SPEED_EPS_MPS and _speed() <= 1.2 + SPEED_EPS_MPS,
		"entering a hide during a jump immediately applies its motion cap")
	player.force_hide_mode(&"none")
	check(absf(player.speed_limit() - WALK_MPS) <= SPEED_EPS_MPS,
		"removing a hide in the air restores normal control without a stale run or hide cap")

func _reset_and_standing_jump() -> void:
	await _reset()
	Input.action_press(&"move_forward")
	_shift(true)
	await _ticks(_count(RUN_RESPONSE_S))
	await _reset()
	check(_speed() <= SPEED_EPS_MPS and player.global_position.distance_to(Vector3.ZERO) <= 0.02,
		"place/reset leaves no stored run movement after controls are released")
	var origin := player.global_position
	var apex := 0.0
	var flight_ticks := 0
	var took_off := await _jump_takeoff()
	check(took_off, "ordinary standing jump actually leaves the floor after run reset")
	if not took_off:
		return
	apex = maxf(0.0, player.global_position.y - origin.y)
	flight_ticks = 1
	while not player.is_on_floor() and flight_ticks < _count(2.0):
		await _ticks(1)
		flight_ticks += 1
		apex = maxf(apex, player.global_position.y - origin.y)
	check(player.is_on_floor(), "ordinary standing jump lands after run reset")
	check(absf(apex - JUMP_APEX_M) <= HEIGHT_EPS_M, "standing-jump height remains unchanged by running")
	check(absf(flight_ticks * dt - JUMP_FLIGHT_S) <= 2.0 * dt,
		"standing-jump flight time remains unchanged by running")
	check(_flat(player.global_position - origin).length() <= 0.01,
		"standing jump after reset adds no latent run displacement")
	print("PLAY04_SPRINT_STANDING ", JSON.stringify({"apex_m": apex, "flight_s": flight_ticks * dt}))

func _jump_takeoff() -> bool:
	Input.action_press(&"jump")
	for i in _count(0.1):
		await _ticks(1)
		if not player.is_on_floor() and player.velocity.y > 0.0:
			Input.action_release(&"jump")
			return true
	Input.action_release(&"jump")
	return false

func _wait_for_landing(budget: float) -> bool:
	for i in _count(budget):
		await _ticks(1)
		if player.is_on_floor():
			return true
	return false

func _reset() -> void:
	_release()
	player.input_enabled = true
	player.force_hide_mode(&"none")
	player.place(Vector3.ZERO, 0.0)
	rig.yaw = 0.0
	rig.follow(player, &"on_foot")
	rig.apply_mouse(Vector2.ZERO)
	await _ticks(_count(0.2))
	check(player.is_on_floor(), "scenario preflight reaches actual floor contact")

func _build_fixture() -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.position.y = -0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 1.0, 100.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	fixture.add_child(floor_body)
	player = PlayerScript.new()
	fixture.add_child(player)
	rig = CameraScript.new()
	fixture.add_child(rig)
	player.camera_rig = rig
	rig.follow(player, &"on_foot")

func _shift(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	event.keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)

func _shoulder(pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_LEFT_SHOULDER
	event.pressed = pressed
	Input.parse_input_event(event)

func _sprint_pressed() -> bool:
	return InputMap.has_action(&"sprint") and Input.is_action_pressed(&"sprint")

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	_shift(false)
	_shoulder(false)

func _ticks(count: int) -> void:
	for i in count:
		await observer.stepped
		maximum_speed = maxf(maximum_speed, _speed())

func _count(seconds: float) -> int:
	return maxi(1, ceili(seconds / dt))

func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)

func _speed() -> float:
	return _flat(player.velocity).length()

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

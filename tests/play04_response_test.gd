extends SceneTree
## PLAY-04: observable responsiveness of the actual walker, InputMap and auto-camera.
## This is our proposed responsiveness contract, not recovered original-game tuning.
## Run: tools/godot.sh --headless --path . --script tests/play04_response_test.gd
## Bounds were fixed before candidate changes. No velocity assignment or controller model.

const PlayerScript = preload("res://game/player/ilyusha.gd")
const CameraScript = preload("res://game/camera/camera_rig.gd")
const InputSetup = preload("res://game/input_setup.gd")
const ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump"]
const EXPECTED_TOP_MPS := 4.0
const SPEED_EPS_MPS := 0.02
const INITIAL_FULL_SPEED_S := 0.25
const STOP_BUDGET_S := 0.25
const STOP_DISTANCE_M := 0.5
const REVERSE_BUDGET_S := 0.3
const QUARTER_TURN_BUDGET_S := 0.25
const SETTLED_ANGLE_RAD := 0.1
const MAGNITUDE_HEADING_TOLERANCE_RAD := 0.01
const CAMERA_REBASE_EPS_RAD := 0.001

class PostPhysics:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var observer: PostPhysics
var fixture: Node3D
var player: Ilyusha
var rig: CameraRig
var checks := 0
var failures: Array[String] = []
var dt := 0.0
var maximum_speed := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	InputSetup.install()
	dt = 1.0 / Engine.physics_ticks_per_second
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("PLAY04_RESPONSE: watchdog exceeded 30 simulated seconds")
		quit(2))
	observer = PostPhysics.new()
	observer.process_physics_priority = 1000
	root.add_child(observer)
	_build_fixture()
	print("PLAY04_RESPONSE_PROFILE ", JSON.stringify({
		"scope": "real input to displacement/facing and camera-basis continuity on flat floor",
		"bounds": "own proposed responsiveness; not original loaded tuning",
		"physics_hz": Engine.physics_ticks_per_second,
		"player_sha256": FileAccess.get_sha256("res://game/player/ilyusha.gd"),
		"camera_sha256": FileAccess.get_sha256("res://game/camera/camera_rig.gd"),
		"test_sha256": FileAccess.get_sha256(get_script().resource_path),
		"top_mps": EXPECTED_TOP_MPS,
		"start_s": INITIAL_FULL_SPEED_S, "stop_s": STOP_BUDGET_S,
		"stop_distance_m": STOP_DISTANCE_M, "reverse_s": REVERSE_BUDGET_S,
		"quarter_turn_s": QUARTER_TURN_BUDGET_S,
		"magnitude_heading_tolerance_rad": MAGNITUDE_HEADING_TOLERANCE_RAD}))
	await _start_stop()
	await _turn_back()
	await _turn_right()
	await _analog_camera_continuity()
	await _partial_speed()
	check(maximum_speed <= EXPECTED_TOP_MPS + SPEED_EPS_MPS,
		"all response scenarios stay within the agreed speed limit")
	_release()
	fixture.queue_free()
	observer.queue_free()
	await process_frame
	print("PLAY04_RESPONSE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _start_stop() -> void:
	await _reset()
	Input.action_press(&"move_forward")
	var start := player.global_position
	await _ticks(_count(INITIAL_FULL_SPEED_S))
	check(_speed() >= EXPECTED_TOP_MPS - SPEED_EPS_MPS,
		"full input reaches the agreed walking speed within 0.25s")
	check((player.global_position - start).dot(Vector3.FORWARD) > 0.1,
		"start response produces real forward displacement")
	await _ticks(_count(0.1))
	var release_at := player.global_position
	_release()
	await _ticks(_count(STOP_BUDGET_S))
	check(_speed() <= SPEED_EPS_MPS, "released ground input stops within 0.25s")
	await _ticks(_count(0.35))
	var stop_distance := _flat(player.global_position - release_at).length()
	check(stop_distance < STOP_DISTANCE_M, "release travels less than 0.5m before stopping")
	print("PLAY04_RESPONSE_STOP ", JSON.stringify({"distance_m": stop_distance, "speed_mps": _speed()}))

func _turn_back() -> void:
	await _reset()
	Input.action_press(&"move_forward")
	await _ticks(_count(INITIAL_FULL_SPEED_S + 0.05))
	var incoming := _flat(player.velocity).normalized()
	var switch_at := player.global_position
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	await _ticks(1)
	var first_displacement := _flat(player.global_position - switch_at)
	check(first_displacement.dot(incoming) > 0.0,
		"opposite input does not instantly reverse actual travel on the first tick")
	await _ticks(_count(REVERSE_BUDGET_S) - 1)
	var desired := -incoming
	check(_flat(player.velocity).dot(desired) >= EXPECTED_TOP_MPS * 0.9,
		"opposite input reaches useful reverse travel within 0.3s")
	check(_heading_gap(player.facing_dir(), desired) <= SETTLED_ANGLE_RAD,
		"opposite input finishes turning the visible character within 0.3s")
	print("PLAY04_RESPONSE_REVERSE ", JSON.stringify({
		"first_incoming_displacement_m": first_displacement.dot(incoming),
		"settled_reverse_mps": _flat(player.velocity).dot(desired)}))

func _turn_right() -> void:
	await _reset()
	Input.action_press(&"move_forward")
	await _ticks(_count(INITIAL_FULL_SPEED_S + 0.05))
	Input.action_release(&"move_forward")
	Input.action_press(&"move_right")
	var turn_at := player.global_position
	await _ticks(_count(QUARTER_TURN_BUDGET_S))
	check(_heading_gap(_flat(player.velocity), Vector3.RIGHT) <= SETTLED_ANGLE_RAD,
		"90-degree input settles actual travel toward the requested side within 0.25s")
	check(_heading_gap(player.facing_dir(), Vector3.RIGHT) <= SETTLED_ANGLE_RAD,
		"90-degree input settles the visible facing within 0.25s")
	check((player.global_position - turn_at).dot(Vector3.RIGHT) > 0.1,
		"90-degree turn produces actual progress toward the requested side")

func _analog_camera_continuity() -> void:
	await _reset()
	Input.action_press(&"move_right", 0.8)
	await _ticks(_count(3.0))
	var before_direction := _flat(player.velocity)
	var accumulated_yaw := absf(angle_difference(rig.input_yaw, rig.yaw))
	check(accumulated_yaw >= 0.5,
		"analog scenario reaches substantial real automatic camera rotation")
	Input.action_press(&"move_right", 0.81)
	await _ticks(1)
	var magnitude_heading_jump := _heading_gap(before_direction, _flat(player.velocity))
	check(magnitude_heading_jump <= MAGNITUDE_HEADING_TOLERANCE_RAD,
		"same-angle stick magnitude change does not steer the character with automatic camera yaw")
	var before_jitter := _flat(player.velocity)
	Input.action_press(&"move_forward", 0.001)
	await _ticks(1)
	check(_heading_gap(before_jitter, _flat(player.velocity)) <= MAGNITUDE_HEADING_TOLERANCE_RAD,
		"tiny stick angle noise does not adopt accumulated automatic camera rotation")
	Input.action_release(&"move_forward")
	var camera_basis_before_turn := rig.yaw
	Input.action_release(&"move_right")
	Input.action_press(&"move_forward", 0.81)
	await _ticks(1)
	check(absf(angle_difference(camera_basis_before_turn, rig.input_yaw)) <= CAMERA_REBASE_EPS_RAD,
		"genuine stick direction change adopts the current camera basis")
	print("PLAY04_RESPONSE_ANALOG ", JSON.stringify({
		"accumulated_camera_yaw_rad": accumulated_yaw,
		"magnitude_heading_jump_rad": magnitude_heading_jump,
		"direction_change_basis_error_rad": absf(angle_difference(camera_basis_before_turn, rig.input_yaw))}))

func _partial_speed() -> void:
	for sample in [[0.5, 0.6, 0.8], [0.75, 2.4, 2.8]]:
		await _reset()
		Input.action_press(&"move_forward", sample[0])
		await _ticks(_count(0.3))
		var speed := _speed()
		check(speed >= sample[1] and speed <= sample[2],
			"partial input %.2f provides useful walking speed without a full-speed jump" % sample[0])
		print("PLAY04_RESPONSE_PARTIAL ", JSON.stringify({"raw_strength":sample[0],"speed_mps":speed}))

func _reset() -> void:
	_release()
	player.place(Vector3.ZERO, 0.0)
	rig.yaw = 0.0
	rig.follow(player, &"on_foot")
	rig.apply_mouse(Vector2.ZERO)
	await _ticks(_count(0.2))
	check(player.is_on_floor() and player.input_enabled and player.camera_rig == rig,
		"scenario preflight: actual enabled player has floor contact and real camera")

func _build_fixture() -> void:
	fixture = Node3D.new()
	fixture.name = "ResponseFixture"
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
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

func _ticks(count: int) -> void:
	for i in count:
		await observer.stepped
		maximum_speed = maxf(maximum_speed, _speed())

func _count(seconds: float) -> int:
	return maxi(1, ceili(seconds / dt))

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)

func _speed() -> float:
	return _flat(player.velocity).length()

func _heading_gap(first: Vector3, second: Vector3) -> float:
	if first.length_squared() < 0.000001 or second.length_squared() < 0.000001:
		return PI
	return absf(first.signed_angle_to(second, Vector3.UP))

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

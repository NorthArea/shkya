extends "res://tools/play04_car_measure.gd"
## Independent PLAY-04 car-input oracle; controller author owns a separate scope.
## Run with the existing provider: tools/godot.sh --headless --path . --script tests/play04_car_test.gd -- --skip-intro
## Mechanisms only: 3UR/Simpsons-Hit-Run@c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6.
## OUR bounds below are not original C++ vehicle tuning or a feel/visual acceptance.
## Baseline: builds/checks/PLAY-04/car/baseline.log, MEASURED, invalid_measurements=[], 60 Hz.
## Baseline did not reach forward cap or measure snow, handbrake, grip, collisions or C4 exit.
## The small additional input cases below cover smoke properties, not historical numeric preservation for those gaps.
## Mandatory outside this slice: DRIVE01, DRIVE02, STUCK, PAD01, COINS/BREAK, STEALTH, DEMO_ACCEPTANCE, C9 FPS/manual route.

const SOURCE_PIN := "3UR/Simpsons-Hit-Run@c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6"
const PROVIDER_SHA256 := "d82563b7bd092759a707a404169936af0b9fe0c760947fc2c1b3486037cea6a7"
const BASELINE_LOG_SHA256 := "31ac3d3b50d20b7148e0152fd87c70a70635c60458171d1da83aef89ad4cb84e"
const BASELINE_CAR_SHA256 := "752910fac34a95bdccf4945a4bc9f54b46f58a857424d1cb53633a564d6ffb6b"
const PRESERVED_LIMITS := {"forward_mps": 28.0, "reverse_mps": 10.0, "full_accel_mps2": 9.0, "full_brake_mps2": 24.0}
const PRESERVED_HANDLING := {"roll_drag": 2.0, "air_drag": 0.004, "handbrake": 8.0, "handbrake_turn": 1.4,
	"grip": 7.0, "handbrake_grip": 1.2, "turn_low": 1.3, "turn_high": 0.85, "turn_full_at": 5.0}
const SPEED_PRESERVATION_MPS := 0.08 # < one 60 Hz full-gas step (0.15 m/s); prevents full-pedal retuning
const ACCEL_PRESERVATION_MPS2 := 0.10 # < 0.5% full braking; separate from new partial-input response
const TIME_TOLERANCE_TICKS := 2.0 # fixed-step zero-cross discretization
const INPUT_EPS := 0.00001
const REST_EPS_MPS := 0.01 # provider resolution
const PARTIAL_GAP_MPS2 := 0.05 # distinguish real ordered braking from binary or numerically tiny differences
const PARTIAL_GAP_MPS := 0.02
const STEER_RATE_BOUND := 5.0 # our normalized units/s ceiling, NOT a C++ numeric tune
const STEER_RATE_EPS := 0.0001
const STEER_POSITION_EPS := 0.00001
const LOCAL_PLANE_EPS_M := 0.01 # independent flat-patch compatibility, not Layout coordinates

var checks := 0
var failures: Array[String] = []

func _assess() -> int:
	check(invalid.is_empty(), "provider reached every baseline scenario without measurement contamination")
	if not invalid.is_empty(): return failures.size()
	var profile: Dictionary = measurements.profile
	check(profile.source == SOURCE_PIN, "primary source pin is explicit")
	check(profile.measurement_sha256 == PROVIDER_SHA256, "qualified measurement provider is unchanged")
	_fixture_compatibility(profile)
	for key: String in PRESERVED_LIMITS:
		check(is_equal_approx(float(profile.limits[key]), PRESERVED_LIMITS[key]), "preserved configured limit: " + key)
	for key: String in PRESERVED_HANDLING:
		check(is_equal_approx(float(profile.preserved_handling[key]), PRESERVED_HANDLING[key]), "preserved handling parameter: " + key)
	check(car.collision_mask & 64 == 0, "C10: SnowBank remains a SnowField surface rather than a car wall")
	_preserved_endpoints()
	_pedal_independence()
	_partial_brakes()
	_steer_properties()
	return failures.size()

## Layout/project hashes remain provenance emitted by the provider. Compatibility of this
## translation-invariant dynamics experiment depends on its real local conditions, not unrelated appended data.
func _fixture_compatibility(profile: Dictionary) -> void:
	check(profile.physics_hz == 60, "baseline preservation is scoped to the measured 60 Hz physics profile")
	check(profile.engine.major == 4 and profile.engine.minor == 7 and profile.engine.patch == 2,
		"comparison uses the measured Godot 4.7.2 engine version")
	for action: StringName in ACTIONS:
		var expected := 0.05 if action in [&"car_gas", &"car_brake"] else 0.25
		check(is_equal_approx(float(profile.action_deadzones[action]), expected), "measured input deadzone matches its pedal/stick context: " + String(action))
	check(car.collision_layer == 4 and car.collision_mask == (1 | 32), "C2: actual Lada retains Car layer and World/Breakable contact masks")
	check(road.has_area() and road.has_point(Vector2(origin.x, origin.z)), "derived fixture origin lies on the current canonical Street B")
	check(world.camera_rig.target == car and world.camera_rig.profile == &"in_car", "C4: measured input is driving the actual car camera profile")

func _preserved_endpoints() -> void:
	for item: Array in [["gas_1.00", 15.8913097381592], ["gas_0.50", 8.70577907562256],
		["gas_0.75", 12.5528898239136], ["coast", 13.0513677597046], ["brake_full", -2.54369068145752],
		["forward_to_reverse", -10.0], ["reverse_full", -10.0], ["reverse_to_forward", 13.4137592315674]]:
		var result: Dictionary = measurements[item[0]]
		check(absf(float(result.final.forward_speed) - float(item[1])) <= SPEED_PRESERVATION_MPS,
			"baseline full-pedal/coast endpoint preserved: " + item[0])
	for item: Array in [["gas_1.00", -9.0], ["gas_0.50", -4.5], ["gas_0.75", -6.75],
		["coast", 3.01013946533203], ["brake_full", 24.0], ["reverse_full", 8.1], ["reverse_to_forward", -24.0]]:
		check(absf(float(measurements[item[0]].first_deceleration_mps2) - float(item[1])) <= ACCEL_PRESERVATION_MPS2,
			"baseline first input response preserved: " + item[0])
	for item: Array in [["forward_to_reverse", 0.7], ["reverse_to_forward", 0.383333333333333]]:
		var crossing: Variant = measurements[item[0]].direction_cross_s
		check(crossing != null and absf(float(crossing) - float(item[1])) <= TIME_TOLERANCE_TICKS * dt,
			"baseline single-pedal direction transition preserved: " + item[0])
	check(float(measurements["gas_0.50"].final.forward_speed) < float(measurements["gas_0.75"].final.forward_speed)
		and float(measurements["gas_0.75"].final.forward_speed) < float(measurements["gas_1.00"].final.forward_speed),
		"independent partial gas retains its ordered positive speed response")

func _pedal_independence() -> void:
	for item: Array in [["both_full", 1.0, 1.0], ["gas_half_brake_full", 0.5, 1.0], ["reverse_both", 1.0, 1.0]]:
		var result: Dictionary = measurements[item[0]]
		check(absf(float(result.first.gas_input) - float(item[1])) <= INPUT_EPS
			and absf(float(result.first.brake_input) - float(item[2])) <= INPUT_EPS,
			item[0] + ": real Input carries gas and brake simultaneously")
		_check_both_stop(item[0], result)

func _check_both_stop(label: String, result: Dictionary) -> void:
	var direction := signf(float(result.entry.forward_speed))
	check(bool(result.first.braking), label + ": actual full-brake response publishes its braking signal for lights/FX")
	check(absf(absf(float(result.first_deceleration_mps2)) - PRESERVED_LIMITS.full_brake_mps2) <= ACCEL_PRESERVATION_MPS2,
		label + ": held gas does not weaken a full braking response")
	var ideal_seconds := absf(float(result.entry.forward_speed)) / PRESERVED_LIMITS.full_brake_mps2
	check(result.stop_s != null and absf(float(result.stop_s) - ideal_seconds) <= TIME_TOLERANCE_TICKS * dt,
		label + ": full brake dominates and reaches rest within the preserved full-brake stop window")
	var stopped := false
	var held_at_rest := true
	var no_direction_cross := true
	for sample: Dictionary in result.samples:
		no_direction_cross = no_direction_cross and float(sample.forward_speed) * direction >= -REST_EPS_MPS
		if float(sample.speed) <= REST_EPS_MPS: stopped = true
		if stopped and float(sample.speed) > REST_EPS_MPS: held_at_rest = false
	check(no_direction_cross and result.direction_cross_s == null, label + ": both pedals never reverse driving direction")
	check(stopped and held_at_rest and float(result.final.speed) <= REST_EPS_MPS,
		label + ": both pedals hold the car still after the stop")

func _partial_brakes() -> void:
	var ordered: Array[String] = ["coast", "brake_tenth", "brake_quarter", "brake_half", "brake_full"]
	for i in range(1, ordered.size()):
		var lighter: Dictionary = measurements[ordered[i - 1]]
		var stronger: Dictionary = measurements[ordered[i]]
		check(absf(float(lighter.entry.forward_speed) - float(stronger.entry.forward_speed)) <= REST_EPS_MPS,
			ordered[i] + ": comparison starts from the same actual driven speed")
		check(float(stronger.first_deceleration_mps2) >= float(lighter.first_deceleration_mps2) + PARTIAL_GAP_MPS2,
			ordered[i] + ": stronger real brake input increases initial deceleration between coast and full")
		check(float(stronger.final.forward_speed) <= float(lighter.final.forward_speed) - PARTIAL_GAP_MPS,
			ordered[i] + ": stronger brake lowers final forward speed without a binary partial-brake plateau")
	for item: Array in [["brake_tenth", 0.1], ["brake_quarter", 0.25], ["brake_half", 0.5]]:
		var first: Dictionary = measurements[item[0]].first
		check(absf(float(first.gas_input)) <= INPUT_EPS and absf(float(first.brake_input) - float(item[1])) <= INPUT_EPS,
			item[0] + ": requested analog brake strength reaches real Input unchanged")

func _steer_properties() -> void:
	for label: String in measurements:
		var result: Variant = measurements[label]
		if not result is Dictionary or not result.has("samples") or not ("stationary_" in label or label.ends_with("_left") or label.ends_with("_right")):
			continue
		var target: float = result.first.steer_input
		var previous: float = result.entry.steer
		var direction := signf(target - previous)
		var monotone := true
		var bounded := true
		for sample: Dictionary in result.samples:
			var value: float = sample.steer
			bounded = bounded and absf(value - previous) <= STEER_RATE_BOUND * dt + STEER_POSITION_EPS
			monotone = monotone and (value - previous) * direction >= -STEER_POSITION_EPS
			monotone = monotone and (target - value) * direction >= -STEER_POSITION_EPS
			previous = value
		check(bounded and float(result.maximum_steer_rate_units_s) <= STEER_RATE_BOUND + STEER_RATE_EPS,
			label + ": actual steering change stays within our 5 normalized units/s limit")
		check(monotone, label + ": response advances monotonically toward target without overshoot")
		var distance := absf(target - float(result.entry.steer))
		check(distance <= STEER_POSITION_EPS or absf(float(result.first_steer_step)) > STEER_POSITION_EPS,
			label + ": new steering input produces a nonzero first response")
		if label.begins_with("stationary_"):
			check(result.steer_settle_s != null and absf(float(result.final.steer) - target) <= STEER_POSITION_EPS,
				label + ": stationary step/reversal/release reaches its finite target within 0.65 s")
			check(float(result.path_length_m) <= REST_EPS_MPS, label + ": parking steering does not move the car")
		if result.steer_settle_s != null:
			check(float(result.steer_settle_s) + dt >= distance / STEER_RATE_BOUND,
				label + ": target arrival respects the necessary travel time of the rate bound")
	for label in ["moving_forward_left", "moving_reverse_left"]:
		var result: Dictionary = measurements[label]
		check(absf(float(result.yaw_change_rad)) > 0.01, label + ": smoothed input still changes real vehicle heading")
	check(float(measurements.moving_forward_left.yaw_change_rad) > 0.0
		and float(measurements.moving_reverse_left.yaw_change_rad) < 0.0,
		"the same left input turns forward and reverse motion in their respective directions")

func _all_samples() -> void:
	var finite := true
	var within_limits := true
	var compatible_floor := true
	var compatible_road := true
	var outside_mission_areas := true
	for result: Variant in measurements.values():
		if not result is Dictionary or not result.has("samples"): continue
		var entry_height: float = result.entry.position[1]
		for sample: Dictionary in result.samples:
			var at := _position(sample)
			compatible_floor = compatible_floor and bool(sample.floor) and not bool(sample.airborne) \
				and float(sample.snow_depth) == 0.0 and absf(at.y - entry_height) <= LOCAL_PLANE_EPS_M
			var pose := Transform3D(Basis(Vector3.UP, float(sample.yaw)), at)
			for side_x in [-1.0, 1.0]:
				for side_z in [-1.0, 1.0]:
					var corner := pose * Vector3(side_x * car.SIZE.x * 0.5, 0.0, side_z * car.SIZE.z * 0.5)
					var xz := Vector2(corner.x, corner.z)
					compatible_road = compatible_road and road.has_point(xz)
					outside_mission_areas = outside_mission_areas and not Layout.KIOSK_SQUARE.has_point(xz) \
						and not Layout.ROOF_AREA.has_point(xz) and not Layout.KIOSK_ZONE.has_point(corner)
			finite = finite and at.is_finite() and is_finite(float(sample.speed)) and is_finite(float(sample.steer))
			within_limits = within_limits and float(sample.forward_speed) <= PRESERVED_LIMITS.forward_mps + SPEED_PRESERVATION_MPS
			within_limits = within_limits and float(sample.forward_speed) >= -PRESERVED_LIMITS.reverse_mps - SPEED_PRESERVATION_MPS
	check(compatible_floor, "fixture compatibility: every sample stays grounded on one flat snow-free patch")
	check(compatible_road, "fixture compatibility: the full sampled car footprint stays inside the current Street B")
	check(outside_mission_areas, "fixture compatibility: all sampled car corners remain outside kiosk/roof/mission areas")
	check(finite, "all recorded real input samples retain finite position/speed/steering")
	check(within_limits, "sampled forward/reverse speeds remain inside preserved configured caps (forward cap was not reached)")

## Keep the qualified provider as the one runner; extend its existing completion hook before teardown.
func _finish(exit_code: int) -> void:
	if invalid.is_empty():
		await _extra_input_cases()
		_all_samples()
		await _c4_input_roundtrip()
	check(invalid.is_empty(), "additional input cases retained the uncontaminated fixture")
	var code := 0 if exit_code == 0 and failures.is_empty() and invalid.is_empty() else 1
	print("PLAY04_CAR: %d checks, %d failures; baseline_car=%s baseline_log=%s" % [checks, failures.size(), BASELINE_CAR_SHA256, BASELINE_LOG_SHA256])
	print("PLAY04_CAR_SCOPE: input/pedals/steering only; full-speed attainment, snow/collision regression, C9 FPS and manual feel acceptance remain NOT_RUN")
	await super._finish(code)

func _extra_input_cases() -> void:
	await _reset()
	_pedals(1.0, 1.0)
	var stationary: Dictionary = await _record("both_stationary_extra", 1.0)
	check(float(stationary.max_forward_mps) <= REST_EPS_MPS and float(stationary.min_forward_mps) >= -REST_EPS_MPS
		and float(stationary.path_length_m) <= REST_EPS_MPS,
		"both full pedals from a real standstill neither launch forward nor engage reverse")
	await _reset()
	_pedals(1.0, 0.0)
	await _record("handbrake_runup_extra", RUNUP_SECONDS)
	_pedals(0.0, 0.0)
	Input.action_press(&"handbrake")
	var handbrake: Dictionary = await _record("handbrake_extra", PEDAL_SECONDS)
	check(absf(float(handbrake.first_deceleration_mps2) - PRESERVED_HANDLING.handbrake) <= ACCEL_PRESERVATION_MPS2,
		"real handbrake retains the configured full longitudinal braking response")
	check(float(handbrake.final.forward_speed) < float(measurements.coast.final.forward_speed) - 1.0,
		"real handbrake slows more than coast from the same driven runup")
	await _reset()
	_pedals(1.0, 0.0)
	await _record("grip_runup_extra", MOVING_RUNUP_SECONDS)
	_steering(1.0)
	await _record("grip_turn_extra", MOVING_STEER_SECONDS)
	_pedals(0.0, 0.0)
	_steering(0.0)
	var recovery: Dictionary = await _record("grip_recovery_extra", STEER_SECONDS)
	check(float(recovery.entry.lateral_speed) > 0.02 and float(recovery.final.lateral_speed) < float(recovery.entry.lateral_speed) * 0.5,
		"real input creates lateral motion and ordinary grip recovers after steering is released")
	_release()

func _c4_input_roundtrip() -> void:
	await _reset()
	await _interact()
	check(world.control_mode == &"on_foot" and car.driver == null, "C4: real interaction exits a stopped car")
	check(world.player.visible and world.player.input_enabled and not (world.player.get_node("CollisionShape3D") as CollisionShape3D).disabled,
		"C4: exit restores visible on-foot input and collision")
	check(world.player.global_position.distance_to(car.global_position) < 4.0
		and world.camera_rig.target == world.player and world.camera_rig.profile == &"on_foot",
		"C4: exit stays beside the car and restores the on-foot camera")
	await _interact()
	check(world.control_mode == &"in_car" and car.driver == world.player, "C4: real interaction re-enters the same car")
	check(not world.player.visible and not world.player.input_enabled and (world.player.get_node("CollisionShape3D") as CollisionShape3D).disabled,
		"C4: car mode suppresses on-foot visibility/input/collision again")
	check(world.camera_rig.target == car and world.camera_rig.profile == &"in_car", "C4: camera follows the car after re-entry")

func _interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(2)
	event = InputEventAction.new()
	event.action = &"interact"
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(4)

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("PLAY04_CAR FAIL: " + label)
	return condition

extends "res://tools/play04_measure.gd"
## PLAY-04 independent first-slice properties. Uses real measured runtime, no controller model.
## tools/godot.sh --headless --path . --script tests/play04_motion_test.gd -- --skip-intro
## C++ pin/principles and configuration are emitted by the measurement provider.
## Bounds below are OUR preservation/behaviour contract, not unavailable original loaded tuning.
## Baseline evidence: builds/checks/REVIEW-01/play04_baseline.log, 60 Hz, on flat Layout.SPAWN.
## Only this on-foot slice: existing C7/roof/pad/interaction/visual suites remain mandatory.

const PRESERVED_WALK_MPS := 4.0
const PRESERVED_APEX_M := 1.8877
const PRESERVED_FLIGHT_S := 1.25
const PRESERVED_APEX_SECONDS := 0.616666666666667
const SPEED_TOLERANCE_MPS := 0.01 # below one original acceleration step; no max-speed retuning
const HEIGHT_TOLERANCE_M := 0.02 # 2 cm permits collision safe-margin variation, not roof reach changes
const TIME_TOLERANCE_TICKS := 2.0 # takeoff/landing discretization, no gravity/jump-tempo retuning
const TURN_SPEED_FLOOR := 0.9 # scalar speed: at most 10% transient loss; rejects vector cancellation
const NONLINEAR_MARGIN := 0.03 # 3% full-speed gap visibly separates curve from baseline linear response
const AIR_SPEED_TOLERANCE := 0.02 # 2% numerical margin around inertial coast, no release brake
const AIR_DIRECTION_TOLERANCE_RAD := 0.02 # ~1 degree; collision-free released input adds no turn
const CAMERA_HEIGHT_TOLERANCE_M := 0.05 # 5 cm on flat ground: hold ground view, baseline follows 1.86 m
const FACING_ANGLE_EPSILON_RAD := 0.01 # distinguish smooth turn from zero update/instant snap

var checks := 0
var failures: Array[String] = []

func _assess() -> int:
	check(invalid.is_empty(), "measurement reached real on-foot scenarios without contamination")
	if not invalid.is_empty():
		print("PLAY04_MOTION: %d checks, %d failures; invalid measurements prevent behavioural assessment" % [checks, failures.size()])
		return failures.size()
	var ground: Array = measurements["ground"]
	var full: Dictionary = ground[0]
	check(absf(full.steady_mps - PRESERVED_WALK_MPS) <= SPEED_TOLERANCE_MPS,
		"full-stick walking preserves the existing speed limit")
	check(full.t90_s != null and full.stop_s != null,
		"real input reaches steady speed and released ground input stops within measurement windows")
	var half: Dictionary = ground[1]
	var three_quarters: Dictionary = ground[2]
	check(half.strength_effective > 0.0 and half.strength_effective < three_quarters.strength_effective,
		"partial inputs remain ordered after actual InputMap deadzone")
	check(half.steady_mps > SPEED_TOLERANCE_MPS and half.steady_mps < three_quarters.steady_mps and three_quarters.steady_mps < full.steady_mps,
		"partial-stick speed stays positive and monotonic")
	for partial: Dictionary in [half, three_quarters]:
		check(partial.fraction_of_full <= partial.strength_effective - NONLINEAR_MARGIN,
			"partial effective stick %.3f has nonlinear sublinear speed response" % partial.strength_effective)
	for name in ["turn90", "turn180"]:
		var turn: Dictionary = measurements[name]
		check(turn.min_speed_ratio >= TURN_SPEED_FLOOR,
			name + ": full-stick turn preserves scalar speed without cancellation stop")
		check(turn.max_speed_mps <= PRESERVED_WALK_MPS + SPEED_TOLERANCE_MPS,
			name + ": turning does not increase the speed limit")
		var requested_turn := PI * 0.5 if name == "turn90" else PI
		var first_turn := absf(angle_difference(turn.entry_facing_rad, turn.first_facing_rad))
		check(first_turn > FACING_ANGLE_EPSILON_RAD and first_turn < requested_turn - FACING_ANGLE_EPSILON_RAD,
			name + ": facing rotates gradually while scalar speed is retained")
	var hold: Dictionary = measurements["jump_hold"]
	var released: Dictionary = measurements["jump_release"]
	var reverse: Dictionary = measurements["jump_reverse"]
	var standing: Dictionary = measurements["jump_standing"]
	for name in ["jump_hold", "jump_release", "jump_reverse", "jump_standing"]:
		var jump: Dictionary = measurements[name]
		check(absf(jump.apex_m - PRESERVED_APEX_M) <= HEIGHT_TOLERANCE_M,
			name + ": existing jump height / roof reach is preserved")
		check(absf(jump.flight_s - PRESERVED_FLIGHT_S) <= TIME_TOLERANCE_TICKS * dt and absf(jump.apex_s - PRESERVED_APEX_SECONDS) <= TIME_TOLERANCE_TICKS * dt,
			name + ": existing apex and flight timing is preserved")
		check(jump.probe_airborne, name + ": air probe precedes real landing")
		check(jump.max_speed_mps <= PRESERVED_WALK_MPS + SPEED_TOLERANCE_MPS,
			name + ": air control stays within existing speed limit")
		check(jump.camera_vertical_excursion_m <= CAMERA_HEIGHT_TOLERANCE_M and jump.pivot_vertical_excursion_m <= CAMERA_HEIGHT_TOLERANCE_M,
			name + ": camera and pivot retain ground height during flat-ground jump")
		check(absf(jump.entry.fov - jump.landing.fov) <= 0.01,
			name + ": on-foot jump preserves FOV")
	check(absf(released.release_speed_ratio - 1.0) <= AIR_SPEED_TOLERANCE,
		"released air input retains horizontal drift instead of applying ground brake")
	check(absf(angle_difference(released.switch.motion, released.probe.motion)) <= AIR_DIRECTION_TOLERANCE_RAD,
		"released air input preserves drift direction")
	var release_motion := _flat_sample_velocity(released.switch).normalized()
	var release_progress := _sample_position(released.probe) - _sample_position(released.switch)
	check(release_progress.dot(release_motion) > SPEED_TOLERANCE_MPS,
		"released air input actually moves forward in the world")
	var incoming := _flat_sample_velocity(reverse.switch).normalized()
	var before_component := _flat_sample_velocity(reverse.switch).dot(incoming)
	var first_component := _flat_sample_velocity(reverse.first_after_switch).dot(incoming)
	var later_component := _flat_sample_velocity(reverse.probe).dot(incoming)
	check(first_component > 0.0 and later_component < before_component - SPEED_TOLERANCE_MPS,
		"opposite air input changes momentum gradually, without instantaneous reversal")
	check(absf(hold.probe.speed - hold.switch.speed) <= SPEED_TOLERANCE_MPS,
		"held forward air input retains capped walking momentum")
	check(standing.range_m <= SPEED_TOLERANCE_MPS,
		"standing jump adds no horizontal displacement")
	print("PLAY04_MOTION: %d checks, %d failures" % [checks, failures.size()])
	return failures.size()

func _flat_sample_velocity(sample: Dictionary) -> Vector3:
	return Vector3(sample.velocity[0], 0.0, sample.velocity[2])

func _sample_position(sample: Dictionary) -> Vector3:
	return Vector3(sample.position[0], sample.position[1], sample.position[2])

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

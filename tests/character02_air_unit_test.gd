extends SceneTree
## Developer checks for the state/velocity helper. Actual CharacterBody3D,
## controls, target filtering and perimeter qualification require integration QA.
const Air = preload("res://game/player/character_air_motion.gd")
const DT := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_jumps()
	_air_attacks()
	_reset_and_contacts()
	_rates()
	_midpoint_contract()
	print("CHARACTER02_AIR_UNIT: %d checks, %d failures; controller/collisions/perimeter NOT_RUN" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHARACTER02_AIR_UNIT: " + label)

func _launched() -> Air:
	var air := Air.new()
	air.begin_step(DT, Vector3.ZERO, true, Vector3.ZERO, 4.0, true)
	air.resolve_contacts(false)
	return air

func _jumps() -> void:
	var air := Air.new()
	var standing: Vector3 = air.begin_step(DT, Vector3(2, -3, 0), true, Vector3.ZERO, 4, false)
	check(standing == Vector3(2, 0, 0), "ground contact clears vertical drift without changing controller horizontal motion")
	var velocity: Vector3 = air.begin_step(DT, Vector3(8, 0, 0), true, Vector3.ZERO, 8.0, true)
	var impulse := sqrt(2.0 * Air.GRAVITY * Air.FIRST_HEIGHT)
	check(is_equal_approx(velocity.y, impulse - 0.5 * Air.GRAVITY * DT), "first jump proposes the analytic mean velocity of its launch step")
	check(velocity.x == 8.0 and air.jump_count == 1 and air.phase == &"launch", "launch preserves sprint momentum and starts the first jump")
	var takeoff: Dictionary = air.resolve_contacts(false)
	check(takeoff.took_off, "takeoff is reported after controller resolves the move")
	check(is_equal_approx(velocity.y + float(takeoff.vertical_correction), impulse - Air.GRAVITY * DT), "resolved free launch restores physical endpoint velocity")
	check(not air.resolve_contacts(false).took_off, "duplicate contact resolution cannot repeat takeoff")
	velocity = air.begin_step(DT, Vector3(8, 3, 0), false, Vector3.ZERO, 8, true)
	check(air.jump_count == 1 and velocity.y < 3.0, "early second jump above its upward window is rejected")
	velocity = air.begin_step(DT, Vector3(8, 0, 0), false, Vector3.ZERO, 8, false)
	check(air.jump_count == 1 and velocity.y < 0, "rejected early press is not buffered until the apex")
	velocity = air.begin_step(DT, Vector3(8, 2, 0), false, Vector3.ZERO, 8, true)
	check(air.jump_count == 2 and is_equal_approx(velocity.y, sqrt(2.0 * Air.GRAVITY * Air.SECOND_HEIGHT) - 0.5 * Air.GRAVITY * DT), "second jump accepts the physical upper window boundary and proposes its mean launch velocity")
	velocity = air.begin_step(DT, Vector3(8, 0, 0), false, Vector3.ZERO, 8, true)
	check(air.jump_count == 2 and velocity.y < 0, "third jump is rejected")
	air = _launched()
	velocity = air.begin_step(DT, Vector3(0, -12, 0), false, Vector3.ZERO, 4, true)
	check(air.jump_count == 2 and velocity.y > 0, "second jump accepts the lower window boundary")
	air = _launched()
	velocity = air.begin_step(DT, Vector3(0, -12.1, 0), false, Vector3.ZERO, 4, true)
	check(air.jump_count == 1 and velocity.y < -12, "late falling second jump is rejected")
	air = Air.new()
	velocity = air.begin_step(DT, Vector3(2, -1, 0), false, Vector3.ZERO, 4, true)
	check(air.natural_fall and air.jump_count == 0 and velocity.y < 0, "walking off a ledge grants no midair jump")
	check(air.request_air_attack(false) == &"", "natural fall grants no airborne attack")
	var landing: Dictionary = air.resolve_contacts(true)
	check(landing.landed and not landing.stomp_landed and air.phase == &"land", "natural fall can land in its first controller move")

func _air_attacks() -> void:
	var air := _launched()
	check(air.request_air_attack(false) == &"jump_kick", "attack during the first jump selects a kick")
	check(air.request_air_attack(false) == &"", "repeated attack cannot restart the air action")
	air.begin_step(0.10, Vector3(0, 1, 0), false, Vector3.ZERO, 4, true)
	check(air.jump_count == 1 and not air.resolve_contacts(false).air_hit, "air kick prevents a second jump and has no premature hit")
	air.begin_step(0.03, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	check(air.resolve_contacts(false).air_hit, "kick crosses one authored impact phase")
	check(not air.resolve_contacts(false).air_hit, "reading contacts twice cannot repeat the kick impact")
	air.begin_step(1.0, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	check(not air.resolve_contacts(false).air_hit, "completed kick does not repeat its impact later in the flight")
	air = _launched()
	air.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 8, true)
	check(air.request_air_attack(false) == &"stomp_antic", "attack after the second jump selects a stomp")
	var velocity: Vector3 = air.begin_step(0.05, Vector3(8, 6, 2), false, Vector3.RIGHT, 8, false)
	check(velocity == Vector3.ZERO, "stomp anticipation holds both horizontal and vertical movement")
	velocity = air.begin_step(0.05, velocity, false, Vector3.RIGHT, 8, false)
	check(velocity == Vector3.ZERO and air.action == &"stomp_antic", "stomp hold does not accumulate gravity")
	velocity = air.begin_step(0.05, velocity, false, Vector3.RIGHT, 8, false)
	check(air.action == &"stomp_air" and velocity.y < 0 and velocity.x == 0 and velocity.z == 0, "stomp leaves anticipation into a strictly downward fall")
	velocity.y += float(air.resolve_contacts(false).vertical_correction)
	var previous_y := velocity.y
	velocity = air.begin_step(DT, velocity, false, Vector3.RIGHT, 8, false)
	velocity.y += float(air.resolve_contacts(false).vertical_correction)
	check(is_equal_approx(previous_y - velocity.y, Air.GRAVITY * Air.STOMP_GRAVITY_FACTOR * DT), "stomp uses its chosen stronger gravity without air steering")
	var event: Dictionary = air.resolve_contacts(true)
	check(event.landed and event.stomp_landed and not event.air_hit, "stomp emits one landing pulse for the controller's existing targets")
	event = air.resolve_contacts(true)
	check(not event.landed and not event.stomp_landed, "stationary floor contacts cannot repeat a stomp")
	check(air.snapshot().action == &"stomp_land", "landing exposes a presentation phase")
	air.begin_step(DT, Vector3(3, 0, 0), true, Vector3.RIGHT, 4, false)
	check(air.snapshot().action == &"stomp_land" and air.blocks_ground_motion() and air.snapshot().blocks_ground_motion, "movement alone cannot skip stomp recovery and exposes its controller XZ gate")
	velocity = air.begin_step(DT, Vector3.ZERO, true, Vector3.ZERO, 4, true)
	check(air.jump_count == 1 and velocity.y > 0, "landing never locks out a fresh jump")
	check(not air.blocks_ground_motion(), "fresh jump leaves the stomp recovery movement gate")
	var recovering := _launched()
	recovering.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 4, true)
	recovering.request_air_attack(false)
	recovering.resolve_contacts(true)
	recovering.begin_step(Air.LAND_SECONDS - 0.01, Vector3.ZERO, true, Vector3.RIGHT, 4, false)
	check(recovering.blocks_ground_motion(), "stomp recovery retains its full chosen duration despite movement input")
	recovering.begin_step(0.02, Vector3.ZERO, true, Vector3.RIGHT, 4, false)
	check(not recovering.blocks_ground_motion() and recovering.phase == &"ground", "completed stomp recovery releases the controller movement gate")

func _reset_and_contacts() -> void:
	var air := _launched()
	air.request_air_attack(false)
	air.begin_step(Air.KICK_HIT_SECONDS, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	air.cancel()
	var event: Dictionary = air.resolve_contacts(true)
	check(air.phase == &"ground" and air.jump_count == 0 and not event.air_hit and not event.landed, "place/hide/car/reset cancellation clears pending effects and credits")
	air = _launched()
	air.request_air_attack(false)
	air.begin_step(Air.KICK_HIT_SECONDS, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	event = air.resolve_contacts(true)
	check(event.landed and not event.air_hit, "landing wins over a kick marker crossed during the same physics move")
	check(not air.resolve_contacts(true).air_hit, "suppressed landing-frame kick cannot leak into a later contact resolution")
	air.cancel()
	var velocity: Vector3 = air.begin_step(DT, Vector3.ZERO, true, Vector3.ZERO, 4, true, false)
	check(velocity == Vector3.ZERO and air.jump_count == 0, "blocked input cannot queue a takeoff")
	velocity = air.begin_step(DT, Vector3.ZERO, true, Vector3.ZERO, 4, false, true)
	check(velocity == Vector3.ZERO and air.jump_count == 0, "unblocking does not replay a denied jump")
	air = Air.new()
	air.begin_step(DT, Vector3.ZERO, true, Vector3.ZERO, 4, true)
	event = air.resolve_contacts(true, true)
	check(air.jump_count == 0 and not event.took_off and not event.landed and not event.stomp_landed and event.ceiling, "an obstructed launch confirms no takeoff, airborne credit or landing hit")
	var other := _launched()
	air.cancel()
	check(other.jump_count == 1 and other.snapshot().airborne, "flight state belongs to one character instance")
	var before: Dictionary = other.snapshot()
	other.begin_step(0.0, Vector3.ZERO, false, Vector3.RIGHT, 8, true)
	check(other.snapshot() == before, "a zero-duration step changes no phase or input state")

func _rates() -> void:
	var reference := Vector3.INF
	for hz: int in [30, 60, 120]:
		var air := Air.new()
		var velocity := Vector3.ZERO
		for tick in int(hz / 10):
			velocity = air.begin_step(1.0 / hz, velocity, false, Vector3.RIGHT, 8, false)
			velocity.y += float(air.resolve_contacts(false).vertical_correction)
		check(absf(velocity.x - 3.6) < 0.0001 and absf(velocity.y + 2.5) < 0.0001, "air acceleration is integrated per second at %d Hz" % hz)
		if reference != Vector3.INF:
			check(velocity.distance_to(reference) < 0.0001, "equal elapsed air time agrees across physics rates")
		reference = velocity
	var air := _launched()
	var velocity: Vector3 = air.begin_step(DT, Vector3(8, 2, 0), false, Vector3.ZERO, 8, false)
	check(velocity.x == 8 and velocity.z == 0, "releasing air input preserves takeoff horizontal momentum")

func _midpoint_contract() -> void:
	for hz: int in [30, 60, 120]:
		var dt := 1.0 / hz
		for second: bool in [false, true]:
			var flight := _launched() if second else Air.new()
			var flight_velocity := Vector3.ZERO
			var flight_height := 0.0
			var impulse := sqrt(2.0 * Air.GRAVITY * (Air.SECOND_HEIGHT if second else Air.FIRST_HEIGHT))
			var analytic := true
			for tick in hz:
				flight_velocity = flight.begin_step(dt, flight_velocity, tick == 0 and not second, Vector3.ZERO, 4, tick == 0)
				flight_height += flight_velocity.y * dt
				flight_velocity.y += float(flight.resolve_contacts(false).vertical_correction)
				var time := (tick + 1) * dt
				analytic = analytic and absf(flight_height - (impulse * time - 0.5 * Air.GRAVITY * time * time)) < 0.0001
				analytic = analytic and absf(flight_velocity.y - (impulse - Air.GRAVITY * time)) < 0.0001
			check(analytic, "jump %d matches analytic position and endpoint velocity at %d Hz" % [2 if second else 1, hz])
		var stomp := _launched()
		stomp.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 4, true)
		stomp.resolve_contacts(false)
		stomp.request_air_attack(false)
		var stomp_velocity := Vector3.ZERO
		var stomp_height := 0.0
		for tick in int(hz / 5):
			stomp_velocity = stomp.begin_step(dt, stomp_velocity, false, Vector3.RIGHT, 4, false)
			stomp_height += stomp_velocity.y * dt
			stomp_velocity.y += float(stomp.resolve_contacts(false).vertical_correction)
		var fall_time := 0.2 - Air.STOMP_ANTIC_SECONDS
		var acceleration := Air.GRAVITY * Air.STOMP_GRAVITY_FACTOR
		check(absf(stomp_height + 0.5 * acceleration * fall_time * fall_time) < 0.0001 and absf(stomp_velocity.y + acceleration * fall_time) < 0.0001, "partial anticipation step preserves analytic stomp displacement and endpoint velocity at %d Hz" % hz)
	var air := Air.new()
	air.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	check(is_equal_approx(float(air.resolve_contacts(false).vertical_correction), -0.5 * Air.GRAVITY * DT), "free flight delivers the remaining half gravity once")
	check(float(air.resolve_contacts(false).vertical_correction) == 0.0, "repeated contact resolution cannot apply gravity twice")
	air.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	check(float(air.resolve_contacts(true).vertical_correction) == 0.0 and float(air.resolve_contacts(false).vertical_correction) == 0.0, "floor contact consumes and suppresses the pending correction")
	air.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	check(float(air.resolve_contacts(false, true).vertical_correction) == 0.0 and float(air.resolve_contacts(false).vertical_correction) == 0.0, "ceiling contact consumes and suppresses the pending correction")
	air.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	air.cancel()
	check(float(air.resolve_contacts(false).vertical_correction) == 0.0, "cancellation discards a proposed gravity correction")
	air.begin_step(DT, Vector3.ZERO, false, Vector3.ZERO, 4, false)
	air.begin_step(DT, Vector3.ZERO, true, Vector3.ZERO, 4, false)
	check(float(air.resolve_contacts(false).vertical_correction) == 0.0, "an unconsumed correction cannot leak into the next step")

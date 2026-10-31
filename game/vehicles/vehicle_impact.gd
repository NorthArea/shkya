extends RefCounted
## Planar contact impulse, shared by player, traffic and parked-car adapters.

const DAMAGE = preload("res://game/vehicles/vehicle_damage.gd")
const META := &"vehicle_impact_adapter"
const RESTITUTION := 0.22
const CONTACT_FRICTION := 0.3
const TANGENTIAL_DAMPING := 0.4
const DAMAGE_REFERENCE_MASS := 1000.0
const HITTER_DAMAGE_FACTOR := 0.5
const MIN_CLOSING := 0.001
const MIN_EFFECT_SPEED := 1.2
const CONTACT_SECONDS := 0.18
const SAFE_MASK := 1 | 2 | 4 | 32 | 64

static func register(body: CollisionObject3D, mass: float, size: Vector3, visual: Node3D, receive: Callable, get_velocity: Callable, get_yaw: Callable = Callable()) -> void:
	body.set_meta(META, {"mass": mass, "size": size, "visual": visual, "receive": receive, "velocity": get_velocity, "yaw": get_yaw, "contacts": {}})

static func inertia(mass: float, size: Vector3) -> float:
	return mass * (size.x * size.x + size.z * size.z) / 12.0

## Normal points from B towards A. Zero mass is an immovable world surface.
static func solve(va: Vector3, vb: Vector3, normal: Vector3, ma: float, mb: float, arm_a: Vector3, arm_b: Vector3, size_a: Vector3, size_b: Vector3, yaw_a := 0.0, yaw_b := 0.0) -> Dictionary:
	var n := Vector3(normal.x, 0.0, normal.z).normalized()
	var at_a := va + Vector3.UP.cross(arm_a) * yaw_a
	var at_b := vb + Vector3.UP.cross(arm_b) * yaw_b
	var closing := maxf(-(at_a - at_b).dot(n), 0.0)
	var inv_a := 1.0 / ma if ma > 0.0 else 0.0
	var inv_b := 1.0 / mb if mb > 0.0 else 0.0
	var inv_ia := 1.0 / inertia(ma, size_a) if ma > 0.0 else 0.0
	var inv_ib := 1.0 / inertia(mb, size_b) if mb > 0.0 else 0.0
	var lever_a := arm_a.cross(n).y
	var lever_b := arm_b.cross(n).y
	var denominator := inv_a + inv_b + lever_a * lever_a * inv_ia + lever_b * lever_b * inv_ib
	var normal_impulse := (1.0 + RESTITUTION) * closing / denominator if denominator > 0.0 and closing >= MIN_CLOSING else 0.0
	var tangent := Vector3(-n.z, 0.0, n.x)
	var lever_ta := arm_a.cross(tangent).y
	var lever_tb := arm_b.cross(tangent).y
	var after_normal := at_a - at_b + n * normal_impulse * (inv_a + inv_b)
	after_normal += Vector3.UP.cross(arm_a) * lever_a * normal_impulse * inv_ia
	after_normal += Vector3.UP.cross(arm_b) * lever_b * normal_impulse * inv_ib
	var tangent_denominator := inv_a + inv_b + lever_ta * lever_ta * inv_ia + lever_tb * lever_tb * inv_ib
	var tangent_impulse := 0.0
	if tangent_denominator > 0.0:
		tangent_impulse = clampf(-after_normal.dot(tangent) * TANGENTIAL_DAMPING / tangent_denominator,
			-CONTACT_FRICTION * normal_impulse, CONTACT_FRICTION * normal_impulse)
	var impulse := n * normal_impulse + tangent * tangent_impulse
	return {"closing_speed": closing, "impulse": impulse.length(), "velocity_a": impulse * inv_a, "velocity_b": -impulse * inv_b,
		"yaw_a": arm_a.cross(impulse).y * inv_ia, "yaw_b": -arm_b.cross(impulse).y * inv_ib,
		"into_a": maxf(-at_a.dot(n), 0.0), "into_b": maxf(at_b.dot(n), 0.0)}

static func _velocity(adapter: Dictionary) -> Vector3:
	var callback: Callable = adapter.get("velocity", Callable())
	return callback.call() if callback.is_valid() else Vector3.ZERO

static func _yaw(adapter: Dictionary) -> float:
	var callback: Callable = adapter.get("yaw", Callable())
	return float(callback.call()) if callback.is_valid() else 0.0

static func reset(body: CollisionObject3D) -> void:
	if body.has_meta(META):
		var adapter: Dictionary = body.get_meta(META)
		(adapter["contacts"] as Dictionary).clear()

static func _deliver(body: CollisionObject3D, adapter: Dictionary, dv: Vector3, dyaw: float, point: Vector3, inward: Vector3, closing: float, damage_speed: float) -> void:
	body.set_meta("vehicle_impact_serial", int(body.get_meta("vehicle_impact_serial", 0)) + 1)
	var receive: Callable = adapter["receive"]
	receive.call(dv, dyaw, point, inward, closing, damage_speed)

## Pair cooldown is written symmetrically: a swept parked body and the player's slide cannot
## resolve the same pair twice, but a different receiver in a pile-up still gets its impulse.
static func _contact(body: CollisionObject3D, other: CollisionObject3D, point: Vector3, normal: Vector3, before: Vector3, slide_done: bool) -> float:
	if not body.has_meta(META) or other == null or absf(normal.y) > 0.6:
		return 0.0
	if not other.has_meta(META) and (other.collision_layer & 32) != 0:
		return 0.0
	var own: Dictionary = body.get_meta(META)
	var adapter: Dictionary = other.get_meta(META, {})
	var n := Vector3(normal.x, 0.0, normal.z).normalized()
	var result := solve(before, _velocity(adapter), n, own["mass"], adapter.get("mass", 0.0), point - (body as Node3D).global_position,
		point - (other as Node3D).global_position, own["size"], adapter.get("size", Vector3.ONE), _yaw(own), _yaw(adapter))
	if result["impulse"] <= 0.0:
		return 0.0
	var frame := Engine.get_physics_frames()
	var now := frame / float(Engine.physics_ticks_per_second)
	var cooldowns: Dictionary = own["contacts"]
	var id := other.get_instance_id()
	var previous: Dictionary = cooldowns.get(id, {})
	if int(previous.get("frame", -1)) == frame:
		return 0.0
	var cosmetics: bool = result["closing_speed"] >= MIN_EFFECT_SPEED and now - float(previous.get("cosmetic_time", -INF)) >= CONTACT_SECONDS
	var stamp := {"frame": frame, "cosmetic_time": now if cosmetics else previous.get("cosmetic_time", -INF)}
	cooldowns[id] = stamp
	if adapter.is_empty():
		# A house remains a stop, as before. Plastic damage is independent of bounce/camera counters.
		var stop := Vector3.ZERO if slide_done else n * maxf(-before.dot(n), 0.0)
		var wall_damage: float = own["mass"] * result["closing_speed"] / DAMAGE_REFERENCE_MASS if cosmetics else 0.0
		_deliver(body, own, stop, 0.0, point, n, result["closing_speed"], wall_damage)
		return 0.0
	var other_cooldowns: Dictionary = adapter["contacts"]
	other_cooldowns[body.get_instance_id()] = stamp
	var correction := Vector3.ZERO
	if slide_done and body is CharacterBody3D:
		correction = n * (before - (body as CharacterBody3D).velocity).dot(n)
	# Strength follows the solved impulse. The reference mass is our own tuning scale;
	# Hit & Run's damage normalization uses a different health system and units.
	var damage_speed: float = result["impulse"] / DAMAGE_REFERENCE_MASS if cosmetics else 0.0
	var own_hitter: bool = result["into_a"] >= result["into_b"]
	_deliver(body, own, correction + result["velocity_a"], result["yaw_a"], point, n, result["closing_speed"], damage_speed * (HITTER_DAMAGE_FACTOR if own_hitter else 1.0))
	_deliver(other, adapter, result["velocity_b"], result["yaw_b"], point, -n, result["closing_speed"], damage_speed * (1.0 if own_hitter else HITTER_DAMAGE_FACTOR))
	return result["closing_speed"] if cosmetics else 0.0

## Called once after move_and_slide, before breakable pass-through handling.
static func contacts(body: CharacterBody3D, before: Vector3) -> float:
	var seen := {}
	var strongest := 0.0
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var other := hit.get_collider() as CollisionObject3D
		if other == null or seen.has(other.get_instance_id()):
			continue
		seen[other.get_instance_id()] = true
		strongest = maxf(strongest, _contact(body, other, hit.get_position(), hit.get_normal(), before, true))
	return strongest

## Translation is swept against the real collider; rotation advances in small collision-checked steps.
static func safe_move(body: PhysicsBody3D, motion: Vector3, turn: float, size: Vector3, mask := SAFE_MASK) -> Vector3:
	var before := body.global_position
	if motion.length_squared() > 0.0000001:
		var hit := KinematicCollision3D.new()
		if body.test_move(body.global_transform, motion, hit, 0.02, false):
			body.global_position += hit.get_travel()
			if body.has_meta(META):
				_contact(body, hit.get_collider() as CollisionObject3D, hit.get_position(), hit.get_normal(), _velocity(body.get_meta(META)), false)
		else:
			body.global_position += motion
	if absf(turn) > 0.00001:
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(size.x - 0.04, 0.01), maxf(size.y - 0.08, 0.01), maxf(size.z - 0.04, 0.01))
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = mask
		query.exclude = [body.get_rid()]
		var steps := maxi(1, ceili(absf(turn) / 0.015))
		for i in steps:
			var candidate := body.global_transform
			candidate.basis = Basis(Vector3.UP, turn / steps) * candidate.basis
			query.transform = candidate.translated_local(Vector3.UP * size.y * 0.5)
			if not body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				break
			body.global_transform = candidate
	return body.global_position - before

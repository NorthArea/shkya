extends RefCounted
## Distance-paced contact/swing controller. It never writes an actor transform.
const Rig = preload("res://game/characters/locomotion_rig.gd")
# One cycle contains two steps. Short cartoon legs must not turn root speed into
# arbitrarily fast cycles: faster motion adds flight between reachable contacts.
const FULL_CYCLE_LEG_LENGTHS := 2.2
const WALK_CYCLE_HZ := 1.7
const RUN_CYCLE_HZ := 2.2
const CONTACT_TRAVEL_LEG_LENGTHS := 1.15
var rig: Rig
var phase := 0.0
var motion_weight := 0.0
var speed := 0.0
var grounded := true
var mode := &"locomotion"
var _feet: Array[Dictionary] = []
var _direction := Vector3.FORWARD
var _travel_direction := Vector3.FORWARD
var _last_yaw := NAN
var _turn := 0.0
var _land := 0.0
var _last_origin := Vector3.INF
var _air_weight := 0.0
var _pelvis_drop := 0.0
var cadence := 0.0
var _sole_corners: Array[PackedVector3Array] = []

func configure(adapter: Rig) -> void:
	rig = adapter
	for index in 2:
		_feet.append({"plant": Vector3.ZERO, "basis": Basis.IDENTITY,
			"support": true, "initialized": false, "release_correction": Vector3.ZERO,
			"cycle": -1, "release_phase": -1.0})
		_sole_corners.append(_sole_footprint(index))
		var leg: Dictionary = rig.legs[index]
		# A toe/corner vertex is unsuitable as a yaw pivot: switching from a
		# planted world orientation to swing would throw the ankle sideways.
		var ankle: Vector3 = leg.ankle_rest
		leg.rest_sole = Vector3(ankle.x, ankle.y + _sole_corners[index][0].y, ankle.z)

func _sole_footprint(index: int) -> PackedVector3Array:
	var leg: Dictionary = rig.legs[index]
	var low: Vector3 = leg.rest_sole
	var high: Vector3 = leg.rest_sole
	for surface in rig.mesh.mesh.get_surface_count():
		var arrays := rig.mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			for slot in 4:
				var influence := vertex * 4 + slot
				if bones[influence] == leg.ankle and weights[influence] > 0.5:
					low = low.min(vertices[vertex])
					high = high.max(vertices[vertex])
	# A conservative sole footprint gives the tilted boot a heel/toe support,
	# instead of pivoting its whole bottom plane around one arbitrary vertex.
	return PackedVector3Array([Vector3(low.x, low.y, low.z) - leg.ankle_rest,
		Vector3(low.x, low.y, high.z) - leg.ankle_rest,
		Vector3(high.x, low.y, low.z) - leg.ankle_rest,
		Vector3(high.x, low.y, high.z) - leg.ankle_rest])

func reset() -> void:
	motion_weight = 0.0
	speed = 0.0
	_air_weight = 0.0
	_land = 0.0
	_pelvis_drop = 0.0
	cadence = 0.0
	_last_origin = Vector3.INF
	for foot: Dictionary in _feet:
		foot.initialized = false
	rig.skeleton.reset_bone_poses()

func update(velocity: Vector3, on_floor: bool, pose_mode: StringName, delta: float, vertical_speed: float, action_phase: float) -> void:
	if delta <= 0.0:
		return
	var skeleton: Skeleton3D = rig.skeleton
	var frame := skeleton.global_transform
	var scale_y := frame.basis.y.length()
	var local_velocity := frame.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	var measured := Vector2(velocity.x, velocity.z).length()
	var teleported := _last_origin != Vector3.INF and frame.origin.distance_to(_last_origin) > maxf(1.0, measured * delta * 3.0)
	if teleported:
		reset()
	_last_origin = frame.origin
	mode = pose_mode
	if mode in [&"hidden", &"knock"]:
		reset()
		return
	var was_grounded := grounded
	grounded = on_floor
	if grounded and not was_grounded:
		_land = minf(1.0, absf(vertical_speed) / 6.0 + 0.45)
		for foot: Dictionary in _feet:
			foot.initialized = false
	_land = move_toward(_land, 0.0, delta * 4.5)
	var walking := measured > 0.06 and grounded and mode in [&"locomotion", &"punch"]
	speed = lerpf(speed, measured if walking else 0.0, 1.0 - exp(-delta * 14.0))
	motion_weight = move_toward(motion_weight, 1.0 if walking else 0.0, delta * (7.5 if walking else 5.0))
	_air_weight = move_toward(_air_weight, 0.0 if grounded else 1.0, delta * 12.0)
	if local_velocity.length_squared() > 0.0001:
		_travel_direction = local_velocity.normalized()
		var from_yaw := atan2(-_direction.x, -_direction.z)
		var to_yaw := atan2(-local_velocity.x, -local_velocity.z)
		_direction = Vector3.FORWARD.rotated(Vector3.UP, lerp_angle(from_yaw, to_yaw, 1.0 - exp(-delta * 14.0)))
	var yaw := frame.basis.get_euler().y
	var yaw_speed := 0.0 if is_nan(_last_yaw) else angle_difference(_last_yaw, yaw) / delta
	_last_yaw = yaw
	_turn = lerpf(_turn, clampf(yaw_speed * measured * 0.006, -0.16, 0.16), 1.0 - exp(-delta * 10.0))
	var leg_length: float = float(rig.legs[0].upper_length) + float(rig.legs[0].lower_length)
	var run := smoothstep(2.2, 5.5, speed)
	var world_leg_length := leg_length * scale_y
	var cadence_ceiling := lerpf(WALK_CYCLE_HZ, RUN_CYCLE_HZ, smoothstep(4.0, 8.0, speed))
	cadence = minf(measured / maxf(0.01, world_leg_length * FULL_CYCLE_LEG_LENGTHS), cadence_ceiling) if walking else 0.0
	var stride := measured / (cadence * scale_y) if cadence > 0.0 else leg_length * FULL_CYCLE_LEG_LENGTHS
	var stance := minf(0.62, leg_length * CONTACT_TRAVEL_LEG_LENGTHS / stride)
	# A rotating hip socket cannot keep its old world contact for a full
	# straight stride. Release earlier, rather than crouching to an unreachable foot.
	stance *= lerpf(1.0, 0.60, smoothstep(0.5, 3.0, absf(yaw_speed)))
	if walking:
		phase += cadence * delta
	var cycle := fposmod(phase, 1.0)
	var transfer := sin(cycle * TAU)
	for index in 2:
		_plan_foot(index, frame, cycle, stride, stance, leg_length, run)
	var hips := skeleton.find_bone("hips")
	var shift := transfer * leg_length * 0.025 * motion_weight
	var drop := _required_pelvis_drop(shift)
	drop = maxf(drop, _land * leg_length * 0.13)
	# Lower before the support leg would overextend; recover height gradually.
	_pelvis_drop = maxf(drop, lerpf(_pelvis_drop, drop, 1.0 - exp(-delta * 16.0)))
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_rest(hips).origin + Vector3(shift, -_pelvis_drop, 0))
	skeleton.set_bone_pose_rotation(hips, Quaternion.from_euler(Vector3(0, transfer * 0.055 * motion_weight, -transfer * 0.025 * motion_weight - _turn)))
	var spine := skeleton.find_bone("spine")
	var forward_lean := -0.065 * run * motion_weight
	skeleton.set_bone_pose_rotation(spine, Quaternion.from_euler(Vector3(forward_lean, -transfer * 0.08 * motion_weight, _turn * 0.45)))
	var head := skeleton.find_bone("head")
	skeleton.set_bone_pose_rotation(head, Quaternion.from_euler(Vector3(-forward_lean * 0.5, transfer * 0.025 * motion_weight, _turn * 0.25)))
	skeleton.force_update_all_bone_transforms()
	for index in 2:
		var foot: Dictionary = _feet[index]
		rig.solve_leg(index, foot.target, foot.target_basis, foot.pose_weight)
		var suffix: String = "_l" if index == 0 else "_r"
		var side := 1.0 if index == 0 else -1.0
		var arm := -transfer * side * lerpf(0.24, 0.52, run) * motion_weight
		var elbow := -lerpf(0.07, 0.65, run) * motion_weight - _air_weight * 0.30
		var air_arm := -0.28 * _air_weight
		var arm_roll := side * _air_weight * 0.22
		if mode == &"punch":
			var hit := sin(clampf(action_phase, 0, 1) * PI)
			arm = lerpf(arm, 1.25 * hit, 0.95 if index == 1 else 0.4)
			elbow = lerpf(elbow, -0.5 * (1.0 - hit), 0.95)
		skeleton.set_bone_pose_rotation(skeleton.find_bone("upper_arm" + suffix), Quaternion.from_euler(Vector3(arm + air_arm, 0, arm_roll)))
		skeleton.set_bone_pose_rotation(skeleton.find_bone("lower_arm" + suffix), Quaternion(Vector3.RIGHT, elbow))
	if motion_weight <= 0.0 and _air_weight <= 0.0 and _land <= 0.0 and mode != &"punch":
		skeleton.reset_bone_poses()
		_pelvis_drop = 0.0
		for foot: Dictionary in _feet:
			foot.initialized = false
	skeleton.force_update_all_bone_transforms()

func _required_pelvis_drop(shift: float) -> float:
	var drop := 0.0
	for index in 2:
		var foot: Dictionary = _feet[index]
		if float(foot.pose_weight) <= 0.0:
			continue
		var leg: Dictionary = rig.legs[index]
		var ankle: Vector3 = foot.target - foot.target_basis * (leg.rest_sole - leg.ankle_rest)
		var hip: Vector3 = leg.hip_rest + Vector3(shift, 0, 0)
		var horizontal := Vector2(ankle.x - hip.x, ankle.z - hip.z).length()
		var length: float = (float(leg.upper_length) + float(leg.lower_length)) * 0.985
		var height := sqrt(maxf(0.0, length * length - horizontal * horizontal))
		drop = maxf(drop, (hip.y - ankle.y - height) * float(foot.pose_weight))
	return drop

func _plan_foot(index: int, frame: Transform3D, cycle: float, stride: float, stance: float, leg_length: float, run: float) -> void:
	var foot: Dictionary = _feet[index]
	var leg: Dictionary = rig.legs[index]
	var rest: Vector3 = leg.rest_sole
	var t := fposmod(cycle + float(index) * 0.5, 1.0)
	var step_cycle := int(floor(phase + float(index) * 0.5))
	if int(foot.cycle) != step_cycle:
		foot.cycle = step_cycle
		foot.release_phase = -1.0
	var support := t < stance
	var desired_basis := Basis.IDENTITY
	if not foot.initialized:
		var initial: Vector3 = rest + _travel_direction * stride * (stance * 0.5 - t) if support else rest
		foot.plant = frame * initial
		foot.basis = frame.basis.orthonormalized()
		foot.support = support
		foot.release_correction = Vector3.ZERO
		foot.initialized = true
	if support and foot.support and float(foot.release_phase) < 0.0:
		var contact_basis: Basis = frame.basis.orthonormalized().inverse() * Basis(foot.basis)
		var contact: Vector3 = frame.affine_inverse() * Vector3(foot.plant)
		var ankle: Vector3 = contact - contact_basis * (rest - leg.ankle_rest)
		var horizontal := Vector2(ankle.x - float(leg.hip_rest.x), ankle.z - float(leg.hip_rest.z)).length()
		# A body turn may exhaust reach before the scheduled straight-stride
		# liftoff. Start recovery while the leg can still support an upright hip.
		if horizontal > leg_length * 0.65:
			foot.release_phase = t
	var release_phase := float(foot.release_phase) if float(foot.release_phase) >= 0.0 else stance
	support = t < release_phase
	var lifting: bool = not support and foot.support
	if support and not foot.support:
		# Account for the part of stance elapsed between sampled physics ticks.
		foot.plant = frame * (rest + _travel_direction * stride * (stance * 0.5 - t))
		foot.basis = frame.basis.orthonormalized()
	foot.support = support
	var sole: Vector3
	if support:
		sole = frame.affine_inverse() * Vector3(foot.plant)
		desired_basis = frame.basis.orthonormalized().inverse() * Basis(foot.basis)
	else:
		var swing := (t - release_phase) / (1.0 - release_phase)
		var blend := swing * swing * (3.0 - 2.0 * swing)
		var half_contact := stride * stance * 0.5
		var tangent_window := minf(0.18, stance / (1.0 - stance) * 0.20)
		# Match the world-stationary contact's -root-speed local tangent. The
		# short endpoint windows bound overshoot even during long running flights.
		var tangent := -stride * (1.0 - stance) * (swing * exp(-swing / tangent_window) - (1.0 - swing) * exp(-(1.0 - swing) / tangent_window))
		var offset := lerpf(-half_contact, half_contact, blend) + tangent
		sole = rest + _direction * offset
		var clearance := maxf(leg_length * lerpf(0.24, 0.40, run), float(leg.ankle_rest.y) * 0.70)
		# Clear the ground during the release/landing windows, before fast foot
		# recovery. A long low sine-squared tail would drag the boot at root speed.
		var lift_window := minf(0.30, stance / (1.0 - stance) * 0.40)
		var lift := smoothstep(0.0, lift_window, swing) * smoothstep(0.0, lift_window, 1.0 - swing)
		sole.y += lift * lerpf(0.72, 1.0, pow(sin(swing * PI), 2.0)) * clearance
		if lifting:
			var release: Vector3 = (frame.affine_inverse() * Vector3(foot.plant) - sole) / maxf(0.001, 1.0 - blend)
			# The planted XZ point may differ during a turn or inspection override.
			# Its height must not cancel the independently timed ground clearance.
			release.y = 0.0
			foot.release_correction = release
		sole += Vector3(foot.release_correction) * (1.0 - blend)
		foot.plant = frame * sole
		var pitch := sin(swing * TAU) * lerpf(0.15, 0.35, run)
		desired_basis = Basis(Vector3.RIGHT, pitch)
	if not grounded:
		sole = rest + Vector3(0, leg_length * (0.16 + float(index) * 0.10), 0.035 if index == 0 else -0.045)
		desired_basis = Basis(Vector3.RIGHT, -0.20)
	var pose_weight := maxf(motion_weight, maxf(_air_weight, _land))
	if mode == &"activity":
		pose_weight = motion_weight
		sole = rest
	if not grounded:
		pose_weight = _air_weight
	# Settle the contacts toward bind space as movement fades, without resetting phase.
	sole = rest.lerp(sole, pose_weight)
	var rotated_rest: Vector3 = desired_basis * (rest - leg.ankle_rest)
	var lowest := INF
	for corner: Vector3 in _sole_corners[index]:
		lowest = minf(lowest, (desired_basis * corner).y)
	sole.y += maxf(0.0, rotated_rest.y - lowest)
	if not grounded:
		for other: Dictionary in _feet:
			other.initialized = false
	foot.target = sole
	foot.target_basis = desired_basis
	foot.pose_weight = pose_weight

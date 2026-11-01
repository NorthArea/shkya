extends SceneTree
## Independent LOCOMOTION-01 technical acceptance; no screenshots or naturalness verdict.
## tools/godot.sh --headless --fixed-fps 60 --script tests/locomotion01_test.gd
## CPU skinning observes actual soles, not merely changing joint angles.
const Uniform = preload("res://game/characters/uniform_visual.gd")
const CharacterLook = preload("res://game/characters/character_sprite.gd")
const Civilian = preload("res://game/characters/models/civilian_model.gd")
const PlayerScript = preload("res://game/player/ilyusha.gd")
const ResidentScript = preload("res://game/npc/resident.gd")
const LifeScript = preload("res://game/world/life.gd")
const Driver = preload("res://game/vehicles/lada_driver.gd")
const InputSetup = preload("res://game/input_setup.gd")
const AUTHOR_NAMES := ["root", "hips", "spine", "head", "upper_arm_l", "lower_arm_l", "hand_l", "upper_arm_r", "lower_arm_r", "hand_r", "leg_l", "foot_l", "leg_r", "foot_r"]
const DT := 1.0 / 60.0
const CONTACT_HEIGHT_M := 0.05
const SWING_HEIGHT_M := 0.025
const SOLE_CONTACT_M := 0.01
const CONTACT_VERTICAL_STEP_M := 0.003
const PENETRATION_M := 0.05
const ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back", &"jump", &"sprint"]

class PostPhysics:
	extends Node
	signal stepped
	func _physics_process(_delta: float) -> void:
		stepped.emit()

var checks := 0
var failures: Array[String] = []
var observer: PostPhysics

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(2))
	InputSetup.install()
	observer = PostPhysics.new()
	observer.process_physics_priority = 1000
	root.add_child(observer)
	print("LOCOMOTION01_PROFILE ", JSON.stringify({"engine": Engine.get_version_info(), "physics_hz": Engine.physics_ticks_per_second, "test_sha256": FileAccess.get_sha256(get_script().resource_path), "scope": "runtime rigs, skinned soles, movement consumers, priorities", "contact_height_m": CONTACT_HEIGHT_M, "penetration_m": PENETRATION_M}))
	check(Engine.physics_ticks_per_second == 60, "fixture uses 60 Hz")
	_rigs_and_instances()
	for drawing: String in ["ilyusha", "babka", "police"]:
		_gait_contacts(drawing)
	for drawing: String in ["ilyusha", "police"]:
		_run_contacts(drawing)
	_start_stop_air_turn()
	_reverse_contacts()
	_action_priorities()
	_visual_offsets_are_not_travel()
	_occupant_priority()
	_xray_binding()
	await _player_wall()
	await _player_walk_sprint_jump()
	_resident_sparse_lod()
	_resident_knock_return()
	_release()
	observer.queue_free()
	await process_frame
	print("LOCOMOTION01: %d checks, %d failures; GPU/manual naturalness/likeness NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _visual(drawing: String, parent: Node3D) -> Node3D:
	var visual := Uniform.new()
	visual.configure(drawing, 2.0, Color.WHITE)
	parent.add_child(visual)
	return visual

func _rigs_and_instances() -> void:
	for drawing: String in ["police", "guard"] + Array(Civilian.DRAWINGS):
		var actor := Node3D.new()
		root.add_child(actor)
		var visual := _visual(drawing, actor)
		var sibling := _visual(drawing, actor)
		var authored: Skeleton3D = visual.skeleton
		var authored_mesh: Mesh = visual.uniform_mesh.mesh
		var authored_skin: Skin = visual.uniform_mesh.skin
		var authored_signature := _mesh_signature(authored_mesh)
		var original_rest: Array[Transform3D] = []
		for index in AUTHOR_NAMES.size():
			original_rest.append(authored.get_bone_global_rest(index))
		check(authored.get_bone_count() == AUTHOR_NAMES.size(), drawing + ": factory retains authored 14-bone rig")
		visual.update_locomotion(Vector3.FORWARD, true, &"locomotion", DT)
		var runtime: Skeleton3D = visual.skeleton
		check(runtime != authored and runtime.get_bone_count() >= 16, drawing + ": live gait has a separate articulated leg rig")
		var preserved := true
		for index in AUTHOR_NAMES.size():
			preserved = preserved and runtime.get_bone_name(index) == AUTHOR_NAMES[index]
			preserved = preserved and runtime.get_bone_global_rest(index).is_equal_approx(original_rest[index])
		check(preserved, drawing + ": first 14 names, indices and global rests survive adaptation")
		var uniform_kind := drawing in ["police", "guard", "police_long", "police_round", "guard_alt"]
		for suffix: String in ["_l", "_r"]:
			var knee := runtime.find_bone("knee" + suffix) if uniform_kind else runtime.find_bone("foot" + suffix)
			var ankle := runtime.find_bone("foot" + suffix) if uniform_kind else runtime.find_bone("ankle" + suffix)
			check(knee >= 0 and ankle >= 0 and knee != ankle, drawing + ": runtime distinguishes knee and ankle " + suffix)
			if knee >= 0 and ankle >= 0:
				check(runtime.get_bone_parent(ankle) == knee and runtime.get_bone_global_rest(knee).origin.y > runtime.get_bone_global_rest(ankle).origin.y + 0.01, drawing + ": real knee is upstream and above the ankle " + suffix)
		check(authored.get_bone_count() == 14 and authored_mesh == sibling.uniform_mesh.mesh and authored_skin == sibling.uniform_mesh.skin, drawing + ": authored rig and shared resources remain available to other consumers")
		check(_rest(authored) and _mesh_signature(authored_mesh) == authored_signature, drawing + ": adapting gait never mutates authored rest or mesh arrays")
		check(sibling.skeleton.get_bone_count() == 14 and _rest(sibling.skeleton), drawing + ": sibling does not inherit another instance's gait")
		check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), drawing + ": runtime visual adds no physics owner")
		actor.free()

func _gait_contacts(drawing: String) -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := _visual(drawing, actor)
	visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
	var samples := _sole_samples(visual)
	if not check(not samples[0].is_empty() and not samples[1].is_empty(), drawing + ": independent mesh oracle found both soles"):
		actor.free()
		return
	var velocity := Vector3.FORWARD * 1.2
	for frame in 60:
		actor.position += velocity * DT
		visual.update_locomotion(velocity, true, &"locomotion", DT)
	var previous := _soles(visual, samples)
	var supporting := 0
	var below_floor := 0
	var lifts: Array[int] = [0, 0]
	var lift_edges: Array[int] = [0, 0]
	var was_lifted: Array[bool] = [false, false]
	var contact_travel: Array[float] = [0.0, 0.0]
	var contact_intervals: Array[int] = [0, 0]
	var contact_max_speed: Array[float] = [0.0, 0.0]
	var max_jump := 0.0
	for frame in 180:
		actor.position += velocity * DT
		visual.update_locomotion(velocity, true, &"locomotion", DT)
		var current := _soles(visual, samples)
		if minf(current[0].low, current[1].low) <= CONTACT_HEIGHT_M:
			supporting += 1
		for side in 2:
			if current[side].low < -PENETRATION_M:
				below_floor += 1
			var lifted: bool = current[side].low > SWING_HEIGHT_M
			if lifted:
				lifts[side] += 1
			if lifted and not was_lifted[side]:
				lift_edges[side] += 1
			was_lifted[side] = lifted
			var travel := _planar(current[side].center - previous[side].center).length()
			max_jump = maxf(max_jump, travel)
			var in_contact: bool = absf(current[side].low) <= SOLE_CONTACT_M and absf(previous[side].low) <= SOLE_CONTACT_M
			in_contact = in_contact and absf(current[side].low - previous[side].low) <= CONTACT_VERTICAL_STEP_M
			if in_contact:
				contact_intervals[side] += 1
				contact_travel[side] += travel
				contact_max_speed[side] = maxf(contact_max_speed[side], travel / DT)
		previous = current
	check(below_floor == 0, drawing + ": skinned soles stay above the penetration budget")
	check(supporting >= 165, drawing + ": at least one real sole supports steady walking")
	for side in 2:
		check(lifts[side] >= 10 and lift_edges[side] >= 2, drawing + ": each actual sole alternates support and swing, side %d" % side)
		var slip: float = contact_travel[side] / maxf(1.0, float(contact_intervals[side])) / DT
		check(contact_intervals[side] >= 45 and slip <= 0.8, drawing + ": actual ground contact slips less than body travel, side %d, %.3fm/s" % [side, slip])
	check(max_jump <= 0.12, drawing + ": foot trajectory has no per-frame teleport")
	print("LOCOMOTION01_CONTACT ", JSON.stringify({"drawing": drawing, "support_frames": supporting, "lift_frames": lifts, "lift_edges": lift_edges, "contact_intervals": contact_intervals, "contact_travel_m": contact_travel, "contact_max_speed_mps": contact_max_speed, "max_frame_travel_m": max_jump}))
	actor.free()

func _start_stop_air_turn() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := _visual("ilyusha", actor)
	visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
	var samples := _sole_samples(visual)
	var previous := _soles(visual, samples)
	var max_jump := 0.0
	for frame in 60:
		actor.position += Vector3.FORWARD * 1.2 * DT
		visual.update_locomotion(Vector3.FORWARD * 1.2, true, &"locomotion", DT)
		var current := _soles(visual, samples)
		max_jump = maxf(max_jump, _sole_delta(previous, current))
		previous = current
	var phase_before: float = visual.gait.phase
	visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
	check(_phase_delta(phase_before, visual.gait.phase) < 0.1, "release preserves phase without restarting the step")
	for frame in 90:
		visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
		var current := _soles(visual, samples)
		max_jump = maxf(max_jump, _sole_delta(previous, current))
		previous = current
	check(visual.gait.motion_weight < 0.01, "stopped actor settles out of moving gait")
	var stopped_phase: float = visual.gait.phase
	for frame in 30:
		visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
	check(absf(visual.gait.phase - stopped_phase) < 0.0001, "idle actor does not invent travelled steps")
	var physical_before := actor.transform
	visual.update_locomotion(Vector3.RIGHT * 1.2, true, &"locomotion", DT)
	check(_phase_delta(stopped_phase, visual.gait.phase) < 0.1, "restart continues the saved gait phase")
	for frame in 60:
		visual.update_locomotion(Vector3.RIGHT * 1.2, true, &"locomotion", DT)
		var current := _soles(visual, samples)
		max_jump = maxf(max_jump, _sole_delta(previous, current))
		previous = current
	check(actor.transform.is_equal_approx(physical_before), "visual start/turn cannot move the physical actor")
	var takeoff_phase: float = visual.gait.phase
	for frame in 60:
		visual.update_locomotion(Vector3.RIGHT * 1.2, false, &"locomotion", DT, 3.0)
	check(absf(visual.gait.phase - takeoff_phase) < 0.0001, "airborne travel does not advance ground-contact steps")
	var airborne := _soles(visual, samples)
	for frame in 30:
		visual.update_locomotion(Vector3.RIGHT * 1.2, false, &"locomotion", DT, 3.0)
	check(_sole_delta(airborne, _soles(visual, samples)) < 0.025, "steady airborne pose does not cycle grounded footsteps")
	for frame in 90:
		visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT, -5.0 if frame == 0 else 0.0)
		var current := _soles(visual, samples)
		check(current[0].low >= -PENETRATION_M and current[1].low >= -PENETRATION_M, "landing keeps real sole geometry above the floor, frame %d" % frame)
	check(actor.transform.is_equal_approx(physical_before), "air and landing pose do not apply a second root motion")
	check(max_jump < 0.20, "start/stop/turn blend does not snap the visible feet")
	actor.free()

func _run_contacts(drawing: String) -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := _visual(drawing, actor)
	visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
	var samples := _sole_samples(visual)
	var velocity := Vector3.FORWARD * 6.0
	var leg_length := _world_leg_length(visual)
	# Running permits flight and longer per-tick travel. This bound uses actual
	# body travel and half a real leg, rather than the walking frame limit.
	var travel_budget := 2.0 * velocity.length() * DT + leg_length * 0.5
	for frame in 60:
		actor.position += velocity * DT
		visual.update_locomotion(velocity, true, &"locomotion", DT)
	check(visual.gait.speed >= 5.5 and visual.gait.grounded and visual.gait.mode == &"locomotion", drawing + ": positive run profile reaches the active high-speed branch")
	var previous := _soles(visual, samples)
	var previous_phase: float = visual.gait.phase
	var phase_start := previous_phase
	var phase_continuous := true
	var penetration := 0.0
	var flight_frames := 0
	var max_travel := 0.0
	var lifted: Array[int] = [0, 0]
	var edges: Array[int] = [0, 0]
	var previous_lift: Array[bool] = [false, false]
	var contact_count: Array[int] = [0, 0]
	var contact_travel: Array[float] = [0.0, 0.0]
	var contact_max_speed: Array[float] = [0.0, 0.0]
	for frame in 180:
		actor.position += velocity * DT
		visual.update_locomotion(velocity, true, &"locomotion", DT)
		var current := _soles(visual, samples)
		var phase_step: float = visual.gait.phase - previous_phase
		phase_continuous = phase_continuous and is_finite(visual.gait.phase) and phase_step > 0.0 and phase_step < 0.5
		previous_phase = visual.gait.phase
		if minf(current[0].low, current[1].low) > CONTACT_HEIGHT_M:
			flight_frames += 1
		for side in 2:
			penetration = maxf(penetration, -float(current[side].low))
			var in_swing: bool = current[side].low > SWING_HEIGHT_M
			if in_swing:
				lifted[side] += 1
			if in_swing and not previous_lift[side]:
				edges[side] += 1
			previous_lift[side] = in_swing
			var travel := _planar(current[side].center - previous[side].center).length()
			max_travel = maxf(max_travel, current[side].center.distance_to(previous[side].center))
			var contact: bool = absf(current[side].low) <= SOLE_CONTACT_M and absf(previous[side].low) <= SOLE_CONTACT_M
			contact = contact and absf(current[side].low - previous[side].low) <= CONTACT_VERTICAL_STEP_M
			if contact:
				contact_count[side] += 1
				contact_travel[side] += travel
				contact_max_speed[side] = maxf(contact_max_speed[side], travel / DT)
		previous = current
	check(penetration <= PENETRATION_M, drawing + ": running real soles retain the same floor penetration budget")
	check(phase_continuous and visual.gait.phase - phase_start >= 5.0, drawing + ": running phase advances continuously with travelled ground distance")
	check(max_travel <= travel_budget, drawing + ": running feet stay inside the body-travel/leg-size continuity budget, %.3f <= %.3fm" % [max_travel, travel_budget])
	for side in 2:
		check(lifted[side] >= 20 and edges[side] >= 5, drawing + ": running actual sole alternates swing/contact, side %d" % side)
		var mean_slip: float = contact_travel[side] / maxf(1.0, float(contact_count[side])) / DT
		# The stationary floor keeps the same absolute slip budget. Ten intervals
		# suffice for short running contacts; flight is never counted as contact.
		check(contact_count[side] >= 10 and mean_slip <= 0.8, drawing + ": running actual contact retains the absolute slip budget, side %d, %.3fm/s" % [side, mean_slip])
		check(contact_max_speed[side] <= velocity.length() * 2.0, drawing + ": running contact has no instantaneous stride-length reset, side %d" % side)
	print("LOCOMOTION01_RUN ", JSON.stringify({"drawing": drawing, "speed_mps": velocity.length(), "flight_frames": flight_frames, "lift_frames": lifted, "lift_edges": edges, "contact_intervals": contact_count, "contact_travel_m": contact_travel, "contact_max_speed_mps": contact_max_speed, "max_frame_travel_m": max_travel, "travel_budget_m": travel_budget, "penetration_m": penetration, "phase_cycles": visual.gait.phase - phase_start}))
	actor.free()

func _action_priorities() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := _visual("ilyusha", actor)
	for frame in 60:
		visual.update_locomotion(Vector3.FORWARD * 1.2, true, &"locomotion", DT)
	var phase: float = visual.gait.phase
	for mode: StringName in [&"hidden", &"knock"]:
		visual.update_locomotion(Vector3.FORWARD * 4.0, false, mode, DT, -4.0)
		check(visual.gait.motion_weight == 0.0 and visual.gait.speed == 0.0 and _rest(visual.skeleton), String(mode) + ": suppresses ground and airborne gait despite stale velocity")
		check(visual.gait.phase == phase, String(mode) + ": cannot invent a travelled step")
	for frame in 60:
		visual.update_locomotion(Vector3.FORWARD * 1.2, true, &"activity", DT)
	check(visual.gait.phase == phase and visual.gait.motion_weight < 0.01, "authored activity owns the pose while locomotion input persists")
	visual.update_locomotion(Vector3.ZERO, true, &"punch", DT, 0.0, 0.0)
	var before := _hand_position(visual, "hand_r")
	for frame in 10:
		visual.update_locomotion(Vector3.ZERO, true, &"punch", DT, 0.0, 0.5)
	var palm := _hand_position(visual, "hand_r")
	check((palm - before).dot(Vector3.FORWARD) >= 0.15, "standing punch carries the actual palm forward without being erased by idle reset")
	check(actor.position == Vector3.ZERO, "action priorities cannot manufacture actor displacement")
	actor.free()

func _reverse_contacts() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := _visual("ilyusha", actor)
	visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
	var samples := _sole_samples(visual)
	var rest := _soles(visual, samples)
	for frame in 90:
		actor.position += Vector3.FORWARD * 1.2 * DT
		visual.update_locomotion(Vector3.FORWARD * 1.2, true, &"locomotion", DT)
	var advance: Array[float] = [-INF, -INF]
	for frame in 180:
		actor.position += Vector3.BACK * 1.2 * DT
		visual.update_locomotion(Vector3.BACK * 1.2, true, &"locomotion", DT)
		if frame < 60:
			continue
		var soles := _soles(visual, samples)
		for side in 2:
			var local_center: Vector3 = actor.to_local(soles[side].center)
			advance[side] = maxf(advance[side], (local_center - Vector3(rest[side].center)).dot(Vector3.BACK))
	for side in 2:
		check(advance[side] >= 0.08, "exact 180-degree movement reversal transfers each actual sole ahead along the new course, side %d, %.3fm" % [side, advance[side]])
	actor.free()

func _visual_offsets_are_not_travel() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var presentation := Node3D.new()
	presentation.name = "Visual"
	actor.add_child(presentation)
	var look := CharacterLook.new()
	look.name = "Look"
	presentation.add_child(look)
	look.set_physics_process(false)
	look._physics_process(DT)
	for frame in 90:
		presentation.position = Vector3(sin(frame * 0.5) * 0.3, 0.03 * sin(frame * 0.2), cos(frame * 0.5) * 0.3)
		presentation.scale = Vector3.ONE * (1.0 + 0.015 * sin(frame * 0.3))
		look._physics_process(DT)
	check(look.uniform_visual.gait.motion_weight < 0.01 and look.uniform_visual.gait.speed < 0.01, "breathing/lunge/presentation offsets do not masquerade as actor travel")
	var before: float = look.uniform_visual.gait.phase
	for frame in 60:
		actor.position += Vector3.FORWARD * DT
		look._physics_process(DT)
	check(_phase_delta(before, look.uniform_visual.gait.phase) > 0.01, "generic actual actor movement reaches CharacterSprite gait fallback")
	actor.free()

func _occupant_priority() -> void:
	var cabin := Node3D.new()
	root.add_child(cabin)
	var driver := Driver.new()
	driver.character = "ilyusha"
	cabin.add_child(driver)
	var visual: Node3D = driver.uniform_visual
	var skeleton: Skeleton3D = visual.skeleton
	var pose := _poses(skeleton)
	var hands := [_hand_position(visual, "hand_l"), _hand_position(visual, "hand_r")]
	var sole: float = visual.occupant_sole_height() + visual.position.y
	for frame in 120:
		visual.update_locomotion(Vector3.FORWARD * 4.0, true, &"locomotion", DT)
	check(visual.skeleton == skeleton and _poses(skeleton) == pose, "real Lada occupant pose has priority over stale locomotion input")
	check(_hand_position(visual, "hand_l").distance_to(hands[0]) < 0.0001 and _hand_position(visual, "hand_r").distance_to(hands[1]) < 0.0001, "seated priority preserves actual steering hand placement")
	check(absf(visual.occupant_sole_height() + visual.position.y - sole) < 0.0001, "seated priority preserves cabin sole clearance")
	cabin.free()

func _player_wall() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	fixture.add_child(_box(Vector3(30, 1, 30), Vector3(0, -0.5, 0)))
	var wall := _box(Vector3(1, 3, 20), Vector3(0.5, 1.5, 0))
	fixture.add_child(wall)
	var player := PlayerScript.new()
	fixture.add_child(player)
	player.place(Vector3(-0.65, 0, 0), 0.0)
	await _ticks(12)
	Input.action_press(&"move_right")
	await _ticks(90)
	var look: Node = player.visual.get_node("Look")
	var start := player.global_position
	var phase: float = look.uniform_visual.gait.phase
	await _ticks(60)
	check(player.is_on_wall() and player.is_on_floor(), "real held player input reaches the wall on grounded physics")
	check(player.global_position.distance_to(start) < 0.005, "wall scenario has no permitted physical travel")
	check(look.uniform_visual.gait.speed < 0.02 and look.uniform_visual.gait.motion_weight < 0.02, "wall-blocked input cannot make the skinned player walk in place")
	check(absf(look.uniform_visual.gait.phase - phase) < 0.0001, "wall-blocked player accumulates no fictitious steps")
	_release()
	fixture.queue_free()
	await _ticks(2)

func _player_walk_sprint_jump() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	fixture.add_child(_box(Vector3(300, 1, 300), Vector3(0, -0.5, 0)))
	var player := PlayerScript.new()
	fixture.add_child(player)
	player.place(Vector3.ZERO, 0.0)
	await _ticks(12)
	var look: Node = player.visual.get_node("Look")
	var visual: Node3D = look.uniform_visual
	var samples := _sole_samples(visual)
	check(player.is_on_floor(), "real movement fixture reaches grounded player state")
	Input.action_press(&"move_forward")
	var rates: Array[float] = []
	for sprint: bool in [false, true]:
		if sprint:
			Input.action_press(&"sprint")
		await _ticks(60)
		var expected := PlayerScript.RUN_SPEED if sprint else PlayerScript.WALK_SPEED
		var label := "sprint" if sprint else "walk"
		var from := player.global_position
		var phase: float = visual.gait.phase
		var previous := _soles(visual, samples)
		var grounded_samples := 0
		var penetration := 0.0
		var max_travel := 0.0
		var phase_continuous := true
		var last_phase := phase
		for frame in 30:
			await _ticks(1)
			var current := _soles(visual, samples)
			if player.is_on_floor() and visual.gait.grounded:
				grounded_samples += 1
			for side in 2:
				penetration = maxf(penetration, -float(current[side].low))
				max_travel = maxf(max_travel, current[side].center.distance_to(previous[side].center))
			var phase_step: float = visual.gait.phase - last_phase
			phase_continuous = phase_continuous and is_finite(visual.gait.phase) and phase_step > 0.0 and phase_step < 0.5
			last_phase = visual.gait.phase
			previous = current
		var actual_speed := _planar(player.global_position - from).length() / (30.0 * DT)
		var phase_rate: float = (visual.gait.phase - phase) / (30.0 * DT)
		rates.append(phase_rate)
		var travel_budget := 2.0 * expected * DT + _world_leg_length(visual) * 0.5
		check(absf(actual_speed - expected) <= 0.1, "real Input " + label + " produces the actual configured player root speed")
		check(grounded_samples == 30 and visual.gait.mode == &"locomotion", "real " + label + " state reaches the grounded locomotion consumer")
		check(absf(visual.gait.speed - actual_speed) <= 0.15, "real " + label + " visual speed follows measured root travel")
		check(phase_continuous, "real " + label + " has continuous forward phase under physical movement")
		check(penetration <= PENETRATION_M and max_travel <= travel_budget, "real " + label + " actual skinned soles keep floor/continuity budgets")
		print("LOCOMOTION01_PLAYER ", JSON.stringify({"state": label, "actual_speed_mps": actual_speed, "phase_hz": phase_rate, "penetration_m": penetration, "max_frame_travel_m": max_travel, "travel_budget_m": travel_budget}))
	check(rates.size() == 2 and rates[1] > rates[0] * 1.2, "real sprint changes foot cadence positively beyond the walking profile")
	Input.action_press(&"jump")
	await _ticks(1)
	Input.action_release(&"jump")
	var takeoff_phase: float = visual.gait.phase
	var airborne_samples := 0
	var airborne_state_ok := true
	var airborne_phase_ok := true
	var peak := player.global_position.y
	var landed := false
	var penetration := 0.0
	var previous := _soles(visual, samples)
	var max_travel := 0.0
	for frame in 150:
		if not player.is_on_floor():
			airborne_samples += 1
			airborne_state_ok = airborne_state_ok and not visual.gait.grounded
			airborne_phase_ok = airborne_phase_ok and absf(visual.gait.phase - takeoff_phase) < 0.0001
		elif airborne_samples > 0:
			landed = true
			break
		await _ticks(1)
		peak = maxf(peak, player.global_position.y)
		var current := _soles(visual, samples)
		for side in 2:
			penetration = maxf(penetration, -float(current[side].low))
			max_travel = maxf(max_travel, current[side].center.distance_to(previous[side].center))
		previous = current
	check(airborne_samples >= 20 and peak >= 0.3, "real jump input reaches a sustained physical airborne trajectory")
	check(airborne_state_ok and airborne_phase_ok, "real airborne player publishes air state and freezes ground-contact phase")
	check(landed and player.is_on_floor() and visual.gait.grounded, "real physics landing returns the same player visual to grounded state")
	var travel_budget := 2.0 * PlayerScript.RUN_SPEED * DT + _world_leg_length(visual) * 0.5
	check(penetration <= PENETRATION_M and max_travel <= travel_budget, "real takeoff/landing keeps actual sole geometry inside floor and continuity budgets")
	_release()
	await _ticks(60)
	var stopped := player.global_position
	var phase: float = visual.gait.phase
	await _ticks(20)
	var soles := _soles(visual, samples)
	check(player.global_position.distance_to(stopped) < 0.005 and player.is_on_floor(), "landed player stops physically after releasing real movement input")
	check(visual.gait.motion_weight < 0.01 and absf(visual.gait.phase - phase) < 0.0001, "landed stopped player settles without fictitious ground steps")
	check(absf(soles[0].low) <= SOLE_CONTACT_M and absf(soles[1].low) <= SOLE_CONTACT_M, "landed stopped player returns both real soles to the physical floor")
	print("LOCOMOTION01_JUMP ", JSON.stringify({"airborne_samples": airborne_samples, "peak_root_y_m": peak, "landed": landed, "penetration_m": penetration, "max_frame_travel_m": max_travel, "travel_budget_m": travel_budget}))
	fixture.queue_free()
	await _ticks(2)

func _xray_binding() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := _visual("police", actor)
	var authored: Skeleton3D = visual.skeleton
	var xray: MeshInstance3D = visual.build_xray()
	xray.visible = true
	_check_xray_pose(visual, xray, "before gait")
	for frame in 30:
		actor.position += Vector3.FORWARD * DT
		visual.update_locomotion(Vector3.FORWARD, true, &"locomotion", DT)
	check(visual.skeleton != authored, "XRay scenario actually switches to runtime skeleton")
	_check_xray_pose(visual, xray, "after gait")
	visual.set_occupant_pose(&"trolley_driver")
	check(visual.skeleton == authored, "XRay scenario actually returns to authored occupant skeleton")
	_check_xray_pose(visual, xray, "after seated transition")
	actor.free()

func _check_xray_pose(visual: Node3D, xray: MeshInstance3D, label: String) -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var visible_mesh: MeshInstance3D = visual.uniform_mesh
	var bound := xray.get_parent() == skeleton and xray.get_node_or_null(xray.skeleton) == skeleton
	bound = bound and xray.mesh == visible_mesh.mesh and xray.skin == visible_mesh.skin
	check(bound and xray.visible, "XRay retains active mesh, skin, skeleton and activation " + label)
	if not bound:
		return
	var samples: Array = []
	for surface in visible_mesh.mesh.get_surface_count():
		var arrays := visible_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for slot in mini(48, vertices.size()):
			var index: int = slot * vertices.size() / mini(48, vertices.size())
			samples.append({"vertex": vertices[index], "bones": bones.slice(index * 4, index * 4 + 4), "weights": weights.slice(index * 4, index * 4 + 4)})
	var normal_points := _skin_points(visible_mesh, samples)
	var xray_points := _skin_points(xray, samples)
	var same_pose := not normal_points.is_empty() and normal_points.size() == xray_points.size()
	for index in mini(normal_points.size(), xray_points.size()):
		same_pose = same_pose and normal_points[index].distance_to(xray_points[index]) < 0.00001
	check(same_pose, "XRay CPU-skinned body points follow the actual visible pose " + label)

func _resident_sparse_lod() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var camera := Camera3D.new()
	fixture.add_child(camera)
	camera.global_position = Vector3(0, 10, 0)
	camera.look_at(camera.global_position + Vector3.BACK, Vector3.UP)
	var resident := ResidentScript.new()
	resident.character = "resident_man"
	var canonical: Array = ResidentScript.Layout.RESIDENT_ROUTES[7]
	var from: Vector3 = canonical[0]
	var to: Vector3 = from + (Vector3(canonical[1]) - from).normalized() * 8.0
	resident.setup(0, [from, to], [], 0)
	fixture.add_child(resident)
	resident.set_physics_process(false)
	resident.set_process(false)
	var look: Node = resident.visual.get_node("Look")
	look.set_physics_process(false)
	var life := LifeScript.new()
	life.camera = camera
	resident.life = life
	resident.errand = true
	check(resident._motion_step_clear(from, to), "sparse LOD fixture uses a canonically clear permitted pedestrian leg")
	check(camera.global_position.distance_to(resident.global_position) > resident.LOD_DISTANCE and not camera.is_position_in_frustum(resident.global_position + Vector3.UP), "real resident fixture reaches sparse offscreen LOD")
	var zero_between_ticks := 0
	var sparse_ticks := 0
	var previous_position := resident.global_position
	for frame in 100:
		resident._physics_process(DT)
		look._physics_process(DT)
		if frame >= 30 and resident.global_position == previous_position:
			sparse_ticks += 1
			if look.uniform_visual.gait.speed < resident.speed * 0.5:
				zero_between_ticks += 1
		previous_position = resident.global_position
	check(sparse_ticks >= 40, "real sparse resident skips most movement updates")
	check(zero_between_ticks == 0, "sparse movement retains velocity between actor ticks instead of flashing idle")
	check(absf(look.uniform_visual.gait.speed - resident.speed) < 0.15, "sparse movement uses accumulated elapsed time rather than fourfold apparent speed")
	fixture.free()

func _resident_knock_return() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var resident := ResidentScript.new()
	resident.character = "resident_man"
	resident.setup(2, [Vector3(1000, 0, 1000), Vector3(1000, 0, 900)], [], 0)
	fixture.add_child(resident)
	resident.set_physics_process(false)
	resident.set_process(false)
	var look: Node = resident.visual.get_node("Look")
	look.set_physics_process(false)
	# The launch uses the production knock action and a real velocity-bearing
	# body. The car then leaves, so a repeat hit cannot mask the return branch.
	var car := CharacterBody3D.new()
	fixture.add_child(car)
	resident.lada = car
	for frame in 30:
		resident._physics_process(DT)
		resident._process(DT)
		look._physics_process(DT)
	car.position = resident.position + Vector3.BACK * 2.0
	car.velocity = Vector3.FORWARD * 5.0
	resident.knock()
	car.position = Vector3.ZERO
	car.velocity = Vector3.ZERO
	check(resident.state == &"knocked" and resident.knock_phase == &"fly", "real Resident.knock enters the flight branch before return acceptance")
	var samples := _sole_samples(look.uniform_visual)
	var counts := {&"fly": 0, &"down": 0, &"getup": 0, &"back": 0}
	var posed_samples := {&"fly": 0, &"down": 0, &"getup": 0}
	var expected_actions := {&"fly": &"flail", &"down": &"down", &"getup": &"getup"}
	var frozen := true
	var action_owned := true
	var back_animated := true
	var back_distance := 0.0
	var back_pose_delta := 0.0
	var reference_feet: Array[Vector3] = []
	var completed := false
	for frame in 1000:
		var before := resident.global_position
		var phase_before: float = look.uniform_visual.gait.phase
		resident._physics_process(DT)
		resident._process(DT)
		look._physics_process(DT)
		var phase_after: float = look.uniform_visual.gait.phase
		var kind: StringName = resident.knock_phase
		if kind in [&"fly", &"down", &"getup"]:
			counts[kind] = int(counts[kind]) + 1
			frozen = frozen and phase_after == phase_before
			frozen = frozen and look.uniform_visual.gait.mode == &"knock" and look.uniform_visual.gait.motion_weight == 0.0
			action_owned = action_owned and look.uniform_visual.last_action_valid \
				and look.uniform_visual.last_action_kind == expected_actions[kind]
			if not _rest(look.uniform_visual.skeleton): posed_samples[kind] = int(posed_samples[kind]) + 1
		elif kind == &"back":
			var distance := _planar(resident.global_position - before).length()
			if distance > 0.0001:
				counts[&"back"] = int(counts[&"back"]) + 1
				back_distance += distance
				back_animated = back_animated and phase_after > phase_before
				back_animated = back_animated and look.uniform_visual.gait.mode == &"locomotion"
				var soles := _soles(look.uniform_visual, samples)
				if reference_feet.is_empty():
					reference_feet.assign([resident.to_local(soles[0].center), resident.to_local(soles[1].center)])
				for side in 2:
					back_pose_delta = maxf(back_pose_delta, resident.to_local(soles[side].center).distance_to(reference_feet[side]))
		elif int(counts[&"back"]) > 0:
			completed = resident.state == &"walk"
			break
	for kind: StringName in [&"fly", &"down", &"getup"]:
		check(int(counts[kind]) >= 10, "real knocked Resident executes nonempty " + String(kind) + " samples")
		check(int(posed_samples[kind]) > 0, "real " + String(kind) + " action deforms the active recovery skeleton")
	check(frozen, "real flight/down/getup freeze gait phase and suppress locomotion weight")
	check(action_owned, "real flight/down/getup retain their explicit valid flail/down/getup action ownership")
	check(int(counts[&"back"]) >= 30 and back_distance >= 2.0, "real knocked Resident physically walks its return path")
	check(back_animated and back_pose_delta >= 0.02, "real back path publishes locomotion, advances phase and deforms actual skinned soles")
	check(completed, "real back path finishes and restores the existing walking route")
	print("LOCOMOTION01_KNOCK_RETURN ", JSON.stringify({"phase_samples": counts, "posed_samples": posed_samples, "back_distance_m": back_distance, "back_sole_excursion_m": back_pose_delta, "completed": completed}))
	fixture.free()

func _sole_samples(visual: Node3D) -> Array:
	var sides := [[], []]
	var mesh: Mesh = visual.uniform_mesh.mesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			if vertices[index].y > 0.012 or absf(vertices[index].x) < 0.01:
				continue
			var side := 0 if vertices[index].x < 0.0 else 1
			sides[side].append({"vertex": vertices[index], "bones": bones.slice(index * 4, index * 4 + 4), "weights": weights.slice(index * 4, index * 4 + 4)})
	for side in 2:
		var all: Array = sides[side]
		var reduced: Array = []
		for index in mini(48, all.size()):
			reduced.append(all[index * all.size() / mini(48, all.size())])
		sides[side] = reduced
	return sides

func _soles(visual: Node3D, samples: Array) -> Array:
	var instance: MeshInstance3D = visual.uniform_mesh
	var result := []
	for side in 2:
		var center := Vector3.ZERO
		var low := INF
		for point: Vector3 in _skin_points(instance, samples[side]):
			center += point
			low = minf(low, point.y)
		result.append({"center": center / maxf(1.0, samples[side].size()), "low": low})
	return result

func _skin_points(instance: MeshInstance3D, samples: Array) -> PackedVector3Array:
	var skeleton := instance.get_node(instance.skeleton) as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var transforms: Array[Transform3D] = []
	for bind in instance.skin.get_bind_count():
		transforms.append(skeleton.get_bone_global_pose(instance.skin.get_bind_bone(bind)) * instance.skin.get_bind_pose(bind))
	var points := PackedVector3Array()
	for sample: Dictionary in samples:
		var point := Vector3.ZERO
		for influence in 4:
			if sample.weights[influence] > 0.0:
				point += (transforms[sample.bones[influence]] * sample.vertex) * sample.weights[influence]
		points.append(instance.to_global(point))
	return points

func _sole_delta(a: Array, b: Array) -> float:
	return maxf(a[0].center.distance_to(b[0].center), a[1].center.distance_to(b[1].center))

func _rest(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone)):
			return false
	return true

func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose(bone))
	return result

func _mesh_signature(mesh: Mesh) -> int:
	var surfaces: Array = []
	for index in mesh.get_surface_count():
		surfaces.append(mesh.surface_get_arrays(index))
	return hash(surfaces)

func _world_leg_length(visual: Node3D) -> float:
	var skeleton: Skeleton3D = visual.skeleton
	var hip := skeleton.find_bone("leg_l")
	var ankle := skeleton.find_bone("ankle_l")
	if ankle < 0:
		ankle = skeleton.find_bone("foot_l")
	var offset := skeleton.get_bone_global_rest(ankle).origin - skeleton.get_bone_global_rest(hip).origin
	return (skeleton.global_basis * offset).length()

func _hand_position(visual: Node3D, name_: String) -> Vector3:
	var skeleton: Skeleton3D = visual.skeleton
	skeleton.force_update_all_bone_transforms()
	return visual.model.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(name_)) * Vector3(0, -0.034, -0.008))

func _phase_delta(before: float, after: float) -> float:
	return fposmod(after - before, 1.0)

func _planar(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0, vector.z)

func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body

func _ticks(count: int) -> void:
	for frame in count:
		await observer.stepped

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)

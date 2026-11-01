extends SceneTree
## Independent CHAR05 acceptance: actual skin, real Resident/Life and tool geometry.
## tools/godot.sh --headless --fixed-fps 60 --script tests/character05_integration_test.gd
## Does not import the action sampler or use its output as an expected pose.
const Uniform = preload("res://game/characters/uniform_visual.gd")
const Look = preload("res://game/characters/character_sprite.gd")
const DT := 1.0 / 60.0
const PALM_SURFACE_GAP_M := 0.04
const PALM_CENTER_GAP_M := 0.12

class EndFrame:
	extends Node
	signal finished
	func _process(_delta: float) -> void:
		finished.emit()

var checks := 0
var failures: Array[String] = []
var observer: EndFrame
var main: Node
var world: Node
var people: Node
var life
var digger: Node
var strikes: Array[Dictionary] = []
var watchdog: SceneTreeTimer

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("CHAR05: " + label)
	return ok

func _run() -> void:
	watchdog = create_timer(240.0, true, false, true)
	watchdog.timeout.connect(_watchdog_timeout)
	observer = EndFrame.new()
	observer.process_priority = 10000
	root.add_child(observer)
	_pipeline_isolation()
	_snapshot_priorities()
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/CHARACTER-05/qa_profile_%d.json" % Time.get_ticks_usec()
	root.add_child(main)
	await frames(3)
	main.start_game()
	await frames(10)
	world = main.world
	people = world.get_node("LevelGeometry/Residents")
	life = people.life
	for sensor: Node in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	world.player.place(Vector3(1000, 0, 1000), 0.0)
	world.player.input_enabled = false
	world.car.set_physics_process(false)
	world.car.global_position = Vector3(1100, 0, 1100)
	world.car.velocity = Vector3.ZERO
	for resident: Node in people.residents:
		resident.set_physics_process(false)
		resident.set_process(false)
		look_of(resident).set_physics_process(false)
		resident._act_stop()
		resident._show()
	life.reserved.clear()
	await _social_consumers()
	digger = people.residents[30]
	digger.activity_sound.connect(_strike)
	await _dig_consumer()
	await _dig_cancellation()
	await _repeated_knock()
	if digger.activity_sound.is_connected(_strike):
		digger.activity_sound.disconnect(_strike)
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	life.reset()
	strikes.clear()
	digger = null
	life = null
	people = null
	world = null
	main.queue_free()
	main = null
	await frames(5)
	# Match the existing qualified Main fixture's deferred audio/resource drain.
	OS.delay_msec(100)
	await process_frame
	watchdog.timeout.disconnect(_watchdog_timeout)
	watchdog = null
	observer.queue_free()
	observer = null
	await process_frame
	print("CHARACTER05_INTEGRATION: %d checks, %d failures; actual World NPC/skin/tools; GPU naturalness NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _watchdog_timeout() -> void:
	quit(2)

func _pipeline_isolation() -> void:
	for drawing: String in ["ilyusha", "resident_man", "police"]:
		var actor := Node3D.new()
		root.add_child(actor)
		var visual := Uniform.new()
		visual.configure(drawing, 2.0, Color.WHITE)
		actor.add_child(visual)
		var sibling := Uniform.new()
		sibling.configure(drawing, 2.0, Color.WHITE)
		actor.add_child(sibling)
		var author: Skeleton3D = visual.skeleton
		visual.prepare_locomotion()
		sibling.prepare_locomotion()
		check(author.get_bone_count() == 14 and visual.skeleton.get_bone_count() == 16, drawing + ": action consumer uses the real authored14/runtime16 mapping")
		check(visual.uniform_mesh.mesh == sibling.uniform_mesh.mesh and visual.uniform_mesh.skin == sibling.uniform_mesh.skin and visual.skeleton != sibling.skeleton, drawing + ": immutable Mesh/Skin are shared, live pose is independent")
		var mesh_signature := mesh_hash(visual.uniform_mesh.mesh)
		var sibling_pose := poses(sibling.skeleton)
		var root_transform := actor.transform
		var hand_samples := skin_samples(visual.uniform_mesh, "hand_r")
		var neutral := skin_points(visual.uniform_mesh, hand_samples)
		var head_samples := skin_samples(visual.uniform_mesh, "head")
		var neutral_head := skin_points(visual.uniform_mesh, head_samples)
		var leg: Dictionary = visual.rig.legs[0]
		var foot_samples := skin_samples(visual.uniform_mesh, visual.skeleton.get_bone_name(int(leg.ankle)), false)
		var neutral_foot := skin_points(visual.uniform_mesh, foot_samples)
		check(int(leg.knee) != int(leg.ankle) and visual.skeleton.get_bone_parent(int(leg.ankle)) == int(leg.knee), drawing + ": recovery resolves the actual distinct runtime knee and ankle")
		for kind: StringName in [&"chat", &"listen", &"flail", &"down", &"getup"]:
			var request := {"kind": kind, "phase": 0.4, "speaker": true, "weight": 1.0}
			visual.submit_action(request)
			request.kind = &"none"
			request.phase = 1.0
			var mode := &"knock" if kind in [&"flail", &"down", &"getup"] else &"activity"
			visual.update_locomotion(Vector3.ZERO, true, mode, DT)
			var once := poses(visual.skeleton)
			var once_skin := skin_points(visual.uniform_mesh, hand_samples)
			var displacement := point_delta(neutral_head, skin_points(visual.uniform_mesh, head_samples)) if kind == &"listen" else point_delta(neutral, once_skin)
			check(displacement >= 0.005, drawing + ": " + String(kind) + " visibly deforms actual hand/head skin")
			if kind in [&"flail", &"down", &"getup"]:
				check(point_delta(neutral_foot, skin_points(visual.uniform_mesh, foot_samples)) >= 0.02, drawing + ": full-body recovery reaches the actual skinned foot through runtime leg roles")
			for repeat in 12:
				visual.update_locomotion(Vector3.ZERO, true, mode, DT)
			check(visual.last_action_valid and visual.last_action_kind == kind, drawing + ": submitted " + String(kind) + " survives caller snapshot mutation")
			check(same_poses(once, poses(visual.skeleton)) and point_delta(once_skin, skin_points(visual.uniform_mesh, hand_samples)) < 0.00001, drawing + ": repeated same action phase never accumulates offsets/IK")
			check(same_poses(sibling_pose, poses(sibling.skeleton)), drawing + ": action leaves cached neighbour pose untouched")
			visual.submit_action({})
			visual.update_locomotion(Vector3.ZERO, true, &"locomotion", DT)
			check(at_rest(visual.skeleton) and point_delta(neutral, skin_points(visual.uniform_mesh, hand_samples)) < 0.00001, drawing + ": none releases every action bone, including residual hand rotation")
		visual.submit_action({"kind": &"getup", "phase": 1.0})
		visual.update_locomotion(Vector3.ZERO, true, &"knock", DT)
		check(at_rest(visual.skeleton), drawing + ": completed getup returns the entire active rig to base")
		check(actor.transform == root_transform, drawing + ": action evaluation never supplies a second actor motion")
		check(mesh_hash(visual.uniform_mesh.mesh) == mesh_signature, drawing + ": action evaluation preserves shared geometry/weights")
		actor.free()

func _snapshot_priorities() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var presentation := Node3D.new()
	actor.add_child(presentation)
	var look := Look.new()
	presentation.add_child(look)
	look.set_physics_process(false)
	look.submit_action({"kind": &"chat", "phase": 0.5})
	look._physics_process(DT)
	check(look.uniform_visual.last_action_kind == &"chat", "real CharacterSprite evaluates the cached owner action")
	actor.position.x += 3.0
	look._physics_process(DT)
	check(look.uniform_visual.last_action_kind == &"none" and at_rest(look.uniform_visual.skeleton), "actual actor teleport clears stale action snapshot")
	look.submit_action({"kind": &"flail", "phase": 0.3})
	look.hide()
	look._physics_process(DT)
	look.show()
	look._physics_process(DT)
	check(look.uniform_visual.last_action_kind == &"none" and at_rest(look.uniform_visual.skeleton), "hidden then restored look cannot resurrect an old action")
	look.submit_action({"kind": &"flail", "phase": 0.3})
	look._physics_process(DT)
	look.reset_pose()
	look._physics_process(DT)
	check(look.uniform_visual.last_action_kind == &"none" and at_rest(look.uniform_visual.skeleton), "explicit CharacterSprite reset clears both snapshots and all masked bones")
	var occupant := Uniform.new()
	occupant.configure("ilyusha", 1.45, Color.WHITE)
	actor.add_child(occupant)
	occupant.set_occupant_pose(&"lada")
	var seated := poses(occupant.skeleton)
	occupant.submit_action({"kind": &"flail", "phase": 0.5})
	occupant.update_locomotion(Vector3.FORWARD * 8.0, false, &"knock", DT)
	check(same_poses(seated, poses(occupant.skeleton)) and occupant.skeleton.get_bone_count() == 14, "occupant authority excludes late action/gait input")
	actor.free()

func _at(actor: Node, destination: StringName) -> void:
	actor.set_physics_process(false)
	actor.set_process(false)
	look_of(actor).set_physics_process(false)
	actor._act_stop()
	if actor.spot_id != &"":
		life.release(actor.spot_id, actor)
	actor._knock_reset()
	actor.spot_id = destination
	actor._show()
	actor.place(life.spots[destination].pos)
	actor._go_to(destination)
	actor._wait = 100.0
	actor.set_physics_process(true)
	actor.set_process(true)
	look_of(actor).set_physics_process(true)

func _social_consumers() -> void:
	var a: Node = people.residents[33]
	var b: Node = people.residents[35]
	_at(a, &"chat_h11a")
	_at(b, &"chat_h11b")
	a.clock = 0.4
	b.clock = 0.4
	await frames(6)
	var turn: Dictionary = life.social_turn(a)
	if check(turn.get("members", []).size() == 2, "actual Life reservations and presence form the conversation pair"):
		var speaker: Node = turn.speaker
		var listener: Node = b if speaker == a else a
		check(look_of(speaker).uniform_visual.last_action_kind == &"chat" and look_of(listener).uniform_visual.last_action_kind == &"listen", "actual social speaker/listener ownership reaches distinct visual actions")
		var old_speaker: Node = speaker
		a.clock += life.CHAT_TURN_SECONDS
		b.clock = a.clock
		await frames(6)
		var next: Dictionary = life.social_turn(a)
		check(next.speaker != old_speaker and look_of(next.speaker).uniform_visual.last_action_kind == &"chat", "the real Life turn change transfers the speaking gesture")
	for actor: Node in [a, b]:
		actor._act_stop()
		actor.state = &"pause"
		actor._wait = 100.0
	await frames(6)
	check(look_of(a).uniform_visual.last_action_kind == &"none" and look_of(b).uniform_visual.last_action_kind == &"none", "ending actual conversation clears both role masks")
	for actor: Node in [a, b]:
		actor.set_physics_process(false)
		actor.set_process(false)
		look_of(actor).set_physics_process(false)
		life.release(actor.spot_id, actor)

func _dig_consumer() -> void:
	_at(digger, &"dig_1")
	strikes.clear()
	digger.sound_counts.clear()
	await frames(6)
	check(digger._working_now() and digger._work_tool != null and digger._work_tool.visible, "real Resident/Life dig_1 creates its authoritative shovel")
	var visual: Node3D = look_of(digger).uniform_visual
	var palms := [skin_samples(visual.uniform_mesh, "hand_l"), skin_samples(visual.uniform_mesh, "hand_r")]
	check(not palms[0].is_empty() and not palms[1].is_empty(), "actual mesh oracle finds skin geometry for both palms")
	var sampled := 0
	var failed_grips := 0
	var maximum_gap := 0.0
	var minimum_separation := INF
	var first_tool := Transform3D.IDENTITY
	var tool_moved := false
	for frame in 125:
		await frames(1)
		if not digger._working_now():
			continue
		var tool: Node3D = digger._work_tool
		var shaft := shaft_geometry(tool)
		if shaft.is_empty():
			continue
		sampled += 1
		if sampled == 1:
			first_tool = tool.global_transform
		tool_moved = tool_moved or not tool.global_transform.is_equal_approx(first_tool)
		var contacts: Array[Vector3] = []
		for side in 2:
			var points := skin_points(visual.uniform_mesh, palms[side])
			var contact := closest_to_shaft(points, shaft)
			contacts.append(contact.point)
			maximum_gap = maxf(maximum_gap, float(contact.gap))
			var center := mean_point(points)
			var center_gap := center.distance_to(Geometry3D.get_closest_point_to_segment(center, shaft.a, shaft.b))
			if contact.gap > PALM_SURFACE_GAP_M or center_gap > PALM_CENTER_GAP_M:
				failed_grips += 1
		var axis: Vector3 = (shaft.b - shaft.a).normalized()
		var separation := absf((contacts[0] - contacts[1]).dot(axis))
		minimum_separation = minf(minimum_separation, separation)
		if separation < float(shaft.length) * 0.20:
			failed_grips += 1
		if visual.last_action_kind != &"dig" or not visual.last_action_valid:
			failed_grips += 1
	check(sampled >= 100 and tool_moved, "actual dig producer covers the complete moving tool cycle")
	check(failed_grips == 0, "actual CPU-skinned palms stay near the shaft with two separated grips throughout the stroke")
	check(strikes.size() >= 1 and strikes.size() <= 2, "actual dig preserves bounded canonical stroke sounds")
	var contact_events := true
	for strike: Dictionary in strikes:
		contact_events = contact_events and strike.stroke >= 0.99 and strike.visible
	check(contact_events, "each canonical dig sound occurs at the existing tool contact pose")
	var tool_before: Transform3D = digger._work_tool.global_transform
	var pose_before := poses(visual.skeleton)
	for repeat in 8:
		visual.update_locomotion(Vector3.ZERO, true, &"activity", DT)
	check(digger._work_tool.global_transform.is_equal_approx(tool_before) and same_poses(pose_before, poses(visual.skeleton)), "re-evaluating the same snapshot moves hands to the tool without moving the tool or accumulating IK")
	print("CHAR05_DIG ", JSON.stringify({"samples": sampled, "failed_grips": failed_grips, "max_wood_surface_gap_m": maximum_gap, "min_grip_separation_m": minimum_separation, "strikes": strikes.size()}))

func _dig_cancellation() -> void:
	var tool: Node3D = digger._work_tool
	var anchor = life.breakables.get_by_id(life.spots[&"dig_1"].anchor)
	if check(anchor != null, "dig cancellation reaches the actual breakable anchor"):
		anchor.smash(&"punch", Vector3.RIGHT)
		await frames(6)
		check(not digger._working_now() and not tool.visible and look_of(digger).uniform_visual.last_action_kind != &"dig", "broken real anchor clears dig action and shovel")
		anchor.reset()
	_at(digger, &"dig_1")
	await frames(6)
	digger._board()
	await frames(6)
	check(digger.state == &"board" and not tool.visible and look_of(digger).uniform_visual.last_action_kind != &"dig", "actual boarding cancels old dig grip/prop ownership")
	digger._act_stop()
	digger.state = &"pause"
	digger._wait = 100.0
	await frames(6)

func _repeated_knock() -> void:
	_at(digger, &"dig_1")
	await frames(6)
	var car: Node3D = world.car
	car.global_position = digger.global_position + Vector3.LEFT * 2.0
	car.velocity = Vector3.RIGHT * 5.0
	digger.knock()
	car.global_position = Vector3(1100, 0, 1100)
	car.velocity = Vector3.ZERO
	var counts := {&"fly": 0, &"down": 0, &"getup": 0}
	var producer_ok := true
	var repeated := false
	var recovered := false
	for frame in 900:
		await frames(1)
		var phase: StringName = digger.knock_phase
		if counts.has(phase):
			counts[phase] = int(counts[phase]) + 1
			var expected: StringName = &"flail" if phase == &"fly" else phase
			producer_ok = producer_ok and look_of(digger).uniform_visual.last_action_kind == expected
			producer_ok = producer_ok and not digger._work_tool.visible
		if phase == &"getup" and not repeated and digger._knock_t >= digger.KNOCK_RISE_SECONDS * 0.4:
			car.global_position = digger.global_position + Vector3.LEFT * 2.0
			car.velocity = Vector3.RIGHT * 5.0
			digger.knock()
			car.global_position = Vector3(1100, 0, 1100)
			car.velocity = Vector3.ZERO
			repeated = true
			continue
		if repeated and phase in [&"back", &""]:
			recovered = true
			break
	for phase: StringName in counts:
		check(int(counts[phase]) >= 10, "actual knock action samples are nonempty for " + String(phase))
	check(repeated and digger.knocks >= 2 and producer_ok, "real repeated knock during getup cancels recovery and republishes flail/down/getup without a stale dig pose")
	check(recovered, "repeated real knock reaches recovery completion")
	digger._act_stop()
	digger.state = &"pause"
	digger.knock_phase = &""
	digger._wait = 100.0
	await frames(60)
	check(look_of(digger).uniform_visual.last_action_kind == &"none" and at_rest(look_of(digger).uniform_visual.skeleton), "recovery to no action leaves no residual hand/leg mask in the real NPC")
	print("CHAR05_KNOCK ", JSON.stringify({"samples": counts, "repeated": repeated, "recovered": recovered}))

func _strike(actor: Node, kind: StringName) -> void:
	if actor != digger or kind != &"dig":
		return
	strikes.append({"stroke": actor._work_stroke(), "visible": actor._work_tool != null and actor._work_tool.visible})

func shaft_geometry(tool: Node3D) -> Dictionary:
	var shaft: MeshInstance3D
	var cross: MeshInstance3D
	for child: Node in tool.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			var box: BoxMesh = child.mesh
			if box.size.y > maxf(box.size.x, box.size.z) * 8.0:
				shaft = child
			elif box.size.x > maxf(box.size.y, box.size.z) * 2.0 and child.position.y > 0.0:
				if cross == null or child.position.y > cross.position.y:
					cross = child
	if shaft == null or cross == null:
		return {}
	var shaft_box: BoxMesh = shaft.mesh
	var cross_box: BoxMesh = cross.mesh
	var a: Vector3 = shaft.to_global(Vector3(0, -shaft_box.size.y * 0.5, 0))
	var b: Vector3 = shaft.to_global(Vector3(0, shaft_box.size.y * 0.5, 0))
	return {"a": a, "b": b, "length": a.distance_to(b), "part": shaft, "half": shaft_box.size * 0.5, "cross_a": cross.to_global(Vector3(-cross_box.size.x * 0.5, 0, 0)), "cross_b": cross.to_global(Vector3(cross_box.size.x * 0.5, 0, 0))}

func skin_samples(instance: MeshInstance3D, bone_name: String, skin_only := true) -> Array:
	var skeleton := instance.get_node(instance.skeleton) as Skeleton3D
	var bone := skeleton.find_bone(bone_name)
	var samples: Array = []
	for surface in instance.mesh.get_surface_count():
		if skin_only and "skin" not in instance.mesh.surface_get_name(surface):
			continue
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in vertices.size():
			var belongs := false
			for influence in 4:
				var slot := index * 4 + influence
				belongs = belongs or (weights[slot] > 0.5 and instance.skin.get_bind_bone(bones[slot]) == bone)
			if belongs:
				samples.append({"vertex": vertices[index], "bones": bones.slice(index * 4, index * 4 + 4), "weights": weights.slice(index * 4, index * 4 + 4)})
	return samples

func skin_points(instance: MeshInstance3D, samples: Array) -> PackedVector3Array:
	var skeleton := instance.get_node(instance.skeleton) as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var transforms: Array[Transform3D] = []
	for bind in instance.skin.get_bind_count():
		transforms.append(skeleton.get_bone_global_pose(instance.skin.get_bind_bone(bind)) * instance.skin.get_bind_pose(bind))
	var result := PackedVector3Array()
	for sample: Dictionary in samples:
		var point := Vector3.ZERO
		for influence in 4:
			if sample.weights[influence] > 0:
				point += (transforms[sample.bones[influence]] * sample.vertex) * sample.weights[influence]
		result.append(instance.to_global(point))
	return result

func closest_to_shaft(points: PackedVector3Array, shaft: Dictionary) -> Dictionary:
	var nearest := INF
	var contact := Vector3.ZERO
	var part: Node3D = shaft.part
	var half: Vector3 = shaft.half
	for point: Vector3 in points:
		var local := part.to_local(point)
		var clamped := Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y), clampf(local.z, -half.z, half.z))
		var gap := point.distance_to(part.to_global(clamped))
		if gap < nearest:
			nearest = gap
			contact = point
	return {"gap": nearest, "point": contact}

func mean_point(points: PackedVector3Array) -> Vector3:
	var result := Vector3.ZERO
	for point: Vector3 in points:
		result += point
	return result / maxf(1.0, points.size())

func point_delta(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var maximum := 0.0
	for index in a.size():
		maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum

func poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose(bone))
	return result

func mesh_hash(mesh: Mesh) -> int:
	var arrays: Array = []
	for surface in mesh.get_surface_count():
		arrays.append(mesh.surface_get_arrays(surface))
	return hash(arrays)

func same_poses(a: Array[Transform3D], b: Array[Transform3D]) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		if not a[index].is_equal_approx(b[index]):
			return false
	return true

func at_rest(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone)):
			return false
	return true

func look_of(actor: Node) -> Node:
	return actor.visual.get_node("Look")

func frames(count: int) -> void:
	for frame in count:
		await observer.finished

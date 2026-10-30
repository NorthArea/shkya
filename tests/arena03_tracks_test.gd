extends SceneTree
## ARENA-03 A: настоящий житель оставляет следы на снегу; поверхность, состояние и общий бюджет ограничивают их.

const Layout = preload("res://game/world/layout.gd")

var main: Node
var world: DemoWorld
var tracks: Node3D
var actor: Resident
var camera: Camera3D
var checks := 0
var failures: Array[String] = []
var yard := Layout.SPAWN + Vector3(8, 0, -10)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	tracks = world.get_node("SnowTracks")
	tracks.set_physics_process(false)
	world.player.set_physics_process(false)
	world.car.set_physics_process(false)
	world.camera_rig.set_physics_process(false)
	world.camera_rig.set_process(false)
	camera = root.get_camera_3d()
	camera.global_position = yard + Vector3(0, 6, 8)
	camera.look_at(yard)
	var residents: Node = world.get_node("LevelGeometry/Residents")
	for resident in residents.residents:
		resident.set_physics_process(false)
		resident.hide()
	actor = residents.residents[0]
	actor.hidden = false
	actor.show()
	actor.state = &"walk"
	actor._acting = false
	actor.knock_phase = &""
	actor.visual.position = Vector3.ZERO
	var player_buffer: int = tracks._foot_next
	var before := _foot_count()
	_walk(yard, Vector3.RIGHT, 4.0)
	check(_foot_count() > before + 2, "a nearby walking resident leaves several footprints in real snow")
	check(tracks._foot_next == player_buffer, "residents do not consume or modify Ilyusha's footprint buffer")
	var children_before := actor.get_child_count()
	check(tracks.find_children("*", "CollisionObject3D", true, false).is_empty(), "footprints add no physics objects")
	_freed_resident()
	_negative_states()
	_road_and_ice()
	_distance_and_teleport()
	_buffer_and_camera()
	check(actor.get_child_count() == children_before, "footprints add no nodes to the resident")
	await _finish()

func _freed_resident() -> void:
	var removed = Resident.new()
	tracks._residents.push_front(removed)
	removed.free()
	var before := _foot_count()
	_walk(yard + Vector3(0, 0, 2), Vector3.RIGHT, 2.0)
	check(_foot_count() > before, "a removed resident does not interrupt footprints of living residents")
	tracks._residents.pop_front()

func _negative_states() -> void:
	var before := _foot_count()
	actor.hide()
	_walk(yard, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "hidden residents and trolley passengers leave no footprints")
	actor.show()
	actor.hidden = true
	_walk(yard, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "a hidden passenger cannot stamp through the trolley floor")
	actor.hidden = false
	actor._acting = true
	actor._act_sit = -0.5
	actor.state = &"activity"
	_walk(yard, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "a seated resident leaves no walking footprints")
	actor._act_sit = 0.0
	actor._act_kind = &"slide"
	_walk(yard, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "sliding children leave no walking footprints")
	actor._act_kind = &"hockey"
	_walk(yard, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "skating residents leave no walking footprints")
	actor._acting = false
	actor.state = &"knocked"
	actor.knock_phase = &"fly"
	_walk(yard + Vector3.UP * 2.0, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "an airborne resident cannot stamp the snow below")
	actor.state = &"walk"
	actor.knock_phase = &""
	_walk(yard + Vector3.UP * 2.0, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "height above the ground suppresses footprints regardless of state")

func _road_and_ice() -> void:
	var before := _foot_count()
	var road: Vector2 = Layout.SURFACES.filter(func(surface): return surface[1] == "road")[0][2]
	camera.global_position = Vector3(road.x, 6, road.y + 8)
	camera.look_at(Vector3(road.x, 0, road.y))
	_walk(Vector3(road.x, 0, road.y), Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "asphalt and frozen road ruts receive no snow footprints")
	var rink_center: Vector2 = Layout.RINK[0]
	var rink := Vector3(rink_center.x, 0.0, rink_center.y)
	camera.global_position = rink + Vector3(0, 6, 8)
	camera.look_at(rink)
	_walk(rink, Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "a resident walking across the real ice rink leaves no snow stamps")

func _distance_and_teleport() -> void:
	camera.global_position = yard + Vector3(0, 6, 8)
	camera.look_at(yard)
	var before := _foot_count()
	_walk(yard + Vector3(85, 0, 0), Vector3.RIGHT, 4.0)
	check(_foot_count() == before, "distant residents do not consume the near-camera footprint budget")
	actor.global_position = yard
	tracks._physics_process(1.0 / 60.0)
	actor.global_position += Vector3(8, 0, 0)
	tracks._physics_process(1.0 / 60.0)
	check(_foot_count() == before, "a resident teleport does not draw a footprint at the destination")

func _buffer_and_camera() -> void:
	var marks = tracks.get("_resident_marks")
	if marks == null or marks.is_empty():
		check(false, "walking resident has a persistent footprint for buffer checks")
		return
	var first_slot := -1
	for i in marks.size():
		if marks[i].is_finite() and marks[i].distance_to(yard) < 8.0:
			first_slot = i
			break
	if first_slot < 0:
		check(false, "walking resident has a persistent footprint for buffer checks")
		return
	var first_point: Vector3 = marks[first_slot]
	var capacity: int = tracks.get_node("ResidentFeet").multimesh.instance_count
	for pass_index in 150:
		_walk(yard + Vector3(0, 0, float(pass_index % 21) * 0.17), Vector3.RIGHT, 4.0)
	check(_foot_count() <= capacity, "all residents share a bounded number of footprint instances")
	check(tracks._resident_marks[first_slot].is_equal_approx(first_point), "filling the buffer preserves an old footprint beside the camera")
	camera.global_position += Vector3(40, 0, 0)
	tracks._physics_process(1.0 / 60.0)
	check(tracks._resident_marks[first_slot].is_equal_approx(first_point), "moving the camera does not recenter or teleport existing footprints")

func _walk(start: Vector3, direction: Vector3, distance: float) -> void:
	actor.global_position = start
	tracks._physics_process(1.0 / 60.0)
	var steps := ceili(distance / 0.2)
	for i in steps:
		actor.global_position = start + direction * minf((i + 1) * 0.2, distance)
		tracks._physics_process(1.0 / 60.0)

func _foot_count() -> int:
	var marks = tracks.get("_resident_marks")
	if marks == null:
		return 0
	var count := 0
	for point: Vector3 in marks:
		if point.is_finite(): count += 1
	return count

func _frames(count: int) -> void:
	for i in count: await physics_frame

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish() -> void:
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_TRACKS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

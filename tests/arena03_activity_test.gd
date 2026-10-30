extends SceneTree

const Layout = preload("res://game/world/layout.gd")
var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var residents: Node
var life
var actor: Resident
var sound_phases: Array[float] = []
var contact_poses: Array[bool] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	residents = world.get_node("LevelGeometry/Residents")
	life = residents.life
	for resident: Resident in residents.residents:
		resident.set_physics_process(false)
		resident.set_process(false)
		resident._act_stop()
	life.reserved.clear()
	actor = residents.residents[30]
	actor.activity_sound.connect(func(r, kind):
		if kind in [&"dig", &"carpet", &"hood"]:
			sound_phases.append(r._act_t)
			var tool: Node3D = r.get_node_or_null("WorkTool")
			var forward := Vector3(-sin(r.facing_yaw), 0.0, -cos(r.facing_yaw))
			var reach := -tool.basis.y.dot(forward) if kind == &"dig" else tool.basis.y.dot(forward)
			contact_poses.append(tool.visible and reach > (0.3 if kind == &"dig" else 0.95)))
	for spot: StringName in [&"dig_1", &"carpet", &"hood"]:
		_tools(spot)
	_carpet()
	await _finish()

func _at(spot: StringName) -> void:
	actor._act_stop()
	actor.spot_id = spot
	actor.state = &"walk"
	actor.hidden = false
	actor.show()
	actor.knock_phase = &""
	actor._arrive()
	actor._wait = 100.0
	actor.sound_counts.clear()
	sound_phases.clear()
	contact_poses.clear()
	actor._process(0.0)

func _tools(spot: StringName) -> void:
	_at(spot)
	var kind: StringName = life.spots[spot].kind
	var tool: Node3D = actor.get_node_or_null("WorkTool")
	if not check(tool != null and tool.visible, "%s has a visible tool" % kind):
		return
	check(tool.get_child_count() >= 2, "%s tool has a handle and a recognisable head" % kind)
	var before := tool.transform
	var moved := false
	for i in 240:
		actor._tick_activity(1.0 / 60.0)
		actor._process(1.0 / 60.0)
		moved = moved or not tool.transform.is_equal_approx(before)
	check(moved, "%s tool moves throughout the working cycle" % kind)
	check(sound_phases.size() >= 2 and sound_phases.size() <= 5, "%s produces bounded strike events" % kind)
	var timed := sound_phases.size() >= 2
	for i in range(1, sound_phases.size()):
		timed = timed and sound_phases[i] - sound_phases[i - 1] > 0.7
	check(timed, "%s sounds belong to separate strokes" % kind)
	check(not contact_poses.is_empty() and not contact_poses.has(false), "%s strike event occurs with the tool extended toward its target" % kind)
	actor._act_stop()
	check(not tool.visible, "%s tool disappears when the activity stops" % kind)
	_at(spot)
	tool = actor.get_node_or_null("WorkTool")
	actor.hidden = true
	actor._process(0.0)
	check(not tool.visible, "%s tool is hidden with the actor" % kind)
	for i in 180: actor._tick_activity(1.0 / 60.0)
	check(sound_phases.is_empty(), "%s cannot strike while hidden" % kind)
	actor.hidden = false
	actor.state = &"knocked"
	for i in 180: actor._tick_activity(1.0 / 60.0)
	actor._process(0.0)
	check(sound_phases.is_empty() and not tool.visible, "%s cannot work while knocked down" % kind)
	actor._act_stop()

func _carpet() -> void:
	var geometry: Node = world.get_node("LevelGeometry")
	var post: Node3D = geometry._carpet_post(Layout.CARPET_POST, true)
	var cloths := 0
	for child in post.find_children("*", "MeshInstance3D", true, false):
		if child.mesh is BoxMesh and child.mesh.size.y > 0.5:
			cloths += 1
	check(cloths == 0, "the fixed carpet bar does not carry a duplicate carpet")
	post.free()
	_at(&"carpet")
	check(life.props[&"carpet"].visible, "LifeProps carpet appears for the actual carpet activity")
	actor._act_stop()
	check(not life.props[&"carpet"].visible, "LifeProps carpet is removed when its owner leaves")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	return ok

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _finish() -> void:
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): player.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_ACTIVITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

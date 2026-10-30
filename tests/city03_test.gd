extends SceneTree

const Layout = preload("res://game/world/layout.gd")
const SnowField = preload("res://game/world/snow_field.gd")
const WinterGrime = preload("res://game/world/winter_grime.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 8: await physics_frame
	var world: DemoWorld = main.world
	var grime := world.get_node_or_null("LevelGeometry/WinterGrime")
	check(grime != null, "winter road grime is connected to the real world")
	if grime != null:
		check(grime.find_children("*", "CollisionObject3D", true, false).is_empty(), "ice, slush and litter do not alter collisions")
		check(grime.find_children("*", "GPUParticles3D", true, false).is_empty(), "constant frost has no thaw or dripping water")
		var ice: MultiMeshInstance3D = grime.get_node("FrozenRuts")
		var slush: MultiMeshInstance3D = grime.get_node("SaltedSlush")
		check(ice.multimesh.instance_count > 20, "frozen ruts cover the street ring")
		check(slush.multimesh.instance_count > 20, "salted slush is visible along road edges")
		# Dummy rendering does not retain MultiMesh transform buffers in headless mode.
		var patches := WinterGrime.road_patches()
		for kind in [&"ice", &"slush"]:
			var batch := ice if kind == &"ice" else slush
			check(batch.multimesh.instance_count == patches[kind].size(), "all generated road patches are rendered")
			for transform: Transform3D in patches[kind]:
				var box: AABB = transform * batch.multimesh.mesh.get_aabb()
				var rect := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
				var on_road := false
				for surface in Layout.SURFACES:
					if surface[1] != "road": continue
					var road := Rect2(surface[2] - surface[3] * 0.5, surface[3])
					on_road = on_road or road.encloses(rect)
				check(on_road, "road dirt stays on the road instead of clean snowy yards")
				check(transform.origin.y > 0.025 and transform.origin.y < 0.08, "road dressing does not flicker with the road or float above it")
		var snow_before := SnowField.height_at(Layout.HIDE_SNOWDRIFT.x, Layout.HIDE_SNOWDRIFT.z)
		var state_before := world.mission.state
		var money_before := world.mission.money
		for i in 120: await physics_frame
		check(is_equal_approx(snow_before, SnowField.height_at(Layout.HIDE_SNOWDRIFT.x, Layout.HIDE_SNOWDRIFT.z)), "snow and stealth cover do not melt")
		check(world.mission.state == state_before and world.mission.money == money_before, "surface dressing cannot advance the quest or grant money")
	for audio in main.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	for audio in main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	for i in 4: await process_frame
	OS.delay_msec(100)
	await process_frame
	print("CITY03: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)

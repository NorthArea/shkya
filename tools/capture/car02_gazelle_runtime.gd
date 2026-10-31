extends SceneTree
## Actual traffic instance; debug cameras only, production winter lighting and body.
const OUTPUT := "res://builds/screenshots/CAR-02/gazelle-runtime"
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GAZELLE_RUNTIME_CAPTURE requires native rendering")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/CAR-02/gazelle/capture-profile.json"
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(8)
	var world: Node = main.world
	var car: Node3D
	for candidate in world.get_node("LevelGeometry/Traffic").cars:
		if candidate.kind == &"gazelle":
			car = candidate
	assert(car != null)
	car.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = world.camera_rig.camera.fov
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var shots: Array = []
	var views := {
		"front_quarter": Vector3(-5.8, 2.8, -7.0),
		"side": Vector3(-7.4, 2.0, 0),
		"rear_quarter": Vector3(5.8, 2.8, 7.0),
	}
	var failures := 0
	for label: String in views:
		camera.global_position = car.to_global(views[label])
		camera.look_at(car.to_global(Vector3(0, 1.05, 0)), Vector3.UP)
		await _frames(4)
		await RenderingServer.frame_post_draw
		var filename := label + ".png"
		if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join(filename))) != OK:
			failures += 1
		shots.append({"file": filename, "camera": str(camera.global_transform)})
	var report := FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"scope": "actual Main traffic instance frozen for snapshots; debug camera, unchanged world lighting; not manual driving acceptance", "kind": str(car.kind), "instance": str(car.get_path()), "body_transform": str(car.global_transform), "traffic_source": FileAccess.get_sha256("res://game/vehicles/traffic_car.gd"), "provider_source": FileAccess.get_sha256("res://game/vehicles/gazelle_visual.gd"), "shots": shots}, "\t"))
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	main = null
	await _frames(4)
	OS.delay_msec(100)
	await process_frame
	print("GAZELLE_RUNTIME_CAPTURE: %d frames, %d failures" % [shots.size(), failures])
	quit(0 if failures == 0 else 1)

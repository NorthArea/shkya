extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This check requires the real renderer and MultiMesh transforms")
		quit(2)
		return
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 12: await physics_frame
	var world: DemoWorld = main.world
	var tracks := world.get_node("SnowTracks")
	var environment := world.get_node("LevelGeometry/Environment")
	var found := 0
	for batch in environment.get_children():
		if not batch is MultiMeshInstance3D or not String(batch.name).begins_with("EnvNear_patch_"): continue
		for i in batch.multimesh.instance_count:
			var transform: Transform3D = batch.global_transform * batch.multimesh.get_instance_transform(i)
			var point := transform.origin
			point.y = 0.0
			if tracks._on_road(point): continue
			found += 1
			_check(not tracks._resident_snow(point), "the real sidewalk ice patch rejects footprints at %s" % point)
	_check(found > 10, "the actual environment supplies sidewalk patches")
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	for i in 5: await process_frame
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_TRACKS_RENDER: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + description)

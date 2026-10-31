extends SceneTree
## Native actual-Main renderpack. On-foot views plus explicitly labelled cabin debug views.
## tools/run.command --resolution 1920x1080 --fixed-fps 60 --script tools/capture/ip01_civilian_runtime.gd -- --civilian3d
const Layout = preload("res://game/world/layout.gd")
const Uniform = preload("res://game/characters/uniform_visual.gd")
var main: Node
var world: DemoWorld
var anchor: Node3D
var output := "res://builds/screenshots/IP-01/civilian-runtime"
var records: Array = []
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not Uniform.civilians_enabled():
		push_error("This capture needs native rendering and --civilian3d")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	output = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for frame in 8:
		await physics_frame
	world = main.world
	world.stealth.grant_grace(300.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	anchor = Node3D.new()
	world.add_child(anchor)
	world.camera_rig.follow(anchor, &"on_foot")
	for actor: Node3D in [world.player, world.babka]:
		await _on_foot(actor, actor.visual.global_rotation.y + PI)
		await _save(actor.name.to_lower() + "_world", "production on-foot CameraRig; original world lighting", actor)
	# Vendor lives inside the kiosk's solid interaction shell. The real buyer's
	# anchor is outside at the canonical service window; no actor/collider moves.
	await _on_foot(world.vendor, world.vendor.visual.global_rotation.y + PI, Layout.VENDOR_WINDOW)
	await _save("vendor_world", "production on-foot CameraRig anchored outside at the canonical buyer service window; vendor remains inside kiosk", world.vendor)
	var residents: Node = world.get_node("LevelGeometry/Residents")
	var resident: Node3D = residents.residents[0]
	await _on_foot(resident, resident.visual.global_rotation.y + PI)
	await _save("resident_world", "production on-foot CameraRig; original living resident", resident)
	world.enter_car()
	await _on_foot(world.car, world.car.global_rotation.y + PI * 0.75)
	await _save("lada_driver_world", "occupied production Lada through original glass/body", world.car)
	var debug_camera := Camera3D.new()
	world.add_child(debug_camera)
	debug_camera.global_position = world.car.to_global(Vector3(-2.4, 1.5, -1.8))
	debug_camera.look_at(world.car.to_global(Vector3(-0.34, 0.95, -0.2)), Vector3.UP)
	debug_camera.current = true
	var car_body: Node = world.car.visual.get_node("Body")
	var hidden: Array[Node3D] = []
	for part: Node in car_body.get_children():
		if part is MeshInstance3D and part.name == "BodyMesh":
			hidden.append(part)
			part.visible = false
	for frame in 3:
		await process_frame
	await _save("lada_seated_debug", "DEBUG cutaway camera; exterior BodyMesh hidden only in capture; original Interior/wheel/glass and full driver rig retained", world.car)
	for part: Node3D in hidden:
		part.visible = true
	var trolley: Node3D = world.get_node("LevelGeometry/Traffic").trolleybus
	# Freeze only this snapshot so cabin and camera stay together; no production controller edit.
	trolley.set_physics_process(false)
	debug_camera.global_position = trolley.to_global(Vector3(-5.0, 3.6, -8.0))
	debug_camera.look_at(trolley.to_global(Vector3(-0.6, 2.3, -4.9)), Vector3.UP)
	for frame in 3:
		await process_frame
	await _save("trolley_driver_world", "DEBUG exterior camera; production occupied trolley through original glass", trolley)
	debug_camera.global_position = trolley.to_global(Vector3(0.0, 2.65, -3.9))
	debug_camera.look_at(trolley.to_global(Vector3(-0.1, 1.5, 1.8)), Vector3.UP)
	debug_camera.fov = 85.0
	for frame in 3:
		await process_frame
	await _save("trolley_cabin_debug", "DEBUG interior camera; original cabin meshes and real seated/standing occupants", trolley)
	var manifest := FileAccess.open(output.path_join("capture_inputs.json"), FileAccess.WRITE)
	if manifest:
		manifest.store_string(JSON.stringify({"scope": "real Main consumers; exterior on-foot views and explicitly labelled debug cabin views", "civilian_model_sha256": FileAccess.get_sha256("res://game/characters/models/civilian_model.gd"), "character_sprite_sha256": FileAccess.get_sha256("res://game/characters/character_sprite.gd"), "uniform_visual_sha256": FileAccess.get_sha256("res://game/characters/uniform_visual.gd"), "frames": records}, "\t"))
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", kind, true, false):
			audio.stop()
	main.queue_free()
	main = null
	for frame in 4:
		await process_frame
	OS.delay_msec(100)
	await process_frame
	print("IP01_CIVILIAN_CAPTURE: ", records.size(), " frames, ", failures, " failures; visual review required")
	quit(0 if failures == 0 and records.size() == 8 else 1)

func _on_foot(actor: Node3D, yaw: float, buyer_anchor: Vector3 = Vector3.INF) -> void:
	anchor.global_position = actor.global_position if buyer_anchor == Vector3.INF else buyer_anchor
	world.camera_rig.yaw = yaw
	world.camera_rig.pitch = -0.15
	world.camera_rig.snap()
	for frame in 12:
		await physics_frame

func _save(label: String, scope: String, actor: Node3D) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	if result != OK:
		failures += 1
		push_error("Could not capture " + label)
	else:
		records.append({"file": label + ".png", "scope": scope, "actor": str(actor.get_path()), "position": str(actor.global_position)})
		print("IP01_CIVILIAN_CAPTURE: ", output.path_join(label + ".png"))

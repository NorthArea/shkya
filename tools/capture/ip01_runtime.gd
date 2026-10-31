extends SceneTree
## Real production patrols, original world lighting and on-foot camera profile.
## tools/run.command --resolution 1920x1080 --fixed-fps 60 --script tools/capture/ip01_runtime.gd -- --uniform3d
const Layout = preload("res://game/world/layout.gd")
var output := "res://builds/screenshots/IP-01/runtime"
var main: Node
var world: DemoWorld
var anchor: Node3D
var saved := 0
var failures := 0
var records: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	output = ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(1)
		return
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 8: await physics_frame
	world = main.world
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.stealth.grant_grace(120.0)
	anchor = Node3D.new()
	world.add_child(anchor)
	world.camera_rig.follow(anchor, &"on_foot")
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	for patrol: Node3D in [patrols.officer, patrols.officer2]:
		var kind: String = patrol.character
		var look: CharacterSprite = patrol.get_node("Visual/Look")
		if not look.uses_uniform_3d():
			push_error("IP01 runtime capture requires live 3D uniforms: " + kind)
			failures += 1
			continue
		world.player.place(patrol.global_position + Vector3(8, 0, 8), 0.0)
		for sample: Array in [["front", PI], ["side", PI * 0.5], ["back", 0.0]]:
			await _camera(patrol, float(sample[1]))
			await _save(kind + "_" + str(sample[0]), patrol, "on-foot camera; original post")
		# A visual-only wall gives reproducible depth occlusion without changing a sensor or collider.
		await _camera(patrol, PI)
		var blocker := _occluder(patrol)
		for i in 3: await process_frame
		await _save(kind + "_xray", patrol, "visual-only capture wall; sensors unchanged")
		blocker.queue_free()
		await process_frame
	# Use the real post transition to exercise walking and automatic pose reset.
	var officer: Node3D = patrols.officer
	world.player.place(officer.global_position + Vector3(8, 0, 8), 0.0)
	officer.move_post(Layout.OFFICER_POST_AFTER)
	for i in 18: await physics_frame
	await _camera(officer, PI * 0.5, 3)
	await _save("police_walk", officer, "PatrolNpc.move_post; production transition")
	for i in 600:
		if officer._move_target == Vector3.INF:
			break
		await physics_frame
	await _camera(officer, PI)
	await _save("police_arrived", officer, "arrival after production walking transition")
	var guard: Node3D = patrols.officer2
	world.player.place(guard.global_position + Vector3(8, 0, 8), 0.0)
	for i in 900:
		if guard._turn_t < 1.0:
			break
		await physics_frame
	await _camera(guard, PI * 0.5, 2)
	await _save("guard_turn", guard, "unmodified natural PatrolNpc turn cycle")
	var manifest := FileAccess.open(output.path_join("capture_inputs.json"), FileAccess.WRITE)
	if manifest:
		manifest.store_string(JSON.stringify({"scope": "production world; base police/guard only", "lighting": "unmodified world environment and lights", "camera": "CameraRig on_foot profile", "height": "existing height_m times approved SVG alpha height; no SHAR asset proportions claimed", "frames": records}, "\t"))
	else:
		failures += 1
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.queue_free()
	for i in 5: await process_frame
	print("IP01_RUNTIME_CAPTURE: %d frames, %d failures" % [saved, failures])
	quit(0 if failures == 0 and saved == 11 else 1)

func _camera(patrol: Node3D, offset: float, settle: int = 12) -> void:
	anchor.global_position = patrol.global_position
	world.camera_rig.yaw = patrol.visual.global_rotation.y + offset
	world.camera_rig.pitch = -0.15
	world.camera_rig.snap()
	for i in settle: await physics_frame

func _occluder(patrol: Node3D) -> MeshInstance3D:
	var camera: Camera3D = world.camera_rig.camera
	var wall := MeshInstance3D.new()
	wall.name = "CaptureOnlyDepthOccluder"
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 2.8, 0.16)
	wall.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("555b62")
	wall.material_override = material
	world.add_child(wall)
	wall.global_position = camera.global_position.lerp(patrol.global_position + Vector3(0, 1.0, 0), 0.55)
	wall.global_rotation.y = camera.global_rotation.y
	return wall

func _save(label: String, patrol: Node3D, scope: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	if result != OK:
		failures += 1
		push_error("Could not save IP01 runtime frame: " + label)
		return
	var look: CharacterSprite = patrol.get_node("Visual/Look")
	records.append({"file": label + ".png", "scope": scope, "actor": str(patrol.get_path()), "position": str(patrol.global_position), "visual_yaw": patrol.visual.global_rotation.y, "sensor_enabled": patrol.sensor.enabled, "xray_shown": patrol.xray_shown(), "walk_frame": look.frame, "visible_height": look.uniform_visual.visible_height})
	saved += 1
	print("IP01_RUNTIME_CAPTURE: " + output.path_join(label + ".png"))

extends SceneTree
# Eight frames of real, unmodified production consumers; no synthetic production positions.
const Rig = preload("res://game/camera/camera_rig.gd")
const Layout = preload("res://game/world/layout.gd")
var main: Node
var world: Node
var camera: Camera3D
var phase := "after"
var out := "res://builds/screenshots/CAR-02/shared-2106"
var shots := []
var failures := []
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	call_deferred("_capture")
func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native renderer required; screenshot acceptance NOT_RUN")
		quit(2)
		return
	out = ProjectSettings.globalize_path(out.path_join(phase))
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main.start_game()
	for i in 10: await process_frame
	world = main.world
	world.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for layer in world.find_children("*", "CanvasLayer", true, false): layer.hide()
	for p in world.find_children("*", "CPUParticles3D", true, false): p.emitting = false
	camera = Camera3D.new()
	camera.fov = Rig.PROFILES[&"on_foot"]["fov"]
	root.add_child(camera)
	var geo: Node = world.get_node("LevelGeometry")
	var hero: Node3D = world.car.visual
	var traffic: Node3D
	for car in geo.get_node("Traffic").cars:
		if car.kind == &"zhiguli": traffic = car.visual
	var parked: Node3D
	var parked_key := ""
	var solids := Layout.all_solids()
	for i in solids.size():
		var spec: Array = solids[i]
		if spec[1] == "parked_car" and (spec[2] as Vector2).distance_to(Layout.LIFE_HOOD_CAR) > 0.1:
			parked_key = spec[0] if i < Layout.SOLIDS.size() else "%s_%d" % [spec[0], i]
			parked = geo.get_node(parked_key).get_node("Visual")
			break
	var police: Node3D
	for child in geo.get_node("PermanentStreetClosures").get_children():
		if child.has_node("Body/BodyMesh"): police = child
	if traffic == null or parked == null or police == null:
		push_error("Missing actual production consumer; gallery FAIL")
		quit(1)
		return
	await _fixture("01_hero_beige_front_quarter", hero, Vector3(-5.2, 2.35, -6.4))
	await _fixture("02_traffic_red_front_quarter", traffic, Vector3(-5.2, 2.35, -6.4))
	await _fixture("03_parked_front_quarter", parked, Vector3(-5.2, 2.35, -6.4))
	await _fixture("04_police_front_quarter", police, Vector3(-5.2, 2.35, -6.4))
	world.car.enter(world.player)
	world.player.hide()
	hero.get_node("Body/Driver").process_mode = Node.PROCESS_MODE_ALWAYS
	await _fixture("05_occupied_hero_front_quarter", hero, Vector3(-5.2, 2.35, -6.4))
	# BEFORE side is retained as occluded evidence; AFTER fixture moves camera inside Lamp_Yard.
	await _fixture("06_occupied_hero_side", hero, Vector3(-3.0, 1.45, 0))
	await _game_camera("07_city_parking_game_camera", parked, 2.45)
	await _game_camera("08_city_police_post_game_camera", police, 2.45)
	var status := "PASS" if failures.is_empty() and shots.size() == 8 else "FAIL"
	var f := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"status": status, "shots": shots, "failures": failures, "parked_runtime_consumer": parked_key, "scope": "8 native frames; require separate independent visual inspection"}, "\t"))
	print("SHARED_2106_CAPTURE ", status, " frames=", shots.size())
	for p in root.find_children("*", "AudioStreamPlayer3D", true, false): p.stop()
	for p in root.find_children("*", "AudioStreamPlayer", true, false): p.stop()
	main.queue_free()
	camera.queue_free()
	for i in 5: await process_frame
	main = null
	world = null
	preload("res://game/world/materials.gd").clear_cache()
	preload("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	OS.delay_msec(100)
	await process_frame
	quit(0 if status == "PASS" else 1)
func _fixture(id: String, subject: Node3D, offset: Vector3) -> void:
	var basis := Basis(Vector3.UP, subject.global_rotation.y)
	camera.global_position = subject.global_position + basis * offset
	camera.look_at(subject.global_position + Vector3.UP * 0.72)
	camera.make_current()
	await _save(id, subject)
func _game_camera(id: String, subject: Node3D, yaw: float) -> void:
	world.camera_rig.follow(subject, &"on_foot")
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	world.camera_rig.camera.make_current()
	await _save(id, subject)
func _save(id: String, subject: Node3D) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(id + ".png")
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		failures.append("save error %s: %d" % [path, error])
		return
	shots.append({"file": path, "subject": str(subject.get_path()), "subject_position": str(subject.global_position), "camera_position": str(root.get_camera_3d().global_position), "size": str(image.get_size())})
	print("SHARED_2106_SHOT ", path)

extends SceneTree
## Native LIGHT-01 A/B in one production world; no source swaps or alternate renderer.
## tools/run.command --resolution 1920x1080 --fixed-fps 60 --script tools/capture/light01_ab.gd
## Diagnostic views use the on-foot lens/pitch and a torso anchor at 3/6/10 m.
## Context views use the actual player and unchanged on-foot camera profile.
const UniformVisual = preload("res://game/characters/uniform_visual.gd")
const Layout = preload("res://game/world/layout.gd")
const BASELINE_EMISSION_FLOOR := 0.12
const DISTANCES := [3.0, 6.0, 10.0]
const SETTLE_FRAMES := 8

var output := "res://builds/screenshots/LIGHT-01/ab"
var main: Node
var world: DemoWorld
var anchor: Node3D
var materials: Array[Dictionary] = []
var models: Array[MeshInstance3D] = []
var frames: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("LIGHT-01 requires native rendering; headless is not a visual check")
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	output = ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Could not create LIGHT-01 output directory")
		quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 12:
		await physics_frame
	world = main.world
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	anchor = Node3D.new()
	anchor.name = "Light01CaptureAnchor"
	world.add_child(anchor)
	_collect_uniforms()
	if models.size() < 2:
		push_error("LIGHT-01 requires the two production 3D uniforms")
		quit(1)
		return
	# Stop simulation and shader TIME before comparing either state. No sensor,
	# actor pose, weather phase, light, geometry or exposure changes within a pair.
	_freeze(main)
	Engine.time_scale = 0.0
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	for patrol: Node3D in [patrols.officer, patrols.officer2]:
		for view: Array in [["front", PI], ["side", PI * 0.5]]:
			for distance: float in DISTANCES:
				_diagnostic_camera(patrol, float(view[1]), distance)
				await _pair("%s_%s_%02dm" % [patrol.character, view[0], int(distance)], patrol,
					"on-foot optics; capture-only torso anchor and distance; original post/pose")
	_context_camera(Vector3(66, 0, -70), 0.9, -0.25)
	await _pair("kiosk_game_camera", patrols.officer, "production on-foot camera and player at kiosk approach")
	_context_camera(Layout.SPAWN, Layout.SPAWN_YAW, -0.30)
	await _pair("snow_game_camera", patrols.officer, "production on-foot camera and player in courtyard snow")
	_proposed(true)
	var manifest := FileAccess.open(output.path_join("capture_inputs.json"), FileAccess.WRITE)
	if manifest:
		manifest.store_string(JSON.stringify({
			"scope": "LIGHT-01 production world; frozen paired lighting comparison; visual judgement remains manual",
			"baseline": "uniform emission floor 0.12; ordinary uniform mesh shadows off",
			"proposed": "per-surface uniform emission floors; ordinary uniform mesh shadows on",
			"unchanged": "exposure, world lights, geometry, model shape/albedo, xray shadows off, blob shadows",
			"adapter_sha256": FileAccess.get_sha256("res://game/characters/uniform_visual.gd"),
			"lighting_sha256": FileAccess.get_sha256("res://game/world/lighting.gd"),
			"source_floors": {"default": UniformVisual.EMISSION_FLOOR, "cloth": UniformVisual.CLOTH_EMISSION_FLOOR,
				"skin": UniformVisual.SKIN_EMISSION_FLOOR, "ink": UniformVisual.INK_EMISSION_FLOOR},
			"frames": frames, "failures": failures,
		}, "\t"))
	else:
		failures += 1
	Engine.time_scale = 1.0
	main.queue_free()
	for i in 3:
		await process_frame
	print("LIGHT01_AB_CAPTURE: %d frames, %d failures; manual visual review required" % [frames.size(), failures])
	quit(0 if failures == 0 and frames.size() == 28 else 1)

func _freeze(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children():
		_freeze(child)

func _collect_uniforms() -> void:
	var stack: Array[Node] = [world]
	var seen_meshes := {}
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if node.get_script() != UniformVisual:
			continue
		var mesh_instance: MeshInstance3D = node.uniform_mesh
		models.append(mesh_instance)
		var mesh: ArrayMesh = mesh_instance.mesh
		if seen_meshes.has(mesh):
			continue
		seen_meshes[mesh] = true
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			var colors: PackedColorArray = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			var mean := Color(0, 0, 0, 0)
			for color: Color in colors:
				mean += color
			mean /= float(colors.size())
			materials.append({"material": material, "proposed": material.emission,
				"baseline": material.albedo_color * mean * BASELINE_EMISSION_FLOOR})

func _proposed(enabled: bool) -> void:
	for record: Dictionary in materials:
		var material: StandardMaterial3D = record.material
		material.emission = record.proposed if enabled else record.baseline
	for model: MeshInstance3D in models:
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _diagnostic_camera(patrol: Node3D, view_yaw: float, distance: float) -> void:
	# A centred full-body diagnostic at the game's lens and pitch. The anchor is
	# visual-only; its lowered pivot frames the boots at the 3 m sample too.
	anchor.global_position = patrol.global_position + Vector3(0, -0.85, 0)
	world.camera_rig.follow(anchor, &"on_foot")
	world.camera_rig.yaw = patrol.visual.global_rotation.y + view_yaw
	world.camera_rig.snap()
	world.camera_rig.arm.spring_length = distance
	# SpringArm native updates are frozen together with the rest of the world.
	world.camera_rig.camera.position = Vector3(0, 0, distance)
	world.camera_rig.camera.reset_physics_interpolation()

func _context_camera(at: Vector3, yaw: float, pitch: float) -> void:
	world.player.place(at, yaw)
	world.camera_rig.follow(world.player, &"on_foot")
	world.camera_rig.yaw = yaw
	world.camera_rig.pitch = pitch
	world.camera_rig.snap()
	# Use production collision clearance even though native spring updates stop.
	var distance: float = world.camera_rig._safe_arm_distance(world.camera_rig.arm.spring_length)
	world.camera_rig.camera.position = Vector3(0, 0, distance)
	world.camera_rig.camera.reset_physics_interpolation()

func _pair(label: String, patrol: Node3D, scope: String) -> void:
	for state: String in ["baseline", "proposed"]:
		_proposed(state == "proposed")
		for i in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var filename := label + "_" + state + ".png"
		var result := root.get_texture().get_image().save_png(output.path_join(filename))
		if result != OK:
			failures += 1
			push_error("Could not save LIGHT-01 frame: " + filename)
			continue
		var camera: Camera3D = world.camera_rig.camera
		frames.append({"file": filename, "scope": scope, "state": state,
			"actor_position": str(patrol.global_position), "actor_visual_yaw": patrol.visual.global_rotation.y,
			"camera_position": str(camera.global_position), "camera_rotation": str(camera.global_rotation),
			"fov": camera.fov, "camera_actor_ground_distance": Vector2(camera.global_position.x - patrol.global_position.x,
				camera.global_position.z - patrol.global_position.z).length(),
			"sensor_enabled": patrol.sensor.enabled, "sensor_range": patrol.sensor.range_m,
			"xray_shown": patrol.xray_shown()})
		print("LIGHT01_AB_CAPTURE: " + output.path_join(filename))

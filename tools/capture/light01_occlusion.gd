extends SceneTree
## Native production-world before/after and causal wall witness using the production headlight.
const Lighting = preload("res://game/world/lighting.gd")
const Layout = preload("res://game/world/layout.gd")
var main: Node
var checks := 0
var failures := 0
var out := "res://builds/screenshots/LIGHT-01/occlusion"
var original: Array[Dictionary] = []
var validate_only := false
var sky_angular_distance := 0.0
var sky_opacity := 1.0
func _initialize() -> void:
	call_deferred("run")
func frames(n: int) -> void:
	for i in n:
		await process_frame
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LIGHT01_NATIVE FAIL: " + message)
func capture(label: String) -> Image:
	await frames(5)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png(out.path_join(label + ".png"))
	return result
func freeze(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		freeze(child)
func pair(proposed: bool) -> void:
	for record in original:
		var light: Light3D = record.light
		light.shadow_enabled = record.shadow if proposed else false
	var sky: DirectionalLight3D = main.world.get_node("LightingAndWeather/CoolSky")
	sky.shadow_enabled = true
	sky.light_angular_distance = sky_angular_distance if proposed else 0.0
	sky.shadow_opacity = sky_opacity if proposed else 1.0
func run() -> void:
	validate_only = OS.get_cmdline_user_args().has("--validate-fixture")
	if DisplayServer.get_name() == "headless" and not validate_only:
		push_error("Native render required")
		quit(2)
		return
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/LIGHT-01"))
	AudioServer.set_bus_mute(0, true)
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/LIGHT-01/capture_profile.json"
	root.add_child(main)
	await frames(4)
	main.start_game()
	await frames(12)
	var world: Node3D = main.world
	var sky: DirectionalLight3D = world.get_node("LightingAndWeather/CoolSky")
	sky_angular_distance = sky.light_angular_distance
	sky_opacity = sky.shadow_opacity
	freeze(main)
	Engine.time_scale = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Light3D and not node is DirectionalLight3D:
			original.append({"light": node, "shadow": node.shadow_enabled})
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = world.camera_rig.camera.fov
	world.add_child(camera)
	camera.make_current()
	for view in [
		["courtyard", Vector3(-45, 3.1, 102), Vector3(-38, 1.1, 87)],
		["kiosk", Vector3(68, 2.9, -65), Vector3(56, 1.5, -77)],
		["street", Vector3(65, 2.5, -48), Vector3(65, 0.8, -67)],
	]:
		camera.global_position = view[1]
		camera.look_at(view[2])
		for state in [false, true]:
			pair(state)
			if not validate_only:
				await capture(view[0] + ("_after" if state else "_before"))
	pair(true)
	# The same actual headlight is isolated on a separate render layer. A wall
	# between source and receiver must remove the light; an uncovered neighbour
	# must remain lit. No sky, SSR, fog, exposure, particles or unrelated lights.
	var beam: SpotLight3D = world.get_node("Car/Visual/Body/BeamLeft")
	var source: SpotLight3D = beam.duplicate()
	var fixture := Node3D.new()
	fixture.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(fixture)
	fixture.global_position = Vector3(0, 60, 0)
	fixture.add_child(source)
	source.position = Vector3(0, 1.0, 3)
	source.rotation = Vector3(deg_to_rad(-5), 0, 0)
	source.visible = true
	source.light_cull_mask = 1 << 17
	source.distance_fade_enabled = false
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.6, 0.6)
	material.roughness = 1.0
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(12, 0.1, 16)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = material
	floor_instance.layers = 1 << 17
	floor_instance.position = Vector3(0, -0.05, -3)
	fixture.add_child(floor_instance)
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(1.1, 3, 0.25)
	wall.mesh = wall_mesh
	wall.material_override = material
	wall.layers = 1 << 17
	wall.position = Vector3(0, 1.5, 0)
	fixture.add_child(wall)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0
	camera.environment = env
	camera.cull_mask = 1 << 17
	camera.global_position = fixture.global_position + Vector3(0, 10, -1.5)
	camera.look_at(fixture.global_position + Vector3(0, 0, -1.5), Vector3.FORWARD)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	camera.reset_physics_interpolation()
	fixture.reset_physics_interpolation()
	await frames(2)
	var blocked := camera.unproject_position(fixture.global_position + Vector3(0, 0, -3.0))
	var open := camera.unproject_position(fixture.global_position + Vector3(1.8, 0, -3.0))
	check(Rect2(Vector2.ZERO, root.size).has_point(blocked), "blocked receiver in frame " + str(blocked))
	check(Rect2(Vector2.ZERO, root.size).has_point(open), "open receiver in frame " + str(open))
	if validate_only:
		print("LIGHT01_FIXTURE_PROJECTION: %d checks, %d failures; no rendered occlusion assertion" % [checks, failures])
		main.queue_free()
		Engine.time_scale = 1.0
		await frames(3)
		quit(0 if failures == 0 else 1)
		return
	source.shadow_enabled = false
	var leak := await capture("wall_shadow_off")
	source.shadow_enabled = true
	var occluded := await capture("wall_shadow_on")
	source.visible = false
	var dark := await capture("wall_source_off")
	var blocked_leak := luminance(leak, blocked) - luminance(dark, blocked)
	var blocked_fixed := luminance(occluded, blocked) - luminance(dark, blocked)
	var open_fixed := luminance(occluded, open) - luminance(dark, open)
	check(blocked_leak > 0.04, "wall witness actually reproduces the old leak")
	check(blocked_fixed < blocked_leak * 0.2, "wall removes at least 80% of leaked headlight")
	check(open_fixed > 0.035, "unblocked control remains lit")
	print("LIGHT01_NATIVE witness: leak=%.5f blocked=%.5f open=%.5f" % [blocked_leak, blocked_fixed, open_fixed])
	var log := FileAccess.open("res://builds/checks/LIGHT-01/occlusion-measurements.json", FileAccess.WRITE)
	log.store_string(JSON.stringify({"blocked_leak": blocked_leak, "blocked_fixed": blocked_fixed,
		"open_fixed": open_fixed, "checks": checks, "failures": failures, "scope": "actual production headlight on isolated wall witness; production city paired views"}, "\t"))
	fixture.queue_free()
	main.queue_free()
	Engine.time_scale = 1.0
	await frames(3)
	print("LIGHT01_NATIVE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
func luminance(image: Image, at: Vector2) -> float:
	var sum := 0.0
	var count := 0
	if not Rect2(Vector2.ZERO, image.get_size()).has_point(at):
		check(false, "witness receiver must be inside frame: " + str(at))
		return 0.0
	for y in range(int(at.y) - 6, int(at.y) + 7):
		for x in range(int(at.x) - 6, int(at.x) + 7):
			var color := image.get_pixel(x, y)
			sum += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			count += 1
	return sum / count

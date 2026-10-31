extends SceneTree
## Native transparent portraits of the exact runtime model geometry, no SVG crops.
## ./tools/run.command --script tools/capture/ip01_portraits.gd -- --civilian3d
## Native GPU required. Output imports on the next editor/headless import pass.
const Uniform = preload("res://game/characters/uniform_visual.gd")
const Npc = preload("res://game/npc/npc.gd")
const OUTPUT := "res://assets/art/portraits3d"
const PORTRAITS := {"babka": "babka", "vendor": "vendor", "ilyusha": "ilyusha", "officer": "police", "account_officer": "officer"}
var viewport: SubViewport
var stage: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Portrait capture requires native rendering, not headless.")
		quit(2)
		return
	var output_dir := ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create portrait directory: " + output_dir)
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dfe8f0")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-28, -20, 0)
	light.light_energy = 1.2
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	stage.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.43
	stage.add_child(camera)
	camera.position = Vector3(0.11, 0.85, -2.0)
	camera.look_at(Vector3(0, 0.815, 0), Vector3.UP)
	camera.current = true
	var default_npc := Npc.new()
	var quest_tint: Color = default_npc.tint
	default_npc.free()
	var records: Array = []
	var failures := 0
	for key: String in PORTRAITS:
		var drawing: String = PORTRAITS[key]
		var visual := Uniform.new()
		visual.configure(drawing, 1.0, quest_tint if key in ["babka", "vendor"] else Color.WHITE)
		stage.add_child(visual)
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := output_dir.path_join(key + ".png")
		var used := image.get_used_rect()
		if used.size.x < 64 or used.size.y < 128 or image.get_pixel(0, 0).a > 0.01 or image.save_png(path) != OK:
			push_error("Portrait capture failed: " + key)
			failures += 1
		else:
			print("IP01_PORTRAIT: ", key, " ", used, " -> ", path)
			records.append({"portrait": key, "drawing": drawing, "path": path, "sha256": FileAccess.get_sha256(path), "alpha_bounds": str(used)})
		visual.free()
	var report_path := "res://builds/screenshots/IP-01/portraits"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path))
	var report := FileAccess.open(report_path + "/capture_inputs.json", FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify({"scope": "native original runtime geometry portrait render", "resolution": [512, 512], "transparent": true, "civilian_model_sha256": FileAccess.get_sha256("res://game/characters/models/civilian_model.gd"), "police_model_sha256": FileAccess.get_sha256("res://game/characters/models/police_model.gd"), "frames": records}, "\t"))
	if report:
		report.close()
	viewport.queue_free()
	for frame in 3:
		await process_frame
	print("IP01_PORTRAITS: ", records.size(), " captures, ", failures, " failures; visual review required")
	quit(0 if failures == 0 and records.size() == PORTRAITS.size() else 1)

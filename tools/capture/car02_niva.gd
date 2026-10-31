extends SceneTree
## Standalone native visual stand; run by the integrator, not acceptance of a gameplay consumer.
## tools/run.command --resolution 1920x1080 --fixed-fps 60 --script tools/capture/car02_niva.gd -- /absolute/output
const Niva = preload("res://game/vehicles/niva_visual.gd")
const VIEWS := [
	["front_three_quarter", Vector3(-5.5, 2.8, -6.4)],
	["left_profile", Vector3(-7.9, 1.9, 0.0)],
	["rear_three_quarter", Vector3(5.5, 2.8, 6.4)],
]
const PAINTS := [["ochre", Color(0.78, 0.40, 0.16)], ["blue", Color(0.22, 0.38, 0.49)]]
var output_dir := "res://builds/screenshots/CAR-02/niva-stand"
var stage: Node3D
var camera: Camera3D
var title: Label

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output_dir = args[0]
	output_dir = ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create Niva gallery: " + output_dir)
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	_build_stage()
	var record: Array = []
	for paint: Array in PAINTS:
		var model := Niva.build(paint[1], "н212ва 154", 0.08)
		stage.add_child(model)
		for view: Array in VIEWS:
			camera.position = view[1]
			camera.look_at(Vector3(0, 0.86, 0))
			title.text = "VAZ-2121 / %s / %s" % [str(paint[0]).to_upper(), str(view[0]).to_upper()]
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var filename := str(paint[0]) + "_" + str(view[0]) + ".png"
			var image := root.get_texture().get_image()
			var error := image.save_png(output_dir.path_join(filename))
			if error != OK:
				push_error("Niva capture failed: " + filename)
				quit(1)
				return
			record.append({"file": filename, "paint": str(paint[0]), "camera": str(camera.position)})
		model.free()
	var meshes := Niva.body_meshes()
	var body: ArrayMesh = meshes["body"]
	var wheel := Niva.wheel_mesh()
	var manifest := FileAccess.open(output_dir.path_join("capture_inputs.json"), FileAccess.WRITE)
	if manifest == null:
		push_error("Cannot write Niva gallery inputs")
		quit(1)
		return
	manifest.store_string(JSON.stringify({
		"scope": "standalone visual provider; native capture and gameplay integration require independent review",
		"model_sha256": FileAccess.get_sha256("res://game/vehicles/niva_visual.gd"),
		"size_xyz_metres": str(Niva.SIZE), "wheelbase_metres": Niva.WHEELBASE,
		"body_surfaces": body.get_surface_count(), "wheel_surfaces": wheel.get_surface_count(),
		"body_aabb": str(body.get_aabb()), "snow_depth_metres": 0.08,
		"lighting": "neutral studio, physical vehicle dimensions, perspective FOV 40",
		"frames": record,
	}, "\t"))
	manifest.close()
	print("NIVA2121_GALLERY: six frames; visual verdict and runtime consumer are not accepted by this script")
	quit()

func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.24, 0.27, 0.31)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.9, 1.0)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -28, 0)
	light.light_color = Color(1.0, 0.94, 0.86)
	light.light_energy = 1.5
	light.shadow_enabled = true
	stage.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.43, 0.47, 0.52)
	material.roughness = 0.95
	plane.material = material
	ground.mesh = plane
	ground.position.y = -0.006
	stage.add_child(ground)
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.current = true
	stage.add_child(camera)
	title = Label.new()
	title.position = Vector2(32, 24)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9))
	root.add_child(title)

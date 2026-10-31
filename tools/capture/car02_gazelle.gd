extends SceneTree
## Standalone visual stand; the integrator serializes native rendering and gameplay integration.
## tools/run.command --resolution 1920x1080 --fixed-fps 60 --script tools/capture/car02_gazelle.gd -- /absolute/output [2705|32213|32214]
const Gazelle = preload("res://game/vehicles/gazelle_visual.gd")
const VIEWS := [
	["front_three_quarter", Vector3(-7.4, 3.55, -8.5)],
	["front", Vector3(0.0, 2.35, -10.7)],
	["left_profile", Vector3(-10.7, 2.45, 0.0)],
	["right_profile", Vector3(10.7, 2.45, 0.0)],
	["rear_three_quarter", Vector3(7.4, 3.55, 8.5)],
	["rear", Vector3(0.0, 2.35, 10.7)],
	["upper_front", Vector3(4.9, 7.1, -8.3)],
]
const PAINTS := [["ivory", Color(0.82, 0.82, 0.74)], ["cargo_blue", Color(0.13, 0.30, 0.51)]]
var output_dir := "res://builds/screenshots/CAR-02/gazelle-stand"
var stage: Node3D
var camera: Camera3D
var title: Label
var model: StringName = Gazelle.CARGO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output_dir = args[0]
	if args.size() > 1:
		model = StringName(args[1])
	if model not in [Gazelle.CARGO, Gazelle.PASSENGER, Gazelle.AMBULANCE]:
		push_error("Unknown GAZelle gallery model: " + str(model))
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create GAZelle gallery: " + output_dir)
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	_build_stage()
	var record: Array = []
	for paint: Array in PAINTS:
		var vehicle := Gazelle.build(paint[1], "н705га 154", 0.08, model)
		stage.add_child(vehicle)
		for view: Array in VIEWS:
			camera.position = view[1]
			camera.look_at(Vector3(0, 1.10, 0))
			title.text = "GAZ-%s / %s / %s" % [str(model), str(paint[0]).to_upper(), str(view[0]).to_upper()]
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var filename := str(paint[0]) + "_" + str(view[0]) + ".png"
			var capture := root.get_texture().get_image()
			if capture.save_png(output_dir.path_join(filename)) != OK:
				push_error("GAZelle capture failed: " + filename)
				quit(1)
				return
			record.append({"file": filename, "paint": str(paint[0]), "camera": str(camera.position)})
		vehicle.free()
	var meshes := Gazelle.body_meshes(model)
	var body: ArrayMesh = meshes["body"]
	var wheel := Gazelle.wheel_mesh()
	var manifest := FileAccess.open(output_dir.path_join("capture_inputs.json"), FileAccess.WRITE)
	if manifest == null:
		push_error("Cannot write GAZelle gallery inputs")
		quit(1)
		return
	var input_hashes := {}
	for path in ["res://game/vehicles/gazelle_visual.gd", "res://game/vehicles/vehicle_mesh.gd",
		"res://game/vehicles/lada_paint.gdshader", "res://tools/capture/car02_gazelle.gd",
		"res://game/world/materials.gd", "res://project.godot"]:
		input_hashes[path] = FileAccess.get_sha256(path)
	manifest.store_string(JSON.stringify({
		"scope": "standalone visual provider; no gameplay consumer acceptance",
		"production_model": str(model), "standard_roof": true,
		"input_sha256": input_hashes, "engine": Engine.get_version_info(),
		"size_xyz_metres": str(Gazelle.SIZE), "wheelbase_metres": Gazelle.WHEELBASE,
		"wheel_radius_metres": Gazelle.WHEEL_RADIUS, "wheel_centres": str(Gazelle.wheel_spots()),
		"body_surfaces": body.get_surface_count(), "wheel_surfaces": wheel.get_surface_count(),
		"body_aabb": str(body.get_aabb()), "snow_depth_metres": 0.08,
		"lighting": "constant neutral studio; key rotation(-42,-28,0), energy1.5; ambient0.7; FOV40",
		"dimensions_source": "https://www.drom.ru/catalog/lcv/gaz/gazelle/272216/; tyre/twin-track definition: GAZ-2705 1995+ service manual",
		"frames": record,
	}, "\t"))
	manifest.close()
	print("GAZELLE%s_GALLERY: fourteen frames; visual review and gameplay integration remain separate" % model)
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

extends SceneTree
## Native-only geometry gallery. Does not claim actual world lighting/runtime acceptance.
## tools/run.command --resolution 1920x1080 --script tools/capture/ip01_civilian_gallery.gd
## Optional: -- /output/directory ilyusha babka vendor (default: all supported drawings).
const Models = preload("res://game/characters/models/civilian_model.gd")
const DISPLAY_HEIGHT := 1.8
var output_dir := "res://builds/screenshots/IP-01/civilian-gallery"
var panels: Array = []
var header: Label
var models: Array[Node3D] = []
var records: Array = []
var failures := 0
var expected_frames := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("IP01_CIVILIAN_GALLERY: native renderer required; no frames captured")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output_dir = args[0]
	output_dir = ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		quit(1)
		return
	var drawings: Array[String] = Models.DRAWINGS.duplicate()
	if args.size() > 1:
		drawings.clear()
		for index in range(1, args.size()): drawings.append(args[index])
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ui()
	for drawing: String in drawings:
		if not Models.supports(drawing):
			push_error("Unsupported gallery role " + drawing)
			failures += 1
			continue
		expected_frames += 2
		for index in 4:
			var model := Models.new().build_model(drawing)
			model.scale = Vector3.ONE * DISPLAY_HEIGHT
			(panels[index].stage as Node3D).add_child(model)
			models.append(model)
		var angles := [0.0, PI / 4, PI / 2, PI]
		var labels := ["FRONT", "THREE QUARTER", "PROFILE", "BACK"]
		for index in 4:
			_camera(index, angles[index], false)
			(panels[index].label as Label).text = labels[index]
		header.text = drawing + " — ORIGINAL 3D / FOUR VIEWS"
		await _save(drawing, "four_views")
		for index in 4:
			_camera(index, PI / 6 if index == 0 else PI / 4, index == 0)
			var skeleton := models[index].get_node("Skeleton3D") as Skeleton3D
			if index in [1, 2]: _walk(skeleton, 1.0 if index == 1 else -1.0)
			if index == 3:
				_walk(skeleton, 1.0)
				skeleton.reset_bone_poses()
			(panels[index].label as Label).text = ["FACE DETAIL", "LEFT STEP", "RIGHT STEP", "RESET REST"][index]
		header.text = drawing + " — FACE / RIG POSES / RESET"
		await _save(drawing, "face_rig")
		if drawing not in ["police_long", "police_round", "guard_alt"]:
			expected_frames += 1
			for index in 4:
				var skeleton := models[index].get_node("Skeleton3D") as Skeleton3D
				skeleton.reset_bone_poses()
				for side: String in ["l", "r"]:
					skeleton.set_bone_pose_rotation(skeleton.find_bone("leg_" + side), Quaternion(Vector3.RIGHT, 1.35))
					skeleton.set_bone_pose_rotation(skeleton.find_bone("foot_" + side), Quaternion(Vector3.RIGHT, -1.35))
				skeleton.force_update_all_bone_transforms()
				var foot := skeleton.find_bone("foot_l")
				var rest := skeleton.get_bone_global_rest(foot)
				var sole := skeleton.get_bone_global_pose(foot) * rest.affine_inverse() * Vector3(rest.origin.x, 0, rest.origin.z)
				models[index].position.y = -sole.y * DISPLAY_HEIGHT
				_camera(index, angles[index], false)
				(panels[index].label as Label).text = labels[index] + " / THIGH FORWARD, SHIN DOWN"
			header.text = drawing + " — TWO-SEGMENT SEATED / SOLVED SOLE AT Y=0"
			await _save(drawing, "seated")
		for model: Node3D in models: model.free()
		models.clear()
	var hashes := {}
	for source: String in ["civilian_model", "uniform_mesh_builder", "police_model", "guard_model"]:
		var path := "res://game/characters/models/" + source + ".gd"
		hashes[path] = FileAccess.get_sha256(path)
	var out := FileAccess.open(output_dir.path_join("capture_inputs.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify({"scope": "standalone visual geometry; actual CharacterSprite/world/dialog/vehicle integration NOT_RUN", "lighting": "neutral studio, Filmic exposure 1.1; not runtime winter lighting", "height": "1.8 m gallery convention; feet0/top1 model contract; not a physics or SHAR skeleton claim", "source_sha256": hashes, "frames": records}, "\t"))
	print("IP01_CIVILIAN_GALLERY: %d frames saved, %d failures; appearance review required" % [records.size(), failures])
	quit(0 if failures == 0 and records.size() == expected_frames else 1)

func _ui() -> void:
	var background := ColorRect.new()
	background.color = Color("202a36")
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	header = _label(Vector2(20, 8), Vector2(1880, 45), 28)
	var footer := _label(Vector2(20, 1012), Vector2(1880, 66), 18)
	footer.text = "Standalone geometry / neutral studio / display height 1.8 m. Gameplay scale, world light, portraits and drivers require actual consumers.\nOriginal civilian faces replace old designs; Uniform variants need approved-SVG comparison; seated panels solve soles at Y=0. This gallery is not runtime acceptance."
	for index in 4:
		var at := Vector2((index % 2) * 960, 60 + (index / 2) * 472)
		var label := _label(at + Vector2(18, 0), Vector2(920, 28), 20)
		var container := SubViewportContainer.new()
		container.position = at + Vector2(0, 30)
		container.size = Vector2(960, 436)
		root.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 436)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_4X
		container.add_child(viewport)
		var stage := Node3D.new()
		viewport.add_child(stage)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("bcc5cb")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("e7e9e6")
		environment.ambient_light_energy = 0.6
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 1.1
		var world_environment := WorldEnvironment.new()
		world_environment.environment = environment
		stage.add_child(world_environment)
		for light_spec: Vector3 in [Vector3(-32, -28, 1.25), Vector3(-20, 145, 0.45)]:
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(light_spec.x, light_spec.y, 0)
			light.light_energy = light_spec.z
			stage.add_child(light)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.near = 0.05
		camera.far = 30.0
		camera.current = true
		stage.add_child(camera)
		panels.append({"stage": stage, "camera": camera, "label": label})

func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eee8da"))
	root.add_child(label)
	return label

func _camera(index: int, angle: float, detail: bool) -> void:
	var camera := panels[index].camera as Camera3D
	var target := Vector3(0, 1.51 if detail else DISPLAY_HEIGHT * 0.5, 0)
	camera.size = 0.6 if detail else 2.1
	camera.position = target + Vector3(sin(angle) * 5, 0, -cos(angle) * 5)
	camera.look_at(target, Vector3.UP)

func _walk(skeleton: Skeleton3D, phase: float) -> void:
	for spec: Array in [["leg_l", 0.25], ["leg_r", -0.25], ["foot_l", -0.09], ["foot_r", 0.09], ["upper_arm_l", -0.13], ["upper_arm_r", 0.13]]:
		skeleton.set_bone_pose_rotation(skeleton.find_bone(spec[0]), Quaternion(Vector3.RIGHT, float(spec[1]) * phase))
	skeleton.force_update_all_bone_transforms()

func _save(drawing: String, mode: String) -> void:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var file := drawing + "_" + mode + ".png"
	var error := root.get_texture().get_image().save_png(output_dir.path_join(file))
	if error != OK:
		failures += 1
		push_error("Cannot save gallery frame " + file)
		return
	var cameras: Array = []
	for panel: Dictionary in panels:
		cameras.append({"label": (panel.label as Label).text, "transform": str((panel.camera as Camera3D).transform), "size": (panel.camera as Camera3D).size})
	records.append({"drawing": drawing, "mode": mode, "file": file, "cameras": cameras})
	print("IP01_CIVILIAN_GALLERY: " + output_dir.path_join(file))

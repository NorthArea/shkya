extends SceneTree
## Native rendering only. Does not modify live scenes, models or actor controllers.
## ./tools/run.command --resolution 1920x1080 --fixed-fps 60 --script tools/capture/ip01_uniform_gallery.gd
## Optional: -- /absolute/output/directory
const MODEL_DIR := "res://game/characters/models/"
const ART_DIR := "res://assets/art/characters/"
const DISPLAY_HEIGHT := 1.8
const PANEL_SIZE := Vector2i(960, 900)
const VIEWS := [["front", 0.0, "front"], ["three_quarter", PI / 4.0, "front"], ["profile", PI / 2.0, "side"], ["back", PI, "back"]]
var output_dir := "res://builds/screenshots/IP-01/uniform-gallery"
var failures := 0
var saved := 0
var stage_3d: Node3D
var stage_reference: Node3D
var camera_3d: Camera3D
var camera_reference: Camera3D
var title: Label
var reference_label: Label
var footer: Label
var model: Node3D
var reference: Sprite3D
var record: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): output_dir = args[0]
	output_dir = ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create gallery directory: " + output_dir)
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	for kind: String in ["police", "guard"]:
		var factory: Script = load(MODEL_DIR + kind + "_model.gd") as Script
		if factory == null or not factory.can_instantiate():
			_fail("Cannot load model factory: " + kind)
			continue
		var instance: RefCounted = factory.new() as RefCounted
		if instance == null or not instance.has_method("build_model"):
			_fail("Factory lacks build_model: " + kind)
			continue
		model = instance.call("build_model") as Node3D
		if model == null:
			_fail("Factory returned no model: " + kind)
			continue
		model.scale = Vector3.ONE * DISPLAY_HEIGHT
		stage_3d.add_child(model)
		for view: Array in VIEWS:
			_reset_pose()
			_set_camera(float(view[1]), false)
			_set_reference(kind, str(view[2]), "idle")
			title.text = "%s — %s / 3D REST" % [kind.to_upper(), str(view[0]).to_upper()]
			reference_label.text = "APPROVED SVG — %s" % ("FRONT (no 3/4 source)" if view[0] == "three_quarter" else str(view[2]).to_upper())
			await _save(kind + "_" + str(view[0]), kind, str(view[0]), "rest")
		for phase: int in [1, -1]:
			_reset_pose()
			_walking_pose(float(phase))
			_set_camera(PI / 4.0, false)
			_set_reference(kind, "side", "idle")
			title.text = "%s — SKELETON STEP %s" % [kind.to_upper(), "LEFT" if phase == 1 else "RIGHT"]
			reference_label.text = "APPROVED SVG — SIDE IDLE (no walk reference available)"
			await _save(kind + "_rig_step_" + str(phase), kind, "three_quarter", "step " + str(phase))
		_reset_pose()
		_set_camera(PI / 6.0, true)
		_set_reference(kind, "front", "idle")
		title.text = kind.to_upper() + " — FACE / HAT / SHOULDERS"
		reference_label.text = "APPROVED SVG — FRONT DETAIL"
		await _save(kind + "_face_hat_shoulders", kind, "detail", "rest")
		model.free()
		model = null
	if reference != null:
		reference.free()
	var manifest := FileAccess.open(output_dir.path_join("capture_inputs.json"), FileAccess.WRITE)
	if manifest == null:
		_fail("Cannot write capture inputs")
	else:
		var source_hashes: Dictionary = {}
		for name: String in ["uniform_mesh_builder", "police_model", "guard_model"]:
			var source_path := MODEL_DIR + name + ".gd"
			source_hashes[source_path] = FileAccess.get_sha256(source_path)
		manifest.store_string(JSON.stringify({"scope": "standalone visual models; not runtime integration", "display_height_metres": DISPLAY_HEIGHT, "scale_status": "gallery convention only, SHAR world/physics scale undecided here", "lighting": "neutral studio, Filmic exposure 1.1; NOT actual world lighting", "model_sha256": source_hashes, "frames": record}, "\t"))
		manifest.close()
	print("IP01_GALLERY: %d frames saved, %d failures; visual verdict and runtime acceptance require review" % [saved, failures])
	quit(0 if failures == 0 and saved == 14 else 1)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("18212b")
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	title = _label(Vector2(24, 10), Vector2(1870, 48), 30)
	var left_label := _label(Vector2(24, 57), Vector2(900, 30), 22)
	left_label.text = "TRUE 3D / neutral studio / same orthographic camera"
	reference_label = _label(Vector2(984, 57), Vector2(900, 30), 22)
	footer = _label(Vector2(24, 1004), Vector2(1870, 70), 19)
	footer.text = "DISPLAY HEIGHT 1.8 m ONLY — no gameplay scale decision. Model feet/top = 0/1. Reference alpha bounds normalized to same visible height.\nPolice: prominent epaulettes, props, NO blue sleeve patch. Guard: maroon beret, NO cockade/badge, empty hands. Gallery is not runtime acceptance."
	var left: Array = _panel(Vector2(0, 96))
	stage_3d = left[0] as Node3D
	camera_3d = left[1] as Camera3D
	var right: Array = _panel(Vector2(960, 96))
	stage_reference = right[0] as Node3D
	camera_reference = right[1] as Camera3D

func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eee8d9"))
	root.add_child(label)
	return label

func _panel(at: Vector2) -> Array:
	var container := SubViewportContainer.new()
	container.position = at
	container.size = Vector2(PANEL_SIZE)
	root.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = PANEL_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("bdc6ce")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dfe8f0")
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, -28, 0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_energy = 0.45
	stage.add_child(fill)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(20, 20)
	ground.mesh = ground_mesh
	ground.position.y = -0.006
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a8b2ba")
	material.roughness = 1.0
	ground.material_override = material
	stage.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 2.25
	camera.near = 0.05
	camera.far = 30.0
	camera.current = true
	stage.add_child(camera)
	return [stage, camera]

func _set_camera(angle: float, detail: bool) -> void:
	var target := Vector3(0, 1.42 if detail else DISPLAY_HEIGHT * 0.5, 0)
	var eye := target + Vector3(sin(angle) * 5.0, 0.0, -cos(angle) * 5.0)
	for camera: Camera3D in [camera_3d, camera_reference]:
		camera.size = 0.82 if detail else 2.25
		camera.position = eye
		camera.look_at(target, Vector3.UP)

func _set_reference(kind: String, view: String, frame: String) -> void:
	if reference != null:
		reference.free()
		reference = null
	var path := ART_DIR + "%s_%s_%s.svg" % [kind, view, frame]
	if not ResourceLoader.exists(path):
		_fail("Missing approved reference " + path)
		return
	var source := load(path) as Texture2D
	if source == null:
		_fail("Unreadable approved reference " + path)
		return
	var image: Image = source.get_image()
	if image == null:
		_fail("Cannot inspect approved reference bounds " + path)
		return
	if image.is_compressed():
		if image.decompress() != OK:
			_fail("Cannot decompress reference " + path)
			return
	var used: Rect2i = image.get_used_rect()
	if used.size.y <= 0:
		_fail("Reference is empty " + path)
		return
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = Rect2(used)
	reference = Sprite3D.new()
	reference.name = "ApprovedReferenceOnly"
	reference.texture = cropped
	reference.pixel_size = DISPLAY_HEIGHT / float(used.size.y)
	reference.position.y = DISPLAY_HEIGHT * 0.5
	reference.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	reference.shaded = false
	reference.double_sided = true
	reference.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	reference.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage_reference.add_child(reference)
	reference.set_meta("reference_path", path)
	reference.set_meta("alpha_crop", [used.position.x, used.position.y, used.size.x, used.size.y])

func _skeleton() -> Skeleton3D:
	if model == null: return null
	return model.find_child("Skeleton3D", true, false) as Skeleton3D

func _reset_pose() -> void:
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null:
		_fail("Model lacks Skeleton3D")
		return
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()

func _rotate_bone(skeleton: Skeleton3D, bone_name: String, axis: Vector3, angle: float) -> void:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		_fail("Missing pose bone " + bone_name)
		return
	skeleton.set_bone_pose_rotation(index, Quaternion(axis, angle))

func _walking_pose(phase: float) -> void:
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null: return
	_rotate_bone(skeleton, "leg_l", Vector3.RIGHT, 0.28 * phase)
	_rotate_bone(skeleton, "leg_r", Vector3.RIGHT, -0.28 * phase)
	_rotate_bone(skeleton, "foot_l", Vector3.RIGHT, -0.12 * phase)
	_rotate_bone(skeleton, "foot_r", Vector3.RIGHT, 0.12 * phase)
	_rotate_bone(skeleton, "upper_arm_l", Vector3.RIGHT, -0.10 * phase)
	_rotate_bone(skeleton, "upper_arm_r", Vector3.RIGHT, 0.10 * phase)
	_rotate_bone(skeleton, "head", Vector3.UP, 0.10 * phase)
	skeleton.force_update_all_bone_transforms()

func _save(label: String, kind: String, view: String, pose: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(output_dir.path_join(label + ".png"))
	if result != OK:
		_fail("Cannot save " + label + ": " + str(result))
		return
	saved += 1
	var reference_path: String = str(reference.get_meta("reference_path", "")) if reference != null else ""
	record.append({"file": label + ".png", "kind": kind, "view": view, "pose": pose, "camera_transform": str(camera_3d.transform), "orthographic_size": camera_3d.size, "reference": reference_path, "reference_sha256": FileAccess.get_sha256(reference_path) if reference_path != "" else "", "reference_alpha_crop": reference.get_meta("alpha_crop", []) if reference != null else []})
	print("IP01_GALLERY: " + output_dir.path_join(label + ".png"))

func _fail(message: String) -> void:
	failures += 1
	push_error("IP01_GALLERY: " + message)

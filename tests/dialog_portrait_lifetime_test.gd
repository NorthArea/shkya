extends SceneTree
## Headless checks resource lifetime after actual CanvasItem draw submission.
## Dummy cannot verify final pixels; native verification remains separate.
const Dialog = preload("res://game/ui/dialog_panel.gd")
var failures: Array[String] = []
var checks := 0
var draws := 0
var capture := false
var capture_directory := ""
const EVIDENCE := "res://builds/checks/POLISH-03/dialog-portraits"

func source_has_face(kind: StringName, path: String) -> bool:
	var image := Image.new()
	if image.load_svg_from_string(FileAccess.get_file_as_string(path)) != OK:
		return false
	var region: Rect2 = Dialog.PORTRAIT_REGION[kind]
	var scale := image.get_width() / 400.0
	var crop := image.get_region(Rect2i(region.position * scale, region.size * scale))
	var ink := 0
	for y in range(0, crop.get_height(), 4):
		for x in range(0, crop.get_width(), 4):
			var color := crop.get_pixel(x, y)
			if color.a > 0.5 and color.get_luminance() < 0.85:
				ink += 1
	return ink > crop.get_width() * crop.get_height() / 16 * 0.2

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in count:
		await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	capture = "--capture-portraits" in OS.get_cmdline_user_args()
	if capture and DisplayServer.get_name() == "headless":
		push_error("Native portrait capture requires a real renderer")
		quit(1)
		return
	if capture:
		root.set_flag(Window.FLAG_NO_FOCUS, true)
		await frames(2)
		root.set_flag(Window.FLAG_NO_FOCUS, true)
		if not capture_focus_is_safe():
			return
		capture_directory = EVIDENCE + "/native-%d" % Time.get_ticks_usec()
		if DirAccess.dir_exists_absolute(capture_directory) or DirAccess.make_dir_recursive_absolute(capture_directory) != OK:
			push_error("Cannot create fresh portrait capture directory")
			quit(1)
			return
		print("NATIVE PORTRAIT DIRECTORY: ", capture_directory)
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.portrait.draw.connect(func(): draws += 1)
	for kind: StringName in [&"vendor", &"babka", &"ilyusha", &"officer", &"account_officer"]:
		var path := Dialog.portrait_source_path(kind)
		check(ResourceLoader.exists(path), "%s approved source exists" % kind)
		check(source_has_face(kind, path), "%s approved crop contains visible face artwork" % kind)
		var previous_draws := draws
		dialog.open("QA", "Portrait lifetime", [], kind)
		await frames(4)
		check(draws > previous_draws, "%s actual draw callback ran" % kind)
		check(ResourceLoader.has_cached(path), "%s draw keeps its texture alive after callback returns" % kind)
		var resource: WeakRef = weakref(dialog._portrait_texture(path))
		check(resource.get_ref() != null, "%s retained texture can be reused" % kind)
		for side in [150, 220]:
			dialog.portrait.custom_minimum_size = Vector2(side, side)
			dialog.portrait.queue_redraw()
			await frames(3)
			check(dialog.portrait.size.x >= side and dialog.portrait.size.y >= side, "%s portrait adapts to %d UI size" % [kind, side])
			if capture:
				await RenderingServer.frame_post_draw
				if not capture_focus_is_safe():
					dialog.queue_free()
					return
				var image := root.get_texture().get_image()
				check(not image.is_empty(), "native rendered image available")
				check(image.save_png(capture_directory + "/%s-%d.png" % [kind, side]) == OK, "native portrait capture saved")
			dialog.close()
			dialog.open("QA", "Reopened portrait", [], kind)
			await frames(3)
			check(dialog._portrait_texture(path) == resource.get_ref(), "%s reopen reuses the live texture" % kind)
		dialog.close()
		await frames(2)
	var missing := EVIDENCE + "/late-texture.tres"
	if FileAccess.file_exists(missing):
		DirAccess.remove_absolute(missing)
	check(dialog._portrait_texture(missing) == null, "missing resource returns no texture")
	check(not dialog._portrait_textures.has(missing), "missing resource is not negatively cached")
	var late_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	late_image.fill(Color.CORAL)
	check(ResourceSaver.save(ImageTexture.create_from_image(late_image), missing) == OK, "late texture fixture created")
	check(dialog._portrait_texture(missing) != null, "resource appearing after a failed load is retried")
	dialog._portrait_textures.erase(missing)
	DirAccess.remove_absolute(missing)
	if not capture:
		print("NATIVE PORTRAIT PIXELS: NOT RUN (Dummy renderer); source SVG crop raster checked on CPU")
	var lifetime_refs: Array[WeakRef] = []
	for texture: Texture2D in dialog._portrait_textures.values():
		lifetime_refs.append(weakref(texture))
	dialog.queue_free()
	await frames(2)
	for resource_ref in lifetime_refs:
		check(resource_ref.get_ref() == null, "panel destruction releases its portrait texture")
	call_deferred("finish")

func capture_focus_is_safe() -> bool:
	var no_focus := root.get_flag(Window.FLAG_NO_FOCUS)
	var focused := root.has_focus()
	check(no_focus, "native capture window retains NO_FOCUS")
	check(not focused, "native capture window does not have focus")
	if not no_focus or focused:
		push_error("Aborting native portrait capture: unsafe window focus")
		quit(1)
		return false
	return true

func finish() -> void:
	print("DIALOG_PORTRAIT_LIFETIME: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

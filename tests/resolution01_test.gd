extends SceneTree
## RESOLUTION-01: real Viewport scale, preference persistence and unchanged UI/projection.

const SETTINGS_PATH := "res://game/display_settings.gd"
const OUTPUT := "res://builds/checks/RESOLUTION-01"
var checks := 0
var failures: Array[String] = []
var settings: Node
var config_path: String
var changes := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not check(ResourceLoader.exists(SETTINGS_PATH), "resolution controller exists"):
		_finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	config_path = OUTPUT.path_join("display-%d.cfg" % OS.get_process_id())
	_remove_config()
	root.size = Vector2i(1280, 720)
	await _frames(2)
	settings = _new_settings()
	check(settings.is_in_group(&"display_settings"), "settings are discoverable by both menus")
	check(settings.render_width == 1920, "first run prefers a 1920 pixel rendering budget")
	check(is_equal_approx(root.scaling_3d_scale, 1.0), "1280 window renders natively under the default budget")
	check(settings.selected_option_width() == 0, "default budget above the current size selects native")
	await _resize(Vector2i(1920, 1080), 1.0)
	await _resize(Vector2i(3024, 1964), 1920.0 / 3024.0)
	check(settings.render_width == 1920, "resizing preserves the preferred width")
	_check_options()
	await _unchanged_ui_and_projection()
	await _pause_and_resize()
	await _saved_preference()
	await _invalid_config()
	settings.free()
	_remove_config()
	_finish()

func _new_settings() -> Node:
	var node: Node = load(SETTINGS_PATH).new()
	node.config_path = config_path
	node.changed.connect(func(): changes += 1)
	root.add_child(node)
	return node

func _resize(size: Vector2i, scale: float) -> void:
	var before := changes
	root.size = size
	await _frames(2)
	check(root.size == size, "test viewport accepts %s" % size)
	check(is_equal_approx(root.scaling_3d_scale, scale), "%s uses the actual requested 3D scale" % size)
	check(changes > before, "resizing notifies open settings menus")

func _check_options() -> void:
	var options: Array = settings.available_resolutions()
	check(options[0].width == 0 and options[0].size == root.size, "native option reflects the real current aspect")
	var widths: Array[int] = []
	for option: Dictionary in options:
		check(not widths.has(option.width), "resolution options contain no duplicate widths")
		widths.append(option.width)
		check(not str(option.label).is_empty(), "every choice has a readable label")
		if option.width == 0:
			continue
		check(option.width < root.size.x and float(option.width) / root.size.x >= 0.25, "choices are valid downscales only")
		check(option.size.x == option.width, "option size uses its render width")
		var height := roundi(float(option.width) * root.size.y / root.size.x)
		check(option.size.y == height, "resolution height preserves the current display aspect")
	check(widths == [0, 2560, 1920, 1600, 1280, 960], "options descend from native through supported widths")
	var before: int = settings.render_width
	check(settings.set_resolution_width(-1) == ERR_INVALID_PARAMETER, "negative selection is rejected")
	check(settings.set_resolution_width(1111) == ERR_INVALID_PARAMETER, "unsupported width is rejected")
	check(settings.set_resolution_width(3840) == ERR_INVALID_PARAMETER, "upscale selection is rejected")
	check(settings.render_width == before, "invalid selections preserve the preference")

func _unchanged_ui_and_projection() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var window_size := root.size
	var mode := root.mode
	var content_size := root.content_scale_size
	var canvas := root.get_visible_rect()
	var stretch := root.get_stretch_transform()
	var screen_point := camera.unproject_position(Vector3(1, 1, -10))
	var ray := camera.project_ray_normal(canvas.size * 0.75)
	var physics_ticks := Engine.physics_ticks_per_second
	var time_scale := Engine.time_scale
	var before := changes
	check(settings.set_resolution_width(1280) == OK, "lower 3D resolution can be selected")
	await _frames(2)
	check(is_equal_approx(root.scaling_3d_scale, 1280.0 / window_size.x), "selection changes the actual root 3D scale")
	check(settings.selected_option_width() == 1280 and changes > before, "selection and menu notification track the requested width")
	check(root.size == window_size and root.mode == mode, "resolution selection never changes OS window size or fullscreen mode")
	check(root.content_scale_size == content_size and root.get_visible_rect() == canvas, "UI retains the same viewport and logical size")
	check(root.get_stretch_transform().is_equal_approx(stretch), "UI stretch remains unchanged")
	check(camera.unproject_position(Vector3(1, 1, -10)).distance_to(screen_point) < 0.001, "world markers keep the same screen projection")
	check(camera.project_ray_normal(canvas.size * 0.75).distance_to(ray) < 0.0001, "camera rays and world aspect remain unchanged")
	check(Engine.physics_ticks_per_second == physics_ticks and Engine.time_scale == time_scale, "rendering choice does not affect simulation timing")
	camera.free()
	check(settings.set_resolution_width(0) == OK, "native rendering is selectable")
	check(settings.render_width == 0 and is_equal_approx(root.scaling_3d_scale, 1.0), "native selection removes the rendering cap")

func _pause_and_resize() -> void:
	check(settings.set_resolution_width(1920) == OK, "rendering preference can be restored")
	paused = true
	await _resize(Vector2i(1280, 800), 1.0)
	check(settings.render_width == 1920 and settings.selected_option_width() == 0, "pause and a smaller display preserve the rendering preference")
	check(settings.available_resolutions().size() == 2, "small display offers native and its valid lower width only")
	check(settings.set_resolution_width(960) == OK, "settings work while the game is paused")
	check(is_equal_approx(root.scaling_3d_scale, 0.75), "paused selection reaches the actual viewport")
	await _resize(Vector2i(1920, 1200), 0.5)
	check(settings.render_width == 960, "a paused resize retains the selected rendering budget")
	paused = false

func _saved_preference() -> void:
	settings.free()
	settings = _new_settings()
	check(settings.render_width == 960 and is_equal_approx(root.scaling_3d_scale, 0.5), "a new controller loads and applies the saved width")
	check(settings.set_resolution_width(0) == OK, "native preference saves successfully")
	settings.free()
	settings = _new_settings()
	check(settings.render_width == 0 and is_equal_approx(root.scaling_3d_scale, 1.0), "native preference survives a reload")

func _invalid_config() -> void:
	for value in [-1, 1111, "1280", 1280.5]:
		settings.free()
		var config := ConfigFile.new()
		config.set_value("display", "render_width", value)
		check(config.save(config_path) == OK, "invalid-config fixture is isolated and writable")
		settings = _new_settings()
		check(settings.render_width == 1920 and is_equal_approx(root.scaling_3d_scale, 1.0), "invalid saved value %s falls back to the default budget" % str(value))
	settings.free()
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	file.store_string("[malformed")
	file.close()
	settings = _new_settings()
	check(settings.render_width == 1920, "malformed configuration falls back to the default budget")

func _remove_config() -> void:
	if FileAccess.file_exists(config_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("RESOLUTION01: " + label)
	return ok

func _finish() -> void:
	paused = false
	print("RESOLUTION01: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

const Settings = preload("res://game/display_settings.gd")
const SettingsPanel = preload("res://game/ui/settings_panel.gd")
const PATH := "res://builds/checks/SETTINGS-01/graphics.cfg"
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func world() -> Node3D:
	var node := Node3D.new()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	for property in Settings.EFFECT_PROPERTIES.values():
		env.environment.set(property, true)
	node.add_child(env)
	for enabled in [true, false]:
		var light := SpotLight3D.new()
		light.shadow_enabled = enabled
		light.distance_fade_enabled = true
		light.distance_fade_shadow = 17.0
		node.add_child(light)
	return node

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	root.size = Vector2i(1920, 1080)
	var controller := Settings.new()
	controller.config_path = PATH
	root.add_child(controller)
	var scene := world()
	root.add_child(scene)
	await process_frame
	await process_frame
	var environment: Environment = scene.get_child(0).environment
	check(controller.graphics == Settings.DEFAULT_GRAPHICS, "authored defaults preserved")
	check(Engine.max_fps == 120 and not controller.graphics.vsync, "frame pacing defaults preserved")
	for key: String in Settings.EFFECT_PROPERTIES:
		check(controller.set_graphics_option(key, false) == OK, key + " save succeeds")
		check(not environment.get(Settings.EFFECT_PROPERTIES[key]), key + " changes actual Environment")
	check(controller.set_graphics_option("shadows", false) == OK, "disable shadows")
	check(not scene.get_child(1).shadow_enabled and not scene.get_child(2).shadow_enabled, "all shadows disabled")
	var dynamic_light := OmniLight3D.new()
	dynamic_light.shadow_enabled = true
	dynamic_light.distance_fade_shadow = 19.0
	scene.add_child(dynamic_light)
	var later := world()
	later.get_child(0).environment.ssil_enabled = false
	root.add_child(later)
	await process_frame
	await process_frame
	check(not later.get_child(1).shadow_enabled and not later.get_child(0).environment.ssao_enabled, "new world receives saved effects")
	check(not dynamic_light.shadow_enabled, "dynamic light inherits disabled shadows")
	check(controller.set_graphics_option("shadows", true) == OK, "restore shadows")
	check(dynamic_light.shadow_enabled and dynamic_light.distance_fade_shadow == 19.0, "dynamic light restores authored budget")
	check(controller.set_graphics_option("ssil", true) == OK and environment.ssil_enabled and not later.get_child(0).environment.ssil_enabled, "authored disabled effect stays disabled on restore")
	for item in [scene, later]:
		check(item.get_child(1).shadow_enabled and not item.get_child(2).shadow_enabled, "restore only authored shadow flags")
		check(item.get_child(1).distance_fade_shadow == 17.0, "shadow distance budget untouched")
	var ticks := Engine.physics_ticks_per_second
	check(controller.set_graphics_option("fps_limit", 80) == OK and Engine.max_fps == 80, "real frame cap changes")
	check(controller.set_graphics_option("vsync", true) == OK and controller.graphics.vsync, "VSync saves requested state")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_vsync_mode(root.get_window_id()) == DisplayServer.VSYNC_ENABLED, "native VSync changes")
	else:
		print("SKIP native VSync observation: headless DisplayServer has no swapchain")
	check(Engine.physics_ticks_per_second == ticks, "physics timing preserved")
	check(controller.set_graphics_option("fps_limit", 81) == ERR_INVALID_PARAMETER, "invalid cap rejected")
	check(controller.set_graphics_option("shadows", "false") == ERR_INVALID_PARAMETER, "invalid bool rejected")
	var menu := SettingsPanel.new()
	var pause_menu := SettingsPanel.new()
	root.add_child(menu)
	root.add_child(pause_menu)
	menu.open()
	await process_frame
	await process_frame
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(menu.get_global_rect()), "settings fits 1080p")
	menu.graphics_options["ssao"].item_selected.emit(0)
	check(environment.ssao_enabled and controller.graphics.ssao, "menu selection changes world property")
	check(pause_menu.graphics_options["ssao"].selected == 0, "pause panel shares menu selection")
	paused = true
	pause_menu.graphics_options["ssao"].item_selected.emit(1)
	check(not environment.ssao_enabled and menu.graphics_options["ssao"].selected == 1, "pause selection changes same world and menu")
	paused = false
	menu.free()
	pause_menu.free()
	scene.free()
	later.free()
	controller.free()
	controller = Settings.new()
	controller.config_path = PATH
	root.add_child(controller)
	check(controller.graphics.fps_limit == 80 and controller.graphics.vsync and not controller.graphics.ssao, "preference round trip")
	scene = world()
	root.add_child(scene)
	await process_frame
	await process_frame
	check(not scene.get_child(0).environment.ssao_enabled, "reloaded preferences affect next world")
	controller.config_path = PATH.path_join("missing/never.cfg")
	check(controller.set_graphics_option("ssao", true) != OK and not controller.graphics.ssao, "save failure does not falsely apply setting")
	scene.free()
	controller.free()
	var config := ConfigFile.new()
	config.set_value("graphics", "fps_limit", 99999)
	config.set_value("graphics", "shadows", "false")
	config.set_value("graphics", "ssao", false)
	config.save(PATH)
	controller = Settings.new()
	controller.config_path = PATH
	root.add_child(controller)
	check(controller.graphics.fps_limit == 120 and controller.graphics.shadows and not controller.graphics.ssao, "invalid values fall back independently")
	controller.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("SETTINGS01_GRAPHICS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

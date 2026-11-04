extends SceneTree

const OUT := "res://builds/checks/SETTINGS-01/independent/"
const SHOTS := "res://builds/screenshots/SETTINGS-01/independent/"
var checks := 0
var failures := 0

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	_run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for index in count:
		await process_frame

func snapshot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	root.get_texture().get_image().save_png(SHOTS + label + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1920, 1080)
	for file in ["display.cfg", "audio.cfg", "achievements.json"]:
		DirAccess.remove_absolute(OUT + file)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.display_settings_path = OUT + "display.cfg"
	main.audio_settings_path = OUT + "audio.cfg"
	main.achievement_path = OUT + "achievements.json"
	root.add_child(main)
	await frames(5)
	var panel: Control = main.menu.settings
	var other: Control = main.pause_menu.settings
	main.menu.settings_button.pressed.emit()
	await frames(15)
	verify(panel.visible and not main.menu.card.visible, "menu button opens settings")
	verify(root.gui_get_focus_owner() == panel.back_button, "menu opens with back focus")
	verify(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel.get_global_rect()), "real menu settings fits viewport")
	await snapshot("menu-graphics")
	var option: OptionButton = panel.graphics_options["fps_limit"]
	option.item_selected.emit(2)
	verify(Engine.max_fps == 80 and other.graphics_options["fps_limit"].selected == 2, "menu UI applies engine cap and synchronizes pause UI")
	if DisplayServer.get_name() != "headless":
		panel.graphics_options["vsync"].item_selected.emit(0)
		verify(DisplayServer.window_get_vsync_mode(root.get_window_id()) == DisplayServer.VSYNC_ENABLED, "real menu UI enables native VSync")
		panel.graphics_options["vsync"].item_selected.emit(1)
		verify(DisplayServer.window_get_vsync_mode(root.get_window_id()) == DisplayServer.VSYNC_DISABLED, "real menu UI disables native VSync")
	for key in ["shadows", "ssao", "ssil", "ssr", "fog"]:
		panel.graphics_options[key].item_selected.emit(1)
	verify(not main.display_settings.graphics.shadows, "menu UI disables shadows")
	var records: Dictionary = main.display_settings._world_nodes
	verify(not records.is_empty(), "real menu worlds registered")
	for record: Dictionary in records.values():
		var node: Node = record.node.get_ref()
		if node is Light3D:
			verify(not node.shadow_enabled, "real menu light loses shadows")
		elif record.has("environment"):
			for property in main.display_settings.EFFECT_PROPERTIES.values():
				verify(not record.environment.get(property), "real menu environment effect disabled")
	for channel: StringName in [&"master", &"music", &"effects"]:
		var slider: HSlider = panel.audio_section.sliders[channel]
		for value in [0.0, 50.0, 100.0]:
			slider.value = value
			var bus: int = AudioServer.get_bus_index(main.audio_settings.CHANNEL_BUSES[channel])
			verify(is_equal_approx(main.audio_settings.get_volume(channel), value / 100.0), "UI changes channel gain")
			verify(other.audio_section.sliders[channel].value == value, "menu and pause audio synchronized")
			verify(AudioServer.is_bus_mute(bus) == (value == 0.0), "0 mute and positive gain unmute")
			if value > 0:
				verify(is_equal_approx(AudioServer.get_bus_volume_linear(bus), value / 100.0), "actual bus linear gain matches UI")
		verify(slider.get_node(slider.focus_next) != null and slider.get_node(slider.focus_previous) != null, "audio keyboard focus paths resolve")
	panel.audio_section.sliders[&"effects"].grab_focus()
	await frames(3)
	var focused_audio: Control = panel.audio_section.sliders[&"effects"]
	print("FOCUS_AUDIO: focus=%s scroll=%d viewport=%s control=%s" % [root.gui_get_focus_owner(), panel._scroll.scroll_vertical, panel._scroll.get_global_rect(), focused_audio.get_global_rect()])
	verify(panel._scroll.get_global_rect().encloses(focused_audio.get_global_rect()), "focusing audio reveals the whole slider")
	await snapshot("menu-audio")
	panel.back_button.pressed.emit()
	await frames(2)
	verify(not panel.visible and root.gui_get_focus_owner() == main.menu.settings_button, "back closes settings and restores menu focus")
	main.start_game()
	await frames(8)
	verify(not main.display_settings._world_nodes.is_empty(), "new mission world registered")
	for record: Dictionary in main.display_settings._world_nodes.values():
		var node: Node = record.node.get_ref()
		verify(is_instance_valid(node) and node.is_inside_tree(), "registry retains live world nodes only")
		if node is Light3D:
			verify(not node.shadow_enabled, "new mission lights inherit settings")
	main.set_paused(true)
	main.pause_menu.settings_button.pressed.emit()
	await frames(15)
	verify(paused and other.visible, "actual pause settings stays paused")
	other.audio_section.sliders[&"effects"].value = 50
	verify(main.music.muffled(), "volume slider preserves pause lowpass")
	other.audio_section.sliders[&"effects"].grab_focus()
	await frames(3)
	await snapshot("pause-audio")
	other.graphics_options["shadows"].item_selected.emit(0)
	for record: Dictionary in main.display_settings._world_nodes.values():
		var node: Node = record.node.get_ref()
		if node is Light3D:
			verify(node.shadow_enabled == record.shadow, "pause UI restores authored light flag")
	other.back_button.pressed.emit()
	verify(paused and not other.visible and main.pause_menu.card.visible, "pause back returns to paused menu")
	main.set_paused(false)
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in root.find_children("*", type, true, false):
			verify(player.bus in [&"Music", &"SettingsMusic", &"Effects"], "actual live player routed through settings master")
			player.stop()
	main.queue_free()
	await frames(8)
	main = null
	load("res://game/world/materials.gd").clear_cache()
	load("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	await frames(3)
	print("SETTINGS01_INDEPENDENT: %d checks, %d failures; display=%s; audio=%s" % [checks, failures, DisplayServer.get_name(), AudioServer.get_driver_name()])
	quit(1 if failures else 0)

extends SceneTree
## Controller-only reading of every help row; push_input uses the GUI path even without a native window.
const SettingsPanel = preload("res://game/ui/settings_panel.gd")
const Display = preload("res://game/display_settings.gd")
const Audio = preload("res://game/audio/audio_settings.gd")
const Dialog = preload("res://game/ui/dialog_panel.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 4) -> void:
	for i in count:
		await process_frame

func button(code: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		root.push_input(event)
		await frames()

func _run() -> void:
	load("res://game/input_setup.gd").install()
	var display := Display.new()
	display.config_path = "res://builds/checks/SETTINGS-01/final-ux/unused-display.cfg"
	root.add_child(display)
	var audio := Audio.new()
	audio.config_path = "res://builds/checks/SETTINGS-01/final-ux/unused-audio.cfg"
	root.add_child(audio)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := SettingsPanel.new()
	center.add_child(panel)
	await frames()
	var grid: GridContainer = panel.find_children("*", "GridContainer", true, false)[0]
	for height in [1080, 600]:
		root.size = Vector2i(1920, 1080) if height == 1080 else Vector2i(1067, 600)
		await frames()
		panel.open()
		await frames(20)
		check(root.gui_get_focus_owner() == panel.back_button, "entry focus stays on Back at %dp" % height)
		for direction: JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP]:
			var seen: Array[int] = []
			for step in 40:
				await button(direction)
				var focused := root.gui_get_focus_owner()
				for row in Dialog.CONTROLS.size():
					var action: Control = grid.get_child(3 + row * 3)
					if focused != action or row in seen:
						continue
					seen.append(row)
					var focus_style := action.get_theme_stylebox("panel")
					check(action is PanelContainer and focus_style is StyleBoxFlat and focus_style.border_color == SettingsPanel.INK and focus_style.get_border_width(SIDE_LEFT) >= 2, "focused help row draws an ink panel border at %dp" % height)
					var bounds := action.get_global_rect()
					for column in [1, 2]:
						bounds = bounds.merge((grid.get_child(3 + row * 3 + column) as Control).get_global_rect())
					check(panel._scroll.get_global_rect().grow(1.0).encloses(bounds), "whole controls row '%s' visible at %dp" % [Dialog.CONTROLS[row][0], height])
				check(root.get_visible_rect().encloses(panel.back_button.get_global_rect()), "Back remains visible at %dp step %d" % [height, step])
				if focused == panel.back_button:
					break
			check(seen.size() == Dialog.CONTROLS.size(), "D-pad %s reaches every controls row at %dp (%d/%d)" % [direction, height, seen.size(), Dialog.CONTROLS.size()])
			check(root.gui_get_focus_owner() == panel.back_button, "D-pad completes cycle to Back at %dp" % height)
		var closed := [false]
		var close := func(): closed[0] = true
		panel.back_requested.connect(close, CONNECT_ONE_SHOT)
		await button(JOY_BUTTON_A)
		check(closed[0], "A still activates Back at %dp" % height)
		await button(JOY_BUTTON_DPAD_UP)
		await button(JOY_BUTTON_DPAD_UP)
		check(root.gui_get_focus_owner() == grid.get_child(3 + (Dialog.CONTROLS.size() - 1) * 3), "Up reaches help from footer at %dp" % height)
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var folder := "res://builds/screenshots/SETTINGS-01/final-ux"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
			check(root.get_texture().get_image().save_png(folder.path_join("controls-%dp.png" % height)) == OK, "native controls frame saved at %dp" % height)
		closed[0] = false
		panel.back_requested.connect(close, CONNECT_ONE_SHOT)
		await button(JOY_BUTTON_B)
		check(closed[0], "B returns from help at %dp" % height)
		panel.hide()
	panel.free()
	center.free()
	display.free()
	audio.free()
	print("SETTINGS01_CONTROLS: %d checks, %d failures; display=%s audio=%s" % [checks, failures, DisplayServer.get_name(), AudioServer.get_driver_name()])
	quit(1 if failures else 0)

extends SceneTree

const SETTINGS := "res://game/audio/audio_settings.gd"
const OUTPUT := "res://builds/checks/AUDIO-SETTINGS-01/audio.cfg"
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not check(ResourceLoader.exists(SETTINGS), "audio settings controller exists"):
		_finish()
		return
	DirAccess.remove_absolute(OUTPUT)
	var dialog: Node = load("res://game/ui/dialog_panel.gd").new()
	root.add_child(dialog)
	check(AudioServer.get_bus_index(&"Effects") >= 0 and dialog.voice.bus == &"Effects", "standalone dialog creates and routes effects bus before Main")
	dialog.free()
	var controller: Node = load(SETTINGS).new()
	controller.config_path = OUTPUT
	root.add_child(controller)
	check(controller.is_in_group(&"audio_settings"), "both menus can discover one controller")
	for channel in [&"master", &"music", &"effects"]:
		check(controller.get_volume(channel) == 1.0, "default mix unchanged: %s" % channel)
	check(controller.set_volume(&"music", 0.4) == OK, "music preference saved")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(&"SettingsMusic")), 0.4), "actual music bus gain changes immediately")
	check(controller.set_volume(&"effects", 0.0) == OK, "zero preference accepted")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Effects")), "zero uses bus mute")
	check(is_finite(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Effects"))), "zero retains finite bus gain")
	check(controller.set_volume(&"music", NAN) == ERR_INVALID_PARAMETER, "NaN rejected")
	check(controller.set_volume(&"music", -1.0) == ERR_INVALID_PARAMETER, "negative rejected")
	check(controller.set_volume(&"music", 1.1) == ERR_INVALID_PARAMETER, "overrange rejected")
	check(controller.set_volume(&"unknown", 1.0) == ERR_INVALID_PARAMETER, "unknown rejected")
	paused = true
	check(controller.set_volume(&"master", 0.7) == OK, "preferences work during pause")
	check(paused, "audio preferences preserve pause")
	paused = false
	var section: VBoxContainer = load("res://game/ui/audio_settings_section.gd").new()
	root.add_child(section)
	check(section.get_focus_controls().size() == 3, "three keyboard/gamepad controls")
	var controls: Array = section.get_focus_controls()
	controls[1].value = 65.0
	check(is_equal_approx(controller.get_volume(&"music"), 0.65), "slider applies preference")
	controller.set_volume(&"music", 0.4)
	section.free()
	controller.free()
	controller = load(SETTINGS).new()
	controller.config_path = OUTPUT
	root.add_child(controller)
	check(is_equal_approx(controller.get_volume(&"music"), 0.4), "music roundtrip")
	check(controller.get_volume(&"effects") == 0.0, "mute roundtrip")
	check(is_equal_approx(controller.get_volume(&"master"), 0.7), "master roundtrip")
	controller.free()
	var invalid := ConfigFile.new()
	invalid.set_value("audio", "master", "loud")
	invalid.set_value("audio", "music", -0.2)
	invalid.set_value("audio", "effects", NAN)
	invalid.save(OUTPUT)
	controller = load(SETTINGS).new()
	controller.config_path = OUTPUT
	root.add_child(controller)
	for channel in [&"master", &"music", &"effects"]:
		check(controller.get_volume(channel) == 1.0, "invalid saved channel falls back: %s" % channel)
	controller.config_path = "res://builds/checks/AUDIO-SETTINGS-01/missing/audio.cfg"
	check(controller.set_volume(&"music", 0.2) != OK, "failed save reported")
	check(controller.get_volume(&"music") == 1.0, "failed save keeps previous mix")
	controller.free()
	DirAccess.remove_absolute(OUTPUT)
	await _actual_players()
	_finish()

func _actual_players() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	main.audio_settings_path = OUTPUT
	main.achievement_path = "res://builds/checks/AUDIO-SETTINGS-01/achievements.json"
	root.add_child(main)
	await process_frame
	var controller: Node = main.audio_settings
	check(get_nodes_in_group(&"audio_settings").size() == 1, "Main owns exactly one controller")
	var menu_audio: Node = main.menu.settings.find_child("AudioSettings", true, false)
	var pause_audio: Node = main.pause_menu.settings.find_child("AudioSettings", true, false)
	check(menu_audio != null and pause_audio != null, "both actual menus contain audio section")
	if menu_audio and pause_audio:
		menu_audio.sliders[&"music"].value = 42.0
		check(is_equal_approx(controller.get_volume(&"music"), 0.42) and pause_audio.sliders[&"music"].value == 42.0, "both menus share live preference")
	check(main.ui_click.bus == &"Effects", "menu clicks follow effects")
	check(main.music.player.bus == &"Music", "authored music bus preserved")
	var authored := AudioServer.get_bus_index(&"Music")
	check(AudioServer.get_bus_send(authored) == &"SettingsMusic", "pause lowpass sends to music preference")
	check(AudioServer.get_bus_effect(authored, 0) is AudioEffectLowPassFilter, "pause lowpass preserved")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"SettingsMusic")) == &"SettingsMaster", "music follows master")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Effects")) == &"SettingsMaster", "effects follow master")
	main.start_game()
	for i in 5:
		await process_frame
	var sound: Node = main.world.get_node("SoundDirector")
	for player in [sound.engine, sound.skid, sound.wind, sound.city_traffic, sound.ui, sound.chime, sound.step_player, sound.coin_player, sound.door_slam]:
		check(player.bus == &"Effects", "actual effect routed: " + player.name)
	check(sound.window_music.bus == &"SettingsMusic", "window music follows music")
	check(sound.car_radio.music.player.bus == &"SettingsMusic", "radio bed follows music")
	check(sound.car_radio.music.tuning.bus == &"Effects", "radio tuning follows effects")
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in root.find_children("*", type, true, false):
			check(player.bus in [&"Effects", &"Music", &"SettingsMusic"], "actual source follows master: " + String(player.get_path()))
	var engine_level: float = sound.engine.volume_db
	main.set_paused(true)
	check(controller.set_volume(&"effects", 0.25) == OK, "paused world mix updates")
	check(sound.engine.volume_db == engine_level, "mixer keeps authored engine envelope")
	check(main.music.muffled(), "mixer keeps pause lowpass")
	main.set_paused(false)
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in root.find_children("*", type, true, false):
			player.stop()
	main.queue_free()
	for i in 5:
		await process_frame
	main = null
	sound = null
	load("res://game/world/materials.gd").clear_cache()
	load("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	await create_timer(0.15).timeout
	DirAccess.remove_absolute(OUTPUT)

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
	return condition

func _finish() -> void:
	print("AUDIO-SETTINGS-01: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

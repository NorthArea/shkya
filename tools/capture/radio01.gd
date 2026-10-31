extends SceneTree
## Native capture: tools/run.command --resolution 1920x1080 --max-fps 60 --script tools/capture/radio01.gd -- --skip-intro
## Captures the real tuning/music/weather timing; no private delay overrides.
const OUT := "res://builds/screenshots/RADIO-01/playlist"
var main: Node
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(name_: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name_ + ".png"))
func run() -> void:
	create_timer(25.0, true, false, true).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/RADIO-01/capture-profile.json"
	root.add_child(main)
	await frames(5)
	main.menu._open_settings()
	await frames(24)
	var card: Control = main.menu.settings
	print("RADIO_SETTINGS_RECT: ", card.get_global_rect(), " viewport ", root.get_visible_rect())
	await shot("settings_credits_controls")
	main.menu._close_settings()
	main.start_game()
	await frames(8)
	var world: Node = main.world
	world.enter_car()
	var sound: Node = world.get_node("SoundDirector")
	var music: Node = sound.car_radio.music
	while not music.player.playing: await process_frame
	while sound.radio_text() == "": await process_frame
	await shot("live_news_and_music")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = true
	Input.parse_input_event(key)
	await shot("tuning_classical")
	key = InputEventKey.new()
	key.physical_keycode = KEY_R
	key.pressed = false
	Input.parse_input_event(key)
	while not music.player.playing: await process_frame
	await shot("classical_station")
	main.quit_game()

extends SceneTree
## INTRO-01: кадры вступительной заставки в настоящем окне → builds/screenshots/INTRO-01/NN_*.png.
## Заставка здесь НЕ пропускается (Intro.force_enabled): телефон крупно с заголовком, свайп, последний заголовок,
## пузырь «Пойду прогуляюсь», отъезд камеры, первый игровой кадр после заставки и затемнение пропуска по E.
## Запуск: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/capture_intro.gd

const IntroScript = preload("res://game/ui/intro.gd")
const OUT := "res://builds/screenshots/INTRO-01"

var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	IntroScript.force_enabled = true
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.menu.start_button.pressed.emit()
	for i in 2:
		await process_frame
	var intro: Intro = main.world.get_node("Intro")
	var shots := [
		["01_phone_headline0", 1.75],
		["02_swipe", IntroScript.headline_start(1) - IntroScript.SWIPE * 0.45],
		["03_phone_headline1", IntroScript.headline_start(1) + 0.9],
		["04_phone_headline3", IntroScript.headline_start(3) + 0.9],
		["05_bubble", IntroScript.bubble_at() + 1.0],
		["06_pullback", IntroScript.pullback_at() + 1.0],
	]
	for shot in shots:
		while is_instance_valid(intro) and intro.elapsed < shot[1]:
			await physics_frame
		await _shot(shot[0])
	while is_instance_valid(intro):
		await physics_frame
	for i in 30:
		await physics_frame
	await _shot("07_game_start")
	# Пропуск по E: кадр посреди затемнения.
	main.start_game()
	for i in 2:
		await process_frame
	intro = main.world.get_node("Intro")
	while intro.elapsed < 3.0:
		await physics_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	for i in 9:
		await physics_frame
	await _shot("08_skip_fade")
	IntroScript.force_enabled = false
	main.queue_free()
	for i in 10:
		await process_frame
	quit(0)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())

extends SceneTree
## STORY-01: кадры в настоящем окне → builds/screenshots/STORY-01/NN_*.png: три поста ленты заставки, пузырь,
## гашение экрана при провале стелса (полоса, точка) и карточка «В ГОРОДЕ Н. НИЧЕГО НЕ ПРОИЗОШЛО» (два подзаголовка).
## Запуск (окно в фоне): open -g -n -W -a tools/local/Godot.app --args --path "$PWD" --fixed-fps 60
##   --resolution 1920x1080 --script tools/capture/capture_story01.gd

const IntroScript = preload("res://game/ui/intro.gd")
const CaughtPanelScript = preload("res://game/ui/caught_panel.gd")
const OUT := "res://builds/screenshots/STORY-01"

var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	IntroScript.force_enabled = true
	CaughtPanelScript.force_enabled = true
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.start_game()
	for i in 2:
		await process_frame
	var intro: Intro = main.world.get_node("Intro")
	var shots := []
	for k in 3:
		shots.append(["0%d_post%d" % [k + 1, k], IntroScript.headline_start(k) + IntroScript.headline_hold(k) * 0.5])
	shots.append(["04_bubble", IntroScript.bubble_at() + 1.0])
	for shot in shots:
		while is_instance_valid(intro) and intro.elapsed < shot[1]:
			await physics_frame
		await _shot(shot[0])
	while is_instance_valid(intro):
		await physics_frame
	for i in 60:
		await physics_frame
	await _shot("05_game_start")
	var world: Node = main.world
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	var panel: CaughtPanel = world.get_node("CaughtPanel")
	world.stealth.alert_now()
	while panel.elapsed < CaughtPanel.SQUASH * 0.6:
		await physics_frame
	await _shot("06_off_squash")
	while panel.elapsed < CaughtPanel.SQUASH + CaughtPanel.LINE * 0.5:
		await physics_frame
	await _shot("07_off_line")
	while panel.elapsed < CaughtPanel.off_seconds() + 0.6:
		await physics_frame
	await _shot("08_card_1")
	panel.retry()
	for i in 30:
		await physics_frame
	await _shot("09_after_retry")
	while world.stealth.protection_left() > 0.0:
		await physics_frame
	world.stealth.alert_now()
	await physics_frame
	while panel.elapsed < CaughtPanel.off_seconds() + 0.6:
		await physics_frame
	await _shot("10_card_2")
	IntroScript.force_enabled = false
	CaughtPanelScript.force_enabled = false
	paused = false
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

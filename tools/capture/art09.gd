extends SceneTree
## ART-09: сравнение кандидатов с исходными моделями e01/e03.
## Слева исходный police/guard, справа его варианты. Игровой профиль камеры и единый масштаб.
## tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/art09.gd
## Только фронт: тот же вызов с -- front. Только семейство: -- police или -- guard.
const Layout = preload("res://game/world/layout.gd")
const NpcScript = preload("res://game/npc/npc.gd")
const OUT := "res://builds/screenshots/ART-09/revision3"
const GROUPS := {"police": ["police", "police_long", "police_round"], "guard": ["guard", "guard_alt"]}
var main: Node
var world: DemoWorld
var actors: Array[Node3D] = []
var saved_frames := 0
var save_failures := 0

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var families: Array = GROUPS.keys()
	if "police" in args: families = ["police"]
	elif "guard" in args: families = ["guard"]
	var angles := [["front", PI], ["side", PI * 0.5], ["back", 0.0], ["walking", -PI * 0.5]]
	if "front" in args: angles = [["front", PI]]
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 8: await physics_frame
	world = main.world
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var spot := Layout.SPAWN + Vector3(10, 0, -12)
	# Профиль on_foot, без смены FOV или размеров персонажей; герой не закрывает середину ряда.
	var anchor := Node3D.new()
	anchor.position = spot + Vector3(0, 0, 2.2)
	world.add_child(anchor)
	world.camera_rig.follow(anchor, &"on_foot")
	world.camera_rig.yaw = 0.0
	world.camera_rig.pitch = -0.15
	world.camera_rig.snap()
	# Перед/бок/спина/ходьба, в каждом случае сначала police, затем guard.
	for angle in angles:
		for family: String in families:
			var drawings: Array = GROUPS[family]
			for i in drawings.size():
				var npc := NpcScript.new()
				npc.name = "ART09_" + drawings[i]
				npc.character = drawings[i]
				npc.solid = false
				npc.height_m = 2.05
				npc.tint = Color.WHITE
				npc.position = spot + Vector3((i - (drawings.size() - 1) * 0.5) * 2.6, 0, 0)
				npc.facing_yaw = angle[1]
				world.add_child(npc)
				npc.interactable.enabled = false
				var label := Label3D.new()
				label.text = "ИСХОДНЫЙ" if i == 0 else "КАНДИДАТ %d" % i
				label.position.y = 2.18
				label.font = load("res://assets/fonts/Pangolin-Regular.ttf")
				label.font_size = 42
				label.pixel_size = 0.006
				label.outline_size = 8
				label.modulate = Color(0.94, 0.9, 0.74)
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				npc.add_child(label)
				actors.append(npc)
			for i in 20: await physics_frame
			if angle[0] == "walking":
				for i in 18:
					for npc in actors: npc.position.x += 0.035
					await physics_frame
			await _save(family + "_" + angle[0] + "_comparison")
			for npc in actors: npc.queue_free()
			actors.clear()
			await process_frame
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	for i in 5: await physics_frame
	OS.delay_msec(100)
	await process_frame
	var expected := families.size() * angles.size()
	if save_failures == 0 and saved_frames == expected:
		print("ART09_CAPTURE: PASS (%d frames)" % saved_frames)
		quit(0)
	else:
		push_error("ART09_CAPTURE: FAIL (%d/%d frames, %d save errors)" % [saved_frames, expected, save_failures])
		quit(1)

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT.path_join(label + ".png"))
	var result := root.get_texture().get_image().save_png(path)
	if result != OK:
		save_failures += 1
		push_error("ART09 CAPTURE: could not save %s (error %d)" % [path, result])
		return
	saved_frames += 1
	print("ART09 CAPTURE: ", path)

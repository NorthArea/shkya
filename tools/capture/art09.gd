extends SceneTree
## ART-09: витрина новых обличий в настоящем дворе, на камере следования.
## Существующие посты/сенсоры и жители не переставляются. Временные NPC без тела/сенсора.
## tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/art09.gd
## Существующие NPC в городе: тот же вызов с -- --native; два последовательных мира и третий после меню.
const Layout = preload("res://game/world/layout.gd")
const NpcScript = preload("res://game/npc/npc.gd")
const OUT := "res://builds/screenshots/ART-09"
const PAIRS := [["police_long", "police_round"], ["omon_helmet", "omon_hood"], ["resident_parka", "resident_scarf"]]
var main: Node
var saved_frames := 0
var save_failures := 0
var world: DemoWorld
var actors: Array[Node3D] = []

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	# Необязательный фильтр одной из существующих пар: -- omon_helmet.
	var args := OS.get_cmdline_user_args()
	if "--native" in args:
		await _native()
		return
	var selected: Array = PAIRS
	if not args.is_empty():
		selected = []
		for pair in PAIRS:
			if args[0] in pair:
				selected.append(pair)
		if selected.is_empty():
			push_error("ART09_CAPTURE: unknown pair filter " + args[0])
			quit(1)
			return
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 8: await physics_frame
	world = main.world
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Открытый двор; камера и масштаб — штатная камера героя.
	var spot := Layout.SPAWN + Vector3(10, 0, -12)
	world.player.place(spot + Vector3(0, 0, 4.8), 0.0)
	world.camera_rig.yaw = 0.0
	world.camera_rig.pitch = -0.15
	world.camera_rig.snap()
	for pair in selected:
		for i in 2:
			var npc := NpcScript.new()
			npc.name = "ART09_" + pair[i]
			npc.character = "police" if pair[i].begins_with("police") else "guard" if pair[i].begins_with("omon") else "resident_ushanka_walk"
			npc.appearance = pair[i]
			npc.solid = false
			npc.height_m = 2.05
			npc.tint = Color.WHITE
			npc.position = spot + Vector3((i - 0.5) * 2.8, 0, 0)
			npc.facing_yaw = PI
			world.add_child(npc)
			npc.interactable.enabled = false
			actors.append(npc)
		for angle in [["front", PI], ["side", PI * 0.5], ["back", 0.0]]:
			for npc in actors: npc.facing_yaw = angle[1]
			for i in 40: await physics_frame
			await _save(pair[0] + "_" + angle[0] + "_game_camera")
		# Рядом видны разные силуэты и настоящая смена кадров на пути, не принудительный frame.
		for npc in actors: npc.facing_yaw = -PI * 0.5
		for i in 18:
			for npc in actors: npc.position.x += 0.035
			await physics_frame
		await _save(pair[0] + "_walking_game_camera")
		for npc in actors: npc.queue_free()
		actors.clear()
		await process_frame
	await _finish(selected.size() * 4)

func _finish(expected: int) -> void:
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.queue_free()
	for i in 5: await physics_frame
	OS.delay_msec(100)
	await process_frame
	if save_failures == 0 and saved_frames == expected:
		print("ART09_CAPTURE: PASS (%d frames)" % saved_frames)
		quit(0)
	else:
		push_error("ART09_CAPTURE: FAIL (%d/%d frames saved, %d save failures)" % [saved_frames, expected, save_failures])
		quit(1)

func _native() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("native")))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for generation in 3:
		if generation > 0:
			for audio in world.find_children("*", "AudioStreamPlayer", true, false) + world.find_children("*", "AudioStreamPlayer3D", true, false):
				audio.stop()
		if generation == 2:
			main.return_to_menu()
			for i in 5: await physics_frame
			for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
				audio.stop()
		main.start_game()
		for i in 8: await physics_frame
		world = main.world
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var patrols: Node = world.get_node("LevelGeometry/Patrols")
		var people: Node = world.get_node("LevelGeometry/Residents")
		var subjects: Array = [patrols.officer, patrols.officer2]
		for index in [56, 57, 58, 59, 62, 63]: subjects.append(people.residents[index])
		for subject: Node3D in subjects:
			# Житель сам выходит из подъезда/магазина; его план, позицию и видимость не меняем.
			var available := false
			for step in 1800:
				if _visible_subject(subject):
					world.camera_rig.follow(subject, &"on_foot")
					var visual: Node3D = subject.get_node("Visual")
					world.camera_rig.yaw = visual.global_rotation.y + PI
					world.camera_rig.snap()
					for i in 12: await physics_frame
					if _visible_subject(subject):
						available = true
						break
				await physics_frame
			if not available:
				save_failures += 1
				push_error("ART09_CAPTURE: actual subject never became visible " + str(subject.name))
				continue
			var look: CharacterSprite = subject.get_node("Visual/Look")
			var label := "native/world%d_%s_%s" % [generation + 1, subject.name, look.resolved_character()]
			print("ART09 NATIVE: ", subject.name, " drawing=", look.resolved_character(), " position=", subject.global_position)
			await _save(label)
	await _finish(24)

func _visible_subject(subject: Node3D) -> bool:
	return subject.is_visible_in_tree() and (not subject is Resident or not (subject as Resident).hidden)


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

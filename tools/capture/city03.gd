extends SceneTree

var main: Node
var world: DemoWorld
var out: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "res://builds/screenshots/CITY-03/after"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 12: await physics_frame
	world = main.world
	var shots := [
		["01_yard", Vector3(-30, 2.0, 96), Vector3(-60, 2.5, 80)],
		["02_street_a", Vector3(16, 1.7, 40), Vector3(-14, 1.0, 28)],
		["03_stop", Vector3(67, 1.8, -52), Vector3(56, 2, -77)],
		["04_street_b", Vector3(72, 1.8, -40), Vector3(72, 4, 30)],
		["05_road_surface", Vector3(5, 1.5, 38), Vector3(0, 0.0, 32)],
		["06_dog", Vector3(35, 1.7, -83), Vector3(40, 0.5, -86)],
	]
	var cam := Camera3D.new()
	cam.far = 4000.0
	root.add_child(cam)
	for shot in shots:
		cam.make_current()
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		for i in 12: await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(shot[0] + ".png"))
	cam.queue_free()
	world.player.place(Vector3(0, 0, 40), PI * 0.5)
	world.camera_rig.yaw = PI * 0.5
	world.camera_rig.snap()
	for i in 24: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("07_game_camera.png"))
	if world.get_node_or_null("LevelGeometry/WindBags"):
		for i in 600: await physics_frame
		var bag: Node3D = world.get_node("LevelGeometry/WindBags").bags[0]
		var close := Camera3D.new()
		root.add_child(close)
		close.make_current()
		close.global_position = bag.global_position + Vector3(-2.2, 1.2, 2.2)
		close.look_at(bag.global_position)
		for i in 2: await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("08_bag.png"))
		close.queue_free()
	var ambient := world.get_node("LevelGeometry/Ambient")
	var dog: Node3D = ambient.dog
	world.player.place(dog.global_position + Vector3(-1.5, 0, 0), -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.15
	world.camera_rig.snap()
	for i in 12: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("09_dog_prompt.png"))
	var interaction := world.player.current_interactable()
	if interaction != null and interaction.interaction_id == &"dog":
		interaction.interact(world.player)
		for i in 25: await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("10_dog_pet.png"))
	main.quit_game()

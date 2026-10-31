extends SceneTree
## Opt-in experiment on the real map. No race or chase is enabled in the normal game.
## -- --interactive --evade: player follows an escaping NPC; omit --evade for NPC pursuit.
## Without --interactive, records a 30-second physical trace; headless skips screenshots.
const OUTPUT := "res://builds/checks/DRIVER-01/chase-experiment.json"
var main: Node
var world: DemoWorld
var records: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var interactive := args.has("--interactive")
	var mode: StringName = &"evade" if args.has("--evade") else &"pursue"
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/DRIVER-01/experiment-achievements.json"
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 8:
		await physics_frame
	world = main.world
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	var npc: PathVehicle = traffic.cars[0]
	if not npc.has_method("start_driving"):
		push_error("Driver mode is not integrated into TrafficCar")
		quit(1)
		return
	var lane = traffic.car_path
	var player_s := 30.0 if mode == &"evade" else 54.0
	var npc_s := 54.0 if mode == &"evade" else 30.0
	var direction: Vector3 = lane.direction_at(player_s)
	# Initial fixture placement only. All subsequent movement uses the real vehicle controllers.
	world.car.reset_to(lane.position_at(player_s), atan2(-direction.x, -direction.z))
	npc.setup(lane, npc_s)
	world.enter_car()
	world.stealth.grant_grace(3600.0)
	world.camera_rig.snap()
	if not npc.call("start_driving", mode, world.car):
		push_error("Driver mode rejected the experiment")
		quit(1)
		return
	print("DRIVER01_EXPERIMENT: ", mode, "; ordinary player controls; interactive=", interactive)
	var frame := 0
	while interactive or frame < 1800:
		await physics_frame
		frame += 1
		if frame % 30 == 0:
			var ai: RefCounted = npc.get("driver_ai")
			records.append({"seconds": frame / 60.0, "npc": vector(npc.global_position), "player": vector(world.car.global_position),
				"speed": npc.speed, "mode": ai.get("mode"), "state": ai.get("state"), "reason": ai.get("reason"),
				"target_visible": ai.get("target_visible"), "observation_age": ai.get("observation_age")})
			if records.size() > 7200:
				records.pop_front()
		if frame in [120, 480, 960, 1800] and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var output := "res://builds/screenshots/DRIVER-01/%s-%04d.png" % [mode, frame]
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"mode": mode, "records": records}, "\t"))
	main.queue_free()
	await process_frame
	print("DRIVER01_EXPERIMENT: trace saved; visual and gameplay acceptance remain separate")
	quit(0)

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

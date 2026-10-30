extends SceneTree
## Постановочные кадры настоящих занятий с игровой камеры; не ручной проход миссии.

const Layout = preload("res://game/world/layout.gd")
const OUT := "res://builds/screenshots/ARENA-03/activities"
var main: Node
var world: DemoWorld

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(15)
	world = main.world
	world.stealth.grant_grace(120.0)
	var residents: Node = world.get_node("LevelGeometry/Residents")
	for actor: Resident in residents.residents:
		actor.set_physics_process(false)
		actor._act_stop()
	residents.life.reserved.clear()
	for spec in [[15, &"dig_1"], [1, &"carpet"], [18, &"hood"]]:
		var actor: Resident = residents.residents[spec[0]]
		actor.spot_id = spec[1]
		actor.hidden = false
		actor.show()
		actor.state = &"walk"
		residents.life.reserve(actor.spot_id, actor)
		actor._arrive()
		actor._wait = 100.0
		var at := actor.global_position
		var forward := Vector3(-sin(actor.facing_yaw), 0.0, -cos(actor.facing_yaw))
		var side := Vector3(-forward.z, 0.0, forward.x)
		world.player.place(at - forward * 2.5 + side * 1.5, actor.facing_yaw)
		world.camera_rig.follow(world.player, &"on_foot")
		world.camera_rig.yaw = actor.facing_yaw
		world.camera_rig.snap()
		await _frames(12)
		for phase in 2:
			actor._act_t = float(actor.WORK_PERIODS[actor._act_kind]) * (actor.WORK_CONTACT - actor.index * 0.17 + phase * 0.5)
			actor._process(0.0)
			await _frames(2)
			await RenderingServer.frame_post_draw
			var path := ProjectSettings.globalize_path(OUT.path_join("%s_%d.png" % [spec[1], phase]))
			if root.get_texture().get_image().save_png(path) != OK:
				quit(1)
				return
			print("ARENA03_ACTIVITY SHOT ", spec[1], " ", phase)
		actor._act_stop()
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	print("ARENA03_ACTIVITY_CAPTURE: PASS")
	quit(0)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

extends SceneTree
const Uniform = preload("res://game/characters/uniform_visual.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var visual := Uniform.new()
	visual.configure("ilyusha", 1.765, Color.WHITE)
	root.add_child(visual)
	visual.imported_hero.set_process(false)
	await process_frame
	print("FACADE imported=", visual.imported_hero != null, " manual=", visual.supports_manual_bone_interpolation(), " scale=", visual.model.scale, " bones=", visual.skeleton.get_bone_count())
	print("SOLE SURFACES ", visual.imported_hero._sole_surfaces)
	for speed: float in [0.0, 0.975, 2.0, 4.0, 5.357, 7.0, 8.25]:
		visual.reset_pose()
		var lowest := INF
		var highest := -INF
		var head_low := INF
		var head_high := -INF
		for frame in 120:
			visual.position.z -= speed / 60.0
			visual.update_locomotion(Vector3(0, 0, -speed), true, &"locomotion", 1.0 / 60.0)
			visual.imported_hero._sample(1.0 / 60.0)
			await process_frame
			for point: Vector3 in visual.posed_vertices():
				var posed := visual.model.transform * point
				lowest = minf(lowest, posed.y)
				highest = maxf(highest, posed.y)
			if speed == 0.975 and frame % 20 == 0:
				print("CONTACT ", frame, " foot=", visual.bone_transform("LeftFoot").origin, " target=", visual.imported_hero._foot_targets[0].position, " targetR=", visual.imported_hero._foot_targets[1].position, " finalfootR=", visual.bone_transform("RightFoot").origin)
				for surface in visual.uniform_mesh.mesh.get_surface_count():
					var surface_low := INF
					for point: Vector3 in visual.imported_hero._posed_surface_vertices(surface):
						surface_low = minf(surface_low, point.y)
					if surface_low < -0.005:
						print("LOW ", visual.uniform_mesh.mesh.surface_get_material(surface).resource_name, "=", surface_low)
			var head := (visual.model.transform * visual.bone_transform("Head")).origin
			head_low = minf(head_low, head.y)
			head_high = maxf(head_high, head.y)
		print("SPEED ", speed, " minsole=", lowest, " maxheight=", highest, " headbob=", head_high - head_low, " modelY=", visual.model.position.y)
	visual.free()
	quit()

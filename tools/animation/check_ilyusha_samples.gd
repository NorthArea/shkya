extends SceneTree
const Visual = preload("res://game/characters/imported_hero_visual.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var hero := Visual.new()
	root.add_child(hero)
	hero.configure(1.765, Color.WHITE)
	hero.set_process(false)
	hero.animation_tree.active = false
	hero.skeleton.reset_bone_poses()
	var rest_low := INF
	for point: Vector3 in hero.posed_vertices():
		rest_low = minf(rest_low, point.y)
	print("REST sole=", rest_low, " height=", hero.uniform_mesh.mesh.get_aabb().size.y, " scale=", hero.model.scale)
	for clip: String in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Driving", "Jump"]:
		hero.animation_tree.active = false
		hero.animation_player.play(clip)
		for fraction: float in [0.0, 0.25, 0.5, 0.75]:
			hero.animation_player.seek(hero.animation_player.get_animation(clip).length * fraction, true)
			hero.animation_player.advance(0.0)
			hero.skeleton.force_update_all_bone_transforms()
			var points := hero.posed_vertices()
			var bounds := AABB(points[0], Vector3.ZERO)
			for point: Vector3 in points:
				assert(point.is_finite())
				bounds = bounds.expand(point)
			print(clip, " t=", fraction, " bounds=", bounds, " head=", hero.bone_transform("Head").origin, " hand=", hero.bone_transform("LeftHand").origin, " knee=", hero.bone_transform("LeftLowerLeg").origin, " foot=", hero.bone_transform("LeftFoot").origin, " hips=", hero.bone_transform("Hips").origin)
		hero.animation_player.stop()
	hero.animation_tree.active = true
	hero.update_locomotion(Vector3(0, 0, -2.0), true, &"locomotion", 0.016)
	hero._sample(0.016)
	print("TREE tracks=", hero.animation_tree.get("parameters/WalkJog/blend_amount"), " bones=", hero.skeleton.get_bone_count(), " player=", hero.animation_player.is_playing())
	hero.free()
	quit()

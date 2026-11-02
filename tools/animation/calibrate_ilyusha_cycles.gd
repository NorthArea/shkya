extends SceneTree
const Visual = preload("res://game/characters/imported_hero_visual.gd")
const WINDOWS := {
	"Walk": [[0.075, 0.6033], [0.5767, 1.1033]],
	"Jog_Fwd": [[0.0333, 0.1883], [0.5283, 0.6883]],
	"Sprint": [[0.0267, 0.2217], [0.585, 0.7433]],
}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var hero := Visual.new()
	root.add_child(hero)
	hero.configure(1.765, Color.WHITE)
	hero.set_process(false)
	hero.animation_tree.active = false
	hero._leg_ik.active = false
	hero._foot_orientation.active = false
	hero.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip: String in WINDOWS:
		hero.skeleton.reset_bone_poses()
		hero.animation_player.play(clip)
		var duration := hero.animation_player.get_animation(clip).length
		var speeds: Array[float] = []
		var hips_low := INF
		var hips_high := -INF
		for side in 2:
			var toe := hero.skeleton.find_bone("LeftToes" if side == 0 else "RightToes")
			var window: Array = WINDOWS[clip][side]
			for sample_index in 100:
				var phase: float = lerpf(window[0], window[1], float(sample_index) / 99.0)
				var at := _sample_toe(hero, toe, fposmod(phase, 1.0) * duration)
				var after := _sample_toe(hero, toe, fposmod(phase + 0.0005, 1.0) * duration)
				speeds.append(absf((after.z - at.z) / (duration * 0.0005)))
		for sample_index in 101:
			_sample_toe(hero, 1, duration * float(sample_index) / 100.0)
			var hips_y := hero.skeleton.get_bone_global_pose(hero.skeleton.find_bone("Hips")).origin.y
			hips_low = minf(hips_low, hips_y)
			hips_high = maxf(hips_high, hips_y)
		speeds.sort()
		var speed: float = speeds[speeds.size() / 2]
		print(clip, " target_contact_speed=", speed, " stride=", speed * duration, " hips_y_range=", Vector2(hips_low, hips_high))
	hero.free()
	quit()

func _sample_toe(hero: Node3D, bone: int, time: float) -> Vector3:
	hero.animation_player.seek(time, true)
	hero.animation_player.advance(0.0)
	hero.skeleton.force_update_all_bone_transforms()
	return hero.skeleton.get_bone_global_pose(bone).origin

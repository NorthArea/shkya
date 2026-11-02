extends SceneTree
## Both scenes have passed Godot's BoneMap, silhouette and rest-axis import.
## This step strips foreign/unmapped tracks and fixes target-specific positions.
const TARGET := "res://assets/models/characters/ilyusha/ilyusha.glb"
const SOURCE := "res://assets/animations/ilyusha/quaternius_in_place.glb"
const OUTPUT := "res://assets/animations/ilyusha/locomotion.tres"
const CLIPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump_Start", "Jump", "Jump_Land", "Punch_Jab", "Crouch_Idle", "Driving", "Sitting_Idle"]
const GROUNDED_HIPS_Y_SPAN_M := 0.020
const GROUNDED_HIPS_MEAN_M := {"Walk": 0.835, "Jog_Fwd": 0.80, "Sprint": 0.78}

func _initialize() -> void:
	var target := (load(TARGET) as PackedScene).instantiate()
	var source := (load(SOURCE) as PackedScene).instantiate()
	root.add_child(target)
	root.add_child(source)
	var target_sk := target.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var source_sk := source.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(target_sk != null and source_sk != null and player != null)
	var library := AnimationLibrary.new()
	var target_hips := target_sk.get_bone_rest(target_sk.find_bone("Hips")).origin / target_sk.motion_scale
	var source_hips := source_sk.get_bone_rest(source_sk.find_bone("Hips")).origin / source_sk.motion_scale
	for clip: String in CLIPS:
		var animation := player.get_animation(clip).duplicate() as Animation
		for track in range(animation.get_track_count() - 1, -1, -1):
			var path := animation.track_get_path(track)
			var bone := String(path.get_subname(0)) if path.get_subname_count() == 1 else ""
			var kind := animation.track_get_type(track)
			if target_sk.find_bone(bone) < 0 or bone == "Root" or kind == Animation.TYPE_SCALE_3D or (kind == Animation.TYPE_POSITION_3D and bone != "Hips"):
				animation.remove_track(track)
				continue
			animation.track_set_path(track, NodePath(String(target.get_path_to(target_sk)) + ":" + bone))
			if kind == Animation.TYPE_POSITION_3D:
				for key in animation.track_get_key_count(track):
					var position: Vector3 = animation.track_get_key_value(track, key)
					animation.track_set_key_value(track, key, target_hips + position - source_hips)
				if clip in ["Walk", "Jog_Fwd", "Sprint"]:
					if not _adapt_grounded_hips(animation, track, target_sk, clip):
						target.free()
						source.free()
						quit(1)
						return
		animation.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump", "Crouch_Idle", "Driving", "Sitting_Idle"] else Animation.LOOP_NONE
		library.add_animation(clip, animation)
		print(clip, " tracks=", animation.get_track_count(), " length=", animation.length)
	assert(ResourceSaver.save(library, OUTPUT) == OK)
	target.free()
	source.free()
	quit()

func _adapt_grounded_hips(animation: Animation, track: int, skeleton: Skeleton3D, clip: String) -> bool:
	var offsets: Array[float] = []
	var positions: Array[Vector3] = []
	var mean := 0.0
	var low := INF
	var high := -INF
	var path := String(animation.track_get_path(track).get_concatenated_names())
	for sample_index in 241:
		var time := animation.length * float(sample_index) / 240.0
		positions.append(animation.position_track_interpolate(track, time))
		var relative := Transform3D.IDENTITY
		for name_: String in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]:
			var bone := skeleton.find_bone(name_)
			var local := skeleton.get_bone_rest(bone)
			if name_ == "Hips":
				local.origin = Vector3.ZERO
			var rotation_track := animation.find_track(NodePath(path + ":" + name_), Animation.TYPE_ROTATION_3D)
			if rotation_track >= 0:
				local.basis = Basis(animation.rotation_track_interpolate(rotation_track, time))
			relative *= local
		offsets.append(relative.origin.y)
		if sample_index < 240:
			mean += relative.origin.y / 240.0
		low = minf(low, relative.origin.y)
		high = maxf(high, relative.origin.y)
	var span := high - low
	if span > GROUNDED_HIPS_Y_SPAN_M + 0.030:
		push_error("Rotation-only Head excursion cannot fit the bounded Hips stabilization: " + clip)
		return false
	var compensation := minf(1.0, GROUNDED_HIPS_Y_SPAN_M / maxf(span, 0.0001))
	for key in range(animation.track_get_key_count(track) - 1, -1, -1):
		animation.track_remove_key(track, key)
	for sample_index in 241:
		var position := positions[sample_index]
		position.y = (float(GROUNDED_HIPS_MEAN_M[clip]) + (mean - offsets[sample_index]) * compensation) / skeleton.motion_scale
		animation.track_insert_key(track, animation.length * float(sample_index) / 240.0, position)
	print(clip, " rotation-only Head span=", span, " Hips span=", span * compensation, " remaining Head span=", span * (1.0 - compensation), " mean=", GROUNDED_HIPS_MEAN_M[clip])
	return true

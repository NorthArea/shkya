extends SceneTree
## Diagnostic pictures use the real Main/Player/Look/imported skin and world light.
## CameraRig's existing on_foot profile is preserved; only its ordinary orbit yaw changes.
var main: Node
var world: DemoWorld
var hero: Node3D
var output := "res://builds/screenshots/IP-01/runtime-pose-before"
var records: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	AudioServer.set_bus_mute(0, true)
	Engine.max_fps = 60
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for frame in 30: await physics_frame
	world = main.world
	world.stealth.grant_grace(120.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hero = world.player.visual.get_node("Look").uniform_visual.imported_hero
	assert(hero != null, "Capture must show the actual imported Player body")
	await _save("idle_game_camera")
	var heading: float = world.player.visual.global_rotation.y
	await _orbit(heading + PI)
	await _save("idle_front")
	await _orbit(heading + PI * .5)
	await _save("idle_side")
	# Compare the very same sampled AnimationTree pose before foot modifiers.
	# This diagnostic is explicitly labelled; ordinary captures above are unchanged.
	if hero.has_method("_update_foot_targets"):
		hero.set_process(false)
		hero._leg_ik.active = false
		hero._foot_sampler.active = false
		hero._foot_orientation.active = false
		hero._final_bone_poses.clear()
		hero.animation_tree.advance(0.0)
		hero.skeleton.force_update_all_bone_transforms()
		await _save("idle_side_animation_without_ik")
		hero._foot_sampler.active = true
		hero._foot_orientation.active = true
		hero._leg_ik.active = true
		hero.set_process(true)
	await _orbit(heading)
	Input.action_press("move_forward")
	for frame in 50: await physics_frame
	await _save("walk_game_camera")
	var walking_yaw: float = world.camera_rig.input_yaw
	world.camera_rig.yaw += PI * .5
	world.camera_rig.input_yaw = walking_yaw
	world.camera_rig._mouse_idle = 0.0
	world.camera_rig.snap()
	for frame in 12: await physics_frame
	await _save("walk_side")
	Input.action_press("sprint")
	for frame in 45: await physics_frame
	await _save("run_side")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	for frame in 45: await physics_frame
	await _save("stopped_side")
	Input.action_press("move_right")
	for frame in 6: await physics_frame
	await _save("turn_start")
	for frame in 18: await physics_frame
	await _save("turn_finished")
	Input.action_release("move_right")
	for frame in 35: await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for frame in 105:
		await physics_frame
		if frame in [1, 13, 29, 43, 57, 71, 84, 103]:
			await _save("jump_%03d" % frame)
	var manifest := {"scope": "Real Main and Player, original world light and CameraRig on_foot profile; source-only comparison is labelled", "graphics": DisplayServer.get_name(), "provider_scene":hero.model.scene_file_path,"provider_scene_sha256":FileAccess.get_sha256(hero.model.scene_file_path), "adapter_sha256": FileAccess.get_sha256("res://game/characters/imported_hero_visual.gd"), "library_sha256": FileAccess.get_sha256("res://assets/animations/quaternius/original_locomotion.res"), "records": records}
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
	main.queue_free()
	for frame in 3: await process_frame
	print("IP01_RUNTIME_POSE_CAPTURE ", output, " frames=",records.size())
	quit()

func _orbit(yaw: float) -> void:
	world.camera_rig.follow(world.player, &"on_foot")
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	for frame in 15: await physics_frame

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var pose := {"label":label,"player_position":_v(world.player.global_position),"camera_yaw":world.camera_rig.yaw,"speed":hero._speed,"phase":hero.get("_cycle_phase"),"grounded":world.player.is_on_floor(),"vertical_speed":world.player.velocity.y,"state":hero._playback.get_current_node() if hero.get("_playback") != null else "legacy","joints":{}}
	for bone: String in ["Hips","Spine","Chest","UpperChest","Neck","Head","LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot"]:
		var transform: Transform3D = hero.model.global_transform * hero.bone_transform(bone)
		pose.joints[bone] = {"position":_v(transform.origin),"up":_v(transform.basis.y.normalized()),"forward":_v(transform.basis.z.normalized())}
	var hips: Vector3 = hero.bone_transform("Hips").origin
	var neck: Vector3 = hero.bone_transform("Neck").origin
	var axis := (neck-hips).normalized()
	pose["torso_lean_degrees"] = rad_to_deg(acos(clampf(axis.dot(Vector3.UP),-1,1)))
	pose["head_tilt_degrees"] = rad_to_deg(acos(clampf(hero.bone_transform("Head").basis.y.normalized().dot(Vector3.UP),-1,1)))
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(label+".png")))
	assert(result==OK)
	records.append(pose)
	FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify(pose,"\t"))
	print("POSE ",label," torsoLean=",pose.torso_lean_degrees," headTilt=",pose.head_tilt_degrees)

func _v(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

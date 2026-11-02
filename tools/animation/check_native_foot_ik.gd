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
	hero.animation_player.play("Idle")
	hero.animation_player.advance(0.0)
	var skeleton := hero.skeleton
	var foot := skeleton.find_bone("LeftFoot")
	var before := skeleton.get_bone_global_pose(foot)
	var target := Node3D.new()
	target.name = "FootTarget"
	skeleton.add_child(target)
	target.position = before.origin + Vector3.UP * 0.10
	var ik := TwoBoneIK3D.new()
	ik.name = "NativeFootIK"
	skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "LeftUpperLeg")
	ik.set_middle_bone_name(0, "LeftLowerLeg")
	ik.set_end_bone_name(0, "LeftFoot")
	ik.set_use_virtual_end(0, false)
	ik.set_target_node(0, ik.get_path_to(target))
	var pole := Node3D.new()
	pole.name = "KneePole"
	skeleton.add_child(pole)
	pole.position = skeleton.get_bone_global_pose(skeleton.find_bone("LeftLowerLeg")).origin + Vector3(0, 0, 1.0)
	ik.set_pole_node(0, ik.get_path_to(pole))
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	await process_frame
	print("IK active=", ik.active, " skeleton=", ik.get_skeleton(), " root=", ik.get_root_bone(0), " mid=", ik.get_middle_bone(0), " end=", ik.get_end_bone(0), " target=", ik.get_target_node(0))
	for property: Dictionary in ik.get_property_list():
		if String(property.name).begins_with("settings/"):
			print(property.name, "=", ik.get(property.name))
	ik.modification_processed.connect(func(): print("DURING ", skeleton.get_bone_global_pose(foot).origin))
	skeleton.advance(0.016)
	await process_frame
	target.position.y += 0.1
	target.force_update_transform()
	skeleton.advance(0.016)
	await process_frame
	print("BEFORE ", before.origin, " GOAL ", target.position, " AFTER ", skeleton.get_bone_global_pose(foot).origin)
	hero.free()
	quit()

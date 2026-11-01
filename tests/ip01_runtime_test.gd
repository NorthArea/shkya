extends SceneTree
const Visual = preload("res://game/characters/character_sprite.gd")
const Uniform = preload("res://game/characters/uniform_visual.gd")
const Layout = preload("res://game/world/layout.gd")
const FOOT_GROUND_TOL := 0.08
var checks := 0
var errors: Array[String] = []
var observations: Array = []
var main: Node
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error("FAIL: " + message)
func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame
func idle_pose(skeleton: Skeleton3D) -> bool:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_pose_position(i).distance_to(skeleton.get_bone_rest(i).origin) > 0.00001:
			return false
		if skeleton.get_bone_pose_rotation(i).angle_to(Quaternion.IDENTITY) > 0.00001:
			return false
	return true
func alpha_height(kind: String, canvas_height: float) -> float:
	var texture: Texture2D = load("res://assets/art/characters/%s_front_idle.svg" % kind)
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return canvas_height * float(image.get_used_rect().size.y) / image.get_height()
func skinned_bounds(visual: Node, ground_y: float) -> Dictionary:
	var skeleton: Skeleton3D = visual.skeleton
	var mesh: MeshInstance3D = visual.uniform_mesh
	var minimum := INF
	var foot_minimum := INF
	var maximum := -INF
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex_index in vertices.size():
			var point := Vector3.ZERO
			var foot := false
			for influence in 4:
				var index := vertex_index * 4 + influence
				var weight: float = weights[index]
				if weight <= 0.0:
					continue
				var bind: int = bones[index]
				var bone: int = mesh.skin.get_bind_bone(bind)
				point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex_index]) * weight
				if String(skeleton.get_bone_name(bone)).begins_with("foot") and weight > 0.5:
					foot = true
			var y: float = (mesh.global_transform * point).y - ground_y
			minimum = minf(minimum, y)
			maximum = maxf(maximum, y)
			if foot:
				foot_minimum = minf(foot_minimum, y)
	return {"minimum": minimum, "feet_minimum": foot_minimum, "maximum": maximum}
func verify_gait(visual: Node, floor_y: float, label_: String) -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var hips := skeleton.find_bone("hips")
	var rest := skeleton.get_bone_rest(hips).origin
	var pose := skeleton.get_bone_pose_position(hips)
	check(pose.is_finite() and (pose - rest).length() <= 0.08, label_ + " retains bounded hips displacement relative to authored rest, including IK crouch")
	var bounds := skinned_bounds(visual, floor_y)
	check(bounds.feet_minimum >= -FOOT_GROUND_TOL, "%s skinned feet remain near ground, y=%.4f" % [label_, bounds.feet_minimum])
	check(bounds.maximum >= visual.visible_height * 0.9, "%s full model height survives walking, top=%.4f" % [label_, bounds.maximum])
	observations.append({"phase": label_, "hips_rest": str(rest), "hips_pose": str(pose), "bounds": bounds})
func check_rig(visual: Node, label_: String) -> void:
	var author: Skeleton3D = visual.author_skeleton
	var authored: MeshInstance3D = visual.author_mesh
	var active: Skeleton3D = visual.skeleton
	var mesh: MeshInstance3D = visual.uniform_mesh
	check(author.get_bone_count() == 14 and authored.skin.get_bind_count() == 14 and authored.get_node(authored.skeleton) == author, label_ + " retains the authored 14-bone rig and Skin")
	var walking_adapter := active != author
	var expected := 16 if walking_adapter else 14
	check(active.get_bone_count() == expected and mesh.skin != null and mesh.skin.get_bind_count() == expected and mesh.get_node(mesh.skeleton) == active, label_ + " live mesh binds to its actual 14-author/16-locomotion skeleton")
	check((walking_adapter and visual.rig != null and active == visual.rig.skeleton and mesh == visual.rig.mesh and not authored.visible and mesh.visible) or (not walking_adapter and mesh == authored and authored.visible), label_ + " exactly the selected author or locomotion mesh is active")
	var names_preserved := true
	for bone in 14:
		names_preserved = names_preserved and active.get_bone_name(bone) == author.get_bone_name(bone)
	if walking_adapter:
		for suffix in ["_l", "_r"]:
			names_preserved = names_preserved and (active.find_bone("knee" + suffix) >= 14 or active.find_bone("ankle" + suffix) >= 14)
	check(names_preserved, label_ + " preserves artist bone names and adds the two leg joints separately")
	var seen := {}
	var binds_valid := true
	for bind in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0 or bone >= active.get_bone_count() or seen.has(bone):
			binds_valid = false
			continue
		seen[bone] = true
		var identity := active.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind)
		binds_valid = binds_valid and identity.is_finite() and identity.origin.length() < 0.0001 and identity.basis.is_equal_approx(Basis.IDENTITY)
	check(binds_valid and seen.size() == active.get_bone_count(), label_ + " live Skin has unique valid inverse-rest binds")
	var materials_shared := mesh.mesh.get_surface_count() == authored.mesh.get_surface_count()
	for surface in mini(mesh.mesh.get_surface_count(), authored.mesh.get_surface_count()):
		materials_shared = materials_shared and mesh.mesh.surface_get_material(surface) == authored.mesh.surface_get_material(surface)
	check(materials_shared, label_ + " locomotion preserves authored material resources")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/IP-01/regression"))
	create_timer(80.0, true, false, true).timeout.connect(func(): quit(2))
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/IP-01/regression/runtime_profile_%d.json" % Time.get_ticks_usec()
	root.add_child(main)
	await frames(4)
	main.start_game()
	await frames(5)
	var world: Node = main.world
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	var guard: Node3D = patrols.officer2
	var officer_look: Node = officer.visual.get_node("Look")
	var guard_look: Node = guard.visual.get_node("Look")
	var sensor_count := get_nodes_in_group(&"detection_sensors").size()
	check(officer_look.uses_uniform_3d() and guard_look.uses_uniform_3d(), "actual two Patrols use 3D runtime visuals")
	if not officer_look.uses_uniform_3d() or not guard_look.uses_uniform_3d():
		await finish()
		return
	var officer_uniform: Node = officer_look.uniform_visual
	var guard_uniform: Node = guard_look.uniform_visual
	var identities := {}
	for actor: Node3D in [officer, guard]:
		var look: Node = actor.visual.get_node("Look")
		var visual: Node = look.uniform_visual
		identities[actor.name] = {"sensor": actor.sensor.get_instance_id(), "body": actor.get_node("Body").get_instance_id()}
		check(look.sprite == null and look.find_children("*", "Sprite3D", true, false).is_empty(), actor.name + " has no surviving billboard")
		check_rig(visual, actor.name)
		check(look.find_children("*", "Skeleton3D", true, false).size() == (2 if visual.skeleton != visual.author_skeleton else 1), actor.name + " has only its author rig and optional independent locomotion rig")
		check(look.find_children("*", "CollisionObject3D", true, false).is_empty(), actor.name + " visual adds no gameplay collision")
		var expected_height := alpha_height("police" if actor == officer else "guard", actor.height_m)
		check(absf(visual.visible_height - expected_height) <= 0.00001 and absf(visual.model.scale.y - expected_height) <= 0.00001, actor.name + " matches old SVG visible-alpha height, not gallery convention")
		var body_shape: CapsuleShape3D = actor.get_node("Body").find_children("*", "CollisionShape3D", true, false)[0].shape
		check(is_equal_approx(body_shape.radius, 0.6) and is_equal_approx(body_shape.height, 1.8), actor.name + " preserves original gameplay capsule")
		check(actor.sensor.range_m == 14.0 and actor.sensor.fov_deg == 100.0 and actor.sensor.car_area == Layout.KIOSK_SQUARE and actor.sensor.enabled, actor.name + " preserves original initial sensor parameters")
		check(actor.xray != null and actor.xray.mesh == visual.uniform_mesh.mesh and actor.xray.skin == visual.uniform_mesh.skin, actor.name + " xray uses actual shared 3D geometry and skin")
		check(actor.xray.get_parent() == visual.skeleton and actor.xray.get_node(actor.xray.skeleton) == visual.skeleton, actor.name + " xray binds under the same skeleton")
		check(idle_pose(visual.skeleton), actor.name + " initial pose equals authored rest")
		var rest_bounds := skinned_bounds(visual, actor.global_position.y)
		check(absf(rest_bounds.feet_minimum) <= 0.01 and rest_bounds.maximum >= expected_height * 0.98, actor.name + " real skinned rest feet/top match intended scale")
	check(officer.interaction_id == &"officer" and guard.interaction_id == &"officer2" and not guard.interactable.enabled, "original officer identities/guard no-dialog behavior remain")
	check(officer.global_position.distance_to(Layout.OFFICER_POST) < 0.00001 and guard.global_position.distance_to(Layout.OFFICER2_POST) < 0.00001, "original two post positions remain")
	# Same model resource, separate skeleton poses. No substitute animation on real officer.
	var spare_actor := Node3D.new()
	spare_actor.position = Vector3(1000.0, 0.0, 1000.0)
	world.add_child(spare_actor)
	var spare := Visual.new()
	spare.character = "police"
	spare.height_m = officer.height_m
	spare_actor.add_child(spare)
	await frames(3)
	spare.uniform_visual.update_locomotion(Vector3.ZERO, true, &"locomotion", 1.0 / 60.0)
	officer_uniform.update_locomotion(Vector3.ZERO, true, &"locomotion", 1.0 / 60.0)
	check(spare.uniform_visual.uniform_mesh.mesh == officer_uniform.uniform_mesh.mesh and spare.uniform_visual.uniform_mesh.skin == officer_uniform.uniform_mesh.skin and spare.uniform_visual.skeleton != officer_uniform.skeleton, "same-kind locomotion instances share mesh/Skin and keep separate live bones")
	var initial: Vector3 = officer.global_position
	var target := initial + Vector3(1.5, 0.0, 0.0)
	officer.move_post(target)
	check(not officer.sensor.enabled and officer.is_moving(), "real move_post disables original sensor while moving")
	await frames(15)
	check(officer.global_position.distance_to(initial) >= 0.30 and officer.global_position.distance_to(initial) <= 0.43, "real patrol keeps original 1.5m/s movement")
	check(not officer.sensor.enabled and not officer.xray.visible, "moving officer hides xray along with sensor")
	check(not idle_pose(officer_uniform.skeleton), "actual parent movement drives skinned gait")
	check_rig(officer_uniform, "officer real walking")
	check(officer.xray.mesh == officer_uniform.uniform_mesh.mesh and officer.xray.skin == officer_uniform.uniform_mesh.skin and officer.xray.get_parent() == officer_uniform.skeleton and officer.xray.get_node(officer.xray.skeleton) == officer_uniform.skeleton, "walking officer xray follows the current mesh/Skin and active skeleton")
	verify_gait(officer_uniform, officer.global_position.y, "officer real walking")
	check(idle_pose(spare.uniform_visual.skeleton) and idle_pose(guard_uniform.skeleton), "walking one instance leaves spare/guard bones at rest")
	await frames(70)
	check(not officer.is_moving() and officer.global_position.distance_to(target) < 0.00001 and officer.sensor.enabled, "arrival restores original sensor at exact post")
	await frames(4)
	check(idle_pose(officer_uniform.skeleton), "arrival resets all gait bones to authored rest")
	officer.place_at(initial + Vector3(10.0, 0.0, 0.0))
	await frames(2)
	check(idle_pose(officer_uniform.skeleton), "teleport does not manufacture walking frame")
	officer.place_at(initial)
	await frames(2)
	check(idle_pose(officer_uniform.skeleton), "teleport back stays at rest")
	# Guard's genuine timed turn rotates body/sensor while its stationary legs stay at rest.
	var began_turn := false
	for i in 900:
		await frames(1)
		if guard.is_turning():
			began_turn = true
			break
	check(began_turn, "actual guard enters original timed turn")
	var yaw_before: float = guard.body_yaw()
	await frames(20)
	check(absf(angle_difference(yaw_before, guard.body_yaw())) > 0.01 and absf(angle_difference(guard.sensor.rotation.y, guard.body_yaw())) < 0.00001, "guard body and original sensor turn together")
	check(idle_pose(guard_uniform.skeleton), "stationary guard turn does not fake leg walking")
	# Guard's public visual locomotion override also must preserve rest hip origin/feet.
	guard_look.set_walk_speed(1.5)
	await frames(15)
	verify_gait(guard_uniform, guard.global_position.y, "guard visual walk API")
	guard_look.set_walk_speed(0.0)
	await frames(2)
	check(idle_pose(guard_uniform.skeleton), "zero visual speed restores guard rest origin exactly")
	for spec in [["police", "police_long"], ["police", "police_round"], ["guard", "guard_alt"]]:
		var fallback := Visual.new()
		fallback.character = spec[0]
		fallback.appearance = spec[1]
		spare_actor.add_child(fallback)
		await frames(1)
		if Uniform.civilians_enabled():
			check(fallback.sprite == null and fallback.uses_uniform_3d() and fallback.resolved_character() == spec[1] and fallback.uniform_visual.model.get_meta("drawing", "") == spec[1], "converted approved variant retains its own model identity: " + spec[1])
		else:
			check(fallback.sprite != null and not fallback.uses_uniform_3d() and fallback.resolved_character() == spec[1], "unconverted approved variant retains its own SVG: " + spec[1])
	for actor: Node3D in [officer, guard]:
		check(actor.sensor.get_instance_id() == identities[actor.name].sensor and actor.get_node("Body").get_instance_id() == identities[actor.name].body, actor.name + " keeps same original sensor/body across visual lifecycle")
		check(actor.sensor.visibility() == 0.0 and actor.sensor.range_m == 14.0, actor.name + " visual tests do not change detection gameplay")
	check(get_nodes_in_group(&"detection_sensors").size() == sensor_count and world.mission.money == 0 and world.mission.state == &"NOT_STARTED", "model instances add no sensors, awards or mission state")
	await finish()
func finish() -> void:
	var out := FileAccess.open("res://builds/checks/IP-01/regression/runtime_result.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks": checks, "errors": errors, "observations": observations, "default_3d": Uniform.ENABLED_BY_DEFAULT, "adapter_sha256": FileAccess.get_sha256("res://game/characters/uniform_visual.gd"), "character_sha256": FileAccess.get_sha256("res://game/characters/character_sprite.gd"), "patrol_sha256": FileAccess.get_sha256("res://game/npc/patrol_npc.gd"), "scope": "actual Main two Patrols, alpha scale, live gait/turn/teleport, shared mesh and independent skeleton, original sensor/body identities; native xray rendering separate oracle"}, "\t"))
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	for child in root.get_children():
		if child != main:
			child.queue_free()
	await frames(4)
	OS.delay_msec(100)
	await process_frame
	print("IP01_INDEPENDENT_RUNTIME: %d checks, %d failures" % [checks, errors.size()])
	quit(0 if errors.is_empty() else 1)

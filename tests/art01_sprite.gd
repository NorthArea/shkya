extends SceneTree
## ART-01, облик персонажей на настоящем main.tscn: выбор ракурса по камере и кадры ходьбы
## при настоящей ходьбе через физику. Гонять при 60 и 120 к/с (`make test`): на 120 к/с
## кадры отрисовки идут чаще шага физики — ходьба не должна сбрасываться в стойку.

const Layout = preload("res://game/world/layout.gd")
const Uniform = preload("res://game/characters/uniform_visual.gd")

var failures: Array[String] = []
var checks := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("FAIL: art01 test exceeded 120 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _physics(2)
	main.start_game()
	await _physics(10)
	var world: DemoWorld = main.world
	var look: CharacterSprite = world.player.get_node("Visual/Look")
	var sensor_ids: Array[int] = []
	for sensor: Node in get_nodes_in_group(&"detection_sensors"):
		sensor_ids.append(sensor.get_instance_id())
	_check_identities_and_bodies(world, "before")
	if Uniform.civilians_enabled():
		await _check_3d(world, look)
	else:
		await _check_legacy(world, look)
	_check_identities_and_bodies(world, "after")
	var remaining_sensors: Array[int] = []
	for sensor: Node in get_nodes_in_group(&"detection_sensors"):
		remaining_sensors.append(sensor.get_instance_id())
	check(remaining_sensors == sensor_ids, "appearance/camera/walk lifecycle preserves the same original detection sensors")
	await _finish()

func _check_legacy(world: DemoWorld, look: CharacterSprite) -> void:
	check(look != null and look.sprite != null, "Ilyusha has a CharacterSprite look")
	# Ракурсы: Илюша смотрит на запад (yaw PI/2), камера обходит его.
	world.player.place(Layout.SPAWN, PI * 0.5)
	for case in [[PI * 0.5, &"back"], [-PI * 0.5, &"front"], [0.0, &"side"], [PI, &"side"]]:
		world.camera_rig.yaw = case[0]
		world.camera_rig.snap()
		await _render(3)
		check(look.view == case[1], "camera yaw %.2f shows %s (got %s)" % [case[0], case[1], look.view])
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await _render(3)
	var flip_a := look.sprite.flip_h
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await _render(3)
	check(look.sprite.flip_h != flip_a, "side view mirrors when the camera goes round to the other side")
	check(look.frame == -1 and look.sprite.texture == look._idle[look.view], "standing still shows the idle drawing")
	# Ходьба через физику: камера за спиной, «вперёд» — на запад.
	world.camera_rig.yaw = PI * 0.5
	world.camera_rig.snap()
	await _render(3)
	Input.action_press(&"move_forward")
	var seen := {}
	var idle_samples := 0
	for i in 90:
		await process_frame
		if i < 10:
			continue  # разгон
		seen[look.frame] = true
		if look.frame == -1:
			idle_samples += 1
	Input.action_release(&"move_forward")
	check(idle_samples == 0, "walking never drops to the idle drawing between physics steps (idle samples: %d)" % idle_samples)
	check(seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "walking cycles through all four frames (seen %s)" % [seen.keys()])
	check(look.sprite.texture in (look._walk[look.view] as Array), "walking shows a walk drawing")
	# Илюша тормозит ~0,4 с (Ilyusha.DECELERATION, PLAY-02) и всё это время перебирает ногами; после — стойка.
	await _physics(int(Engine.physics_ticks_per_second * 0.5))
	check(look.frame == -1, "stopping returns to the idle drawing")
	# Телепорт — не шаг.
	world.player.place(Layout.SPAWN + Vector3(5, 0, 0), PI * 0.5)
	await _physics(2)
	check(look.frame == -1, "teleport (place) does not start the walk cycle")
	# NPC.
	for npc in [world.babka, world.vendor]:
		var npc_look: CharacterSprite = npc.get_node("Visual/Look")
		check(npc_look != null and npc_look.sprite.texture != null, "%s has a CharacterSprite look" % npc.name)

func _rest_pose(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_pose_position(bone).distance_to(skeleton.get_bone_rest(bone).origin) > 0.00001:
			return false
		if skeleton.get_bone_pose_rotation(bone).angle_to(Quaternion.IDENTITY) > 0.00001:
			return false
	return true

func _check_identities_and_bodies(world: DemoWorld, phase: String) -> void:
	var player_look: CharacterSprite = world.player.get_node("Visual/Look")
	check(world.player.name == "Ilyusha" and player_look.character == "ilyusha" and player_look.appearance == "" and player_look.resolved_character() == "ilyusha", phase + ": player retains the original gameplay/drawing identity")
	var player_collider: CollisionShape3D = world.player.get_node("CollisionShape3D")
	var capsule := player_collider.shape as CapsuleShape3D
	check(capsule != null and is_equal_approx(capsule.radius, 0.35) and is_equal_approx(capsule.height, 1.5) and player_collider.position.is_equal_approx(Vector3(0, 0.75, 0)), phase + ": player retains its original capsule and offset")
	check(world.player.collision_layer == 2 and world.player.collision_mask == (1 | 4 | 32 | 64) and world.control_mode == &"on_foot", phase + ": player retains its gameplay collision layers and on-foot mode")
	for spec: Array in [[world.babka, "babka", 2.5], [world.vendor, "vendor", 2.0]]:
		var npc: Node = spec[0]
		var look: CharacterSprite = npc.get_node("Visual/Look")
		check(npc.character == spec[1] and String(npc.interaction_id) == spec[1] and look.character == spec[1] and look.appearance == "" and look.resolved_character() == spec[1], phase + ": " + npc.name + " retains role, interaction and appearance identity")
		check(npc.interactable.interaction_id == npc.interaction_id and npc.interactable.collision_layer == 8 and npc.interactable.collision_mask == 0 and is_equal_approx(npc.interactable.radius, spec[2]), phase + ": " + npc.name + " retains its original interaction area")
		check(look.find_children("*", "CollisionObject3D", true, false).is_empty(), phase + ": " + npc.name + " visual adds no gameplay collider")
	var babka_body: StaticBody3D = world.babka.get_node("Body")
	var babka_collider: CollisionShape3D = babka_body.get_child(0)
	var babka_capsule := babka_collider.shape as CapsuleShape3D
	check(world.babka.solid and babka_body.collision_layer == 1 and babka_body.collision_mask == 0 and babka_capsule != null and is_equal_approx(babka_capsule.radius, 0.7) and is_equal_approx(babka_capsule.height, 1.8) and babka_collider.position.is_equal_approx(Vector3(0, 0.9, 0)), phase + ": Babka retains the original solid capsule")
	check(not world.vendor.solid and world.vendor.get_node_or_null("Body") == null, phase + ": vendor retains the original non-solid body")

func _check_3d(world: DemoWorld, look: CharacterSprite) -> void:
	for actor: Node3D in [world.player, world.babka, world.vendor]:
		var actor_look: CharacterSprite = actor.get_node("Visual/Look")
		check(actor_look.uses_uniform_3d() and actor_look.sprite == null and actor_look._idle.is_empty() and actor_look._walk.is_empty(), actor.name + " uses a 3D visual without legacy sprite banks")
		var visual: Node = actor_look.uniform_visual
		var mesh: MeshInstance3D = visual.uniform_mesh
		var skeleton: Skeleton3D = visual.skeleton
		check(visual.model.get_meta("drawing", "") == actor_look.resolved_character() and visual.model.get_meta("forward_axis", "") == "-Z", actor.name + " real model matches its selected original drawing and forward axis")
		check(mesh.mesh is ArrayMesh and mesh.skin != null and mesh.skin.get_bind_count() == 14 and skeleton.get_bone_count() == 14 and mesh.get_node(mesh.skeleton) == skeleton, actor.name + " has real skinned geometry and its own live skeleton")
		check(mesh.mesh.get_aabb().size.x > 0.2 and mesh.mesh.get_aabb().size.z > 0.1, actor.name + " appearance has actual width and depth")
		check(_rest_pose(skeleton), actor.name + " stationary visual starts at authored rest")
	world.player.place(Layout.SPAWN, PI * 0.5)
	await _physics(2)
	var mesh: MeshInstance3D = look.uniform_visual.uniform_mesh
	var skeleton: Skeleton3D = look.uniform_visual.skeleton
	var original_basis := mesh.global_basis
	var original_view := look.view
	for sample: Array in [[PI * 0.5, &"back"], [-PI * 0.5, &"front"], [0.0, &"side"], [PI, &"side"]]:
		world.camera_rig.yaw = sample[0]
		world.camera_rig.snap()
		await _render(3)
		var forward: Vector3 = -look.uniform_visual.model.global_basis.z
		forward.y = 0.0
		var to_camera: Vector3 = world.camera_rig.camera.global_position - look.global_position
		to_camera.y = 0.0
		var facing := forward.normalized().dot(to_camera.normalized())
		var observed: StringName = &"front" if facing > look.FRONT_DOT else (&"back" if facing < -look.FRONT_DOT else &"side")
		check(observed == sample[1], "camera yaw %.2f physically observes the 3D %s face (dot %.3f)" % [sample[0], sample[1], facing])
		check(look.view == original_view and mesh.global_basis.is_equal_approx(original_basis) and look.uniform_visual.uniform_mesh == mesh and look.find_children("*", "Sprite3D", true, false).is_empty(), "camera orbit preserves the same 3D model/basis without billboard or view switching")
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await _render(3)
	var side_a := (world.camera_rig.camera.global_position - look.global_position).dot(look.global_basis.x)
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await _render(3)
	var side_b := (world.camera_rig.camera.global_position - look.global_position).dot(look.global_basis.x)
	check(side_a * side_b < 0.0 and mesh.global_basis.is_equal_approx(original_basis), "opposite side observations use the same fixed 3D model instead of mirroring a sprite")
	check(look.frame == -1 and _rest_pose(skeleton), "standing still shows the actual authored 3D rest pose")
	world.camera_rig.yaw = PI * 0.5
	world.camera_rig.snap()
	await _render(3)
	Input.action_press(&"move_forward")
	var seen := {}
	var idle_samples := 0
	var leg_moved := false
	var arm_moved := false
	var from := world.player.global_position
	for frame in 90:
		await process_frame
		if frame < 10:
			continue
		seen[look.frame] = true
		if look.frame == -1:
			idle_samples += 1
		leg_moved = leg_moved or skeleton.get_bone_pose_rotation(skeleton.find_bone("leg_l")).angle_to(Quaternion.IDENTITY) > 0.02
		arm_moved = arm_moved or skeleton.get_bone_pose_rotation(skeleton.find_bone("upper_arm_l")).angle_to(Quaternion.IDENTITY) > 0.01
	Input.action_release(&"move_forward")
	check(world.player.global_position.distance_to(from) > 0.5, "3D gait is driven by actual player movement through physics")
	check(idle_samples == 0, "3D walking never drops to idle between physics steps (idle samples: %d)" % idle_samples)
	check(seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "3D walking retains all four distance-based phases (seen %s)" % [seen.keys()])
	check(leg_moved and arm_moved, "3D walking animates actual leg and arm bones")
	for npc: Node3D in [world.babka, world.vendor]:
		var npc_look: CharacterSprite = npc.get_node("Visual/Look")
		check(_rest_pose(npc_look.uniform_visual.skeleton) and npc_look.uniform_visual.skeleton != skeleton, npc.name + " idle bones remain independent of the walking player")
	await _physics(int(Engine.physics_ticks_per_second * 0.5))
	check(look.frame == -1 and _rest_pose(skeleton), "stopping resets every 3D bone to authored rest")
	world.player.place(Layout.SPAWN + Vector3(5, 0, 0), PI * 0.5)
	await _physics(2)
	check(look.frame == -1 and _rest_pose(skeleton), "teleport restores 3D idle without manufacturing a walking pose")

func _physics(count: int) -> void:
	for i in count:
		await physics_frame

func _render(count: int) -> void:
	for i in count:
		await process_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("ART01: %d checks, %d failures" % [checks, failures.size()])
	Input.action_release(&"move_forward")
	if is_instance_valid(main):
		for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
			for audio: Node in main.find_children("*", kind, true, false):
				audio.stop()
		main.queue_free()
		main = null
	for i in 4:
		await physics_frame
		await process_frame
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)

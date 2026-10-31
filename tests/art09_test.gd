extends SceneTree
## ART-09: presentation-вариант на настоящем NPC, ракурсы и ходьба.
## Визуальная похожесть и различимость принимаются отдельно по игровым кадрам.

const SpriteScript = preload("res://game/characters/character_sprite.gd")
const Layout = preload("res://game/world/layout.gd")
const PatrolsScript = preload("res://game/world/patrols.gd")
const LifeScript = preload("res://game/world/life.gd")
const CIVILIANS := {56: ["resident_kolpak", &"babka"], 57: ["resident_ushanka_walk", &"man"], 58: ["resident_shuba", &"babka"], 59: ["resident_turban", &"babka"], 62: ["resident_bow", &"babka"], 63: ["resident_tourist", &"man"]}
const NpcScript = preload("res://game/npc/npc.gd")
const Uniform = preload("res://game/characters/uniform_visual.gd")
const SENSOR_PATHS: Array[String] = ["LevelGeometry/Patrols/Officer/DetectionSensor", "LevelGeometry/Patrols/Officer2/DetectionSensor", "LevelGeometry/Patrols/CityVan/DetectionSensor", "LevelGeometry/Patrols/RoadClosure/ClosureVan/DetectionSensor"]
const TYPES: Array[String] = ["police_long", "police_round", "guard_alt"]
var checks := 0
var failures := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 3: await physics_frame
	var world: DemoWorld = main.world
	var first_world_id := world.get_instance_id()
	var first_drawings := _live_world(world, "first world")
	var sensors_before := get_nodes_in_group(&"detection_sensors").size()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var npc := NpcScript.new()
	npc.name = "Art09Npc"
	npc.character = "police"
	npc.appearance = "police_long"
	npc.interaction_id = &"art09_presentation"
	npc.solid = false
	npc.position = world.player.position + Vector3(0, 0, -8)
	world.add_child(npc)
	var look: CharacterSprite = npc.get_node("Visual/Look")
	check(look.resolved_character() == "police_long", "NPC passes explicit drawing to CharacterSprite")
	check(npc.character == "police" and npc.interaction_id == &"art09_presentation", "drawing keeps NPC character and interaction identity")
	check(get_nodes_in_group(&"detection_sensors").size() == sensors_before, "appearance creates no observers")
	if Uniform.civilians_enabled():
		check(look.uses_uniform_3d() and look.sprite == null and look.uniform_visual.model.get_meta("drawing", "") == "police_long", "NPC displays the selected 3D drawing on the real consumer")
	else:
		check(look.sprite.texture.resource_path.ends_with("police_long_front_idle.svg"), "NPC displays the selected drawing")
	npc.queue_free()
	await process_frame
	for drawing in TYPES:
		var actor := Node3D.new()
		actor.position = world.player.position + Vector3(0, 0, -8)
		world.add_child(actor)
		var sprite: CharacterSprite = SpriteScript.new()
		sprite.character = "police"
		sprite.appearance = drawing
		actor.add_child(sprite)
		check(sprite.resolved_character() == drawing, drawing + " resolves independently from base character")
		var reference: CharacterSprite = null
		var initial_mesh: MeshInstance3D = null
		var initial_basis := Basis.IDENTITY
		var initial_view: StringName = sprite.view
		if Uniform.civilians_enabled():
			check(sprite.uses_uniform_3d() and sprite.sprite == null and sprite._idle.is_empty() and sprite._walk.is_empty(), drawing + " selects 3D before loading SVG banks")
			var visual: Node = sprite.uniform_visual
			var skeleton: Skeleton3D = visual.skeleton
			initial_mesh = visual.uniform_mesh
			initial_basis = initial_mesh.global_basis
			check(visual.model.get_meta("drawing", "") == drawing and visual.model.get_meta("forward_axis", "") == "-Z", drawing + " model preserves its selected drawing and authored facing")
			check(skeleton.get_bone_count() == 14 and initial_mesh.mesh is ArrayMesh and initial_mesh.skin != null and initial_mesh.skin.get_bind_count() == 14, drawing + " provides a real skinned 14-bone rig")
			check(initial_mesh.mesh.get_aabb().size.z > 0.1 and initial_mesh.mesh.get_aabb().size.x > 0.2, drawing + " has volume in depth and width")
			check(_rest_pose(skeleton), drawing + " begins at authored rest")
			check(sprite.find_children("*", "CollisionObject3D", true, false).is_empty() and get_nodes_in_group(&"detection_sensors").size() == sensors_before, drawing + " presentation adds no physics body or observer")
			reference = SpriteScript.new()
			reference.character = "police"
			reference.appearance = drawing
			reference.position = actor.position + Vector3(3, 0, 0)
			world.add_child(reference)
			check(reference.uniform_visual.skeleton != skeleton and reference.uniform_visual.uniform_mesh.mesh == initial_mesh.mesh, drawing + " shares mesh while keeping its own live bones")
		else:
			for view in [&"front", &"back", &"side"]:
				check(sprite._idle[view] != null and sprite._walk[view].size() == 4, "%s has %s idle and all four walk frames" % [drawing, view])
				for texture in sprite._walk[view]:
					check(texture.get_height() == sprite._idle[view].get_height() and texture.get_width() == sprite._idle[view].get_width(), "%s %s walk keeps canvas dimensions" % [drawing, view])
		for sample in [[Vector3(0, 1.5, -6), &"front", 1.0], [Vector3(0, 1.5, 6), &"back", -1.0], [Vector3(6, 1.5, 0), &"side", 0.0]]:
			camera.position = actor.position + sample[0]
			camera.look_at(actor.position + Vector3(0, 1, 0))
			await process_frame
			await process_frame
			if Uniform.civilians_enabled():
				var forward: Vector3 = -sprite.uniform_visual.model.global_basis.z
				forward.y = 0.0
				var to_camera := camera.global_position - sprite.global_position
				to_camera.y = 0.0
				check(absf(forward.normalized().dot(to_camera.normalized()) - float(sample[2])) < 0.001, "%s camera physically observes authored %s facing" % [drawing, sample[1]])
				check(sprite.view == initial_view and sprite.uniform_visual.uniform_mesh == initial_mesh and initial_mesh.global_basis.is_equal_approx(initial_basis) and sprite.find_children("*", "Sprite3D", true, false).is_empty(), "%s %s observation keeps the same fixed 3D rig without billboard/view switching" % [drawing, sample[1]])
			else:
				check(sprite.view == sample[1], "%s camera selects %s" % [drawing, sample[1]])
		var seen := {}
		var bent_leg := false
		for step in 24:
			actor.position.x += 0.08
			await physics_frame
			if sprite.frame >= 0: seen[sprite.frame] = true
			if Uniform.civilians_enabled():
				var skeleton: Skeleton3D = sprite.uniform_visual.skeleton
				bent_leg = bent_leg or skeleton.get_bone_pose_rotation(skeleton.find_bone("leg_l")).angle_to(Quaternion.IDENTITY) > 0.02
		check(seen.size() == 4, drawing + " walks through all four frames")
		if Uniform.civilians_enabled():
			check(bent_leg, drawing + " real parent movement animates a skinned leg")
			check(_rest_pose(reference.uniform_visual.skeleton), drawing + " walking does not mutate a stationary same-kind rig")
			for frame in 3: await physics_frame
			check(sprite.frame == -1 and _rest_pose(sprite.uniform_visual.skeleton), drawing + " arrival restores the authored rest pose")
			reference.queue_free()
		actor.queue_free()
		await process_frame
	var plain: CharacterSprite = SpriteScript.new()
	plain.character = "babka"
	check(plain.resolved_character() == "babka", "empty appearance preserves quest Babka")
	plain.character = "ilyusha"
	plain.appearance = "missing_variant"
	check(plain.resolved_character() == "ilyusha", "unknown appearance falls back to base character")
	plain.free()
	# Повторный запуск использует настоящую смену мира Main, без записи в static cycle.
	for audio in world.find_children("*", "AudioStreamPlayer", true, false) + world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.start_game()
	for i in 5: await physics_frame
	world = main.world
	check(world.get_instance_id() != first_world_id, "restart creates a new actual world")
	var second_drawings := _live_world(world, "second world")
	check(first_drawings == second_drawings, "new games retain the restored original police and guard drawings")
	check(first_drawings == ["police", "guard"], "normal games keep original drawings while new variants remain candidates")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false) + world.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.return_to_menu()
	for i in 5: await physics_frame
	check(main.world == null and main.menu.visible, "return to menu removes the second gameplay world")
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.start_game()
	for i in 5: await physics_frame
	var third_drawings := _live_world(main.world, "world after menu")
	check(third_drawings == first_drawings, "menu transitions retain the restored original drawings")
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	main.queue_free()
	main = null
	world = null
	look = null
	camera = null
	npc = null
	for i in 5:
		await physics_frame
		await process_frame
	OS.delay_msec(100)
	await process_frame
	print("ART09: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _rest_pose(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_pose_position(bone).distance_to(skeleton.get_bone_rest(bone).origin) > 0.00001:
			return false
		if skeleton.get_bone_pose_rotation(bone).angle_to(Quaternion.IDENTITY) > 0.00001:
			return false
	return true

func _live_world(world: DemoWorld, label: String) -> Array[String]:
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var people: Node = world.get_node("LevelGeometry/Residents")
	check(_sensor_paths(world) == _expected_sensor_paths(), label + ": sensor owners match the pre-ART gameplay composition")
	check(not patrols.closure.van.sensor.enabled, label + ": closure van keeps its pre-existing disabled sensor")
	check(people.residents.size() == 64, label + ": population remains 64")
	var drawing_ids: Array[String] = []
	var sensor_ids: Array[int] = []
	for spec in [[patrols.officer, "police", &"officer", Layout.OFFICER_POST, PatrolsScript.OFFICER_RANGE, Layout.OFFICER_FACING], [patrols.officer2, "guard", &"officer2", Layout.OFFICER2_POST, PatrolsScript.OFFICER2_RANGE, Layout.OFFICER2_FACING]]:
		var npc: Node3D = spec[0]
		var look: CharacterSprite = npc.get_node("Visual/Look")
		check(npc.character == spec[1] and npc.interaction_id == spec[2], label + ": post keeps semantic identity " + str(spec[2]))
		check(npc.position.is_equal_approx(spec[3]) and npc.facings == spec[5], label + ": post keeps position and facings " + str(spec[2]))
		check(is_equal_approx(npc.sensor.range_m, spec[4]) and npc.sensor.car_area == Layout.KIOSK_SQUARE, label + ": sensor keeps range and car area " + str(spec[2]))
		check(npc.get_node("Body").collision_layer == 1 and is_equal_approx(npc.body_radius, 0.6), label + ": post keeps physical body " + str(spec[2]))
		check(npc.appearance == "" and look.resolved_character() == npc.character and look.character == npc.character, label + ": real post retains its original drawing " + str(spec[2]))
		if look.uses_uniform_3d():
			check(look.sprite == null and look.uniform_visual != null, label + ": post uses an actual volume without billboard " + str(spec[2]))
			var model: Node3D = look.uniform_visual.model
			var skeleton: Skeleton3D = model.get_node("Skeleton3D")
			var mesh: MeshInstance3D = skeleton.get_node("UniformMesh")
			check(skeleton.get_bone_count() == 14 and mesh.mesh is ArrayMesh and mesh.skin != null and mesh.skin.get_bind_count() == 14, label + ": approved uniform has real skinned geometry " + str(spec[2]))
		else:
			check(look.sprite.texture.resource_path.contains("/" + npc.character + "_"), label + ": real post renders its original texture " + str(spec[2]))
		drawing_ids.append(look.resolved_character())
		sensor_ids.append(npc.sensor.get_instance_id())
	check(drawing_ids == ["police", "guard"], label + ": rejected candidate drawings are not used at the posts")
	check(not patrols.officer2.interactable.enabled and patrols.officer2.interactable.prompt == "", label + ": second post remains without dialogue")
	check(patrols.account_officer.character == "officer" and patrols.account_officer.appearance == "" and patrols.account_officer.interaction_id == &"account_officer", label + ": account officer remains unchanged")
	for npc in [world.player, world.babka, world.vendor]:
		var look: CharacterSprite = npc.get_node("Visual/Look")
		check(look.appearance == "" and look.resolved_character() == look.character, label + ": quest character retains its base drawing " + str(npc.name))
	for index in CIVILIANS:
		var resident: Resident = people.residents[index]
		var look: CharacterSprite = resident.get_node("Visual/Look")
		var expected: Array = CIVILIANS[index]
		check(resident.character == expected[0] and look.resolved_character() == expected[0], "%s: resident %d renders %s" % [label, index, expected[0]])
		check(resident.voice == expected[1], "%s: resident %d has its civilian voice" % [label, index])
		check(resident.home == LifeScript.PERSONAS[index]["home"] and resident.plan == LifeScript.PERSONAS[index]["plan"], "%s: resident %d retains home and errands" % [label, index])
		check(resident.errand and resident.rider and resident.carry == &"" and resident.find_children("*", "DetectionSensor", true, false).is_empty(), "%s: resident %d remains an ordinary civilian" % [label, index])
	# Пройденный переход и штатный reset не меняют выбранный комплект или владельца сенсора.
	patrols._on_bread_received()
	check(patrols.officer.is_moving() and not patrols.officer.sensor.enabled, label + ": moving post keeps its existing sensor rule")
	patrols.reset_positions()
	people.reset_positions()
	check(patrols.officer.position.is_equal_approx(Layout.OFFICER_POST) and patrols.officer2.position.is_equal_approx(Layout.OFFICER2_POST), label + ": reset restores original posts")
	check(patrols.officer.sensor.enabled and patrols.officer2.sensor.enabled and is_equal_approx(patrols.officer.sensor.range_m, PatrolsScript.OFFICER_RANGE), label + ": reset restores sensor state")
	check(patrols.officer.sensor.get_instance_id() == sensor_ids[0] and patrols.officer2.sensor.get_instance_id() == sensor_ids[1], label + ": reset reuses both sensors")
	check(patrols.officer.get_node("Visual/Look").resolved_character() == drawing_ids[0] and patrols.officer2.get_node("Visual/Look").resolved_character() == drawing_ids[1], label + ": reset preserves both appearances")
	for index in CIVILIANS:
		var resident: Resident = people.residents[index]
		check(resident.get_node("Visual/Look").resolved_character() == CIVILIANS[index][0] and resident.voice == CIVILIANS[index][1], "%s: reset preserves civilian %d drawing and voice" % [label, index])
	check(_sensor_paths(world) == _expected_sensor_paths() and people.residents.size() == 64, label + ": reset preserves the exact sensor owners and population")
	return drawing_ids


func _expected_sensor_paths() -> Array[String]:
	var paths: Array[String] = SENSOR_PATHS.duplicate()
	paths.sort()
	return paths

func _sensor_paths(world: DemoWorld) -> Array[String]:
	var paths: Array[String] = []
	for sensor in get_nodes_in_group(&"detection_sensors"):
		paths.append(String(world.get_path_to(sensor)))
	paths.sort()
	print("ART09 SENSOR OWNERS: ", paths)
	return paths


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

extends SceneTree
## ART-09: presentation-вариант на настоящем NPC, ракурсы и ходьба.
## Визуальная похожесть и различимость принимаются отдельно по игровым кадрам.

const SpriteScript = preload("res://game/characters/character_sprite.gd")
const Layout = preload("res://game/world/layout.gd")
const PatrolsScript = preload("res://game/world/patrols.gd")
const LifeScript = preload("res://game/world/life.gd")
const CIVILIANS := {56: ["resident_kolpak", &"babka"], 57: ["resident_ushanka_walk", &"man"], 58: ["resident_shuba", &"babka"], 59: ["resident_turban", &"babka"], 62: ["resident_bow", &"babka"], 63: ["resident_tourist", &"man"]}
const NpcScript = preload("res://game/npc/npc.gd")
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
		for view in [&"front", &"back", &"side"]:
			check(sprite._idle[view] != null and sprite._walk[view].size() == 4, "%s has %s idle and all four walk frames" % [drawing, view])
			for texture in sprite._walk[view]:
				check(texture.get_height() == sprite._idle[view].get_height() and texture.get_width() == sprite._idle[view].get_width(), "%s %s walk keeps canvas dimensions" % [drawing, view])
		for sample in [[Vector3(0, 1.5, -6), &"front"], [Vector3(0, 1.5, 6), &"back"], [Vector3(6, 1.5, 0), &"side"]]:
			camera.position = actor.position + sample[0]
			camera.look_at(actor.position + Vector3(0, 1, 0))
			await process_frame
			await process_frame
			check(sprite.view == sample[1], "%s camera selects %s" % [drawing, sample[1]])
		var seen := {}
		for step in 24:
			actor.position.x += 0.08
			await physics_frame
			if sprite.frame >= 0: seen[sprite.frame] = true
		check(seen.size() == 4, drawing + " walks through all four frames")
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
	for i in 5: await physics_frame
	OS.delay_msec(100)
	await process_frame
	print("ART09: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

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

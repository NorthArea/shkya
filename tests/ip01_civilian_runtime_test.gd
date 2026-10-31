extends SceneTree
## Developer regression of City N 3D visuals in the real Main composition.
## Run headless with --fixed-fps 60 --script tests/ip01_civilian_runtime_test.gd -- --civilian3d
const Visual = preload("res://game/characters/character_sprite.gd")
const Uniform = preload("res://game/characters/uniform_visual.gd")
const Models = preload("res://game/characters/models/civilian_model.gd")
const Driver = preload("res://game/vehicles/lada_driver.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
const Dialog = preload("res://game/ui/dialog_panel.gd")
const Layout = preload("res://game/world/layout.gd")
var checks := 0
var errors: Array[String] = []
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error("FAIL: " + message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func rest(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_pose_position(bone).distance_to(skeleton.get_bone_rest(bone).origin) > 0.00001:
			return false
		if skeleton.get_bone_pose_rotation(bone).angle_to(Quaternion.IDENTITY) > 0.00001:
			return false
	return true

func bounds(visual: Node, relative_to: Node3D) -> AABB:
	var skeleton: Skeleton3D = visual.skeleton
	var instance: MeshInstance3D = visual.uniform_mesh
	var minimum := Vector3.INF
	var maximum := -Vector3.INF
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			var point := Vector3.ZERO
			for influence in 4:
				var slot := vertex * 4 + influence
				if weights[slot] > 0.0:
					var bind := bones[slot]
					var bone := instance.skin.get_bind_bone(bind)
					point += (skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind) * vertices[vertex]) * weights[slot]
			point = relative_to.to_local(instance.global_transform * point)
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)

func palm_in_parent(occupant: Node3D, suffix: String) -> Vector3:
	var visual: Node = occupant.uniform_visual
	var skeleton: Skeleton3D = visual.skeleton
	var hand := skeleton.find_bone("hand" + suffix)
	var point := skeleton.get_bone_global_pose(hand) * Vector3(0, -0.034, -0.008)
	return (occupant.get_parent() as Node3D).to_local(visual.model.to_global(point))

func hand_surface_to_wheel(occupant: Node3D, suffix: String) -> float:
	var visual: Node = occupant.uniform_visual
	var skeleton: Skeleton3D = visual.skeleton
	var instance: MeshInstance3D = visual.uniform_mesh
	var frame_3d := occupant.get_parent() as Node3D
	var wheel := Vector3(-0.36, 1.12, -0.53)
	var rim := PackedVector3Array()
	for index in 12:
		var angle := TAU * index / 12.0
		rim.append(wheel + (Vector3.RIGHT * cos(angle) + Vector3(0, 0.87, -0.5) * sin(angle)) * 0.18)
	var nearest := INF
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var hand_vertex := false
			for influence in 4:
				var slot := vertex * 4 + influence
				if weights[slot] <= 0.0:
					continue
				var bind := bones[slot]
				var bone := instance.skin.get_bind_bone(bind)
				point += (skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind) * vertices[vertex]) * weights[slot]
				hand_vertex = hand_vertex or (String(skeleton.get_bone_name(bone)) == "hand" + suffix and weights[slot] > 0.5)
			if not hand_vertex:
				continue
			point = frame_3d.to_local(instance.global_transform * point)
			for index in rim.size():
				nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, rim[index], rim[(index + 1) % rim.size()])))
	return nearest

func trolley_sill_lid_triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for index in range(0, vertices.size(), 3):
			var a := vertices[index]
			var b := vertices[index + 1]
			var c := vertices[index + 2]
			var centre := (a + b + c) / 3.0
			if absf(centre.x) < 1.0 and absf(centre.z) < 5.4 and absf(a.y - 1.72) < 0.0001 and absf(b.y - 1.72) < 0.0001 and absf(c.y - 1.72) < 0.0001 and (b - a).cross(c - a).length() > 0.001:
				count += 1
	return count

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(2))
	check(Uniform.civilians_enabled(), "the civilian 3D visual path is enabled")
	if not Uniform.civilians_enabled():
		quit(2)
		return
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/IP-01/civilian_profile_%d.json" % Time.get_ticks_usec()
	root.add_child(main)
	await frames(3)
	main.start_game()
	await frames(5)
	var world: Node = main.world
	var residents: Node = world.get_node("LevelGeometry/Residents")
	check(residents.residents.size() == 64 and Layout.RESIDENT_ROUTES.size() == 64 and Layout.RESIDENT_LOOKS.size() == 64, "actual Main preserves the owner's 64 residents and both canonical lists")
	for actor: Node in [world.player, world.babka, world.vendor] + residents.residents:
		var look: Node = actor.visual.get_node("Look") if actor.get("visual") != null else actor.get_node("Visual/Look")
		check(look.uses_uniform_3d() and look.sprite == null, actor.name + " actual consumer uses a skinned 3D look")
		if not look.uses_uniform_3d():
			continue
		check(look.uniform_visual.skeleton.get_bone_count() == 14, actor.name + " has its own live 14-bone skeleton")
		check(look.find_children("*", "CollisionObject3D", true, false).is_empty(), actor.name + " appearance adds no physics")
	# Factory consumers such as portrait capture have no CharacterSprite physics tick.
	for drawing: String in ["police", "guard"]:
		var fresh := Uniform.new()
		fresh.configure(drawing, 1.0, Color.WHITE)
		check(rest(fresh.skeleton), drawing + " factory immediately supplies authored rest without a consumer tick")
		fresh.free()
	var sandbox := Node3D.new()
	sandbox.position = Vector3(1000, 0, 1000)
	world.add_child(sandbox)
	for drawing: String in Models.DRAWINGS:
		var look := Visual.new()
		look.character = drawing
		look.height_m = 2.0
		sandbox.add_child(look)
		var spare := Visual.new()
		spare.character = drawing
		spare.height_m = 2.0
		sandbox.add_child(spare)
		var live: Node = look.uniform_visual
		check(live != null and look._idle.is_empty() and look._walk.is_empty(), drawing + " selects 3D before loading legacy SVGs")
		if live == null:
			continue
		check(rest(live.skeleton) and rest(spare.uniform_visual.skeleton), drawing + " fresh and cached instances start at authored rest")
		check(live.uniform_mesh.mesh == spare.uniform_visual.uniform_mesh.mesh and live.skeleton != spare.uniform_visual.skeleton, drawing + " shares immutable mesh, not live bone poses")
		var expected := 2.0 * Catalog.visible_height_ratio(drawing)
		var legacy_texture: Texture2D = load("res://assets/art/characters/%s_front_idle.svg" % drawing)
		var legacy_image := legacy_texture.get_image()
		if legacy_image.is_compressed():
			legacy_image.decompress()
		check(absf(expected - 2.0 * float(legacy_image.get_used_rect().size.y) / legacy_image.get_height()) < 0.00001, drawing + " code catalog preserves independently measured previous visible size")
		var box := bounds(live, sandbox)
		check(absf(box.position.y) < 0.015 and absf(box.end.y - expected) < 0.02, drawing + " rest has soles at ground and preserved visible height")
		for phase: float in [0.25, 0.75]:
			live.update_walk(look.walk_stride * 4.0 * phase, true, 1.0 / 60.0, look.walk_stride)
			live.skeleton.force_update_all_bone_transforms()
			box = bounds(live, sandbox)
			check(box.position.y >= -0.08 and box.end.y >= expected * 0.9, drawing + " true skinned gait keeps feet/height")
		check(rest(spare.uniform_visual.skeleton), drawing + " gait does not mutate cached sibling")
		live.set_walk_speed(0.0)
		check(rest(live.skeleton), drawing + " stop resets every authored rest transform")
		look.free()
		spare.free()
	var car: Node = world.car
	var driver: Node = car.visual.get_node("Body/Driver")
	check(driver.uses_uniform_3d() and driver.sprite == null, "actual Lada driver does not dereference an absent sprite")
	if driver.uses_uniform_3d():
		var box := bounds(driver.uniform_visual, driver.get_parent())
		check(box.end.y <= 1.355 and box.end.y >= 1.20, "actual seated Lada head has at least 3cm roof clearance with adult proportions")
		check(box.position.y >= 0.04, "actual seated Lada geometry stays above the car floor")
		check(not rest(driver.uniform_visual.skeleton), "actual Lada driver uses a seated arm/leg pose")
		for suffix: String in ["_l", "_r"]:
			var palm := palm_in_parent(driver, suffix)
			var wheel := Vector3(-0.36, 1.12, -0.53)
			check(palm.distance_to(wheel) > 0.09 and palm.distance_to(wheel) < 0.23 and absf(palm.z - wheel.z) < 0.10, "actual Lada " + suffix + " hand reaches its original steering wheel")
			var surface_gap := hand_surface_to_wheel(driver, suffix)
			check(surface_gap <= 0.04, "actual Lada " + suffix + " skinned hand surface touches the original wheel rim, gap=%.4f" % surface_gap)
	var trolley: Node = world.get_node("LevelGeometry/Traffic").trolleybus
	var people: Node = trolley.people
	var body_mesh: MeshInstance3D = people.get_parent().get_node("BodyMesh")
	check(trolley_sill_lid_triangles(body_mesh.mesh) == 0, "actual 3D trolley lower hull has no full-width opaque lid at window-sill height")
	check(people.shown().size() >= 3, "actual Main has trolley passengers")
	for occupant: Node in people.shown() + [people.driver]:
		check(occupant.uses_uniform_3d() and occupant.sprite == null, occupant.name + " actual trolley consumer is 3D")
		if not occupant.uses_uniform_3d():
			continue
		var box := bounds(occupant.uniform_visual, occupant.get_parent())
		check(box.end.y > 2.07 and box.end.y < 2.87, occupant.name + " head stays inside the trolley window band")
		check(absf(box.position.y - 0.80) < 0.015, occupant.name + " actual 3D soles stand on the lowered physical cabin floor")
		check(occupant.uniform_visual.uniform_mesh.visibility_range_end == 60.0 and occupant.get_node_or_null("Shadow") == null, occupant.name + " actual trolley geometry respects LOD and no foot shadow")
	var standing: Node = Driver.new()
	standing.character = "resident_kid"
	standing.height_m = 2.0
	standing.occupant_profile = &"trolley_standing"
	sandbox.add_child(standing)
	standing.set_lod(60.0)
	check(standing.uniform_visual.uniform_mesh.visibility_range_end == 60.0, "3D trolley LOD targets live geometry")
	check(standing.uniform_visual.skeleton.get_bone_pose_rotation(standing.uniform_visual.skeleton.find_bone("leg_l")).is_equal_approx(Quaternion.IDENTITY), "standing trolley consumer does not inherit Lada seated legs")
	var player_look: Node = world.player.visual.get_node("Look")
	for mode: StringName in [&"box", &"snowdrift", &"barrel"]:
		world.player.force_hide_mode(mode)
		check(not player_look.visible and world.player.hide_mode == mode, "actual hide mode suppresses the full 3D player: " + String(mode))
	world.player.force_hide_mode(&"none")
	check(player_look.visible, "leaving hiding restores the same 3D player")
	world.enter_car()
	await frames(2)
	check(driver.visible and not world.player.visible, "real car entry shows matching seated appearance and hides on-foot actor")
	world.exit_car()
	await frames(3)
	check(not driver.visible and world.player.visible, "real car exit restores on-foot actor")
	var resident: Node = residents.residents[0]
	var look: Node = resident.visual.get_node("Look")
	car.velocity = Vector3(5.0, 0.0, 0.0)
	resident.knock()
	await frames(3)
	check(resident.state == &"knocked" and look.sprite == null, "real resident knock enters the existing 3D roll path")
	check(rest(look.uniform_visual.skeleton), "knock freezes 3D gait at rest")
	residents.reset_positions()
	await frames(2)
	check(resident.state != &"knocked" and resident.knock_roll == 0.0, "reset restores resident state and visual roll")
	check(look.get_node("Shadow").visible, "reset restores 3D foot shadow")
	var dialog: Node = world.quest_flow.dialog
	for kind: StringName in [&"babka", &"vendor", &"ilyusha", &"officer", &"account_officer"]:
		var source := Dialog.portrait_source_path(kind)
		check(source == "res://assets/art/portraits3d/%s.png" % kind, String(kind) + " actual dialog consumer chooses same-model 3D portrait path")
		if ResourceLoader.exists(source):
			var texture: Texture2D = load(source)
			check(texture.get_size() == Vector2(512, 512), String(kind) + " native portrait has expected resolution")
		dialog.open("QA", "QA", [], kind)
		await frames(1)
		check(dialog.is_open() and dialog._portrait_kind == kind, String(kind) + " actual panel opens with 3D portrait or explicit neutral placeholder")
		dialog.close()
	# Match the qualified Main-test teardown: queued UI children and audio commands
	# must drain before SceneTree shutdown, including the final dialog voice.
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", kind, true, false):
			audio.stop()
	main.queue_free()
	main = null
	await frames(4)
	OS.delay_msec(100)
	await process_frame
	print("IP01_CIVILIAN_RUNTIME: ", checks, " checks, ", errors.size(), " failures; native art/FPS acceptance separate")
	quit(0 if errors.is_empty() else 1)

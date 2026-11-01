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
const NORMAL_REPACK_BUDGET := 0.0002
var normal_witness_checked := false

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

# A normal is accepted only when it is the exact independent engine identity
# roundtrip AND remains within the measured octahedral-repack error budget.
# The control mesh receives source arrays, never adapter-produced normal data.
func normals_preserved(source: PackedVector3Array, active: PackedVector3Array, control: PackedVector3Array) -> bool:
	return active == control and normal_budget(source, active)

func normal_budget(source: PackedVector3Array, active: PackedVector3Array) -> bool:
	if source.size() != active.size(): return false
	for index in source.size():
		var before := source[index]
		var after := active[index]
		if not before.is_finite() or not after.is_finite(): return false
		if absf(before.length() - 1.0) > NORMAL_REPACK_BUDGET or absf(after.length() - 1.0) > NORMAL_REPACK_BUDGET: return false
		if before.dot(after) <= 0.0 or before.distance_to(after) > NORMAL_REPACK_BUDGET: return false
	return true

func check_normal_witness(source: PackedVector3Array, control: PackedVector3Array) -> void:
	if normal_witness_checked or control.is_empty(): return
	normal_witness_checked = true
	var changed := control.duplicate()
	var tangent := control[0].cross(Vector3.RIGHT)
	if tangent.length_squared() < 0.01: tangent = control[0].cross(Vector3.UP)
	changed[0] = (control[0] + tangent.normalized() * 0.00004).normalized()
	check(changed != control and normal_budget(source, changed), "normal witness reaches exact-control boundary while staying finite/unit/within 2e-4")
	check(not normals_preserved(source, changed, control), "normal oracle rejects a changed direction even inside the repack tolerance")

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
		check_rig(look.uniform_visual, actor.name)
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
		check(live.author_mesh.mesh == spare.uniform_visual.author_mesh.mesh and live.author_mesh.skin == spare.uniform_visual.author_mesh.skin and live.author_skeleton != spare.uniform_visual.author_skeleton, drawing + " shares immutable artist mesh/Skin, not author poses")
		var authored_mesh: Mesh = live.author_mesh.mesh
		var authored_skin: Skin = live.author_mesh.skin
		var author_arrays: Array[Array] = []
		var identity_control := ArrayMesh.new()
		for surface in authored_mesh.get_surface_count():
			var snapshot := authored_mesh.surface_get_arrays(surface).duplicate(true)
			author_arrays.append(snapshot)
			identity_control.add_surface_from_arrays(authored_mesh.surface_get_primitive_type(surface), snapshot)
		var expected := 2.0 * Catalog.visible_height_ratio(drawing)
		var legacy_texture: Texture2D = load("res://assets/art/characters/%s_front_idle.svg" % drawing)
		var legacy_image := legacy_texture.get_image()
		if legacy_image.is_compressed():
			legacy_image.decompress()
		check(absf(expected - 2.0 * float(legacy_image.get_used_rect().size.y) / legacy_image.get_height()) < 0.00001, drawing + " code catalog preserves independently measured previous visible size")
		var box := bounds(live, sandbox)
		check(absf(box.position.y) < 0.015 and absf(box.end.y - expected) < 0.02, drawing + " rest has soles at ground and preserved visible height")
		# Contact-based gait needs elapsed time and matching actor displacement;
		# two unrelated distance snapshots imply an artificial near-teleport speed.
		var velocity := Vector3.FORWARD * 1.5
		for step in 60:
			look.position += velocity / 60.0
			live.update_locomotion(velocity, true, &"locomotion", 1.0 / 60.0)
			live.skeleton.force_update_all_bone_transforms()
			if step in [15, 45]:
				box = bounds(live, sandbox)
				check(box.position.y >= -0.08 and box.end.y >= expected * 0.9, drawing + " true skinned gait keeps feet/height")
		check_rig(live, drawing + " walking")
		spare.uniform_visual.update_locomotion(Vector3.ZERO, true, &"locomotion", 1.0 / 60.0)
		check(live.uniform_mesh.mesh == spare.uniform_visual.uniform_mesh.mesh and live.uniform_mesh.skin == spare.uniform_visual.uniform_mesh.skin and live.skeleton != spare.uniform_visual.skeleton, drawing + " locomotion shares immutable mesh/Skin with independent poses")
		check(live.author_mesh.mesh == authored_mesh and live.author_mesh.skin == authored_skin, drawing + " locomotion leaves original author resources intact")
		var shape_preserved: bool = live.uniform_mesh.mesh.get_surface_count() == authored_mesh.get_surface_count()
		var source_immutable: bool = authored_mesh.get_surface_count() == author_arrays.size()
		var normal_preserved := true
		var normal_max_delta := 0.0
		for surface in mini(live.uniform_mesh.mesh.get_surface_count(), mini(authored_mesh.get_surface_count(), author_arrays.size())):
			var original: Array = author_arrays[surface]
			var active: Array = live.uniform_mesh.mesh.surface_get_arrays(surface)
			var control := identity_control.surface_get_arrays(surface)
			source_immutable = source_immutable and original == authored_mesh.surface_get_arrays(surface)
			for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
				shape_preserved = shape_preserved and original[attribute] == active[attribute]
			var before: PackedVector3Array = original[Mesh.ARRAY_NORMAL]
			var after: PackedVector3Array = active[Mesh.ARRAY_NORMAL]
			var canonical: PackedVector3Array = control[Mesh.ARRAY_NORMAL]
			normal_preserved = normal_preserved and normals_preserved(before, after, canonical)
			for index in mini(before.size(), after.size()): normal_max_delta = maxf(normal_max_delta, before[index].distance_to(after[index]))
			check_normal_witness(before, canonical)
		check(shape_preserved, drawing + " locomotion preserves every author vertex, colour and topology array exactly")
		check(source_immutable, drawing + " original author arrays remain exactly unchanged after locomotion adaptation")
		check(normal_preserved, drawing + " normals exactly match independent Godot identity roundtrip within finite/unit/hemisphere 2e-4 budget")
		print("IP01_CIVILIAN_NORMAL_REPACK: %s max_source_delta=%.9f budget=%.9f exact_engine_control=%s" % [drawing, normal_max_delta, NORMAL_REPACK_BUDGET, normal_preserved])
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
		check(box.position.y >= 0.31, "actual seated Lada geometry stays above its exterior underbody")
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
		var drawing: String = {&"officer": "police", &"account_officer": "officer"}.get(kind, String(kind))
		check(source == "res://assets/art/characters/%s_front_idle.svg" % drawing, String(kind) + " dialog retains the approved drawing while revised GPU portraits are pending")
		if ResourceLoader.exists(source):
			var texture: Texture2D = load(source)
			check(texture.get_width() >= 400 and texture.get_height() >= 600, String(kind) + " approved portrait source has full drawing resolution")
		dialog.open("QA", "QA", [], kind)
		await frames(1)
		check(dialog.is_open() and dialog._portrait_kind == kind, String(kind) + " actual panel opens with the approved face")
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

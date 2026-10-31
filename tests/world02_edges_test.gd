extends SceneTree
## WORLD-02 developer checks: real perimeter colliders, shared lens material and parked body adapter.
const Layout = preload("res://game/world/layout.gd")
const Skyline = preload("res://game/world/skyline.gd")
const Impact = preload("res://game/vehicles/vehicle_impact.gd")
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
const LadaVisual = preload("res://game/vehicles/lada_visual.gd")
var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var bk: Breakables

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	bk = world.get_node("LevelGeometry/Breakables")
	world.player.set_physics_process(false)
	world.car.set_physics_process(false)
	world.player.position = Vector3(2000, 0, 2000)
	world.car.position = Vector3(2010, 0, 2000)
	for resident in world.get_node("LevelGeometry/Residents").residents:
		resident.set_physics_process(false)
	for sensor in get_nodes_in_group(&"detection_sensors"): sensor.enabled = false
	_perimeter()
	_signs()
	await _parked()
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	await _frames(5)
	preload("res://game/world/materials.gd").clear_cache()
	preload("res://game/world/environment_dress.gd").clear_cache()
	preload("res://game/vehicles/vehicle_mesh.gd").cache().clear()
	main = null
	world = null
	bk = null
	# AudioServer releases stopped playback on its real mixer clock.
	OS.delay_msec(100)
	await process_frame
	print("WORLD02: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error("WORLD02: " + failure)
	quit(0 if failures.is_empty() else 1)

func _perimeter() -> void:
	var b := Layout.BOUNDS
	var size := Vector3(1.8, 1.5, 4.2)
	var probe := CharacterBody3D.new()
	probe.collision_layer = 4
	probe.collision_mask = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position.y = size.y * 0.5
	probe.add_child(collider)
	world.add_child(probe)
	# New exterior runs are canonical walls next to the bounds, before the insurance wall.
	var witnesses := 0
	for wall: Array in Layout.PERIMETER_WALLS:
		var a: Vector2 = wall[0]
		var c: Vector2 = wall[1]
		var horizontal := is_equal_approx(a.y, c.y)
		if (horizontal and (a.y < b.position.y + 2 or a.y > b.end.y - 2)) or (not horizontal and a.x > b.end.x - 2 and a.y > 50):
			var p := a.lerp(c, 0.5)
			# A1 is the west part of the northern wall; G5/D5 cover both ends of the southern run.
			var samples := [p]
			if horizontal: samples = [a.lerp(c, 0.1), a.lerp(c, 0.9)]
			for at: Vector2 in samples:
				var out := Vector3(0, 0, signf(at.y)) if horizontal else Vector3(signf(at.x), 0, 0)
				probe.global_position = Vector3(at.x, 0.05, at.y) - out * 5.0
				var hit := KinematicCollision3D.new()
				var blocked := probe.test_move(probe.global_transform, out * 9.0, hit)
				check(blocked, "a full car sweep meets visible perimeter before leaving the arena")
				if blocked:
					var body := hit.get_collider() as Node3D
					check(body != null and not body.name.begins_with("Bound_"), "the visible wall, not insurance bounds, blocks the approach")
				witnesses += 1
	check(witnesses >= 5, "north and both southeast courtyard edges have tested full-body witnesses")
	check(Skyline.STREETS_OUT.all(func(st): return (st[1] as Vector2).y >= 0), "there is no disconnected northern road beyond Bogatkova's actual turn into Vybornaya")
	probe.queue_free()

func _signs() -> void:
	for warning in Layout.PERIMETER_WARNINGS:
		var at: Vector2 = warning[0]
		var board := AABB(Vector3(at.x - 0.06, 2.225, at.y - 2.25), Vector3(0.12, 1.35, 4.5))
		var clear := true
		for solid: Array in Layout.all_solids():
			if solid[1] not in ["panel", "panel_low", "garage", "kiosk"]:
				continue
			var centre: Vector2 = solid[2]
			var size: Vector3 = solid[3]
			var obstacle := AABB(Vector3(centre.x - size.x / 2, 0, centre.y - size.z / 2), size)
			clear = clear and not board.intersects(obstacle)
		check(clear, "full warning board clears actual building envelopes")
	for warning in Layout.PERIMETER_WARNINGS:
		for street in Layout.STREET_SIGNS:
			check((warning[0] as Vector2).distance_to(street[0]) > 4.0, "warning board and street-name arms occupy separate physical locations")

func _parked() -> void:
	var parked: Breakables.Breakable = null
	for b: Breakables.Breakable in bk.env_objects:
		if b.kind == &"parked" and b.id == &"Zhiguli_A": parked = b
	if not check(parked != null, "actual roadside parked car is registered"): return
	check(parked.body.has_meta(Impact.META), "parked physical body participates in the shared impulse solver")
	var visual := parked.parked_visual
	var mesh := visual.get_node("Body/BodyMesh") as MeshInstance3D
	var original_mesh := mesh.mesh
	var original_body := parked.body.global_transform
	var original_visual := visual.global_transform
	var amber := (mesh.mesh.get_meta("slots") as Array).find("lens_amber")
	var material := visual.get_meta("indicator_material") as StandardMaterial3D
	check(amber >= 0 and mesh.get_surface_override_material(amber) == material, "alarm illuminates the actual amber lens surface of the shared car mesh")
	var other_material: StandardMaterial3D
	for b: Breakables.Breakable in bk.env_objects:
		if b.kind == &"parked" and b != parked:
			other_material = b.parked_visual.get_meta("indicator_material")
			break
	check(other_material != material, "individual parked-car indicators do not share a mutable emission material")
	# Use a contact on the actual outer body panel, independent of random parked yaw.
	var point := visual.global_transform * Vector3(0.79, 0.78, 0.2)
	var inward := -visual.global_basis.x
	var debris_before := bk.debris_count()
	var drawn_debris_before := _drawn_debris_instances()
	parked.receive_vehicle_impact(Vector3(0.7, 0, 0), 0.24, point, inward, 5.0)
	parked.restore_left = 10000
	await _frames(12)
	check(parked.body.global_position.distance_to(original_body.origin) > 0.02, "a real impulse moves the physical parked body")
	var delta := parked.body.global_transform * original_body.affine_inverse()
	check(visual.global_transform.is_equal_approx(delta * original_visual), "body, visual and lights retain one rigid transform after translation and yaw")
	check(mesh.mesh != original_mesh and int(visual.get_meta("vehicle_dent_count", 0)) > 0, "impact changes this instance's actual mesh without editing the shared mesh")
	check(bk.debris_count() == debris_before, "native parked-body dent does not allocate generic environment fracture fragments")
	if drawn_debris_before >= 0:
		check(_drawn_debris_instances() == drawn_debris_before, "native parked-body dent has no extra steel-beam draw instances over the real car")
	else:
		print("NOT_RUN: parked fracture-debris draw transforms require a real rendering backend; native WORLD-02 capture remains required")
	check(mesh.get_surface_override_material(amber) == material, "deformation preserves the real amber lens material binding")
	check(bk.alarms > 0, "vehicle impact starts its existing alarm event")
	LadaVisual.set_indicators(visual, true)
	check(material.emission_energy_multiplier > 0 and other_material.emission_energy_multiplier == 0, "alarm lights only the struck car's real lenses")
	var query := PhysicsRayQueryParameters3D.create(parked.body.global_position + Vector3.UP * 3, parked.body.global_position + Vector3.UP * 0.1, 1)
	check(world.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == parked.body, "moved visible parked roof has the matching real World collider")
	bk.reset_positions()
	check(parked.body.global_transform.is_equal_approx(original_body) and visual.global_transform.is_equal_approx(original_visual), "reset restores both physical and visible parked transforms exactly")
	check(mesh.mesh == original_mesh and material.emission_energy_multiplier == 0, "reset restores the original mesh and turns alarm lenses off")
	check(parked.parked_velocity == Vector3.ZERO and parked.parked_yaw_velocity == 0, "reset releases all residual physical motion")

func _drawn_debris_instances() -> int:
	var native_gl := DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if RenderingServer.get_rendering_device() == null and not native_gl:
		return -1
	var node := bk.get_node("Debris") as MultiMeshInstance3D
	if not node.is_visible_in_tree():
		return 0
	var count := 0
	for i in node.multimesh.instance_count:
		if node.multimesh.get_instance_transform(i).basis.get_scale().length_squared() > 0.000001:
			count += 1
	return count

func check(value: bool, message: String) -> bool:
	checks += 1
	if not value: failures.append(message)
	return value

func _frames(count: int) -> void:
	for i in count: await physics_frame

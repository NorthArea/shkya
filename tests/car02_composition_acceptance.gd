extends SceneTree
## Independent CAR-02 oracle: real Main consumers, C1/C2/C5/C7/C9/C11.
## Headless only. Rendering, recognition, FPS and complete route traversal are NOT RUN.

const Layout = preload("res://game/world/layout.gd")
const Gazelle = preload("res://game/vehicles/gazelle_visual.gd")
const Niva = preload("res://game/vehicles/niva_visual.gd")
const Samara = preload("res://game/vehicles/samara_visual.gd")
const Van = preload("res://game/vehicles/city_van.gd")
const MainScene = preload("res://game/main.tscn")

var checks := 0
var failures := 0
var main: Node
var world: DemoWorld

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("CAR02_COMPOSITION FAIL: " + message)

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		printerr("CAR02_COMPOSITION requires --headless; renderer/audio acceptance is separate")
		quit(2)
		return
	main = MainScene.instantiate()
	root.add_child(main)
	main.start_game()
	for i in 4:
		await process_frame
		await physics_frame
	world = main.world
	expect(world != null and world.get_parent() == main, "Main creates its actual DemoWorld")
	if world == null:
		_finish()
		return
	# Freeze background actors only after genuine startup and deferred consumer binding.
	# Individual physics callbacks below advance real CityVan code deterministically.
	_stop_callbacks(world)
	_parking_composition()
	_van_composition()
	_mission_composition()
	_finish()

func _stop_callbacks(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_stop_callbacks(child)

func _parking_composition() -> void:
	var geo: Node = world.get_node("LevelGeometry")
	var breaks: Node = geo.get_node("Breakables")
	var solids: Array = Layout.all_solids()
	var expected_count := 0
	var actual_count := 0
	var nivas: Array = []
	var samaras: Array = []
	var hood_found := false
	for b in breaks.env_objects:
		if b.kind == &"parked":
			actual_count += 1
	for index in solids.size():
		var spec: Array = solids[index]
		if spec[1] != "parked_car":
			continue
		expected_count += 1
		var b = breaks.env_at_index(index)
		expect(b != null, "each pre-existing parking box has exactly one breakable owner: %d" % index)
		if b == null:
			continue
		expect(b.kind == &"parked" and b.mode == &"dent", "parking retains dent/solid behavior: %d" % index)
		expect(b.center == spec[2] and b.size == spec[3], "parking physical dimensions and position follow Layout: %d" % index)
		var visual: Node3D = b.parked_visual
		expect(visual != null, "existing parking owns a registered visual: %d" % index)
		if visual == null:
			continue
		var body := visual.get_node_or_null("Body/BodyMesh") as MeshInstance3D
		expect(body != null, "parking has a real shared body mesh: %d" % index)
		if body == null:
			continue
		if body.mesh == Niva.body_meshes()["body"]:
			nivas.append(b)
		elif body.mesh == Samara.body_meshes()["body"]:
			samaras.append(b)
		var xz: Vector2 = spec[2]
		if xz.distance_to(Layout.LIFE_HOOD_CAR) < 0.1:
			hood_found = true
			expect(not nivas.has(b) and not samaras.has(b), "the existing hood occupation keeps its original car family")
			expect((-visual.global_basis.z).dot(Vector3.FORWARD) > 0.99, "hood car still faces its existing work spot")
			expect(geo.get_node_or_null("Residents/LifeProps/Hood") != null, "hood prop remains attached to the existing resident activity")
	expect(actual_count == expected_count, "replacement does not increase parked body population")
	expect(hood_found, "the original hood occupation parking is present")
	expect(nivas.size() == 1, "exactly one existing parking uses shared Niva2121")
	expect(samaras.size() == 1, "exactly one existing parking uses shared Samara2109")
	for b in nivas + samaras:
		var provider = Niva if nivas.has(b) else Samara
		var visual: Node3D = b.parked_visual
		var body := visual.get_node("Body/BodyMesh") as MeshInstance3D
		var glass := visual.get_node("Body/Glass") as MeshInstance3D
		expect(glass.mesh == provider.body_meshes()["glass"], "parking shares provider glazing")
		_body_fits(b.body, visual, "parking %s" % b.id)
		var wheels := 0
		for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == provider.wheel_mesh():
				wheels += 1
		expect(wheels == 4, "replacement keeps exactly four shared wheels")
		var peer: Node3D = provider.build(Color(0.21, 0.37, 0.61), "", 0.0)
		_paint_isolation(body, peer.get_node("Body/BodyMesh"), "parking")
		var twin: Node3D = provider.build(Color(0.21, 0.37, 0.61), "", 0.0)
		_paint_isolation(peer.get_node("Body/BodyMesh"), twin.get_node("Body/BodyMesh"), "identical replacement builds")
		twin.free()
		peer.free()
		# Hit the real registered parked vehicle, then reset through the real owner.
		var original_mesh := body.mesh
		var original_transform: Transform3D = b.body.global_transform
		var point: Vector3 = body.to_global(Vector3(provider.HALF_WIDTH, 0.7, 0.0))
		b.receive_vehicle_impact(Vector3(0.5, 0, 0), 0.02, point, -body.global_basis.x.normalized(), 4.0)
		expect(body.mesh != original_mesh, "actual impact dents the replacement without editing its cached mesh")
		expect(provider.body_meshes()["body"] == original_mesh, "impact preserves shared provider body")
		b.reset()
		breaks.animate(b)
		expect(body.mesh == original_mesh, "reset restores the original shared body resource")
		expect(b.body.global_transform.is_equal_approx(original_transform), "reset restores replacement collision transform")
		expect(b.parked_velocity.is_zero_approx() and is_zero_approx(b.parked_yaw_velocity), "reset clears replacement momentum")
		expect(b.body.collision_layer == 33, "reset preserves World and Breakable collision layers")
	# A family mesh must not be added beside a second complete car at the same parking.
	var full_shells := 0
	for part in world.find_children("BodyMesh", "MeshInstance3D", true, false):
		full_shells += 1
	# Existing composition: parked fleet, player, ring cars, trolley, perimeter police and two CityVans.
	expect(full_shells == expected_count + Layout.TRAFFIC_CARS + 5, "Main contains no additional complete vehicle shells")

func _van_composition() -> void:
	var vans: Array = []
	for node in world.find_children("*", "AnimatableBody3D", true, false):
		if node is CityVan:
			vans.append(node)
	expect(vans.size() == 2, "Main retains its two existing CityVan consumers")
	var meshes: Dictionary = Gazelle.body_meshes(Gazelle.PASSENGER, true)
	var closed: Node3D = Gazelle.build(Color.WHITE, "", 0.0, Gazelle.PASSENGER)
	var closed_meshes: Dictionary = Gazelle.body_meshes(Gazelle.PASSENGER)
	expect(meshes["body"] != closed_meshes["body"], "open passenger shell is actual geometry distinct from the closed state")
	for van: CityVan in vans:
		var body := van.visual.get_node_or_null("Body/BodyMesh") as MeshInstance3D
		var glass := van.visual.get_node_or_null("Body/Glass") as MeshInstance3D
		expect(body != null and glass != null, "actual CityVan uses common provider structure")
		if body == null or glass == null:
			continue
		expect(body.mesh == meshes["body"] and glass.mesh == meshes["glass"], "both CityVan roles use shared open passenger meshes")
		expect(van.interactable.interaction_id == &"city_van" and not van.interactable.prompt.is_empty(), "CityVan retains existing interaction identity and sign")
		_body_fits(van, van.visual, "CityVan %s" % van.name)
		var wheels := 0
		for part: MeshInstance3D in van.visual.find_children("*", "MeshInstance3D", true, false):
			if part.mesh == Gazelle.wheel_mesh():
				wheels += 1
		expect(wheels == 6, "CityVan has the shared six-wheel passenger layout")
		expect((-van.sensor.transform.basis.z).dot(Vector3.RIGHT) > 0.99, "door sensor faces out of the right side")
		expect(van.sensor.position.x > 0.0, "sensor remains anchored on the right door")
		var open_hits := 0
		var closed_hits := 0
		# Probe the usable torso-height doorway around the sensor's longitudinal anchor.
		# Triangles from every actual mesh are tested, including glass and role decoration.
		for y in [1.0, 1.35, 1.7]:
			for dz in [-0.2, 0.0, 0.2]:
				var z: float = van.sensor.position.z + dz
				var a := Vector3(Gazelle.HALF_WIDTH + 0.22, y, z)
				var b := Vector3(Gazelle.HALF_WIDTH - 0.16, y, z)
				var hits := _segment_hit_details(van.visual, a, b)
				if not hits.is_empty():
					open_hits += 1
					printerr("CAR02_COMPOSITION DOOR HIT %s ray %s -> %s: %s" % [van.name, a, b, hits])
				if not _segment_hit_details(closed, a, b).is_empty(): closed_hits += 1
		expect(closed_hits >= 6, "doorway oracle detects the closed passenger side (negative control)")
		expect(open_hits == 0, "actual CityVan right doorway has no hidden body/glass closure (%d/9 blocked)" % open_hits)
		_paint_isolation(body, closed.get_node("Body/BodyMesh"), "CityVan")
	if vans.size() == 2:
		_paint_isolation(vans[0].visual.get_node("Body/BodyMesh"), vans[1].visual.get_node("Body/BodyMesh"), "two actual CityVans")
	closed.free()

func _mission_composition() -> void:
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var van: CityVan = patrols.van
	var closure: Node = patrols.closure
	var mission: MissionDirector = world.mission
	expect(mission.state == MissionDirector.NOT_STARTED, "real Main starts with the existing mission state")
	_tutorial_mode(van)
	expect(not closure.van.sensor.enabled, "hidden road-closure van has no active sensor")
	world.player.place(van.sensor.global_position + van.global_basis.x * 2.0, 0.0)
	expect(van.sensor.poll() > 0.0, "real parked sensor still detects the pedestrian in its tutorial area")
	expect(not mission.buy_bread() and not van.is_driving(), "invalid purchase does not drive the van")
	mission.interact(&"babka")
	mission.accept()
	world.enter_car()
	expect(mission.state == MissionDirector.DRIVE_TO_KIOSK, "actual car entry still advances the real mission")
	expect(van.sensor.poll() == 0.0, "the van does not detect Ilyusha inside the car")
	expect(world.exit_car(), "real car exit remains available")
	_stop_callbacks(world.player)
	mission.notify_arrived_kiosk()
	mission.add_money(MissionDirector.BREAD_PRICE)
	var start: Vector3 = van.global_position
	expect(mission.buy_bread(), "valid purchase reaches the real bread_received signal")
	expect(mission.has_bread and mission.road_closed and mission.state == MissionDirector.RETURN_HOME, "bread and closure state survive visual replacement")
	expect(van.is_driving() and not van.sensor.enabled, "purchase starts the actual van route and disables its sensor")
	expect(not closure.van.sensor.enabled, "road-closure role does not acquire the tutorial sensor")
	for i in 60:
		van._physics_process(1.0 / 60.0)
	expect(van.global_position.distance_to(start) > 0.1, "actual CityVan body advances along its configured route")
	expect(van.sensor.poll() == 0.0, "moving sensor returns no visibility")
	# Exercise the real route-completion boundary; this is not full traffic/path traversal.
	var curve: Curve3D = van.get("_curve")
	expect(curve != null and curve.point_count == Layout.VAN_PATH.size(), "mission connected the complete canonical van path")
	if curve != null:
		van.set("_offset", curve.get_baked_length() - 0.001)
		van._physics_process(1.0 / 60.0)
		expect(not van.is_driving() and van.sensor.enabled, "actual route completion restores doorway detection")
		expect(is_equal_approx(van.sensor.range_m, Van.SENSOR_RANGE) and is_equal_approx(van.sensor.fov_deg, Van.SENSOR_FOV) and is_equal_approx(van.sensor.suspicion_cap, 1.0), "arrival restores the existing full doorway sensor mode")
		expect(van.global_position.distance_to(Layout.VAN_PATH[-1]) < 0.02, "completion stops at the canonical kiosk endpoint")
	mission.interact(&"babka")
	expect(closure.finale_parked and not closure.van.sensor.enabled, "turn-in reuses the closure van in the finale with its sensor off")
	mission.reset()
	patrols.reset_positions()
	_tutorial_mode(van)
	expect(van.global_position.distance_to(Layout.VAN_PARK) < 0.001 and not van.is_driving(), "reset returns the actual van to the original parking")
	expect(not closure.finale_parked and not closure.van.sensor.enabled, "mission reset hides the finale without activating its sensor")
	expect(mission.state == MissionDirector.NOT_STARTED and not mission.has_bread, "reset preserves the existing mission reset contract")

func _tutorial_mode(van: CityVan) -> void:
	expect(van.sensor.enabled and is_equal_approx(van.sensor.range_m, Van.PARK_SENSOR_RANGE), "park/reset enables the original tutorial range")
	expect(is_equal_approx(van.sensor.fov_deg, Van.PARK_SENSOR_FOV) and is_equal_approx(van.sensor.suspicion_cap, Van.TUTORIAL_CAP), "tutorial remains omnidirectional and cannot produce full alert")

func _paint_isolation(subject: MeshInstance3D, peer: MeshInstance3D, label: String) -> void:
	var a := _paint(subject)
	var b := _paint(peer)
	expect(a != null and b != null, label + " has a real per-instance paint material")
	if a == null or b == null: return
	var original: Variant = a.get_shader_parameter("paint")
	var peer_original: Variant = b.get_shader_parameter("paint")
	var index: int = (subject.mesh.get_meta("slots", []) as Array).find("paint")
	var cached := subject.mesh.surface_get_material(index) as ShaderMaterial
	var cached_original: Variant = cached.get_shader_parameter("paint") if cached else null
	a.set_shader_parameter("paint", Color(0.91, 0.02, 0.72))
	expect(b.get_shader_parameter("paint") == peer_original, label + " paint edits do not leak to another consumer")
	expect(cached == null or cached.get_shader_parameter("paint") == cached_original, label + " paint edits preserve provider cache")
	a.set_shader_parameter("paint", original)

func _paint(part: MeshInstance3D) -> ShaderMaterial:
	var index: int = (part.mesh.get_meta("slots", []) as Array).find("paint")
	return part.get_active_material(index) as ShaderMaterial if index >= 0 else null

func _body_fits(physical: CollisionObject3D, visual: Node3D, label: String) -> void:
	var collider: CollisionShape3D
	for child in physical.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			collider = child
			break
	expect(collider != null, label + " has a physical box")
	if collider == null: return
	var box: BoxShape3D = collider.shape
	var body := visual.get_node("Body/BodyMesh") as MeshInstance3D
	var bounds: AABB = (collider.global_transform.affine_inverse() * body.global_transform) * body.mesh.get_aabb()
	# SIZE excludes mirrors. The 20 cm side allowance follows the VISUAL's lateral
	# axis, including a parking turned 90 degrees; roof/bumper tolerance stays 8 cm.
	var relative_basis: Basis = collider.global_basis.inverse() * body.global_basis
	var lateral := relative_basis.x.abs() * 0.20
	var vertical := relative_basis.y.abs() * 0.08
	var longitudinal := relative_basis.z.abs() * 0.08
	var excess := lateral + vertical + longitudinal
	var limit := AABB(-box.size * 0.5 - excess, box.size + excess * 2.0)
	expect(limit.encloses(bounds), label + " shell matches its actual physical box: %s vs %s" % [bounds, box.size])
	if body.mesh == Niva.body_meshes()["body"] or body.mesh == Samara.body_meshes()["body"]:
		# The mirror allowance must not conceal an oversized painted torso. Unlike
		# mirrors, both parked families' painted shell belongs inside the solid box.
		var core_limit := AABB(-box.size * 0.5 - Vector3.ONE * 0.03, box.size + Vector3.ONE * 0.06)
		var core := _paint_bounds(collider, body)
		expect(core_limit.encloses(core), label + " painted torso fits without mirror allowance: %s" % core)
		var original_scale := body.scale
		body.scale.x *= 1.20
		var widened := _paint_bounds(collider, body)
		body.scale = original_scale
		expect(not core_limit.encloses(widened), label + " torso oracle rejects a 20 percent wider painted shell (negative control)")

func _paint_bounds(collider: CollisionShape3D, body: MeshInstance3D) -> AABB:
	var surface: int = (body.mesh.get_meta("slots", []) as Array).find("paint")
	var arrays: Array = body.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var transform: Transform3D = collider.global_transform.affine_inverse() * body.global_transform
	var result := AABB(transform * vertices[0], Vector3.ZERO)
	for vertex in vertices:
		result = result.expand(transform * vertex)
	return result

func _segment_hit_details(visual: Node3D, from: Vector3, to: Vector3) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or not part.visible: continue
		var transform: Transform3D = _relative_transform(visual, part)
		var local_from := transform.affine_inverse() * from
		var local_to := transform.affine_inverse() * to
		var slots: Array = part.mesh.get_meta("slots", [])
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for index in vertices.size(): indices.append(index)
			var nearest: Dictionary = {}
			var distance := INF
			for index in range(0, indices.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(local_from, local_to,
					vertices[indices[index]], vertices[indices[index + 1]], vertices[indices[index + 2]])
				if hit == null: continue
				var point: Vector3 = transform * (hit as Vector3)
				var candidate := from.distance_squared_to(point)
				if candidate < distance:
					distance = candidate
					nearest = {"node": str(visual.get_path_to(part)), "surface": surface,
						"slot": slots[surface] if surface < slots.size() else "?", "triangle": index / 3,
						"hit_visual": point, "hit_mesh": hit}
			if not nearest.is_empty(): hits.append(nearest)
	return hits

func _relative_transform(ancestor: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != ancestor and cursor is Node3D:
		result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result

func _finish() -> void:
	print("CAR02_COMPOSITION NOT RUN: renderer, recognition, screenshots, FPS, full route/traffic traversal, manual mission")
	print("CAR02_COMPOSITION: %d checks, %d failures" % [checks, failures])
	if is_instance_valid(main):
		for kind in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
			for player in main.find_children("*", kind, true, false):
				player.stop()
		main.queue_free()
	world = null
	main = null
	await process_frame
	# The test owns the scene-root mesh cache and must release it before server
	# teardown; stopped audio playback is released on the audio thread's next tick.
	if root.has_meta(&"vehicle_mesh_cache"):
		root.remove_meta(&"vehicle_mesh_cache")
	# Fixed-fps SceneTree timers elapse before the real audio thread can release playback.
	OS.delay_msec(100)
	await process_frame
	quit(1 if failures else 0)

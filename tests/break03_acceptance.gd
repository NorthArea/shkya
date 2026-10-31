extends SceneTree
## Независимые сценарии BREAK-03: DECISIONS «Разрушаемое»/«Собака», C7/C11 и исходная карточка BREAK-03.
## Проверяем реальный мир: заслонение World, граф проводов, свет, восстановление, занятия и пакеты.
## Пороги урона/монет, базовые 88 объектов и их запасы проверяет существующий BREAK.

const Layout = preload("res://game/world/layout.gd")
const SnowShader = preload("res://game/world/shaders/snow.gdshader")
const CoinStates = preload("res://game/world/coins.gd")
const IMMUTABLE_KINDS = ["panel", "panel_low", "garage", "kiosk", "snow", "snow_bank"]
const IMMUTABLE_NAMES = ["DogHouse", "KioskPavilion", "KioskBins"]
var checks = 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var geo: Node
var bk: Node
var residents: Node
var life
var lighting: Node
var wind: Node
var camera: Camera3D
var solids: Array = []
var entries: Array = []
var finished = false
var population_ids: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(360.0, true, false, true).timeout.connect(func():
		check(false, "acceptance finishes within its simulated time budget")
		_finish())
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(12)
	world = main.world
	geo = world.get_node("LevelGeometry")
	bk = geo.get_node("Breakables")
	residents = geo.get_node("Residents")
	life = residents.life
	lighting = world.get_node("LightingAndWeather")
	wind = geo.get_node("WindBags")
	camera = root.get_camera_3d()
	var camera_id = camera.get_instance_id()
	# Manual camera poses must survive native SpringArm updates while the rig script is frozen.
	# Keep the actual viewport camera, rather than substituting a different camera or weakening visibility guards.
	camera.reparent(world, true)
	check(root.get_camera_3d() == camera and camera.get_instance_id() == camera_id, "the fixture retains the same actual viewport camera after detaching its spring arm")
	world.player.set_physics_process(false)
	world.car.set_physics_process(false)
	world.camera_rig.set_process(false)
	world.camera_rig.set_physics_process(false)
	wind.set_physics_process(false)
	check(residents.residents.size() == 64, "the actual world has all 64 residents before fixture preparation")
	for resident in residents.residents:
		population_ids.append(resident.get_instance_id())
		resident.set_physics_process(false)
		resident.set_process(false)
		resident._act_stop()
		resident.position = Vector3(1200 + resident.index * 3, 0, 1000)
	for sensor in get_nodes_in_group(&"detection_sensors"): sensor.enabled = false
	solids = Layout.all_solids()
	entries = Layout.env_breakables()
	_catalogue()
	if not check(not entries.is_empty(), "the arena contains breakable environment entries"):
		await _finish()
		return
	_away()
	await _coin_allowed_fallback_controls()
	await _impact_entry()
	await _world_occlusion()
	await _wires_and_light()
	await _longitudinal_wires()
	await _dependent_visuals()
	await _safe_restore()
	await _visible_upper_billboard()
	await _dent()
	await _dent_coin_landing()
	await _activities()
	await _bags()
	await _services_and_queue()
	await _knock_reacquires_reservation()
	await _hidden_shop()
	await _edge_and_immutable_doors()
	await _environment_coins()
	check(residents.residents.size() == 64 and residents.residents.all(func(r): return is_instance_valid(r) and population_ids.has(r.get_instance_id()) and r.is_inside_tree()), "all 64 original resident nodes survive destruction, recovery and reset")
	check(root.get_camera_3d() == camera and camera.get_instance_id() == camera_id, "the same actual viewport camera remains current through destruction and recovery")
	await _finish()

func _catalogue() -> void:
	var by_source = {}
	var ids = {}
	var valid_sources = true
	var unique = true
	for entry in entries:
		if entry.size() < 7:
			valid_sources = false
			continue
		unique = unique and not ids.has(entry[0]) and not by_source.has(entry[6])
		ids[entry[0]] = true
		by_source[entry[6]] = entry
		valid_sources = valid_sources and entry[6] >= 0 and entry[6] < solids.size()
		if entry[6] >= 0 and entry[6] < solids.size():
			valid_sources = valid_sources and entry[2] == solids[entry[6]][2] and entry[3] == solids[entry[6]][3]
	check(valid_sources and unique, "stable unique environment ids refer to their original solid geometry")
	check(Layout.env_breakables() == entries, "repeated catalogue lookup preserves ids and source indexes")
	var missing = []
	var forbidden = []
	var expected_count = 0
	for i in solids.size():
		var solid = solids[i]
		var immutable = solid[1] in IMMUTABLE_KINDS or solid[0] in IMMUTABLE_NAMES
		if immutable:
			if by_source.has(i): forbidden.append("%s@%s" % [solid[0], solid[2]])
			var body_name = solid[0] if i < Layout.SOLIDS.size() else "%s_%d" % [solid[0], i]
			var body = geo.get_node_or_null(NodePath(body_name))
			check(body is StaticBody3D and body.collision_layer == (64 if solid[1] in ["snow", "snow_bank"] else 1) and not body.get_child(0).disabled,
				"immutable source %s has its actual enabled physical body" % body_name)
		else:
			expected_count += 1
			if not by_source.has(i): missing.append("%s@%s" % [solid[0], solid[2]])
	check(missing.is_empty() and entries.size() == expected_count, "all actual street solid geometry is destructible except explicit owner exceptions: %s" % [missing])
	check(forbidden.is_empty(), "houses, garages, kiosk, snow, stealth cover and the dog house are immutable: %s" % [forbidden])
	var instantiated = true
	for entry in entries:
		var b = bk.get_by_id(entry[0])
		instantiated = instantiated and b != null
		if b != null:
			instantiated = instantiated and b.is_intact() and (b.body.collision_layer & 33) == 33
	check(instantiated, "each catalogued environment object has an intact World|Breakable body")

func _pick(names: Array, near: Vector2 = Vector2.INF):
	var best = null
	var distance = INF
	for entry in entries:
		if solids[entry[6]][0] not in names: continue
		var d = entry[2].distance_to(near) if near.is_finite() else 0.0
		if d < distance:
			distance = d
			best = bk.get_by_id(entry[0])
	return best

func _away() -> void:
	world.player.position = Vector3(1000, 0, 1000)
	world.car.position = Vector3(1100, 0, 1000)
	camera.global_position = Vector3(1000, 5, 1000)
	camera.look_at(Vector3(1100, 5, 1000))

func _body_hits(b, mask: int) -> Array:
	var shape = SphereShape3D.new()
	shape.radius = 0.04
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, b.body.global_transform * Vector3(0, b.size.y * 0.5, 0))
	query.collision_mask = mask
	return world.get_world_3d().direct_space_state.intersect_shape(query, 32)

func _contains_body(hits: Array, b) -> bool:
	return hits.any(func(hit): return hit.collider == b.body)

func _ray(b, mask: int) -> Dictionary:
	var size: Vector3 = b.size
	var middle = b.body.global_transform * Vector3(0, minf(size.y * 0.5, 1.2), 0)
	# Cross the nearest horizontal face; long-axis endpoints may lie in an adjacent house or perpendicular board.
	var axis = b.body.global_basis.x if size.x <= size.z else b.body.global_basis.z
	var dir = axis.normalized() * (minf(size.x, size.z) * 0.5 + 0.08)
	var query = PhysicsRayQueryParameters3D.create(middle - dir, middle + dir, mask)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _snapshot(b) -> Dictionary:
	var entry: Dictionary = geo.break_visuals.get(b.id, {})
	var nodes = []
	var mm = []
	for node in entry.get("nodes", []): nodes.append([node, node.global_transform, node.visible])
	for slot in entry.get("mm", []): mm.append([slot[0], slot[1], slot[0].get_instance_transform(slot[1])])
	return {"nodes": nodes, "mm": mm}

func _matches(snapshot: Dictionary) -> bool:
	for record in snapshot.nodes:
		if not record[0].global_transform.is_equal_approx(record[1]) or record[0].visible != record[2]: return false
	for record in snapshot.mm:
		if not record[0].get_instance_transform(record[1]).is_equal_approx(record[2]): return false
	return true

func _world_occlusion() -> void:
	var representatives = {}
	for entry in entries:
		if not representatives.has(entry[1]): representatives[entry[1]] = bk.get_by_id(entry[0])
	for kind in representatives:
		bk.reset_positions()
		var b = representatives[kind]
		await _frames(2)
		var snapshot = _snapshot(b)
		check(not snapshot.nodes.is_empty() or not snapshot.mm.is_empty(), "%s has a registered original visual" % kind)
		var hit = _ray(b, 1)
		check(not hit.is_empty() and hit.collider == b.body, "%s retains its original World occlusion before breaking" % kind)
		check(_body_hits(b, 33).size() == 1 and _contains_body(_body_hits(b, 33), b), "%s has one original physical volume without a duplicate static collider" % kind)
		b.smash(&"punch", Vector3.RIGHT)
		b.restore_left = 10000.0
		await _frames(240)
		var source_name: String = solids[b.env_index][0]
		var parked = source_name in ["ParkedCar", "Zhiguli_A", "Zhiguli_B"]
		check((b.mode == &"dent") == parked, "%s uses crushed persistent-body destruction only for parked cars" % kind)
		if not parked:
			check(not b.blocks() and _body_hits(b, 33).is_empty(), "%s leaves no solid obstacle, duplicate collider or support after falling" % kind)
			check(_ray(b, 1).get("collider") != b.body, "%s no longer occludes the actual World ray" % kind)
			check(b.env_hidden(), "%s original visual has left the street after its fall/shatter" % kind)
			var hidden_nodes = snapshot.nodes.all(func(record): return not record[0].visible)
			var hidden_mm = snapshot.mm.all(func(record): return is_zero_approx(record[0].get_instance_transform(record[1]).basis.determinant()))
			check(hidden_nodes and hidden_mm, "%s actual original nodes and multimesh instances are hidden" % kind)
		else:
			check(b.blocks() and _contains_body(_body_hits(b, 33), b), "%s dent stays physically solid" % kind)
		bk.reset_positions()
		await _frames(2)
		check(b.is_intact() and _matches(snapshot), "%s reset restores its exact original nodes and multimesh transforms" % kind)

func _snow_materials() -> Array:
	var found = {}
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		var materials = []
		if node.material_override != null:
			materials.append(node.material_override)
		else:
			var mesh: Mesh = node.mesh if node is MeshInstance3D else (node.multimesh.mesh if node is MultiMeshInstance3D and node.multimesh != null else null)
			if mesh != null:
				for i in mesh.get_surface_count():
					var override: Material = node.get_surface_override_material(i) if node is MeshInstance3D else null
					materials.append(override if override != null else mesh.surface_get_material(i))
		for material in materials:
			if material is ShaderMaterial and material.shader == SnowShader: found[material] = true
	return found.keys()

func _sparkle_source_on(material: ShaderMaterial, center: Vector2) -> bool:
	var lamps = material.get_shader_parameter("sparkle_lamps")
	var colors = material.get_shader_parameter("sparkle_lamp_colors")
	var count = material.get_shader_parameter("sparkle_lamp_count")
	if lamps == null or colors == null or count == null: return false
	for i in mini(count, mini(lamps.size(), colors.size())):
		var source: Vector4 = lamps[i]
		var power: Vector4 = colors[i]
		if Vector2(source.x, source.z).distance_to(center) < 0.1:
			if source.w > 0.0 and power.w > 0.0 and Vector3(power.x, power.y, power.z).length_squared() > 0.0: return true
	return false

func _wires_and_light() -> void:
	bk.reset_positions()
	var lamp = _pick(["Lamp_Yard"])
	if check(lamp != null, "a courtyard lamp is available for a real light lifecycle"):
		check(lighting.lamp_on(lamp.center), "intact lamp emits light")
		var snow = _snow_materials()
		check(not snow.is_empty(), "actual snow surface materials are present in the playable scene")
		for material in snow: check(_sparkle_source_on(material, lamp.center), "the intact lamp illuminates actual snow sparkle facets")
		lamp.smash(&"punch", Vector3.RIGHT)
		lamp.restore_left = 10000.0
		await _frames(2)
		check(not lighting.lamp_on(lamp.center), "breaking the actual lamp switches its associated light off")
		for material in snow: check(not _sparkle_source_on(material, lamp.center), "the broken lamp no longer lights snow through sparkle_lamps/sparkle_lamp_colors")
		bk.reset_positions()
		check(lighting.lamp_on(lamp.center), "reset restores the lamp light")
		for material in snow: check(_sparkle_source_on(material, lamp.center), "reset restores the lamp contribution to the actual snow material")
	var wire: Array = []
	for entry in geo.break_visuals.values():
		for candidate in entry.get("wires", []):
			if candidate[3].size() >= 2:
				wire = candidate
				break
		if not wire.is_empty(): break
	if not check(not wire.is_empty(), "a real wire span records both of its breakable supports"): return
	var one = bk.get_by_id(wire[3][0])
	var two = bk.get_by_id(wire[3][1])
	if not check(one != null and two != null and one != two, "wire support ids resolve to distinct environment objects"): return
	var original: Transform3D = wire[0].get_instance_transform(wire[1])
	one.smash(&"punch", Vector3.RIGHT)
	two.smash(&"punch", Vector3.LEFT)
	one.restore_left = 10000.0
	two.restore_left = 10000.0
	await _frames(240)
	check(wire[0].get_instance_transform(wire[1]).basis.determinant() == 0.0, "wire disappears when both supports have fallen")
	_away()
	one.restore_left = 0.0
	await _frames(50)
	check(one.is_intact() and not two.is_intact(), "only the first eligible support has regrown")
	check(wire[0].get_instance_transform(wire[1]).basis.determinant() == 0.0, "a wire cannot reappear with the other support still absent")
	two.restore_left = 0.0
	await _frames(50)
	check(two.is_intact() and wire[0].get_instance_transform(wire[1]).is_equal_approx(original), "restoring both supports reconstructs the original wire span")

func _dependent_visuals() -> void:
	bk.reset_positions()
	var target = null
	var dependents = []
	for entry in entries:
		var visual: Dictionary = geo.break_visuals.get(entry[0], {})
		var visible = visual.get("cut", []).filter(func(node): return node.visible)
		if not visible.is_empty():
			target = bk.get_by_id(entry[0])
			dependents = visible
			break
	if not check(target != null, "a real dependent visual is registered against a destructible support"): return
	target.smash(&"punch", Vector3.RIGHT)
	target.restore_left = 10000.0
	await _frames(2)
	check(dependents.all(func(node): return not node.visible), "dependent decorations cannot float after their support breaks")
	bk.reset_positions()
	await _frames(2)
	check(dependents.all(func(node): return node.visible), "reset restores the original dependent decorations")

func _safe_restore() -> void:
	bk.reset_positions()
	var b = _pick(["Lamp_Yard"])
	if b == null: return
	b.smash(&"punch", Vector3.RIGHT)
	b.restore_left = 10000.0
	await _frames(240)
	world.player.position = b.global_position
	b.restore_left = 0.0
	b.tick(0.1)
	check(b.state == &"broken", "expired restoration waits while the player is nearby")
	_away()
	world.car.position = b.global_position
	b.restore_left = 0.0
	b.tick(0.1)
	check(b.state == &"broken", "expired restoration waits while the car is nearby")
	_away()
	camera.global_position = b.global_position + Vector3(0, 3, 12)
	camera.look_at(b.global_position + Vector3.UP * 2.0)
	b.restore_left = 0.0
	b.tick(0.1)
	check(b.state == &"broken", "expired restoration waits while the original object would appear in frame")
	_away()
	var blocker: Resident = residents.residents[0]
	var old_position = blocker.position
	blocker.hidden = false
	blocker.show()
	blocker.place(b.global_position)
	await _frames(2)
	b.restore_left = 0.0
	b.tick(0.1)
	check(b.state == &"broken", "expired restoration waits while a real resident occupies the original volume")
	blocker.place(old_position)
	await _frames(2)
	var trolley: Node3D = geo.get_node("Traffic").trolleybus
	var trolley_transform = trolley.global_transform
	var trolley_running = trolley.is_physics_processing()
	trolley.set_physics_process(false)
	trolley.global_position = b.global_ground()
	await _frames(2)
	b.restore_left = 0.0
	b.tick(0.1)
	check(b.state == &"broken", "expired restoration waits while a real World-layer trolleybus occupies its original volume")
	trolley.global_transform = trolley_transform
	trolley.set_physics_process(trolley_running)
	await _frames(2)
	b.restore_left = 0.0
	await _frames(50)
	check(b.is_intact() and _contains_body(_body_hits(b, 1), b), "out of sight and with free space, the original physical object is restored")
	check(lighting.lamp_on(b.center), "ordinary safe restoration restores the lamp light too")

func _visible_upper_billboard() -> void:
	bk.reset_positions()
	var board = _pick(["Billboard"])
	if not check(board != null, "a real billboard is available for the upper-geometry visibility case"): return
	var upper = Vector3(0, -INF, 0)
	var visuals: Dictionary = geo.break_visuals.get(board.id, {})
	for branch in visuals.get("nodes", []):
		var meshes = branch.find_children("*", "MeshInstance3D", true, false)
		if branch is MeshInstance3D: meshes.append(branch)
		for mesh_node in meshes:
			if not mesh_node.is_visible_in_tree() or mesh_node.mesh == null: continue
			for surface in mesh_node.mesh.get_surface_count():
				var arrays = mesh_node.mesh.surface_get_arrays(surface)
				if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					var point: Vector3 = mesh_node.global_transform * vertex
					if point.y > upper.y: upper = point
	if not check(upper.is_finite() and upper.y > board.size.y + 1.0, "the actual billboard mesh extends well above its nominal collision box"): return
	_away()
	board.smash(&"punch", Vector3.RIGHT)
	board.restore_left = 10000.0
	await _frames(240)
	var original_fov = camera.fov
	camera.fov = 4.0
	camera.global_position = upper + Vector3(0, 0, 12)
	camera.look_at(upper)
	var lower_outside = true
	for sx in [-1.0, 1.0]:
		for sy in [0.0, board.size.y]:
			for sz in [-1.0, 1.0]:
				var lower: Vector3 = board.base_xf() * Vector3(sx * board.size.x * 0.5, sy, sz * board.size.z * 0.5)
				lower_outside = lower_outside and not camera.is_position_in_frustum(lower)
	check(camera.is_position_in_frustum(upper) and lower_outside, "the narrow real camera frame sees only the high billboard mesh, beyond every corner of its nominal box")
	board.restore_left = 0.0
	board.tick(0.1)
	check(board.state == &"broken", "billboard restoration is blocked when only its upper rendered geometry would be visible")
	camera.fov = original_fov
	_away()
	bk.reset_positions()

func _dent() -> void:
	bk.reset_positions()
	var car = _pick(["Zhiguli_A"])
	if not check(car != null, "a parked car participates in the same destruction lifecycle"): return
	var before = bk.coins_dropped
	var above = car.global_ground() + Vector3.UP * (car.size.y + 1.0)
	var original_visual = _snapshot(car)
	car.smash(&"car", Vector3.RIGHT)
	car.restore_left = 10000.0
	await _frames(60)
	check(car.state == &"broken" and car.mode == &"dent" and car.blocks(), "a dented car is broken and remains a solid crushed body")
	check(_contains_body(_body_hits(car, 1), car), "the crushed car still blocks the actual World collision query")
	var roof_query = PhysicsRayQueryParameters3D.create(above, car.global_ground() + Vector3.UP * 0.1, 1)
	check(world.get_world_3d().direct_space_state.intersect_ray(roof_query).get("collider") == car.body, "the actual crushed car roof remains physically present to downward collision rays")
	check(not car.env_hidden() and not _matches(original_visual), "the dent visibly deforms the actual original parked-car geometry")
	world.player.set_physics_process(true)
	var roof_point: Vector3 = car.body.global_transform * Vector3(0, car.size.y + 0.3, 0)
	world.player.place(roof_point, 0.0)
	await _frames(30)
	var feet: Vector3 = world.player.global_position
	var foot_query = PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.1, feet - Vector3.UP * 0.5, 1)
	check(world.player.is_on_floor() and feet.y > 0.3 and world.get_world_3d().direct_space_state.intersect_ray(foot_query).get("collider") == car.body,
		"the actual player stands on the crushed car roof without falling through its physical body")
	world.player.set_physics_process(false)
	_away()
	check(bk.coins_dropped > before, "the first destruction of a parked car produces the applicable coin reward")
	var paid = bk.coins_dropped
	var count = bk.breaks
	for i in 5: car.smash(&"car", Vector3.LEFT)
	await _frames(2)
	check(bk.coins_dropped == paid and bk.breaks == count, "repeated contacts with the same crushed car cannot farm destruction or coins")
	bk.reset_positions()
	check(_matches(original_visual), "reset restores the exact original parked-car geometry after its dent")

func _activities() -> void:
	var actor: Resident = residents.residents[30]
	for scenario in [[&"carpet", ["CarpetBar"]], [&"hood", ["ParkedCar"]], [&"slide_1", ["PropIceSlide"]],
		[&"slide_1", ["PropIceSlideRamp"]], [&"hockey_w", ["PropRinkBoard"]]]:
		bk.reset_positions()
		var spot: StringName = scenario[0]
		if not check(life.spots.has(spot), "activity spot %s exists in the actual arena" % spot): continue
		var target: Vector3 = life.spots[spot].pos
		var support = _pick(scenario[1], Vector2(target.x, target.z))
		if not check(support != null, "%s has its actual breakable support" % spot): continue
		actor._act_stop()
		actor.spot_id = spot
		actor.state = &"walk"
		actor.hidden = false
		actor.show()
		actor.knock_phase = &""
		actor._arrive()
		actor._wait = 100.0
		var kind = life.spots[spot].kind
		check(actor.is_playing(kind), "%s starts while its real support is present" % spot)
		support.smash(&"punch", Vector3.RIGHT)
		actor._tick_activity(1.0 / 60.0)
		check(not actor.is_playing(kind), "%s stops when its real support disappears" % spot)
		actor._act_stop()
	bk.reset_positions()

func _bags() -> void:
	bk.reset_positions()
	if not check(wind.has_method("_owner_present"), "bags resolve live owners for their stored environment geometry"): return
	var point_index = -1
	var support = null
	for i in wind._snag_points.size():
		var point: Array = wind._snag_points[i]
		if point.size() < 4 or point[3] < 0: continue
		var entry = Layout.env_break_at(point[3])
		if not entry.is_empty():
			var candidate = bk.get_by_id(entry[0])
			if candidate.mode != &"dent":
				point_index = i
				support = candidate
				break
	if not check(point_index >= 0 and support != null, "a real bag snag point belongs to a destructible environment object"): return
	var point: Array = wind._snag_points[point_index]
	var bag = wind.bags[0]
	bag.state = &"snag"
	bag.snag_on_person = false
	bag.snag_target = null
	bag.last_snag = point_index
	bag.snag_point = point[0]
	bag.snag_left = 100.0
	bag.snag_time = 0.0
	check(wind._owner_present(point[3]), "an intact object can support the bag's current snag")
	support.smash(&"punch", Vector3.RIGHT)
	wind._snagged(bag, Vector3(1, 0, 0), 0.0, 1.0 / 60.0)
	check(not wind._owner_present(point[3]) and bag.state == &"fly", "a disappearing support releases its attached bag without waiting for a gust")
	bk.reset_positions()
	var roof = _pick(["BusPavilion"])
	if check(roof != null, "a real pavilion roof is available for the indexed bag-ground lifecycle"):
		check(wind._walls.any(func(w): return w.size() > 2 and w[2] == roof.env_index), "the pavilion is actually present in the original low-roof wall index")
		var above = roof.global_position + Vector3.UP * (roof.size.y + 0.2)
		var height_before = wind.ground_at(above)
		check(is_equal_approx(height_before, roof.size.y + wind.GROUND_LIFT), "the intact indexed pavilion provides its actual roof height to bags")
		roof.smash(&"test", Vector3.RIGHT)
		roof.restore_left = 10000.0
		var height_after = wind.ground_at(above)
		check(height_before > height_after + 1.0, "a shattered pavilion roof no longer holds up flying bags")
		await _frames(240)
		_away()
		roof.restore_left = 0.0
		await _frames(50)
		check(roof.is_intact() and is_equal_approx(wind.ground_at(above), height_before), "ordinary safe restoration restores the indexed pavilion roof for bags")
	bk.reset_positions()

# Реальный ввод удара/физический контакт дополняют lifecycle-проверки через smash.
func _impact_entry() -> void:
	bk.reset_positions()
	var sign_post = _pick(["StreetSign"])
	if check(sign_post != null, "a real light street object is available to punch"):
		world.player.set_physics_process(true)
		world.player.place(sign_post.global_ground() + Vector3(0, 0, 1.0), 0.0)
		await _frames(2)
		check(world.player.punch(), "the real player starts a punch at a street sign")
		await _frames(25)
		check(not sign_post.is_intact() and sign_post.last_by == &"punch" and sign_post.hits == 1,
			"the actual punch query reaches the environment body and breaks the sign once")
		world.player.set_physics_process(false)
	bk.reset_positions()
	var lamp = _pick(["Lamp_Yard"])
	if check(lamp != null, "a real heavy environment object is available for car contact"):
		world.car.set_physics_process(true)
		world.car.reset_to(lamp.global_ground() + Vector3(0, 0, lamp.size.z * 0.5 + Lada.SIZE.z * 0.5 + 1.2), 0.0)
		world.enter_car()
		await _frames(2)
		for i in 90:
			world.car.velocity = Vector3(0, world.car.velocity.y, -5.0)
			await physics_frame
			if not lamp.is_intact(): break
		check(not lamp.is_intact() and lamp.last_by == &"car", "real Lada physics contact breaks the heavy environment lamp")
		check(world.exit_car(), "the player can leave the Lada after the real environment impact")
		world.player.set_physics_process(false)
		world.car.set_physics_process(false)
	bk.reset_positions()
	_away()

func _at_activity(actor: Resident, id: StringName) -> void:
	actor._act_stop()
	if actor.spot_id != &"": life.release(actor.spot_id, actor)
	actor.spot_id = id
	actor.knock_phase = &""
	actor._show()
	actor.place(life.spots[id].pos)
	actor._go_to(id)

func _services_and_queue() -> void:
	var actors = [residents.residents[46], residents.residents[47], residents.residents[53]]
	# Discover queue members from Layout data, but select each real service's support independently of Life.environment_support.
	for scenario in [[&"press", "PropPress"], [&"shaw", "PropShawarma"]]:
		bk.reset_positions()
		life.reset()
		var service: StringName = scenario[0]
		var queue: Array = life.spots.values().filter(func(s): return s.kind == &"queue" and s.service == service)
		queue.sort_custom(func(a, b): return a.rank < b.rank)
		if not check(queue.size() == 2, "%s has the two actual bounded waiting places" % service): continue
		var ids = [service, queue[0].id, queue[1].id]
		for i in actors.size():
			_at_activity(actors[i], ids[i])
			check(life.reserved.get(ids[i], []).has(actors[i]), "%s is reserved by its real arriving customer" % ids[i])
			check(actors[i].is_playing(life.spots[ids[i]].kind), "%s starts its actual service/queue activity" % ids[i])
		var at: Vector3 = life.spots[service].pos
		var support = _pick([scenario[1]], Vector2(at.x, at.z))
		if not check(support != null, "%s has its actual street kiosk" % service): continue
		support.smash(&"punch", Vector3.RIGHT)
		support.restore_left = 10000.0
		for id in ids:
			check(not life.anchor_intact(id), "%s inherits service unavailability when the actual kiosk breaks" % id)
			check(life.reserved.get(id, []).is_empty(), "%s reservation is released by destruction itself" % id)
			check(not life.reserve(id, actors[0]), "%s rejects fresh reservations while its service is destroyed" % id)
		for actor in actors:
			check(life.window_arrival(actor) == &"", "%s refuses arrival at a destroyed service" % actor.spot_id)
			check(life.queue_next(actor) == &"", "the destroyed service does not advance waiting customers")
			actor._tick_activity(1.0 / 60.0)
			check(not actor.is_playing(&"window") and not actor.is_playing(&"queue"), "the real service/queue animation stops after destruction")
		check(life.choose(actors[0], service, actors[0].home, actors[0].rng) == &"", "the planner cannot route a new customer to destroyed %s" % service)
		bk.reset_positions()
		for id in ids: check(life.anchor_intact(id), "%s becomes usable again after reset" % id)
		life.reset()
		for i in actors.size():
			_at_activity(actors[i], ids[i])
			check(life.reserved.get(ids[i], []).has(actors[i]), "%s can be reserved again after reset" % ids[i])
		for actor in actors: actor._act_stop()
	life.reset()
	bk.reset_positions()
	_away()

func _hidden_shop() -> void:
	bk.reset_positions()
	life.reset()
	var actor: Resident = residents.residents[57]
	var at: Vector3 = life.spots[&"shop24"].pos
	var shop = _pick(["Shop24"], Vector2(at.x, at.z))
	if not check(shop != null, "the real shop building supports its entrance activity"): return
	_at_activity(actor, &"shop24")
	check(actor.hidden and actor.state == &"inside" and actor._acting and actor._act_kind == &"shop", "a resident actually enters the intact shop and becomes hidden inside")
	shop.smash(&"punch", Vector3.RIGHT)
	shop.restore_left = 10000.0
	check(life.reserved.get(&"shop24", []).is_empty(), "breaking the shop immediately releases its entrance reservation")
	actor._tick_hidden(1.0 / 60.0)
	check(not actor.hidden and actor.is_visible_in_tree() and not actor.is_playing(&"shop"), "destruction releases a hidden shopper into the actual world")
	check(life.choose(actor, &"shop24", actor.home, actor.rng) == &"", "the absent shop cannot be chosen again")
	actor._act_stop()
	bk.reset_positions()
	check(life.anchor_intact(&"shop24"), "the shop entrance is usable after reset")
	_at_activity(actor, &"shop24")
	check(actor.hidden and actor.state == &"inside", "a real resident can enter the restored shop again")
	actor._show()
	actor._act_stop()
	life.reset()
	_away()

func _edge_and_immutable_doors() -> void:
	bk.reset_positions()
	life.reset()
	var actor: Resident = residents.residents[58]
	var doors = {}
	for node in geo.find_children("StoreEntrance_*", "Node3D", true, false):
		doors[node] = node.global_transform
	var moving = get_nodes_in_group(PathVehicle.GROUP)
	var moving_layers = moving.map(func(vehicle): return [vehicle, vehicle.collision_layer, vehicle.collision_mask])
	var protected_bodies = []
	# World geometry is directly parented by LevelGeometry; moving patrol bodies are not static scenery.
	var candidates = geo.get_children().filter(func(node): return node is StaticBody3D)
	for spot in get_nodes_in_group(&"hide_spots"):
		candidates.append_array(spot.find_children("*", "StaticBody3D", true, false))
	for body in candidates:
		if body.collision_layer == 0: continue
		protected_bodies.append([body, body.collision_layer, body.global_transform])
	for entry in entries:
		var b = bk.get_by_id(entry[0])
		b.smash(&"test", Vector3.RIGHT)
		b.restore_left = 10000.0
	await _frames(240)
	check(protected_bodies.all(func(record): return is_instance_valid(record[0]) and record[0].collision_layer == record[1] and record[0].global_transform.is_equal_approx(record[2])),
		"destroying all street environment preserves the physical houses, garages, snow and stealth cover")
	check(not moving_layers.is_empty() and moving_layers.all(func(record): return is_instance_valid(record[0]) and record[0].collision_layer == record[1] and record[0].collision_mask == record[2]), "moving traffic keeps its original physical layers/masks while the environment is destroyed")
	check(doors.keys().all(func(node): return node.is_visible_in_tree() and node.global_transform.is_equal_approx(doors[node])), "immutable building store entrances retain their actual visible thresholds")
	for id in life.spots:
		var spot: Dictionary = life.spots[id]
		if spot.kind == &"door":
			check(life.anchor_intact(id), "house door %s remains usable in the destroyed world" % id)
		elif spot.kind == &"edge":
			check(life.anchor_intact(id), "arena exit %s is independent of destructible street furniture" % id)
			_at_activity(actor, id)
			actor._tick_activity(1.0 / 60.0)
			check(actor.hidden and actor.state == &"away", "%s actually exits out of frame after environment destruction" % id)
			actor._wait = 0.0
			actor._tick_hidden(1.0 / 60.0)
			check(not actor.hidden and actor.is_visible_in_tree(), "%s returns to the live world after its wait" % id)
			actor._act_stop()
	bk.reset_positions()
	life.reset()
	_away()

func _environment_coins() -> void:
	bk.reset_positions()
	var coins = geo.get_node("Coins")
	coins.reset()
	var total = 0
	var zero = []
	var unsafe = []
	var batch = 0
	var made_batch = 0
	var lanes = [Layout.ring_lane(), Layout.ring_lane(6.0, 6, true)]
	var paid_kinds = {}
	var max_emitter_distance = 0.0
	var max_emitter_clearance = 0.0
	var max_drop_elapsed_us := 0
	var displaced_emitters = []
	for i in entries.size():
		var b = bk.get_by_id(entries[i][0])
		bk.coin_drops.clear()
		b.coins_at = -INF
		# Keep the collector in a real reachable free volume, including at the arena edge.
		var witness = _coin_witness(b)
		check(witness.is_finite(), "%s has a legal player-side coin-drop witness" % b.id)
		if not witness.is_finite(): witness = Layout.SPAWN
		world.player.position = witness
		# Capture actual newly published AIR slots before any physics advances their trajectory.
		var before_slots: PackedInt32Array = coins._state.duplicate()
		var drop_started_us := Time.get_ticks_usec()
		var made: int = bk.drop_coins(b, &"punch")
		var elapsed_us := Time.get_ticks_usec() - drop_started_us
		max_drop_elapsed_us = maxi(max_drop_elapsed_us, elapsed_us)
		var source_rect: Rect2 = b.rect()
		var emitted = []
		var source_distance = 0.0
		var source_clearance = 0.0
		for slot in range(coins._fixed, coins._state.size()):
			if before_slots[slot] != CoinStates.GONE or coins._state[slot] != CoinStates.AIR: continue
			var at: Vector3 = coins._pos[slot]
			var flat = Vector2(at.x, at.z)
			var nearest = Vector2(clampf(at.x, source_rect.position.x, source_rect.end.x), clampf(at.z, source_rect.position.y, source_rect.end.y))
			source_distance = maxf(source_distance, flat.distance_to(b.center))
			source_clearance = maxf(source_clearance, flat.distance_to(nearest))
			emitted.append({"slot": slot, "position": at})
		check(emitted.size() == made, "%s actual newly published AIR slots match the returned reward" % b.id)
		max_emitter_distance = maxf(max_emitter_distance, source_distance)
		max_emitter_clearance = maxf(max_emitter_clearance, source_clearance)
		var displacement = {"id": String(b.id), "center_distance_xz": source_distance, "source_rect_clearance_xz": source_clearance}
		if source_distance > 0.0: displaced_emitters.append(displacement)
		print("COIN_EMITTER_TELEMETRY: ", JSON.stringify({"id": String(b.id), "source_center": b.global_ground(),
			"source_rect": source_rect, "made": made, "elapsed_us": elapsed_us, "new_air_slots": emitted, "displacement": displacement}))
		check(made == Breakables.coin_count(b.kind, b.heavy), "%s emits its configured reward through the real drop path" % b.id)
		check(bk.drop_coins(b, &"punch") == 0, "%s cannot immediately pay again during cooldown" % b.id)
		_away()
		if made == 0: zero.append(b.id)
		else: paid_kinds[b.kind] = true
		check(made >= 0 and made <= Breakables.coin_count(b.kind, b.heavy), "%s emits at most its actual configured reward" % b.id)
		total += made
		made_batch += made
		batch += 1
		if batch < 10 and i < entries.size() - 1: continue
		var positions = await _settled_loose_positions(coins, made_batch, "environment batch ending at %s" % b.id)
		check(positions.size() == made_batch, "every emitted environment coin survives to its actual landing (%d/%d)" % [positions.size(), made_batch])
		for p: Vector3 in positions:
			var xz = Vector2(p.x, p.z)
			var bad = not Layout.BOUNDS.has_point(xz) or Layout.KIOSK_SQUARE.has_point(xz) or Layout.ROOF_AREA.has_point(xz)
			for spec in solids:
				var center: Vector2 = spec[2]
				var size: Vector3 = spec[3]
				if Rect2(center - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)).grow(0.3).has_point(xz): bad = true
			for lane in lanes:
				for j in lane.size():
					var a: Vector3 = lane[j]
					var z: Vector3 = lane[(j + 1) % lane.size()]
					if xz.distance_to(Geometry2D.get_closest_point_to_segment(xz, Vector2(a.x, a.z), Vector2(z.x, z.z))) < 2.3: bad = true
			if bad: unsafe.append(p)
		coins.reset()
		batch = 0
		made_batch = 0
		await _frames(1)
	check(total > 0 and paid_kinds.size() > 1, "actual environment drops reach the real coin system across multiple kinds")
	check(unsafe.is_empty(), "real environment rewards never land inside intact source geometry, walls, lanes or forbidden edges: %s" % [unsafe.slice(0, 8)])
	print("COIN_EMITTER_SUMMARY: ", JSON.stringify({"max_center_distance_xz": max_emitter_distance,
		"max_source_rect_clearance_xz": max_emitter_clearance, "max_drop_elapsed_us": max_drop_elapsed_us, "displaced": displaced_emitters,
		"scope": "observed emission positions before physics; elapsed_us covers only actual drop_coins, excluding state copy, print and frame waits; no new acceptance bound"}))
	print("INFO: environment coins %d; boundary/blocked sources emitting no coins %s" % [total, zero])
	# The old shared cap must cover environment and the original base objects together.
	coins.reset()
	bk.coin_drops.clear()
	var reward = 0
	for b in bk.objects:
		b.coins_at = -INF
		reward += bk.drop_coins(b, &"car")
	check(reward == Breakables.COIN_WINDOW_CAP, "environment and original objects share the same global coin-window cap")
	coins.reset()
	bk.reset_positions()

func _coin_witness(b) -> Vector3:
	var inward: Vector2 = (Layout.BOUNDS.get_center() - b.center).normalized()
	var radius: float = maxf(b.size.x, b.size.z) * 0.5 + 2.0
	for angle in [0.0, PI / 4, -PI / 4, PI / 2, -PI / 2, PI * 3 / 4, -PI * 3 / 4, PI]:
		var direction = inward.rotated(angle)
		var point: Vector2 = b.center + direction * radius
		if not Layout.BOUNDS.grow(-0.5).has_point(point): continue
		var query = PhysicsShapeQueryParameters3D.new()
		var shape = CapsuleShape3D.new()
		shape.radius = 0.4
		shape.height = 1.5
		query.shape = shape
		query.collision_mask = world.player.collision_mask
		query.exclude = [world.player.get_rid(), world.car.get_rid()]
		query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, 0.8, point.y))
		if world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return Vector3(point.x, 0, point.y)
	return Vector3.INF

func _layout_coin(p: Vector3) -> bool:
	return Layout.COIN_POINTS.any(func(q): return Vector2(p.x - q.x, p.z - q.z).length() < 0.2)

# Select the rendered contact line by arena geometry, even when its owner registry is empty.
# Empty/misassigned ownership must not exclude the very wire this acceptance is meant to test.
func _wire_geometry(from: Vector3, to: Vector3, batch: String, ends_only := false) -> Array:
	var out = []
	var dir = (to - from).normalized()
	var length = from.distance_to(to)
	for node in geo.find_children("*", "MultiMeshInstance3D", true, false):
		var name_text = String(node.name)
		var selected = false
		if batch == "Wires":
			selected = name_text == "Wires"
		else:
			selected = name_text == "Env_%s" % batch or name_text.begins_with("EnvNear_%s_" % batch)
		if not selected or node.multimesh == null: continue
		var mm: MultiMesh = node.multimesh
		for i in mm.instance_count:
			var original = mm.get_instance_transform(i)
			var xf: Transform3D = node.global_transform * original
			var point: Vector3 = xf.origin
			if ends_only:
				if minf(point.distance_to(from), point.distance_to(to)) > 0.45: continue
				if xf.basis.y.length() > 0.31: continue
			else:
				var along = (point - from).dot(dir)
				if along < 0.0 or along > length: continue
				if point.distance_to(from + dir * along) > 0.4: continue
				if batch == "Wires" and absf(xf.basis.y.normalized().dot(dir)) < 0.95: continue
			out.append([node, mm, i, original, node.visible])
	return out

func _wire_hidden(records: Array) -> bool:
	return not records.is_empty() and records.all(func(record): return is_zero_approx(record[1].get_instance_transform(record[2]).basis.determinant()))

func _wire_original(records: Array) -> bool:
	return not records.is_empty() and records.all(func(record): return record[0].visible == record[4] and record[1].get_instance_transform(record[2]).is_equal_approx(record[3]))

func _longitudinal_wires() -> void:
	var spans = Layout.a_spans()
	if not check(spans.size() >= 4 and Layout.B_SPANS.size() >= 3, "real A and ring suspension spans are available"): return
	# A longitudinal contact segment lies over the road; its ends are not pole coordinates.
	var a_z: float = Layout.RING[0].z - geo.WIRE_PAIR
	var b_x: float = Layout.RING[0].x - geo.WIRE_PAIR
	var cases = [
		["A", Vector3(spans[1], geo.CONTACT_Y, a_z), Vector3(spans[2], geo.CONTACT_Y, a_z), spans[1], Layout.RING[0].z, true],
		["ring B", Vector3(b_x, geo.CONTACT_Y, Layout.B_SPANS[1]), Vector3(b_x, geo.CONTACT_Y, Layout.B_SPANS[2]), Layout.B_SPANS[1], Layout.RING[0].x, false],
	]
	for scenario in cases:
		bk.reset_positions()
		var poles = []
		for entry in entries:
			var source: String = solids[entry[6]][0]
			if source not in ["StreetLamp", "TrolleyPole"]: continue
			var center: Vector2 = entry[2]
			var same_span = absf(center.x - scenario[3]) < 0.1 if scenario[5] else absf(center.y - scenario[3]) < 0.1
			var across_road = absf(center.y - scenario[4]) if scenario[5] else absf(center.x - scenario[4])
			if same_span and across_road < 15.0: poles.append(bk.get_by_id(entry[0]))
		if not check(poles.size() == 2, "%s contact segment resolves to the two real transverse support poles" % scenario[0]): continue
		var support = poles[0]
		var from: Vector3 = scenario[1]
		var to: Vector3 = scenario[2]
		var contact = _wire_geometry(from, to, "Wires")
		var frost = _wire_geometry(from, to, "wire_snow")
		var cross_from = Vector3(poles[0].center.x, geo.SPAN_Y, poles[0].center.y)
		var cross_to = Vector3(poles[1].center.x, geo.SPAN_Y, poles[1].center.y)
		# Longitudinal contact spans have no twist by design (sag 0.22); the actual transverse suspension has both twists.
		var twist = _wire_geometry(cross_from, cross_to, "rod", true)
		check(contact.size() >= 8, "%s selects the complete rendered longitudinal contact span independently of owners" % scenario[0])
		check(not frost.is_empty(), "%s contact span has actual rendered frost pieces" % scenario[0])
		check(not twist.is_empty(), "%s transverse support has actual rendered twist/insulator pieces" % scenario[0])
		var unrelated = []
		var wires: MultiMeshInstance3D = geo.get_node("Wires")
		for i in wires.multimesh.instance_count:
			var xf = wires.multimesh.get_instance_transform(i)
			var center: Vector3 = wires.global_transform * xf.origin
			if Vector2(center.x, center.z).distance_to(support.center) > 60.0:
				unrelated.append([wires, wires.multimesh, i, xf, wires.visible])
				break
		check(not unrelated.is_empty(), "%s has an unrelated real wire as a selective-damage control" % scenario[0])
		support.smash(&"test", Vector3.RIGHT)
		support.restore_left = 10000.0
		await _frames(240)
		check(_wire_hidden(contact), "%s longitudinal contact line disappears when its transverse support falls" % scenario[0])
		check(_wire_hidden(frost), "%s contact-line frost cannot float without the supported line" % scenario[0])
		check(_wire_hidden(twist), "%s suspension twists cannot float after their support breaks" % scenario[0])
		check(_wire_original(unrelated), "%s destruction preserves the unrelated wire exactly" % scenario[0])
		_away()
		support.restore_left = 0.0
		await _frames(50)
		check(support.is_intact(), "%s support completes ordinary safe restoration" % scenario[0])
		check(_wire_original(contact) and _wire_original(frost) and _wire_original(twist), "%s safe restoration restores the exact contact, frost and twist geometry" % scenario[0])
		check(_wire_original(unrelated), "%s recovery still preserves unrelated wire geometry" % scenario[0])
	bk.reset_positions()

# A released reservation is a lost resource, even if the same spot later becomes intact again.
func _knock_reacquires_reservation() -> void:
	var actor: Resident = residents.residents[20]
	var newcomer: Resident = residents.residents[21]
	var spot: StringName = &"hockey_w"
	for occupied in [true, false]:
		actor._act_stop()
		newcomer._act_stop()
		bk.reset_positions()
		life.reset()
		if not check(life.spots[spot].cap == 1, "knock/resume fixture uses a real capacity-one hockey place"): continue
		_at_activity(actor, spot)
		check(actor.is_playing(&"hockey") and life.reserved.get(spot, []).has(actor), "the original hockey player starts with a real reservation")
		world.car.global_position = actor.global_position + Vector3(0, 0, 2.0)
		world.car.velocity = Vector3(0, 0, -5.0)
		actor.knock()
		world.car.velocity = Vector3.ZERO
		_away()
		check(actor.knock_phase == &"fly" and not actor._resume_act.is_empty(), "real knock records the resumable activity through the component API")
		var pos: Vector3 = life.spots[spot].pos
		var support = _pick(["PropRinkBoard"], Vector2(pos.x, pos.z))
		if not check(support != null, "the knocked hockey place has an actual breakable rink support"): continue
		support.smash(&"test", Vector3.RIGHT)
		support.restore_left = 10000.0
		check(not life.anchor_intact(spot) and life.reserved.get(spot, []).is_empty(), "breaking the support releases even the knocked player's reservation immediately")
		await _frames(240)
		support.restore_left = 0.0
		await _frames(50)
		check(support.is_intact() and life.anchor_intact(spot), "the support regrows before the knocked player finishes returning")
		if occupied:
			_at_activity(newcomer, spot)
			check(newcomer.is_playing(&"hockey") and life.reserved.get(spot, []) == [newcomer], "a different real resident claims the restored capacity-one place")
		# Run the actual flight/down/get-up/return transitions; never inject the saved activity or call resume directly.
		for i in 2400:
			actor.clock += 1.0 / 60.0
			actor._tick_knock(1.0 / 60.0)
			if actor.knock_phase == &"": break
		check(actor.knock_phase == &"", "the actual knock recovery reaches its completion boundary")
		var owners: Array = life.reserved.get(spot, [])
		check(owners.size() <= 1, "knock recovery never overbooks a capacity-one place")
		if occupied:
			check(owners == [newcomer] and newcomer.is_playing(&"hockey"), "returning from knock preserves the new reservation owner")
			check(not actor.is_playing(&"hockey"), "a stale saved activity cannot resume at a place now owned by another resident")
		else:
			check(owners == [actor] and actor.is_playing(&"hockey"), "a free restored place resumes only after the returning resident reacquires its reservation")
		check(not actor.is_playing(&"hockey") or owners.has(actor), "every resumed hockey activity has a current reservation, never only a saved spot id")
	actor._act_stop()
	newcomer._act_stop()
	life.reset()
	bk.reset_positions()
	_away()

# The reward source is ignorable only after it actually stops being a solid obstacle.
func _dent_coin_landing() -> void:
	bk.reset_positions()
	var coins = geo.get_node("Coins")
	coins.reset()
	var car = _pick(["ParkedCar"], Layout.LIFE_HOOD_CAR)
	if not check(car != null and car.center.distance_to(Layout.LIFE_HOOD_CAR) < 0.1, "dent coin scenario uses the real courtyard parked car, away from road/kiosk exclusions"): return
	world.player.position = car.global_ground() + Vector3(car.size.x * 0.5 + 0.8, 0, 0)
	# Use the component's actual heavy-punch lifecycle: the third punch emits its real loose reward.
	for i in 3: car.punch(Vector3.LEFT)
	car.restore_left = 10000.0
	_away()
	var loose = await _settled_loose_positions(coins, Breakables.coin_count(car.kind, car.heavy), "punched dent reward")
	check(car.state == &"broken" and car.mode == &"dent" and car.blocks() and car.last_by == &"punch", "the punched parked car is actually dented, paid and still physically solid")
	var interior: Vector3 = car.body.global_transform * Vector3(0, car.size.y * 0.5, 0)
	check(_point_hits_body(interior, car), "the callback witness is inside the actual current dent collider")
	check(not bk.coin_spot_ok(interior, car), "the real reward callback rejects the still-solid source car itself")
	check(loose.size() == Breakables.coin_count(car.kind, car.heavy), "the third punch emitted the real configured loose reward before landing validation")
	var unsafe = []
	var solid: Rect2 = car.rect()
	for point: Vector3 in loose:
		if solid.has_point(Vector2(point.x, point.z)) or _point_hits_body(point, car): unsafe.append(point)
	check(unsafe.is_empty(), "actual punch coins land outside their own still-solid crushed car: %s" % [unsafe])
	# Positive control: a shattered pavilion loses its body, so the former source footprint is usable.
	bk.reset_positions()
	coins.reset()
	var pavilion = _pick(["BusPavilion"])
	if check(pavilion != null, "a real nonblocking destroyed owner is available as the callback control"):
		for i in 3: pavilion.punch(Vector3.RIGHT)
		pavilion.restore_left = 10000.0
		await _frames(2)
		var former_interior: Vector3 = pavilion.global_ground() + Vector3.UP * 0.7
		check(not pavilion.blocks() and not _point_hits_body(former_interior, pavilion), "the positive-control source really lost its physical body")
		check(bk.coin_spot_ok(former_interior), "the former pavilion interior satisfies every unrelated landing constraint")
		check(bk.coin_spot_ok(former_interior, pavilion), "the actual callback permits a source footprint once that source no longer blocks")
	coins.reset()
	bk.reset_positions()
	_away()

func _point_hits_body(point: Vector3, b) -> bool:
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.02
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1 | 32
	return world.get_world_3d().direct_space_state.intersect_shape(query, 32).any(func(hit): return hit.collider == b.body)

# Independent publication controls: a denied fallback must not emit, a legal vertical fallback must still emit.
func _coin_allowed_fallback_controls() -> void:
	var coins = geo.get_node("Coins")
	coins.reset()
	_away()
	var safe = Vector3.INF
	for i in coins._fixed:
		var candidate: Vector3 = coins._origin[i]
		if not bk.coin_spot_ok(candidate): continue
		var query = PhysicsShapeQueryParameters3D.new()
		var shape = SphereShape3D.new()
		shape.radius = 0.1
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, candidate)
		query.collision_mask = 1 | 4 | 32 | 64
		if world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			safe = candidate
			break
	if not check(safe.is_finite(), "coin guard controls use an existing legal fixed-coin point in the actual scene"): return
	var start = safe + Vector3.UP * 0.8
	var requested = 3
	var pool_size: int = coins._state.size()
	var original_loose = coins._state.slice(coins._fixed)
	var denied_calls = [0]
	var deny_all = func(_point: Vector3) -> bool:
		denied_calls[0] += 1
		return false
	var denied: int = coins.spawn_burst(start, requested, deny_all)
	check(denied_calls[0] > 0, "the denied-drop control reaches its actual allowed predicate with valid input and free pool slots")
	check(denied == 0, "an always-false allowed predicate rejects every publication, including vertical fallback")
	check(coins._state.size() == pool_size and coins._state.slice(coins._fixed) == original_loose,
		"a rejected drop leaves the actual loose pool unchanged, with no hidden emitted slots")
	coins.reset()
	var vertical_only = func(point: Vector3) -> bool:
		return Vector2(point.x - safe.x, point.z - safe.z).length() < 0.005 and absf(point.y - safe.y) < 0.005
	var made: int = coins.spawn_burst(start, requested, vertical_only)
	check(made == requested, "a legal vertical-only fallback emits the entire requested reward through actual Coins")
	var landed = await _settled_loose_positions(coins, requested, "vertical-only fallback control")
	check(landed.size() == requested and landed.all(vertical_only), "the real positive-control cohort reaches IDLE only at its allowed vertical landing")
	check(coins._state.size() == pool_size, "fallback controls preserve the configured real coin pool size")
	coins.reset()
	_away()

# Geometry is a landing oracle: capture emitted loose slots and observe their real AIR -> IDLE boundary.
# The provider's own LOOSE_LIFETIME bounds survival; disappearance/collection is a failure, never settlement.
func _settled_loose_positions(coins, expected: int, context: String) -> Array[Vector3]:
	var cohort: Array[int] = []
	for i in range(coins._fixed, coins._state.size()):
		if coins._state[i] != CoinStates.GONE: cohort.append(i)
	if not check(cohort.size() == expected, "%s captures exactly its emitted loose slots (%d/%d)" % [context, cohort.size(), expected]): return []
	var pending = true
	while pending:
		pending = false
		for i in cohort:
			var state: int = coins._state[i]
			if state not in [CoinStates.AIR, CoinStates.IDLE] or coins._age[i] >= CoinStates.LOOSE_LIFETIME:
				check(false, "%s loose slot %d left the uncollected landing lifecycle (state %d, age %.3f)" % [context, i, state, coins._age[i]])
				return []
			pending = pending or state != CoinStates.IDLE
		if pending: await physics_frame
	var positions: Array[Vector3] = []
	for i in cohort: positions.append(coins._pos[i])
	return positions

func _frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	if main != null:
		for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): player.stop()
		main.queue_free()
	await _frames(5)
	print("BREAK03_ACCEPTANCE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

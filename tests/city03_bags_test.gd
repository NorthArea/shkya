extends SceneTree
## CITY-03: пакеты в настоящем мире; декоративный ветер не толкает игрока и не реагирует на телепортации.

const Layout = preload("res://game/world/layout.gd")

var checks := 0
var failures: Array[String] = []
var main: Node
var world: DemoWorld
var wind: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	wind = world.get_node_or_null("LevelGeometry/WindBags")
	if not check(wind != null, "wind bags are connected to the playable city"):
		await _finish()
		return
	wind.set_physics_process(false)
	world.player.set_physics_process(false)
	world.car.set_physics_process(false)
	for sensor in get_nodes_in_group(&"detection_sensors"):
		sensor.enabled = false
	check(wind.bags.size() == 1, "exactly one bag lives in the playable city")
	var kinds := {}
	for bag in wind.bags:
		kinds[bag.kind] = true
		check(bag.look.mesh != null and bag.look.material_override != null, "%s has a mesh and material" % bag.name)
	check(kinds.size() == 1 and kinds.has(&"plan_white"), "the only bag uses the approved white menu design")
	var arrays: Array = wind.bags[0].look.mesh.surface_get_arrays(0)
	var faces := {}
	for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
		faces[signf(normal.z)] = true
	var all_colors_valid := true
	for color: Color in arrays[Mesh.ARRAY_COLOR]:
		all_colors_valid = all_colors_valid and color.r >= 0.0 and color.r <= 1.0
	check(faces.has(1.0) and faces.has(-1.0), "bag has front and back surfaces with opposite normals")
	check(all_colors_valid, "bag vertex colors fit the mesh color format")
	check(wind.find_children("*", "CollisionObject3D", true, false).is_empty(), "bags add no physical obstacles or stealth occluders")
	check(wind.rustle.stream != null and wind.rustle.volume_db <= -9.0, "local rustle stays below the quest sound level")
	_starting_courtyard()
	_no_camera_warp()
	_stationary_player()
	_walking_player()
	_teleported_car()
	_moving_car()
	_wind_and_bounds()
	_snag_and_release()
	await _people_attachment()
	await _finish()

func _starting_courtyard() -> void:
	var spawn := Vector2(Layout.SPAWN.x, Layout.SPAWN.z)
	for point: Vector2 in Layout.WIND_BAG_SOURCES:
		check(point.distance_to(spawn) <= 12.0, "bag recovery stays in the starting courtyard")
	var bag = wind.bags[0]
	var lighting: Node = wind._lighting
	# Advance the real controller through its fallback gust cycle without frame waits.
	wind._lighting = null
	var max_radius := 0.0
	var max_height := 0.0
	var jumped := false
	for frame in 7200:
		var before: Vector3 = bag.position
		var was_seen: bool = wind._seen(before)
		wind._physics_process(1.0 / 60.0)
		var radius := Vector2(bag.position.x, bag.position.z).distance_to(spawn)
		max_radius = maxf(max_radius, radius)
		max_height = maxf(max_height, bag.position.y - wind.ground_at(bag.position))
		if was_seen and bag.visible and wind._seen(bag.position) and before.distance_to(bag.position) > 0.8:
			jumped = true
		if frame in [1799, 7199]:
			check(bag.visible and radius <= 12.0, "bag remains near Ilyusha after %d seconds" % [(frame + 1) / 60])
	wind._lighting = lighting
	check(max_radius <= 12.0, "ordinary wind keeps bag in starting courtyard (%.2f m)" % max_radius)
	check(max_height <= 3.2, "ordinary flight remains low (%.2f m)" % max_height)
	check(not jumped, "local wind causes no visible reset jump")

func _people_attachment() -> void:
	var player := world.player
	player.place(Layout.SPAWN, 0.0)
	player.visual.rotation.y = 0.0
	var bag = _contact_person(player)
	if check(bag != null, "wind can stick a passing bag to Ilyusha's coat"):
		wind._snagged(bag, Vector3(2, 0, 0), 0.0, 1.0 / 60.0)
		var local_anchor: Vector3 = player.visual.to_local(bag.snag_point)
		check(bag.snag_point.y < player.global_position.y + 1.5, "bag attaches below Ilyusha's face")
		player.position += Vector3(1.0, 0, 0)
		player.visual.rotation.y = PI * 0.5
		wind._snagged(bag, Vector3(2, 0, 0), 0.0, 1.0 / 60.0)
		check(bag.snag_point.distance_to(player.visual.to_global(local_anchor)) < 0.01, "attached bag follows Ilyusha's movement and turn")
		for i in 480:
			if bag.state != &"snag":
				break
			wind.clock += 1.0 / 60.0
			wind._snagged(bag, Vector3(4, 0, 1), 1.0, 1.0 / 60.0)
		check(bag.state == &"fly" and bag.get("snag_target") == null and bag.velocity.y > 0.0, "a gust peels the bag off the coat")
	var residents: Node = world.get_node("LevelGeometry/Residents")
	var resident: Resident = residents.residents.filter(func(person): return person.visible and not person.hidden)[0]
	resident.set_physics_process(false)
	resident.position = Layout.SPAWN + Vector3(12, 0, -8)
	resident.visual.position = Vector3(0, -0.4, 0)
	bag = _contact_person(resident)
	if check(bag != null, "wind can stick a passing bag to a resident's coat"):
		wind._snagged(bag, Vector3(2, 0, 0), 0.0, 1.0 / 60.0)
		var before_y: float = bag.snag_point.y
		resident.visual.position.y = 0.0
		wind._snagged(bag, Vector3(2, 0, 0), 0.0, 1.0 / 60.0)
		check(is_equal_approx(bag.snag_point.y - before_y, 0.4), "bag follows the resident's visible body when standing up")
		for i in 1500:
			if bag.state != &"snag":
				break
			wind.clock += 1.0 / 60.0
			wind._snagged(bag, Vector3(1, 0, 0), 0.0, 1.0 / 60.0)
		check(bag.state == &"fly" and bag.get("snag_target") == null, "coat attachment has a time limit even without a gust")
	bag = _contact_person(resident)
	if check(bag != null, "resident can encounter the same bag later"):
		resident.hide()
		wind._snagged(bag, Vector3(2, 0, 0), 0.0, 1.0 / 60.0)
		check(bag.state == &"fly" and bag.visible, "bag stays in the street when its wearer disappears indoors")
		resident.show()
	bag = _contact_person(player)
	if check(bag != null, "Ilyusha can encounter the same bag later"):
		world.enter_car()
		wind._snagged(bag, Vector3(2, 0, 0), 0.0, 1.0 / 60.0)
		check(bag.state == &"fly" and bag.get("snag_target") == null, "entering the Lada releases the bag")
		world.exit_car()
	bag = _contact_person(resident)
	if check(bag != null, "resident can catch a bag before leaving the scene"):
		var parent := resident.get_parent()
		parent.remove_child(resident)
		wind._snagged(bag, Vector3(2, 0, 0), 0.0, 1.0 / 60.0)
		check(bag.state == &"fly" and bag.position.is_finite(), "losing the wearer releases the bag safely")
		parent.add_child(resident)
	check(wind.find_children("*", "CollisionObject3D", true, false).is_empty(), "coat attachments add no colliders or movement restrictions")
	await _frames(1)

func _contact_person(person: Node3D):
	for attempt in 12:
		wind.clock += 1.0
		for candidate in wind.bags:
			candidate.state = &"fly"
			candidate.show()
			candidate.hidden_wait = 0.0
			candidate.snag_on_person = false
			candidate.snag_target = null
			candidate.last_person = null
			candidate.last_snag = -1
			candidate.position = person.visual.to_global(Vector3(0.3, 1.05, -0.05))
			candidate.velocity = Vector3(2, 0, 0)
			wind._try_snag(candidate)
			if candidate.state == &"snag" and candidate.get("snag_target") == person:
				return candidate
	return null

func _no_camera_warp() -> void:
	var continuous := true
	var thresholds: Array[float] = []
	for bag in wind.bags:
		thresholds.append(bag.liftoff_gust)
		bag.state = &"rest"
		bag.rest_left = 100.0
		bag.liftoff_gust = 2.0
	for i in 180:
		var positions: Array[Vector3] = []
		for bag in wind.bags:
			positions.append(bag.position)
		wind._physics_process(1.0 / 60.0)
		for k in wind.bags.size():
			var bag = wind.bags[k]
			if wind._seen(bag.position) and bag.position.distance_to(positions[k]) > 3.0:
				continuous = false
	for k in wind.bags.size():
		wind.bags[k].liftoff_gust = thresholds[k]
	check(continuous, "bags follow the wind continuously when entering the player's view")

func _stationary_player() -> void:
	var player := world.player
	player.place(Layout.SPAWN, 0.0)
	player.velocity = Vector3.ZERO
	wind._track_movers(1.0 / 60.0)
	wind._track_movers(1.0 / 60.0)
	var bag = wind.bags[0]
	wind._put_down(bag, player.global_position + Vector3(0.35, 0, 0), 0.0)
	bag.hit_cooldown = 0.0
	var before: int = wind.hits[&"player"]
	wind._react(bag, wind._movers())
	check(wind.hits[&"player"] == before and bag.state == &"rest", "standing beside a bag does not kick it")

func _walking_player() -> void:
	var player := world.player
	player.velocity = Vector3(2.0, 0, 0)
	player.position += player.velocity / 60.0
	wind._track_movers(1.0 / 60.0)
	var bag = wind.bags[0]
	wind._put_down(bag, player.global_position + Vector3(0.35, 0, 0), 0.0)
	bag.hit_cooldown = 0.0
	var before: int = wind.hits[&"player"]
	wind._react(bag, wind._movers())
	check(wind.hits[&"player"] == before + 1 and bag.velocity.y > 0.0, "walking into a bag throws it up")
	player.velocity = Vector3.ZERO
	player.position = Layout.SPAWN

func _teleported_car() -> void:
	var car := world.car
	car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	wind._track_movers(1.0 / 60.0)
	car.reset_to(Layout.CAR_SPAWN + Vector3(20, 0, 0), Layout.CAR_SPAWN_YAW)
	wind._track_movers(1.0 / 60.0)
	var bag = wind.bags[0]
	wind._put_down(bag, car.global_position, 0.0)
	bag.hit_cooldown = 0.0
	var before: int = wind.hits[&"car"]
	wind._react(bag, wind._movers())
	check(wind.hits[&"car"] == before, "resetting the car does not launch nearby bags at teleport speed")

func _moving_car() -> void:
	var car := world.car
	car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	wind._track_movers(1.0 / 60.0)
	car.velocity = -car.global_basis.z * 5.0
	car.position += car.velocity / 60.0
	wind._track_movers(1.0 / 60.0)
	var bag = wind.bags[0]
	wind._put_down(bag, car.global_position - car.global_basis.z, 0.0)
	bag.hit_cooldown = 0.0
	var before: int = wind.hits[&"car"]
	wind._react(bag, wind._movers())
	check(wind.hits[&"car"] == before + 1 and bag.velocity.y > 0.0, "a passing Lada blows a bag aside")
	check(bag.velocity.length() < 20.0, "bag reacts at street speed")
	car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)

func _wind_and_bounds() -> void:
	var black = wind.bags[0]
	var original_weight: float = black.weight
	black.weight = 1.6
	wind._put_down(black, Vector3(15, 0, 32), 0.0)
	black.rest_left = 0.0
	black.liftoff_gust = 0.8
	wind._rest(black, Vector3(4, 0, 1), 1.0, 1.0 / 60.0)
	check(black.state == &"fly", "even a temporarily weighted bag can lift in a strong gust")
	black.weight = original_weight
	var bag = wind.bags[0]
	wind._put_down(bag, Vector3(15, 0, 32), 0.0)
	bag.rest_left = 0.0
	var start: Vector3 = bag.position
	wind._rest(bag, Vector3(3, 0, 1), 1.0, 1.0 / 60.0)
	check(bag.state == &"fly" and bag.velocity.y > 0.0, "a strong gust lifts a resting bag")
	for i in 120:
		wind.clock += 1.0 / 60.0
		wind._fly(bag, Vector3(3, 0, 1), 1.0 / 60.0)
	check(bag.position.distance_to(start) > 1.0, "a flying bag travels through the street")
	check(bag.position.is_finite() and bag.position.y >= wind.ground_at(bag.position) - 0.01, "bag stays finite and above the snow")
	bag.position = Vector3(1000, 2, 1000)
	for i in 180:
		wind._bounds(bag, Vector3(3, 0, 1), 1.0 / 60.0)
	check(Layout.BOUNDS.has_point(Vector2(bag.position.x, bag.position.z)) or not bag.visible, "bag returns to the city off screen within three seconds")

func _snag_and_release() -> void:
	var bag = wind.bags[0]
	bag.state = &"fly"
	bag.last_snag = -1
	for point in wind._snag_points:
		bag.position = point[0] + Vector3.UP * 0.1
		wind._try_snag(bag)
		if bag.state == &"snag":
			break
	check(bag.state == &"snag", "a bag catches on a real tree, post or fence")
	if bag.state != &"snag":
		return
	var anchor: Vector3 = bag.snag_point
	wind._snagged(bag, Vector3(3, 0, 1), 0.0, 1.0 / 60.0)
	check(bag.position.distance_to(anchor) < 1.0, "a snagged bag flaps close to its anchor")
	for i in 1200:
		if bag.state != &"snag":
			break
		wind._snagged(bag, Vector3(3, 0, 1), 0.0, 1.0 / 60.0)
	check(bag.state == &"fly" and bag.velocity.y > 0.0, "a snagged bag eventually pulls free")

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish() -> void:
	for player in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
	main.queue_free()
	await _frames(5)
	OS.delay_msec(100)
	await process_frame
	print("CITY03_BAGS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

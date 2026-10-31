extends SceneTree
## Native WORLD-02 evidence in the production world. Run only after warning the owner.
## tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/world02_damage.gd
## Boundary contact uses the real Lada collider swept by move_and_collide; damage uses
## ordinary Lada physics + car_gas input. No direct impact, dent or alarm callbacks.

const Layout = preload("res://game/world/layout.gd")
const Damage = preload("res://game/vehicles/vehicle_damage.gd")
const MAX_IMPACT_FRAMES := 240
var output := "res://builds/screenshots/WORLD-02/native"
var main: Node
var world: DemoWorld
var camera: Camera3D
var bk: Breakables
var parked: Breakables.Breakable
var shots: Array[Dictionary] = []
var events: Array[Dictionary] = []
var failures: Array[String] = []
var impacted := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("WORLD02 native image capture requires a real renderer")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	output = ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create WORLD02 capture directory")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	AudioServer.set_bus_mute(0, true)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	await _frames(12)
	world = main.world
	bk = world.get_node("LevelGeometry/Breakables")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera = Camera3D.new()
	camera.fov = world.camera_rig.camera.fov
	camera.far = world.camera_rig.camera.far
	root.add_child(camera)
	world.car.set_physics_process(false)
	# Sample the actual Layout walls in the requested sectors, without new geometry.
	var north: Array = []
	var south: Array = []
	for wall: Array in Layout.PERIMETER_WALLS:
		var a: Vector2 = wall[0]
		var b: Vector2 = wall[1]
		if not is_equal_approx(a.y, b.y): continue
		if a.y < Layout.BOUNDS.position.y + 2.0: north = wall
		if a.y > Layout.BOUNDS.end.y - 2.0: south = wall
	if north.is_empty() or south.is_empty():
		failures.append("Missing canonical north/south boundary wall")
	else:
		await _boundary("a1_north", north, 0.10, Vector3.FORWARD)
		await _boundary("g5_south", south, 0.34, Vector3.BACK)
		await _boundary("d5_south", south, 0.80, Vector3.BACK)
	await _signs()
	await _damage_collision()
	# No lighting changes: the occupied Lada's normal headlights face a real wall.
	if not north.is_empty(): await _headlight_wall(north)
	_release_input()
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if manifest:
		manifest.store_string(JSON.stringify({"scope": "production world native frames; independent visual review required",
			"boundary_scope": "real Lada collider sweep + production camera; not a manual driving acceptance",
			"damage_scope": "ordinary Lada physics with input; initial fixture placement only",
			"unchanged": "world lights/exposure, NPCs, sensors, source geometry and collision behavior",
			"source_sha256": {"layout": FileAccess.get_sha256("res://game/world/layout.gd"),
				"breakables": FileAccess.get_sha256("res://game/world/breakables.gd"),
				"impact": FileAccess.get_sha256("res://game/vehicles/vehicle_impact.gd"),
				"damage": FileAccess.get_sha256("res://game/vehicles/vehicle_damage.gd")},
			"shots": shots, "events": events, "failures": failures}, "\t"))
	else:
		failures.append("Cannot write capture manifest")
	main.queue_free()
	camera.queue_free()
	await _frames(4)
	print("WORLD02_DAMAGE_CAPTURE: %d images, %d failures; images require independent review" % [shots.size(), failures.size()])
	for failure in failures: push_error("WORLD02_CAPTURE: " + failure)
	quit(0 if failures.is_empty() else 1)

func _boundary(label: String, wall: Array, fraction: float, outward: Vector3) -> void:
	var a: Vector2 = wall[0]
	var b: Vector2 = wall[1]
	var p := a.lerp(b, fraction)
	var surface := Vector3(p.x, 0, p.y)
	var start := surface - outward * 7.0 + Vector3.UP * 0.05
	var yaw := atan2(-outward.x, -outward.z)
	world.car.reset_to(start, yaw)
	await _foot(label + "_game_camera", start + Vector3.RIGHT * 3.0, surface + Vector3.UP * 1.4)
	var before := world.car.global_transform
	var collision: KinematicCollision3D = world.car.move_and_collide(outward * 10.0)
	var evidence := {"event": label, "method": "actual Lada move_and_collide sweep", "start": str(before),
		"final": str(world.car.global_transform), "wall_endpoints": [str(a), str(b)], "hit": collision != null}
	if collision:
		var collider := collision.get_collider() as Node
		evidence["collider"] = str(collider.get_path()) if collider else "null"
		evidence["position"] = str(collision.get_position())
		evidence["normal"] = str(collision.get_normal())
		if collider == null or not str(collider.name).begins_with("PerimeterWall"):
			failures.append(label + " sweep hit another object before the requested visible wall")
	else:
		failures.append(label + " Lada crossed the requested wall without contact")
	events.append(evidence)
	world.camera_rig.follow(world.car, &"in_car")
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	world.camera_rig.camera.make_current()
	await _frames(12)
	await _save(label + "_car_contact", "production in-car camera; real collider stopped by sweep")
	await _detail(label + "_wall_detail", surface - outward * 5.0 + Vector3(2.0, 1.65, 0), surface + Vector3.UP * 1.55)

func _signs() -> void:
	var sign: Array = Layout.STREET_SIGNS[1]
	var at: Vector2 = sign[0]
	var subject := Vector3(at.x, 2.7, at.y)
	await _foot("lenin_bogatkova_game_camera", Vector3(at.x + 5.0, 0, at.y + 6.0), subject)
	await _detail("lenin_bogatkova_sign_detail", subject + Vector3(4.2, 0, 4.2), subject)
	for i in Layout.PERIMETER_WARNINGS.size():
		var spec: Array = Layout.PERIMETER_WARNINGS[i]
		var p: Vector2 = spec[0]
		var yaw: float = spec[1]
		var face := Vector3(sin(yaw), 0, cos(yaw))
		var target := Vector3(p.x, 2.9, p.y)
		await _foot("warning_%d_approach" % i, Vector3(p.x, 0, p.y) + face * 10.0, target)
		await _detail("warning_%d_reverse" % i, target - face * 7.0 + Vector3.UP * 0.3, target)

func _damage_collision() -> void:
	for candidate: Breakables.Breakable in bk.env_objects:
		if candidate.id == &"Zhiguli_A": parked = candidate
	if parked == null or parked.parked_visual == null:
		failures.append("Actual Zhiguli_A is missing")
		return
	var visual := parked.parked_visual
	var mesh := visual.get_node("Body/BodyMesh") as MeshInstance3D
	var original_mesh: Mesh = mesh.mesh
	var original_body := parked.body.global_transform
	var original_visual := visual.global_transform
	var at := parked.body.global_position
	# A northbound ordinary Lada hits the south side off centre; no injected event.
	var start := at + Vector3(1.15, 0.05, 7.2)
	world.car.reset_to(start, 0.0)
	world.player.place(start + Vector3.RIGHT * 2.5, 0.0)
	world.car.set_physics_process(true)
	world.enter_car()
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	var eye := at + Vector3(5.4, 2.65, 5.2)
	var look := at + Vector3(0.6, 0.75, 0)
	await _detail("parked_before_quarter", eye, look)
	var initial_serial := int(parked.body.get_meta("vehicle_impact_serial", 0))
	var trail: Array[Dictionary] = []
	Input.action_press(&"car_gas")
	for frame in MAX_IMPACT_FRAMES:
		await physics_frame
		if frame % 6 == 0: trail.append(_vehicle_state("drive_%d" % frame))
		if int(parked.body.get_meta("vehicle_impact_serial", 0)) > initial_serial:
			impacted = true
			break
	_release_input()
	world.car.set_physics_process(false)
	var collision_contacts: Array[Dictionary] = []
	for i in world.car.get_slide_collision_count():
		var hit: KinematicCollision3D = world.car.get_slide_collision(i)
		var collider := hit.get_collider() as Node
		collision_contacts.append({"collider": str(collider.get_path()) if collider else "null",
			"point": str(hit.get_position()), "normal": str(hit.get_normal())})
	events.append({"event": "lada_into_actual_parked", "input": "car_gas", "initial_parked_body": str(original_body),
		"initial_parked_visual": str(original_visual), "impact_serial_changed": impacted,
		"contacts": collision_contacts, "trail": trail, "after": _vehicle_state("contact"),
		"damage": _damage_stats(mesh, original_mesh)})
	if not impacted: failures.append("Ordinary driven Lada did not contact Zhiguli_A before timeout")
	if int(visual.get_meta("vehicle_dent_count", 0)) < 1:
		failures.append("Actual collision did not create a private visible parked dent")
	await _detail("parked_after_quarter", eye, look)
	var stats := _damage_stats(mesh, original_mesh)
	if float(stats.get("maximum_displacement", 0.0)) > 0.0:
		var point: Vector3 = stats["world_point"]
		await _detail("parked_actual_dent_close", point + Vector3(1.8, 1.2, 2.8), point)
	# Wait for the existing alarm clock to produce both native lens states.
	var seen := {}
	for frame in 120:
		var material: StandardMaterial3D = visual.get_meta("indicator_material")
		var on := material.emission_energy_multiplier > 0.01
		if not seen.has(on):
			seen[on] = true
			var current := visual.global_position
			await _detail("parked_alarm_" + ("on" if on else "off"), current + Vector3(5.2, 1.9, 4.0), current + Vector3.UP * 0.65, false)
		if seen.size() == 2: break
		await physics_frame
	if not seen.has(true) or not seen.has(false):
		failures.append("Existing alarm did not expose both on/off lens phases")
	events.append({"event": "after_settle", "state": _vehicle_state("settled"),
		"damage": _damage_stats(mesh, original_mesh), "alarm_phases_observed": seen.size()})

func _headlight_wall(wall: Array) -> void:
	var p: Vector2 = (wall[0] as Vector2).lerp(wall[1], 0.10)
	var at := Vector3(p.x, 0, p.y)
	world.car.reset_to(at + Vector3(0, 0.05, 4.6), 0.0)
	# The prior normal enter_car leaves headlights in their production occupied state.
	await _detail("headlight_wall_front", at + Vector3(3.6, 1.6, 5.2), at + Vector3.UP * 0.9)
	await _detail("headlight_wall_reverse", at + Vector3(1.5, 1.6, -5.2), at + Vector3.UP * 0.9)
	var query := PhysicsRayQueryParameters3D.create(world.car.global_position + Vector3.UP * 0.7,
		at + Vector3(0, 0.7, -2), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node
	events.append({"event": "headlight_real_wall", "car": str(world.car.global_transform),
		"occupied": world.car.driver != null, "wall_raycast_collider": str(collider.get_path()) if collider else "null",
		"scope": "opposite wall faces; global lighting unchanged, not an isolated light-off comparison"})

func _foot(label: String, at: Vector3, target: Vector3) -> void:
	var direction := target - at
	var yaw := atan2(-direction.x, -direction.z)
	world.player.place(Vector3(at.x, 0, at.z), yaw)
	world.camera_rig.follow(world.player, &"on_foot")
	world.camera_rig.yaw = yaw
	world.camera_rig.pitch = -0.12
	world.camera_rig.snap()
	world.camera_rig.camera.make_current()
	await _frames(14)
	await _save(label, "production on-foot camera, unmodified collision profile")

func _detail(label: String, eye: Vector3, target: Vector3, settle := true) -> void:
	camera.global_position = eye
	camera.look_at(target)
	camera.make_current()
	if settle: await _frames(6)
	await _save(label, "capture-only detail camera; production world materials and lighting")

func _save(label: String, scope: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output.path_join(label + ".png")
	if image.save_png(path) != OK:
		failures.append("Cannot save " + path)
		return
	var actual: Camera3D = root.get_camera_3d()
	shots.append({"file": label + ".png", "scope": scope, "camera_position": str(actual.global_position),
		"camera_rotation": str(actual.global_rotation), "fov": actual.fov, "size": str(image.get_size()),
		"physics_frame": Engine.get_physics_frames(), "vehicles": _vehicle_state(label)})
	print("WORLD02_CAPTURE: " + path)

func _vehicle_state(label: String) -> Dictionary:
	var state := {"label": label, "lada_position": str(world.car.global_position), "lada_yaw": world.car.global_rotation.y,
		"lada_velocity": str(world.car.velocity), "lada_dents": int(world.car.visual.get_meta("vehicle_dent_count", 0))}
	if parked:
		state["parked_position"] = str(parked.body.global_position)
		state["parked_yaw"] = parked.body.global_rotation.y
		state["parked_visual_transform"] = str(parked.parked_visual.global_transform)
		state["parked_velocity"] = str(parked.parked_velocity)
		state["parked_yaw_velocity"] = parked.parked_yaw_velocity
		state["parked_dents"] = int(parked.parked_visual.get_meta("vehicle_dent_count", 0))
		state["parked_impact_serial"] = int(parked.body.get_meta("vehicle_impact_serial", 0))
		var indicators: StandardMaterial3D = parked.parked_visual.get_meta("indicator_material")
		state["indicator_energy"] = indicators.emission_energy_multiplier
		var others: Array[Dictionary] = []
		for b: Breakables.Breakable in bk.env_objects:
			if b.kind == &"parked" and b != parked and b.parked_visual:
				var material: StandardMaterial3D = b.parked_visual.get_meta("indicator_material")
				others.append({"id": str(b.id), "energy": material.emission_energy_multiplier,
					"material_is_struck_car": material == indicators})
		state["other_parked_indicators"] = others
	return state

func _damage_stats(part: MeshInstance3D, original: Mesh) -> Dictionary:
	var maximum := 0.0
	var changed := 0
	var point := Vector3.ZERO
	for surface in part.mesh.get_surface_count():
		var current: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var before: PackedVector3Array = original.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in current.size():
			var displacement := current[vertex].distance_to(before[vertex])
			if displacement > 0.00001: changed += 1
			if displacement > maximum:
				maximum = displacement
				point = current[vertex]
	return {"mesh_is_private": part.mesh != original, "maximum_displacement": maximum,
		"changed_vertices": changed, "world_point": part.to_global(point)}

func _release_input() -> void:
	for action: StringName in [&"car_gas", &"car_brake", &"handbrake", &"move_left", &"move_right"]:
		Input.action_release(action)

func _frames(count: int) -> void:
	for frame in count: await physics_frame

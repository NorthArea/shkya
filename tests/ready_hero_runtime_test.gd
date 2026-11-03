extends SceneTree
## Paused imported-provider qualification; production runtime is hero2d_runtime_test.
## Explicit fixture enables the retained 3D provider without changing production switches.
const Player = preload("res://game/player/ilyusha.gd")
const Car = preload("res://game/vehicles/lada_visual.gd")
const Inputs = preload("res://game/input_setup.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
const Reader = preload("res://tests/actual_skin_reader.gd")
class ImportedPlayer:
	extends "res://game/player/ilyusha.gd"
	func _build_visual() -> Node3D:
		var result := super._build_visual()
		result.get_node("Look").force_sprite_2d = false
		return result

const FLOOR_EPS := 0.012
## Original source-cycle qualification has an idle head maximum of 15.22 degrees.
const IDLE_HEAD_LIMIT := 20.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("READY_HERO: " + label)

func _run() -> void:
	create_timer(35.0, true, false, true).timeout.connect(func(): quit(2))
	Engine.max_fps = 120
	Inputs.install()
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	fixture.add_child(floor_body)
	var player := ImportedPlayer.new()
	fixture.add_child(player)
	player.place(Vector3.ZERO, 0.0)
	await _step(12)
	var uniform: Node = player.visual.get_node("Look").uniform_visual
	var hero: Node = uniform.imported_hero
	check(hero != null, "actual Player factory provides the ready humanoid backend")
	if hero == null:
		fixture.free()
		_finish()
		return
	check(String(hero.model.scene_file_path).to_lower().contains("quaternius"), "Player displays the qualified upstream scene, not rejected custom mesh")
	check(hero.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual adds no second physics owner")
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	var capsule := collider.shape as CapsuleShape3D
	check(capsule != null and is_equal_approx(capsule.height, Catalog.ILYUSHA_VISIBLE_HEIGHT_M), "physical height retains the fixed Catalog value")
	var readers := _readers(hero, player)
	check(not readers.is_empty(), "ready body has actual skinned geometry")
	var bind_points := _points(readers, true, player)
	check(not bind_points.is_empty() and absf(Reader.bounds(bind_points).size.y - Catalog.ILYUSHA_VISIBLE_HEIGHT_M) <= 0.001, "all source meshes share one correctly normalized bind height")
	var idle_min := INF
	var idle_max := -INF
	var maximum_head_angle := 0.0
	for frame in 24:
		await _step(1)
		var points := _points(readers, false, player)
		check(_finite(points), "final idle skin is finite at sample %d" % frame)
		var bounds := Reader.bounds(points)
		idle_min = minf(idle_min, bounds.position.y)
		idle_max = maxf(idle_max, bounds.position.y)
		var head: int = hero.skeleton.find_bone("Head")
		var frame_basis: Basis = readers[0].final_skeleton_world.basis
		var up: Vector3 = frame_basis * readers[0].bone_global_pose(head).basis.y
		maximum_head_angle = maxf(maximum_head_angle, rad_to_deg(up.normalized().angle_to(Vector3.UP)))
	check(maximum_head_angle <= IDLE_HEAD_LIMIT, "idle retains qualified source posture; head maximum %.3f degrees" % maximum_head_angle)
	check(idle_min >= -FLOOR_EPS and idle_max <= FLOOR_EPS, "constant floor registration keeps idle soles on the floor: %.5f..%.5f" % [idle_min, idle_max])
	var origin: Vector3 = player.global_position
	Input.action_press("move_forward")
	await _step(24)
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()
	check(walk_speed > 0.5 and player.global_position.distance_to(origin) > 0.2, "real input moves the Player through the walking consumer")
	Input.action_press("sprint")
	await _step(24)
	check(Vector2(player.velocity.x, player.velocity.z).length() > walk_speed + 0.5, "sprint keeps the existing physical speed distinction")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _step(30)
	await physics_frame
	Input.action_press("jump")
	await process_frame
	Input.action_release("jump")
	var peak := player.global_position.y
	for frame in 150:
		await _step(1)
		peak = maxf(peak, player.global_position.y)
	check(peak > 0.4 and player.is_on_floor(), "real physics jump takes off and lands without moving the visual root as physics")
	var meshes: Array = hero.find_children("*", "MeshInstance3D", true, false)
	uniform.set_lod(37.0, 3.0)
	var all_lod := true
	for mesh: MeshInstance3D in meshes:
		all_lod = all_lod and is_equal_approx(mesh.visibility_range_end, 37.0)
	check(all_lod, "LOD applies to body and every facial mesh")
	var xray: MeshInstance3D = uniform.build_xray()
	check(xray != null and xray.skin != null and xray.get_node_or_null(xray.skeleton) == hero.skeleton, "XRay stays bound to the active source skeleton")
	player.place(Vector3(0.25, 0.0, 0.0), PI / 2.0)
	await _step(4)
	check(_finite(_points(readers, false, player)), "short placement and facing reset retain a finite real body")
	var car := Car.build()
	car.get_node("Body/Driver").force_sprite_2d = false
	fixture.add_child(car)
	await _step(3)
	var driver: Node = car.get_node("Body/Driver")
	var seated: Node = driver.uniform_visual.imported_hero
	check(seated != null and seated.skeleton != hero.skeleton, "Driver uses the ready provider with independent pose state")
	if seated != null:
		var driver_readers := _readers(seated, car)
		var seated_bind := _points(driver_readers, true, car)
		check(absf(Reader.bounds(seated_bind).size.y - Catalog.ILYUSHA_VISIBLE_HEIGHT_M) <= 0.001, "Driver retains the same intrinsic height; no shrink for the cabin")
	fixture.free()
	await process_frame
	_finish()

func _step(frames: int) -> void:
	for frame in frames:
		await physics_frame
		await process_frame

func _readers(hero: Node, reference: Node3D) -> Array:
	var result: Array = []
	for mesh: MeshInstance3D in hero.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null or mesh.mesh == null or mesh.name == "XRay": continue
		var reader := Reader.new()
		reader.prepare(mesh, reference)
		reader.use_final_pose = true
		check(reader.issues.is_empty(), "source skin binds and vertex weights are valid: " + String(mesh.name))
		result.append(reader)
	return result

func _points(readers: Array, rest: bool, reference: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for reader in readers:
		if not rest and reader.final_pose_serial == 0: continue
		result.append_array(reader.referenced(reader.capture(rest, reference)))
	return result

func _finite(points: PackedVector3Array) -> bool:
	if points.is_empty(): return false
	for point in points:
		if not point.is_finite(): return false
	return true

func _finish() -> void:
	print("READY_HERO_RUNTIME: %d checks, %d failures; actual Player/Driver CPU; appearance/native gait/FPS NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

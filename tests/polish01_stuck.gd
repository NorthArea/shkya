extends SceneTree
## POLISH-01, застревания: случайные свободные точки по всей карте (фиксированный seed).
## Илюша должен уходить хотя бы в одну из 8 сторон, машина — ехать вперёд или назад; никто не падает и не покидает карту.

const Layout = preload("res://game/world/layout.gd")
const WALK_POINTS := 120
const CAR_POINTS := 60

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(1200.0, true, false, true).timeout.connect(func():
		push_error("FAIL: stuck sweep exceeded 1200 simulated seconds")
		quit(2)
	)
	rng.seed = 2610
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.start_game()
	await _frames(10)
	world = main.world
	world.car.reset_to(Vector3(95, 0, 120), 0.0)  # убрать машину с дороги, чтобы не мешала пешеходу
	await _sweep_walk()
	await _sweep_car()
	_finish()

func _sweep_walk() -> void:
	var player := world.player
	var trapped := []
	var escaped := []
	var tested := 0
	while tested < WALK_POINTS:
		var point := _random_point(0.5)
		if not _free(point, _capsule(), 0.8):
			continue
		tested += 1
		var free_directions := 0
		for k in 8:
			player.place(point, 0.0)
			world.camera_rig.yaw = k * TAU / 8.0
			await _frames(2)
			Input.action_press(&"move_forward")
			await _frames(15)
			Input.action_release(&"move_forward")
			var p := player.global_position
			if Vector2(p.x - point.x, p.z - point.z).length() > 0.3:
				free_directions += 1
			if p.y < -0.5 or not Layout.BOUNDS.has_point(Vector2(p.x, p.z)):
				escaped.append(point)
		if free_directions == 0:
			trapped.append(point)
	print("INFO: walk sweep %d points, trapped %d, escaped %d" % [tested, trapped.size(), escaped.size()])
	check(trapped.is_empty(), "Ilyusha is never trapped (%s)" % [trapped.slice(0, 5)])
	check(escaped.is_empty(), "Ilyusha never falls or leaves the map (%s)" % [escaped.slice(0, 5)])

func _sweep_car() -> void:
	var car := world.car
	world.enter_car()
	await _frames(3)
	var trapped := []
	var broken := []
	var tested := 0
	var box := BoxShape3D.new()
	box.size = Lada.SIZE + Vector3(0.6, -0.2, 0.6)
	while tested < CAR_POINTS:
		var point := _random_point(2.5)
		var yaw := rng.randf_range(-PI, PI)
		if not _free(point, box, Lada.SIZE.y * 0.5 + 0.1, yaw):
			continue
		tested += 1
		var moved := false
		for action in [&"move_forward", &"move_back"]:
			car.reset_to(point, yaw)
			await _frames(2)
			Input.action_press(action)
			await _frames(45)
			Input.action_release(action)
			if car.global_position.distance_to(point) > 0.5:
				moved = true
		# Покататься с рулём в случайную сторону и проверить, что машина цела.
		car.reset_to(point, yaw)
		Input.action_press(&"move_forward")
		Input.action_press(&"move_left" if rng.randf() < 0.5 else &"move_right")
		await _frames(120)
		_release_all()
		await _frames(30)
		var p := car.global_position
		if p.y < -0.3 or p.y > 0.3 or car.global_basis.y.dot(Vector3.UP) < 0.999 or not Layout.BOUNDS.has_point(Vector2(p.x, p.z)):
			broken.append([point, p])
		if not moved:
			trapped.append(point)
	print("INFO: car sweep %d points, trapped %d, broken %d" % [tested, trapped.size(), broken.size()])
	check(trapped.is_empty(), "Lada can always drive forward or back from a free spot (%s)" % [trapped.slice(0, 5)])
	check(broken.is_empty(), "Lada stays upright, on the ground and inside the map (%s)" % [broken.slice(0, 3)])

func _random_point(margin: float) -> Vector3:
	var b := Layout.BOUNDS
	return Vector3(rng.randf_range(b.position.x + margin, b.end.x - margin), 0.0, rng.randf_range(b.position.y + margin, b.end.y - margin))

func _capsule() -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	return capsule

func _free(point: Vector3, shape: Shape3D, lift: float, yaw := 0.0) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 4
	query.exclude = [world.car.get_rid(), world.player.get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP, yaw), point + Vector3.UP * lift)
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"handbrake"]:
		Input.action_release(action)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("STUCK: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)

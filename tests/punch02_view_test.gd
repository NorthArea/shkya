extends SceneTree
## PUNCH-02 developer check: боковая точка в настоящем мире, камера со всех сторон, объём у стены,
## настоящий удар после коррекции и пять монет. Полёт/возрождение/стелс проверяет существующий PUNCH.
## tools/run.command --headless --fixed-fps 60 --script tests/punch02_view_test.gd

const DronesScript = preload("res://game/world/drones.gd")
var main: Node
var world: DemoWorld
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	world.stealth.grant_grace(900.0)
	world.camera_rig.set_physics_process(false)
	var drones: Node3D = world.get_node("LevelGeometry/Drones")
	drones.set_physics_process(false)
	world.player.place(Vector3(-16, 0, 85), 0.0)
	await _frames(3)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = CameraRig.PROFILES[&"on_foot"]["fov"]
	camera.make_current()
	var player: Ilyusha = world.player
	var bad_view: Array[int] = []
	var bad_reach: Array[int] = []
	for degrees in range(0, 360, 10):
		var angle := deg_to_rad(float(degrees))
		camera.global_position = player.global_position + Vector3(sin(angle) * 4.3, 2.6, cos(angle) * 4.3)
		camera.look_at(player.global_position + Vector3.UP * 1.1)
		var target: Vector3 = drones.hover_point(player)
		# Независимая проекция через Camera3D, а не production helper.
		var hero: Vector2 = camera.unproject_position(player.global_position + Vector3.UP * DronesScript.HOVER_HEIGHT)
		var center: Vector2 = camera.unproject_position(target)
		var drone_edge: Vector2 = camera.unproject_position(target + camera.global_basis.x * 0.5)
		var hero_edge: Vector2 = camera.unproject_position(player.global_position + Vector3.UP * DronesScript.HOVER_HEIGHT + camera.global_basis.x * 0.28)
		if absf(center.x - hero.x) <= absf(drone_edge.x - center.x) + absf(hero_edge.x - hero.x):
			bad_view.append(degrees)
		if target.distance_to(player.punch_center()) >= Ilyusha.PUNCH_RADIUS + DronesScript.HIT_RADIUS - 0.05 or absf(target.y - player.global_position.y - 1.9) > 0.001:
			bad_reach.append(degrees)
	check(bad_view.is_empty(), "horizontal silhouettes remain separate for camera orbit every 10 degrees: %s" % [bad_view])
	check(bad_reach.is_empty(), "all orbit targets stay within the punch sphere with 5 cm margin at original height: %s" % [bad_reach])
	# Узкая стенка закрывает только исходную точку; центр за 0,4 м до неё ещё не защищает край кольца.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	world.add_child(wall)
	wall.global_position = player.global_position + Vector3(0.6, 1.9, -2.0)
	var box := BoxShape3D.new()
	box.size = Vector3(0.35, 1.0, 0.35)
	var collision := CollisionShape3D.new()
	collision.shape = box
	wall.add_child(collision)
	await _frames(2)
	var target: Vector3 = drones.hover_point(player)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.49
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, target)
	query.collision_mask = 1 | 4
	query.exclude = [player.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "hover leaves clearance for the full rotor envelope beside a wall")
	wall.queue_free()
	await _frames(3)
	# Камера перед героем: после бокового обхода реальная форма удара всё ещё задевает реальную Area3D.
	camera.global_position = player.global_position + Vector3(0, 2.6, -4.3)
	camera.look_at(player.global_position + Vector3.UP * 1.1)
	var drone: Node3D = drones.drones[0]
	drone.global_position = drones.hover_point(player)
	drone.state = &"hover"
	await _frames(40)
	var coins: Node = world.get_node("LevelGeometry/Coins")
	var before: int = coins.remaining()
	check(player.punch(), "a real punch starts against the corrected front-camera hover")
	await _frames(12)
	check(drone.state == &"broken" and drone in player.last_punch_targets, "the corrected hover is hit by the real punch query")
	check(drones.coin_bursts == 1 and coins.remaining() == before + 5, "the hit still emits exactly five collectible coins")
	print("PUNCH02_VIEW: %d checks, %d failures" % [checks, failures.size()])
	main.queue_free()
	await _frames(3)
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

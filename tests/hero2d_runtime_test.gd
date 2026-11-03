extends SceneTree
const Player = preload("res://game/player/ilyusha.gd")
const Car = preload("res://game/vehicles/lada_visual.gd")
const Look = preload("res://game/characters/character_sprite.gd")
const Inputs = preload("res://game/input_setup.gd")
const Occupant = preload("res://game/vehicles/lada_driver.gd")
class FlyingTarget:
	extends Node3D
	func is_flying() -> bool:
		return true

var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HERO2D: " + label)
func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var player := Player.new()
	fixture.add_child(player)
	player.set_physics_process(false)
	var look: Node = player.visual.get_node("Look")
	look.set_physics_process(false)
	check(look.sprite != null and look.uniform_visual == null, "Player restores original SVG backend")
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	check(is_equal_approx(collider.shape.height, 1.60) and is_equal_approx(collider.position.y, 0.80), "capsule spans floor to requested 160cm")
	if look.sprite != null:
		var image: Image = look.sprite.texture.get_image()
		var alpha: Rect2i = image.get_used_rect()
		check(absf(alpha.size.y * look.sprite.pixel_size - 1.60) < 0.003, "actual opaque SVG height measures 160cm")
		var bottom: float = look.sprite.position.y + (image.get_height() * 0.5 - alpha.end.y) * look.sprite.pixel_size
		check(absf(bottom) < 0.015, "opaque soles register on floor")
		look._physics_process(1.0 / 60.0)
		look.submit_locomotion(Vector3(0, 0, -6), true)
		look._physics_process(1.0 / 60.0)
		check(look.frame == -1, "blocked actual root stays idle despite desired velocity")
		player.position.z -= 0.2
		look._physics_process(1.0 / 60.0)
		check(look.frame >= 0, "actual horizontal travel advances walking")
		player.position.z -= 10.0
		look._physics_process(1.0 / 60.0)
		check(look.frame == -1 and is_zero_approx(look._distance), "teleport clears walking distance")
		look.reset_pose()
		check(look.frame == -1, "explicit pose reset clears stale walk")
	var car := Car.build()
	fixture.add_child(car)
	var driver: Node = car.get_node("Body/Driver")
	check(driver.sprite != null and driver.uniform_visual == null, "player Lada restores local SVG driver")
	if driver.sprite != null and look.sprite != null:
		check(is_equal_approx(driver.sprite.pixel_size, look.sprite.pixel_size), "driver retains intrinsic 160cm canvas scale")
		var head_top: float = driver.position.y + driver.sprite.position.y + driver.sprite.region_rect.size.y * driver.sprite.pixel_size * 0.5
		check(head_top < 1.49 and head_top > 1.2, "cropped same-scale driver stays below sedan roof")
		var crop_bottom: float = driver.position.y + driver.sprite.position.y - driver.sprite.region_rect.size.y * driver.sprite.pixel_size * 0.5
		check(crop_bottom >= 0.32, "cropped driver cannot protrude below cabin floor")
		check(not driver.is_physics_processing(), "seated SVG driver has no physics animation overhead")
	var npc := Look.new()
	npc.character = "police"
	fixture.add_child(npc)
	check(npc.uniform_visual != null, "police remains on accepted 3D backend")
	var passenger := Occupant.new()
	passenger.character = "resident_kid"
	passenger.occupant_profile = &"trolley_standing"
	fixture.add_child(passenger)
	check(passenger.uniform_visual != null, "trolley occupant remains on accepted 3D backend")
	fixture.free()
	await process_frame
	await _actual_movement()
	print("HERO2D_RUNTIME: %d checks, %d failures; native appearance NOT_RUN" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.position = at
	body.add_child(collision)
	return body

func _step(frames: int) -> void:
	for frame in frames:
		await physics_frame
		await process_frame

func _actual_movement() -> void:
	Inputs.install()
	var fixture := Node3D.new()
	root.add_child(fixture)
	fixture.add_child(_box(Vector3(300, 1, 300), Vector3(0, -0.5, 0)))
	fixture.add_child(_box(Vector3(1, 3, 20), Vector3(0.5, 1.5, 0)))
	var player := Player.new()
	fixture.add_child(player)
	player.place(Vector3(-0.65, 0, 0), 0.0)
	await _step(12)
	var look: Node = player.visual.get_node("Look")
	Input.action_press("move_right")
	await _step(90)
	var start := player.global_position
	var phase: float = look._distance
	await _step(30)
	check(player.is_on_wall() and player.global_position.distance_to(start) < 0.005, "held real input reaches a blocking physical wall")
	check(look.frame == -1 and absf(look._distance - phase) < 0.001, "physical wall generates no false SVG footsteps")
	Input.action_release("move_right")
	player.place(Vector3(-20, 0, 0), 0.0)
	await _step(12)
	Input.action_press("move_forward")
	await _step(60)
	start = player.global_position
	phase = look._distance
	await _step(30)
	var walked := player.global_position.distance_to(start)
	check(walked > 1.8 and walked < 2.2 and look.frame >= 0, "real walk retains 4m/s and original walking frames")
	check(absf(look._distance - phase - walked) < 0.08, "walk cadence measures travelled metres")
	Input.action_press("sprint")
	await _step(60)
	start = player.global_position
	phase = look._distance
	await _step(30)
	var ran := player.global_position.distance_to(start)
	check(ran > 3.8 and ran < 4.2 and ran > walked * 1.8, "real sprint retains 8m/s distinction")
	check(absf(look._distance - phase - ran) < 0.15, "sprint cadence follows the faster actual distance")
	Input.action_press("jump")
	await _step(1)
	Input.action_release("jump")
	await _step(3)
	phase = look._distance
	var peak := player.global_position.y
	var airborne_idle := true
	for frame in 15:
		await _step(1)
		peak = maxf(peak, player.global_position.y)
		airborne_idle = airborne_idle and look.frame == -1
	check(peak > 0.4 and airborne_idle and is_equal_approx(look._distance, phase), "airborne SVG suspends ground steps during unchanged physical jump")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _step(150)
	check(player.is_on_floor() and look.frame == -1, "landing and braking settle into original idle")
	player.place(player.global_position + Vector3(0.1, 0, 0), PI / 2)
	check(look.frame == -1 and is_zero_approx(look._distance), "short placement clears contact history too")
	# Enter/exit visibility lifecycle: locomotion must not replay the old sample.
	player.visible = false
	await _step(2)
	player.position += Vector3(5, 0, 0)
	player.visible = true
	player.place(player.position, 0.0)
	await _step(2)
	check(look.frame == -1 and is_zero_approx(look._distance), "hidden vehicle transition restores an idle visible body")
	var target := Area3D.new()
	target.collision_layer = 16
	target.collision_mask = 0
	var target_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	target_shape.shape = sphere
	target.add_child(target_shape)
	var drone := FlyingTarget.new()
	fixture.add_child(drone)
	drone.add_child(target)
	target.global_position = player.global_position + Vector3(0, 1.9, -1.0)
	await _step(2)
	check(player.punch(), "160cm hero starts the existing punch action")
	await _step(12)
	check(drone in player.last_punch_targets, "unchanged punch volume still reaches a hovering drone-height target")
	fixture.free()
	await process_frame

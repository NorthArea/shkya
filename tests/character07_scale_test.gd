extends SceneTree
## Production SVG/capsule measurements; imported-provider skin qualification is retained separately.
const Player = preload("res://game/player/ilyusha.gd")
const Car = preload("res://game/vehicles/lada_visual.gd")
const Occupant = preload("res://game/vehicles/lada_driver.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHAR07: " + label)
func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var player := Player.new()
	fixture.add_child(player)
	player.set_physics_process(false)
	var look: Node = player.visual.get_node("Look")
	check(look.sprite != null and look.uniform_visual == null, "production hero uses the restored SVG")
	if look.sprite != null:
		var image: Image = look.sprite.texture.get_image()
		var alpha := image.get_used_rect()
		var actual_height: float = alpha.size.y * look.sprite.pixel_size
		check(absf(actual_height - 1.60) < 0.003, "opaque standing body independently measures 160cm")
		var floor_y: float = look.sprite.position.y + (image.get_height() * 0.5 - alpha.end.y) * look.sprite.pixel_size
		check(absf(floor_y) < 0.015, "opaque soles remain registered to world floor")
		check(look.scale.is_equal_approx(Vector3.ONE), "body uses no proportional deformation")
		for view in ["front", "back", "side"]:
			for frame in ["idle", "walk0", "walk1", "walk2", "walk3"]:
				check(ResourceLoader.exists("res://assets/art/characters/ilyusha_%s_%s.svg" % [view, frame]), "original drawing retained: " + view + " " + frame)
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	check(collider.shape is CapsuleShape3D and absf(collider.shape.height - 1.60) < 0.001, "capsule independently measures requested height")
	check(absf(collider.position.y - 0.80) < 0.001, "capsule spans same floor and top")
	var car := Car.build()
	fixture.add_child(car)
	var driver: Node = car.get_node("Body/Driver")
	check(driver.sprite != null and driver.uniform_visual == null, "same restored hero occupies player sedan")
	if driver.sprite != null and look.sprite != null:
		check(is_equal_approx(driver.sprite.pixel_size, look.sprite.pixel_size), "driver retains standing intrinsic scale")
		check(driver.sprite.region_enabled and driver.sprite.region_rect.size.y < driver.sprite.texture.get_height(), "seat clips legs instead of shrinking body")
		check(driver.scale.is_equal_approx(Vector3.ONE), "driver has no hidden proportional shrink")
	var passenger := Occupant.new()
	passenger.character = "resident_kid"
	passenger.height_m = 2.0
	passenger.occupant_profile = &"trolley_standing"
	passenger.occupant_floor_y = 0.80
	fixture.add_child(passenger)
	check(passenger.uniform_visual != null and passenger.sprite == null, "generic trolley passenger retains 3D provider")
	check(absf(passenger.uniform_visual.uniform_mesh.mesh.get_aabb().size.y * passenger.uniform_visual.model.global_basis.get_scale().y - 1.5583333333333333) < 0.001, "generic trolley scale remains independent from hero")
	fixture.free()
	await process_frame
	print("CHARACTER07_SCALE: %d checks, %d failures; native appearance NOT_RUN" % [checks, failures])
	quit(0 if failures == 0 else 1)

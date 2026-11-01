extends SceneTree
## Independent MSG-0142 hero slice: actual world skin/bind geometry, not config values.
## tools/godot.sh --headless --script tests/character07_scale_test.gd
## Cabin/wheel/roof acceptance remains car01_cabin_clearance_test and trolley01.
const Player = preload("res://game/player/ilyusha.gd")
const Car = preload("res://game/vehicles/lada_visual.gd")
const Occupant = preload("res://game/vehicles/lada_driver.gd")
const HEIGHT_M := 1.50
const HEIGHT_EPS_M := 0.001
const POINT_EPS_M := 0.0002
# Frozen before the scale-only patch: approved normalized shape and skin builder.
const SHAPE_SOURCES := {
	"res://game/characters/models/civilian_model.gd": "1d1ff47002db9067744a692bb3eb81c5f43b230d0bbb8bd5ef4021694b3498b1",
	"res://game/characters/models/uniform_mesh_builder.gd": "bb056c56ff816c777e1ec662ad9fd21b154c0f0b8786c3f36c11a32afe41147a",
}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("CHAR07: " + label)

func _run() -> void:
	for path: String in SHAPE_SOURCES:
		check(FileAccess.get_sha256(path) == SHAPE_SOURCES[path], "scale-only change preserves the approved proportion source: " + path)
	var fixture := Node3D.new()
	root.add_child(fixture)
	var player := Player.new()
	player.input_enabled = false
	player.set_physics_process(false)
	fixture.add_child(player)
	player.place(Vector3.ZERO, 0.0)
	var look: Node = player.visual.get_node("Look")
	look.set_physics_process(false)
	look.reset_pose()
	var standing: Node3D = look.uniform_visual
	var standing_world := skin_points(standing.uniform_mesh, false)
	var standing_bind := skin_points(standing.uniform_mesh, true)
	var standing_box := bounds(standing_world)
	var bind_box := bounds(standing_bind)
	check(absf(standing_box.position.y) <= HEIGHT_EPS_M, "real standing Ilyusha soles lie on world floor zero")
	check(absf(standing_box.end.y - HEIGHT_M) <= HEIGHT_EPS_M and absf(standing_box.size.y - HEIGHT_M) <= HEIGHT_EPS_M, "real standing skin measures exactly 1.50m floor to top")
	check(absf(bind_box.size.y - HEIGHT_M) <= HEIGHT_EPS_M and point_delta(standing_world, standing_bind) <= POINT_EPS_M, "rest and bind geometry agree on actual hero height")
	_check_isotropic_shape(standing, "standing hero")
	var collider := player.get_node("CollisionShape3D") as CollisionShape3D
	check(collider.shape is CapsuleShape3D and absf(collider.shape.height - HEIGHT_M) <= HEIGHT_EPS_M, "actual player collision capsule agrees with the requested height")
	check(absf(collider.position.y - HEIGHT_M * 0.5) <= HEIGHT_EPS_M, "actual collision capsule spans the same floor and top")
	var car := Car.build()
	fixture.add_child(car)
	var driver: Node3D = car.get_node("Body/Driver")
	var seated: Node3D = driver.uniform_visual
	var seated_pose := skin_points(seated.uniform_mesh, false)
	var seated_bind := skin_points(seated.uniform_mesh, true)
	var seated_box := bounds(seated_pose)
	var seated_bind_box := bounds(seated_bind)
	check(absf(seated_bind_box.size.y - HEIGHT_M) <= HEIGHT_EPS_M, "real Lada driver's intrinsic world bind height is 1.50m")
	check(absf(seated_bind_box.size.y - bind_box.size.y) <= HEIGHT_EPS_M, "standing and seated consumers retain the same intrinsic scale")
	check(seated_box.size.y < seated_bind_box.size.y - 0.05 and not at_rest(seated.skeleton), "same-scale driver fits by an actual seated pose rather than a standing-height comparison")
	_check_isotropic_shape(seated, "seated hero")
	var standing_scale: Vector3 = standing.model.global_basis.get_scale()
	var seated_scale: Vector3 = seated.model.global_basis.get_scale()
	check(standing_scale.distance_to(seated_scale) <= 0.00001, "actual seated model basis contains no hidden shrink relative to standing")
	# This generic occupant is a production trolley caller, not Ilyusha.
	# Its accepted intrinsic height is 2m canvas * 935/1200 visible fraction.
	var passenger := Occupant.new()
	passenger.character = "resident_kid"
	passenger.height_m = 2.0
	passenger.occupant_profile = &"trolley_standing"
	passenger.occupant_floor_y = 0.80
	fixture.add_child(passenger)
	var passenger_box := bounds(skin_points(passenger.uniform_visual.uniform_mesh, true))
	check(absf(passenger_box.size.y - 1.5583333333333333) <= HEIGHT_EPS_M, "generic trolley occupants retain their own accepted scale rather than inheriting hero height")
	print("CHAR07_SCALE ", JSON.stringify({"standing_cpu_bounds": str(standing_box), "standing_bind_height_m": bind_box.size.y, "seated_cpu_bounds": str(seated_box), "seated_bind_height_m": seated_bind_box.size.y, "standing_basis_scale": str(standing_scale), "seated_basis_scale": str(seated_scale), "generic_trolley_bind_height_m": passenger_box.size.y}))
	fixture.free()
	await process_frame
	print("CHARACTER07_SCALE: %d checks, %d failures; hero/same-seat-scale slice only; NPC/vehicle audit and cabin suites separate; GPU NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_isotropic_shape(visual: Node3D, label: String) -> void:
	var scale_: Vector3 = visual.model.global_basis.get_scale()
	check(absf(scale_.x - scale_.y) <= 0.00001 and absf(scale_.z - scale_.y) <= 0.00001, label + ": model uses a uniform world scale")
	var measured := skin_points(visual.uniform_mesh, true)
	var raw := PackedVector3Array()
	for surface in visual.uniform_mesh.mesh.get_surface_count():
		var arrays: Array = visual.uniform_mesh.mesh.surface_get_arrays(surface)
		for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			raw.append(visual.model.to_global(point))
	check(point_delta(measured, raw) <= POINT_EPS_M, label + ": every bound vertex follows the same rigid/uniform transform without proportional edits")

func skin_points(instance: MeshInstance3D, bind_pose: bool) -> PackedVector3Array:
	var skeleton := instance.get_node(instance.skeleton) as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var transforms: Array[Transform3D] = []
	for bind in instance.skin.get_bind_count():
		var bone := instance.skin.get_bind_bone(bind)
		var pose := skeleton.get_bone_global_rest(bone) if bind_pose else skeleton.get_bone_global_pose(bone)
		transforms.append(pose * instance.skin.get_bind_pose(bind))
	var result := PackedVector3Array()
	for surface in instance.mesh.get_surface_count():
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			var point := Vector3.ZERO
			for influence in 4:
				var slot := vertex * 4 + influence
				if weights[slot] > 0.0:
					point += (transforms[bones[slot]] * vertices[vertex]) * weights[slot]
			result.append(instance.to_global(point))
	return result

func bounds(points: PackedVector3Array) -> AABB:
	var low := Vector3.INF
	var high := -Vector3.INF
	for point: Vector3 in points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)

func point_delta(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.is_empty() or a.size() != b.size():
		return INF
	var maximum := 0.0
	for index in a.size():
		maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum

func at_rest(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone)):
			return false
	return true

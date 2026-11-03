extends SceneTree
## A placement must move the presented feet with the body, including short moves.
const Player = preload("res://game/player/ilyusha.gd")
const Inputs = preload("res://game/input_setup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Inputs.install()
	var fixture := Node3D.new()
	root.add_child(fixture)
	var player := Player.new()
	fixture.add_child(player)
	player.set_physics_process(false)
	var look: Node = player.visual.get_node("Look")
	look.set_physics_process(false)
	var uniform: Node = look.uniform_visual
	var imported: Node = uniform.imported_hero
	imported.set_process(false)
	player.place(Vector3.ZERO, 0.0)
	uniform.update_locomotion(Vector3.FORWARD * 4.0, true, &"locomotion", 0.0)
	imported._process(0.001)
	await process_frame
	await process_frame
	var before := _left_foot(uniform.skeleton)
	var contact: Node3D = uniform.skeleton.get_node("LeftFootContact")
	var contact_before := contact.global_position
	var shift := Vector3(0.25, 0.0, 0.0)
	player.place(shift, 0.0)
	imported._process(0.001)
	await process_frame
	await process_frame
	var after := _left_foot(uniform.skeleton)
	check(absf((contact.global_position - contact_before).x - shift.x) <= 0.001,
		"short Player.place reanchors the planted IK target: displacement=%s expected_x=%s" % [contact.global_position - contact_before, shift.x])
	check(after.distance_to(before + shift) <= 0.001,
		"short Player.place moves the actual planted foot with the body: displacement=%s expected=%s" % [after - before, shift])
	var settled := _left_foot(uniform.skeleton)
	player.place(shift, 0.0)
	imported._process(0.001)
	await process_frame
	await process_frame
	check(_left_foot(uniform.skeleton).distance_to(settled) <= 0.001,
		"placing twice at the same location does not drift the foot")
	var local_contact := contact.global_position - player.global_position
	var rotated_point := Vector3(0.4, 0.0, 0.2)
	player.place(rotated_point, PI / 2.0)
	imported._process(0.001)
	await process_frame
	await process_frame
	var rotated_contact := rotated_point + Basis(Vector3.UP, PI / 2.0) * local_contact
	check(contact.global_position.distance_to(rotated_contact) <= 0.001,
		"placement with a new facing reanchors contact in the new world frame")
	fixture.free()
	await process_frame
	print("IP01_IMPORTED_RESET: %d checks, %d failures; actual foot placement; likeness/GPU NOT_RUN" % [checks, failures])
	quit(1 if failures else 0)

func _left_foot(skeleton: Skeleton3D) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

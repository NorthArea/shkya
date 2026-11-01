extends SceneTree
## Independent temporal acceptance on actual Ilyusha/Look/skin, not a pose helper.
## Run at real clock without --fixed-fps: physics60/render cap120, four-second run.
const PlayerScript = preload("res://game/player/ilyusha.gd")
const DriverScript = preload("res://game/vehicles/lada_driver.gd")
const InputSetup = preload("res://game/input_setup.gd")
const EPS := 0.000001
const HIP_STEP_LIMIT_M := 0.035

class AfterConsumers:
	extends Node
	signal physics_done
	signal render_done
	var inspect_physics: Callable
	var inspect_render: Callable
	func _physics_process(delta: float) -> void:
		if inspect_physics.is_valid(): inspect_physics.call(delta)
		physics_done.emit()
	func _process(_delta: float) -> void:
		if inspect_render.is_valid(): inspect_render.call()
		render_done.emit()

var checks := 0
var failures: Array[String] = []
var observer: AfterConsumers
var fixture: Node3D
var player: CharacterBody3D
var look: Node
var visual: Node
var vertices: Array[Dictionary] = []
var measuring := false
var previous := {}
var physics_samples := 0
var render_samples := 0
var between_physics := 0
var held_bones := 0
var held_skin := 0
var render_phase_changes := 0
var render_root_changes := 0
var physical_distance := 0.0
var physical_seconds := 0.0
var phase_first := 0.0
var phase_last := 0.0
var physics_previous := Vector3.ZERO
var min_fraction := INF
var max_fraction := -INF
var hip_previous_y := NAN
var hip_samples := 0
var hip_peak_step := 0.0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("MOTION01_POSE_INTERPOLATION: " + message)

func _run() -> void:
	create_timer(15.0, true, false, true).timeout.connect(func(): quit(2))
	var previous_fps := Engine.max_fps
	Engine.max_fps = 120
	check(Engine.physics_ticks_per_second == 60, "temporal fixture runs real 60Hz physics")
	InputSetup.install()
	fixture = Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	fixture.add_child(floor_body)
	player = PlayerScript.new()
	fixture.add_child(player)
	player.place(Vector3.ZERO, 0.0)
	look = player.visual.get_node("Look")
	visual = look.uniform_visual
	check(look.uses_uniform_3d() and visual.rig != null, "real Ilyusha factory selects the live articulated 3D consumer")
	vertices = _sole_vertices()
	check(vertices.size() == 2, "independent mesh scan finds actual skinned sole vertices on both active ankles")
	observer = AfterConsumers.new()
	observer.process_physics_priority = 1000
	observer.process_priority = 1000
	observer.inspect_physics = _inspect_physics
	observer.inspect_render = _inspect_render
	root.add_child(observer)
	await create_timer(0.1).timeout
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await create_timer(2.0).timeout
	check(player.is_on_floor() and Vector2(player.velocity.x, player.velocity.z).length() > 7.5,
		"real input reaches sustained grounded sprint before temporal sampling")
	physics_previous = player.global_position
	phase_first = visual.gait.phase
	measuring = true
	await create_timer(2.0).timeout
	measuring = false
	check(physics_samples >= 100 and render_samples > physics_samples + 30 and between_physics >= 30,
		"real-clock measurement contains changing interpolation fractions between physical updates")
	check(held_bones == 0, "moving leg bones advance on every sampled render-only interpolation interval")
	check(held_skin == 0, "actual skinned sole vertices advance between physical updates in skeleton space")
	check(render_phase_changes == 0 and render_root_changes == 0,
		"render presentation advances neither gait simulation phase nor raw physical actor root")
	var speed := physical_distance / maxf(physical_seconds, 0.000001)
	check(absf(speed - PlayerScript.RUN_SPEED) < 0.1 and phase_last > phase_first,
		"real sprint root speed and physics-owned gait progression survive temporal presentation")
	check(hip_samples >= 100 and hip_peak_step <= HIP_STEP_LIMIT_M,
		"warmed real sprint hips move at most 3.5cm vertically per physical step")
	print("MOTION01_POSE_TEMPORAL ", JSON.stringify({"physics_samples": physics_samples,
		"render_samples": render_samples, "render_only_intervals": between_physics,
		"held_bones": held_bones, "held_skin": held_skin, "render_phase_changes": render_phase_changes,
		"render_root_changes": render_root_changes, "actual_speed": speed,
		"fraction_range": [min_fraction, max_fraction], "phase_advance": phase_last - phase_first,
		"physical_hip_samples": hip_samples, "peak_physical_hip_y_step_m": hip_peak_step,
		"sha256": FileAccess.get_sha256(get_script().resource_path)}))
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	player.input_enabled = false
	player.place(player.global_position + Vector3.RIGHT * 25.0, 0.0)
	var relocated := player.global_position
	var teleport_clear := true
	for frame in 8:
		await observer.render_done
		teleport_clear = teleport_clear and player.get_global_transform_interpolated().origin.distance_to(relocated) < 0.02
		for point: Vector3 in _skin_points():
			var world_point: Vector3 = visual.skeleton.global_transform * point
			teleport_clear = teleport_clear and world_point.distance_to(player.global_position) < 3.0
	check(teleport_clear, "place cancels any interpolation bridge to the previous actor/skin position")
	player.force_hide_mode(&"box")
	await observer.physics_done
	var hidden_clear := true
	for frame in 6:
		await observer.render_done
		hidden_clear = hidden_clear and not look.visible and _at_rest(visual.skeleton) and visual.gait.speed == 0.0
	check(hidden_clear, "hidden real hero never resurrects a buffered walking pose between physics updates")
	player.force_hide_mode(&"none")
	await observer.physics_done
	await observer.render_done
	check(look.visible and _at_rest(visual.skeleton), "showing the stopped hero starts from the current settled pose")
	var seated := DriverScript.new()
	seated.character = "ilyusha"
	seated.occupant_profile = &"lada"
	fixture.add_child(seated)
	var seated_poses := _poses(seated.uniform_visual.skeleton)
	var seat_stable := not _at_rest(seated.uniform_visual.skeleton)
	for frame in 12:
		await observer.render_done
		seat_stable = seat_stable and _poses(seated.uniform_visual.skeleton) == seated_poses
	check(seat_stable, "actual seated factory consumer keeps its authored cabin pose across render frames")
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	observer.inspect_physics = Callable()
	observer.inspect_render = Callable()
	fixture.queue_free()
	await process_frame
	await process_frame
	observer.queue_free()
	Engine.max_fps = previous_fps
	print("MOTION01_POSE_INTERPOLATION: %d checks, %d failures; GPU/manual naturalness NOT_RUN" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _inspect_physics(delta: float) -> void:
	if not measuring: return
	physics_samples += 1
	physical_distance += Vector2(player.global_position.x - physics_previous.x, player.global_position.z - physics_previous.z).length()
	physical_seconds += delta
	physics_previous = player.global_position
	phase_last = visual.gait.phase
	if player.is_on_floor() and Vector2(player.velocity.x, player.velocity.z).length() > 7.5:
		var skeleton: Skeleton3D = visual.skeleton
		skeleton.force_update_all_bone_transforms()
		var hip_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hips")).origin
		if not is_nan(hip_previous_y):
			hip_samples += 1
			hip_peak_step = maxf(hip_peak_step, absf(hip_world.y - hip_previous_y))
		hip_previous_y = hip_world.y
	else:
		hip_previous_y = NAN

func _inspect_render() -> void:
	if not measuring: return
	render_samples += 1
	var fraction := Engine.get_physics_interpolation_fraction()
	var sample := {"frame": Engine.get_physics_frames(), "fraction": fraction,
		"root": player.global_position, "phase": float(visual.gait.phase),
		"bones": _leg_poses(), "skin": _skin_points()}
	min_fraction = minf(min_fraction, fraction)
	max_fraction = maxf(max_fraction, fraction)
	if not previous.is_empty() and sample.frame == previous.frame and fraction > float(previous.fraction) + 0.005:
		between_physics += 1
		if _pose_delta(sample.bones, previous.bones) <= EPS: held_bones += 1
		if _point_delta(sample.skin, previous.skin) <= EPS: held_skin += 1
		if absf(float(sample.phase) - float(previous.phase)) > 0.000001: render_phase_changes += 1
		if Vector3(sample.root).distance_to(previous.root) > EPS: render_root_changes += 1
	previous = sample

func _leg_poses() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for leg: Dictionary in visual.rig.legs:
		for bone: int in [leg.hip, leg.knee, leg.ankle]: result.append(visual.skeleton.get_bone_pose(bone))
	return result

func _pose_delta(a: Array, b: Array) -> float:
	var largest := 0.0
	for i in mini(a.size(), b.size()):
		var x: Transform3D = a[i]
		var y: Transform3D = b[i]
		largest = maxf(largest, x.origin.distance_to(y.origin))
		largest = maxf(largest, x.basis.x.distance_to(y.basis.x))
		largest = maxf(largest, x.basis.y.distance_to(y.basis.y))
		largest = maxf(largest, x.basis.z.distance_to(y.basis.z))
	return largest

func _point_delta(a: Array, b: Array) -> float:
	var largest := 0.0
	for i in mini(a.size(), b.size()): largest = maxf(largest, Vector3(a[i]).distance_to(b[i]))
	return largest

func _sole_vertices() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var mesh: MeshInstance3D = visual.uniform_mesh
	for leg: Dictionary in visual.rig.legs:
		var best := {}
		var lowest := INF
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for index in points.size():
				var ankle_weight := 0.0
				for influence in 4:
					var slot := index * 4 + influence
					if mesh.skin.get_bind_bone(bones[slot]) == int(leg.ankle): ankle_weight += weights[slot]
				if ankle_weight > 0.5 and points[index].y < lowest:
					lowest = points[index].y
					best = {"vertex": points[index], "bones": bones.slice(index * 4, index * 4 + 4),
						"weights": weights.slice(index * 4, index * 4 + 4)}
		if not best.is_empty(): found.append(best)
	return found

func _skin_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var mesh: MeshInstance3D = visual.uniform_mesh
	var skeleton: Skeleton3D = visual.skeleton
	skeleton.force_update_all_bone_transforms()
	for sample: Dictionary in vertices:
		var point := Vector3.ZERO
		for influence in 4:
			if sample.weights[influence] <= 0.0: continue
			var bind: int = sample.bones[influence]
			var bone := mesh.skin.get_bind_bone(bind)
			point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * Vector3(sample.vertex)) * float(sample.weights[influence])
		result.append(point)
	return result

func _poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result

func _at_rest(skeleton: Skeleton3D) -> bool:
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone)): return false
	return true

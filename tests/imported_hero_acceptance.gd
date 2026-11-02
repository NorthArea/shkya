extends SceneTree
## Independent imported-hero acceptance on the real Player -> Look -> Uniform and
## Lada -> Driver chains. Technical skin/temporal proof; appearance and GPU NOT_RUN.
const Reader = preload("res://tests/actual_skin_reader.gd")
const Clearance = preload("res://tests/skinned_clearance.gd")
const PlayerScript = preload("res://game/player/ilyusha.gd")
const Car = preload("res://game/vehicles/lada_visual.gd")
const Driver = preload("res://game/vehicles/lada_driver.gd")
const InputSetup = preload("res://game/input_setup.gd")
const SourceAnimations = preload("res://assets/animations/ilyusha/locomotion.tres")
const OUT := "res://builds/checks/IP-01/imported-qa/acceptance.json"
const HEIGHT := 1.765 # Owner's fixed reference, independently of Catalog.
const HEIGHT_EPS := 0.001
const SEAM_EPS := 0.0002
const FLOOR_PENETRATION := 0.012
const HISTORICAL_SOLE_LIFT := 0.07
const BODY_BOB := 0.03
const HISTORICAL_CONTACT_GAP_SECONDS := 0.10
const CONTACT_SLIP_MPS := 0.8
const SIDES := ["Left", "Right"]
## Root's anatomical adaptation pin, agreed after independent methodology review.
## These are target windows/envelopes, not claims about the raw source mannequin.
const PHASE_PROFILE := {
	"Walk": {"clip": "Walk", "duty": 0.58, "hip_mean": 0.835, "swing_m": 0.08},
	"Jog": {"clip": "Jog_Fwd", "duty": 0.28, "hip_mean": 0.80, "swing_m": 0.10},
	"Run": {"clip": "Sprint", "duty": 0.22, "hip_mean": 0.78, "swing_m": 0.12},
}
const PHASE_EDGE_SECONDS := 1.0 / 60.0
const HIP_EXCURSION_LIMIT := 0.02
const REQUIRED := ["Root", "Hips", "Spine", "Chest", "Neck", "Head",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]

class Observer:
	extends Node
	signal rendered
	signal stepped
	var inspect_render: Callable
	var inspect_physics: Callable
	var render_delta := 0.0
	func _process(delta: float) -> void:
		render_delta = delta
		if inspect_render.is_valid(): inspect_render.call(delta)
		rendered.emit()
	func _physics_process(delta: float) -> void:
		if inspect_physics.is_valid(): inspect_physics.call(delta)
		stepped.emit()

var checks := 0
var failures: Array[String] = []
var report := {"scope": "imported hero CPU mesh/skin, real Player and Lada consumer, 60Hz physics/120Hz presentation", "graphics": "NOT_RUN", "likeness": "NOT_RUN", "lifecycle": "NOT_RUN", "cabin": "NOT_RUN", "metrics": {}}
var fixture: Node3D
var player: CharacterBody3D
var look: Node3D
var visual: Node3D
var reader: RefCounted
var observer: Observer
var sole_samples: Array = [[], []]
var plant_slots: Array = [[], []]
var temporal_physics: Array[Dictionary] = []
var temporal_render: Array[Dictionary] = []
var measuring := false
var motion_only := false
var target_probe := false
var cabin_only := false
var previous_render := {}
var render_intervals := 0
var held_bones := 0
var held_skin := 0
var render_root_changes := 0
var stale_final_snapshots := 0
var model_base_y := 0.0
var previous_final_time_usec := 0
var previous_physical_root := Vector3.ZERO
var physical_root_distance := 0.0
var physical_root_seconds := 0.0
var rest_points := PackedVector3Array()
var seam_pairs: Array[Vector2i] = []
var geometry_metrics := {"finite": true, "maximum_seam_m": 0.0, "maximum_limb_length_error_m": 0.0, "maximum_bone_scale_error": 0.0,
	"minimum_joint_triangle_area_ratio": 1.0, "maximum_joint_edge_ratio": 1.0, "joint_triangles_inspected": 0,
	"minimum_area_witness": {}, "maximum_edge_witness": {},
	"minimum_visible_skin_y_m_diagnostic": 0.0, "lowest_visible_skin_source": {},
	"minimum_knee_forward_m": 0.0, "maximum_knee_bend_degrees": [0.0, 0.0], "maximum_elbow_bend_degrees": [0.0, 0.0]}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("IMPORTED_HERO: " + message)
	return ok

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(2))
	report["source_start_sha256"] = _source_hashes()
	target_probe = "--target-probe" in OS.get_cmdline_user_args()
	cabin_only = "--cabin-only" in OS.get_cmdline_user_args()
	motion_only = "--motion-only" in OS.get_cmdline_user_args() or target_probe or cabin_only
	if motion_only: report["scope"] = "quick imported hero bind/Idle/real Player4/8/final semantic joints; cabin/lifecycle/full geometry NOT_RUN"
	if target_probe: report["scope"] = "short read-only native target/anchor/frame diagnosis; gait/lifecycle/cabin acceptance NOT_RUN"
	if cabin_only: report["scope"] = "static actual Driver/cabin acceptance; gait/lifecycle/full-mesh deformation NOT_RUN"
	report["phase_gait_acceptance"] = "NOT_RUN"
	report["target_phase_pin"] = {"profile": PHASE_PROFILE, "right_phase_offset": 0.5, "plant_edge_exclusion_seconds": PHASE_EDGE_SECONDS, "minimum_core_samples": 2,
		"hip_excursion_limit_m": HIP_EXCURSION_LIMIT, "source_clock": "read-only actual AnimationTree position/length, checked against the pinned AnimationLibrary duration",
		"swing": "declared ankle budgets recorded; actual sole lift remains raw diagnostic; visible boot floor and flat plant tested",
		"usable_reach_reserve": 0.90, "cadence": "raw diagnostic; manual naturalness NOT_RUN"}
	_reader_self_checks()
	if "--reader-only" in OS.get_cmdline_user_args():
		report["scope"] = "reader selfchecks only; production acceptance NOT_RUN"
		_finish()
		return
	var previous_fps := Engine.max_fps
	Engine.max_fps = 120
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
	model_base_y = visual.model.position.y
	check(Engine.physics_ticks_per_second == 60, "temporal fixture uses real 60Hz physics")
	check(look.uses_uniform_3d() and visual.imported_hero != null, "real Player factory selects imported GLB facade")
	check(visual.find_children("*", "Skeleton3D", true, false).size() == 1, "hero contains one real skeleton, without a procedural alternate body")
	check(visual.find_children("*", "MeshInstance3D", true, false).size() == 1, "hero facade contains exactly one imported skinned mesh")
	check(visual.model.scene_file_path == "res://assets/models/characters/ilyusha/ilyusha.glb", "actual visible body is the authored Ilyusha GLB scene")
	check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "imported visual adds no physics owner")
	var skeleton: Skeleton3D = visual.skeleton
	var names := PackedStringArray()
	for bone in skeleton.get_bone_count(): names.append(skeleton.get_bone_name(bone))
	var complete_humanoid := true
	for name_ in REQUIRED:
		if not check(skeleton.find_bone(name_) >= 0, "canonical humanoid bone exists: " + name_): complete_humanoid = false
	if not complete_humanoid:
		fixture.free()
		_finish()
		return
	for side in SIDES:
		var thigh := skeleton.find_bone(side + "UpperLeg")
		var calf := skeleton.find_bone(side + "LowerLeg")
		var foot := skeleton.find_bone(side + "Foot")
		check(thigh >= 0 and calf >= 0 and foot >= 0 and skeleton.get_bone_parent(calf) == thigh and skeleton.get_bone_parent(foot) == calf,
			side + " real knee joins distinct thigh/calf/foot bones")
	reader = Reader.new()
	reader.prepare(visual.uniform_mesh, player)
	reader.snapshot_metadata = _motion_metadata
	if not check(reader.issues.is_empty(), "actual imported mesh has resolved binds, normalized weights and valid indexed topology: " + str(reader.issues.slice(0, 5))):
		fixture.free()
		_finish()
		return
	rest_points = reader.capture(true)
	var bind_box := Reader.bounds(reader.referenced(rest_points))
	check(absf(bind_box.size.y - HEIGHT) <= HEIGHT_EPS and absf(bind_box.end.y - HEIGHT) <= HEIGHT_EPS, "actual world bind skin is exactly 1.765m within 1mm")
	check(absf(bind_box.position.y) <= HEIGHT_EPS, "actual world bind sole is floor zero within 1mm")
	var raw_world := PackedVector3Array()
	for surface in reader.surfaces:
		for point: Vector3 in surface.raw: raw_world.append(visual.uniform_mesh.to_global(point))
	# RestFixer deliberately converts the authored A pose to a humanoid T rest.
	# Raw A-space vertices need not equal T-rest skin vertices after retargeting.
	check(absf(Reader.bounds(reader.referenced(raw_world)).size.y - HEIGHT) <= HEIGHT_EPS, "authored A-pose mesh retains the same intrinsic 1.765m height")
	var original_scale: Vector3 = visual.model.scale
	var world_scale: Vector3 = visual.model.global_basis.get_scale()
	check(absf(world_scale.x - world_scale.y) <= 0.00001 and absf(world_scale.z - world_scale.y) <= 0.00001, "actual imported body uses a uniform intrinsic scale")
	visual.model.scale *= 1.5 / HEIGHT
	check(absf(Reader.bounds(reader.referenced(reader.capture(true))).size.y - 1.5) <= HEIGHT_EPS, "height oracle distinguishes superseded 1.50m using actual skin")
	visual.model.scale = original_scale
	for surface in reader.surfaces:
		var indexed: PackedInt32Array = visual.uniform_mesh.mesh.surface_get_arrays(surface.surface)[Mesh.ARRAY_INDEX]
		check(not indexed.is_empty(), "imported material uses real indexed geometry: " + String(surface.material))
	_prepare_seams()
	_prepare_soles()
	check(not sole_samples[0].is_empty() and not sole_samples[1].is_empty(), "independent material/bind scan finds both actual rubber soles")
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	check(collider.shape is CapsuleShape3D and absf(collider.shape.height - HEIGHT) <= HEIGHT_EPS and absf(collider.position.y - HEIGHT * 0.5) <= HEIGHT_EPS, "actual physical capsule agrees with fixed full-height hero")
	if not motion_only: _weighted_joint_witnesses()
	report.metrics["bind"] = {"bounds": str(bind_box), "vertices": reader.vertex_count, "triangles": reader.triangle_count, "bones": Array(names), "retargeted_T_rest_vs_raw_A_delta_m": Reader.delta(rest_points, raw_world), "raw_A_height_m": Reader.bounds(raw_world).size.y}
	observer = Observer.new()
	observer.process_priority = 1000
	observer.process_physics_priority = 1000
	observer.process_mode = Node.PROCESS_MODE_ALWAYS
	observer.inspect_physics = _inspect_physics
	root.add_child(observer)
	await create_timer(0.2).timeout
	check(reader.final_pose_serial > 0, "independent skeleton_updated observer saw actual final skin matrices")
	reader.use_final_pose = true
	reader.final_pose_captured.connect(_inspect_final_pose)
	if motion_only: _inspect_bones()
	else: _inspect_integrity()
	for speed in ([] if cabin_only else [4.0, 8.0]):
		Input.action_press(&"move_forward")
		if speed == 8.0: Input.action_press(&"sprint")
		await create_timer(0.4 if target_probe else 0.8).timeout
		previous_render.clear()
		temporal_physics.clear()
		temporal_render.clear()
		render_intervals = 0
		held_bones = 0
		held_skin = 0
		render_root_changes = 0
		stale_final_snapshots = 0
		previous_physical_root = player.global_position
		physical_root_distance = 0.0
		physical_root_seconds = 0.0
		measuring = true
		await create_timer(0.65 if target_probe else 2.10).timeout
		measuring = false
		if target_probe:
			report.metrics["actual %.0fm/s" % speed] = {"physics": _metrics(temporal_physics), "render": _metrics(temporal_render)}
		else: _temporal_limits(speed)
		# Full mesh scans run outside cadence measurement. Use actual render
		# updates to sample a further cycle without adding artificial frames.
		if not motion_only:
			for pose in 12:
				await observer.rendered
				_inspect_integrity()
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	await create_timer(0.1 if target_probe or cabin_only else 0.7).timeout
	if cabin_only:
		await _seated_chain()
	elif not motion_only:
		await _lifecycle()
		await _seated_chain()
		_inspect_integrity()
	else: _inspect_bones()
	check(geometry_metrics.finite, "every inspected final skeleton transform is finite" if motion_only else "every inspected actual weighted vertex and final skeleton transform is finite")
	if not motion_only: check(geometry_metrics.maximum_seam_m <= SEAM_EPS, "authored coincident skin seams stay joined within 0.2mm")
	check(geometry_metrics.maximum_limb_length_error_m <= SEAM_EPS and geometry_metrics.maximum_bone_scale_error <= 0.00001, "head/neck/limbs retain rest lengths and per-bone scale, without shrink")
	# Local area/edge ratios are witnesses for the native-pose visual reviewer.
	# They are not owner-approved shape thresholds; continuity is tested above.
	geometry_metrics["area_edge_ratios"] = "DIAGNOSTIC_ONLY; native-final peer review required for a visible deformation finding"
	check(geometry_metrics.minimum_knee_forward_m >= -0.015 and geometry_metrics.maximum_knee_bend_degrees[0] <= 150.0 and geometry_metrics.maximum_knee_bend_degrees[1] <= 150.0, "actual knee chains avoid reverse bend and complete folding")
	check(geometry_metrics.maximum_elbow_bend_degrees[0] <= 165.0 and geometry_metrics.maximum_elbow_bend_degrees[1] <= 165.0, "actual elbow chains avoid complete folding")
	if not cabin_only: check(geometry_metrics.maximum_knee_bend_degrees[0] >= 8.0 and geometry_metrics.maximum_knee_bend_degrees[1] >= 8.0, "both real calf joints bend visibly rather than swinging rigid legs")
	geometry_metrics["full_mesh_geometry_status"] = "NOT_RUN" if motion_only else "MEASURED"
	report.metrics["integrity"] = geometry_metrics
	observer.inspect_physics = Callable()
	observer.inspect_render = Callable()
	fixture.queue_free()
	observer.queue_free()
	await process_frame
	await process_frame
	Engine.max_fps = previous_fps
	_finish()

func _finish() -> void:
	report["source_sha256"] = _source_hashes()
	check(report.source_start_sha256 == report.source_sha256, "acceptance sources stayed unchanged during the entire run")
	report["checks"] = checks
	report["failures"] = failures
	report["acceptance_status"] = "FAIL" if not failures.is_empty() else ("DIAGNOSTIC_ONLY" if target_probe else "PASS_FOR_STATED_SCOPE")
	report["engine"] = Engine.get_version_info()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("IMPORTED_HERO_ACCEPTANCE: %d checks, %d failures; status=%s; GPU/likeness/manual NOT_RUN; phase=%s" % [checks, failures.size(), report.acceptance_status, report.phase_gait_acceptance])
	quit(1 if not failures.is_empty() else 0)

func _source_hashes() -> Dictionary:
	var result := {}
	for path in [get_script().resource_path, "res://tests/actual_skin_reader.gd", "res://assets/models/characters/ilyusha/ilyusha.glb", "res://assets/models/characters/ilyusha/ilyusha.glb.import",
		"res://assets/animations/ilyusha/locomotion.tres", "res://assets/animations/ilyusha/quaternius_in_place.glb.import", "res://assets/animations/ilyusha/target_bone_map.tres", "res://assets/animations/ilyusha/source_bone_map.tres",
		"res://tests/skinned_clearance.gd", "res://game/characters/imported_hero_visual.gd", "res://game/characters/imported_hero_driving.gd", "res://game/characters/uniform_visual.gd", "res://game/characters/character_sprite.gd", "res://game/player/ilyusha.gd", "res://game/vehicles/lada_driver.gd", "res://game/vehicles/lada_visual.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _reader_self_checks() -> void:
	var group := Node3D.new()
	root.add_child(group)
	group.transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3.ONE * 1.3), Vector3(2, 3, 4))
	var skeleton := Skeleton3D.new()
	group.add_child(skeleton)
	skeleton.position = Vector3(0.4, 0.5, 0.6)
	skeleton.add_bone("Tip")
	skeleton.add_bone("Root")
	skeleton.set_bone_parent(0, 1)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	skeleton.reset_bone_poses()
	var instance := MeshInstance3D.new()
	group.add_child(instance)
	instance.transform = Transform3D(Basis(Vector3.UP, -0.2), Vector3(-0.3, 0.7, 0.2))
	instance.skeleton = instance.get_path_to(skeleton)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 2, 0), Vector3(1, 2, 0), Vector3(0, 3, 0), Vector3(8, 9, 10)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([2, 0, 1])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	# 40/60 is exactly representable in Godot's uint16 skin weights (26214/39321).
	# 25/75 loses a unit during encoding and is unsuitable for a 10um selfcheck.
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, .4, .6, 0, 0, 1, 0, 0, 0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh
	var skin := Skin.new()
	skin.set_bind_count(2)
	var mesh_to_skeleton := skeleton.global_transform.affine_inverse() * instance.global_transform
	# Bind order deliberately differs from skeleton order. Named binds have no
	# numeric bone assignment, so a reader assuming bind==bone fails here.
	for bind in 2:
		var bone := 1 - bind
		skin.set_bind_name(bind, skeleton.get_bone_name(bone))
		skin.set_bind_pose(bind, skeleton.get_bone_global_rest(bone).affine_inverse() * mesh_to_skeleton)
	instance.skin = skin
	var probe := Reader.new()
	probe.prepare(instance)
	var rest := probe.capture(true)
	var expected := PackedVector3Array()
	for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]: expected.append(instance.to_global(point))
	var selfcheck_metrics := {"rest_delta_m": Reader.delta(rest, expected), "issues": probe.issues.duplicate()}
	check(probe.issues.is_empty() and Reader.delta(rest, expected) < 0.00001, "reader selfcheck: named bind permutation plus separate mesh/skeleton/root transforms")
	var triangles := probe.triangles(rest)
	check(triangles.size() == 1 and triangles[0][0].distance_to(expected[2]) < 0.00001 and triangles[0][1].distance_to(expected[0]) < 0.00001 and triangles[0][2].distance_to(expected[1]) < 0.00001, "reader selfcheck: actual index order excludes unused fourth vertex")
	check(probe.referenced(rest).size() == 3 and Reader.bounds(probe.referenced(rest)).end.y < expected[3].y - 1.0, "reader selfcheck: unreferenced dummy vertices cannot extend visible bounds")
	skeleton.set_bone_pose_rotation(0, Quaternion(Vector3.RIGHT, PI * 0.5))
	var actual := probe.capture()
	var tip_xf := skeleton.global_transform * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 2, 0)) * skin.get_bind_pose(1)
	var root_xf := skeleton.global_transform * skeleton.get_bone_global_rest(1) * skin.get_bind_pose(0)
	var blended: Vector3 = (tip_xf * arrays[Mesh.ARRAY_VERTEX][2]) * 0.4 + (root_xf * arrays[Mesh.ARRAY_VERTEX][2]) * 0.6
	selfcheck_metrics["analytic_bend_delta_m"] = actual[2].distance_to(blended)
	check(actual[2].distance_to(blended) < 0.00001 and actual[2].distance_to(rest[2]) > 0.01, "reader selfcheck: real articulated 40/60 weighted bend agrees with analytic result")
	var numeric_skin := Skin.new()
	numeric_skin.set_bind_count(2)
	for bind in 2:
		numeric_skin.set_bind_bone(bind, 1 - bind)
		numeric_skin.set_bind_pose(bind, skin.get_bind_pose(bind))
	instance.skin = numeric_skin
	probe.prepare(instance)
	check(Reader.delta(probe.capture(), actual) < 0.00001, "reader selfcheck: numeric binds preserve the same deliberately permuted mapping")
	var eight_arrays := arrays.duplicate()
	var eight_bones := PackedInt32Array()
	var eight_weights := PackedFloat32Array()
	for vertex in 4:
		for influence in 8:
			eight_bones.append(arrays[Mesh.ARRAY_BONES][vertex * 4 + influence] if influence < 4 else 0)
			eight_weights.append(arrays[Mesh.ARRAY_WEIGHTS][vertex * 4 + influence] if influence < 4 else 0.0)
	eight_arrays[Mesh.ARRAY_BONES] = eight_bones
	eight_arrays[Mesh.ARRAY_WEIGHTS] = eight_weights
	# The blended vertex genuinely uses slot7, mapped to a different bone.
	# A reader silently iterating four slots must fail this analytic comparison.
	eight_bones[16] = 0
	eight_weights[16] = .6
	eight_weights[17] = 0.0
	eight_bones[23] = 1
	eight_weights[23] = .4
	eight_arrays[Mesh.ARRAY_BONES] = eight_bones
	eight_arrays[Mesh.ARRAY_WEIGHTS] = eight_weights
	var eight_mesh := ArrayMesh.new()
	eight_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, eight_arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	instance.mesh = eight_mesh
	probe.prepare(instance)
	var encoded_eight: Array = eight_mesh.surface_get_arrays(0)
	check(encoded_eight[Mesh.ARRAY_WEIGHTS][23] > 0.3 and encoded_eight[Mesh.ARRAY_BONES][23] == 1, "reader selfcheck: serialized slot7 retains a nonzero influence from the distinct tip bone")
	check(probe.issues.is_empty() and Reader.delta(probe.capture(), actual) < 0.00001, "reader selfcheck: eight-influence surface uses its actual array format")
	var quantized_arrays := arrays.duplicate()
	var quantized_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS].duplicate()
	quantized_weights[8] = .25
	quantized_weights[9] = .75
	quantized_arrays[Mesh.ARRAY_WEIGHTS] = quantized_weights
	var quantized_mesh := ArrayMesh.new()
	quantized_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quantized_arrays)
	instance.mesh = quantized_mesh
	instance.skin = skin
	probe.prepare(instance)
	var encoded_weights: PackedFloat32Array = quantized_mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]
	var local_tip := skeleton.get_bone_global_pose(0) * skin.get_bind_pose(1)
	var local_root := skeleton.get_bone_global_pose(1) * skin.get_bind_pose(0)
	var quantized_expected: Vector3 = skeleton.global_transform * ((local_tip * arrays[Mesh.ARRAY_VERTEX][2]) * encoded_weights[8] + (local_root * arrays[Mesh.ARRAY_VERTEX][2]) * encoded_weights[9])
	check(probe.capture()[2].distance_to(quantized_expected) < 0.00001 and encoded_weights[8] + encoded_weights[9] < 1.0, "reader selfcheck: quantized weight sum never scales the external world translation")
	selfcheck_metrics["quantized_weight_sum"] = encoded_weights[8] + encoded_weights[9]
	selfcheck_metrics["quantized_affine_delta_m"] = probe.capture()[2].distance_to(quantized_expected)
	instance.mesh = mesh
	instance.skin = skin
	var saved := skin.get_bind_pose(1)
	skin.set_bind_pose(1, Transform3D(Basis.IDENTITY, Vector3(0.5, 0, 0)) * saved)
	probe.prepare(instance)
	check(Reader.delta(probe.capture(true), expected) > 0.1, "reader selfcheck: inverse-bind corruption reaches the geometric oracle")
	skin.set_bind_pose(1, saved)
	report.metrics["reader_selfchecks"] = selfcheck_metrics
	print("IMPORTED_READER_SELFCHECK ", JSON.stringify(selfcheck_metrics))
	group.free()

func _prepare_seams() -> void:
	var seen := {}
	for index in reader.referenced_vertices:
		var p := rest_points[index]
		var key := Vector3i(roundi(p.x * 1000000), roundi(p.y * 1000000), roundi(p.z * 1000000))
		if seen.has(key): seam_pairs.append(Vector2i(seen[key], index))
		else: seen[key] = index

func _weighted_joint_witnesses() -> void:
	var skeleton: Skeleton3D = visual.skeleton
	var evidence := {}
	for side in SIDES:
		for part in ["UpperLeg", "LowerLeg", "Foot", "LowerArm"]:
			var name_: String = side + part
			var bone := skeleton.find_bone(name_)
			var samples: Array[Vector2i] = []
			for surface in reader.surfaces:
				for vertex: int in surface.referenced:
					var weight := 0.0
					for influence in int(surface.influences):
						var slot: int = vertex * int(surface.influences) + influence
						if reader.bind_bones[surface.bones[slot]] == bone: weight += surface.weights[slot]
					if weight >= 0.5: samples.append(Vector2i(surface.surface, vertex))
			var before: PackedVector3Array = reader.subset(samples)
			var saved := skeleton.get_bone_pose_rotation(bone)
			skeleton.set_bone_pose_rotation(bone, saved * Quaternion(Vector3.RIGHT, 0.25))
			var movement := Reader.delta(before, reader.subset(samples))
			skeleton.set_bone_pose_rotation(bone, saved)
			skeleton.force_update_all_bone_transforms()
			check(samples.size() >= 3 and movement > 0.005, name_ + " drives actual weighted visible geometry, rather than an unused dummy joint")
			evidence[name_] = {"majority_weight_vertices": samples.size(), "actual_skin_witness_delta_m": movement}
	report.metrics["weighted_joint_witnesses"] = evidence

func _prepare_soles() -> void:
	for surface_index in reader.surfaces.size():
		var surface: Dictionary = reader.surfaces[surface_index]
		if not String(surface.material).contains("Rubber_soles"): continue
		for side in 2:
			for index: int in surface.referenced:
				if not String(surface.names[index]).begins_with(SIDES[side]): continue
				# Every actual rubber vertex participates. A pitch change can make
				# a vertex above the authored bottom become the posed lowest point.
				sole_samples[side].append(Vector2i(surface_index, index))
	for side in 2:
		var lowest := INF
		for sample: Vector2i in sole_samples[side]:
			var surface: Dictionary = reader.surfaces[sample.x]
			lowest = minf(lowest, rest_points[surface.offset + sample.y].y)
		for slot in sole_samples[side].size():
			var sample: Vector2i = sole_samples[side][slot]
			var surface: Dictionary = reader.surfaces[sample.x]
			if rest_points[surface.offset + sample.y].y <= lowest + 0.001: plant_slots[side].append(slot)
	check(plant_slots[0].size() >= 3 and plant_slots[1].size() >= 3, "independent bind geometry finds a real bottom support patch on both soles")
	report.metrics["sole_vertex_counts"] = [sole_samples[0].size(), sole_samples[1].size()]
	report.metrics["plant_vertex_counts"] = [plant_slots[0].size(), plant_slots[1].size()]

func _bone_world(name_: String, interpolated := false) -> Vector3:
	var skeleton: Skeleton3D = visual.skeleton
	var frame := skeleton.get_global_transform_interpolated() if interpolated else skeleton.global_transform
	if reader.use_final_pose: frame = reader.final_skeleton_presented if interpolated else reader.final_skeleton_world
	return frame * reader.bone_global_pose(skeleton.find_bone(name_)).origin

func _motion_metadata() -> Dictionary:
	var metadata := {"speed": Vector2(player.velocity.x, player.velocity.z).length(), "grounded": player.is_on_floor(), "model_y": visual.model.position.y, "targets": [], "targets_finite": true, "clip_clocks": {}}
	# Native target helpers are read only for frame-conversion diagnosis. They
	# supply no expected result to the independent Skin/stance acceptance.
	var imported: Node = visual.imported_hero
	var tree: AnimationTree = imported.get("animation_tree")
	# Godot AnimationNode exposes read-only timing on the actual graph instance:
	# https://github.com/godotengine/godot/blob/master/scene/animation/animation_tree.cpp
	for name_: String in PHASE_PROFILE:
		metadata.clip_clocks[name_] = {"position": tree.get("parameters/" + name_ + "/current_position"), "length": tree.get("parameters/" + name_ + "/current_length")}
	metadata["diagnostic_phase"] = imported.get("_cycle_phase")
	metadata["diagnostic_stride"] = imported.get("_cycle_stride")
	var anchors: Variant = imported.get("_foot_anchors")
	metadata["diagnostic_anchors"] = anchors.duplicate() if anchors is Array else []
	var targets: Variant = imported.get("_foot_targets")
	if targets is Array:
		for target: Node3D in targets:
			var world := target.global_position
			var presented := target.get_global_transform_interpolated().origin
			metadata.targets_finite = metadata.targets_finite and world.is_finite() and presented.is_finite()
			metadata.targets.append({"global": world, "presented": presented})
	return metadata

func _sample(interpolated: bool, delta: float) -> Dictionary:
	var frame: Transform3D = reader.final_reference_presented if interpolated else reader.final_reference_world
	var lows: Array[float] = []
	var centers: Array[Vector3] = []
	var local_skin := PackedVector3Array()
	var support_points: Array[PackedVector3Array] = []
	for side in 2:
		var samples: Array[Vector2i] = []
		samples.assign(sole_samples[side])
		var points: PackedVector3Array = reader.subset(samples, null, interpolated)
		var low := INF
		var center := Vector3.ZERO
		for p in points:
			low = minf(low, p.y)
			center += p
			local_skin.append(frame.affine_inverse() * p)
		lows.append(low)
		centers.append(center / maxf(1.0, points.size()))
		var support := PackedVector3Array()
		for slot: int in plant_slots[side]: support.append(points[slot])
		support_points.append(support)
	var poses: Array[Transform3D] = []
	for name_ in ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		poses.append(reader.bone_local_pose(visual.skeleton.find_bone(name_)))
	var ankles_world: Array[Vector3] = []
	var ankles_presented: Array[Vector3] = []
	var hips_presented: Array[Vector3] = []
	var leg_lengths: Array[float] = []
	for side in SIDES:
		ankles_world.append(_bone_world(side + "Foot", false))
		ankles_presented.append(_bone_world(side + "Foot", true))
		hips_presented.append(_bone_world(side + "UpperLeg", true))
		var skeleton: Skeleton3D = visual.skeleton
		leg_lengths.append(skeleton.get_bone_rest(skeleton.find_bone(side + "LowerLeg")).origin.length() + skeleton.get_bone_rest(skeleton.find_bone(side + "Foot")).origin.length())
	var profile := "Run" if float(reader.final_metadata.speed) > 6.0 else "Jog"
	var clock: Dictionary = reader.final_metadata.clip_clocks[profile]
	var phase := -1.0
	if clock.position is float and clock.length is float and clock.length > 0.0:
		phase = fposmod(float(clock.position) / float(clock.length), 1.0)
	return {"delta": delta, "root": reader.final_reference_world.origin, "frame": reader.final_physics_frame, "fraction": reader.final_interpolation_fraction,
		"serial": reader.final_pose_serial, "render_frame": reader.final_pose_frame,
		"hips": _bone_world("Hips", interpolated).y - frame.origin.y, "head": _bone_world("Head", interpolated).y - frame.origin.y,
		"speed": reader.final_metadata.speed, "grounded": reader.final_metadata.grounded, "model_y": reader.final_metadata.model_y, "low": lows, "center": centers, "skin": local_skin, "poses": poses,
		"ankles_world": ankles_world, "ankles_presented": ankles_presented, "skeleton_world_origin": reader.final_skeleton_world.origin,
		"skeleton_presented_origin": reader.final_skeleton_presented.origin, "native_diagnostic": reader.final_metadata.duplicate(true),
		"phase": phase, "clip_clock": clock, "support_points": support_points, "hips_presented": hips_presented, "leg_lengths": leg_lengths}

func _inspect_physics(delta: float) -> void:
	if not measuring: return
	var root_movement := player.global_position - previous_physical_root
	physical_root_distance += Vector2(root_movement.x, root_movement.z).length()
	physical_root_seconds += delta
	previous_physical_root = player.global_position
	temporal_physics.append(_sample(false, delta))
	_inspect_bones()

func _inspect_final_pose() -> void:
	var tick_usec: int = reader.final_time_usec
	var delta := (tick_usec - previous_final_time_usec) / 1000000.0 if previous_final_time_usec != 0 else 1.0 / 120.0
	previous_final_time_usec = tick_usec
	if not measuring: return
	var sample := _sample(true, delta)
	temporal_render.append(sample)
	if sample.render_frame != Engine.get_process_frames() or (not previous_render.is_empty() and sample.serial <= previous_render.serial): stale_final_snapshots += 1
	if not previous_render.is_empty() and sample.frame == previous_render.frame and sample.fraction > previous_render.fraction + 0.005:
		render_intervals += 1
		if _pose_delta(sample.poses, previous_render.poses) <= 0.000001: held_bones += 1
		if Reader.delta(sample.skin, previous_render.skin) <= 0.000001: held_skin += 1
		if sample.root.distance_to(previous_render.root) > 0.000001: render_root_changes += 1
	previous_render = sample

func _metrics(samples: Array[Dictionary]) -> Dictionary:
	var result := {"samples": samples.size(), "seconds": 0.0, "hip_min": INF, "hip_max": -INF, "head_min": INF, "head_max": -INF,
		"lift": 0.0, "penetration": 0.0, "longest_gap": 0.0, "speed_min": INF, "speed_max": -INF, "grounded": 0,
		"maximum_model_y_adjustment_m": 0.0,
		"nonfinite_native_target_samples": 0,
		"first_contact_samples": [],
		"contact_intervals": [0, 0], "contact_travel_m": [0.0, 0.0], "contact_seconds": [0.0, 0.0], "mean_slip_mps": [INF, INF]}
	var previous := {}
	var gap := 0.0
	for sample in samples:
		result.seconds += sample.delta
		result.hip_min = minf(result.hip_min, sample.hips)
		result.hip_max = maxf(result.hip_max, sample.hips)
		result.head_min = minf(result.head_min, sample.head)
		result.head_max = maxf(result.head_max, sample.head)
		result.lift = maxf(result.lift, maxf(sample.low[0], sample.low[1]))
		result.penetration = maxf(result.penetration, -minf(sample.low[0], sample.low[1]))
		result.speed_min = minf(result.speed_min, sample.speed)
		result.speed_max = maxf(result.speed_max, sample.speed)
		result.maximum_model_y_adjustment_m = maxf(result.maximum_model_y_adjustment_m, absf(sample.model_y - model_base_y))
		if not sample.native_diagnostic.targets_finite: result.nonfinite_native_target_samples += 1
		if sample.grounded: result.grounded += 1
		if minf(sample.low[0], sample.low[1]) > 0.025:
			gap += sample.delta
			result.longest_gap = maxf(result.longest_gap, gap)
		else: gap = 0.0
		if not previous.is_empty():
			for side in 2:
				if absf(sample.low[side]) <= 0.01 and absf(previous.low[side]) <= 0.01 and absf(sample.low[side] - previous.low[side]) <= 0.003:
					var movement: Vector3 = sample.center[side] - previous.center[side]
					result.contact_intervals[side] += 1
					result.contact_seconds[side] += sample.delta
					result.contact_travel_m[side] += Vector2(movement.x, movement.z).length()
					if result.contact_intervals[side] <= 2:
						var targets: Array = sample.native_diagnostic.targets
						var target: Dictionary = targets[side] if targets.size() > side else {}
						var anchor: Vector3 = sample.native_diagnostic.diagnostic_anchors[side] if sample.native_diagnostic.diagnostic_anchors.size() > side else Vector3.INF
						result.first_contact_samples.append({"side": SIDES[side], "serial": sample.serial, "physics_frame": sample.frame, "render_frame": sample.render_frame, "fraction": sample.fraction,
							"phase_diagnostic": sample.native_diagnostic.diagnostic_phase, "stride_diagnostic": sample.native_diagnostic.diagnostic_stride,
							"actual_animation_tree_clock": sample.clip_clock, "actual_animation_tree_phase": sample.phase,
							"native_targets_finite": sample.native_diagnostic.targets_finite,
							"sole_low_m": sample.low[side], "sole_centre": _v(sample.center[side]), "sole_step_m": Vector2(movement.x, movement.z).length(),
							"actual_final_foot_world": _v(sample.ankles_world[side]), "actual_final_foot_presented": _v(sample.ankles_presented[side]),
							"anchor_world_diagnostic": _v(anchor), "hip_presented": _v(sample.hips_presented[side]), "leg_length_m": sample.leg_lengths[side],
							"anchor_to_hip_m": anchor.distance_to(sample.hips_presented[side]) if anchor.is_finite() else -1.0,
							"target_presented_to_anchor_m": anchor.distance_to(target.presented) if anchor.is_finite() and target.has("presented") and Vector3(target.presented).is_finite() else -1.0,
							"target_world": _v(target.global) if target.has("global") else [], "target_presented": _v(target.presented) if target.has("presented") else [],
							"skeleton_world_origin": _v(sample.skeleton_world_origin), "skeleton_presented_origin": _v(sample.skeleton_presented_origin)})
		previous = sample
	result["hips_p2p"] = result.hip_max - result.hip_min
	result["head_p2p"] = result.head_max - result.head_min
	for side in 2: result.mean_slip_mps[side] = result.contact_travel_m[side] / maxf(0.000001, result.contact_seconds[side])
	return result

func _phase_core_metrics(samples: Array[Dictionary], speed: float) -> Dictionary:
	var profile := "Run" if speed > 6.0 else "Jog"
	var duration: float = SourceAnimations.get_animation(PHASE_PROFILE[profile].clip).length
	var result := {"profile": profile, "valid_clock": true, "cycles": 0.0, "phase_rate_hz": 0.0, "steps_per_second": 0.0, "actual_stride_m": 0.0,
		"core_intervals": [0, 0], "complete_core_episodes": [0, 0], "short_core_episodes": [0, 0], "maximum_core_ground_error_m": [0.0, 0.0],
		"worst_support_vertex_slip_mps": [-1.0, -1.0]}
	var seconds := 0.0
	for index in samples.size():
		var sample := samples[index]
		if not is_finite(sample.phase) or sample.phase < 0.0 or not (sample.clip_clock.length is float) or absf(float(sample.clip_clock.length) - duration) > 0.0001:
			result.valid_clock = false
			return result
		if index == 0: continue
		var advance := fposmod(float(sample.phase) - float(samples[index - 1].phase), 1.0)
		if advance > 0.5: result.valid_clock = false
		result.cycles += advance
		seconds += sample.delta
	result.phase_rate_hz = result.cycles / maxf(seconds, 0.000001)
	result.steps_per_second = 2.0 * result.phase_rate_hz
	result.actual_stride_m = speed / maxf(result.phase_rate_hz, 0.000001)
	var edge: float = PHASE_EDGE_SECONDS * result.phase_rate_hz
	var duty: float = PHASE_PROFILE[profile].duty
	result["excluded_edge_seconds"] = PHASE_EDGE_SECONDS
	result["core_phase_range"] = [edge, duty - edge]
	for side in 2:
		var travel := PackedFloat64Array()
		travel.resize(plant_slots[side].size())
		var core_seconds := 0.0
		var previous := {}
		var previous_core := false
		var episode_started := false
		var episode_samples := 0
		for sample in samples:
			var phase := fposmod(float(sample.phase) + (0.5 if side == 1 else 0.0), 1.0)
			var core := phase >= edge and phase <= duty - edge
			if core:
				for point: Vector3 in sample.support_points[side]: result.maximum_core_ground_error_m[side] = maxf(result.maximum_core_ground_error_m[side], absf(point.y))
				if not previous_core:
					episode_started = not previous.is_empty()
					episode_samples = 0
				episode_samples += 1
				if previous_core:
					result.core_intervals[side] += 1
					core_seconds += sample.delta
					for point in travel.size():
						var movement: Vector3 = sample.support_points[side][point] - previous.support_points[side][point]
						travel[point] += Vector2(movement.x, movement.z).length()
			elif previous_core and episode_started:
				result.complete_core_episodes[side] += 1
				if episode_samples < 2: result.short_core_episodes[side] += 1
			previous = sample
			previous_core = core
		if core_seconds > 0.0 and not travel.is_empty():
			var worst := 0.0
			for distance in travel: worst = maxf(worst, distance / core_seconds)
			result.worst_support_vertex_slip_mps[side] = worst
	return result

func _v(point: Vector3) -> Array:
	return [point.x, point.y, point.z] if point.is_finite() else []

func _temporal_limits(speed: float) -> void:
	var physics := _metrics(temporal_physics)
	var presented := _metrics(temporal_render)
	var phase_physics := _phase_core_metrics(temporal_physics, speed)
	var phase_presented := _phase_core_metrics(temporal_render, speed)
	var label := "actual %.0fm/s" % speed
	check(physics.samples >= 115 and physics.seconds >= 2.0 and physics.grounded == physics.samples and absf(physics.speed_min - speed) < 0.1 and absf(physics.speed_max - speed) < 0.1, label + " remains physically grounded at requested speed for two seconds")
	var physical_root_speed := physical_root_distance / maxf(0.000001, physical_root_seconds)
	check(absf(physical_root_speed - speed) < 0.1, label + " actual physical displacement agrees with controller speed without imported root motion")
	check(render_intervals >= 20 and temporal_render.size() > temporal_physics.size() + 20, label + " observes real render-only intervals between physics steps")
	check(held_bones == 0 and held_skin == 0, label + " actual bones and weighted sole vertices advance in render-only intervals")
	check(stale_final_snapshots == 0, label + " every presented sample uses fresh final bones and root/frame/fraction from the same skeleton_updated event")
	check(physics.nonfinite_native_target_samples == 0 and presented.nonfinite_native_target_samples == 0, label + " actual native Skin control targets stay finite")
	check(render_root_changes == 0, label + " render animation never moves raw physical root")
	check(maxf(physics.maximum_model_y_adjustment_m, presented.maximum_model_y_adjustment_m) <= 0.000001, label + " no per-render model-Y lift hides foot clipping")
	check(maxf(physics.penetration, presented.penetration) <= FLOOR_PENETRATION, label + " actual soles penetrate real floor by at most 12mm")
	check(maxf(physics.hips_p2p, presented.hips_p2p) <= BODY_BOB and maxf(physics.head_p2p, presented.head_p2p) <= BODY_BOB, label + " hips and head bob stay within 3cm peak-to-peak")
	check(phase_presented.valid_clock and phase_physics.valid_clock and phase_presented.cycles >= 2.0, label + " plant phase comes from the active AnimationTree clip clock")
	var phase_ok: bool = phase_presented.valid_clock and phase_physics.valid_clock
	for side in 2:
		var supported: bool = phase_presented.complete_core_episodes[side] >= 2 and phase_presented.short_core_episodes[side] == 0 and phase_presented.core_intervals[side] >= 2 and phase_presented.maximum_core_ground_error_m[side] <= FLOOR_PENETRATION
		phase_ok = check(supported, label + " alternating declared plant cores have at least two actual grounded support-patch samples: " + SIDES[side]) and phase_ok
		phase_ok = check(phase_presented.worst_support_vertex_slip_mps[side] >= 0.0 and phase_presented.worst_support_vertex_slip_mps[side] <= CONTACT_SLIP_MPS, label + " real presented sole support vertices retain 0.8m/s stance slip budget: " + SIDES[side]) and phase_ok
	if not phase_ok: report["phase_gait_acceptance"] = "FAIL"
	elif report.phase_gait_acceptance != "FAIL": report["phase_gait_acceptance"] = "CORE_PLANT_MEASURED; cadence/naturalness manual NOT_RUN"
	report.metrics[label] = {"physics": physics, "render": presented, "phase_physics_diagnostic": phase_physics, "phase_presented": phase_presented,
		"render_only_intervals": render_intervals, "held_bones": held_bones, "held_skin": held_skin, "render_root_changes": render_root_changes, "stale_final_snapshots": stale_final_snapshots, "actual_physical_root_speed_mps": physical_root_speed}
	# Root accepted independent review: these guards describe the superseded
	# low-step gait, not universal run/sprint bounds. Keep the raw evidence; new
	# phase/envelope limits must be pinned independently before gait acceptance.
	report.metrics[label]["historical_low_step_diagnostics"] = {"sole_lift_limit_m": HISTORICAL_SOLE_LIFT,
		"sole_lift_would_pass": maxf(physics.lift, presented.lift) <= HISTORICAL_SOLE_LIFT,
		"gap_limit_seconds": HISTORICAL_CONTACT_GAP_SECONDS, "gap_would_pass": maxf(physics.longest_gap, presented.longest_gap) <= HISTORICAL_CONTACT_GAP_SECONDS}
	var summary: Dictionary = report.metrics[label].duplicate(true)
	summary.physics.erase("first_contact_samples")
	summary.render.erase("first_contact_samples")
	print("IMPORTED_HERO_MOTION ", JSON.stringify(summary))

func _pose_delta(first: Array, second: Array) -> float:
	if first.size() != second.size(): return INF
	var result := 0.0
	for index in first.size():
		var a: Transform3D = first[index]
		var b: Transform3D = second[index]
		result = maxf(result, a.origin.distance_to(b.origin))
		result = maxf(result, a.basis.x.distance_to(b.basis.x))
		result = maxf(result, a.basis.y.distance_to(b.basis.y))
		result = maxf(result, a.basis.z.distance_to(b.basis.z))
	return result

func _inspect_integrity() -> void:
	var points: PackedVector3Array = reader.capture()
	for surface in reader.surfaces:
		for vertex: int in surface.referenced:
			var point := points[surface.offset + vertex]
			geometry_metrics.finite = geometry_metrics.finite and point.is_finite()
			if point.y < geometry_metrics.minimum_visible_skin_y_m_diagnostic:
				geometry_metrics.minimum_visible_skin_y_m_diagnostic = point.y
				geometry_metrics.lowest_visible_skin_source = {"material": surface.material, "owner": surface.names[vertex], "vertex": vertex, "world": _v(point)}
	for pair in seam_pairs: geometry_metrics.maximum_seam_m = maxf(geometry_metrics.maximum_seam_m, points[pair.x].distance_to(points[pair.y]))
	_inspect_bones()
	var joints := ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm"]
	for surface in reader.surfaces:
		var indices: PackedInt32Array = surface.indices
		for offset in range(0, indices.size() - 2, 3):
			var a: int = indices[offset]
			var b: int = indices[offset + 1]
			var c: int = indices[offset + 2]
			if surface.names[a] not in joints and surface.names[b] not in joints and surface.names[c] not in joints: continue
			a += int(surface.offset)
			b += int(surface.offset)
			c += int(surface.offset)
			var rest_area := (rest_points[b] - rest_points[a]).cross(rest_points[c] - rest_points[a]).length()
			if rest_area < 0.00000001: continue
			geometry_metrics.joint_triangles_inspected += 1
			var posed_area := (points[b] - points[a]).cross(points[c] - points[a]).length()
			if posed_area / rest_area < geometry_metrics.minimum_joint_triangle_area_ratio:
				geometry_metrics.minimum_joint_triangle_area_ratio = posed_area / rest_area
				geometry_metrics.minimum_area_witness = {"material": surface.material, "vertices": [a - int(surface.offset), b - int(surface.offset), c - int(surface.offset)], "owners": [surface.names[a - int(surface.offset)], surface.names[b - int(surface.offset)], surface.names[c - int(surface.offset)]], "rest": [_v(rest_points[a]), _v(rest_points[b]), _v(rest_points[c])], "posed": [_v(points[a]), _v(points[b]), _v(points[c])], "serial": reader.final_pose_serial, "source_clocks": reader.final_metadata.clip_clocks.duplicate(true)}
			for edge in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
				var rest_length := rest_points[edge.x].distance_to(rest_points[edge.y])
				if rest_length > 0.001:
					var ratio := points[edge.x].distance_to(points[edge.y]) / rest_length
					if ratio > geometry_metrics.maximum_joint_edge_ratio:
						geometry_metrics.maximum_joint_edge_ratio = ratio
						geometry_metrics.maximum_edge_witness = {"material": surface.material, "vertices": [edge.x - int(surface.offset), edge.y - int(surface.offset)], "rest_length_m": rest_length, "posed_length_m": points[edge.x].distance_to(points[edge.y]), "rest": [_v(rest_points[edge.x]), _v(rest_points[edge.y])], "posed": [_v(points[edge.x]), _v(points[edge.y])], "serial": reader.final_pose_serial, "source_clocks": reader.final_metadata.clip_clocks.duplicate(true)}

func _inspect_bones() -> void:
	var skeleton: Skeleton3D = visual.skeleton
	for bone in skeleton.get_bone_count():
		var pose: Transform3D = reader.bone_local_pose(bone)
		geometry_metrics.finite = geometry_metrics.finite and pose.origin.is_finite() and pose.basis.is_finite()
		if skeleton.get_bone_name(bone) not in ["Root", "Hips"]:
			geometry_metrics.maximum_limb_length_error_m = maxf(geometry_metrics.maximum_limb_length_error_m, absf(pose.origin.length() - skeleton.get_bone_rest(bone).origin.length()) * skeleton.global_basis.get_scale().y)
		geometry_metrics.maximum_bone_scale_error = maxf(geometry_metrics.maximum_bone_scale_error, pose.basis.get_scale().distance_to(Vector3.ONE))
	for side in 2:
		var hip := _bone_world(SIDES[side] + "UpperLeg")
		var knee := _bone_world(SIDES[side] + "LowerLeg")
		var ankle := _bone_world(SIDES[side] + "Foot")
		var bend := rad_to_deg((knee - hip).angle_to(ankle - knee))
		geometry_metrics.maximum_knee_bend_degrees[side] = maxf(geometry_metrics.maximum_knee_bend_degrees[side], bend)
		var chord := hip.lerp(ankle, hip.distance_to(knee) / (hip.distance_to(knee) + knee.distance_to(ankle)))
		geometry_metrics.minimum_knee_forward_m = minf(geometry_metrics.minimum_knee_forward_m, (knee - chord).dot(-look.global_basis.z.normalized()))
		var shoulder := _bone_world(SIDES[side] + "UpperArm")
		var elbow := _bone_world(SIDES[side] + "LowerArm")
		var hand := _bone_world(SIDES[side] + "Hand")
		geometry_metrics.maximum_elbow_bend_degrees[side] = maxf(geometry_metrics.maximum_elbow_bend_degrees[side], rad_to_deg((elbow - shoulder).angle_to(hand - elbow)))

func _lifecycle() -> void:
	var failures_before := failures.size()
	player.input_enabled = false
	var stopped := player.global_position
	check(player.is_on_floor() and Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "real input release settles physical actor")
	var stopped_samples: Array[Vector2i] = []
	stopped_samples.assign(sole_samples[0] + sole_samples[1])
	var stopped_soles: PackedVector3Array = reader.subset(stopped_samples, player)
	await create_timer(0.2).timeout
	check(Reader.delta(stopped_soles, reader.subset(stopped_samples, player)) < 0.025, "stopped root does not continue cycling grounded footsteps")
	var before_pause: PackedVector3Array = reader.capture()
	paused = true
	await create_timer(0.08, true, false, true).timeout
	check(Reader.delta(before_pause, reader.capture()) <= 0.000001 and player.global_position.distance_to(stopped) <= 0.000001, "pause freezes actual physical actor and skin")
	paused = false
	player.place(player.global_position + Vector3.RIGHT * 25.0, 0.0)
	var relocated := player.global_position
	var clean := true
	var teleport_frames: Array[Dictionary] = []
	for frame in 8:
		await observer.rendered
		var root_error := player.get_global_transform_interpolated().origin.distance_to(relocated)
		var skin_distance := 0.0
		var cached_distance := 0.0
		# A rigid actor teleport updates the renderer's Node3D world matrix even
		# when no bone changed and Skeleton3D emits no new pose event. Rendering
		# reuses the last final local Skin matrices under this CURRENT world frame.
		var current_skeleton: Transform3D = visual.skeleton.get_global_transform_interpolated()
		var reframe: Transform3D = current_skeleton * reader.final_skeleton_world.affine_inverse()
		for point: Vector3 in reader.capture():
			cached_distance = maxf(cached_distance, point.distance_to(relocated))
			skin_distance = maxf(skin_distance, (reframe * point).distance_to(relocated))
		clean = clean and root_error < 0.02 and skin_distance < 3.0
		teleport_frames.append({"render_frame": Engine.get_process_frames(), "pose_frame": reader.final_pose_frame, "pose_serial": reader.final_pose_serial,
			"root_interpolated_error_m": root_error, "maximum_actual_skin_distance_m": skin_distance, "maximum_cached_skin_distance_m_diagnostic": cached_distance, "cached_skeleton_presented": _v(reader.final_skeleton_presented.origin),
			"current_skeleton_presented": _v(current_skeleton.origin), "relocated_root": _v(relocated)})
	report.metrics["teleport"] = teleport_frames
	check(clean, "real place has no interpolation bridge to previous actor or skin position")
	player.force_hide_mode(&"box")
	await observer.stepped
	await observer.rendered
	var hidden: PackedVector3Array = reader.capture()
	var frozen := true
	for frame in 6:
		await observer.rendered
		frozen = frozen and not look.visible and Reader.delta(hidden, reader.capture()) <= 0.000001
	check(frozen, "hidden real hero cannot resurrect a walking skin between physics updates")
	player.force_hide_mode(&"none")
	await observer.stepped
	var reset_serial: int = reader.final_pose_serial
	visual.reset_pose()
	check(await _await_new_final(reader, reset_serial), "show/reset reaches a fresh final native skeleton snapshot")
	var reset: PackedVector3Array = reader.capture()
	reset_serial = reader.final_pose_serial
	visual.reset_pose()
	check(await _await_new_final(reader, reset_serial), "second reset reaches another fresh final native skeleton snapshot")
	check(look.visible and Reader.delta(reset, reader.capture()) <= SEAM_EPS, "show and repeated reset restore the current pose deterministically")
	check(player.global_position.distance_to(relocated) < 0.02, "visual lifecycle does not modify physical root")
	report["lifecycle"] = "PASS" if failures.size() == failures_before else "FAIL"

func _seated_chain() -> void:
	var failures_before := failures.size()
	var car := Car.build()
	fixture.add_child(car)
	var driver: Node3D = car.get_node("Body/Driver")
	var seated: Node3D = driver.uniform_visual
	var frame: Node3D = car.get_node("Body")
	var seated_reader := Reader.new()
	seated_reader.prepare(seated.uniform_mesh, frame)
	check(seated.imported_hero != null and seated_reader.issues.is_empty(), "real Lada Driver consumes the same imported GLB pipeline")
	await observer.rendered
	check(seated_reader.final_pose_serial > 0, "independent Driver observer sees final native modifier output")
	seated_reader.use_final_pose = true
	var bind_box := Reader.bounds(seated_reader.referenced(seated_reader.capture(true)))
	check(absf(bind_box.size.y - HEIGHT) <= HEIGHT_EPS and seated.model.global_basis.get_scale().distance_to(visual.model.global_basis.get_scale()) <= 0.00001, "actual Lada bind height and intrinsic world scale equal full standing hero")
	var before: PackedVector3Array = seated_reader.capture(false, frame)
	var body_box := Reader.bounds(seated_reader.referenced(before))
	check(body_box.position.y >= 0.31 and body_box.end.y <= 1.355 and body_box.end.y >= 1.20, "actual seated full-size skin remains above underbody and below roof lining")
	var intrinsic_error := 0.0
	var scale_error := 0.0
	for bone in seated.skeleton.get_bone_count():
		var pose := seated_reader.bone_local_pose(bone)
		if seated.skeleton.get_bone_name(bone) not in ["Root", "Hips"]:
			intrinsic_error = maxf(intrinsic_error, absf(pose.origin.length() - seated.skeleton.get_bone_rest(bone).origin.length()) * seated.skeleton.global_basis.get_scale().y)
		scale_error = maxf(scale_error, pose.basis.get_scale().distance_to(Vector3.ONE))
	check(intrinsic_error <= SEAM_EPS and scale_error <= 0.00001, "actual Driver preserves full head/neck/limb rest lengths and bone scales")
	for side in SIDES:
		var skeleton: Skeleton3D = seated.skeleton
		var hip: Vector3 = seated_reader.bone_global_pose(skeleton.find_bone(side + "UpperLeg")).origin
		var knee: Vector3 = seated_reader.bone_global_pose(skeleton.find_bone(side + "LowerLeg")).origin
		var ankle: Vector3 = seated_reader.bone_global_pose(skeleton.find_bone(side + "Foot")).origin
		var bend := rad_to_deg((knee - hip).angle_to(ankle - knee))
		check(bend >= 25.0 and bend <= 150.0, "full-size driver uses an articulated unfolded seated knee: " + side)
	check(body_box.size.y < HEIGHT - 0.05, "full-size driver fits using actual seated articulation")
	var reset_serial := seated_reader.final_pose_serial
	seated.reset_pose()
	check(await _await_new_final(seated_reader, reset_serial), "real Driver reset reaches a fresh final native skeleton snapshot")
	var reset_pose: PackedVector3Array = seated_reader.capture(false, frame)
	reset_serial = seated_reader.final_pose_serial
	seated.reset_pose()
	check(await _await_new_final(seated_reader, reset_serial) and Reader.delta(reset_pose, seated_reader.capture(false, frame)) <= SEAM_EPS, "real Driver repeated reset preserves the same clip-time-zero cabin pose and steering grips")
	var stable := true
	var tree: AnimationTree = seated.imported_hero.animation_tree
	var action_node := (tree.tree_root as AnimationNodeBlendTree).get_node("Action") as AnimationNodeAnimation
	var previous_clock := float(tree.get("parameters/Action/current_position"))
	var driving_length: float = SourceAnimations.get_animation("Driving").length
	for sample in 12:
		seated.update_locomotion(Vector3.FORWARD * 8.0, false, &"punch", 1.0 / 60.0, 6.0, 0.7)
		await observer.rendered
		var clock := float(tree.get("parameters/Action/current_position"))
		var advance := fposmod(clock - previous_clock, driving_length)
		stable = stable and action_node.animation == &"Driving" and absf(advance - observer.render_delta) <= 0.0001
		previous_clock = clock
	check(stable, "seated priority keeps the real Driving clip advancing normally despite stale movement/air/action samples")
	_cabin_oracle(car, seated, seated_reader)
	var xray: MeshInstance3D = seated.build_xray()
	check(xray.mesh == seated.uniform_mesh.mesh and xray.skin == seated.uniform_mesh.skin and xray.get_node(xray.skeleton) == seated.skeleton, "real imported XRay retains the active mesh/Skin/Skeleton binding")
	car.free()
	report["cabin"] = "PASS" if failures.size() == failures_before else "FAIL"

func _await_new_final(probe: RefCounted, previous_serial: int) -> bool:
	# A manual Skeleton3D.advance() inside reset may already emit the required
	# final snapshot synchronously. That is a new serial after this reset, not
	# the stale pre-reset cache. A static pose need not dirty the next frame.
	if probe.final_pose_serial > previous_serial: return true
	for frame in 6:
		await observer.rendered
		if probe.final_pose_serial > previous_serial: return true
	return false

func _cabin_oracle(car: Node3D, seated: Node3D, seated_reader: RefCounted) -> void:
	var frame: Node3D = car.get_node("Body")
	var points: PackedVector3Array = seated_reader.capture(false, frame)
	var body_triangles: Array[PackedVector3Array] = seated_reader.triangles(points)
	var interior: MeshInstance3D = frame.get_node("Interior")
	var walls: Array[PackedVector3Array] = []
	var cloth: Array[PackedVector3Array] = []
	var dark_points := PackedVector3Array()
	for surface in interior.mesh.get_surface_count():
		var slot: String = interior.mesh.get_meta("slots")[surface]
		if slot not in ["dark", "cloth"]: continue
		var arrays := interior.mesh.surface_get_arrays(surface)
		var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index in raw.size(): indices.append(index)
		for offset in range(0, indices.size() - 2, 3):
			var triangle := PackedVector3Array()
			for index in 3: triangle.append(frame.to_local(interior.to_global(raw[indices[offset + index]])))
			if slot == "cloth": cloth.append(triangle)
			else:
				dark_points.append_array(triangle)
				if (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).length() * 0.5 > 0.02: walls.append(triangle)
	var unique := {}
	for point: Vector3 in seated_reader.referenced(points): unique[Vector3i(roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000))] = point
	for triangle in body_triangles:
		var centre := (triangle[0] + triangle[1] + triangle[2]) / 3.0
		unique[Vector3i(roundi(centre.x * 1000000), roundi(centre.y * 1000000), roundi(centre.z * 1000000))] = centre
	var doors := 0
	var firewall := 0
	var firewall_depth := 0.0
	var deepest_firewall_point := Vector3.ZERO
	var deepest_firewall_triangle := PackedVector3Array()
	var seat_depth := 0.0
	var deepest_seat_point := Vector3.ZERO
	var deepest_seat_triangle := PackedVector3Array()
	var support_gap := INF
	for point: Vector3 in unique.values():
		var left := -INF
		var right := INF
		var toe_board := -INF
		var toe_board_triangle := PackedVector3Array()
		for triangle in walls:
			var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
			var centre := (triangle[0] + triangle[1] + triangle[2]) / 3.0
			if absf(normal.x) > 0.95 and absf(centre.x) > 0.5:
				var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(-2, point.y, point.z), Vector3(2, point.y, point.z), triangle[0], triangle[1], triangle[2])
				if hit != null:
					if hit.x < 0.0: left = maxf(left, hit.x)
					else: right = minf(right, hit.x)
			if absf(normal.z) > 0.5 and centre.z < -0.5:
				var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(point.x, point.y, -2), Vector3(point.x, point.y, 2), triangle[0], triangle[1], triangle[2])
				if hit != null and hit.z > toe_board:
					toe_board = hit.z
					toe_board_triangle = triangle
		if point.x < left - 0.001 or point.x > right + 0.001: doors += 1
		if point.z < toe_board - 0.001:
			firewall += 1
			if toe_board - point.z > firewall_depth:
				firewall_depth = toe_board - point.z
				deepest_firewall_point = point
				deepest_firewall_triangle = toe_board_triangle
		if point.y > 0.9: continue
		var hits: Array[float] = []
		var nearest := INF
		var nearest_triangle := PackedVector3Array()
		for triangle in cloth:
			var hit: Variant = Geometry3D.segment_intersects_triangle(point, point + Vector3(.123, .067, 1).normalized() * 5.0, triangle[0], triangle[1], triangle[2])
			if hit != null: hits.append(point.distance_to(hit))
			var distance := Clearance.point_triangle_distance(point, triangle[0], triangle[1], triangle[2])
			if distance < nearest:
				nearest = distance
				nearest_triangle = triangle
		hits.sort()
		var crossings := 0
		var previous := -INF
		for distance in hits:
			if distance - previous > 0.000001:
				crossings += 1
				previous = distance
		if crossings % 2 == 1 and nearest > seat_depth:
			seat_depth = nearest
			deepest_seat_point = point
			deepest_seat_triangle = nearest_triangle
		if point.y < 0.55 and absf(point.x - Driver.LADA_SEAT_X) < 0.23 and point.z > -0.35 and point.z < 0.15: support_gap = minf(support_gap, nearest)
	check(not walls.is_empty() and not cloth.is_empty() and doors == 0, "all actual indexed skin vertices/triangle centres stay inside real door lining")
	check(firewall == 0, "all actual indexed skin vertices/triangle centres stay behind real toe-board/dashboard")
	check(seat_depth <= 0.001, "actual body stays outside real solid cushion/backrest core within 1mm")
	check(support_gap <= 0.01, "actual body contacts its real cushion within 1cm")
	var body_source := _skin_source_at(seated_reader, points, deepest_seat_point)
	var firewall_source := _skin_source_at(seated_reader, points, deepest_firewall_point) if firewall > 0 else {}
	var firewall_witness := {"depth_along_z_m": firewall_depth, "body_point": _v(deepest_firewall_point), "actual_wall_triangle": str(deepest_firewall_triangle), "body_source": firewall_source}
	report.metrics["cabin"] = {"seat_core_penetration_m": seat_depth, "deepest_body_point": _v(deepest_seat_point), "deepest_body_source": body_source, "nearest_seat_triangle": str(deepest_seat_triangle), "seat_support_gap_m": support_gap, "door_violations": doors, "firewall_violations": firewall, "firewall_witness": firewall_witness}
	var spec: Dictionary = Car.SEDANS[Car.PLAYER_MODEL]
	var windscreen_bottom: Vector2 = spec["ws"][0]
	var wheel_centre := Vector3(Driver.LADA_STEERING_X, float(spec["belt"]) + 0.13, windscreen_bottom.y + 0.30)
	var wheel_distance := INF
	var head_triangles: Array[PackedVector3Array] = seated_reader.triangles(points, ["Head"])
	var ring_present := true
	for section in 12:
		var angle := TAU * section / 12.0
		var next := TAU * (section + 1) / 12.0
		var first := wheel_centre + (Vector3.RIGHT * cos(angle) + Vector3(0, .87, -.50) * sin(angle)) * .18
		var second := wheel_centre + (Vector3.RIGHT * cos(next) + Vector3(0, .87, -.50) * sin(next)) * .18
		var actual_ring_distance := INF
		for point in dark_points: actual_ring_distance = minf(actual_ring_distance, point.distance_to(first))
		ring_present = ring_present and actual_ring_distance <= .015
		for triangle in head_triangles: wheel_distance = minf(wheel_distance, Clearance.segment_triangle_distance(first, second, triangle[0], triangle[1], triangle[2]))
	check(ring_present and not head_triangles.is_empty() and wheel_distance >= 0.019, "actual indexed full head clears the real steering tube by 5mm")
	var grip_errors: Array[float] = []
	var visible_hand_errors: Array[float] = []
	var palm_centre_errors: Array[float] = []
	var hand_diagnostics: Array[Dictionary] = []
	for side in 2:
		var bone: int = seated.skeleton.find_bone(SIDES[side] + "Hand")
		var wrist: Vector3 = frame.to_local(seated.skeleton.to_global(seated_reader.bone_global_pose(bone).origin))
		grip_errors.append(wrist.distance_to(Driver.LADA_GRIPS[side]))
		var hand_error := INF
		for triangle: PackedVector3Array in seated_reader.triangles(points, [SIDES[side] + "Hand"]):
			hand_error = minf(hand_error, Clearance.point_triangle_distance(Driver.LADA_GRIPS[side], triangle[0], triangle[1], triangle[2]))
		var hand_skin := PackedVector3Array()
		for surface in seated_reader.surfaces:
			if not String(surface.material).contains("Warm_pale_skin"): continue
			for index: int in surface.referenced:
				if surface.names[index] == SIDES[side] + "Hand": hand_skin.append(points[surface.offset + index])
		var palm_error := Reader.bounds(hand_skin).get_center().distance_to(Driver.LADA_GRIPS[side]) if not hand_skin.is_empty() else INF
		var shoulder_bone: int = seated.skeleton.find_bone(SIDES[side] + "UpperArm")
		var shoulder: Vector3 = frame.to_local(seated_reader.final_skeleton_world * seated_reader.bone_global_pose(shoulder_bone).origin)
		var arm_length: float = seated.skeleton.get_bone_rest(seated.skeleton.find_bone(SIDES[side] + "LowerArm")).origin.length() + seated.skeleton.get_bone_rest(bone).origin.length()
		hand_diagnostics.append({"side": SIDES[side], "shoulder": _v(shoulder), "wrist": _v(wrist), "palm_centre": _v(Reader.bounds(hand_skin).get_center()), "target_grip": _v(Driver.LADA_GRIPS[side]), "shoulder_to_grip_m": shoulder.distance_to(Driver.LADA_GRIPS[side]), "upper_plus_lower_arm_length_m": arm_length})
		palm_centre_errors.append(palm_error)
		visible_hand_errors.append(hand_error)
		# The contract concerns the visible palm, not a new rig's wrist origin.
		check(palm_error <= 0.04 and hand_error <= 0.04, "actual imported visible palm retains 4cm steering grip bound: " + SIDES[side])
	report.metrics["cabin"] = {"bounds": str(Reader.bounds(seated_reader.referenced(points))), "skin_vertex_and_indexed_centroid_samples": unique.size(), "door_violations": doors,
		"firewall_violations": firewall, "firewall_witness": firewall_witness, "seat_core_penetration_m": seat_depth, "seat_support_gap_m": support_gap,
		"deepest_body_point": _v(deepest_seat_point), "deepest_body_source": body_source, "nearest_seat_triangle": str(deepest_seat_triangle),
		"head_wheel_centreline_distance_m": wheel_distance, "head_triangles": head_triangles.size(), "wrist_grip_error_m_diagnostic": grip_errors, "visible_hand_grip_error_m": visible_hand_errors, "palm_centre_grip_error_m": palm_centre_errors, "hands": hand_diagnostics}
	print("IMPORTED_HERO_CABIN ", JSON.stringify(report.metrics["cabin"]))

func _skin_source_at(probe: RefCounted, points: PackedVector3Array, point: Vector3) -> Dictionary:
	for centroid in [false, true]:
		for surface in probe.surfaces:
			var candidates: Array = []
			if centroid:
				var indices: PackedInt32Array = surface.indices
				for offset in range(0, indices.size() - 2, 3):
					var found := (points[surface.offset + indices[offset]] + points[surface.offset + indices[offset + 1]] + points[surface.offset + indices[offset + 2]]) / 3.0
					if found.distance_to(point) <= 0.000001: candidates.append([indices[offset], indices[offset + 1], indices[offset + 2]])
			else:
				for vertex: int in surface.referenced:
					if points[surface.offset + vertex].distance_to(point) <= 0.000001: candidates.append([vertex])
			if candidates.is_empty(): continue
			var result := {"kind": "triangle_centroid" if centroid else "vertex", "material": surface.material, "surface": surface.surface, "vertices": []}
			for vertex: int in candidates[0]:
				var weights := {}
				for influence in int(surface.influences):
					var slot: int = vertex * int(surface.influences) + influence
					if surface.weights[slot] > 0.0: weights[String(probe.skeleton.get_bone_name(probe.bind_bones[surface.bones[slot]]))] = surface.weights[slot]
				result.vertices.append({"index": vertex, "bind": _v(surface.raw[vertex]), "posed": _v(points[surface.offset + vertex]), "bone_weights": weights})
			return result
	return {}

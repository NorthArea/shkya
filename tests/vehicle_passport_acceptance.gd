extends SceneTree
## Independent CPU geometry acceptance. Expected values transcribed from source drawings/tables,
## never loaded from production Dimensions.SPECS. This accepts dimensions, not cabin fit or appearance.
const LV = preload("res://game/vehicles/lada_visual.gd")
const NIVA = preload("res://game/vehicles/niva_visual.gd")
const SAMARA = preload("res://game/vehicles/samara_visual.gd")
const GAZ = preload("res://game/vehicles/gaz3110_visual.gd")
const VAN = preload("res://game/vehicles/gazelle_visual.gd")
const VM = preload("res://game/vehicles/vehicle_mesh.gd")
const DAMAGE = preload("res://game/vehicles/vehicle_damage.gd")
const SKY = preload("res://game/world/skyline.gd")
const OUT := "res://builds/checks/CHARACTER-07/passport/acceptance.json"
# Eight mm allows rounded mesh detail over integer-mm drawings, not percent-scale errors.
# Axles are explicit centres; one mm is floating-point/detail allowance, not shape tolerance.
const DETAIL := 0.008
const AXLE_EPS := 0.001
const CASES := {
	"vaz2106": {"size": Vector3(1.611, 1.440, 4.166), "wb": 2.424, "tracks": [1.365, 1.321], "radius": 0.2971, "front": -1.433,
		"tier": "primary_avtoexport_manual_scan", "url": "https://djvu.online/file/RNBpBfUZ8o1QH", "page": "fig2, p9", "snapshot": "vaz2106_fig2.webp",
		"convention": "Unladen roof; diagram static tyre276mm; mesh nominal165/80R13 radius297.1mm is a separate unladen approximation."},
	"niva2121": {"size": Vector3(1.680, 1.640, 3.740), "wb": 2.200, "tracks": [1.430, 1.400], "radius": 0.3432, "front": -1.165,
		"tier": "primary_manual_reprint", "url": "https://www.landy.ee/niva/manuals/workshop_manual/1600om.PDF", "page": "p27-28 fig2", "snapshot": "niva_p28.png",
		"convention": "Diagram static tyre322mm; mesh nominal175/80R16 radius343.2mm is separate; roof height does not establish floor/headroom."},
	"samara2109": {"size": Vector3(1.650, 1.402, 4.006), "wb": 2.460, "tracks": [1.400, 1.370], "radius": 0.2876, "front": -1.218,
		"tier": "secondary_technical_manual_scan", "url": "https://djvu.online/file/AGlqwHZRmyMC7", "page": "Third Rome1999 p8 fig2", "snapshot": "samara_fig1.webp",
		"convention": "Five-door long-wing2109; table static tyre260mm; mesh nominal175/70R13 separate. OEM original unavailable."},
	"gaz3110": {"size": Vector3(1.800, 1.455, 4.880), "wb": 2.800, "tracks": [1.500, 1.444], "radius": 0.31725,
		"tier": "primary_oem_manual_scan", "url": "https://djvu.online/file/dTwhY2A0FYnuU", "page": "GAZ3110-3902008RE1998 p187/189", "snapshot": "gaz3110_p187.webp",
		"convention": "Unladen height, first of3110/3102 paired table values; nominal195/65R15. No confirmed individual overhangs."},
	"gaz2705": {"size": Vector3(2.075, 2.285, 5.500), "wb": 2.900, "tracks": [1.700, 1.560], "radius": 0.34195,
		"tier": "secondary_repair_manual_transcription", "url": "https://sinref.ru/avtomobili/0000_YY1_15_4600_raznie_2_sin_2026-06/400_06_GAZ_2705_1995_gazel/003.htm", "page": "technical table", "snapshot": "",
		"convention": "Cargo, rear track between twin-pair centres, nominal185/75R16C; height load/mirror convention and OEM original unconfirmed."},
	"gaz32213": {"size": Vector3(2.075, 2.255, 5.500), "wb": 2.900, "tracks": [1.700, 1.560], "radius": 0.34195,
		"tier": "secondary_repair_manual_transcription", "url": "https://sinref.ru/avtomobili/0000_YY1_15_4600_raznie_2_sin_2026-06/400_06_GAZ_2705_1995_gazel/003.htm", "page": "bus columns", "snapshot": "",
		"convention": "Passenger height2255 differs from cargo2285. Rear twin-pair centres. OEM original and load/mirror convention unconfirmed."},
	"ziu9": {"size": Vector3(2.500, 2.984, 11.888), "wb": 6.025, "tracks": [2.006, 1.710], "radius": 0.527, "front": -3.595,
		"tier": "secondary_period_technical_manual_scan", "url": "https://djvu.online/file/G1Xtg92LGghnn", "page": "Transport1977 fig1 p6, static radius p8", "snapshot": "ziu682b_fig1.webp",
		"convention": "682B round lamps. Roof2984; overall3347 with LOWERED poles, active poles excluded. Static tyre527+-5mm. Front axle derived from2282+67 buffer dimension; rear track twin-pair centres. OEM original unavailable."},
}
var checks := 0
var failures: Array[String] = []
var report := {"cases": {}, "instances": {}, "source_sha256": {}, "input_sha256": {}}
var frozen := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ", message)

func near(a: float, b: float, epsilon := DETAIL) -> bool:
	return absf(a - b) <= epsilon

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var lo := points[0]
	var hi := lo
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)

func points(node: MeshInstance3D, visual: Node3D, selection := "all") -> PackedVector3Array:
	var result := PackedVector3Array()
	if node == null or node.mesh == null:
		return result
	var xf := visual.global_transform.affine_inverse() * node.global_transform
	for index in node.mesh.get_surface_count():
		var material: Material = node.mesh.surface_get_material(index)
		# Actual material assignments, not metadata labels, determine shell/bumper membership.
		var paint: bool = material is ShaderMaterial and material.shader.resource_path.ends_with("lada_paint.gdshader")
		if selection == "paint" and not paint:
			continue
		if selection == "bumper" and material != VM.mat("bumper_dark"):
			continue
		if selection == "equipment" and material != VM.mat("grey_roof"):
			continue
		var arrays: Array = node.mesh.surface_get_arrays(index)
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			result.append(xf * vertex)
	return result

func wheels(visual: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		# Direct wheel children may be auto-renamed @MeshInstance3D by Godot.
		if mi.get_parent() != visual and not str(mi.get_parent().name).begins_with("WheelPivot"):
			continue
		var xf := visual.global_transform.affine_inverse() * mi.global_transform
		var radius := 0.0
		for surface in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(surface)
			for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var q := xf.basis * p
				radius = maxf(radius, Vector2(q.y, q.z).length())
		result.append({"center": xf.origin, "radius": radius, "mesh": mi.mesh})
	return result

func measure(visual: Node3D, model: String, label: String, open_door := false) -> void:
	var spec: Dictionary = CASES[model]
	var expected: Vector3 = spec.size
	var body := visual.get_node_or_null("Body/BodyMesh") as MeshInstance3D
	if body == null:
		check(false, label + ": real Body/BodyMesh exists")
		return
	check(visual.global_basis.get_scale().is_equal_approx(Vector3.ONE), label + ": actual world scale1, no instance shrink")
	var shell_points := points(body, visual, "paint")
	var span_points := points(body, visual, "bumper" if model == "ziu9" else "all")
	check(not shell_points.is_empty() and not span_points.is_empty(), label + ": assigned paint/bumper surfaces contain real vertices")
	var shell := bounds(shell_points)
	var span := bounds(span_points)
	if not open_door:
		check(near(shell.size.x, expected.x), label + ": shell width %.6f expected %.6f excludes mirrors" % [shell.size.x, expected.x])
	check(near(shell.end.y, expected.y), label + ": roof %.6f expected %.6f excludes snow/aerial/poles" % [shell.end.y, expected.y])
	check(near(span.size.z, expected.z), label + ": full bumper length %.6f expected %.6f" % [span.size.z, expected.z])
	var tyres := wheels(visual)
	check(tyres.size() == (6 if model in ["gaz2705", "gaz32213", "ziu9"] else 4), label + ": actual single-front/dual-rear wheel count")
	var front: Array[Vector3] = []
	var rear: Array[Vector3] = []
	for tyre in tyres:
		var centre: Vector3 = tyre.center
		var radius: float = tyre.radius
		check(near(radius, spec.radius, 0.005 if model == "ziu9" else 0.001), label + ": actual tyre radius matches stated nominal/static convention")
		check(near(centre.y, radius, 0.001), label + ": tyre bottom rests on ground")
		if centre.z < 0.0:
			front.append(centre)
		else:
			rear.append(centre)
	if front.size() == 2 and rear.size() in [2, 4]:
		var fz := front[0].z
		var rz := rear[0].z
		check(near(rz - fz, spec.wb, AXLE_EPS), label + ": measured wheelbase")
		for axle in [front, rear]:
			var ax := 0.0
			for centre in axle:
				ax += absf(centre.x)
			ax = 2.0 * ax / axle.size()
			check(near(ax, spec.tracks[0 if axle == front else 1], AXLE_EPS), label + ": track between single/twin-pair centres")
		if spec.has("front"):
			check(near(fz, spec.front, AXLE_EPS), label + ": asymmetric front overhang establishes axle position")
		for centre in front:
			check(near(centre.z, fz, AXLE_EPS), label + ": front wheels on one axle")
		for centre in rear:
			check(near(centre.z, rz, AXLE_EPS), label + ": rear wheels on one axle")
	if model == "ziu9":
		var equipment := bounds(points(body, visual, "equipment"))
		check(equipment.size.y > 0.0 and equipment.end.y <= 3.347 + DETAIL, label + ": fixed roof hardware within folded-pole transport height")
		trolley_interior_case(visual, label)
	report.instances[label] = {"model": model, "shell_size": vec(shell.size), "roof": shell.end.y, "bumper_length": span.size.z, "wheel_centres": tyres.map(func(t: Dictionary) -> Array: return vec(t.center))}

func trolley_interior_case(visual: Node3D, label: String) -> void:
	var cabin: MeshInstance3D = visual.get_node("Body/Interior")
	var xf := visual.global_transform.affine_inverse() * cabin.global_transform
	var floor_y := INF
	var ceiling_y := INF
	for surface in cabin.mesh.get_surface_count():
		var material: Material = cabin.mesh.surface_get_material(surface)
		if material != VM.mat("dark") and material != VM.mat("ceiling"):
			continue
		var arrays: Array = cabin.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		for i in range(0, indices.size() - 2, 3):
			var a := xf * vertices[indices[i]]
			var b := xf * vertices[indices[i + 1]]
			var c := xf * vertices[indices[i + 2]]
			# Godot front faces use clockwise winding, the opposite of the RH cross product.
			var normal := (c - a).cross(b - a).normalized()
			var lo := a.min(b).min(c)
			var hi := a.max(b).max(c)
			# Large actual horizontal triangles distinguish the floor/ceiling from seats,
			# steps and poles without assuming their expected height in the selector.
			if hi.x - lo.x < 1.2 or hi.z - lo.z < 5.0 or hi.y - lo.y > 0.001:
				continue
			if material == VM.mat("dark") and normal.y > 0.99:
				floor_y = minf(floor_y, a.y)
			if material == VM.mat("ceiling"):
				ceiling_y = minf(ceiling_y, a.y)
	check(near(floor_y, 0.720, 0.002), label + ": source floor720mm measured from actual large upward cabin triangles")
	check(near(ceiling_y - floor_y, 2.008, 0.002), label + ": source clear interior2008mm measured independently of external roof")

func collider_case(owner: Node3D, visual: Node3D, model: String, label: String) -> void:
	var collider: CollisionShape3D
	for child in owner.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			collider = child
			break
	if collider == null:
		check(false, label + ": active box collider exists")
		return
	var xf := visual.global_transform.affine_inverse() * collider.global_transform
	var corners := PackedVector3Array()
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				corners.append(xf * (collider.shape.size * Vector3(x, y, z)))
	var box := bounds(corners)
	var expected: Vector3 = CASES[model].size
	check(box.size.distance_to(expected) <= 0.002, label + ": collider follows real full dimensions in visual coordinates")
	check(absf(box.position.y) < 0.002, label + ": physics box begins at ground")

func path_pose_case(vehicle: Node3D, model: String) -> void:
	var actual_wheels := wheels(vehicle.visual)
	var front_z := INF
	var rear_z := -INF
	for tyre in actual_wheels:
		front_z = minf(front_z, tyre.center.z)
		rear_z = maxf(rear_z, tyre.center.z)
	var original: Transform3D = vehicle.global_transform
	var lane: RefCounted = vehicle.path
	var arc: Vector2 = lane.arcs[0]
	for sample in [["straight", arc.x * 0.5], ["curve", (arc.x + arc.y) * 0.5]]:
		var label: String = "path/" + model + "/" + sample[0]
		var at: float = sample[1]
		var front_target: Vector3 = lane.position_at(at - front_z)
		var rear_target: Vector3 = lane.position_at(at - rear_z)
		var chord := front_target - rear_target
		var pose: Transform3D = vehicle._transform_at(at, 0.0)
		check(pose.basis.get_scale().is_equal_approx(Vector3.ONE) and absf(pose.origin.y) < AXLE_EPS, label + ": rigid body pose keeps unit scale and ground zero")
		check((-pose.basis.z).dot(chord.normalized()) > 0.999999, label + ": real axle targets determine heading")
		# The vehicle origin divides the chord in the physical axle-arm ratio. Testing
		# distances/collinearity avoids copying production's weighted-vector expression.
		check((pose.origin - rear_target).cross(chord.normalized()).length() < AXLE_EPS, label + ": body centre lies on axle-target chord")
		var fraction := (pose.origin - rear_target).dot(chord) / chord.length_squared()
		check(near(fraction, rear_z / (rear_z - front_z), 0.0001), label + ": asymmetric overhangs preserve correct body-origin ratio")
		if sample[0] == "straight":
			check(pose.origin.distance_to(lane.position_at(at)) < AXLE_EPS, label + ": no longitudinal body-centre drift on straight")
		var shifted: Transform3D = vehicle._transform_at(at, 1.0)
		var lateral := shifted.origin - pose.origin
		check(near(lateral.length(), 1.0, AXLE_EPS) and absf(lateral.dot(chord.normalized())) < AXLE_EPS, label + ": yielding offset remains exactly lateral")
		var old_s: float = vehicle.s
		var old_side: float = vehicle.side
		vehicle.s = at
		vehicle.side = 0.0
		vehicle._apply_transform()
		check(vehicle.global_transform.is_equal_approx(pose), label + ": actual production consumer applies predicted full pose")
		vehicle.s = old_s
		vehicle.side = old_side
	vehicle.global_transform = original

func snow_slope_case(car: Lada) -> void:
	# A known plane supplies the support samples, rather than deriving an expectation
	# from the production interpolation helper. After the real visual pose, all four
	# contact points must still lie on that plane; the origin height is its intercept.
	var old_transform := car.global_transform
	var old_visual := car.visual.transform
	var old_heights: Array[float] = car.wheel_heights()
	var old_center: float = car.get("_center_h")
	var fields := ["snow_lift", "snow_pitch", "snow_roll", "susp_pitch", "susp_roll", "heave"]
	var saved := {}
	for field in fields:
		saved[field] = car.get(field)
	car.global_transform = Transform3D.IDENTITY
	var legacy_mode := "--legacy-mean-slope" in OS.get_cmdline_user_args()
	var samples_report := []
	for slope in [-0.15, -0.08, 0.08, 0.15]:
		var intercept := 0.8
		var samples: Array[float] = []
		# Independent passport axle stations, not Lada.WHEELS or the interpolation code.
		for z in [-1.433, -1.433, 0.991, 0.991]:
			samples.append(intercept + slope * z)
		car.set("_wheel_h", samples)
		car.set("_center_h", intercept)
		var target := car.snow_ride_target()
		var legacy_mean := (samples[0] + samples[1] + samples[2] + samples[3]) * 0.25
		if legacy_mode:
			target = legacy_mean # deliberate original algorithm mutation, no production edits
		check(near(target, intercept, 0.0001), "snow plane %.2f: body-origin lift equals known plane intercept" % slope)
		car.snow_lift = target
		car.snow_pitch = -atan(slope)
		car.snow_roll = 0.0
		car.susp_pitch = 0.0
		car.susp_roll = 0.0
		car.heave = 0.0
		car._apply_visual()
		var worst := 0.0
		for i in 4:
			var contact := car.wheel_contact(i)
			worst = maxf(worst, absf(contact.y - (intercept + slope * contact.z)))
		check(worst <= 0.001, "snow plane %.2f: real posed support points lie on the known plane (%.6fm)" % [slope, worst])
		# The old mean locates the origin at the axle midpoint z=-.221; it must be
		# rejected at the same geometric boundary, not merely differ from a new helper.
		car.snow_lift = legacy_mean
		car._apply_visual()
		var legacy_error := 0.0
		for i in 4:
			var contact := car.wheel_contact(i)
			legacy_error = maxf(legacy_error, absf(contact.y - (intercept + slope * contact.z)))
		check(legacy_error > 0.01, "snow negative %.2f: original mean4 violates actual plane contact by over10mm" % slope)
		samples_report.append({"slope": slope, "intercept": intercept, "target": target, "contact_error_m": worst, "old_mean_contact_error_m": legacy_error})
	report["snow_slope_oracle"] = {"legacy_mutation": legacy_mode, "planes": samples_report, "scope": "real Lada target and visual contact consumer; controlled affine support samples; snow dynamics covered separately by DRIVE02"}
	car.global_transform = old_transform
	car.set("_wheel_h", old_heights)
	car.set("_center_h", old_center)
	for field in fields:
		car.set(field, saved[field])
	car.visual.transform = old_visual

func factory(model: String) -> Node3D:
	match model:
		"vaz2106": return LV.build(Color.WHITE, "", false, 0.0, 0.0)
		"niva2121": return NIVA.build(Color.WHITE, "", 0.0)
		"samara2109": return SAMARA.build(Color.WHITE, "", 0.0)
		"gaz3110": return GAZ.build(Color.WHITE, "", 0.0)
		_: return VAN.build(Color.WHITE, "", 0.0, VAN.CARGO if model == "gaz2705" else VAN.PASSENGER)

func negative_controls(visual: Node3D) -> void:
	# Alter only this instance's real mesh transform; shared meshes/other guards remain valid.
	# These controls establish that each geometric selector reaches its intended dimension.
	var body: MeshInstance3D = visual.get_node("Body/BodyMesh")
	var original := body.transform
	body.scale.z = 1.02
	check(not near(bounds(points(body, visual)).size.z, 4.166), "oracle negative: rejects2percent bumper-length distortion")
	body.transform = original
	body.scale.y = 0.98
	check(not near(bounds(points(body, visual, "paint")).end.y, 1.440), "oracle negative: rejects2percent roof shrink")
	body.transform = original
	body.scale.x = 1.02
	check(not near(bounds(points(body, visual, "paint")).size.x, 1.611), "oracle negative: rejects2percent shell-width distortion")
	body.transform = original
	var front: Node3D = visual.get_node("WheelPivot0")
	var axle_original := front.position
	front.position.z += 0.010
	check(not near(wheels(visual)[0].center.z, -1.433, AXLE_EPS), "oracle negative: rejects10mm asymmetric axle displacement")
	front.position = axle_original

func stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.stop()
	for child in node.get_children():
		stop(child)

func skyline_case() -> void:
	var sky := SKY.new()
	root.add_child(sky)
	var color := Color(0.62, 0.12, 0.08)
	sky._car(Vector3.ZERO, 0.0, color)
	# Dummy RenderingServer cannot read back MultiMesh transforms/colors. Retain the actual
	# CPU payload supplied by the production emitter, and inspect its real BoxMesh vertices.
	var payload: Array = sky._lit.duplicate(true)
	sky.finish()
	var decor: MultiMeshInstance3D = sky.get_node("NearDecor")
	var mm := decor.multimesh
	var shell := PackedVector3Array()
	var roof := PackedVector3Array()
	check(mm.instance_count == payload.size(), "skyline: production emitter uploads every CPU car part")
	for i in payload.size():
		var c: Color = payload[i][1]
		if c.r > 0.8 and c.g > 0.8 and c.b > 0.8:
			continue # actual white snow instances; snow height is not the underlying car roof
		var xf: Transform3D = payload[i][0]
		for surface in mm.mesh.get_surface_count():
			var arrays: Array = mm.mesh.surface_get_arrays(surface)
			for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				roof.append(xf * p)
				if c.is_equal_approx(color):
					shell.append(xf * p)
	var body := bounds(shell)
	var all_unsnowed := bounds(roof)
	check(near(body.size.x, 4.166) and near(body.size.z, 1.611), "skyline: emitted actual box vertices use2106 length/width")
	check(near(all_unsnowed.end.y, 1.440), "skyline: actual unsnowed roof uses2106 height")
	report.instances["skyline"] = {"shell_size": vec(body.size), "roof": all_unsnowed.end.y, "scope": "production CPU instance payload and emitted BoxMesh vertices; Dummy has no GPU transform readback; distant silhouette has no wheels/collision"}
	sky.free()

func _run() -> void:
	for path in ["vehicle_dimensions", "lada_visual", "niva_visual", "samara_visual", "gaz3110_visual", "gazelle_visual", "trolleybus", "path_vehicle", "city_van", "traffic_car", "vehicle_mesh", "vehicle_damage", "lada"]:
		var full: String = "res://game/vehicles/" + path + ".gd"
		frozen[full] = FileAccess.get_sha256(full)
	for path in ["layout", "level_geometry", "breakables", "perimeter", "skyline", "wind_bags"]:
		var full: String = "res://game/world/" + path + ".gd"
		frozen[full] = FileAccess.get_sha256(full)
	for full in ["res://game/vehicles/lada_driver.gd", "res://game/vehicles/trolley_cabin.gd", "res://game/characters/uniform_visual.gd", "res://game/characters/character_catalog.gd", "res://game/characters/models/civilian_model.gd", "res://game/characters/models/selected_ilyusha_model.gd"]:
		frozen[full] = FileAccess.get_sha256(full)
	frozen["res://tests/vehicle_passport_acceptance.gd"] = FileAccess.get_sha256("res://tests/vehicle_passport_acceptance.gd")
	for model in CASES:
		var spec: Dictionary = CASES[model]
		report.cases[model] = {"size": vec(spec.size), "tier": spec.tier, "url": spec.url, "page": spec.page, "convention": spec.convention}
		if not spec.snapshot.is_empty():
			var path: String = "res://builds/checks/CHARACTER-07/passport/" + spec.snapshot
			report.source_sha256[path] = FileAccess.get_sha256(path)
		if model == "ziu9":
			continue
		var a := factory(model)
		var b := factory(model)
		root.add_child(a)
		root.add_child(b)
		stop(a)
		stop(b)
		measure(a, model, "factory/" + model)
		if model == "vaz2106":
			negative_controls(a)
		var mesh_a: MeshInstance3D = a.get_node("Body/BodyMesh")
		var mesh_b: MeshInstance3D = b.get_node("Body/BodyMesh")
		var shared := mesh_b.mesh
		check(mesh_a.mesh == shared, model + ": production factory keeps shared immutable geometry")
		check(DAMAGE.dent(a, a.to_global(Vector3(CASES[model].size.x * 0.5, 0.8, 0)), -a.global_basis.x, 8.0), model + ": real dent changes body geometry")
		check(mesh_a.mesh != shared and mesh_b.mesh == shared, model + ": dent isolates instance from shared cache")
		DAMAGE.reset(a)
		check(mesh_a.mesh == shared, model + ": damage reset restores shared original")
		a.free()
		b.free()
	skyline_case()
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	main.start_game()
	await process_frame
	stop(main)
	var world: Node = main.world
	measure(world.car.visual, "vaz2106", "player")
	collider_case(world.car, world.car.visual, "vaz2106", "player")
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	for vehicle in traffic.vehicles:
		var model: String = "ziu9" if vehicle is Trolleybus else {&"zhiguli": "vaz2106", &"volga": "gaz3110", &"gazelle": "gaz2705"}[vehicle.kind]
		measure(vehicle.visual, model, "traffic/" + model)
		collider_case(vehicle, vehicle.visual, model, "traffic/" + model)
		path_pose_case(vehicle, model)
	var breaks: Node = world.get_node("LevelGeometry/Breakables")
	var parking_count := 0
	for parked in breaks.env_objects:
		if parked.kind != &"parked":
			continue
		var model := "niva2121" if parked.id == &"Zhiguli_A" else ("samara2109" if parked.id == &"Zhiguli_B" else "vaz2106")
		var label := "parking/%s/%d" % [parked.id, parking_count]
		measure(parked.parked_visual, model, label)
		collider_case(parked.body, parked.parked_visual, model, label)
		parking_count += 1
	check(parking_count >= 3, "actual world contains varied parking fleet")
	var vans := world.find_children("*", "CityVan", true, false)
	check(vans.size() == 2, "both mission/closure passenger consumers exist")
	for van in vans:
		measure(van.visual, "gaz32213", "passenger/" + str(van.name), true)
		collider_case(van, van.visual, "gaz32213", "passenger/" + str(van.name))
	var police_count := 0
	for mi: MeshInstance3D in world.find_children("BodyMesh", "MeshInstance3D", true, false):
		if not "PermanentStreetClosures" in str(mi.get_path()) or mi.mesh != LV.sedan_meshes(&"vaz2106").body:
			continue
		var visual := mi.get_parent().get_parent() as Node3D
		measure(visual, "vaz2106", "police")
		police_count += 1
	check(police_count == 1, "actual police post consumes passport-scaled common2106")
	snow_slope_case(world.car)
	main.free()
	for path in frozen:
		check(frozen[path] == FileAccess.get_sha256(path), "frozen acceptance input unchanged: " + path)
	report.input_sha256 = frozen
	report.checks = checks
	report.failures = failures
	report.scope = "Real CPU vertices/transforms, live consumers/colliders, wheels/twins, immutable cache/damage. Three primary/reprinted sources; four secondary sources remain unqualified as OEM passports. No cabin ergonomic, GPU appearance, sound, FPS or route acceptance."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("VEHICLE_PASSPORT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## APARTMENT-01: native, unmodified city apartments; room predictions plus actual pixel illumination.
## tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/apartment01.gd
const Layout = preload("res://game/world/layout.gd")
const OUT := "res://builds/screenshots/APARTMENT-01"
const ROOM_NAMES := ["kitchen", "living", "bedroom"]
var world: DemoWorld
var camera: Camera3D
var output := OUT
var saved := 0
var failed := 0
var manifest := {"selection": "float32 room prediction; illumination confirmed from native pixels, no sin-hash prediction", "probes": [], "captures": []}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 12: await physics_frame
	world = main.world
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = world.camera_rig.camera.fov
	root.add_child(camera)
	# These short ends have no external loggias covering their apartment panes.
	var candidates: Array[Dictionary] = []
	for spec in [["H1_South", "panel", Vector3.RIGHT], ["H3_North", "stucco", Vector3.RIGHT], ["H11_West", "brick", Vector3.FORWARD]]:
		candidates.append_array(_candidates(spec[0], spec[1], spec[2]))
	var used_houses: Array[String] = []
	for kind in 3:
		var options: Array[Dictionary] = []
		for candidate in candidates:
			if candidate.kind == kind: options.append(candidate)
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var sa: float = a.open_fraction - (0.5 if a.house in used_houses else 0.0) - a.storey * 0.025
			var sb: float = b.open_fraction - (0.5 if b.house in used_houses else 0.0) - b.storey * 0.025
			return sa > sb)
		var selected: Dictionary = {}
		for candidate in options:
			if await _illuminated(candidate):
				selected = candidate
				break
		if selected.is_empty():
			failed += 1
			push_error("APARTMENT01: NOT RUN: no pixel-confirmed open " + ROOM_NAMES[kind])
			continue
		used_houses.append(selected.house)
		var stem := "%d_%s_%s" % [kind, ROOM_NAMES[kind], selected.facade]
		await _apartment(stem, selected)
		var neighbours: Array[Dictionary] = []
		for candidate in candidates:
			if candidate.house == selected.house and candidate.cell != selected.cell: neighbours.append(candidate)
		neighbours.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a.target as Vector3).distance_squared_to(selected.target) < (b.target as Vector3).distance_squared_to(selected.target))
		var found_neighbour := false
		for neighbour in neighbours:
			if await _illuminated(neighbour):
				await _close(stem + "_neighbour_" + ROOM_NAMES[neighbour.kind], neighbour, 0.0)
				found_neighbour = true
				break
		if not found_neighbour:
			failed += 1
			push_error("APARTMENT01: NOT RUN: no pixel-confirmed open neighbour for " + stem)
	var h1 := _house("H1_South")
	var center: Vector2 = h1[2]
	var size: Vector3 = h1[3]
	var front := Vector3(center.x, 4.0, center.y - size.z * 0.5)
	await _position_camera(front + Vector3(8.0, -2.25, -14.0), front, 12)
	await _save("loggias_street", {})
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		failed += 1
		push_error("Cannot save apartment capture manifest")
	else:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
	print("APARTMENT01_CAPTURE: %d frames, %d failures; predicted room types require manual furniture confirmation" % [saved, failed])
	main.queue_free()
	await process_frame
	quit(0 if failed == 0 and saved == 13 else 1)

func _house(id: String) -> Array:
	for solid in Layout.SOLIDS:
		if solid[0] == id: return solid
	return []

func _candidates(id: String, facade: String, outward: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var house := _house(id)
	assert(not house.is_empty(), "Capture house missing from Layout")
	var body := world.get_node("LevelGeometry").find_child(id, true, false)
	assert(body != null, "Production house body missing")
	var material: ShaderMaterial
	for child in body.get_children():
		if child is MeshInstance3D and child.material_override is ShaderMaterial:
			material = child.material_override
			break
	assert(material != null, "Production facade material missing")
	# Read actual values including shader defaults; never override production materials.
	var seed := float(material.get_shader_parameter("seed"))
	var spacing := float(material.get_shader_parameter("window_spacing"))
	var floor_height := float(material.get_shader_parameter("floor_height"))
	var width := float(material.get_shader_parameter("window_width"))
	var height := float(material.get_shader_parameter("window_height"))
	var lit_ratio := float(material.get_shader_parameter("lit_ratio"))
	assert(spacing > 0.0 and floor_height > 0.0 and width > 0.0 and height > 0.0, "Facade uniform values unavailable")
	var center: Vector2 = house[2]
	var size: Vector3 = house[3]
	var along_z := absf(outward.x) > 0.5
	var tangent := Vector3.BACK if along_z else Vector3.RIGHT
	var along := center.y if along_z else center.x
	var length := size.z if along_z else size.x
	var wall := Vector3(center.x, 0.0, center.y) + outward * (size.x if along_z else size.z) * 0.5
	var face_offset := Vector2(outward.x * 13.0 + outward.z * 29.0, floorf(_f32(wall.dot(outward) * _f32(0.07))))
	for storey in range(0, mini(6, floori((size.y - 0.85 - height) / floor_height) + 1)):
		for column in range(floori((along - length * 0.5) / spacing), ceili((along + length * 0.5) / spacing)):
			var u := (float(column) + 0.5) * spacing
			if u - width * 0.5 < along - length * 0.5 + 0.15 or u + width * 0.5 > along + length * 0.5 - 0.15: continue
			var cell := Vector2(column, storey)
			var room_cell := cell + face_offset
			var kind_hash := _room_hash(room_cell + Vector2(13.1, 13.1), seed)
			var kind := floori(kind_hash * 3.0)
			# Avoid floating contraction boundaries when predicting room/curtain categories.
			if minf(kind_hash - float(kind) / 3.0, float(kind + 1) / 3.0 - kind_hash) < 0.035: continue
			var closed_hash := _room_hash(room_cell + Vector2(3.8, 3.8), seed)
			if closed_hash < 0.20: continue
			var left_width := 0.13 + 0.19 * _room_hash(room_cell + Vector2(6.9, 6.9), seed)
			var right_width := 0.13 + 0.19 * _room_hash(room_cell + Vector2(8.7, 8.7), seed)
			var open_fraction := 1.0 - left_width - right_width
			if open_fraction < 0.46: continue
			var target := wall + tangent * (u - along)
			target.y = float(storey) * floor_height + 0.85 + height * 0.5
			result.append({"house": id, "facade": facade, "seed": seed, "cell": cell, "room_cell": room_cell, "kind": kind, "kind_hash": kind_hash, "closed_hash": closed_hash, "open_fraction": open_fraction, "left_curtain_fraction": left_width, "right_curtain_fraction": right_width, "lit_ratio": lit_ratio, "storey": storey, "target": target, "outward": outward, "tangent": tangent, "width": width, "height": height})
	return result

# Scalar GDScript math is float64. Round intermediate hash operations to float32.
# Classification remains a prediction; lit state is measured from native pixels.
func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func _fraction(value: float) -> float:
	return value - floorf(value)

func _room_hash(cell: Vector2, seed: float) -> float:
	var x := _fraction(_f32(cell.x * _f32(0.1031)))
	var y := _fraction(_f32(cell.y * _f32(0.1030)))
	var z := _fraction(_f32(seed * _f32(0.0973)))
	var dot_xy := _f32(_f32(x * _f32(y + _f32(33.33))) + _f32(y * _f32(z + _f32(33.33))))
	var dot_xyz := _f32(dot_xy + _f32(z * _f32(x + _f32(33.33))))
	x = _f32(x + dot_xyz)
	y = _f32(y + dot_xyz)
	z = _f32(z + dot_xyz)
	return _fraction(_f32(_f32(x + y) * z))

func _illuminated(candidate: Dictionary) -> bool:
	if candidate.has("pixel_confirmed"): return candidate.pixel_confirmed
	var target: Vector3 = candidate.target
	await _position_camera(target + (candidate.outward as Vector3) * 3.5 + Vector3.UP * 0.35, target - Vector3.UP * 0.1, 3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var luminances: Array[float] = []
	# Sample pane interiors, away from the centre mullion and upper transom.
	for horizontal in [-0.32, -0.22, 0.22, 0.32]:
		for vertical in [-0.28, -0.12, 0.02, 0.12]:
			var sample: Vector3 = target + (candidate.tangent as Vector3) * horizontal * float(candidate.width) + Vector3.UP * vertical * float(candidate.height)
			var pixel := camera.unproject_position(sample)
			var color := image.get_pixel(clampi(roundi(pixel.x), 0, image.get_width() - 1), clampi(roundi(pixel.y), 0, image.get_height() - 1))
			luminances.append(color.get_luminance())
	luminances.sort()
	var median := (luminances[7] + luminances[8]) * 0.5
	candidate["pixel_median_luminance"] = median
	candidate["pixel_confirmed"] = median > 0.30
	manifest.probes.append(_record(candidate))
	print("APARTMENT01_PROBE: %s cell=%s kind~%d open~%.2f median=%.3f illuminated=%s" % [candidate.house, candidate.cell, candidate.kind, candidate.open_fraction, median, candidate.pixel_confirmed])
	return candidate.pixel_confirmed

func _apartment(stem: String, candidate: Dictionary) -> void:
	var target: Vector3 = candidate.target
	var outward: Vector3 = candidate.outward
	var stand := target + outward * 7.0
	stand.y = 0.0
	var look := -outward
	var yaw := atan2(-look.x, -look.z)
	world.player.place(stand, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.pitch = -0.10
	world.camera_rig.snap()
	world.camera_rig.camera.make_current()
	for i in 20: await physics_frame
	await _save(stem + "_game_camera", candidate)
	await _close(stem + "_window_left", candidate, -0.55)
	await _close(stem + "_window_right", candidate, 0.55)

func _close(label: String, candidate: Dictionary, side: float) -> void:
	var target: Vector3 = candidate.target
	await _position_camera(target + (candidate.outward as Vector3) * 3.5 + (candidate.tangent as Vector3) * side + Vector3.UP * 0.35, target - Vector3.UP * 0.1, 12)
	await _save(label, candidate)

func _position_camera(eye: Vector3, target: Vector3, frames: int) -> void:
	camera.position = eye
	camera.look_at(target)
	camera.make_current()
	for i in frames: await physics_frame

func _record(candidate: Dictionary) -> Dictionary:
	var record := candidate.duplicate()
	for key in record.keys():
		var value: Variant = record[key]
		if value is Vector2: record[key] = [value.x, value.y]
		elif value is Vector3: record[key] = [value.x, value.y, value.z]
	return record

func _save(label: String, candidate: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(output.path_join(label + ".png"))
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		failed += 1
		push_error("APARTMENT01 capture failed: " + path)
		return
	var record := _record(candidate)
	record["file"] = label + ".png"
	manifest.captures.append(record)
	saved += 1
	print("CAPTURE: " + path)

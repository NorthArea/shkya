extends SceneTree
## Existing runner path retained; the current oracle is the approved idle SVG.
## CPU-rasterized isolated artwork paths supply independent contour bounds.
## Inspect the author mesh; the runtime gait adapter has its own skeleton/skin.
## These coarse guards cannot establish 1:1 likeness or replace owner acceptance.

const Models = preload("res://game/characters/models/civilian_model.gd")
const SOURCE := "res://assets/art/characters/ilyusha_%s_idle.svg"
var checks := 0
var failures := 0
var groups: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("IP01_ILYUSHA_CONCEPT: " + message)

func _run() -> void:
	var reference := {
		"face": _svg_bounds("front", "M200,86"),
		"tuft": _svg_bounds("front", "M156.0,106"),
		"torso": _svg_bounds("front", "M95,300"),
		"trousers": _svg_bounds("front", "M106,436"),
		"boot": _svg_bounds("front", "M106,554.0"),
		"side_face": _svg_bounds("side", "M140,108"),
		"side_nose": _svg_bounds("side", "M264,200"),
	}
	if failures > 0:
		quit(1)
		return
	var model := Models.new().build_model("ilyusha")
	var skeleton := model.get_node("Skeleton3D") as Skeleton3D
	var instance := skeleton.get_node("UniformMesh") as MeshInstance3D
	var mesh := instance.mesh as ArrayMesh
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for index in vertices.size():
			var point := vertices[index]
			_add("all", point)
			var slot := index * 4
			for influence in range(1, 4):
				if weights[index * 4 + influence] > weights[slot]: slot = index * 4 + influence
			var bone_name := skeleton.get_bone_name(instance.skin.get_bind_bone(bones[slot]))
			var color := colors[index]
			if bone_name == "head":
				_add("head", point)
				if _pink(color): _add("pink_head", point)
				if _yellow(color): _add("tuft", point)
			if _lime(color):
				_add("coat", point)
				if bone_name in ["spine", "hips"]: _add("torso", point)
				if bone_name in ["upper_arm_l", "lower_arm_l"]: _add("sleeve_l", point)
				if bone_name in ["upper_arm_r", "lower_arm_r"]: _add("sleeve_r", point)
			if bone_name in ["leg_l", "leg_r", "foot_l", "foot_r"]:
				if _dark_green(color): _add("trousers", point)
				if _dark(color): _add("boots", point)
			if bone_name in ["hand_l", "hand_r"] and _pink(color): _add(bone_name, point)
			if bone_name in ["spine", "hips"] and _pale(color): _add("fur", point)
	for required in ["head", "pink_head", "tuft", "coat", "torso", "sleeve_l", "sleeve_r", "trousers", "boots", "hand_l", "hand_r", "fur"]:
		check(groups.has(required) and groups[required].size() >= 12, "approved SVG region exists: " + required)
	if failures == 0:
		_relations(reference)
	model.free()
	print("IP01_ILYUSHA_CONCEPT_NOT_RUN: contour XOR, facial expression, gait/seating, game lighting/GPU and owner likeness acceptance")
	print("IP01_ILYUSHA_CONCEPT: %d checks, %d failures; independent SVG-derived coarse geometry guards, never 1:1 acceptance" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _relations(reference: Dictionary) -> void:
	var all := _bounds("all")
	var head := _bounds("head")
	var pink := _bounds("pink_head")
	var tuft := _bounds("tuft")
	var torso := _bounds("torso")
	var trousers := _bounds("trousers")
	var boots := _bounds("boots")
	var face_source: Rect2 = reference.face
	var tuft_source: Rect2 = reference.tuft
	var torso_source: Rect2 = reference.torso
	var trouser_source: Rect2 = reference.trousers
	var boot_source: Rect2 = reference.boot
	var source_height := boot_source.end.y - tuft_source.position.y
	var height := all.size.y
	var head_source_height := face_source.end.y - tuft_source.position.y
	print("IP01_ILYUSHA_SVG_METRICS source_head/H=%.4f mesh_head/H=%.4f source_coat/head=%.4f mesh_coat/head=%.4f" % [head_source_height / source_height, head.size.y / height, torso_source.size.y / head_source_height, torso.size.y / head.size.y])
	# Fixed artwork-relative tolerances allow solid ears and collar overlap;
	# they are not inferred from the current generated model.
	_near(head.size.y / height, head_source_height / source_height, 0.045, "large head+tuft fraction from approved SVG")
	_near(pink.size.x / height, face_source.size.x / source_height, 0.045, "front pink head width including small solid ears")
	_near(tuft.size.y / height, tuft_source.size.y / source_height, 0.025, "short lumpy tuft height, not withdrawn tall cone")
	_near(tuft.size.x / height, tuft_source.size.x / source_height, 0.030, "yellow tuft width")
	_near(torso.size.y / head.size.y, torso_source.size.y / head_source_height, 0.11, "short puffer relative to the large SVG head")
	_near(torso.position.y / height, (boot_source.end.y - torso_source.end.y) / source_height, 0.035, "puffer hem leaves original long trouser section")
	_near(trousers.size.y / height, trouser_source.size.y / source_height, 0.045, "straight dark green trouser height")
	_near(boots.size.y / height, boot_source.size.y / source_height, 0.035, "low broad boots, not invented tall shafts")
	check(absf(all.position.y) <= height * 0.01, "soles remain at ground level")
	check(torso.size.z >= height * 0.15 and pink.size.z >= height * 0.20, "SVG reconstruction retains real body/head volumes")
	var fur := _bounds("fur")
	check(fur.size.x >= pink.size.x * 0.80 and fur.size.z >= height * 0.07, "pale scalloped collar wraps around upper torso")
	for side in ["l", "r"]:
		var sleeve := _bounds("sleeve_" + side)
		var hand := _bounds("hand_" + side)
		# Approved idle mittens occupy SVG y410..454, centered at about432.
		_near(hand.get_center().y / height, (boot_source.end.y - 432.0) / source_height, 0.040, "pink mitten location: " + side)
		check(hand.end.y < sleeve.end.y and sleeve.size.z > height * 0.05, "sleeve and mitten retain solid volume: " + side)
	var side_face: Rect2 = reference.side_face
	var side_nose: Rect2 = reference.side_nose
	var profile_source := side_face.merge(side_nose)
	_near(pink.size.z / height, profile_source.size.x / source_height, 0.085, "long trunk and head preserve approved side depth")
	var near_front: Array[Vector3] = []
	var extreme_front: Array[Vector3] = []
	for point: Vector3 in groups["pink_head"]:
		if point.z <= pink.position.z + pink.size.z * 0.25: near_front.append(point)
		if point.z <= pink.position.z + pink.size.z * 0.08: extreme_front.append(point)
	var front := _point_bounds(near_front)
	var tip := _point_bounds(extreme_front)
	check(tip.get_center().y > front.position.y + height * 0.015, "side trunk tip curls upward beyond lower bend")

func _svg_bounds(view: String, prefix: String) -> Rect2:
	var parser := XMLParser.new()
	var error := parser.open(SOURCE % view)
	check(error == OK, "approved " + view + " SVG is readable")
	if error != OK: return Rect2()
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT or parser.get_node_name() != "path": continue
		var path := parser.get_named_attribute_value_safe("d")
		var fill := parser.get_named_attribute_value_safe("fill")
		if not path.begins_with(prefix) or fill.is_empty() or fill == "none": continue
		var image := Image.new()
		error = image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="800" height="1200" viewBox="0 0 400 600"><path d="%s" fill="white"/></svg>' % path)
		check(error == OK, "isolated approved contour rasterizes: " + prefix)
		if error != OK: return Rect2()
		var used := image.get_used_rect()
		check(used.size.x > 0 and used.size.y > 0, "approved contour is nonempty: " + prefix)
		return Rect2(Vector2(used.position) / 2.0, Vector2(used.size) / 2.0)
	check(false, "approved contour not found: " + prefix)
	return Rect2()

func _near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance, "%s: actual %.4f, SVG %.4f, tolerance %.4f" % [message, actual, expected, tolerance])

# Palette classes come from tools/generate_characters.py / approved SVG fills.
func _in_palette(c: Color, palette: Array) -> bool:
	for value: String in palette:
		var expected := Color(value)
		if Vector3(c.r - expected.r, c.g - expected.g, c.b - expected.b).length() < 0.015: return true
	return false

func _lime(c: Color) -> bool:
	return _in_palette(c, ["a2f03a", "c8ff78", "7fcb22"])

func _pink(c: Color) -> bool:
	return _in_palette(c, ["f4b3cd", "fad3e3", "e296b6"])

func _yellow(c: Color) -> bool:
	return _in_palette(c, ["ebc458", "cfa43a"])

func _dark_green(c: Color) -> bool:
	return _in_palette(c, ["2f8a36", "226a29", "1b5521"])

func _dark(c: Color) -> bool:
	return _in_palette(c, ["3a3436", "1c1819"])

func _pale(c: Color) -> bool:
	return _in_palette(c, ["f6f3ea"])

func _add(group: String, point: Vector3) -> void:
	if not groups.has(group): groups[group] = []
	groups[group].append(point)

func _bounds(group: String) -> AABB:
	return _point_bounds(groups[group])

func _point_bounds(points: Array) -> AABB:
	var result := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points: result = result.expand(point)
	return result

func _slice_width(group: String, from_y: float, to_y: float) -> float:
	var low := INF
	var high := -INF
	for point: Vector3 in groups[group]:
		if point.y >= from_y and point.y <= to_y:
			low = minf(low, point.x)
			high = maxf(high, point.x)
	return high - low

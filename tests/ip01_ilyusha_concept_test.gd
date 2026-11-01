extends SceneTree
## MSG-0131 independent COARSE guards, not proof of a 1:1 likeness.
## Sources inspected directly: concepts/01,02,04,08 PNG; DECISIONS and CHARACTERS.
## Those perspective views show head+tuft about 1/4--1/3 of the figure and a
## comparable/larger long puffer. They do not define exact front/3D anatomy.
## Matching CPU view 02 and owner GPU inspection remain required.

const Models = preload("res://game/characters/models/civilian_model.gd")
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
		check(groups.has(required) and groups[required].size() >= 12, "concept region exists: " + required)
	if failures == 0:
		_relations()
	model.free()
	print("IP01_ILYUSHA_CONCEPT_NOT_RUN: exact likeness, scallop/face/hood/hand anatomy, matching CPU view 02, owner GPU review")
	print("IP01_ILYUSHA_CONCEPT: %d checks, %d failures; coarse PNG regression guards only, never 1:1 acceptance" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _relations() -> void:
	var all := _bounds("all")
	var head := _bounds("head")
	var pink := _bounds("pink_head")
	var tuft := _bounds("tuft")
	var coat := _bounds("torso")
	var trousers := _bounds("trousers")
	var boots := _bounds("boots")
	var fur := _bounds("fur")
	var height := all.size.y
	var head_fraction := head.size.y / height
	var coat_to_head := coat.size.y / head.size.y
	print("IP01_ILYUSHA_CONCEPT_METRICS head_fraction=%.4f coat/head=%.4f head/coat_width=%.4f trousers_green_height=%.4f" % [head_fraction, coat_to_head, pink.size.x / coat.size.x, trousers.size.y / height])
	# Broad bands account for perspective and the absent clean front view. The
	# old 47% SVG head + short jacket is deliberately outside both upper guards.
	check(head_fraction >= 0.22 and head_fraction <= 0.38, "head+tuft is roughly a quarter to a third, not the obsolete 47 percent head")
	check(coat_to_head >= 0.90, "long puffer torso is comparable to or taller than head+tuft")
	check(coat.size.y / height >= 0.27, "puffer occupies a substantial vertical part of the figure")
	check(pink.size.x / coat.size.x >= 0.35 and pink.size.x / coat.size.x <= 0.90, "compact pink head does not dominate the puffer width")
	check(coat.size.z >= pink.size.z * 0.45, "puffer is a volume around the torso")
	check(trousers.size.y / height >= 0.20 and trousers.end.y < coat.end.y, "dark green long trousers remain below the puffer")
	check(boots.position.y < trousers.position.y + height * 0.03 and boots.size.y / height >= 0.055, "dark winter boots reach the ground and have a visible shaft")
	check(fur.size.x >= pink.size.x * 0.80 and fur.size.z >= height * 0.07, "large pale hood/collar border wraps around the upper torso")
	for side in ["l", "r"]:
		var sleeve := _bounds("sleeve_" + side)
		var hand := _bounds("hand_" + side)
		check(sleeve.size.y >= head.size.y * 0.65 and sleeve.size.z >= height * 0.055, "padded lime sleeve retains length and volume: " + side)
		check(hand.size.y / height >= 0.025 and hand.size.y / height <= 0.13 and hand.end.y < sleeve.end.y, "pink hand remains a compact visible volume at its cuff: " + side)
	var lower_tuft := _slice_width("tuft", tuft.position.y, tuft.position.y + tuft.size.y * 0.35)
	var upper_tuft := _slice_width("tuft", tuft.position.y + tuft.size.y * 0.75, tuft.end.y)
	check(tuft.position.y > pink.get_center().y and upper_tuft < lower_tuft * 0.85, "yellow tuft sits atop the head and narrows toward its cone tip")
	# A coarse profile proxy for the visibly upturned projecting pink nose. This
	# cannot establish the exact S outline, facial expression or scallop drawing.
	var near_front: Array[Vector3] = []
	var extreme_front: Array[Vector3] = []
	for point: Vector3 in groups["pink_head"]:
		if point.z <= pink.position.z + pink.size.z * 0.25: near_front.append(point)
		if point.z <= pink.position.z + pink.size.z * 0.08: extreme_front.append(point)
	var front := _point_bounds(near_front)
	var tip := _point_bounds(extreme_front)
	check(front.size.y > height * 0.025 and tip.get_center().y > front.position.y + height * 0.01, "projecting pink nose has an upward profile beyond its lower bend")

# Independent source RGB samples from PNG 02 (unlit artwork, not author code):
# coat patch(530,550)-(615,595) median159/245/98; head(570,410)-(620,447)
# 231/158/189; tuft(580,364)-(610,385)239/192/64; trousers(560,742)-(610,777)
# 41/89/44; boots(610,860)-(640,875)41/33/38; fur233/221/214.
# These broad colour-family ranges allow artwork shading and sRGB variation;
# they deliberately do not reimpose obsolete exact SVG hex colours.
func _lime(c: Color) -> bool:
	return c.g > 0.65 and c.r > 0.35 and c.r < 0.85 and c.b < 0.55 and c.g > c.r + 0.12

func _pink(c: Color) -> bool:
	return c.r > 0.65 and c.g > 0.35 and c.g < 0.85 and c.b > 0.45 and c.r > c.g + 0.10 and c.b > c.g + 0.03

func _yellow(c: Color) -> bool:
	return c.r > 0.70 and c.g > 0.50 and c.b < 0.55 and c.r > c.b + 0.30

func _dark_green(c: Color) -> bool:
	return c.g > 0.15 and c.g < 0.47 and c.g > c.r + 0.10 and c.g > c.b + 0.10

func _dark(c: Color) -> bool:
	return maxf(c.r, maxf(c.g, c.b)) < 0.32

func _pale(c: Color) -> bool:
	return minf(c.r, minf(c.g, c.b)) > 0.70 and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < 0.20

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

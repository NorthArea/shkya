extends RefCounted
## Solid translations of the project's previous resident drawings, not new character designs.
## Source dimensions below are in the SVG's authored 400x600 canvas (soles at 590).
## Cross-sections have depth, closed backs and profiles; no image planes or face textures.
const Builder = preload("res://game/characters/models/uniform_mesh_builder.gd")
const IDS := ["babka", "man", "woman", "boy", "shuba", "beret", "violet", "ushanka", "ushanka_walk", "tourist", "kid", "kid2", "dog", "kolpak", "bow", "turban"]
var b: Builder
var d: Dictionary
var unit: float
var role: String
var head_rows: Array
var head_z: float

static func handles(drawing: String) -> bool:
	return drawing == "officer" or (drawing.begins_with("resident_") and drawing.trim_prefix("resident_") in IDS)

static func append_to(builder: Builder, drawing: String) -> void:
	assert(handles(drawing))
	var author = load("res://game/characters/models/legacy_resident_models.gd").new()
	author._author(builder, drawing)

func _author(builder: Builder, drawing: String) -> void:
	b = builder
	role = drawing.trim_prefix("resident_")
	d = _design(role)
	unit = 1.0 / (590.0 - float(d.top))
	head_rows = d.face
	head_z = float(d.get("head_z", -42.0))
	_bones()
	_body()
	_legs()
	_arms()
	_head()
	_hat()
	_skin_clothing()
	_details()

func _design(id: String) -> Dictionary:
	# Face rows: SVG y, half-width, profile depth. Coat rows have the same layout.
	var a := {"top": 124, "cloth": "5a4c43", "skin": "edc6a6", "hat_color": "4a6fae", "trim": "3e3530", "pants": "827769", "shoe": "6c6863", "hat": "kerchief", "old": true,
		"face": [[166, 24, 24], [185, 58, 43], [224, 72, 52], [260, 73, 50], [289, 61, 41], [310, 30, 21]],
		"body": [[558, 128, 65], [530, 130, 76], [430, 112, 76], [346, 99, 70], [305, 80, 55], [286, 38, 34]],
		"shoulder": 309, "arm_x": 79, "elbow_x": 103, "hand_x": 110, "hand_y": 446, "leg_x": 26, "leg_width": 19, "leg_top": 535, "nose": 12, "eye_y": 228, "eye_x": 21, "mouth_y": 280, "hat_bottom": 175, "hat_width": 84, "mouth": "frown"}
	match id:
		"man": a.merge({"top": 48, "old": false, "cloth": "2c2e34", "skin": "e7b699", "hat_color": "c65f30", "pants": "3b4457", "shoe": "1e1a1a", "hat": "knit", "hat_bottom": 138, "hat_width": 80,
			"face": [[117, 35, 32], [141, 66, 48], [180, 72, 54], [210, 61, 49], [231, 36, 29]], "body": [[488, 104, 72], [460, 123, 84], [392, 129, 91], [315, 119, 85], [261, 91, 64], [235, 46, 40]],
			"shoulder": 260, "arm_x": 89, "elbow_x": 128, "hand_x": 74, "hand_y": 444, "leg_x": 48, "leg_width": 32, "leg_top": 478, "eye_y": 164, "eye_x": 22, "mouth_y": 218, "nose": 20}, true)
		"woman": a.merge({"top": 76, "cloth": "4e4954", "skin": "f2d4bf", "trim": "a0968a", "hat_color": "4e4954", "pants": "353139", "shoe": "2a2323", "hat": "hood", "hat_bottom": 182, "hat_width": 96,
			"face": [[124, 28, 24], [150, 59, 43], [196, 65, 49], [232, 57, 44], [257, 30, 24]], "body": [[544, 99, 61], [520, 105, 69], [450, 96, 72], [405, 81, 65], [346, 87, 66], [300, 63, 49], [281, 35, 32]],
			"shoulder": 304, "arm_x": 65, "elbow_x": 88, "hand_x": 105, "hand_y": 446, "leg_x": 43, "leg_width": 23, "leg_top": 527, "eye_y": 190, "eye_x": 20, "mouth_y": 238, "nose": 10}, true)
		"boy": a.merge({"top": 191, "old": false, "cloth": "3d4b64", "skin": "f2c6ac", "hat_color": "c3373a", "trim": "2f5875", "pants": "2d2f35", "shoe": "2a2424", "hat": "cock", "hat_bottom": 301, "hat_width": 66,
			"face": [[275, 35, 27], [297, 63, 43], [329, 68, 48], [352, 53, 37], [367, 26, 22]], "body": [[506, 73, 47], [480, 84, 56], [426, 81, 59], [382, 63, 48], [360, 35, 28]],
			"shoulder": 384, "arm_x": 60, "elbow_x": 80, "hand_x": 86, "hand_y": 486, "leg_x": 24, "leg_width": 22, "leg_top": 498, "eye_y": 314, "eye_x": 18, "mouth_y": 346, "nose": 11, "mouth": "smile"}, true)
		"shuba": a.merge({"top": 108, "cloth": "9a666b", "skin": "e4eae6", "hat_color": "a6d8e2", "trim": "b08c8e", "shoe": "463b3d", "hat": "turban", "hat_bottom": 188, "hat_width": 56,
			"face": [[181, 23, 24], [199, 36, 34], [223, 45, 42], [247, 55, 46], [262, 47, 38], [271, 22, 20]], "body": [[528, 103, 65], [508, 123, 77], [440, 123, 87], [362, 114, 83], [302, 104, 77], [251, 82, 62], [214, 52, 45]],
			"shoulder": 278, "arm_x": 79, "elbow_x": 98, "hand_x": 104, "hand_y": 452, "leg_x": 58, "leg_width": 25, "leg_top": 510, "eye_y": 220, "eye_x": 18, "mouth_y": 251, "nose": 11}, true)
		"beret": a.merge({"top": 84, "cloth": "f2bde8", "skin": "c9578a", "hat_color": "a4dae6", "trim": "a4dae6", "pants": "7a3577", "shoe": "55484a", "hat": "beret", "hat_bottom": 149, "hat_width": 56,
			"face": [[140, 39, 36], [173, 51, 42], [211, 54, 46], [239, 45, 38], [252, 23, 23]], "body": [[394, 97, 77], [385, 137, 91], [350, 151, 113], [299, 153, 119], [252, 150, 110], [213, 126, 84], [190, 71, 60]],
			"shoulder": 216, "arm_x": 103, "elbow_x": 127, "hand_x": 122, "hand_y": 392, "leg_x": 53, "leg_width": 25, "leg_top": 532, "eye_y": 185, "eye_x": 18, "mouth_y": 225, "nose": 14}, true)
		"violet": a.merge({"top": 100, "cloth": "86497a", "skin": "eee0ea", "hat_color": "c4532f", "trim": "9c8c20", "shoe": "3c2d31", "hat": "turban_knot", "hat_bottom": 179, "hat_width": 61, "head_z": -67,
			"face": [[177, 38, 30], [202, 52, 43], [249, 54, 46], [280, 43, 35], [290, 21, 20]], "body": [[502, 95, 70], [480, 123, 87], [420, 128, 94], [340, 128, 104], [270, 127, 111], [213, 119, 98], [172, 81, 72], [150, 43, 39]],
			"shoulder": 215, "arm_x": 91, "elbow_x": 146, "hand_x": 166, "hand_y": 409, "leg_x": 81, "leg_width": 29, "leg_top": 489, "eye_y": 216, "eye_x": 20, "mouth_y": 265, "nose": 15, "mouth": "open"}, true)
		"ushanka", "ushanka_walk": a.merge({"top": 48, "cloth": "858868", "skin": "ede9e1", "hat_color": "6e4c3e", "trim": "7c2c46", "pants": "c4f1ea", "shoe": "c6432f", "hat": "ushanka", "hat_bottom": 103, "hat_width": 48,
			"face": [[96, 33, 31], [117, 46, 39], [140, 51, 43], [160, 44, 38], [176, 23, 22]], "body": [[308, 69, 57], [300, 84, 66], [254, 91, 70], [198, 93, 66], [171, 75, 54], [166, 41, 37]],
			"shoulder": 198, "arm_x": 71, "elbow_x": 104, "hand_x": 108, "hand_y": 404, "leg_x": 43, "leg_width": 30, "leg_top": 299, "eye_y": 126, "eye_x": 19, "mouth_y": 158, "nose": 15}, true)
		"tourist": a.merge({"top": 55, "cloth": "c3cfae", "skin": "f2e3dd", "hat_color": "b9b98c", "trim": "eba0bc", "pants": "c0a086", "shoe": "8c5242", "hat": "cylinder", "hat_bottom": 132, "hat_width": 42,
			"face": [[116, 31, 28], [147, 43, 38], [177, 47, 42], [198, 34, 32], [205, 18, 18]], "body": [[384, 91, 73], [363, 108, 90], [300, 109, 97], [242, 100, 90], [207, 77, 66], [186, 43, 39]],
			"shoulder": 218, "arm_x": 71, "elbow_x": 94, "hand_x": 99, "hand_y": 405, "leg_x": 46, "leg_width": 31, "leg_top": 360, "eye_y": 148, "eye_x": 17, "mouth_y": 185, "nose": 18, "mouth": "open"}, true)
		"kid", "kid2": a.merge({"top": 127, "old": false, "cloth": "c2f5ee" if id == "kid" else "e2d2f2", "skin": "ebd6cc", "hat_color": "a6eadc" if id == "kid" else "ee7cc6", "trim": "e07cbc", "pants": "93545c" if id == "kid" else "e2a04c", "shoe": "4a4446", "hat": "knit", "hat_bottom": 198, "hat_width": 33,
			"face": [[188, 25, 24], [202, 39, 33], [222, 44, 38], [241, 37, 33], [256, 18, 18]], "body": [[394, 77, 57], [382, 89, 66], [339, 91, 74], [292, 86, 72], [249, 70, 59], [225, 44, 38]],
			"shoulder": 251, "arm_x": 61, "elbow_x": 84, "hand_x": 96, "hand_y": 402, "leg_x": 37, "leg_width": 27, "leg_top": 385, "eye_y": 213, "eye_x": 13, "mouth_y": 243, "nose": 10, "mouth": "smile"}, true)
		"dog": a.merge({"top": 95, "cloth": "fbbee9", "skin": "f7f3c8", "hat_color": "f9b6e2", "trim": "dc97bc", "shoe": "746e69", "hat": "pillbox", "hat_bottom": 163, "hat_width": 59,
			"face": [[151, 33, 30], [180, 46, 39], [221, 49, 44], [250, 42, 37], [266, 20, 21]], "body": [[536, 108, 72], [520, 127, 83], [440, 129, 94], [351, 136, 102], [280, 130, 101], [222, 108, 83], [181, 49, 43]],
			"shoulder": 235, "arm_x": 92, "elbow_x": 113, "hand_x": 129, "hand_y": 432, "leg_x": 50, "leg_width": 26, "leg_top": 516, "eye_y": 191, "eye_x": 18, "mouth_y": 245, "nose": 12, "mouth": "bow"}, true)
		"kolpak": a.merge({"top": 80, "cloth": "a24b53", "skin": "dcdce2", "hat_color": "834376", "trim": "b0975c", "shoe": "3a2c2e", "hat": "curl", "hat_bottom": 171, "hat_width": 43,
			"face": [[182, 27, 27], [207, 43, 38], [240, 49, 43], [267, 42, 37], [290, 20, 21]], "body": [[572, 99, 64], [553, 134, 81], [480, 138, 89], [420, 128, 89], [350, 116, 87], [280, 102, 77], [239, 64, 49]],
			"shoulder": 270, "arm_x": 79, "elbow_x": 115, "hand_x": 128, "hand_y": 350, "leg_x": 51, "leg_width": 26, "leg_top": 545, "eye_y": 216, "eye_x": 21, "mouth_y": 267, "nose": 16}, true)
		"bow": a.merge({"top": 119, "cloth": "d9c78e", "skin": "f2d9f5", "hat_color": "f57e1e", "trim": "e477e0", "shoe": "4a3a36", "hat": "bow", "hat_bottom": 203, "hat_width": 58,
			"face": [[205, 51, 40], [235, 64, 48], [262, 62, 48], [283, 47, 39], [294, 22, 21]], "body": [[560, 99, 64], [548, 134, 79], [520, 142, 85], [470, 135, 88], [420, 123, 85], [370, 112, 80], [318, 107, 71], [283, 93, 56], [263, 53, 40]],
			"shoulder": 309, "arm_x": 82, "elbow_x": 116, "hand_x": 128, "hand_y": 514, "leg_x": 39, "leg_width": 25, "leg_top": 546, "eye_y": 236, "eye_x": 22, "mouth_y": 273, "nose": 20, "mouth": "open_lips"}, true)
		"turban": a.merge({"top": 75, "cloth": "beeef5", "skin": "fbf8da", "hat_color": "b4b664", "trim": "edb0e3", "shoe": "3e3a3e", "hat": "turban_brooch", "hat_bottom": 157, "hat_width": 56,
			"face": [[141, 43, 35], [180, 58, 44], [223, 55, 43], [249, 42, 35], [260, 19, 20]], "body": [[562, 111, 62], [539, 131, 72], [460, 127, 78], [380, 119, 79], [300, 111, 77], [220, 103, 73], [170, 93, 64], [139, 68, 50]],
			"shoulder": 248, "arm_x": 83, "elbow_x": 99, "hand_x": 106, "hand_y": 452, "leg_x": 37, "leg_width": 23, "leg_top": 545, "eye_y": 183, "eye_x": 22, "mouth_y": 237, "nose": 15, "mouth": "open"}, true)
		"officer": a.merge({"top": 15, "cloth": "5f4e29", "skin": "f5a3b0", "hat_color": "665a2e", "trim": "9a2414", "pants": "54513c", "shoe": "28272b", "hat": "officer_cap", "hat_bottom": 74, "hat_width": 46, "head_z": -73,
			"face": [[67, 19, 24], [83, 25, 30], [108, 28, 32], [132, 24, 29], [147, 13, 18]], "body": [[516, 102, 63], [496, 104, 73], [428, 88, 71], [350, 77, 65], [275, 72, 60], [227, 84, 55], [213, 60, 40]],
			"shoulder": 227, "arm_x": 75, "elbow_x": 84, "hand_x": 90, "hand_y": 438, "leg_x": 35, "leg_width": 18, "leg_top": 486, "eye_y": 91, "eye_x": 11, "mouth_y": 130, "nose": 24, "mouth": "teeth"}, true)
	return a

func _p(x: float, y: float, z: float = 0.0) -> Vector3:
	return Vector3(x * unit, (590.0 - y) * unit, z * unit)

func _tint(material: String, color: String) -> void:
	b.vertex_tints[material] = Color(color)

func _e(x: float, y: float, z: float, rx: float, ry: float, rz: float, material: String, color: String, bone: int = 3, segments: int = 12, rings: int = 8) -> void:
	_tint(material, color)
	b.ellipsoid(_p(x, y, z), Vector3(rx, ry, rz) * unit, material, bone, segments, rings)

func _box(x: float, y: float, z: float, sx: float, sy: float, sz: float, material: String, color: String, bone: int = 2, rotation: Basis = Basis.IDENTITY) -> void:
	_tint(material, color)
	b.box(_p(x, y, z), Vector3(sx, sy, sz) * unit, material, bone, rotation)

func _tube(points: Array, radius: float, material: String, color: String, bone: int = 3, sides: int = 6) -> void:
	var path := PackedVector3Array()
	for p: Vector3 in points: path.append(_p(p.x, p.y, p.z))
	_tint(material, color)
	b.tube(path, radius * unit, material, bone, sides)

func _loft(rows: Array, material: String, color: String, bone: int, x: float = 0.0, z: float = 0.0, sides: int = 16) -> void:
	var levels: Array[Vector3] = []
	for row: Array in rows: levels.append(Vector3(float(row[1]) * unit, (590.0 - float(row[0])) * unit, float(row[2]) * unit))
	levels.sort_custom(func(v: Vector3, w: Vector3) -> bool: return v.y < w.y)
	_tint(material, color)
	var starts: Dictionary = {}
	for key: String in b._parts: starts[key] = b._parts[key].positions.size()
	b.body_profile(levels, material, bone, sides)
	var part: Dictionary = b._parts[material]
	for i in range(int(starts.get(material, 0)), part.positions.size()): part.positions[i] += Vector3(x * unit, 0, z * unit)

func _bones() -> void:
	b.add_bone("root", -1, Vector3.ZERO)
	b.add_bone("hips", 0, Vector3(0, .36, 0))
	b.add_bone("spine", 1, Vector3(0, .54, 0))
	b.add_bone("head", 2, _p(0, float(d.face[-1][0]), head_z * .4))
	for s: float in [1.0, -1.0]:
		var suffix := "_l" if s > 0 else "_r"
		var upper := b.add_bone("upper_arm" + suffix, 2, _p(s * float(d.arm_x), d.shoulder))
		var lower := b.add_bone("lower_arm" + suffix, upper, _p(s * float(d.elbow_x), lerpf(float(d.shoulder), float(d.hand_y), .55), -5))
		b.add_bone("hand" + suffix, lower, _p(s * float(d.hand_x), d.hand_y, -15))
	for s: float in [1.0, -1.0]:
		var suffix := "_l" if s > 0 else "_r"
		var leg := b.add_bone("leg" + suffix, 1, Vector3(s * float(d.leg_x) * unit, .355, 0))
		b.add_bone("foot" + suffix, leg, Vector3(s * float(d.leg_x) * unit, .22, 0))

func _body() -> void:
	_loft(d.body, "cloth", d.cloth, 2)
	if role == "beret":
		_loft([[546, 84, 62], [520, 88, 69], [455, 90, 72], [381, 85, 66]], "accent", d.pants, 2)
		for x in range(-70, 80, 20):
			_tube([Vector3(x, 400, -64), Vector3(x * 1.05, 535, -66)], 1.3, "ink", "5c2459", 2, 4)
	if role == "officer":
		# Leaning neck and Adam's apple are exposed between cap/face and high collar.
		_tube([Vector3(0, 220, -17), Vector3(0, 154, -65), Vector3(0, 139, head_z)], 12, "skin", d.skin, 3)
		_e(0, 177, -67, 7, 9, 6, "skin", d.skin)
		for s: float in [-1.0, 1.0]:
			_box(s * 64, 223, -8, 30, 7, 57, "trim", d.trim)
			_box(s * 23, 265, -55, 29, 72, 5, "accent", "71633a", 2, Basis(Vector3.FORWARD, s * .18))
			for y: float in [320.0, 371.0, 423.0]: _e(s * 19, y, -73, 4, 4, 3, "accent", "bba45e", 2, 8, 4)
	else:
		var hem: float = d.body[0][0]
		for y in range(int(d.shoulder) + 60, int(hem) - 20, 57):
			var depth := _row_at(d.body, y).y
			_e(3, y, -depth - 1, 3, 3.3, 2, "ink", "3c303b", 2, 8, 4)
		# A back seam and a rear-only belt give the actual back its own construction.
		if hem > 490:
			var depth := _row_at(d.body, 420).y
			_box(0, 420, depth, 82, 9, 4, "accent", Color(d.cloth).darkened(.15).to_html(false))

func _legs() -> void:
	for s: float in [1.0, -1.0]:
		var leg := 10 if s > 0 else 12
		var x: float = s * float(d.leg_x)
		var width: float = d.leg_width
		var top: float = minf(float(d.leg_top), 590 - .36 / unit)
		var flare := role in ["ushanka", "ushanka_walk"]
		_loft([[575, width * (1.12 if flare else .85), width * .82], [520, width, width * .85], [590 - .22 / unit, width * .91, width * .88], [top, width * (1.15 if role == "officer" else 1), width]], "accent", d.pants, leg, x)
		# Boots have a flattened sole at y=590 and a projecting toe, not floating ovals.
		_loft([[590, width * 1.1, width * 1.35], [582, width * 1.19, width * 1.6], [568, width * 1.07, width * 1.45], [550, width * .8, width * .83]], "accent", d.shoe, leg + 1, x + s * width * .1, -width * .35, 12)
		if role == "officer": _loft([[572, width * .81, width * .83], [523, width * .73, width * .74]], "accent", d.shoe, leg + 1, x)

func _arms() -> void:
	for s: float in [1.0, -1.0]:
		var upper := 4 if s > 0 else 7
		var lower := upper + 1
		var hand := upper + 2
		var sx: float = s * float(d.arm_x)
		var ex: float = s * float(d.elbow_x)
		var hx: float = s * float(d.hand_x)
		var sy: float = d.shoulder
		var hy: float = d.hand_y
		var ey := lerpf(sy, hy, .55)
		var hz := -22.0
		if role == "kolpak" and s < 0: hy = 426; hx = -89; ey = 339
		if role == "officer" and s < 0: hx = -35; hy = 306; ey = 337; hz = -82
		if role == "ushanka":
			if s > 0: ex = 122; ey = 236; hx = 86; hy = 282; hz = -18
			else: ex = -108; ey = 286; hx = -54; hy = 244; hz = -94
		var radius := 22.0 if role not in ["boy", "kid", "kid2", "officer"] else 16.0 if role == "officer" else 17.0
		_tube([Vector3(sx, sy, 0), Vector3(ex, ey, -7)], radius, "cloth", d.cloth, upper, 8)
		_e(ex, ey, -7, radius, radius, radius, "cloth", d.cloth, upper, 10, 6)
		_tube([Vector3(ex, ey, -7), Vector3(hx, hy - 10, hz)], radius * .9, "cloth", d.cloth, lower, 8)
		if role != "man":
			_e(hx, hy, hz, 12 if role != "officer" else 9, 14, 10, "skin", d.skin, hand, 10, 6)
			_e(hx - s * 8, hy - 3, hz - 6, 5, 9, 5, "skin", d.skin, hand, 8, 4)
			if role in ["violet", "kolpak", "officer"]:
				for finger in 4:
					var fx := hx - 7 + finger * 4.5
					_tube([Vector3(fx, hy + 7, hz - 2), Vector3(fx + (finger - 1.5), hy + 23 + (4 if finger in [1, 2] else 0), hz - 4)], 2.3, "skin", d.skin, hand, 5)
		else:
			_e(hx, hy - 2, hz + 3, 9, 10, 7, "skin", d.skin, hand, 10, 6)
			_box(hx, hy, hz - 5, 38, 7, 7, "ink", "181a21", lower, Basis(Vector3.FORWARD, s * .5))

func _row_at(rows: Array, y: float) -> Vector2:
	var result := Vector2(float(rows[0][1]), float(rows[0][2]))
	for i in range(rows.size() - 1):
		var a: Array = rows[i]
		var c: Array = rows[i + 1]
		if y >= minf(a[0], c[0]) and y <= maxf(a[0], c[0]):
			var f := (y - float(a[0])) / (float(c[0]) - float(a[0]))
			return Vector2(lerpf(a[1], c[1], f), lerpf(a[2], c[2], f))
		if absf(float(c[0]) - y) < absf(float(rows[0][0]) - y): result = Vector2(c[1], c[2])
	return result

func _front(x: float, y: float) -> float:
	var dims := _row_at(head_rows, y)
	return head_z - dims.y * sqrt(maxf(.01, 1.0 - pow(x / dims.x, 2)))

func _head() -> void:
	_loft(head_rows, "skin", d.skin, 3, 0, head_z, 20)
	var ey: float = d.eye_y
	for s: float in [-1.0, 1.0]:
		var x: float = s * float(d.eye_x)
		var z := _front(x, ey)
		var size := 5.2 if role not in ["boy", "woman", "babka"] else 6.5
		if role == "kolpak":
			_box(x, ey, z - 3, 25, 13, 5, "ink", "1c1719", 3, Basis(Vector3.FORWARD, s * .07))
		else:
			_e(x, ey, z - 1.5, size + 1, size * .69, 2.3, "ink", "211f27", 3, 10, 6)
			_e(x, ey + .8, z - 3, size, size * .42, 2, "eye", "ffffff", 3, 10, 6)
			_e(x + .6, ey + .8, z - 4.8, 1.6, 2.2, 1, "ink", "211f27", 3, 8, 4)
			# Upper lids are solid colored skin, and meet the eye's curved surface.
			_e(x, ey - 2.5, z - 2, size * 1.02, size * .31, 2.2, "skin", d.skin, 3, 10, 4)
			if d.old:
				_tube([Vector3(x - 5, ey + 7, _front(x - 5, ey + 7) - 1), Vector3(x, ey + 8.5, _front(x, ey + 8.5) - 1), Vector3(x + 5, ey + 7, _front(x + 5, ey + 7) - 1)], .9, "ink", "665762", 3, 4)
		if role in ["man", "ushanka", "ushanka_walk", "officer"]:
			_tube([Vector3(x - 7, ey - 9 - s, _front(x - 7, ey - 9) - 2), Vector3(x + 6, ey - 8 + s, _front(x + 6, ey - 8) - 2)], 1.7, "ink", "4b4144", 3, 5)
		if role in ["kid", "kid2", "boy"]: _e(s * float(d.eye_x) * 1.28, ey + 13, _front(s * float(d.eye_x) * 1.28, ey + 13), 11, 7, 2.4, "skin", "df9d9e", 3, 10, 6)
	var ny := ey + (18 if role not in ["officer", "man"] else 24)
	var nz := _front(0, ny)
	var nose: float = d.nose
	_e(0, ey + 9, _front(0, ey + 9) - 3, nose * .4, 12, nose * .48, "skin", d.skin)
	_e(0, ny, nz - nose * .58, nose * .69, nose * .56, nose * .94, "skin", d.skin)
	for s: float in [-1.0, 1.0]: _e(s * nose * .34, ny + nose * .34, nz - nose * 1.15, 1.5, 1, 1, "ink", "5e444d", 3, 8, 4)
	var my: float = d.mouth_y
	var mz := _front(0, my)
	if d.mouth in ["open", "open_lips", "teeth", "bow"]:
		if d.mouth in ["open_lips", "bow"]: _e(0, my, mz - 1.2, 12, 7, 2.6, "accent", "d2485c")
		_e(0, my, mz - 2.5, 8.5, 6 if d.mouth != "teeth" else 3.5, 2.5, "ink", "38202b")
		if d.mouth == "teeth": _e(0, my - .6, mz - 4, 7.5, 1.8, 1, "eye", "fff9dc", 3, 10, 4)
	else:
		var middle := my - 4 if d.mouth == "frown" else my + 4
		_tube([Vector3(-14, my, _front(-14, my) - 1), Vector3(0, middle, _front(0, middle) - 1.6), Vector3(14, my, _front(14, my) - 1)], 1.4, "ink", "48323c", 3, 5)
	if d.old:
		for s: float in [-1.0, 1.0]:
			var x := s * (nose + 5)
			_tube([Vector3(x, ny + 2, _front(x, ny + 2) - 1), Vector3(x + s * 4, my - 3, _front(x + s * 4, my - 3) - 1), Vector3(x + s * 1, my + 8, _front(x + s, my + 8) - 1)], .9, "ink", "88717a", 3, 4)
	if role == "officer":
		for s: float in [-1.0, 1.0]:
			_tube([Vector3(s * 3, 115, _front(s * 3, 115) - 2), Vector3(s * 12, 120, _front(s * 12, 120) - 2), Vector3(s * 17, 131, _front(s * 17, 131) - 1)], 3, "accent", "bfbec2", 3)
			_e(s * 25, 107, head_z + 5, 6, 30, 14, "accent", "bfbec2")
	if role in ["man", "boy"]:
		var young := role == "boy"
		var hair_y := 322.0 if young else 170.0
		var hair_color := "6a4a34" if young else "4b3f37"
		_e(0, hair_y, head_z + 28, 61 if young else 66, 22 if young else 41, 30, "accent", hair_color)
		for s: float in [-1.0, 1.0]: _e(s * (69 if young else 72), 316 if young else 164, head_z + 4, 7 if young else 8, 15 if young else 18, 10, "skin", d.skin)
	if role == "man":
		for i in range(16):
			var x := -45 + (i % 8) * 12
			var y := 208.0 + (i / 8) * 8
			_e(x, y, _front(x, y) - .7, .9, 1.6, .9, "ink", "695153", 3, 6, 4)

func _hat() -> void:
	var top: float = d.top
	var bottom: float = d.hat_bottom
	var w: float = d.hat_width
	var c: String = d.hat_color
	var h := bottom - top
	var z := head_z + 7
	match d.hat:
		"kerchief", "hood":
			var trim: String = d.trim if d.hat == "hood" else c
			# Rear fabric is a whole hood, while the opening frames the real head.
			var fabric_height := 99.0 if d.hat == "kerchief" else 114.0
			_e(0, top + fabric_height, head_z + 29, w, fabric_height, w * .78, "accent", c)
			for s: float in [-1.0, 1.0]:
				_tube([Vector3(s * w * .52, top + 43, head_z - 36), Vector3(s * w * .89, top + 85, head_z - 40), Vector3(s * w * .81, top + 150, head_z - 34), Vector3(s * 39, top + 190, head_z - 22)], 9 if d.hat == "kerchief" else 12, "trim", trim, 3, 8)
			if d.hat == "kerchief":
				_e(0, 318, -68, 12, 10, 8, "accent", c)
				_tube([Vector3(-5, 324, -60), Vector3(-19, 357, -56)], 7, "accent", c)
				_tube([Vector3(5, 324, -60), Vector3(19, 357, -56)], 7, "accent", c)
				for s: float in [-1.0, 1.0]:
					for y: float in [145.0, 189.0, 236.0]: _e(s * w * .75, y, head_z - 40, 3.1, 3.1, 2, "trim", "d7c9a1", 3, 8, 4)
			else:
				# Fur spans only the opening, leaving hair and cheeks visible.
				_tube([Vector3(-58, 134, head_z - 37), Vector3(0, 114, head_z - 42), Vector3(58, 134, head_z - 37)], 11, "trim", d.trim)
				_e(0, 145, head_z - 43, 58, 18, 10, "accent", "5a3f31")
		"knit", "cock", "cylinder":
			_loft([[bottom, w, w * .75], [bottom - h * .28, w, w * .8], [top + h * .17, w * .77, w * .65], [top, .2, .2]], "accent", c, 3, 0, z)
			_loft([[bottom + 3, w * 1.04, w * .8], [bottom - 17, w * 1.04, w * .81]], "accent", c, 3, 0, z)
			if d.hat == "cylinder":
				# The tourist has a straight tall crown and button, not a bobble beanie.
				_loft([[bottom - 4, w * .96, w * .76], [top + 10, w * .94, w * .75]], "accent", c, 3, 0, z)
				_e(0, top + 5, z, 5, 5, 5, "accent", Color(c).darkened(.15).to_html(false))
			elif d.hat == "cock":
				_e(42, top + 10, z + 10, 11, 10, 10, "trim", "ece5d6")
				for band: Vector3 in [Vector3(239, w * .89, w * .735), Vector3(266, w * 1.005, w * .81), Vector3(290, w * 1.05, w * .825)]:
					_loft([[band.x + 3, band.y + .5, band.z + .5], [band.x - 3, band.y - .5, band.z - .5]], "trim", "ece5d6", 3, 0, z)
			else:
				for x in range(-int(w) + 10, int(w), 13):
					var nz := z - w * .8 * sqrt(maxf(.05, 1.0 - pow(float(x) / w, 2)))
					_tube([Vector3(x, bottom, nz - 1), Vector3(x * .95, bottom - 15, nz - 1)], 1, "accent", Color(c).darkened(.18).to_html(false), 3, 4)
		"ushanka":
			_loft([[bottom, w, w * .8], [top + 12, w, w * .75], [top, 13, 20]], "accent", c, 3, 0, z)
			_box(0, 92, z - 34, 95, 20, 15, "accent", "52372b", 3)
			for s: float in [-1.0, 1.0]:
				_tube([Vector3(s * 43, 91, z), Vector3(s * 64, 113, z - 1), Vector3(s * 71, 132, z - 4)], 13, "accent", c)
		"officer_cap":
			_loft([[66, 35, 34], [50, 43, 40], [29, 47, 40], [top, 11, 15]], "accent", c, 3, 4, z)
			_loft([[74, 36, 35], [57, 37, 36]], "trim", d.trim, 3, 3, z)
			_box(7, 72, z - 41, 86, 8, 51, "ink", "27252c", 3, Basis(Vector3.FORWARD, -.08))
			_e(8, 63, z - 37, 4, 5, 2, "accent", "bda162")
		"beret":
			_e(-5, top + h * .47, z, w, h * .47, w * .83, "accent", c)
			_loft([[bottom, w * .78, w * .69], [bottom - 9, w * .82, w * .71]], "accent", c, 3, 0, z)
			# Orange side curls and nape remain visible in both profile and back.
			for s: float in [-1.0, 1.0]: _e(s * 48, 164, head_z + 12, 13, 29, 21, "accent", "e2783a")
			_e(0, 172, head_z + 29, 44, 28, 25, "accent", "e2783a")
		"pillbox", "bow":
			_loft([[bottom, w, w * .75], [top + 22, w * .96, w * .75], [top + 5, w * .57, w * .5], [top, 7, 8]], "accent", c, 3, 0, z)
			if d.hat == "bow":
				_loft([[214, w * 1.08, w * .84], [184, w * 1.08, w * .84]], "trim", d.trim, 3, 0, z)
				for s: float in [-1.0, 1.0]: _e(-45 + s * 13, 197, z - 52, 16, 14, 7, "trim", d.trim)
				_e(-45, 198, z - 59, 5, 7, 5, "trim", "c35cc2")
			else: _flower(45, 143, z - 35, "e9819f", 3)
		"curl":
			_loft([[bottom, 40, 33], [148, 42, 33], [127, 32, 28], [107, 22, 21], [88, 9, 12], [top, .2, .2]], "accent", c, 3, 8, z)
			_tube([Vector3(16, 89, z), Vector3(23, 99, z - 2), Vector3(30, 113, z - 4)], 6, "accent", c)
			_e(0, 176, head_z + 20, 47, 20, 29, "accent", "de3a4c")
			for s: float in [-1.0, 1.0]: _e(s * 44, 179, head_z, 12, 14, 17, "accent", "de3a4c")
		_:
			_loft([[bottom, w, w * .75], [top + h * .5, w, w * .8], [top + h * .18, w * .66, w * .61], [top, 1, 1]], "accent", c, 3, 0, z)
			for fraction: float in [.28, .52, .75]:
				var y := bottom - h * fraction
				var width := w * (1.0 - fraction * .45)
				_tube([Vector3(-width, y + 4, z - w * .25), Vector3(0, y - 9, z - w * .8), Vector3(width, y - 2, z - w * .25)], 1.3, "accent", Color(c).darkened(.22).to_html(false), 3, 5)
			if d.hat == "turban_knot": _e(32, 165, z - 39, 12, 10, 9, "accent", "de7448")
			if d.hat == "turban_brooch": _e(0, 134, z - 42, 6, 6, 4, "trim", "e8e2c0")
			if role == "shuba": _e(-48, 174, z - 15, 12, 12, 9, "accent", "e2a3c6")

func _scarf(y: float, width: float, depth: float, color: String, wraps: int = 1) -> void:
	var center_z := -maxf(25.0, _row_at(d.body, y).y * .65)
	for i in wraps:
		_e(0, y + i * 12, center_z, width, 18, depth, "trim", color, 3, 14, 6)
	_tube([Vector3(14, y + 10, center_z - depth - 5), Vector3(27, y + 55, center_z - depth + 2)], 9, "trim", color, 3, 6)

func _wrapped_scarf(top: float, bottom: float, width: float, color: String, collar_only: bool = false) -> void:
	# The original shawls surround the cheeks and cover the nape. A U-shaped
	# front roll joins a closed rear hood; the lower cloth spans the chest.
	var middle := (top + bottom) * .5
	var body_depth := _row_at(d.body, middle).y
	var front := -maxf(92.0, body_depth + 11.0)
	var back := 0.0
	for row: Array in d.body:
		if float(row[0]) >= top and float(row[0]) <= bottom: back = maxf(back, float(row[2]))
	back = maxf(back, _row_at(d.body, middle).y) + 2.0
	_e(0, middle - (19 if collar_only else 0), back, width, 23 if collar_only else (bottom - top) * .5, 38, "trim", color)
	for side: float in [-1.0, 1.0]:
		_tube([Vector3(side * width * .73, top, front + 23), Vector3(side * width * .91, middle - 8, front + 9), Vector3(side * width * .78, bottom - 20, front), Vector3(side * width * .38, bottom - 5, front - 3), Vector3(0, bottom, front - 5)], 12, "trim", color, 3, 8)
	var face_bottom: float = d.face[-1][0]
	var cloth_top := maxf(face_bottom + 10, bottom - 36)
	_loft([[bottom + 7, width * .48, 8], [bottom - 2, width * .78, 12], [cloth_top, width * .72, 10]], "trim", color, 3, 0, front + 8)
	if not collar_only:
		# Rear folds are visible above the coat instead of a second face.
		for fraction: float in [.4, .65]:
			var y := lerpf(top, bottom, fraction)
			_tube([Vector3(-width * .7, y, back + 9), Vector3(0, y + 9, back + 16), Vector3(width * .7, y, back + 9)], 1.2, "trim", Color(color).darkened(.16).to_html(false), 3, 5)

func _bag(x: float, y: float, width: float, height: float, color: String, bone: int) -> void:
	# Thickness and two closed handle tubes make a bag from every direction.
	var bottom := minf(y + height, 590 - .145 / unit)
	_loft([[bottom, width * .38, width * .16], [bottom - 8, width * .48, width * .20], [y + 30, width * .44, width * .18], [y + 20, width * .28, width * .15]], "trim", color, bone, x, -15, 12)
	for s: float in [-1.0, 1.0]:
		_tube([Vector3(x + s * width * .27, y + 25, -17), Vector3(x + s * width * .17, y + 3, -17), Vector3(x, y - 3, -17)], 2.5, "trim", color, bone, 5)

func _flower(x: float, y: float, z: float, color: String, bone: int) -> void:
	for i in 5:
		var angle := TAU * i / 5.0
		_e(x + 7 * cos(angle), y + 7 * sin(angle), z, 5, 5, 4, "trim", color, bone, 8, 4)
	_e(x, y, z - 4, 4, 4, 3, "trim", "e6c764", bone, 8, 4)

func _details() -> void:
	match role:
		"babka":
			_bag(-113, 446, 74, 102, "7a6b58", 9)
			_bag(113, 446, 77, 102, "47474e", 6)
			for x in range(-139, -85, 13): _box(x, 499, -34, 2, 54, 2, "accent", "5b4e40", 9)
			for y in range(477, 531, 13): _box(-113, y, -34, 58, 2, 2, "accent", "5b4e40", 9)
		"man":
			for y: float in [292.0, 342.0, 392.0, 442.0]:
				var dims := _row_at(d.body, y)
				_tube([Vector3(-dims.x * .8, y, -dims.y * .6), Vector3(0, y + 7, -dims.y - 1), Vector3(dims.x * .8, y, -dims.y * .6)], 1.3, "ink", "171a22", 2, 5)
		"woman":
			var sled_start: Dictionary = {}
			for key: String in b._parts: sled_start[key] = b._parts[key].positions.size()
			# The reserve woman's sled is also solid: two runners, upright struts, slatted seat.
			for x: float in [-35.0, 35.0]:
				_tube([Vector3(x, 587, 88), Vector3(x, 587, 240), Vector3(x, 574, 254), Vector3(x, 559, 248)], 3, "trim", "3a3a40", 13)
				for z: float in [115.0, 210.0]: _tube([Vector3(x, 586, z), Vector3(x, 551, z)], 3, "trim", "3a3a40", 13)
			for z in range(103, 238, 22): _box(0, 549, z, 83, 9, 17, "accent", "2e8e86", 13)
			_tube([Vector3(105, 446, -22), Vector3(84, 481, 86), Vector3(35, 561, 246)], 1.7, "trim", "cdbfa0", 13)
			# A dragged sled stays level during opposite leg swings. Both feet move
			# together when seated, retaining the shared sole-height contract.
			for key: String in b._parts:
				var part: Dictionary = b._parts[key]
				for i in range(int(sled_start.get(key, 0)), part.positions.size()):
					part.bones[i * 4] = 11
					part.bones[i * 4 + 1] = 13
					part.weights[i * 4] = .5
					part.weights[i * 4 + 1] = .5
		"boy", "tourist":
			var boy := role == "boy"
			var y := 438.0 if boy else 281.0
			var w := 59.0 if boy else 91.0
			var color := "5c5047" if boy else "bfb070"
			_e(0, y, 78 if boy else 91, w, 61 if boy else 103, 32 if boy else 46, "accent", color, 2)
			_box(0, y + 17, 111 if boy else 135, w * 1.4, 32, 5, "accent", Color(color).darkened(.15).to_html(false))
			for s: float in [-1.0, 1.0]: _tube([Vector3(s * 42, float(d.shoulder), -26), Vector3(s * 38, y + 25, -float(_row_at(d.body, y).y))], 5, "accent", color, 2)
			if not boy:
				_scarf(203, 55, 57, d.trim)
				_e(101, 438, -20, 15, 23, 14, "trim", "f2f2ec", 6)
				_box(101, 414, -20, 27, 5, 25, "trim", "cfd2ca", 6)
				_tube([Vector3(88, 420, -20), Vector3(90, 401, -20), Vector3(110, 401, -20), Vector3(114, 420, -20)], 2, "trim", "cfd2ca", 6)
		"shuba":
			# Shawl collar embraces the coat, staying behind the pear-shaped face.
			_e(0, 307, -45, 91, 22, 65, "trim", d.trim, 2)
			for s: float in [-1.0, 1.0]: _e(s * 57, 282, -54, 33, 35, 24, "trim", d.trim, 2)
			_bag(-104, 452, 94, 94, "eef6f4", 9)
			_bag(104, 452, 56, 64, "eef6f4", 6)
		"beret":
			_scarf(247, 56, 59, d.trim)
			for s: float in [-1.0, 1.0]: _bag(s * 121, 392, 70, 96, "f2e7a2", 6 if s > 0 else 9)
		"violet":
			_wrapped_scarf(178, 334, 86, d.trim)
			_flower(58, 291, -74, "b6a63c", 3)
			_bag(166, 409, 56, 116, "ede6aa", 6)
		"ushanka", "ushanka_walk":
			_scarf(186, 82, 68, d.trim)
			_box(-44, 221, 66, 21, 65, 9, "trim", d.trim, 3, Basis(Vector3.FORWARD, -.25))
			if role == "ushanka":
				_tube([Vector3(-54, 244, -99), Vector3(-29, 241, -115)], 2.4, "trim", "f6eee0", 9)
				_e(-29, 241, -115, 2.5, 2.5, 2.5, "accent", "a25135", 9, 6, 4)
		"kid": _scarf(254, 48, 49, d.trim)
		"dog":
			_wrapped_scarf(166, 290, 79, d.trim)
			_bag(-129, 432, 84, 118, "f5f6a2", 9)
			_dog()
		"kolpak":
			_wrapped_scarf(247, 326, 82, d.trim, true)
			_e(23, 320, -79, 15, 13, 10, "trim", d.trim)
			_tube([Vector3(-20, 216, _front(-20, 216)), Vector3(0, 214, _front(0, 214)), Vector3(20, 216, _front(20, 216))], 1.4, "ink", "1c1719")
		"bow":
			for s: float in [-1.0, 1.0]: _e(s * 42, 313, -53, 44, 27, 26, "cloth", "c7b37c", 2)
			for x in [-86, -58, 58, 86]: _tube([Vector3(x, 374, -67), Vector3(x * 1.08, 520, -65)], 1.2, "accent", "b8a46c", 2, 4)
		"turban":
			# Pink face-wrapping scarf has a full rear hood and two cheek-side rolls.
			_e(0, 216, head_z + 25, 82, 87, 66, "trim", d.trim)
			_wrapped_scarf(140, 293, 77, d.trim)
		"officer":
			_box(-38, 304, -97, 57, 83, 10, "accent", "795b36", 9, Basis(Vector3.FORWARD, -.13))
			_box(-38, 304, -104, 46, 68, 2, "trim", "d6ccac", 9, Basis(Vector3.FORWARD, -.13))
			_box(-43, 265, -106, 14, 9, 4, "trim", "aaa596", 9)

func _dog() -> void:
	const C := "f4f5b0"
	# Small ground-standing dog is modeled as a quadruped, including far-side legs.
	var x := 151.0
	_e(x, 551, -20, 31, 20, 17, "trim", C, 13, 12, 6)
	_e(x - 30, 537, -23, 14, 13, 12, "trim", C, 13, 10, 6)
	_e(x - 42, 540, -25, 4, 3, 5, "ink", "28232b", 13, 8, 4)
	_e(x - 33, 533, -34, 2, 2, 1.5, "ink", "28232b", 13, 8, 4)
	for z: float in [-31.0, -9.0]:
		for dx: float in [-18.0, 18.0]: _tube([Vector3(x + dx, 560, z), Vector3(x + dx - 2, 589.7, z)], 3.2, "trim", C, 13)
	for dx: float in [-37.0, -24.0]: _loft([[531, 6, 5], [516, .2, .2]], "trim", C, 13, x + dx, -22)
	_tube([Vector3(x + 26, 546, -20), Vector3(x + 40, 531, -20), Vector3(x + 40, 517, -20), Vector3(x + 31, 511, -20)], 3, "trim", C, 13)
	_tube([Vector3(129, 432, -22), Vector3(155, 488, -17), Vector3(x - 25, 550, -20)], 1.3, "ink", "584558", 13)

func _skin_clothing() -> void:
	# Two-joint lower legs retain the shared seated solver. Long coats also bend
	# with the thighs, rather than leaving a rigid skirt passing through the seat.
	for part: Dictionary in b._parts.values():
		var vertices: PackedVector3Array = part.positions
		var bones: PackedInt32Array = part.bones
		var weights: PackedFloat32Array = part.weights
		for i in vertices.size():
			var offset := i * 4
			var bone := bones[offset]
			if bone in [10, 12] and vertices[i].y < .22: bones[offset] = bone + 1
			elif bone == 2 and vertices[i].y < .42:
				var influence := clampf((.42 - vertices[i].y) / .065, 0, 1)
				bones[offset + 1] = 10 if vertices[i].x > 0 else 12
				weights[offset] = 1 - influence
				weights[offset + 1] = influence
		part.bones = bones
		part.weights = weights

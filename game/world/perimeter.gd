extends Node3D
## PERIMETER-01: two permanent street closures. Layout owns every gameplay box.
## Track furniture outside the arena and warning arms are visual scenery only.
const Layout = preload("res://game/world/layout.gd")
const Train = preload("res://game/vehicles/er2k_train_visual.gd")
const Lada = preload("res://game/vehicles/lada_visual.gd")
const Greybox = preload("res://game/world/greybox.gd")
const Materials = preload("res://game/world/materials.gd")

const STEEL := Color(0.16, 0.19, 0.19)
const RED := Color(0.70, 0.055, 0.035)
const WHITE := Color(0.87, 0.88, 0.84)
const BLUE := Color(0.035, 0.20, 0.68)
const SNOW := Color(0.83, 0.86, 0.88)
var _batches: Dictionary = {}
var _solids: Dictionary = {}

func _ready() -> void:
	name = "PermanentStreetClosures"
	for spec: Array in Layout.perimeter_solids():
		_solids[spec[0]] = spec
	_train()
	_crossing()
	_police_post()
	_warnings()
	_courtyard_walls()
	_flush()

func _box(size: Vector3, at: Vector3, color: Color, yaw := 0.0) -> void:
	if not _batches.has(color):
		_batches[color] = []
	(_batches[color] as Array).append(Transform3D((Basis(Vector3.UP, yaw) * Basis.from_scale(size)), at))

func _beam(a: Vector3, b: Vector3, width: float, height: float, color: Color) -> void:
	var delta := b - a
	_box(Vector3(width, height, delta.length()), (a + b) * 0.5, color, atan2(delta.x, delta.z))

func _label(text: String, at: Vector3, yaw: float, size: int, color := WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.rotation.y = yaw
	label.font_size = size
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 4
	label.no_depth_test = false
	add_child(label)

func _train() -> void:
	var cars := Layout.train_cars()
	for i in cars.size():
		var car: Array = cars[i]
		var visual := Train.build_car(i == 0 or i == cars.size() - 1)
		visual.name = "RailCar%d" % i
		visual.position = Vector3(car[0].x, 0, car[0].y)
		visual.rotation.y = car[1] + (PI if i == cars.size() - 1 else 0.0)
		add_child(visual)
	# The full-height rubber bellows occupy the space between car ends. No invisible
	# fence sits behind the couplings; these visible boxes are the canonical blockers.
	for solid: Array in Layout.perimeter_solids():
		var p: Vector2 = solid[2]
		var size: Vector3 = solid[3]
		if solid[1] == "perimeter_gangway":
			_box(size, Vector3(p.x, size.y * 0.5, p.y), Color(0.095, 0.12, 0.11))
		elif solid[1] == "perimeter_wall":
			_box(Vector3(size.x, 0.12, size.z + 0.08), Vector3(p.x, size.y + 0.04, p.y), SNOW)
	var d := -96.0
	while d < 146.0:
		var p := Layout.train_track(d)
		var q := Layout.train_track(d + 0.8)
		var v := (q - p).normalized()
		var across := Vector2(v.y, -v.x)
		var yaw := atan2(v.x, v.y)
		_box(Vector3(4.5, 0.10, 0.82), Vector3(p.x, -0.015, p.y), Color(0.30, 0.31, 0.29), yaw)
		_box(Vector3(2.65, 0.10, 0.20), Vector3(p.x, 0.025, p.y), Color(0.27, 0.23, 0.18), yaw)
		for side: float in [-1.0, 1.0]:
			var a := p + across * side * 0.76
			var b := q + across * side * 0.76
			_beam(Vector3(a.x, 0.04, a.y), Vector3(b.x, 0.04, b.y), 0.075, 0.08, STEEL)
		d += 0.8
	# One-sided railway masts remain west of the train and outside playable bounds.
	for k in 9:
		var p := Layout.train_track(-82.0 + k * 26.0)
		_box(Vector3(0.24, 6.7, 0.24), Vector3(p.x - 5.0, 3.35, p.y), Color(0.38, 0.40, 0.38))
		_box(Vector3(5.2, 0.14, 0.14), Vector3(p.x - 2.5, 6.3, p.y), STEEL)
		_box(Vector3(0.18, 0.45, 0.18), Vector3(p.x, 6.0, p.y), Color(0.28, 0.22, 0.16))
	var previous := Layout.train_track(-96.0)
	for k in 120:
		var p := Layout.train_track(-96.0 + (k + 1) * 2.0)
		_beam(Vector3(previous.x, 5.5, previous.y), Vector3(p.x, 5.5, p.y), 0.022, 0.022, STEEL)
		previous = p

func _crossing() -> void:
	# Recessed timber crossing deck; the coach side is the actual road closure.
	var centre := Layout.TRAIN_CENTRE
	var near: Vector2 = _solids["CrossingPedestal24"][2]
	_box(Vector3(7.0, 0.04, 14.0), Vector3(centre.x + 4.1, 0.025, centre.y), Color(0.24, 0.21, 0.17))
	for spec: Array in _solids.values():
		if spec[1] != "perimeter_pedestal":
			continue
		var p: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		var z := p.y
		_box(size, Vector3(p.x, size.y * 0.5, z), Color(0.72, 0.70, 0.63))
		var direction := 1.0 if z < centre.y else -1.0
		for j in 16:
			_box(Vector3(0.16, 0.18, 0.47), Vector3(p.x, 1.12, z + direction * (j * 0.47 + 0.235)), RED if j % 2 == 0 else WHITE)
		_box(Vector3(0.12, 3.2, 0.12), Vector3(p.x + size.x * 0.5, 1.6, z), STEEL)
		_box(Vector3(0.18, 0.5, 1.1), Vector3(p.x + size.x * 0.5, 2.5, z), STEEL)
		for dz in [-0.30, 0.30]:
			var lamp := Greybox.mesh_sphere(0.16, RED)
			lamp.position = Vector3(p.x + size.x * 0.5 + 0.12, 2.5, z + dz)
			lamp.material_override = Materials.plain(RED, 0.35, RED, 2.0)
			add_child(lamp)
		if direction < 0.0:
			_label("ПЕРЕЕЗД ЗАКРЫТ", Vector3(p.x + 0.6, 3.0, p.y), PI * 0.5, 48, WHITE)
	_box(Vector3(0.25, 0.025, 12.0), Vector3(near.x + 3.0, 0.045, centre.y), WHITE)
	_label("СТОП", Vector3(near.x + 3.2, 0.45, near.y - 0.4), PI * 0.5, 80, WHITE)

func _police_post() -> void:
	var car_spec: Array = _solids["LeninPoliceCar"]
	var p: Vector2 = car_spec[2]
	var car_size: Vector3 = car_spec[3]
	var police := Lada.build(WHITE, "", false, 0.1, 0.03)
	police.position = Vector3(p.x, 0, p.y)
	add_child(police)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.035, 0.25, 3.3), Vector3(p.x + side * (car_size.x * 0.5 + 0.01), 0.82, p.y + 0.15), BLUE)
		_label("ПОЛИЦИЯ", Vector3(p.x + side * (car_size.x * 0.5 + 0.034), 0.89, p.y), side * PI * 0.5, 32, WHITE)
	_box(Vector3(1.05, 0.09, 0.32), Vector3(p.x, car_size.y + 0.057, p.y), STEEL)
	_box(Vector3(0.32, 0.22, 0.3), Vector3(p.x - 0.35, car_size.y + 0.187, p.y), BLUE)
	_box(Vector3(0.32, 0.22, 0.3), Vector3(p.x + 0.35, car_size.y + 0.187, p.y), BLUE)
	# Continuous ribbed steel shutter and posts are the permanent final barrier.
	var shutter: Array = _solids["LeninEastShutter"]
	p = shutter[2]
	var size: Vector3 = shutter[3]
	for k in 5:
		var z := p.y + (float(k) / 4.0 - 0.5) * (size.z - 0.2)
		_box(Vector3(size.x + 0.07, size.y, 0.22), Vector3(p.x, size.y * 0.5, z), STEEL)
	for k in int((size.z - 0.7) / 0.5):
		_box(Vector3(0.03, size.y - 0.35, 0.06), Vector3(p.x - size.x * 0.5 - 0.015, size.y * 0.5 + 0.03, p.y - size.z * 0.5 + 0.5 + k * 0.5), Color(0.32, 0.37, 0.36))
	_box(Vector3(size.x + 0.1, 0.12, size.z + 0.1), Vector3(p.x, size.y + 0.03, p.y), SNOW)
	_label("ПРОЕЗД ЗАКРЫТ", Vector3(p.x - size.x * 0.5 - 0.035, size.y * 2.0 / 3.0, p.y), -PI * 0.5, 85, WHITE)
	for spec: Array in _solids.values():
		if spec[1] != "perimeter_barrier":
			continue
		var at: Vector2 = spec[2]
		var barrier: Vector3 = spec[3]
		for j in int(barrier.z / 0.5):
			_box(Vector3(0.035, 0.45, 0.5), Vector3(at.x - barrier.x * 0.5 - 0.02, 0.84, at.y - barrier.z * 0.5 + 0.25 + j * 0.5), RED if j % 2 == 0 else WHITE)
		_box(Vector3(barrier.x + 0.1, 0.08, barrier.z + 0.1), Vector3(at.x, barrier.y + 0.04, at.y), SNOW)

func _warnings() -> void:
	# A reflective sign face stays legible in the unlit street shadow. It adds
	# no light to the world and keeps ordinary depth occlusion and scene fog.
	var face_material := StandardMaterial3D.new()
	face_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_material.albedo_color = Color(0.86, 0.72, 0.32)
	face_material.roughness = 1.0
	for i in Layout.PERIMETER_WARNINGS.size():
		var warning: Array = Layout.PERIMETER_WARNINGS[i]
		var p: Vector2 = warning[0]
		var yaw: float = warning[1]
		var post := Vector3(p.x, 2.9, p.y)
		var face := Vector3(sin(yaw), 0, cos(yaw))
		var centre := post + face * 0.10
		_box(Vector3(0.12, 3.1, 0.12), Vector3(p.x, 1.55, p.y), STEEL)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(4.5, 1.35, 0.12)
		mesh.material = face_material
		var board := MeshInstance3D.new()
		board.name = "WarningBoard%d" % i
		board.mesh = mesh
		board.position = centre
		board.rotation.y = yaw
		add_child(board)
		_warning_label(warning[2], centre + Vector3.UP * 0.22 + face * 0.071, yaw, 63)
		_warning_label(warning[3], centre - Vector3.UP * 0.22 + face * 0.071, yaw, 35)

func _warning_label(text: String, at: Vector3, yaw: float, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.rotation.y = yaw
	label.font_size = size
	label.pixel_size = 0.006
	label.modulate = Color(0.025, 0.03, 0.025)
	label.outline_size = 0
	label.shaded = false
	label.no_depth_test = false
	add_child(label)

func _courtyard_walls() -> void:
	# Vertical joints and coping make the colliding concrete boundary legible from ground level.
	for wall: Array in Layout.PERIMETER_WALLS:
		var a: Vector2 = wall[0]
		var b: Vector2 = wall[1]
		if a.x != b.x and a.y != b.y: continue
		var delta := b - a
		var count := maxi(1, ceili(delta.length() / 4.0))
		var along_z := a.x == b.x
		for k in count + 1:
			var p := a.lerp(b, float(k) / count)
			var size := Vector3(wall[2] + 0.04, wall[3] - 0.06, 0.14) if along_z else Vector3(0.14, wall[3] - 0.06, wall[2] + 0.04)
			_box(size, Vector3(p.x, size.y * 0.5, p.y), Color(0.32, 0.35, 0.34))

func _flush() -> void:
	for color: Color in _batches:
		var entries: Array = _batches[color]
		var mesh := BoxMesh.new()
		mesh.material = Materials.plain(color)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = entries.size()
		for i in entries.size():
			multi.set_instance_transform(i, entries[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		add_child(node)

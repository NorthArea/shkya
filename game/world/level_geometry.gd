extends Node3D
## LevelGeometry: земля, здания, декор и покрытия из Layout (C1). Коллизии — простые коробки;
## внешний вид зимнего Новосибирска — процедурный (ART-02): фасады с окнами, гаражи, сугробы, фонари, вывески.

const Layout = preload("res://game/world/layout.gd")
const Greybox = preload("res://game/world/greybox.gd")
const Materials = preload("res://game/world/materials.gd")

const WALL_HEIGHT := 12.0
const WALL_THICKNESS := 2.0
const SHOP_FRONTS := ["H5_North", "H6_West", "H8_East"]
const GARAGE_DOOR_SIDE := {"Garages_Yard": -1.0, "Garages_Kiosk": 1.0}   # дверями к двору / к улице
const GARAGE_COLORS := [Color(0.42, 0.30, 0.22), Color(0.30, 0.38, 0.32), Color(0.36, 0.38, 0.42), Color(0.45, 0.40, 0.33)]
const CAR_COLORS := [Color(0.18, 0.22, 0.30), Color(0.55, 0.48, 0.36), Color(0.35, 0.12, 0.10)]
const WARM := Color(1.0, 0.75, 0.42)

# Надписи: [текст, позиция, поворот y, размер шрифта, цвет].
const SIGNS := [
	["3", Vector3(-41.7, 2.55, 107.94), PI, 90, Color(0.92, 0.92, 0.9)],
	["кв. 36–60", Vector3(-41.7, 2.2, 107.94), PI, 36, Color(0.92, 0.92, 0.9)],
	["АПТЕКА", Vector3(-70, 3.3, 14.05), 0.0, 120, Color(0.35, 1.0, 0.55)],
	["ПРОДУКТЫ", Vector3(-40, 3.3, 14.05), 0.0, 120, Color(1.0, 0.35, 0.3)],
	["ПРОДУКТЫ 24", Vector3(56.05, 3.3, -20), PI * 0.5, 110, Color(1.0, 0.8, 0.35)],
	["ГАСТРОНОМ", Vector3(81.95, 3.3, -10), -PI * 0.5, 110, Color(1.0, 0.8, 0.35)],
	["ШКЯ", Vector3(21.9, 1.6, 88), -PI * 0.5, 120, Color(0.12, 0.12, 0.14)],
	["ШИНОМОНТАЖ", Vector3(50.1, 2.4, -95), PI * 0.5, 70, Color(0.95, 0.95, 0.9)],
]

func _ready() -> void:
	_build_ground()
	var solids := Layout.all_solids()
	for i in solids.size():
		_build_solid(i, solids[i])
	_build_canopy()
	_build_surfaces()
	_build_bounds()
	_build_signs()
	_build_kiosk_sign()
	_build_wires()
	_build_skyline()

func _exit_tree() -> void:
	Materials.clear_cache()

# --- коллизии + вид ---

func _build_ground() -> void:
	var b := Layout.BOUNDS
	var center := Vector3(b.position.x + b.size.x * 0.5, -0.5, b.position.y + b.size.y * 0.5)
	var ground := Greybox.solid_box("Ground", center, Vector3(b.size.x, 1.0, b.size.y), Greybox.COLORS["ground"])
	(ground.get_child(1) as MeshInstance3D).material_override = Materials.snow(0.0)
	add_child(ground)

func _build_solid(index: int, spec: Array) -> void:
	var kind: String = spec[1]
	var xz: Vector2 = spec[2]
	var size: Vector3 = spec[3]
	var body := Greybox.solid_box(spec[0] if index < Layout.SOLIDS.size() else "%s_%d" % [spec[0], index], Vector3(xz.x, size.y * 0.5, xz.y), size, Greybox.COLORS.get(kind, Color.GRAY))
	var mesh := body.get_child(1) as MeshInstance3D
	match kind:
		"panel", "panel_low":
			mesh.material_override = Materials.facade(float(index), kind == "panel_low", spec[0] in SHOP_FRONTS)
		"garage":
			mesh.queue_free()
			_garage_row(body, spec[0], size)
		"snow", "snow_bank":
			mesh.queue_free()
			body.add_child(_lumpy_bank(size, Materials.snow(0.0 if kind == "snow" else 0.3), index))
		"prop":
			mesh.material_override = Materials.snow(0.1) if spec[0] == "Playground" else Materials.plain(Color(0.35, 0.25, 0.18))
			if spec[0] == "Bench":
				body.add_child(_slab(size, Vector3(0, size.y * 0.5 + 0.03, 0)))
		"parked_car":
			mesh.queue_free()
			body.add_child(_zhiguli(size, CAR_COLORS[index % CAR_COLORS.size()]))
		"kiosk":
			mesh.queue_free()
			body.add_child(_kiosk(size))
		"lamp":
			mesh.material_override = Materials.plain(Color(0.12, 0.12, 0.13), 0.6)
			body.add_child(_lamp_head(size.y))
		"tree":
			mesh.queue_free()
			body.add_child(_birch(size.y, float(index)))
		"sign_post":
			mesh.material_override = Materials.plain(Color(0.15, 0.15, 0.16), 0.6)
			body.add_child(_street_sign(size.y))
		"fence":
			mesh.material_override = Materials.plain(Color(0.16, 0.24, 0.18), 0.7)
	add_child(body)

func _build_canopy() -> void:
	var canopy := Greybox.solid_box("Canopy", Layout.CANOPY[0], Layout.CANOPY[1], Greybox.COLORS["canopy"])
	canopy.add_child(_slab(Layout.CANOPY[1], Vector3(0, Layout.CANOPY[1].y * 0.5 + 0.04, 0)))
	add_child(canopy)

func _build_surfaces() -> void:
	var lift := {"yard_road": 0.01, "sidewalk": 0.015, "road": 0.02}
	for spec in Layout.SURFACES:
		var xz: Vector2 = spec[2]
		var size: Vector2 = spec[3]
		var mesh := Greybox.mesh_box(Vector3(size.x, 0.01, size.y), Greybox.COLORS[spec[1]])
		mesh.name = spec[0]
		mesh.position = Vector3(xz.x, lift[spec[1]], xz.y)
		match spec[1]:
			"road":
				mesh.material_override = Materials.road(size.x > size.y, xz, minf(size.x, size.y))
			"sidewalk":
				mesh.material_override = Materials.snow(0.7)
			"yard_road":
				mesh.material_override = Materials.snow(0.9)
		add_child(mesh)

func _build_bounds() -> void:
	var b := Layout.BOUNDS
	var cx := b.position.x + b.size.x * 0.5
	var cz := b.position.y + b.size.y * 0.5
	var h := WALL_HEIGHT * 0.5
	var t := WALL_THICKNESS
	var walls := [
		["Bound_West", Vector3(b.position.x - t * 0.5, h, cz), Vector3(t, WALL_HEIGHT, b.size.y)],
		["Bound_East", Vector3(b.end.x + t * 0.5, h, cz), Vector3(t, WALL_HEIGHT, b.size.y)],
		["Bound_North", Vector3(cx, h, b.position.y - t * 0.5), Vector3(b.size.x, WALL_HEIGHT, t)],
		["Bound_South", Vector3(cx, h, b.end.y + t * 0.5), Vector3(b.size.x, WALL_HEIGHT, t)],
	]
	for spec in walls:
		var body := Greybox.solid_box(spec[0], spec[1], spec[2], Color.BLACK)
		body.get_child(1).queue_free()  # стена невидима
		add_child(body)

# --- детали ---

## Вал снега из перекрывающихся комков разной высоты, чтобы не было гладкой «трубы».
func _lumpy_bank(size: Vector3, material: Material, seed: int) -> Node3D:
	var root := Node3D.new()
	var long_x := size.x >= size.z
	var length := size.x if long_x else size.z
	var count := maxi(1, int(ceil(length / 2.2)))
	var step := length / count
	for i in count:
		var h := 0.75 + 0.5 * fposmod(sin(float(seed * 31 + i) * 12.9898) * 43758.5453, 1.0)
		var lump_size := Vector3(step * 1.6, size.y * h, size.z * (0.85 + 0.3 * h)) if long_x else Vector3(size.x * (0.85 + 0.3 * h), size.y * h, step * 1.6)
		var lump := _mound(lump_size, material)
		var offset := -length * 0.5 + step * (i + 0.5)
		lump.position += Vector3(offset, -size.y * 0.5 + lump_size.y * 0.5, 0) if long_x else Vector3(0, -size.y * 0.5 + lump_size.y * 0.5, offset)
		root.add_child(lump)
	return root

## Округлый сугроб, вписанный в коллизионную коробку (центр коробки — начало координат).
func _mound(size: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 10
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.scale = Vector3(size.x * 1.05, size.y * 2.0, size.z * 1.05)
	mesh.position.y = -size.y * 0.5
	return mesh

## Снежная шапка толщиной 8 см.
func _slab(size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := Greybox.mesh_box(Vector3(size.x + 0.08, 0.08, size.z + 0.08), Color.WHITE)
	mesh.material_override = Materials.snow(0.0)
	mesh.position = at
	return mesh

func _garage_row(body: Node3D, name: String, size: Vector3) -> void:
	var long_z := size.z > size.x
	var length := size.z if long_z else size.x
	var count := maxi(1, int(round(length / 3.6)))
	var unit := length / count
	var side: float = GARAGE_DOOR_SIDE.get(name, 1.0)
	for i in count:
		var offset := -length * 0.5 + unit * (i + 0.5)
		var color: Color = GARAGE_COLORS[(i * 7 + name.length()) % GARAGE_COLORS.size()]
		var box := Greybox.mesh_box(Vector3(size.x, size.y, unit - 0.12) if long_z else Vector3(unit - 0.12, size.y, size.z), color)
		box.material_override = Materials.plain(color, 0.7)
		box.position = Vector3(0, 0, offset) if long_z else Vector3(offset, 0, 0)
		body.add_child(box)
		var door := Greybox.mesh_box(Vector3(0.05, size.y * 0.75, unit * 0.8), color.darkened(0.35))
		door.material_override = Materials.plain(color.darkened(0.35), 0.5)
		door.position = Vector3(side * (size.x * 0.5 + 0.02), -size.y * 0.1, offset)
		if long_z:
			body.add_child(door)
	body.add_child(_slab(size, Vector3(0, size.y * 0.5 + 0.04, 0)))

func _zhiguli(size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var long_x := size.x > size.z
	var length := size.x if long_x else size.z
	var width := size.z if long_x else size.x
	var visual := Node3D.new()
	if long_x:
		visual.rotation.y = PI * 0.5
	root.add_child(visual)
	var lower := Greybox.mesh_box(Vector3(width, 0.7, length), color)
	lower.material_override = Materials.plain(color, 0.35)
	lower.position.y = -size.y * 0.5 + 0.55
	visual.add_child(lower)
	var cabin := Greybox.mesh_box(Vector3(width * 0.9, 0.5, length * 0.48), color)
	cabin.material_override = Materials.plain(color.darkened(0.1), 0.35)
	cabin.position = Vector3(0, -size.y * 0.5 + 1.15, 0.2)
	visual.add_child(cabin)
	var snow_top := Greybox.mesh_box(Vector3(width * 0.88, 0.1, length * 0.46), Color.WHITE)
	snow_top.material_override = Materials.snow(0.0)
	snow_top.position = Vector3(0, -size.y * 0.5 + 1.45, 0.2)
	visual.add_child(snow_top)
	var tyre := Materials.plain(Color(0.06, 0.06, 0.06), 0.9)
	for wx in [-width * 0.47, width * 0.47]:
		for wz in [-length * 0.32, length * 0.32]:
			var wheel := Greybox.mesh_cylinder(0.3, 0.3, 0.2, Color.BLACK)
			wheel.material_override = tyre
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(wx, -size.y * 0.5 + 0.3, wz)
			visual.add_child(wheel)
	return root

func _kiosk(size: Vector3) -> Node3D:
	# Пустая будка: окно на восток (к улице), внутри тёплый свет и продавщица.
	var root := Node3D.new()
	var green := Materials.plain(Color(0.22, 0.38, 0.28), 0.7)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var t := 0.1
	var parts := [
		[Vector3(t, size.y, size.z), Vector3(-hx + t * 0.5, 0, 0)],             # задняя стена
		[Vector3(size.x, size.y, t), Vector3(0, 0, -hz + t * 0.5)],             # северная
		[Vector3(size.x, size.y, t), Vector3(0, 0, hz - t * 0.5)],              # южная
		[Vector3(t, 1.0, size.z), Vector3(hx - t * 0.5, -hy + 0.5, 0)],         # прилавок под окном
		[Vector3(t, 0.7, size.z), Vector3(hx - t * 0.5, hy - 0.35, 0)],         # над окном
		[Vector3(size.x + 0.6, 0.12, size.z + 0.6), Vector3(0.3, hy + 0.06, 0)], # крыша с козырьком
	]
	for part in parts:
		var mesh := Greybox.mesh_box(part[0], Color.WHITE)
		mesh.material_override = green
		mesh.position = part[1]
		root.add_child(mesh)
	var glass := Greybox.mesh_box(Vector3(0.02, size.y - 1.7, size.z - 0.2), Color.WHITE)
	glass.material_override = Materials.glass()
	glass.position = Vector3(hx - 0.02, -hy + 1.0 + (size.y - 1.7) * 0.5, 0)
	root.add_child(glass)
	var shelves := Greybox.mesh_box(Vector3(0.4, 1.4, size.z - 0.4), Color.WHITE)
	shelves.material_override = Materials.plain(Color(0.75, 0.55, 0.30), 0.8, WARM, 0.6)   # полки с батонами
	shelves.position = Vector3(-hx + 0.35, -hy + 1.5, 0)
	root.add_child(shelves)
	root.add_child(_slab(Vector3(size.x + 0.6, 0.12, size.z + 0.6), Vector3(0.3, hy + 0.16, 0)))
	var inside := OmniLight3D.new()
	inside.light_color = WARM
	inside.light_energy = 1.5
	inside.omni_range = 4.0
	inside.position = Vector3(0, hy - 0.5, 0)
	root.add_child(inside)
	return root

func _lamp_head(height: float) -> Node3D:
	var head := Greybox.mesh_box(Vector3(0.5, 0.18, 0.3), Color.WHITE)
	head.material_override = Materials.plain(Color(0.2, 0.2, 0.2), 0.5, WARM, 4.0)
	head.position = Vector3(0, height * 0.5 - 0.1, 0)
	return head

func _birch(height: float, seed: float) -> Node3D:
	var root := Node3D.new()
	var trunk := Greybox.mesh_cylinder(0.1, 0.16, height, Color.WHITE)
	trunk.material_override = Materials.plain(Color(0.85, 0.84, 0.80), 0.9)
	root.add_child(trunk)
	var bark := Materials.plain(Color(0.10, 0.09, 0.08), 0.9)
	for i in 6:
		var branch := Greybox.mesh_cylinder(0.02, 0.05, 2.2, Color.WHITE)
		branch.material_override = bark
		var angle := seed * 1.7 + i * 1.1
		branch.position = Vector3(cos(angle) * 0.6, height * (0.05 + i * 0.07), sin(angle) * 0.6)
		branch.rotation = Vector3(sin(angle) * 0.7, 0, -cos(angle) * 0.7)
		root.add_child(branch)
	return root

func _street_sign(height: float) -> Node3D:
	var root := Node3D.new()
	var plate := Greybox.mesh_box(Vector3(1.9, 0.5, 0.05), Color.WHITE)
	plate.material_override = Materials.plain(Color(0.10, 0.20, 0.42), 0.5)
	plate.position = Vector3(0, height * 0.5 - 0.3, 0)
	root.add_child(plate)
	for side in [1.0, -1.0]:
		var label := _label("УЛ. ЛЕНИНА", 64, Color(0.95, 0.95, 0.95))
		label.position = Vector3(0, height * 0.5 - 0.3, 0.035 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		root.add_child(label)
	return root

func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	return label

func _build_signs() -> void:
	for spec in SIGNS:
		var label := _label(spec[0], spec[3], spec[4])
		label.name = "Sign_%s" % spec[0]
		label.position = spec[1]
		label.rotation.y = spec[2]
		add_child(label)

func _build_kiosk_sign() -> void:
	var sign := Label3D.new()
	sign.name = "KioskSign"
	sign.text = "ХЛЕБ"
	sign.font_size = 160
	sign.pixel_size = 0.005
	sign.modulate = Color(1.0, 0.85, 0.25)
	sign.outline_size = 24
	sign.position = Layout.KIOSK + Vector3(2.62, 2.85, 0.0)
	sign.rotation.y = PI * 0.5  # смотрит на улицу, на восток
	add_child(sign)

## Троллейбусные провода над улицами A и B.
func _build_wires() -> void:
	var wire_material := Materials.plain(Color(0.05, 0.05, 0.05), 0.5)
	for z in [30.5, 33.5]:
		_wire(Vector3(-100, 7.5, z), Vector3(100, 7.5, z), wire_material)
	for x in [68.5, 71.5]:
		_wire(Vector3(x, 7.5, 25), Vector3(x, 7.5, -112), wire_material)

func _wire(from: Vector3, to: Vector3, material: Material) -> void:
	var mesh := Greybox.mesh_cylinder(0.02, 0.02, from.distance_to(to), Color.BLACK)
	mesh.material_override = material
	mesh.position = (from + to) * 0.5
	# Ось цилиндра (Y) — вдоль провода.
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.UP).normalized()
	mesh.basis = Basis(side, axis, side.cross(axis))
	add_child(mesh)

## Город за границей карты: только вид, без коллизий; башня «ГОСТИНИЦА» в конце улицы B.
func _build_skyline() -> void:
	var b := Layout.BOUNDS
	var index := 100
	for x in range(-120, 140, 32):
		for z in [b.position.y - 28.0, b.end.y + 28.0]:
			_backdrop(Vector3(x, 0, z), Vector3(26, 21.0 + (index % 3) * 6.0, 16), index)
			index += 1
	for z in range(-110, 130, 34):
		for x in [b.position.x - 26.0, b.end.x + 26.0]:
			_backdrop(Vector3(x, 0, z), Vector3(16, 21.0 + (index % 3) * 6.0, 26), index)
			index += 1
	var tower := Greybox.mesh_box(Vector3(26, 58, 22), Color.WHITE)
	tower.material_override = Materials.facade(7.0, true)
	tower.position = Vector3(70, 29, -205)
	tower.name = "Landmark"
	add_child(tower)
	var spire := Greybox.mesh_cylinder(0.0, 4.0, 18.0, Color.WHITE)
	spire.material_override = Materials.plain(Color(0.45, 0.42, 0.38), 0.6)
	spire.position = Vector3(70, 67, -205)
	add_child(spire)
	var hotel := _label("ГОСТИНИЦА", 260, Color(1.0, 0.92, 0.75))
	hotel.pixel_size = 0.02
	hotel.position = Vector3(70, 50, -193.9)
	add_child(hotel)

func _backdrop(at: Vector3, size: Vector3, seed: int) -> void:
	var mesh := Greybox.mesh_box(size, Color.WHITE)
	mesh.material_override = Materials.facade(float(seed), seed % 4 == 0)
	mesh.position = at + Vector3.UP * size.y * 0.5
	add_child(mesh)

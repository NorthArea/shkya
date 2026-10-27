extends Node3D
## LevelGeometry: земля, здания, сугробы и покрытия из Layout; невидимые стены по краю карты.

const Layout = preload("res://game/world/layout.gd")
const Greybox = preload("res://game/world/greybox.gd")

const WALL_HEIGHT := 12.0
const WALL_THICKNESS := 2.0

func _ready() -> void:
	_build_ground()
	for spec in Layout.SOLIDS:
		var xz: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		add_child(Greybox.solid_box(spec[0], Vector3(xz.x, size.y * 0.5, xz.y), size, Greybox.COLORS[spec[1]]))
	add_child(Greybox.solid_box("Canopy", Layout.CANOPY[0], Layout.CANOPY[1], Greybox.COLORS["canopy"]))
	_build_surfaces()
	_build_bounds()
	_build_kiosk_sign()

func _build_ground() -> void:
	var b := Layout.BOUNDS
	var center := Vector3(b.position.x + b.size.x * 0.5, -0.5, b.position.y + b.size.y * 0.5)
	add_child(Greybox.solid_box("Ground", center, Vector3(b.size.x, 1.0, b.size.y), Greybox.COLORS["ground"]))

func _build_surfaces() -> void:
	# Покрытия чуть приподняты над землёй и друг над другом, чтобы не мерцали.
	var lift := {"yard_road": 0.01, "sidewalk": 0.015, "road": 0.02}
	for spec in Layout.SURFACES:
		var xz: Vector2 = spec[2]
		var size: Vector2 = spec[3]
		var mesh := Greybox.mesh_box(Vector3(size.x, 0.01, size.y), Greybox.COLORS[spec[1]])
		mesh.name = spec[0]
		mesh.position = Vector3(xz.x, lift[spec[1]], xz.y)
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

func _build_kiosk_sign() -> void:
	var sign := Label3D.new()
	sign.name = "KioskSign"
	sign.text = "ХЛЕБ"
	sign.font_size = 160
	sign.pixel_size = 0.005
	sign.modulate = Color(1.0, 0.85, 0.25)
	sign.outline_size = 24
	sign.position = Layout.KIOSK + Vector3(2.55, 2.7, 0.0)
	sign.rotation.y = PI * 0.5  # смотрит на улицу, на восток
	add_child(sign)

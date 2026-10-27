extends Control
## Круглая мини-карта (QUEST-01): север сверху, карта по Layout (C1), белая стрелка — взгляд камеры,
## жёлтый ромб — цель (на краю круга, если цель за пределами). Только рисует то, что ей передали.

const Layout = preload("res://game/world/layout.gd")

const RADIUS := 130.0
const SCALE := 1.25  # пикселей на метр

const COL_GROUND := Color(0.36, 0.37, 0.38)
const COL_ROAD := Color(0.66, 0.67, 0.68)
const COL_WALK := Color(0.50, 0.51, 0.52)
const COL_SOLID := Color(0.18, 0.19, 0.20)
const COL_LOW := Color(0.26, 0.27, 0.28)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)

var center_world := Vector2.ZERO  # x, z центра карты (игрок или машина)
var yaw := 0.0
var has_target := false
var target_world := Vector2.ZERO
## Положение ромба относительно центра круга (экранные пиксели карты); для проверок.
var target_marker := Vector2.ZERO
var target_on_edge := false

var _disc: PackedVector2Array
var _n_label: Label

func _ready() -> void:
	name = "Minimap"
	custom_minimum_size = Vector2(RADIUS * 2.0 + 8.0, RADIUS * 2.0 + 8.0)
	size = custom_minimum_size
	_disc = _circle_polygon(RADIUS, 48)
	_n_label = Label.new()
	_n_label.text = "N"
	_n_label.add_theme_font_size_override("font_size", 26)
	_n_label.add_theme_color_override("font_color", INK)
	_n_label.add_theme_color_override("font_outline_color", Color(0.93, 0.87, 0.72))
	_n_label.add_theme_constant_override("outline_size", 8)
	_n_label.position = Vector2(size.x * 0.5 - 9.0, -8.0)
	add_child(_n_label)

func set_view(new_center: Vector2, new_yaw: float, target: Variant) -> void:
	center_world = new_center
	yaw = new_yaw
	has_target = target is Vector3 and target != Vector3.INF
	if has_target:
		target_world = Vector2(target.x, target.z)
		var offset := (target_world - center_world) * SCALE
		target_on_edge = offset.length() > RADIUS - 14.0
		target_marker = offset.limit_length(RADIUS - 14.0)
	else:
		target_on_edge = false
		target_marker = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var mid := size * 0.5
	draw_colored_polygon(_translate(_disc, mid), COL_GROUND)
	for spec in Layout.SURFACES:
		var color := COL_ROAD if spec[1] == "road" or spec[1] == "yard_road" else COL_WALK
		_draw_box(spec[2], spec[3], color, mid)
	for spec in Layout.SOLIDS:
		var kind: String = spec[1]
		if kind == "lamp" or kind == "snow" or kind == "prop" or kind == "fence":
			continue
		var size_xz := Vector2(spec[3].x, spec[3].z)
		_draw_box(spec[2], size_xz, COL_LOW if kind == "panel_low" or kind == "garage" else COL_SOLID, mid)
	_draw_arrow(mid)
	if has_target:
		_draw_diamond(mid + target_marker, 12.0)
	draw_polyline(_close(_translate(_disc, mid)), INK, 4.0, true)

func _draw_box(center_xz: Vector2, size_xz: Vector2, color: Color, mid: Vector2) -> void:
	var half := size_xz * 0.5
	var corners := PackedVector2Array()
	for sign in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(mid + (center_xz + half * sign - center_world) * SCALE)
	for piece in Geometry2D.intersect_polygons(corners, _translate(_disc, mid)):
		if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
			draw_colored_polygon(piece, color)

func _draw_diamond(at: Vector2, r: float) -> void:
	var points := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	draw_colored_polygon(points, YELLOW)
	draw_polyline(_close(points), INK, 2.5)

func _draw_arrow(at: Vector2) -> void:
	# yaw 0 — на север (вверх по карте); поворот камеры влево (+yaw) разворачивает стрелку влево.
	var points := PackedVector2Array([Vector2(0, -15), Vector2(11, 12), Vector2(0, 6), Vector2(-11, 12)])
	var rotated := PackedVector2Array()
	for p in points:
		rotated.append(at + p.rotated(-yaw))
	draw_colored_polygon(rotated, Color(0.97, 0.97, 0.97))
	draw_polyline(_close(rotated), INK, 2.0)

func _translate(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out

func _close(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out

func _circle_polygon(radius: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out

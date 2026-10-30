extends Node3D
## Краска только на существующих переходах Life. Подходы, снег и физика остаются прежними.

const Layout = preload("res://game/world/layout.gd")
const RoadSurface = preload("res://game/world/road_surface.gd")
const SnowField = preload("res://game/world/snow_field.gd")
const Materials = preload("res://game/world/materials.gd")

const WIDTH := 2.4
const STRIPE_LENGTH := 0.55
const STRIPE_STEP := 1.10
const CURB_INSET := 0.18
const PAINT_LIFT := 0.002
const APPROACH_WIDTH := 1.1
const APPROACH_STEP := 0.18

var _crossings: Array[Dictionary] = []

func _ready() -> void:
	name = "Crosswalks"
	for edge in Layout.LIFE_EDGES:
		if edge.size() > 2 and edge[2] == &"cross":
			_plan(edge)
	var stripes: Array[Transform3D] = []
	for crossing in _crossings:
		stripes.append_array(crossing.stripes)
		_approach(crossing.from, crossing.road_from)
		_approach(crossing.to, crossing.road_to)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	# Существующая дорога передаёт и колеи кольца, и мокрые пятна. Её шейдер сохраняет их нормали под краской.
	var road: MeshInstance3D = get_parent().get_node("RoadSurface")
	var paint := road.material_override.duplicate() as ShaderMaterial
	paint.set_shader_parameter("crosswalk_paint", true)
	plane.material = paint
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = plane
	batch.instance_count = stripes.size()
	for i in stripes.size():
		batch.set_instance_transform(i, stripes[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Stripes"
	instance.multimesh = batch
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(instance)

func crossings() -> Array[Dictionary]:
	return _crossings

func _approach(from: Vector3, curb: Vector3) -> void:
	var direction := (curb - from).normalized()
	var across := Vector3(direction.z, 0, -direction.x)
	# Не заходим на проезжую часть: там видны краска и собственная колея дороги.
	var length := maxf(0.0, from.distance_to(curb) - 0.04)
	if length <= 0.0:
		return
	var along_steps := maxi(1, ceili(length / APPROACH_STEP))
	var side_steps := ceili(APPROACH_WIDTH / APPROACH_STEP)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in along_steps:
		for column in side_steps:
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]:
				var uv := Vector2(float(column + corner.x) / side_steps, float(row + corner.y) / along_steps)
				var point := from + direction * (uv.y * length) + across * ((uv.x - 0.5) * APPROACH_WIDTH)
				point.y = maxf(0.02, SnowField.height_at(point.x, point.z)) + 0.004
				surface.set_uv(uv)
				surface.set_normal(SnowField.normal_at(point.x, point.z))
				surface.add_vertex(point)
	var mesh := MeshInstance3D.new()
	mesh.name = "Approach"
	mesh.mesh = surface.commit()
	mesh.material_override = Materials.trail(APPROACH_WIDTH, length)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _plan(edge: Array) -> void:
	var a: Vector2 = Layout.LIFE_NODES[edge[0]]
	var b: Vector2 = Layout.LIFE_NODES[edge[1]]
	# Выбираем фактическую проезжую часть поперёк маршрута, а не всю связь от тротуара до тротуара.
	for surface in Layout.SURFACES:
		if surface[1] != "road":
			continue
		var rect := Rect2(surface[2] - surface[3] * 0.5, surface[3])
		var clipped := _clip(a, b, rect)
		if clipped.is_empty():
			continue
		var road_from := Vector3(clipped[0].x, 0, clipped[0].y)
		var road_to := Vector3(clipped[1].x, 0, clipped[1].y)
		var direction := (road_to - road_from).normalized()
		var across := Vector3(direction.z, 0, -direction.x)
		var length := road_from.distance_to(road_to) - CURB_INSET * 2.0
		var count := floori((length - STRIPE_LENGTH) / STRIPE_STEP) + 1
		var used := (count - 1) * STRIPE_STEP + STRIPE_LENGTH
		var start := road_from + direction * ((road_from.distance_to(road_to) - used) * 0.5 + STRIPE_LENGTH * 0.5)
		var stripes: Array[Transform3D] = []
		for i in count:
			var center := start + direction * (float(i) * STRIPE_STEP)
			center.y = RoadSurface.HEIGHT + PAINT_LIFT
			# Плоскость остаётся на асфальте: SnowField сам перекрывает краску у снежной кромки, нового вала нет.
			stripes.append(Transform3D(Basis(across * WIDTH, Vector3.UP, direction * STRIPE_LENGTH), center))
		_crossings.append({"edge": edge, "from": Vector3(a.x, 0, a.y), "to": Vector3(b.x, 0, b.y),
			"road_rect": rect, "road_from": road_from, "road_to": road_to, "width": WIDTH, "stripes": stripes})

## Пересечение отрезка с прямоугольником дорог Layout (две оси, без координат переходов в модуле).
static func _clip(a: Vector2, b: Vector2, rect: Rect2) -> Array[Vector2]:
	var low := 0.0
	var high := 1.0
	var delta := b - a
	for axis in 2:
		if is_zero_approx(delta[axis]):
			if a[axis] <= rect.position[axis] or a[axis] >= rect.end[axis]:
				return []
			continue
		var first := (rect.position[axis] - a[axis]) / delta[axis]
		var last := (rect.end[axis] - a[axis]) / delta[axis]
		low = maxf(low, minf(first, last))
		high = minf(high, maxf(first, last))
		if low >= high:
			return []
	return [a.lerp(b, low), a.lerp(b, high)]

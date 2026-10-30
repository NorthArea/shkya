extends RefCounted
## Общая непересекающаяся поверхность прежних дорог Layout; физику и маршруты не меняет.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const Vehicle = preload("res://game/vehicles/path_vehicle.gd")
const HEIGHT := 0.025

static func create() -> MeshInstance3D:
	var rectangles: Array[Rect2] = []
	var road_bounds := PackedVector4Array()
	var xs: Array[float] = []
	var zs: Array[float] = []
	for surface in Layout.SURFACES:
		if surface[1] != "road":
			continue
		var rect := Rect2(surface[2] - surface[3] * 0.5, surface[3])
		rectangles.append(rect)
		road_bounds.append(Vector4(rect.get_center().x, rect.get_center().y, rect.size.x * 0.5, rect.size.y * 0.5))
		for x: float in [rect.position.x, rect.end.x]:
			if not xs.has(x): xs.append(x)
		for z: float in [rect.position.y, rect.end.y]:
			if not zs.has(z): zs.append(z)
	xs.sort()
	zs.sort()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in xs.size() - 1:
		for iz in zs.size() - 1:
			var center := Vector2((xs[ix] + xs[ix + 1]) * 0.5, (zs[iz] + zs[iz + 1]) * 0.5)
			if not rectangles.any(func(rect: Rect2): return rect.has_point(center)):
				continue
			var corners := [Vector3(xs[ix], HEIGHT, zs[iz]), Vector3(xs[ix], HEIGHT, zs[iz + 1]),
				Vector3(xs[ix + 1], HEIGHT, zs[iz + 1]), Vector3(xs[ix + 1], HEIGHT, zs[iz])]
			for index: int in [0, 2, 1, 0, 3, 2]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(corners[index])
	var lanes := [Vehicle.LanePath.build(Layout.RING, Layout.RING_LANE, Vehicle.TURN_RADIUS),
		Vehicle.LanePath.build(Layout.CAR_RING, Layout.RING_LANE, Vehicle.CAR_TURN_RADIUS)]
	var lane_bounds := PackedVector4Array()
	for lane in lanes:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for point: Vector3 in lane.points:
			low = low.min(Vector2(point.x, point.z))
			high = high.max(Vector2(point.x, point.z))
		lane_bounds.append(Vector4((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, (high.x - low.x) * 0.5, (high.y - low.y) * 0.5))
	var mesh := MeshInstance3D.new()
	mesh.name = "RoadSurface"
	mesh.mesh = surface.commit()
	mesh.material_override = Materials.road_network(lane_bounds, Vector2(lanes[0].radius, lanes[1].radius), road_bounds)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

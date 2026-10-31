extends RefCounted
## Derived driving graph. Layout owns roads; this object owns a disposable route and learned closures.
const Layout = preload("res://game/world/layout.gd")
const ROAD_REACH := 8.0
const TURN_RADIUS := 6.0
const BLOCK_SECONDS := 6.0
var points := PackedVector3Array()
var cumulative := PackedFloat32Array()
var length := 0.0
var _nodes: Array[Vector3] = []
var _edges: Array[Dictionary] = []
var _blocks: Dictionary = {}
var _size := Vector3.ONE
var _solids: Array = []

func configure(_canonical_lane: RefCounted, vehicle_size: Vector3) -> void:
	_size = vehicle_size
	_nodes.clear()
	_edges.clear()
	_blocks.clear()
	_solids = Layout.all_solids()
	# Split the ring at its existing yard exit and kiosk parking access.
	var parking_exit := Vector3(Layout.RING[0].x, 0.0, Layout.ROUTE_LEAVE_KIOSK[-1].z)
	var junctions: Array[Vector3] = [Layout.ROUTE_DRIVE[3], Layout.ROUTE_DRIVE[5], parking_exit]
	for i in Layout.RING.size():
		var a: Vector3 = Layout.RING[i]
		var b: Vector3 = Layout.RING[(i + 1) % Layout.RING.size()]
		var cuts: Array[Vector3] = [a, b]
		for junction in junctions:
			if _project(junction, a, b).distance_to(junction) < 0.1:
				cuts.append(junction)
		cuts.sort_custom(func(x: Vector3, y: Vector3): return a.distance_squared_to(x) < a.distance_squared_to(y))
		for k in cuts.size() - 1:
			_add_edge(cuts[k], cuts[k + 1], Layout.RING_LANE)
	for i in 3:
		_add_edge(Layout.ROUTE_DRIVE[i], Layout.ROUTE_DRIVE[i + 1], 0.0)
	_add_edge(Layout.ROUTE_DRIVE[5], Layout.ROUTE_DRIVE[6], 0.0)
	_add_edge(Layout.ROUTE_DRIVE[6], Layout.ROUTE_LEAVE_KIOSK[0], 0.0)
	for i in Layout.ROUTE_LEAVE_KIOSK.size() - 1:
		_add_edge(Layout.ROUTE_LEAVE_KIOSK[i], Layout.ROUTE_LEAVE_KIOSK[i + 1], 0.0)
	_add_edge(Layout.ROUTE_LEAVE_KIOSK[-1], parking_exit, 0.0)

func tick(delta: float) -> void:
	for edge in _blocks.keys():
		_blocks[edge] -= delta
		if _blocks[edge] <= 0.0:
			_blocks.erase(edge)

func clear_blocks() -> void:
	_blocks.clear()

func block_edge_at(position: Vector3) -> void:
	var nearest := _nearest(position)
	if nearest[0] >= 0 and nearest[2] < ROAD_REACH:
		_blocks[nearest[0]] = BLOCK_SECONDS

func _node(position: Vector3) -> int:
	for i in _nodes.size():
		if _nodes[i].distance_squared_to(position) < 0.01:
			return i
	_nodes.append(position)
	return _nodes.size() - 1

func _add_edge(a: Vector3, b: Vector3, lane: float) -> void:
	if a.distance_to(b) < 0.1:
		return
	_edges.append({"a": _node(a), "b": _node(b), "lane": lane})

static func _project(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	return a + ab * clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)

func _nearest(position: Vector3) -> Array:
	var best := [-1, Vector3.ZERO, INF]
	for i in _edges.size():
		var edge := _edges[i]
		var p := _project(position, _nodes[edge.a], _nodes[edge.b])
		var distance := p.distance_to(position)
		if distance < best[2]:
			best = [i, p, distance]
	return best

func reachable(position: Vector3) -> bool:
	var nearest := _nearest(position)
	return nearest[0] >= 0 and nearest[2] <= ROAD_REACH and not _inside_solid(position)

func _inside_solid(position: Vector3) -> bool:
	for solid in _solids:
		var center: Vector2 = solid[2]
		var size: Vector3 = solid[3]
		if absf(position.x - center.x) < size.x * 0.5 and absf(position.z - center.y) < size.z * 0.5:
			return true
	return false

## Heading constrains the initial edge; traversals cannot reverse in the middle of a street.
func plan(from: Vector3, heading: Vector3, goal: Vector3) -> bool:
	points.clear()
	cumulative.clear()
	length = 0.0
	if not reachable(from) or not reachable(goal):
		return false
	var start := _nearest(from)
	var finish := _nearest(goal)
	var nodes: Array[Vector3] = _nodes.duplicate()
	var links: Array[Dictionary] = []
	var start_id := -1
	var goal_id := -1
	for i in nodes.size():
		if nodes[i].distance_to(start[1]) < 0.05:
			start_id = i
		if nodes[i].distance_to(finish[1]) < 0.05:
			goal_id = i
	if start_id < 0:
		start_id = nodes.size()
		nodes.append(start[1])
	if goal_id < 0:
		goal_id = nodes.size()
		nodes.append(finish[1])
	for i in _edges.size():
		if _blocks.has(i):
			continue
		var edge := _edges[i]
		links.append({"a": edge.a, "b": edge.b, "lane": edge.lane})
		if i == start[0]:
			links.append({"a": start_id, "b": edge.a, "lane": edge.lane})
			links.append({"a": start_id, "b": edge.b, "lane": edge.lane})
		if i == finish[0]:
			links.append({"a": edge.a, "b": goal_id, "lane": edge.lane})
			links.append({"a": edge.b, "b": goal_id, "lane": edge.lane})
		if i == start[0] and i == finish[0]:
			links.append({"a": start_id, "b": goal_id, "lane": edge.lane})
	var first := Vector2i(-1, start_id)
	var costs := {first: 0.0}
	var previous: Dictionary = {}
	var open: Array[Vector2i] = [first]
	var found := Vector2i(-2, -2)
	while not open.is_empty():
		var current := open[0]
		for candidate in open:
			if costs[candidate] < costs[current]:
				current = candidate
		open.erase(current)
		if current.y == goal_id:
			found = current
			break
		for link in links:
			var next := -1
			if link.a == current.y:
				next = link.b
			elif link.b == current.y:
				next = link.a
			if next < 0 or next == current.x or next == start_id:
				continue
			var direction := nodes[next] - nodes[current.y]
			if direction.length() < 0.05:
				continue
			var incoming := heading if current.x < 0 else nodes[current.y] - nodes[current.x]
			if incoming.normalized().dot(direction.normalized()) < -0.35:
				continue
			var state := Vector2i(current.y, next)
			var cost: float = costs[current] + direction.length()
			if not costs.has(state) or cost < costs[state]:
				costs[state] = cost
				previous[state] = [current, float(link.lane)]
				if not open.has(state):
					open.append(state)
	if found.x == -2:
		return false
	var centers: Array[Vector3] = [nodes[goal_id]]
	var lanes: Array[float] = []
	while found != first:
		var entry: Array = previous[found]
		lanes.push_front(entry[1])
		found = entry[0]
		centers.push_front(nodes[found.y])
	if lanes.is_empty():
		return false
	_build_curve(centers, lanes, from)
	return length > 0.1

static func right_of(direction: Vector3) -> Vector3:
	return Vector3(-direction.z, 0.0, direction.x)

func _build_curve(centers: Array[Vector3], lanes: Array[float], from: Vector3) -> void:
	var joined: Array[Vector3] = []
	for i in centers.size():
		var before := (centers[i] - centers[maxi(0, i - 1)]).normalized()
		var after := (centers[mini(i + 1, centers.size() - 1)] - centers[i]).normalized()
		if i == 0:
			joined.append(centers[i] + right_of(after) * lanes[0])
		elif i == centers.size() - 1:
			joined.append(centers[i] + right_of(before) * lanes[i - 1])
		else:
			var denom := 1.0 + before.dot(after)
			var offset := (right_of(before) * lanes[i - 1] + right_of(after) * lanes[i]) / maxf(denom, 0.5)
			joined.append(centers[i] + offset)
	points.append(from)
	# The initial lane convergence is continuous; a pose is never reset to a projected point.
	if joined[0].distance_to(from) > 0.05:
		points.append(joined[0])
	for i in range(1, joined.size() - 1):
		var incoming := (joined[i] - joined[i - 1]).normalized()
		var outgoing := (joined[i + 1] - joined[i]).normalized()
		var angle := incoming.angle_to(outgoing)
		if angle < 0.03:
			points.append(joined[i])
			continue
		var trim := minf(TURN_RADIUS * tan(angle * 0.5), minf(joined[i].distance_to(joined[i - 1]), joined[i + 1].distance_to(joined[i])) * 0.35)
		var a := joined[i] - incoming * trim
		var b := joined[i] + outgoing * trim
		var radius := trim / tan(angle * 0.5)
		var sign_turn := signf(incoming.cross(outgoing).y)
		var center := a - right_of(incoming) * radius * sign_turn
		var arm := a - center
		var sweep := arm.signed_angle_to(b - center, Vector3.UP)
		points.append(a)
		for k in range(1, 13):
			points.append(center + arm.rotated(Vector3.UP, sweep * k / 12.0))
	points.append(joined[-1])
	cumulative.resize(points.size())
	cumulative[0] = 0.0
	for i in range(1, points.size()):
		length += points[i].distance_to(points[i - 1])
		cumulative[i] = length

func _segment(at: float) -> int:
	for i in range(1, cumulative.size()):
		if cumulative[i] > at:
			return i - 1
	return maxi(0, points.size() - 2)

func position_at(at: float) -> Vector3:
	if points.size() < 2:
		return Vector3.ZERO
	var i := _segment(clampf(at, 0.0, length))
	var t := (clampf(at, 0.0, length) - cumulative[i]) / maxf(cumulative[i + 1] - cumulative[i], 0.0001)
	return points[i].lerp(points[i + 1], t)

func direction_at(at: float) -> Vector3:
	if points.size() < 2:
		return Vector3.FORWARD
	var i := _segment(clampf(at, 0.0, length))
	return (points[i + 1] - points[i]).normalized()

func offset_of(position: Vector3) -> float:
	var best := INF
	var at := 0.0
	for i in points.size() - 1:
		var p := _project(position, points[i], points[i + 1])
		var distance := p.distance_squared_to(position)
		if distance < best:
			best = distance
			at = cumulative[i] + points[i].distance_to(p)
	return at

func curvature_at(at: float) -> float:
	var distance := minf(2.0, minf(at, length - at))
	if distance < 0.1:
		return 0.0
	return direction_at(at - distance).angle_to(direction_at(at + distance)) / (2.0 * distance)

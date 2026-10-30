extends SceneTree
## Native data-only export. No world, renderer, physics bodies or editor import are created.
const Layout = preload("res://game/world/layout.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Usage: --script tools/export_arena_map.gd -- /absolute/path/arena.json")
		quit(2)
		return
	var data := {
		"schema": 1,
		"units": "meters",
		"axes": {"x": "east", "z": "south"},
		"bounds": {"x": Layout.BOUNDS.position.x, "z": Layout.BOUNDS.position.y,
			"width": Layout.BOUNDS.size.x, "height": Layout.BOUNDS.size.y},
		"surfaces": [], "solids": [], "breakables": [], "paths": [], "crossings": [],
		"landmarks": [], "doors": [], "sources": ["game/world/layout.gd", "game/world/ambient.gd",
			"game/world/props.gd", "game/world/level_geometry.gd"],
		"routes": {"car": _points(Layout.ROUTE_DRIVE), "walk": _points(Layout.ROUTE_WALK)},
	}
	var road_names := {"Street_A": Layout.STREET_SIGNS[0][1], "Street_B": Layout.STREET_SIGNS[0][2],
		"Street_C": Layout.STREET_SIGNS[2][1], "Street_D": Layout.STREET_SIGNS[1][2]}
	for spec in Layout.SURFACES:
		data.surfaces.append({"id": spec[0], "kind": spec[1], "center": _point(spec[2]),
			"size": _point(spec[3]), "label": road_names.get(spec[0], "")})
	for spec in Layout.all_solids():
		data.solids.append(_solid(spec[0], spec[1], spec[2], spec[3]))
	for spec in Layout.BREAKABLES:
		var item := _solid(String(spec[0]), String(spec[1]), spec[2], spec[3])
		item["yaw"] = spec[4]
		data.breakables.append(item)
	for edge in Layout.LIFE_EDGES:
		var item := {"from": _point(Layout.LIFE_NODES[edge[0]]), "to": _point(Layout.LIFE_NODES[edge[1]]),
			"kind": String(edge[2]) if edge.size() > 2 else ""}
		data.paths.append(item)
		if item.kind == "cross": data.crossings.append(item.duplicate())
	for spot in Layout.LIFE_SPOTS:
		if spot[1] == &"door": data.doors.append({"point": _point(spot[3]), "yaw": spot[4]})
	_landmark(data, "start", "Старт • Илюша", Layout.SPAWN, "start")
	_landmark(data, "babka", "Бабка • подъезд", Layout.BABKA, "home")
	_landmark(data, "car", "«Лада»", Layout.CAR_SPAWN, "car")
	_landmark(data, "bread", "Киоск «ХЛЕБ»", Layout.KIOSK, "bread")
	_landmark(data, "officer", "Пост у киоска", Layout.OFFICER_POST, "post")
	_landmark(data, "guard", "Второй пост", Layout.OFFICER2_POST, "post")
	_landmark(data, "stop_a", "Остановка • троллейбус 13", Layout.TROLLEY_STOPS[0], "stop")
	_landmark(data, "stop_b", "Остановка • троллейбус 13", Layout.TROLLEY_STOPS[1], "stop")
	for spec in Layout.PROPS_SOLIDS:
		var labels := {"PropShawarma": "ШАУРМА", "PropPress": "ПРЕССА", "PropDovecote": "Голубятня",
			"PropShells": "Гаражи-«ракушки»", "PropIceSlide": "Ледяная горка"}
		if labels.has(spec[0]): _landmark(data, spec[0], labels[spec[0]], spec[2], "place")
	_landmark(data, "rink", "Хоккейная коробка", Layout.RINK[0], "place")
	_landmark(data, "shop24", "ПРОДУКТЫ 24", Layout.SHOP24[0], "shop")
	for spec in Layout.BREAKABLES:
		if spec[0] == &"Z7_dig": _landmark(data, "dig", "Раскопка", spec[2], "works")
	# These established sources own the dog and the actual storefront signs; no coordinates are copied.
	var ambient: Script = load("res://game/world/ambient.gd")
	var props: Script = load("res://game/world/props.gd")
	var geometry: Script = load("res://game/world/level_geometry.gd")
	_landmark(data, "dog", "Собака у гаражей", ambient.get_script_constant_map()["DOG_LOOP"][0], "dog")
	data["dog_house"] = _point(props.get_script_constant_map()["DOG_HOUSE"])
	for sign in geometry.get_script_constant_map()["SIGNS"]:
		if sign[0] in ["АПТЕКА", "ПРОДУКТЫ", "ГАСТРОНОМ", "ШИНОМОНТАЖ"]:
			_landmark(data, String(sign[0]), sign[0], sign[1], "shop")
	data["coverage"] = {"solids": data.solids.size(), "surfaces": data.surfaces.size(),
		"snow_banks": Layout.snow_banks().size(), "crossings": data.crossings.size(),
		"pedestrian_edges": data.paths.size(), "pedestrian_nodes": Layout.LIFE_NODES.size(),
		"resident_start_routes": Layout.RESIDENT_ROUTES.size()}
	var output := args[0]
	var error := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if error != OK:
		push_error("MAP01 cannot create export directory: " + error_string(error))
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("MAP01 cannot open export: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(data, "\t", true, true) + "\n")
	file.close()
	print("MAP01_EXPORT: ", data.coverage)
	quit(0)

func _solid(id: String, kind: String, center: Vector2, size: Vector3) -> Dictionary:
	return {"id": id, "kind": kind, "center": _point(center), "size": [size.x, size.y, size.z]}

func _point(value: Variant) -> Array:
	return [value.x, value.z] if value is Vector3 else [value.x, value.y]

func _points(values: Array) -> Array:
	var output := []
	for value in values: output.append(_point(value))
	return output

func _landmark(data: Dictionary, id: String, label: String, point: Variant, kind: String) -> void:
	data.landmarks.append({"id": id, "label": label, "point": _point(point), "kind": kind})

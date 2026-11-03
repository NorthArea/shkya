extends Node
## Resolution limits the 3D render target; the OS display and 2D canvas stay native.

signal changed

const DEFAULT_WIDTH := 1920
const RENDER_WIDTHS: Array[int] = [2560, 1920, 1600, 1280, 960]
const MIN_SCALE := 0.25
const FPS_LIMITS: Array[int] = [0, 60, 80, 100, 120, 140, 160, 180, 200]
const EFFECT_PROPERTIES := {
	"ssao": "ssao_enabled", "ssil": "ssil_enabled",
	"ssr": "ssr_enabled", "fog": "volumetric_fog_enabled",
}
const DEFAULT_GRAPHICS := {
	"vsync": false, "fps_limit": 120, "shadows": true,
	"ssao": true, "ssil": true, "ssr": true, "fog": true,
}

@export var config_path: String = "user://display.cfg"
var render_width: int = DEFAULT_WIDTH
var graphics: Dictionary = DEFAULT_GRAPHICS.duplicate()
var _window: Window
var _world_nodes: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"display_settings")
	_window = get_tree().root
	_load_preference()
	_window.size_changed.connect(_apply_resolution)
	_apply_resolution()
	_apply_frame_pacing()
	get_tree().node_added.connect(_on_node_added)
	_register_branch(get_tree().root)

func _register_branch(node: Node) -> void:
	_register_world_node(node)
	for child in node.get_children():
		_register_branch(child)

func _on_node_added(node: Node) -> void:
	if not (node is Light3D or node is WorldEnvironment):
		return
	# Construction code sets authored flags/resources after add_child().
	_register_world_node.call_deferred(weakref(node))

func _register_world_node(value: Variant) -> void:
	var node: Node = value.get_ref() if value is WeakRef else value
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if not (node is Light3D or node is WorldEnvironment):
		return
	var id := node.get_instance_id()
	if not _world_nodes.has(id):
		var record := {"node": weakref(node)}
		if node is Light3D:
			record["shadow"] = node.shadow_enabled
		elif node.environment != null:
			record["environment"] = node.environment
			for key: String in EFFECT_PROPERTIES:
				record[key] = node.environment.get(EFFECT_PROPERTIES[key])
		_world_nodes[id] = record
		# No stale resource or light references survive scene changes.
		node.tree_exiting.connect(func(): _world_nodes.erase(id), CONNECT_ONE_SHOT)
	_apply_world_record(_world_nodes[id])

func _apply_world_record(record: Dictionary) -> void:
	var node: Node = record.node.get_ref()
	if not is_instance_valid(node):
		return
	if node is Light3D:
		node.shadow_enabled = record.shadow and graphics.shadows
	elif record.has("environment"):
		var environment: Environment = record.environment
		for key: String in EFFECT_PROPERTIES:
			environment.set(EFFECT_PROPERTIES[key], record[key] and graphics[key])

func set_graphics_option(key: String, value: Variant) -> Error:
	if not DEFAULT_GRAPHICS.has(key):
		return ERR_INVALID_PARAMETER
	if key == "fps_limit":
		if typeof(value) != TYPE_INT or not FPS_LIMITS.has(value):
			return ERR_INVALID_PARAMETER
	elif typeof(value) != TYPE_BOOL:
		return ERR_INVALID_PARAMETER
	var next := graphics.duplicate()
	next[key] = value
	var error := _save_preferences(render_width, next)
	if error != OK:
		return error
	graphics = next
	_apply_frame_pacing()
	for record: Dictionary in _world_nodes.values():
		_apply_world_record(record)
	changed.emit()
	return OK

func _apply_frame_pacing() -> void:
	Engine.max_fps = graphics.fps_limit
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if graphics.vsync else DisplayServer.VSYNC_DISABLED, _window.get_window_id())

func _save_preferences(width: int, options: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "render_width", width)
	for key: String in options:
		config.set_value("graphics", key, options[key])
	return config.save(config_path)

func available_resolutions() -> Array[Dictionary]:
	var size := _window.size
	var options: Array[Dictionary] = [{
		"width": 0,
		"size": size,
		"label": "Родное (%d × %d)" % [size.x, size.y],
	}]
	for width: int in RENDER_WIDTHS:
		if width >= size.x or float(width) / maxi(size.x, 1) < MIN_SCALE:
			continue
		var height := roundi(float(size.y) * width / maxi(size.x, 1))
		options.append({
			"width": width,
			"size": Vector2i(width, height),
			"label": "%d × %d" % [width, height],
		})
	return options

func selected_option_width() -> int:
	return 0 if render_width == 0 or render_width >= _window.size.x else render_width

func set_resolution_width(width: int) -> Error:
	var allowed := false
	for option: Dictionary in available_resolutions():
		if option.width == width:
			allowed = true
			break
	if not allowed:
		return ERR_INVALID_PARAMETER
	var error := _save_preferences(width, graphics)
	if error != OK:
		return error
	render_width = width
	_apply_resolution()
	return OK

func _load_preference() -> void:
	render_width = DEFAULT_WIDTH
	graphics = DEFAULT_GRAPHICS.duplicate()
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	var saved: Variant = config.get_value("display", "render_width", DEFAULT_WIDTH)
	if typeof(saved) == TYPE_INT and (saved == 0 or RENDER_WIDTHS.has(saved)):
		render_width = saved
	for key: String in DEFAULT_GRAPHICS:
		var value: Variant = config.get_value("graphics", key, DEFAULT_GRAPHICS[key])
		if key == "fps_limit":
			if typeof(value) == TYPE_INT and FPS_LIMITS.has(value):
				graphics[key] = value
		elif typeof(value) == TYPE_BOOL:
			graphics[key] = value

func _apply_resolution() -> void:
	var scale := 1.0 if render_width == 0 else float(render_width) / maxi(_window.size.x, 1)
	_window.scaling_3d_scale = clampf(scale, MIN_SCALE, 1.0)
	changed.emit()

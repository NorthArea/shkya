extends Node
## Resolution limits the 3D render target; the OS display and 2D canvas stay native.

signal changed

const DEFAULT_WIDTH := 1920
const RENDER_WIDTHS: Array[int] = [2560, 1920, 1600, 1280, 960]
const MIN_SCALE := 0.25

@export var config_path: String = "user://display.cfg"
var render_width: int = DEFAULT_WIDTH
var _window: Window

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"display_settings")
	_window = get_tree().root
	_load_preference()
	_window.size_changed.connect(_apply_resolution)
	_apply_resolution()

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
	var config := ConfigFile.new()
	config.set_value("display", "render_width", width)
	var error := config.save(config_path)
	if error != OK:
		return error
	render_width = width
	_apply_resolution()
	return OK

func _load_preference() -> void:
	render_width = DEFAULT_WIDTH
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	var saved: Variant = config.get_value("display", "render_width", DEFAULT_WIDTH)
	if typeof(saved) == TYPE_INT and (saved == 0 or RENDER_WIDTHS.has(saved)):
		render_width = saved

func _apply_resolution() -> void:
	var scale := 1.0 if render_width == 0 else float(render_width) / maxi(_window.size.x, 1)
	_window.scaling_3d_scale = clampf(scale, MIN_SCALE, 1.0)
	changed.emit()

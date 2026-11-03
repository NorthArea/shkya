extends VBoxContainer

const LABELS := {&"master": "Общий звук", &"music": "Музыка", &"effects": "Эффекты"}
const INK := Color(0.12, 0.10, 0.08)
var sliders: Dictionary = {}
var _percentages: Dictionary = {}
var _controller: Node
var _error: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "AudioSettings"
	add_theme_constant_override("separation", 10)
	var heading := _label("ЗВУК", 26)
	add_child(heading)
	_controller = get_tree().get_first_node_in_group(&"audio_settings")
	for channel: StringName in LABELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		add_child(row)
		var label := _label(LABELS[channel], 22)
		label.custom_minimum_size.x = 180
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = String(channel).capitalize() + "Volume"
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		slider.custom_minimum_size = Vector2(180, 36)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_ALL
		slider.editable = _controller != null
		slider.tooltip_text = LABELS[channel] + ": ← / →"
		row.add_child(slider)
		sliders[channel] = slider
		var percentage := _label("100%", 22)
		percentage.custom_minimum_size.x = 64
		percentage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(percentage)
		_percentages[channel] = percentage
		slider.value_changed.connect(_set_volume.bind(channel))
	_error = _label("", 18)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.visible = false
	add_child(_error)
	if _controller:
		_controller.changed.connect(_refresh)
	_refresh()

func _set_volume(value: float, channel: StringName) -> void:
	if _controller == null:
		return
	var result: Error = _controller.set_volume(channel, value / 100.0)
	_error.visible = result != OK
	_error.text = "Не удалось сохранить звук: " + error_string(result) if result != OK else ""
	_refresh()

func _refresh() -> void:
	for channel: StringName in sliders:
		var value: float = _controller.get_volume(channel) * 100.0 if _controller else 100.0
		sliders[channel].set_value_no_signal(value)
		_percentages[channel].text = "%d%%" % roundi(value)

func get_focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for slider: HSlider in sliders.values():
		controls.append(slider)
	return controls

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	return label

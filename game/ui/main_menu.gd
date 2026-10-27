extends CanvasLayer
## Главное меню: НАЧАТЬ / ВЫХОД.

signal start_requested
signal quit_requested

var start_button: Button

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.color = Color(0.12, 0.13, 0.16)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = "ШКЯ: НОВОСИБИРСК"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "За хлебом"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 40)
	box.add_child(subtitle)
	start_button = _button("НАЧАТЬ", start_requested.emit)
	box.add_child(start_button)
	box.add_child(_button("ВЫХОД", quit_requested.emit))
	add_child(box)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()

func _on_visibility_changed() -> void:
	if visible and is_inside_tree():
		start_button.grab_focus.call_deferred()

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 72)
	button.add_theme_font_size_override("font_size", 36)
	button.pressed.connect(action)
	return button

extends CanvasLayer
## Меню паузы: ПРОДОЛЖИТЬ / НАЧАТЬ ЗАНОВО / В ГЛАВНОЕ МЕНЮ.
## Кнопку «СБРОСИТЬ АВТОМОБИЛЬ» добавляет DRIVE-01 через add_action().

signal resume_requested
signal restart_requested
signal menu_requested

var box: VBoxContainer

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	box = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 20)
	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	add_child(box)
	add_action("ПРОДОЛЖИТЬ", resume_requested.emit)
	add_action("НАЧАТЬ ЗАНОВО", restart_requested.emit)
	add_action("В ГЛАВНОЕ МЕНЮ", menu_requested.emit)
	visibility_changed.connect(_on_visibility_changed)
	hide()

func add_action(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(460, 68)
	button.add_theme_font_size_override("font_size", 34)
	button.pressed.connect(action)
	box.add_child(button)
	return button

func _on_visibility_changed() -> void:
	if visible and is_inside_tree():
		(box.get_child(1) as Button).grab_focus.call_deferred()

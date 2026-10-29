extends CanvasLayer
## Меню паузы: ПРОДОЛЖИТЬ / СБРОСИТЬ АВТОМОБИЛЬ / НАЧАТЬ ЗАНОВО / НАСТРОЙКИ / В ГЛАВНОЕ МЕНЮ.
## POLISH-02 (п. 3): бумажная карточка в стиле HUD; управление — в НАСТРОЙКАХ (владелец 29.10, вечер).

signal resume_requested
signal reset_car_requested
signal restart_requested
signal menu_requested

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const INK := Color(0.12, 0.10, 0.08)
const SettingsPanel = preload("res://game/ui/settings_panel.gd")

var box: VBoxContainer
var card: PanelContainer
var settings: PanelContainer
var settings_button: Button
var _focus_before: Variant = null  # Control или null; без типа: узел мог освободиться

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	card = PanelContainer.new()
	card.name = "PauseCard"
	var style := DialogPanelScript.paper_style()
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	card.add_theme_stylebox_override("panel", style)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)
	add_action("ПРОДОЛЖИТЬ", resume_requested.emit)
	add_action("СБРОСИТЬ АВТОМОБИЛЬ", reset_car_requested.emit)
	add_action("НАЧАТЬ ЗАНОВО", restart_requested.emit)
	settings_button = add_action("НАСТРОЙКИ", _open_settings)
	add_action("В ГЛАВНОЕ МЕНЮ", menu_requested.emit)
	settings = SettingsPanel.new()
	settings.set_anchors_preset(Control.PRESET_CENTER)
	settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings.back_requested.connect(_close_settings)
	add_child(settings)
	visibility_changed.connect(_on_visibility_changed)
	hide()

func add_action(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(560, 64)
	DialogPanelScript.style_button(button, box.get_child_count() == 1)
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(action)
	box.add_child(button)
	return button

func _open_settings() -> void:
	card.hide()
	settings.open()

func _close_settings() -> void:
	settings.hide()
	card.show()
	settings_button.grab_focus.call_deferred()

func _on_visibility_changed() -> void:
	if visible and is_inside_tree():
		settings.hide()
		card.show()
		# PAD-01: фокус до паузы (кнопка открытого диалога, панели финала) вернётся после неё — иначе с геймпада
		# диалог под паузой оставался без выделенной кнопки и A ничего не нажимала.
		var focused := get_viewport().gui_get_focus_owner()
		_focus_before = focused if focused and not is_ancestor_of(focused) else null
		(box.get_child(1) as Button).grab_focus.call_deferred()
		DialogPanelScript.pop(card, 0.9)
	elif not visible:
		_restore_focus.call_deferred()

func _restore_focus() -> void:
	var before: Variant = _focus_before
	_focus_before = null
	if is_instance_valid(before) and (before as Control).is_visible_in_tree() and (before as Control).focus_mode != Control.FOCUS_NONE:
		(before as Control).grab_focus()

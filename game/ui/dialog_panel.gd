class_name DialogPanel
extends CanvasLayer
## Панель диалога (QUEST-01): портрет, имя, реплика и кнопки внизу экрана, как на кадрах 02, 03, 07.
## Сама ничего не решает: показывает, что ей передали, и шлёт choice(id) по нажатию кнопки.
## Координаты — в пространстве 1920x1080 (stretch canvas_items).

signal choice(id: StringName)

const PAPER := Color(0.93, 0.87, 0.72)
const PAPER_DARK := Color(0.84, 0.76, 0.58)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)

var panel: PanelContainer
var speaker_label: Label
var text_label: Label
var portrait: Control
var buttons: Dictionary = {}  # id -> Button
var _row: HBoxContainer
var _portrait_kind := &"babka"

func _ready() -> void:
	layer = 8
	visible = false
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", paper_style())
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -270
	panel.offset_bottom = -50
	add_child(panel)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 24)
	panel.add_child(outer)
	portrait = Control.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(150, 150)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.draw.connect(_draw_portrait)
	outer.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	outer.add_child(column)
	speaker_label = Label.new()
	speaker_label.name = "Speaker"
	speaker_label.add_theme_font_size_override("font_size", 38)
	speaker_label.add_theme_color_override("font_color", INK)
	column.add_child(speaker_label)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)
	text_label = Label.new()
	text_label.name = "Text"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(0, 52)
	text_label.add_theme_font_size_override("font_size", 34)
	text_label.add_theme_color_override("font_color", INK)
	column.add_child(text_label)
	_row = HBoxContainer.new()
	_row.name = "Buttons"
	_row.add_theme_constant_override("separation", 20)
	column.add_child(_row)

## specs: [{id, text, enabled (по умолчанию true), primary (по умолчанию false)}].
func open(speaker: String, text: String, specs: Array, portrait_kind: StringName = &"babka") -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	buttons.clear()
	speaker_label.text = speaker
	text_label.text = text
	_portrait_kind = portrait_kind
	portrait.queue_redraw()
	var first_enabled: Button = null
	for spec in specs:
		var button := Button.new()
		button.name = "Button_" + String(spec["id"])
		button.text = spec["text"]
		button.disabled = not spec.get("enabled", true)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 58)
		_style_button(button, spec.get("primary", false))
		button.pressed.connect(_on_pressed.bind(spec["id"]))
		_row.add_child(button)
		buttons[spec["id"]] = button
		if first_enabled == null and not button.disabled:
			first_enabled = button
	visible = true
	if first_enabled:
		first_enabled.grab_focus()

func close() -> void:
	visible = false
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	buttons.clear()

func is_open() -> bool:
	return visible

func _on_pressed(id: StringName) -> void:
	choice.emit(id)

static func paper_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	return style

func _style_button(button: Button, primary: bool) -> void:
	button.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.border_color = INK
		style.set_border_width_all(3)
		style.set_corner_radius_all(3)
		var base := YELLOW if primary else PAPER_DARK
		match state:
			"hover": base = base.lightened(0.15)
			"pressed": base = base.darkened(0.15)
			"disabled": base = Color(0.62, 0.60, 0.55)
		style.bg_color = base
		if state == "focus":
			style.set_border_width_all(5)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(0.35, 0.33, 0.30))

## Портрет-заглушка: голова в платке. Настоящие портреты — ART-01.
func _draw_portrait() -> void:
	var rect := Rect2(Vector2.ZERO, portrait.size)
	portrait.draw_rect(rect, PAPER_DARK)
	portrait.draw_rect(rect, INK, false, 3.0)
	var scarf := Color(0.62, 0.20, 0.22) if _portrait_kind == &"vendor" else Color(0.45, 0.48, 0.20)
	var skin := Color(0.93, 0.88, 0.62)
	var c := rect.get_center() + Vector2(0, 8)
	portrait.draw_circle(c + Vector2(0, 40), 62.0, Color(0.35, 0.30, 0.28))
	portrait.draw_circle(c, 46.0, scarf)
	portrait.draw_circle(c + Vector2(0, 8), 36.0, skin)
	portrait.draw_circle(c + Vector2(-13, 2), 4.0, INK)
	portrait.draw_circle(c + Vector2(13, 2), 4.0, INK)
	portrait.draw_line(c + Vector2(-10, 24), c + Vector2(10, 24), INK, 3.0)

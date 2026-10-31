extends CanvasLayer
## Shared by title-menu and pause settings; all conditions remain visible while locked.

signal back_requested

const Dialog = preload("res://game/ui/dialog_panel.gd")
const INK := Color(0.12, 0.10, 0.08)
const SOFT := Color(0.32, 0.29, 0.24)
const GREEN := Color(0.14, 0.38, 0.20)
var cards: Array[PanelContainer] = []
var back_button: Button
var count_label: Label
var grid: GridContainer
var store: Node

func _ready() -> void:
	name = "AchievementsPanel"
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.06, 0.84)
	add_child(shade)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -820
	card.offset_right = 820
	card.offset_top = -470
	card.offset_bottom = 470
	var paper := Dialog.paper_style()
	paper.content_margin_left = 34
	paper.content_margin_right = 34
	paper.content_margin_top = 24
	paper.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", paper)
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := _label("ДОСТИЖЕНИЯ", 44, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	count_label = _label("", 26, SOFT)
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(count_label)
	grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "НАЗАД"
	back_button.custom_minimum_size.y = 56
	back_button.add_theme_font_size_override("font_size", 30)
	Dialog.style_button(back_button, true)
	back_button.pressed.connect(back_requested.emit)
	box.add_child(back_button)
	hide()

func open(collection: Node = null) -> void:
	store = collection if collection != null else get_tree().get_first_node_in_group(&"achievements_store")
	_refresh()
	show()
	back_button.grab_focus.call_deferred()

func _refresh() -> void:
	for card in cards:
		grid.remove_child(card)
		card.queue_free()
	cards.clear()
	if store == null:
		count_label.text = "Коллекция недоступна"
		return
	var earned := 0
	for entry: Dictionary in store.entries():
		earned += int(entry["unlocked"])
		var card := _entry_card(entry)
		cards.append(card)
		grid.add_child(card)
	count_label.text = "Получено: %d / %d" % [earned, cards.size()]

func _entry_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = String(entry["id"])
	card.custom_minimum_size = Vector2(772, 170)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var paper := Dialog.paper_style()
	paper.bg_color = Color(0.98, 0.94, 0.82) if entry["unlocked"] else Color(0.85, 0.81, 0.71)
	paper.content_margin_left = 14
	paper.content_margin_right = 14
	paper.content_margin_top = 10
	paper.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", paper)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.name = "Illustration"
	icon.texture = load(entry["icon"])
	icon.custom_minimum_size = Vector2(138, 138)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color.WHITE if entry["unlocked"] else Color(0.56, 0.54, 0.49, 0.64)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	text.add_child(_label(entry["title"], 29, INK))
	var condition := _label(entry["description"], 23, INK)
	condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(condition)
	text.add_child(_label("ПОЛУЧЕНО" if entry["unlocked"] else "ЕЩЁ НЕ ПОЛУЧЕНО", 19, GREEN if entry["unlocked"] else SOFT))
	return card

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		back_requested.emit()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

extends CanvasLayer
## Main owns the queue; gameplay and UI never pause or steal focus for a reward.

const Catalog = preload("res://game/progression/achievements.gd")
const Dialog = preload("res://game/ui/dialog_panel.gd")
const DISPLAY_SECONDS := 5.0
var card: PanelContainer
var icon: TextureRect
var title: Label
var quip: Label
var pending: Array[StringName] = []
var current_id: StringName = &""
var remaining := 0.0
var world: Node

func _ready() -> void:
	name = "AchievementToast"
	layer = 7
	process_mode = Node.PROCESS_MODE_ALWAYS
	card = PanelContainer.new()
	card.name = "AchievementNotification"
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -740
	card.offset_right = -70
	card.offset_top = 160
	card.offset_bottom = 334
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", Dialog.paper_style())
	add_child(card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(118, 118)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	text.add_child(_label("ДОСТИЖЕНИЕ ПОЛУЧЕНО", 18))
	title = _label("", 30)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	quip = _label("", 23)
	quip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(quip)
	card.hide()

func setup(collection: Node) -> void:
	collection.achievement_unlocked.connect(_enqueue)

func bind_world(new_world: Node) -> void:
	world = new_world
	pending.clear()
	current_id = &""
	remaining = 0.0
	if card:
		card.hide()

func _enqueue(id: StringName) -> void:
	if is_instance_valid(world) and id != current_id and id not in pending:
		pending.append(id)

func _process(delta: float) -> void:
	if _blocked():
		card.hide()
		return
	if current_id != &"":
		remaining -= delta
		if remaining <= 0.0:
			current_id = &""
	if current_id == &"" and not pending.is_empty():
		current_id = pending.pop_front()
		var entry := Catalog.definition(current_id)
		title.text = entry["title"]
		quip.text = entry["toast"]
		icon.texture = load(Catalog.icon_path(current_id))
		remaining = DISPLAY_SECONDS
	card.visible = current_id != &""

func _blocked() -> bool:
	if not is_instance_valid(world) or get_tree().paused or world.ui_blocking or world.is_stealth_failing():
		return true
	var hud := world.get_node_or_null("GameHUD")
	if hud and ((hud.completion_panel and hud.completion_panel.visible) or (hud.end_panel and hud.end_panel.visible)):
		return true
	var phone := world.get_node_or_null("Phone")
	return phone != null and phone.phone_panel != null and phone.phone_panel.is_visible_in_tree()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

extends CanvasLayer
## GameHUD greybox: слева сверху заголовок и задача, внизу подсказка E. Только читает DemoWorld.get_hud_state() (C6).
## Мини-карта, ромб, маркеры, скорость, «ХЛЕБ +1» и финал — QUEST-01.

var title_label: Label
var task_label: Label
var prompt_label: Label

func _ready() -> void:
	layer = 5
	var card := PanelContainer.new()
	card.name = "ObjectiveCard"
	card.position = Vector2(40, 32)
	var box := VBoxContainer.new()
	title_label = _label(40)
	task_label = _label(30)
	box.add_child(title_label)
	box.add_child(task_label)
	card.add_child(box)
	add_child(card)
	prompt_label = _label(36)
	prompt_label.name = "Prompt"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_top = -160
	prompt_label.offset_bottom = -110
	prompt_label.offset_left = -400
	prompt_label.offset_right = 400
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	prompt_label.add_theme_constant_override("outline_size", 8)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(prompt_label)

func _process(_delta: float) -> void:
	var world := get_parent()
	if not world or not world.has_method("get_hud_state"):
		return
	var state: Dictionary = world.get_hud_state()
	title_label.text = state["title"]
	task_label.text = "□ " + state["task"] if state["task"] != "" else ""
	prompt_label.text = state["prompt"]
	prompt_label.visible = state["prompt"] != ""

func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	return label

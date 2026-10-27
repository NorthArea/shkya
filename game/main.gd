extends Node
## Точка входа. Сейчас — каркас BOOT-01: экран-заглушка вместо главного меню.
## Мир DemoWorld, миссия и меню появятся в задачах GREY-01 и QUEST-01.

const InputSetup = preload("res://game/input_setup.gd")

const TITLE := "ШКЯ: Новосибирск — «За хлебом»"
const STATUS := "Каркас проекта. Миссия ещё не реализована."

func _ready() -> void:
	InputSetup.install()
	var layer := CanvasLayer.new()
	layer.name = "Placeholder"
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for line in [[TITLE, 64], [STATUS, 32]]:
		var label := Label.new()
		label.text = line[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", line[1])
		box.add_child(label)
	layer.add_child(box)
	add_child(layer)

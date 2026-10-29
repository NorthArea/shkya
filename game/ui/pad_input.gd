extends Node
## PAD-01: какое устройство последним использовал игрок — геймпад или клавиатура/мышь. По нему HUD пишет «X — …»
## вместо «E — …». Узел — последний ребёнок корня, поэтому видит ввод раньше всех (_input идёт от конца дерева
## к началу) и ничего не съедает.

## Последним использовался геймпад.
static var pad_active := false
static var current: Node

## Отклонение стика или курка, с которого геймпад считается «использованным» (дрожь в покое — нет).
const STICK_SWITCH := 0.3
## Сдвиг мыши (пиксели за событие), после которого подсказки снова клавиатурные: дрожь мыши не в счёт.
const MOUSE_SWITCH := 4.0

## Добавить узел к корню дерева (один на процесс); исчезает вместе с owner_node.
static func ensure(owner_node: Node) -> void:
	if is_instance_valid(current):
		return
	var node: Node = load("res://game/ui/pad_input.gd").new()
	node.name = "PadInput"
	current = node
	owner_node.get_tree().root.add_child.call_deferred(node)
	owner_node.tree_exiting.connect(node.queue_free)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Подсказка с клавишей клавиатуры → с кнопкой геймпада, если последним был геймпад («E — …» → «X — …»).
static func hint(text: String) -> String:
	if pad_active and text.begins_with("E "):
		return "X" + text.substr(1)
	return text

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		pad_active = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= STICK_SWITCH:
			pad_active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			pad_active = false
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > MOUSE_SWITCH:
			pad_active = false

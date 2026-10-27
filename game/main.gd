extends Node
## Точка входа: главное меню → DemoWorld → пауза. Каждый запуск создаёт мир заново,
## поэтому миссия всегда начинается с NOT_STARTED (раздел 6 канона).

const InputSetup = preload("res://game/input_setup.gd")
const WorldScene = preload("res://game/world/demo_world.tscn")
const MainMenu = preload("res://game/ui/main_menu.gd")
const PauseMenu = preload("res://game/ui/pause_menu.gd")

var world: DemoWorld
var menu: CanvasLayer
var pause_menu: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.install()
	menu = MainMenu.new()
	menu.name = "MainMenu"
	menu.start_requested.connect(start_game)
	menu.quit_requested.connect(func(): get_tree().quit())
	add_child(menu)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.resume_requested.connect(set_paused.bind(false))
	pause_menu.restart_requested.connect(start_game)
	pause_menu.menu_requested.connect(return_to_menu)
	add_child(pause_menu)

func start_game() -> void:
	_free_world()
	world = WorldScene.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	menu.hide()
	set_paused(false)

func return_to_menu() -> void:
	_free_world()
	set_paused(false)
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_menu.visible = paused
	if world:
		var free_mouse := paused or world.ui_blocking
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not world:
		return
	if event.is_action_pressed(&"pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused and not world.ui_blocking:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _free_world() -> void:
	if world:
		remove_child(world)
		world.free()
		world = null

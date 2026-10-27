extends Node
## Точка входа: главное меню → DemoWorld → пауза. Каждый запуск создаёт мир заново,
## поэтому миссия всегда начинается с NOT_STARTED (раздел 6 канона).

const InputSetup = preload("res://game/input_setup.gd")
const WorldScene = preload("res://game/world/demo_world.tscn")
const MainMenu = preload("res://game/ui/main_menu.gd")
const PauseMenu = preload("res://game/ui/pause_menu.gd")
const UI_CLICK := preload("res://assets/audio/ui_click.wav")

var world: DemoWorld
var menu: CanvasLayer
var pause_menu: CanvasLayer
## Щелчок кнопок меню и паузы (POLISH-01): плеер вне мира, играет и на паузе.
var ui_click: AudioStreamPlayer

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
	pause_menu.reset_car_requested.connect(reset_car)
	pause_menu.restart_requested.connect(start_game)
	pause_menu.menu_requested.connect(return_to_menu)
	add_child(pause_menu)
	ui_click = AudioStreamPlayer.new()
	ui_click.name = "UiClick"
	ui_click.stream = UI_CLICK
	ui_click.volume_db = -6.0
	add_child(ui_click)
	for layer in [menu, pause_menu]:
		for button in layer.find_children("*", "Button", true, false):
			button.pressed.connect(ui_click.play)

## Смена мира откладывается до конца кадра: её можно вызвать из сигнала самого мира
## (кнопка на панели финала, физический callback) без освобождения узла посреди обработки.
func start_game() -> void:
	_swap_world.call_deferred(true)

func return_to_menu() -> void:
	_swap_world.call_deferred(false)

func _swap_world(new_game: bool) -> void:
	if world:
		remove_child(world)
		world.queue_free()
		world = null
	if new_game:
		world = WorldScene.instantiate()
		world.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(world)
		menu.hide()
		set_paused(false)
	else:
		set_paused(false)
		menu.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func reset_car() -> void:
	if world:
		world.reset_car()
	set_paused(false)

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

extends Node
## Точка входа: главное меню → загрузка → DemoWorld → пауза. Каждый запуск создаёт мир заново,
## поэтому миссия всегда начинается с NOT_STARTED (раздел 6 канона).

const InputSetup = preload("res://game/input_setup.gd")
const WORLD_SCENE_PATH := "res://game/world/demo_world.tscn"
const StartupScreen = preload("res://game/ui/startup_screen.gd")
const MainMenu = preload("res://game/ui/main_menu.gd")
const PauseMenu = preload("res://game/ui/pause_menu.gd")
const IntroScript = preload("res://game/ui/intro.gd")
const CaughtPanelScript = preload("res://game/ui/caught_panel.gd")
const PhoneScript = preload("res://game/ui/phone.gd")
const PadInput = preload("res://game/ui/pad_input.gd")
const AudioSettingsScript = preload("res://game/audio/audio_settings.gd")
const MusicDirectorScript = preload("res://game/audio/music_director.gd")
const AchievementsStore = preload("res://game/progression/achievements_store.gd")
const AchievementsTracker = preload("res://game/progression/achievements_tracker.gd")
const AchievementToast = preload("res://game/ui/achievement_toast.gd")
const DisplaySettingsScript = preload("res://game/display_settings.gd")
const PerformanceOverlayScript = preload("res://game/ui/performance_overlay.gd")
const UI_CLICK := preload("res://assets/audio/ui_click.wav")

# Set before _ready in tests/captures; script runs isolate the owner's persistent profile.
var achievement_path := ""
var display_settings_path := ""
var audio_settings_path := ""
var audio_settings: Node
var display_settings: Node
var achievements: Node
var achievement_toast: CanvasLayer
var world: DemoWorld
var startup_screen: Control
var _start_pending := false
var menu: CanvasLayer
var pause_menu: CanvasLayer
## Щелчок кнопок меню и паузы (POLISH-01): плеер вне мира, играет и на паузе.
var ui_click: AudioStreamPlayer
## Тема меню (MUSIC-01): вне мира, в меню и (тише, приглушённо) на паузе; в игре молчит.
var music: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	InputSetup.install()
	add_child(PerformanceOverlayScript.new())
	PadInput.ensure(self)  # PAD-01: последнее устройство (геймпад или клавиатура) для подсказок HUD
	display_settings = DisplaySettingsScript.new()
	display_settings.name = "DisplaySettings"
	if not display_settings_path.is_empty():
		display_settings.config_path = display_settings_path
	elif get_tree().get_script() != null:
		# Scripted checks must not read or overwrite the owner's rendering preference.
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/RESOLUTION-01"))
		display_settings.config_path = "res://builds/checks/RESOLUTION-01/script-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	add_child(display_settings)
	if achievement_path.is_empty():
		var args := OS.get_cmdline_args()
		var scripted := args.has("--script") or args.has("-s")
		achievement_path = "res://builds/checks/ACHIEVE-01/script-session-%d.json" % OS.get_process_id() if scripted else AchievementsStore.DEFAULT_PATH
	achievements = AchievementsStore.new()
	var load_error: Error = achievements.setup(achievement_path)
	if load_error != OK:
		push_warning("Не удалось загрузить достижения: %s" % error_string(load_error))
	add_child(achievements)
	achievement_toast = AchievementToast.new()
	add_child(achievement_toast)
	achievement_toast.setup(achievements)
	audio_settings = AudioSettingsScript.new()
	audio_settings.name = "AudioSettings"
	if not audio_settings_path.is_empty():
		audio_settings.config_path = audio_settings_path
	elif get_tree().get_script() != null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/AUDIO-SETTINGS-01"))
		audio_settings.config_path = "res://builds/checks/AUDIO-SETTINGS-01/script-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	add_child(audio_settings)
	menu = MainMenu.new()
	menu.name = "MainMenu"
	menu.start_requested.connect(request_start_game)
	menu.quit_requested.connect(quit_game)
	add_child(menu)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.resume_requested.connect(set_paused.bind(false))
	pause_menu.reset_car_requested.connect(reset_car)
	pause_menu.restart_requested.connect(request_start_game)
	pause_menu.menu_requested.connect(return_to_menu)
	add_child(pause_menu)
	ui_click = AudioStreamPlayer.new()
	ui_click.name = "UiClick"
	ui_click.bus = AudioSettingsScript.EFFECTS_BUS
	ui_click.stream = UI_CLICK
	ui_click.volume_db = -6.0
	add_child(ui_click)
	for layer in [menu, pause_menu]:
		for button in layer.find_children("*", "Button", true, false):
			button.pressed.connect(ui_click.play)
	music = MusicDirectorScript.new()
	music.name = "MusicDirector"
	add_child(music)
	music.to_menu()

## UI запускает настоящий загрузчик; повторный сигнал до готовности не создаёт второй мир.
func request_start_game() -> void:
	if _start_pending or startup_screen != null:
		return
	_start_pending = true
	_show_startup.call_deferred()

func _show_startup() -> void:
	if not _start_pending:
		return
	_clear_world()
	set_paused(false)
	menu.hide()
	music.to_game()
	startup_screen = StartupScreen.new()
	startup_screen.name = "StartupScreen"
	startup_screen.scene_path = WORLD_SCENE_PATH
	startup_screen.embedded = true
	startup_screen.scene_ready.connect(_start_loaded_world)
	add_child(startup_screen)

func _start_loaded_world(scene: PackedScene) -> void:
	if startup_screen == null or not _start_pending:
		return
	_swap_world(true, scene)

## Прямой hook для headless-проверок: без UI-подтверждения, с ленивой загрузкой.
## Смена мира отложена: сигнал мира не освобождает свой узел посреди callback.
func start_game() -> void:
	_swap_world.call_deferred(true)

func return_to_menu() -> void:
	_start_pending = false
	_swap_world.call_deferred(false)

func _clear_startup() -> void:
	_start_pending = false
	if startup_screen != null:
		remove_child(startup_screen)
		startup_screen.queue_free()
		startup_screen = null

func _clear_world() -> void:
	achievement_toast.bind_world(null)
	if world:
		remove_child(world)
		world.queue_free()
		world = null

func _swap_world(new_game: bool, scene: PackedScene = null) -> void:
	_clear_startup()
	_clear_world()
	if new_game:
		menu.hide()
		music.to_game()
		if scene == null:
			scene = load(WORLD_SCENE_PATH) as PackedScene
		world = scene.instantiate()
		world.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(world)
		_connect_end_card(world)
		# INTRO-01: после загрузки прежний Intro сохраняет свой приоритет ввода.
		IntroScript.attach(world)
		_connect_caught_panel(world)
		PhoneScript.attach(world)
		var tracker := AchievementsTracker.new()
		tracker.setup(world, achievements)
		world.add_child(tracker)
		achievement_toast.bind_world(world)
		set_paused(false)
	else:
		set_paused(false)
		menu.show()
		music.to_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Карточка «Конец демо» (POLISH-02): «ЕЩЁ РАЗ» — новый мир с NOT_STARTED, как из меню; «В МЕНЮ» — главное меню.
func _connect_end_card(new_world: Node) -> void:
	var hud := new_world.get_node_or_null("GameHUD")
	if hud == null or not hud.has_signal("restart_requested"):
		return
	hud.restart_requested.connect(request_start_game)
	hud.menu_requested.connect(return_to_menu)
	for button in hud.end_buttons.values():
		button.pressed.connect(ui_click.play)

## STORY-01: провал стелса — карточка «В ГОРОДЕ Н. НИЧЕГО НЕ ПРОИЗОШЛО»; «В ГЛАВНОЕ МЕНЮ» — как из паузы.
## В тестах и headless её нет (как заставки) — провал прежний. Музыка на ней не играет (обоснование — caught_panel.gd).
func _connect_caught_panel(new_world: Node) -> void:
	var caught := CaughtPanelScript.attach(new_world)
	if caught == null:
		return
	caught.menu_requested.connect(return_to_menu)
	for button in caught.buttons.values():
		button.pressed.connect(ui_click.play)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

## Выход из игры: сначала остановить весь звук. Если выйти, когда звук на паузе или только
## запущен (щелчок кнопки), Godot при выходе пишет «ObjectDB instances were leaked» про
## AudioStreamWAV и AudioStreamPlayback (POLISH-01; замеры в карточке).
func quit_game() -> void:
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in get_tree().root.find_children("*", type, true, false):
			player.stop()
	get_tree().quit()

func reset_car() -> void:
	if world:
		world.reset_car()
	set_paused(false)

func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_menu.visible = paused
	if world:
		music.set_paused(paused)
	if world:
		var free_mouse := paused or world.ui_blocking
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not world:
		return
	# B геймпада (ui_cancel) на паузе — «продолжить» (PAD-01); Esc — это и pause, и ui_cancel: срабатывает один раз.
	if event.is_action_pressed(&"pause") or (get_tree().paused and event.is_action_pressed(&"ui_cancel")):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused and not world.ui_blocking:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	preload("res://game/world/bank_mesh_cache.gd").clear()

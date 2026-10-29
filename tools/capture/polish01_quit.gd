## POLISH-01: выход из игры без «ObjectDB instances were leaked» (звук на паузе, щелчок кнопки).
## Только в окне: в headless звуковой драйвер-заглушка не микширует, и плееры «утекают» всегда.
## Запуск по одному режиму (pause, restart, click, close, menu_quit):
##   PROBE_MODE=pause tools/run.command --verbose --resolution 1280x720 --script tools/capture/polish01_quit.gd
## Итог: код 0 и в логе нет «leaked» и «still in use»; PROBE_STUCK — игра не вышла сама.
extends SceneTree
# Пути выхода, которых нет у автопилота: пауза, перезапуск, меню, щелчок кнопки.
var main: Node
func _initialize() -> void:
	call_deferred("_run")
func _f(n: int) -> void:
	for i in n: await process_frame
func _run() -> void:
	var mode := OS.get_environment("PROBE_MODE")
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _f(3)
	main.menu.start_button.pressed.emit()
	await _f(90)
	match mode:
		"pause":
			main.set_paused(true)
			await _f(30)
		"restart":
			main.set_paused(true)
			await _f(10)
			main.start_game()
			await _f(90)
		"menu":
			main.set_paused(true)
			await _f(10)
			main.return_to_menu()
			await _f(60)
		"click":
			main.ui_click.play()
			await _f(2)
		"menu_quit":
			main.return_to_menu()
			await _f(10)
			main.ui_click.play()
		"close":
			root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
			await _f(30)
	print("PROBE_DONE ", mode)
	# Как закрытие окна крестиком: игра должна выйти сама.
	if mode == "menu_quit":
		main.menu.quit_requested.emit()
	else:
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _f(600)
	print("PROBE_STUCK")
	quit(3)

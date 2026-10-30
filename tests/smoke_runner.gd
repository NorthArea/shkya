extends SceneTree
## Smoke-проверка каркаса: главная сцена загружается и ставит раскладку из канона.
## Это не приёмка миссии — сценарии раздела 8 канона появятся вместе с QUEST-01.

const InputSetup = preload("res://game/input_setup.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("FAIL: smoke runner exceeded 30 simulated seconds")
		quit(2)
	)
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene")
	check(main_path == "res://game/main.tscn", "main scene is game/main.tscn")
	var packed = load(main_path)
	check(packed is PackedScene, "main scene is an instantiable PackedScene")
	if packed is PackedScene:
		var main: Node = packed.instantiate()
		root.add_child(main)
		await process_frame
		for action in InputSetup.KEYS:
			check(InputMap.has_action(action), "input action '%s' installed" % action)
		check(InputMap.action_get_events("interact").any(
			func(e): return e is InputEventKey and e.physical_keycode == KEY_E), "interact is bound to E")
		main.queue_free()
		await process_frame
		# MUSIC-01: тема меню звучит с первого кадра; остановленный поток аудиосервер отпускает в своём потоке
		# микширования — без паузы по часам выход ловит его живым («resources still in use»).
		OS.delay_msec(100)
		await process_frame
	_finish()

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("SMOKE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## ART-01, облик персонажей на настоящем main.tscn: выбор ракурса по камере и кадры ходьбы
## при настоящей ходьбе через физику. Гонять при 60 и 120 к/с (`make test`): на 120 к/с
## кадры отрисовки идут чаще шага физики — ходьба не должна сбрасываться в стойку.

const Layout = preload("res://game/world/layout.gd")

var failures: Array[String] = []
var checks := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("FAIL: art01 test exceeded 120 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _physics(2)
	main.start_game()
	await _physics(10)
	var world: DemoWorld = main.world
	var look: CharacterSprite = world.player.get_node("Visual/Look")
	check(look != null and look.sprite != null, "Ilyusha has a CharacterSprite look")
	# Ракурсы: Илюша смотрит на запад (yaw PI/2), камера обходит его.
	world.player.place(Layout.SPAWN, PI * 0.5)
	for case in [[PI * 0.5, &"back"], [-PI * 0.5, &"front"], [0.0, &"side"], [PI, &"side"]]:
		world.camera_rig.yaw = case[0]
		world.camera_rig.snap()
		await _render(3)
		check(look.view == case[1], "camera yaw %.2f shows %s (got %s)" % [case[0], case[1], look.view])
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await _render(3)
	var flip_a := look.sprite.flip_h
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await _render(3)
	check(look.sprite.flip_h != flip_a, "side view mirrors when the camera goes round to the other side")
	check(look.frame == -1 and look.sprite.texture == look._idle[look.view], "standing still shows the idle drawing")
	# Ходьба через физику: камера за спиной, «вперёд» — на запад.
	world.camera_rig.yaw = PI * 0.5
	world.camera_rig.snap()
	await _render(3)
	Input.action_press(&"move_forward")
	var seen := {}
	var idle_samples := 0
	for i in 90:
		await process_frame
		if i < 10:
			continue  # разгон
		seen[look.frame] = true
		if look.frame == -1:
			idle_samples += 1
	Input.action_release(&"move_forward")
	check(idle_samples == 0, "walking never drops to the idle drawing between physics steps (idle samples: %d)" % idle_samples)
	check(seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "walking cycles through all four frames (seen %s)" % [seen.keys()])
	check(look.sprite.texture in (look._walk[look.view] as Array), "walking shows a walk drawing")
	await _physics(10)
	check(look.frame == -1, "stopping returns to the idle drawing")
	# Телепорт — не шаг.
	world.player.place(Layout.SPAWN + Vector3(5, 0, 0), PI * 0.5)
	await _physics(2)
	check(look.frame == -1, "teleport (place) does not start the walk cycle")
	# NPC.
	for npc in [world.babka, world.vendor]:
		var npc_look: CharacterSprite = npc.get_node("Visual/Look")
		check(npc_look != null and npc_look.sprite.texture != null, "%s has a CharacterSprite look" % npc.name)
	_finish()

func _physics(count: int) -> void:
	for i in count:
		await physics_frame

func _render(count: int) -> void:
	for i in count:
		await process_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("ART01: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)

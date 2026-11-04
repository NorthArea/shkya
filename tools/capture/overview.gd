extends SceneTree
## Сценическая витрина настоящей игры, не автоматический проход миссии.
## ./tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/overview.gd

const Layout = preload("res://game/world/layout.gd")
const OUT := "res://builds/screenshots/OVERVIEW"
var main: Node
var world: DemoWorld
var flow: Node
var photo_camera: Camera3D
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func():
		push_error("OVERVIEW: capture exceeded 180 simulated seconds")
		quit(2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(40)
	await _photo("01-menu")
	main.start_game()
	await _frames(20)
	world = main.world
	flow = world.get_node("QuestFlow")
	photo_camera = Camera3D.new()
	photo_camera.far = 4000.0
	photo_camera.fov = 65.0
	root.add_child(photo_camera)
	await _place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _photo("02-yard")
	await _babka_offer()
	await _driving()
	await _city()
	await _stealth()
	await _kiosk()
	await _phone()
	await _dog()
	await _bags()
	await _life()
	await _finale()
	await _finish()

func _babka_offer() -> void:
	await _place(Layout.BABKA + Vector3(1.5, 0, -1.9), PI)
	world.babka.interactable.interact(world.player)
	await _frames(90)
	if _require(flow.is_dialog_open(), "Babka offer dialog opens"):
		flow.dialog.finish_typing()
		await _frames(2)
		await _photo("03-babka")
		flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(10)

func _driving() -> void:
	world.enter_car()
	world.car.reset_to(Layout.ROUTE_DRIVE[3], -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	world.camera_rig.snap()
	Input.action_press(&"car_gas")
	await _frames(85)
	await _photo("04-driving")
	Input.action_release(&"car_gas")
	world.car.velocity = Vector3.ZERO
	_require(world.exit_car(), "Ilyusha exits the Lada after the driving scene")
	await _frames(8)

func _city() -> void:
	var traffic: Node = world.get_node("LevelGeometry/Traffic")
	var bus: Node3D = traffic.trolleybus
	var at := bus.global_position
	var right := bus.global_basis.x
	var forward := -bus.global_basis.z
	world.player.place(at + right * 8.0 + forward * 3.0, 0.0)
	await _look(at + right * 12.0 + forward * 9.0 + Vector3.UP * 2.8, at + Vector3.UP * 1.6)
	await _photo("05-city")

func _stealth() -> void:
	world.mission.notify_arrived_kiosk()
	world.car.reset_to(Layout.ROUTE_DRIVE[-1], -1.2)
	var box: HideSpot = world.get_node("LevelGeometry/HideSpots/BreadBox")
	await _place(box.home, -0.1)
	if _require(box.enter(), "Ilyusha enters the actual bread box"):
		await _frames(16)
		await _photo("06-stealth")
		box.exit()
	await _frames(4)

func _kiosk() -> void:
	world.reset_hide()
	world.mission.add_money(world.mission.money_missing())
	world.stealth.grant_grace(4.0)
	await _place(Layout.VENDOR_WINDOW + Vector3(0.6, 0, 0), PI * 0.5)
	world.vendor.interactable.interact(world.player)
	await _frames(90)
	if _require(flow.is_dialog_open(), "vendor dialog opens"):
		flow.dialog.finish_typing()
		await _frames(2)
		await _photo("07-kiosk")
		_finish_chain()
		if _require(flow.dialog.buttons.has(&"buy"), "vendor offers the actual bread purchase"):
			flow.dialog.buttons[&"buy"].pressed.emit()
	await _frames(10)

func _phone() -> void:
	await _place(Layout.SPAWN, Layout.SPAWN_YAW)
	var phone: Node = world.get_node_or_null("Phone")
	if not _require(phone != null and phone.open_phone(), "the in-game phone opens"):
		return
	phone.select_tab(&"news")
	phone.turn_page(2)
	await _frames(8)
	await _photo("08-phone-news")
	phone.select_tab(&"sms")
	phone.turn_page(phone.inbox.size())
	await _frames(8)
	await _photo("09-phone-sms")
	phone.close_phone()
	await _frames(8)

func _dog() -> void:
	var ambient: Node = world.get_node("LevelGeometry/Ambient")
	var at: Vector3 = ambient.dog.global_position
	world.player.place(at + Vector3(-1.3, 0, 0.8), -PI * 0.5)
	await _look(at + Vector3(-4.0, 1.9, -3.8), at + Vector3(-0.5, 0.8, 0.2))
	await _frames(8)
	await _photo("10-dog")
	var zone: Interactable = world.player.current_interactable()
	if _require(zone != null and zone.interaction_id == &"dog", "dog petting is available in the scene"):
		zone.interact(world.player)
		await _frames(22)
		await _photo("10-dog-petting")

func _bags() -> void:
	var wind: Node = world.get_node("LevelGeometry/WindBags")
	world.player.place(Layout.SPAWN + Vector3(-6, 0, -5), 0.0)
	await _frames(8)
	# Намеренно ставим реальный пакет в контакт: кадр показывает анимацию, а не вероятность встречи.
	var caught: Node3D = null
	for attempt in 12:
		for bag in wind.bags:
			if bag.kind != &"shop": continue
			bag.state = &"fly"
			bag.position = world.player.visual.to_global(Vector3(0.3, 1.05, -0.05))
			bag.velocity = Vector3(2, 0, 0)
			wind._try_snag(bag)
			if bag.state == &"snag" and bag.snag_target == world.player:
				caught = bag
				break
		if caught != null: break
		wind.clock += 1.0
	_require(caught != null, "a real bag catches on Ilyusha's coat")
	var flying: Node3D = wind.bags[1]
	flying.state = &"fly"
	flying.position = world.player.global_position + Vector3(-1.1, 1.7, -0.8)
	flying.velocity = Vector3(1.8, 0.2, 0.5)
	var at := world.player.global_position
	await _look(at + Vector3(2.6, 1.8, 3.2), at + Vector3(0, 1.0, 0))
	await _photo("11-bags")

func _life() -> void:
	var people: Node = world.get_node("LevelGeometry/Residents")
	var seats: Array[StringName] = [&"domino_w", &"domino_e"]
	var actors: Array = people.life.players(&"domino")
	for index in [17, 29, 10, 11]:
		if actors.size() >= 2: break
		var resident: Resident = people.residents[index]
		if resident in actors: continue
		var seat: StringName = people.life.choose(resident, &"domino", resident.home, resident.rng)
		if seat == &"": continue
		resident._act_stop()
		people.life.release(resident.spot_id, resident)
		resident.place(people.life.spots[seat].pos)
		resident._go_to(seat)
		actors.append(resident)
	if not _require(actors.size() >= 2, "two real residents can use the domino table"):
		return
	var center: Vector3 = (people.life.spots[seats[0]].pos + people.life.spots[seats[1]].pos) * 0.5
	world.player.place(center + Vector3(-3, 0, 4), 0.0)
	await _look(center + Vector3(-6, 2.4, 7), center + Vector3.UP * 0.9)
	var sounds_before := _domino_sounds(actors)
	for i in 180:
		await _frames(1)
		if _domino_sounds(actors) > sounds_before:
			break
	await _frames(4)
	await _photo("12-life")

func _domino_sounds(actors: Array) -> int:
	var count := 0
	for actor in actors: count += int(actor.sound_counts.get(&"domino", 0))
	return count

func _finale() -> void:
	world.reset_hide()
	await _place(Layout.BABKA + Vector3(1.5, 0, -1.9), PI)
	world.mission.notify_home_reached()
	world.babka.interactable.interact(world.player)
	await _frames(60)
	if not _require(flow.is_dialog_open(), "return dialog opens"):
		return
	_finish_chain()
	if not _require(flow.dialog.buttons.has(&"turn_in"), "return dialog offers the actual quest turn-in"):
		return
	flow.dialog.buttons[&"turn_in"].pressed.emit()
	var hud: Node = world.get_node("GameHUD")
	var protocol_visible := false
	# STORY-02: обе реплики читаются до протокола; снимать и закрывать только реально показанную панель.
	for i in 600:
		await _frames(1)
		protocol_visible = flow.protocol_ready() and hud.completion_panel.visible and hud.completion_panel.scale.is_equal_approx(Vector2.ONE)
		if protocol_visible: break
	if not _require(protocol_visible, "both finale replies finish before the actual protocol is shown"):
		return
	await _photo("13-finale")
	hud.completion_close.pressed.emit()
	for i in 600:
		await _frames(1)
		if hud.is_end_card_open(): break
	if _require(hud.is_end_card_open(), "the ending reaches the end card"):
		await _frames(10)
		await _photo("13-finale-end")

func _finish_chain() -> void:
	while flow.is_dialog_open() and not flow.dialog.is_last_line():
		flow.dialog.finish_typing()
		flow.dialog.advance()
	flow.dialog.finish_typing()

func _place(at: Vector3, yaw: float) -> void:
	photo_camera.current = false
	world.camera_rig.camera.make_current()
	world.player.place(at, yaw)
	world.camera_rig.follow(world.player, &"on_foot")
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await _frames(24)

func _look(from: Vector3, to: Vector3) -> void:
	photo_camera.global_position = from
	photo_camera.look_at(to)
	photo_camera.make_current()
	await _frames(10)

func _photo(label: String) -> void:
	if paused:
		# На паузе дерево не гарантирует следующий draw; UI уже прошёл process-кадры для раскладки.
		RenderingServer.force_draw(false)
	else:
		await RenderingServer.frame_post_draw
	var frame := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT.path_join(label + ".png"))
	var error := frame.save_png(path)
	_require(error == OK, "saved " + label)
	print("OVERVIEW SHOT ", label, " ", frame.get_size())

func _frames(count: int) -> void:
	for i in count:
		if paused: await process_frame
		else: await physics_frame

func _require(ok: bool, label: String) -> bool:
	if not ok:
		failures.append(label)
		push_error("OVERVIEW: " + label)
	return ok

func _finish() -> void:
	Input.action_release(&"car_gas")
	paused = false
	var phone: Node = world.get_node_or_null("Phone")
	if phone: phone.close_phone()
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	photo_camera.queue_free()
	main.queue_free()
	for i in 10: await process_frame
	OS.delay_msec(100)
	await process_frame
	print("OVERVIEW: ", "PASS" if failures.is_empty() else "FAIL ", failures)
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## CITY-02 E: кадры среды и панорамы «до | после» с одних точек. Каталог вывода — первый аргумент после --.
var main
var cam: Camera3D
var out := ""
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/Users/a.iuskasov/Workspace/shkya/builds/screenshots/CITY-02/e/x/"
	var only := args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await physics_frame
	main.menu.start_button.pressed.emit()
	for i in 30: await physics_frame
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	var shots := [
		["01_yard", Vector3(-30, 2.0, 96), Vector3(-60, 2.5, 80)],
		["02_a_x_b", Vector3(60, 2.2, 44), Vector3(80, 5, 10)],
		["03_kiosk_stop", Vector3(67, 1.8, -52), Vector3(56, 2, -77)],
		["04_street_d_night", Vector3(-60, 1.8, 16), Vector3(-60, 3, -60)],
		["05_pano_c_north", Vector3(0, 1.8, -99), Vector3(0, 14, -260)],
		["06_pano_a_south", Vector3(0, 1.8, 34), Vector3(0, 16, 220)],
		["07_kiosk_close", Vector3(62.5, 1.7, -72.5), Vector3(55, 1.8, -77)],
		["08_garages_c", Vector3(-12, 1.7, -105), Vector3(-12, 1.4, -117)],
		["09_playground", Vector3(-51, 2.2, 73.5), Vector3(-60, 0.6, 80)],
		["10_bank_3m", Vector3(8, 1.3, 27.6), Vector3(8, 0.3, 24.4)],
		["11_poplar_close", Vector3(-5, 1.6, 21.5), Vector3(-5, 9, 17)],
		["12_pano_b_north", Vector3(70, 1.8, 22), Vector3(70, 16, -250)],
		["13_wires_a", Vector3(-20, 1.8, 30), Vector3(40, 7, 32)],
		["14_shop24", Vector3(-53, 1.8, -34), Vector3(-46, 1.8, -40)],
		["15_billboard", Vector3(-66, 1.8, -99), Vector3(-78, 8, -117)],
		["16_bus_stop_a", Vector3(-27, 1.7, 27), Vector3(-30, 1.3, 21)],
		["17_pano_d_west", Vector3(-62, 1.8, -40), Vector3(-260, 14, -40)],
		["18_pano_a_east", Vector3(97, 1.8, 30), Vector3(260, 14, 30)],
	]
	for s in shots:
		if only == "" or (s[0] as String).begins_with(only):
			await _shot(s[0], s[1], s[2])
	main.queue_free()
	for i in 5: await process_frame
	quit(0)
func _shot(name: String, from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to)
	for i in 8: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + name + ".png")

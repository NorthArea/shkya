extends SceneTree
## POLISH-03 A: кадры «до | после» читаемости — маркер Бабки, киоск с парковки, стелс за гаражами (силуэт, конусы
## на мини-карте), диалог с продавщицей, ромб с расстоянием. Окном: open -g … --script tools/capture/polish03a.gd -- <метка>.
## Кадры: builds/screenshots/POLISH-03/a/<метка>_*.png.

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")

var main: Node
var drv
var w: DemoWorld
var out := ""
var tag := "after"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	tag = args[0] if args.size() > 0 else "after"
	out = ProjectSettings.globalize_path("res://builds/screenshots/POLISH-03/a/")
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(300.0, true, false, true).timeout.connect(func(): quit(3))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	for i in 30: await process_frame
	main.start_game()
	for i in 30: await process_frame
	w = main.world
	var m := w.mission
	if args.size() > 1 and args[1] == "xray":
		m.interact(&"babka")
		m.accept()
		w.stealth.grant_grace(60.0)
		_look(Vector3(51, 0, -81.5), Vector3(62, 0, -70), -0.12)
		await drv.frames(60)
		await _save("04b_xray_officer")
		quit(0)
		return
	# 1. Маркер «!» над Бабкой: вблизи (кадр 01) и издалека.
	_look(Layout.SPAWN, Layout.BABKA, -0.17)
	await drv.frames(90)
	await _save("01_marker_near")
	_look(Layout.BABKA + Vector3(14, 0, -26), Layout.BABKA, -0.17)
	await drv.frames(90)
	await _save("01b_marker_far")
	# Квест взят, деньги есть, едем к киоску.
	m.interact(&"babka")
	m.accept()
	m.add_money(50)
	m.notify_entered_car()
	# 2. Ромб с расстоянием: двор, цель — киоск.
	_look(Layout.SPAWN, Layout.SPAWN + Vector3(0, 0, -10), -0.17)
	await drv.frames(60)
	await _save("02_diamond_far")
	# 3. Киоск с парковки (вид критика v02).
	_look(Vector3(61, 0, -50), Vector3(59, 0, -75), -0.17)
	await drv.frames(120)
	await _save("03_kiosk_from_parking")
	m.notify_arrived_kiosk()
	# 4. За гаражами (p0080): полицейского за киоском не видно.
	_look(Vector3(51.3, 0, -57.5), Vector3(55, 0, -76), -0.17)
	for i in 4:
		await drv.frames(150)
		await _save("04_garages_%d" % i)
	# 4b. Силуэт поста сквозь киоск: из коридора за гаражами.
	w.stealth.grant_grace(60.0)
	_look(Vector3(51, 0, -81.5), Vector3(62, 0, -70), -0.12)
	await drv.frames(60)
	await _save("04b_xray_officer")
	_look(Vector3(51, 0, -70), Vector3(58, 0, -86), -0.12)
	await drv.frames(60)
	await _save("04c_xray_guard")
	# 5. Диалог с продавщицей.
	w.stealth.grant_grace(30.0)
	w.player.place(Layout.VENDOR_WINDOW, -PI * 0.5)
	w.camera_rig.yaw = PI * 0.5 + 0.4
	w.camera_rig.pitch = -0.2
	w.camera_rig.snap()
	await drv.frames(30)
	await drv.interact()
	await drv.frames(90)
	await _save("05_vendor")
	quit(0)

func _look(p: Vector3, t: Vector3, pitch := -0.25) -> void:
	var yaw := atan2(p.x - t.x, p.z - t.z)
	w.player.place(p, yaw + PI)
	w.camera_rig.yaw = yaw
	w.camera_rig.pitch = pitch
	w.camera_rig.snap()

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		print("SHOT(skip) ", label)
		return
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out + tag + "_" + label + ".png")
	print("SHOT ", out + tag + "_" + label + ".png")

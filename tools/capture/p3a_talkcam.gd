extends SceneTree
## POLISH-03 A: камера диалога — серия кадров каждые 0,1 с при открытии и после закрытия диалога с Бабкой и продавщицей,
## и покадровый журнал камеры (шаг положения, угла, длина пружины). Подход — ходьбой, как игрок.
## Окном: open -g … --script tools/capture/p3a_talkcam.gd -- <метка>; headless — только журнал.

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")

var main: Node
var drv
var w: DemoWorld
var out := ""
var tag := "talk"
var _prev_pos := Vector3.INF
var _prev_basis := Basis()
var max_step := 0.0
var max_turn := 0.0
var _prev_step := -1.0
var _prev_turn := -1.0
var max_dstep := 0.0     # наибольшее изменение шага между соседними кадрами (рывок)
var max_dturn := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	tag = args[0] if args.size() > 0 else "talk"
	out = ProjectSettings.globalize_path("res://builds/screenshots/POLISH-03/a/talk/")
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(300.0, true, false, true).timeout.connect(func(): quit(3))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	for i in 30: await process_frame
	main.menu.start_button.pressed.emit()
	for i in 30: await process_frame
	w = main.world
	# Бабка: от появления пешком к подъезду.
	await drv.walk_to(Layout.BABKA + Vector3(0.6, 0, -2.0))
	await _series("babka_open", true)
	await drv.press_button("ОТКАЗАТЬСЯ", &"ui_right")
	await _series("babka_close", false)
	# Продавщица: квест взят, деньги есть, пешком с юга по тротуару B к окну.
	var m := w.mission
	m.interact(&"babka")
	m.accept()
	m.add_money(50)
	m.notify_entered_car()
	w.stealth.grant_grace(120.0)
	w.player.place(Vector3(59.5, 0, -58.0), 0.0)
	w.camera_rig.yaw = 0.0
	w.camera_rig.snap()
	await drv.frames(20)
	await drv.walk_to(Layout.VENDOR_WINDOW)
	await _series("vendor_open", true)
	await drv.press_button("ДАЛЬШЕ")
	for i in 6:
		if not await drv.press_button("ДАЛЬШЕ"):
			break
	await drv.press_button("УЙТИ", &"ui_right")
	await _series("vendor_close", false)
	print("TALKCAM max step %.3f m, max turn %.2f deg" % [max_step, max_turn])
	quit(0)

## open: E и 2 с кадров; иначе — 2 с после уже нажатой кнопки. Каждый физкадр — журнал, каждые 6 — кадр.
func _series(label: String, open: bool) -> void:
	_prev_pos = Vector3.INF
	_prev_step = -1.0
	max_dstep = 0.0
	max_dturn = 0.0
	if open:
		drv.tap(&"interact")
	for f in 120:
		await physics_frame
		var cam: Camera3D = w.camera_rig.camera
		var t := cam.global_transform
		if _prev_pos != Vector3.INF:
			var step := t.origin.distance_to(_prev_pos)
			var turn := rad_to_deg(_prev_basis.get_rotation_quaternion().angle_to(t.basis.get_rotation_quaternion()))
			max_step = maxf(max_step, step)
			max_turn = maxf(max_turn, turn)
			if _prev_step >= 0.0:
				max_dstep = maxf(max_dstep, absf(step - _prev_step))
				max_dturn = maxf(max_dturn, absf(turn - _prev_turn))
			_prev_step = step
			_prev_turn = turn
			if step > 0.3 or turn > 6.0:
				print("JUMP %s f%d step %.3f turn %.2f arm %.2f/%.2f yaw %.3f" % [label, f, step, turn, w.camera_rig.arm.get_hit_length(), w.camera_rig.arm.spring_length, w.camera_rig.yaw])
		_prev_pos = t.origin
		_prev_basis = t.basis
		if f % 6 == 0:
			print("CAM %s f%d pos %s yaw %.3f arm %.2f/%.2f" % [label, f, t.origin, w.camera_rig.yaw, w.camera_rig.arm.get_hit_length(), w.camera_rig.arm.spring_length])
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_viewport().get_texture().get_image().save_png("%s%s_%s_%03d.png" % [out, tag, label, f])
	print("SERIES %s: max step change %.3f m/frame, max turn change %.2f deg/frame" % [label, max_dstep, max_dturn])

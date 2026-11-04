extends "res://tests/demo_acceptance.gd"
## Automated input-only review recording, not a human playtest or an FPS benchmark.
## Reuses QA-01: one complete quest, then the no-quest/restart regression route.
## Adds the normal intro and an intentional real patrol detection/retry.
## Startup loading is NOT covered: QA-01 instantiates main.tscn directly.
## Do not use --capture: QA-01's optional front shots directly reposition the camera.

const ReviewIntro = preload("res://game/ui/intro.gd")
const ReviewCaught = preload("res://game/ui/caught_panel.gd")

var _review_event_index := 0
var _review_focus_fault := false

func check(scenario: int, ok: bool, label: String) -> bool:
	var passed := super.check(scenario, ok, label)
	_review_event_index += 1
	# Movie60 frame mapping is approximate until sampled JPEGs verify its offset.
	print("REVIEW_EVENT ", JSON.stringify({"process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(), "sim_frames": sim_frames, "index": _review_event_index, "scenario": scenario, "passed": passed, "message": label}))
	return passed

class ReviewDriver extends "res://tests/playthrough_driver.gd":
	func press_button(text: String, nav: StringName = &"ui_right", tries := 6) -> bool:
		var ok: bool = await super.press_button(text, nav, tries)
		if not ok:
			return false
		# Starting/restarting a world attaches the same intro used in the normal game.
		for i in 6000:
			var w: DemoWorld = world()
			var intro: Node = w.get_node_or_null("Intro") if is_instance_valid(w) else null
			if not is_instance_valid(intro) or not intro.is_running():
				if i > 0:
					print("REVIEW: normal intro finished after %d waited physics frames" % i)
				return true
			if i == 0:
				print("REVIEW: waiting for normal intro, without skip input")
			await frames(1)
		last_error = "normal intro did not finish within 100 simulated seconds"
		return false

	func click(control: Control) -> void:
		if control is Button and (control as Button).text == QuestLines.PROTOCOL_BUTTON:
			print("REVIEW_HOLD ", JSON.stringify({"message": "ordinary protocol reading hold before mouse click", "process_frame": Engine.get_process_frames(), "physics_frames": 360}))
			await frames(360)
		await super.click(control)

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	if "--capture" in OS.get_cmdline_user_args():
		push_error("Review recording forbids QA-01 camera fixture --capture")
		quit(2)
		return
	ReviewIntro.force_enabled = true
	ReviewCaught.force_enabled = true
	print("REVIEW: automated input-only; one full quest + restart regression + intentional detection/retry")
	print("REVIEW: startup loader excluded; intro/caught presentation enabled; fixed-fps/movie is NOT FPS evidence")
	super._initialize()

func _run() -> void:
	# Native initialization can reset flags set during SceneTree._initialize().
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	print("REVIEW_VERSION ", JSON.stringify({"wrapper_sha256": FileAccess.get_sha256("res://tools/capture/full_gameplay_review.gd"), "base_sha256": FileAccess.get_sha256("res://tests/demo_acceptance.gd"), "driver_sha256": FileAccess.get_sha256("res://tests/playthrough_driver.gd"), "quest_flow_sha256": FileAccess.get_sha256("res://game/mission/quest_flow.gd"), "dialog_panel_sha256": FileAccess.get_sha256("res://game/ui/dialog_panel.gd"), "finale_sha256": FileAccess.get_sha256("res://game/mission/finale.gd"), "project_sha256": FileAccess.get_sha256("res://project.godot")}))
	if not check(1, AudioServer.get_driver_name() == "Dummy", "review capture uses Dummy audio; no speaker output"):
		quit(2)
		return
	if DisplayServer.get_name() != "headless":
		for i in 2:
			await process_frame
		root.set_flag(Window.FLAG_NO_FOCUS, true)
		_review_native_focus_guard()
		if _review_focus_fault:
			return
		if not check(1, root.get_flag(Window.FLAG_NO_FOCUS) and not root.has_focus(), "review native root NoFocus=true and has_focus=false"):
			quit(3)
			return
		process_frame.connect(_review_native_focus_guard)
	else:
		print("SKIP review OS focus assertion: headless ignores NoFocus; not a native PASS")
	print("REVIEW_FOCUS_SCOPE ", JSON.stringify({"display": DisplayServer.get_name(), "no_focus": root.get_flag(Window.FLAG_NO_FOCUS), "has_focus": root.has_focus(), "scope": "native root OS window only; embedded GUI focus excluded", "every_process_frame": DisplayServer.get_name() != "headless"}))
	await super._run()

func _review_native_focus_guard() -> void:
	if _review_focus_fault or DisplayServer.get_name() == "headless":
		return
	if root.get_flag(Window.FLAG_NO_FOCUS) and not root.has_focus():
		return
	_review_focus_fault = true
	if drv != null:
		drv.release_all()
	print("REVIEW_FOCUS_GUARD_FAIL ", JSON.stringify({"process_frame": Engine.get_process_frames(), "no_focus": root.get_flag(Window.FLAG_NO_FOCUS), "has_focus": root.has_focus()}))
	push_error("Review root OS focus drift: reject movie; quit without freeing Main beneath pending input coroutines")
	quit(3)

func _pass_one() -> bool:
	drv = ReviewDriver.new(self, main)
	drv.on_frame = _monitor
	print("REVIEW: display=%s window=%s viewport=%s render_scale=%s" % [DisplayServer.get_name(), DisplayServer.window_get_size(), root.get_visible_rect().size, root.scaling_3d_scale])
	# Leave the menu visible long enough to read in a 60 fps movie.
	await drv.frames(180)
	return await super._pass_one()

func _monitor() -> void:
	var w: DemoWorld = main.world if is_instance_valid(main) else null
	var intro: Node = w.get_node_or_null("Intro") if is_instance_valid(w) else null
	if is_instance_valid(intro) and intro.is_running():
		# QA-01's HUD/marker invariants apply after the intro returns control.
		sim_frames += 1
		return
	super._monitor()

func _pass_two() -> void:
	await super._pass_two()
	if not failures.is_empty():
		return
	await _caught_retry()

func _caught_retry() -> void:
	print("--- REVIEW: INTENTIONAL DETECTION / RETRY ---")
	var w: DemoWorld = main.world
	if not check(1, await drv.walk_to(_car_stand(w)), "review caught: walk to car (%s)" % drv.last_error):
		return
	await drv.interact()
	await drv.frames(10)
	if not check(1, await drv.drive_path(Layout.ROUTE_DRIVE.slice(1)), "review caught: drive to kiosk (%s)" % drv.last_error):
		return
	await drv.brake()
	await drv.interact()
	await drv.frames(15)
	var panel: Node = w.get_node_or_null("CaughtPanel")
	var officer: Node3D = drv.officer()
	if not check(1, panel != null and officer != null, "review caught: real presentation and patrol exist"):
		return
	var state_before: StringName = w.mission.state
	var money_before: int = w.mission.money
	var detections_before: int = w.stealth.detections
	# Deliberately approach the live officer using normal walking input. No alert_now,
	# sensor edits, placement, mission calls, or success state are injected.
	for i in 2400:
		if w.is_stealth_failing():
			break
		var direction := officer.global_position - w.player.global_position
		direction.y = 0.0
		drv._walk_axes(direction.normalized())
		await drv.frames(1)
	drv.release_all()
	if not check(1, w.is_stealth_failing() and w.stealth.detections > detections_before, "review caught: live sensor detects intentional approach"):
		return
	for i in 600:
		if panel.is_open():
			break
		await drv.frames(1)
	if not check(1, panel.is_open(), "review caught: actual caught card opens"):
		return
	await drv.frames(240)
	if not check(1, await drv.press_button(ReviewCaught.AGAIN_TEXT), "review caught: retry selected through UI (%s)" % drv.last_error):
		return
	await drv.frames(30)
	check(1, not panel.is_open() and not paused and not w.is_stealth_failing(), "review caught: retry restores control")
	check(1, _near2(w.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "review caught: normal checkpoint reached")
	check(1, w.mission.state == state_before and w.mission.money == money_before, "review caught: retry preserves mission and money")
	check(1, await _can_walk(w), "review caught: can walk after retry")
	await drv.frames(180)

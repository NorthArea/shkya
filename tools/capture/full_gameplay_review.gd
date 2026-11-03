extends "res://tests/demo_acceptance.gd"
## Automated input-only review recording, not a human playtest or an FPS benchmark.
## Reuses QA-01: one complete quest, then the no-quest/restart regression route.
## Adds the normal intro and an intentional real patrol detection/retry.
## Startup loading is NOT covered: QA-01 instantiates main.tscn directly.
## Do not use --capture: QA-01's optional front shots directly reposition the camera.

const ReviewIntro = preload("res://game/ui/intro.gd")
const ReviewCaught = preload("res://game/ui/caught_panel.gd")

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

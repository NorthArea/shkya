extends SceneTree
## Agent display policy, physical fullscreen bounds and real late size events.
const DisplayProbe = preload("res://tools/fps_display.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen := Rect2i(0, 0, 3024, 1964)
	for height: int in [1736, 1834, 1898]:
		check(DisplayProbe.fullscreen_rect(screen, Rect2i(0, 66, 3024, height), "macOS") == Rect2i(0, 66, 3024, 1898),
			"Dock workarea height %d preserves physical fullscreen bounds" % height)
	check(DisplayProbe.fullscreen_rect(screen, Rect2i(100, 66, 2924, 1898), "macOS") == Rect2i(0, 66, 3024, 1898),
		"side Dock preserves fullscreen width")
	check(DisplayProbe.fullscreen_rect(Rect2i(-3024, -1964, 3024, 1964), Rect2i(-3024, -1898, 3024, 1834), "macOS")
		== Rect2i(-3024, -1898, 3024, 1898), "external screen offset keeps safe top local")
	check(DisplayProbe.fullscreen_rect(screen, Rect2i(0, 66, 3024, 1736), "Linux") == screen,
		"other platforms use native fullscreen display bounds")
	var hint := OS.get_environment("GODOT_WINDOW_MODE_WORKLOAD")
	check(hint in ["unspecified", "windowed", "fullscreen"], "real launcher preserves consumed engine window-mode flags")
	var observed_policy := DisplayProbe.window_policy(hint, false, "macOS")
	check(observed_policy.launcher_hint == hint and observed_policy.valid, "runtime policy consumes the actual launcher marker")
	check(DisplayProbe.window_policy("windowed", false, "macOS").declared_mode == "explicit_windowed",
		"explicit windowed diagnostic retains its limited declaration")
	check(DisplayProbe.window_policy("windowed", true, "macOS").declared_mode == "agent_borderless_fullscreen",
		"script full-coverage request qualifies borderless despite engine windowed transport")
	check(DisplayProbe.window_policy("fullscreen", false, "Linux").declared_mode == "native_fullscreen",
		"other platforms retain native fullscreen")
	check(not DisplayProbe.window_policy("bad", false, "macOS").valid, "unsupported launcher marker is rejected")
	var original_size := root.size
	var original_mode := root.mode
	root.size = Vector2i(1280, 720)
	var limited := DisplayProbe.window_policy("windowed", false, "macOS")
	DisplayProbe.apply_window(root, limited)
	check(root.size == Vector2i(1280, 720) and root.mode == original_mode,
		"explicit windowed policy does not resize or change the real test window")
	call_deferred("_late_resize")
	var settle: Dictionary = await DisplayProbe.settle(self, root, limited)
	check(root.size == Vector2i(960, 600) and not settle.reapplied,
		"post-startup evidence observes late native size changes without mutating a windowed diagnostic")
	check(settle.before.window_size == [960, 600] and settle.after.window_size == [960, 600],
		"settled evidence records concrete size after event processing")
	check(settle.elapsed_ms >= 1000 and settle.elapsed_ms < 5000, "settle waits for OS events with a bounded delay")
	var capture := DisplayProbe.InternalSizeCapture.new()
	check(capture.snapshot() == Vector2i.ZERO, "no callback cannot fabricate actual internal render dimensions")
	var no_camera: Dictionary = await DisplayProbe.capture_internal_size(self, root)
	check(no_camera.status == "unavailable" and no_camera.reason == "no_active_camera",
		"missing active 3D camera records unavailable internal size")
	root.size = original_size
	print("FULLSCREEN_SETTLE_TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _late_resize() -> void:
	root.size = Vector2i(960, 600)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

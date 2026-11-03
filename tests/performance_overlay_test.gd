extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PERF_HUD: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "res://game/ui/frame_window.gd"
	check(ResourceLoader.exists(path), "rolling wall-clock frame statistics exist")
	if failures:
		quit(1)
		return
	var window: RefCounted = load(path).new()
	check(window.snapshot().is_empty(), "empty window has no invented FPS")
	window.add_interval_usec(0)
	window.add_interval_usec(-10)
	check(window.snapshot().is_empty(), "invalid intervals cannot divide by zero or corrupt FPS")
	window.add_interval_usec(10000)
	window.add_interval_usec(30000)
	var stats: Dictionary = window.snapshot()
	check(is_equal_approx(stats.fps, 50.0) and is_equal_approx(stats.frame_ms, 30.0), "FPS uses elapsed time; frame time is the latest real interval")
	check(is_equal_approx(stats.worst_ms, 30.0), "recent outlier remains visible")
	for i in 10000:
		window.add_interval_usec(5000)
	stats = window.snapshot()
	check(window.count == window.CAPACITY and window.intervals.size() == window.CAPACITY, "long sessions retain bounded storage")
	check(is_equal_approx(stats.fps, 200.0) and is_equal_approx(stats.worst_ms, 5.0), "expired outlier leaves the rolling window")
	var overlay: CanvasLayer = load("res://game/ui/performance_overlay.gd").new()
	root.add_child(overlay)
	overlay.set_process(false)
	overlay.sample_at(1000000)
	overlay.sample_at(1010000)
	var text: String = overlay.metrics.text
	overlay.sample_at(1020000)
	check(overlay.refresh_count == 1 and overlay.metrics.text == text, "UI refresh is throttled independently of frame collection")
	overlay.sample_at(1260000)
	check(overlay.refresh_count == 2 and overlay.frames.count == 3, "outlier is collected while text updates at most four times per second")
	check(overlay.panel.visible and overlay.panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "panel is visible by default and cannot capture clicks")
	overlay.free()
	overlay = load("res://game/ui/performance_overlay.gd").new()
	root.add_child(overlay)
	var before: int = overlay.frames.count
	paused = true
	overlay.set_process(true)
	await process_frame
	await process_frame
	await process_frame
	check(overlay.frames.count > before, "sampling continues while the game is paused")
	paused = false
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	overlay._unhandled_key_input(key)
	check(not overlay.panel.visible, "F3 hides the panel")
	key.echo = true
	overlay._unhandled_key_input(key)
	check(not overlay.panel.visible, "held F3 does not repeatedly toggle")
	key.echo = false
	overlay._unhandled_key_input(key)
	check(overlay.panel.visible, "F3 restores the panel")
	overlay.queue_free()
	await process_frame
	print("PERF_HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

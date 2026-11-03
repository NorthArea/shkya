extends SceneTree
## Synthetic dispatch boundaries; headless evidence only, never FPS acceptance.

var checks := 0
var failures := 0

class DelayFixture extends Node:
	var process_window := []
	var physics_window := []
	var deferred_window := []
	var deferred_done := false

	func _process(_delta: float) -> void:
		if process_window.is_empty():
			process_window = [Time.get_ticks_usec(), 0, Engine.get_process_frames()]
			OS.delay_usec(4000)
			process_window[1] = Time.get_ticks_usec()
			_delay_deferred.call_deferred()

	func _physics_process(_delta: float) -> void:
		if physics_window.is_empty():
			physics_window = [Time.get_ticks_usec(), 0, Engine.get_physics_frames()]
			OS.delay_usec(5000)
			physics_window[1] = Time.get_ticks_usec()

	func _delay_deferred() -> void:
		deferred_window = [Time.get_ticks_usec(), 0, Engine.get_process_frames()]
		OS.delay_usec(6000)
		deferred_window[1] = Time.get_ticks_usec()
		deferred_done = true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not check(FileAccess.file_exists("res://tools/frame_dispatch_trace.gd"), "dispatch tracer exists"):
		_finish()
		return
	var script: Variant = load("res://tools/frame_dispatch_trace.gd")
	var before := root.get_child_count()
	var off: Dictionary = script.install(root, "off")
	check(off.valid and off.trace == null and root.get_child_count() == before,
		"off creates no trace or sentinel nodes")
	var invalid: Dictionary = script.install(root, "maybe")
	check(not invalid.valid and root.get_child_count() == before, "unsupported mode has no scene side effects")
	var blocker := Node.new()
	blocker.process_priority = 2147483647
	root.add_child(blocker)
	var conflict: Dictionary = script.install(root, "on")
	check(not conflict.valid and conflict.trace == null and root.get_child_count() == before + 1,
		"reserved priority collision rejects installation without extra nodes")
	blocker.free()
	var installed: Dictionary = script.install(root, "on", 256)
	if not check(installed.valid and installed.trace != null, "on installs bounded sentinels"):
		_finish()
		return
	var trace: Node = installed.trace
	await process_frame
	var fixture := DelayFixture.new()
	root.add_child(fixture)
	var events: Array = []
	var deadline := Time.get_ticks_usec() + 1000000
	while (not fixture.deferred_done or fixture.physics_window.is_empty()) and Time.get_ticks_usec() < deadline:
		await process_frame
		events.append_array(trace.take_sample().events)
	await process_frame
	events.append_array(trace.take_sample().events)
	check(not fixture.process_window.is_empty() and not fixture.physics_window.is_empty() and fixture.deferred_done,
		"real SceneTree executes process, physics and deferred fixture")
	if not fixture.process_window.is_empty():
		check(_enclosed(events, script.PROCESS_BEGIN, script.PROCESS_END, fixture.process_window, 2),
			"4ms process delay is enclosed by matching process-frame sentinels")
	if not fixture.physics_window.is_empty():
		check(_enclosed(events, script.PHYSICS_BEGIN, script.PHYSICS_END, fixture.physics_window, 3),
			"5ms physics delay is enclosed by matching physics-frame sentinels")
	if fixture.deferred_done:
		check(not _enclosed(events, script.PROCESS_BEGIN, script.PROCESS_END, fixture.deferred_window, 2),
			"6ms deferred delay stays outside process callback dispatch")
		check(_enclosed(events, script.PROCESS_SIGNAL, script.PROCESS_SIGNAL, fixture.deferred_window, -1),
			"deferred delay belongs to one raw process-signal interval")
	var ordered := true
	for i in range(1, events.size()):
		ordered = ordered and events[i][1] >= events[i - 1][1]
	check(ordered, "absolute event ticks preserve order across drained samples")
	var late := Node.new()
	late.process_physics_priority = -2147483648
	root.add_child(late)
	check(not trace.take_sample().valid, "new runtime node cannot silently occupy a reserved physics priority")
	late.free()
	fixture.free()
	trace.free()
	var small: Dictionary = script.install(root, "on", 4)
	trace = small.trace
	await process_frame
	await process_frame
	await process_frame
	var bounded: Dictionary = trace.take_sample()
	check(bounded.events.size() == 4 and bounded.dropped_events > 0 and not bounded.valid,
		"overflow remains bounded and explicitly invalidates phase attribution")
	check(trace.take_sample().events.is_empty(), "drain does not repeat stale events")
	trace.free()
	check(root.get_child_count() == before, "free removes both sentinels")
	_finish()

func _enclosed(events: Array, begin: int, end: int, window: Array, frame_column: int) -> bool:
	for a: Array in events:
		if a[0] != begin or a[1] > window[0]:
			continue
		for b: Array in events:
			if b[0] != end or b[1] <= a[1]:
				continue
			if frame_column < 0:
				return b[1] >= window[1]
			if a[frame_column] == window[2] and b[frame_column] == window[2] and b[1] >= window[1]:
				return true
	return false

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

func _finish() -> void:
	print("FRAME_DISPATCH_TRACE_TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

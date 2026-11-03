extends SceneTree
## MOTION-01: spikes must remain visible even when the average meets the target.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe: Variant = load("res://tools/fps_probe.gd")
	if not check(probe.has_method("frame_stats"), "FPS runner exposes independently testable raw-frame statistics"):
		_finish()
		return
	var spike: Dictionary = probe.call("frame_stats", [10000, 10000, 10000, 50000], 60)
	check(is_equal_approx(spike.average_fps, 50.0), "average derives from elapsed time, not averaged instantaneous FPS")
	check(is_equal_approx(spike.minimum_fps, 20.0), "one slow frame remains visible as the minimum")
	check(spike.over_budget_frames == 1, "one frame breaches the current target")
	check(spike.worst_frame_us == 50000 and spike.p99_frame_us == 50000, "short sample p99 includes its slowest frame")
	check(spike.target_met == false, "one breach prevents target acceptance")
	var hidden_spike: Dictionary = probe.call("frame_stats", [1000, 1000, 1000, 50000], 60)
	check(hidden_spike.average_fps > 60.0 and not hidden_spike.target_met, "good average cannot hide a serious hitch")
	var stable: Dictionary = probe.call("frame_stats", [10000, 10000, 10000, 10000], 80)
	check(stable.target_met and stable.over_budget_frames == 0, "every frame within the budget meets the sampled target")
	var boundary: Dictionary = probe.call("frame_stats", [12500, 12500], 80)
	check(boundary.target_met, "a frame exactly on the 80 FPS budget is allowed")
	var empty: Dictionary = probe.call("frame_stats", [], 60)
	check(not empty.target_met and empty.frames == 0, "no samples cannot accept a level")
	var invalid: Dictionary = probe.call("frame_stats", [10000, 0, -1], 60)
	check(not invalid.target_met and invalid.invalid_frames == 2, "invalid raw intervals cannot turn into passing evidence")
	_finish()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

func _finish() -> void:
	print("FPS_PROBE_TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

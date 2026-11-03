extends RefCounted
## Fixed recent-frame window. Collection is O(1); only the 4 Hz UI scans for the peak.
const CAPACITY := 240
var intervals := PackedInt64Array()
var count := 0
var _next := 0
var _total_usec := 0
var _last_usec := 0

func _init() -> void:
	intervals.resize(CAPACITY)

func add_interval_usec(elapsed: int) -> void:
	if elapsed <= 0:
		return
	_total_usec -= intervals[_next]
	intervals[_next] = elapsed
	_total_usec += elapsed
	_last_usec = elapsed
	_next = (_next + 1) % CAPACITY
	count = mini(count + 1, CAPACITY)

func snapshot() -> Dictionary:
	if count == 0:
		return {}
	var worst := 0
	for i in count:
		worst = maxi(worst, intervals[i])
	return {"fps": count * 1000000.0 / _total_usec,
		"frame_ms": _last_usec / 1000.0, "worst_ms": worst / 1000.0}

extends Node
## Opt-in wall boundaries, not CPU/GPU timings. No renderer queries or per-event I/O.

const FIRST := -2147483648
const LAST := 2147483647
const PHYSICS_SIGNAL := 0
const PHYSICS_BEGIN := 1
const PHYSICS_END := 2
const PROCESS_SIGNAL := 3
const PROCESS_BEGIN := 4
const PROCESS_END := 5
const DRAW_BEGIN := 6
const DRAW_END := 7
const EVENT_NAMES := ["physics_signal", "physics_begin", "physics_end", "process_signal",
	"process_begin", "process_end", "draw_begin", "draw_end"]

var _buffer := PackedInt64Array()
var _used := 0
var _dropped := 0
var _conflicts: Array[String] = []
var _end: Node

class EndSentinel extends Node:
	var trace: Node
	func _process(_delta: float) -> void:
		trace.record(PROCESS_END)
	func _physics_process(_delta: float) -> void:
		trace.record(PHYSICS_END)

static func install(parent: Node, requested: String, capacity := 256) -> Dictionary:
	if requested not in ["on", "off"]:
		return {"valid": false, "trace": null, "reason": "dispatch-trace must be on or off"}
	if requested == "off":
		return {"valid": true, "trace": null}
	var script: Script = load("res://tools/frame_dispatch_trace.gd")
	var trace: Node = script.new()
	trace.validate_priorities(parent)
	if not trace._conflicts.is_empty():
		var reason := "dispatch trace reserved priority collision: " + str(trace._conflicts)
		trace.free()
		return {"valid": false, "trace": null, "reason": reason}
	trace._buffer.resize(clampi(capacity, 4, 4096) * 4)
	trace.name = "FPSDispatchTrace"
	trace.process_priority = FIRST
	trace.process_physics_priority = FIRST
	parent.add_child(trace)
	return {"valid": true, "trace": trace}

func _ready() -> void:
	_end = EndSentinel.new()
	_end.name = "End"
	_end.trace = self
	_end.process_priority = LAST
	_end.process_physics_priority = LAST
	add_child(_end)
	get_tree().physics_frame.connect(_physics_signal)
	get_tree().process_frame.connect(_process_signal)
	get_tree().node_added.connect(_node_added)
	RenderingServer.frame_pre_draw.connect(_draw_begin)
	RenderingServer.frame_post_draw.connect(_draw_end)

func validate_priorities(node: Node) -> void:
	if node == self or node == _end:
		return
	_check_priority(node)
	for child: Node in node.get_children():
		validate_priorities(child)

func _check_priority(node: Node) -> void:
	if node.process_priority in [FIRST, LAST] or node.process_physics_priority in [FIRST, LAST]:
		var path := str(node.get_path())
		if path not in _conflicts and _conflicts.size() < 16:
			_conflicts.append(path)

func _node_added(node: Node) -> void:
	_check_priority(node)
	if not node.is_node_ready():
		node.ready.connect(_check_priority.bind(node), CONNECT_ONE_SHOT)

func record(kind: int) -> void:
	if _used * 4 >= _buffer.size():
		_dropped += 1
		return
	var offset := _used * 4
	_buffer[offset] = kind
	_buffer[offset + 1] = Time.get_ticks_usec()
	_buffer[offset + 2] = Engine.get_process_frames()
	_buffer[offset + 3] = Engine.get_physics_frames()
	_used += 1

func take_sample() -> Dictionary:
	var events: Array = []
	events.resize(_used)
	for i in _used:
		var offset := i * 4
		events[i] = [_buffer[offset], _buffer[offset + 1], _buffer[offset + 2], _buffer[offset + 3]]
	var result := {"events": events, "dropped_events": _dropped,
		"valid": _dropped == 0 and _conflicts.is_empty()}
	if not _conflicts.is_empty():
		result["priority_conflicts"] = _conflicts.duplicate()
	_used = 0
	_dropped = 0
	return result

func metadata() -> Dictionary:
	return {"event_columns": ["kind", "tick_us", "process_frame_id", "physics_frame_id"],
		"event_names": EVENT_NAMES, "capacity_per_sample": _buffer.size() / 4,
		"scope": "events since previous sample drain; dispatch brackets exclude deferred work; wall clocks include waits/preemption; priorities checked on install, node addition/ready and motion-batch entry"}

func _process(_delta: float) -> void:
	record(PROCESS_BEGIN)

func _physics_process(_delta: float) -> void:
	record(PHYSICS_BEGIN)

func _physics_signal() -> void:
	record(PHYSICS_SIGNAL)

func _process_signal() -> void:
	record(PROCESS_SIGNAL)

func _draw_begin() -> void:
	record(DRAW_BEGIN)

func _draw_end() -> void:
	record(DRAW_END)

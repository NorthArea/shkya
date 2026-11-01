extends RefCounted
## Broadcast position belongs to world time, independently of receiver playback.

var index := 0
var position := 0.0
var revision := 0
var _lengths: Array[float] = []
var _cycle_length := 0.0

func _init(lengths: Array[float]) -> void:
	assert(not lengths.is_empty())
	_lengths = lengths.duplicate()
	for length in _lengths:
		assert(length > 0.0)
		_cycle_length += length

func advance(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	var before := revision
	var cycles := floori(seconds / _cycle_length)
	revision += cycles * _lengths.size()
	position += seconds - cycles * _cycle_length
	while position >= _lengths[index]:
		position -= _lengths[index]
		index = (index + 1) % _lengths.size()
		revision += 1
	return revision - before

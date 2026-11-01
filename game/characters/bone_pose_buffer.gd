extends RefCounted
## Local physical poses only; render interpolation never advances the solver.

var _skeleton: Skeleton3D
var _previous: Array[Transform3D] = []
var _current: Array[Transform3D] = []

func clear() -> void:
	_skeleton = null
	_previous.clear()
	_current.clear()

func capture(skeleton: Skeleton3D) -> void:
	if not _matches(skeleton):
		clear()
		_skeleton = skeleton
		for bone in skeleton.get_bone_count():
			_current.append(skeleton.get_bone_pose(bone))
		_previous = _current.duplicate()
		return
	_previous = _current
	_current = []
	for bone in skeleton.get_bone_count():
		_current.append(skeleton.get_bone_pose(bone))

func restore_current(skeleton: Skeleton3D) -> void:
	if not _matches(skeleton):
		clear()
		return
	for bone in _current.size():
		skeleton.set_bone_pose(bone, _current[bone])

func apply(skeleton: Skeleton3D, fraction: float) -> void:
	if not _matches(skeleton):
		clear()
		return
	var weight := clampf(fraction, 0.0, 1.0)
	for bone in _current.size():
		skeleton.set_bone_pose(bone, _previous[bone].interpolate_with(_current[bone], weight))

func _matches(skeleton: Skeleton3D) -> bool:
	return is_instance_valid(_skeleton) and skeleton == _skeleton and _current.size() == skeleton.get_bone_count()

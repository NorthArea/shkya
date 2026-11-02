extends RefCounted
## Low-sedan correction of a freshly sampled Driving clip, in glTF skeleton space.
## Root placement, bone translations/scales and the authored arm animation stay with callers.
const TORSO_RECLINE := deg_to_rad(32.0)
const THIGH_RISE := deg_to_rad(26.0)
const SHIN_FORWARD := deg_to_rad(35.0)
const PELVIS_FORWARD := deg_to_rad(12.0)

static func apply_pose(skeleton: Skeleton3D) -> void:
	var spine := skeleton.find_bone("Spine")
	var neck := skeleton.find_bone("Neck")
	var hips := skeleton.find_bone("Hips")
	assert(hips >= 0 and spine >= 0 and neck >= 0, "Imported driving requires the canonical humanoid skeleton")
	skeleton.force_update_all_bone_transforms()
	var neck_rotation := skeleton.get_bone_global_pose(neck).basis.get_rotation_quaternion()
	# The generic clip's posterior pelvic tilt drives the rear coat hem into a
	# low cushion. Tilt the pelvis forward before reclining the connected spine.
	_aim_child(skeleton, hips, spine, Vector3(0.0, cos(PELVIS_FORWARD), sin(PELVIS_FORWARD)))
	skeleton.force_update_all_bone_transforms()
	var spine_at := skeleton.get_bone_global_pose(spine).origin
	var neck_at := skeleton.get_bone_global_pose(neck).origin
	var upper_axis := Vector3(0.0, cos(TORSO_RECLINE), -sin(TORSO_RECLINE))
	_aim_axis(skeleton, spine, neck_at - spine_at, upper_axis)
	# Keep the clip's look direction while the connected neck follows the reclined torso.
	_set_global_rotation(skeleton, neck, neck_rotation)
	for side: String in ["Left", "Right"]:
		var thigh := skeleton.find_bone(side + "UpperLeg")
		var shin := skeleton.find_bone(side + "LowerLeg")
		var foot := skeleton.find_bone(side + "Foot")
		var toes := skeleton.find_bone(side + "Toes")
		assert(thigh >= 0 and shin >= 0 and foot >= 0 and toes >= 0)
		var thigh_rest := skeleton.get_bone_global_rest(shin).origin - skeleton.get_bone_global_rest(thigh).origin
		var sagittal_length := Vector2(thigh_rest.y, thigh_rest.z).length()
		var thigh_axis := Vector3(thigh_rest.x, sagittal_length * sin(THIGH_RISE), sagittal_length * cos(THIGH_RISE))
		_aim_child(skeleton, thigh, shin, thigh_axis)
		_aim_child(skeleton, shin, foot, Vector3(0.0, -cos(SHIN_FORWARD), sin(SHIN_FORWARD)))
		_set_global_rotation(skeleton, foot, skeleton.get_bone_global_rest(foot).basis.get_rotation_quaternion())
		_set_global_rotation(skeleton, toes, skeleton.get_bone_global_rest(toes).basis.get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

static func _aim_child(skeleton: Skeleton3D, bone: int, child: int, direction: Vector3) -> void:
	skeleton.force_update_all_bone_transforms()
	var current_axis := skeleton.get_bone_global_pose(child).origin - skeleton.get_bone_global_pose(bone).origin
	_aim_axis(skeleton, bone, current_axis, direction)

static func _aim_axis(skeleton: Skeleton3D, bone: int, current_axis: Vector3, direction: Vector3) -> void:
	var current := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	_set_global_rotation(skeleton, bone, Quaternion(current_axis.normalized(), direction.normalized()) * current)

static func _set_global_rotation(skeleton: Skeleton3D, bone: int, rotation: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * rotation).normalized())

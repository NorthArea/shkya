extends SceneTree
## Pure action-library contract; no Main, physics, original clips or art acceptance.
const Pose = preload("res://game/characters/character_action_pose.gd")
const ROLES := {"hips": 1, "spine": 2, "head": 3,
	"upper_arm_l": 4, "lower_arm_l": 5, "hand_l": 6,
	"upper_arm_r": 7, "lower_arm_r": 8, "hand_r": 9,
	"thigh_l": 10, "knee_l": 11, "ankle_l": 14,
	"thigh_r": 12, "knee_r": 13, "ankle_r": 15, "root": 0}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHARACTER05_ACTION_UNIT: " + message)

func _run() -> void:
	var grips := {"_l": Transform3D(Basis(Vector3.UP, 0.3), Vector3(8, 1.4, -12)),
		"_r": Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(8, 1.0, -12))}
	for kind: StringName in [&"chat", &"listen", &"dig", &"flail", &"down", &"getup"]:
		var request := {"kind": kind, "phase": 0.4, "stroke": 0.7, "reaction": 0.2,
			"speaker": true, "weight": 1.0, "grips": grips}
		var saved := request.duplicate(true)
		var pose: Dictionary = Pose.sample(request, ROLES)
		check(pose.valid and pose.active and not pose.bone_offsets.is_empty(), String(kind) + " supplies an explicit masked bone pose")
		check(request == saved and grips == saved.grips, String(kind) + " does not mutate owner snapshot or world tool targets")
		check(pose == Pose.sample(request, ROLES), String(kind) + " is deterministic without a hidden clock or transition state")
		check(not pose.bone_offsets.has(ROLES.root), String(kind) + " never writes physical/root motion")
		var finite := true
		for offset: Transform3D in pose.bone_offsets.values(): finite = finite and offset.is_finite()
		check(finite, String(kind) + " returns finite local bone offsets")
		var clear: Dictionary = Pose.sample({"kind": &"none"}, ROLES)
		check(clear.valid and not clear.active and clear.bone_offsets.is_empty() and clear.grips.is_empty(), String(kind) + " to none immediately releases every pose/IK target")
	var speaker: Dictionary = Pose.sample({"kind": &"chat", "phase": 0.3, "speaker": true}, ROLES)
	var listener: Dictionary = Pose.sample({"kind": &"chat", "phase": 0.3, "speaker": false}, ROLES)
	check(listener.kind == &"listen" and listener.bone_offsets != speaker.bone_offsets, "owner's speaker flag distinguishes listening from speaking")
	check(not speaker.full_body and not listener.full_body and not speaker.bone_offsets.has(ROLES.thigh_l), "conversation leaves grounded gait/leg authority intact")
	var dig: Dictionary = Pose.sample({"kind": &"dig", "stroke": 0.0, "grips": grips}, ROLES)
	var contact: Dictionary = Pose.sample({"kind": &"dig", "stroke": 1.0, "grips": grips}, ROLES)
	check(dig.valid and contact.valid and dig.bone_offsets != contact.bone_offsets, "owner stroke drives the work gesture")
	for suffix: String in ["_l", "_r"]:
		check(dig.grips[suffix].target == grips[suffix] and contact.grips[suffix].target == grips[suffix], "dig preserves exact world-space tool target: " + suffix)
		check(contact.grips[suffix].hand_bone == ROLES["hand" + suffix], "dig resolves hand through supplied active rig roles: " + suffix)
	check(not contact.full_body and not contact.bone_offsets.has(ROLES.knee_l), "dig does not replace ground contacts")
	var blended: Dictionary = Pose.sample({"kind": &"dig", "stroke": 1.0, "weight": 0.5, "grips": grips}, ROLES)
	var half_spine: Transform3D = blended.bone_offsets[ROLES.spine]
	var full_spine: Transform3D = contact.bone_offsets[ROLES.spine]
	check(half_spine.basis.get_rotation_quaternion().get_angle() < full_spine.basis.get_rotation_quaternion().get_angle(), "blend weight scales the offset relative to fresh base, not an accumulated pose")
	check(blended.grips._l.weight == 0.5 and blended.grips._l.target == grips._l, "IK receives its weight separately without scaling the world-space target")
	var start: Dictionary = Pose.sample({"kind": &"getup", "phase": 0.0}, ROLES)
	var end: Dictionary = Pose.sample({"kind": &"getup", "phase": 1.0}, ROLES)
	check(start.full_body and start.bone_offsets.has(ROLES.knee_l) and start.bone_offsets.has(ROLES.ankle_l), "recovery uses distinct semantic knee and ankle roles")
	var neutral := true
	for offset: Transform3D in end.bone_offsets.values(): neutral = neutral and offset.is_equal_approx(Transform3D.IDENTITY)
	check(neutral and start.bone_offsets != end.bone_offsets, "getup reaches fresh base pose at owner phase one")
	var repeat: Dictionary = Pose.sample({"kind": &"flail", "phase": 0.0}, ROLES)
	check(repeat == Pose.sample({"kind": &"flail", "phase": 0.0}, ROLES), "getup to repeated flail carries no previous offset or phase")
	var remapped := ROLES.duplicate()
	for role: String in remapped: remapped[role] += 100
	var remapped_pose: Dictionary = Pose.sample({"kind": &"getup", "phase": 0.0}, remapped)
	check(remapped_pose.valid and remapped_pose.bone_offsets.has(remapped.knee_l) and not remapped_pose.bone_offsets.has(ROLES.knee_l), "active adapter mapping determines bone indices, never authored foot indices")
	var missing := ROLES.duplicate()
	missing.erase("ankle_l")
	var bad: Dictionary = Pose.sample({"kind": &"getup", "phase": 0.2}, missing)
	check(not bad.valid and not bad.active and bad.bone_offsets.is_empty(), "missing recovery role rejects the whole pose instead of applying half a body")
	bad = Pose.sample({"kind": &"dig", "stroke": 0.4}, ROLES)
	check(not bad.valid and bad.grips.is_empty(), "work never invents missing world-space tool grips")
	bad = Pose.sample({"kind": &"invented_action"}, ROLES)
	check(not bad.valid and bad.bone_offsets.is_empty(), "unknown action cannot silently become another activity")
	bad = Pose.sample({"kind": &"flail", "phase": NAN}, ROLES)
	check(not bad.valid and not bad.active and bad.bone_offsets.is_empty(), "nonfinite owner phase cannot produce invalid bone transforms")
	var zero: Dictionary = Pose.sample({"kind": &"getup", "phase": 0.2, "weight": 0.0}, ROLES)
	check(zero.valid and not zero.active and zero.bone_offsets.is_empty(), "zero weight does not retain a previous action")
	var clamped: Dictionary = Pose.sample({"kind": &"getup", "phase": 2.0}, ROLES)
	check(clamped.bone_offsets == end.bone_offsets, "owner phase is bounded at recovery endpoint")
	print("CHARACTER05_ACTION_UNIT: %d checks, %d failures; pure helper only; actual consumer, skinned palms, repeated knock physics and GPU NOT_RUN" % [checks, failures])
	quit(0 if failures == 0 else 1)

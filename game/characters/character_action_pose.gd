extends RefCounted
## Stateless own-authored gestures. Original SHAR authored clips/curves are UNKNOWN.
## Resident/Life supply already selected actions and canonical phases; this helper
## never advances time, chooses AI states, moves props, or writes a Skeleton3D.
## Apply each offset once relative to this frame's fresh base pose, after gait.
## Roles map semantic names to ACTIVE bone indices; knee/ankle are never inferred
## from historical author14 foot_* names. Grip transforms remain in world space.

const ACTIONS := [&"none", &"chat", &"listen", &"dig", &"flail", &"down", &"getup"]
const UPPER_ROLES := ["spine", "head", "upper_arm_l", "lower_arm_l", "upper_arm_r", "lower_arm_r"]
const RECOVERY_ROLES := ["hips", "spine", "head", "upper_arm_l", "lower_arm_l", "hand_l",
	"upper_arm_r", "lower_arm_r", "hand_r", "thigh_l", "knee_l", "ankle_l", "thigh_r", "knee_r", "ankle_r"]

## request: kind:StringName, phase/stroke/reaction/weight:float in0..1,
## speaker:bool, grips:{"_l":Transform3D,"_r":Transform3D} for dig only.
## result: valid/active/full_body:bool, kind:StringName, error:String,
## bone_offsets:{active_bone:int -> Transform3D}, grips:{suffix -> descriptor}.
## Offsets already include weight; compose fresh_bone_pose * offset once.
## Grip descriptor: target:world Transform3D, weight:float, upper_bone/lower_bone/
## hand_bone:int. Caller owns actual IK and must use posed parent transforms.
static func sample(request: Dictionary, roles: Dictionary) -> Dictionary:
	var kind := StringName(request.get("kind", &"none"))
	if kind not in ACTIONS: return _empty(kind, false, "unsupported_kind")
	for field: String in ["phase", "stroke", "reaction", "weight"]:
		if not is_finite(float(request.get(field, 1.0 if field == "weight" else 0.0))):
			return _empty(kind, false, "nonfinite_" + field)
	var weight := clampf(float(request.get("weight", 1.0)), 0.0, 1.0)
	if kind == &"none" or weight == 0.0: return _empty(kind)
	if kind == &"chat" and not bool(request.get("speaker", true)): kind = &"listen"
	var phase := clampf(float(request.get("phase", 0.0)), 0.0, 1.0)
	var stroke := clampf(float(request.get("stroke", 0.0)), 0.0, 1.0)
	var reaction := clampf(float(request.get("reaction", 0.0)), 0.0, 1.0)
	var full_body := kind in [&"flail", &"down", &"getup"]
	var required: Array = RECOVERY_ROLES if full_body else ["spine", "head"] if kind == &"listen" else UPPER_ROLES.duplicate()
	if kind == &"dig": required.append_array(["hand_l", "hand_r"])
	var seen := {}
	for role: String in required:
		if not roles.has(role) or typeof(roles[role]) != TYPE_INT or int(roles[role]) < 0:
			return _empty(kind, false, "missing_role:" + role)
		if seen.has(roles[role]): return _empty(kind, false, "aliased_role:" + role)
		seen[roles[role]] = true
	var grips: Dictionary = request.get("grips", {})
	if kind == &"dig":
		for suffix: String in ["_l", "_r"]:
			if not grips.has(suffix) or typeof(grips[suffix]) != TYPE_TRANSFORM3D:
				return _empty(kind, false, "missing_grip:" + suffix)
			var target: Transform3D = grips[suffix]
			if not target.is_finite(): return _empty(kind, false, "nonfinite_grip:" + suffix)
	var rotations := {}
	var translations := {}
	# These bounded local curves are original work, not measured SHAR animation.
	match kind:
		&"chat":
			var beat := sin(phase * PI)
			rotations = {"spine": Vector3(0, beat * 0.045, 0), "head": Vector3(beat * 0.07, -beat * 0.035, 0),
				"upper_arm_r": Vector3(-beat * 0.24, 0, -beat * 0.12), "lower_arm_r": Vector3(-beat * 0.42, 0, 0),
				"upper_arm_l": Vector3(-beat * 0.05, 0, beat * 0.04), "lower_arm_l": Vector3(-beat * 0.12, 0, 0)}
		&"listen":
			var nod := sin(phase * PI)
			rotations = {"spine": Vector3(0, 0, 0), "head": Vector3(nod * 0.09, 0, nod * 0.025)}
		&"dig":
			# Existing tool trajectory and its contact/sound phase stay authoritative.
			# Hands are solved to the supplied grips after these torso offsets.
			rotations = {"spine": Vector3(-0.10 - stroke * 0.19, 0, 0), "head": Vector3(0.05 + stroke * 0.08, 0, 0)}
		&"flail":
			var beat := sin(phase * TAU * 2.0)
			rotations = {"hips": Vector3(beat * 0.07, 0, 0), "spine": Vector3(-0.12, 0, beat * 0.07), "head": Vector3(0.08, 0, -beat * 0.08)}
			for suffix: String in ["_l", "_r"]:
				var side := 1.0 if suffix == "_l" else -1.0
				rotations["upper_arm" + suffix] = Vector3(-0.45 + side * beat * 0.24, 0, side * 0.72)
				rotations["lower_arm" + suffix] = Vector3(-0.45 - side * beat * 0.16, 0, 0)
				rotations["hand" + suffix] = Vector3(side * beat * 0.14, 0, 0)
				rotations["thigh" + suffix] = Vector3(-0.28 + side * beat * 0.15, 0, side * 0.08)
				rotations["knee" + suffix] = Vector3(0.55 + side * beat * 0.18, 0, 0)
				rotations["ankle" + suffix] = Vector3(-0.16, 0, 0)
		&"down", &"getup":
			var folded := 1.0 - smoothstep(0.0, 1.0, phase) if kind == &"getup" else 1.0
			var push := sin(phase * PI) if kind == &"getup" else 0.0
			rotations = {"hips": Vector3(-folded * 0.08, 0, 0), "spine": Vector3(-folded * 0.18 - push * 0.16, 0, 0),
				"head": Vector3(folded * 0.12, 0, 0)}
			translations["hips"] = Vector3(0, -push * 0.025, 0)
			for suffix: String in ["_l", "_r"]:
				var side := 1.0 if suffix == "_l" else -1.0
				rotations["upper_arm" + suffix] = Vector3(-folded * 0.30 - push * 0.30, 0, side * folded * 0.28)
				rotations["lower_arm" + suffix] = Vector3(-folded * 0.48 - push * 0.20, 0, 0)
				rotations["hand" + suffix] = Vector3(push * 0.10, 0, 0)
				rotations["thigh" + suffix] = Vector3(-folded * 0.44 - push * 0.16, 0, 0)
				rotations["knee" + suffix] = Vector3(folded * 0.72 + push * 0.24, 0, 0)
				rotations["ankle" + suffix] = Vector3(-folded * 0.18, 0, 0)
	if not full_body and reaction > 0.0:
		rotations["head"] = Vector3(rotations.get("head", Vector3.ZERO)) + Vector3(-reaction * 0.08, 0, reaction * 0.12)
		rotations["spine"] = Vector3(rotations.get("spine", Vector3.ZERO)) + Vector3(0, 0, -reaction * 0.045)
	var result := _empty(kind)
	result.active = true
	result.full_body = full_body
	for role: String in rotations:
		var rotation := Quaternion.IDENTITY.slerp(Quaternion.from_euler(rotations[role]), weight)
		var translation: Vector3 = translations.get(role, Vector3.ZERO)
		result.bone_offsets[roles[role]] = Transform3D(Basis(rotation), translation * weight)
	if kind == &"dig":
		for suffix: String in ["_l", "_r"]:
			result.grips[suffix] = {"target": grips[suffix], "weight": weight,
				"upper_bone": roles["upper_arm" + suffix], "lower_bone": roles["lower_arm" + suffix], "hand_bone": roles["hand" + suffix]}
	return result

static func _empty(kind: StringName, valid := true, error := "") -> Dictionary:
	return {"kind": kind, "valid": valid, "error": error, "active": false, "full_body": false, "bone_offsets": {}, "grips": {}}

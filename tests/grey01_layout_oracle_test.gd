extends SceneTree
## Adversarial data fixtures for the GREY canonical collider inventory.
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func runtime(expected: Array[Dictionary]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in expected:
		var row := record.duplicate(true)
		row.merge({"is_box":true,"shape_count":1,"rotation":Vector3.ZERO,"scale":Vector3.ONE,"shape_position":Vector3.ZERO,"shape_rotation":Vector3.ZERO,"shape_scale":Vector3.ONE,"layer":1,"disabled":false})
		rows.append(row)
	return rows

func case(oracle: Script, label: String, expected: Array[Dictionary], rows: Array[Dictionary], valid: bool) -> void:
	var errors: Array = oracle.call("validate",rows,expected,Rect2(-100,-125,200,250))
	var ok: bool = errors.is_empty() == valid
	checks += 1
	if not ok:
		failures += 1
	print("%s: %s; expected_valid=%s errors=%s" % ["PASS" if ok else "FAIL",label,valid,errors])

func _run() -> void:
	var path := "res://tests/helpers/grey_layout_oracle.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle="):
			path = argument.trim_prefix("--oracle=")
	var oracle: Script = load(path)
	var expected: Array[Dictionary] = [
		{"name":"House","category":"gameplay","position":Vector3(0,2,0),"size":Vector3(4,4,4)},
		{"name":"RailCoachCanonical_1","category":"perimeter","position":Vector3(-100.2,1.84,0),"size":Vector3(3.48,3.68,19.6)},
	]
	case(oracle,"valid gameplay plus authored exterior perimeter",expected,runtime(expected),true)
	var edge := expected.duplicate(true)
	edge[0].position = Vector3(98,2,0)
	case(oracle,"gameplay exactly touches original bounds",edge,runtime(edge),true)
	var outside := expected.duplicate(true)
	outside[0].position = Vector3(99,2,0)
	case(oracle,"matching gameplay record crossing bounds is rejected",outside,runtime(outside),false)
	var fake := runtime(expected)
	var extra: Dictionary = fake[0].duplicate(true)
	extra.name = "RailCoachFake"
	extra.position = Vector3(-110,2,0)
	fake.append(extra)
	case(oracle,"RailCoach-like name grants no exemption",expected,fake,false)
	var shifted := runtime(expected)
	shifted[1].position = Vector3(-100.18,1.84,0)
	case(oracle,"shifted canonical perimeter is rejected",expected,shifted,false)
	var wider := runtime(expected)
	wider[1].size = Vector3(3.68,3.68,19.6)
	case(oracle,"widened canonical perimeter is rejected",expected,wider,false)
	var below := expected.duplicate(true)
	below[1].position = Vector3(-100.2,1.74,0)
	case(oracle,"even a matching below-ground perimeter record is rejected",below,runtime(below),false)
	var missing := runtime(expected)
	missing.remove_at(1)
	case(oracle,"missing canonical perimeter is rejected",expected,missing,false)
	var duplicate := runtime(expected)
	duplicate.append(duplicate[1].duplicate(true))
	case(oracle,"duplicate canonical perimeter is rejected",expected,duplicate,false)
	var rotated := runtime(expected)
	rotated[1].rotation = Vector3(0,0.1,0)
	case(oracle,"rotated perimeter box is rejected",expected,rotated,false)
	var no_world := runtime(expected)
	no_world[1].layer = 0
	case(oracle,"perimeter without World collision is rejected",expected,no_world,false)
	var disabled := runtime(expected)
	disabled[1].disabled = true
	case(oracle,"disabled perimeter collision is rejected",expected,disabled,false)
	print("GREY_LAYOUT_ORACLE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

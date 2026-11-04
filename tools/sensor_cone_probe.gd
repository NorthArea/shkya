extends "res://tools/fps_probe.gd"
## MOTION-01: same workload, bounded sensor trace saved only after all samples.

func _run_motion(main: Node, started: int) -> void:
	DetectionSensor.start_cone_trace(int(_argument("--sensor-trace-capacity=", "16384")))
	await super._run_motion(main, started)

func _finish_motion(main: Node) -> void:
	var trace := DetectionSensor.stop_cone_trace()
	var path := _argument("--output=", "res://builds/checks/MOTION-01/fps-motion.json") + ".sensor.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_report_write_failed = true
		push_error("Cannot write sensor trace: " + path)
	else:
		file.store_string(JSON.stringify(trace))
		file.close()
	await super._finish_motion(main)

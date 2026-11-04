extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var sensor := DetectionSensor.new()
	sensor.show_cone = true
	sensor.cone_wanted = true
	sensor.set_physics_process(false)
	root.add_child(sensor)
	await physics_frame
	sensor._update_cone()
	check(DetectionSensor.stop_cone_trace().rows.is_empty(), "ordinary updates collect no trace")
	var original_cone := sensor._cone_mesh.get_faces()
	var original_near := sensor._near_mesh.get_faces()
	DetectionSensor.start_cone_trace(2)
	sensor._update_cone()
	sensor._update_cone()
	sensor._update_cone()
	var trace := DetectionSensor.stop_cone_trace()
	check(trace.rows.size() == 2 and trace.dropped == 1, "capture is bounded and reports overflow")
	check(sensor._cone_mesh.get_faces() == original_cone and sensor._near_mesh.get_faces() == original_near,
		"instrumentation preserves both mesh geometries")
	for row: Dictionary in trace.rows:
		check(row.clear_count == 2 and row.commit_count == 2, "visible sector and near ring each clear and commit")
		check(row.sensor_id == sensor.get_instance_id() and row.physics_frame == Engine.get_physics_frames()
			and row.process_frame == Engine.get_process_frames() and row.render_frame == Engine.get_frames_drawn(),
			"trace identifies sensor and exact physics/process/render frames")
		check(row.ended_tick_us >= row.started_tick_us and row.update_us == row.ended_tick_us - row.started_tick_us
			and row.update_us >= row.rebuild_us + row.near_us, "timings cover nested work with absolute monotonic ticks")
	DetectionSensor.start_cone_trace(3)
	sensor.fov_deg = 360.0
	sensor._update_cone()
	sensor.cone_wanted = false
	sensor._update_cone()
	trace = DetectionSensor.stop_cone_trace()
	check(trace.rows.size() == 2 and trace.dropped == 0, "new capture resets prior rows and overflow")
	check(trace.rows[0].clear_count == 1 and trace.rows[0].commit_count == 1,
		"full-circle sensor rebuilds only its sector")
	check(trace.rows[1].clear_count == 0 and trace.rows[1].commit_count == 0,
		"hidden geometry does not invent clear or commit events")
	check(not sensor._cone.visible and not sensor._near_disc.visible, "trace preserves visibility transitions")
	sensor.queue_free()
	await process_frame
	print("SENSOR_CONE_TRACE: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)

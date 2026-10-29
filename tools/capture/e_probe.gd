extends SceneTree
## CITY-02 E: проверка сборки мира без окна — время _ready LevelGeometry и число узлов.
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var t0 := Time.get_ticks_msec()
	print("PROBE start")
	var geo: Node3D = load("res://game/world/level_geometry.gd").new()
	root.add_child(geo)
	print("PROBE geometry built in %d ms, children %d" % [Time.get_ticks_msec() - t0, geo.get_child_count()])
	geo.queue_free()
	for i in 3: await process_frame
	quit(0)

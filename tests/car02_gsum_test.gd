extends SceneTree
## CAR-02 developer composition: common 32213 in real Main, C7 and bread signal.
const Gazelle = preload("res://game/vehicles/gazelle_visual.gd")
const Layout = preload("res://game/world/layout.gd")
const OUT := "res://builds/checks/CAR-02/gsum-integration/developer_result.json"
var checks := 0
var failures: Array[String] = []
var main: Node
var finished := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ", message)
	return ok

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func run() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	main.start_game()
	await frames(10)
	var world: DemoWorld = main.world
	var patrols: Node3D = world.get_node("LevelGeometry/Patrols")
	var van: CityVan = patrols.van
	var closure: Node3D = patrols.closure
	var closed := Gazelle.body_meshes(Gazelle.PASSENGER)
	var opened := Gazelle.body_meshes(Gazelle.PASSENGER, true)
	for actual: CityVan in [van, closure.van]:
		var collider: CollisionShape3D = actual.get_node("CollisionShape3D")
		check(actual.SIZE == Vector3(2.075, 2.255, 5.500) and collider.shape.size == Vector3(2.075, 2.255, 5.500)
			and is_equal_approx(collider.position.y, 2.255 * 0.5),
			"both real mission consumers use passenger Gazelle dimensions and grounded collider")
		check(actual.collision_layer == (1 if actual.visible else 0) and actual.collision_mask == 0,
			"C2 visible mission transport is World; hidden closure consumer has no collision layer")
		check(actual.visual.get_node("Body/BodyMesh").mesh == opened.body
			and actual.visual.get_node("Body/Glass").mesh == opened.glass
			and actual.visual.get_node("Body/Interior").mesh == closed.interior,
			"both Main vans use shared passenger open-door shell/glass and common interior")
		check(actual._wheels.size() == 6, "all six common Gazelle wheels registered for animation")
		for index in actual._wheels.size():
			var wheel: MeshInstance3D = actual._wheels[index]
			check(wheel.mesh == Gazelle.wheel_mesh()
				and wheel.get_parent().position == Gazelle.wheel_spots()[index],
				"shared wheel mesh and real axle/twin position %d" % index)
		check(actual.sensor.position.x > Gazelle.SIZE.x * 0.5
			and absf(actual.sensor.position.z - 0.3) < 0.01
			and (-actual.sensor.basis.z).dot(Vector3.RIGHT) > 0.999,
			"C7 sensor eye is outside right shell at doorway, points outward")
		check(actual.get_rid() in actual.sensor._exclude,
			"C7 sensor excludes its real transport collider from sight rays")
		check(actual.interactable.interaction_id == &"city_van"
			and actual.interactable.prompt == CityVan.PROMPT,
			"C3 mission transport interaction identity and prompt unchanged")
		check(actual.visual.get_node_or_null("CabinLight") != null,
			"warm cabin light preserved with common geometry")
	check(van.sensor.enabled and van.sensor.range_m == CityVan.PARK_SENSOR_RANGE
		and van.sensor.fov_deg == CityVan.PARK_SENSOR_FOV
		and van.sensor.suspicion_cap == CityVan.TUTORIAL_CAP,
		"actual initial van remains tutorial observer capped below detection")
	check(not closure.van.sensor.enabled, "closure transport does not add another observer")
	var wheel_before: Basis = van._wheels[0].basis
	world.player.set_physics_process(false)
	world.player.global_position = Layout.STEALTH_CHECKPOINT
	for sensor in get_nodes_in_group(&"detection_sensors"):
		if sensor != van.sensor:
			sensor.enabled = false
	var mission: MissionDirector = world.mission
	check(mission.interact(&"babka") == MissionDirector.R_OFFER_DIALOG and mission.accept(),
		"real MissionDirector accepts bread quest")
	check(mission.notify_entered_car() and mission.notify_arrived_kiosk(),
		"real mission enters purchase state through normal commands")
	mission.add_money(mission.money_missing())
	check(mission.buy_bread(), "real purchase emits bread_received to actual Patrols")
	check(van.is_driving() and not van.sensor.enabled and patrols._moved,
		"bread signal starts original route and disables door sensor during travel")
	check(van._path == Layout.VAN_PATH and van._stop_yaw == Layout.VAN_STOP_YAW,
		"original authored van route and destination yaw retained")
	var moved := false
	for index in 5400:
		await frames(1)
		moved = moved or not van._wheels[0].basis.is_equal_approx(wheel_before)
		if not van.is_driving():
			break
	check(moved, "actual mission driving animates common passenger wheels")
	check(not van.is_driving() and van.global_position.distance_to(Layout.VAN_PATH[-1]) < 0.35,
		"mission van reaches original kiosk stop with real traffic and closure")
	check(van.stall_ends == 0, "normal bread journey never uses emergency teleport")
	check(van.sensor.enabled and van.sensor.range_m == CityVan.SENSOR_RANGE
		and van.sensor.fov_deg == CityVan.SENSOR_FOV and van.sensor.suspicion_cap == 1.0,
		"arrival restores full C7 doorway observer")
	check(mission.has_bread and mission.state == MissionDirector.RETURN_HOME,
		"van visual transition and journey preserve purchased bread and return FSM")
	check(closure.activations == 1 and mission.road_closed,
		"same purchase activates original return-road closure exactly once")
	check(closure.van.visible and closure.van.collision_layer == 1 and closure.van.collision_mask == 0,
		"active closure transport restores its real World collider")
	patrols.reset_positions()
	await frames(3)
	check(not van.is_driving() and van.global_position.distance_to(Layout.VAN_PARK) < 0.01
		and van.sensor.enabled and van.sensor.suspicion_cap == CityVan.TUTORIAL_CAP,
		"actual Patrols reset restores initial park and tutorial sensor")
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", kind, true, false):
			audio.stop()
	main.queue_free()
	main = null
	await frames(4)
	OS.delay_msec(100)
	await process_frame
	finish()

func finish() -> void:
	if finished:
		return
	finished = true
	var report := {"checks": checks, "failures": failures,
		"scope": "developer actual Main shared 32213/chassis/material/wheels/C7/mission-signal/route/closure/reset; GPU likeness and FPS separate",
		"input_sha256": {}}
	for path in ["res://game/vehicles/city_van.gd", "res://game/vehicles/gazelle_visual.gd",
		"res://game/world/patrols.gd", "res://tests/car02_gsum_test.gd"]:
		report.input_sha256[path] = FileAccess.get_sha256(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write GSUM developer result")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CAR02_GSUM: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

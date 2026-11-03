extends SceneTree
## CPU diagnostics only: Dummy cannot measure GPU cost, displayed FPS or perceived smoothness.
## tools/godot.sh --path . --fixed-fps 60 --script tools/motion01_walk_cpu_probe.gd

var _physics_started := 0

class MeasuredHero extends "res://game/characters/imported_hero_visual.gd":
	var skin_us := 0
	var skin_calls := 0
	func _posed_surface_vertices(surface: int, use_final := true) -> PackedVector3Array:
		var started := Time.get_ticks_usec()
		var result := super(surface, use_final)
		skin_us += Time.get_ticks_usec() - started
		skin_calls += 1
		return result

class MeasuredCamera extends CameraRig:
	var samples := {}
	var measuring := false

	func record(key: String, started: int) -> void:
		if measuring:
			if not samples.has(key):
				samples[key] = []
			samples[key].append(Time.get_ticks_usec() - started)

	func _physics_process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super(delta)
		record("camera_total_us", started)

	func _safe_arm_distance(requested: float) -> float:
		var started := Time.get_ticks_usec()
		var result := super(requested)
		record("arm_queries_us", started)
		return result

	func _resolve_pivot_overlap(previous: Vector3) -> bool:
		var started := Time.get_ticks_usec()
		var result := super(previous)
		record("pivot_query_us", started)
		return result

	func _dodge_target() -> float:
		var started := Time.get_ticks_usec()
		var result := super()
		record("pole_dodge_us", started)
		return result

	func _fade_near_poles() -> void:
		var started := Time.get_ticks_usec()
		super()
		record("pole_fade_us", started)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("CPU probe requires headless/Dummy")
		quit(2)
		return
	if "--imported-hero" in OS.get_cmdline_user_args():
		await _hero_microbench()
		return
	preload("res://game/input_setup.gd").install()
	physics_frame.connect(func(): _physics_started = Time.get_ticks_usec())
	var world: DemoWorld = load("res://game/world/demo_world.tscn").instantiate()
	world.get_node("CameraRig").set_script(MeasuredCamera)
	root.add_child(world)
	for frame in 30:
		await process_frame
	var rig := world.camera_rig as MeasuredCamera
	var people: Node = world.get_node("LevelGeometry/Residents")
	var geometry := {"meshes": 0, "multimeshes": 0, "shadow_meshes": 0, "lights": 0, "shadow_lights": 0, "skeletons": 0}
	for node in world.find_children("*", "Node3D", true, false):
		if node is MeshInstance3D:
			geometry.meshes += 1
			if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				geometry.shadow_meshes += 1
		if node is MultiMeshInstance3D:
			geometry.multimeshes += 1
		if node is Skeleton3D:
			geometry.skeletons += 1
		if node is Light3D:
			geometry.lights += 1
			if node.shadow_enabled:
				geometry.shadow_lights += 1
	print("MOTION_CPU_CONTEXT ", JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(), "physics_hz": Engine.physics_ticks_per_second,
		"residents": people.residents.size(), "thin_poles": rig._thin.size(), "exclusions": rig.permanent_exclusions.size(),
		"geometry": geometry, "scope": "actual DemoWorld; no Main menu/music/phone; fixed simulation, CPU only"}))
	for scenario in ["idle", "idle_turn", "walk", "walk_turn"]:
		world.player.place(DemoWorld.Layout.SPAWN, DemoWorld.Layout.SPAWN_YAW)
		rig.yaw = DemoWorld.Layout.SPAWN_YAW
		rig.follow(world.player)
		if scenario.begins_with("walk"):
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")
		rig.samples.clear()
		rig.measuring = false
		var physics_us: Array = []
		var frame_us: Array = []
		var active_npc: Array = []
		var previous := Time.get_ticks_usec()
		for frame in 150:
			if scenario.ends_with("turn"):
				rig.apply_mouse(Vector2(9.0, 0.0)) # 1.35 rad/s at physics60.
			await process_frame
			var now := Time.get_ticks_usec()
			if frame >= 30:
				physics_us.append(now - _physics_started)
				frame_us.append(now - previous)
				var active := 0
				for resident in people.residents:
					if resident._locomotion_delta > 0.0:
						active += 1
				active_npc.append(active)
			rig.measuring = frame >= 29
			previous = now
		rig.measuring = false
		var report := {"scenario": scenario, "physics_phase_us": _stats(physics_us),
			"wall_frame_us": _stats(frame_us), "updated_npc": _stats(active_npc), "displacement": world.player.global_position.distance_to(DemoWorld.Layout.SPAWN)}
		for key in rig.samples:
			report[key] = _stats(rig.samples[key])
		print("MOTION_CPU_SCENARIO ", JSON.stringify(report))
	Input.action_release("move_forward")
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var looks := world.find_children("*", "CharacterSprite", true, false)
	var timings := {"all_character_poses_us": [], "all_resident_logic_us": [], "lighting_us": [], "hud_us": []}
	for iteration in 60:
		var started := Time.get_ticks_usec()
		for look in looks:
			look._physics_process(1.0 / 60.0)
		timings.all_character_poses_us.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		for resident in people.residents:
			resident._physics_process(1.0 / 60.0)
		timings.all_resident_logic_us.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		world.get_node("LightingAndWeather")._process(1.0 / 60.0)
		timings.lighting_us.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		world.get_node("GameHUD")._process(1.0 / 60.0)
		timings.hud_us.append(Time.get_ticks_usec() - started)
	var microbench := {"scope": "direct CPU calls after scenarios, scene disabled; not additive frame budget", "character_sprites": looks.size()}
	for key in timings:
		microbench[key] = _stats(timings[key])
	print("MOTION_CPU_MICROBENCH ", JSON.stringify(microbench))
	world.queue_free()
	for frame in 5:
		await process_frame
	print("MOTION_CPU_DONE; native FPS/GPU NOT_RUN")
	quit(0)

func _hero_microbench() -> void:
	var hero := MeasuredHero.new()
	hero.configure(preload("res://game/characters/character_catalog.gd").ILYUSHA_VISIBLE_HEIGHT_M, Color.WHITE)
	root.add_child(hero)
	for i in 3:
		await process_frame
	hero.set_process(false)
	var surfaces: Array = []
	for surface in hero.uniform_mesh.mesh.get_surface_count():
		var arrays: Array = hero.uniform_mesh.mesh.surface_get_arrays(surface)
		surfaces.append({"surface": surface, "material": hero.uniform_mesh.mesh.surface_get_material(surface).resource_name,
			"vertices": arrays[Mesh.ARRAY_VERTEX].size(), "is_sole": surface in hero._sole_surfaces})
	print("MOTION_HERO_CONTEXT ", JSON.stringify({"scope": "isolated real imported hero; Dummy CPU, no world/GPU",
		"model_sha256": FileAccess.get_sha256("res://assets/models/characters/ilyusha/ilyusha.glb"), "surfaces": surfaces}))
	for speed in [0.0, 4.0, 8.0]:
		hero.update_locomotion(Vector3(0, 0, -speed), true, &"locomotion", 1.0 / 60.0)
		for i in 5:
			hero._sample(1.0 / 60.0)
		hero.skin_us = 0
		hero.skin_calls = 0
		var times: Array = []
		for i in 60:
			var started := Time.get_ticks_usec()
			hero._sample(1.0 / 60.0)
			# Skeleton modifiers are deferred by the server; invoke the actual
			# foot modifier explicitly to include the skinning CPU work here.
			hero._foot_orientation._process_modification_with_delta(1.0 / 60.0)
			times.append(Time.get_ticks_usec() - started)
		print("MOTION_HERO_SAMPLE ", JSON.stringify({"speed": speed, "total_sample_us": _stats(times),
			"sole_skin_us_per_sample": hero.skin_us / 60.0, "skin_calls": hero.skin_calls}))
	hero.queue_free()
	for i in 3:
		await process_frame
	quit(0)

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += float(value)
	return {"n": values.size(), "mean": snappedf(total / values.size(), 0.01),
		"p50": sorted[values.size() / 2], "p95": sorted[mini(values.size() - 1, floori(values.size() * 0.95))], "max": sorted[-1]}

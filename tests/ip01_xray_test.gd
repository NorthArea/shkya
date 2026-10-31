extends SceneTree
# Frozen native render counterfactual: no external occluder => no xray color.
# Actual Main/Patrols/skin/material, isolated camera layers remove particle noise.
const NORMAL_LAYER := 1 << 18
const XRAY_LAYER := 1 << 19
const WALL_LAYER := 1 << 17
const PIXEL_DELTA := 0.025
const UNOBSTRUCTED_MAX_FRACTION := 0.005
const WALL_MIN_FRACTION := 0.02
var checks := 0
var errors: Array[String] = []
var measurements: Array = []
var main: Node
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error("FAIL: " + message)
func frames(n: int) -> void:
	for i in n:
		await process_frame
func capture(path: String) -> Image:
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(path)
	return image
func changed(a: Image, b: Image, rect: Rect2i) -> Dictionary:
	var count := 0
	var maximum := 0.0
	var sum := 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			maximum = maxf(maximum, d)
			sum += d
			if d > PIXEL_DELTA:
				count += 1
	var area := rect.size.x * rect.size.y
	return {"changed_pixels": count, "area": area, "fraction": float(count) / maxf(area, 1), "max_delta": maximum, "mean_delta": sum / maxf(area, 1)}
func crop(camera: Camera3D, mesh: MeshInstance3D) -> Rect2i:
	var bounds := mesh.get_aabb()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = mesh.global_transform * bounds.get_endpoint(i)
		var screen := camera.unproject_position(p)
		minimum = minimum.min(screen)
		maximum = maximum.max(screen)
	return Rect2i(Vector2i(minimum.floor()), Vector2i((maximum - minimum).ceil())).grow(4).intersection(Rect2i(root.get_visible_rect()))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/IP-01/regression"))
	check(DisplayServer.get_name() != "headless", "native renderer is required")
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	main = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/IP-01/regression/profile_%d.json" % Time.get_ticks_usec()
	root.add_child(main)
	await frames(4)
	main.start_game()
	await frames(6)
	var world: Node3D = main.world
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var camera := Camera3D.new()
	camera.fov = 45.0
	world.add_child(camera)
	for actor: Node3D in [patrols.officer, patrols.officer2]:
		var look: Node = actor.visual.get_node("Look")
		check(look.uses_uniform_3d(), actor.name + " is actual 3D runtime consumer")
		if not look.uses_uniform_3d():
			continue
		var visual: Node = look.uniform_visual
		var mesh: MeshInstance3D = visual.uniform_mesh
		var xray: MeshInstance3D = actor.xray
		var original_layers: int = mesh.layers
		mesh.layers = NORMAL_LAYER
		xray.layers = XRAY_LAYER
		var sensor_id: int = actor.sensor.get_instance_id()
		var sensor_range: float = actor.sensor.range_m
		var sensor_fov: float = actor.sensor.fov_deg
		var sensor_enabled: bool = actor.sensor.enabled
		world.player.place(actor.global_position + actor.visual.global_basis.z.normalized() * 8.0, 0.0)
		await frames(4)
		check(xray.visible and actor.sensor.enabled, actor.name + " live proximity gate enables xray")
		paused = true
		var center: Vector3 = actor.global_position + Vector3.UP * (visual.visible_height * 0.5)
		var direction: Vector3 = -actor.visual.global_basis.z.normalized()
		camera.global_position = center + direction * 4.0 + Vector3.UP * 0.1
		camera.look_at(center, Vector3.UP)
		camera.make_current()
		camera.cull_mask = NORMAL_LAYER | XRAY_LAYER | WALL_LAYER
		camera.force_update_transform()
		# Camera projection must observe its registered viewport/transform after entering tree.
		await frames(3)
		check(root.get_camera_3d() == camera, actor.name + " counterfactual camera remains current")
		var rect := crop(camera, mesh)
		print("IP01_CROP ", actor.name, " viewport=", root.get_visible_rect(), " mesh_aabb=", mesh.get_aabb(), " mesh_world=", mesh.global_transform, " camera=", camera.global_transform, " projected_origin=", camera.unproject_position(actor.global_position), " crop=", rect)
		check(rect.size.x > 100 and rect.size.y > 100, actor.name + " render crop contains full native actor")
		var prefix := "res://builds/checks/IP-01/regression/" + String(actor.name)
		var on := await capture(prefix + "_clear_on.png")
		camera.cull_mask = NORMAL_LAYER | WALL_LAYER
		var off := await capture(prefix + "_clear_off.png")
		var clear := changed(on, off, rect)
		check(clear.fraction <= UNOBSTRUCTED_MAX_FRACTION, "%s unoccluded actor has no xray overlay (changed %.4f)" % [actor.name, clear.fraction])
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.0, 3.0, 0.15)
		wall.mesh = box
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.22, 0.22, 0.22)
		wall.material_override = material
		wall.layers = WALL_LAYER
		world.add_child(wall)
		wall.global_position = center + direction * 1.5
		wall.global_basis = camera.global_basis.orthonormalized()
		camera.cull_mask = NORMAL_LAYER | XRAY_LAYER | WALL_LAYER
		var wall_on := await capture(prefix + "_wall_on.png")
		camera.cull_mask = NORMAL_LAYER | WALL_LAYER
		var wall_off := await capture(prefix + "_wall_off.png")
		var occluded := changed(wall_on, wall_off, rect)
		check(occluded.fraction >= WALL_MIN_FRACTION, "%s external wall produces actual 3D xray silhouette (changed %.4f)" % [actor.name, occluded.fraction])
		check(actor.sensor.get_instance_id() == sensor_id and actor.sensor.range_m == sensor_range and actor.sensor.fov_deg == sensor_fov and actor.sensor.enabled == sensor_enabled, actor.name + " camera/xray isolation leaves live sensor identity and state untouched")
		measurements.append({"actor": actor.name, "crop": str(rect), "clear": clear, "external_wall": occluded})
		wall.free()
		mesh.layers = original_layers
		xray.layers = 1
		paused = false
		await frames(3)
	var out := FileAccess.open("res://builds/checks/IP-01/regression/xray_result.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks": checks, "errors": errors, "measurements": measurements, "adapter_sha256": FileAccess.get_sha256("res://game/characters/uniform_visual.gd"), "patrol_sha256": FileAccess.get_sha256("res://game/npc/patrol_npc.gd"), "thresholds": {"pixel_delta": PIXEL_DELTA, "clear_fraction_max": UNOBSTRUCTED_MAX_FRACTION, "wall_fraction_min": WALL_MIN_FRACTION}, "scope": "actual Main Patrols skinned xray counterfactual under native renderer, camera-layer isolation; no particles/background false RED"}, "\t"))
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	for child in root.get_children():
		if child != main:
			child.queue_free()
	await frames(4)
	OS.delay_msec(100)
	await process_frame
	print("IP01_INDEPENDENT_XRAY: %d checks, %d failures" % [checks, errors.size()])
	quit(0 if errors.is_empty() else 1)

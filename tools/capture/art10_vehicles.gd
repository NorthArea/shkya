extends SceneTree
## ART-10: неподвижные реальные потребители Lada/TrafficCar, одинаковый свет и ракурсы до/после.
## tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tools/capture/art10_vehicles.gd -- --out=ART-10/after
## Это стенд формы. Игровой город/движение и ручной проход проверяются отдельно.
const LadaScript = preload("res://game/vehicles/lada.gd")
const TrafficScript = preload("res://game/vehicles/traffic_car.gd")
const RigScript = preload("res://game/camera/camera_rig.gd")
const Materials = preload("res://game/world/materials.gd")
const MODELS := ["vaz2105", "vaz2106", "volga"]
const SHOTS := {
	"front": Vector3(0, 1.30, -7.6),
	"front_quarter": Vector3(-5.2, 2.35, -6.4),
	"side": Vector3(-8.6, 1.45, 0),
	"rear": Vector3(0, 1.30, 7.6),
	"rear_quarter": Vector3(-5.2, 2.35, 6.4),
}
var output_dir := "res://builds/screenshots/ART-10/after"
var stage: Node3D
var camera: Camera3D
var rig: CameraRig
var caption: Label
var saved := 0
var failures := 0
var measurements := {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_dir = "res://builds/screenshots".path_join(argument.trim_prefix("--out="))
	call_deferred("_capture")

func _capture() -> void:
	preload("res://game/input_setup.gd").install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	_stage()
	await process_frame
	for model in MODELS:
		var actor: Node3D
		if model == "vaz2105":
			actor = LadaScript.new()
		else:
			var traffic := TrafficScript.new()
			traffic.kind = &"volga" if model == "volga" else &"zhiguli"
			actor = traffic
		stage.add_child(actor)
		# Ready построил штатный облик и коллизию. На стенде физика и эффекты движения остановлены.
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		for particles in actor.find_children("*", "CPUParticles3D", true, false):
			particles.emitting = false
		measurements[model] = _measure(actor)
		for shot in SHOTS:
			camera.position = SHOTS[shot]
			camera.look_at(Vector3(0, 0.72, 0))
			camera.make_current()
			caption.text = model + " / " + shot
			await _settle()
			await _save(model + "_" + shot)
		# Штатный CameraRig, те же FOV/дистанция/высота. Без изменения игровых профилей.
		for profile in [&"on_foot", &"in_car"]:
			rig.follow(actor, profile)
			rig.yaw = 2.45 if profile == &"on_foot" else 0.0
			rig.snap()
			rig.camera.make_current()
			caption.text = model + " / " + String(profile)
			await _settle()
			await _save(model + "_" + String(profile))
		actor.queue_free()
		rig.target = null
		await process_frame
	var report := FileAccess.open(output_dir.path_join("geometry.json"), FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify(measurements, "\t"))
		report.close()
	else:
		failures += 1
		push_error("ART10 CAPTURE: cannot write geometry.json")
	stage.queue_free()
	await process_frame
	Materials.clear_cache()
	if failures == 0 and saved == MODELS.size() * (SHOTS.size() + 2):
		print("ART10_CAPTURE: PASS (%d frames; stand only)" % saved)
		quit(0)
	else:
		push_error("ART10_CAPTURE: FAIL (%d frames, %d save errors)" % [saved, failures])
		quit(1)

func _stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.29, 0.34, 0.40)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.78, 0.85, 0.95)
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	ground.material_override = Materials.snow(0.0)
	ground.position.y = -0.01
	stage.add_child(ground)
	camera = Camera3D.new()
	camera.fov = RigScript.PROFILES[&"on_foot"]["fov"]
	stage.add_child(camera)
	rig = RigScript.new()
	stage.add_child(rig)
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(32, 25)
	caption.add_theme_font_size_override("font_size", 28)
	overlay.add_child(caption)

func _measure(actor: Node3D) -> Dictionary:
	var report := {}
	for node in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := actor.global_transform.affine_inverse() * mesh_instance.global_transform * mesh_instance.get_aabb()
		report[String(actor.get_path_to(mesh_instance))] = {
			"position": [bounds.position.x, bounds.position.y, bounds.position.z],
			"size": [bounds.size.x, bounds.size.y, bounds.size.z],
		}
	return report

func _settle() -> void:
	for i in 12:
		await process_frame

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(output_dir.path_join(label + ".png"))
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		failures += 1
		push_error("ART10 CAPTURE cannot save %s (%d)" % [path, error])
		return
	saved += 1
	print("ART10 SHOT ", path)

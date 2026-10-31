extends SceneTree
## APARTMENT-01: production balcony batching must preserve metre coordinates and per-flat identity.
## CPU contract runs headless; actual render-buffer readback needs a native renderer.
## Neither part judges furniture appearance or proves shader compilation.

const Buildings = preload("res://game/world/buildings.gd")
const Materials = preload("res://game/world/materials.gd")

var failed := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var buildings := Buildings.new(null)
	root.add_child(buildings)
	var along_x := {"long_x": true, "wall": 4.0, "side": 1.0}
	var along_z := {"long_x": false, "wall": -6.0, "side": -1.0}
	# Include the raised rail used by grille balconies: its opening starts 5 cm higher.
	buildings._glass_frames(along_x, 7.5, 3.85, 2.76, 1.63, 1.2, "pvc", 79, 1.05)
	buildings._glass_frames(along_z, -4.5, 6.6, 2.70, 1.68, 1.1, "wood", 137, 1.0)
	buildings._glass_frames(along_x, 10.5, 3.85, 2.76, 1.63, 1.2, "pvc", 79, 1.05)
	# Inspect the real production payload before build() consumes it. Dummy rendering
	# keeps instance_count/flags but does not retain transform/custom-data buffers.
	var payload: Dictionary = buildings._batches["glass"].duplicate(true)
	var transforms: Array = payload.xf
	var custom_data: Array = payload.custom
	_check(transforms.size() == 3 and custom_data.size() == 3, "production CPU glass batch contains all three room payloads")
	for i in transforms.size():
		var xf: Transform3D = transforms[i]
		var data: Color = custom_data[i]
		_check(is_equal_approx(data.r, maxf(xf.basis.x.length(), xf.basis.z.length())), "CPU pane width in metres matches geometry on either facade axis")
		_check(is_equal_approx(data.g, xf.basis.y.length()), "CPU pane height in metres matches geometry")
		_check(data.b > 0.0 and data.a >= 0.0 and data.a < 1.0, "CPU floor offset and flat identity fit shader contract")
	_check(is_equal_approx((custom_data[0] as Color).b, 1.05), "CPU grille opening retains its raised sill")
	_check((custom_data[0] as Color).a == (custom_data[2] as Color).a, "same CPU flat seed is repeatable")
	_check((custom_data[0] as Color).a != (custom_data[1] as Color).a, "different CPU flat seeds vary interiors")
	buildings.build()
	var glass: MultiMeshInstance3D = buildings.get_node("glass")
	var mm := glass.multimesh
	_check(mm.use_custom_data and mm.instance_count == transforms.size(), "production MultiMesh enables custom data and retains the instance count")
	_check(glass.material_override is ShaderMaterial and (glass.material_override as ShaderMaterial).shader != null, "production glass material references a shader resource (compilation unverified)")
	var driver := "unknown"
	if RenderingServer.has_method("get_current_rendering_driver_name"):
		driver = String(RenderingServer.call("get_current_rendering_driver_name"))
	var has_rendering_device := RenderingServer.get_rendering_device() != null
	print("APARTMENT01_RENDERER: display=%s method=%s driver=%s rendering_device=%s adapter=%s" % [DisplayServer.get_name(), RenderingServer.get_current_rendering_method(), driver, has_rendering_device, RenderingServer.get_video_adapter_name()])
	var native_renderer := has_rendering_device or (DisplayServer.get_name() != "headless" and driver in ["opengl3", "opengl3_es", "opengl3_angle"])
	if native_renderer:
		await process_frame
		var failures_before_readback := failed
		for i in transforms.size():
			_check(mm.get_instance_transform(i).is_equal_approx(transforms[i]), "native render buffer retains the production pane transform")
			_check(mm.get_instance_custom_data(i).is_equal_approx(custom_data[i]), "native render buffer retains the complete room payload")
		print("APARTMENT01_RENDER_READBACK: %s (6 checks); shader compilation and image QA NOT RUN" % ["PASS" if failed == failures_before_readback else "FAIL"])
	else:
		print("APARTMENT01_RENDER_READBACK: NOT RUN (no native renderer); GPU upload and shader compilation unverified")
	_check(buildings.find_children("*", "CollisionObject3D", true, false).is_empty(), "interior detailing adds no collisions")
	_check(buildings.find_children("*", "Light3D", true, false).is_empty(), "interior detailing adds no scene lights")
	print("APARTMENT01: %d checks, %d failures; shader compilation and image QA NOT RUN" % [checks, failed])
	buildings.queue_free()
	await process_frame
	Materials.clear_cache()
	quit(1 if failed else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		push_error("APARTMENT01: " + label)

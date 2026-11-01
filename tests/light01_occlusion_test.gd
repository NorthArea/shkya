extends SceneTree
## Structural half of LIGHT-01: production sources must be able to occlude nearby solid walls.
## Native light01_occlusion.gd separately measures rendered blocked/open receivers.
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LIGHT01 FAIL: " + label)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/checks/LIGHT-01"))
	AudioServer.set_bus_mute(0, true)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.achievement_path = "res://builds/checks/LIGHT-01/profile_test.json"
	root.add_child(main)
	await process_frame
	main.start_game()
	for i in 5:
		await process_frame
	var lights: Array[Light3D] = []
	var pending: Array[Node] = [main.world]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node is Light3D and not node is DirectionalLight3D:
			lights.append(node)
	check(lights.size() > 20, "production local light population")
	for light in lights:
		check(light.shadow_enabled, "solid occlusion: " + str(light.get_path()))
		check(light.distance_fade_enabled and light.distance_fade_shadow <= 40.0,
			"bounded shadow distance: " + str(light.get_path()))
	var player_visual: CharacterSprite = main.world.player.visual.get_node("Look")
	var shadow: MeshInstance3D = player_visual.get_node("Shadow")
	var texture: GradientTexture2D = shadow.mesh.material.albedo_texture
	check(texture.gradient.get_color(0).a <= 0.2, "3D contact blob avoids doubling the real shadow")
	var sky: DirectionalLight3D = main.world.get_node("LightingAndWeather/CoolSky")
	check(sky.light_angular_distance > 0.5 and sky.shadow_opacity < 1.0, "diffuse winter sky casts soft moderate shadows")
	check(is_equal_approx(main.world.get_node("LightingAndWeather/WorldEnvironment").environment.tonemap_exposure, 1.1),
		"global exposure preserved")
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for player: Node in main.find_children("*", kind, true, false):
			player.stop()
	main.queue_free()
	main = null
	for i in 4:
		await process_frame
	# The mixer releases stopped WAV playbacks on its own wall-clock thread.
	OS.delay_msec(100)
	await process_frame
	print("LIGHT01_OCCLUSION_CONFIG: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

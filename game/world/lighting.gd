extends Node3D
## LightingAndWeather для greybox: прохладный общий свет, тёплые точки у подъезда, фонарей и киоска.
## Финальный свет, окна и мокрый снег — ART-02.

const Layout = preload("res://game/world/layout.gd")

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.33, 0.40)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.70)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.48, 0.55)
	env.fog_density = 0.006
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "CoolSky"
	sun.light_color = Color(0.75, 0.82, 0.95)
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	add_child(sun)

	for i in Layout.LAMPS.size():
		var spec: Array = Layout.LAMPS[i]
		var lamp := OmniLight3D.new()
		lamp.name = "WarmLamp%d" % i
		lamp.position = spec[0]
		lamp.light_color = Color(1.0, 0.78, 0.45)
		lamp.light_energy = spec[1]
		lamp.omni_range = 9.0
		add_child(lamp)

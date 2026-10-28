extends Node3D
## Брызги снежной каши из-под задних колёс «Лады» (PLAY-03): видимый отклик на скорость и занос.
## Только облик: на физику и управление не влияет. Сила струи — прозрачность частиц, от скорости и заноса.
## CPUParticles3D, а не GPUParticles3D: материал GPU-частиц оставлял при выходе «ParticlesShaderRD were never freed».

const SPEED_FROM := 4.0       # м/с: медленнее брызг нет
const SPEED_FULL := 20.0      # м/с: полная струя
const SLIDE_FULL := 4.0       # м/с боковой скорости: занос даёт полную струю
const WHEELS := [Vector3(-0.78, 0.15, 1.45), Vector3(0.78, 0.15, 1.45)]   # за задними колёсами (перед — −Z)

var car: Lada
var _emitters: Array[CPUParticles3D] = []

func _ready() -> void:
	car = get_parent() as Lada
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	# Мягкое круглое пятно вместо квадрата.
	var blob := Gradient.new()
	blob.set_color(0, Color(1, 1, 1, 1))
	blob.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = blob
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.66, 0.64, 0.60)   # светлая серо-бурая каша (ART-05: #a7a18e)
	look.albedo_texture = dot
	look.vertex_color_use_as_albedo = true
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.roughness = 0.9
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	quad.material = look
	for at in WHEELS:
		var emitter := CPUParticles3D.new()
		emitter.name = "Spray"
		emitter.amount = 140
		emitter.lifetime = 0.7
		emitter.local_coords = false
		emitter.mesh = quad
		emitter.direction = Vector3(0, 0.6, 1)          # назад и вверх в осях машины
		emitter.spread = 25.0
		emitter.initial_velocity_min = 1.5
		emitter.initial_velocity_max = 4.0
		emitter.gravity = Vector3(0, -9.8, 0)
		emitter.scale_amount_min = 0.6
		emitter.scale_amount_max = 1.4
		emitter.damping_min = 1.0
		emitter.damping_max = 2.0
		emitter.color_ramp = fade
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.position = at
		emitter.emitting = false
		add_child(emitter)
		_emitters.append(emitter)

func _process(_delta: float) -> void:
	if not car:
		return
	var speed := Vector2(car.velocity.x, car.velocity.z).length()
	var strength := clampf((speed - SPEED_FROM) / (SPEED_FULL - SPEED_FROM), 0.0, 1.0)
	strength = maxf(strength, clampf(car.lateral_speed / SLIDE_FULL, 0.0, 1.0))
	if not car.is_on_floor():
		strength = 0.0
	for emitter in _emitters:
		emitter.emitting = strength > 0.02
		emitter.color = Color(1, 1, 1, strength)

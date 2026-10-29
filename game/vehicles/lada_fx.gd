extends Node3D
## DRIVE-02: эффекты «Лады» — только облик, на физику не влияют.
## Снег: пыль из-под колёс глубже DUST_DEPTH на скорости > DUST_SPEED (при буксовании — из-под колёс в снегу), облачко при
## посадке после отрыва; след колёс по сугробу (шейдер тропы trail.gdshader на узких полосах).
## Занос (Lada.skidding: ручник или боковая скорость на дороге): дым из-под задних колёс и тёмные следы шин.
## Частицы — CPUParticles3D с шейдером брызг PLAY-03 (slush_spray.gdshader) в мировых координатах; следы — по одному
## MultiMeshInstance3D на вид (кольцевой буфер полос, один вызов отрисовки).

const SPRAY_SHADER := preload("res://game/vehicles/slush_spray.gdshader")
const TRAIL_SHADER := preload("res://game/world/shaders/trail.gdshader")

const DUST_DEPTH := 0.1        # м рыхлого снега под колесом
const DUST_SPEED := 2.0        # м/с
const LANDING_PUFF := 0.3      # с облачка после посадки
const TRACK_STEP := 0.35       # м между полосами следа
const SNOW_TRACK_WIDTH := 0.32
const SKID_TRACK_WIDTH := 0.2
const SNOW_TRACKS := 320       # полос в кольцевом буфере
const SKID_TRACKS := 240
const TRACK_LIFT := 0.03       # м над поверхностью — без мерцания

var car: Node   # Lada
var dust: Array[CPUParticles3D] = []
var smoke: Array[CPUParticles3D] = []
var snow_tracks: Tracks
var skid_tracks: Tracks
var _puff := 0.0
var _landings := 0

func _ready() -> void:
	car = get_parent()
	var blob := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	blob.gradient = g
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(1.0, 0.5)
	blob.width = 32
	blob.height = 32
	for i in 4:
		var e := _emitter(blob, Color(0.93, 0.95, 0.99, 0.9), 0.4, 36, 0.7)
		e.name = "SnowDust%d" % i
		e.direction = Vector3(0, 1, 0.7)
		e.spread = 40.0
		e.initial_velocity_min = 1.0
		e.initial_velocity_max = 3.0
		e.gravity = Vector3(0, -3.0, 0)   # лёгкая снежная пыль оседает медленно
		e.damping_min = 1.5
		e.damping_max = 3.0
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		e.emission_sphere_radius = 0.15
		dust.append(e)
	for i in 2:
		var e := _emitter(blob, Color(0.80, 0.81, 0.84, 0.5), 0.7, 30, 1.4)
		e.name = "SkidSmoke%d" % i
		e.direction = Vector3(0, 1, 0.4)
		e.spread = 60.0
		e.initial_velocity_min = 0.4
		e.initial_velocity_max = 1.2
		e.gravity = Vector3(0, 0.4, 0)    # дым поднимается
		e.damping_min = 0.5
		e.damping_max = 1.0
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.5))
		grow.add_point(Vector2(1, 1.8))
		e.scale_amount_curve = grow
		smoke.append(e)
	snow_tracks = Tracks.new(SNOW_TRACKS, SNOW_TRACK_WIDTH, Color(0.72, 0.76, 0.83), Color(0.50, 0.54, 0.62), 0.8, 4)
	snow_tracks.name = "SnowTracks"
	add_child(snow_tracks)
	skid_tracks = Tracks.new(SKID_TRACKS, SKID_TRACK_WIDTH, Color(0.20, 0.20, 0.22), Color(0.11, 0.11, 0.12), 0.6, 2)
	skid_tracks.name = "SkidTracks"
	add_child(skid_tracks)

func _emitter(blob: Texture2D, color: Color, size: float, amount: int, lifetime: float) -> CPUParticles3D:
	var look := ShaderMaterial.new()
	look.shader = SPRAY_SHADER
	look.set_shader_parameter("albedo", color)
	look.set_shader_parameter("texture_albedo", blob)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = look
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var e := CPUParticles3D.new()
	e.amount = amount
	e.lifetime = lifetime
	e.local_coords = false   # частицы остаются в мире позади машины
	e.mesh = quad
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.5
	e.color_ramp = fade
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.emitting = false
	add_child(e)
	return e

## Шаг эффектов после физики «Лады» (вызывает Lada._after_slide).
func step(delta: float) -> void:
	if car == null:
		return
	var speed := Vector2(car.velocity.x, car.velocity.z).length()
	if car.landings != _landings:
		_landings = car.landings
		_puff = LANDING_PUFF
	_puff = maxf(_puff - delta, 0.0)
	var heights: Array[float] = car.wheel_heights()
	for i in 4:
		var ground: Vector3 = car.wheel_ground(i)
		var h := heights[i]
		# На ходу — из-под колёс в рыхлом снегу; при буксовании — из-под всех колёс, что упёрлись в снег.
		var digging: bool = not car.airborne and ((h > DUST_DEPTH and speed > DUST_SPEED) or (car.spinning and h > 0.02))
		var e := dust[i]
		e.global_position = Vector3(ground.x, h + 0.05, ground.z)
		var on := digging or (_puff > 0.0 and h > 0.02)
		e.emitting = on
		if on:
			var strength := clampf(maxf(speed / 10.0, 0.6 if car.spinning else 0.0), 0.35, 1.0)
			e.color = Color(1, 1, 1, maxf(strength, 0.8 if _puff > 0.0 else 0.0))
			e.initial_velocity_max = 2.0 + 0.25 * minf(speed, 12.0)
		snow_tracks.wheel(i, Vector3(ground.x, h, ground.z), h > 0.05 and not car.airborne, SnowField.normal_at(ground.x, ground.z) if h > 0.05 else Vector3.UP)
	for k in 2:
		var ground: Vector3 = car.wheel_ground(2 + k)
		var e := smoke[k]
		e.global_position = Vector3(ground.x, 0.15, ground.z)
		e.emitting = car.skidding
		if car.skidding:
			e.color = Color(1, 1, 1, clampf(maxf(car.lateral_speed, speed * 0.3) / 6.0, 0.3, 1.0))
		skid_tracks.wheel(k, Vector3(ground.x, 0.0, ground.z), car.skidding, Vector3.UP)

## Перестановка машины (reset_to): следы не тянутся через всю карту.
func reset() -> void:
	if snow_tracks:
		snow_tracks.cut()
		skid_tracks.cut()
	_puff = 0.0

## Полосы следа на кольцевом буфере MultiMesh: от прошлой точки колеса к новой, когда колесо прошло TRACK_STEP.
class Tracks extends MultiMeshInstance3D:
	var width := 0.3
	var count := 0          # всего положено полос (для проверок)
	var _next := 0
	var _last: Array[Vector3] = []

	func _init(capacity: int, track_width: float, clean: Color, dirty: Color, opacity: float, wheels: int) -> void:
		width = track_width
		top_level = true
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var plane := PlaneMesh.new()
		plane.size = Vector2(1, 1)
		var look := ShaderMaterial.new()
		look.shader = TRAIL_SHADER
		# Кромка тропы в шейдере — в метрах: «ширина» и «длина» заданы крупнее полосы, чтобы полоса не растворилась.
		look.set_shader_parameter("width", 1.6)
		look.set_shader_parameter("length_m", 1.6)
		look.set_shader_parameter("opacity", opacity)
		look.set_shader_parameter("clean", Vector3(clean.r, clean.g, clean.b))
		look.set_shader_parameter("dirty", Vector3(dirty.r, dirty.g, dirty.b))
		look.set_shader_parameter("print_walkers", 0.0)   # без отпечатков ног (CITY-02 L)
		plane.material = look
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = plane
		multimesh.instance_count = capacity
		multimesh.visible_instance_count = 0
		for i in wheels:
			_last.append(Vector3.INF)

	func wheel(i: int, point: Vector3, active: bool, normal: Vector3) -> void:
		if not active:
			_last[i] = Vector3.INF
			return
		if _last[i] == Vector3.INF:
			_last[i] = point
			return
		var span := point - _last[i]
		if span.length() < TRACK_STEP:
			return
		_add(_last[i], point, normal)
		_last[i] = point

	func cut() -> void:
		for i in _last.size():
			_last[i] = Vector3.INF

	func _add(a: Vector3, b: Vector3, normal: Vector3) -> void:
		var along := (b - a).normalized()
		var right := along.cross(normal).normalized()
		if right.length_squared() < 0.5:
			return
		var up := (-along).cross(right).normalized()
		var frame := Basis(right * width, up, -along * (a.distance_to(b) * 1.8))
		var t := Transform3D(frame, (a + b) * 0.5 + up * TRACK_LIFT)
		multimesh.set_instance_transform(_next, t)
		_next = (_next + 1) % multimesh.instance_count
		count += 1
		multimesh.visible_instance_count = mini(count, multimesh.instance_count)

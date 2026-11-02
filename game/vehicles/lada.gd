class_name Lada
extends CharacterBody3D
## Светло-бежевая ВАЗ-2106 (DRIVE-01): аркадная езда на CharacterBody3D, вход и выход по E (C4).
## Модель: продольная скорость от газа/тормоза, поворот зависит от скорости,
## боковая скорость гасится сцеплением — на мокрой дороге остаётся лёгкий занос, ручник его усиливает.

signal driver_entered(driver: Node3D)
signal driver_exited(driver: Node3D)

const Greybox = preload("res://game/world/greybox.gd")
const InteractableScript = preload("res://game/interaction/interactable.gd")
const LadaVisual = preload("res://game/vehicles/lada_visual.gd")
const SlushSpray = preload("res://game/vehicles/slush_spray.gd")
const LadaFx = preload("res://game/vehicles/lada_fx.gd")
const SnowField = preload("res://game/world/snow_field.gd")   # DRIVE-02 (C10): форма валов для колёс
const VehicleImpact = preload("res://game/vehicles/vehicle_impact.gd")
const VehicleDamage = preload("res://game/vehicles/vehicle_damage.gd")
const IMPACT_MASS := 1045.0
const IMPACT_YAW_DAMP := 3.0

const SIZE := LadaVisual.SIZE
## Темп по замеру эталона PLAY-01 (G02, G03): потолок 28 м/с ≈ 100 км/ч, разгон спадает к максимуму
## (0→20 м/с ≈ 2,8 с, как у G02), радиусы поворота в метрах — как у G02 (PLAY-02).
const MAX_SPEED := 28.0         # м/с ≈ 100 км/ч
const MAX_REVERSE := 10.0
const ACCELERATION := 9.0       # м/с² с места; к максимуму спадает как 1 − (v/MAX_SPEED)²
const REVERSE_ACCEL := 0.9      # доля ACCELERATION на заднем ходу
const BRAKE := 24.0             # 18→0 м/с за ~0,75 с, как у эталона (повторная сверка PLAY-02)
const ROLL_DRAG := 2.0          # накат PLAY-01 P3 (1,2) не взят: машина катилась бы 145 м
const AIR_DRAG := 0.004         # ·v²: на скорости накат короче (повторная сверка PLAY-02, P3)
const HANDBRAKE := 8.0
const HANDBRAKE_TURN := 1.4     # ручник докручивает машину
const GRIP := 7.0               # мокрая дорога: боковая скорость гасится не мгновенно
const HANDBRAKE_GRIP := 1.2
const TURN_RATE_LOW := 1.3      # рад/с на малой скорости: радиус ниже TURN_FULL_AT = 5/1,3 ≈ 3,9 м
const TURN_RATE_HIGH := 0.85    # рад/с на максимальной
const TURN_FULL_AT := 5.0       # ниже этой скорости поворот слабеет до нуля; 7 (PLAY-01) не взято: в щели тротуар–вал «Лада» не выкручивалась (тест застреваний)
const STEER_SHARPNESS := 10.0   # прежний отклик отдельного прототипа LadaRaycast
const STEER_RATE := 5.0         # нормализованных единиц/с: 0→упор за 0,2 с, между упорами за 0,4 с
const EXIT_SPEED_KMH := 3.0     # быстрее этого водитель не выходит, машина сначала тормозит

var driver: Node3D
var exit_requested := false
var enter_zone: Interactable
var lateral_speed := 0.0        # для тестов и звука заноса
var braking := false            # тормоз или ручник с водителем — стоп-сигналы ярче (POLISH-02)
var visual: Node3D
var _steer_now := 0.0
var _lights := -1
var _breakables: Node   # BREAK-01
var _impact_yaw := 0.0

# --- DRIVE-02 (C10): сугробы, подвеска, отскок ---
## Тело CharacterBody3D остаётся на земле (коллизии, зоны, тесты застреваний — как были); на снег поднимается и
## кренится облик Visual: высота над землёй snow_lift по SnowField, крен/тангаж — по высотам четырёх колёс.
## Перенос веса (DRIVE-03, вариант A): нос клюёт при торможении, корма приседает при разгоне, крен наружу в повороте —
## пружина с затуханием поверх наклона по снегу, тоже поворотом Visual. Константы PLAY-02 выше не меняются.
const WHEEL_TRACK: float = (LadaVisual.FRONT_TRACK + LadaVisual.REAR_TRACK) * 0.5
const WHEEL_AXLE: float = LadaVisual.PLAYER_SPEC["wheelbase_m"] * 0.5
const WHEELS: Array[Vector2] = [
	Vector2(-LadaVisual.FRONT_TRACK, LadaVisual.FRONT_AXLE), Vector2(LadaVisual.FRONT_TRACK, LadaVisual.FRONT_AXLE),
	Vector2(-LadaVisual.REAR_TRACK, LadaVisual.REAR_AXLE), Vector2(LadaVisual.REAR_TRACK, LadaVisual.REAR_AXLE),
] # (x,z): ЛП,ПП,ЛЗ,ПЗ; реальные свесы дают разные плечи относительно середины кузова.
const SNOW_DRAG := 4.0          # 1/(м·с): замедление SNOW_DRAG · глубина · max(|v|, SNOW_DRAG_MIN_SPEED)
const SNOW_DRAG_MIN_SPEED := 1.0
const MAX_CLIMB := 0.6109       # рад (35°): склон круче под ведущими колёсами — газ не тянет, буксует
const SPIN_STALL := 0.25        # с: столько буксует на месте (скорость → 0), потом колёса прокапываются
const SPIN_DIG := 0.25          # с: за столько тяга возвращается полностью — из кармана у вала выезд всегда есть
const SNOW_GRAVITY := 9.8       # м/с²: скатывание по тангажу на снегу
const BELLY := 0.25             # м: на узком гребне корпус садится «на брюхо» — центр не ниже height − BELLY
const LAUNCH_MAX := 1.2         # м/с: вертикальная скорость отрыва на гребне не больше этой
const AIR_GAP := 0.05           # м над снегом — «в полёте»
const TILT_MAX := 0.45          # рад: предел крена/тангажа по снегу
const TILT_SHARPNESS := 14.0
const LANDING_HEAVE := 0.35     # доля скорости приземления → проседание пружины
const PITCH_PER_ACCEL := 0.003  # рад на м/с² продольного ускорения (торможение 24 м/с² → нос −4°)
const ROLL_PER_ACCEL := 0.004   # рад на м/с² бокового ускорения (крен наружу)
const SUSP_PITCH_MAX := 0.07
const SUSP_ROLL_MAX := 0.07
const SUSP_FREQ := 10.0         # рад/с: частота пружины подвески
const SUSP_DAMP := 0.3          # доля критического затухания — «покачивание» в одно-два колебания
const SKID_SLIDE := 2.0         # м/с боковой скорости — занос (дым, след, скрип)
const SKID_MIN_SPEED := 3.0     # м/с: медленнее нет дыма и следа заноса
const SHAKE_SECONDS := 0.35
const SHAKE := 0.12             # м: тряска камеры при сильном ударе
const CAMERA_LIFT_SHARPNESS := 8.0

var snow_lift := 0.0            # м: облик над землёй
var snow_vy := 0.0              # м/с: вертикальная скорость облика (отрыв на гребне, падение)
var airborne := false
var snow_depth := 0.0           # м: средняя глубина рыхлого снега под колёсами
var spinning := false           # буксует: склон круче MAX_CLIMB, газ не тянет
var _spin_time := 0.0
var skidding := false           # занос или ручник на скорости — дым и след шин
var snow_pitch := 0.0           # рад: наклон облика по снегу
var snow_roll := 0.0
var susp_pitch := 0.0           # рад: перенос веса
var susp_roll := 0.0
var heave := 0.0                # м: проседание пружины
var impacts := 0                # отскоков (для проверок)
var landings := 0               # приземлений после полёта
var max_air := 0.0              # м: наибольший зазор над снегом с последнего reset_to (для проверок)
var _wheel_h: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _center_h := 0.0
var _susp_pitch_v := 0.0
var _susp_roll_v := 0.0
var _heave_v := 0.0
var _last_speed := 0.0
var _last_yaw := 0.0
var _shake_left := 0.0
var _shake_power := 0.0
var _camera_offset := Vector2.ZERO
var _camera_lift := 0.0
var _clock := 0.0
var fx: Node3D
var _spray: Node3D

func _ready() -> void:
	collision_layer = 4  # Car
	collision_mask = 1 | 32   # World, Breakable (BREAK-01: разрушаемые объекты, Breakables.LAYER)
	floor_snap_length = 0.5
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = SIZE.y * 0.5
	add_child(collider)
	visual = LadaVisual.build()  # светло-бежевая ВАЗ-2106; водитель, фары и огни — POLISH-02
	add_child(visual)
	VehicleImpact.register(self, IMPACT_MASS, SIZE, visual, receive_vehicle_impact, vehicle_velocity, vehicle_yaw)
	_update_lights()
	var spray := SlushSpray.new()  # брызги каши из-под колёс — PLAY-03
	spray.name = "SlushSpray"
	add_child(spray)
	_spray = spray
	fx = LadaFx.new()   # DRIVE-02: снежная пыль, след по снегу, дым и следы заноса
	fx.name = "DriveFx"
	add_child(fx)
	enter_zone = InteractableScript.new()
	enter_zone.name = "EnterZone"
	enter_zone.interaction_id = &"car"
	enter_zone.radius = 3.5   # ≈ длина машины, как у эталона (PLAY-01)
	add_child(enter_zone)

func _physics_process(delta: float) -> void:
	var gas := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false
	var stopping := not driver or exit_requested  # пустая машина и машина перед выходом тормозят до остановки
	if driver and not exit_requested:
		gas = Input.get_action_strength(&"car_gas")
		brake = Input.get_action_strength(&"car_brake")
		steer = Input.get_axis(&"move_right", &"move_left")
		handbrake = Input.is_action_pressed(&"handbrake")
	var both_pedals := gas > 0.0 and brake > 0.0
	var throttle := 0.0 if both_pedals else gas - brake
	var old_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var forward := -global_basis.z
	var forward_speed := old_velocity.dot(forward)

	_steer_now = move_toward(_steer_now, steer, STEER_RATE * delta)
	var speed_factor := clampf(absf(forward_speed) / TURN_FULL_AT, 0.0, 1.0)
	var turn_rate := lerpf(TURN_RATE_LOW, TURN_RATE_HIGH, clampf(absf(forward_speed) / MAX_SPEED, 0.0, 1.0))
	if handbrake:
		turn_rate *= HANDBRAKE_TURN
	var turn := (_steer_now * turn_rate * speed_factor * signf(forward_speed) + _impact_yaw) * delta
	VehicleImpact.safe_move(self, Vector3.ZERO, turn, SIZE, collision_mask)
	_impact_yaw *= exp(-IMPACT_YAW_DAMP * delta)

	forward = -global_basis.z
	forward_speed = old_velocity.dot(forward)
	var lateral := old_velocity - forward * forward_speed
	var speed_in := forward_speed   # DRIVE-02: до газа и тормоза — для буксования и переноса веса
	var coast_drag := ROLL_DRAG + AIR_DRAG * forward_speed * forward_speed
	if stopping:
		forward_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
	elif handbrake:
		forward_speed = move_toward(forward_speed, 0.0, HANDBRAKE * delta)
	elif both_pedals:
		# Собственный упрощённый аркадный ответ: тормоз удерживает машину, газ не включает реверс.
		forward_speed = move_toward(forward_speed, 0.0, lerpf(coast_drag, BRAKE, brake) * delta)
	elif gas > 0.0:
		if forward_speed < -0.5:
			forward_speed = move_toward(forward_speed, 0.0, lerpf(coast_drag, BRAKE, gas) * delta)
		else:
			var ratio := clampf(forward_speed / MAX_SPEED, 0.0, 1.0)
			forward_speed = minf(forward_speed + ACCELERATION * gas * (1.0 - ratio * ratio) * delta, MAX_SPEED)
	elif brake > 0.0:
		if forward_speed > 0.5:
			forward_speed = move_toward(forward_speed, 0.0, lerpf(coast_drag, BRAKE, brake) * delta)
		else:
			forward_speed = maxf(forward_speed - ACCELERATION * REVERSE_ACCEL * brake * delta, -MAX_REVERSE)
	else:
		forward_speed = move_toward(forward_speed, 0.0, coast_drag * delta)
	forward_speed = _snow_speed(forward_speed, speed_in, forward, throttle, stopping or handbrake or both_pedals, delta)   # DRIVE-02
	braking = driver != null and (handbrake or both_pedals or (stopping and absf(forward_speed) > 0.5)
		or (brake > 0.0 and forward_speed > 0.5) or (gas > 0.0 and forward_speed < -0.5))
	_update_lights()
	lateral *= exp(-(HANDBRAKE_GRIP if handbrake else GRIP) * delta)
	lateral_speed = lateral.length()

	var horizontal := forward * forward_speed + lateral
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= get_gravity().length() * delta
	var before_slide := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_vehicle_contacts(before_slide)
	_bump_breakables(before_slide, throttle, delta)
	_after_slide(before_slide, forward_speed, handbrake, delta)   # DRIVE-02: отскок, снег, подвеска, эффекты
	if exit_requested and speed_kmh() < EXIT_SPEED_KMH:
		exit_requested = false
		var world := get_parent()
		if world and world.has_method("exit_car"):
			world.exit_car()

## BREAK-01: касания за этот move_and_slide решает Breakables (скорость до упора, газ); поломка без замедления или
## тяжёлая (× 0,8) — горизонтальная скорость поправляется. Нет узла Breakables — ничего.
func _bump_breakables(before: Vector3, throttle: float, delta: float) -> void:
	if _breakables == null or not is_instance_valid(_breakables):
		_breakables = get_tree().get_first_node_in_group(&"breakables_root") if is_inside_tree() else null
		if _breakables == null:
			return
	var after: Vector3 = _breakables.car_contacts(self, before, throttle, delta)
	if after != Vector3.INF:
		velocity.x = after.x
		velocity.z = after.z

## E в машине: на месте — выход сразу, на ходу — машина тормозит и водитель выходит после остановки.
## Второе E во время торможения отменяет выход (итоговая сверка PLAY-02).
func _unhandled_input(event: InputEvent) -> void:
	if driver and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		exit_requested = not exit_requested

func enter(new_driver: Node3D) -> void:
	driver = new_driver
	LadaVisual.set_driver_visible(visual, true)
	_update_lights()
	driver_entered.emit(driver)

func exit() -> Node3D:
	var former := driver
	driver = null
	exit_requested = false
	braking = false
	LadaVisual.set_driver_visible(visual, false)
	_update_lights()
	if former:
		driver_exited.emit(former)
	return former

## Фары и стоп-сигналы: без водителя погашены (задние тусклые), с водителем горят, при торможении ярче.
func _update_lights() -> void:
	var mode: int = LadaVisual.Lights.OFF
	if driver:
		mode = LadaVisual.Lights.BRAKE if braking else LadaVisual.Lights.ON
	if mode != _lights:
		_lights = mode
		LadaVisual.set_lights(visual, mode)

func speed_kmh() -> float:
	return Vector2(velocity.x, velocity.z).length() * 3.6

## Поставить машину ровно на точку, без скорости (сброс, появление).
func reset_to(point: Vector3, facing_yaw: float) -> void:
	global_position = point
	rotation = Vector3(0.0, facing_yaw, 0.0)
	velocity = Vector3.ZERO
	lateral_speed = 0.0
	_steer_now = 0.0
	_impact_yaw = 0.0
	VehicleImpact.reset(self)
	VehicleDamage.reset(visual)
	exit_requested = false
	reset_physics_interpolation()
	_reset_drive_state()

# --- DRIVE-02 (C10): сугробы, подвеска, отскок ---

## Точка колеса i на земле (в плане, y = 0) в текущем положении тела.
func wheel_ground(i: int) -> Vector3:
	var right := Vector3(global_basis.x.x, 0.0, global_basis.x.z).normalized()
	var back := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
	var p := global_position + right * WHEELS[i].x + back * WHEELS[i].y
	return Vector3(p.x, 0.0, p.z)

## Точка касания колеса i у облика (с подъёмом и наклоном Visual) — для пыли и следа.
func wheel_contact(i: int) -> Vector3:
	if visual == null:
		return wheel_ground(i)
	return visual.global_transform * Vector3(WHEELS[i].x, 0.0, WHEELS[i].y)

## Высоты снега под колёсами (ЛП, ПП, ЛЗ, ПЗ) с последнего замера.
func wheel_heights() -> Array[float]:
	return _wheel_h.duplicate()

## Опора в начале кузова z=0: оси имеют разные плечи из-за паспортных свесов.
func _wheel_height_at_origin() -> float:
	var front := (_wheel_h[0] + _wheel_h[1]) * 0.5
	var rear := (_wheel_h[2] + _wheel_h[3]) * 0.5
	return (front * LadaVisual.REAR_AXLE - rear * LadaVisual.FRONT_AXLE) / (LadaVisual.REAR_AXLE - LadaVisual.FRONT_AXLE)

## Высота облика над землёй по опорам; на узком гребне — «на брюхе» (центр − BELLY).
func snow_ride_target() -> float:
	return maxf(maxf(_wheel_height_at_origin(), _center_h - BELLY), 0.0)

func _sample_snow() -> void:
	for i in 4:
		var w := wheel_ground(i)
		_wheel_h[i] = SnowField.height_at(w.x, w.z)
	_center_h = SnowField.height_at(global_position.x, global_position.z)

## Снег под колёсами до движения: сопротивление по глубине, скатывание по тангажу, буксование на крутом склоне.
## holding — тормоз, ручник или пустая машина: стоящая не скатывается.
func _snow_speed(forward_speed: float, speed_in: float, forward: Vector3, throttle: float, holding: bool, delta: float) -> float:
	_sample_snow()
	var depth := 0.0
	for h in _wheel_h:
		depth += minf(h, SnowField.DEPTH_MAX)
	snow_depth = depth * 0.25
	spinning = false
	if (snow_depth <= 0.0 and _center_h <= 0.0) or airborne:
		return forward_speed
	var push := signf(throttle)
	if push != 0.0 and forward_speed * push >= -0.5:
		var dir := Vector2(forward.x, forward.z) * push
		var steep := 0.0
		for i in ([0, 1] if push > 0.0 else [2, 3]):
			var w := wheel_ground(i)
			steep = maxf(steep, SnowField.slope_along(w.x, w.z, dir))
		if steep > tan(MAX_CLIMB):
			spinning = true
			_spin_time += delta
			# Газ не тянет — колёса крутятся в снегу; через SPIN_STALL прокапываются и тянут, к SPIN_DIG — полностью.
			var traction := clampf((_spin_time - SPIN_STALL) / SPIN_DIG, 0.0, 1.0)
			if (forward_speed - speed_in) * push > 0.0:
				forward_speed = speed_in + (forward_speed - speed_in) * traction
	if not spinning:
		_spin_time = maxf(_spin_time - delta * 0.5, 0.0)
	# Скатывание — по уклону высоты облика вдоль хода (энергия на подъём кузова): средний уклон под колёсами,
	# на узком гребне «на брюхе» — под центром.
	var along := Vector2(forward.x, forward.z)
	var grade := 0.0
	var support_height := _wheel_height_at_origin()
	if _center_h - BELLY > support_height:
		grade = SnowField.slope_along(global_position.x, global_position.z, along)
	else:
		for i in 4:
			var w := wheel_ground(i)
			grade += SnowField.slope_along(w.x, w.z, along) * 0.25
	if not (holding and absf(forward_speed) < 0.5):
		forward_speed -= SNOW_GRAVITY * grade / sqrt(1.0 + grade * grade) * delta
	return move_toward(forward_speed, 0.0, SNOW_DRAG * snow_depth * maxf(absf(forward_speed), SNOW_DRAG_MIN_SPEED) * delta)

## После move_and_slide: отскок от машин и разрушаемых, высота и наклон облика по снегу, перенос веса, эффекты.
func _after_slide(_before: Vector3, _planned_speed: float, handbrake: bool, delta: float) -> void:
	_clock += delta
	_sample_snow()
	var target := snow_ride_target()
	if snow_lift <= target + 0.0005:
		# Снег выталкивает облик вверх по профилю; скорость подъёма — для отрыва на гребне (не выше LAUNCH_MAX).
		snow_vy = minf((target - snow_lift) / delta, LAUNCH_MAX)
		snow_lift = target
		airborne = false
	else:
		# Поверхность ушла вниз: облик падает с ускорением g — на скорости со склона короткий полёт.
		snow_vy -= SNOW_GRAVITY * delta
		snow_lift += snow_vy * delta
		if snow_lift <= target:
			if airborne and snow_vy < -1.0:
				_heave_v += snow_vy * LANDING_HEAVE   # мягкая посадка: пружина проседает и возвращается
				landings += 1
			snow_lift = target
			snow_vy = 0.0
			airborne = false
		else:
			airborne = snow_lift > target + AIR_GAP
	max_air = maxf(max_air, snow_lift - target)
	if not airborne:
		var front := (_wheel_h[0] + _wheel_h[1]) * 0.5
		var rear := (_wheel_h[2] + _wheel_h[3]) * 0.5
		var left := (_wheel_h[0] + _wheel_h[2]) * 0.5
		var right := (_wheel_h[1] + _wheel_h[3]) * 0.5
		var k := 1.0 - exp(-TILT_SHARPNESS * delta)
		snow_pitch = lerpf(snow_pitch, clampf(atan2(front - rear, 2.0 * WHEEL_AXLE), -TILT_MAX, TILT_MAX), k)
		snow_roll = lerpf(snow_roll, clampf(atan2(right - left, 2.0 * WHEEL_TRACK), -TILT_MAX, TILT_MAX), k)
	# Перенос веса по фактической скорости после упора и отскока.
	var yaw := global_rotation.y
	var speed := Vector3(velocity.x, 0.0, velocity.z).dot(-global_basis.z)
	if _clock <= delta * 1.5:   # первый кадр: курс и скорость могли выставить без reset_to
		_last_yaw = yaw
		_last_speed = speed
	var a_long := clampf((speed - _last_speed) / delta, -40.0, 40.0)
	var a_lat := speed * clampf(angle_difference(_last_yaw, yaw) / delta, -3.0, 3.0)
	_last_speed = speed
	_last_yaw = yaw
	var pitch_goal := 0.0 if airborne else clampf(a_long * PITCH_PER_ACCEL, -SUSP_PITCH_MAX, SUSP_PITCH_MAX)
	var roll_goal := 0.0 if airborne else clampf(-a_lat * ROLL_PER_ACCEL, -SUSP_ROLL_MAX, SUSP_ROLL_MAX)
	var w2 := SUSP_FREQ * SUSP_FREQ
	var damp := 2.0 * SUSP_DAMP * SUSP_FREQ
	_susp_pitch_v += (w2 * (pitch_goal - susp_pitch) - damp * _susp_pitch_v) * delta
	susp_pitch += _susp_pitch_v * delta
	_susp_roll_v += (w2 * (roll_goal - susp_roll) - damp * _susp_roll_v) * delta
	susp_roll += _susp_roll_v * delta
	_heave_v += (-w2 * heave - damp * _heave_v) * delta
	heave = clampf(heave + _heave_v * delta, -0.15, 0.15)
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	skidding = driver != null and not airborne and snow_depth < 0.05 and flat_speed > SKID_MIN_SPEED \
		and (handbrake or lateral_speed > SKID_SLIDE)
	_apply_visual()
	if fx:
		fx.step(delta)
	_camera_fx(delta)

func vehicle_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)

func vehicle_yaw() -> float:
	return _impact_yaw

func receive_vehicle_impact(delta_velocity: Vector3, delta_yaw: float, point: Vector3, inward: Vector3, closing: float, damage_speed := -1.0) -> void:
	velocity += delta_velocity
	_impact_yaw = clampf(_impact_yaw + delta_yaw, -2.5, 2.5)
	VehicleDamage.dent(visual, point, inward, damage_speed if damage_speed >= 0.0 else closing)

func _vehicle_contacts(before: Vector3) -> void:
	var closing := VehicleImpact.contacts(self, before)
	if closing > 0.0:
		impacts += 1
		_shake_left = SHAKE_SECONDS
		_shake_power = clampf(closing / 12.0, 0.25, 1.0)
		_susp_pitch_v -= closing * 0.04
		_heave_v -= closing * 0.02

func _apply_visual() -> void:
	if visual == null:
		return
	visual.position = Vector3(0.0, snow_lift + heave, 0.0)
	visual.rotation = Vector3(snow_pitch + susp_pitch, 0.0, snow_roll + susp_roll)
	if _spray:
		_spray.position.y = snow_lift
		_spray.visible = snow_depth < 0.05   # на снегу вместо каши — снежная пыль DriveFx

## Камера за «Ладой»: поднимается вслед за обликом на снегу и трясётся после удара (смещения камеры — добавкой,
## как тряска Breakables). Пружину камеры (CameraRig) не трогаем.
func _camera_fx(delta: float) -> void:
	_shake_left = maxf(_shake_left - delta, 0.0)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var arm := camera.get_parent()
	var rig: Node = arm.get_parent() if arm else null
	var mine: bool = rig != null and rig.get("target") == self
	_camera_lift = lerpf(_camera_lift, snow_lift if mine else 0.0, 1.0 - exp(-CAMERA_LIFT_SHARPNESS * delta))
	var want := Vector2(0.0, _camera_lift)
	if mine and _shake_left > 0.0:
		want += Vector2(sin(_clock * 67.0), cos(_clock * 49.0)) * SHAKE * _shake_power * (_shake_left / SHAKE_SECONDS)
	if want.distance_squared_to(_camera_offset) < 0.0000001:
		return
	camera.h_offset += want.x - _camera_offset.x
	camera.v_offset += want.y - _camera_offset.y
	_camera_offset = want

## Камера трясётся (для проверок): осталось секунд.
func shake_left() -> float:
	return _shake_left

func _reset_drive_state() -> void:
	if not is_inside_tree():
		return
	_sample_snow()
	snow_lift = snow_ride_target()
	snow_vy = 0.0
	airborne = false
	spinning = false
	_spin_time = 0.0
	skidding = false
	max_air = 0.0
	snow_pitch = clampf(atan2((_wheel_h[0] + _wheel_h[1] - _wheel_h[2] - _wheel_h[3]) * 0.5, 2.0 * WHEEL_AXLE), -TILT_MAX, TILT_MAX)
	snow_roll = clampf(atan2((_wheel_h[1] + _wheel_h[3] - _wheel_h[0] - _wheel_h[2]) * 0.5, 2.0 * WHEEL_TRACK), -TILT_MAX, TILT_MAX)
	susp_pitch = 0.0
	susp_roll = 0.0
	heave = 0.0
	_susp_pitch_v = 0.0
	_susp_roll_v = 0.0
	_heave_v = 0.0
	_last_speed = 0.0
	_last_yaw = global_rotation.y
	_apply_visual()
	if fx:
		fx.reset()

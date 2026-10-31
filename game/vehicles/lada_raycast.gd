class_name LadaRaycast
extends Lada
## DRIVE-03, прототип D: «Лада» на четырёх лучах-пружинах (запуск с флагом --raycar, переключатель — demo_world.gd).
## Своя реализация. Идеи алгоритма (не код): пружина по закону Гука + демпфер вдоль оси кузова у каждого колеса,
## жёсткость из собственной частоты и развесовки по осям, боковое сцепление гасит скорость поперёк колеса —
## открытые контроллеры Godot 4 (DAShoe1/Godot-Easy-Vehicle-Physics, Dechode/Godot-Simple-Vehicle, MIT), см. assets/README.md.
##
## Тип и API — прежние (наследник Lada): сигналы, зона входа, enter/exit, speed_kmh(), reset_to(), lateral_speed, braking.
## Твёрдое тело считается вручную: velocity (Lada) — линейная скорость, _ang_vel — угловая (мир), ориентация — кватернион
## тела, масса MASS и главные моменты INERTIA. Опора — лучи от колёс (подвеска), перемещение и стены — move_and_slide().
## Привод, тормоз, руль, ручник — константы Lada (PLAY-02); кривая разгона — до потолка эталона G02 (ACCEL_CURVE_TOP).
## Крен/тангаж — настоящий поворот тела (силы пружин и шин дают момент), не наклон Visual.

const MASS := 1000.0                            # ВАЗ-2105 снаряжённая ≈ 995 кг
const INERTIA := Vector3(1600.0, 1700.0, 420.0) # тангаж (x), рыскание (y), крен (z), кг·м²: брусок 1,62 × 1,4 × 4,13 м
const COM := Vector3(0.0, 0.55, 0.0)            # центр масс над точкой опоры тела (начало координат — земля)
const WHEEL_R := 0.30                           # физический радиус прежней калибровки прототипа; облик — ВАЗ-2106
const REST_LEN := 0.20                          # длина пружины, когда тело стоит ровно на земле (y = 0)
const TRAVEL := 0.25                            # ход подвески
const RIDE_HZ := 1.5                            # собственная частота подвески на угол
const DAMPING_RATIO := 0.4
const PRELOAD := 0.01      # равновесие пружин на 1 см ниже: опора-салазка лежит на земле → is_on_floor() для брызг/следов
const BUMP_K := 8.0        # отбойник: жёсткость × BUMP_K за пределом хода
const TIRE_LEVER := 0.4    # доля высоты ЦМ в плече сил шин: перенос веса есть, «кувырка» от тормоза 24 м/с² нет
const YAW_RESPONSE := 25.0 # 1/с: рыскание догоняет руль (как аркада), пока передние колёса на земле
const ACCEL_CURVE_TOP := 33.3  # м/с: разгон спадает как 1 − (v/33,3)², потолок — MAX_SPEED (G02: максимум 33,3, 0→30 за 5,5 с)
const MAX_TILT := 0.6109   # 35°: крен/тангаж тела не больше — машина не переворачивается
const AIR_LEVEL := 6.0     # 1/с²: в воздухе тело выравнивается
const AIR_LEVEL_DAMP := 3.0
const ANG_DAMP := 0.6      # 1/с: гашение крена/тангажа (трение в шарнирах)
const WALL_BOUNCE := 0.3   # отскок от стены: доля нормальной скорости
const WALL_SPIN := 0.5     # доля рыскания от удара (смещение точки удара от ЦМ)
const WALL_MIN_SPEED := 1.5
const CHASSIS_CLEARANCE := 0.25  # низ коробки кузова над землёй: по земле катят лучи, а не коробка
const SKID_R := 0.08
const SNOW_FIELD_PATH := "res://game/world/snow_field.gd"   # DRIVE-02 (C10), если уже есть

var wheels_on_ground := 0
var airborne_time := 0.0
var _ang_vel := Vector3.ZERO
var _mounts: Array[Vector3] = []
var _front: Array[bool] = []
var _k: Array[float] = []
var _c: Array[float] = []
var _free: Array[float] = []
var _len: Array[float] = []
var _pivots: Array[Node3D] = []
var _snow = null   # Script SnowField или null (статический height_at вызывается динамически)
var _ray_mask := 1 | 32 | 64   # World | Breakable | SnowBank

func _ready() -> void:
	super._ready()
	floor_snap_length = 0.02
	# Коробка кузова поднята на клиренс, к ней — салазка-шар в точке опоры (касается земли только в покое).
	var chassis := get_node("CollisionShape3D") as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, SIZE.y - CHASSIS_CLEARANCE, SIZE.z)
	chassis.shape = box
	chassis.position.y = CHASSIS_CLEARANCE + box.size.y * 0.5
	var skid := CollisionShape3D.new()
	skid.name = "Skid"
	var sphere := SphereShape3D.new()
	sphere.radius = SKID_R
	skid.shape = sphere
	skid.position.y = SKID_R
	add_child(skid)
	if ResourceLoader.exists(SNOW_FIELD_PATH):
		_snow = load(SNOW_FIELD_PATH)
		_ray_mask = 1 | 32   # валы — по профилю SnowField, коробки слоя 64 дали бы ступеньку
	# Сохраняем прежние плечи сил и развесовку; смена модели касается только облика.
	var spots := LadaVisual.wheel_spots(&"vaz2105")
	var front_z := INF
	var rear_z := -INF
	for spot in spots:
		front_z = minf(front_z, spot.z)
		rear_z = maxf(rear_z, spot.z)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)   # get_gravity() в _ready ещё 0
	for spot in spots:
		var front := spot.z < 0.0
		# Развесовка по осям от положения ЦМ (z = 0): нагрузка на угол и жёсткость на RIDE_HZ.
		var share := (rear_z / (rear_z - front_z)) if front else (-front_z / (rear_z - front_z))
		var corner := MASS * share * 0.5
		var k := corner * pow(TAU * RIDE_HZ, 2.0)
		_mounts.append(Vector3(spot.x, WHEEL_R + REST_LEN, spot.z))
		_front.append(front)
		_k.append(k)
		_c.append(2.0 * DAMPING_RATIO * sqrt(k * corner))
		_free.append(REST_LEN - PRELOAD + corner * g / k)
		_len.append(REST_LEN)
	for child in visual.get_children():
		if String(child.name).begins_with("WheelPivot") or String(child.name).contains("WheelPivot"):
			_pivots.append(child)
	var motion := visual.get_node_or_null("Motion")
	if motion:
		motion.set("body", null)   # наклон кузова теперь настоящий — «видимая подвеска» Motion не нужна

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false
	var stopping := not driver or exit_requested
	if driver and not exit_requested:
		throttle = Input.get_axis(&"move_back", &"move_forward")
		steer = Input.get_axis(&"move_right", &"move_left")
		handbrake = Input.is_action_pressed(&"handbrake")
	var b := global_basis.orthonormalized()
	var up := b.y
	var com := global_transform * COM
	var g := get_gravity().length()
	var v := velocity
	var force := Vector3.DOWN * g * MASS
	var torque := Vector3.ZERO

	# --- подвеска: луч от крепления вниз по оси кузова ---
	var space := get_world_3d().direct_space_state
	var contacts: Array[Vector3] = []
	var front_down := 0
	var rear_down := 0
	for i in _mounts.size():
		var mount := global_transform * _mounts[i]
		var reach := _free[i] + WHEEL_R
		var query := PhysicsRayQueryParameters3D.create(mount, mount - up * reach, _ray_mask, [get_rid()])
		var hit := space.intersect_ray(query)
		var dist := INF
		if not hit.is_empty():
			dist = mount.distance_to(hit["position"])
		if _snow:
			var snow_y: float = _snow.height_at(mount.x, mount.z)
			if snow_y > 0.0:
				dist = minf(dist, (mount.y - snow_y) / maxf(up.y, 0.5))
		var length := dist - WHEEL_R
		if length < _free[i]:
			var arm := mount - com
			var point_v := v + _ang_vel.cross(arm)
			var stretch_rate := point_v.dot(up)   # крепление вверх — пружина длиннее
			var f := _k[i] * (_free[i] - length) - _c[i] * stretch_rate
			var stop := _free[i] - TRAVEL
			if length < stop:
				f += BUMP_K * _k[i] * (stop - length)
			f = maxf(f, 0.0)
			force += up * f
			torque += arm.cross(up * f)
			contacts.append(mount - up * (length + WHEEL_R))
			if _front[i]:
				front_down += 1
			else:
				rear_down += 1
			_len[i] = maxf(length, stop)
		else:
			_len[i] = _free[i]
	wheels_on_ground = contacts.size()
	airborne_time = 0.0 if wheels_on_ground > 0 else airborne_time + delta
	var grip_all := wheels_on_ground / 4.0
	var grip_front := front_down / 2.0
	var grip_rear := rear_down / 2.0
	v += force / MASS * delta

	# --- руль: рыскание по аркадной формуле Lada, пока передние колёса на земле ---
	var forward := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var horizontal := Vector3(v.x, 0.0, v.z)
	var forward_speed := horizontal.dot(forward)
	_steer_now = lerpf(_steer_now, steer, 1.0 - exp(-STEER_SHARPNESS * delta))
	var speed_factor := clampf(absf(forward_speed) / TURN_FULL_AT, 0.0, 1.0)
	var turn_rate := lerpf(TURN_RATE_LOW, TURN_RATE_HIGH, clampf(absf(forward_speed) / MAX_SPEED, 0.0, 1.0))
	if handbrake:
		turn_rate *= HANDBRAKE_TURN
	var yaw_target := _steer_now * turn_rate * speed_factor * signf(forward_speed)
	_ang_vel.y += (yaw_target - _ang_vel.y) * (1.0 - exp(-YAW_RESPONSE * delta)) * grip_front

	# --- продольная сила: привод на задние колёса, тормоз на все (цифры Lada) ---
	var new_speed := forward_speed
	var long_grip := grip_all
	if stopping:
		new_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
	elif handbrake:
		new_speed = move_toward(forward_speed, 0.0, HANDBRAKE * delta)
		long_grip = grip_rear
	elif throttle > 0.0:
		if forward_speed < -0.5:
			new_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
		else:
			var ratio := clampf(forward_speed / ACCEL_CURVE_TOP, 0.0, 1.0)
			new_speed = minf(forward_speed + ACCELERATION * throttle * (1.0 - ratio * ratio) * delta, MAX_SPEED)
			long_grip = grip_rear
	elif throttle < 0.0:
		if forward_speed > 0.5:
			new_speed = move_toward(forward_speed, 0.0, BRAKE * delta)
		else:
			new_speed = maxf(forward_speed + ACCELERATION * REVERSE_ACCEL * throttle * delta, -MAX_REVERSE)
			long_grip = grip_rear
	else:
		new_speed = move_toward(forward_speed, 0.0, (ROLL_DRAG + AIR_DRAG * forward_speed * forward_speed) * delta)
	var long_dv := forward * (new_speed - forward_speed) * long_grip
	braking = driver != null and (handbrake or (stopping and absf(forward_speed) > 0.5)
		or (throttle < 0.0 and forward_speed > 0.5) or (throttle > 0.0 and forward_speed < -0.5))
	_update_lights()

	# --- боковое сцепление: поперечная скорость гаснет (мокрый снег — не мгновенно, ручник — слабо) ---
	var lateral := horizontal - forward * forward_speed
	var lat_dv := -lateral * (1.0 - exp(-(HANDBRAKE_GRIP if handbrake else GRIP) * delta)) * grip_all
	lateral_speed = (lateral + lat_dv).length()
	var tire_dv := long_dv + lat_dv
	v += tire_dv
	if throttle == 0.0 and grip_all >= 0.75 and Vector2(v.x, v.z).length() < 0.05:
		v.x = 0.0   # стоит — не ползёт
		v.z = 0.0
	# Силы шин приложены в пятнах контакта, плечо по высоте укорочено (TIRE_LEVER): тангаж при разгоне/торможении,
	# крен в повороте. Рыскание задаёт руль, поэтому его составляющую момента шин отбрасываем.
	if not contacts.is_empty():
		var tire_force := tire_dv * MASS / delta / contacts.size()
		var tire_torque := Vector3.ZERO
		for c in contacts:
			var arm := c - com
			arm -= up * arm.dot(up) * (1.0 - TIRE_LEVER)
			tire_torque += arm.cross(tire_force)
		tire_torque.y = 0.0
		torque += tire_torque

	# --- вращение тела ---
	var yaw_rate := _ang_vel.y
	_ang_vel += b * ((b.transposed() * torque) / INERTIA) * delta
	_ang_vel.y = yaw_rate if wheels_on_ground > 0 else _ang_vel.y   # рыскание на земле — только от руля и ударов
	var tilt_w := Vector3(_ang_vel.x, 0.0, _ang_vel.z)
	_ang_vel -= tilt_w * (1.0 - exp(-ANG_DAMP * delta))
	if wheels_on_ground == 0:
		tilt_w = Vector3(_ang_vel.x, 0.0, _ang_vel.z)
		_ang_vel += (up.cross(Vector3.UP) * AIR_LEVEL - tilt_w * AIR_LEVEL_DAMP) * delta
	var q := b.get_rotation_quaternion()
	var w_len := _ang_vel.length()
	if w_len > 1e-6:
		q = (Quaternion(_ang_vel / w_len, w_len * delta) * q).normalized()
	q = _limit_tilt(q)
	global_basis = Basis(q)

	# --- перемещение: стены и земля — move_and_slide ---
	velocity = v
	var before := velocity
	var before_slide := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_wall_bounce(before, com)
	_bump_breakables(before_slide, throttle, delta)
	_place_wheels()
	if exit_requested and speed_kmh() < EXIT_SPEED_KMH:
		exit_requested = false
		var world := get_parent()
		if world and world.has_method("exit_car"):
			world.exit_car()

## Крен/тангаж не больше MAX_TILT: лишнее срезается, угловая скорость «на опрокидывание» гасится.
func _limit_tilt(q: Quaternion) -> Quaternion:
	var up := Basis(q).y
	var tilt := acos(clampf(up.y, -1.0, 1.0))
	if tilt <= MAX_TILT:
		return q
	var axis := up.cross(Vector3.UP)
	if axis.length() < 1e-6:
		return q
	axis = axis.normalized()
	var toward := _ang_vel.dot(axis)
	if toward < 0.0:
		_ang_vel -= axis * toward
	return (Quaternion(axis, tilt - MAX_TILT) * q).normalized()

## Удар о стену (World, другие машины): нормальная скорость возвращается с WALL_BOUNCE, смещение точки удара от ЦМ
## даёт рыскание. Земля и разрушаемые (их решает Breakables) — без отскока.
func _wall_bounce(before: Vector3, com: Vector3) -> void:
	var best: KinematicCollision3D
	var best_vn := -WALL_MIN_SPEED
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var n := hit.get_normal()
		if n.y > 0.6:
			continue
		var body := hit.get_collider() as CollisionObject3D
		if body and (body.collision_layer & 32) != 0:
			continue
		var vn := before.dot(n)
		if vn < best_vn:
			best_vn = vn
			best = hit
	if best == null:
		return
	var n := best.get_normal()
	velocity += n * (-best_vn) * WALL_BOUNCE
	var impulse := n * (-best_vn) * (1.0 + WALL_BOUNCE) * MASS
	var b := global_basis
	var spin := b * ((b.transposed() * (best.get_position() - com).cross(impulse)) / INERTIA)
	_ang_vel.y = clampf(_ang_vel.y + spin.y * WALL_SPIN, -2.5, 2.5)

## Нижняя точка шины совпадает с прежним контактом луча; радиус облика не меняет физику прототипа.
func _place_wheels() -> void:
	var visual_radius: float = LadaVisual.SEDANS[LadaVisual.PLAYER_MODEL]["wheel_r"]
	for i in mini(_pivots.size(), _len.size()):
		_pivots[i].position.y = _mounts[i].y - _len[i] + visual_radius - WHEEL_R

func reset_to(point: Vector3, facing_yaw: float) -> void:
	super.reset_to(point, facing_yaw)
	_ang_vel = Vector3.ZERO
	airborne_time = 0.0
	for i in _len.size():
		_len[i] = REST_LEN
	_place_wheels()

## Крен и тангаж тела, градусы (для тестов и кадров): крен + — правый борт ниже, тангаж + — нос вверх.
func roll_deg() -> float:
	return rad_to_deg(asin(clampf(-global_basis.x.y, -1.0, 1.0)))

func pitch_deg() -> float:
	return rad_to_deg(asin(clampf(-global_basis.z.y, -1.0, 1.0)))

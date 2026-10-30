class_name CameraRig
extends Node3D
## C4 — камера от третьего лица на SpringArm3D. Мышь крутит yaw/pitch, когда курсор захвачен.
## Профиль in_car использует DRIVE-01.

## Кадр по замеру эталона PLAY-01 (G02) и концептам 01, 04, 05: камера ближе и ниже, FOV 55°,
## в машине FOV растёт со скоростью (до +6°), пешком камера сама доворачивает за Илюшей (PLAY-02).
const PROFILES := {
	&"on_foot": {"distance": 4.3, "height": 1.9, "pitch": -0.17, "fov": 55.0},
	&"in_car": {"distance": 5.2, "height": 1.5, "pitch": -0.18, "fov": 55.0},   # «Лада» крупнее, к концепту 05 (итоговая сверка PLAY-02)
}
const FOV_PER_SPEED := 0.16     # градусов на м/с в машине
const FOV_SPEED_MAX := 6.0
const FOV_SHARPNESS := 4.0
const AUTO_FOLLOW_IDLE := 1.0   # с без мыши — камера начинает доворачивать за Илюшей
const AUTO_FOLLOW_RATE := 2.2   # 1/с
const AUTO_FOLLOW_MAX := 2.2    # рад: при ходьбе на камеру (разворот больше) не доворачивать
const PITCH_MIN := -1.1
const PITCH_MAX := 0.35
const FOLLOW_SHARPNESS := 14.0
const CHASE_SHARPNESS := 3.0

@export var mouse_sensitivity := 0.0025

var target: Node3D
var profile: StringName = &"on_foot"
## Любое присваивание yaw снаружи (мышь, сцена, тесты) переносит и input_yaw — опору ходьбы.
## Автодоводка меняет только yaw: пока нажаты те же клавиши, Илюша идёт прежним курсом и не закручивается
## по спирали; при смене клавиш он берёт новый yaw (sync_input_yaw).
var yaw := 0.0:
	set(value):
		yaw = value
		input_yaw = value
var input_yaw := 0.0
## Курс, за которым доворачивает камера пешком (Ilyusha задаёт его по взгляду), и скорость цели.
var follow_heading := 0.0
var follow_speed := 0.0
var _mouse_idle := 0.0
var pitch := -0.30
var arm: SpringArm3D
var camera: Camera3D
var permanent_exclusions: Array[RID] = []
## Плечевое смещение вправо, м: на время диалога камера уходит вбок, чтобы собеседник
## за спиной Илюши был виден (кадр 07). Меняется плавно.
var shoulder := 0.0
var _shoulder_now := 0.0
const SHOULDER_SHARPNESS := 5.0
## Пешком на время диалога (shoulder > 0) камера ближе: собеседник с 25–27 % высоты кадра становится ≈30 %,
## как Бабка на концепте 03 (LOOK-01: кадры диалога builds/screenshots/LOOK-01/).
const TALK_DISTANCE := 3.4
## POLISH-03 A: на время диалога пешком камера поворачивается к говорящему (кадр 07: окно киоска и продавщица в кадре,
## Илюша слева со спины), после — плавно возвращается к прежнему взгляду. Любая запись yaw снаружи (мышь, стик, сцена,
## тесты) снимает и поворот, и возврат.
const TALK_PITCH := -0.10        # почти горизонтально: окно и собеседник над панелью диалога
const TALK_AIM_BIAS := 0.25      # точка взгляда — от собеседника на четверть пути к Илюше: собеседник правее центра
const TALK_AIM_HEIGHT := 1.3     # м над землёй собеседника
const TALK_TURN_RATE := 4.0      # 1/с
const RETURN_RATE := 3.0         # 1/с
var talk_focus := Vector3.INF    # INF — нет собеседника
var _return_active := false
var _saved_yaw := 0.0
var _saved_pitch := 0.0
var _focus_written := NAN        # последнее значение yaw, записанное поворотом/возвратом
func _ready() -> void:
	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.collision_mask = 1  # только World
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	arm.shape = sphere
	add_child(arm)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = PROFILES[&"on_foot"]["fov"]
	camera.current = true
	arm.add_child(camera)

## instant = false: камера встаёт за новой целью сразу, а дистанция плавно меняется до профиля.
func follow(new_target: Node3D, new_profile: StringName = &"on_foot", instant := true) -> void:
	talk_focus = Vector3.INF
	_return_active = false
	target = new_target
	profile = new_profile
	pitch = PROFILES[profile]["pitch"]
	arm.clear_excluded_objects()
	for rid in permanent_exclusions:
		arm.add_excluded_object(rid)
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	snap(instant)

## Тела, которые не должны притягивать камеру (NPC рядом с героем).
func exclude_permanently(rid: RID) -> void:
	permanent_exclusions.append(rid)
	arm.add_excluded_object(rid)

## Мгновенно поставить камеру за целью, без сглаживания.
func snap(with_distance := true) -> void:
	if target:
		global_position = _goal()
		if with_distance:
			arm.spring_length = PROFILES[profile]["distance"]
			camera.fov = PROFILES[profile]["fov"]
		rotation = Vector3(pitch, yaw, 0.0)
		reset_physics_interpolation()

## Камера движется в физическом кадре вместе с целью; плавность между кадрами даёт интерполяция физики.
const STICK_LOOK_SPEED := 2.6   # рад/с при полном отклонении правого стика

func _physics_process(delta: float) -> void:
	if not target:
		return
	# Правый стик геймпада — как мышь (решение владельца 28.10.2026, вечер).
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick.length_squared() > 0.04 and profile != &"in_car":
		apply_mouse(stick * STICK_LOOK_SPEED * delta / mouse_sensitivity)
	global_position = global_position.lerp(_goal(), 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	if _update_talk(delta):
		pass   # POLISH-03 A: поворот к собеседнику или возврат ведёт yaw сам
	elif profile == &"in_car":
		# Камера преследования: плавно встаёт за машиной по её курсу.
		yaw = lerp_angle(yaw, target.global_rotation.y, 1.0 - exp(-CHASE_SHARPNESS * delta))
	elif follow_speed > 0.2:
		_mouse_idle += delta
		var diff := wrapf(follow_heading - yaw, -PI, PI)
		if _mouse_idle >= AUTO_FOLLOW_IDLE and absf(diff) < AUTO_FOLLOW_MAX:
			var keep := input_yaw
			yaw = yaw + diff * (1.0 - exp(-AUTO_FOLLOW_RATE * delta))
			input_yaw = keep
	else:
		_mouse_idle += delta
	var fov: float = PROFILES[profile]["fov"]
	if profile == &"in_car" and target is Lada:
		fov += minf(FOV_PER_SPEED * (target as Lada).speed_kmh() / 3.6, FOV_SPEED_MAX)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-FOV_SHARPNESS * delta))
	var distance: float = PROFILES[profile]["distance"]
	if shoulder > 0.0 and profile == &"on_foot":
		distance = TALK_DISTANCE
	arm.spring_length = lerpf(arm.spring_length, distance, 1.0 - exp(-4.0 * delta))
	_shoulder_now = lerpf(_shoulder_now, shoulder, 1.0 - exp(-SHOULDER_SHARPNESS * delta))
	rotation = Vector3(pitch, yaw, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse(event.relative)

## POLISH-03 A: повернуться к собеседнику в точке point (пешком; прежний взгляд запоминается для возврата).
func focus_talk(point: Vector3) -> void:
	if profile != &"on_foot" or target == null:
		return
	if talk_focus == Vector3.INF and not _return_active:
		_saved_yaw = yaw
		_saved_pitch = pitch
	talk_focus = point
	_return_active = false
	_focus_written = yaw

## Диалог закрыт: плавно вернуть прежний взгляд (если его не перехватили).
func release_talk() -> void:
	if talk_focus == Vector3.INF:
		return
	talk_focus = Vector3.INF
	_return_active = true

## Идёт поворот к собеседнику или возврат после диалога.
func is_talk_framing() -> bool:
	return talk_focus != Vector3.INF or _return_active

## Угол yaw, при котором собеседник в point оказывается в кадре правее центра, а Илюша — слева (плечо shoulder).
func talk_yaw(point: Vector3) -> float:
	var aim := point + (target.global_position - point) * TALK_AIM_BIAS
	var y := yaw
	for i in 3:
		var right := Vector3(cos(y), 0.0, -sin(y))
		var pivot := target.global_position + right * _shoulder_now
		var to := aim - pivot
		if Vector2(to.x, to.z).length() < 0.2:
			return y
		y = atan2(-to.x, -to.z)
	return y

func _update_talk(delta: float) -> bool:
	if not is_talk_framing():
		return false
	var walking_off := _return_active and follow_speed > 0.2   # пошёл сразу после диалога — курс не крутить
	if walking_off or profile != &"on_foot" or (not is_nan(_focus_written) and yaw != _focus_written):
		talk_focus = Vector3.INF   # yaw перехвачен (мышь, сцена, тест) или сели в машину — не спорить
		_return_active = false
		return false
	var k_rate := TALK_TURN_RATE if talk_focus != Vector3.INF else RETURN_RATE
	var goal_yaw := talk_yaw(talk_focus) if talk_focus != Vector3.INF else _saved_yaw
	var goal_pitch := TALK_PITCH if talk_focus != Vector3.INF else _saved_pitch
	var k := 1.0 - exp(-k_rate * delta)
	yaw = lerp_angle(yaw, goal_yaw, k)
	pitch = lerpf(pitch, goal_pitch, k)
	_focus_written = yaw
	if _return_active and absf(angle_difference(yaw, _saved_yaw)) < 0.01:
		yaw = _saved_yaw
		pitch = _saved_pitch
		_return_active = false
	_mouse_idle = 0.0
	return true

## Мышь вправо — камера вправо, мышь вверх — взгляд вверх.
func apply_mouse(relative: Vector2) -> void:
	_mouse_idle = 0.0
	talk_focus = Vector3.INF
	_return_active = false
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)

## Опора ходьбы догоняет камеру: вызывается при смене нажатых клавиш.
func sync_input_yaw() -> void:
	input_yaw = yaw

func _goal() -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return target.global_position + Vector3.UP * PROFILES[profile]["height"] + right * _shoulder_now

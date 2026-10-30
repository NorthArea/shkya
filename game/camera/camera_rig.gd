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
const AUTO_FOLLOW_IDLE := 1.0   # с без мыши и правого стика — ручная камера в приоритете, доводка ждёт паузы
const AUTO_FOLLOW_RATE := 2.2   # 1/с
## POLISH-03 C (критик 30.10, p0105/v05): доводка начинается через AUTO_FOLLOW_DELAY с ходьбы; при ходьбе на камеру
## (разворот больше AUTO_FOLLOW_MAX) камера тоже заводится за спину — позже (TURN_AROUND_DELAY) и в одну сторону,
## выбранную в начале облёта. Угловая скорость не больше AUTO_FOLLOW_SPEED и набирается за AUTO_FOLLOW_RAMP — без рывка.
const AUTO_FOLLOW_DELAY := 0.5  # с ходьбы до начала доводки
const AUTO_FOLLOW_MAX := 2.2    # рад: больше — «идёт на камеру», облёт за спину после TURN_AROUND_DELAY
const TURN_AROUND_DELAY := 0.8  # с ходьбы на камеру до облёта
const AUTO_FOLLOW_SPEED := 2.6  # рад/с: облёт на 180° ≈ 1,4 с
const AUTO_FOLLOW_RAMP := 0.35  # с: разгон угловой скорости доводки от нуля
## Тонкие столбы (фонари в валах, опоры, деревья, таблички) пружина камеры не замечает: за фонарём в валу камера
## впрыгивала к затылку и лицо Илюши занимало пол-экрана (критик 30.10, v05). Порог — по ширине коробки в плане.
const THIN_SOLID := 0.6         # м
## Пружина сжата стеной — камера приподнимается и чуть смотрит вниз, а не садится в затылок (доля сжатия × значение).
const WALL_LIFT := 0.5          # м
const WALL_TILT := 0.2          # рад
## Тонкий столб между головой и камерой (пружина его не замечает) — камера объезжает его вбок, не приближаясь:
## сдвиг вдоль «вправо» до DODGE_MAX так, чтобы линия взгляда прошла не ближе DODGE_CLEAR от оси столба.
const DODGE_CLEAR := 0.95       # м (с листовками на столбе — они общей сеткой и не прозрачнеют)
const DODGE_MAX := 1.1          # м
const DODGE_SHARPNESS := 6.0
## Столб ближе POLE_FADE_NEAR к камере (по земле) — полупрозрачный (GeometryInstance3D.transparency), не чёрная полоса.
const POLE_FADE_NEAR := 3.6     # м
const POLE_FADE := 0.75
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
var _walk_time := 0.0
var _follow_ramp := 0.0
var _swing_sign := 0.0          # сторона облёта при ходьбе на камеру (0 — не облетает)
var _lift := 0.0                # 0…1: сжатие пружины пешком, сглаженное
var _thin := {}                 # RID тонких столбов (exclude_thin_solids) → тело
var _dodge := 0.0               # м: текущий объезд столба вбок
var _faded := {}                # тело столба → его сетки, сейчас полупрозрачные
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
	call_deferred(&"exclude_thin_solids", get_parent())

## instant = false: камера встаёт за новой целью сразу, а дистанция плавно меняется до профиля.
func follow(new_target: Node3D, new_profile: StringName = &"on_foot", instant := true) -> void:
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

## Статичные тонкие тела мира (слой World, все формы в плане не шире THIN_SOLID) — в исключения пружины.
func exclude_thin_solids(root: Node) -> void:
	if root == null:
		return
	for body in root.find_children("*", "StaticBody3D", true, false):
		if body is AnimatableBody3D or (body as StaticBody3D).collision_layer & arm.collision_mask == 0:
			continue
		if _is_thin(body):
			exclude_permanently((body as StaticBody3D).get_rid())
			_thin[(body as StaticBody3D).get_rid()] = body

static func _is_thin(body: Node) -> bool:
	var shapes := 0
	for child in body.get_children():
		if not (child is CollisionShape3D):
			continue
		var shape: Shape3D = (child as CollisionShape3D).shape
		shapes += 1
		if shape is BoxShape3D:
			var size: Vector3 = (shape as BoxShape3D).size
			if maxf(size.x, size.z) > THIN_SOLID:
				return false
		elif shape is CylinderShape3D:
			if (shape as CylinderShape3D).radius * 2.0 > THIN_SOLID:
				return false
		elif shape is CapsuleShape3D:
			if (shape as CapsuleShape3D).radius * 2.0 > THIN_SOLID:
				return false
		else:
			return false
	return shapes > 0

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
	var dodge := _dodge_target() if profile == &"on_foot" else 0.0
	_dodge = lerpf(_dodge, dodge, 1.0 - exp(-DODGE_SHARPNESS * delta))
	global_position = global_position.lerp(_goal(), 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	if profile == &"in_car":
		# Камера преследования: плавно встаёт за машиной по её курсу.
		yaw = lerp_angle(yaw, target.global_rotation.y, 1.0 - exp(-CHASE_SHARPNESS * delta))
	else:
		_mouse_idle += delta
		_auto_follow(delta)
	var fov: float = PROFILES[profile]["fov"]
	if profile == &"in_car" and target is Lada:
		fov += minf(FOV_PER_SPEED * (target as Lada).speed_kmh() / 3.6, FOV_SPEED_MAX)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-FOV_SHARPNESS * delta))
	var distance: float = PROFILES[profile]["distance"]
	if shoulder > 0.0 and profile == &"on_foot":
		distance = TALK_DISTANCE
	arm.spring_length = lerpf(arm.spring_length, distance, 1.0 - exp(-4.0 * delta))
	_shoulder_now = lerpf(_shoulder_now, shoulder, 1.0 - exp(-SHOULDER_SHARPNESS * delta))
	var squeeze := 0.0
	if profile == &"on_foot" and arm.spring_length > 0.5:
		squeeze = clampf((arm.spring_length - arm.get_hit_length()) / arm.spring_length, 0.0, 1.0)
	_lift = lerpf(_lift, squeeze, 1.0 - exp(-6.0 * delta))
	rotation = Vector3(pitch - _lift * WALL_TILT, yaw, 0.0)
	_fade_near_poles()

## Доводка пешком (PLAY-02, POLISH-03 C): только после паузы ручной камеры и AUTO_FOLLOW_DELAY ходьбы; при ходьбе на
## камеру — облёт за спину после TURN_AROUND_DELAY. Меняет только yaw: курс ходьбы (input_yaw) прежний, пока те же клавиши.
func _auto_follow(delta: float) -> void:
	if follow_speed <= 0.2:
		_walk_time = 0.0
		_follow_ramp = 0.0
		_swing_sign = 0.0
		return
	_walk_time += delta
	var diff := wrapf(follow_heading - yaw, -PI, PI)
	var facing_camera := absf(diff) >= AUTO_FOLLOW_MAX
	if facing_camera and _swing_sign == 0.0:
		_swing_sign = 1.0 if diff >= 0.0 else -1.0
	elif not facing_camera and absf(diff) < AUTO_FOLLOW_MAX - 0.3:
		_swing_sign = 0.0
	if _swing_sign != 0.0 and signf(diff) != _swing_sign:
		diff += TAU * _swing_sign   # у ±π не перекидываться на другую сторону
	var wait := TURN_AROUND_DELAY if _swing_sign != 0.0 else AUTO_FOLLOW_DELAY
	if _mouse_idle < AUTO_FOLLOW_IDLE or _walk_time < wait:
		_follow_ramp = 0.0
		return
	_follow_ramp = minf(_follow_ramp + delta / AUTO_FOLLOW_RAMP, 1.0)
	var ease := _follow_ramp * _follow_ramp * (3.0 - 2.0 * _follow_ramp)
	var step := diff * (1.0 - exp(-AUTO_FOLLOW_RATE * delta))
	step = clampf(step, -AUTO_FOLLOW_SPEED * delta, AUTO_FOLLOW_SPEED * delta) * ease
	var keep := input_yaw
	yaw = wrapf(yaw + step, -PI, PI)
	input_yaw = keep

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse(event.relative)

## Мышь вправо — камера вправо, мышь вверх — взгляд вверх.
func apply_mouse(relative: Vector2) -> void:
	_mouse_idle = 0.0
	_follow_ramp = 0.0
	yaw = wrapf(yaw - relative.x * mouse_sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)

## Опора ходьбы догоняет камеру: вызывается при смене нажатых клавиш.
func sync_input_yaw() -> void:
	input_yaw = yaw

## Сдвиг вбок, чтобы тонкий столб не закрывал Илюшу: столбы ближе DODGE_CLEAR (в плане) к отрезку «голова — несдвинутая
## камера» на отрезке до стены (длина пружины). Считается по несдвинутой линии — без качелей «объехал → вернулся».
func _dodge_target() -> float:
	if _thin.is_empty() or target == null:
		return 0.0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var origin := target.global_position + right * _shoulder_now
	var reach := minf(arm.spring_length, arm.get_hit_length() + 0.3)
	var want := 0.0
	for body in _thin.values():
		var node := body as Node3D
		if not is_instance_valid(node):
			continue
		var rel := node.global_position - origin
		var along := rel.x * back.x + rel.z * back.z
		if along < 0.4 or along > reach:
			continue
		var off := rel.x * right.x + rel.z * right.z
		if absf(off) >= DODGE_CLEAR:
			continue
		var need := (-1.0 if off >= 0.0 else 1.0) * (DODGE_CLEAR - absf(off))
		if absf(need) > absf(want):
			want = need
	return clampf(want, -DODGE_MAX, DODGE_MAX)

## Тонкие столбы у самой камеры — полупрозрачные; отошли — снова сплошные.
func _fade_near_poles() -> void:
	if _thin.is_empty() or camera == null:
		return
	var at := camera.global_position
	for body in _thin.values():
		var node := body as Node3D
		if not is_instance_valid(node):
			continue
		var near := Vector2(node.global_position.x - at.x, node.global_position.z - at.z).length() < POLE_FADE_NEAR
		if near == _faded.has(node):
			continue
		if near:
			var meshes := node.find_children("*", "GeometryInstance3D", true, false)
			_faded[node] = meshes
			for m in meshes:
				(m as GeometryInstance3D).transparency = POLE_FADE
		else:
			for m in _faded[node]:
				if is_instance_valid(m):
					(m as GeometryInstance3D).transparency = 0.0
			_faded.erase(node)

## Столбы, полупрозрачные сейчас (для проверок).
func faded_poles() -> Array:
	return _faded.keys()

func _goal() -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return target.global_position + Vector3.UP * (float(PROFILES[profile]["height"]) + _lift * WALL_LIFT) + right * (_shoulder_now + _dodge)

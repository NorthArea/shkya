extends RefCounted
## Автопилот для тестов и кадров QUEST-01: ведёт настоящую «Ладу» только управляющим вводом
## (move_forward/back/left/right), как игрок. Телепортов машины здесь нет.

var tree: SceneTree
var world: DemoWorld

func _init(scene_tree: SceneTree, demo_world: DemoWorld) -> void:
	tree = scene_tree
	world = demo_world

func release_all() -> void:
	for action in [&"car_gas", &"car_brake", &"move_left", &"move_right"]:
		Input.action_release(action)

func speed() -> float:
	var car: Lada = world.car
	return Vector3(car.velocity.x, 0.0, car.velocity.z).dot(-car.global_basis.z)

## Одно управляющее воздействие к точке; возвращает расстояние до неё.
func steer_to(point: Vector3, vmax: float, reverse := false) -> float:
	var car: Lada = world.car
	var to := point - car.global_position
	to.y = 0.0
	var dist := to.length()
	var want := atan2(-to.x, -to.z)
	var heading := car.global_rotation.y
	var err := wrapf(want - (heading + (PI if reverse else 0.0)), -PI, PI)
	var steer := clampf(err * 2.0, -1.0, 1.0)
	if reverse:
		steer = -steer  # задним ходом поворот руля инвертируется
	_apply_steer(steer)
	var limit := vmax
	if absf(err) > 0.6:
		limit = minf(limit, 5.0)
	if dist < 12.0:
		limit = minf(limit, 6.0)
	var v := speed()
	if reverse:
		_throttle(-1.0 if v > -limit else 0.0)
	elif v < limit:
		_throttle(1.0)
	elif v > limit + 3.0:
		_throttle(-1.0)
	else:
		_throttle(0.0)
	return dist

## Проехать по точкам (вперёд или задним ходом). false — не уложились в max_frames на точку.
func drive(points: Array, vmax := 12.0, tol := 6.0, reverse := false, max_frames := 2400) -> bool:
	for p in points:
		var frames := 0
		while steer_to(p, vmax, reverse) > tol:
			await tree.physics_frame
			frames += 1
			if frames > max_frames:
				release_all()
				return false
	return true

## Затормозить до остановки.
func stop(max_frames := 600) -> bool:
	var frames := 0
	_apply_steer(0.0)
	while absf(speed()) > 0.4:
		_throttle(-1.0 if speed() > 0.0 else 1.0)
		await tree.physics_frame
		frames += 1
		if frames > max_frames:
			release_all()
			return false
	release_all()
	await tree.physics_frame
	return true

## Разворот на месте проезда: ехать вперёд с полным рулём, пока курс не станет ≈ target_yaw.
## Упёрлись в вал — сдать назад с обратным рулём и продолжить, как игрок в три приёма
## (PLAY-02: радиус разворота по эталону шире улицы Б). direction: +1 — влево, -1 — вправо.
func turn_to(target_yaw: float, direction: float, max_frames := 900) -> bool:
	var frames := 0
	var blocked := 0
	while absf(wrapf(target_yaw - world.car.global_rotation.y, -PI, PI)) > 0.3:
		if blocked > 20:
			for i in 70:
				_apply_steer(-direction)
				_throttle(-1.0 if speed() > -3.0 else 0.0)
				await tree.physics_frame
			blocked = 0
			frames += 70
		_apply_steer(direction)
		_throttle(1.0 if speed() < 4.0 else 0.0)
		await tree.physics_frame
		blocked = blocked + 1 if absf(speed()) < 0.3 else 0
		frames += 1
		if frames > max_frames:
			release_all()
			print("INFO: turn_to failed at %s, yaw %.2f, speed %.1f" % [world.car.global_position, world.car.global_rotation.y, speed()])
			return false
	release_all()
	return true

func _apply_steer(steer: float) -> void:
	if steer > 0.0:
		Input.action_release(&"move_right")
		Input.action_press(&"move_left", steer)
	elif steer < 0.0:
		Input.action_release(&"move_left")
		Input.action_press(&"move_right", -steer)
	else:
		Input.action_release(&"move_left")
		Input.action_release(&"move_right")

func _throttle(value: float) -> void:
	if value > 0.0:
		Input.action_release(&"car_brake")
		Input.action_press(&"car_gas")
	elif value < 0.0:
		Input.action_release(&"car_gas")
		Input.action_press(&"car_brake")
	else:
		Input.action_release(&"car_gas")
		Input.action_release(&"car_brake")

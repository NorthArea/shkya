extends RefCounted
## QA-01: игрок-автомат для независимой приёмки. Всё, что он делает с игрой, — ввод:
## оси ходьбы и руления — Input.action_press/release (как клавиатура или стик),
## E, Esc, кнопки меню и диалогов — InputEventAction через Input.parse_input_event
## (кнопки — фокусом ui_left/ui_right/ui_up/ui_down и ui_accept, панель финала — щелчком мыши).
## Телепортов, place()/reset_to() и вызовов MissionDirector здесь нет: автомат только читает
## положение героя, машины и камеры, чтобы решить, какую клавишу жать.

const MOVE: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]

var tree: SceneTree
var main: Node
## Последняя причина неудачи шага — для лога.
var last_error := ""
## Вызывается каждый физический кадр, пока автомат ждёт (монитор инвариантов теста).
var on_frame: Callable

func _init(scene_tree: SceneTree, main_node: Node) -> void:
	tree = scene_tree
	main = main_node

func world() -> DemoWorld:
	return main.world

# --- время ---

func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
		if on_frame.is_valid():
			on_frame.call()

# --- клавиши ---

func release_all() -> void:
	for action in MOVE:
		Input.action_release(action)
	Input.action_release(&"handbrake")

## Нажать и отпустить действие (E, Esc, ui_accept…). Событие идёт обычным путём ввода.
func tap(action: StringName, hold := 2) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	down.strength = 1.0
	Input.parse_input_event(down)
	await frames(hold)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)

func interact() -> void:
	await tap(&"interact")

func pause_key() -> void:
	await tap(&"pause")

## Текущий владелец фокуса GUI.
func focused() -> Control:
	return tree.root.gui_get_focus_owner()

## Перевести фокус на кнопку с текстом text стрелками и нажать ui_accept. false — кнопка недостижима.
func press_button(text: String, nav: StringName = &"ui_right", tries := 6) -> bool:
	await frames(2)  # меню и диалоги берут фокус отложенно
	for i in tries + 1:
		var owner := focused()
		if owner is Button and (owner as Button).text == text and owner.is_visible_in_tree():
			if (owner as Button).disabled:
				last_error = "button '%s' is disabled" % text
				return false
			await tap(&"ui_accept")
			await frames(2)
			return true
		await tap(nav)
	var owner := focused()
	last_error = "focus never reached '%s' (focus on %s)" % [text, owner.text if owner is Button else str(owner)]
	return false

## Щелчок левой кнопкой мыши по центру кнопки (для панелей, которые не берут фокус клавиатуры).
func click(control: Control) -> void:
	var at: Vector2 = tree.root.get_final_transform() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await frames(2)
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = at
		button.global_position = at
		Input.parse_input_event(button)
		await frames(2)

# --- ходьба: направление в мире переводится в оси относительно камеры, как это делает игрок ---

func _walk_axes(world_dir: Vector3) -> void:
	var local := world_dir.rotated(Vector3.UP, -world().camera_rig.yaw)
	_axis(&"move_right", &"move_left", local.x)
	_axis(&"move_back", &"move_forward", local.z)

func _axis(positive: StringName, negative: StringName, value: float) -> void:
	if value > 0.02:
		Input.action_release(negative)
		Input.action_press(positive, clampf(value, 0.0, 1.0))
	elif value < -0.02:
		Input.action_release(positive)
		Input.action_press(negative, clampf(-value, 0.0, 1.0))
	else:
		Input.action_release(positive)
		Input.action_release(negative)

## Дойти до точки. false — не дошёл (упёрся или кончились кадры).
func walk_to(target: Vector3, tolerance := 0.35, max_frames := 2400) -> bool:
	var player := world().player
	var best := INF
	var stall := 0
	for i in max_frames:
		var to := target - player.global_position
		to.y = 0.0
		var distance := to.length()
		if distance <= tolerance:
			release_all()
			await frames(12)  # погасить скорость
			return true
		_walk_axes(to.normalized() * clampf(distance / 1.2, 0.35, 1.0))
		await frames(1)
		if distance < best - 0.02:
			best = distance
			stall = 0
		else:
			stall += 1
			if stall > 150:
				release_all()
				last_error = "walk stalled at %s, %.2f m from %s" % [player.global_position, distance, target]
				return false
	release_all()
	last_error = "walk timeout at %s, target %s" % [player.global_position, target]
	return false

func walk_path(points: Array, tolerance := 0.6) -> bool:
	for i in points.size():
		var tol := tolerance if i < points.size() - 1 else 0.35
		if not await walk_to(points[i], tol):
			return false
	return true

# --- стелс у киоска (EXT-01): автомат читает, куда смотрит полицейский, и выжидает за укрытием ---

## Полицейский у киоска (LevelGeometry/Patrols/Officer) или null.
func officer() -> Node3D:
	var patrols := world().get_node_or_null("LevelGeometry/Patrols")
	return patrols.officer if patrols else null

## Дождаться, пока полицейский заново развернётся на угол facings[index] и встанет: если он уже смотрит туда,
## сначала дождаться, пока отвернётся (осторожный игрок не знает, сколько ему осталось стоять). false — не дождался.
func wait_officer_turn(index: int, max_frames := 1500, o: Node3D = null) -> bool:
	release_all()
	if o == null:
		o = officer()
	var waited := 0
	while o.facing_index() == index and waited < max_frames:
		await frames(1)
		waited += 1
	while (o.facing_index() != index or o.is_turning() or o.is_moving()) and waited < max_frames:
		await frames(1)
		waited += 1
	if waited >= max_frames:
		last_error = "officer never turned to facing %d" % index
		return false
	return true

## Второй наблюдатель у киоска (LevelGeometry/Patrols/Officer2, EXT-01 fix3) или null.
func officer2() -> Node3D:
	var patrols := world().get_node_or_null("LevelGeometry/Patrols")
	return patrols.officer2 if patrols else null

## Пройти укрытие → выждать разворот → пройти открытый участок. sneak: [[точки до укрытия], индекс угла, [точки после]].
## EXT-01 fix4: с safe_facing2 ≥ 0 — в конце after выждать разворот второго поста (Officer2) на этот угол и пройти after2.
func sneak(to_cover: Array, safe_facing: int, after: Array, safe_facing2 := -1, after2: Array = []) -> bool:
	if not await walk_path(to_cover):
		return false
	if not await wait_officer_turn(safe_facing):
		return false
	if safe_facing2 < 0:
		return await walk_path(after)
	if not await walk_path(after):
		return false
	if not await wait_officer_turn(safe_facing2, 1500, officer2()):
		return false
	return await walk_path(after2)

## Честный путь Layout.SNEAK_*: три элемента [до укрытия, угол, после] или пять (SNEAK_WEST, fix4: …, угол второго поста,
## после).
func sneak_route(route: Array) -> bool:
	if route.size() >= 5:
		return await sneak(route[0], route[1], route[2], route[3], route[4])
	return await sneak(route[0], route[1], route[2])

# --- езда: руль и газ по курсу на точку маршрута ---

func forward_speed() -> float:
	var car: Lada = world().car
	return Vector3(car.velocity.x, 0.0, car.velocity.z).dot(-car.global_basis.z)

func _steer_and_throttle(target: Vector3, wanted_speed: float) -> float:
	var car: Lada = world().car
	var to := target - car.global_position
	to.y = 0.0
	var want := atan2(-to.x, -to.z)
	var error := wrapf(want - car.global_rotation.y, -PI, PI)
	_axis(&"move_left", &"move_right", clampf(error * 2.5, -1.0, 1.0))
	var limit := wanted_speed
	if absf(error) > 0.5:
		limit = minf(limit, 5.0)
	var v := forward_speed()
	if v < limit - 0.5:
		_axis(&"move_forward", &"move_back", 1.0)
	elif v > limit + 2.0:
		_axis(&"move_forward", &"move_back", -1.0)
	else:
		_axis(&"move_forward", &"move_back", 0.0)
	return to.length()

## Проехать по точкам. Перед крутым поворотом и на последней точке — сбросить скорость.
## stop_at: функция без аргументов; true — прервать поездку (например, «выйти посреди пути»).
func drive_path(points: Array, top_speed := 13.0, tolerance := 5.0, stop_at := Callable()) -> bool:
	var car: Lada = world().car
	for i in points.size():
		var target: Vector3 = points[i]
		var last := i == points.size() - 1
		var turn := 0.0
		if not last:
			var here: Vector3 = target - (points[i - 1] if i > 0 else car.global_position)
			var next: Vector3 = points[i + 1] - target
			turn = absf(Vector2(here.x, here.z).angle_to(Vector2(next.x, next.z)))
		var tol := 2.5 if last else tolerance
		var stuck := 0
		var backups := 0
		var frames_left := 3600
		while true:
			var to := target - car.global_position
			to.y = 0.0
			var distance := to.length()
			if distance <= tol:
				break
			var speed := top_speed
			if (last or turn > 0.7) and distance < 18.0:
				speed = minf(speed, 4.0 if last else 7.0)
			_steer_and_throttle(target, speed)
			await frames(1)
			if stop_at.is_valid() and stop_at.call():
				return true
			stuck = stuck + 1 if absf(forward_speed()) < 0.3 else 0
			frames_left -= 1
			# Упёрлись носом (разворот на узкой улице): сдать назад с обратным рулём, как игрок в три приёма
			# (PLAY-02: радиус разворота по эталону шире улицы Б).
			if stuck == 40 and backups < 4:
				backups += 1
				var error := wrapf(atan2(-to.x, -to.z) - car.global_rotation.y, -PI, PI)
				for k in 70:
					_axis(&"move_left", &"move_right", -signf(error))
					_axis(&"move_forward", &"move_back", -1.0 if forward_speed() > -3.0 else 0.0)
					await frames(1)
				stuck = 0
			if stuck > 180 or frames_left <= 0:
				release_all()
				last_error = "drive stuck at %s, %.1f m from point %d %s" % [car.global_position, distance, i, target]
				return false
	return true

## Затормозить до остановки.
func brake(max_frames := 600) -> bool:
	_axis(&"move_left", &"move_right", 0.0)
	for i in max_frames:
		var v := forward_speed()
		if absf(v) < 0.3:
			release_all()
			await frames(3)
			return true
		_axis(&"move_forward", &"move_back", -signf(v))
		await frames(1)
	release_all()
	last_error = "car did not stop"
	return false

## Ехать носом в точку, пока машина не упрётся (неудачная парковка). Возвращает число кадров упора.
func ram(point: Vector3, max_frames := 900) -> int:
	var pinned := 0
	var moving := false
	for i in max_frames:
		_steer_and_throttle(point, 9.0)
		_axis(&"move_forward", &"move_back", 1.0)
		await frames(1)
		var v := absf(forward_speed())
		if v > 3.0:
			moving = true
		if moving and v < 0.3:
			pinned += 1
			if pinned >= 60:
				break
	release_all()
	await frames(3)
	return pinned

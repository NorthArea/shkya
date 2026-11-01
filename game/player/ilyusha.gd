class_name Ilyusha
extends CharacterBody3D
## Илюша пешком: ходьба относительно камеры, взаимодействие по E (C3).
## Visual — облик ШКЯ в зимнем костюме (ART-01, CharacterSprite); поворот Visual = взгляд Илюши.
## EXT-02 (C7, docs/extension/HIDE_SPOTS.md раздел 9): режим укрытия hide_mode (&"none", &"box", &"snowdrift",
## &"barrel") — предел скорости speed_limit(), без прыжка, заметность exposure_factor() для DetectionSensor.
## Облик укрытия кладёт HideSpot в hide_visual (дочерний Visual); спрайт Илюши в режиме скрыт, тело и коллизия те же.
## PUNCH-01: удар (действие punch — F, ЛКМ при захваченной мыши, B геймпада пешком): замах PUNCH_SWING с рывком облика
## вперёд (пружина, как pop в POLISH-02), в момент PUNCH_HIT_AT — запрос формой: сфера PUNCH_RADIUS в PUNCH_REACH
## перед Илюшей на высоте PUNCH_CENTER_Y (области — только в полосе PUNCH_LOW…PUNCH_HIGH над землёй); кулдаун
## PUNCH_COOLDOWN от нажатия. В укрытии, в машине, в диалоге и при провале стелса удара нет. Цели — владельцы
## задетых объектов: дроны (Area3D слоя 16) и NPC (есть interaction_id); реагируют подписчики punch_landed (Drones).
## К Илюше узлов не добавляется (инвариант DEMO_ACCEPTANCE 3): запрос — через direct_space_state.

const CharacterSpriteScript = preload("res://game/characters/character_sprite.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")

const WALK_SPEED := 4.0
const RUN_SPEED := 8.0          # удерживаемый бег; своя настройка по разделению walk/turbo в C++
const ACCELERATION := 30.0
const DECELERATION := 11.0      # прежнее торможение укрытий
const GROUND_BRAKE := 24.0      # обычный ход: короткая остановка без скольжения после отпускания
const MOTION_ACCELERATION := 40.0 # ограничение изменения фактической скорости, включая разворот
const INPUT_SPEED_SCALE := 0.69 # нормализация квадратной аналоговой кривой; C++ Character::GetInputScale
const INPUT_TURN_THRESHOLD := 0.01 # рад: направление должно выйти из зоны дрожания стика
const TURN_RATE := 12.0
const AIR_ACCELERATION := 8.0   # м/с²: ввод добавляет управление к скорости отрыва, без тормоза при отпускании
const PROBE_RADIUS := 0.5
const JUMP_VELOCITY := 6.0        # подскок ≈1,8 м: на крышу «Лады» (1,4 м) с запасом — решение владельца 28.10.2026
# PUNCH-01: удар.
const PUNCH_SWING := 0.35         # с: весь замах (рывок вперёд и пружина назад)
const PUNCH_HIT_AT := 0.14        # с от нажатия: пик рывка — момент попадания
const PUNCH_COOLDOWN := 0.5       # с между ударами (от нажатия)
const PUNCH_RADIUS := 1.2
const PUNCH_REACH := 1.0          # м: центр сферы перед Илюшей
const PUNCH_CENTER_Y := 1.55      # м: середина полосы 0,8…2,3
const PUNCH_LOW := 0.8
const PUNCH_HIGH := 2.3
const PUNCH_LUNGE := 0.38         # м: рывок облика вперёд
const PUNCH_MASK := 1 | 4 | 16 | 32    # World (Бабка, патруль), Car (жители), 16 — дроны (Drones.HIT_LAYER), 32 — разрушаемые (BREAK-01)

## Режим укрытия сменился (old → new). Подписчики — укрытия и HUD; шкалу не трогает.
signal hide_mode_changed(old: StringName, new: StringName)
## PUNCH-01: начат замах (звук) и попадание — владельцы задетых целей (дроны, NPC); удар мимо — без punch_landed.
signal punched
signal punch_landed(targets: Array)

var input_enabled := true
var camera_rig: CameraRig
var visual: Node3D
var probe: Area3D
## Режим укрытия: &"none" или один из HideTuning.MODES; менять только set_hide_mode()/force_hide_mode().
var hide_mode: StringName = HideTuning.NONE
## Укрытие, которое включило режим (зона Interactable); в режиме E без других зон уходит ему. null — нет.
var hide_owner: Node = null
## Контейнер обликов укрытий (дочерний Visual, поворачивается с Илюшей). При переходе в &"none" очищается.
var hide_visual: Node3D
## Фактический путь в плоскости XZ с последней смены режима, м (вращение бочки «по пройденному пути»).
var hide_travel := 0.0
var _look: Node3D
var _basis_input := Vector2.ZERO # направление последней привязки ввода к камере
var _ground_speed := 0.0
var _air_speed_limit := WALK_SPEED # сохраняет импульс разбега после отпускания бега в прыжке
## PUNCH-01: сколько ударов начато и сколько задели цель; цели последнего попадания.
var punches := 0
var punch_hits := 0
var last_punch_targets: Array = []
var _punch_time := -1.0          # с с начала замаха; < 0 — замаха нет
var _punch_pending := false      # попадание ещё не считали
var _punch_cooldown := 0.0
var _punch_tween: Tween
var _punch_shape: SphereShape3D

func _ready() -> void:
	collision_layer = 2       # Player
	collision_mask = 1 | 4 | 32 | 64   # World, Car, Breakable (BREAK-01), SnowBank (DRIVE-02: валы — стена пешеходу)
	# Без привязки к полу: квартал плоский, ступеней и спусков нет. Привязка 0,3 м при упоре в вертикальное ребро
	# коробки (угол дома, торец вала снега) проваливала Илюшу в землю на 0,15–0,30 м (POLISH-01, tests/polish01_stuck.gd).
	floor_snap_length = 0.0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = capsule
	collider.position.y = 0.75
	add_child(collider)
	visual = _build_visual()
	add_child(visual)
	probe = Area3D.new()
	probe.name = "InteractProbe"
	probe.collision_layer = 0
	probe.collision_mask = 8  # Interact
	probe.monitorable = false
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_RADIUS
	var probe_shape := CollisionShape3D.new()
	probe_shape.shape = sphere
	probe_shape.position.y = 0.9
	probe.add_child(probe_shape)
	add_child(probe)
	_punch_shape = SphereShape3D.new()
	_punch_shape.radius = PUNCH_RADIUS
	visibility_changed.connect(_cancel_punch)   # посадка в машину прячет Илюшу: замах не доигрывается

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# Опора курса меняется при новом направлении, но не от силы или дрожания стика.
	# Сравнение с последней привязкой позволяет медленному намеренному повороту накопиться.
	var input_direction := input.normalized()
	var starts_or_stops := input_direction.is_zero_approx() != _basis_input.is_zero_approx()
	if starts_or_stops or absf(_basis_input.angle_to(input_direction)) >= INPUT_TURN_THRESHOLD:
		if camera_rig:
			camera_rig.sync_input_yaw()
		_basis_input = input_direction
	var yaw := camera_rig.input_yaw if camera_rig else 0.0
	var limit := speed_limit()
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	if limit <= 0.0:
		direction = Vector3.ZERO   # сугроб: движения и поворота нет
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if not input_enabled:
		horizontal = Vector3.ZERO
		_ground_speed = 0.0
		_air_speed_limit = WALK_SPEED
	elif hide_mode != HideTuning.NONE:
		# Укрытия сохраняют прежние пределы и остановку.
		var rate := ACCELERATION if direction.length_squared() > 0.01 else DECELERATION
		horizontal = horizontal.move_toward(direction * limit, rate * delta)
		_ground_speed = horizontal.length()
	elif is_on_floor():
		# Желаемая скорость и фактическое движение разделены: разворот проходит через короткое торможение.
		# Нелинейная кривая применяется после штатной мёртвой зоны Input.get_vector().
		var strength := direction.length()
		var wanted_speed := minf(strength * strength / INPUT_SPEED_SCALE, 1.0) * limit
		# После столкновения velocity содержит только остаток скольжения. Повторное использование
		# его длины как скорости разгона каждый кадр гасило касательное движение вдоль стены.
		if strength <= 0.0:
			_ground_speed = horizontal.length()
		var rate := ACCELERATION if wanted_speed > _ground_speed else GROUND_BRAKE
		_ground_speed = move_toward(_ground_speed, wanted_speed, rate * delta)
		var wanted_velocity := (direction.normalized() if strength > 0.0 else horizontal.normalized()) * _ground_speed
		horizontal = horizontal.move_toward(wanted_velocity, MOTION_ACCELERATION * delta)
	else:
		# В воздухе нет наземного тормоза: отпускание оставляет дрейф, ввод меняет импульс постепенно.
		horizontal = (horizontal + direction * direction.length() * AIR_ACCELERATION * delta).limit_length(limit)
		_ground_speed = horizontal.length()
	if is_on_floor():
		_air_speed_limit = maxf(limit, horizontal.length())
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		var jump := input_enabled and hide_mode == HideTuning.NONE and Input.is_action_just_pressed(&"jump")
		velocity.y = JUMP_VELOCITY if jump else 0.0
	else:
		velocity.y -= get_gravity().length() * delta
	var before := global_position
	# При прямом задании курса малый касательный ввод должен давать скольжение, а не
	# остановку под штатным углом 15°. Укрытия сохраняют прежнюю контактную динамику.
	var wall_angle := wall_min_slide_angle
	if input_enabled and hide_mode == HideTuning.NONE and is_on_floor():
		wall_min_slide_angle = 0.0
	var impact_speed := velocity.y
	move_and_slide()
	wall_min_slide_angle = wall_angle
	hide_travel += Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if direction.length_squared() > 0.01:
		var facing := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, facing, clampf(TURN_RATE * delta, 0.0, 1.0))
	if camera_rig and camera_rig.target == self:
		# Курс доводки — направление ввода, а не плавно поворачивающийся облик: иначе при ходьбе
		# на камеру она рывком облетала героя (повторная сверка PLAY-02, P2).
		if direction.length_squared() > 0.01:
			camera_rig.follow_heading = atan2(-direction.x, -direction.z)
		camera_rig.follow_speed = Vector2(velocity.x, velocity.z).length() if input_enabled else 0.0
	_punch_step(delta)
	var pose_mode := &"locomotion"
	if hide_mode != HideTuning.NONE or not visible:
		pose_mode = &"hidden"
	elif _punch_time >= 0.0:
		pose_mode = &"punch"
	_look.submit_locomotion((global_position - before) / delta if delta > 0 else Vector3.ZERO,
		is_on_floor(), pose_mode, impact_speed, maxf(0.0, _punch_time / PUNCH_SWING))

func _unhandled_input(event: InputEvent) -> void:
	# ЛКМ при свободной мыши — только захват мыши (Main), не удар; событие не съедаем — Main захватит мышь.
	if event.is_action_pressed(&"punch") and not (event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		punch()
	if input_enabled and event.is_action_pressed(&"interact"):
		var target := current_interactable()
		if target:
			get_viewport().set_input_as_handled()
			target.interact(self)

## Ближайшая доступная зона взаимодействия, в которой стоит Илюша. В укрытии, если других зон рядом нет или
## ближайшая — другое укрытие (группа hide_spots), — зона своего укрытия hide_owner (снять коробку, вылезти — где
## угодно, и у бочки, и у сугроба); у квестовой зоны (Бабка, продавщица, «Лада», наблюдатели) — она сама: E снимает
## укрытие и показывает отказ (DemoWorld.refuse_in_hide), следующий E — обычное действие (приёмка EXT-02, P2-2).
func current_interactable() -> Interactable:
	if not input_enabled:
		return null
	var best: Interactable = null
	var best_distance := INF
	# Квестовая зона (Бабка, продавщица, «Лада», наблюдатели) важнее зоны укрытия, даже если укрытие ближе:
	# иначе брошенные у двери коробка/бочка по E надевались снова (приёмка EXT-02, P2).
	for area in probe.get_overlapping_areas():
		if area is Interactable and area.enabled and area.prompt != "":
			var is_hide := area.is_in_group(&"hide_spots")
			var distance := global_position.distance_squared_to(area.global_position)
			if is_hide:
				distance += 1000.0   # укрытия — после всех квестовых зон
			if distance < best_distance:
				best = area
				best_distance = distance
	if hide_mode != HideTuning.NONE and (best == null or (best != hide_owner and best.is_in_group(&"hide_spots"))):
		best = null
		if is_instance_valid(hide_owner) and hide_owner is Interactable:
			var own: Interactable = hide_owner
			if own.enabled and own.prompt != "":
				best = own
	return best

## Поставить на точку и остановить (появление, перезапуск, выход из машины).
func place(point: Vector3, facing_yaw: float) -> void:
	global_position = point
	velocity = Vector3.ZERO
	_ground_speed = 0.0
	_air_speed_limit = WALK_SPEED
	_basis_input = Vector2.ZERO
	visual.rotation.y = facing_yaw
	reset_physics_interpolation()

# --- EXT-02: укрытия ---

## Укрытия сохраняют свои пределы. В воздухе остаётся предел последнего наземного шага.
func speed_limit() -> float:
	if hide_mode != HideTuning.NONE:
		return HideTuning.speed_for(hide_mode, WALK_SPEED)
	if not is_on_floor():
		return _air_speed_limit
	return RUN_SPEED if input_enabled and Input.is_action_pressed(&"sprint") else WALK_SPEED

## Стоит: горизонтальная скорость меньше HideTuning.STILL_SPEED (0,1 м/с).
func is_still() -> bool:
	return Vector2(velocity.x, velocity.z).length() < HideTuning.STILL_SPEED

## Коэффициент заметности 0…1 для наблюдателя с глазами в eye_position (таблица 5.3 HIDE_SPOTS.md).
## «Вплотную» — ближе HideTuning.CLOSE_RADIUS в плоскости XZ.
func exposure_factor(eye_position: Vector3) -> float:
	var close := Vector2(eye_position.x - global_position.x, eye_position.z - global_position.z).length() <= HideTuning.CLOSE_RADIUS
	return HideTuning.exposure_for(hide_mode, is_still(), close)

## Можно ли сейчас менять режим: не в машине, нет диалога, провала и блокирующей панели (раздел 9).
func can_change_hide_mode() -> bool:
	var world := get_parent()
	if world == null or world.get("control_mode") == null:
		return true
	if world.get("control_mode") == &"in_car" or world.get("ui_blocking") == true:
		return false
	if world.has_method("is_stealth_failing") and world.is_stealth_failing():
		return false
	var flow: Variant = world.get("quest_flow")
	if flow is Node and (flow as Node).has_method("is_dialog_open") and flow.is_dialog_open():
		return false
	return true

## Сменить режим укрытия. spot — зона укрытия (для E «вылезти» вдали от неё). Переход только через &"none":
## из одного укрытия сразу в другое — false. false и без изменений, если can_change_hide_mode() запрещает.
func set_hide_mode(mode: StringName, spot: Node = null) -> bool:
	if not mode in HideTuning.MODES:
		return false
	if mode == hide_mode:
		return true
	if mode != HideTuning.NONE and hide_mode != HideTuning.NONE:
		return false
	if not can_change_hide_mode():
		return false
	_apply_hide_mode(mode, spot)
	return true

## Сменить режим в обход запретов (респавн, сброс мира). Для &"none" — всегда безопасно.
func force_hide_mode(mode: StringName, spot: Node = null) -> void:
	if mode in HideTuning.MODES and mode != hide_mode:
		_apply_hide_mode(mode, spot)

func _apply_hide_mode(mode: StringName, spot: Node) -> void:
	var old := hide_mode
	hide_mode = mode
	hide_owner = spot if mode != HideTuning.NONE else null
	hide_travel = 0.0
	_look.visible = mode == HideTuning.NONE
	if mode == HideTuning.NONE:
		for child in hide_visual.get_children():
			hide_visual.remove_child(child)
			child.queue_free()
	var limit := speed_limit()
	var horizontal := Vector2(velocity.x, velocity.z).limit_length(limit)
	_ground_speed = horizontal.length()
	_air_speed_limit = WALK_SPEED
	velocity.x = horizontal.x
	velocity.y = minf(velocity.y, 0.0)
	velocity.z = horizontal.y
	hide_mode_changed.emit(old, mode)
	if mode != HideTuning.NONE:
		_cancel_punch()

# --- PUNCH-01: удар ---

## Можно ли бить сейчас: пешком, ввод включён, не в укрытии, на земле или в прыжке — всё равно; не в машине, без
## диалога/панели и провала (те же запреты, что у смены укрытия).
func can_punch() -> bool:
	return input_enabled and visible and is_physics_processing() and hide_mode == HideTuning.NONE and can_change_hide_mode()

## Начать удар. false — нельзя (кулдаун, идёт замах, запрет can_punch()).
func punch() -> bool:
	if _punch_cooldown > 0.0 or _punch_time >= 0.0 or not can_punch():
		return false
	punches += 1
	_punch_time = 0.0
	_punch_pending = true
	_punch_cooldown = PUNCH_COOLDOWN
	punched.emit()
	_play_lunge()
	return true

## Идёт замах (от нажатия до конца PUNCH_SWING).
func is_punching() -> bool:
	return _punch_time >= 0.0

## Направление взгляда облика в плоскости XZ.
func facing_dir() -> Vector3:
	var forward := -visual.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

## Центр сферы удара в мире.
func punch_center() -> Vector3:
	return global_position + facing_dir() * PUNCH_REACH + Vector3.UP * PUNCH_CENTER_Y

func _punch_step(delta: float) -> void:
	_punch_cooldown = maxf(_punch_cooldown - delta, 0.0)
	if _punch_time < 0.0:
		return
	_punch_time += delta
	if _punch_pending and _punch_time >= PUNCH_HIT_AT:
		_punch_pending = false
		if can_punch():
			_resolve_punch()
	if _punch_time >= PUNCH_SWING:
		_punch_time = -1.0

## Попадание: сфера перед Илюшей, области (дроны) — по высоте в полосе PUNCH_LOW…PUNCH_HIGH. Владельцы целей — без
## повторов; не цель (дом, «Лада», вал) пропускается.
func _resolve_punch() -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _punch_shape
	query.transform = Transform3D(Basis.IDENTITY, punch_center())
	query.collision_mask = PUNCH_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var targets: Array = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider: Object = hit.get("collider")
		if not collider is Node3D:
			continue
		var target: Node = null
		if collider is Area3D:
			var height: float = (collider as Node3D).global_position.y - global_position.y
			if height < PUNCH_LOW or height > PUNCH_HIGH:
				continue
			target = (collider as Node).get_parent()
			if target == null or not target.has_method("is_flying") or not target.is_flying():
				continue
		else:
			var owner_node := (collider as Node).get_parent()
			if owner_node == null or (owner_node.get("interaction_id") == null and not owner_node.is_in_group(&"breakables")):   # BREAK-01: Breakable
				continue
			target = owner_node
		if not target in targets:
			targets.append(target)
	last_punch_targets = targets
	if not targets.is_empty():
		punch_hits += 1
		punch_landed.emit(targets)

## Рывок облика вперёд и пружина назад (TRANS_BACK, как pop). Сдвигается только Look внутри Visual.
func _play_lunge() -> void:
	if _punch_tween and _punch_tween.is_valid():
		_punch_tween.kill()
	_look.position = Vector3.ZERO
	_look.scale = Vector3.ONE
	var tween := _look.create_tween()
	_punch_tween = tween
	tween.tween_property(_look, "position", Vector3(0, 0, -PUNCH_LUNGE), PUNCH_HIT_AT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_look, "scale", Vector3(1.08, 0.95, 1.0), PUNCH_HIT_AT)
	tween.tween_property(_look, "position", Vector3.ZERO, PUNCH_SWING - PUNCH_HIT_AT).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_look, "scale", Vector3.ONE, PUNCH_SWING - PUNCH_HIT_AT).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _cancel_punch() -> void:
	_punch_time = -1.0
	_punch_pending = false
	if _punch_tween and _punch_tween.is_valid():
		_punch_tween.kill()
	_punch_tween = null
	if _look:
		_look.position = Vector3.ZERO
		_look.scale = Vector3.ONE

func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var look = CharacterSpriteScript.new()
	look.name = "Look"
	look.character = "ilyusha"
	look.height_m = 2.0   # фигура ≈1,8 м — чуть выше крыши «Лады», как в концепте 04 и у эталона (PLAY-01)
	root.add_child(look)
	_look = look
	hide_visual = Node3D.new()
	hide_visual.name = "HideVisual"
	root.add_child(hide_visual)
	return root

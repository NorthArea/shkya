class_name Ilyusha
extends CharacterBody3D
## Илюша пешком: ходьба относительно камеры, взаимодействие по E (C3).
## Visual — облик ШКЯ в зимнем костюме (ART-01, CharacterSprite); поворот Visual = взгляд Илюши.
## EXT-02 (C7, docs/extension/HIDE_SPOTS.md раздел 9): режим укрытия hide_mode (&"none", &"box", &"snowdrift",
## &"barrel") — предел скорости speed_limit(), без прыжка, заметность exposure_factor() для DetectionSensor.
## Облик укрытия кладёт HideSpot в hide_visual (дочерний Visual); спрайт Илюши в режиме скрыт, тело и коллизия те же.

const CharacterSpriteScript = preload("res://game/characters/character_sprite.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")

const WALK_SPEED := 4.0         # 2,2 роста/с при фигуре 1,8 м, как у эталона (PLAY-02)
const ACCELERATION := 30.0
const DECELERATION := 11.0      # остановка за ~0,4 с, как у эталона (PLAY-01)
const TURN_RATE := 12.0
const PROBE_RADIUS := 0.5
const JUMP_VELOCITY := 6.0        # подскок ≈1,8 м: на крышу «Лады» (1,4 м) с запасом — решение владельца 28.10.2026

## Режим укрытия сменился (old → new). Подписчики — укрытия и HUD; шкалу не трогает.
signal hide_mode_changed(old: StringName, new: StringName)

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
var _last_input := Vector2.ZERO

func _ready() -> void:
	collision_layer = 2       # Player
	collision_mask = 1 | 4    # World, Car
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

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# Курс ходьбы — от камеры на момент смены клавиш (CameraRig.input_yaw): автодоводка камеры
	# не закручивает Илюшу, пока держишь те же клавиши (PLAY-02).
	if camera_rig and not input.is_equal_approx(_last_input):
		camera_rig.sync_input_yaw()
	_last_input = input
	var yaw := camera_rig.input_yaw if camera_rig else 0.0
	var limit := speed_limit()
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	if limit <= 0.0:
		direction = Vector3.ZERO   # сугроб: движения и поворота нет
	var rate := ACCELERATION if direction.length_squared() > 0.01 else DECELERATION
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * limit, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		var jump := input_enabled and hide_mode == HideTuning.NONE and Input.is_action_just_pressed(&"jump")
		velocity.y = JUMP_VELOCITY if jump else 0.0
	else:
		velocity.y -= get_gravity().length() * delta
	var before := global_position
	move_and_slide()
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

func _unhandled_input(event: InputEvent) -> void:
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
	visual.rotation.y = facing_yaw
	reset_physics_interpolation()

# --- EXT-02: укрытия ---

## Предел горизонтальной скорости в текущем режиме, м/с: обычный — WALK_SPEED, коробка 1,2, бочка 2,6, сугроб 0.
func speed_limit() -> float:
	return HideTuning.speed_for(hide_mode, WALK_SPEED)

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
	velocity.x = horizontal.x
	velocity.y = minf(velocity.y, 0.0)
	velocity.z = horizontal.y
	hide_mode_changed.emit(old, mode)

func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var look: CharacterSprite = CharacterSpriteScript.new()
	look.name = "Look"
	look.character = "ilyusha"
	look.height_m = 2.0   # фигура ≈1,8 м — чуть выше крыши «Лады», как в концепте 04 и у эталона (PLAY-01)
	root.add_child(look)
	_look = look
	hide_visual = Node3D.new()
	hide_visual.name = "HideVisual"
	root.add_child(hide_visual)
	return root

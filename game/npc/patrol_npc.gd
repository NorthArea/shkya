extends "res://game/npc/npc.gd"
## Патрульный полицейский (EXT-01 N, STEALTH_DESIGN «Наблюдатели»): стоит на посту и каждые TURN_EVERY с
## плавно (TURN_SECONDS) разворачивает корпус на следующий угол из facings; дочерний DetectionSensor (C7)
## смотрит туда же, куда корпус. move_post(point) — переход на новый пост шагом MOVE_SPEED (этап 7: после
## покупки хлеба): на переходе сенсор выключен и конус скрыт — идущий патруль не «смотрит» (приёмка 28.10, P1),
## на новом посту доворачивается на текущий угол из facings и включает сенсор. Облик, тело, дыхание и зона E —
## npc.gd; на время диалога смотрит на Илюшу (look_at_target).
## EXT-01 fix2 (P2-3, этап 5 «может спокойно уйти, если быстро завершит диалог»): после диалога QuestFlow зовёт
## turn_away_from(Илюша, grace) — сразу разворот на угол из facings, в котором Илюши нет, таймер разворотов заново.
## Если по истечении grace Илюша всё ещё стоит рядом (LINGER_RADIUS), полицейский поворачивается к нему и смотрит,
## пока тот не отойдёт: дальше видит сенсор — провал через 2 с. can_talk_to(target) — Илюша не за спиной (P3).
## EXT-01 fix4 (четвёртая приёмка P3: после диалога разворачивался на юг, куда Илюша уходит к парковке): из углов, в
## конусе которых Илюши нет, — тот, что дальше от направления на away_point (парковка); если Илюша во всех — дальше всего
## от Илюши.
## fix4: avoid_yaw — угол корпуса, через который разворот не проходит (второй пост: окно киоска на юге; кратчайший путь
## между западом и востоком-юго-востоком шёл через юг и на 0,3 с открывал окно): разворот идёт длинной дугой, время —
## TURN_SECONDS на каждые 90° (не меньше TURN_SECONDS).
## EXT-01 fix5: facing_holds — удержание по номеру угла (Vector2 с, мин…макс); пусто или без записи — turn_every;
## facing_fovs — обзор сенсора по номеру угла (град), ставится в начале разворота на угол; без записи — sensor_fov.

## POLISH-03 A (критик: стелс вслепую — из-за гаражей полицейского не видно): за WARN_LEAD с до разворота поста —
## сигнал turn_warning(следующий угол), треск рации с поста (слышно ближе WARN_RADIUS) и силуэт желтеет; если следующий
## угол накроет пешего Илюшу (не в укрытии) ближе WARN_RADIUS — субтитр QuestLines.PATROL_TURN (не чаще WARN_TEXT_COOLDOWN, не поверх
## идущего гэга). Силуэт сквозь стены (patrol_xray.gdshader) — пока герой ближе XRAY_RADIUS: голубой, перед разворотом
## жёлтый, когда сенсор видит Илюшу — красный. Время удержаний и углы не меняются — честный путь не проще (C7).

const DetectionSensorScript = preload("res://game/stealth/detection_sensor.gd")
const XRAY_SHADER := preload("res://game/stealth/patrol_xray.gdshader")
const CRACKLE := preload("res://assets/audio/radio_mumble.wav")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")
signal turn_warning(next_index: int)
const WARN_LEAD := 1.0            # с до начала разворота
const WARN_RADIUS := 25.0         # м: ближе — треск рации и субтитр
const WARN_TEXT_COOLDOWN := 6.0   # с между субтитрами одного поста
const WARN_CONE_SLACK := 20.0     # град к половине обзора: «повернётся к тебе», с запасом
const CRACKLE_SECONDS := 0.7
const XRAY_RADIUS := 25.0         # м от героя (или машины) до поста
const XRAY_CALM := Color(0.62, 0.86, 1.0)
const XRAY_WARN := Color(1.0, 0.85, 0.2)
const XRAY_SEEN := Color(1.0, 0.3, 0.2)

## Углы корпуса в осях узла (yaw: 0 — на север), по кругу.
@export var facings: Array = [0.0]
@export var turn_every := Vector2(3.0, 4.0)   # с между разворотами, случайно в этих границах
## Удержание угла facings[i], с (Vector2 мин…макс), если задано; иначе turn_every (fix5).
@export var facing_holds: Array = []
## Обзор сенсора на угле facings[i], град, если задан; иначе sensor_fov (fix5).
@export var facing_fovs: Array = []
@export var sensor_range := 9.0
@export var sensor_fov := 75.0
## Куда уходит Илюша после диалога (парковка): turn_away_from не выбирает угол, смотрящий туда. INF — не учитывать.
@export var away_point := Vector3.INF
## Угол корпуса (в осях узла), через который не разворачиваться; NAN — кратчайшим путём (fix4).
@export var avoid_yaw := NAN

const TURN_SECONDS := 0.6
const MOVE_SPEED := 1.5
const LOOK_SPEED := 6.0   # доворот к собеседнику, 1/с (как у npc.gd)
const TALK_ANGLE := 100.0      # град от направления корпуса: дальше — «за спиной», подсказки E нет
const LINGER_RADIUS := 3.5     # м: после диалога ближе этого — «не ушёл» (зона E 2,5 м + зонд Илюши 0,5 м + запас)

var sensor: Node3D
var _facing_index := 0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_t := 1.0        # 0…1 — идёт разворот
var _turn_delta := 0.0    # дуга разворота, рад (со знаком; fix4 — может быть длинной)
var _turn_time := TURN_SECONDS
var _wait_left := 0.0
var _move_target := Vector3.INF
var _linger_target: Node3D
var _linger_left := 0.0
var _watching := false     # после диалога Илюша не ушёл — смотрим на него
var _rng := RandomNumberGenerator.new()
## POLISH-03 A: сколько раз предупредил о развороте и сколько из них — субтитром (для тестов).
var warnings := 0
var warning_texts := 0
var _warned := false
var _warn_cooldown := 0.0
var _warn_glow := 0.0     # с: силуэт жёлтый после предупреждения
var _crackle_left := 0.0
var crackle: AudioStreamPlayer3D
var xray: MeshInstance3D
var _xray_material: ShaderMaterial
var _look: Node   # CharacterSprite облика (npc.gd: Visual/Look)

func _ready() -> void:
	super()
	_rng.seed = String(interaction_id).hash()
	if facings.is_empty():
		facings = [facing_yaw]
	_turn_from = float(facings[0])
	_turn_to = _turn_from
	facing_yaw = _turn_from
	visual.rotation.y = _turn_from
	_reset_hold()
	sensor = DetectionSensorScript.new()
	sensor.name = "DetectionSensor"
	sensor.range_m = sensor_range
	sensor.fov_deg = _fov_for(0)
	sensor.rotation.y = _turn_from
	add_child(sensor)
	crackle = AudioStreamPlayer3D.new()
	crackle.name = "TurnCrackle"
	crackle.stream = CRACKLE
	crackle.volume_db = -6.0
	crackle.max_distance = WARN_RADIUS
	crackle.position.y = 1.6
	add_child(crackle)
	_look = visual.get_node_or_null("Look")
	call_deferred(&"_build_xray")

func _process(delta: float) -> void:
	_breath_time += delta
	var s := sin(_breath_time * TAU / BREATH_PERIOD)
	visual.scale = Vector3(1.0 - s * BREATH * 0.5, 1.0 + s * BREATH, 1.0)
	_update_linger(delta)
	if is_instance_valid(_look_target):
		# Диалог (или Илюша задержался после него): корпус к Илюше, таймер разворотов стоит.
		var to := _look_target.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.3:
			var wanted := atan2(-to.x, -to.z) - global_rotation.y
			visual.rotation.y = lerp_angle(visual.rotation.y, wanted, 1.0 - exp(-LOOK_SPEED * delta))
	elif _move_target != Vector3.INF:
		var to := _move_target - global_position
		to.y = 0.0
		if to.length() > 0.001:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-to.x, -to.z) - global_rotation.y, 1.0 - exp(-LOOK_SPEED * delta))
	else:
		if _turn_t < 1.0:
			_turn_t = minf(_turn_t + delta / _turn_time, 1.0)
			var k := smoothstep(0.0, 1.0, _turn_t)
			visual.rotation.y = _turn_from + _turn_delta * k
		else:
			_wait_left -= delta
			if not _warned and _wait_left <= WARN_LEAD and facings.size() > 1:
				_warn()
			if _wait_left <= 0.0:
				_next_facing()
	facing_yaw = visual.rotation.y
	sensor.rotation.y = visual.rotation.y
	_warn_cooldown = maxf(0.0, _warn_cooldown - delta)
	_warn_glow = maxf(0.0, _warn_glow - delta)
	if _crackle_left > 0.0:
		_crackle_left -= delta
		if _crackle_left <= 0.0:
			crackle.stop()
	_update_xray()

func _physics_process(delta: float) -> void:
	if _move_target == Vector3.INF:
		return
	var to := _move_target - global_position
	to.y = 0.0
	var step := MOVE_SPEED * delta
	if to.length() <= step:
		global_position = Vector3(_move_target.x, global_position.y, _move_target.z)
		_move_target = Vector3.INF
		# Пришёл: доворот на текущий угол поста, затем обычный цикл разворотов; сенсор снова смотрит.
		_turn_from = visual.rotation.y
		_turn_to = float(facings[_facing_index])
		_start_turn()
		_reset_hold()
		sensor.enabled = true
		return
	global_position += to.normalized() * step

func _next_facing() -> void:
	_facing_index = (_facing_index + 1) % facings.size()
	_turn_from = visual.rotation.y
	_turn_to = float(facings[_facing_index])
	_start_turn()
	_reset_hold()

## После диалога (P2-3, fix4): сразу на угол из facings без target в конусе — из таких дальше всего от away_point;
## если target во всех — дальше всего от target. Таймер разворотов заново; grace с — время уйти. Позже — _update_linger.
func turn_away_from(target: Node3D, grace: float) -> void:
	_look_target = null
	_watching = false
	_linger_target = target
	_linger_left = grace
	if not is_instance_valid(target) or facings.is_empty():
		return
	_facing_index = away_facing(target.global_position)
	_turn_from = visual.rotation.y
	_turn_to = float(facings[_facing_index])
	_start_turn()
	_reset_hold()

func _update_linger(delta: float) -> void:
	if not is_instance_valid(_linger_target):
		_linger_target = null
		return
	var near := _flat_distance(_linger_target) <= LINGER_RADIUS
	if _watching:
		if not near:
			# Отошёл: перестать смотреть, снова на угол без него.
			var target := _linger_target
			turn_away_from(target, 0.0)
			_linger_target = null
		return
	_linger_left -= delta
	if _linger_left > 0.0:
		return
	if near:
		_watching = true
		_look_target = _linger_target
	else:
		_linger_target = null

## Илюша задержался после диалога, полицейский смотрит на него (для тестов).
func is_watching() -> bool:
	return _watching

## Новое удержание угла: таймер заново, предупреждение о развороте — снова впереди.
func _reset_hold() -> void:
	_wait_left = _hold()
	_warned = false

## POLISH-03 A: до разворота WARN_LEAD с — сигнал, треск рации рядом, силуэт желтеет; субтитр, если повернётся к Илюше.
func _warn() -> void:
	_warned = true
	warnings += 1
	var next := (_facing_index + 1) % facings.size()
	_warn_glow = WARN_LEAD + TURN_SECONDS
	turn_warning.emit(next)
	var world := _world()
	if world == null:
		return
	var p: Vector3 = world.player.global_position
	if Vector2(p.x - global_position.x, p.z - global_position.z).length() > WARN_RADIUS:
		return
	crackle.play()
	_crackle_left = CRACKLE_SECONDS
	if world.control_mode != &"on_foot" or _warn_cooldown > 0.0 or not will_face(p, next):
		return
	if world.player.get("hide_mode") not in [null, HideTuning.NONE]:
		return   # в укрытии — свои гэги с лимитом на попытку (HIDE_SPOTS, раздел 11); треск и силуэт остаются
	var sound: Node = world.get_node_or_null("SoundDirector")
	if sound and sound.has_method("show_gag") and not sound.gag_playing():
		sound.show_gag(QuestLines.PATROL_TURN, QuestLines.PATROL_TURN_SECONDS)
		_warn_cooldown = WARN_TEXT_COOLDOWN
		warning_texts += 1

## Накроет ли угол facings[index] точку p: дальность сенсора на этом угле (+4 м) и половина обзора + WARN_CONE_SLACK.
func will_face(p: Vector3, index: int) -> bool:
	var flat := Vector2(p.x - global_position.x, p.z - global_position.z)
	if flat.length() > sensor.range_m + 4.0:
		return false
	return _angle_to_point(p, float(facings[index])) <= _fov_for(index) * 0.5 + WARN_CONE_SLACK

## Время до следующего разворота, с (для тестов; во время разворота, перехода или взгляда на Илюшу — 0).
func seconds_to_turn() -> float:
	if _turn_t < 1.0 or _move_target != Vector3.INF or is_instance_valid(_look_target):
		return 0.0
	return maxf(_wait_left, 0.0)

func _world() -> Node:
	var node := get_parent()
	while node:
		if node.get("control_mode") != null and node.get("player") != null:
			return node
		node = node.get_parent()
	return null

## Силуэт сквозь стены: тот же рисунок, что у спрайта облика, на квадрате его размера; ребёнок спрайта (дыхание и
## положение — его).
func _build_xray() -> void:
	if _look == null or _look.get("sprite") == null:
		return
	var sprite: Sprite3D = _look.sprite
	_xray_material = ShaderMaterial.new()
	_xray_material.shader = XRAY_SHADER
	_xray_material.render_priority = 2
	var quad := QuadMesh.new()
	quad.size = Vector2(sprite.texture.get_width(), sprite.texture.get_height()) * sprite.pixel_size
	xray = MeshInstance3D.new()
	xray.name = "XRay"
	xray.mesh = quad
	xray.material_override = _xray_material
	xray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	xray.visible = false
	sprite.add_child(xray)

func _update_xray() -> void:
	if xray == null:
		return
	var world := _world()
	var hero: Node3D = null
	if world:
		hero = world.player if world.control_mode == &"on_foot" else world.get("car")
	var near := hero != null and Vector2(hero.global_position.x - global_position.x, hero.global_position.z - global_position.z).length() <= XRAY_RADIUS
	xray.visible = near and sensor.enabled
	if not xray.visible:
		return
	var sprite: Sprite3D = _look.sprite
	_xray_material.set_shader_parameter(&"albedo_tex", sprite.texture)
	_xray_material.set_shader_parameter(&"flip", 1.0 if sprite.flip_h else 0.0)
	var color := XRAY_CALM
	if sensor.visibility() > 0.0:
		color = XRAY_SEEN
	elif _warn_glow > 0.0 or _turn_t < 1.0:
		color = XRAY_WARN
	_xray_material.set_shader_parameter(&"tint", color)

## Силуэт сквозь стены показан (для тестов).
func xray_shown() -> bool:
	return xray != null and xray.visible

## Можно ли заговорить: target не за спиной — угол от направления корпуса не больше TALK_ANGLE.
func can_talk_to(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return true
	if is_instance_valid(_look_target):
		return true
	return _angle_to(target, visual.rotation.y) <= TALK_ANGLE

## Обзор сенсора на угле i: facing_fovs[i] или sensor_fov (fix5).
func _fov_for(i: int) -> float:
	if i < facing_fovs.size() and (facing_fovs[i] is float or facing_fovs[i] is int):
		return float(facing_fovs[i])
	return sensor_fov

## Случайное удержание текущего угла _facing_index: facing_holds[i] или turn_every (fix5).
func _hold() -> float:
	var h: Vector2 = turn_every
	if _facing_index < facing_holds.size() and facing_holds[_facing_index] is Vector2:
		h = facing_holds[_facing_index]
	return _rng.randf_range(h.x, h.y)

## Начать разворот _turn_from → _turn_to: кратчайшей дугой, если она не проходит через avoid_yaw, иначе длинной (fix4).
func _start_turn() -> void:
	if sensor:
		sensor.fov_deg = _fov_for(_facing_index)   # fix5: обзор целевого угла — с начала разворота
	var d := wrapf(_turn_to - _turn_from, -PI, PI)
	if not is_nan(avoid_yaw) and absf(d) > 0.001:
		var a := wrapf(avoid_yaw - _turn_from, -PI, PI)
		if signf(a) == signf(d) and absf(a) < absf(d):
			d -= signf(d) * TAU
	_turn_delta = d
	_turn_time = TURN_SECONDS * maxf(1.0, absf(d) / (PI * 0.5))
	_turn_t = 0.0

## Номер угла facings для разворота от точки p (fix4): без p в конусе (угол > половины обзора) и дальше всего от
## away_point; если p во всех конусах — дальше всего от p.
func away_facing(p: Vector3) -> int:
	var best := -1
	var best_angle := -1.0
	for i in facings.size():
		var yaw := float(facings[i])
		var off := _angle_to_point(p, yaw)
		if off <= _fov_for(i) * 0.5:
			continue
		var angle := _angle_to_point(away_point, yaw) if away_point != Vector3.INF else off
		if angle > best_angle:
			best_angle = angle
			best = i
	if best >= 0:
		return best
	best = _facing_index
	for i in facings.size():
		var off := _angle_to_point(p, float(facings[i]))
		if off > best_angle:
			best_angle = off
			best = i
	return best

## Угол (град) между направлением корпуса при yaw (в осях узла) и направлением на target в плоскости XZ.
func _angle_to(target: Node3D, yaw: float) -> float:
	return _angle_to_point(target.global_position, yaw)

func _angle_to_point(p: Vector3, yaw: float) -> float:
	var to := p - global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.01:
		return 0.0
	var world_yaw := yaw + global_rotation.y
	return rad_to_deg(absf(Vector2(-sin(world_yaw), -cos(world_yaw)).angle_to(flat)))

func _flat_distance(target: Node3D) -> float:
	var to := target.global_position - global_position
	return Vector2(to.x, to.z).length()

## Перейти на новый пост (этап 7): шагом MOVE_SPEED, лицом по ходу, сенсор выключен до прихода; на месте — снова
## разворачивается по facings.
func move_post(point: Vector3) -> void:
	_move_target = Vector3(point.x, 0.0, point.z)
	sensor.enabled = false

func is_moving() -> bool:
	return _move_target != Vector3.INF

## Встать на пост сразу (перезапуск, тесты): без перехода, с первым углом facings, сенсор включён.
func place_at(point: Vector3) -> void:
	_move_target = Vector3.INF
	_linger_target = null
	_watching = false
	_look_target = null
	global_position = Vector3(point.x, global_position.y, point.z)
	_facing_index = 0
	_turn_from = float(facings[0])
	_turn_to = _turn_from
	_turn_t = 1.0
	visual.rotation.y = _turn_from
	_reset_hold()
	sensor.fov_deg = _fov_for(0)
	sensor.enabled = true

## Идёт плавный разворот корпуса (между углами facings).
func is_turning() -> bool:
	return _turn_t < 1.0

## Номер текущего (или целевого, если идёт разворот) угла в facings.
func facing_index() -> int:
	return _facing_index

## Текущий угол корпуса в осях узла (для тестов).
func body_yaw() -> float:
	return visual.rotation.y

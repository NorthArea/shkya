extends Node3D
## Монеты (COINS-01, решение владельца 29.10: 35 рублей собрать до батона, стартовых денег нет).
## Узел «Coins» создаёт LevelGeometry (DemoWorld/LevelGeometry/Coins). Точки — Layout.COIN_POINTS (C1,
## layout.gd); деньги — только MissionDirector.add_money() (C5): монета — 1 ₽, сигнал collected — для звука и проверок.
##
## Монета — простой объём без чужих ассетов: жёлтый диск Ø 0,4 м с «₽» на обеих сторонах (текстура рисуется кодом),
## парит над землёй, вращается, слегка светится (emission с медленной пульсацией). Коллизии нет — подбор по расстоянию
## в плоскости xz: пешком 0,9 м от Илюши, на машине 1,6 м от центра «Лады»; магнит — с 1,5 м пешком (2,4 м в машине)
## монета летит к собирающему и засчитывается на радиусе подбора.
## Идеи — из реконструкции Hit & Run (G03, Vheissu/hit-and-run-web, MIT; код не скопирован): подбор по расстоянию,
## а не по коллизии, с увеличенным радиусом в машине; засчитанная монета коротко летит к игроку и исчезает;
## вращение ~3 рад/с; один общий меш на все монеты (у нас — MultiMesh); выброс «пачкой» с разлётом, гравитацией и
## отскоком, в полёте не подбирается, со временем гаснет; звук — с чередованием (у нас — высоты одного синтеза).
## Респавн на чекпоинте монеты не трогает; reset() — для перезапуска (все точки заново, выброшенные исчезают).
## spawn_burst(position, count) — монеты из сбитых дронов (PUNCH-01: по 5).

signal collected(position: Vector3, total: int)


const Layout = preload("res://game/world/layout.gd")

const DIAMETER := 0.4
const THICKNESS := 0.05
const HOVER := 0.55              # м: центр монеты над землёй
const BOB := 0.06                # м: покачивание по высоте
const SPIN := 3.0                # рад/с
const PICKUP_FOOT := 0.9         # м от Илюши (xz)
const PICKUP_CAR := 1.6          # м от центра «Лады» (xz)
const MAGNET_FOOT := 1.5         # м: ближе — монета летит к Илюше
const MAGNET_CAR := 2.4
const MAGNET_SPEED := 7.0        # м/с в начале притяжения, дальше разгон
const MAGNET_ACCEL := 30.0
const REACH_HEIGHT := 2.2        # м: по высоте дальше — не подбирается (крыша гаражей, прыжок)
const POP_SECONDS := 0.22        # засчитанная монета летит к собирающему и уменьшается
const BURST_SPEED := 4.5         # м/с: разлёт выброшенных монет
const BURST_UP := 4.0            # м/с вверх
const GRAVITY := 14.0
const BOUNCE := 0.45
const LOOSE_LIFETIME := 30.0     # с: выброшенная монета живёт столько…
const LOOSE_BLINK := 5.0         # …и мигает последние секунды
const MAX_LOOSE := 60
const GLOW := 0.55               # базовая яркость свечения

const GOLD := Color(0.99, 0.79, 0.16)
const RIM := Color(0.86, 0.56, 0.08)
const INK := Color(0.52, 0.30, 0.04)

enum { IDLE, MAGNET, POP, GONE, AIR }

## Сколько монет подобрано за мир (выброшенные — тоже).
var collected_count := 0
## Для проверок: подобрано на машине.
var collected_in_car := 0
var multimesh_instance: MultiMeshInstance3D
var material: StandardMaterial3D

var _world: Node
var _mission: Node
var _origin: PackedVector3Array = PackedVector3Array()
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _state: PackedInt32Array = PackedInt32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
var _fixed := 0                  # первые _fixed — точки Layout, дальше — пул выброшенных
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "Coins"


func _ready() -> void:
	_world = _find_world()
	_rng.seed = 29102026
	_fixed = Layout.COIN_POINTS.size()
	var total := _fixed + MAX_LOOSE
	_origin.resize(total)
	_pos.resize(total)
	_vel.resize(total)
	_state.resize(total)
	_age.resize(total)
	_phase.resize(total)
	_speed.resize(total)
	for i in total:
		_phase[i] = _rng.randf() * TAU
	_build_view(total)
	reset()


## Все точки раскладки на месте, выброшенные монеты исчезают, счётчик подобранных — 0. Деньги не трогает (их
## обнуляет MissionDirector.reset()).
func reset() -> void:
	for i in _state.size():
		_vel[i] = Vector3.ZERO
		_age[i] = 0.0
		if i < _fixed:
			_origin[i] = Layout.COIN_POINTS[i] + Vector3.UP * HOVER
			_pos[i] = _origin[i]
			_state[i] = IDLE
		else:
			_state[i] = GONE
	collected_count = 0
	collected_in_car = 0
	_update_view()


## PUNCH-01: count монет разлетаются от точки at (сбитый дрон). В полёте не подбираются, после приземления
## парят как обычные и гаснут через LOOSE_LIFETIME. Возвращает, сколько выброшено (пул MAX_LOOSE).
func spawn_burst(at: Vector3, count: int) -> int:
	var made := 0
	for i in range(_fixed, _state.size()):
		if made >= count:
			break
		if _state[i] != GONE:
			continue
		var a := TAU * (float(made) / maxf(1.0, float(count))) + _rng.randf_range(-0.4, 0.4)
		var speed := BURST_SPEED * _rng.randf_range(0.6, 1.0)
		_pos[i] = Vector3(at.x, maxf(at.y, HOVER), at.z)
		_vel[i] = Vector3(cos(a) * speed, BURST_UP * _rng.randf_range(0.8, 1.2), sin(a) * speed)
		_age[i] = 0.0
		_state[i] = AIR
		made += 1
	return made


## Сколько монет ещё можно подобрать (точки и выброшенные на земле или в полёте).
func remaining() -> int:
	var n := 0
	for s in _state:
		if s == IDLE or s == MAGNET or s == AIR:
			n += 1
	return n


## Положения монет, которые можно подобрать (для проверок и кадров).
func active_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in _state.size():
		if _state[i] == IDLE or _state[i] == MAGNET or _state[i] == AIR:
			out.append(_pos[i])
	return out


## Монета i — точка раскладки и ещё не подобрана.
func is_available(i: int) -> bool:
	return i >= 0 and i < _fixed and (_state[i] == IDLE or _state[i] == MAGNET)


func layout_count() -> int:
	return _fixed


func _physics_process(delta: float) -> void:
	_time += delta
	var who := _collector()
	for i in _state.size():
		match _state[i]:
			IDLE:
				if i >= _fixed:
					_age_loose(i, delta)
				if not who.is_empty():
					_try_attract(i, who)
			MAGNET:
				if who.is_empty():
					_state[i] = IDLE
					continue
				var target: Vector3 = who["position"] + Vector3.UP * HOVER
				_speed[i] += MAGNET_ACCEL * delta
				_pos[i] = _pos[i].move_toward(target, _speed[i] * delta)
				if _flat(_pos[i], who["position"]) <= who["pickup"]:
					_collect(i, who)
				elif _flat(_pos[i], who["position"]) > who["magnet"] * 1.5:
					_state[i] = IDLE   # убежал — монета остаётся, где была
			POP:
				_age[i] += delta
				if not who.is_empty():
					_pos[i] = _pos[i].lerp(who["position"] + Vector3.UP * (HOVER + 0.6), minf(1.0, delta * 14.0))
				if _age[i] >= POP_SECONDS:
					_state[i] = GONE
			AIR:
				_age_loose(i, delta)
				_fly(i, delta)
	_update_view()


func _age_loose(i: int, delta: float) -> void:
	_age[i] += delta
	if _age[i] >= LOOSE_LIFETIME:
		_state[i] = GONE


func _fly(i: int, delta: float) -> void:
	var v := _vel[i]
	v.y -= GRAVITY * delta
	var p := _pos[i] + v * delta
	if p.y <= HOVER and v.y < 0.0:
		p.y = HOVER
		v.y = -v.y * BOUNCE
		v.x *= 0.55
		v.z *= 0.55
		if v.y < 1.0:
			v = Vector3.ZERO
			_origin[i] = p
			_state[i] = IDLE
	_pos[i] = p
	_vel[i] = v


func _try_attract(i: int, who: Dictionary) -> void:
	var p: Vector3 = who["position"]
	if absf(_pos[i].y - HOVER - p.y) > REACH_HEIGHT:
		return
	var d := _flat(_pos[i], p)
	if d <= who["pickup"]:
		_collect(i, who)
	elif d <= who["magnet"]:
		_state[i] = MAGNET
		_speed[i] = MAGNET_SPEED


func _collect(i: int, who: Dictionary) -> void:
	_state[i] = POP
	_age[i] = 0.0
	collected_count += 1
	if who["in_car"]:
		collected_in_car += 1
	if _mission and _mission.has_method(&"add_money"):
		_mission.add_money(1)
	collected.emit(_pos[i], collected_count)


## Кто собирает: Илюша пешком или «Лада» с ним за рулём. {} — никто (нет мира).
func _collector() -> Dictionary:
	if _world == null:
		return {}
	if _mission == null:
		_mission = _world.get_node_or_null("MissionDirector")
	if _world.get("control_mode") == &"in_car":
		var car: Node3D = _world.get_node_or_null("Car")
		if car == null:
			return {}
		return {"position": car.global_position, "pickup": PICKUP_CAR, "magnet": MAGNET_CAR, "in_car": true}
	var player: Node3D = _world.get_node_or_null("Ilyusha")
	if player == null or not player.is_inside_tree():
		return {}
	return {"position": player.global_position, "pickup": PICKUP_FOOT, "magnet": MAGNET_FOOT, "in_car": false}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _find_world() -> Node:
	var node := get_parent()
	while node and not node.has_method(&"get_hud_state"):
		node = node.get_parent()
	return node


# --- вид ---

func _update_view() -> void:
	if multimesh_instance == null:
		return
	var mm := multimesh_instance.multimesh
	material.emission_energy_multiplier = GLOW + 0.25 * sin(_time * 3.0)
	for i in _state.size():
		mm.set_instance_transform(i, instance_transform(i))


## Как рисуется монета i: поворот вокруг y, покачивание, масштаб (0 — не видна). В headless MultiMesh трансформы
## не хранит, проверки читают отсюда.
func instance_transform(i: int) -> Transform3D:
	var s := _state[i]
	var k := 1.0
	var at := _pos[i]
	match s:
		GONE:
			k = 0.0
		POP:
			k = maxf(0.0, 1.0 - _age[i] / POP_SECONDS) * (1.0 + 0.4 * sin(_age[i] / POP_SECONDS * PI))
		IDLE:
			at.y += sin(_time * 2.2 + _phase[i]) * BOB
			# Выброшенная монета мигает перед тем, как погаснуть.
			if i >= _fixed and _age[i] > LOOSE_LIFETIME - LOOSE_BLINK and int(_time * 8.0) % 2 == 0:
				k = 0.0
	var spin := _time * SPIN * (4.0 if s == POP else 1.0) + _phase[i]
	return Transform3D(Basis(Vector3.UP, spin).scaled(Vector3.ONE * k), at)


func _build_view(total: int) -> void:
	material = StandardMaterial3D.new()
	var texture := face_texture()
	material.albedo_texture = texture
	material.metallic = 0.55
	material.roughness = 0.32
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.12)
	material.emission_texture = texture
	material.emission_energy_multiplier = GLOW
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = coin_mesh()
	mm.instance_count = total
	mm.custom_aabb = AABB(Vector3(-120, -10, -140), Vector3(240, 40, 280))
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.name = "CoinMeshes"
	multimesh_instance.multimesh = mm
	multimesh_instance.material_override = material
	multimesh_instance.top_level = true   # позиции монет — мировые
	multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(multimesh_instance)


## Диск вдоль оси z (стоит ребром на земле, вращается вокруг y): торцы с «₽», бортик — цветом каймы текстуры.
static func coin_mesh(segments := 28) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := DIAMETER * 0.5
	var h := THICKNESS * 0.5
	var rim_uv := Vector2(0.5, 0.015)
	for k in segments:
		var a0 := TAU * k / segments
		var a1 := TAU * (k + 1) / segments
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		for side in [1.0, -1.0]:
			# Торец: с обратной стороны u зеркалится, чтобы «₽» читался и сзади.
			var n := Vector3(0, 0, side)
			var verts := [Vector3.ZERO, Vector3(c0.x * r, c0.y * r, 0), Vector3(c1.x * r, c1.y * r, 0)]
			var uvs := [Vector2(0.5, 0.5), Vector2(0.5 + 0.5 * c0.x * side, 0.5 - 0.5 * c0.y), Vector2(0.5 + 0.5 * c1.x * side, 0.5 - 0.5 * c1.y)]
			var order := [0, 1, 2] if side < 0.0 else [0, 2, 1]
			for j in order:
				st.set_normal(n)
				st.set_uv(uvs[j])
				st.add_vertex(verts[j] + Vector3(0, 0, h * side))
		# Бортик.
		var n0 := Vector3(c0.x, c0.y, 0)
		var n1 := Vector3(c1.x, c1.y, 0)
		var quad := [[n0, h], [n1, h], [n1, -h], [n0, h], [n1, -h], [n0, -h]]
		for q in quad:
			st.set_normal(q[0])
			st.set_uv(rim_uv)
			st.add_vertex(Vector3(q[0].x * r, q[0].y * r, q[1]))
	return st.commit()


## Лицо монеты 128×128: золотой круг, тёмная кайма, внутреннее кольцо и «₽» из штрихов (без шрифтов и чужих картинок).
static func face_texture(size := 128) -> ImageTexture:
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var d := Vector2(u - 0.5, v - 0.5).length()
			var color := GOLD
			if d > 0.44:
				color = RIM
			elif d > 0.37 and d < 0.395:
				color = RIM
			elif _ruble(u, v):
				color = INK
			else:
				# Лёгкий блик сверху слева — объём без освещения.
				color = GOLD.lightened(clampf(0.25 - Vector2(u - 0.36, v - 0.32).length(), 0.0, 0.25))
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## «₽» в координатах лица (u вправо, v вниз): стойка, чаша буквы Р и две перекладины.
static func _ruble(u: float, v: float) -> bool:
	var stem := u >= 0.40 and u <= 0.47 and v >= 0.24 and v <= 0.77
	var bowl_c := Vector2(0.47, 0.385)
	var bd := Vector2(u, v).distance_to(bowl_c)
	var bowl := u >= 0.44 and bd <= 0.145 and bd >= 0.075
	var top := u >= 0.40 and u <= 0.47 and v >= 0.24 and v <= 0.31
	var mid := u >= 0.31 and u <= 0.47 and v >= 0.46 and v <= 0.53
	var cross := u >= 0.31 and u <= 0.60 and v >= 0.60 and v <= 0.665
	return stem or bowl or top or mid or cross

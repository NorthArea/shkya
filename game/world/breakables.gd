class_name Breakables
extends Node3D
## BREAK-01: разрушаемые объекты двора и улиц (идея *Hit & Run*, своя реализация без ассетов; контракт — C11
## в docs/workflow/README.md, план объектов — docs/workflow/tasks/ARENA-02.md). Данные — Layout.BREAKABLES (C1): [id, kind, центр, размер,
## yaw, class]. Узел создаёт LevelGeometry (DemoWorld/LevelGeometry/Breakables, группа GROUP_ROOT).
##
## Каждый объект — Breakable (Node3D в группе GROUP): StaticBody3D на слое LAYER (6, «Breakable»), hp, остаток после
## поломки. Облик — общие сетки-примитивы в MultiMesh по виду (kind) и кварталу CLUSTER: целый объект, мелкие детали
## (гаснут дальше FAR_DETAIL) и остаток — экземпляры тех же MultiMesh; у объектов ниже LOW_NO_SHADOW теней нет.
##
## Кто ломает: «Лада» — по касанию (Lada._bump_breakables → car_contacts): скорость до упора, спроецированная на
## направление в объект (минус нормаль касания); light — от LIGHT_SPEED или от упора с газом дольше PUSH_SECONDS
## (лёгкий объект машину не держит), heavy — от HEAVY_SPEED, медленнее стоит стеной; после тяжёлого удара скорость
## «Лады» × HEAVY_SLOWDOWN и тряска камеры SHAKE м, после лёгкого — без замедления. Илюша — удар F
## (Ilyusha.punch_landed): light — с одного удара, heavy — с HEAVY_HP, покачивание WOBBLE_SECONDS на удар. Ходьба,
## транспорт кольца, автобус ГСУМ, сбитые жители и дроны ничего не ломают (слой 32 видят только «Лада» и Илюша).
##
## Поломка: коллизия выключается в том же физическом кадре, остаток (ниже 0,15 м, без коллизии) появляется, обломки —
## кинематическая парабола в общем MultiMesh на DEBRIS_POOL экземпляров (не больше DEBRIS_MAX_BREAKS поломок разом),
## лежат на снегу DEBRIS_REST с и тают; разлёт уходит от жителя, если он ближе DEBRIS_CLEAR; снежная пыль — как у
## сбитого жителя (KNOCK-01, шейдер брызг PLAY-03). Сигналы broken(b, by) и restored(b) — у Breakable и здесь
## (их слушают SoundDirector и Residents). Квестовая Бабка ближе BABKA_DISTANCE — пузырь (не диалог), реплика 1
## QuestLines.BREAK_LINES; FSM миссии (MissionDirector) сцены не знает и не трогается.
##
## Восстановление: через RESTORE_SECONDS (RandomNumberGenerator с SEED), только если Илюша и «Лада» дальше RESTORE_FAR,
## объект вне усечённой пирамиды камеры и на месте нет тела (Илюша, «Лада», житель, собака); рост из снега за
## GROW_SECONDS. reset_positions() — всё целое сразу, обломков нет, rng с начала.
##
## Реакции без разрушения (ARENA-02, P1): припаркованные машины (Layout.PARKED, «Жигули» A и B) от толчка «Ладой» ≥
## ALARM_SPEED — сигнализация (сигнал car_alarm, мигают поворотники ALARM_SECONDS); дворовые контейнеры BINS и
## H10_BINS — хлопок крышек (сигнал bin_lid). Контейнеры у киоска (KioskBins, укрытие стелса) не реагируют.

const VehicleImpact = preload("res://game/vehicles/vehicle_impact.gd")
const VehicleDamage = preload("res://game/vehicles/vehicle_damage.gd")
const LadaVisual = preload("res://game/vehicles/lada_visual.gd")
const Layout = preload("res://game/world/layout.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
const Materials = preload("res://game/world/materials.gd")
const SNOW_PUFF_SHADER := preload("res://game/vehicles/slush_spray.gdshader")   # пыль — как у сбитого жителя
const STEAM_SHADER := preload("res://game/world/shaders/steam_puff.gdshader")    # пар раскопки — как у люков
const DIG_PUFFS := 12

signal broken(b: Breakable, by: StringName)
signal restored(b: Breakable)
signal wobbled(b: Breakable)                 # удар по heavy, который его ещё не сломал
signal car_alarm(at: Vector3)
signal bin_lid(at: Vector3)

const GROUP_ROOT := &"breakables_root"
const GROUP := &"breakables"
const LAYER := 32                    # слой 6 «Breakable» (project.godot)
const SEED := 2950
const LIGHT_SPEED := 1.0             # м/с: light ломается от этой скорости
const HEAVY_SPEED := 3.0             # м/с: как Resident.KNOCK_MIN_SPEED
const PUSH_SECONDS := 0.3            # упор с газом в light дольше — ломается
const HEAVY_SLOWDOWN := 0.8
const SHAKE := 0.1                   # м: тряска камеры после heavy
const SHAKE_SECONDS := 0.25
const HEAVY_HP := 3
const WOBBLE_SECONDS := 0.2
const WOBBLE_ANGLE := 0.12           # рад
const RESTORE_SECONDS := Vector2(60.0, 120.0)
const RESTORE_FAR := 20.0
const RESTORE_RETRY := 1.0           # с: условия не выполнены — проверить снова
const GROW_SECONDS := 0.5
const MIN_BODY_HEIGHT := 0.7         # м: коробка низкой клумбы выше облика — до неё достаёт сфера удара (центр 1,55, r 1,2)
const LOW_NO_SHADOW := 1.0
const FAR_DETAIL := 60.0
const CLUSTER := 40.0                # м: MultiMesh вида — на квартал, чтобы дальность деталей считалась от него
const DEBRIS_POOL := 96
const DEBRIS_MAX_BREAKS := 4
const DEBRIS_PER_BREAK := 24         # DEBRIS_POOL / DEBRIS_MAX_BREAKS
const DEBRIS_REST := Vector2(1.5, 3.0)
const DEBRIS_MELT := 0.5
const DEBRIS_CLEAR := 2.0
const DEBRIS_GRAVITY := 9.8
const BABKA_DISTANCE := 15.0
const BABKA_COOLDOWN := 15.0
const BABKA_BUBBLE_SECONDS := 2.5
const ALARM_SPEED := 2.0
const ALARM_SECONDS := 6.0
const ALARM_BLINK := 0.5             # с: период поворотников
const LID_SPEED := 1.0
const LID_COOLDOWN := 1.0
const SNOW := Color(0.88, 0.91, 0.96)

## BREAK-02: монеты из сломанного (решение владельца 29.10, вечер). Сломал «Ладой» — монеты вылетают и сами летят к
## машине (Coins.spawn_to_collector); ударом — разлетаются, как из сбитого дрона (Coins.spawn_burst), и подбираются
## проходом. Сколько — по виду: light 1–2, heavy 3–5. Тот же объект снова даёт монеты не раньше COIN_COOLDOWN после
## прошлой выдачи (восстановление 60–120 с — фарм одного объекта не чаще раза в 4 мин); со всех разрушаемых — не
## больше COIN_WINDOW_CAP за COIN_WINDOW (проезд вдоль палисадника из 19 секций — 12, а не 19). Ломает тест или
## кто-то ещё (by не car/punch) — монет нет. Монета ложится вне постоянных и целых коробок (+COIN_SOLID_PAD), дальше
## COIN_LANE_MIN от осей полос кольца, вне KIOSK_SQUARE/ROOF_AREA (стелс C7), вне целых разрушаемых и в BOUNDS.
const COINS := {&"fence": 1, &"planter": 1, &"cones": 1, &"laundry": 1, &"carpet": 1, &"sand_box": 1,
	&"bin": 2, &"snowman": 2, &"sign_board": 2, &"crate": 2, &"stall": 2, &"sofa": 2, &"fort": 2, &"barrier": 2,
	&"bench": 3, &"seesaw": 3, &"domino": 4, &"sandpit": 4, &"slide": 4, &"carousel": 5, &"swing": 5, &"playhouse": 5,
	# BREAK-03: окружение (светлые 1–2, тяжёлые 3–5; общий лимит COIN_WINDOW_CAP тот же)
	&"sign_post": 1, &"fence_long": 2, &"lamp": 3, &"pole": 3, &"lamp_yard": 3, &"birch": 3,
	&"rowan": 3, &"bins": 3, &"bench_big": 3, &"poplar": 4, &"billboard": 4, &"parked": 4, &"pavilion": 5,
	&"shop24": 5, &"shawarma": 5, &"press": 5, &"shells": 5, &"dovecote": 5, &"playground": 5,
	&"carpet_post": 3, &"rink_board": 3, &"ice_slide": 4, &"ice_ramp": 3}
const COIN_COOLDOWN := 240.0
const COIN_WINDOW := 30.0
const COIN_WINDOW_CAP := 12
const COIN_SOLID_PAD := 0.45
const COIN_LANE_MIN := 2.5           # как у раскладки монет (coins_test: кузов троллейбуса 1,25 от оси)
const COIN_EMITTER_STEP := 0.5
const COIN_EMITTER_LOCAL_RADIUS := Ilyusha.PUNCH_REACH # перенос начала — не дальше выноса обычного удара
const COIN_EMITTER_DIRECTIONS := 32
const COIN_EMITTER_FINE_STEP := 0.05
const COIN_EMITTER_FINE_DIRECTIONS := 180

## Надписи штендеров (Label3D на обеих досках).
const SIGN_TEXT := {&"Z11_3": "ПРОДУКТЫ", &"Z17_2": "ПРОДУКТЫ 24\nХЛЕБ\nМОЛОКО"}

## Звук по виду: SoundDirector играет break_<материал>.
const SOUND := {&"planter": &"plastic", &"bin": &"metal", &"snowman": &"snow", &"seesaw": &"wood", &"carousel": &"metal",
	&"barrier": &"wood", &"cones": &"plastic", &"fence": &"metal", &"sign_board": &"plastic", &"crate": &"wood",
	&"sand_box": &"wood", &"laundry": &"plastic", &"carpet": &"snow", &"fort": &"snow", &"sofa": &"wood",
	&"tires": &"plastic", &"stall": &"wood", &"swing": &"metal", &"slide": &"metal", &"sandpit": &"wood",
	&"playhouse": &"wood", &"bench": &"wood", &"domino": &"wood",
	&"lamp": &"metal", &"pole": &"metal", &"lamp_yard": &"metal", &"sign_post": &"metal", &"billboard": &"metal",
	&"bins": &"metal", &"parked": &"metal", &"pavilion": &"metal", &"shop24": &"metal", &"shawarma": &"metal",
	&"press": &"metal", &"shells": &"metal", &"fence_long": &"metal", &"playground": &"metal", &"birch": &"wood",
	&"poplar": &"wood", &"rowan": &"wood", &"dovecote": &"wood", &"bench_big": &"wood",
	&"carpet_post": &"metal", &"rink_board": &"wood", &"ice_slide": &"wood", &"ice_ramp": &"snow"}

## BREAK-03 (решение владельца 30.10: «надо, чтобы всё, включая деревья»): окружение — записи
## Layout.env_breakables(). Облик — прежний (узлы LevelGeometry/Props и экземпляры пакетов EnvDress, записанные в
## LevelGeometry.break_visuals), из Looks — только остаток и обломки. Как ломается — ENV_MODE: topple — валится в
## сторону удара за FALL_SECONDS (с ускорением), сбрасывает снег и куржак, лежит LIE_SECONDS и уходит в снег за
## SINK_SECONDS, остаётся пень/обломок столба; shatter — стенки и стёкла разлетаются сразу, остаётся низкий каркас;
## dent — припаркованная машина сминается и сдвигается (облик), коллизия остаётся, воет сигнализация. Фонарь гаснет
## (LightingAndWeather.set_lamp) и загорается при восстановлении; провода на упавшем столбе оборваны, пока он лежит.
const ENV_MODE := {&"lamp": &"topple", &"pole": &"topple", &"lamp_yard": &"topple", &"birch": &"topple",
	&"poplar": &"topple", &"rowan": &"topple", &"sign_post": &"topple", &"billboard": &"topple", &"parked": &"dent"}
const ENV_KINDS := [&"lamp", &"pole", &"lamp_yard", &"birch", &"poplar", &"rowan", &"sign_post", &"billboard",
	&"pavilion", &"shop24", &"shawarma", &"press", &"shells", &"dovecote", &"bins", &"parked", &"bench_big",
	&"playground", &"fence_long", &"carpet_post", &"rink_board", &"ice_slide", &"ice_ramp"]
const LAMP_KINDS := [&"lamp", &"lamp_yard", &"shop24"]
## Видимая высота (м): куда ложится дерево, качание от удара и проверка «вне кадра» при восстановлении.
const ENV_HEIGHT := {&"poplar": 17.0, &"birch": 9.5, &"rowan": 5.0, &"lamp": 8.0, &"pole": 8.0, &"lamp_yard": 6.4,
	&"sign_post": 3.4, &"billboard": 10.8, &"dovecote": 6.0, &"pavilion": 3.0, &"shop24": 3.6}
const FALL_SECONDS := 0.9
const FALL_ANGLE := PI * 0.48
const LIE_SECONDS := 1.6
const SINK_SECONDS := 0.7
const DENT_SECONDS := 0.2
const PARKED_MASS := 1045.0
const PARKED_DRAG := 5.5
const PARKED_YAW_DRAG := 3.0
const PARKED_MASK := 1 | 2 | 4 | 32  # snow follows the same rule as the player car

var objects: Array = []          # Breakable по порядку Layout.BREAKABLES
var breaks := 0
var restores := 0
var debris_peak := 0             # для проверок: больше всего обломков разом
var alarms := 0
var lid_slams := 0
var babka_bubbles := 0
var coins_dropped := 0           # BREAK-02: монет выдано разрушаемыми (выброс и к машине)
var coin_drops: Array = []       # [clock, by, сколько, id] — для проверок и окна COIN_WINDOW
var clock := 0.0
var shake_left := 0.0

var _rng := RandomNumberGenerator.new()
var _world: Node
var _player: Node3D
var _car: Node3D
var _residents: Node
var _ambient: Node
var _meshes := {}                # prim → Mesh
var _mm := {}                    # ключ → MultiMesh
var _mm_nodes := {}              # ключ → MultiMeshInstance3D
var _pending := {}               # ключ → [[Breakable, slot]] при сборке
var _bakes := {}                 # вид|размер|роль|материал|вращение → имя запечённой сетки в _meshes
var _animating: Array = []       # Breakable с покачиванием, вращением или ростом
var _debris_mm: MultiMesh
var _debris_node: MultiMeshInstance3D
var _debris: Array = []          # слоты пула: {} — свободен
var _debris_groups: Array = []   # [номер группы] по времени
var _debris_group := 0
var _dust: Array = []            # CPUParticles3D, пул из DEBRIS_MAX_BREAKS
var _dust_next := 0
var _camera_offset := Vector2.ZERO
var _babka_back: Sprite3D
var _babka_label: Label3D
var _babka_left := 0.0
var _babka_ready_at := -INF
var _alarms := {}                # индекс машины → {left, node}
var _lid_ready := {}             # индекс контейнера → clock
var _connected_punch := false
var _coins_node: Node
var _coin_rects: Array = []      # постоянные коробки с запасом COIN_SOLID_PAD; разрушаемые проверяются живыми
var _coin_lanes: Array = []      # оси полос кольца (Vector2)
var _by_id := {}                 # id → Breakable
var _remnant_users := {}         # ключ MultiMesh остатка → [Breakable]: узел виден, только пока хоть один сломан
var _cut := []                   # BREAK-03: [узел, [Breakable]] — виден, пока ни один владелец не сломан
var _wires := []                 # BREAK-03: [MultiMesh, индекс, Transform3D, [Breakable]] — провод на столбах
var _lighting: Node
var _by_solid := {}
var env_objects: Array = []      # BREAK-03: Breakable окружения (Layout.env_breakables) по порядку

static var _live: Array = []     # Breakable всех миров — для Resident.flight_distance

func _init() -> void:
	name = "Breakables"

func _ready() -> void:
	add_to_group(GROUP_ROOT)
	_rng.seed = SEED
	_world = _find_world()
	if _world:
		_player = _world.get_node_or_null("Ilyusha")
		_car = _world.get_node_or_null("Car")
	_build_meshes()
	for spec: Array in Layout.BREAKABLES:
		_add(spec)
	_add_env()
	_flush_multimeshes()
	_build_debris()
	_connect_punch()

## BREAK-03: окружение (Layout.env_breakables): тело слоя 6, остаток из Looks, облик — из LevelGeometry.break_visuals.
func _add_env() -> void:
	var geo := get_parent()
	var registry: Dictionary = geo.get("break_visuals") if geo and geo.get("break_visuals") is Dictionary else {}
	var cut := {}       # узел → [Breakable]
	var wires := {}     # "mm|индекс" → [MultiMesh, индекс, Transform3D, [id]]
	for spec: Array in Layout.env_breakables():
		var b := _add(spec)
		b.mode = ENV_MODE.get(b.kind, &"shatter")
		b.env_index = spec[6]
		_by_solid[b.env_index] = b
		b.body.collision_layer = LAYER | 1
		env_objects.append(b)
		var entry: Dictionary = registry.get(b.id, {})
		b.attach_env(entry)
		if b.kind == &"parked":
			b.register_vehicle()
		for node: Node3D in entry.get("cut", []):
			if not cut.has(node):
				cut[node] = []
			cut[node].append(b)
		for w: Array in entry.get("wires", []):
			wires["%d|%d" % [(w[0] as MultiMesh).get_instance_id(), w[1]]] = w
	for node in cut:
		_cut.append([node, cut[node], node.visible, false])
	for key in wires:
		var w: Array = wires[key]
		var owners: Array = []
		for id: StringName in w[3]:
			if _by_id.has(id):
				owners.append(_by_id[id])
		if not owners.is_empty():
			_wires.append([w[0], w[1], w[2], owners])

func _exit_tree() -> void:
	for b in objects:
		_live.erase(b)

func _find_world() -> Node:
	var node := get_parent()
	while node:
		if node is DemoWorld:
			return node
		node = node.get_parent()
	return null

## Новый объект по записи Layout.BREAKABLES (и для замеров FPS: spawn после _ready).
func spawn(spec: Array) -> Breakable:
	var b := _add(spec)
	_flush_multimeshes()
	return b

func _add(spec: Array) -> Breakable:
	var b := Breakable.new()
	b.env_index = int(spec[6]) if spec.size() > 6 else -1
	b.setup(spec)
	b.name = "Breakable_%s" % b.id
	add_child(b)
	b.root = self
	objects.append(b)
	_live.append(b)
	_by_id[b.id] = b
	b.broken.connect(func(o: Breakable, by: StringName): broken.emit(o, by))
	b.restored.connect(func(o: Breakable): restored.emit(o))
	var cx := floori(b.center.x / CLUSTER)
	var cz := floori(b.center.y / CLUSTER)
	if ENV_KINDS.has(b.kind):
		cx = 0   # BREAK-03: у окружения из Looks только остаток — один MultiMesh на вид, виден, пока что-то сломано
		cz = 0
	# BREAK-02: части вида с одной ролью, материалом и вращением запечены в одну сетку (цвет — в вершинах): один
	# экземпляр MultiMesh на группу вместо экземпляра на примитив — меньше вызовов отрисовки.
	var groups := {}
	for part: Array in Looks.parts(b.kind, b.size):
		var g := "%s|%s|%s" % [part[4], part[3], part[5]]
		if not groups.has(g):
			groups[g] = []
		groups[g].append(part)
	for g: String in groups:
		var first: Array = groups[g][0]
		var bake_key := "%s|%s|%s" % [b.kind, b.size, g]
		var prim: String = _bakes.get(bake_key, "")
		if prim == "":
			prim = "bake%d" % _bakes.size()
			_meshes[prim] = bake(groups[g], _meshes)
			_bakes[bake_key] = prim
		var key := "%s|%d|%d|%s|%s|%s" % [b.kind, cx, cz, prim, first[3], "detail" if first[4] == "detail" else "main"]
		var slot := {"key": key, "local": Transform3D.IDENTITY, "color": Color.WHITE, "role": first[4], "spin": first[5], "index": -1}
		b.slots.append(slot)
		if first[4] == "remnant":
			if not _remnant_users.has(key):
				_remnant_users[key] = []
			_remnant_users[key].append(b)
		if not _pending.has(key):
			_pending[key] = []
		_pending[key].append(slot)
	if b.kind == &"barrier":
		b.add_dig_extras()
	if SIGN_TEXT.has(b.id):
		b.add_sign_text(SIGN_TEXT[b.id])
	return b

## Части [примитив, Transform3D, цвет, …] — одна сетка: вершины и нормали в осях объекта, цвет части в вершинах.
static func bake(parts: Array, meshes: Dictionary) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Array in parts:
		var arrays: Array = (meshes[part[0]] as PrimitiveMesh).get_mesh_arrays()
		var xf: Transform3D = part[1]
		var nb := xf.basis.inverse().transposed()
		var base := verts.size()
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var color: Color = part[2]
		for k in pv.size():
			verts.append(xf * pv[k])
			normals.append((nb * pn[k]).normalized())
			colors.append(color)
		var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var flip := xf.basis.determinant() < 0.0
		for k in range(0, pi.size(), 3):
			indices.append(base + pi[k])
			indices.append(base + (pi[k + 2] if flip else pi[k + 1]))
			indices.append(base + (pi[k + 1] if flip else pi[k + 2]))
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh

## Слоты, накопленные _add, — в MultiMesh (существующий ключ — пересобрать с прежними экземплярами).
func _flush_multimeshes() -> void:
	for key: String in _pending:
		var fresh: Array = _pending[key]
		var mm: MultiMesh = _mm.get(key)
		var keep: Array = []
		if mm != null:
			for b in objects:
				for slot in b.slots:
					if slot["key"] == key and slot["index"] >= 0:
						keep.append(slot)
		var all: Array = keep + fresh
		var bits: PackedStringArray = key.split("|")
		var prim := bits[3]
		var mat := bits[4]
		var role := bits[5]
		if mm == null:
			mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = mat == "paint" and not prim.begins_with("bake")   # у запечённых цвет в вершинах
			mm.mesh = _meshes[prim]
			_mm[key] = mm
			var node := MultiMeshInstance3D.new()
			node.name = "MM_" + key.replace("|", "_")
			node.multimesh = mm
			node.material_override = Materials.instance_colored() if mat == "paint" else Materials.snow(0.0)
			var kind := StringName(bits[0])
			node.set_meta(&"kind", kind)
			var tall := false
			for b in objects:
				if b.kind == kind and b.size.y >= LOW_NO_SHADOW:
					tall = true
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tall and role != "detail" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if role == "detail":
				node.visibility_range_end = FAR_DETAIL
				node.visibility_range_end_margin = 4.0
			add_child(node)
			_mm_nodes[key] = node
		mm.instance_count = all.size()
		for i in all.size():
			all[i]["index"] = i
		for b in objects:
			b.mm_dirty = true
	_pending.clear()
	for b in objects:
		if b.mm_dirty:
			b.mm_dirty = false
			_write(b)
	for key: String in _remnant_users:
		_refresh_remnant(key)

## BREAK-03 (FPS): узел MultiMesh остатков рисуется, только пока сломан хоть один его объект.
func _refresh_remnant(key: String) -> void:
	var node: MultiMeshInstance3D = _mm_nodes.get(key)
	if node:
		node.visible = (_remnant_users[key] as Array).any(func(o: Breakable): return o.state == &"broken")

## Положение всех экземпляров объекта: поза (покачивание, рост) × вращение части × локальная сетка.
func _write(b: Breakable) -> void:
	if not b.env_nodes.is_empty() or not b.env_mm.is_empty():
		_write_env(b)
	var base := b.pose()
	for slot in b.slots:
		if slot["role"] == "remnant" and _remnant_users.has(slot["key"]):
			_refresh_remnant(slot["key"])
	var spin := Transform3D(Basis(Vector3.UP, b.spin_angle), Vector3.ZERO)
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), b.global_ground())
	for slot in b.slots:
		var i: int = slot["index"]
		if i < 0:
			continue
		var mm: MultiMesh = _mm[slot["key"]]
		var role: String = slot["role"]
		var shown := (role == "remnant") == (b.state == &"broken") or role == "base"
		if b.state == &"growing" and role == "remnant":
			shown = false
		var xf: Transform3D = zero
		if shown:
			var local: Transform3D = slot["local"]
			if slot["spin"]:
				local = spin * local
			xf = (b.base_xf() * local) if role in ["remnant", "base"] else (base * local)
		mm.set_instance_transform(i, xf)
		if mm.use_colors:
			mm.set_instance_color(i, slot["color"])

## Поиск динамической опоры для потребителей, которые хранят исходные коробки Layout.
func env_at_index(index: int) -> Breakable:
	return _by_solid.get(index)

func _write_env(b: Breakable) -> void:
	var delta := b.env_delta()
	var hidden := b.env_hidden()
	for i in b.env_nodes.size():
		var node: Node3D = b.env_nodes[i]
		if is_instance_valid(node):
			node.global_transform = delta * b.env_node_xf[i]
			node.visible = not hidden and b.env_node_visible[i]
	if b.mode == &"dent":
		b.body.global_transform = delta * b.base_xf()
	for part: Array in b.env_mm:
		var node: MultiMeshInstance3D = part[3]
		if not is_instance_valid(node): continue
		var xf: Transform3D = delta * part[4]
		if hidden: xf.basis = Basis.from_scale(Vector3.ZERO)
		(part[0] as MultiMesh).set_instance_transform(part[1], node.global_transform.affine_inverse() * xf)

func register_cut(node: Node3D, id: StringName) -> void:
	var owner: Breakable = _by_id.get(id)
	if owner == null: return
	for entry: Array in _cut:
		if entry[0] == node:
			if not (entry[1] as Array).has(owner): entry[1].append(owner)
			return
	_cut.append([node, [owner], node.visible, false])

func _refresh_cut_wires() -> void:
	# Residents может удалить LifeProps; проверяем ссылку до присваивания Node3D.
	var index := 0
	while index < _cut.size():
		var entry: Array = _cut[index]
		if not is_instance_valid(entry[0]):
			_cut.remove_at(index)
			continue
		var node: Node3D = entry[0]
		index += 1
		var intact := (entry[1] as Array).all(func(b: Breakable): return b.is_intact())
		if not intact:
			if not entry[3]: entry[2] = node.visible
			entry[3] = true
			node.visible = false
		elif entry[3]:
			node.visible = false if node.has_meta(&"life_support_prop") else entry[2]
			entry[3] = false
	for entry: Array in _wires:
		var visible := (entry[3] as Array).all(func(b: Breakable): return b.is_intact())
		var xf: Transform3D = entry[2]
		if not visible: xf.basis = Basis.from_scale(Vector3.ZERO)
		(entry[0] as MultiMesh).set_instance_transform(entry[1], xf)

func _env_lamp(b: Breakable, on: bool) -> void:
	if not LAMP_KINDS.has(b.kind): return
	if not is_instance_valid(_lighting) and _world:
		_lighting = _world.get_node_or_null("LightingAndWeather")
	if is_instance_valid(_lighting) and _lighting.has_method("set_lamp"):
		_lighting.set_lamp(b.center, on)

func _build_meshes() -> void:
	var box := BoxMesh.new()
	_meshes["box"] = box
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	_meshes["cyl"] = cyl
	var frustum := CylinderMesh.new()
	frustum.top_radius = 0.36
	frustum.bottom_radius = 0.5
	frustum.height = 1.0
	frustum.radial_segments = 12
	frustum.rings = 1
	_meshes["frustum"] = frustum
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 12
	cone.rings = 1
	_meshes["cone"] = cone
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 14
	sphere.rings = 7
	_meshes["sphere"] = sphere
	var torus := TorusMesh.new()
	torus.inner_radius = 0.25
	torus.outer_radius = 0.5
	torus.rings = 16
	torus.ring_segments = 8
	_meshes["torus"] = torus
	_meshes["prism"] = PrismMesh.new()   # BREAK-02: фронтоны (остриё вверху, глубина по z)

# --- кадр ---

func _physics_process(delta: float) -> void:
	clock += delta
	if not _connected_punch:
		_connect_punch()
	for b in objects:
		b.tick(delta)
	var still: Array = []
	for b in _animating:
		if b.animate(delta):
			still.append(b)
		_write(b)
	_animating = still
	_update_debris(delta)
	_update_shake(delta)
	_update_babka(delta)
	_update_alarms(delta)

func animate(b: Breakable) -> void:
	if not b in _animating:
		_animating.append(b)

# --- кто ломает: «Лада» ---

## Касания «Лады» за последний move_and_slide. before — горизонтальная скорость до упора. Возвращает новую
## горизонтальную скорость, если её надо поправить (поломка без замедления или × HEAVY_SLOWDOWN), иначе Vector3.INF.
func car_contacts(car: CharacterBody3D, before: Vector3, throttle: float, delta: float) -> Vector3:
	var result := Vector3.INF
	var other_hit := false
	var any_broken := false
	var heavy_broken := false
	for i in car.get_slide_collision_count():
		var hit := car.get_slide_collision(i)
		var collider := hit.get_collider()
		var normal := hit.get_normal()
		var into := Vector3(-normal.x, 0.0, -normal.z)
		if into.length_squared() < 0.0001:
			continue   # пол
		into = into.normalized()
		var speed := maxf(before.dot(into), 0.0)
		var b := _breakable_of(collider)
		if b == null:
			other_hit = true
			_react(hit.get_position(), speed)
			continue
		if b.kind in [&"parked", &"bins"]:
			_react(hit.get_position(), speed)
		if b.kind == &"parked":
			other_hit = true   # solid even when the shared impulse has already marked it broken
		var outcome := b.car_contact(speed, absf(throttle) > 0.05, delta, into)
		if outcome == &"dent":
			other_hit = true
		elif outcome == &"light":
			any_broken = true
		elif outcome == &"heavy":
			any_broken = true
			heavy_broken = true
	if any_broken and not other_hit:
		result = before * (HEAVY_SLOWDOWN if heavy_broken else 1.0)
	if heavy_broken:
		shake_left = SHAKE_SECONDS
	return result

func _breakable_of(collider: Object) -> Breakable:
	if collider is StaticBody3D:
		var owner_node := (collider as Node).get_parent()
		if owner_node is Breakable:
			return owner_node
	return null

# --- кто ломает: Илюша ---

func _connect_punch() -> void:
	_connected_punch = true
	if _player and _player.has_signal("punch_landed") and not _player.punch_landed.is_connected(_on_punch_landed):
		_player.punch_landed.connect(_on_punch_landed)

func _on_punch_landed(targets: Array) -> void:
	var dir := Vector3.FORWARD
	if _player and _player.has_method("facing_dir"):
		dir = _player.facing_dir()
	for target in targets:
		if target is Breakable:
			(target as Breakable).punch(dir)

# --- обломки ---

func _build_debris() -> void:
	_debris_mm = MultiMesh.new()
	_debris_mm.transform_format = MultiMesh.TRANSFORM_3D
	_debris_mm.use_colors = true
	_debris_mm.mesh = _meshes["box"]
	_debris_mm.instance_count = DEBRIS_POOL
	_debris_mm.custom_aabb = AABB(Vector3(Layout.BOUNDS.position.x - 10.0, -1.0, Layout.BOUNDS.position.y - 10.0),
		Vector3(Layout.BOUNDS.size.x + 20.0, 20.0, Layout.BOUNDS.size.y + 20.0))
	for i in DEBRIS_POOL:
		_debris_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_debris.append({})
	_debris_node = MultiMeshInstance3D.new()
	_debris_node.name = "Debris"
	_debris_node.multimesh = _debris_mm
	_debris_node.material_override = Materials.instance_colored()
	_debris_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debris_node.visible = false
	add_child(_debris_node)

## Сколько обломков сейчас в воздухе или на снегу.
func debris_count() -> int:
	var n := 0
	for d: Dictionary in _debris:
		if not d.is_empty():
			n += 1
	return n

## Сколько поломок сейчас дают обломки.
func debris_breaks() -> int:
	var groups := {}
	for d: Dictionary in _debris:
		if not d.is_empty():
			groups[d["group"]] = true
	return groups.size()

## Обломки после поломки: куски по виду, разлёт вверх и по dir; житель ближе DEBRIS_CLEAR — разлёт от него.
func spawn_debris(b: Breakable, dir: Vector3) -> void:
	# A dent keeps the native body intact; generic ENV beams would falsely depict fractured panels.
	if b.mode == &"dent":
		return
	var live := {}
	for d: Dictionary in _debris:
		if not d.is_empty():
			live[d["group"]] = true
	while live.size() >= DEBRIS_MAX_BREAKS and not _debris_groups.is_empty():
		var oldest: int = _debris_groups.pop_front()
		if live.has(oldest):
			_free_group(oldest)
			live.erase(oldest)
	_debris_group += 1
	_debris_groups.append(_debris_group)
	var away := Vector3.ZERO
	var near := _nearest_resident(b.global_ground())
	if near != null:
		var to: Vector3 = b.global_ground() - near.global_position
		to.y = 0.0
		if to.length() < DEBRIS_CLEAR:
			away = to.normalized() if to.length() > 0.01 else -dir
	var flat_dir := Vector3(dir.x, 0.0, dir.z)
	flat_dir = flat_dir.normalized() if flat_dir.length() > 0.01 else Vector3.ZERO
	var pieces := Looks.debris(b.kind, b.size)
	var budget := DEBRIS_PER_BREAK
	var free_slots: Array[int] = []
	for i in DEBRIS_POOL:
		if _debris[i].is_empty():
			free_slots.append(i)
	var count := mini(mini(pieces.size(), budget), free_slots.size())
	for k in count:
		var piece: Array = pieces[k]
		var size: Vector3 = piece[0] * _rng.randf_range(0.8, 1.2)
		var a := TAU * float(k) / float(count) + _rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0.0, sin(a))
		var horizontal: Vector3 = out * _rng.randf_range(0.8, 2.2) + flat_dir * _rng.randf_range(1.0, 2.5) * float(piece[2])
		if away != Vector3.ZERO and horizontal.dot(away) < 0.0:
			horizontal -= away * horizontal.dot(away) * 2.0   # от жителя
		var start := b.global_ground() + Vector3(_rng.randf_range(-0.3, 0.3) * b.size.x, _rng.randf_range(0.1, 0.4) * minf(b.size.y, 2.0) if b.env_index >= 0 else _rng.randf_range(0.2, 0.9) * b.size.y,
			_rng.randf_range(-0.3, 0.3) * b.size.z)
		var slot := free_slots[k]
		_debris[slot] = {"group": _debris_group, "pos": start,
			"vel": horizontal + Vector3.UP * _rng.randf_range(2.0, 4.0),
			"rot": Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)),
			"spin": Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9), _rng.randf_range(-9, 9)),
			"size": size, "color": piece[1], "rest": _rng.randf_range(DEBRIS_REST.x, DEBRIS_REST.y),
			"landed": false, "age": 0.0, "melt": 0.0}
		_debris_mm.set_instance_color(slot, piece[1])
	_debris_node.visible = true
	debris_peak = maxi(debris_peak, debris_count())
	_puff(b.global_ground(), b.kind in [&"snowman", &"fort"] or b.env_index >= 0)

func _free_group(group: int) -> void:
	for i in DEBRIS_POOL:
		var d: Dictionary = _debris[i]
		if not d.is_empty() and d["group"] == group:
			_debris[i] = {}
			_debris_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

func _update_debris(delta: float) -> void:
	if not _debris_node.visible:
		return
	var any := false
	for i in DEBRIS_POOL:
		var d: Dictionary = _debris[i]
		if d.is_empty():
			continue
		any = true
		var size: Vector3 = d["size"]
		var rest_y := minf(minf(size.x, size.y), size.z) * 0.5 + 0.01
		var p: Vector3 = d["pos"]
		if not d["landed"]:
			var v: Vector3 = d["vel"]
			v.y -= DEBRIS_GRAVITY * delta
			p += v * delta
			d["rot"] = (d["rot"] as Basis).rotated((d["spin"] as Vector3).normalized(), (d["spin"] as Vector3).length() * delta).orthonormalized()
			if p.y <= rest_y and v.y < 0.0:
				p.y = rest_y
				if absf(v.y) > 2.5:   # один отскок
					v = Vector3(v.x * 0.35, absf(v.y) * 0.25, v.z * 0.35)
				else:
					d["landed"] = true
					d["rot"] = _lay_flat(d["rot"], size)
			d["vel"] = v
			d["pos"] = p
		else:
			d["rest"] = float(d["rest"]) - delta
			if d["rest"] <= 0.0:
				d["melt"] = float(d["melt"]) + delta
				if d["melt"] >= DEBRIS_MELT:
					_debris[i] = {}
					_debris_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
					continue
		d["age"] = float(d["age"]) + delta
		var k := 1.0 - clampf(float(d["melt"]) / DEBRIS_MELT, 0.0, 1.0)
		var shown := Vector3(size.x * lerpf(0.4, 1.0, k), size.y * k, size.z * lerpf(0.4, 1.0, k))
		var at := p
		if d["landed"]:
			at.y = rest_y * k
		_debris_mm.set_instance_transform(i, Transform3D((d["rot"] as Basis) * Basis.from_scale(shown), at))
	if not any:
		_debris_node.visible = false

## Лечь на снег: самая короткая ось — вертикально, поворот вокруг вертикали сохраняется.
static func _lay_flat(rot: Basis, size: Vector3) -> Basis:
	var axis := 0
	if size.y <= size.x and size.y <= size.z:
		axis = 1
	elif size.z <= size.x and size.z <= size.y:
		axis = 2
	var yaw := atan2(rot.x.z, rot.x.x)
	var flat := Basis(Vector3.UP, -yaw)
	match axis:
		0: return flat * Basis(Vector3.FORWARD, PI * 0.5)
		2: return flat * Basis(Vector3.RIGHT, PI * 0.5)
	return flat

## Обломки, которые сейчас на снегу: [позиция, размер] — для проверок.
func debris_pieces() -> Array:
	var out := []
	for d: Dictionary in _debris:
		if not d.is_empty():
			out.append([d["pos"], d["size"], d["landed"], d["age"]])
	return out

func _puff(at: Vector3, big: bool) -> void:
	if _dust.is_empty():
		for i in DEBRIS_MAX_BREAKS:
			_dust.append(_make_dust())
	var dust: CPUParticles3D = _dust[_dust_next]
	_dust_next = (_dust_next + 1) % _dust.size()
	dust.global_position = at + Vector3.UP * 0.2
	dust.amount = 48 if big else 28
	dust.emission_sphere_radius = 0.6 if big else 0.4
	dust.restart()
	dust.emitting = true

## Снежная пыль — как Resident._puff (KNOCK-01): шейдер брызг PLAY-03, разово.
func _make_dust() -> CPUParticles3D:
	var blob := Gradient.new()
	blob.set_color(0, Color(1, 1, 1, 1))
	blob.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = blob
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	var look := ShaderMaterial.new()
	look.shader = SNOW_PUFF_SHADER
	look.set_shader_parameter("albedo", Resident.KNOCK_SNOW)
	look.set_shader_parameter("texture_albedo", dot)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	quad.material = look
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.95))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var dust := CPUParticles3D.new()
	dust.name = "BreakDust"
	dust.top_level = true
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = 28
	dust.lifetime = 0.9
	dust.mesh = quad
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.4
	dust.direction = Vector3.UP
	dust.spread = 75.0
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 2.6
	dust.gravity = Vector3(0, -3.0, 0)
	dust.damping_min = 2.0
	dust.damping_max = 3.5
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 2.0
	dust.color_ramp = fade
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.emitting = false
	add_child(dust)
	return dust

# --- монеты (BREAK-02) ---

## Сколько монет даст объект вида kind (нет в COINS — light 1, heavy 3).
static func coin_count(kind: StringName, heavy: bool) -> int:
	return COINS.get(kind, 3 if heavy else 1)

## Монеты из сломанного b: по виду, с лимитами COIN_COOLDOWN и COIN_WINDOW_CAP; «Лада» — к машине, удар — разлёт.
func drop_coins(b: Breakable, by: StringName) -> int:
	if by != &"car" and by != &"punch":
		return 0
	if clock - b.coins_at < COIN_COOLDOWN:
		return 0
	var recent := 0
	for d: Array in coin_drops:
		if clock - float(d[0]) < COIN_WINDOW:
			recent += int(d[2])
	var n := mini(coin_count(b.kind, b.heavy), COIN_WINDOW_CAP - recent)
	var coins := _coins()
	if n <= 0 or coins == null:
		return 0
	var at := b.global_ground() + Vector3.UP * clampf(b.size.y * 0.7, 0.6, 1.4)
	if b.env_index >= 0:
		var away := (_player.global_position - at) if is_instance_valid(_player) else b.fall_dir
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
		var reach := maxf(b.size.x, b.size.z) * 0.5
		if by == &"punch":
			# Выброс рядом с задетой гранью: длина забора не отодвигает монеты от его тонкого бока.
			reach = INF
			if not is_zero_approx(away.x):
				reach = minf(reach, b.size.x * 0.5 / absf(away.x))
			if not is_zero_approx(away.z):
				reach = minf(reach, b.size.z * 0.5 / absf(away.z))
		at += away * (reach + 0.8)
	var made := 0
	if by == &"car":
		made = coins.spawn_to_collector(at, n)
	else:
		if b.env_index >= 0:
			at = _coin_emitter(at)
			if not at.is_finite():
				return 0
		made = coins.spawn_burst(at, n, coin_spot_ok.bind(b))
	if made > 0:
		b.coins_at = clock
		b.coins_given += made
		coins_dropped += made
		coin_drops.append([clock, by, made, b.id])
	return made

## Допустимое исходное начало сохраняется. Иначе ищем только рядом с ним, у задетой грани;
## если локальной безопасной точки нет, drop_coins возвращает ноль до учёта награды.
func _coin_emitter(at: Vector3) -> Vector3:
	if coin_spot_ok(at):
		return at
	for ring in range(1, ceili(COIN_EMITTER_LOCAL_RADIUS / COIN_EMITTER_STEP) + 1):
		var radius := minf(ring * COIN_EMITTER_STEP, COIN_EMITTER_LOCAL_RADIUS)
		for direction in COIN_EMITTER_DIRECTIONS:
			var angle := TAU * direction / COIN_EMITTER_DIRECTIONS
			var candidate := at + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if coin_spot_ok(candidate):
				return candidate
	# У границы досягаемости проверяем и узкие промежутки между направлениями.
	for direction in COIN_EMITTER_FINE_DIRECTIONS:
		var angle := TAU * direction / COIN_EMITTER_FINE_DIRECTIONS
		var candidate := at + Vector3(cos(angle), 0.0, sin(angle)) * COIN_EMITTER_LOCAL_RADIUS
		if coin_spot_ok(candidate):
			return candidate
	# Узкая безопасная полоса может лежать между крупными кольцами.
	for ring in range(1, ceili(COIN_EMITTER_LOCAL_RADIUS / COIN_EMITTER_FINE_STEP) + 1):
		var radius := minf(ring * COIN_EMITTER_FINE_STEP, COIN_EMITTER_LOCAL_RADIUS)
		for direction in COIN_EMITTER_DIRECTIONS:
			var angle := TAU * direction / COIN_EMITTER_DIRECTIONS
			var candidate := at + Vector3(cos(angle), 0.0, sin(angle)) * radius
			if coin_spot_ok(candidate):
				return candidate
	return Vector3.INF

## Узел монет COINS-01 (как у дронов): группа «coins» или узел «Coins» в мире; нет — null.
func _coins() -> Node:
	if _coins_node == null or not is_instance_valid(_coins_node):
		_coins_node = get_tree().get_first_node_in_group(&"coins") if is_inside_tree() else null
		if _coins_node == null and get_parent():
			_coins_node = get_parent().get_node_or_null("Coins")
		if _coins_node == null and _world:
			_coins_node = _world.find_child("Coins", true, false)
	return _coins_node if _coins_node and _coins_node.has_method("spawn_to_collector") else null

## Можно ли монете лечь в p (выброс из сломанного b): не в стене, не на полосе кольца, не на площадке киоска.
func coin_spot_ok(p: Vector3, _owner: Breakable = null) -> bool:
	var xz := Vector2(p.x, p.z)
	if not Layout.BOUNDS.grow(-1.0).has_point(xz) or Layout.KIOSK_SQUARE.grow(1.0).has_point(xz) or Layout.ROOF_AREA.has_point(xz):
		return false
	if _coin_rects.is_empty():
		var solids := Layout.all_solids()
		for index in solids.size():
			if not Layout.env_break_at(index).is_empty(): continue
			var spec: Array = solids[index]
			var c: Vector2 = spec[2]
			var size: Vector3 = spec[3]
			_coin_rects.append(Rect2(c - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)).grow(COIN_SOLID_PAD))
		for lane in [Layout.ring_lane(), Layout.ring_lane(6.0, 6, true)]:
			var pts: Array = []
			for q: Vector3 in lane:
				pts.append(Vector2(q.x, q.z))
			_coin_lanes.append(pts)
	for r: Rect2 in _coin_rects:
		if r.has_point(xz):
			return false
	for pts: Array in _coin_lanes:
		for i in pts.size():
			var a: Vector2 = pts[i]
			var c: Vector2 = pts[(i + 1) % pts.size()]
			if xz.distance_to(Geometry2D.get_closest_point_to_segment(xz, a, c)) < COIN_LANE_MIN:
				return false
	# Смятая машина остаётся твёрдой, в том числе для монет собственного выброса.
	for o: Breakable in objects:
		if o.blocks() and o.rect().grow(COIN_SOLID_PAD if o.env_index >= 0 else 0.2).has_point(xz):
			return false
	return true

# --- кто рядом ---

func _residents_list() -> Array:
	if _residents == null or not is_instance_valid(_residents):
		_residents = get_tree().get_first_node_in_group(&"residents") if is_inside_tree() else null
	return _residents.residents if _residents != null else []

func _nearest_resident(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for r: Node3D in _residents_list():
		if not r.is_visible_in_tree():
			continue
		var d := Vector2(r.global_position.x - at.x, r.global_position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = r
	return best

func _dog() -> Node3D:
	if _ambient == null or not is_instance_valid(_ambient):
		_ambient = get_parent().get_node_or_null("Ambient") if get_parent() else null
	return _ambient.get("dog") if _ambient != null else null

## Можно ли вернуть объект сейчас: Илюша и «Лада» дальше RESTORE_FAR, объект вне кадра, на месте нет тела.
func can_restore(b: Breakable) -> bool:
	var at := b.global_ground()
	for body in [_player, _car]:
		if body != null and Vector2(body.global_position.x - at.x, body.global_position.z - at.z).length() <= RESTORE_FAR:
			return false
	if in_view(b):
		return false
	return place_free(b)

## Объект (его коробка) в усечённой пирамиде текущей камеры.
func in_view(b: Breakable) -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return false
	var box := b.env_bounds if b.env_index >= 0 else b.base_xf() * AABB(Vector3(-b.size.x * 0.5, 0.0, -b.size.z * 0.5), b.size)
	if b.mode == &"dent":
		box = box.merge(b.env_delta() * box)
	var corners: Array[Vector3] = []
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			for z in [box.position.z, box.end.z]:
				corners.append(Vector3(x, y, z))
	# The view may intersect a face without seeing a single corner (e.g. only a billboard's top).
	var inside := camera.global_position - camera.global_basis.z * ((camera.near + camera.far) * 0.5)
	for plane: Plane in camera.get_frustum():
		var side := signf(plane.distance_to(inside))
		if corners.all(func(point: Vector3): return plane.distance_to(point) * side < 0.0):
			return false
	return true

## На месте объекта нет тела: Илюша, «Лада», жители, собака (по коробке с запасом 0,3 м) и физика слоёв 2 и 4.
func place_free(b: Breakable) -> bool:
	var rect := b.rect().grow(0.3)
	var bodies: Array = [_player, _car]
	for r in _residents_list():
		if r.is_visible_in_tree():
			bodies.append(r)
	bodies.append(_dog())
	for body in bodies:
		if body is Node3D and is_instance_valid(body):
			var p: Vector3 = (body as Node3D).global_position
			if rect.has_point(Vector2(p.x, p.z)):
				return false
	if _car is Lada:
		var car_rect := Rect2(Vector2(_car.global_position.x, _car.global_position.z) - Vector2(2.3, 2.3), Vector2(4.6, 4.6))
		if car_rect.intersects(rect):
			return false
	return overlaps(b).is_empty()

## Подвижные тела Player, Car и World (транспорт), пересекающие исходную коробку.
## Статические земля/стены не блокируют возврат существовавшего здесь окружения.
func overlaps(b: Breakable) -> Array:
	if not is_inside_tree():
		return []
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = b.body_size() - Vector3(0.1, 0.1, 0.1)
	query.shape = box
	query.transform = b.base_xf() * Transform3D(Basis.IDENTITY, Vector3(0, b.body_size().y * 0.5, 0))
	query.collision_mask = 1 | 2 | 4
	query.exclude = [b.body.get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 64)
	return hits.filter(func(hit: Dictionary): return hit.collider is CharacterBody3D or hit.collider is AnimatableBody3D)

func next_restore_delay() -> float:
	return _rng.randf_range(RESTORE_SECONDS.x, RESTORE_SECONDS.y)

## Для тестов и перезапуска: всё целое сразу, обломков и пыли нет, тряски и пузыря нет, rng и счётчики с начала.
func reset_positions() -> void:
	_rng.seed = SEED
	for b in objects:
		b.reset()
		_env_lamp(b, true)
		_write(b)
	_animating.clear()
	_refresh_cut_wires()
	for i in DEBRIS_POOL:
		_debris[i] = {}
		_debris_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_debris_node.visible = false
	_debris_groups.clear()
	for dust: CPUParticles3D in _dust:
		dust.emitting = false
	breaks = 0
	restores = 0
	debris_peak = 0
	alarms = 0
	lid_slams = 0
	babka_bubbles = 0
	coins_dropped = 0
	coin_drops.clear()
	shake_left = 0.0
	_update_shake(0.0)
	_babka_left = 0.0
	_babka_ready_at = -INF
	if _babka_back:
		_babka_back.visible = false
	for k in _alarms.keys():
		_stop_alarm(k)
	_lid_ready.clear()

## Целые объекты в плане (с запасом pad) — препятствия для полёта сбитого жителя (Resident.flight_distance).
## Мира нет — все записи Layout.BREAKABLES и Layout.env_breakables().
static func intact_rects(pad: float) -> Array:
	var out: Array = []
	var alive := _live.filter(func(b): return is_instance_valid(b))
	if alive.is_empty():
		for spec: Array in Layout.BREAKABLES + Layout.env_breakables():
			out.append(spec_rect(spec).grow(pad))
		return out
	for b: Breakable in alive:
		if b.blocks():
			out.append(b.rect().grow(pad))
	return out

## Прямоугольник в плане по записи (с учётом yaw — описанный).
static func spec_rect(spec: Array) -> Rect2:
	var c: Vector2 = spec[2]
	var size: Vector3 = spec[3]
	var yaw: float = spec[4]
	var hx := absf(cos(yaw)) * size.x * 0.5 + absf(sin(yaw)) * size.z * 0.5
	var hz := absf(sin(yaw)) * size.x * 0.5 + absf(cos(yaw)) * size.z * 0.5
	return Rect2(c - Vector2(hx, hz), Vector2(hx, hz) * 2.0)

func get_by_id(id: StringName) -> Breakable:
	return _by_id.get(id)

# --- тряска камеры ---

func _update_shake(delta: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	if shake_left <= 0.0:
		if _camera_offset != Vector2.ZERO:
			camera.h_offset -= _camera_offset.x
			camera.v_offset -= _camera_offset.y
			_camera_offset = Vector2.ZERO
		return
	shake_left = maxf(shake_left - delta, 0.0)
	var k := shake_left / SHAKE_SECONDS
	var offset := Vector2(sin(clock * 71.0), cos(clock * 53.0)) * SHAKE * k
	camera.h_offset += offset.x - _camera_offset.x
	camera.v_offset += offset.y - _camera_offset.y
	_camera_offset = offset

# --- квестовая Бабка: пузырь ---

## Объект сломан рядом с квестовой Бабкой — пузырь над ней (QuestLines.BREAK_LINES_BABKA по кругу), не чаще BABKA_COOLDOWN и не в диалоге.
func babka_react(b: Breakable) -> void:
	var babka: Node3D = _world.get_node_or_null("Babka") if _world else null
	if babka == null or clock < _babka_ready_at:
		return
	var at := b.global_ground()
	if Vector2(babka.global_position.x - at.x, babka.global_position.z - at.z).length() > BABKA_DISTANCE:
		return
	var flow := _world.get_node_or_null("QuestFlow")
	if flow and flow.has_method("is_dialog_open") and flow.is_dialog_open():
		return
	var text := QuestLines.break_line(&"babka", babka_bubbles)
	if _babka_back == null:
		_babka_back = Sprite3D.new()
		_babka_back.name = "BreakBubble"
		_babka_back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_babka_back.no_depth_test = true
		_babka_back.shaded = false
		_babka_back.pixel_size = Resident.BUBBLE_PIXEL * Resident.BUBBLE_DOWNSCALE
		_babka_back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		_babka_back.render_priority = 1
		babka.add_child(_babka_back)
		_babka_label = Label3D.new()
		_babka_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_babka_label.no_depth_test = true
		_babka_label.pixel_size = Resident.BUBBLE_PIXEL
		_babka_label.font = Resident.DialogPanelScript.ui_font()
		_babka_label.font_size = Resident.BUBBLE_FONT
		_babka_label.outline_size = 0
		_babka_label.modulate = Resident.INK
		_babka_label.render_priority = 2
		_babka_label.position = Vector3(0, Resident.BUBBLE_TAIL * 0.5 * Resident.BUBBLE_PIXEL, 0)
		_babka_back.add_child(_babka_label)
	_babka_back.texture = Resident.bubble_texture(text)
	_babka_back.position = Vector3(0, Catalog.RF_ADULT_FEMALE_REFERENCE_M + 0.10 + _babka_back.texture.get_height() * _babka_back.pixel_size * 0.5, 0)
	_babka_label.text = text
	_babka_back.visible = true
	_babka_left = maxf(BABKA_BUBBLE_SECONDS, QuestLines.read_seconds(text))   # TEXT-01: успеть прочитать
	_babka_ready_at = clock + BABKA_COOLDOWN
	babka_bubbles += 1

## Текст пузыря Бабки, пока он на экране ("" — нет).
func babka_bubble_text() -> String:
	return _babka_label.text if _babka_back != null and _babka_back.visible else ""

func _update_babka(delta: float) -> void:
	if _babka_left <= 0.0:
		return
	_babka_left -= delta
	if _babka_left <= 0.0 and _babka_back:
		_babka_back.visible = false

# --- реакции без разрушения: сигнализация машин, крышки контейнеров ---

## Касание «Лады» не разрушаемого: припаркованная машина — сигнализация, дворовый контейнер — хлопок крышек.
func _react(at: Vector3, speed: float) -> void:
	var p := Vector2(at.x, at.z)
	if speed >= ALARM_SPEED:
		var cars := _parked_rects()
		for i in cars.size():
			var owner := _parked_owner(i)
			var rect: Rect2 = owner.rect() if owner else cars[i]
			if rect.grow(0.15).has_point(p):
				_start_alarm(i, cars[i])
				return
	if speed >= LID_SPEED:
		var bins := [Layout.BINS, Layout.H10_BINS]
		for i in bins.size():
			var c: Vector2 = bins[i][0]
			var s: Vector3 = bins[i][1]
			if Rect2(c - Vector2(s.x, s.z) * 0.5, Vector2(s.x, s.z)).grow(0.15).has_point(p) and clock >= float(_lid_ready.get(i, -INF)):
				_lid_ready[i] = clock + LID_COOLDOWN
				lid_slams += 1
				bin_lid.emit(Vector3(c.x, 1.2, c.y))
				return

## Коробки машин без поведения: Layout.PARKED, затем «Жигули» A и B.
static func _parked_rects() -> Array:
	var out := []
	for car in Layout.PARKED:
		var c: Vector2 = car[0]
		var s := Vector2(Layout.LADA_SIZE.z, Layout.LADA_SIZE.x) if car[1] else Vector2(Layout.LADA_SIZE.x, Layout.LADA_SIZE.z)
		out.append(Rect2(c - s * 0.5, s))
	for spec in Layout.SOLIDS:
		if spec[1] == "parked_car":
			var c: Vector2 = spec[2]
			var size: Vector3 = spec[3]
			out.append(Rect2(c - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
	return out

func _parked_owner(i: int) -> Breakable:
	var rects := _parked_rects()
	if i < 0 or i >= rects.size(): return null
	for b: Breakable in env_objects:
		if b.kind == &"parked" and b.center.is_equal_approx((rects[i] as Rect2).get_center()):
			return b
	return null

func _start_alarm(i: int, rect: Rect2) -> void:
	if _alarms.has(i):
		_alarms[i]["left"] = ALARM_SECONDS
		return
	var owner := _parked_owner(i)
	if owner == null or owner.parked_visual == null: return
	_alarms[i] = {"left": ALARM_SECONDS, "visual": owner.parked_visual}
	LadaVisual.set_indicators(owner.parked_visual, true)
	alarms += 1
	car_alarm.emit(owner.body.global_position + Vector3.UP)

func _update_alarms(delta: float) -> void:
	for i in _alarms.keys():
		var a: Dictionary = _alarms[i]
		a["left"] = float(a["left"]) - delta
		if a["left"] <= 0.0:
			_stop_alarm(i)
			continue
		LadaVisual.set_indicators(a["visual"], fmod(ALARM_SECONDS - float(a["left"]), ALARM_BLINK) < ALARM_BLINK * 0.5)

## Сигнализация машины i ещё звучит.
func alarm_on(i: int) -> bool:
	return _alarms.has(i)

func _stop_alarm(i: int) -> void:
	var a: Dictionary = _alarms[i]
	if is_instance_valid(a["visual"]):
		LadaVisual.set_indicators(a["visual"], false)
	_alarms.erase(i)


## Один разрушаемый объект: тело слоя LAYER, hp, состояние intact → broken → growing → intact; облик — слоты MultiMesh
## у Breakables (role body — целый, detail — мелочь целого, remnant — остаток, base — всегда: плиты раскопки).
class Breakable extends Node3D:
	signal broken(b: Breakable, by: StringName)
	signal restored(b: Breakable)

	var id: StringName
	var kind: StringName
	var center := Vector2.ZERO
	var size := Vector3.ONE
	var yaw := 0.0
	var heavy := false
	var hp := 1
	var state: StringName = &"intact"   # intact, broken, growing
	var body: StaticBody3D
	var root: Breakables
	var slots: Array = []
	var mm_dirty := false
	var breaks := 0
	var restores := 0
	var hits := 0
	var last_by: StringName = &""
	var broken_at := -1.0                # clock Breakables
	var restore_left := 0.0
	var spin_angle := 0.0
	var extras: Array[Node3D] = []       # узлы облика вне MultiMesh (надписи раскопки и штендера), прячутся при поломке
	var coins_at := -INF                 # BREAK-02: clock прошлой выдачи монет
	var coins_given := 0
	var _push := 0.0
	var _push_frame := -10
	var _wobble := 0.0
	var _wobble_axis := Vector3.RIGHT
	var _spin_speed := 0.0
	var _grow := 1.0
	var mode: StringName = &""
	var env_index := -1
	var env_nodes: Array = []
	var env_node_xf: Array[Transform3D] = []
	var env_node_visible: Array[bool] = []
	var env_mm: Array = []
	var fall_dir := Vector3.RIGHT
	var env_bounds := AABB()
	var parked_visual: Node3D
	var parked_velocity := Vector3.ZERO
	var parked_yaw_velocity := 0.0
	var parked_offset := Vector3.ZERO
	var parked_angle := 0.0
	var _parked_receiving := false

	func register_vehicle() -> void:
		for node: Node3D in env_nodes:
			parked_visual = node.get_node_or_null("Visual")
			if parked_visual: break
		body.collision_mask = PARKED_MASK
		VehicleImpact.register(body, PARKED_MASS, size, parked_visual, receive_vehicle_impact,
			func(): return parked_velocity, func(): return parked_yaw_velocity)

	func receive_vehicle_impact(delta_velocity: Vector3, delta_yaw: float, contact: Vector3, inward: Vector3, speed: float, damage_speed := -1.0) -> void:
		# A swept pile-up can deliver this callback after advancing the physical body.
		parked_offset = body.global_position - global_ground()
		parked_angle = body.global_rotation.y - yaw
		parked_velocity += Vector3(delta_velocity.x, 0, delta_velocity.z)
		parked_yaw_velocity += delta_yaw
		if parked_visual:
			VehicleDamage.dent(parked_visual, contact, inward, damage_speed if damage_speed >= 0.0 else speed)
		if speed >= ALARM_SPEED: root._react(body.global_position, speed)
		if state == &"intact" and speed >= HEAVY_SPEED:
			_parked_receiving = true
			smash(&"car", inward)
			_parked_receiving = false
		root.animate(self)

	func _step_vehicle(delta: float) -> void:
		if parked_velocity.length_squared() < 0.000001 and absf(parked_yaw_velocity) < 0.001: return
		var expected := parked_velocity * delta
		var serial := int(body.get_meta("vehicle_impact_serial", 0))
		var actual := VehicleImpact.safe_move(body, expected, parked_yaw_velocity * delta, size, PARKED_MASK)
		parked_offset = body.global_position - global_ground()
		parked_angle = body.global_rotation.y - yaw
		# A real obstacle absorbs the component that cannot advance; no hidden drift through walls.
		if serial == int(body.get_meta("vehicle_impact_serial", 0)) and expected.length_squared() > 0.000001 and actual.length() + 0.001 < expected.length():
			parked_velocity = actual / maxf(delta, 0.0001)
		parked_velocity = parked_velocity.move_toward(Vector3.ZERO, PARKED_DRAG * delta)
		parked_yaw_velocity = move_toward(parked_yaw_velocity, 0.0, PARKED_YAW_DRAG * delta)
		root.animate(self)

	func _reset_vehicle() -> void:
		if kind == &"parked": VehicleImpact.reset(body)
		parked_velocity = Vector3.ZERO
		parked_yaw_velocity = 0.0
		parked_offset = Vector3.ZERO
		parked_angle = 0.0
		if parked_visual: VehicleDamage.reset(parked_visual)

	func attach_env(entry: Dictionary) -> void:
		env_bounds = base_xf() * AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		for node: Node3D in entry.get("nodes", []):
			if not is_instance_valid(node): continue
			env_nodes.append(node)
			env_node_xf.append(node.global_transform)
			env_node_visible.append(node.visible)
			var geometry := node.find_children("*", "GeometryInstance3D", true, false)
			if node is GeometryInstance3D: geometry.append(node)
			for part: GeometryInstance3D in geometry:
				if part.is_queued_for_deletion(): continue
				var mesh: Mesh = (part as MeshInstance3D).mesh if part is MeshInstance3D else ((part as MultiMeshInstance3D).multimesh.mesh if part is MultiMeshInstance3D and (part as MultiMeshInstance3D).multimesh else null)
				if mesh == null: continue
				if part is MultiMeshInstance3D:
					var mm: MultiMesh = (part as MultiMeshInstance3D).multimesh
					for i in mm.instance_count:
						env_bounds = env_bounds.merge((part.global_transform * mm.get_instance_transform(i)) * mesh.get_aabb())
				else:
					env_bounds = env_bounds.merge(part.global_transform * mesh.get_aabb())
		for part: Array in entry.get("mm", []):
			var item := part.duplicate()
			item.append((part[3] as Node3D).global_transform * (part[2] as Transform3D))
			env_mm.append(item)
			env_bounds = env_bounds.merge((item[4] as Transform3D) * (part[0] as MultiMesh).mesh.get_aabb())

	func env_hidden() -> bool:
		return state == &"broken" and (mode == &"shatter" or (mode == &"topple" and root.clock - broken_at >= FALL_SECONDS + LIE_SECONDS + SINK_SECONDS))

	## Мировая дельта вокруг основания; исходные узлы и экземпляры остаются в своих родителях.
	func env_delta() -> Transform3D:
		var pivot := global_ground()
		var basis := Basis.IDENTITY
		var shift := Vector3.ZERO
		if state == &"broken" and mode == &"topple":
			var age := maxf(root.clock - broken_at, 0.0)
			var t := clampf(age / FALL_SECONDS, 0.0, 1.0)
			basis = Basis(Vector3.UP.cross(fall_dir).normalized(), FALL_ANGLE * t * t)
			shift.y = -maxf(size.y, ENV_HEIGHT.get(kind, 0.0)) * clampf((age - FALL_SECONDS - LIE_SECONDS) / SINK_SECONDS, 0.0, 1.0)
		elif mode == &"dent":
			basis = Basis(Vector3.UP, parked_angle)
			shift = parked_offset
		elif state == &"growing":
			var g := maxf(1.0 - pow(1.0 - _grow, 3.0), 0.001)
			basis = Basis.from_scale(Vector3(lerpf(0.6, 1.0, g), g, lerpf(0.6, 1.0, g)))
		elif _wobble > 0.0:
			var height := maxf(size.y, ENV_HEIGHT.get(kind, 0.0))
			basis = Basis(_wobble_axis, sin(PI * (1.0 - _wobble / WOBBLE_SECONDS)) * WOBBLE_ANGLE * minf(1.0, 2.5 / height))
		return Transform3D(basis, pivot + shift - basis * pivot)

	func setup(spec: Array) -> void:
		id = spec[0]
		kind = spec[1]
		center = spec[2]
		size = spec[3]
		yaw = spec[4]
		heavy = spec[5] == &"heavy"
		hp = HEAVY_HP if heavy else 1
		add_to_group(GROUP)
		position = Vector3(center.x, 0.0, center.y)
		rotation.y = yaw
		body = StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = LAYER
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = body_size()
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = body_size().y * 0.5
		body.add_child(collider)
		add_child(body)

	func body_size() -> Vector3:
		return size if env_index >= 0 else Vector3(size.x, maxf(size.y, MIN_BODY_HEIGHT), size.z)

	func global_ground() -> Vector3:
		return Vector3(center.x, 0.0, center.y)

	func base_xf() -> Transform3D:
		return Transform3D(Basis(Vector3.UP, yaw), global_ground())

	## Поза целого: покачивание от удара, рост из снега.
	func pose() -> Transform3D:
		var xf := base_xf()
		if _wobble > 0.0:
			var angle := sin(PI * (1.0 - _wobble / WOBBLE_SECONDS)) * WOBBLE_ANGLE
			xf = Transform3D(Basis(_wobble_axis, angle), xf.origin) * Transform3D(xf.basis, Vector3.ZERO)
		if state == &"growing":
			var g := 1.0 - pow(1.0 - _grow, 3.0)
			var s := lerpf(0.6, 1.0, g)
			xf = xf * Transform3D(Basis.from_scale(Vector3(s, maxf(g, 0.001), s)), Vector3.ZERO)
		return xf

	func rect() -> Rect2:
		if mode != &"dent":
			return Breakables.spec_rect([id, kind, center, size, yaw])
		var xf := env_delta() * base_xf()
		var points: Array[Vector2] = []
		for x in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				for y in [0.0, 1.0]:
					var point := xf * (size * Vector3(x, y, z))
					points.append(Vector2(point.x, point.z))
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points: bounds = bounds.expand(point)
		return bounds

	func is_intact() -> bool:
		return state == &"intact"

	## Целый и с коллизией (рост — тоже: коллизия возвращается в начале роста).
	func blocks() -> bool:
		return state != &"broken" or mode == &"dent"

	## Касание «Лады»: &"light"/&"heavy" — сломан этим касанием, &"" — нет.
	func car_contact(speed: float, pushing: bool, delta: float, into: Vector3) -> StringName:
		if state == &"broken":
			return &""
		var frame := Engine.get_physics_frames()
		if pushing:
			_push = (_push + delta) if _push_frame >= frame - 1 else delta
			_push_frame = frame
		if heavy:
			if speed >= HEAVY_SPEED:
				smash(&"car", into)
				return &"dent" if mode == &"dent" else &"heavy"
			return &""
		if speed >= LIGHT_SPEED or (pushing and _push > PUSH_SECONDS):
			smash(&"car", into)
			return &"light"
		return &""

	## Удар Илюши: light — сразу, heavy — hp, покачивание и раскрутка карусели.
	func punch(dir: Vector3) -> bool:
		if state == &"broken":
			return false
		hits += 1
		hp -= 1
		if hp <= 0:
			smash(&"punch", dir)
			return true
		_wobble = WOBBLE_SECONDS
		var flat := Vector3(dir.x, 0.0, dir.z)
		_wobble_axis = Vector3.UP.cross(flat.normalized()) if flat.length() > 0.01 else Vector3.RIGHT
		if kind == &"carousel":
			_spin_speed += 4.0
		root.animate(self)
		root.wobbled.emit(self)
		return false

	## Сломать: коллизия — сразу (в том же физическом кадре), остаток, обломки, сигнал, таймер восстановления.
	func smash(by: StringName, dir: Vector3) -> void:
		if state == &"broken":
			return
		state = &"broken"
		fall_dir = Vector3(dir.x, 0.0, dir.z).normalized()
		if fall_dir.length_squared() < 0.01: fall_dir = Vector3.RIGHT
		body.collision_layer = (LAYER | 1) if mode == &"dent" else 0
		(body.get_child(0) as CollisionShape3D).disabled = mode != &"dent"
		breaks += 1
		root.breaks += 1
		last_by = by
		broken_at = root.clock
		hp = HEAVY_HP if heavy else 1
		_wobble = 0.0
		_spin_speed = 0.0
		restore_left = root.next_restore_delay()
		for node in extras:
			node.visible = false
		if kind == &"parked":
			root._react(body.global_position, ALARM_SPEED)
			# Punch/scripted destruction also creates a physical nudge; real vehicle contacts already own theirs.
			if not _parked_receiving:
				parked_velocity += fall_dir * 0.65
				if parked_visual:
					var contact := body.global_position + Vector3.UP * 0.75 - fall_dir * minf(size.x, size.z) * 0.5
					VehicleDamage.dent(parked_visual, contact, fall_dir, HEAVY_SPEED)
		if kind == &"bins": root._react(global_ground(), LID_SPEED)
		root._env_lamp(self, false)
		root._refresh_cut_wires()
		root.animate(self)
		root._write(self)
		root.spawn_debris(self, dir)
		root.drop_coins(self, by)
		broken.emit(self, by)
		root.babka_react(self)

	func tick(delta: float) -> void:
		if kind == &"parked":
			_step_vehicle(delta)
		if state != &"broken":
			return
		restore_left -= delta
		if restore_left > 0.0:
			return
		if not root.can_restore(self):
			restore_left = RESTORE_RETRY
			return
		state = &"growing"
		_reset_vehicle()
		_grow = 0.0
		body.collision_layer = LAYER | (1 if env_index >= 0 else 0)
		body.transform = Transform3D.IDENTITY
		(body.get_child(0) as CollisionShape3D).disabled = false
		for node in extras:
			node.visible = true
		root.animate(self)
		root._write(self)

	## Шаг анимации; false — анимация кончилась.
	func animate(delta: float) -> bool:
		var age := root.clock - broken_at
		var busy := state == &"broken" and ((mode == &"topple" and age < FALL_SECONDS + LIE_SECONDS + SINK_SECONDS) or (mode == &"dent" and age < DENT_SECONDS))
		if _wobble > 0.0:
			_wobble = maxf(_wobble - delta, 0.0)
			busy = busy or _wobble > 0.0
		if _spin_speed > 0.0:
			spin_angle = fmod(spin_angle + _spin_speed * delta, TAU)
			_spin_speed = maxf(_spin_speed - 1.5 * delta, 0.0)
			busy = busy or _spin_speed > 0.0
		if state == &"growing":
			_grow = minf(_grow + delta / GROW_SECONDS, 1.0)
			if _grow >= 1.0:
				state = &"intact"
				restores += 1
				root.restores += 1
				root._env_lamp(self, true)
				root._refresh_cut_wires()
				restored.emit(self)
			else:
				busy = true
		return busy or parked_velocity.length_squared() > 0.000001 or absf(parked_yaw_velocity) > 0.001

	## Сразу целый (сброс мира).
	func reset() -> void:
		_reset_vehicle()
		state = &"intact"
		hp = HEAVY_HP if heavy else 1
		body.collision_layer = LAYER | (1 if env_index >= 0 else 0)
		body.transform = Transform3D.IDENTITY
		(body.get_child(0) as CollisionShape3D).disabled = false
		_wobble = 0.0
		_spin_speed = 0.0
		spin_angle = 0.0
		_grow = 1.0
		_push = 0.0
		restore_left = 0.0
		breaks = 0
		restores = 0
		hits = 0
		coins_at = -INF
		coins_given = 0
		for node in extras:
			node.visible = true

	## Раскопка: табличка «ВЕДУТСЯ РАБОТЫ» на ограждении (Label3D, прячется с ограждением) и пар из щели между плитами
	## (остаётся и после поломки).
	func add_dig_extras() -> void:
		var label := Label3D.new()
		label.name = "WorksSign"
		label.text = "ВЕДУТСЯ\nРАБОТЫ"
		label.font = Resident.DialogPanelScript.ui_font()
		label.font_size = 64
		label.pixel_size = 0.004
		label.modulate = Color(0.1, 0.08, 0.06)
		label.outline_size = 0
		label.double_sided = false
		label.position = Vector3(0.0, 0.78, -size.z * 0.5 - 0.035)
		label.rotation.y = PI
		label.visibility_range_end = FAR_DETAIL
		add_child(label)
		extras.append(label)
		# Пар — клубы шейдера steam_puff в MultiMesh, как у люков lighting.gd и вытяжки props.gd (круглая мягкая
		# маска; прежние частицы-квадраты читались прозрачными прямоугольниками — сверка CITY-02).
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var look := ShaderMaterial.new()
		look.shader = STEAM_SHADER
		look.set_shader_parameter("color", Color(0.64, 0.67, 0.74, 0.3))
		look.set_shader_parameter("size_start", 0.4)
		look.set_shader_parameter("size_end", 1.8)
		look.set_shader_parameter("rise", 2.0)
		quad.material = look
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = DIG_PUFFS
		for k in DIG_PUFFS:
			var along := (float(k % 3) - 1.0) * 0.6   # щель между плитами — вдоль z
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, along)))
			mm.set_instance_custom_data(k, Color(float(k) / DIG_PUFFS, fposmod(0.37 * k, 1.0), fposmod(0.61 * k + 0.2, 1.0), 0.0))
		var steam := MultiMeshInstance3D.new()
		steam.name = "Steam"
		steam.multimesh = mm
		steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		steam.custom_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 6, 6))
		steam.visibility_range_end = FAR_DETAIL
		add_child(steam)

	## Штендер: надпись на обеих досках «домика» (Label3D, прячется при поломке). Наклон и место — как у досок
	## Looks._sign_board.
	func add_sign_text(text: String) -> void:
		for side in [1.0, -1.0]:
			var label := Label3D.new()
			label.name = "SignText"
			label.text = text
			label.font = Resident.DialogPanelScript.ui_font()
			label.font_size = 48
			label.pixel_size = 0.0021
			label.line_spacing = -6.0
			label.modulate = Color(0.12, 0.10, 0.09)
			label.outline_size = 0
			label.double_sided = false
			label.basis = Basis(Vector3.UP, 0.0 if side > 0.0 else PI) * Basis(Vector3.RIGHT, -Looks.SIGN_TILT)
			label.position = Vector3(0.0, 0.42, side * (Looks.SIGN_SPREAD * 0.55 + 0.02))
			label.visibility_range_end = FAR_DETAIL
			add_child(label)
			extras.append(label)


## Облик по виду — части из примитивов в осях объекта (начало — центр на земле, перед — +Z), снег на горизонталях,
## остаток ниже 0,15 м; и обломки. Часть: [примитив, Transform3D единичной сетки, цвет, материал, роль, вращается].
## Примитивы: box (1 м), cyl (d 1, h 1), frustum (низ d 1, верх 0,72), cone (низ d 1, верх 0,16), sphere (d 1),
## torus (наружный d 1, трубка 0,25), prism (1 м, остриё вверху). Материалы: paint (цвет экземпляра), snow (шейдер снега). Роли: body, detail,
## remnant, base. Цвета — sRGB, приглушённые, как у двора (_playground в level_geometry.gd).
class Looks:
	const STEEL := Color(0.55, 0.57, 0.6)
	const WOOD := Color(0.42, 0.29, 0.17)
	const WOOD_DARK := Color(0.30, 0.21, 0.13)
	const RED := Color(0.66, 0.15, 0.11)
	const YELLOW := Color(0.82, 0.62, 0.14)
	const BLUE := Color(0.20, 0.33, 0.58)
	const GREEN := Color(0.22, 0.38, 0.28)
	const WHITE := Color(0.86, 0.86, 0.83)
	const EARTH := Color(0.20, 0.15, 0.11)
	const STEM := Color(0.36, 0.28, 0.17)
	const COAL := Color(0.07, 0.07, 0.08)
	const ORANGE := Color(0.95, 0.42, 0.08)
	const RUBBER := Color(0.09, 0.09, 0.10)
	const CONCRETE := Color(0.52, 0.52, 0.53)
	const SNOW_C := Color(0.88, 0.91, 0.96)
	const PAPER := Color(0.82, 0.80, 0.72)
	const FENCE := Color(0.24, 0.42, 0.31)       # трубная ограда палисадника
	const FABRIC := Color(0.45, 0.22, 0.18)      # выцветшая обивка дивана
	const SAND := Color(0.56, 0.46, 0.32)
	const RUG := Color(0.48, 0.10, 0.10)         # как ковёр на выбивалке двора (level_geometry._carpet_post)
	const BORDER := Color(0.78, 0.62, 0.30)
	const BAR := Color(0.20, 0.34, 0.30)
	const PLANK := Color(0.70, 0.52, 0.30)       # светлые доски детского домика
	const PICKLE := Color(0.30, 0.42, 0.18)
	const TOMATO := Color(0.62, 0.20, 0.12)
	const SIGN_TILT := 0.218                     # рад: наклон доски штендера от вертикали
	const SIGN_SPREAD := 0.21                    # м: доска внизу отходит от оси на столько

	## Виды со своим обликом (остальные — заглушка-коробка; набор BREAK проверяет, что заглушек нет).
	const KINDS := [&"bin", &"planter", &"snowman", &"seesaw", &"carousel", &"barrier", &"cones", &"fence", &"domino",
		&"laundry", &"fort", &"sofa", &"sand_box", &"carpet", &"sign_board", &"swing", &"slide", &"sandpit", &"playhouse",
		&"bench", &"crate", &"stall"]

	static func has_look(kind: StringName) -> bool:
		return kind in KINDS or kind in ENV_KINDS

	static func _xf(scale: Vector3, at: Vector3, euler := Vector3.ZERO) -> Transform3D:
		return Transform3D(Basis.from_euler(euler) * Basis.from_scale(scale), at)

	## Стержень from → to радиуса r (цилиндр).
	static func _rod(from: Vector3, to: Vector3, r: float) -> Transform3D:
		var axis := to - from
		var length := axis.length()
		var y := axis / length
		var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		return Transform3D(Basis(x, y, z) * Basis.from_scale(Vector3(r * 2.0, length, r * 2.0)), (from + to) * 0.5)

	## У тора в _xf высота задаётся как у остальных (м), а трубка единичного тора — 0,25: множитель 4 по y сетки.
	static func _p(prim: String, xf: Transform3D, color: Color, role := "body", spin := false, mat := "paint") -> Array:
		if prim == "torus":
			xf.basis = xf.basis * Basis.from_scale(Vector3(1.0, 4.0, 1.0))
		return [prim, xf, color, mat, role, spin]

	static func _snow(prim: String, xf: Transform3D, role := "body", spin := false) -> Array:
		return _p(prim, xf, SNOW_C, role, spin, "snow")

	static func _environment_remnant(kind: StringName, size: Vector3) -> Array:
		var out := []
		if kind in [&"birch", &"poplar", &"rowan"]:
			var diameter := maxf(size.x * 1.15, 0.24)
			out.append(_p("cyl", _xf(Vector3(diameter, 0.12, diameter), Vector3(0, 0.06, 0)), WOOD, "remnant"))
		elif kind in [&"lamp", &"pole", &"lamp_yard", &"sign_post", &"carpet_post", &"billboard"]:
			out.append(_p("box", _xf(Vector3(maxf(size.x, 0.3), 0.06, maxf(size.z, 0.3)), Vector3(0, 0.03, 0)), STEEL, "remnant"))
			out.append(_p("cyl", _xf(Vector3(0.14, 0.12, 0.14), Vector3(0, 0.06, 0)), STEEL, "remnant"))
		elif kind == &"parked":
			# The dented body remains visible; only small shards lie underneath.
			for side in [-1.0, 1.0]:
				out.append(_p("box", _xf(Vector3(0.1, 0.025, 0.15), Vector3(side * size.x * 0.3, 0.013, 0)), Color(0.4, 0.52, 0.58), "remnant"))
		else:
			var wood := kind in [&"dovecote", &"bench_big", &"rink_board", &"ice_slide"]
			var color := WOOD if wood else STEEL
			for side in [-1.0, 1.0]:
				out.append(_p("box", _xf(Vector3(size.x, 0.06, 0.08), Vector3(0, 0.03, side * size.z * 0.4)), color, "remnant"))
				out.append(_p("box", _xf(Vector3(0.08, 0.06, size.z), Vector3(side * size.x * 0.4, 0.03, 0)), color, "remnant"))
		return out

	static func parts(kind: StringName, size: Vector3) -> Array:
		if ENV_KINDS.has(kind): return _environment_remnant(kind, size)
		match kind:
			&"bin": return _bin()
			&"planter": return _planter()
			&"snowman": return _snowman()
			&"seesaw": return _seesaw(size)
			&"carousel": return _carousel(size)
			&"barrier": return _barrier(size)
			&"cones": return _cone()
			&"fence": return _fence(size)
			&"domino": return _domino(size)
			&"laundry": return _laundry(size)
			&"fort": return _fort(size)
			&"sofa": return _sofa(size)
			&"sand_box": return _sand_box(size)
			&"carpet": return _carpet(size)
			&"sign_board": return _sign_board(size)
			&"swing": return _swing(size)
			&"slide": return _slide(size)
			&"sandpit": return _sandpit(size)
			&"playhouse": return _playhouse(size)
			&"bench": return _bench(size)
			&"crate": return _crate(size)
			&"stall": return _stall(size)
		return [_p("box", _xf(size, Vector3(0, size.y * 0.5, 0)), WOOD), _p("box", _xf(Vector3(size.x, 0.05, size.z), Vector3(0, 0.03, 0)), EARTH, "remnant")]

	## Урна-вазон у лавки: зелёный крашеный бак на ножке, обод, шапка снега, бумажка торчит.
	static func _bin() -> Array:
		var out := []
		out.append(_p("cyl", _xf(Vector3(0.3, 0.12, 0.3), Vector3(0, 0.06, 0)), CONCRETE))
		out.append(_p("frustum", _xf(Vector3(0.46, 0.6, 0.46), Vector3(0, 0.42, 0), Vector3(PI, 0, 0)), GREEN))
		out.append(_p("torus", _xf(Vector3(0.48, 0.12, 0.48), Vector3(0, 0.72, 0)), GREEN.darkened(0.25)))
		out.append(_p("cyl", _xf(Vector3(0.38, 0.02, 0.38), Vector3(0, 0.7, 0)), COAL))
		out.append(_snow("sphere", _xf(Vector3(0.36, 0.1, 0.36), Vector3(0.02, 0.74, 0))))
		out.append(_p("box", _xf(Vector3(0.12, 0.16, 0.02), Vector3(0.08, 0.8, -0.05), Vector3(0.2, 0.5, 0.3)), PAPER, "detail"))
		out.append(_p("box", _xf(Vector3(0.05, 0.1, 0.05), Vector3(-0.1, 0.76, 0.06), Vector3(0.3, 0, -0.2)), Color(0.55, 0.35, 0.15), "detail"))
		# остаток: ножка и рассыпанный мусор
		out.append(_p("cyl", _xf(Vector3(0.3, 0.12, 0.3), Vector3(0, 0.06, 0)), CONCRETE, "remnant"))
		out.append(_p("box", _xf(Vector3(0.14, 0.01, 0.1), Vector3(0.25, 0.01, 0.1), Vector3(0, 0.6, 0)), PAPER, "remnant"))
		out.append(_p("box", _xf(Vector3(0.1, 0.01, 0.08), Vector3(-0.2, 0.01, -0.22), Vector3(0, -0.4, 0)), PAPER, "remnant"))
		return out

	## Клумба из покрышки: покрышка в белой краске с синей полосой, земля, шапка снега, сухие стебли из-под снега.
	static func _planter() -> Array:
		var out := []
		out.append(_p("torus", _xf(Vector3(1.0, 0.34, 1.0), Vector3(0, 0.17, 0)), WHITE))
		out.append(_p("torus", _xf(Vector3(1.02, 0.07, 1.02), Vector3(0, 0.2, 0)), BLUE))
		out.append(_p("cyl", _xf(Vector3(0.62, 0.26, 0.62), Vector3(0, 0.13, 0)), EARTH))
		out.append(_snow("sphere", _xf(Vector3(0.66, 0.16, 0.66), Vector3(0, 0.27, 0))))
		out.append(_snow("torus", _xf(Vector3(0.96, 0.08, 0.96), Vector3(0, 0.33, 0))))
		for k in 7:
			var a := TAU * k / 7.0 + 0.4
			var r := 0.08 + 0.17 * float(k % 3) / 2.0
			var base := Vector3(cos(a) * r, 0.28, sin(a) * r)
			var top := base + Vector3(cos(a) * 0.08, 0.26 + 0.06 * float(k % 2), sin(a) * 0.08)
			out.append(_p("cyl", _rod(base, top, 0.008), STEM, "detail"))
			if k % 2 == 0:
				out.append(_p("sphere", _xf(Vector3(0.05, 0.04, 0.05), top), Color(0.30, 0.20, 0.12), "detail"))   # сухая головка
		# остаток: земля, обрывки стеблей, разбитый снег
		out.append(_p("cyl", _xf(Vector3(0.8, 0.06, 0.8), Vector3(0, 0.03, 0)), EARTH, "remnant"))
		for k in 3:
			var a := TAU * k / 3.0
			var base := Vector3(cos(a) * 0.15, 0.05, sin(a) * 0.15)
			out.append(_p("cyl", _rod(base, base + Vector3(0.03, 0.08, 0.02), 0.01), STEM, "remnant"))
		out.append(_snow("sphere", _xf(Vector3(0.5, 0.06, 0.4), Vector3(0.25, 0.03, 0.1)), "remnant"))
		return out

	## Снеговик: три кома, ведро набекрень, морковка, угольки, метла у бока; перед — +Z.
	static func _snowman() -> Array:
		var out := []
		out.append(_snow("sphere", _xf(Vector3(0.86, 0.78, 0.86), Vector3(0, 0.38, 0))))
		out.append(_snow("sphere", _xf(Vector3(0.6, 0.56, 0.6), Vector3(0.02, 0.98, 0))))
		out.append(_snow("sphere", _xf(Vector3(0.42, 0.42, 0.42), Vector3(0, 1.4, 0.01))))
		out.append(_p("frustum", _xf(Vector3(0.3, 0.24, 0.3), Vector3(-0.03, 1.66, -0.02), Vector3(-0.15, 0, 0.22)), RED))
		out.append(_p("cone", _xf(Vector3(0.07, 0.24, 0.07), Vector3(0, 1.4, 0.3), Vector3(PI * 0.5, 0, 0)), ORANGE))
		for sx in [-0.08, 0.08]:
			out.append(_p("sphere", _xf(Vector3(0.05, 0.05, 0.05), Vector3(sx, 1.47, 0.18)), COAL, "detail"))
		for k in 3:
			out.append(_p("sphere", _xf(Vector3(0.06, 0.06, 0.06), Vector3(0.02, 0.86 + 0.13 * k, 0.29 - 0.02 * absf(k - 1.0))), COAL, "detail"))
		# метла: черенок у правого бока, веник наверху
		var from := Vector3(0.42, 0.0, 0.08)
		var to := Vector3(0.36, 1.45, 0.02)
		out.append(_p("cyl", _rod(from, to, 0.018), WOOD))
		out.append(_p("cone", _xf(Vector3(0.16, 0.32, 0.12), to + Vector3(-0.01, 0.12, 0.0), Vector3(PI, 0, -0.04)), Color(0.55, 0.42, 0.22), "detail"))
		# остаток: раскатанный снег и угольки
		out.append(_snow("sphere", _xf(Vector3(1.0, 0.12, 0.9), Vector3(0, 0.05, 0)), "remnant"))
		out.append(_p("sphere", _xf(Vector3(0.05, 0.04, 0.05), Vector3(0.2, 0.1, 0.15)), COAL, "remnant"))
		out.append(_p("sphere", _xf(Vector3(0.05, 0.04, 0.05), Vector3(-0.15, 0.1, -0.1)), COAL, "remnant"))
		return out

	## Качели-балансир: стойка с осью, доска наискось, ручки-скобы, покрышки под концами, снег на доске.
	static func _seesaw(size: Vector3) -> Array:
		var out := []
		var half := size.x * 0.5
		var tilt := 0.12
		var pivot := Vector3(0, 0.55, 0)
		var board := Transform3D(Basis(Vector3.BACK, tilt), pivot)
		for sz in [-0.12, 0.12]:
			out.append(_p("cyl", _rod(Vector3(-0.18, 0, sz), pivot + Vector3(0, 0, sz), 0.035), BLUE))
			out.append(_p("cyl", _rod(Vector3(0.18, 0, sz), pivot + Vector3(0, 0, sz), 0.035), BLUE))
		out.append(_p("cyl", _rod(pivot + Vector3(0, 0, -0.16), pivot + Vector3(0, 0, 0.16), 0.04), STEEL))
		out.append(_p("box", board * _xf(Vector3(size.x, 0.06, 0.28), Vector3(0, 0.05, 0)), WOOD))
		out.append(_snow("box", board * _xf(Vector3(size.x - 0.5, 0.035, 0.24), Vector3(0, 0.095, 0))))
		for sx in [-1.0, 1.0]:
			var h: float = sx * (half - 0.45)
			for sz in [-0.1, 0.1]:
				out.append(_p("cyl", board * _rod(Vector3(h, 0.08, sz), Vector3(h, 0.34, sz), 0.018), RED))
			out.append(_p("cyl", board * _rod(Vector3(h, 0.34, -0.11), Vector3(h, 0.34, 0.11), 0.018), RED))
			out.append(_p("box", board * _xf(Vector3(0.36, 0.05, 0.3), Vector3(sx * (half - 0.2), 0.1, 0)), RED.darkened(0.2), "detail"))
			out.append(_p("torus", _xf(Vector3(0.55, 0.2, 0.55), Vector3(sx * (half - 0.25), 0.06, 0)), RUBBER, "detail"))
		# остаток: пенёк стойки и обломок доски
		out.append(_p("cyl", _xf(Vector3(0.16, 0.13, 0.16), Vector3(0, 0.065, 0)), BLUE, "remnant"))
		out.append(_p("box", _xf(Vector3(0.7, 0.04, 0.26), Vector3(0.7, 0.02, 0.05), Vector3(0, 0.3, 0)), WOOD, "remnant"))
		return out

	## Карусель-вертушка: ось, круг с цветными секторами, поручень на стойках, снег на круге. Круг и поручни вращаются.
	static func _carousel(size: Vector3) -> Array:
		var out := []
		var r := size.x * 0.5 - 0.1
		out.append(_p("cyl", _xf(Vector3(0.5, 0.08, 0.5), Vector3(0, 0.04, 0)), CONCRETE))
		out.append(_p("cyl", _xf(Vector3(0.14, 0.9, 0.14), Vector3(0, 0.45, 0)), STEEL))
		out.append(_p("cyl", _xf(Vector3(r * 2.0, 0.07, r * 2.0), Vector3(0, 0.34, 0)), RED, "body", true))
		var colors := [YELLOW, BLUE, YELLOW, BLUE]
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			out.append(_p("box", _xf(Vector3(r * 1.9, 0.075, 0.08), Vector3(0, 0.345, 0), Vector3(0, a, 0)), colors[k], "detail", true))
		out.append(_snow("cyl", _xf(Vector3(r * 1.75, 0.04, r * 1.75), Vector3(0, 0.39, 0)), "body", true))
		var rail := 0.62
		for k in 4:
			var a := TAU * k / 4.0
			var foot := Vector3(cos(a) * rail, 0.38, sin(a) * rail)
			out.append(_p("cyl", _rod(foot, Vector3(cos(a) * rail, 0.92, sin(a) * rail), 0.022), YELLOW, "body", true))
			out.append(_p("cyl", _rod(Vector3(0, 0.92, 0), Vector3(cos(a) * rail, 0.92, sin(a) * rail), 0.02), BLUE, "detail", true))
		out.append(_p("torus", _xf(Vector3(rail * 2.0 + 0.05, 0.05, rail * 2.0 + 0.05), Vector3(0, 0.92, 0)), YELLOW, "body", true))
		out.append(_p("sphere", _xf(Vector3(0.12, 0.08, 0.12), Vector3(0, 0.95, 0)), STEEL, "detail"))
		# остаток: пенёк оси на бетонном круге
		out.append(_p("cyl", _xf(Vector3(0.5, 0.08, 0.5), Vector3(0, 0.04, 0)), CONCRETE, "remnant"))
		out.append(_p("cyl", _xf(Vector3(0.14, 0.13, 0.14), Vector3(0, 0.065, 0)), STEEL, "remnant"))
		out.append(_p("box", _xf(Vector3(0.6, 0.03, 0.2), Vector3(0.6, 0.02, -0.3), Vector3(0, 0.7, 0)), RED, "remnant"))
		return out

	## Раскопка теплотрассы: ограждение из щитов в красно-белую полоску на стойках вокруг ямы; яма, две бетонные плиты
	## (одна сдвинута, из щели пар — base, остаются всегда); снег по верху щитов.
	static func _barrier(size: Vector3) -> Array:
		var out := []
		var hx := size.x * 0.5 - 0.05
		var hz := size.z * 0.5 - 0.05
		# Яма и плиты (base)
		out.append(_p("box", _xf(Vector3(size.x - 1.0, 0.03, size.z - 1.0), Vector3(0, 0.015, 0)), EARTH, "base"))
		out.append(_p("box", _xf(Vector3(1.9, 0.12, 2.3), Vector3(-1.05, 0.06, 0)), CONCRETE, "base"))
		out.append(_p("box", _xf(Vector3(1.9, 0.12, 2.3), Vector3(1.1, 0.07, 0.15), Vector3(0, 0.06, 0)), CONCRETE.darkened(0.08), "base"))
		out.append(_snow("box", _xf(Vector3(1.7, 0.03, 2.0), Vector3(-1.05, 0.125, 0)), "base"))
		# Стенки ограждения: [от, до]
		var sides := [[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz)], [Vector3(-hx, 0, hz), Vector3(hx, 0, hz)],
			[Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz)], [Vector3(hx, 0, -hz), Vector3(hx, 0, hz)]]
		for side: Array in sides:
			var a: Vector3 = side[0]
			var b: Vector3 = side[1]
			var length := a.distance_to(b)
			var along := (b - a) / length
			var yaw := atan2(-along.z, along.x)
			var posts := 3
			for k in posts:
				var p := a.lerp(b, float(k) / float(posts - 1))
				out.append(_p("cyl", _rod(p, p + Vector3(0, 1.05, 0), 0.03), STEEL))
				out.append(_p("cyl", _xf(Vector3(0.09, 0.12, 0.09), p + Vector3(0, 0.06, 0)), CONCRETE, "remnant"))
			var stripes := int(round(length / 0.5))
			for k in stripes:
				var mid := a + along * ((k + 0.5) * length / stripes)
				var color := RED if k % 2 == 0 else WHITE
				for y in [0.55, 0.92]:
					out.append(_p("box", _xf(Vector3(length / stripes, 0.16, 0.025), mid + Vector3(0, y, 0), Vector3(0, yaw, 0)), color))
			out.append(_snow("box", _xf(Vector3(length - 0.1, 0.035, 0.06), (a + b) * 0.5 + Vector3(0, 1.015, 0), Vector3(0, yaw, 0))))
		# Табличка под надпись (надпись — Label3D Breakable), на стенке к выезду (−z)
		out.append(_p("box", _xf(Vector3(1.3, 0.52, 0.03), Vector3(0, 0.78, -hz - 0.02)), YELLOW))
		out.append(_p("box", _xf(Vector3(1.36, 0.04, 0.035), Vector3(0, 1.06, -hz - 0.02)), RED, "detail"))
		# остаток: поваленные щиты
		out.append(_p("box", _xf(Vector3(1.6, 0.03, 0.16), Vector3(-1.5, 0.02, -hz - 0.4), Vector3(0, 0.2, 0)), RED, "remnant"))
		out.append(_p("box", _xf(Vector3(1.2, 0.03, 0.16), Vector3(1.8, 0.02, hz + 0.3), Vector3(0, -0.3, 0)), WHITE, "remnant"))
		return out

	## Дорожный конус: чёрное основание, оранжевый конус, две белые полосы, щепоть снега на макушке.
	static func _cone() -> Array:
		var out := []
		out.append(_p("box", _xf(Vector3(0.38, 0.04, 0.38), Vector3(0, 0.02, 0)), RUBBER))
		out.append(_p("cone", _xf(Vector3(0.3, 0.62, 0.3), Vector3(0, 0.35, 0)), ORANGE))
		out.append(_p("cyl", _xf(Vector3(0.23, 0.07, 0.23), Vector3(0, 0.36, 0)), WHITE))
		out.append(_p("cyl", _xf(Vector3(0.17, 0.05, 0.17), Vector3(0, 0.5, 0)), WHITE, "detail"))
		out.append(_snow("sphere", _xf(Vector3(0.09, 0.04, 0.09), Vector3(0, 0.66, 0))))
		out.append(_snow("box", _xf(Vector3(0.36, 0.02, 0.1), Vector3(0, 0.05, 0.13)), "detail"))
		out.append(_p("box", _xf(Vector3(0.38, 0.04, 0.38), Vector3(0, 0.02, 0)), RUBBER, "remnant"))
		return out

	# --- BREAK-02: облики видов PROPS-01 ---

	## Секция трубной ограды палисадника: стойки, две перекладины, прутья (детали), снег по верху и сугроб у низа
	## (base — остаётся); длинная ось — по большему из size.x / size.z.
	static func _fence(size: Vector3) -> Array:
		var length := maxf(size.x, size.z)
		var h := size.y
		var half := length * 0.5 - 0.04
		var out := []
		for sx in [-1.0, 1.0]:
			out.append(_p("cyl", _rod(Vector3(sx * half, 0, 0), Vector3(sx * half, h + 0.04, 0), 0.03), FENCE))
			out.append(_snow("sphere", _xf(Vector3(0.09, 0.05, 0.09), Vector3(sx * half, h + 0.06, 0))))
			out.append(_p("cyl", _xf(Vector3(0.09, 0.1, 0.09), Vector3(sx * half, 0.05, 0)), FENCE.darkened(0.3), "remnant"))
		for y in [0.14, h - 0.06]:
			out.append(_p("cyl", _rod(Vector3(-half, y, 0), Vector3(half, y, 0), 0.016), FENCE))
		var pickets := maxi(int(length / 0.2), 2)
		for k in range(1, pickets):
			var x := -half + 2.0 * half * float(k) / float(pickets)
			out.append(_p("cyl", _rod(Vector3(x, 0.14, 0), Vector3(x, h - 0.06, 0), 0.008), FENCE, "detail"))
		out.append(_snow("box", _xf(Vector3(length - 0.12, 0.025, 0.05), Vector3(0, h - 0.035, 0))))
		out.append(_snow("box", _xf(Vector3(length - 0.15, 0.09, 0.24), Vector3(0, 0.02, 0.03)), "base"))
		out.append(_p("box", _xf(Vector3(length * 0.45, 0.03, 0.04), Vector3(0.2, 0.02, 0.18), Vector3(0, 0.25, 0)), FENCE, "remnant"))
		out.append(_p("box", _xf(Vector3(length * 0.3, 0.03, 0.04), Vector3(-0.5, 0.02, -0.16), Vector3(0, -0.4, 0)), FENCE, "remnant"))
		if size.z > size.x:
			var turn := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
			for part: Array in out:
				part[1] = turn * (part[1] as Transform3D)
		return out

	## Столик доминошников с двумя лавками вдоль x: стальные ножки, доска стола, костяшки на снегу.
	static func _domino(size: Vector3) -> Array:
		var out := []
		for sx in [-0.38, 0.38]:
			out.append(_p("cyl", _rod(Vector3(sx, 0, 0), Vector3(sx, 0.72, 0), 0.035), STEEL))
			out.append(_p("cyl", _xf(Vector3(0.09, 0.12, 0.09), Vector3(sx, 0.06, 0)), STEEL, "remnant"))
		out.append(_p("cyl", _rod(Vector3(-0.38, 0.3, 0), Vector3(0.38, 0.3, 0), 0.02), STEEL, "detail"))
		out.append(_p("box", _xf(Vector3(1.1, 0.05, 0.78), Vector3(0, 0.745, 0)), WOOD))
		out.append(_p("box", _xf(Vector3(1.12, 0.06, 0.04), Vector3(0, 0.735, 0.39)), WOOD_DARK, "detail"))
		out.append(_snow("box", _xf(Vector3(0.98, 0.035, 0.66), Vector3(0, 0.785, 0))))
		for k in 6:
			var at := Vector3(-0.3 + 0.12 * k, 0.81, -0.08 + 0.05 * float(k % 3))
			out.append(_p("box", _xf(Vector3(0.05, 0.016, 0.1), at, Vector3(0, 0.3 * float(k % 2), 0)), WHITE, "detail"))
		var bench_z := size.z * 0.5 - 0.25
		for sz in [-1.0, 1.0]:
			var z: float = sz * bench_z
			for sx in [-0.55, 0.55]:
				out.append(_p("box", _xf(Vector3(0.08, 0.4, 0.26), Vector3(sx, 0.2, z)), STEEL.darkened(0.25)))
				out.append(_p("box", _xf(Vector3(0.08, 0.1, 0.26), Vector3(sx, 0.05, z)), STEEL.darkened(0.25), "remnant"))
			out.append(_p("box", _xf(Vector3(1.4, 0.05, 0.3), Vector3(0, 0.425, z)), WOOD))
			out.append(_snow("box", _xf(Vector3(1.3, 0.035, 0.24), Vector3(0, 0.465, z))))
		out.append(_p("box", _xf(Vector3(0.9, 0.03, 0.14), Vector3(0.3, 0.015, 0.2), Vector3(0, 0.4, 0)), WOOD, "remnant"))
		out.append(_p("box", _xf(Vector3(0.6, 0.03, 0.14), Vector3(-0.4, 0.015, -0.5), Vector3(0, -0.3, 0)), WOOD, "remnant"))
		return out

	## Бельевые верёвки на двух Т-стойках (вдоль z), бельё колом на морозе, снег на перекладинах.
	static func _laundry(size: Vector3) -> Array:
		var out := []
		var half := size.z * 0.5 - 0.1
		var top := size.y - 0.1
		var arm := size.x * 0.5 - 0.05
		for sz in [-1.0, 1.0]:
			var z: float = sz * half
			out.append(_p("cyl", _rod(Vector3(0, 0, z), Vector3(0, top + 0.05, z), 0.035), BLUE))
			out.append(_p("cyl", _rod(Vector3(-arm, top, z), Vector3(arm, top, z), 0.025), BLUE))
			out.append(_snow("box", _xf(Vector3(arm * 2.0, 0.03, 0.05), Vector3(0, top + 0.035, z))))
			out.append(_p("cyl", _xf(Vector3(0.1, 0.1, 0.1), Vector3(0, 0.05, z)), BLUE.darkened(0.3), "remnant"))
		var lines := [-arm + 0.1, 0.0, arm - 0.1]
		for x: float in lines:
			out.append(_p("cyl", _rod(Vector3(x, top - 0.01, -half), Vector3(x, top - 0.01, half), 0.006), PAPER, "detail"))
		# [линия, доля полудлины, ширина, высота, цвет]
		var cloth := [[0, -0.55, 0.9, 0.8, WHITE], [0, 0.2, 0.5, 0.55, Color(0.55, 0.70, 0.88)], [1, -0.2, 1.1, 0.9, Color(0.95, 0.88, 0.80)],
			[1, 0.6, 0.4, 0.7, Color(0.85, 0.40, 0.45)], [2, -0.7, 0.45, 0.6, Color(0.30, 0.32, 0.45)], [2, 0.0, 0.7, 0.5, WHITE],
			[2, 0.65, 0.35, 0.4, RED]]
		for c: Array in cloth:
			var x: float = lines[c[0]]
			var z: float = float(c[1]) * half
			var h: float = c[3]
			out.append(_p("box", _xf(Vector3(0.02, h, c[2]), Vector3(x, top - 0.01 - h * 0.5, z), Vector3(0, 0, 0.04 * float(int(c[0]) - 1))), c[4]))
			out.append(_snow("box", _xf(Vector3(0.04, 0.025, c[2]), Vector3(x, top + 0.005, z))))
		out.append(_p("box", _xf(Vector3(0.8, 0.02, 0.9), Vector3(0.3, 0.01, -0.4), Vector3(0, 0.3, 0)), Color(0.95, 0.88, 0.80), "remnant"))
		out.append(_p("box", _xf(Vector3(0.45, 0.02, 0.5), Vector3(-0.4, 0.012, 0.8), Vector3(0, -0.5, 0)), Color(0.55, 0.70, 0.88), "remnant"))
		return out

	## Снежная крепость: два ряда блоков вперевязку по периметру, проём спереди (+z), зубцы, флажок и запас снежков.
	static func _fort(size: Vector3) -> Array:
		var out := []
		var hx := size.x * 0.5 - 0.2
		var hz := size.z * 0.5 - 0.2
		var sides := [[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz)], [Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz)],
			[Vector3(hx, 0, -hz), Vector3(hx, 0, hz)], [Vector3(-hx, 0, hz), Vector3(-0.45, 0, hz)], [Vector3(0.45, 0, hz), Vector3(hx, 0, hz)]]
		var n := 0
		for side: Array in sides:
			var a: Vector3 = side[0]
			var b: Vector3 = side[1]
			var length := a.distance_to(b)
			var along := (b - a) / length
			var yaw := atan2(-along.z, along.x)
			var count := maxi(int(round(length / 0.5)), 1)
			for row in 2:
				for k in count:
					var t := (float(k) + 0.5 + 0.25 * float(row % 2) - 0.125) / float(count)
					var p := a.lerp(b, clampf(t, 0.0, 1.0))
					n += 1
					out.append(_snow("box", _xf(Vector3(length / count - 0.03, 0.37, 0.4), p + Vector3(0, 0.19 + 0.38 * row, 0), Vector3(0, yaw + 0.05 * float(n % 3 - 1), 0))))
			var crenels := maxi(int(round(length / 1.0)), 1)
			for k in crenels:
				var p := a.lerp(b, (float(k) + 0.5) / float(crenels))
				out.append(_snow("box", _xf(Vector3(0.32, 0.22, 0.36), p + Vector3(0, 0.87, 0), Vector3(0, yaw, 0))))
		out.append(_p("cyl", _rod(Vector3(-hx, 0.76, -hz), Vector3(-hx, 1.55, -hz), 0.012), WOOD, "detail"))
		out.append(_p("box", _xf(Vector3(0.3, 0.18, 0.01), Vector3(-hx + 0.16, 1.45, -hz)), RED, "detail"))
		for k in 4:
			out.append(_snow("sphere", _xf(Vector3(0.17, 0.17, 0.17), Vector3(0.3 + 0.15 * float(k % 2), 0.09 + 0.13 * float(k / 3), -hz + 0.45 + 0.12 * float(k % 3))), "detail"))
		out.append(_snow("torus", _xf(Vector3(size.x - 0.3, 0.12, size.z - 0.3), Vector3(0, 0.06, 0)), "remnant"))
		out.append(_snow("box", _xf(Vector3(0.5, 0.12, 0.4), Vector3(0.9, 0.06, 1.2), Vector3(0, 0.6, 0.0)), "remnant"))
		out.append(_snow("box", _xf(Vector3(0.45, 0.11, 0.38), Vector3(-1.0, 0.055, 0.7), Vector3(0, -0.3, 0.0)), "remnant"))
		return out

	## Старый диван у помойки: выцветшая обивка, подушки, подлокотники, снег на сиденье и спинке, пружина из дыры.
	static func _sofa(size: Vector3) -> Array:
		var out := []
		var w := size.x
		var d := size.z
		out.append(_p("box", _xf(Vector3(w - 0.3, 0.3, d - 0.05), Vector3(0, 0.21, 0)), FABRIC.darkened(0.15)))
		for sx in [-1.0, 1.0]:
			out.append(_p("box", _xf(Vector3((w - 0.3) * 0.5 - 0.02, 0.14, d - 0.3), Vector3(sx * ((w - 0.3) * 0.25), 0.43, 0.1)), FABRIC))
			out.append(_p("box", _xf(Vector3(0.15, 0.56, d - 0.05), Vector3(sx * (w * 0.5 - 0.075), 0.34, 0)), FABRIC.darkened(0.08)))
			out.append(_snow("box", _xf(Vector3(0.13, 0.04, d - 0.15), Vector3(sx * (w * 0.5 - 0.075), 0.64, 0))))
			for sz in [-1.0, 1.0]:
				out.append(_p("box", _xf(Vector3(0.06, 0.06, 0.06), Vector3(sx * (w * 0.5 - 0.1), 0.03, sz * (d * 0.5 - 0.08))), WOOD_DARK, "detail"))
		out.append(_p("box", _xf(Vector3(w - 0.3, 0.45, 0.2), Vector3(0, 0.6, -(d * 0.5 - 0.1))), FABRIC))
		out.append(_snow("box", _xf(Vector3(w - 0.45, 0.06, d - 0.4), Vector3(0, 0.53, 0.12))))
		out.append(_snow("box", _xf(Vector3(w - 0.35, 0.05, 0.18), Vector3(0, 0.845, -(d * 0.5 - 0.1)))))
		out.append(_p("box", _xf(Vector3(0.25, 0.1, 0.012), Vector3(0.45, 0.25, d * 0.5 - 0.02)), FABRIC.darkened(0.45), "detail"))   # дыра
		out.append(_p("torus", _xf(Vector3(0.1, 0.04, 0.1), Vector3(0.45, 0.27, d * 0.5 + 0.01), Vector3(PI * 0.5, 0, 0)), STEEL, "detail"))
		out.append(_p("box", _xf(Vector3(0.85, 0.1, 0.55), Vector3(0.2, 0.05, 0.1), Vector3(0, 0.35, 0)), FABRIC, "remnant"))
		out.append(_p("box", _xf(Vector3(w * 0.6, 0.04, 0.1), Vector3(-0.3, 0.02, -0.3), Vector3(0, -0.2, 0)), WOOD, "remnant"))
		out.append(_p("torus", _xf(Vector3(0.14, 0.04, 0.14), Vector3(-0.5, 0.03, 0.3)), STEEL, "remnant"))
		return out

	## Деревянный ящик с песком для посыпки: доски с щелями, крышка, жёлтая табличка, снег на крышке.
	static func _sand_box(size: Vector3) -> Array:
		var out := []
		var w := size.x
		var d := size.z
		var h := size.y - 0.18
		out.append(_p("box", _xf(Vector3(w, h, d), Vector3(0, h * 0.5, 0)), WOOD))
		for k in 3:
			out.append(_p("box", _xf(Vector3(w + 0.006, 0.015, d + 0.006), Vector3(0, h * (k + 1) / 4.0, 0)), WOOD_DARK, "detail"))
		out.append(_p("box", _xf(Vector3(w + 0.06, 0.05, d + 0.06), Vector3(0, h + 0.03, 0), Vector3(-0.05, 0, 0)), WOOD_DARK))
		out.append(_p("box", _xf(Vector3(0.5, 0.13, 0.012), Vector3(0, h * 0.6, d * 0.5 + 0.006)), YELLOW, "detail"))
		out.append(_p("box", _xf(Vector3(0.24, 0.035, 0.04), Vector3(0, h + 0.02, d * 0.5 + 0.04)), STEEL, "detail"))
		out.append(_snow("box", _xf(Vector3(w - 0.06, 0.06, d - 0.06), Vector3(0, h + 0.08, 0), Vector3(-0.05, 0, 0))))
		out.append(_snow("sphere", _xf(Vector3(w * 0.7, 0.1, d * 0.6), Vector3(0.05, h + 0.11, 0))))
		out.append(_p("box", _xf(Vector3(w * 0.95, 0.04, d * 0.9), Vector3(0.05, 0.02, 0.05), Vector3(0, 0.15, 0)), SAND, "remnant"))
		out.append(_p("box", _xf(Vector3(w * 0.8, 0.03, 0.14), Vector3(0.1, 0.05, d * 0.6), Vector3(0, -0.3, 0)), WOOD, "remnant"))
		out.append(_p("box", _xf(Vector3(0.6, 0.03, 0.14), Vector3(-0.3, 0.05, -d * 0.55), Vector3(0, 0.5, 0)), WOOD, "remnant"))
		return out

	## Ковры на снегу (чистят снегом — base, остаются) и выбивалка-турник у заднего края (−z) с перекинутым ковром.
	static func _carpet(size: Vector3) -> Array:
		var out := []
		var z0 := 0.55
		out.append(_p("box", _xf(Vector3(1.4, 0.02, 2.0), Vector3(0, 0.01, z0)), RUG, "base"))
		out.append(_p("box", _xf(Vector3(0.5, 0.024, 0.8), Vector3(0, 0.012, z0)), Color(0.16, 0.20, 0.38), "base"))
		for sx in [-1.0, 1.0]:
			out.append(_p("box", _xf(Vector3(0.07, 0.023, 2.0), Vector3(sx * 0.6, 0.012, z0)), BORDER, "base"))
			out.append(_p("box", _xf(Vector3(1.4, 0.023, 0.07), Vector3(0, 0.012, z0 + sx * 0.9)), BORDER, "base"))
		for k in 3:
			out.append(_snow("box", _xf(Vector3(0.35, 0.03, 0.28), Vector3(-0.35 + 0.35 * k, 0.02, z0 - 0.5 + 0.45 * k), Vector3(0, 0.5 * k, 0)), "base"))
		var zb := -size.z * 0.5 + 0.5
		var hx := size.x * 0.5 - 0.06
		var bar := size.y - 0.12
		for sx in [-1.0, 1.0]:
			out.append(_p("cyl", _rod(Vector3(sx * hx, 0, zb), Vector3(sx * hx, size.y, zb), 0.04), BAR))
			out.append(_p("cyl", _xf(Vector3(0.1, 0.1, 0.1), Vector3(sx * hx, 0.05, zb)), BAR.darkened(0.3), "remnant"))
		out.append(_p("cyl", _rod(Vector3(-hx, bar, zb), Vector3(hx, bar, zb), 0.03), BAR))
		out.append(_snow("box", _xf(Vector3(hx * 2.0, 0.04, 0.08), Vector3(0, bar + 0.05, zb))))
		for side in [-1.0, 1.0]:
			var panel := Transform3D(Basis(Vector3.RIGHT, side * 0.12), Vector3(0, bar, zb))
			out.append(_p("box", panel * _xf(Vector3(1.25, 1.1, 0.03), Vector3(0, -0.57, side * 0.06)), RUG.darkened(0.1)))
			out.append(_p("box", panel * _xf(Vector3(1.25, 0.08, 0.035), Vector3(0, -1.06, side * 0.06)), BORDER))
			out.append(_snow("box", panel * _xf(Vector3(1.2, 0.03, 0.05), Vector3(0, 0.01, side * 0.05))))
		out.append(_p("cyl", _rod(Vector3(hx + 0.12, 0, zb + 0.2), Vector3(hx + 0.05, 0.75, zb + 0.08), 0.012), WOOD, "detail"))
		out.append(_p("torus", _xf(Vector3(0.24, 0.03, 0.24), Vector3(hx + 0.04, 0.88, zb + 0.06), Vector3(0, 0, PI * 0.5)), WOOD, "detail"))
		out.append(_p("box", _xf(Vector3(1.2, 0.06, 0.9), Vector3(0.1, 0.03, zb + 0.6), Vector3(0, 0.25, 0)), RUG.darkened(0.1), "remnant"))
		return out

	## Штендер-«домик»: две доски на петле, шапка цветом магазина, надпись — Label3D (Breakable.add_sign_text).
	static func _sign_board(size: Vector3) -> Array:
		var out := []
		var h := size.y - 0.04
		var board_len := sqrt(h * h + SIGN_SPREAD * SIGN_SPREAD)
		for side in [1.0, -1.0]:
			var board := Transform3D(Basis(Vector3.RIGHT, -side * SIGN_TILT), Vector3(0, h * 0.5, side * SIGN_SPREAD * 0.5))
			out.append(_p("box", board * _xf(Vector3(size.x - 0.04, board_len, 0.025), Vector3.ZERO), WHITE))
			out.append(_p("box", board * _xf(Vector3(size.x - 0.035, 0.16, 0.03), Vector3(0, board_len * 0.5 - 0.12, 0)), BLUE))
			out.append(_p("box", board * _xf(Vector3(size.x - 0.02, 0.03, 0.035), Vector3(0, -board_len * 0.5 + 0.015, 0)), STEEL.darkened(0.3), "detail"))
		out.append(_p("cyl", _rod(Vector3(-size.x * 0.5 + 0.03, h, 0), Vector3(size.x * 0.5 - 0.03, h, 0), 0.015), STEEL))
		out.append(_snow("box", _xf(Vector3(size.x - 0.1, 0.03, 0.07), Vector3(0, h + 0.02, 0))))
		out.append(_p("box", _xf(Vector3(size.x - 0.04, 0.025, board_len), Vector3(0.08, 0.013, 0.12), Vector3(0, 0.4, 0)), WHITE, "remnant"))
		out.append(_p("box", _xf(Vector3(size.x - 0.04, 0.028, 0.16), Vector3(0.0, 0.014, 0.12 - board_len * 0.45), Vector3(0, 0.4, 0)), BLUE, "remnant"))
		return out

	## Качели на А-стойках: две «А» по краям, балка, два сиденья на подвесах, снег на балке и сиденьях.
	static func _swing(size: Vector3) -> Array:
		var out := []
		var hx := size.x * 0.5 - 0.1
		var top := size.y - 0.1
		var foot := size.z * 0.5 - 0.1
		for sx in [-1.0, 1.0]:
			var x: float = sx * hx
			for sz in [-1.0, 1.0]:
				out.append(_p("cyl", _rod(Vector3(x, 0, sz * foot), Vector3(x, top, 0), 0.04), BLUE))
				out.append(_p("cyl", _xf(Vector3(0.1, 0.1, 0.1), Vector3(x, 0.05, sz * foot)), BLUE.darkened(0.3), "remnant"))
			out.append(_p("cyl", _rod(Vector3(x, 0.7, -foot * 0.67), Vector3(x, 0.7, foot * 0.67), 0.022), BLUE, "detail"))
		out.append(_p("cyl", _rod(Vector3(-hx - 0.06, top, 0), Vector3(hx + 0.06, top, 0), 0.05), YELLOW))
		out.append(_snow("box", _xf(Vector3(hx * 2.0, 0.04, 0.09), Vector3(0, top + 0.065, 0))))
		var seats := [[-0.6, RED], [0.6, GREEN]]
		for seat: Array in seats:
			var x: float = seat[0]
			for dx in [-0.2, 0.2]:
				out.append(_p("cyl", _rod(Vector3(x + dx, top, 0), Vector3(x + dx, 0.47, 0), 0.008), STEEL))
			out.append(_p("box", _xf(Vector3(0.46, 0.04, 0.22), Vector3(x, 0.46, 0)), seat[1]))
			out.append(_snow("box", _xf(Vector3(0.4, 0.03, 0.18), Vector3(x, 0.495, 0))))
		out.append(_p("box", _xf(Vector3(0.46, 0.04, 0.22), Vector3(0.3, 0.02, 0.4), Vector3(0, 0.5, 0)), RED, "remnant"))
		out.append(_p("cyl", _rod(Vector3(0.1, 0.02, 0.3), Vector3(0.9, 0.02, 0.1), 0.01), STEEL, "remnant"))
		return out

	## Горка: лесенка сзади (+z), площадка под двускатной крышей, жёлоб вниз к −z с раскатом, снег на крыше и жёлобе.
	static func _slide(size: Vector3) -> Array:
		var out := []
		var hz := size.z * 0.5
		var deck := 1.4
		var z_front := hz - 1.2
		var z_back := hz - 0.5
		for sx in [-0.4, 0.4]:
			for z in [z_front, z_back]:
				out.append(_p("cyl", _rod(Vector3(sx, 0, z), Vector3(sx, 2.25, z), 0.035), RED))
				out.append(_p("cyl", _xf(Vector3(0.09, 0.1, 0.09), Vector3(sx, 0.05, z)), RED.darkened(0.3), "remnant"))
			out.append(_p("cyl", _rod(Vector3(sx, 1.95, z_front), Vector3(sx, 1.95, z_back), 0.02), YELLOW))
		out.append(_p("box", _xf(Vector3(0.84, 0.06, 0.74), Vector3(0, deck, (z_front + z_back) * 0.5)), WOOD))
		out.append(_snow("box", _xf(Vector3(0.7, 0.04, 0.6), Vector3(0, deck + 0.05, (z_front + z_back) * 0.5))))
		for sx in [-1.0, 1.0]:
			var roof := Transform3D(Basis(Vector3.BACK, -sx * 0.62), Vector3(sx * 0.26, 2.42, (z_front + z_back) * 0.5))
			out.append(_p("box", roof * _xf(Vector3(0.62, 0.03, 0.95), Vector3.ZERO), YELLOW))
			out.append(_snow("box", roof * _xf(Vector3(0.56, 0.035, 0.9), Vector3(0, 0.03, 0))))
		var ladder_top := Vector3(0, deck, z_back)
		var ladder_foot := Vector3(0, 0, hz - 0.05)
		for sx in [-0.3, 0.3]:
			out.append(_p("cyl", _rod(ladder_foot + Vector3(sx, 0, 0), ladder_top + Vector3(sx, 0, 0), 0.025), RED))
		for k in range(1, 6):
			var p := ladder_foot.lerp(ladder_top, k / 6.0)
			out.append(_p("cyl", _rod(p + Vector3(-0.3, 0, 0), p + Vector3(0.3, 0, 0), 0.015), STEEL, "detail"))
		var high := Vector3(0, deck, z_front)
		var low := Vector3(0, 0.25, -hz + 0.45)
		var pitch := atan2(high.y - low.y, high.z - low.z)
		var length := high.distance_to(low)
		var chute := Transform3D(Basis(Vector3.RIGHT, -pitch), (high + low) * 0.5)
		out.append(_p("box", chute * _xf(Vector3(0.5, 0.03, length), Vector3.ZERO), STEEL))
		for sx in [-1.0, 1.0]:
			out.append(_p("box", chute * _xf(Vector3(0.03, 0.15, length), Vector3(sx * 0.26, 0.07, 0)), STEEL.darkened(0.15)))
		out.append(_snow("box", chute * _xf(Vector3(0.42, 0.03, length - 0.4), Vector3(0, 0.03, 0.1))))
		out.append(_p("box", _xf(Vector3(0.5, 0.03, 0.4), Vector3(0, 0.24, -hz + 0.25)), STEEL))
		for sx in [-0.25, 0.25]:
			out.append(_p("cyl", _rod(Vector3(sx, 0, -hz + 0.25), Vector3(sx, 0.24, -hz + 0.25), 0.025), RED))
		out.append(_p("cyl", _rod(Vector3(0, 0, (high.z + low.z) * 0.5), (high + low) * 0.5, 0.03), RED))
		out.append(_p("box", _xf(Vector3(0.5, 0.03, 1.2), Vector3(0.25, 0.015, -0.9), Vector3(0, 0.3, 0)), STEEL, "remnant"))
		out.append(_p("box", _xf(Vector3(0.6, 0.03, 0.5), Vector3(-0.3, 0.015, 0.6), Vector3(0, -0.4, 0)), YELLOW, "remnant"))
		return out

	## Песочница с грибком: крашеная рама, снег внутри, столб с красной шляпкой в белый горох под снегом.
	static func _sandpit(size: Vector3) -> Array:
		var out := []
		var hx := size.x * 0.5 - 0.05
		var hz := size.z * 0.5 - 0.05
		for sz in [-1.0, 1.0]:
			out.append(_p("box", _xf(Vector3(size.x, 0.28, 0.1), Vector3(0, 0.14, sz * hz)), YELLOW))
			out.append(_p("box", _xf(Vector3(size.x, 0.1, 0.1), Vector3(0, 0.05, sz * hz)), YELLOW.darkened(0.25), "remnant"))
		for sx in [-1.0, 1.0]:
			out.append(_p("box", _xf(Vector3(0.1, 0.28, size.z - 0.2), Vector3(sx * hx, 0.14, 0)), RED))
			out.append(_p("box", _xf(Vector3(0.1, 0.1, size.z - 0.2), Vector3(sx * hx, 0.05, 0)), RED.darkened(0.25), "remnant"))
			for sz in [-1.0, 1.0]:
				out.append(_p("box", _xf(Vector3(0.3, 0.04, 0.3), Vector3(sx * (hx - 0.15), 0.3, sz * (hz - 0.15)), Vector3(0, PI * 0.25, 0)), WOOD, "detail"))
		out.append(_snow("box", _xf(Vector3(size.x - 0.2, 0.22, size.z - 0.2), Vector3(0, 0.11, 0))))
		out.append(_snow("sphere", _xf(Vector3(size.x - 0.4, 0.22, size.z - 0.4), Vector3(0.1, 0.22, -0.1))))
		out.append(_snow("box", _xf(Vector3(size.x - 0.2, 0.1, size.z - 0.2), Vector3(0, 0.05, 0)), "remnant"))
		var cap_y := size.y - 0.32
		out.append(_p("cyl", _rod(Vector3(0, 0, 0), Vector3(0, cap_y, 0), 0.05), WOOD_DARK))
		out.append(_p("cyl", _xf(Vector3(0.12, 0.12, 0.12), Vector3(0, 0.06, 0)), WOOD_DARK, "remnant"))
		out.append(_p("cone", _xf(Vector3(1.9, 0.4, 1.9), Vector3(0, cap_y + 0.2, 0)), RED))
		out.append(_p("cyl", _xf(Vector3(1.86, 0.03, 1.86), Vector3(0, cap_y + 0.01, 0)), WHITE))
		for k in 7:
			var a := TAU * k / 7.0 + 0.3
			var r := 0.62 + 0.18 * float(k % 2)
			var y := cap_y + 0.4 - 0.4 * (r - 0.08) / 0.87
			out.append(_p("sphere", _xf(Vector3(0.14, 0.06, 0.14), Vector3(cos(a) * r, y, sin(a) * r), Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)), WHITE, "detail"))
		out.append(_snow("cone", _xf(Vector3(1.3, 0.3, 1.3), Vector3(0, cap_y + 0.32, 0))))
		return out

	## Детский домик: пол (base), стены из досок с дверным проёмом спереди (+z) и окнами, двускатная крыша со снегом.
	static func _playhouse(size: Vector3) -> Array:
		var out := []
		var hw := size.x * 0.5 - 0.1
		var wall := 1.1
		var top := 0.08 + wall
		out.append(_p("box", _xf(Vector3(size.x - 0.1, 0.08, size.z - 0.1), Vector3(0, 0.04, 0)), WOOD_DARK, "base"))
		out.append(_p("box", _xf(Vector3(hw * 2.0, wall, 0.06), Vector3(0, 0.08 + wall * 0.5, -hw + 0.03)), PLANK))
		for sx in [-1.0, 1.0]:
			out.append(_p("box", _xf(Vector3(0.06, wall, hw * 2.0), Vector3(sx * (hw - 0.03), 0.08 + wall * 0.5, 0)), PLANK))
			out.append(_p("box", _xf(Vector3(0.065, 0.36, 0.42), Vector3(sx * (hw - 0.03), 0.72, 0)), COAL.lightened(0.15), "detail"))
			out.append(_p("box", _xf(Vector3(0.55, wall, 0.06), Vector3(sx * (hw - 0.275), 0.08 + wall * 0.5, hw - 0.03)), PLANK))
			for sz in [-1.0, 1.0]:
				out.append(_p("box", _xf(Vector3(0.08, wall + 0.06, 0.08), Vector3(sx * hw, 0.08 + (wall + 0.06) * 0.5, sz * hw)), WOOD_DARK))
		out.append(_p("box", _xf(Vector3(hw * 2.0 - 1.1, 0.36, 0.06), Vector3(0, top - 0.18, hw - 0.03)), PLANK))
		var rise := size.y - top
		for sz in [-1.0, 1.0]:
			out.append(_p("prism", _xf(Vector3(hw * 2.0, rise, 0.04), Vector3(0, top + rise * 0.5, sz * (hw - 0.05))), PLANK.darkened(0.1)))
		var run := hw + 0.1
		var tilt := atan2(rise, run)
		var slope := sqrt(rise * rise + run * run) + 0.08
		for sx in [-1.0, 1.0]:
			var roof := Transform3D(Basis(Vector3.BACK, -sx * tilt), Vector3(sx * run * 0.5, top + rise * 0.5, 0))
			out.append(_p("box", roof * _xf(Vector3(slope, 0.05, size.z), Vector3.ZERO), RED))
			out.append(_snow("box", roof * _xf(Vector3(slope - 0.1, 0.05, size.z - 0.08), Vector3(0, 0.045, 0))))
		out.append(_snow("box", _xf(Vector3(1.1, 0.03, 0.9), Vector3(0.15, 0.09, 0.15), Vector3(0, 0.2, 0)), "remnant"))   # снег на полу
		out.append(_p("box", _xf(Vector3(0.9, 0.04, 0.12), Vector3(0.2, 0.1, 0.4), Vector3(0, 0.4, 0)), PLANK, "remnant"))
		out.append(_p("box", _xf(Vector3(0.8, 0.04, 0.5), Vector3(-0.3, 0.1, -0.3), Vector3(0, -0.3, 0)), RED, "remnant"))
		return out

	## Лавка без спинки: бетонные опоры, три крашеных бруса, снег на сиденье.
	static func _bench(size: Vector3) -> Array:
		var out := []
		var leg_x := size.x * 0.5 - 0.2
		for sx in [-1.0, 1.0]:
			out.append(_p("box", _xf(Vector3(0.1, size.y - 0.08, size.z - 0.15), Vector3(sx * leg_x, (size.y - 0.08) * 0.5, 0)), CONCRETE))
			out.append(_p("box", _xf(Vector3(0.1, 0.12, size.z - 0.15), Vector3(sx * leg_x, 0.06, 0)), CONCRETE, "remnant"))
		for k in 3:
			out.append(_p("box", _xf(Vector3(size.x, 0.045, 0.12), Vector3(0, size.y - 0.07, (k - 1) * 0.14)), GREEN.lightened(0.1)))
		out.append(_snow("box", _xf(Vector3(size.x - 0.1, 0.05, 0.38), Vector3(0, size.y - 0.02, 0))))
		out.append(_p("box", _xf(Vector3(1.0, 0.03, 0.12), Vector3(0.3, 0.015, 0.35), Vector3(0, 0.3, 0)), GREEN.lightened(0.1), "remnant"))
		out.append(_p("box", _xf(Vector3(0.7, 0.03, 0.12), Vector3(-0.4, 0.015, -0.3), Vector3(0, -0.5, 0)), GREEN.lightened(0.1), "remnant"))
		return out

	## Пластиковые ящики стопкой у магазина: 2 × 2 в три яруса (верхний неполный), полоса «ручек», снег сверху.
	static func _crate(size: Vector3) -> Array:
		var out := []
		var cw := size.x * 0.5 - 0.02
		var cd := size.z * 0.5 - 0.02
		var ch := size.y / 3.0 - 0.01
		var colors := [BLUE, RED, YELLOW, GREEN.lightened(0.15)]
		var n := 0
		for layer in 3:
			for ix in 2:
				for iz in 2:
					if layer == 2 and ix == 1 and iz == 1:
						continue
					var at := Vector3((ix - 0.5) * (cw + 0.02), ch * (layer + 0.5) + 0.005 * layer, (iz - 0.5) * (cd + 0.02))
					var yaw := 0.08 * float(layer == 2) * (1.0 if ix == 0 else -1.0)
					var color: Color = colors[n % colors.size()]
					n += 1
					out.append(_p("box", _xf(Vector3(cw, ch, cd), at, Vector3(0, yaw, 0)), color))
					out.append(_p("box", _xf(Vector3(cw + 0.006, 0.05, cd + 0.006), at + Vector3(0, ch * 0.25, 0), Vector3(0, yaw, 0)), color.darkened(0.45), "detail"))
					if layer == 2 or (layer == 1 and ix == 1 and iz == 1):
						out.append(_snow("box", _xf(Vector3(cw - 0.06, 0.04, cd - 0.06), at + Vector3(0, ch * 0.5 + 0.02, 0), Vector3(0, yaw, 0))))
		out.append(_p("box", _xf(Vector3(cw, 0.08, cd), Vector3(0.2, 0.04, 0.1), Vector3(0, 0.4, 0)), BLUE, "remnant"))
		out.append(_p("box", _xf(Vector3(cw, 0.07, cd), Vector3(-0.35, 0.035, -0.2), Vector3(0, -0.3, 0)), RED, "remnant"))
		return out

	## Прилавок-ящик бабки: ящик из досок, клеёнка, трёхлитровые банки с огурцами и помидорами, баночка грибов, ценник.
	static func _stall(size: Vector3) -> Array:
		var out := []
		var h := size.y - 0.18
		out.append(_p("box", _xf(Vector3(size.x - 0.1, h, size.z - 0.1), Vector3(0, h * 0.5, 0)), WOOD))
		for k in 2:
			out.append(_p("box", _xf(Vector3(size.x - 0.094, 0.015, size.z - 0.094), Vector3(0, h * (k + 1) / 3.0, 0)), WOOD_DARK, "detail"))
		out.append(_p("box", _xf(Vector3(size.x - 0.04, 0.025, size.z - 0.04), Vector3(0, h + 0.012, 0)), PAPER))
		out.append(_p("box", _xf(Vector3(size.x - 0.035, 0.03, 0.06), Vector3(0, h + 0.01, 0.2)), RED, "detail"))
		var jars := [[-0.35, -0.1, PICKLE], [-0.08, 0.12, TOMATO], [0.2, -0.12, PICKLE]]
		for j: Array in jars:
			var at := Vector3(j[0], h + 0.155, j[1])
			out.append(_p("cyl", _xf(Vector3(0.16, 0.26, 0.16), at), j[2]))
			out.append(_p("cyl", _xf(Vector3(0.12, 0.03, 0.12), at + Vector3(0, 0.145, 0)), YELLOW))
			out.append(_snow("cyl", _xf(Vector3(0.11, 0.015, 0.11), at + Vector3(0, 0.165, 0)), "detail"))
		out.append(_p("cyl", _xf(Vector3(0.1, 0.14, 0.1), Vector3(0.42, h + 0.095, 0.1)), Color(0.40, 0.28, 0.14), "detail"))
		out.append(_p("box", _xf(Vector3(0.24, 0.14, 0.01), Vector3(0.3, h - 0.05, size.z * 0.5 - 0.03), Vector3(-0.15, 0, 0)), PAPER.darkened(0.15), "detail"))
		out.append(_p("box", _xf(Vector3(0.8, 0.03, 0.14), Vector3(0.1, 0.015, 0.2), Vector3(0, 0.3, 0)), WOOD, "remnant"))
		out.append(_p("box", _xf(Vector3(0.6, 0.03, 0.14), Vector3(-0.2, 0.015, -0.2), Vector3(0, -0.4, 0)), WOOD, "remnant"))
		for k in 5:
			out.append(_p("sphere", _xf(Vector3(0.1, 0.05, 0.05), Vector3(-0.3 + 0.15 * k, 0.025, 0.05 * float(k % 2) - 0.02), Vector3(0, 0.6 * k, 0)), PICKLE.lightened(0.1) if k % 2 else TOMATO, "remnant"))
		return out

	## Обломки по виду: [размер, цвет, вес направления удара].
	static func debris(kind: StringName, size: Vector3) -> Array:
		var out := []
		if ENV_KINDS.has(kind):
			var wood := kind in [&"birch", &"poplar", &"rowan", &"dovecote", &"bench_big"]
			for k in 12:
				out.append([Vector3(0.12 + 0.05 * (k % 3), 0.06, 0.25 + 0.1 * (k % 4)), WOOD if wood else STEEL, 1.0])
			for k in 6: out.append([Vector3(0.15, 0.1, 0.16), SNOW_C, 0.6])
			return out
		match kind:
			&"snowman":
				for k in 12:
					out.append([Vector3(0.22, 0.2, 0.24) * (1.0 + 0.4 * float(k % 3)), SNOW_C, 0.8])
				out.append([Vector3(0.05, 0.05, 0.2), ORANGE, 1.0])
				out.append([Vector3(0.22, 0.16, 0.03), RED, 1.0])
				out.append([Vector3(0.2, 0.15, 0.03), RED, 1.0])
				out.append([Vector3(0.035, 0.035, 0.7), WOOD, 1.0])
				out.append([Vector3(0.12, 0.2, 0.08), Color(0.55, 0.42, 0.22), 1.0])
			&"planter":
				for k in 6:
					out.append([Vector3(0.28, 0.12, 0.08), WHITE if k % 3 else BLUE, 1.0])
				for k in 5:
					out.append([Vector3(0.12, 0.1, 0.12), EARTH, 0.6])
				for k in 4:
					out.append([Vector3(0.16, 0.14, 0.16), SNOW_C, 0.6])
				for k in 5:
					out.append([Vector3(0.015, 0.3, 0.015), STEM, 0.8])
			&"bin":
				for k in 5:
					out.append([Vector3(0.24, 0.2, 0.02), GREEN, 1.0])
				for k in 7:
					out.append([Vector3(0.11, 0.01, 0.08), PAPER if k % 2 else Color(0.6, 0.4, 0.2), 0.7])
				out.append([Vector3(0.18, 0.12, 0.18), SNOW_C, 0.5])
			&"seesaw":
				for k in 4:
					out.append([Vector3(0.8, 0.05, 0.27), WOOD, 1.0])
				for k in 4:
					out.append([Vector3(0.03, 0.3, 0.03), RED, 1.0])
				for k in 5:
					out.append([Vector3(0.25, 0.03, 0.05), WOOD_DARK, 0.8])
				for k in 4:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"carousel":
				var colors := [RED, YELLOW, BLUE]
				for k in 8:
					out.append([Vector3(0.6, 0.06, 0.3), colors[k % 3], 1.0])
				for k in 5:
					out.append([Vector3(0.035, 0.55, 0.035), YELLOW if k % 2 else STEEL, 1.0])
				for k in 5:
					out.append([Vector3(0.22, 0.12, 0.22), SNOW_C, 0.5])
			&"barrier":
				for k in 12:
					out.append([Vector3(0.5, 0.16, 0.025), RED if k % 2 else WHITE, 1.0])
				out.append([Vector3(0.65, 0.5, 0.03), YELLOW, 1.0])
				for k in 4:
					out.append([Vector3(0.04, 0.5, 0.04), STEEL, 0.8])
				for k in 5:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"cones":
				for k in 4:
					out.append([Vector3(0.16, 0.22, 0.02), ORANGE, 1.0])
				out.append([Vector3(0.14, 0.06, 0.02), WHITE, 1.0])
				out.append([Vector3(0.1, 0.06, 0.02), WHITE, 1.0])
				out.append([Vector3(0.08, 0.06, 0.08), SNOW_C, 0.5])
			&"fence":
				for k in 6:
					out.append([Vector3(0.4, 0.03, 0.03), FENCE, 1.0])
				for k in 4:
					out.append([Vector3(0.02, 0.4, 0.02), FENCE, 1.0])
				for k in 3:
					out.append([Vector3(0.18, 0.1, 0.18), SNOW_C, 0.5])
			&"domino":
				for k in 6:
					out.append([Vector3(0.5, 0.05, 0.14), WOOD, 1.0])
				for k in 6:
					out.append([Vector3(0.05, 0.016, 0.1), WHITE, 1.2])
				for k in 3:
					out.append([Vector3(0.04, 0.4, 0.04), STEEL, 0.8])
				for k in 5:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"laundry":
				var cloth := [WHITE, Color(0.55, 0.70, 0.88), Color(0.95, 0.88, 0.80), Color(0.85, 0.40, 0.45), Color(0.30, 0.32, 0.45), RED]
				for k in 8:
					out.append([Vector3(0.45, 0.4, 0.02), cloth[k % cloth.size()], 1.0])
				for k in 3:
					out.append([Vector3(0.03, 0.6, 0.03), BLUE, 0.8])
				for k in 3:
					out.append([Vector3(0.15, 0.08, 0.15), SNOW_C, 0.5])
			&"fort":
				for k in 18:
					out.append([Vector3(0.3, 0.24, 0.26) * (1.0 + 0.3 * float(k % 3)), SNOW_C, 0.8])
				out.append([Vector3(0.3, 0.18, 0.01), RED, 1.0])
				out.append([Vector3(0.02, 0.6, 0.02), WOOD, 1.0])
			&"sofa":
				for k in 6:
					out.append([Vector3(0.4, 0.14, 0.3), FABRIC, 0.8])
				for k in 4:
					out.append([Vector3(0.5, 0.04, 0.08), WOOD, 1.0])
				for k in 3:
					out.append([Vector3(0.12, 0.12, 0.04), STEEL, 1.0])
				for k in 5:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"sand_box":
				for k in 6:
					out.append([Vector3(0.5, 0.03, 0.14), WOOD, 1.0])
				for k in 6:
					out.append([Vector3(0.14, 0.1, 0.14), SAND, 0.6])
				out.append([Vector3(0.4, 0.12, 0.012), YELLOW, 1.0])
				for k in 3:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"carpet":
				for k in 4:
					out.append([Vector3(0.5, 0.4, 0.03), RUG, 1.0])
				for k in 2:
					out.append([Vector3(0.5, 0.06, 0.035), BORDER, 1.0])
				for k in 3:
					out.append([Vector3(0.04, 0.6, 0.04), BAR, 0.8])
				for k in 4:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"sign_board":
				for k in 3:
					out.append([Vector3(0.28, 0.4, 0.025), WHITE, 1.0])
				for k in 2:
					out.append([Vector3(0.28, 0.16, 0.03), BLUE, 1.0])
				out.append([Vector3(0.3, 0.03, 0.03), STEEL, 1.0])
				out.append([Vector3(0.12, 0.08, 0.12), SNOW_C, 0.5])
			&"swing":
				for k in 4:
					out.append([Vector3(0.05, 0.7, 0.05), BLUE, 1.0])
				out.append([Vector3(0.7, 0.06, 0.06), YELLOW, 1.0])
				out.append([Vector3(0.46, 0.04, 0.22), RED, 1.2])
				out.append([Vector3(0.46, 0.04, 0.22), GREEN, 1.2])
				for k in 4:
					out.append([Vector3(0.015, 0.4, 0.015), STEEL, 1.0])
				for k in 4:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"slide":
				for k in 3:
					out.append([Vector3(0.5, 0.03, 0.6), STEEL, 1.0])
				for k in 4:
					out.append([Vector3(0.04, 0.6, 0.04), RED, 1.0])
				for k in 3:
					out.append([Vector3(0.5, 0.03, 0.4), YELLOW, 1.0])
				for k in 4:
					out.append([Vector3(0.3, 0.02, 0.02), STEEL, 0.8])
				for k in 5:
					out.append([Vector3(0.22, 0.12, 0.22), SNOW_C, 0.5])
			&"sandpit":
				for k in 6:
					out.append([Vector3(0.5, 0.25, 0.1), YELLOW if k % 2 else RED, 1.0])
				for k in 4:
					out.append([Vector3(0.5, 0.1, 0.35), RED, 1.0])
				out.append([Vector3(0.08, 0.7, 0.08), WOOD_DARK, 1.0])
				for k in 6:
					out.append([Vector3(0.25, 0.15, 0.25), SNOW_C, 0.5])
			&"playhouse":
				for k in 8:
					out.append([Vector3(0.5, 0.3, 0.05), PLANK, 1.0])
				for k in 4:
					out.append([Vector3(0.5, 0.04, 0.4), RED, 1.0])
				for k in 3:
					out.append([Vector3(0.07, 0.5, 0.07), WOOD_DARK, 0.8])
				for k in 5:
					out.append([Vector3(0.22, 0.12, 0.22), SNOW_C, 0.5])
			&"bench":
				for k in 6:
					out.append([Vector3(0.6, 0.045, 0.12), GREEN.lightened(0.1), 1.0])
				for k in 2:
					out.append([Vector3(0.1, 0.15, 0.2), CONCRETE, 0.6])
				for k in 4:
					out.append([Vector3(0.2, 0.12, 0.2), SNOW_C, 0.5])
			&"crate":
				var tones := [BLUE, RED, YELLOW, GREEN.lightened(0.15)]
				for k in 10:
					out.append([Vector3(0.3, 0.14, 0.04), tones[k % tones.size()], 1.0])
				for k in 3:
					out.append([Vector3(0.2, 0.1, 0.2), SNOW_C, 0.5])
			&"stall":
				for k in 5:
					out.append([Vector3(0.45, 0.03, 0.14), WOOD, 1.0])
				for k in 6:
					out.append([Vector3(0.08, 0.04, 0.04), PICKLE if k % 2 else TOMATO, 1.0])
				for k in 4:
					out.append([Vector3(0.06, 0.08, 0.01), Color(0.70, 0.80, 0.78), 1.2])   # стекло банок
				out.append([Vector3(0.4, 0.02, 0.3), PAPER, 0.8])
			_:
				for k in 8:
					out.append([size * 0.3, WOOD, 1.0])
		return out

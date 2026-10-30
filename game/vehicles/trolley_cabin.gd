extends Node3D
## Люди в троллейбусе № 13 (TROLLEY-01, решение владельца 30.10: «действующий — с водителем и пассажирами, обычными
## горожанами»). Узел — ребёнок Body троллейбуса, оси транспорта: перед −Z, двери справа (+X), начало на земле.
## Все — плоские облики жителей (CharacterSprite через LadaDriver: без тени и шагов), без тел и коллизий (C2), вне
## стелса (C7) и сбивания (KNOCK-01): сбить можно только вышедшего наружу жителя. Облики — только Layout.RESIDENT_LOOKS.
## Водитель — слева за рулём, на стоянке поворачивает голову к дверям. Пассажиры сидят на местах SLOTS: фоновые
## (BACKGROUND) едут всё время, жители LIFE-01 в поездке (Resident: hidden и state &"ride") занимают места тем же
## обликом — их список даёт Residents каждый шаг (set_riders); вышел — место свободно. В салоне не больше MAX_SHOWN:
## на место севшего жителя уходит фоновый, вышел житель — фоновый возвращается. Дальше LOD_RANGE от камеры не рисуются.
## Высоты условные, как салон trolleybus.gd: пол салона на уровне низа окон (SILL), сидящие — головой в оконном поясе.

const Layout = preload("res://game/world/layout.gd")
const OccupantScript = preload("res://game/vehicles/lada_driver.gd")
const ART_DIR := "res://assets/art/characters/"

const CANVAS_M := 2.0              # высота холста облика жителя (Residents.SILHOUETTES)
const SEAT_FEET := 0.95            # ноги сидящего: голова взрослого ≈ 2,6 м, ниже верха окон 2,92
const STAND_FEET := 1.0            # стоящий у поручня — чуть выше сидящих, макушка ниже верха окон
const DRIVER_AT := Vector3(-0.62, 0.8, -4.95)   # голова ≈ 2,5 м: в лобовом и в первом боковом окне
const DRIVER_LOOK: StringName = &"ushanka_walk"
const DRIVER_TURN := -0.9          # рад: голова к дверям (+X) на стоянке
const DRIVER_TURN_SPEED := 3.0     # 1/с
const LOD_RANGE := 60.0
const MAX_SHOWN := 8
## Места: [x, z, стоит]. Сиденья — как в trolleybus.gd (вдоль бортов с z −3,5 шагом 0,85; справа — не у дверей),
## стоящие — у вертикальных поручней.
const SLOTS: Array = [
	[-0.72, -1.95, false], [0.72, 1.5, false], [-0.72, 2.2, false], [-0.72, -0.25, false],
	[0.72, -2.8, false], [-0.4, 3.0, true], [-0.72, 4.75, false], [-0.4, -2.4, true],
	[0.72, 2.35, false], [-0.72, -3.3, false],
]
## Фоновые пассажиры: облик и место (индекс SLOTS). Разные силуэты: бабка в тюрбане, дед-турист, бабка с бантом, пацан.
const BACKGROUND: Array = [[&"turban", 0], [&"tourist", 1], [&"bow", 2], [&"kid", 5]]

var driver: Node3D
var riders: Array = []             # Resident в поездке, по порядку посадки
var _seats := {}                   # индекс места → узел облика
var _owner := {}                   # индекс места → Resident или &"bg<k>"
var _rider_slot := {}              # Resident → индекс места
var _turn := 0.0

static func character_for(look: StringName) -> String:
	var art := "resident_%s" % look
	return art if ResourceLoader.exists("%s%s_front_idle.svg" % [ART_DIR, art]) else "vendor"

func _init() -> void:
	name = "Passengers"

func _ready() -> void:
	driver = _occupant(character_for(DRIVER_LOOK), CANVAS_M)
	driver.name = "Driver"
	driver.position = DRIVER_AT
	add_child(driver)
	_refill()

## Голова водителя: на стоянке (двери открыты) — к дверям, в пути — вперёд.
func tick(delta: float, doors_open: bool) -> void:
	var wanted := DRIVER_TURN if doors_open else 0.0
	_turn = lerpf(_turn, wanted, 1.0 - exp(-DRIVER_TURN_SPEED * delta))
	driver.rotation.y = _turn

## Жители в поездке (Residents, каждый шаг физики). Порядок не важен; меняется состав — меняются места.
func set_riders(list: Array) -> void:
	var changed := false
	for r in riders.duplicate():
		if not list.has(r) or not is_instance_valid(r):
			riders.erase(r)
			_free_slot(_rider_slot.get(r, -1))
			_rider_slot.erase(r)
			changed = true
	for r in list:
		if not riders.has(r) and riders.size() < MAX_SHOWN:
			riders.append(r)
			changed = true
	if changed:
		_refill()

## Узел облика жителя r в салоне (null — его в салоне нет).
func seat_of(r: Object) -> Node3D:
	return _seats.get(_rider_slot.get(r, -1))

## Все пассажиры в салоне (без водителя): узлы обликов.
func shown() -> Array:
	return _seats.values()

## Расставить: сначала жители в поездке (каждый — на своё место до выхода), остаток до MAX_SHOWN — фоновые.
func _refill() -> void:
	for r in riders:
		if _rider_slot.has(r):
			continue
		var slot := _free_index(true)
		if slot < 0:
			slot = _bg_slot_to_take()
			_free_slot(slot)
		_rider_slot[r] = slot
		_take(slot, r, String(r.get("character")), float(r.get("height_m")))
	var room := MAX_SHOWN - riders.size()
	for k in BACKGROUND.size():
		var tag := StringName("bg%d" % k)
		var at = _owner.find_key(tag)
		if k < room and at == null:
			var slot: int = BACKGROUND[k][1]
			if _owner.has(slot):
				slot = _free_index(false)
			if slot >= 0:
				_take(slot, tag, character_for(BACKGROUND[k][0]), CANVAS_M)
		elif k >= room and at != null:
			_free_slot(at)

func _free_index(prefer_free_of_bg: bool) -> int:
	for i in SLOTS.size():
		if not _owner.has(i):
			# Места фоновых пассажиров житель занимает последними — чтобы фоновые сидели на своих.
			if prefer_free_of_bg and _is_bg_home(i):
				continue
			return i
	if prefer_free_of_bg:
		return _free_index(false)
	return -1

func _is_bg_home(i: int) -> bool:
	for bg in BACKGROUND:
		if bg[1] == i:
			return true
	return false

func _bg_slot_to_take() -> int:
	for k in range(BACKGROUND.size() - 1, -1, -1):
		var at = _owner.find_key(StringName("bg%d" % k))
		if at != null:
			return at
	return -1

func _take(slot: int, who: Variant, character: String, height: float) -> void:
	var spec: Array = SLOTS[slot]
	var node := _occupant(character, height)
	node.name = "Seat%d" % slot
	node.position = Vector3(spec[0], STAND_FEET if spec[2] else SEAT_FEET, spec[1])
	# Сидят лицом вперёд; стоящий — вполоборота к проходу.
	node.rotation.y = (0.7 if float(spec[0]) < 0.0 else -0.7) if spec[2] else 0.0
	add_child(node)
	_seats[slot] = node
	_owner[slot] = who

func _free_slot(slot: int) -> void:
	if slot < 0 or not _seats.has(slot):
		return
	var node: Node3D = _seats[slot]
	_seats.erase(slot)
	_owner.erase(slot)
	remove_child(node)
	node.queue_free()

func _occupant(character: String, height: float) -> Node3D:
	var node: Node3D = OccupantScript.new()
	node.character = character
	node.height_m = height
	node.ready.connect(_lod.bind(node), CONNECT_ONE_SHOT)
	return node

func _lod(node: Node3D) -> void:
	node.sprite.visibility_range_end = LOD_RANGE
	node.sprite.visibility_range_end_margin = 4.0

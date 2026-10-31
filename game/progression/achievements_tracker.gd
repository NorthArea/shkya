extends Node
## One tracker per world; existing producers remain the owners of gameplay outcomes.

const DOUBLE_WINDOW := 3.0
const TREE_KINDS := [&"birch", &"poplar", &"rowan"]
const BENCH_KINDS := [&"bench", &"bench_big"]
var world: Node
var store: Node
var clock := 0.0
var _last_granny := -1
var _last_granny_at := -INF
var _broke_something := false
var _broke_by_car := false
var _broke_by_punch := false
var _coins := 0
var _alarm_count := 0

func setup(new_world: Node, collection: Node) -> void:
	name = "AchievementsTracker"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	world = new_world
	store = collection
	var residents := world.get_node("LevelGeometry/Residents")
	residents.resident_knocked.connect(_on_resident_knocked)
	var breakables := world.get_node("LevelGeometry/Breakables")
	breakables.broken.connect(_on_broken)
	world.player.hide_mode_changed.connect(_on_hide_mode_changed)
	world.get_node("LevelGeometry/Coins").collected.connect(_on_coin_collected)
	world.get_node("LevelGeometry/Drones").drone_broken.connect(_on_drone_broken)
	breakables.car_alarm.connect(_on_car_alarm)
	world.get_node("LevelGeometry/Ambient").dog_petted.connect(_on_dog_petted)

func _physics_process(delta: float) -> void:
	clock += delta

func _on_resident_knocked(resident: Node) -> void:
	if resident.voice != &"babka":
		return
	if _last_granny >= 0 and _last_granny != resident.index and clock - _last_granny_at <= DOUBLE_WINDOW:
		store.unlock(&"double_granny")
	_last_granny = resident.index
	_last_granny_at = clock

func _on_broken(item: Node, by: StringName) -> void:
	if by not in [&"car", &"punch"]:
		return
	_broke_something = true
	_broke_by_car = _broke_by_car or by == &"car"
	_broke_by_punch = _broke_by_punch or by == &"punch"
	if _broke_by_car and _broke_by_punch:
		store.unlock(&"professional_ditcher")
	if by == &"car" and item.kind in TREE_KINDS:
		store.unlock(&"timber_delivery")
	if by == &"punch" and item.kind in BENCH_KINDS:
		store.unlock(&"standing_room")

func _on_hide_mode_changed(_old: StringName, mode: StringName) -> void:
	if mode == &"box":
		store.unlock(&"bread_box")
	elif mode == &"snowdrift":
		store.unlock(&"cold_storage")

func _on_dog_petted(_actor: Node) -> void:
	if _broke_something:
		store.unlock(&"good_boy_certificate")

func _on_coin_collected(_at: Vector3, _total: int) -> void:
	_coins += 1
	if _coins >= 10:
		store.unlock(&"bread_zero")

func _on_drone_broken(_drone: Node3D) -> void:
	store.unlock(&"drone_silence")

func _on_car_alarm(_at: Vector3) -> void:
	_alarm_count += 1
	if _alarm_count >= 3:
		store.unlock(&"alarm_clock")

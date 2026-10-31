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
var _declined := false

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
	world.mission.bread_received.connect(_on_bread_received)
	world.mission.quest_completed.connect(_on_quest_completed)
	world.mission.state_changed.connect(_on_state_changed)
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
	if by == &"car" and item.kind in TREE_KINDS:
		store.unlock(&"timber_delivery")
	if by == &"punch" and item.kind in BENCH_KINDS:
		store.unlock(&"standing_room")

func _on_bread_received() -> void:
	if world.mission.money == 0:
		store.unlock(&"bread_zero")

func _on_hide_mode_changed(_old: StringName, mode: StringName) -> void:
	if not world.mission.has_bread:
		return
	if mode == &"box":
		store.unlock(&"bread_box")
	elif mode == &"snowdrift":
		store.unlock(&"cold_storage")

func _on_dog_petted(_actor: Node) -> void:
	if _broke_something:
		store.unlock(&"good_boy_certificate")

func _on_state_changed(old: StringName, state: StringName) -> void:
	if old == &"OFFERED" and state == &"NOT_STARTED":
		_declined = true
	elif state == &"NOT_STARTED":
		_declined = false
		_broke_something = false
		_last_granny = -1

func _on_quest_completed(_xp: int) -> void:
	if _declined:
		store.unlock(&"professional_ditcher")

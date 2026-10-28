extends "res://game/stealth/hide_spot.gd"
## EXT-02 C (docs/extension/HIDE_SPOTS.md, разделы 6, 11, 14 C): коробка из-под батонов у киоска.
## Облик — картонный короб SIZE с надписью «БАТОНЫ» на четырёх боках и снегом на крышке, простые объёмы без
## коллизии (на путь патруля и лучи сенсоров не влияет). E — надеть: такой же короб в player.hide_visual (стоит на
## снегу, Илюша внутри; на ходу покачивается по пройденному пути), короб в мире скрыт. E — снять: короб остаётся
## рядом с Илюшей (за спиной, на свободном месте). reset() — на home (Layout.BREAD_BOX), Илюша без режима.
## Гэги (раздел 11) — субтитрами SoundDirector.show_gag, по разу за попытку (между reset()):
## C02 — коробка GAG_STILL_SECONDS неподвижна у полицейского в конусе (in_view, до GAG_RANGE), не обнаружен;
## C03 — коробка идёт в конусе и шкала подозрения > GAG_MOVING_SUSPICION.

const SIZE := Vector3(1.0, 1.2, 0.8)   # ширина × высота × глубина, м
const LIFT := 0.02                     # зазор над снегом
const ZONE_RADIUS := 1.6               # зона E вокруг короба (+0,5 м щупа Илюши)
const CARDBOARD := Color(0.80, 0.60, 0.37)     # светлый картон: в вечернем свете не сливается с тёмным киоском
const CARDBOARD_DARK := Color(0.58, 0.42, 0.24)
const TAPE := Color(0.86, 0.74, 0.52)
const INK := Color(0.20, 0.13, 0.08)
const SNOW := Color(0.93, 0.95, 0.98)
const LABEL_TEXT := "БАТОНЫ"
## Покачивание надетого короба: высота и крен на пройденный метр.
const BOB_HEIGHT := 0.035
const BOB_ROLL := 0.05
const BOB_STEP := 0.55                 # м пути на один «шаг»

const GAG_STILL_SECONDS := 3.0
const GAG_RANGE := 12.0
const GAG_MOVING_SUSPICION := 0.3
const GAG_PAGE_SECONDS := 2.5
const OFFICER_PATH := "LevelGeometry/Patrols/Officer"

## Сколько раз показан каждый гэг за всё время (для тестов); за попытку — не больше одного.
var gag_counts := {&"C02": 0, &"C03": 0}
## Короб на Илюше (в player.hide_visual), пока он внутри; иначе null.
var worn: Node3D = null

var _gag_done := {}
var _still_seen := 0.0

func _init() -> void:
	super()   # группа hide_spots — в _init предка
	mode = HideTuning.BOX
	prompt_enter = HideTuning.PROMPT_BOX_ENTER
	prompt_exit = HideTuning.PROMPT_BOX_EXIT
	interaction_id = &"bread_box"
	radius = ZONE_RADIUS

func _build_look() -> Node3D:
	var crate := build_crate()
	crate.name = "BreadBoxLook"
	return crate

## Короб «БАТОНЫ»: корпус, лента по крышке, снег сверху, надписи на четырёх боках. Начало — на снегу под центром.
static func build_crate() -> Node3D:
	var root := Node3D.new()
	var body := _mesh(SIZE, CARDBOARD)
	body.name = "Body"
	body.position.y = LIFT + SIZE.y * 0.5
	root.add_child(body)
	# Клапаны крышки: тёмный шов поперёк и светлая лента вдоль.
	var seam := _mesh(Vector3(SIZE.x + 0.004, 0.012, 0.03), CARDBOARD_DARK)
	seam.position.y = LIFT + SIZE.y + 0.002
	root.add_child(seam)
	var tape := _mesh(Vector3(0.12, 0.014, SIZE.z + 0.006), TAPE)
	tape.position.y = LIFT + SIZE.y + 0.004
	root.add_child(tape)
	# Снег на крышке: шапка чуть меньше крышки и сугробик к одному краю.
	var cap := _mesh(Vector3(SIZE.x * 0.92, 0.05, SIZE.z * 0.88), SNOW)
	cap.name = "Snow"
	cap.position = Vector3(0.0, LIFT + SIZE.y + 0.03, 0.0)
	root.add_child(cap)
	var heap_mesh := SphereMesh.new()
	heap_mesh.radius = 0.24
	heap_mesh.height = 0.14
	heap_mesh.material = (cap as MeshInstance3D).material_override
	var heap := MeshInstance3D.new()
	heap.mesh = heap_mesh
	heap.position = Vector3(-0.16, LIFT + SIZE.y + 0.06, 0.08)
	heap.scale = Vector3(1.0, 1.0, 0.8)
	root.add_child(heap)
	# «БАТОНЫ» на всех боках: широкие (±z) крупнее, узкие (±x) мельче.
	var faces := [
		[Vector3(0, 0, SIZE.z * 0.5), 0.0, 0.0062],
		[Vector3(0, 0, -SIZE.z * 0.5), PI, 0.0062],
		[Vector3(SIZE.x * 0.5, 0, 0), PI * 0.5, 0.005],
		[Vector3(-SIZE.x * 0.5, 0, 0), -PI * 0.5, 0.005],
	]
	for face in faces:
		var label := Label3D.new()
		label.name = "Label"
		label.text = LABEL_TEXT
		label.font_size = 40
		label.pixel_size = face[2]
		label.modulate = INK
		label.outline_size = 0
		label.shaded = true
		label.double_sided = false
		label.position = face[0] * 1.01 + Vector3(0, LIFT + SIZE.y * 0.6, 0)
		label.rotation.y = face[1]
		root.add_child(label)
	return root

static func _mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = material
	return node

# --- вход, выход, сброс ---

func _on_entered(p: Ilyusha) -> void:
	_drop_worn()
	worn = build_crate()
	worn.name = "WornBreadBox"
	p.hide_visual.add_child(worn)
	_still_seen = 0.0

func _on_exited(_p: Ilyusha) -> void:
	worn = null   # Ilyusha очищает hide_visual при переходе в &"none"

func _on_reset() -> void:
	if is_occupied():
		player().force_hide_mode(HideTuning.NONE)   # сброс без reset_hide: не оставлять короб на Илюше
	worn = null
	_gag_done.clear()
	_still_seen = 0.0

func _drop_worn() -> void:
	if is_instance_valid(worn):
		worn.get_parent().remove_child(worn)
		worn.queue_free()
	worn = null

## Снятый короб — за спиной Илюши (он «выходит» вперёд), иначе сбоку или спереди; на свободном от стен месте.
func _place_look_at_player(p: Ilyusha) -> void:
	var yaw: float = p.visual.rotation.y
	var back := Vector3(sin(yaw), 0.0, cos(yaw))   # −(направление взгляда)
	var side := Vector3(back.z, 0.0, -back.x)
	var base := Vector3(p.global_position.x, home.y, p.global_position.z)
	var spot := base
	for offset in [back * 1.0, side * 1.0, -side * 1.0, -back * 1.0, back * 0.6]:
		if _crate_fits(base + offset, yaw):
			spot = base + offset
			break
	global_position = spot
	rotation.y = yaw

func _crate_fits(point: Vector3, yaw: float) -> bool:
	if not is_inside_tree():
		return false
	var shape := BoxShape3D.new()
	shape.size = SIZE - Vector3(0.05, 0.1, 0.05)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 4   # World, Car
	query.transform = Transform3D(Basis(Vector3.UP, yaw), point + Vector3.UP * (LIFT + SIZE.y * 0.5 + 0.05))
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

# --- покачивание и гэги ---

func _process(_delta: float) -> void:
	if not is_instance_valid(worn):
		return
	var p := player()
	if p == null:
		return
	var phase := p.hide_travel / BOB_STEP * PI
	worn.position.y = absf(sin(phase)) * BOB_HEIGHT
	worn.rotation.z = sin(phase) * BOB_ROLL

func _physics_process(delta: float) -> void:
	if not is_occupied():
		_still_seen = 0.0
		return
	var w := world()
	var p := player()
	if w.is_stealth_failing():
		_still_seen = 0.0
		return
	var sensor := _officer_sensor()
	if sensor == null:
		return
	var seen: bool = sensor.in_view and sensor.distance_to_player() <= GAG_RANGE
	if p.is_still() and seen:
		_still_seen += delta
		if _still_seen >= GAG_STILL_SECONDS:
			_gag(&"C02", QuestLines.HIDE_BOX_STILL)
	else:
		_still_seen = 0.0
	if not p.is_still() and seen and w.stealth.suspicion > GAG_MOVING_SUSPICION:
		_gag(&"C03", QuestLines.HIDE_BOX_MOVING)

func _gag(id: StringName, lines: Array) -> void:
	if _gag_done.has(id):
		return
	_gag_done[id] = true
	gag_counts[id] += 1
	var sound := world().get_node_or_null("SoundDirector")
	if sound and sound.has_method(&"show_gag"):
		sound.show_gag(lines, GAG_PAGE_SECONDS)

func _officer_sensor() -> DetectionSensor:
	var officer := world().get_node_or_null(OFFICER_PATH)
	if officer == null:
		return null
	var sensor: Variant = officer.get("sensor")
	return sensor if sensor is DetectionSensor else null

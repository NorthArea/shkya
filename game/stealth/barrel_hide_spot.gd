extends HideSpot
## EXT-02 E (docs/extension/HIDE_SPOTS.md, раздел 8; C7а): ржавая бочка у павильона остановки — «секретный транспорт
## с очень плохой маскировкой». Облик в мире — бочка Ø 0,9 м, высота 1,2 м стоймя (обручи, ржавые пятна, снег сверху),
## без коллизии: маршрут не перегораживает. E — Илюша внутри (`hide_mode = &"barrel"`): предел 2,6 м/с, без прыжка,
## заметность стоя 0 / катясь 1,0 — всё это даёт ядро (Ilyusha, HideTuning). Здесь — только своё:
## - облик на Илюше (player.hide_visual): бочка лежит на боку поперёк движения и вращается вокруг своей оси на угол
##   player.hide_travel / RADIUS (фактический путь по XZ; у стены пути нет — вращения нет), спрайт скрыт ядром;
## - капсула Илюши на время бочки — радиус COLLIDER_RADIUS 0,45 вместо 0,35: лежащая бочка не входит в стену по ходу
##   (торцы по бокам — до 0,15 м, см. tests/hide_barrel_test.gd); прежняя форма возвращается при любом выходе из режима;
## - удар о стену: столкновение move_and_slide() со скоростью в стену > BUMP_SPEED — «БУМ» (SoundDirector.barrel_bump)
##   не чаще раза в BUMP_COOLDOWN; первый удар за попытку — тост «БОЧКА ПРИБЫЛА» (строка подсказки, как тост сугроба)
##   и субтитр Илюши «Ну всё» (C06); дребезжание качения — SoundDirector.barrel_roll(скорость / предел);
## - гэг C05: бочка катится, полицейский Officer видит её (in_view сенсора) — субтитры раз за попытку;
## - выход — в свободную точку рядом (капсула, маска World|Car, луч от бочки), иначе «ВЫХОД ЗАНЯТ»; бочка встаёт
##   там, где Илюша вылез; reset() — бочка на Layout.BARREL, счётчики попытки сброшены.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")

const RADIUS := 0.45                    # Ø 0,9 м
const LENGTH := 1.2
const ZONE_RADIUS := 1.6                # зона E вокруг бочки (+0,5 м щупа Илюши)
## Радиус капсулы Илюши в бочке (HIDE_SPOTS.md, раздел 8, «Техническое решение»).
const COLLIDER_RADIUS := 0.45
## Удар: скорость в стену до столкновения больше этой, м/с; «БУМ» — не чаще раза в BUMP_COOLDOWN с.
const BUMP_SPEED := 1.0
const BUMP_COOLDOWN := 4.0
## Выход: кольца точек вокруг бочки (м от центра), капсула Илюши с запасом.
const EXIT_RINGS: Array[float] = [1.0, 1.4]
const EXIT_CAPSULE_RADIUS := 0.4
const EXIT_MASK := 1 | 4 | 64           # World | Car | SnowBank (DRIVE-02: валы — как раньше)
const GAG_PAGE_SECONDS := 2.5
const TOAST_SECONDS := 2.0
const OFFICER_PATH := "LevelGeometry/Patrols/Officer"

const RUST := Color(0.42, 0.21, 0.11)
const RUST_LIGHT := Color(0.62, 0.32, 0.13)
const RUST_DARK := Color(0.23, 0.12, 0.07)
const PAINT := Color(0.24, 0.31, 0.30)  # остатки старой краски
const HOOP := Color(0.30, 0.17, 0.10)
const SNOW := Color(0.93, 0.95, 0.98)
## Пятна: [угол, высота от центра, размер, цвет 0 — светлая ржа, 1 — тёмная, 2 — краска].
const SPOTS := [
	[0.3, 0.25, 0.16, 0], [1.4, -0.32, 0.12, 1], [2.2, 0.05, 0.2, 2], [2.9, 0.38, 0.1, 0],
	[3.7, -0.12, 0.17, 1], [4.4, 0.3, 0.14, 2], [5.1, -0.4, 0.11, 0], [5.8, 0.1, 0.13, 1],
	[0.9, -0.05, 0.09, 1], [3.2, -0.38, 0.15, 0],
]

## Бочка ударилась о стену (speed — скорость в стену до удара, м/с).
signal bumped(speed: float)

## Угол вращения лежащей бочки, рад (−путь / радиус: верх уходит по ходу движения).
var roll_angle := 0.0
## Счётчики за мир (для тестов): «БУМ», тост «БОЧКА ПРИБЫЛА», гэг C05.
var bump_count := 0
var toast_count := 0
var roll_gag_count := 0
## Время (с от старта мира) каждого «БУМ».
var bump_times: Array[float] = []
var shell: Node3D                       # бочка на Илюше (лежит), ребёнок player.hide_visual
var roller: Node3D                      # вращающаяся часть shell

var _clock := 0.0
var _cooldown := 0.0
var _bumped_attempt := false
var _rolled_attempt := false
var _prev_velocity := Vector3.ZERO
var _saved_shape: Shape3D = null
var _hooked: Ilyusha = null
var _exit_spot := Vector3.INF
var _drop_spot := Vector3.INF
var _sound_on := false
var _toast_left := 0.0

func _init() -> void:
	super()
	mode = HideTuning.BARREL
	interaction_id = &"barrel"
	prompt_enter = HideTuning.PROMPT_BARREL_ENTER
	prompt_exit = HideTuning.PROMPT_BARREL_EXIT
	radius = ZONE_RADIUS
	# После Илюши (приоритет 0): столкновения и путь этого кадра уже посчитаны.
	process_physics_priority = 10

func _build_look() -> Node3D:
	var look_root := Node3D.new()
	look_root.name = "BarrelLook"
	var barrel := build_barrel(true)
	barrel.position.y = LENGTH * 0.5
	look_root.add_child(barrel)
	return look_root

## Бочка осью по локальной Y, центр в начале координат: корпус, обручи, крышка с пробкой, пятна; snow — шапка снега.
static func build_barrel(snow: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Barrel"
	var body := CylinderMesh.new()
	body.top_radius = RADIUS
	body.bottom_radius = RADIUS
	body.height = LENGTH
	body.radial_segments = 24
	body.rings = 1
	root.add_child(_mesh(body, _rust_material(), Vector3.ZERO))
	for y in [-0.58, -0.2, 0.2, 0.58]:
		var hoop := CylinderMesh.new()
		hoop.top_radius = RADIUS + 0.014
		hoop.bottom_radius = RADIUS + 0.014
		hoop.height = 0.045 if absf(y) < 0.5 else 0.035
		hoop.radial_segments = 24
		hoop.rings = 1
		root.add_child(_mesh(hoop, Materials.plain(HOOP, 0.75), Vector3(0, y, 0)))
	for top in [1.0, -1.0]:
		var lid := CylinderMesh.new()
		lid.top_radius = RADIUS - 0.02
		lid.bottom_radius = RADIUS - 0.02
		lid.height = 0.02
		lid.radial_segments = 24
		lid.rings = 1
		root.add_child(_mesh(lid, Materials.plain(RUST_DARK, 0.9), Vector3(0, top * (LENGTH * 0.5 + 0.005), 0)))
	var bung := CylinderMesh.new()
	bung.top_radius = 0.035
	bung.bottom_radius = 0.035
	bung.height = 0.03
	bung.radial_segments = 10
	bung.rings = 1
	root.add_child(_mesh(bung, Materials.plain(HOOP, 0.6), Vector3(0.24, LENGTH * 0.5 + 0.02, 0.0)))
	var colors := [RUST_LIGHT, RUST_DARK, PAINT]
	for spot in SPOTS:
		var blot := SphereMesh.new()
		blot.radius = spot[2]
		blot.height = spot[2] * 2.0
		blot.radial_segments = 10
		blot.rings = 5
		var a: float = spot[0]
		var normal := Vector3(cos(a), 0.0, sin(a))
		var instance := _mesh(blot, Materials.plain(colors[spot[3]], 0.95), normal * (RADIUS - 0.01) + Vector3(0, spot[1], 0))
		instance.basis = Basis(Vector3.UP.cross(normal), Vector3.UP * 1.25, normal * 0.12)   # плоская клякса по нормали
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	if snow:
		var cap := CylinderMesh.new()
		cap.top_radius = RADIUS - 0.1
		cap.bottom_radius = RADIUS - 0.015
		cap.height = 0.09
		cap.radial_segments = 20
		cap.rings = 1
		root.add_child(_mesh(cap, Materials.plain(SNOW, 0.95), Vector3(0, LENGTH * 0.5 + 0.055, 0)))
		var lump := SphereMesh.new()
		lump.radius = 0.2
		lump.height = 0.16
		lump.radial_segments = 12
		lump.rings = 6
		root.add_child(_mesh(lump, Materials.plain(SNOW, 0.95), Vector3(-0.08, LENGTH * 0.5 + 0.1, 0.06)))
	return root

static func _mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance

static var _rust: StandardMaterial3D

## Ржавый корпус: пятнистая ржавчина шумом (собственная NoiseTexture2D, без внешних текстур).
static func _rust_material() -> StandardMaterial3D:
	if _rust == null:
		var noise := FastNoiseLite.new()
		noise.seed = 517
		noise.frequency = 0.06
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, RUST_DARK)
		ramp.set_color(1, RUST_LIGHT)
		ramp.add_point(0.5, RUST)
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.seamless = true
		texture.noise = noise
		texture.color_ramp = ramp
		_rust = StandardMaterial3D.new()
		_rust.albedo_texture = texture
		_rust.roughness = 0.85
		_rust.metallic = 0.15
		_rust.uv1_scale = Vector3(2.0, 1.0, 1.0)
	return _rust

# --- вход / выход / сброс ---

func enter() -> bool:
	_hook(player())
	return super()

func _hook(p: Ilyusha) -> void:
	if p == null or _hooked == p:
		return
	_hooked = p
	p.hide_mode_changed.connect(_on_hide_mode_changed)

## Режим Илюши сменился (вход, выход, принудительный сброс при респавне): облик и капсула — по режиму.
func _on_hide_mode_changed(old: StringName, new: StringName) -> void:
	var p := player()
	if p == null:
		return
	if new == HideTuning.BARREL and p.hide_owner == self:
		_set_wide_collider(p, true)
		shell = Node3D.new()
		shell.name = "BarrelShell"
		shell.position.y = RADIUS
		roller = Node3D.new()
		roller.name = "Roll"
		shell.add_child(roller)
		var barrel := build_barrel(false)
		barrel.rotation.z = PI * 0.5   # ось бочки — поперёк движения (локальная X облика Илюши)
		roller.add_child(barrel)
		p.hide_visual.add_child(shell)
		roll_angle = 0.0
		_prev_velocity = p.velocity
	elif old == HideTuning.BARREL:
		_set_wide_collider(p, false)
		shell = null      # ядро освобождает облики hide_visual при переходе в &"none"
		roller = null
		_roll_sound(0.0)

func _set_wide_collider(p: Ilyusha, wide: bool) -> void:
	var node := p.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if node == null:
		return
	if wide and _saved_shape == null:
		_saved_shape = node.shape
		var capsule := CapsuleShape3D.new()
		capsule.radius = COLLIDER_RADIUS
		capsule.height = maxf((_saved_shape as CapsuleShape3D).height if _saved_shape is CapsuleShape3D else 1.5, COLLIDER_RADIUS * 2.0)
		node.shape = capsule
	elif not wide and _saved_shape != null:
		node.shape = _saved_shape
		_saved_shape = null

## Радиус капсулы Илюши сейчас (для тестов): 0,45 в бочке, иначе прежний.
func player_collider_radius() -> float:
	var p := player()
	if p == null:
		return -1.0
	var node := p.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return (node.shape as CapsuleShape3D).radius if node and node.shape is CapsuleShape3D else -1.0

func _exit_allowed(p: Ilyusha) -> bool:
	_drop_spot = Vector3(p.global_position.x, home.y, p.global_position.z)
	_exit_spot = free_exit_spot(p)
	return _exit_spot != Vector3.INF

## Свободная точка рядом с бочкой: сначала по торцам (бочка лежит поперёк хода), затем назад, вперёд, по диагоналям.
## Капсула Илюши с запасом не задевает World|Car, от бочки до точки луч не перекрыт. Vector3.INF — места нет.
func free_exit_spot(p: Ilyusha) -> Vector3:
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = EXIT_CAPSULE_RADIUS
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = EXIT_MASK
	query.exclude = [p.get_rid()]
	var center := Vector3(p.global_position.x, home.y, p.global_position.z)
	var facing := p.visual.rotation.y
	for ring in EXIT_RINGS:
		for turn in [PI * 0.5, -PI * 0.5, PI, 0.0, PI * 0.75, -PI * 0.75, PI * 0.25, -PI * 0.25]:
			var spot := center + Vector3(0, 0, -ring).rotated(Vector3.UP, facing + turn)
			if not Layout.BOUNDS.has_point(Vector2(spot.x, spot.z)):
				continue
			query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.8)
			if not space.intersect_shape(query, 1).is_empty():
				continue
			var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.8, spot + Vector3.UP * 0.8, EXIT_MASK, [p.get_rid()])
			if space.intersect_ray(ray).is_empty():
				return spot
	return Vector3.INF

func _on_exited(p: Ilyusha) -> void:
	_set_wide_collider(p, false)
	_roll_sound(0.0)
	p.place(_exit_spot, p.visual.rotation.y)

## Бочка встаёт там, где была на Илюше (Илюша вылез рядом).
func _place_look_at_player(_p: Ilyusha) -> void:
	if _drop_spot != Vector3.INF:
		global_position = _drop_spot

func _on_reset() -> void:
	var p := player()
	if p and _saved_shape != null:
		_set_wide_collider(p, false)
	_roll_sound(0.0)
	_bumped_attempt = false
	_rolled_attempt = false
	_cooldown = 0.0
	_toast_left = 0.0
	roll_angle = 0.0
	_drop_spot = Vector3.INF
	_exit_spot = Vector3.INF

# --- качение, удар, гэги ---

func _physics_process(delta: float) -> void:
	_clock += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_toast_left = maxf(_toast_left - delta, 0.0)
	var p := player()
	if p == null:
		return
	_hook(p)
	if not is_occupied():
		if _sound_on:
			_roll_sound(0.0)
		return
	roll_angle = -p.hide_travel / RADIUS
	if roller:
		roller.rotation.x = roll_angle
	var real := p.get_real_velocity()
	_roll_sound(Vector2(real.x, real.z).length() / HideTuning.HIDE_SPEED_BARREL)
	_check_bump(p)
	_check_roll_gag(p)
	_prev_velocity = p.velocity

## Удар: стена (нормаль почти горизонтальна) в этом кадре, а до удара бочка шла в неё быстрее BUMP_SPEED.
func _check_bump(p: Ilyusha) -> void:
	for i in p.get_slide_collision_count():
		var normal := p.get_slide_collision(i).get_normal()
		var flat := Vector2(normal.x, normal.z)
		if absf(normal.y) > 0.7 or flat.length() < 0.01:
			continue
		var into := -Vector2(_prev_velocity.x, _prev_velocity.z).dot(flat.normalized())
		if into > BUMP_SPEED:
			_bump(into)
			return

func _bump(speed: float) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = BUMP_COOLDOWN
	bump_count += 1
	bump_times.append(_clock)
	bumped.emit(speed)
	var sound := _sound()
	if sound and sound.has_method(&"barrel_bump"):
		sound.barrel_bump()
	if not _bumped_attempt:
		_bumped_attempt = true
		toast_count += 1
		_toast_left = TOAST_SECONDS
		var w := world()
		if w and w.has_method(&"show_hide_hint"):
			w.show_hide_hint(QuestLines.HIDE_BARREL_BUMP_TOAST, TOAST_SECONDS)
		say_gag(&"C06", [QuestLines.HIDE_BARREL_BUMP_ILYUSHA], GAG_PAGE_SECONDS)   # «Ну всё» — через лимит и очередь

## C05: катится, полицейский видит (геометрия сенсора, без множителя) — раз за попытку.
func _check_roll_gag(p: Ilyusha) -> void:
	if _rolled_attempt or p.is_still():
		return
	var sensor := _officer_sensor()
	if sensor == null or not sensor.enabled or not sensor.in_view:
		return
	_rolled_attempt = true
	if say_gag(&"C05", QuestLines.HIDE_BARREL_ROLL, GAG_PAGE_SECONDS):   # общий лимит попытки и очередь
		roll_gag_count += 1

## Тост «БОЧКА ПРИБЫЛА» сейчас на экране ("" — нет).
func toast_text() -> String:
	return QuestLines.HIDE_BARREL_BUMP_TOAST if _toast_left > 0.0 else ""

func _roll_sound(ratio: float) -> void:
	_sound_on = ratio > 0.02
	var sound := _sound()
	if sound and sound.has_method(&"barrel_roll"):
		sound.barrel_roll(ratio)

func _sound() -> Node:
	var w := world()
	return w.get_node_or_null("SoundDirector") if w else null

func _officer_sensor() -> DetectionSensor:
	var w := world()
	var officer := w.get_node_or_null(OFFICER_PATH) if w else null
	if officer == null:
		return null
	var sensor: Variant = officer.get("sensor")
	return sensor if sensor is DetectionSensor else null

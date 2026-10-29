extends "res://game/stealth/hide_spot.gd"
## EXT-02 D (docs/extension/HIDE_SPOTS.md, разделы 5.1, 7, 11, 14 D): сугроб-укрытие у киоска — Илюша изображает
## элемент благоустройства. Облик — грязный сугроб SIZE из комков (материал валов ART-02, Materials.snow_bank), коллизия
## — коробка SIZE на слое World: честно перекрывает луч сенсоров и не пускает пешком. Сугроб не двигается.
## E — зарыться: Илюша на Layout.HIDE_SNOWDRIFT_ANCHOR внутри сугроба (с ним — исключение коллизий, у камеры —
## исключение пружины), спрайт скрыт (Ilyusha), снаружи торчит ботинок (player.hide_visual), всплеск снежной пыли.
## E — вылезти: только если Layout.HIDE_SNOWDRIFT_EXIT свободна (капсула, World|Car — как DemoWorld._free_exit_spot),
## иначе «ВЫХОД ЗАНЯТ» (предок) и Илюша внутри; при выходе — тост QuestLines.HIDE_SNOW_TOAST в строке подсказки
## (DemoWorld.show_hide_hint, TOAST_SECONDS). Сброс режима в обход выхода (DemoWorld.reset_hide → force_hide_mode:
## провал, респавн, «Сбросить автомобиль») — Илюша извлекается на EXIT (занята — на соседнюю свободную точку), без тоста.
## Гэг C04 (раздел 11) — субтитрами SoundDirector.show_gag, раз за попытку (между reset()): Илюша внутри, полицейский
## ближе GAG_RANGE и корпус смотрит на сугроб точнее GAG_ANGLE_DEG.

const Layout = preload("res://game/world/layout.gd")
const Materials = preload("res://game/world/materials.gd")
const DUST_SHADER := preload("res://game/vehicles/slush_spray.gdshader")

const SIZE := Vector3(2.4, 1.4, 1.6)    # ширина (x) × высота × глубина (z), м — коллизия World
const ZONE_RADIUS := 2.5                # зона E вокруг сугроба (+0,5 м щупа Илюши)
## Комки поверх основного купола: [центр, размер] — рваный верх, как у валов после уборки.
const LUMPS := [
	[Vector3(-0.62, 0.0, 0.18), Vector3(1.2, 1.15, 1.1)],
	[Vector3(0.70, 0.0, -0.22), Vector3(1.0, 0.95, 1.0)],
	[Vector3(-0.15, 1.05, -0.2), Vector3(0.7, 0.32, 0.55)],
	[Vector3(1.05, 0.0, 0.45), Vector3(0.55, 0.35, 0.5)],
]
const BOOT_COLOR := Color("3a3436")     # ботинок и подошва — как у Илюши (tools/generate_characters.py: BOOT, SOLE)
const SOLE_COLOR := Color("1c1819")
const DUST_COLOR := Color(0.86, 0.87, 0.90)
## Выход занят — куда ещё можно извлечь Илюшу при принудительном сбросе (от центра сугроба).
const FORCED_EXITS := [Vector3(0, 0, 2.3), Vector3(2.3, 0, 0), Vector3(-2.3, 0, 0)]

const GAG_RANGE := 12.0
const GAG_ANGLE_DEG := 40.0
const GAG_PAGE_SECONDS := 2.5
const TOAST_SECONDS := 2.5
const OFFICER_PATH := "LevelGeometry/Patrols/Officer"

## Коллизия сугроба (слой World).
var drift: StaticBody3D
## Всплеск снежной пыли при входе и выходе.
var dust: CPUParticles3D
## Ботинок на Илюше (в player.hide_visual), пока он внутри; иначе null.
var boot: Node3D = null
## Счётчики для тестов: сколько раз показан гэг C04 и тост выхода (за всё время).
var gag_count := 0
var toast_count := 0

var _inside := false
var _leaving := false
var _gag_done := false

func _init() -> void:
	super()
	mode = HideTuning.SNOWDRIFT
	prompt_enter = HideTuning.PROMPT_SNOWDRIFT_ENTER
	prompt_exit = HideTuning.PROMPT_SNOWDRIFT_EXIT
	interaction_id = &"snowdrift"
	radius = ZONE_RADIUS

func _ready() -> void:
	super._ready()
	drift = _build_drift()
	add_child(drift)
	dust = _build_dust()
	add_child(dust)

## Илюша внутри этого сугроба.
func is_inside() -> bool:
	return _inside

# --- облик ---

func _build_drift() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "SnowdriftBody"
	body.collision_layer = 1   # World: перекрывает луч сенсоров (раздел 5.1)
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = SIZE.y * 0.5
	body.add_child(collider)
	var material := Materials.snow_bank()
	body.add_child(_dome(Vector3.ZERO, SIZE, material, 24, 10))
	for lump in LUMPS:
		body.add_child(_dome(lump[0], lump[1], material, 14, 6))
	return body

## Купол: верхняя половина эллипсоида size (ширина, высота, глубина), основание — at.
static func _dome(at: Vector3, size: Vector3, material: Material, segments: int, rings: int) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = segments
	sphere.rings = rings
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.scale = Vector3(size.x * 1.05, size.y * 2.0, size.z * 1.05)
	mesh.position = at
	return mesh

## Ботинок подошвой вверх над макушкой сугроба: голенище из снега, носок вбок (в осях hide_visual).
static func _build_boot() -> Node3D:
	var root := Node3D.new()
	root.name = "SnowdriftBoot"
	root.position = Vector3(0.3, 1.18, 0.12)
	root.rotation = Vector3(0.0, 0.5, 0.22)
	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.075
	cylinder.bottom_radius = 0.085
	cylinder.height = 0.34
	shaft.mesh = cylinder
	shaft.material_override = _plain(BOOT_COLOR)
	shaft.position.y = 0.17
	root.add_child(shaft)
	var foot := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.14, 0.12, 0.3)
	foot.mesh = box
	foot.material_override = _plain(BOOT_COLOR)
	foot.position = Vector3(0.0, 0.36, -0.08)
	root.add_child(foot)
	var sole := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(0.15, 0.035, 0.32)
	sole.mesh = plate
	sole.material_override = _plain(SOLE_COLOR)
	sole.position = Vector3(0.0, 0.435, -0.08)
	root.add_child(sole)
	return root

static func _plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

## Снежная пыль — как брызги каши PLAY-03 (тот же шейдер-билборд), один выброс на вход/выход.
func _build_dust() -> CPUParticles3D:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.85))
	fade.set_color(1, Color(1, 1, 1, 0.0))
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
	var look_material := ShaderMaterial.new()
	look_material.shader = DUST_SHADER
	look_material.set_shader_parameter("albedo", DUST_COLOR)
	look_material.set_shader_parameter("texture_albedo", dot)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.material = look_material
	var emitter := CPUParticles3D.new()
	emitter.name = "SnowDust"
	emitter.one_shot = true
	emitter.emitting = false
	emitter.amount = 48
	emitter.lifetime = 0.9
	emitter.explosiveness = 0.85
	emitter.mesh = quad
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emitter.emission_sphere_radius = 0.7
	emitter.direction = Vector3.UP
	emitter.spread = 70.0
	emitter.initial_velocity_min = 1.2
	emitter.initial_velocity_max = 2.8
	emitter.gravity = Vector3(0, -5.0, 0)
	emitter.damping_min = 0.8
	emitter.damping_max = 1.6
	emitter.scale_amount_min = 0.6
	emitter.scale_amount_max = 1.5
	emitter.color_ramp = fade
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.position = Vector3(0, SIZE.y * 0.75, 0)
	return emitter

func _burst() -> void:
	if dust:
		dust.restart()

# --- вход, выход, сброс ---

func exit() -> bool:
	_leaving = true
	var ok := super.exit()
	_leaving = false
	return ok

func _on_entered(p: Ilyusha) -> void:
	_inside = true
	if not p.hide_mode_changed.is_connected(_on_hide_mode_changed):
		p.hide_mode_changed.connect(_on_hide_mode_changed)
	p.add_collision_exception_with(drift)
	var rig := _camera_rig()
	if rig:
		rig.arm.add_excluded_object(drift.get_rid())
	var to_exit := Layout.HIDE_SNOWDRIFT_EXIT - Layout.HIDE_SNOWDRIFT_ANCHOR
	p.place(Layout.HIDE_SNOWDRIFT_ANCHOR, atan2(-to_exit.x, -to_exit.z))
	if is_instance_valid(boot):
		boot.queue_free()
	boot = _build_boot()
	p.hide_visual.add_child(boot)
	_burst()

func _exit_allowed(_p: Ilyusha) -> bool:
	return _exit_free(Layout.HIDE_SNOWDRIFT_EXIT)

func _on_exited(p: Ilyusha) -> void:
	_release(p, true)
	toast_count += 1
	var w := world()
	if w and w.has_method("show_hide_hint"):
		w.show_hide_hint(QuestLines.HIDE_SNOW_TOAST, TOAST_SECONDS)

## Режим сменился: выход через exit() — обычный, иначе принудительный сброс (DemoWorld.reset_hide).
func _on_hide_mode_changed(old: StringName, new: StringName) -> void:
	if _inside and old == HideTuning.SNOWDRIFT and new != HideTuning.SNOWDRIFT:
		var p := player()
		if p:
			_release(p, _leaving)

func _on_reset() -> void:
	if _inside:
		var p := player()
		if p and is_occupied():
			p.force_hide_mode(HideTuning.NONE)   # сброс без reset_hide: обработчик режима извлечёт Илюшу
		elif p:
			_release(p, false)
	_inside = false
	_gag_done = false

## Сугроб не двигается: после выхода остаётся на home.
func _place_look_at_player(_p: Ilyusha) -> void:
	pass

## Извлечь Илюшу: снять исключения коллизии и камеры, поставить на EXIT (при принудительном сбросе — на первую
## свободную точку вокруг сугроба). Повторный вызов ничего не делает.
func _release(p: Ilyusha, normal: bool) -> void:
	if not _inside:
		return
	_inside = false
	boot = null   # Ilyusha очищает hide_visual при переходе в &"none"
	if is_instance_valid(drift):
		p.remove_collision_exception_with(drift)
		var rig := _camera_rig()
		if rig:
			rig.arm.remove_excluded_object(drift.get_rid())
	var spot := Layout.HIDE_SNOWDRIFT_EXIT
	if not normal and not _exit_free(spot):
		for offset in FORCED_EXITS:
			var candidate: Vector3 = Layout.HIDE_SNOWDRIFT_ANCHOR + offset
			if _exit_free(candidate):
				spot = candidate
				break
	var away := spot - Layout.HIDE_SNOWDRIFT_ANCHOR
	p.place(spot, atan2(-away.x, -away.z))
	if normal:
		_burst()

## Точка свободна для Илюши: капсула 0,4 × 1,5 м, World | Car (как DemoWorld._free_exit_spot), сам сугроб не в счёт.
func _exit_free(point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | 4 | 64   # DRIVE-02: и валы снега (слой 7), как раньше
	var exclude: Array[RID] = []
	if drift:
		exclude.append(drift.get_rid())
	var p := player()
	if p:
		exclude.append(p.get_rid())
	query.exclude = exclude
	query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, 0.0, point.z) + Vector3.UP * 0.8)
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _camera_rig() -> CameraRig:
	var w := world()
	if w == null:
		return null
	var rig: Variant = w.get("camera_rig")
	return rig if rig is CameraRig else null

# --- гэг C04 ---

func _physics_process(_delta: float) -> void:
	if not _inside or _gag_done:
		return
	var w := world()
	if w == null or w.is_stealth_failing():
		return
	if officer_looks_at_drift():
		_gag_done = true
		if say_gag(&"C04", QuestLines.HIDE_SNOW_LOOK, GAG_PAGE_SECONDS):   # общий лимит попытки и очередь
			gag_count += 1

## Полицейский ближе GAG_RANGE, и корпус (его сенсор) смотрит на сугроб точнее GAG_ANGLE_DEG.
func officer_looks_at_drift() -> bool:
	var w := world()
	var officer: Node3D = w.get_node_or_null(OFFICER_PATH) if w else null
	if officer == null:
		return false
	var sensor: Variant = officer.get("sensor")
	var basis: Basis = (sensor as Node3D).global_basis if sensor is Node3D else officer.global_basis
	var to := global_position - officer.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() >= GAG_RANGE:
		return false
	var forward := -basis.z
	var heading := Vector2(forward.x, forward.z)
	if heading.length() < 0.001 or flat.length() < 0.01:
		return false
	return rad_to_deg(absf(heading.angle_to(flat))) < GAG_ANGLE_DEG

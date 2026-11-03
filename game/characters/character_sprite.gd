class_name CharacterSprite
extends Node3D
## Appearance adapter: skinned uniforms plus opt-in original City N civilians.
## Ракурс — по углу между взглядом персонажа (-Z родителя) и камерой: front, back или side
## (side нарисован лицом вправо, второй бок — зеркало). Кадры ходьбы — по пройденному пути.
## Рисунки: assets/art/characters/<character>_<view>_<idle|walkN>.svg (tools/generate_characters.py).

const DIR := "res://assets/art/characters/"
const UniformVisual = preload("res://game/characters/uniform_visual.gd")
const Catalog = preload("res://game/characters/character_catalog.gd")
const BonePoseBuffer = preload("res://game/characters/bone_pose_buffer.gd")
const CANVAS_HEIGHT := 600.0  # условные единицы холста; ноги стоят на 590
const FEET_Y := 590.0
const FRONT_DOT := 0.55       # cos ≈ 57°: ближе к оси — лицом или спиной, иначе бок
const WALK_SPEED_MIN := 0.4   # м/с: медленнее — стойка

@export var character := "ilyusha"
## Consumer-local fallback; shared NPC and vehicle geometry switches stay intact.
@export var force_sprite_2d := false
## ART-09: рисунок задаётся до _ready, независимо от квестовой роли и interaction_id.
## Пустое значение сохраняет прежний облик. Имена ограничены готовыми комплектами.
const APPEARANCES: Array[String] = ["police_long", "police_round", "guard_alt"]
@export var appearance := ""
@export var height_m := 2.4     # высота холста в метрах
@export var walk_stride := 0.32 # метров на кадр ходьбы
@export var shadow_size := Vector2(1.1, 0.75)
## Множитель цвета: тонмаппер Filmic с экспозицией 1,1 и glow выбеливают плоскую заливку,
## подобран по кадрам builds/screenshots/art01/ под палитру паспорта.
@export var tone := 0.72
## Тёплый оттенок поверх тона: светлая кожа и платье NPC в холодном свете сцены серели (сверка ART-01, P3).
@export var tint := Color.WHITE

## Smooth the hero pose between fixed physics steps.
@export var interpolate_bone_pose := false

var sprite: Sprite3D
var uniform_visual: Node3D
var look_material: StandardMaterial3D
var view := &"front"
var frame := -1  # -1 — стойка, 0..3 — ходьба
var _idle := {}
var _walk := {}
var _distance := 0.0
var _last := Vector3.INF
var _actor: Node3D
var _controlled := false
var _velocity := Vector3.ZERO
var _grounded := true
var _pose_mode := &"locomotion"
var _vertical_speed := 0.0
var _action_phase := 0.0

var _bone_pose_buffer = BonePoseBuffer.new()

func _notification(what: int) -> void:
	if _bone_pose_buffer == null:
		return
	if what == NOTIFICATION_RESET_PHYSICS_INTERPOLATION:
		_clear_bone_interpolation()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _uses_locomotion() and is_inside_tree() and not is_visible_in_tree():
		reset_pose()

func resolved_character() -> String:
	return appearance if appearance in APPEARANCES else character

func _ready() -> void:
	_actor = get_parent().get_parent() as Node3D if get_parent() != null else null
	var drawing := resolved_character()
	if not force_sprite_2d and UniformVisual.use_for(drawing):
		uniform_visual = UniformVisual.new()
		uniform_visual.name = "UniformVisual"
		uniform_visual.configure(drawing, _model_visible_height(drawing), tint)
		add_child(uniform_visual)
		if _uses_locomotion():
			uniform_visual.prepare_locomotion()
		add_child(_shadow())
		return
	for v in [&"front", &"back", &"side"]:
		_idle[v] = load("%s%s_%s_idle.svg" % [DIR, drawing, v])
		var frames: Array[Texture2D] = []
		for k in 4:
			var path := "%s%s_%s_walk%d.svg" % [DIR, drawing, v, k]
			if ResourceLoader.exists(path):
				frames.append(load(path))
		_walk[v] = frames
	var texture: Texture2D = _idle[&"front"]
	sprite = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Свой материал: без тумана (персонаж читается на дистанции, как на кадрах 01–10) и с поправкой тона.
	look_material = StandardMaterial3D.new()
	look_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	look_material.billboard_keep_scale = true
	look_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	look_material.alpha_scissor_threshold = 0.5
	look_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	look_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	look_material.disable_fog = true
	look_material.albedo_color = Color(tone * tint.r, tone * tint.g, tone * tint.b)
	look_material.albedo_texture = texture
	sprite.material_override = look_material
	sprite.pixel_size = height_m / texture.get_height()
	# Спрайт центрирован: поднять так, чтобы линия ног холста (y=590) легла на землю.
	sprite.position.y = height_m * (0.5 - (CANVAS_HEIGHT - FEET_Y) / CANVAS_HEIGHT)
	add_child(sprite)
	add_child(_shadow())

func _process(_delta: float) -> void:
	if uniform_visual != null:
		if _uses_manual_bone_interpolation():
			if is_visible_in_tree() and _pose_mode != &"hidden":
				_bone_pose_buffer.apply(uniform_visual.skeleton, Engine.get_physics_interpolation_fraction())
			else:
				_bone_pose_buffer.clear()
		return
	if not is_visible_in_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if not camera or not sprite:
		return
	var forward := -global_basis.z
	forward.y = 0.0
	var to_camera := camera.global_position - global_position
	to_camera.y = 0.0
	if forward.length_squared() < 0.0001 or to_camera.length_squared() < 0.0001:
		return
	var facing := forward.normalized().dot(to_camera.normalized())
	if facing > FRONT_DOT:
		view = &"front"
	elif facing < -FRONT_DOT:
		view = &"back"
	else:
		view = &"side"
	# Бок нарисован лицом вправо: зеркалим, если персонаж смотрит влево на экране.
	sprite.flip_h = view == &"side" and forward.dot(camera.global_basis.x) < 0.0
	var frames: Array[Texture2D] = _walk[view]
	var texture: Texture2D = frames[frame] if frame >= 0 and frame < frames.size() else _idle[view]
	if sprite.texture != texture:
		sprite.texture = texture
		look_material.albedo_texture = texture

## Путь копится на шаге физики: в _process при physics_interpolation положение между шагами
## не меняется, и на 120+ к/с ходьба сбрасывалась бы в стойку (ревью ART-01, P1).
func _physics_process(delta: float) -> void:
	if _uses_manual_bone_interpolation():
		_bone_pose_buffer.restore_current(uniform_visual.skeleton)
	# Visual offsets (punches, work, breathing) are not travelled ground distance.
	var at := _actor.global_position if is_instance_valid(_actor) else global_position
	var moved := 0.0
	if _last != Vector3.INF:
		moved = Vector2(at.x - _last.x, at.z - _last.z).length()
	_last = at
	var teleport := moved > 1.0
	if teleport:  # телепорт (place, перезапуск) — не шаг
		moved = 0.0
		_distance = 0.0
		if uniform_visual != null:
			uniform_visual.reset_pose()
		_bone_pose_buffer.clear()
	var velocity := _velocity if _controlled else Vector3.ZERO
	if not _controlled and delta > 0.0 and not teleport:
		velocity = (at - _last_root) / delta if _last_root != Vector3.INF else Vector3.ZERO
	if teleport:
		velocity = Vector3.ZERO
	_last_root = at
	# SVG cadence follows measured planar displacement, never desired input or falling.
	var sprite_moving := delta > 0.0 and moved / delta >= WALK_SPEED_MIN and _grounded and _pose_mode == &"locomotion" and is_visible_in_tree()
	var moving := sprite_moving if sprite != null else velocity.length() >= WALK_SPEED_MIN and not teleport
	if moving:
		_distance += moved if sprite != null else Vector2(velocity.x, velocity.z).length() * delta
		frame = int(_distance / walk_stride) % 4
	else:
		frame = -1
	if uniform_visual != null:
		var pose_mode := _pose_mode if _controlled else &"locomotion"
		if not is_visible_in_tree():
			pose_mode = &"hidden"
		uniform_visual.update_locomotion(velocity, _grounded, pose_mode, delta, _vertical_speed, _action_phase)
		if _uses_manual_bone_interpolation():
			if pose_mode == &"hidden":
				_bone_pose_buffer.clear()
			else:
				_bone_pose_buffer.capture(uniform_visual.skeleton)

var _last_root := Vector3.INF

## Parent publishes measured root motion, never desired input or a visual offset.
## Retained samples let sparse NPC updates keep their cadence between actor ticks.
func submit_locomotion(world_velocity: Vector3, grounded: bool, mode: StringName = &"locomotion", vertical_speed := 0.0, action_phase := 0.0) -> void:
	_controlled = true
	_velocity = world_velocity
	_grounded = grounded
	_pose_mode = mode
	_vertical_speed = vertical_speed
	_action_phase = action_phase

func reset_pose() -> void:
	if sprite != null:
		_distance = 0.0
		frame = -1
		_last = Vector3.INF
		_last_root = Vector3.INF
		_velocity = Vector3.ZERO
	_bone_pose_buffer.clear()
	if uniform_visual != null:
		uniform_visual.reset_pose()

func _clear_bone_interpolation() -> void:
	if sprite != null:
		reset_pose()
	if uniform_visual != null and uniform_visual.supports_manual_bone_interpolation():
		_bone_pose_buffer.restore_current(uniform_visual.skeleton)
	elif uniform_visual != null and uniform_visual.imported_hero != null:
		uniform_visual.reset_pose()
	_bone_pose_buffer.clear()

func _uses_manual_bone_interpolation() -> bool:
	return uniform_visual != null and interpolate_bone_pose and _uses_locomotion() and uniform_visual.supports_manual_bone_interpolation()

func _model_visible_height(drawing: String) -> float:
	return height_m * Catalog.visible_height_ratio(drawing)

func _uses_locomotion() -> bool:
	return true

func uses_uniform_3d() -> bool:
	return uniform_visual != null

func set_walk_speed(speed: float) -> void:
	if speed == 0.0:
		_bone_pose_buffer.clear()
	if uniform_visual != null:
		uniform_visual.set_walk_speed(speed)

func build_uniform_xray() -> MeshInstance3D:
	return uniform_visual.build_xray() if uniform_visual != null else null

func _shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.18 if uniform_visual != null else 0.45))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var mesh := PlaneMesh.new()
	mesh.size = shadow_size
	mesh.material = material
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = mesh
	shadow.position.y = 0.03
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shadow

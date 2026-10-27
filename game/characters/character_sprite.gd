class_name CharacterSprite
extends Node3D
## Облик персонажа ШКЯ (ART-01): плоский рисунок, всегда повёрнутый к камере (billboard по Y).
## Ракурс — по углу между взглядом персонажа (-Z родителя) и камерой: front, back или side
## (side нарисован лицом вправо, второй бок — зеркало). Кадры ходьбы — по пройденному пути.
## Рисунки: assets/art/characters/<character>_<view>_<idle|walkN>.svg (tools/generate_characters.py).

const DIR := "res://assets/art/characters/"
const CANVAS_HEIGHT := 600.0  # условные единицы холста; ноги стоят на 590
const FEET_Y := 590.0
const FRONT_DOT := 0.55       # cos ≈ 57°: ближе к оси — лицом или спиной, иначе бок
const WALK_SPEED_MIN := 0.4   # м/с: медленнее — стойка

@export var character := "ilyusha"
@export var height_m := 2.4     # высота холста в метрах
@export var walk_stride := 0.32 # метров на кадр ходьбы
@export var shadow_size := Vector2(1.1, 0.75)
## Множитель цвета: тонмаппер Filmic с экспозицией 1,1 и glow выбеливают плоскую заливку,
## подобран по кадрам builds/screenshots/art01/ под палитру паспорта.
@export var tone := 0.72

var sprite: Sprite3D
var material: StandardMaterial3D
var view := &"front"
var frame := -1  # -1 — стойка, 0..3 — ходьба
var _idle := {}
var _walk := {}
var _distance := 0.0
var _last := Vector3.INF

func _ready() -> void:
	for v in [&"front", &"back", &"side"]:
		_idle[v] = load("%s%s_%s_idle.svg" % [DIR, character, v])
		var frames: Array[Texture2D] = []
		for k in 4:
			var path := "%s%s_%s_walk%d.svg" % [DIR, character, v, k]
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
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.disable_fog = true
	material.albedo_color = Color(tone, tone, tone)
	material.albedo_texture = texture
	sprite.material_override = material
	sprite.pixel_size = height_m / texture.get_height()
	# Спрайт центрирован: поднять так, чтобы линия ног холста (y=590) легла на землю.
	sprite.position.y = height_m * (0.5 - (CANVAS_HEIGHT - FEET_Y) / CANVAS_HEIGHT)
	add_child(sprite)
	add_child(_shadow())

func _process(delta: float) -> void:
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
	_update_walk(delta)
	var frames: Array[Texture2D] = _walk[view]
	var texture: Texture2D = frames[frame] if frame >= 0 and frame < frames.size() else _idle[view]
	if sprite.texture != texture:
		sprite.texture = texture
		material.albedo_texture = texture

func _update_walk(delta: float) -> void:
	var position := global_position
	var moved := 0.0
	if _last != Vector3.INF:
		moved = Vector2(position.x - _last.x, position.z - _last.z).length()
	_last = position
	if moved > 1.0:  # телепорт (place, перезапуск) — не шаг
		moved = 0.0
	if delta > 0.0 and moved / delta >= WALK_SPEED_MIN and not (_walk[view] as Array).is_empty():
		_distance += moved
		frame = int(_distance / walk_stride) % 4
	else:
		_distance = 0.0
		frame = -1

func _shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.45))
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

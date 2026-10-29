extends Node3D
## NPC-заглушка (Бабка, продавщица): фигура, твёрдое тело и зона Interactable.
## Облик ШКЯ — объёмный CharacterBody3DLook (CHAR3D-02) или CharacterSprite (ART-01, --sprites); диалоги и маркеры — QUEST-01.
## POLISH-02: облик «дышит» (масштаб по высоте ±1,5 %) и на время диалога поворачивается к собеседнику
## (look_at_target / stop_looking — вызывает QuestFlow). Поворачивается только облик, не узел и не зона E.

const CharacterSpriteScript = preload("res://game/characters/character_sprite.gd")
const CharacterBody3DLookScript = preload("res://game/characters/character_body3d.gd")
## CHAR3D-02: true — объёмный облик (CharacterBody3DLook) для рисунков с паспортом (по умолчанию — все персонажи);
## запасной путь — спрайт: аргумент запуска --sprites или false здесь.
const LOOK_3D := true
const InteractableScript = preload("res://game/interaction/interactable.gd")

@export var interaction_id: StringName
@export var character := "babka"
@export var height_m := 2.17  # Бабка крупнее Илюши (паспорт ART-01); ×0,83 вместе с Илюшей (PLAY-02)
@export var tint := Color(1.06, 1.02, 0.88)  # тёплее, как лицо и платье Бабки на концептах 02, 10
@export var facing_yaw := 0.0  # поворот облика относительно узла (зона взаимодействия не поворачивается)
@export var solid := true
@export var interact_radius := 2.5
@export var body_radius := 0.7  # по силуэту облика ART-01: Бабка-«гора» ≈1,5 м в ширину
@export var interact_offset := Vector3.ZERO

const BREATH := 0.015          # ±1,5 % по высоте
const BREATH_PERIOD := 3.4     # с на вдох и выдох
const TURN_SPEED := 6.0        # скорость доворота облика, 1/с

var interactable: Interactable
var visual: Node3D
var _look_target: Node3D
var _breath_time := 0.0

func _ready() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	visual.rotation.y = facing_yaw
	var look = CharacterBody3DLookScript.new() if CharacterBody3DLookScript.wanted(LOOK_3D, character) else CharacterSpriteScript.new()
	look.name = "Look"
	look.character = character
	look.height_m = height_m
	look.tint = tint
	visual.add_child(look)
	add_child(visual)
	if solid:
		var shape := CapsuleShape3D.new()
		shape.radius = body_radius
		shape.height = 1.8
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = 0.9
		var static_body := StaticBody3D.new()
		static_body.name = "Body"
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		static_body.add_child(collider)
		add_child(static_body)
	interactable = InteractableScript.new()
	interactable.name = "Interactable"
	interactable.interaction_id = interaction_id
	interactable.radius = interact_radius
	interactable.position = interact_offset
	add_child(interactable)
	# Разная фаза у Бабки и продавщицы — дышат не в такт.
	_breath_time = fposmod(float(String(interaction_id).hash() % 1000) * 0.0137, BREATH_PERIOD)

func _process(delta: float) -> void:
	_breath_time += delta
	var s := sin(_breath_time * TAU / BREATH_PERIOD)
	visual.scale = Vector3(1.0 - s * BREATH * 0.5, 1.0 + s * BREATH, 1.0)
	var wanted := facing_yaw
	if is_instance_valid(_look_target):
		var to := _look_target.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.3:
			# −Z облика смотрит на цель; угол в осях узла.
			wanted = atan2(-to.x, -to.z) - global_rotation.y
	visual.rotation.y = lerp_angle(visual.rotation.y, wanted, 1.0 - exp(-TURN_SPEED * delta))

## Повернуться к target (Илюша) и держать взгляд, пока не вызван stop_looking().
func look_at_target(target: Node3D) -> void:
	_look_target = target

func stop_looking() -> void:
	_look_target = null

extends Node3D
## NPC-заглушка (Бабка, продавщица): фигура, твёрдое тело и зона Interactable.
## Облик ШКЯ — CharacterSprite (ART-01); диалоги и маркеры — QUEST-01.

const CharacterSpriteScript = preload("res://game/characters/character_sprite.gd")
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

var interactable: Interactable

func _ready() -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.rotation.y = facing_yaw
	var look: CharacterSprite = CharacterSpriteScript.new()
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

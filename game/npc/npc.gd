extends Node3D
## NPC-заглушка (Бабка, продавщица): фигура, твёрдое тело и зона Interactable.
## Облик ШКЯ делает ART-01; диалоги и маркеры — QUEST-01.

const Greybox = preload("res://game/world/greybox.gd")
const InteractableScript = preload("res://game/interaction/interactable.gd")

@export var interaction_id: StringName
@export var body_color := Color(0.35, 0.45, 0.20)
@export var head_color := Color(0.93, 0.90, 0.75)
@export var head_radius := 0.45
@export var hat_color := Color(0.45, 0.48, 0.20)
@export var solid := true
@export var interact_radius := 2.5
@export var interact_offset := Vector3.ZERO

var interactable: Interactable

func _ready() -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	var body := Greybox.mesh_capsule(0.45, 1.5, body_color)
	body.position.y = 0.75
	visual.add_child(body)
	var collar := Greybox.mesh_cylinder(0.32, 0.42, 0.12, Color(0.95, 0.95, 0.95))
	collar.position.y = 1.45
	visual.add_child(collar)
	var head := Greybox.mesh_sphere(head_radius, head_color)
	head.position.y = 1.5 + head_radius
	visual.add_child(head)
	var hat := Greybox.mesh_cylinder(head_radius * 0.85, head_radius * 1.02, 0.25, hat_color)
	hat.position.y = 1.5 + head_radius * 1.6
	visual.add_child(hat)
	add_child(visual)
	if solid:
		var shape := CapsuleShape3D.new()
		shape.radius = 0.45
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

class_name Interactable
extends Area3D
## C3 — зона взаимодействия по E. Текст и доступность выставляет мир по MissionDirector.prompt_for(id).

signal interacted(actor: Node)

@export var interaction_id: StringName
@export var prompt := ""
@export var enabled := true
@export var radius := 2.5

func _ready() -> void:
	collision_layer = 8   # Interact
	collision_mask = 0
	monitoring = false
	monitorable = true
	if get_child_count() == 0:
		var shape := SphereShape3D.new()
		shape.radius = radius
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = 1.0
		add_child(collider)

func interact(actor: Node) -> void:
	if enabled:
		interacted.emit(actor)

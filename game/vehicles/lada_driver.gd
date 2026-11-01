extends "res://game/characters/character_sprite.gd"
## Visual-only occupant shared by Lada and trolley, with explicit consumer poses.
## Legacy cropped canvas remains available for the previous visual branch.
const CUT_Y := 440.0
const LADA_VISIBLE_HEIGHT := 1.45
const LADA_FLOOR := 0.32
const LADA_GRIPS := [Vector3(-0.18, 1.10, -0.50), Vector3(-0.54, 1.10, -0.50)]
const TROLLEY_GRIPS := [Vector3(-0.38, 1.97, -5.35), Vector3(-0.82, 1.97, -5.35)]
@export var occupant_profile: StringName = &"lada"
@export var occupant_floor_y := LADA_FLOOR

static func uses_3d() -> bool:
	return UniformVisual.civilians_enabled()

func _model_visible_height(drawing: String) -> float:
	return LADA_VISIBLE_HEIGHT if occupant_profile == &"lada" else super._model_visible_height(drawing)

func _uses_locomotion() -> bool:
	return false

func _ready() -> void:
	super._ready()
	var shadow := get_node_or_null("Shadow")
	if shadow:
		remove_child(shadow)
		shadow.free()
	set_physics_process(false)
	frame = -1
	if uniform_visual != null:
		uniform_visual.set_occupant_pose(occupant_profile)
		uniform_visual.position.y = occupant_floor_y - position.y - uniform_visual.occupant_sole_height()
		if occupant_profile in [&"lada", &"trolley_driver"]:
			var grips: Array = LADA_GRIPS if occupant_profile == &"lada" else TROLLEY_GRIPS
			var frame_3d := get_parent() as Node3D
			uniform_visual.reach_hands(uniform_visual.model.to_local(frame_3d.to_global(grips[0])), uniform_visual.model.to_local(frame_3d.to_global(grips[1])))
		return
	var texture: Texture2D = sprite.texture
	var px_per_unit := texture.get_height() / CANVAS_HEIGHT
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0.0, 0.0, texture.get_width(), CUT_Y * px_per_unit)
	sprite.position.y = (FEET_Y - CUT_Y * 0.5) * height_m / CANVAS_HEIGHT

func _physics_process(_delta: float) -> void:
	pass

func set_lod(distance: float, margin: float = 4.0) -> void:
	if uniform_visual != null:
		uniform_visual.set_lod(distance, margin)
	else:
		sprite.visibility_range_end = distance
		sprite.visibility_range_end_margin = margin

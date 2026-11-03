extends "res://game/characters/character_sprite.gd"
## Visual-only occupant shared by Lada and trolley, with explicit consumer poses.
## Legacy cropped canvas remains available for the previous visual branch.
const CUT_Y := 440.0
const LADA_CUT_Y := 370.0
const LADA_CANVAS_TOP_Y := 1.42
const LADA_VISIBLE_HEIGHT := Catalog.ILYUSHA_VISIBLE_HEIGHT_M
const LADA_FLOOR := 0.32
const LADA_SEAT_X := -0.285
const LADA_HIP_Z := -0.19
const LADA_STEERING_X := LADA_SEAT_X - 0.015
const LADA_GRIPS := [Vector3(LADA_STEERING_X - 0.18, 1.10, -0.50), Vector3(LADA_STEERING_X + 0.18, 1.10, -0.50)]
const Dimensions = preload("res://game/vehicles/vehicle_dimensions.gd")
# Эргономика модели: руль на 80см над подтверждённым полом, не паспортная высота руля.
const TROLLEY_STEERING_AT := Vector3(-0.60, Dimensions.INTERIOR_SPECS[&"ziu9"]["floor_height_m"] + 0.80, -5.35)
const TROLLEY_GRIPS := [TROLLEY_STEERING_AT + Vector3(0.22, 0, 0), TROLLEY_STEERING_AT - Vector3(0.22, 0, 0)]
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
		var frame_3d := get_parent() as Node3D
		var imported_lada := occupant_profile == &"lada" and uniform_visual.imported_hero != null
		if imported_lada:
			var actual_skeleton: Skeleton3D = uniform_visual.skeleton
			var hip_index: int = uniform_visual.bone_index("Hips")
			var hip := frame_3d.to_local(actual_skeleton.to_global(actual_skeleton.get_bone_global_pose(hip_index).origin))
			uniform_visual.global_position += frame_3d.global_basis * Vector3(0, 0, LADA_HIP_Z - hip.z)
		if occupant_profile in [&"lada", &"trolley_driver"]:
			var grips: Array = LADA_GRIPS if occupant_profile == &"lada" else TROLLEY_GRIPS
			if occupant_profile == &"lada" and not imported_lada:
				grips = [LADA_GRIPS[1], LADA_GRIPS[0]]
			uniform_visual.reach_hands(uniform_visual.model.to_local(frame_3d.to_global(grips[0])), uniform_visual.model.to_local(frame_3d.to_global(grips[1])))
		return
	var texture: Texture2D = sprite.texture
	var px_per_unit := texture.get_height() / CANVAS_HEIGHT
	sprite.region_enabled = true
	var crop_y := LADA_CUT_Y if occupant_profile == &"lada" else CUT_Y
	sprite.region_rect = Rect2(0.0, 0.0, texture.get_width(), crop_y * px_per_unit)
	sprite.position.y = (FEET_Y - CUT_Y * 0.5) * height_m / CANVAS_HEIGHT
	if occupant_profile == &"lada":
		# Place the uncropped head below the roof without shrinking the canvas.
		sprite.position.y = LADA_CANVAS_TOP_Y - position.y - crop_y * height_m / CANVAS_HEIGHT * 0.5

func _physics_process(_delta: float) -> void:
	pass

func set_lod(distance: float, margin: float = 4.0) -> void:
	if uniform_visual != null:
		uniform_visual.set_lod(distance, margin)
	else:
		sprite.visibility_range_end = distance
		sprite.visibility_range_end_margin = margin

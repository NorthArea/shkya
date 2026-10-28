extends "res://game/characters/character_sprite.gd"
## Илюша за рулём «Лады» (POLISH-02, п. 1; концепты 04, 05): тот же облик CharacterSprite и те же рисунки
## в зимнем костюме, но только голова, воротник и плечи — ниже линии окон его закрывает кузов.
## Масштаб меньше, чем у Илюши пешком: голова вписана в заднее стекло, как на концепте 05.
## Узел ставится на уровень «ног» холста; виден, только когда в машине есть водитель (lada.gd).

const CUT_Y := 440.0   # нижний край видимой части холста: плечи под воротником, дальше — кузов

func _ready() -> void:
	super._ready()
	# Без пятна тени и без шагов: в машине Илюша сидит, рисунок — стойка.
	var shadow := get_node_or_null("Shadow")
	if shadow:
		remove_child(shadow)
		shadow.free()
	set_physics_process(false)
	frame = -1
	var texture: Texture2D = sprite.texture
	var px_per_unit := texture.get_height() / CANVAS_HEIGHT
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0.0, 0.0, texture.get_width(), CUT_Y * px_per_unit)
	# Центр области — на середине холста по высоте области; ноги холста (FEET_Y) — в начале узла.
	sprite.position.y = (FEET_Y - CUT_Y * 0.5) * height_m / CANVAS_HEIGHT

func _physics_process(_delta: float) -> void:
	pass

extends RefCounted
## Stable gameplay identities; display text and asset names do not identify an unlock.

const ALL := [
	{"id": &"double_granny", "title": "Две бабки — один занос", "description": "Сбей двух разных бабушек за три секунды.", "toast": "Городской хор перешёл на верхние ноты."},
	{"id": &"timber_delivery", "title": "Дрова с доставкой", "description": "Свали дерево «Ладой».", "toast": "Самовывоз оказался слишком буквальным."},
	{"id": &"standing_room", "title": "Место для стояния", "description": "Разбери скамейку ударом.", "toast": "Лавочку прикрыли. Беседу оставили."},
	{"id": &"bread_zero", "title": "Финансовая подушка", "description": "Собери десять монет за одну прогулку.", "toast": "Подушка финансовая. Спать всё ещё негде."},
	{"id": &"good_boy_certificate", "title": "Справка о доброте", "description": "Сначала что-нибудь сломай, потом погладь собаку в той же игре.", "toast": "Эксперт обнюхал. Претензий нет."},
	{"id": &"bread_box", "title": "Коробочный человек", "description": "Спрячься в коробке.", "toast": "Недвижимость экономкласса. Вид из клапана."},
	{"id": &"cold_storage", "title": "Морозильная камера", "description": "Спрячься в сугробе.", "toast": "Коммунальная морозилка приняла жильца."},
	{"id": &"professional_ditcher", "title": "Принципиальный человек", "description": "За одну прогулку сломай один предмет машиной, а другой — ударом.", "toast": "Ручной труд успешно механизирован."},
	{"id": &"drone_silence", "title": "Авиарежим", "description": "Сбей один городской дрон.", "toast": "Режим полёта выключен вручную."},
	{"id": &"alarm_clock", "title": "Будильник для района", "description": "Включи сигнализацию машины три раза за одну прогулку.", "toast": "Жители проснулись. Благодарность уточняется."},
]

static func definition(id: StringName) -> Dictionary:
	for entry: Dictionary in ALL:
		if entry["id"] == id:
			return entry
	return {}

static func icon_path(id: StringName) -> String:
	return "res://assets/art/achievements/%s.%s" % [id, "svg" if id in [&"drone_silence", &"alarm_clock"] else "png"]

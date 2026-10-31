extends RefCounted
## Stable gameplay identities; display text and asset names do not identify an unlock.

const ALL := [
	{"id": &"double_granny", "title": "Две бабки — один занос", "description": "Сбей двух разных бабушек за три секунды.", "toast": "Городской хор перешёл на верхние ноты."},
	{"id": &"timber_delivery", "title": "Дрова с доставкой", "description": "Свали дерево «Ладой».", "toast": "Самовывоз оказался слишком буквальным."},
	{"id": &"standing_room", "title": "Место для стояния", "description": "Разбери скамейку ударом.", "toast": "Лавочку прикрыли. Беседу оставили."},
	{"id": &"bread_zero", "title": "Финансовая подушка", "description": "Купи хлеб на последние деньги.", "toast": "В подушке только мякиш."},
	{"id": &"good_boy_certificate", "title": "Справка о доброте", "description": "Сначала что-нибудь сломай, потом погладь собаку в той же игре.", "toast": "Эксперт обнюхал. Претензий нет."},
	{"id": &"bread_box", "title": "Хлебное место", "description": "Спрячься в коробке с купленным хлебом.", "toast": "Теперь ты комплектная упаковка."},
	{"id": &"cold_storage", "title": "Морозильная камера", "description": "Залезь в сугроб с купленным хлебом.", "toast": "Срок годности увеличен на неловкость."},
	{"id": &"professional_ditcher", "title": "Принципиальный человек", "description": "Откажись идти за хлебом, затем всё-таки выполни поручение в той же игре.", "toast": "Принципы выдержали один разговор."},
]

static func definition(id: StringName) -> Dictionary:
	for entry: Dictionary in ALL:
		if entry["id"] == id:
			return entry
	return {}

static func icon_path(id: StringName) -> String:
	return "res://assets/art/achievements/%s.png" % id

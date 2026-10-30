extends RefCounted
## PHONE-01: оригинальные сообщения города Н.; лента продолжает заставку.

const IntroLines = preload("res://game/mission/intro_lines.gd")

const MESSAGES := {
	&"welcome": {"sender": "Комитет городского спокойствия", "source": "Городская рассылка",
		"body": "В городе Н. существенных происшествий не зарегистрировано. Службы работают в штатном режиме."},
	&"babka_before": {"sender": "Бабка", "source": "Личное сообщение",
		"body": "Илюша, хлеба возьми. Не нарезной. Я у подъезда."},
	&"bread_quest": {"sender": "Бабка", "source": "Личное сообщение",
		"body": "Батон обычный, не нарезной. Патрулей берегись. И ничего не подписывай!"},
	&"kiosk": {"sender": "Управление удобных маршрутов", "source": "Городская рассылка",
		"body": "Пункт новых возможностей открыт. Индивидуальный подход к каждому. Предложения сами вас найдут."},
	&"bread": {"sender": "Бабка", "source": "Личное сообщение",
		"body": "Купил? Давай домой, чай остывает."},
	&"detour": {"sender": "Город Н. · Оповещение", "source": "Городская рассылка",
		"body": "В вашем районе повышается транспортная доступность. Благодарим за временные неудобства."},
	&"detected": {"sender": "Бюро отсутствующих событий", "source": "Городская рассылка",
		"body": "Событие с вашим участием не зарегистрировано. Продолжайте прогулку, как будто ничего не было."},
}

static func news() -> Array[Dictionary]:
	var posts: Array[Dictionary] = []
	for i in IntroLines.HEADLINES.size():
		posts.append({"headline": IntroLines.HEADLINES[i], "source": IntroLines.FEED_TITLE,
			"body": IntroLines.BODIES[i], "footer": IntroLines.FOOTERS[i]})
	posts.append({"headline": "Мороз стабильный", "source": "Городской вестник",
		"body": "Минус десять. Перемен не ожидается. Тепло — у окон.", "footer": "Ощущается как обычно"})
	posts.append({"headline": "Порядок без перерыва", "source": "Комитет городского спокойствия",
		"body": "Отсутствие событий — тоже результат. Благодарим за понимание.", "footer": "Комментарии по расписанию"})
	return posts

static func all_texts() -> Array[String]:
	var texts: Array[String] = []
	for message: Dictionary in MESSAGES.values():
		texts.append(message.sender)
		texts.append(message.source)
		texts.append(message.body)
	for post: Dictionary in news():
		texts.append(post.headline)
		texts.append(post.source)
		texts.append(post.body)
		texts.append(post.footer)
	return texts

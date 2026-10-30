class_name CaughtPanel
extends CanvasLayer
## STORY-01 — провал стелса «В ГОРОДЕ Н. НИЧЕГО НЕ ПРОИЗОШЛО» (поручение владельца 30.10: если Илюшу схватили, обозначить,
## что игра закончена, потому что ничего не произошло). Задержание не показывается (запреты расширения): в момент
## провала (C7, DemoWorld.is_stealth_failing) экран гаснет, как выключенный телевизор — картинка сжимается в светлую
## полосу, полоса в точку, точка гаснет; мир встаёт на паузу (тишина — эфир оборвался). Затем карточка-пост в стиле
## ленты заставки: заголовок, подзаголовок по кругу (SUBTITLES по StealthDirector.detections), «ЕЩЁ РАЗ» — респавн на
## чекпоинте с has_bread (DemoWorld.finish_stealth_fail, логика C7 прежняя), «В ГЛАВНОЕ МЕНЮ» — сигнал menu_requested.
## Ввод (PAD-01): фокус на «ЕЩЁ РАЗ», A/Enter — выбор, B/Esc — «ЕЩЁ РАЗ» (безопасный выбор), Start карточка забирает себе.
## Музыки нет: тишина после гашения — часть шутки, а тема меню (MUSIC-01) спутала бы карточку с паузой.
## Где играет: CaughtPanel.attach(world) из main.gd; как и заставка — не в headless и не под тестовым SceneTree,
## если не выставлен force_enabled. Без карточки провал прежний: экран HUD и респавн через DemoWorld.FAIL_SECONDS.

const IntroLines = preload("res://game/mission/intro_lines.gd")
const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")

const HEADLINE := "В ГОРОДЕ Н. НИЧЕГО НЕ ПРОИЗОШЛО"
## Подзаголовки по кругу: провал n (StealthDirector.detections) — строка (n − 1) % size.
const SUBTITLES: Array[String] = [
	"Илюша за хлебом не ходил. Бабка ждёт.",
	"Прогулка отменена для вашего блага.",
	"Патруль ничего не видел. Вы тоже.",
	"Расходимся, граждане. Смотреть не на что.",
	"Хлеб подождёт. Бабка — тоже.",
]
const STAMP := "только что"
const FOOTER := "Очевидцев: 0"
const AGAIN_TEXT := "ЕЩЁ РАЗ"
const MENU_TEXT := "В ГЛАВНОЕ МЕНЮ"

const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)
const SCREEN_BLACK := Color(0.02, 0.02, 0.025)
const GLOW := Color(0.92, 0.95, 1.0)

## Гашение «телевизора», с: сжатие в полосу, полоса в точку, точка гаснет, темнота; потом карточка.
const SQUASH := 0.18
const LINE := 0.18
const DOT := 0.24
const DARK := 0.30
const CARD_FADE := 0.2
const CARD_WIDTH := 860.0
const CARD_TILT_DEG := -1.2   # чуть криво, как приклеенная вырезка — «нарочито небрежно»

## Включить карточку и там, где она по умолчанию не играет (headless, тестовый SceneTree).
static var force_enabled := false

## «В ГЛАВНОЕ МЕНЮ» — main.gd возвращает в меню.
signal menu_requested
## «ЕЩЁ РАЗ» — Илюша уже на чекпоинте.
signal retried

var world: Node
## &"idle" (ждём провала), &"off" (гашение), &"card" (карточка).
var phase: StringName = &"idle"
var elapsed := 0.0
## Сколько раз карточка открывалась в этом мире; номер подзаголовка на экране.
var shown_count := 0
var subtitle_index := -1
var buttons: Dictionary = {}   # &"again", &"menu" -> Button
var screen: Control
var card: Control
var subtitle_label: Label

var _paused_by_me := false

static func should_play(tree: SceneTree) -> bool:
	if force_enabled:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	return tree.get_script() == null

## Подключить карточку к миру; null — не играет, провал прежний.
static func attach(new_world: Node) -> CaughtPanel:
	if not should_play(new_world.get_tree()):
		return null
	var panel := CaughtPanel.new()
	panel.name = "CaughtPanel"
	new_world.add_child(panel)
	new_world.set("fail_presenter", panel)
	return panel

static func off_seconds() -> float:
	return SQUASH + LINE + DOT + DARK

static func subtitle_for(detections: int) -> String:
	return SUBTITLES[posmod(detections - 1, SUBTITLES.size())]

func _ready() -> void:
	layer = 12   # над HUD (5), диалогом (8) и заставкой (10), под паузой (15)
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = get_parent()
	_build()
	visible = false

func is_open() -> bool:
	return phase == &"card"

func is_active() -> bool:
	return phase != &"idle"

func _physics_process(delta: float) -> void:
	match phase:
		&"idle":
			if world.has_method("is_stealth_failing") and world.is_stealth_failing():
				_start()
		&"off", &"card":
			if not world.is_stealth_failing():
				_close()   # провал закрыли не карточкой — ничего не держим
				return
			elapsed += delta
			if phase == &"off":
				if elapsed >= SQUASH + LINE and not get_tree().paused:
					get_tree().paused = true   # экран уже тёмный: мир и его звук замирают
					_paused_by_me = true
				if elapsed >= off_seconds():
					_show_card()
			else:
				card.modulate.a = clampf((elapsed - off_seconds()) / CARD_FADE, 0.0, 1.0)
			screen.queue_redraw()

func _input(event: InputEvent) -> void:
	if phase == &"idle":
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if phase == &"card":
			retry()
	elif event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()   # пауза поверх карточки не открывается

## «ЕЩЁ РАЗ»: мир снова идёт, Илюша на чекпоинте C7 с прежним has_bread.
func retry() -> void:
	if phase != &"card":
		return
	_close()
	world.finish_stealth_fail()
	var free_mouse: bool = world.get("ui_blocking") == true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED
	retried.emit()

## «В ГЛАВНОЕ МЕНЮ»: мир освобождает main.gd (return_to_menu снимает паузу); без main — просто снять паузу.
func go_to_menu() -> void:
	if phase != &"card":
		return
	var handled := not menu_requested.get_connections().is_empty()
	_close(handled)
	menu_requested.emit()

func _start() -> void:
	phase = &"off"
	elapsed = 0.0
	shown_count += 1
	var stealth: Node = world.get("stealth")
	var detections: int = stealth.detections if stealth else shown_count
	subtitle_index = posmod(detections - 1, SUBTITLES.size())
	subtitle_label.text = SUBTITLES[subtitle_index]
	card.visible = false
	visible = true
	screen.queue_redraw()

func _show_card() -> void:
	phase = &"card"
	card.visible = true
	card.modulate.a = 0.0
	DialogPanelScript.pop(card, 0.9)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	buttons[&"again"].grab_focus()

## keep_paused — паузу снимет тот, кто обработает menu_requested.
func _close(keep_paused := false) -> void:
	phase = &"idle"
	visible = false
	card.visible = false
	if _paused_by_me and not keep_paused:
		get_tree().paused = false
	_paused_by_me = false

# --- гашение экрана ---

func _draw_screen() -> void:
	var size := screen.size
	var mid := size.y * 0.5
	var t := elapsed if phase != &"idle" else 0.0
	if t < SQUASH:
		var k := _ease_in(t / SQUASH)
		var half := maxf(mid * (1.0 - k), 3.0)
		screen.draw_rect(Rect2(0, 0, size.x, mid - half), SCREEN_BLACK)
		screen.draw_rect(Rect2(0, mid + half, size.x, size.y - mid - half), SCREEN_BLACK)
		screen.draw_rect(Rect2(0, mid - half, size.x, half * 2.0), Color(GLOW, 0.85 * k))
		return
	screen.draw_rect(Rect2(Vector2.ZERO, size), SCREEN_BLACK)
	if t < SQUASH + LINE:
		var w := lerpf(size.x, 12.0, _ease_in((t - SQUASH) / LINE))
		screen.draw_rect(Rect2(size.x * 0.5 - w * 0.5, mid - 9.0, w, 18.0), Color(GLOW, 0.25))
		screen.draw_rect(Rect2(size.x * 0.5 - w * 0.5, mid - 3.0, w, 6.0), GLOW)
	elif t < SQUASH + LINE + DOT:
		var u := (t - SQUASH - LINE) / DOT
		screen.draw_circle(Vector2(size.x * 0.5, mid), lerpf(8.0, 2.0, u), Color(GLOW, 1.0 - u))

static func _ease_in(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x

# --- сборка ---

func _build() -> void:
	screen = Control.new()
	screen.name = "Screen"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP   # мир под карточкой мышью не трогается
	screen.draw.connect(_draw_screen)
	add_child(screen)
	card = PanelContainer.new()
	card.name = "CaughtCard"
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.border_color = INK
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(18)
	paper.shadow_color = Color(0, 0, 0, 0.5)
	paper.shadow_size = 12
	card.add_theme_stylebox_override("panel", paper)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -CARD_WIDTH * 0.5
	card.offset_right = CARD_WIDTH * 0.5
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.rotation = deg_to_rad(CARD_TILT_DEG)
	card.visible = false
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	# Шапка ленты — как на экране телефона в заставке.
	var header := PanelContainer.new()
	var band := StyleBoxFlat.new()
	band.bg_color = YELLOW
	band.border_color = INK
	band.border_width_bottom = 3
	band.corner_radius_top_left = 16
	band.corner_radius_top_right = 16
	band.content_margin_top = 14
	band.content_margin_bottom = 12
	header.add_theme_stylebox_override("panel", band)
	var title := _label(IntroLines.FEED_TITLE, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	column.add_child(header)
	var body := MarginContainer.new()
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 44)
	body.add_theme_constant_override("margin_top", 26)
	body.add_theme_constant_override("margin_bottom", 30)
	column.add_child(body)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 12)
	body.add_child(lines)
	var headline := _label(HEADLINE.replace("Н. ", "Н.\n"), 58)   # перенос после «Н.»: «НИЧЕГО НЕ ПРОИЗОШЛО» одной строкой
	headline.name = "Headline"
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(headline)
	var stamp := _label(STAMP, 26)
	stamp.modulate = Color(1, 1, 1, 0.6)
	lines.add_child(stamp)
	subtitle_label = _label(SUBTITLES[0], 38)
	subtitle_label.name = "Subtitle"
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(subtitle_label)
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.25)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(rule)
	var footer := _label(FOOTER, 28)
	footer.modulate = Color(1, 1, 1, 0.7)
	lines.add_child(footer)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	lines.add_child(row)
	for spec in [[&"again", AGAIN_TEXT, true], [&"menu", MENU_TEXT, false]]:
		var button := Button.new()
		button.name = "Caught_" + String(spec[0])
		button.text = spec[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 64)
		DialogPanelScript.style_button(button, spec[2])
		row.add_child(button)
		buttons[spec[0]] = button
	buttons[&"again"].pressed.connect(retry)
	buttons[&"menu"].pressed.connect(go_to_menu)
	# Фокус ходит только между двумя кнопками (PAD-01: d-pad / стик влево-вправо).
	var again: Button = buttons[&"again"]
	var menu: Button = buttons[&"menu"]
	for b: Button in [again, menu]:
		b.focus_neighbor_top = b.get_path()
		b.focus_neighbor_bottom = b.get_path()
	again.focus_neighbor_left = again.get_path()
	again.focus_neighbor_right = menu.get_path()
	menu.focus_neighbor_left = again.get_path()
	menu.focus_neighbor_right = menu.get_path()

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

class_name DialogPanel
extends CanvasLayer
## Панель диалога (QUEST-01): портрет, имя, реплика и кнопки внизу экрана, как на кадрах 02, 03, 07.
## Сама ничего не решает: показывает, что ей передали, и шлёт choice(id) по нажатию кнопки.
## Координаты — в пространстве 1920x1080 (stretch canvas_items).
## POLISH-02: панель «выпрыгивает», реплика печатается ≈40 знаков/с под «бормотание» персонажа;
## E, пробел или щелчок во время печати дописывают реплику сразу, дальше всё как раньше (кнопки).
## text_label.text всегда целиком — печать только открывает знаки (visible_characters).
## EXT-01 (L): цепочка реплик open_chain() — говорящий меняется (Бабка, продавщица, полицейский, «военком»,
## Илюша со своим портретом); «ДАЛЬШЕ» или E после допечатки показывает следующую, варианты ответа —
## только на последней. Тексты — только из QuestLines (game/mission/lines.gd).

signal choice(id: StringName)
## Переключение на следующую реплику цепочки (для щелчка интерфейса).
signal advanced(index: int)

const PAPER := Color(0.93, 0.87, 0.72)
const PAPER_DARK := Color(0.84, 0.76, 0.58)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)
const CHARS_PER_SECOND := 40.0
const POP_SECONDS := 0.15
## Бормотание: свой синтезированный голос на персонажа (tools/generate_audio.py), громкость в ряду сигналов квеста.
const VOICES := {
	&"babka": preload("res://assets/audio/voice_babka.wav"),
	&"vendor": preload("res://assets/audio/voice_vendor.wav"),
	&"ilyusha": preload("res://assets/audio/voice_ilyusha.wav"),
	&"officer": preload("res://assets/audio/voice_officer.wav"),
	&"account_officer": preload("res://assets/audio/voice_account_officer.wav"),
}
const VOICE_DB := -6.0
const NEXT_ID := &"next"
## B геймпада после допечатки — кнопка выхода, если она есть на реплике (PAD-01). «СДАТЬ ХЛЕБ», «ПРИНЯТЬ» и «КУПИТЬ»
## сюда не входят: отмена ничего не выбирает за игрока, кроме «уйти».
const CANCEL_IDS: Array[StringName] = [&"leave", &"close", &"decline"]

var panel: PanelContainer
var speaker_label: Label
var text_label: Label
var portrait: Control
var buttons: Dictionary = {}  # id -> Button
var _row: HBoxContainer
var _portrait_kind := &"babka"
var _typed := 0.0
var voice: AudioStreamPlayer
## Цепочка: строки {speaker, text, portrait}, номер текущей и кнопки последней.
var _lines: Array = []
var _line_index := 0
var _final_specs: Array = []

func _ready() -> void:
	layer = 8
	visible = false
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", paper_style())
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -270
	panel.offset_bottom = -50
	add_child(panel)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 24)
	panel.add_child(outer)
	portrait = Control.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(150, 150)
	portrait.clip_contents = true
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.draw.connect(_draw_portrait)
	outer.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	outer.add_child(column)
	speaker_label = Label.new()
	speaker_label.name = "Speaker"
	speaker_label.add_theme_font_size_override("font_size", 38)
	speaker_label.add_theme_color_override("font_color", INK)
	column.add_child(speaker_label)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)
	text_label = Label.new()
	text_label.name = "Text"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(0, 52)
	text_label.add_theme_font_size_override("font_size", 34)
	text_label.add_theme_color_override("font_color", INK)
	column.add_child(text_label)
	_row = HBoxContainer.new()
	_row.name = "Buttons"
	_row.add_theme_constant_override("separation", 20)
	column.add_child(_row)
	voice = AudioStreamPlayer.new()
	voice.name = "Voice"
	voice.volume_db = VOICE_DB
	add_child(voice)

## Одна реплика. specs: [{id, text, enabled (по умолчанию true), primary (по умолчанию false)}].
func open(speaker: String, text: String, specs: Array, portrait_kind: StringName = &"babka") -> void:
	open_chain([{"speaker": speaker, "text": text, "portrait": portrait_kind}], specs)

## Цепочка реплик (QuestLines.*_CHAIN): до последней — одна кнопка «ДАЛЬШЕ», на последней — specs.
func open_chain(lines: Array, specs: Array) -> void:
	assert(not lines.is_empty())
	_lines = lines
	_final_specs = specs
	_line_index = 0
	visible = true  # до кнопок: фокус берётся на видимой панели (PAD-01)
	_show_line()
	pop(panel)

func _show_line() -> void:
	var line: Dictionary = _lines[_line_index]
	var specs: Array = _final_specs if is_last_line() else [{"id": NEXT_ID, "text": QuestLines.BUTTON_NEXT, "primary": true}]
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	buttons.clear()
	speaker_label.text = line["speaker"]
	text_label.text = line["text"]
	text_label.visible_characters = 0
	_typed = 0.0
	_portrait_kind = line.get("portrait", &"babka")
	portrait.queue_redraw()
	var first_enabled: Button = null
	for spec in specs:
		var button := Button.new()
		button.name = "Button_" + String(spec["id"])
		button.text = spec["text"]
		button.disabled = not spec.get("enabled", true)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 58)
		style_button(button, spec.get("primary", false))
		button.pressed.connect(_on_pressed.bind(spec["id"]))
		_row.add_child(button)
		buttons[spec["id"]] = button
		if first_enabled == null and not button.disabled:
			first_enabled = button
	if first_enabled:
		first_enabled.grab_focus()
	play_voice(_portrait_kind)

func close() -> void:
	visible = false
	voice.stop()
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	buttons.clear()
	_lines = []
	_final_specs = []
	_line_index = 0

func is_open() -> bool:
	return visible

## Номер текущей реплики цепочки (с нуля) и их число.
func line_index() -> int:
	return _line_index

func line_count() -> int:
	return _lines.size()

func is_last_line() -> bool:
	return _line_index >= _lines.size() - 1

## Следующая реплика цепочки. Во время печати — только дописать текущую. На последней ничего не делает.
func advance() -> bool:
	if not visible:
		return false
	if is_typing():
		finish_typing()
		return false
	if is_last_line():
		return false
	_line_index += 1
	_show_line()
	advanced.emit(_line_index)
	return true

## Реплика ещё печатается.
func is_typing() -> bool:
	return visible and text_label.visible_characters >= 0 and text_label.visible_characters < text_label.text.length()

## Дописать реплику сразу.
func finish_typing() -> void:
	text_label.visible_characters = -1
	voice.stop()

func play_voice(kind: StringName) -> void:
	if VOICES.has(kind):
		voice.stream = VOICES[kind]
		voice.play()

func _process(delta: float) -> void:
	if not is_typing():
		return
	_typed += delta * CHARS_PER_SECOND
	text_label.visible_characters = mini(int(_typed), text_label.text.length())
	if not is_typing():
		finish_typing()

## Во время печати E, пробел или щелчок только дописывают реплику; кнопки сработают со следующего нажатия.
## После допечатки E переключает реплику цепочки (пробел и Enter нажимают кнопку «ДАЛЬШЕ» в фокусе).
## Геймпад (PAD-01): X — как E; A — как пробел (во время печати дописывает, потом нажимает кнопку в фокусе);
## B во время печати дописывает, после — выход из разговора, если на реплике есть кнопка выхода (CANCEL_IDS).
## Esc остаётся паузой: отмена диалога — только кнопкой B геймпада.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not is_typing():
		if event.is_action_pressed(&"interact") and not is_last_line():
			advance()
			get_viewport().set_input_as_handled()
		elif _is_pad_button(event, JOY_BUTTON_B):
			for id in CANCEL_IDS:
				if buttons.has(id) and not (buttons[id] as Button).disabled:
					get_viewport().set_input_as_handled()
					_on_pressed(id)
					return
		return
	var skip := event.is_action_pressed(&"interact") or _is_pad_button(event, JOY_BUTTON_A) or _is_pad_button(event, JOY_BUTTON_B)
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_SPACE:
		skip = true
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		skip = true
	if skip:
		finish_typing()
		get_viewport().set_input_as_handled()

static func _is_pad_button(event: InputEvent, index: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == index

## «Выпрыгивание» панели: масштаб от 0,85 до 1 с перелётом (POLISH-02, п. 10).
static func pop(control: Control, from := 0.85) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * from
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Шрифт интерфейса проекта (gui/theme/custom_font), иначе встроенный.
static func ui_font() -> Font:
	var path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return ThemeDB.fallback_font

## Клавиша-«колпачок» для подсказок и строки управления: светлая рамка, буква внутри.
static func key_cap(text: String, font_size := 26, dark := true) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.91, 0.85) if dark else Color(0.20, 0.18, 0.16)
	style.border_color = INK if dark else Color(0.93, 0.87, 0.72)
	style.set_border_width_all(2)
	style.border_width_bottom = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK if dark else Color(0.97, 0.95, 0.90))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(label)
	return cap

## Управление (канон, раздел 7, + геймпад — решения владельца 28.10 и PAD-01): действие, клавиатура, геймпад.
## Показывается в НАСТРОЙКАХ (settings_panel.gd) — из меню и паузы строка управления убрана (владелец 29.10, вечер).
const CONTROLS := [
	["Идти, руль", "W A S D", "Левый стик"],
	["Быстрый бег", "Shift", "LB"],
	["Камера", "Мышь", "Правый стик"],
	["Говорить, сесть, выйти", "E", "X"],
	["Прыжок", "Space", "A"],
	["Удар", "F / ЛКМ", "B"],
	["Газ, тормоз", "W / S", "RT / LT"],
	["Ручник", "Space", "B"],
	["Радиостанция в машине", "R", "Крестовина →"],
	["Выбор в меню", "Enter", "A"],
	["Назад", "Esc", "B"],
	["Пауза", "Esc", "Start"],
	["Телефон", "P", "↑ / ↓"],
]

func _on_pressed(id: StringName) -> void:
	if id == NEXT_ID:
		advance()
		return
	choice.emit(id)

static func paper_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	return style

static func style_button(button: Button, primary: bool) -> void:
	button.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.border_color = INK
		style.set_border_width_all(3)
		style.set_corner_radius_all(3)
		var base := YELLOW if primary else PAPER_DARK
		match state:
			"hover": base = base.lightened(0.15)
			"pressed": base = base.darkened(0.15)
			"disabled": base = Color(0.62, 0.60, 0.55)
		style.bg_color = base
		if state == "focus":
			# PAD-01: фокус — толстая рамка вокруг кнопки поверх её состояния (нажатие под ней видно),
			# чтобы с геймпада и клавиатуры было ясно, какой пункт выбран.
			style.draw_center = false
			style.set_border_width_all(5)
			style.set_expand_margin_all(6)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(0.35, 0.33, 0.30))

## Портрет — вырезка головы и плеч из рисунка персонажа ART-01 (тот же облик, что в мире, кадр 07).
## Область — в единицах холста 400×600 (текстура в 2 раза крупнее).
## Илюша — голова с хохолком (HEAD_FRONT 86…302 по высоте, хохолок на 44 в tools/generate_characters.py).
## Полицейский и «военком» — рисунки исполнителя N (EXT-01); пока их нет, рисуется подложка без портрета.
const PORTRAIT_REGION := {
	&"babka": Rect2(85, 50, 230, 230),
	&"vendor": Rect2(90, 56, 220, 220),
	&"ilyusha": Rect2(80, 36, 240, 240),
	&"officer": Rect2(85, 50, 230, 230),
	&"account_officer": Rect2(85, 50, 230, 230),
}
## Ключ портрета → имя рисунка: полицейский (зона &"officer") нарисован как police_*, сотрудник ГСУМ
## (&"account_officer") — как officer_* (имена генератора EXT-01 N). Приёмка EXT-01, P2 4–5.
const PORTRAIT_FILE := {&"officer": "police", &"account_officer": "officer"}

func _draw_portrait() -> void:
	var rect := Rect2(Vector2.ZERO, portrait.size)
	portrait.draw_rect(rect, PAPER_DARK)
	var path := "res://assets/art/characters/%s_front_idle.svg" % PORTRAIT_FILE.get(_portrait_kind, _portrait_kind)
	var region: Rect2 = PORTRAIT_REGION.get(_portrait_kind, PORTRAIT_REGION[&"babka"])
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path)
		var scale := texture.get_width() / 400.0
		portrait.draw_texture_rect_region(texture, rect, Rect2(region.position * scale, region.size * scale))
	portrait.draw_rect(rect, INK, false, 3.0)

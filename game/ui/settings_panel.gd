extends PanelContainer
## Настройки (решение владельца 29.10, вечер): управление вынесено из главного меню и паузы сюда — таблица
## «действие | клавиатура | геймпад» колпачками клавиш и кнопка НАЗАД. Одна панель для меню и паузы.
## Esc / B (ui_cancel, pause) закрывают панель раньше, чем пауза их увидит: панель — потомок меню (ввод снизу вверх).

signal back_requested

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const AchievementsPanel = preload("res://game/ui/achievements_panel.gd")
const INK := Color(0.12, 0.10, 0.08)
const INK_SOFT := Color(0.12, 0.10, 0.08, 0.6)

var back_button: Button
var achievements_button: Button
var achievements: CanvasLayer
var _box: VBoxContainer

func _ready() -> void:
	name = "SettingsCard"
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := DialogPanelScript.paper_style()
	style.content_margin_left = 44
	style.content_margin_right = 44
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	_box = box
	box.custom_minimum_size = Vector2(640, 0)   # ширина как у карточки главного меню
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	box.add_child(_label("НАСТРОЙКИ", 52, INK, HORIZONTAL_ALIGNMENT_CENTER))
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 3)
	box.add_child(rule)
	box.add_child(_label("УПРАВЛЕНИЕ", 26, INK, HORIZONTAL_ALIGNMENT_LEFT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for head in ["", "Клавиатура", "Геймпад"]:
		grid.add_child(_label(head, 20, INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT))
	for row in DialogPanelScript.CONTROLS:
		grid.add_child(_label(row[0], 24, INK, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(_caps(row[1]))
		grid.add_child(_caps(row[2]))
	var music_credit := RichTextLabel.new()
	music_credit.name = "RadioMusicCredits"
	music_credit.bbcode_enabled = true
	music_credit.fit_content = true
	music_credit.scroll_active = false
	music_credit.add_theme_font_size_override("normal_font_size", 14)
	music_credit.add_theme_color_override("default_color", INK_SOFT)
	music_credit.text = "Радио: Kevin MacLeod (incompetech.com) · [url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]\n[url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100499]Cold Funk[/url] · [url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300012]Local Forecast - Elevator[/url] · [url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400011]Monkeys Spinning Monkeys[/url] · [url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100772]Sneaky Snitch[/url]\nПерекодировано, громкость адаптирована. Классика — Paul Pitman / Olga Gurevich, [url=https://musopen.org/]Musopen[/url]."
	music_credit.meta_clicked.connect(func(url: Variant): OS.shell_open(str(url)))
	box.add_child(music_credit)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	box.add_child(gap)
	achievements_button = Button.new()
	achievements_button.text = "ДОСТИЖЕНИЯ"
	achievements_button.custom_minimum_size = Vector2(0, 64)
	DialogPanelScript.style_button(achievements_button, false)
	achievements_button.add_theme_font_size_override("font_size", 32)
	achievements_button.pressed.connect(_open_achievements)
	box.add_child(achievements_button)
	back_button = Button.new()
	back_button.text = "НАЗАД"
	back_button.custom_minimum_size = Vector2(0, 64)
	DialogPanelScript.style_button(back_button, true)
	back_button.add_theme_font_size_override("font_size", 32)
	back_button.pressed.connect(back_requested.emit)
	box.add_child(back_button)
	achievements = AchievementsPanel.new()
	add_child(achievements)
	achievements.back_requested.connect(_close_achievements)
	visibility_changed.connect(_on_visibility_changed)
	hide()

func open() -> void:
	achievements.hide()
	_box.show()
	show()
	back_button.grab_focus.call_deferred()
	DialogPanelScript.pop(self, 0.92)

func _unhandled_input(event: InputEvent) -> void:
	if achievements.visible:
		return
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		back_requested.emit()

func _open_achievements() -> void:
	_box.hide()
	achievements.open()

func _close_achievements() -> void:
	achievements.hide()
	_box.show()
	achievements_button.grab_focus.call_deferred()

func _on_visibility_changed() -> void:
	if not visible and achievements != null:
		achievements.hide()
		_box.show()

## Клавиши ячейки: «F / ЛКМ» → два колпачка через «/».
func _caps(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts := text.split(" / ")
	for i in parts.size():
		if i > 0:
			row.add_child(_label("/", 22, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
		row.add_child(DialogPanelScript.key_cap(parts[i], 22))
	return row

func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

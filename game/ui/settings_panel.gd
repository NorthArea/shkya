extends PanelContainer
## Настройки (решение владельца 29.10, вечер): управление вынесено из главного меню и паузы сюда — таблица
## «действие | клавиатура | геймпад» колпачками клавиш и кнопка НАЗАД. Одна панель для меню и паузы.
## Esc / B (ui_cancel, pause) закрывают панель раньше, чем пауза их увидит: панель — потомок меню (ввод снизу вверх).

signal back_requested

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const AudioSettingsSection = preload("res://game/ui/audio_settings_section.gd")
const AchievementsPanel = preload("res://game/ui/achievements_panel.gd")
const INK := Color(0.12, 0.10, 0.08)
const INK_SOFT := Color(0.12, 0.10, 0.08, 0.6)

var back_button: Button
var achievements_button: Button
var achievements: CanvasLayer
var resolution_option: OptionButton
var _box: VBoxContainer
var _display_settings: Node
var _resolution_error: Label
var _refreshing_resolution := false
var graphics_options: Dictionary = {}
var _scroll: ScrollContainer
var _footer: VBoxContainer
var audio_section: VBoxContainer
var _control_help: Array[Control] = []

func _ready() -> void:
	name = "SettingsCard"
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := DialogPanelScript.paper_style()
	style.content_margin_left = 44
	style.content_margin_right = 44
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	add_theme_stylebox_override("panel", style)
	var outer := VBoxContainer.new()
	_box = outer
	outer.custom_minimum_size = Vector2(720, 0)
	add_child(outer)
	outer.add_child(_label("НАСТРОЙКИ", 44, INK, HORIZONTAL_ALIGNMENT_CENTER))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.custom_minimum_size.y = 560
	outer.add_child(_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	_scroll.add_child(box)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 3)
	box.add_child(rule)
	_add_resolution_row(box)
	_add_graphics_rows(box)
	audio_section = AudioSettingsSection.new()
	box.add_child(audio_section)
	box.add_child(_label("УПРАВЛЕНИЕ", 26, INK, HORIZONTAL_ALIGNMENT_LEFT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for head in ["", "Клавиатура", "Геймпад"]:
		grid.add_child(_label(head, 20, INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT))
	for row in DialogPanelScript.CONTROLS:
		var action := PanelContainer.new()
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action.add_child(_label(row[0], 24, INK, HORIZONTAL_ALIGNMENT_LEFT))
		var idle_style := StyleBoxEmpty.new()
		action.add_theme_stylebox_override("panel", idle_style)
		action.focus_mode = Control.FOCUS_ALL
		var focus_style := StyleBoxFlat.new()
		focus_style.bg_color = DialogPanelScript.PAPER_DARK
		focus_style.border_color = INK
		focus_style.set_border_width_all(2)
		focus_style.set_content_margin_all(0)
		focus_style.set_expand_margin_all(4)
		action.focus_entered.connect(func(): action.add_theme_stylebox_override("panel", focus_style))
		action.focus_exited.connect(func(): action.add_theme_stylebox_override("panel", idle_style))
		_control_help.append(action)
		grid.add_child(action)
		grid.add_child(_caps(row[1]))
		grid.add_child(_caps(row[2]))
	var music_credit := RichTextLabel.new()
	music_credit.name = "RadioMusicCredits"
	music_credit.bbcode_enabled = true
	music_credit.fit_content = true
	music_credit.scroll_active = false
	music_credit.add_theme_font_size_override("normal_font_size", 14)
	music_credit.add_theme_color_override("default_color", INK_SOFT)
	music_credit.text = "Радио: Kevin MacLeod (incompetech.com) · [url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]\n[url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100499]Cold Funk[/url] · [url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300012]Local Forecast - Elevator[/url] · [url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400011]Monkeys Spinning Monkeys[/url] · [url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100772]Sneaky Snitch[/url]\nПерекодировано, громкость адаптирована. Лунная соната I — Paul Pitman / [url=https://musopen.org/]Musopen[/url].\n[url=https://www.youtube.com/watch?v=uNkRW_9pHRQ]Ride of the Valkyries[/url] — [url=https://pmmusic.pro/]Philip Milman[/url], Lud and Schlatts Musical Emporium; funded by Ludwig and Schlatt · [url=https://creativecommons.org/licenses/by/3.0/]CC BY 3.0[/url]. Перекодировано, громкость адаптирована."
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
	_footer = VBoxContainer.new()
	outer.add_child(_footer)
	_footer.add_child(achievements_button)
	back_button = Button.new()
	back_button.text = "НАЗАД"
	back_button.custom_minimum_size = Vector2(0, 64)
	DialogPanelScript.style_button(back_button, true)
	back_button.add_theme_font_size_override("font_size", 32)
	back_button.pressed.connect(back_requested.emit)
	_footer.add_child(back_button)
	achievements = AchievementsPanel.new()
	add_child(achievements)
	achievements.back_requested.connect(_close_achievements)
	_display_settings = get_tree().get_first_node_in_group(&"display_settings")
	if _display_settings != null:
		_display_settings.changed.connect(_refresh_resolution)
	_refresh_resolution()
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_fit_height)
	_fit_height()
	hide()

func open() -> void:
	achievements.hide()
	_box.show()
	_refresh_resolution()
	_fit_height()
	show()
	back_button.grab_focus.call_deferred()
	DialogPanelScript.pop(self, 0.92)

func _add_resolution_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "ResolutionRow"
	row.add_theme_constant_override("separation", 24)
	row.add_child(_label("Разрешение", 24, INK, HORIZONTAL_ALIGNMENT_LEFT))
	resolution_option = OptionButton.new()
	resolution_option.name = "ResolutionOption"
	resolution_option.custom_minimum_size = Vector2(380, 48)
	resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_option.fit_to_longest_item = false
	DialogPanelScript.style_button(resolution_option, false)
	resolution_option.add_theme_font_size_override("font_size", 22)
	resolution_option.item_selected.connect(_on_resolution_selected)
	var popup := resolution_option.get_popup()
	popup.add_theme_stylebox_override("panel", DialogPanelScript.paper_style())
	popup.add_theme_font_size_override("font_size", 22)
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", INK)
	popup.add_theme_constant_override("v_separation", 12)
	var hover := StyleBoxFlat.new()
	hover.bg_color = DialogPanelScript.PAPER_DARK
	popup.add_theme_stylebox_override("hover", hover)
	row.add_child(resolution_option)
	box.add_child(row)
	_resolution_error = _label("Не удалось сохранить настройки.", 20, INK, HORIZONTAL_ALIGNMENT_LEFT)
	_resolution_error.name = "ResolutionError"
	_resolution_error.hide()
	box.add_child(_resolution_error)

func _refresh_resolution() -> void:
	_refreshing_resolution = true
	resolution_option.clear()
	resolution_option.disabled = not is_instance_valid(_display_settings)
	if resolution_option.disabled:
		resolution_option.add_item("Недоступно")
	else:
		var selected_width: int = _display_settings.selected_option_width()
		for option: Dictionary in _display_settings.available_resolutions():
			var index := resolution_option.item_count
			resolution_option.add_item(option["label"])
			resolution_option.set_item_metadata(index, int(option["width"]))
			if int(option["width"]) == selected_width:
				resolution_option.select(index)
	for key: String in graphics_options:
		var option: OptionButton = graphics_options[key]
		option.disabled = not is_instance_valid(_display_settings)
		if not option.disabled:
			var value: Variant = _display_settings.graphics[key]
			for index in option.item_count:
				if option.get_item_metadata(index) == value:
					option.select(index)
	_refreshing_resolution = false
	_update_focus_order()

func _on_resolution_selected(index: int) -> void:
	if _refreshing_resolution or not is_instance_valid(_display_settings):
		return
	var width: int = resolution_option.get_item_metadata(index)
	var error: Error = _display_settings.set_resolution_width(width)
	_resolution_error.visible = error != OK
	if error != OK:
		push_warning("Не удалось сохранить разрешение: %s" % error_string(error))
	_refresh_resolution()

func _update_focus_order() -> void:
	var controls: Array[Control] = [achievements_button, back_button]
	if not resolution_option.disabled:
		controls.push_front(resolution_option)
	for option: OptionButton in graphics_options.values():
		if not option.disabled:
			controls.insert(controls.size() - 2, option)
	for control: Control in audio_section.get_focus_controls():
		controls.insert(controls.size() - 2, control)
	for action: Control in _control_help:
		controls.insert(controls.size() - 2, action)
	for index in controls.size():
		var control := controls[index]
		var before := control.get_path_to(controls[posmod(index - 1, controls.size())])
		var after := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_neighbor_top = before
		control.focus_previous = before
		control.focus_neighbor_bottom = after
		control.focus_next = after

func _unhandled_input(event: InputEvent) -> void:
	if achievements.visible:
		return
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		var options: Array = [resolution_option] + graphics_options.values()
		for option: OptionButton in options:
			if option.get_popup().visible:
				option.get_popup().hide()
				option.grab_focus()
				return
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
		resolution_option.get_popup().hide()
		for option: OptionButton in graphics_options.values():
			option.get_popup().hide()
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

func _fit_height() -> void:
	# Footer remains reachable while the content scrolls at smaller window sizes.
	_scroll.custom_minimum_size.y = clampf(get_viewport_rect().size.y - 330.0, 140.0, 560.0)

func _add_graphics_rows(box: VBoxContainer) -> void:
	var labels := {
		"vsync": "Синхронизация экрана", "fps_limit": "Предел кадров/с",
		"shadows": "Тени", "ssao": "Мягкие тени в углах",
		"ssil": "Отражённый свет", "ssr": "Отражения", "fog": "Объёмный туман",
	}
	for key: String in labels:
		var row := HBoxContainer.new()
		var label := _label(labels[key], 22, INK, HORIZONTAL_ALIGNMENT_LEFT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var option := OptionButton.new()
		option.name = key.to_pascal_case() + "Option"
		option.custom_minimum_size = Vector2(245, 44)
		DialogPanelScript.style_button(option, false)
		option.add_theme_font_size_override("font_size", 22)
		if key == "fps_limit":
			for limit: int in [0, 60, 80, 100, 120, 140, 160, 180, 200]:
				option.add_item("Без ограничения" if limit == 0 else str(limit))
				option.set_item_metadata(option.item_count - 1, limit)
		else:
			option.add_item("Включено")
			option.set_item_metadata(0, true)
			option.add_item("Выключено")
			option.set_item_metadata(1, false)
		option.item_selected.connect(func(index: int): _on_graphics_selected(key, index))
		graphics_options[key] = option
		row.add_child(option)
		box.add_child(row)

func _on_graphics_selected(key: String, index: int) -> void:
	if _refreshing_resolution or not is_instance_valid(_display_settings):
		return
	var error: Error = _display_settings.set_graphics_option(key, graphics_options[key].get_item_metadata(index))
	_resolution_error.visible = error != OK
	_refresh_resolution()

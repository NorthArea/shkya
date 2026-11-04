extends Control
## Экран перед геймплеем: только 2D; PackedScene мира загружается потоком.

signal scene_ready(scene: PackedScene)

const InputSetup = preload("res://game/input_setup.gd")

const INK := Color("292b35")
const PAPER := Color("eee4cf")
const WARM := Color("edc078")

var scene_path := "res://game/world/demo_world.tscn"
## В Main возвращаем ресурс; standalone fixture сохраняет change_scene_to_packed.
var embedded := false
var loaded_scene: PackedScene
var start_button: Button
var retry_button: Button
var progress_bar: ProgressBar
var status_label: Label
var _loading := false
var _activated := false

func _ready() -> void:
	InputSetup.install()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	resized.connect(queue_redraw)
	_begin_loading()

func _build_ui() -> void:
	var theme_font: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	if not theme_font.is_empty():
		theme = Theme.new()
		theme.default_font = load(theme_font)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.anchor_left = 0.09
	content.anchor_right = 0.49
	content.anchor_top = 0.25
	content.anchor_bottom = 0.81
	content.add_theme_constant_override("separation", 18)
	add_child(content)
	content.add_child(_label("НИЧЕГО НЕОБЫЧНОГО", 26, WARM))
	content.add_child(_label("Город Н", 100, PAPER))
	content.add_child(_label("За хлебом", 38, PAPER))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	status_label = _label("Загружаем город…", 26, PAPER)
	content.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 10
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_theme_stylebox_override("background", _style(Color("414858")))
	progress_bar.add_theme_stylebox_override("fill", _style(WARM))
	content.add_child(progress_bar)
	start_button = _button("Нажать для начала игры")
	start_button.disabled = true
	start_button.pressed.connect(_activate)
	content.add_child(start_button)
	retry_button = _button("Попробовать ещё раз")
	retry_button.hide()
	retry_button.pressed.connect(_begin_loading)
	content.add_child(retry_button)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 70
	button.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color := WARM
		match state:
			"hover": color = PAPER
			"pressed": color = WARM.darkened(0.12)
			"disabled": color = Color("626776")
		button.add_theme_stylebox_override(state, _style(color))
	var focus := _style(Color.TRANSPARENT)
	focus.border_color = PAPER
	focus.set_border_width_all(3)
	focus.set_expand_margin_all(5)
	button.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", Color("c5c5cd"))
	return button

func _begin_loading() -> void:
	if _loading or _activated:
		return
	loaded_scene = null
	start_button.disabled = true
	retry_button.hide()
	progress_bar.value = 0
	status_label.text = "Загружаем город…"
	# Existence check also gives a recoverable error without engine error spam.
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		_load_failed()
		return
	var error := ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if error != OK:
		_load_failed()
		return
	_loading = true
	set_process(true)

func _process(_delta: float) -> void:
	if not _loading:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
	if not progress.is_empty():
		progress_bar.value = float(progress[0]) * 100.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			loaded_scene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
			if loaded_scene == null:
				_load_failed()
				return
			_loading = false
			set_process(false)
			progress_bar.value = 100
			status_label.text = "Город ждёт. Заходи."
			start_button.disabled = false
			start_button.grab_focus()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_load_failed()

func _load_failed() -> void:
	_loading = false
	set_process(false)
	status_label.text = "Не удалось загрузить город"
	retry_button.show()
	retry_button.grab_focus()

func _activate() -> void:
	if _activated or loaded_scene == null:
		return
	_activated = true
	start_button.disabled = true
	_handoff.call_deferred()

func _handoff() -> void:
	if embedded:
		scene_ready.emit(loaded_scene)
		return
	var error := get_tree().change_scene_to_packed(loaded_scene)
	if error != OK:
		_activated = false
		loaded_scene = null
		_load_failed()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(1920, 1080))
	draw_rect(Rect2(0, 0, 1920, 1080), Color("222c40"))
	# Зимний двор, одно тёплое окно и снег — собственная 2D-графика без мира за экраном.
	draw_circle(Vector2(1500, 250), 78, Color("697889"))
	draw_rect(Rect2(1050, 370, 300, 630), Color("30394b"))
	draw_rect(Rect2(1370, 190, 550, 850), Color("3c4657"))
	for row in range(5):
		for col in range(4):
			var rect := Rect2(1412 + col * 132, 245 + row * 150, 70, 100)
			draw_rect(rect, Color("2a3447"))
	var window := Rect2(1544, 545, 70, 100)
	for glow in range(5, 0, -1):
		draw_rect(window.grow(glow * 15), Color(0.96, 0.67, 0.32, 0.015 * (6 - glow)))
	draw_rect(window, WARM)
	draw_line(Vector2(1579, 545), Vector2(1579, 645), INK, 5)
	draw_line(Vector2(1544, 580), Vector2(1614, 580), INK, 5)
	draw_line(Vector2(1538, 649), Vector2(1622, 649), PAPER, 6)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 1035), Vector2(700, 1000), Vector2(1350, 1030), Vector2(1920, 990), Vector2(1920, 1080), Vector2(0, 1080)]), Color("8894a5"))
	for flake in range(95):
		var at := Vector2(fmod(float(flake * 317 + 73), 1920.0), fmod(float(flake * 193 + 41), 1040.0))
		draw_circle(at, 1.3 + (flake % 3) * 0.5, Color(0.9, 0.94, 1, 0.20))

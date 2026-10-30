class_name Phone
extends CanvasLayer
## PHONE-01: локальная лента и СМС. Только телефон владеет своим inbox и своей паузой.

const PhoneLines = preload("res://game/mission/phone_lines.gd")
const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const PadInput = preload("res://game/ui/pad_input.gd")
const SWIPE_SOUND := preload("res://assets/audio/phone_swipe.wav")
const FONT := preload("res://assets/fonts/Pangolin-Regular.ttf")
const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const CASE := Color(0.10, 0.10, 0.11)
const SWIPE_DISTANCE := 40.0

var world: DemoWorld
var inbox: Array[Dictionary] = []
var news_index := 0
var sms_index := 0
var tab: StringName = &"news"
var unread: int:
	get:
		var count := 0
		for message: Dictionary in inbox:
			if not message.read:
				count += 1
		return count

var tab_buttons: Dictionary = {}
var page_control: Control
var phone_panel: PanelContainer
var body_label: Label
var heading_label: Label
var source_label: Label
var footer_label: Label
var page_label: Label
var hint_button: Button
var previous_button: Button
var next_button: Button
var overlay: Control

var _posts: Array[Dictionary] = []
var _seen: Dictionary = {}
var _opened := false
var _owns_pause := false
var _previous_mouse: Input.MouseMode
var _pause_tree: SceneTree
var _dragging := false
var _drag_from := Vector2.ZERO
var _swipe_sound: AudioStreamPlayer

static func attach(new_world: DemoWorld) -> Phone:
	var existing := new_world.get_node_or_null("Phone") as Phone
	if existing:
		return existing
	var phone := Phone.new()
	phone.name = "Phone"
	new_world.add_child(phone)
	return phone

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	world = get_parent() as DemoWorld
	_posts = PhoneLines.news()
	_build()
	_fit_panel()
	get_viewport().size_changed.connect(_fit_panel)
	world.mission.state_changed.connect(_on_state_changed)
	world.mission.bread_received.connect(receive.bind(&"bread"))
	world.mission.road_closed_changed.connect(func(closed: bool):
		if closed:
			receive(&"detour"))
	world.stealth.player_detected.connect(receive.bind(&"detected"))
	receive(&"welcome")
	receive(&"babka_before")
	_refresh_hint()

func is_open() -> bool:
	return _opened

func can_open() -> bool:
	if not is_inside_tree() or _opened or get_tree().paused or not is_instance_valid(world) or not world.is_inside_tree():
		return false
	if world.control_mode != &"on_foot" or world.ui_blocking or not world.player.input_enabled:
		return false
	if world.is_stealth_failing() or world.mission.state == MissionDirector.COMPLETE:
		return false
	var intro := world.get_node_or_null("Intro")
	if intro and intro.is_running():
		return false
	var caught := world.get_node_or_null("CaughtPanel")
	return caught == null or not caught.is_active()

func open_phone() -> bool:
	if not can_open():
		return false
	_opened = true
	_previous_mouse = Input.mouse_mode
	_pause_tree = get_tree()
	_owns_pause = true
	world.ui_blocking = true
	_pause_tree.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay.show()
	hint_button.hide()
	_refresh()
	tab_buttons[tab].grab_focus()
	return true

func close_phone() -> void:
	if not _opened:
		return
	_opened = false
	_dragging = false
	overlay.hide()
	if is_instance_valid(world):
		world.ui_blocking = false
	if _owns_pause:
		_owns_pause = false
		if is_instance_valid(_pause_tree):
			_pause_tree.paused = false
		Input.mouse_mode = _previous_mouse
	_pause_tree = null
	_refresh_hint()

func _exit_tree() -> void:
	close_phone()
	if _swipe_sound:
		_swipe_sound.stop()

func _process(_delta: float) -> void:
	_refresh_hint()

func receive(id: StringName) -> void:
	if _seen.has(id) or not PhoneLines.MESSAGES.has(id):
		return
	_seen[id] = true
	var message: Dictionary = PhoneLines.MESSAGES[id].duplicate()
	message["id"] = id
	message["read"] = false
	inbox.append(message)
	_refresh()

func _on_state_changed(_old: StringName, next: StringName) -> void:
	match next:
		MissionDirector.GO_TO_CAR: receive(&"bread_quest")
		MissionDirector.BUY_BREAD: receive(&"kiosk")

func select_tab(next: StringName) -> void:
	if next not in [&"news", &"sms"]:
		return
	if next != tab:
		_play_swipe()
	tab = next
	_refresh()
	tab_buttons[tab].grab_focus()

func turn_page(step: int) -> void:
	var old := news_index if tab == &"news" else sms_index
	if tab == &"news":
		news_index = clampi(news_index + step, 0, _posts.size() - 1)
	else:
		sms_index = clampi(sms_index + step, 0, inbox.size() - 1)
	if old != (news_index if tab == &"news" else sms_index):
		_play_swipe()
	_refresh()

func _play_swipe() -> void:
	if _opened:
		_swipe_sound.play()

func _refresh() -> void:
	if overlay == null:
		return
	if _opened:
		var item: Dictionary = _posts[news_index] if tab == &"news" else inbox[sms_index]
		if tab == &"sms":
			item["read"] = true
		heading_label.text = item.headline if tab == &"news" else item.sender
		source_label.text = item.source
		body_label.text = item.body
		footer_label.text = item.footer if tab == &"news" else "Прочитано"
		var current := news_index if tab == &"news" else sms_index
		var total := _posts.size() if tab == &"news" else inbox.size()
		page_label.text = "%d / %d" % [current + 1, total]
		previous_button.disabled = current == 0
		next_button.disabled = current == total - 1
	for key: StringName in tab_buttons:
		tab_buttons[key].set_pressed_no_signal(key == tab)
	tab_buttons[&"sms"].text = "СМС · %d" % unread if unread > 0 else "СМС"
	_refresh_hint()

func _refresh_hint() -> void:
	if hint_button == null:
		return
	hint_button.visible = not _opened and can_open()
	var key := "View" if PadInput.pad_active else "P"
	hint_button.text = "%s · ТЕЛЕФОН%s" % [key, " · %d" % unread if unread > 0 else ""]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		if _opened:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"phone"):
		if _opened:
			close_phone()
		else:
			open_phone()
		get_viewport().set_input_as_handled()
		return
	if not _opened:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		close_phone()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in [KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button and overlay.is_ancestor_of(focus):
				return # Оба края нажатия нужны обычному BaseButton, Tab — обходу фокуса.
		if event.pressed and key in [KEY_DOWN, KEY_RIGHT, KEY_UP, KEY_LEFT]:
			turn_page(1 if key in [KEY_DOWN, KEY_RIGHT] else -1)
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER: select_tab(&"news")
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER: select_tab(&"sms")
			JOY_BUTTON_DPAD_UP: turn_page(-1)
			JOY_BUTTON_DPAD_DOWN: turn_page(1)
			JOY_BUTTON_A:
				var focus := get_viewport().gui_get_focus_owner()
				if focus is Button and overlay.is_ancestor_of(focus):
					focus.pressed.emit()
	elif event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return # GUI переводит координаты в локальные и обрабатывает кнопки.
	get_viewport().set_input_as_handled()

func _page_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			turn_page(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_from = event.position
			elif not event.pressed and _dragging:
				_dragging = false
				_swipe(event.position - _drag_from)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_dragging = true
			_drag_from = event.position
		elif not event.pressed and _dragging:
			_dragging = false
			_swipe(event.position - _drag_from)
	page_control.accept_event()

func _swipe(delta: Vector2) -> void:
	var along := delta.x if absf(delta.x) > absf(delta.y) else delta.y
	if absf(along) >= SWIPE_DISTANCE:
		turn_page(-1 if along > 0.0 else 1)

func _build() -> void:
	_swipe_sound = AudioStreamPlayer.new()
	_swipe_sound.stream = SWIPE_SOUND
	_swipe_sound.volume_db = -10.0
	add_child(_swipe_sound)
	hint_button = _button("")
	hint_button.name = "PhoneHint"
	hint_button.focus_mode = Control.FOCUS_NONE
	hint_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint_button.offset_left = -350
	hint_button.offset_right = -35
	hint_button.offset_top = -100
	hint_button.offset_bottom = -44
	hint_button.pressed.connect(open_phone)
	add_child(hint_button)
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.045, 0.42)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	phone_panel = PanelContainer.new()
	phone_panel.name = "PhonePanel"
	phone_panel.anchor_left = 1.0
	phone_panel.anchor_right = 1.0
	phone_panel.anchor_top = 0.5
	phone_panel.anchor_bottom = 0.5
	phone_panel.offset_left = -630
	phone_panel.offset_right = -70
	phone_panel.offset_top = -470
	phone_panel.offset_bottom = 470
	var case_style := StyleBoxFlat.new()
	case_style.bg_color = CASE
	case_style.border_color = Color(0.35, 0.34, 0.32)
	case_style.set_border_width_all(3)
	case_style.set_corner_radius_all(32)
	case_style.content_margin_left = 16
	case_style.content_margin_right = 16
	case_style.content_margin_top = 26
	case_style.content_margin_bottom = 26
	phone_panel.add_theme_stylebox_override("panel", case_style)
	overlay.add_child(phone_panel)
	var screen := PanelContainer.new()
	screen.name = "Screen"
	var paper := DialogPanelScript.paper_style()
	paper.bg_color = PAPER
	paper.set_corner_radius_all(20)
	paper.content_margin_left = 24
	paper.content_margin_right = 24
	paper.content_margin_top = 18
	paper.content_margin_bottom = 18
	screen.add_theme_stylebox_override("panel", paper)
	phone_panel.add_child(screen)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	screen.add_child(column)
	column.add_child(_label("ГОРОД Н.                               −10 °C", 20))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	column.add_child(tabs)
	for key: StringName in [&"news", &"sms"]:
		var button := _button("НОВОСТИ" if key == &"news" else "СМС")
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_tab.bind(key))
		tabs.add_child(button)
		tab_buttons[key] = button
	page_control = Control.new()
	page_control.name = "Page"
	page_control.custom_minimum_size = Vector2(0, 470)
	page_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_control.mouse_filter = Control.MOUSE_FILTER_STOP
	page_control.gui_input.connect(_page_input)
	column.add_child(page_control)
	heading_label = _label("", 42)
	_place_label(heading_label, page_control, 4, 128)
	source_label = _label("", 23)
	source_label.modulate.a = 0.65
	_place_label(source_label, page_control, 136, 68)
	body_label = _label("", 32)
	_place_label(body_label, page_control, 210, 205)
	footer_label = _label("", 22)
	footer_label.modulate.a = 0.65
	_place_label(footer_label, page_control, 438, 32)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	column.add_child(navigation)
	previous_button = _button("←")
	previous_button.custom_minimum_size.x = 70
	previous_button.pressed.connect(turn_page.bind(-1))
	navigation.add_child(previous_button)
	page_label = _label("", 24)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	navigation.add_child(page_label)
	next_button = _button("→")
	next_button.custom_minimum_size.x = 70
	next_button.pressed.connect(turn_page.bind(1))
	navigation.add_child(next_button)
	var close := _button("УБРАТЬ ТЕЛЕФОН")
	close.pressed.connect(close_phone)
	column.add_child(close)
	column.add_child(_label("P / View — убрать    ↑↓ — листать", 19))
	overlay.hide()

func _fit_panel() -> void:
	var size := get_viewport().get_visible_rect().size
	var fit := minf(1.0, minf((size.y - 40.0) / 940.0, (size.x - 40.0) / 560.0))
	phone_panel.scale = Vector2.ONE * fit
	phone_panel.size = Vector2(560, 940)
	phone_panel.position = Vector2(size.x - 40.0 - 560.0 * fit, (size.y - 940.0 * fit) * 0.5)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _place_label(label: Label, parent: Control, top: float, height: float) -> void:
	label.anchor_right = 1.0
	label.offset_top = top
	label.offset_bottom = top + height
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 27)
	DialogPanelScript.style_button(button, false)
	return button

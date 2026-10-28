extends CanvasLayer
## Главное меню: НАЧАТЬ / ВЫХОД.
## POLISH-02 (п. 3): за меню — живой двор (тот же квартал LevelGeometry и свет, Бабка и белая «Лада»)
## с медленной облётной камерой; карточка в бумажном стиле HUD и строка управления по канону (раздел 7).
## Двор строится, пока меню видно, и освобождается при старте игры — мир миссии создаёт main.gd.

signal start_requested
signal quit_requested

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const Layout = preload("res://game/world/layout.gd")
const LevelGeometryScript = preload("res://game/world/level_geometry.gd")
const LightingScript = preload("res://game/world/lighting.gd")
const NpcScript = preload("res://game/npc/npc.gd")
const LadaVisual = preload("res://game/vehicles/lada_visual.gd")

const INK := Color(0.12, 0.10, 0.08)
## Облёт: камера качается дугой с севера на подъезд, Бабку и «Лада», не заходя в дома.
const ORBIT_PIVOT := Vector3(-43.0, 0.0, 101.0)
const ORBIT_RADIUS := 17.0
const ORBIT_HEIGHT := 6.5
const ORBIT_SWING := 0.55      # рад: размах дуги от севера
const ORBIT_SPEED := 0.045     # рад/с фазы качания

var start_button: Button
var backdrop: Node3D
var backdrop_camera: Camera3D
var card: PanelContainer
var _orbit_time := 0.0

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Лёгкое затемнение слева: карточка читается на любом кадре двора.
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.04, 0.06, 0.70))
	gradient.set_color(1, Color(0.03, 0.04, 0.06, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(0.75, 0.5)
	shade.texture = texture
	add_child(shade)
	card = PanelContainer.new()
	card.name = "MenuCard"
	var style := DialogPanelScript.paper_style()
	style.content_margin_left = 44
	style.content_margin_right = 44
	style.content_margin_top = 34
	style.content_margin_bottom = 34
	card.add_theme_stylebox_override("panel", style)
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = 120
	card.offset_right = 120 + 640
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	var title := _text("ШКЯ: ЗА ХЛЕБОМ", 64)
	box.add_child(title)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 3)
	box.add_child(rule)
	box.add_child(_text("Новосибирск, зима. Бабка ждёт хлеб.", 32))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)
	start_button = _button("НАЧАТЬ", start_requested.emit, true)
	box.add_child(start_button)
	box.add_child(_button("ВЫХОД", quit_requested.emit, false))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap2)
	box.add_child(_text("УПРАВЛЕНИЕ", 24))
	box.add_child(DialogPanelScript.controls_row(24))
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()

func _process(delta: float) -> void:
	if not backdrop_camera:
		return
	_orbit_time += delta
	var a := sin(_orbit_time * ORBIT_SPEED * TAU) * ORBIT_SWING
	var at := ORBIT_PIVOT + Vector3(sin(a) * ORBIT_RADIUS, ORBIT_HEIGHT, -cos(a) * ORBIT_RADIUS)
	backdrop_camera.position = at
	backdrop_camera.look_at(ORBIT_PIVOT + Vector3(0.0, 2.2, 3.0), Vector3.UP)

func _on_visibility_changed() -> void:
	if visible and is_inside_tree():
		start_button.grab_focus.call_deferred()
		if backdrop == null:
			_build_backdrop()
		DialogPanelScript.pop(card, 0.9)
	elif not visible:
		_free_backdrop()

## Двор за меню: тот же квартал и свет, что в игре; Бабка у подъезда и «Лада» на стоянке, без миссии.
func _build_backdrop() -> void:
	backdrop = Node3D.new()
	backdrop.name = "MenuBackdrop"
	var geometry: Node3D = LevelGeometryScript.new()
	geometry.name = "LevelGeometry"
	backdrop.add_child(geometry)
	var lighting: Node3D = LightingScript.new()
	lighting.name = "LightingAndWeather"
	backdrop.add_child(lighting)
	var babka: Node3D = NpcScript.new()
	babka.name = "Babka"
	babka.interaction_id = &"menu_babka"
	babka.solid = false
	babka.position = Layout.BABKA
	backdrop.add_child(babka)
	var car: Node3D = LadaVisual.build()
	car.name = "Lada"
	car.position = Layout.CAR_SPAWN
	car.rotation.y = Layout.CAR_SPAWN_YAW
	backdrop.add_child(car)
	backdrop_camera = Camera3D.new()
	backdrop_camera.name = "OrbitCamera"
	backdrop_camera.fov = 55.0
	backdrop.add_child(backdrop_camera)
	add_child(backdrop)
	backdrop_camera.make_current()
	_process(0.0)

func _free_backdrop() -> void:
	if backdrop:
		remove_child(backdrop)
		backdrop.queue_free()
		backdrop = null
		backdrop_camera = null

func _text(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	return label

func _button(text: String, action: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 72)
	DialogPanelScript.style_button(button, primary)
	button.add_theme_font_size_override("font_size", 36)
	button.pressed.connect(action)
	return button

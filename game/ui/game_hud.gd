extends CanvasLayer
## GameHUD (QUEST-01): бумажная карточка задачи слева сверху, круглая мини-карта слева снизу,
## жёлтый ромб к цели, скорость справа внизу в машине, «ХЛЕБ +1», панель финала.
## Только читает DemoWorld.get_hud_state() (C6) и положение камеры; состояние миссии не хранит.
## Координаты — в пространстве 1920x1080 (stretch canvas_items).
## POLISH-02: подсказка E — бумажная плашка с клавишей; тост, финал, «Конец демо» и ромб «выпрыгивают»;
## ромб прячется, когда цель в кадре и ближе DIAMOND_HIDE_DISTANCE (над Бабкой уже есть !/?);
## спидометр с дугой 0–100 км/ч; после финала — карточка «Конец демо» (её открывает QuestFlow).

const MinimapScript = preload("res://game/ui/minimap.gd")
const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const SuspicionMeterScript = preload("res://game/ui/suspicion_meter.gd")

const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)
const RED := Color(0.72, 0.12, 0.10)
const GREEN := Color(0.12, 0.55, 0.20)
const EDGE_MARGIN := 70.0
const DIAMOND_HIDE_DISTANCE := 15.0  # м: ближе и в кадре — ромб не нужен
const SPEED_FULL := 100.0            # км/ч: дуга спидометра заполнена

var title_label: Label
var task_label: Label
var prompt_label: Label
var toast_label: Label
var minimap: Control
var speed_gauge: Control
var speed_label: Label
var completion_panel: PanelContainer
var card: PanelContainer
var checkbox: Control
var strike: ColorRect
var diamond: Control

## Положение ромба в координатах холста 1920x1080 и признаки; для проверок и кадров.
var diamond_position := Vector2.ZERO
var diamond_visible := false
var diamond_clamped := false
var completion_dismissed := false
## Ромб спрятан, потому что цель в кадре и рядом (п. 17).
var diamond_near_hidden := false
var toast_card: PanelContainer
var completion_close: Button
var prompt_plate: PanelContainer
var end_panel: PanelContainer
var end_buttons: Dictionary = {}  # id -> Button: &"again", &"menu", &"stay"
## Стелс (EXT-01, C7): глаз + «!» справа вверху, подсказка, экран провала и тост — читает снимок мира.
var suspicion_meter: SuspicionMeter

signal completion_closed
## Карточка «Конец демо»: «ПОГУЛЯТЬ» — вернуть управление (QuestFlow), остальное — main.gd.
signal end_closed
signal restart_requested
signal menu_requested

var _checked := false
var _loaf_icon: Control
var _speed := 0.0
var _diamond_scale := 1.0
var _last_target: Variant = null
var _key_style: StyleBoxFlat

func _ready() -> void:
	layer = 5
	_build_card()
	_build_minimap()
	_build_diamond()
	_build_speed()
	_build_prompt()
	_build_toast()
	_build_completion()
	_build_end_card()
	suspicion_meter = SuspicionMeterScript.new()
	add_child(suspicion_meter)

func _process(delta: float) -> void:
	var world := get_parent()
	if not world or not world.has_method("get_hud_state"):
		return
	var state: Dictionary = world.get_hud_state()
	title_label.text = state["title"]
	task_label.text = state["task"]
	var complete: bool = state.get("complete", false)
	_checked = complete
	checkbox.queue_redraw()
	strike.visible = complete
	strike.offset_right = minf(task_label.size.x, task_label.get_theme_font("font").get_string_size(task_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x)
	var prompt: String = state["prompt"]
	if prompt != prompt_label.text:
		prompt_label.text = prompt
		_center_plate()
		prompt_plate.queue_redraw()
		if prompt != "":
			_pop_plate.call_deferred()
	prompt_label.visible = prompt != ""
	prompt_plate.visible = prompt != ""
	var toast: String = state.get("toast", "")
	toast_label.text = toast
	toast_label.visible = toast != ""
	if toast != "" and not toast_card.visible:
		DialogPanelScript.pop(toast_card, 0.3)
	toast_card.visible = toast != ""
	var speed: float = state.get("speed_kmh", -1.0)
	speed_gauge.visible = speed >= 0.0
	if speed >= 0.0:
		speed_label.text = str(roundi(speed))
		if absf(speed - _speed) > 0.05:
			_speed = speed
			speed_gauge.queue_redraw()
	var show_completion: bool = complete and not completion_dismissed
	if show_completion and not completion_panel.visible:
		completion_close.grab_focus.call_deferred()  # закрыть можно и E/Enter, не только мышью (QA-01, З2)
		DialogPanelScript.pop(completion_panel, 0.5)
	completion_panel.visible = show_completion
	_update_map_and_diamond(world, state.get("target_position", null), speed >= 0.0)
	suspicion_meter.update_from(state, delta)

func dismiss_completion() -> void:
	completion_dismissed = true
	completion_panel.visible = false

## Карточка «Конец демо» после панели финала (п. 11). Открывает QuestFlow, ввод при ней заблокирован.
func show_end_card() -> void:
	end_panel.visible = true
	DialogPanelScript.pop(end_panel, 0.5)
	end_buttons[&"again"].grab_focus.call_deferred()

func is_end_card_open() -> bool:
	return end_panel.visible

# --- карта и ромб ---

func _update_map_and_diamond(world: Node, target: Variant, in_car := false) -> void:
	var rig: CameraRig = world.get("camera_rig")
	var focus := Vector2.ZERO
	var yaw := 0.0
	if rig:
		yaw = rig.yaw
		if rig.target:
			focus = Vector2(rig.target.global_position.x, rig.target.global_position.z)
	minimap.set_view(focus, yaw, target, in_car)
	var was_visible := diamond_visible
	diamond_visible = false
	diamond_clamped = false
	diamond_near_hidden = false
	if rig and rig.camera and target is Vector3 and target != Vector3.INF:
		var camera := rig.camera
		var canvas := _canvas_size()
		var anchor: Vector3 = target + Vector3.UP * 3.8
		# Проекция считается здесь по трансформу и fov камеры (fov вертикальный), в координатах холста 1920x1080:
		# так результат не зависит от размера окна и совпадает в headless.
		var local := camera.global_transform.affine_inverse() * anchor
		var behind := local.z >= -0.01
		var rect := Rect2(Vector2.ZERO, canvas).grow(-EDGE_MARGIN)
		var p: Vector2
		if behind:
			# За спиной: прижимаем к нижнему краю со стороны цели, чтобы ромб говорил «развернись».
			p = Vector2(canvas.x * 0.5 + signf(local.x if local.x != 0.0 else 1.0) * canvas.x, rect.end.y)
		else:
			var half_h := tan(deg_to_rad(camera.fov) * 0.5)
			var ndc := Vector2(local.x / (-local.z) / (half_h * canvas.x / canvas.y), local.y / (-local.z) / half_h)
			p = Vector2((ndc.x + 1.0) * 0.5 * canvas.x, (1.0 - ndc.y) * 0.5 * canvas.y)
		diamond_clamped = behind or not rect.has_point(p)
		p = Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		diamond_position = _avoid_hud(p)
		# Цель в кадре и рядом: ромб не нужен, над Бабкой уже !/?, машина и киоск видны сами (п. 17).
		var distance := focus.distance_to(Vector2(target.x, target.z))
		diamond_near_hidden = not diamond_clamped and distance < DIAMOND_HIDE_DISTANCE
		diamond_visible = not diamond_near_hidden
		# Новая цель (скачок больше 5 м) или ромб вернулся — «выпрыгнуть».
		var jumped: bool = _last_target == null or (_last_target as Vector3).distance_to(target) > 5.0
		if diamond_visible and (jumped or not was_visible):
			_diamond_scale = 0.3
			create_tween().tween_property(self, "_diamond_scale", 1.0, DialogPanelScript.POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_last_target = target
	else:
		_last_target = null
	diamond.visible = diamond_visible
	diamond.queue_redraw()

## Ромб не рисуется поверх карточки задачи, мини-карты и спидометра: сдвигается за их край.
func _avoid_hud(p: Vector2) -> Vector2:
	var card_zone := Rect2(20, 12, 600, 190)
	if card_zone.grow(24.0).has_point(p):
		p.x = card_zone.end.x + 40.0
	for zone in [Rect2(20, 770, 300, 300), Rect2(1630, 790, 270, 270)]:
		if Rect2(zone).grow(24.0).has_point(p):
			p.y = zone.position.y - 40.0
	return p

func _canvas_size() -> Vector2:
	var content := Vector2(get_window().content_scale_size)
	return content if content != Vector2.ZERO else Vector2(1920, 1080)

# --- сборка ---

func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "ObjectiveCard"
	card.position = Vector2(40, 32)
	card.custom_minimum_size = Vector2(560, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", DialogPanelScript.paper_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	title_label = _label(40)
	title_label.add_theme_color_override("font_color", INK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.custom_minimum_size = Vector2(300, 0)
	header.add_child(title_label)
	var skyline := Control.new()
	skyline.custom_minimum_size = Vector2(90, 44)
	skyline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skyline.draw.connect(func():
		for r in [Rect2(0, 22, 18, 22), Rect2(22, 8, 16, 36), Rect2(42, 26, 18, 18), Rect2(64, 0, 14, 44)]:
			skyline.draw_rect(r, INK)
		for r in [Rect2(26, 14, 4, 5), Rect2(32, 14, 4, 5), Rect2(68, 8, 3, 5), Rect2(68, 20, 3, 5)]:
			skyline.draw_rect(r, PAPER))
	header.add_child(skyline)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	checkbox = Control.new()
	checkbox.custom_minimum_size = Vector2(30, 30)
	checkbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	checkbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	checkbox.draw.connect(func():
		checkbox.draw_rect(Rect2(2, 2, 26, 26), INK, false, 3.0)
		if _checked:
			checkbox.draw_polyline(PackedVector2Array([Vector2(6, 15), Vector2(13, 23), Vector2(27, 4)]), RED, 4.0))
	row.add_child(checkbox)
	task_label = _label(32)
	task_label.add_theme_color_override("font_color", INK)
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_label.custom_minimum_size = Vector2(450, 0)
	task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(task_label)
	strike = ColorRect.new()
	strike.name = "Strike"
	strike.color = RED
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike.anchor_right = 0.0
	strike.anchor_top = 0.5
	strike.anchor_bottom = 0.5
	strike.offset_top = -1.5
	strike.offset_bottom = 1.5
	strike.visible = false
	task_label.add_child(strike)
	add_child(card)

func _build_minimap() -> void:
	minimap = MinimapScript.new()
	minimap.position = Vector2(34, 1080 - 292)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)

func _build_diamond() -> void:
	diamond = Control.new()
	diamond.name = "TargetDiamond"
	diamond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diamond.visible = false
	diamond.draw.connect(func():
		var r := 20.0 * _diamond_scale
		var points := PackedVector2Array([diamond_position + Vector2(0, -r), diamond_position + Vector2(r, 0), diamond_position + Vector2(0, r), diamond_position + Vector2(-r, 0)])
		diamond.draw_colored_polygon(points, YELLOW)
		var outline := points.duplicate()
		outline.append(points[0])
		diamond.draw_polyline(outline, INK, 3.0))
	add_child(diamond)

func _build_speed() -> void:
	speed_gauge = Control.new()
	speed_gauge.name = "SpeedGauge"
	speed_gauge.custom_minimum_size = Vector2(240, 240)
	speed_gauge.size = Vector2(240, 240)
	speed_gauge.position = Vector2(1920 - 240 - 40, 1080 - 280)
	speed_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_gauge.visible = false
	speed_gauge.draw.connect(func():
		var c := Vector2(120, 120)
		speed_gauge.draw_circle(c, 116.0, Color(0.10, 0.10, 0.11))
		speed_gauge.draw_arc(c, 112.0, 0.0, TAU, 48, Color(0.93, 0.87, 0.72), 4.0, true)
		# Дуга 0–100 км/ч: тёмная дорожка, заливка по скорости жёлтым к оранжевому, риски каждые 20 км/ч.
		var start := deg_to_rad(135.0)
		var sweep := deg_to_rad(270.0)
		speed_gauge.draw_arc(c, 94.0, start, start + sweep, 48, Color(0.24, 0.24, 0.26), 14.0, true)
		var k := clampf(_speed / SPEED_FULL, 0.0, 1.0)
		if k > 0.004:
			var fill := YELLOW.lerp(Color(0.95, 0.42, 0.10), k)
			speed_gauge.draw_arc(c, 94.0, start, start + sweep * k, maxi(3, int(48 * k)), fill, 14.0, true)
		for i in 6:
			var a := start + sweep * i / 5.0
			var dir := Vector2(cos(a), sin(a))
			speed_gauge.draw_line(c + dir * 102.0, c + dir * 110.0, Color(0.93, 0.87, 0.72), 3.0, true))
	add_child(speed_gauge)
	speed_label = _label(72)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.position = Vector2(0, 62)
	speed_label.size = Vector2(240, 90)
	speed_label.add_theme_color_override("font_color", Color.WHITE)
	speed_gauge.add_child(speed_label)
	var unit := _label(26)
	unit.text = "КМ/Ч"
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit.position = Vector2(0, 150)
	unit.size = Vector2(240, 40)
	unit.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	speed_gauge.add_child(unit)

## Подсказка E (п. 9): бумажная плашка у нижнего края по центру (под Илюшей, не на нём); первая буква «E» — на колпачке.
## prompt_label хранит подсказку целиком («E — ПОГОВОРИТЬ»), колпачок рисуется под буквой.
func _build_prompt() -> void:
	prompt_plate = PanelContainer.new()
	prompt_plate.name = "PromptPlate"
	prompt_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := DialogPanelScript.paper_style()
	style.content_margin_left = 34
	style.content_margin_right = 26
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	prompt_plate.add_theme_stylebox_override("panel", style)
	prompt_plate.anchor_left = 0.5
	prompt_plate.anchor_right = 0.5
	prompt_plate.anchor_top = 1.0
	prompt_plate.anchor_bottom = 1.0
	prompt_plate.offset_top = -34
	prompt_plate.offset_bottom = -34
	prompt_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_plate.visible = false
	_key_style = StyleBoxFlat.new()
	_key_style.bg_color = Color(0.99, 0.97, 0.90)
	_key_style.border_color = INK
	_key_style.set_border_width_all(3)
	_key_style.border_width_bottom = 6
	_key_style.set_corner_radius_all(7)
	prompt_plate.draw.connect(_draw_key_cap)
	prompt_label = _label(36)
	prompt_label.name = "Prompt"
	prompt_label.add_theme_color_override("font_color", INK)
	# Пробел шире: между колпачком «E» и тире остаётся воздух.
	var wide := FontVariation.new()
	wide.base_font = DialogPanelScript.ui_font()
	wide.spacing_space = 7
	prompt_label.add_theme_font_override("font", wide)
	prompt_plate.add_child(prompt_label)
	add_child(prompt_plate)

func _pop_plate() -> void:
	_center_plate()
	DialogPanelScript.pop(prompt_plate, 0.6)

## Плашка по ширине текста и точно по центру экрана.
func _center_plate() -> void:
	var width := prompt_plate.get_combined_minimum_size().x
	prompt_plate.offset_left = -width * 0.5
	prompt_plate.offset_right = width * 0.5
	prompt_plate.reset_size()

func _draw_key_cap() -> void:
	if not prompt_label.text.begins_with("E "):
		return
	var font := prompt_label.get_theme_font("font")
	var glyph := font.get_string_size("E", HORIZONTAL_ALIGNMENT_LEFT, -1, 36)
	var top := prompt_label.position.y + (prompt_label.size.y - glyph.y) * 0.5
	var rect := Rect2(prompt_label.position.x - 13.0, top - 4.0, glyph.x + 22.0, glyph.y + 10.0)
	prompt_plate.draw_style_box(_key_style, rect)

func _build_toast() -> void:
	toast_card = PanelContainer.new()
	toast_card.name = "ToastCard"
	toast_card.visible = false
	toast_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_card.add_theme_stylebox_override("panel", DialogPanelScript.paper_style())
	toast_card.anchor_left = 1.0
	toast_card.anchor_right = 1.0
	toast_card.offset_left = -360
	toast_card.offset_right = -40
	toast_card.offset_top = 170
	toast_card.offset_bottom = 260
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	toast_card.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(96, 56)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_loaf.bind(icon, 0.5, false))
	row.add_child(icon)
	toast_label = _label(44)
	toast_label.name = "Toast"
	toast_label.add_theme_color_override("font_color", INK)
	toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toast_label.visible = false
	row.add_child(toast_label)
	add_child(toast_card)

func _build_completion() -> void:
	completion_panel = PanelContainer.new()
	completion_panel.name = "CompletionPanel"
	completion_panel.visible = false
	completion_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	completion_panel.add_theme_stylebox_override("panel", DialogPanelScript.paper_style())
	completion_panel.anchor_left = 0.5
	completion_panel.anchor_right = 0.5
	completion_panel.anchor_top = 1.0
	completion_panel.anchor_bottom = 1.0
	completion_panel.offset_left = -430
	completion_panel.offset_right = 430
	completion_panel.offset_top = -330
	completion_panel.offset_bottom = -50
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	completion_panel.add_child(row)
	_loaf_icon = Control.new()
	_loaf_icon.custom_minimum_size = Vector2(210, 150)
	_loaf_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_loaf_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loaf_icon.draw.connect(_draw_loaf.bind(_loaf_icon, 1.0, true))
	row.add_child(_loaf_icon)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(column)
	var head := _label(46)
	head.text = "ЗАДАНИЕ ВЫПОЛНЕНО"
	head.add_theme_color_override("font_color", INK)
	column.add_child(head)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var quest := _label(38)
	quest.text = "ЗА ХЛЕБОМ"
	quest.add_theme_color_override("font_color", INK)
	column.add_child(quest)
	var reward := HBoxContainer.new()
	column.add_child(reward)
	var reward_text := _label(32)
	reward_text.text = "Награда: "
	reward_text.add_theme_color_override("font_color", INK)
	reward.add_child(reward_text)
	var xp := _label(40)
	xp.name = "Reward"
	xp.text = "+50 опыта"
	xp.add_theme_color_override("font_color", GREEN)
	reward.add_child(xp)
	completion_close = Button.new()
	completion_close.name = "CompletionClose"
	completion_close.text = "ЗАКРЫТЬ"
	completion_close.custom_minimum_size = Vector2(0, 54)
	DialogPanelScript.style_button(completion_close, true)
	completion_close.pressed.connect(func():
		dismiss_completion()
		completion_closed.emit())
	column.add_child(completion_close)
	add_child(completion_panel)

## «Конец демо» (п. 11): по центру, «ЕЩЁ РАЗ» — заново с NOT_STARTED, «В МЕНЮ», «ПОГУЛЯТЬ» — остаться в мире
## (после финала у Бабки обычная реплика, покупки нет — сценарий 6 канона).
func _build_end_card() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "EndCard"
	end_panel.visible = false
	end_panel.add_theme_stylebox_override("panel", DialogPanelScript.paper_style())
	end_panel.anchor_left = 0.5
	end_panel.anchor_right = 0.5
	end_panel.anchor_top = 0.5
	end_panel.anchor_bottom = 0.5
	end_panel.offset_left = -420
	end_panel.offset_right = 420
	end_panel.offset_top = 0
	end_panel.offset_bottom = 0
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH  # высота по содержимому
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	end_panel.add_child(column)
	var head := _label(56)
	head.text = "КОНЕЦ ДЕМО"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", INK)
	column.add_child(head)
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var line := _label(32)
	line.text = "Хлеб у Бабки. Спасибо за игру!"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_color_override("font_color", INK)
	column.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	for spec in [[&"again", "ЕЩЁ РАЗ", true], [&"menu", "В МЕНЮ", false], [&"stay", "ПОГУЛЯТЬ", false]]:
		var button := Button.new()
		button.name = "End_" + String(spec[0])
		button.text = spec[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 60)
		DialogPanelScript.style_button(button, spec[2])
		button.pressed.connect(_on_end_button.bind(spec[0]))
		row.add_child(button)
		end_buttons[spec[0]] = button
	add_child(end_panel)

func _on_end_button(id: StringName) -> void:
	end_panel.visible = false
	match id:
		&"again": restart_requested.emit()
		&"menu": menu_requested.emit()
		&"stay": end_closed.emit()

## Иконка в панели финала (кадр 10). Это значок награды, а не предмет в руках Илюши.
func _draw_loaf(canvas: Control, k: float, with_check: bool) -> void:
	var body := Color(0.80, 0.52, 0.22)
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append((Vector2(100, 78) + Vector2(cos(a) * 92.0, sin(a) * 46.0)) * k)
	canvas.draw_colored_polygon(points, body)
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline, INK, 4.0 * k + 1.0)
	for x in [58, 92, 126]:
		canvas.draw_line(Vector2(x, 50) * k, Vector2(x + 14, 78) * k, Color(0.95, 0.80, 0.50), 5.0 * k)
	if with_check:
		canvas.draw_circle(Vector2(170, 122), 28.0, Color(0.45, 0.75, 0.35))
		canvas.draw_polyline(PackedVector2Array([Vector2(158, 122), Vector2(167, 132), Vector2(184, 112)]), INK, 5.0)

func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

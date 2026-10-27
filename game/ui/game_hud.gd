extends CanvasLayer
## GameHUD (QUEST-01): бумажная карточка задачи слева сверху, круглая мини-карта слева снизу,
## жёлтый ромб к цели, скорость справа внизу в машине, «ХЛЕБ +1», панель финала.
## Только читает DemoWorld.get_hud_state() (C6) и положение камеры; состояние миссии не хранит.
## Координаты — в пространстве 1920x1080 (stretch canvas_items).

const MinimapScript = preload("res://game/ui/minimap.gd")
const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")

const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)
const RED := Color(0.72, 0.12, 0.10)
const GREEN := Color(0.12, 0.55, 0.20)
const EDGE_MARGIN := 70.0

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

var _checked := false
var _loaf_icon: Control

func _ready() -> void:
	layer = 5
	_build_card()
	_build_minimap()
	_build_diamond()
	_build_speed()
	_build_prompt()
	_build_toast()
	_build_completion()

func _process(_delta: float) -> void:
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
	prompt_label.text = state["prompt"]
	prompt_label.visible = state["prompt"] != ""
	var toast: String = state.get("toast", "")
	toast_label.text = toast
	toast_label.visible = toast != ""
	var speed: float = state.get("speed_kmh", -1.0)
	speed_gauge.visible = speed >= 0.0
	if speed >= 0.0:
		speed_label.text = str(roundi(speed))
	completion_panel.visible = complete and not completion_dismissed
	_update_map_and_diamond(world, state.get("target_position", null))

func dismiss_completion() -> void:
	completion_dismissed = true
	completion_panel.visible = false

# --- карта и ромб ---

func _update_map_and_diamond(world: Node, target: Variant) -> void:
	var rig: CameraRig = world.get("camera_rig")
	var focus := Vector2.ZERO
	var yaw := 0.0
	if rig:
		yaw = rig.yaw
		if rig.target:
			focus = Vector2(rig.target.global_position.x, rig.target.global_position.z)
	minimap.set_view(focus, yaw, target)
	diamond_visible = false
	diamond_clamped = false
	if rig and rig.camera and target is Vector3 and target != Vector3.INF:
		var camera := rig.camera
		var canvas := _canvas_size()
		var anchor: Vector3 = target + Vector3.UP * 2.6
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
		diamond_position = Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		diamond_visible = true
	diamond.visible = diamond_visible
	diamond.queue_redraw()

func _canvas_size() -> Vector2:
	var content := Vector2(get_window().content_scale_size)
	return content if content != Vector2.ZERO else Vector2(1920, 1080)

# --- сборка ---

func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "ObjectiveCard"
	card.position = Vector2(40, 32)
	card.custom_minimum_size = Vector2(500, 0)
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
	row.add_child(task_label)
	strike = ColorRect.new()
	strike.name = "Strike"
	strike.color = RED
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike.anchor_right = 1.0
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
		var r := 20.0
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
		speed_gauge.draw_arc(c, 90.0, deg_to_rad(135.0), deg_to_rad(405.0), 40, Color(0.7, 0.7, 0.7), 2.0, true))
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

func _build_prompt() -> void:
	prompt_label = _label(36)
	prompt_label.name = "Prompt"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_top = -160
	prompt_label.offset_bottom = -110
	prompt_label.offset_left = -400
	prompt_label.offset_right = 400
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	prompt_label.add_theme_constant_override("outline_size", 8)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(prompt_label)

func _build_toast() -> void:
	toast_label = _label(84)
	toast_label.name = "Toast"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 240
	toast_label.offset_bottom = 350
	toast_label.offset_left = -400
	toast_label.offset_right = 400
	toast_label.add_theme_color_override("font_color", YELLOW)
	toast_label.add_theme_constant_override("outline_size", 14)
	toast_label.add_theme_color_override("font_outline_color", INK)
	toast_label.visible = false
	add_child(toast_label)

func _build_completion() -> void:
	completion_panel = PanelContainer.new()
	completion_panel.name = "CompletionPanel"
	completion_panel.visible = false
	completion_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	completion_panel.add_theme_stylebox_override("panel", DialogPanelScript.paper_style())
	completion_panel.anchor_left = 0.5
	completion_panel.anchor_right = 0.5
	completion_panel.anchor_top = 0.0
	completion_panel.anchor_bottom = 0.0
	completion_panel.offset_left = -400
	completion_panel.offset_right = 400
	completion_panel.offset_top = 300
	completion_panel.offset_bottom = 520
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	completion_panel.add_child(row)
	_loaf_icon = Control.new()
	_loaf_icon.custom_minimum_size = Vector2(210, 150)
	_loaf_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_loaf_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loaf_icon.draw.connect(_draw_loaf)
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
	add_child(completion_panel)

## Иконка в панели финала (кадр 10). Это значок награды, а не предмет в руках Илюши.
func _draw_loaf() -> void:
	var body := Color(0.80, 0.52, 0.22)
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(Vector2(100, 78) + Vector2(cos(a) * 92.0, sin(a) * 46.0))
	_loaf_icon.draw_colored_polygon(points, body)
	var outline := points.duplicate()
	outline.append(points[0])
	_loaf_icon.draw_polyline(outline, INK, 4.0)
	for x in [58, 92, 126]:
		_loaf_icon.draw_line(Vector2(x, 50), Vector2(x + 14, 78), Color(0.95, 0.80, 0.50), 5.0)
	_loaf_icon.draw_circle(Vector2(170, 122), 28.0, Color(0.45, 0.75, 0.35))
	_loaf_icon.draw_polyline(PackedVector2Array([Vector2(158, 122), Vector2(167, 132), Vector2(184, 112)]), INK, 5.0)

func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

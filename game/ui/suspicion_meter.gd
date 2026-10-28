class_name SuspicionMeter
extends Control
## Индикатор подозрения (EXT-01 S, референс e04): жёлтый глаз + «!» справа вверху в бумажном стиле HUD.
## Появляется, когда suspicion > 0, зрачок и «!» наливаются жёлтым по шкале, под глазом — полоска уровня.
## При первом появлении — подсказка «Тебя заметили. Отойди, пока это ни к чему не обязывает» на HINT_SECONDS.
## Экран провала: затемнение и «ВАШ МАРШРУТ УТОЧНЁН» (Tween), пока мир держит stealth_fail;
## затем тост stealth_toast («ВЫ ОСТАЛИСЬ ПЕШЕХОДОМ. ХЛЕБ ПРИ ВАС») из снимка HUD (C6/C7).
## Только читает снимок через update_from(); состояния стелса не хранит.
## EXT-01 fix4 (четвёртая приёмка P3): подсказка «Тебя заметили…» гаснет, как только открыт экран провала, и не
## загорается, если индикатор впервые появился сразу тревогой (alert_now: вышел из машины на глазах) — тогда она
## остаётся на первое настоящее «насторожились»; после респавна не висит.

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")

const PAPER := Color(0.93, 0.87, 0.72)
const PAPER_LIGHT := Color(0.99, 0.97, 0.90)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)
const RED := Color(0.72, 0.12, 0.10)
const HINT_TEXT := "Тебя заметили. Отойди, пока это ни к чему не обязывает"
const HINT_SECONDS := 3.0
const FAIL_TEXT := "ВАШ МАРШРУТ УТОЧНЁН"
const FAIL_FADE_IN := 0.35
const FAIL_FADE_OUT := 0.4
const FAIL_DARK := 0.86
const SHOW_SECONDS := 0.2      # появление индикатора
const HIDE_SECONDS := 0.5      # исчезновение, когда шкала вернулась в ноль
const PLATE_SIZE := Vector2(236, 112)

var plate: PanelContainer
var badge: Control
var hint_plate: PanelContainer
var hint_label: Label
var fail_layer: Control
var fail_rect: ColorRect
var fail_label: Label
var toast_plate: PanelContainer
var toast_label: Label

## Для проверок: индикатор показан (альфа > 0), подсказка показана один раз, экран провала открыт.
var hint_used := false
var fail_shown := false

var _suspicion := 0.0
var _alpha := 0.0
var _hint_left := 0.0
var _fail_tween: Tween

func _ready() -> void:
	name = "SuspicionMeter"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_plate()
	_build_hint()
	_build_toast()
	_build_fail()

## Снимок HUD (C6): suspicion, stealth_state, stealth_fail, stealth_toast.
func update_from(state: Dictionary, delta: float) -> void:
	_suspicion = clampf(float(state.get("suspicion", 0.0)), 0.0, 1.0)
	var stealth_state: StringName = state.get("stealth_state", &"safe")
	var wanted := 1.0 if (_suspicion > 0.0 or stealth_state != &"safe") else 0.0
	var failing: bool = state.get("stealth_fail", false)
	if wanted > _alpha:
		if _alpha <= 0.0 and not hint_used and not failing and stealth_state != &"alert":
			hint_used = true
			_hint_left = HINT_SECONDS
			DialogPanelScript.pop(hint_plate, 0.6)
		if _alpha <= 0.0:
			DialogPanelScript.pop(plate, 0.6)
		_alpha = minf(_alpha + delta / SHOW_SECONDS, 1.0)
	elif wanted < _alpha:
		_alpha = maxf(_alpha - delta / HIDE_SECONDS, 0.0)
	plate.modulate.a = _alpha
	plate.visible = _alpha > 0.0
	badge.queue_redraw()
	_hint_left = 0.0 if failing else maxf(_hint_left - delta, 0.0)
	hint_plate.visible = _hint_left > 0.0
	if failing != fail_shown:
		fail_shown = failing
		_animate_fail(failing)
	var toast: String = state.get("stealth_toast", "")
	if toast != toast_label.text:
		toast_label.text = toast
		if toast != "":
			DialogPanelScript.pop(toast_plate, 0.5)
	toast_plate.visible = toast != ""

func is_showing() -> bool:
	return _alpha > 0.0

func is_hint_showing() -> bool:
	return hint_plate.visible

# --- сборка ---

func _build_plate() -> void:
	plate = PanelContainer.new()
	plate.name = "SuspicionPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := DialogPanelScript.paper_style()
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.position = Vector2(1920 - 40 - PLATE_SIZE.x, 32)
	plate.custom_minimum_size = PLATE_SIZE
	plate.visible = false
	plate.modulate.a = 0.0
	badge = Control.new()
	badge.name = "EyeBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = PLATE_SIZE - Vector2(28, 20)
	badge.draw.connect(_draw_badge)
	plate.add_child(badge)
	add_child(plate)

func _build_hint() -> void:
	hint_plate = PanelContainer.new()
	hint_plate.name = "SuspicionHint"
	hint_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := DialogPanelScript.paper_style()
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	hint_plate.add_theme_stylebox_override("panel", style)
	hint_plate.anchor_left = 1.0
	hint_plate.anchor_right = 1.0
	hint_plate.offset_left = -800   # 760 px: подсказка из 42 знаков шрифтом 30 px обрезалась при 520 (приёмка EXT-01)
	hint_plate.offset_right = -40
	hint_plate.offset_top = 32 + PLATE_SIZE.y + 14
	hint_plate.offset_bottom = hint_plate.offset_top + 64
	hint_plate.visible = false
	hint_label = _label(30)
	hint_label.name = "SuspicionHintText"
	hint_label.text = HINT_TEXT
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.add_theme_color_override("font_color", INK)
	hint_plate.add_child(hint_label)
	add_child(hint_plate)

## Тост после респавна: бумажная плашка по центру, ниже карточки задачи (она слева до y ≈ 190) и выше
## подсказки E у нижнего края; «ХЛЕБ +1» живёт справа и не пересекается.
func _build_toast() -> void:
	toast_plate = PanelContainer.new()
	toast_plate.name = "StealthToast"
	toast_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_plate.add_theme_stylebox_override("panel", DialogPanelScript.paper_style())
	toast_plate.anchor_left = 0.5
	toast_plate.anchor_right = 0.5
	toast_plate.offset_left = -440
	toast_plate.offset_right = 440
	toast_plate.offset_top = 215
	toast_plate.offset_bottom = 305
	toast_plate.visible = false
	toast_label = _label(38)
	toast_label.name = "StealthToastText"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast_label.add_theme_color_override("font_color", INK)
	toast_plate.add_child(toast_label)
	add_child(toast_plate)

func _build_fail() -> void:
	fail_layer = Control.new()
	fail_layer.name = "StealthFail"
	fail_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fail_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fail_layer.visible = false
	fail_layer.modulate.a = 0.0
	fail_rect = ColorRect.new()
	fail_rect.name = "Dark"
	fail_rect.color = Color(0.03, 0.03, 0.04, FAIL_DARK)
	fail_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fail_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fail_layer.add_child(fail_rect)
	fail_label = _label(104)
	fail_label.name = "StealthFailText"
	fail_label.text = FAIL_TEXT
	fail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fail_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fail_label.add_theme_color_override("font_color", YELLOW)
	fail_label.add_theme_color_override("font_outline_color", INK)
	fail_label.add_theme_constant_override("outline_size", 10)
	fail_layer.add_child(fail_label)
	add_child(fail_layer)

func _animate_fail(on: bool) -> void:
	if _fail_tween and _fail_tween.is_valid():
		_fail_tween.kill()
	_fail_tween = create_tween()
	if on:
		fail_layer.visible = true
		fail_label.scale = Vector2.ONE * 0.9
		fail_label.pivot_offset = fail_label.size * 0.5
		_fail_tween.set_parallel(true)
		_fail_tween.tween_property(fail_layer, "modulate:a", 1.0, FAIL_FADE_IN)
		_fail_tween.tween_property(fail_label, "scale", Vector2.ONE, FAIL_FADE_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_fail_tween.tween_property(fail_layer, "modulate:a", 0.0, FAIL_FADE_OUT)
		_fail_tween.tween_callback(func(): fail_layer.visible = false)

# --- рисование: глаз и «!» ---

func _draw_badge() -> void:
	var k := _suspicion
	var cx := 72.0
	var cy := 44.0
	var half_w := 54.0
	var half_h := 30.0
	# Миндалевидный глаз: верхняя и нижняя дуги.
	var points := PackedVector2Array()
	for i in 25:
		var t := PI * i / 24.0
		points.append(Vector2(cx - half_w + 2.0 * half_w * i / 24.0, cy - half_h * sin(t)))
	for i in 25:
		var t := PI * i / 24.0
		points.append(Vector2(cx + half_w - 2.0 * half_w * i / 24.0, cy + half_h * sin(t)))
	badge.draw_colored_polygon(points, PAPER_LIGHT)
	# Радужка: бледная, по шкале наливается жёлтым и краснеет у единицы.
	var iris := PAPER.lerp(YELLOW, clampf(k * 2.0, 0.0, 1.0)).lerp(RED, clampf((k - 0.7) / 0.3, 0.0, 1.0) * 0.7)
	badge.draw_circle(Vector2(cx, cy), 24.0, iris)
	badge.draw_arc(Vector2(cx, cy), 24.0, 0.0, TAU, 32, INK, 3.0, true)
	badge.draw_circle(Vector2(cx, cy), 10.0 + 4.0 * k, INK)
	badge.draw_circle(Vector2(cx - 6.0, cy - 7.0), 3.5, PAPER_LIGHT)
	var outline := points.duplicate()
	outline.append(points[0])
	badge.draw_polyline(outline, INK, 4.0, true)
	# Полоска уровня под глазом: тёмная дорожка, заливка жёлтым к красному.
	var bar := Rect2(cx - half_w, cy + half_h + 8.0, 2.0 * half_w, 10.0)
	badge.draw_rect(bar, Color(0.24, 0.22, 0.18))
	if k > 0.005:
		badge.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), YELLOW.lerp(RED, k))
	badge.draw_rect(bar, INK, false, 2.0)
	# «!» справа: наливается жёлтым по шкале, бледный — пока только насторожились.
	var mark := PAPER.lerp(YELLOW, clampf(0.25 + k, 0.0, 1.0))
	var stem := PackedVector2Array([Vector2(160, 8), Vector2(188, 8), Vector2(182, 58), Vector2(166, 58)])
	badge.draw_colored_polygon(stem, mark)
	var stem_outline := stem.duplicate()
	stem_outline.append(stem[0])
	badge.draw_polyline(stem_outline, INK, 3.0, true)
	badge.draw_circle(Vector2(174, 76), 10.0, mark)
	badge.draw_arc(Vector2(174, 76), 10.0, 0.0, TAU, 24, INK, 3.0, true)

func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

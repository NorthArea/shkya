extends CanvasLayer
## PERF-HUD-01: real wall-clock intervals, independent of time_scale and fixed-fps delta.
const FrameWindow = preload("res://game/ui/frame_window.gd")
const REFRESH_USEC := 250000
const WIDTH := 800.0
const TOP := 4.0
const HEIGHT := 60.0
var frames := FrameWindow.new()
var panel: PanelContainer
var metrics: Label
var refresh_count := 0
var _previous_usec := 0
var _refresh_at := 0

func _ready() -> void:
	name = "PerformanceOverlay"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -WIDTH - 24.0
	panel.offset_right = -24.0
	panel.offset_top = TOP
	panel.offset_bottom = TOP + HEIGHT
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.07, 0.88)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	metrics = Label.new()
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metrics.add_theme_font_size_override("font_size", 18)
	metrics.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0))
	metrics.text = "FPS: сбор…   Кадр: н/д   Пик (240 кадров): н/д\nCPU: н/д   Физика: н/д   GPU: н/д   Вызовы: н/д   Примитивы: н/д   [F3]"
	panel.add_child(metrics)

func _process(_delta: float) -> void:
	sample_at(Time.get_ticks_usec())

func sample_at(now_usec: int) -> void:
	if _previous_usec == 0:
		_previous_usec = now_usec
		return
	if now_usec <= _previous_usec:
		return
	frames.add_interval_usec(now_usec - _previous_usec)
	_previous_usec = now_usec
	if now_usec < _refresh_at or not panel.visible:
		return
	_refresh_at = now_usec + REFRESH_USEC
	var stats := frames.snapshot()
	metrics.text = "FPS: %.1f   Кадр: %.2f мс   Пик (240 кадров): %.2f мс\nCPU: %.2f мс   Физика: %.2f мс   GPU: н/д   Вызовы: %d   Примитивы: %d   [F3]" % [
		stats.fps, stats.frame_ms, stats.worst_ms,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	refresh_count += 1

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

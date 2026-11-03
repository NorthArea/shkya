extends RefCounted
## Agent-only measurement window and display evidence. Never loaded by the game.

const SETTLE_FRAMES := 10
const SETTLE_SECONDS := 1.0
const INTERNAL_SIZE_TIMEOUT_MS := 3000
const Settings = preload("res://game/display_settings.gd")

class InternalSizeCapture extends CompositorEffect:
	var _size := Vector2i.ZERO
	var _mutex := Mutex.new()
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(_kind: int, data: RenderData) -> void:
		var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
		if buffers == null:
			return
		_mutex.lock()
		_size = buffers.get_internal_size()
		enabled = false
		_mutex.unlock()
	func snapshot() -> Vector2i:
		_mutex.lock()
		var size := _size
		_mutex.unlock()
		return size

static func window_policy(hint: String, borderless_fullscreen: bool, platform: String) -> Dictionary:
	var valid := hint in ["", "unspecified", "windowed", "fullscreen"]
	var windowed := hint == "windowed" and not borderless_fullscreen
	return {"valid": valid, "launcher_hint": hint, "borderless_fullscreen_requested": borderless_fullscreen,
		"declared_mode": "explicit_windowed" if windowed else ("agent_borderless_fullscreen" if platform == "macOS" else "native_fullscreen")}

static func fullscreen_rect(screen: Rect2i, usable: Rect2i, platform: String) -> Rect2i:
	var safe_top := clampi(usable.position.y - screen.position.y, 0, screen.size.y) if platform == "macOS" else 0
	return Rect2i(screen.position + Vector2i(0, safe_top), screen.size - Vector2i(0, safe_top))

static func screen_rect(window: Window) -> Rect2i:
	var screen := window.current_screen
	return fullscreen_rect(Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen)),
		DisplayServer.screen_get_usable_rect(screen), OS.get_name())

static func apply_window(window: Window, policy: Dictionary) -> void:
	if policy.declared_mode == "explicit_windowed":
		return
	if policy.declared_mode == "agent_borderless_fullscreen":
		var target := screen_rect(window)
		window.mode = Window.MODE_WINDOWED
		window.borderless = true
		window.size = target.size
		window.position = target.position
	else:
		window.mode = Window.MODE_FULLSCREEN

static func settle(tree: SceneTree, window: Window, policy: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	for i in SETTLE_FRAMES:
		await tree.process_frame
	await tree.create_timer(SETTLE_SECONDS, true, false, true).timeout
	var before := snapshot(window)
	var reapplied: bool = policy.declared_mode == "agent_borderless_fullscreen" and not profile_issues(before, policy.declared_mode).is_empty()
	if reapplied:
		apply_window(window, policy)
	for i in 2:
		await tree.process_frame
	var after := snapshot(window)
	return {"elapsed_ms": Time.get_ticks_msec() - started, "reapplied": reapplied,
		"before": before, "after": after, "valid": profile_issues(after, policy.declared_mode).is_empty()}

static func snapshot(window: Window) -> Dictionary:
	var id := window.get_window_id()
	var physical := DisplayServer.window_get_size(id)
	var position := DisplayServer.window_get_position(id)
	var outer_size := DisplayServer.window_get_size_with_decorations(id)
	var outer_position := DisplayServer.window_get_position_with_decorations(id)
	var target := screen_rect(window)
	var render_size := Vector2(window.size) * window.scaling_3d_scale
	return {"window_size": [window.size.x, window.size.y], "window_position": [window.position.x, window.position.y],
		"window_mode": window.mode, "display_server_window_mode": DisplayServer.window_get_mode(id),
		"display_server_window_size": [physical.x, physical.y], "display_server_window_position": [position.x, position.y],
		"display_server_outer_size": [outer_size.x, outer_size.y], "display_server_outer_position": [outer_position.x, outer_position.y],
		"fullscreen_client_size": [target.size.x, target.size.y], "fullscreen_client_position": [target.position.x, target.position.y],
		"borderless": window.borderless, "no_focus": window.get_flag(Window.FLAG_NO_FOCUS),
		"has_focus": window.has_focus(), "render_scale": window.scaling_3d_scale,
		"render_size": [render_size.x, render_size.y],
		"render_size_source": "estimated_window_size_times_scaling_3d_scale; actual_internal_render recorded separately"}

static func profile_issues(state: Dictionary, declared_mode: String) -> Array[String]:
	var issues: Array[String] = []
	if state.get("window_size", []) != state.get("display_server_window_size", []):
		issues.append("root_native_size_mismatch")
	if state.get("window_mode", -1) != state.get("display_server_window_mode", -1):
		issues.append("root_native_mode_mismatch")
	if declared_mode == "explicit_windowed":
		return issues
	if state.get("window_size", []) != state.get("fullscreen_client_size", []):
		issues.append("not_native_client_size")
	if state.get("display_server_window_position", []) != state.get("fullscreen_client_position", []):
		issues.append("not_fullscreen_position")
	if state.get("window_position", []) != state.get("display_server_window_position", []):
		issues.append("root_native_position_mismatch")
	if declared_mode == "agent_borderless_fullscreen":
		if not state.get("borderless", false):
			issues.append("not_borderless")
		if not state.get("no_focus", false) or state.get("has_focus", true):
			issues.append("focus_policy_changed")
		if int(state.get("display_server_window_mode", -1)) not in [Window.MODE_WINDOWED, Window.MODE_MAXIMIZED]:
			issues.append("unexpected_borderless_window_mode")
		if state.get("display_server_outer_size", []) != state.get("fullscreen_client_size", []) \
			or state.get("display_server_outer_position", []) != state.get("fullscreen_client_position", []):
			issues.append("decorated_or_misplaced_fullscreen")
	elif declared_mode == "native_fullscreen":
		if int(state.get("window_mode", -1)) < Window.MODE_FULLSCREEN \
			or int(state.get("display_server_window_mode", -1)) < Window.MODE_FULLSCREEN:
			issues.append("not_native_fullscreen_mode")
	else:
		issues.append("unknown_declared_mode")
	return issues

static func internal_size_validity(capture: Dictionary, state: Dictionary, render_width: int) -> Dictionary:
	var reasons: Array[String] = []
	var actual: Array = capture.get("internal_size", [])
	var window_size: Array = state.get("window_size", [])
	if capture.get("status", "unavailable") != "captured" or actual.size() != 2 or window_size.size() != 2:
		return {"valid": false, "reasons": ["missing_actual_internal_size"]}
	if actual[0] <= 0 or actual[1] <= 0 or window_size[0] <= 0 or window_size[1] <= 0:
		return {"valid": false, "reasons": ["invalid_internal_or_window_size"]}
	var expected := Vector2(window_size[0], window_size[1]) * float(state.get("render_scale", 0.0))
	# Internal buffers round to integral pixels; do not permit larger discrepancies.
	if absf(float(actual[0]) - expected.x) > 1.0 or absf(float(actual[1]) - expected.y) > 1.0:
		reasons.append("internal_size_does_not_match_window_scale")
	var wanted := float(window_size[0]) if render_width == 0 else clampf(float(render_width), float(window_size[0]) * Settings.MIN_SCALE, float(window_size[0]))
	if absf(float(actual[0]) - wanted) > 1.0:
		reasons.append("internal_width_does_not_match_setting")
	return {"valid": reasons.is_empty(), "reasons": reasons, "tolerance_px": 1,
		"expected_from_window_scale": [expected.x, expected.y], "wanted_render_width": wanted, "actual_internal_size": actual}

static func capture_internal_size(tree: SceneTree, window: Window, on_frame: Callable = Callable()) -> Dictionary:
	var camera := window.get_camera_3d()
	if camera == null:
		return {"status": "unavailable", "reason": "no_active_camera"}
	var previous := camera.compositor
	var compositor := Compositor.new()
	var effects: Array[CompositorEffect] = []
	if previous != null:
		effects.assign(previous.compositor_effects)
	var capture := InternalSizeCapture.new()
	effects.append(capture)
	compositor.compositor_effects = effects
	camera.compositor = compositor
	var started := Time.get_ticks_msec()
	while capture.snapshot() == Vector2i.ZERO and Time.get_ticks_msec() - started < INTERNAL_SIZE_TIMEOUT_MS:
		await tree.process_frame
		if on_frame.is_valid():
			on_frame.call()
	var actual := capture.snapshot()
	if is_instance_valid(camera) and camera.compositor == compositor:
		camera.compositor = previous
	return {"status": "captured" if actual != Vector2i.ZERO else "unavailable",
		"internal_size": [actual.x, actual.y], "source": "CompositorEffect.RenderSceneBuffersRD.get_internal_size",
		"camera_path": str(camera.get_path()) if is_instance_valid(camera) else "freed", "elapsed_ms": Time.get_ticks_msec() - started}

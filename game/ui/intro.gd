class_name Intro
extends CanvasLayer
## INTRO-01 — вступительная заставка «Ничего не происходит» (решение владельца 29.10.2026, идея — вступление
## *Hit & Run*, без его ассетов; стиль ШКЯ, город Н.). Илюша у подъезда (Layout.SPAWN) смотрит в телефон и свайпит:
## на крупной плашке «экрана телефона» листаются заголовки IntroLines.HEADLINES; затем пузырь «Пойду прогуляюсь»,
## камера плавно отъезжает за спину Илюши в ракурс концепта 01, над Бабкой появляется «!» — управление включено.
## Пропуск — E, Esc, A/X/B (геймпад): мягкое затемнение и сразу конечное состояние.
##
## Мир живёт как обычно (стелс, транспорт, жители); на время заставки выключены только ввод Илюши, HUD и маркер «!»
## (маркер — слоем отрисовки, его видимость по-прежнему ведёт QuestFlow), камерой управляет заставка
## (CameraRig._physics_process выключен). Узел — ребёнок DemoWorld, пауза его останавливает.
## Где играет: Intro.attach(world) из main.gd; в headless, под тестовым SceneTree-скриптом и с аргументом
## --skip-intro заставки нет (мир как раньше), если только не выставлен Intro.force_enabled.

const IntroLines = preload("res://game/mission/intro_lines.gd")
const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const Layout = preload("res://game/world/layout.gd")
const SWIPE_SOUND := preload("res://assets/audio/phone_swipe.wav")
const VOICE_SOUND := preload("res://assets/audio/voice_ilyusha.wav")

const PAPER := Color(0.93, 0.87, 0.72)
const PAPER_DARK := Color(0.84, 0.76, 0.58)
const INK := Color(0.12, 0.10, 0.08)
const YELLOW := Color(0.99, 0.82, 0.12)

## Тайминги, с. Заголовок k встаёт целиком в headline_start(k); перед ним SWIPE — свайп с предыдущего.
const FADE_IN := 0.5
const PHONE_IN_AT := 0.3
const PHONE_SLIDE := 0.5
const FIRST_HEADLINE_AT := 0.8
const HEADLINE_HOLD := 2.1      # TEXT-01: заголовок до 5 слов читается целиком (0,8 с + 0,25 с на слово)
const SWIPE := 0.35
const PHONE_OUT := 0.4
const BUBBLE_SECONDS := 2.0
const TO_TALK_SHOT := 0.8      # камера от крупного плана к среднему, пока убирается телефон
const PULLBACK := 2.0
const LETTERBOX_OUT := 0.6     # полосы «кино» уходят в последние LETTERBOX_OUT отъезда
const SKIP_FADE_OUT := 0.25
const SKIP_FADE_IN := 0.35

## Ракурсы камеры: смещение курса от SPAWN_YAW, длина плеча, высота опоры, наклон, FOV, сдвиг опоры вправо от кадра.
## Камера со стороны двора, как в игре; Илюша стоит к ней лицом, спиной к подъезду (за ним — Бабка, пока без «!»).
## Крупный план — Илюша слева, плашка телефона справа; средний — для пузыря; игровой — профиль on_foot CameraRig.
const SHOT_PHONE := {"yaw": 0.35, "distance": 2.1, "height": 1.22, "pitch": -0.10, "fov": 50.0, "shift": 0.55}
const SHOT_PHONE_FROM_DISTANCE := 2.4   # медленный наезд за время ленты
const SHOT_TALK := {"yaw": 0.2, "distance": 3.0, "height": 1.45, "pitch": -0.02, "fov": 55.0, "shift": 0.0}
## Илюша лицом к камере (взгляд — от подъезда); в начале отъезда разворачивается к Бабке (SPAWN_YAW) за TURN_SECONDS.
const FACING_OFFSET := PI + 0.2
const TURN_SECONDS := 0.6

## Телефон в правой руке: высота, вынос к камере, сдвиг к руке, размер корпуса, м (руки облика — на ≈0,7 м).
const PHONE_HEIGHT := 0.74
const PHONE_FORWARD := 0.18
const PHONE_SIDE := 0.31
const PHONE_SIZE := Vector3(0.10, 0.18, 0.016)
const PHONE_TILT := 0.6   # экран к лицу: наклон назад ≈31° (подъём нормали на единицу пути к Илюше)

## Плашка телефона на холсте 1920×1080.
const PHONE_RECT := Rect2(1260, 120, 480, 840)
const SCREEN_INSET := 22.0
const LETTERBOX := 90.0

## Пузырь «Пойду прогуляюсь» — как пузыри квеста (QuestFlow), над головой Илюши.
const BUBBLE_FONT := 80
const BUBBLE_PIXEL := 0.0024
const BUBBLE_PAD := 34.0
const BUBBLE_TAIL := 56.0
const BUBBLE_DOWNSCALE := 2.0
const BUBBLE_Y := 2.0
const POP_SECONDS := 0.15

## Включить заставку и там, где она по умолчанию пропускается (headless, тестовый SceneTree, --skip-intro).
static var force_enabled := false

## Заставка закончилась: сама (skipped = false) или пропуском. Управление уже у игрока.
signal finished(skipped: bool)

var world: Node
var player: Ilyusha
var camera_rig: CameraRig
var hud: CanvasLayer
var marker: Node3D
## Время заставки, с (на пропуске и паузе не растёт).
var elapsed := 0.0
var duration := 0.0
## &"phone" (лента), &"bubble" (пузырь), &"pullback" (отъезд), &"done".
var phase: StringName = &"phone"
## Сколько свайпов сыграно (звук phone_swipe).
var swipe_count := 0
var skipped := false
var phone_3d: Node3D
var phone_panel: Control
var bubble_back: Sprite3D
var bubble_label: Label3D
var fade: ColorRect
var skip_hint: Control

var _skip_time := -1.0
var _cards: Array[Control] = []
var _dots: Array[Panel] = []
var _dot_on: StyleBoxFlat
var _dot_off: StyleBoxFlat
var _finger: Panel
var _letterbox: Array[ColorRect] = []
var _marker_layers := 1
var _swipe_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _bubble_shown := false

## Играть ли заставку в этом запуске.
static func should_play(tree: SceneTree) -> bool:
	if force_enabled:
		return true
	if "--skip-intro" in OS.get_cmdline_args() or "--skip-intro" in OS.get_cmdline_user_args():
		return false
	if DisplayServer.get_name() == "headless":
		return false
	# Тесты и съёмка кадров запускаются своим SceneTree-скриптом (--script): игра без него — обычный SceneTree.
	return tree.get_script() == null

## Подключить заставку к только что созданному миру; null — заставка пропущена, мир как без неё.
static func attach(new_world: Node) -> Intro:
	if not should_play(new_world.get_tree()):
		return null
	var intro := Intro.new()
	intro.name = "Intro"
	new_world.add_child(intro)
	return intro

## Начало заголовка k (целиком на экране), с от старта заставки.
static func headline_start(k: int) -> float:
	return FIRST_HEADLINE_AT + k * (HEADLINE_HOLD + SWIPE)

static func phone_out_at() -> float:
	return headline_start(IntroLines.HEADLINES.size() - 1) + HEADLINE_HOLD

static func bubble_at() -> float:
	return phone_out_at() + PHONE_OUT

static func pullback_at() -> float:
	return bubble_at() + BUBBLE_SECONDS

static func total_seconds() -> float:
	return pullback_at() + PULLBACK

func _ready() -> void:
	layer = 10   # над HUD (5) и диалогом (8), под паузой (15)
	world = get_parent()
	player = world.get_node("Ilyusha")
	camera_rig = world.get_node("CameraRig")
	hud = world.get_node_or_null("GameHUD")
	var flow := world.get_node_or_null("QuestFlow")
	if flow and flow.get("marker") is Node3D:
		marker = flow.marker
	duration = total_seconds()
	player.input_enabled = false
	player.velocity = Vector3.ZERO
	if hud:
		hud.visible = false
	if marker is VisualInstance3D:
		_marker_layers = (marker as VisualInstance3D).layers
		(marker as VisualInstance3D).layers = 0
	camera_rig.set_physics_process(false)
	_build_phone_3d()
	_build_bubble()
	_build_ui()
	_swipe_player = _audio(SWIPE_SOUND, -8.0, "SwipeSound")
	_voice_player = _audio(VOICE_SOUND, -6.0, "VoiceSound")
	_update(0.0)
	camera_rig.reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if _skip_time >= 0.0:
		_skip_time += delta
		if phase != &"done":
			fade.color.a = clampf(_skip_time / SKIP_FADE_OUT, 0.0, 1.0)
			if _skip_time >= SKIP_FADE_OUT:
				_finish(true)
		else:
			fade.color.a = clampf(1.0 - (_skip_time - SKIP_FADE_OUT) / SKIP_FADE_IN, 0.0, 1.0)
			if fade.color.a <= 0.0:
				queue_free()
		return
	if phase == &"done":
		return
	elapsed += delta
	player.input_enabled = false   # провал стелса во время заставки не возвращает управление раньше времени
	_update(elapsed)
	if elapsed >= duration:
		_finish(false)
		queue_free()

func _input(event: InputEvent) -> void:
	if phase == &"done" or _skip_time >= 0.0:
		return
	if _is_skip_event(event):
		get_viewport().set_input_as_handled()
		skip()

## E, Esc (клавиатура) и A, X, B (геймпад; X — как E, PAD-01). Start на геймпаде — пауза, как всегда.
static func _is_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		return key.physical_keycode in [KEY_E, KEY_ESCAPE] or key.keycode in [KEY_E, KEY_ESCAPE]
	if event is InputEventJoypadButton:
		return event.pressed and (event as InputEventJoypadButton).button_index in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_B]
	return false

## Пропустить: затемнение SKIP_FADE_OUT, конечное состояние, просветление SKIP_FADE_IN.
func skip() -> void:
	if phase == &"done" or _skip_time >= 0.0:
		return
	_skip_time = 0.0

func is_running() -> bool:
	return phase != &"done"

## Номер заголовка на экране (тот, что занимает больше половины экрана телефона).
func headline_index() -> int:
	return clampi(roundi(_page(elapsed)), 0, IntroLines.HEADLINES.size() - 1)

func current_headline() -> String:
	return IntroLines.HEADLINES[headline_index()]

func bubble_visible() -> bool:
	return is_instance_valid(bubble_back) and bubble_back.visible

## Страница ленты как непрерывная величина: k — заголовок k на месте, между — идёт свайп.
func _page(t: float) -> float:
	var page := 0.0
	for k in range(1, IntroLines.HEADLINES.size()):
		var start := headline_start(k) - SWIPE
		if t >= headline_start(k):
			page = k
		elif t > start:
			page = k - 1 + _ease((t - start) / SWIPE)
	return page

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

static func _smooth(x: float) -> float:
	return smoothstep(0.0, 1.0, x)

# --- кадр заставки по времени ---

func _update(t: float) -> void:
	if t < bubble_at():
		phase = &"phone"
	elif t < pullback_at():
		phase = &"bubble"
	else:
		phase = &"pullback"
	fade.color.a = 1.0 - clampf(t / FADE_IN, 0.0, 1.0)
	var turn := _smooth((t - pullback_at()) / TURN_SECONDS)
	player.visual.rotation.y = lerp_angle(Layout.SPAWN_YAW + FACING_OFFSET, Layout.SPAWN_YAW, turn)
	_update_camera(t)
	_update_phone_3d(t)
	_update_phone_panel(t)
	# Свайпы: звук в начале каждого.
	for k in range(swipe_count + 1, IntroLines.HEADLINES.size()):
		if t >= headline_start(k) - SWIPE:
			swipe_count = k
			_swipe_player.play()
	var show_bubble := t >= bubble_at() and t < pullback_at()
	if show_bubble != _bubble_shown:
		_bubble_shown = show_bubble
		bubble_back.visible = show_bubble
		bubble_label.visible = show_bubble
		if show_bubble:
			_pop_3d(bubble_back)
			_voice_player.play()
	var bars := 1.0 - _smooth((t - (duration - LETTERBOX_OUT)) / LETTERBOX_OUT)
	_letterbox[0].offset_bottom = LETTERBOX * bars
	_letterbox[1].offset_top = -LETTERBOX * bars
	skip_hint.modulate.a = clampf((t - FADE_IN) / 0.4, 0.0, 1.0) * (1.0 - clampf((t - pullback_at()) / 0.4, 0.0, 1.0))

func _update_camera(t: float) -> void:
	var phone_shot := SHOT_PHONE.duplicate()
	phone_shot["distance"] = lerpf(SHOT_PHONE_FROM_DISTANCE, SHOT_PHONE["distance"], _smooth(t / phone_out_at()))
	var game_shot := {"yaw": 0.0, "distance": CameraRig.PROFILES[&"on_foot"]["distance"],
		"height": CameraRig.PROFILES[&"on_foot"]["height"], "pitch": CameraRig.PROFILES[&"on_foot"]["pitch"],
		"fov": CameraRig.PROFILES[&"on_foot"]["fov"], "shift": 0.0}
	var shot: Dictionary
	if t < phone_out_at():
		shot = phone_shot
	elif t < pullback_at():
		shot = _mix(phone_shot, SHOT_TALK, _smooth((t - phone_out_at()) / TO_TALK_SHOT))
	else:
		shot = _mix(SHOT_TALK, game_shot, _smooth((t - pullback_at()) / PULLBACK))
	_apply_shot(shot)

static func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key in a:
		out[key] = lerp_angle(a[key], b[key], k) if key == "yaw" else lerpf(a[key], b[key], k)
	return out

func _apply_shot(shot: Dictionary) -> void:
	var yaw: float = Layout.SPAWN_YAW + shot["yaw"]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	camera_rig.global_position = player.global_position + Vector3.UP * shot["height"] + right * shot["shift"]
	camera_rig.rotation = Vector3(shot["pitch"], yaw, 0.0)
	camera_rig.arm.spring_length = shot["distance"]
	camera_rig.camera.fov = shot["fov"]

func _update_phone_3d(t: float) -> void:
	phone_3d.visible = t < phone_out_at() + PHONE_OUT * 0.5
	if not phone_3d.visible:
		return
	# Телефон всегда между Илюшей и камерой (облик — плоский рисунок к камере), экраном к лицу.
	var to_camera := camera_rig.camera.global_position - player.global_position
	to_camera.y = 0.0
	to_camera = to_camera.normalized() if to_camera.length_squared() > 0.0001 else Vector3.FORWARD
	var side := to_camera.cross(Vector3.UP)   # правая рука Илюши, если он смотрит на камеру
	var at := player.global_position + Vector3.UP * PHONE_HEIGHT + to_camera * PHONE_FORWARD + side * PHONE_SIDE
	phone_3d.global_position = at
	phone_3d.look_at(at - to_camera + Vector3.UP * PHONE_TILT, Vector3.UP)

func _update_phone_panel(t: float) -> void:
	var slide_in := _ease((t - PHONE_IN_AT) / PHONE_SLIDE)
	var slide_out := _smooth((t - phone_out_at()) / PHONE_OUT)
	phone_panel.position.y = PHONE_RECT.position.y + (1080.0 - PHONE_RECT.position.y) * (1.0 - slide_in + slide_out)
	phone_panel.visible = slide_in > 0.0 and slide_out < 1.0
	var page := _page(t)
	var width := PHONE_RECT.size.x - 2.0 * SCREEN_INSET
	for k in _cards.size():
		_cards[k].position.x = (k - page) * width
		_cards[k].visible = absf(k - page) < 1.0
	var current := headline_index()
	for k in _dots.size():
		_dots[k].add_theme_stylebox_override("panel", _dot_on if k == current else _dot_off)
	# Палец: кружок касания ведёт справа налево во время свайпа.
	var swipe_k := -1.0
	for k in range(1, IntroLines.HEADLINES.size()):
		var start := headline_start(k) - SWIPE
		if t > start and t < headline_start(k):
			swipe_k = (t - start) / SWIPE
	_finger.visible = swipe_k >= 0.0
	if _finger.visible:
		_finger.position = Vector2(lerpf(width * 0.78, width * 0.22, _ease(swipe_k)) - 35.0, 470.0)
		_finger.modulate.a = sin(PI * swipe_k)

# --- конец ---

func _finish(by_skip: bool) -> void:
	phase = &"done"
	skipped = by_skip
	phone_3d.queue_free()
	bubble_back.visible = false
	bubble_back.queue_free()
	phone_panel.visible = false
	skip_hint.visible = false
	for bar in _letterbox:
		bar.visible = false
	_swipe_player.stop()
	_voice_player.stop()
	player.visual.rotation.y = Layout.SPAWN_YAW
	camera_rig.yaw = Layout.SPAWN_YAW
	camera_rig.pitch = CameraRig.PROFILES[&"on_foot"]["pitch"]
	camera_rig.set_physics_process(true)
	camera_rig.snap(true)
	if hud:
		hud.visible = true
		var card: Variant = hud.get("card")
		if card is Control:
			DialogPanelScript.pop(card, 0.85)
	if marker is VisualInstance3D:
		(marker as VisualInstance3D).layers = _marker_layers
		_pop_3d(marker)
	var free_to_walk: bool = world.get("control_mode") == &"on_foot" and not world.get("ui_blocking")
	if world.has_method("is_stealth_failing") and world.is_stealth_failing():
		free_to_walk = false
	player.input_enabled = free_to_walk
	finished.emit(by_skip)

# --- сборка ---

func _audio(stream: AudioStream, volume_db: float, node_name: String) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.name = node_name
	audio.stream = stream
	audio.volume_db = volume_db
	add_child(audio)
	return audio

## Телефон в руке Илюши: тёмный корпус, экран светится к лицу. Только на время заставки.
func _build_phone_3d() -> void:
	phone_3d = Node3D.new()
	phone_3d.name = "IntroPhone"
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = PHONE_SIZE
	body.mesh = box
	var case_material := StandardMaterial3D.new()
	case_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	case_material.albedo_color = Color(0.20, 0.22, 0.28)
	body.material_override = case_material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	phone_3d.add_child(body)
	# Глазок камеры на задней крышке — со стороны зрителя телефон читается телефоном.
	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	var dot := SphereMesh.new()
	dot.radius = 0.012
	dot.height = 0.008
	lens.mesh = dot
	lens.position = Vector3(-PHONE_SIZE.x * 0.25, PHONE_SIZE.y * 0.36, PHONE_SIZE.z * 0.5)
	var lens_material := StandardMaterial3D.new()
	lens_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_material.albedo_color = Color(0.70, 0.72, 0.78)
	lens.material_override = lens_material
	phone_3d.add_child(lens)
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = Vector2(PHONE_SIZE.x * 0.86, PHONE_SIZE.y * 0.88)
	screen.mesh = quad
	screen.position.z = -PHONE_SIZE.z * 0.5 - 0.001
	screen.rotation.y = PI   # лицом по -Z, к Илюше
	var screen_material := StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.albedo_color = Color(0.75, 0.85, 1.0)
	screen.material_override = screen_material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	phone_3d.add_child(screen)
	player.add_child(phone_3d)

func _build_bubble() -> void:
	var font := DialogPanelScript.ui_font()
	var text := IntroLines.GO_FOR_A_WALK
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT)
	bubble_back = Sprite3D.new()
	bubble_back.name = "IntroBubbleBack"
	bubble_back.texture = _bubble_texture(text_size, BUBBLE_TAIL)
	bubble_back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble_back.no_depth_test = true
	bubble_back.shaded = false
	bubble_back.pixel_size = BUBBLE_PIXEL * BUBBLE_DOWNSCALE
	bubble_back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	bubble_back.render_priority = 1
	bubble_back.visible = false
	bubble_back.position = Vector3(0, BUBBLE_Y + bubble_back.texture.get_height() * bubble_back.pixel_size * 0.5, 0)
	player.add_child(bubble_back)
	bubble_label = Label3D.new()
	bubble_label.name = "IntroBubble"
	bubble_label.text = text
	bubble_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble_label.no_depth_test = true
	bubble_label.pixel_size = BUBBLE_PIXEL
	bubble_label.font = font
	bubble_label.font_size = BUBBLE_FONT
	bubble_label.outline_size = 0
	bubble_label.modulate = INK
	bubble_label.render_priority = 2
	bubble_label.position = Vector3(0, BUBBLE_TAIL * 0.5 * BUBBLE_PIXEL, 0)
	bubble_label.visible = false
	bubble_back.add_child(bubble_label)

## Бумажный пузырь с чернильной каймой и хвостиком вниз-влево — та же отрисовка, что у пузырей QuestFlow.
static func _bubble_texture(text_size: Vector2, tail_px: float) -> ImageTexture:
	var k := 1.0 / BUBBLE_DOWNSCALE
	var body := Vector2(text_size.x + 2.0 * BUBBLE_PAD, text_size.y + 2.0 * BUBBLE_PAD) * k
	var tail := tail_px * k
	var w := int(ceil(body.x)) + 4
	var h := int(ceil(body.y + tail)) + 4
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var radius := 14.0 * k
	var border := 7.0 * k
	var half := body * 0.5
	var center := Vector2(w * 0.5, 2.0 + half.y)
	var tri := PackedVector2Array([
		Vector2(center.x - body.x * 0.16, center.y + half.y - border),
		Vector2(center.x - body.x * 0.02, center.y + half.y - border),
		Vector2(center.x - body.x * 0.22, center.y + half.y + tail - 1.0)])
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - center).abs() - half + Vector2(radius, radius)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var in_tail := tail > 0.0 and Geometry2D.is_point_in_polygon(p, tri)
			if d <= -border or (in_tail and d > -border and _tail_inner(p, tri, border)):
				image.set_pixel(x, y, PAPER)
			elif d <= 0.0 or in_tail:
				image.set_pixel(x, y, INK)
	return ImageTexture.create_from_image(image)

static func _tail_inner(p: Vector2, tri: PackedVector2Array, border: float) -> bool:
	for edge in [[tri[1], tri[2]], [tri[2], tri[0]]]:
		if Geometry2D.get_closest_point_to_segment(p, edge[0], edge[1]).distance_to(p) < border:
			return false
	return true

func _pop_3d(node: Node3D) -> void:
	node.scale = Vector3.ONE * 0.3
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _build_ui() -> void:
	var root := Control.new()
	root.name = "IntroRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Полосы «кино» сверху и снизу, как в заставке Hit & Run; уходят в конце отъезда камеры.
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.02, 0.02, 0.03)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.anchor_bottom = 0.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
		root.add_child(bar)
		_letterbox.append(bar)
	_build_phone_panel(root)
	skip_hint = _build_skip_hint()
	root.add_child(skip_hint)
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

## Экран телефона крупно: корпус, шапка ленты, карточки заголовков (свайп — сдвиг по x), точки страниц.
func _build_phone_panel(root: Control) -> void:
	phone_panel = Panel.new()
	phone_panel.name = "PhoneScreen"
	phone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone_panel.position = PHONE_RECT.position
	phone_panel.size = PHONE_RECT.size
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.13, 0.12, 0.13)
	body.border_color = INK
	body.set_border_width_all(3)
	body.set_corner_radius_all(44)
	body.shadow_color = Color(0, 0, 0, 0.45)
	body.shadow_size = 10
	phone_panel.add_theme_stylebox_override("panel", body)
	root.add_child(phone_panel)
	var screen := Panel.new()
	screen.name = "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.clip_contents = true
	screen.position = Vector2(SCREEN_INSET, SCREEN_INSET)
	screen.size = PHONE_RECT.size - Vector2(2.0, 2.0) * SCREEN_INSET
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.set_corner_radius_all(26)
	screen.add_theme_stylebox_override("panel", paper)
	phone_panel.add_child(screen)
	var width := screen.size.x
	# Шапка ленты: жёлтая полоса с названием и чёрная «чёлка» камеры над ней.
	var header := Panel.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := StyleBoxFlat.new()
	band.bg_color = YELLOW
	band.border_color = INK
	band.border_width_bottom = 3
	band.corner_radius_top_left = 26
	band.corner_radius_top_right = 26
	header.add_theme_stylebox_override("panel", band)
	header.position = Vector2.ZERO
	header.size = Vector2(width, 118)
	screen.add_child(header)
	var notch := Panel.new()
	notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var notch_style := StyleBoxFlat.new()
	notch_style.bg_color = Color(0.13, 0.12, 0.13)
	notch_style.set_corner_radius_all(10)
	notch.add_theme_stylebox_override("panel", notch_style)
	notch.size = Vector2(110, 20)
	notch.position = Vector2((width - 110.0) * 0.5, 10)
	screen.add_child(notch)
	var title := _label(IntroLines.FEED_TITLE, 34)
	title.position = Vector2(0, 46)
	title.size = Vector2(width, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(title)
	for k in IntroLines.HEADLINES.size():
		var card := Control.new()
		card.name = "Card%d" % k
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.position = Vector2(0, 140)
		card.size = Vector2(width, 520)
		var headline := _label(IntroLines.HEADLINES[k], 50)
		headline.name = "Headline"
		headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		headline.position = Vector2(30, 10)
		headline.size = Vector2(width - 60, 260)
		headline.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		card.add_child(headline)
		var stamp := _label(IntroLines.STAMPS[k], 26)
		stamp.modulate = Color(1, 1, 1, 0.6)
		stamp.position = Vector2(30, 280)
		stamp.size = Vector2(width - 60, 36)
		card.add_child(stamp)
		# Строки текста заметки — серые полоски, как в ленте.
		for line in 4:
			var bar := ColorRect.new()
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.color = Color(INK, 0.16)
			bar.position = Vector2(30, 340 + line * 34)
			bar.size = Vector2((width - 60) * (0.62 if line == 3 else 1.0), 14)
			card.add_child(bar)
		screen.add_child(card)
		_cards.append(card)
	_dot_on = StyleBoxFlat.new()
	_dot_on.bg_color = INK
	_dot_on.set_corner_radius_all(8)
	_dot_off = StyleBoxFlat.new()
	_dot_off.bg_color = Color(INK, 0.25)
	_dot_off.set_corner_radius_all(8)
	var count := IntroLines.HEADLINES.size()
	for k in count:
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size = Vector2(16, 16)
		dot.position = Vector2(width * 0.5 + (k - (count - 1) * 0.5) * 30.0 - 8.0, screen.size.y - 44)
		screen.add_child(dot)
		_dots.append(dot)
	_finger = Panel.new()
	_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var finger_style := StyleBoxFlat.new()
	finger_style.bg_color = Color(1, 1, 1, 0.45)
	finger_style.border_color = Color(INK, 0.5)
	finger_style.set_border_width_all(3)
	finger_style.set_corner_radius_all(35)
	_finger.add_theme_stylebox_override("panel", finger_style)
	_finger.size = Vector2(70, 70)
	_finger.visible = false
	screen.add_child(_finger)

func _build_skip_hint() -> Control:
	var row := HBoxContainer.new()
	row.name = "SkipHint"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	for key in ["E", "Esc", "A"]:
		row.add_child(DialogPanelScript.key_cap(key, 24))
	var label := _label(IntroLines.SKIP_HINT, 26)
	label.add_theme_color_override("font_color", PAPER)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 6)
	row.add_child(label)
	# Слева внизу, над полосой «кино»: справа — плашка телефона.
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = 40
	row.offset_bottom = -LETTERBOX - 20
	row.modulate.a = 0.0
	return row

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

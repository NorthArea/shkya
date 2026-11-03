extends SceneTree
## INTRO-01: вступительная заставка «Ничего не происходит» на настоящем main.tscn (набор INTRO).
## В headless и под тестовым SceneTree заставки по умолчанию нет — это проверяется первым (остальные наборы и capture
## не меняются). Дальше Intro.force_enabled = true: лента заголовков и тайминги, свайпы, пузырь «Пойду прогуляюсь»,
## пауза, конечное состояние (ввод, камера на SPAWN_YAW, «!» над Бабкой, HUD, миссия прежняя), пропуск по E, Esc и A,
## запрещённые слова. Кадры заставки — tools/capture/capture_intro.gd в окне.

const Layout = preload("res://game/world/layout.gd")
const IntroScript = preload("res://game/ui/intro.gd")
const IntroLines = preload("res://game/mission/intro_lines.gd")
const FORBIDDEN := ["мобилизац", "бусификац"]
const FPS := 60.0

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var finished_skipped: Variant = null

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func():
		push_error("FAIL: intro test exceeded 300 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	await _default_skipped()
	await _marker_state()
	_texts()
	await _full_play()
	await _skip_by(_key(KEY_E), "E")
	await _skip_by(_key(KEY_ESCAPE), "Esc")
	await _skip_by(_joy_a(), "A")
	_finish()

# --- по умолчанию в тестах заставки нет ---

func _default_skipped() -> void:
	check(not IntroScript.should_play(self), "default: no intro under a test SceneTree / headless")
	main.menu.start_button.pressed.emit()
	await _frames(10)
	world = main.world
	check(world.get_node_or_null("Intro") == null, "default: start button gives the world without an intro node")
	check(world.player.input_enabled, "default: input is enabled right away")
	check(world.quest_flow.marker.layers != 0 and world.quest_flow.marker.visible, "default: '!' over Babka is visible")
	check(world.get_node("GameHUD").visible, "default: HUD visible")
	IntroScript.force_enabled = true
	check(IntroScript.should_play(self), "force_enabled turns the intro on")

# --- тексты ---

func _marker_state() -> void:
	var marker: Label3D = world.quest_flow.marker
	var original_layers := marker.layers
	marker.transparency = 0.35
	var intro: Intro = IntroScript.attach(world)
	await _frames(2)
	check(marker.layers == original_layers, "intro keeps renderer light-pairing layers unchanged")
	check(is_equal_approx(marker.transparency, 1.0), "intro marker is fully transparent while QuestFlow owns visibility")
	intro.skip()
	await _frames(int(ceil((IntroScript.SKIP_FADE_OUT + IntroScript.SKIP_FADE_IN) * FPS)) + 4)
	check(marker.layers == original_layers, "skip preserves the marker render layers")
	check(is_equal_approx(marker.transparency, 0.35), "skip restores the marker's original partial transparency")
	marker.transparency = 0.0

func _texts() -> void:
	var headlines := IntroLines.HEADLINES
	var n := headlines.size()
	check(n >= 3 and n <= 4, "texts: 3–4 posts (%d)" % n)
	check(IntroLines.BODIES.size() == n and IntroLines.FOOTERS.size() == n and IntroLines.STAMPS.size() == n,
		"texts: body, footer and stamp for every post")
	check(headlines[0].contains("ничего не происходит") or headlines[0].contains("Ничего не происходит"), "texts: first — nothing happens")
	check(IntroLines.BODIES[0].contains("город") and IntroLines.BODIES[0].contains("ничего не происходит"), "texts: first body — nothing happens in the city")
	check(headlines.any(func(h): return h.contains("по плану")), "texts: 'всё идёт по плану' present")
	check(IntroLines.BODIES.any(func(b): return b.contains("не происходит") and b.contains("для вашего блага")),
		"texts: «всё, что не происходит, — для вашего блага» (STORY-01)")
	# STORY-01: последний пост — про патрули, «для вашего блага» без совета их обходить (официальный голос STORY-02).
	var last := IntroLines.post_text(n - 1)
	check(headlines[-1].contains("Патрул") and last.contains("для вашего блага"), "texts: last post — patrols are for your good")
	check(not last.to_lower().contains("обходите") and last.contains("Пункт новых возможностей"), "texts: official post advertises opportunities without teaching patrol avoidance")
	for k in n:
		var hw := QuestLines.word_count(headlines[k])
		var bw := QuestLines.word_count(IntroLines.BODIES[k])
		check(hw <= 5 and bw <= 12, "texts: post %d — headline %d ≤ 5 words, body %d ≤ 12 words" % [k, hw, bw])
		var need := QuestLines.READ_BASE + QuestLines.READ_PER_WORD * QuestLines.word_count(IntroLines.post_text(k))
		check(IntroScript.headline_hold(k) >= need - 0.001, "timing: post %d shown %.2f s ≥ %.2f s to read it whole" % [k, IntroScript.headline_hold(k), need])
	check(IntroLines.GO_FOR_A_WALK == "Пойду прогуляюсь", "texts: Ilyusha's line")
	for text in IntroLines.all_texts():
		var low := text.to_lower()
		check(FORBIDDEN.all(func(w): return not low.contains(w)), "texts: forbidden words absent in '%s'" % text)
	var total := IntroScript.total_seconds()
	check(total >= 15.0 and total <= 20.0, "timing: total %.2f s within 15–20 s (three posts read whole, STORY-01)" % total)

# --- полный проход ---

func _full_play() -> void:
	var intro := await _new_intro()
	if intro == null:
		return
	var player := world.player
	var rig := world.camera_rig
	var marker: Label3D = world.quest_flow.marker
	var hud: CanvasLayer = world.get_node("GameHUD")
	check(not player.input_enabled, "play: input disabled during the intro")
	check(not hud.visible, "play: HUD hidden during the intro")
	check(marker.layers != 0 and is_equal_approx(marker.transparency, 1.0), "play: '!' is hidden without changing renderer layers")
	check(not rig.is_physics_processing(), "play: the intro drives the camera")
	check(intro.phase == &"phone" and intro.headline_index() == 0, "play: starts on the phone with headline 0")
	var phone: Node3D = player.get_node_or_null("IntroPhone")
	check(phone != null and phone.visible, "play: phone in Ilyusha's hand")
	check(player.global_position.distance_to(Layout.SPAWN) < 0.05, "play: Ilyusha stands at SPAWN")
	var facing_camera := absf(wrapf(player.visual.rotation.y - (Layout.SPAWN_YAW + IntroScript.FACING_OFFSET), -PI, PI)) < 0.001
	check(facing_camera, "play: Ilyusha faces the camera, back to the entrance")
	var cars := world.find_children("*", "TrafficCar", true, false)
	var cars_before := cars.map(func(c): return c.global_position)
	var start_frame := 0
	var frame := 0
	var seen_headlines := []
	var max_frames := int((IntroScript.total_seconds() + 3.0) * FPS)
	var paused_once := false
	var bubble_ok := false
	var bubble_hidden_after := true
	var phone_between := true
	while is_instance_valid(intro) and intro.is_running() and frame < max_frames:
		await physics_frame
		frame += 1
		if not is_instance_valid(intro) or not intro.is_running():
			break
		var t: float = intro.elapsed
		var k: int = intro.headline_index()
		if seen_headlines.is_empty() or seen_headlines[-1] != k:
			seen_headlines.append(k)
		# Середина показа каждого заголовка: на экране он, свайпов сыграно k.
		for j in IntroLines.HEADLINES.size():
			var mid := IntroScript.headline_start(j) + IntroScript.headline_hold(j) * 0.5
			if absf(t - mid) < 0.5 / FPS:
				check(intro.current_headline() == IntroLines.HEADLINES[j], "play: at %.2f s headline %d on screen" % [t, j])
				var card: Control = intro._cards[j]
				check(card.visible and absf(card.position.x) < 1.0 and (card.get_node("Body") as Label).text == IntroLines.BODIES[j]
					and (card.get_node("Footer") as Label).text == IntroLines.FOOTERS[j], "play: post %d shows its body and footer" % j)
				check(intro.swipe_count == j, "play: %d swipe sounds before headline %d" % [j, j])
				check(intro.phone_panel.visible and intro.phase == &"phone", "play: phone screen shown at headline %d" % j)
				var camera_pos: Vector3 = rig.camera.global_position
				phone_between = phone_between and camera_pos.distance_to(phone.global_position) < camera_pos.distance_to(player.global_position)
		# Пауза посреди ленты: время заставки стоит.
		if not paused_once and t >= 2.0:
			paused_once = true
			main.set_paused(true)
			var frozen: float = intro.elapsed
			await _frames(30)
			check(is_equal_approx(intro.elapsed, frozen), "play: pause freezes the intro")
			main.set_paused(false)
		var bubble_mid := IntroScript.bubble_at() + IntroScript.BUBBLE_SECONDS * 0.5
		if absf(t - bubble_mid) < 0.5 / FPS:
			bubble_ok = intro.bubble_visible() and intro.phase == &"bubble" and intro.bubble_label.text == IntroLines.GO_FOR_A_WALK \
				and not intro.phone_panel.visible and not phone.visible
		if t > IntroScript.pullback_at() + 0.1 and intro.bubble_visible():
			bubble_hidden_after = false
		if intro.is_running():
			check_quiet(not player.input_enabled, "play: input stays disabled during the intro")
	check(seen_headlines == range(IntroLines.HEADLINES.size()), "play: posts in order %s" % [seen_headlines])
	check(phone_between, "play: the phone is between Ilyusha and the camera")
	check(bubble_ok, "play: bubble '%s' shown after the feed, phone put away" % IntroLines.GO_FOR_A_WALK)
	check(bubble_hidden_after, "play: bubble hidden during the pullback")
	check(paused_once, "play: pause exercised")
	var expected := int(ceil(IntroScript.total_seconds() * FPS))   # кадры паузы в frame не входят
	check(absi(frame - expected) <= 3, "play: finished after %d frames (expected %d)" % [frame, expected])
	check(finished_skipped == false, "play: finished signal, not skipped")
	await _frames(2)
	check(world.get_node_or_null("Intro") == null, "play: intro node freed")
	_check_after("play")
	var moved := 0
	for i in cars.size():
		if is_instance_valid(cars[i]) and cars[i].global_position.distance_to(cars_before[i]) > 1.0:
			moved += 1
	check(cars.is_empty() or moved > 0, "play: traffic kept moving during the intro (%d of %d cars)" % [moved, cars.size()])

# --- пропуск ---

func _skip_by(event: InputEvent, label: String) -> void:
	var intro := await _new_intro()
	if intro == null:
		return
	await _frames(60)
	check(intro.is_running() and intro.phase == &"phone", "skip %s: intro is on the phone" % label)
	Input.parse_input_event(event)
	var release: InputEvent = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	var frames := 0
	while is_instance_valid(intro) and intro.is_running() and frames < 60:
		await physics_frame
		frames += 1
	check(frames <= int(ceil(IntroScript.SKIP_FADE_OUT * FPS)) + 2, "skip %s: done after the fade (%d frames)" % [label, frames])
	check(finished_skipped == true, "skip %s: finished(skipped = true)" % label)
	check(not paused, "skip %s: the game is not paused" % label)
	_check_after("skip " + label)
	await _frames(int(ceil((IntroScript.SKIP_FADE_OUT + IntroScript.SKIP_FADE_IN) * FPS)) + 3)
	check(world.get_node_or_null("Intro") == null, "skip %s: intro node freed after the fade-in" % label)
	check(not world.quest_flow.is_dialog_open(), "skip %s: no dialog opened by the skip key" % label)

func _check_after(label: String) -> void:
	var player := world.player
	var rig := world.camera_rig
	var marker: Label3D = world.quest_flow.marker
	var profile: Dictionary = CameraRig.PROFILES[&"on_foot"]
	check(player.input_enabled, "%s: input enabled after the intro" % label)
	check(rig.is_physics_processing() and rig.target == player, "%s: camera follows Ilyusha again" % label)
	check(absf(wrapf(rig.yaw - Layout.SPAWN_YAW, -PI, PI)) < 0.001 and absf(rig.rotation.y - Layout.SPAWN_YAW) < 0.001,
		"%s: camera yaw at SPAWN_YAW" % label)
	check(is_equal_approx(rig.pitch, profile["pitch"]) and is_equal_approx(rig.arm.spring_length, profile["distance"]),
		"%s: camera pitch and distance — the on_foot profile" % label)
	var goal: Vector3 = player.global_position + Vector3.UP * profile["height"]
	check(rig.global_position.distance_to(goal) < 0.05, "%s: camera behind Ilyusha at spawn" % label)
	check(marker.layers != 0 and marker.visible and marker.text == "!", "%s: '!' over Babka visible" % label)
	check(is_zero_approx(marker.transparency), "%s: marker opacity restored after intro" % label)
	check(world.get_node("GameHUD").visible, "%s: HUD visible" % label)
	check(world.mission.state == MissionDirector.NOT_STARTED and not world.mission.has_bread, "%s: mission still NOT_STARTED, no bread" % label)
	check(player.get_node_or_null("IntroPhone") == null or player.get_node("IntroPhone").is_queued_for_deletion(), "%s: phone removed" % label)
	check(player.global_position.distance_to(Layout.SPAWN) < 0.05, "%s: Ilyusha still at SPAWN" % label)
	check(absf(wrapf(player.visual.rotation.y - Layout.SPAWN_YAW, -PI, PI)) < 0.001, "%s: Ilyusha faces SPAWN_YAW (towards Babka)" % label)

func _new_intro() -> Intro:
	main.start_game()
	await process_frame
	await process_frame
	world = main.world
	var intro: Intro = world.get_node_or_null("Intro")
	check(intro != null, "intro node attached to the new world")
	finished_skipped = null
	if intro:
		intro.finished.connect(func(s): finished_skipped = s)
	return intro

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func _joy_a() -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	return event

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

## Проверка в цикле: считается один раз (первый провал), чтобы не раздувать счёт.
var _quiet_failed := {}
func check_quiet(condition: bool, label: String) -> void:
	if not condition and not _quiet_failed.has(label):
		_quiet_failed[label] = true
		check(false, label)

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	IntroScript.force_enabled = false
	print("INTRO: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	# Как в smoke_runner: дать аудиопотоку освободить остановленную музыку.
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)

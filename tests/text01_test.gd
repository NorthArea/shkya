extends SceneTree
## TEXT-01 (решение владельца 29.10.2026): весь текст игры — легче, проще, понятнее; без «полицейский — рация»;
## богатые пулы мемных реакций прохожих. Проверки:
## 1. Пулы прохожих: у бабки на каждое событие ≥ 15 реплик, у мужиков, тёток, детей ≥ 8; 1–7 слов, ≤ 40 знаков,
##    без повторов внутри голоса.
## 2. Диалоги квеста: реплика ≤ 8 слов; цепочки короткие; гэги укрытий — одна строка, «РАЦИЯ» нигде не звучит.
## 3. Запрещённые слова (мобилизация, бусификация, военкомат, повестка, мат) — ни в одной строке.
## 4. Время показа каждого текста ≥ QuestLines.read_seconds (0,8 с + 0,25 с на слово).
## 5. «Мешок» реплик: подряд одна строка не повторяется, круг проходит весь пул.
## 6. В мире: недочитанный пузырь перебивается только событием важнее; болтовня улицы ограничена; толчок Илюши —
##    реплика push не чаще Resident.PUSH_COOLDOWN.
## Итог — строка «TEXT01: N checks, M failures».

const IntroLines = preload("res://game/mission/intro_lines.gd")
const CoinLines = preload("res://game/mission/coin_lines.gd")
const LineBagScript = preload("res://game/npc/line_bag.gd")
const SoundDirectorScript = preload("res://game/audio/sound_director.gd")
const DronesScript = preload("res://game/world/drones.gd")
const QuestFlowScript = preload("res://game/mission/quest_flow.gd")
const SnowSpot = preload("res://game/stealth/snow_hide_spot.gd")
const BarrelSpot = preload("res://game/stealth/barrel_hide_spot.gd")
const BoxSpot = preload("res://game/stealth/box_hide_spot.gd")
const ResidentScript = preload("res://game/npc/resident.gd")
const HideTuning = preload("res://game/stealth/hide_tuning.gd")

const FORBIDDEN := ["мобилизац", "бусификац", "военкомат", "повестк", "хуй", "хуе", "хуя", "пизд", "бля", "ебан", "ебат",
	"ёбан", "сука", "суки", "мудак", "мудил", "падл", "гандон", "залуп", "шлюх", "дебил", "чурк", "хохл", "жид"]
const BABKA_MIN := 15
const OTHER_MIN := 8
const STREET_MAX_WORDS := 7
const STREET_MAX_CHARS := 40
const DIALOG_MAX_WORDS := 8

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func():
		push_error("FAIL: text01 test exceeded 240 simulated seconds")
		quit(2)
	)
	_formula()
	_street_pools()
	_quest_texts()
	_forbidden()
	_timings()
	_bag()
	await _in_world()
	_finish()

# --- формула ---

func _formula() -> void:
	print("--- formula ---")
	check(QuestLines.word_count("Илюша, сходи за хлебом") == 4, "word_count: 4 words")
	check(QuestLines.word_count("Ему сказали не топтать — он топчет!") == 6, "word_count: a dash is not a word")
	check(QuestLines.word_count("Батон? 35 рублей") == 3, "word_count: digits count")
	check(is_equal_approx(QuestLines.read_seconds("Привет!"), 1.05), "read_seconds: 0.8 + 0.25 per word (%.2f)" % QuestLines.read_seconds("Привет!"))

# --- 1. пулы прохожих ---

func _street_pools() -> void:
	print("--- street pools ---")
	var total := 0
	for voice in QuestLines.VOICES:
		var seen := {}
		for kind in QuestLines.KINDS:
			var pool: Array = QuestLines.street_lines(voice, kind)
			total += pool.size()
			var need := BABKA_MIN if voice == QuestLines.VOICE_BABKA else OTHER_MIN
			check(pool.size() >= need, "%s/%s: %d lines (≥ %d)" % [voice, kind, pool.size(), need])
			for text: String in pool:
				var words := QuestLines.word_count(text)
				check_quiet(words >= 1 and words <= STREET_MAX_WORDS, "%s/%s: «%s» — %d words (1–%d)" % [voice, kind, text, words, STREET_MAX_WORDS])
				check_quiet(text.length() <= STREET_MAX_CHARS, "%s/%s: «%s» — %d chars (≤ %d)" % [voice, kind, text, text.length(), STREET_MAX_CHARS])
				check_quiet(not seen.has(text), "%s: «%s» only once in the voice" % [voice, text])
				seen[text] = true
	print("INFO: street lines in all %d (unique %d)" % [total, QuestLines.all_street_lines().size()])
	check(total >= 200, "street lines: %d in all (≥ 200)" % total)
	for who in [&"babka", &"domino"]:
		var pool: Array = QuestLines.BREAK_POOLS[who]
		check(not pool.is_empty() and QuestLines.break_line(who, 0) == pool[0], "break_line(%s) cycles its pool" % who)
		for text: String in pool:
			check_quiet(QuestLines.word_count(text) <= STREET_MAX_WORDS, "break %s: «%s» ≤ %d words" % [who, text, STREET_MAX_WORDS])

# --- 2. диалоги квеста и гэги ---

func _dialog_lines() -> Array:
	var lines: Array = [QuestLines.OFFER] + QuestLines.OFFER_WARNING + QuestLines.PATROL_TURN + [QuestLines.IDLE, QuestLines.IDLE_DONE, QuestLines.ACCOUNT_OFFICER_ASK["text"],
		QuestLines.ACCOUNT_OFFICER_REPLY["text"], QuestLines.VENDOR_AGAIN, QuestLines.THANKS, QuestLines.THANKS_AFTER,
		CoinLines.vendor_short(35)]
	for chain in [QuestLines.OFFICER_CHAIN, QuestLines.VENDOR_CHAIN, QuestLines.RETURN_CHAIN]:
		for line in chain:
			lines.append(line["text"])
	return lines

func _gags() -> Array:
	return [QuestLines.HIDE_BOX_STILL, QuestLines.HIDE_BOX_MOVING, QuestLines.HIDE_SNOW_LOOK, QuestLines.HIDE_BARREL_ROLL,
		[QuestLines.HIDE_BARREL_BUMP_ILYUSHA]]

func _quest_texts() -> void:
	print("--- quest dialogs ---")
	for text: String in _dialog_lines():
		var words := QuestLines.word_count(text)
		check(words >= 1 and words <= DIALOG_MAX_WORDS, "dialog «%s» — %d words (≤ %d)" % [text, words, DIALOG_MAX_WORDS])
	check(QuestLines.OFFICER_CHAIN.size() == 1, "officer: one line, no back-and-forth (%d)" % QuestLines.OFFICER_CHAIN.size())
	check(QuestLines.VENDOR_CHAIN.size() <= 3 and QuestLines.RETURN_CHAIN.size() <= 2, "vendor ≤ 3 and return ≤ 2 lines (%d, %d)" % [QuestLines.VENDOR_CHAIN.size(), QuestLines.RETURN_CHAIN.size()])
	check(QuestLines.OFFER.contains("за хлебом") and QuestLines.THANKS_AFTER.contains("за хлебом"), "the «за хлебом» gag opens and closes the quest")
	for gag: Array in _gags():
		check(gag.size() == 1, "hide gag is one line, not a radio dialog: %s" % [gag])
	for text: String in _all_texts():
		check_quiet(not text.to_upper().contains("РАЦИЯ"), "no «РАЦИЯ» in «%s»" % text)

# --- 3. запрещённые слова ---

func _all_texts() -> Array:
	var texts: Array = _dialog_lines()
	for gag: Array in _gags():
		texts.append_array(gag)
	texts.append_array(QuestLines.all_street_lines())
	texts.append_array(QuestLines.BREAK_LINES_BABKA)
	texts.append_array(QuestLines.BREAK_LINES_DOMINO)
	texts.append_array(IntroLines.all_texts())
	texts.append_array([QuestLines.RADIO, QuestLines.HIDE_BOX_VENDOR, QuestLines.HIDE_SNOW_TOAST, QuestLines.HIDE_BARREL_BUMP_TOAST,
		CoinLines.task(0, 35), SuspicionMeter.HINT_TEXT, SuspicionMeter.FAIL_TEXT, DemoWorld.STEALTH_TOAST,
		DemoWorld.STEALTH_TOAST_NO_BREAD, DemoWorld.STEALTH_TOAST_CAR, DemoWorld.HINT_NO_EXIT, DronesScript.PATROL_GAG,
		HideTuning.HINT_BOX, HideTuning.HINT_BARREL, HideTuning.HINT_SNOWDRIFT, HideTuning.HINT_EXIT_BLOCKED,
		MissionDirector.TASK_RETURN, MissionDirector.TASK_DONE, QuestFlowScript.TOAST_TEXT])
	return texts

func _forbidden() -> void:
	print("--- forbidden words ---")
	var texts := _all_texts()
	var bad := []
	for text: String in texts:
		var low := text.to_lower()
		for w: String in FORBIDDEN:
			if low.contains(w):
				bad.append([text, w])
	check(bad.is_empty(), "no forbidden words in %d texts %s" % [texts.size(), bad])

# --- 4. время показа ---

func _enough(seconds: float, text: String, what: String) -> void:
	var need := QuestLines.read_seconds(text)
	check_quiet(seconds + 0.001 >= need, "%s: «%s» shown %.2f s ≥ %.2f s" % [what, text, seconds, need])

func _timings() -> void:
	print("--- display time ---")
	_enough(QuestLines.RADIO_SECONDS, QuestLines.RADIO, "radio")
	for gag: Array in _gags():
		for text: String in gag:
			_enough(HideTuning.GAG_PAGE_SECONDS, text, "hide gag page")
			_enough(SoundDirectorScript.page_seconds(text, 0.0), text, "SoundDirector.page_seconds")
	for spot_seconds in [BoxSpot.GAG_PAGE_SECONDS, SnowSpot.GAG_PAGE_SECONDS, BarrelSpot.GAG_PAGE_SECONDS]:
		check_quiet(spot_seconds >= HideTuning.GAG_PAGE_SECONDS - 0.001, "spot gag page %.2f s" % spot_seconds)
	_enough(SoundDirectorScript.page_seconds("раз два три четыре пять шесть семь восемь девять десять", 2.5), "раз два три четыре пять шесть семь восемь девять десять", "long gag page is stretched")
	_enough(SnowSpot.TOAST_SECONDS, QuestLines.HIDE_SNOW_TOAST, "snow toast")
	_enough(BarrelSpot.TOAST_SECONDS, QuestLines.HIDE_BARREL_BUMP_TOAST, "barrel toast")
	_enough(QuestFlowScript.TOAST_SECONDS, QuestFlowScript.TOAST_TEXT, "bread toast")
	_enough(SuspicionMeter.HINT_SECONDS, SuspicionMeter.HINT_TEXT, "stealth hint")
	_enough(DemoWorld.FAIL_SECONDS, SuspicionMeter.FAIL_TEXT, "stealth fail")
	for toast: String in [DemoWorld.STEALTH_TOAST, DemoWorld.STEALTH_TOAST_NO_BREAD, DemoWorld.STEALTH_TOAST_CAR]:
		_enough(DemoWorld.STEALTH_TOAST_SECONDS, toast, "stealth toast")
	_enough(DemoWorld.HINT_SECONDS, DemoWorld.HINT_NO_EXIT, "no-exit hint")
	for hint: String in [HideTuning.HINT_BOX, HideTuning.HINT_BARREL, HideTuning.HINT_SNOWDRIFT, HideTuning.HINT_EXIT_BLOCKED, QuestLines.HIDE_BOX_VENDOR]:
		_enough(HideTuning.HINT_SECONDS, hint, "hide hint")
	_enough(2.5, DronesScript.PATROL_GAG, "patrol gag")
	for headline: String in IntroLines.HEADLINES:
		_enough(Intro.HEADLINE_HOLD, headline, "intro headline")
	_enough(Intro.BUBBLE_SECONDS, IntroLines.GO_FOR_A_WALK, "intro bubble")
	for text: String in QuestLines.all_street_lines() + QuestLines.BREAK_LINES_BABKA:
		_enough(ResidentScript.bubble_seconds(text), text, "street bubble")
		_enough(maxf(Breakables.BABKA_BUBBLE_SECONDS, QuestLines.read_seconds(text)), text, "Babka break bubble")
	check(true, "display times checked against 0.8 s + 0.25 s per word")

# --- 5. «мешок» ---

func _bag() -> void:
	print("--- line bag ---")
	var bag = LineBagScript.new(7)
	for voice in QuestLines.VOICES:
		for kind in QuestLines.KINDS:
			var pool: Array = QuestLines.street_lines(voice, kind)
			var key := StringName("%s/%s" % [voice, kind])
			var seq: Array = []
			for k in pool.size() * 5:
				seq.append(bag.next(key, pool))
			var repeats := 0
			for k in range(1, seq.size()):
				if seq[k] == seq[k - 1]:
					repeats += 1
			var first := {}
			for t in seq.slice(0, pool.size()):
				first[t] = true
			check_quiet(repeats == 0, "bag %s: no line twice in a row (%d repeats in %d)" % [key, repeats, seq.size()])
			check_quiet(first.size() == pool.size(), "bag %s: a round covers the whole pool (%d of %d)" % [key, first.size(), pool.size()])
	var a = LineBagScript.new(3)
	var b = LineBagScript.new(3)
	var pool: Array = QuestLines.BABKA_HIT
	var same := true
	for k in 40:
		same = same and a.next(&"x", pool) == b.next(&"x", pool)
	check(same, "bag is deterministic for the same seed")
	check(true, "bags checked for every voice and event")

# --- 6. в мире ---

func _in_world() -> void:
	print("--- in world ---")
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.menu.start_button.pressed.emit()
	await _frames(20)
	world = main.world
	var hub: Node = get_first_node_in_group(&"residents")
	if not check(hub != null and hub.residents.size() > 4, "Residents found"):
		return
	var rs: Array = hub.residents
	for r in rs:
		check_quiet(r.bag == hub.bag and r.chatter == hub, "%s shares the street bag and chatter limit" % r.name)
	check(rs.any(func(r): return r.voice == QuestLines.VOICE_MAN) and rs.any(func(r): return r.voice == QuestLines.VOICE_KID) and rs.any(func(r): return r.voice == QuestLines.VOICE_BABKA), "babka, man and kid voices on the street")
	# Недочитанный пузырь: болтовня его не перебивает, событие важнее — перебивает.
	hub.reset_positions()
	await _frames(2)
	var r: Resident = rs[0]
	r._bubble_ready_at = 0.0
	check(r.speak_event(&"car"), "car line shown")
	var first := r.bubble_text
	check(not r.can_show(&"walk") and not r.can_show(&"idle") and not r.can_show(&"car"), "unread car bubble is not replaced by chatter")
	check(r.can_show(&"push") and r.can_show(&"hit") and r.can_show(&"break"), "an event may replace it")
	var shown_for := 0.0
	while r.bubble_visible() and shown_for < 10.0:
		await physics_frame
		shown_for += 1.0 / 60.0
	check(shown_for + 0.05 >= QuestLines.read_seconds(first), "bubble «%s» stayed %.2f s ≥ reading time %.2f s" % [first, shown_for, QuestLines.read_seconds(first)])
	# Лимит улицы: два жителя в один кадр — болтовню начинает один.
	hub.reset_positions()
	await _frames(2)
	var spoke := 0
	for k in range(1, 5):
		rs[k]._bubble_ready_at = 0.0
		if rs[k].speak_event(&"car"):
			spoke += 1
	check(spoke == 1, "chatter: one new street bubble per %.1f s (%d of 4 in one frame)" % [hub.CHATTER_GAP, spoke])
	# Толчок Илюши: реплика push своего голоса, повторный толчок раньше PUSH_COOLDOWN — без новой реплики.
	hub.reset_positions()
	await _frames(2)
	var p: Resident = rs[3]
	world.player.punch_landed.emit([p])
	await _frames(1)
	check(p.bubble_kind == &"push" and QuestLines.street_lines(p.voice, &"push").has(p.bubble_text) and hub.push_bubbles == 1, "push: %s says «%s» (%s)" % [p.name, p.bubble_text, p.voice])
	var line1 := p.bubble_text
	world.player.punch_landed.emit([p])
	await _frames(1)
	check(hub.push_bubbles == 1 and p.bubble_text == line1 and p.pushes == 2, "push again at once: no new line before %.1f s" % Resident.PUSH_COOLDOWN)
	for k in int(Resident.PUSH_COOLDOWN * 60.0) + 5:
		await physics_frame
	world.player.punch_landed.emit([p])
	await _frames(1)
	check(hub.push_bubbles == 2 and p.bubble_text != line1, "push after the cooldown: a different line («%s»)" % p.bubble_text)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

var _quiet_failed := {}

func check_quiet(condition: bool, label: String) -> void:
	if condition:
		checks += 1
		return
	if not _quiet_failed.has(label):
		_quiet_failed[label] = true
		check(false, label)

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		print("FAIL: ", label)
	return condition

func _finish() -> void:
	print("TEXT01: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

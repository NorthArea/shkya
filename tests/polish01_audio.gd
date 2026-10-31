extends SceneTree
## POLISH-01, звук: шаги, мотор, занос, двери, интерфейс, хлеб, финал, фон — на настоящем main.tscn.
## MUSIC-01: тема меню — играет и зациклена в меню и НАСТРОЙКАХ, затухает после «НАЧАТЬ», молчит в игре,
## на паузе тише и приглушённая, снова в главном меню; уровень по данным дорожки.

const Layout = preload("res://game/world/layout.gd")

var failures: Array[String] = []
var checks := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func():
		push_error("FAIL: audio test exceeded 300 simulated seconds")
		quit(2)
	)
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	var music = main.music
	check(music.player.playing and music.player.stream == music.THEME and music.player.bus == music.BUS, "menu theme plays on the Music bus (MUSIC-01)")
	check(music.THEME is AudioStreamOggVorbis and music.THEME.loop and music.THEME.get_length() >= 270.0 and music.THEME.get_length() <= 273.0, "complete nocturne loops after its natural ending, %.1f s" % music.THEME.get_length())
	var rms_db := _stream_rms_db(music.THEME)
	check(absf(rms_db - music.THEME_RMS_DB) < 0.5, "menu theme track RMS %.1f dB matches THEME_RMS_DB" % rms_db)
	var level: float = rms_db + music.MENU_DB + AudioServer.get_bus_volume_db(AudioServer.get_bus_index(music.BUS))
	check(level >= -26.0 and level <= -24.0 and not music.muffled(), "menu piano level %.1f dB in −26…−24, unfiltered with full dynamics" % level)
	await _frames(80)
	check(music.player.volume_db > music.MENU_DB - 0.5, "menu theme faded in to %.1f dB" % music.player.volume_db)
	main.menu.settings_button.pressed.emit()
	await _frames(10)
	check(music.player.playing and main.menu.settings.visible, "menu theme keeps playing in SETTINGS")
	main.menu.settings.back_requested.emit()
	await _frames(2)
	main.menu.start_button.pressed.emit()  # настоящая кнопка меню: щелчок вне мира
	check(main.ui_click.playing and main.ui_click.stream == main.UI_CLICK, "main menu button clicks")
	await _frames(10)
	var world: DemoWorld = main.world
	var sound = world.get_node("SoundDirector")
	check(sound.ambience.playing and sound.ambience.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "yard ambience loops from the start")
	check(sound.ENGINE.loop_mode == AudioStreamWAV.LOOP_FORWARD and sound.SKID.loop_mode == AudioStreamWAV.LOOP_FORWARD, "engine and skid streams loop")
	# Шаги.
	world.player.place(Layout.SPAWN, 0.0)
	world.camera_rig.yaw = PI * 0.5
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(120)
	Input.action_release(&"move_forward")
	var steps: int = sound.played["step"]
	check(steps >= 6 and steps <= 12, "footsteps while walking ~8 m: %d" % steps)
	world.player.place(Layout.SPAWN + Vector3(0, 0, -5), 0.0)
	await _frames(30)
	check(sound.played["step"] == steps, "teleport and standing still make no steps")
	check(not music.player.playing and music.state == music.State.GAME, "menu theme faded out and stopped in the game")
	# Машина: дверь, мотор, высота тона, занос.
	world.car.reset_to(Vector3(-80, 0, 32), -PI * 0.5)
	world.enter_car()
	await _frames(5)
	check(sound.played["door_close"] == 1, "door sound when getting in")
	check(sound.engine.playing, "engine runs with a driver")
	check(sound.played["radio"] == 0 and sound.radio_text() == "", "radio waits a moment after the door (EXT-01)")
	await _wait_radio_tuning(sound)
	var idle_pitch: float = sound.engine.pitch_scale
	Input.action_press(&"car_gas")
	await _frames(150)
	var fast_pitch: float = sound.engine.pitch_scale
	check(fast_pitch > idle_pitch + 0.5, "engine pitch rises with speed (%.2f → %.2f)" % [idle_pitch, fast_pitch])
	check(not sound.skid.playing, "no skid sound driving straight")
	check(sound.played["radio"] >= 1 and sound.radio.playing and not sound.car_radio.player.playing and sound.radio.stream.data == sound.RADIO.data, "STORY-02: welcome caption has one original mumbling announcer")
	check(sound.car_radio.music.player.playing and absf(sound.car_radio.music.player.volume_db - sound.car_radio.music.DUCK_DB) < 0.5 and sound.car_radio.music.player.volume_db > -40.0, "welcome announcer leaves a smoothly ducked audible music bed")
	check(sound.radio_shown == 1, "first transmission shown once")
	check(sound.car_radio.plays == 0, "periodic jingles do not interrupt the first STORY-02 transmission")
	check(sound.radio_text() == QuestLines.RADIO and sound.subtitle_card.visible, "radio subtitle line on screen: '%s'" % sound.radio_text())
	check(not paused and not world.ui_blocking, "radio leaves the world and driving UI unpaused")
	check(world.player.input_enabled == false and world.control_mode == &"in_car" and world.car.speed_kmh() > 5.0, "radio does not block driving")
	Input.action_press(&"handbrake")
	Input.action_press(&"move_left")
	var skid_heard := false
	for i in 40:
		await physics_frame
		skid_heard = skid_heard or sound.skid.playing
	_release_all()
	check(skid_heard, "slush skid sound in a handbrake drift")
	var frames := 0
	await _press(&"interact")
	while world.control_mode == &"in_car" and frames < 400:
		await physics_frame
		frames += 1
	await _frames(3)
	check(sound.played["door_open"] == 1 and not sound.engine.playing, "door sound and engine off after exit")
	await _frames(400)
	check(sound.radio_text() == "" and not sound.subtitle_card.visible, "radio subtitle gone after %.0f s" % QuestLines.RADIO_SECONDS)
	world.player.place(world.car.global_position + world.car.global_basis.x * 2.2, 0.0)
	await _frames(4)
	await _press(&"interact")
	await _wait_radio_tuning(sound)
	await _frames(60)
	check(world.control_mode == &"in_car" and sound.radio_shown == 2 and sound.radio_text() == QuestLines.RADIO_PROGRESS, "re-entry resumes the remaining progress transmission without repeating the welcome")
	check(sound.played["radio"] >= 2 and sound.radio.playing and not sound.car_radio.player.playing and sound.radio.stream.data == sound.RADIO.data, "progress caption also has one original mumbling announcer")
	check(sound.car_radio.music.player.playing and absf(sound.car_radio.music.player.volume_db - sound.car_radio.music.DUCK_DB) < 0.5 and sound.car_radio.music.player.volume_db > -40.0, "progress announcer leaves the ducked music audible")
	await _frames(int(ceil(maxf(QuestLines.RADIO_SECONDS, QuestLines.read_seconds(QuestLines.RADIO_PROGRESS)) * 60.0)) + 90)
	check(sound.radio_text() == "" and sound.radio_shown == 2, "both short transmissions finish once per world")
	check(not sound.story_radio_pending(), "periodic radio becomes eligible only after both STORY-02 transmissions finish")
	await _press(&"interact")
	frames = 0
	while world.control_mode == &"in_car" and frames < 400:
		await physics_frame
		frames += 1
	await _frames(3)
	await _check_car_radio(world, sound)
	# Интерфейс, хлеб, финал.
	world.player.place(Layout.BABKA + Vector3(0, 0, -2.2), 0.0)
	await _frames(4)
	await _press(&"interact")
	var flow = world.get_node("QuestFlow")
	if flow.is_dialog_open() and flow.dialog.buttons.has(&"accept"):
		flow.dialog.buttons[&"accept"].pressed.emit()
	await _frames(3)
	check(sound.played["ui"] >= 1, "dialog button click sound")
	var mission := world.mission
	mission.notify_entered_car()
	mission.notify_arrived_kiosk()
	# Покупка через настоящую кнопку диалога продавщицы: щелчок не должен оборвать звон.
	# EXT-01: первый подход — цепочка реплик, «ДАЛЬШЕ» тоже щёлкает; кнопка покупки на последней.
	mission.add_money(mission.money_missing())   # монеты — COINS: 35 ₽ собраны (сбор проверяет tests/coins_test.gd)
	world.player.place(Layout.VENDOR_WINDOW, 0.0)
	await _frames(4)
	await _press(&"interact")
	var clicks_before: int = sound.played["ui"]
	while flow.is_dialog_open() and not flow.dialog.is_last_line():
		flow.dialog.finish_typing()
		flow.dialog.buttons[&"next"].pressed.emit()
	var nexts: int = QuestLines.VENDOR_CHAIN.size() - 1
	check(sound.played["ui"] == clicks_before + nexts, "ДАЛЬШЕ clicks %d times through the vendor chain (%d)" % [nexts, sound.played["ui"] - clicks_before])
	if flow.is_dialog_open() and flow.dialog.buttons.has(&"buy"):
		flow.dialog.buttons[&"buy"].pressed.emit()
	await _frames(2)
	check(sound.played["bread"] == 1, "bread chime once on purchase")
	check(sound.chime.stream == sound.BREAD and sound.ui.stream == sound.UI_CLICK, "button click does not replace bread chime")
	mission.interact(&"babka")
	await _frames(2)
	check(sound.played["complete"] == 1, "quest complete jingle once")
	mission.interact(&"babka")
	await _frames(2)
	check(sound.played["complete"] == 1, "no second jingle on repeated talk")
	# Пауза останавливает звук мира.
	var position_before: float = sound.ambience.get_playback_position()
	await _frames(30)
	var advanced: float = sound.ambience.get_playback_position() - position_before
	if advanced <= 0.0:
		print("NOT_RUN: audio playback does not advance with this audio driver; pause check needs a real device")
	else:
		main.set_paused(true)
		main.ui_click.stop()
		(main.pause_menu.find_children("*", "Button", true, false)[0] as Button).pressed.emit()
		check(main.ui_click.playing, "pause menu button clicks while paused")
		main.set_paused(true)
		var paused_at: float = sound.ambience.get_playback_position()
		await _frames(30)
		check(absf(sound.ambience.get_playback_position() - paused_at) < 0.05, "pause freezes world sound")
		main.set_paused(false)
	# MUSIC-01: пауза — та же тема тише и через ФНЧ; после паузы гаснет; в главном меню — снова.
	main.set_paused(true)
	await _frames(60)
	check(music.player.playing and music.muffled() and absf(music.player.volume_db - music.PAUSE_DB) < 0.5 and music.PAUSE_DB < music.MENU_DB, "pause plays the theme quieter and muffled (%.1f dB)" % music.player.volume_db)
	main.set_paused(false)
	await _frames(40)
	check(not music.player.playing and not music.muffled(), "theme stops after resuming the game")
	main.return_to_menu()
	await _frames(90)
	check(main.world == null and music.player.playing and not music.muffled() and absf(music.player.volume_db - music.MENU_DB) < 0.5, "menu theme plays again in the main menu after the game")
	_finish()

## POLISH-03 C: радио «Лады» — позывные «ничего необычного» с объявлением; только в машине на ходу, не чаще INTERVAL,
## уступают гэгам и диалогам; пешком молчат.
func _check_car_radio(world: DemoWorld, sound) -> void:
	var radio = sound.car_radio
	check(sound.radio_shown == 2 and sound.played["radio"] >= 2 and not sound.radio.playing, "periodic announcements preserve both completed voiced story transmissions")
	check(radio != null and radio.player != null, "car radio (CarRadio) is set up")
	if radio == null or radio.player == null:
		return
	var CarRadio = radio.get_script()
	check(radio.player.get_parent() == world.car and radio.player is AudioStreamPlayer3D, "radio jingle plays from under the dash (3D on the Lada)")
	check(radio.player.volume_db < sound.engine.volume_db, "radio jingle is quieter than the engine (%.0f < %.0f dB)" % [radio.player.volume_db, sound.engine.volume_db])
	check(CarRadio.JINGLES.size() >= 2 and CarRadio.JINGLES.size() <= 3, "2–3 synthesized jingles (%d)" % CarRadio.JINGLES.size())
	var forbidden := ["мобилизац", "бусификац", "военкомат", "повестк"]
	for line in CarRadio.LINES:
		var bad := forbidden.filter(func(w): return line.to_lower().contains(w))
		check(QuestLines.word_count(line) <= 8 and bad.is_empty(), "radio line ≤ 8 words, no forbidden words: '%s'" % line)
	# Пешком — тишина, даже когда ожидание вышло.
	radio.wait = 0.0
	var before: int = sound.played.get("radio_jingle", 0)
	world.player.place(Layout.SPAWN, 0.0)
	await _frames(180)
	check(sound.played.get("radio_jingle", 0) == before and not radio.player.playing, "no radio jingle on foot")
	# В машине на ходу: первый позывной через FIRST_DELAY езды.
	radio.wait = CarRadio.FIRST_DELAY
	world.car.reset_to(Vector3(-85, 0, 32), -PI * 0.5)
	world.enter_car()
	await _frames(3)
	await _wait_radio_tuning(sound)
	var driven := 0.0
	var started_at := -1.0
	for i in int((CarRadio.FIRST_DELAY + 3.0) * 60.0):
		_cruise(world, 22.0)
		await _frames(1)
		if world.car.speed_kmh() >= CarRadio.MIN_SPEED_KMH:
			driven += 1.0 / 60.0
		if started_at < 0.0 and radio.player.playing:
			started_at = driven
			break
	check(started_at >= CarRadio.FIRST_DELAY - 0.1 and started_at <= CarRadio.FIRST_DELAY + 0.2, "first jingle after %.1f s of driving (%.0f)" % [started_at, CarRadio.FIRST_DELAY])
	check(sound.played.get("radio_jingle", 0) == before + 1, "radio jingle counted once")
	check(sound.radio_text() == CarRadio.LINES[0] and sound.subtitle_card.visible, "announcement subtitle on screen: '%s'" % sound.radio_text())
	# Гэг (квестовая реплика) важнее: позывной гаснет, строку занимает гэг.
	sound.show_gag(["Тестовый гэг"], 1.5)
	await _frames(int((CarRadio.FADE + 0.2) * 60.0))
	check(not radio.player.playing and sound.subtitle_label.text == "Тестовый гэг", "a gag silences the jingle and takes the subtitle")
	# Не чаще INTERVAL: дальше 6 с езды — тишина.
	var plays: int = sound.played["radio_jingle"]
	for i in 360:
		_cruise(world, 22.0)
		await _frames(1)
	check(sound.played["radio_jingle"] == plays, "no second jingle within %.0f s of driving" % CarRadio.INTERVAL)
	# Пока идёт гэг, позывной не начинается; после — начинается.
	radio.wait = 0.0
	sound.show_gag(["Ещё гэг"], 2.0)
	var during_gag := false
	var after_gag := false
	for i in 600:
		_cruise(world, 22.0)
		await _frames(1)
		if sound.gag_playing() and radio.player.playing:
			during_gag = true
		if not sound.gag_playing() and radio.player.playing:
			after_gag = true
			break
	check(not during_gag and after_gag, "jingle waits for the gag to end, then plays")
	# Выход из машины — стоп.
	_release_all()
	var frames := 0
	while world.car.speed_kmh() > 1.0 and frames < 600:
		Input.action_press(&"car_brake")
		await physics_frame
		frames += 1
	_release_all()
	world.exit_car()
	await _frames(3)
	check(world.control_mode == &"on_foot" and not radio.player.playing, "radio jingle stops when Ilyusha gets out")

## Держать «Ладу» около kmh: газ, пока медленнее.
func _cruise(world: DemoWorld, kmh: float) -> void:
	if world.car.speed_kmh() < kmh:
		Input.action_press(&"car_gas")
	else:
		Input.action_release(&"car_gas")

## AudioServer завершает настройку по реальным аудиочасам, даже при --fixed-fps.
func _wait_radio_tuning(sound: Node) -> void:
	var cue: AudioStreamPlayer = sound.car_radio.music.tuning
	var deadline_ms: int = Time.get_ticks_msec() + ceili(cue.stream.get_length() * 1000.0) + 1500
	while cue.playing and Time.get_ticks_msec() < deadline_ms:
		OS.delay_msec(10)
		await process_frame
	check(not cue.playing and sound.car_radio.music.news_enabled(), "receiver finishes its actual tuning sound before news timing starts")

## RMS фактически декодированной дорожки: оба канала каждого 16-го кадра.
func _stream_rms_db(stream: AudioStream) -> float:
	var playback := stream.instantiate_playback()
	playback.start()
	var remaining := roundi(stream.get_length() * AudioServer.get_mix_rate())
	var total := 0.0
	var count := 0
	while remaining > 0:
		var frames := playback.mix_audio(1.0, mini(16384, remaining))
		if frames.is_empty():
			playback.stop()
			return -INF
		for i in range(0, frames.size(), 16):
			total += frames[i].length_squared()
			count += 2
		remaining -= frames.size()
	playback.stop()
	return 10.0 * log(total / count) / log(10.0)

func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"car_gas", &"car_brake", &"move_left", &"move_right", &"handbrake"]:
		Input.action_release(action)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func _finish() -> void:
	print("AUDIO: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	# Как в smoke_runner: аудиопоток освобождает остановленный playback по часам,
	# а headless fixed-fps может исполнить три кадра быстрее одного mix-буфера.
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures.is_empty() else 1)

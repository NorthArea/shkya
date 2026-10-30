extends SceneTree
## EXT-01 S: стелс-ядро по C7 на настоящей сцене main.tscn (docs/extension/STEALTH_DESIGN.md, ACCEPTANCE_TESTS.md).
## Тестовый DetectionSensor ставится в мир; точки — только из Layout (C1) или относительно Илюши.
## Чужие сенсоры (наблюдатели части N) на время прогона выключены, кроме проверки чекпоинта.
## Проверки: видимость по расстоянию и углу; луч — стена дома, гаражи и KioskPavilion укрывают, тропинка
## и низкий снег — нет; спад и сброс при выходе из конуса; frozen в диалоге и на паузе; в машине не видят;
## провал до покупки (has_bread false) и после (has_bread true, FSM не меняется); чекпоинт вне конусов;
## после провалов квест завершается однократно. Диалоги, покупка, ходьба и пауза — вводом (playthrough_driver).
## Часть 10 (приёмка EXT-01 28.10) — свежий мир с настоящими наблюдателями: учебный автобус на улице A (индикатор
## без провала, в машине не видят), парковка южнее павильона, конус при приближении, «в лоб» к полицейскому —
## провал за ≤ 6 с, оба честных пути (Layout.SNEAK_EAST/WEST) — без провала только с ожиданием разворота и за
## 20…90 с, без ожидания — провал или индикатор; после покупки у окна 10 с шкала ≤ 0,3 (идущий патруль не смотрит),
## автобус ГСУМ ждёт за «Ладой» и не сдвигает её, встаёт на площадке носом на север; чекпоинт вне всех конусов;
## обратный путь Layout.SNEAK_BACK к машине без провала.
## EXT-01 fix2: углы [запад-юго-запад, юго-юго-восток] и 100°; «в лоб» — провал во всех 4 фазах разворота (0 / 2,5 /
## 5 / 7 с после поворота на угол 0); путь «за остановкой» без ожидания при угле 1 — провал; учебный круг 6 м (идём по
## южному тротуару у двери). Часть 11 (свежий мир): подсказка E со спины у полицейского нет; после разговора — уйти
## сразу и через 1 с без провала, стоять — провал через 3…6 с; «Лада» с Илюшей на проезжей части B у поста не видна,
## на площадке Layout.KIOSK_SQUARE — провал, машина на парковке (конец ROUTE_DRIVE), тост «МАШИНУ ОТОГНАЛИ НА
## ПАРКОВКУ», has_bread цел, автобус машину не видит; автобус ГСУМ, запертый «Ладой» на полосе, стоит ≤ 12 с и
## встаёт вне полос, «Ладу» не сдвигает. Сектор полицейского обрезан павильоном (луч короче дальности).
## EXT-01 fix3 (третья приёмка): в части 11 — уйти после разговора на юг к парковке без провала (защита 5 с), стоять —
## провал через 5…9 с; проезд «Лады» по B через KIOSK_SQUARE без остановки — шкала 0; автобус ГСУМ без телепорта:
## (A) путь занят — ждёт, крайний случай после 30 с, (B) Илюша на стоянке — через 12 с своим ходом с полосы,
## (C) «Лада» на обочине A — объезд по полосе машин через 20 с. Часть 12 (свежий мир): второй пост Officer2 — без
## диалога, честные пути SNEAK_* и окно вне его конусов, «Лада» встаёт на проезжей части B у окна — провал ≤ 3 с (вышел
## и пошёл к окну — сразу) и машина на парковке, обход пешком по дороге x = 74,6 — провал в угол «юго-восток», проход
## с ожиданием угла «север»; честные пути с двумя постами 15–30 с; после покупки второй пост на месте.
## EXT-01 fix4 (четвёртая приёмка): второй пост на (59, −87), 14 м, углы [запад, восток-юго-восток], разворот через север
## (avoid_yaw); коридор x = 51,3 — в угле 0, у западной стены киоска не видно ни одному посту; «Лада» в коридоре (51,2; −77)
## видна по лучам к углам — провал, выход из машины в коридоре — провал сразу; пешком с улицы C через коридор сразу после
## поворота на запад — провал / шкала ≥ 0,6, после поворота на восток-юго-восток — проход; «Лада» за троллейбусом на
## остановке B — шкала 0 (выдержка 8 с на проезжей части), стоит у окна на дороге — провал через 8…11 с; обход по дороге
## без ожидания — в 12 фазах, число «провал или ≥ 0,6» в логе; SNEAK_WEST ждёт оба поста, ≤ 40 с; после диалога патруль
## отворачивается от парковки; подсказка индикатора после alert_now и респавна не висит; автобус при «Ладе» на полосе —
## крайний случай после 60 с и только вперёд.
## EXT-01 fix5 (пятая приёмка): у первого поста три угла [запад-юго-запад, юго-восток-юг, восток], обзор 120°, разворот
## не через окно; второй держит восток-юго-восток 5–6 с. Часть 13 (свежий мир): восток накрывает диагональ с дороги B,
## окно вне всех углов (30 с у окна — 0 кадров видимости); диагональ (длинная и короткая) без ожидания — 12 фаз 0…16,5 с
## после поворота на угол 0, чистых ≤ 2; с ожиданием угла 0 на дороге — проход; честные пути с ожиданием — проход (время
## в лог); SNEAK_WEST без ожидания — 4 фазы, чистых ≤ 1; KIOSK_BINS в 3,9 м от гаражей, прыжок с них на крышу гаражей не
## достаёт; на крыше гаражей и киоска — провал ≤ 2,5 с; на контейнерах и в прыжке с земли — не «на крыше».
## EXT-01 fix6 (шестая приёмка). Часть 14 (свежий мир): правило близости — ближе 3 м виден без угла и луча, рост ×3, в
## 3…6 м без угла (луч нужен); в коробке/сугробе множитель заметности остаётся; круг 6 м на земле; дальность первого 14 м;
## шесть маршрутов приёмки (dij_south/east/north/west, N1, N2) по 12 фазам цикла первого поста без ожидания — провал в
## ≥ 9 из 12; «в лоб», обе диагонали и SNEAK_WEST без ожидания — 12 фаз, число чистых в лог (норма ≤ 4 / ≤ 6); честные
## SNEAK_EAST/WEST с ожиданием — проход (время в лог); окно 30 с — 0 кадров; чекпоинт вне.
## EXT-01 fix7 (седьмая приёмка): у первого восток — 150° (после покупки — 100°), второй держит восток 10–12 с, как запад;
## окно — ≥ 10° за краями всех секторов обоих постов (и поста после покупки); подходы с востока E_z76/77/78/80 (с дороги B
## на запад вдоль z) и C_e64…68 (с улицы C) — по 12 фаз цикла каждого поста без ожидания, число чистых в лог, норма — не
## во всех 12 (не истинная дыра).
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/stealth_test.gd
## Кадры: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/stealth_test.gd -- --capture
##   (только часть 12: -- --capture --fix3-only; только часть 13: -- --capture --fix5-only → builds/screenshots/EXT-01/fix5/;
##   только часть 14: -- --capture --fix6-only → builds/screenshots/EXT-01/fix6/; только её кадры: -- --capture --fix6-only
##   --fix6-frames)
##   → builds/screenshots/ext01/s/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const SensorScript = preload("res://game/stealth/detection_sensor.gd")
const QuestFlowScript = preload("res://game/mission/quest_flow.gd")
const PatrolsScript = preload("res://game/world/patrols.gd")
const OUT := "res://builds/screenshots/ext01/s"
const OUT5 := "res://builds/screenshots/EXT-01/fix5"
const OUT6 := "res://builds/screenshots/EXT-01/fix6"
const SnowSpotScript = preload("res://game/stealth/snow_hide_spot.gd")
## fix5: диагональ с дороги B к окну (пятая приёмка, P1-1) — от места выхода у парковки; окно — _vendor_stand().
const DIAG_LONG := [Vector3(62, 0, -53), Vector3(73.5, 0, -53), Vector3(73.5, 0, -64.5), Vector3(68, 0, -69), Vector3(62.5, 0, -73.2), Vector3(60.5, 0, -75.3)]
const DIAG_SHORT := [Vector3(62, 0, -53), Vector3(72, 0, -63), Vector3(72.3, 0, -64.3)]
## Где ждать угла 0 на диагонали: восточный край B, дальше дальности первого поста (14,8 м).
const DIAG_WAIT := Vector3(75, 0, -63)
## fix7: начало отрезка обхода по дороге x = 74,6 вне дальности первого поста (17,4 м).
const ROAD_NEAR := Vector3(74.6, 0, -58)
const FAIL_TEXT := "ВАШ МАРШРУТ УТОЧНЁН"
const TOAST_TEXT := DemoWorld.STEALTH_TOAST_NO_BREAD   # до покупки; после — DemoWorld.STEALTH_TOAST (TEXT-01)
const HINT_TEXT := "Тебя заметили! Отойди"   # SuspicionMeter.HINT_TEXT (TEXT-01)
## Начало прямой «в лоб» к окну: перед машиной на парковке, вне конусов (дальше 12 м от поста).
const DIRECT_FROM := Vector3(59.5, 0, -57.3)
const CAR_TOAST := "МАШИНУ ОТОГНАЛИ НА ПАРКОВКУ"
## Где Илюша говорит с полицейским (угол 0): северо-западнее поста, 2,1 м — сбоку, вне конуса, E доступна; fix6 — в
## радиусе близости (3 м): видят без угла, рост ×3 — успеть нажать E.
const TALK_SPOT := Layout.OFFICER_POST + Vector3(-1.5, 0, -1.5)
## За спиной полицейского при угле 0 (169° от корпуса).
const BEHIND_SPOT := Layout.OFFICER_POST + Vector3(1.5, 0, -0.5)

var failures: Array[String] = []
var checks := 0
var capture := false
var main: Node
var drv
var world: DemoWorld
var sensor: DetectionSensor
var detected_signals := 0
var completed_signals := 0
var _foreign: Array = []
# Монитор части 10 (drv.on_frame): максимум шкалы, кадры, первый кадр экрана провала.
var _track_max := 0.0
var _track_frames := 0
var _track_fail := -1
var _kiosk_detections := 0
# Часть 12: кадры, в которые сенсор _watch_sensor (второй пост) видел Илюшу.
var _watch_sensor: DetectionSensor
var _watch_frames := 0
var _out := OUT

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	create_timer(14400.0, true, false, true).timeout.connect(func():
		push_error("FAIL: stealth test exceeded 14400 simulated seconds")
		_finish(2))
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT5))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT6))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	world = main.world
	_free_residents()
	if not check(world != null and world.get_node_or_null("StealthDirector") is StealthDirector, "DemoWorld has the StealthDirector node (C7)"):
		_finish()
		return
	check(world.stealth.process_mode == Node.PROCESS_MODE_PAUSABLE, "StealthDirector is PAUSABLE (no ticking on pause)")
	world.stealth.player_detected.connect(func(): detected_signals += 1)
	world.mission.quest_completed.connect(func(_xp): completed_signals += 1)
	for s in get_nodes_in_group(&"detection_sensors"):
		_foreign.append(s)
		s.enabled = false
	print("INFO: foreign sensors in the world: %d" % _foreign.size())
	sensor = SensorScript.new()
	sensor.name = "TestSensor"
	world.add_child(sensor)
	check(sensor.is_in_group(&"detection_sensors"), "sensor joins group detection_sensors")
	if "--fix3-only" in OS.get_cmdline_user_args():   # кадры части 12 без остального прогона
		await _part_fix3()
		drv.release_all()
		_finish()
		return
	if "--fix5-only" in OS.get_cmdline_user_args():   # часть 13 без остального прогона
		await _part_fix5()
		drv.release_all()
		_finish()
		return
	if "--fix6-only" in OS.get_cmdline_user_args():   # часть 14 без остального прогона
		await _part_fix6()
		drv.release_all()
		_finish()
		return
	await _part_geometry()
	await _part_cover()
	await _part_decay()
	if await _part_dialog_and_pause():
		if await _part_car():
			await _part_fail_before()
			if await _part_buy_and_fail_after():
				await _part_checkpoint()
				await _part_complete()
	check(detected_signals == 2, "player_detected fired exactly twice in the run (%d)" % detected_signals)
	drv.release_all()
	await _part_kiosk_section()
	drv.release_all()
	await _part_fix2()
	drv.release_all()
	await _part_fix3()
	drv.release_all()
	await _part_fix5()
	drv.release_all()
	await _part_fix6()
	drv.release_all()
	_finish()

# =====================================================================================
# 1. Расстояние и угол (открытая площадка двора, относительно SPAWN)
# =====================================================================================

func _part_geometry() -> void:
	print("--- geometry ---")
	var p := Layout.SPAWN + Vector3(10.0, 0.0, -12.0)
	check(_free(p), "yard spot for the geometry checks is free (%s)" % p)
	await _place_player(p, 0.0)
	sensor.range_m = 9.0
	sensor.fov_deg = 75.0
	sensor.enabled = true
	_aim(p + Vector3(0, 0, -5), p)
	check(_vis() == 1.0, "5 m in front, facing Ilyusha → 1")
	_aim(p + Vector3(0, 0, -8.5), p)
	check(_vis() == 1.0, "8.5 m (inside range 9) → 1")
	_aim(p + Vector3(0, 0, -12), p)
	check(_vis() == 0.0, "12 m (outside range 9) → 0")
	# fix6: ближе DetectionSensor.NEAR_RING (6 м) угол не проверяется — угол проверяем в 7–8,5 м.
	_aim(p + Vector3(0, 0, -7), p + Vector3(0, 0, -20))
	check(_vis() == 0.0, "7 m but facing away → 0")
	_aim(p + Vector3(0, 0, -8), p)
	sensor.rotation.y += deg_to_rad(30.0)
	check(_vis() == 1.0, "8 m, 30° off axis (fov 75) → 1")
	sensor.rotation.y += deg_to_rad(16.0)
	check(_vis() == 0.0, "8 m, 46° off axis (fov 75) → 0")
	_aim(p + Vector3(0, 0, -5), p)
	sensor.enabled = false
	check(_vis() == 0.0, "enabled = false → 0")
	sensor.enabled = true
	# Кэш: visibility() обновляется опросом раз в 0,15 с, а не каждый кадр.
	_aim(p + Vector3(0, 0, -5), p)
	await drv.frames(12)
	check(sensor.visibility() == 1.0, "cached visibility() is 1 after the poll")
	sensor.enabled = false
	await drv.frames(60)
	check(world.stealth.suspicion == 0.0 or world.stealth.state != &"alert", "no alert from the geometry checks")

# =====================================================================================
# 2. Луч: укрытия и декор (точки от коробок Layout)
# =====================================================================================

func _part_cover() -> void:
	print("--- cover ---")
	sensor.range_m = 30.0
	sensor.fov_deg = 90.0
	sensor.enabled = true
	# Стена дома H8_East: Илюша у западной стены, сенсор за восточной.
	var h8 := _solid("H8_East")
	var west_x: float = h8[0].x - h8[1].x * 0.5
	var east_x: float = h8[0].x + h8[1].x * 0.5
	var z := -80.0
	var p := Vector3(west_x - 3.0, 0, z)
	check(_free(p), "spot west of H8_East is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(east_x + 3.0, 0, z), p)
	check(_vis() == 0.0, "house wall (H8_East) covers Ilyusha → 0")
	_aim(Vector3(west_x - 8.0, 0, z), p)
	check(_vis() == 1.0, "same distance, nothing between (snow bank 0.9 m is below the ray) → 1")
	# Гаражи у киоска: Илюша западнее ряда, сенсор восточнее.
	var garages := _solid("Garages_Kiosk")
	var gz: float = garages[0].y
	p = Vector3(garages[0].x - garages[1].x * 0.5 - 4.0, 0, gz)
	check(_free(p), "spot west of Garages_Kiosk is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(garages[0].x + garages[1].x * 0.5 + 2.0, 0, gz - 2.0), p)
	check(_vis() == 0.0, "garage row covers Ilyusha → 0")
	# Павильон у киоска (KioskPavilion): Илюша западнее, сенсор восточнее; контроль — рядом, мимо павильона.
	var pav := _solid("KioskPavilion")
	var pz: float = pav[0].y
	p = Vector3(pav[0].x - pav[1].x * 0.5 - 2.2, 0, pz)
	check(_free(p), "spot west of KioskPavilion is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(pav[0].x + pav[1].x * 0.5 + 3.0, 0, pz), p)
	check(_vis() == 0.0, "KioskPavilion covers Ilyusha → 0")
	var dz: float = pav[1].z * 0.5 + 2.5
	p = Vector3(p.x, 0, pz - dz)
	check(_free(p), "control spot past the pavilion is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(pav[0].x + pav[1].x * 0.5 + 3.0, 0, pz - dz), p)
	check(_vis() == 1.0, "control: same offset past the pavilion end → 1")
	# Тропинка у киоска — плоский декор без коллизии: Илюша на ней, сенсор на другом её конце.
	var trail := _trail_near(Layout.KIOSK)
	check(trail != null, "a Trail decor mesh exists near the kiosk and has no collision")
	if trail:
		var a: Vector3 = trail.global_position + Vector3(0, 0, -4.0)
		var b: Vector3 = trail.global_position + Vector3(0, 0, 5.0)
		a.y = 0.0
		b.y = 0.0
		await _place_player(a, 0.0)
		_aim(b, a)
		check(_vis() == 1.0, "snow trail (no collision) does not cover → 1 (blocker '%s', trail %s)" % [sensor.last_blocker, trail.global_position])
	# Низкий снег Snow_StreetA (коробка 0,8 м): луч к центру Илюши проходит над ним.
	var snow := _solid("Snow_StreetA")
	p = Vector3(snow[0].x, 0, snow[0].y + snow[1].z * 0.5 + 2.5)
	check(_free(p), "spot south of Snow_StreetA is free (%s)" % p)
	await _place_player(p, 0.0)
	_aim(Vector3(snow[0].x, 0, snow[0].y - snow[1].z * 0.5 - 2.5), p)
	check(_vis() == 1.0, "low snow mound (0.8 m) does not cover → 1")
	sensor.enabled = false
	sensor.range_m = 9.0
	sensor.fov_deg = 75.0
	await drv.frames(60)

# =====================================================================================
# 3. Рост, индикатор, спад и сброс
# =====================================================================================

func _part_decay() -> void:
	print("--- decay ---")
	var p := Layout.SPAWN + Vector3(10.0, 0.0, -12.0)
	await _place_player(p, 0.0)
	_aim(p + Vector3(0, 0, -5), p)
	sensor.enabled = true
	await drv.frames(60)
	var s0: float = world.stealth.suspicion
	check(s0 >= 0.3 and s0 <= 0.6, "after 1.0 s in view suspicion ≈ 0.5 (%.2f; rise 1/2.0 s, poll 0.15 s)" % s0)
	check(world.stealth.state == &"suspicious", "state is suspicious while filling (%s)" % world.stealth.state)
	var hud := world.get_node("GameHUD")
	check(hud.suspicion_meter.is_showing(), "HUD: suspicion meter (eye + !) is showing")
	check(_hud_has(HINT_TEXT), "HUD: hint «%s» on first appearance" % HINT_TEXT)
	check(hud.suspicion_meter.plate.position.x > 1500 and hud.suspicion_meter.plate.position.y < 100, "HUD: meter sits top-right")
	await _shot("indicator_suspicious")
	s0 = world.stealth.suspicion   # в режиме кадров шкала успела вырасти за время снимка
	# Вышли из конуса: Илюша за спиной сенсора дальше кольца близости (fix6: ближе 6 м видят и за спиной).
	await _place_player(p + Vector3(0, 0, -12), 0.0)
	await drv.frames(30)
	var s1: float = world.stealth.suspicion
	check(s1 < s0 - 0.15, "0.5 s out of view: suspicion decays (%.2f → %.2f)" % [s0, s1])
	await drv.frames(60)
	check(world.stealth.suspicion == 0.0 and world.stealth.state == &"safe", "suspicion resets to 0 and safe out of view (%.2f, %s)" % [world.stealth.suspicion, world.stealth.state])
	await drv.frames(40)
	check(not hud.suspicion_meter.is_showing(), "HUD: meter hidden again at 0")
	check(not _hud_has(HINT_TEXT), "HUD: hint gone after 3 s")
	sensor.enabled = false

# =====================================================================================
# 4. frozen: диалог Бабки (вводом) и пауза
# =====================================================================================

func _part_dialog_and_pause() -> bool:
	print("--- dialog & pause ---")
	await _place_player(Layout.SPAWN, Layout.SPAWN_YAW)
	if not check(await drv.walk_to(_babka_stand()), "walked to Babka (%s)" % drv.last_error):
		return false
	await drv.interact()
	await drv.frames(5)
	if not check(world.mission.state == &"OFFERED", "E at Babka opens the offer dialog (%s)" % world.mission.state):
		return false
	check(world.stealth.frozen and world.stealth.snap()["reasons"].has(&"dialog"), "frozen while the dialog is open (reasons %s)" % [world.stealth.snap()["reasons"]])
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(0, 0, -4), p)
	sensor.enabled = true
	await drv.frames(60)
	check(_vis() == 1.0, "sensor does see Ilyusha during the dialog (visibility 1)")
	check(world.stealth.suspicion == 0.0, "…but suspicion stays 0 in the dialog (%.2f)" % world.stealth.suspicion)
	if not check(await drv.press_button("ПРИНЯТЬ"), "ПРИНЯТЬ pressed (%s)" % drv.last_error):
		return false
	await drv.frames(3)
	check(world.mission.state == &"GO_TO_CAR", "quest accepted → GO_TO_CAR")
	check(not world.stealth.frozen, "not frozen after the dialog closes")
	await drv.frames(30)
	check(world.stealth.suspicion > 0.0, "suspicion rises again after the dialog (%.2f)" % world.stealth.suspicion)
	# Пауза: директор не тикает, frozen читается как true.
	await drv.pause_key()
	await drv.frames(3)
	check(paused, "Esc pauses the game")
	check(world.stealth.frozen, "frozen on pause")
	var before: float = world.stealth.suspicion
	await drv.frames(60)
	check(is_equal_approx(world.stealth.suspicion, before), "suspicion unchanged during pause (%.2f vs %.2f)" % [before, world.stealth.suspicion])
	await drv.pause_key()
	await drv.frames(3)
	check(not paused and not world.stealth.frozen, "resume → not frozen")
	sensor.enabled = false
	await drv.frames(90)
	check(world.stealth.suspicion == 0.0, "decayed to 0 before the car checks")
	return true

# =====================================================================================
# 5. В машине не видят; respawn_at_checkpoint() в машине не применяется
# =====================================================================================

func _part_car() -> bool:
	print("--- car ---")
	if not check(await drv.walk_to(_car_stand()), "walked to the Lada (%s)" % drv.last_error):
		return false
	await drv.interact()
	await drv.frames(10)
	if not check(world.control_mode == &"in_car", "E → in the car"):
		return false
	var car_pos: Vector3 = world.car.global_position
	_aim(car_pos + Vector3(0, 0, -5), car_pos)
	sensor.enabled = true
	check(_vis() == 0.0, "sensor 5 m in front of the car: Ilyusha in the car → 0")
	await drv.frames(30)
	check(world.stealth.suspicion == 0.0, "no suspicion in the car")
	check(not world.respawn_at_checkpoint(), "respawn_at_checkpoint() refuses in the car")
	check(world.car.global_position.distance_to(car_pos) < 0.01, "car untouched by the refused respawn")
	await drv.interact()
	await drv.frames(15)
	if not check(world.control_mode == &"on_foot", "E → out of the car"):
		return false
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(0, 0, -4.0), p)   # не вдоль машины: там столб фонаря двора (Lamp_Yard)
	check(_vis() == 1.0, "on foot next to the car → 1 (blocker '%s')" % sensor.last_blocker)
	sensor.enabled = false
	await drv.frames(30)
	return true

# =====================================================================================
# 6. Провал до покупки
# =====================================================================================

func _part_fail_before() -> void:
	print("--- fail before purchase ---")
	var m := world.mission
	var state_before: StringName = m.state
	var car_pos: Vector3 = world.car.global_position
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(0, 0, -4.0), p)
	sensor.enabled = true
	var fail_frame := await _wait_until(func(): return world.is_stealth_failing(), 240)
	check(fail_frame >= 0 and fail_frame >= 100, "≈2 s in view → detection and fail screen (frame %d, blocker '%s')" % [fail_frame, sensor.last_blocker])
	check(detected_signals == 1, "player_detected emitted once (%d)" % detected_signals)
	check(world.stealth.state == &"alert" and world.stealth.suspicion >= 1.0, "state alert at detection")
	check(not world.player.input_enabled, "Ilyusha's input is off during the fail screen")
	await drv.frames(25)
	check(_hud_has(FAIL_TEXT), "HUD: «%s» shown" % FAIL_TEXT)
	await _shot("fail_screen")
	var respawn_frame := await _wait_until(func(): return not world.is_stealth_failing(), 240)
	check(respawn_frame >= 0 and respawn_frame + 25 <= 180, "fail screen ≤ 3 s (%d frames)" % (respawn_frame + 25))
	await drv.frames(2)
	check(_near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "Ilyusha respawned at Layout.STEALTH_CHECKPOINT (%s)" % world.player.global_position)
	check(absf(world.player.global_position.y) < 0.3, "respawn on the ground (y %.2f)" % world.player.global_position.y)
	check(not m.has_bread, "before purchase: has_bread stays false")
	check(m.state == state_before, "mission state unchanged by the fail (%s)" % m.state)
	check(world.car.global_position.distance_to(car_pos) < 0.01, "car not moved by the respawn")
	check(world.stealth.suspicion == 0.0 and world.stealth.state == &"safe", "suspicion reset to 0 / safe after respawn")
	check(world.stealth.frozen and world.stealth.protection_left() > 3.5, "4 s protection after respawn (%.1f s)" % world.stealth.protection_left())
	check(_hud_has(TOAST_TEXT), "HUD: toast «%s»" % TOAST_TEXT)
	check(world.player.input_enabled, "Ilyusha can move after the respawn")
	await _shot("toast_after_respawn")
	# Защита: сенсор видит, шкала не растёт.
	var c := Layout.STEALTH_CHECKPOINT
	_aim(c + Vector3(0, 0, -5), c)
	await drv.frames(60)
	check(_vis() == 1.0 and world.stealth.suspicion == 0.0, "during protection: seen but suspicion stays 0 (%.2f)" % world.stealth.suspicion)
	await drv.frames(90)
	check(not _hud_has(TOAST_TEXT), "toast gone after 2 s")
	await drv.frames(100)
	check(not world.stealth.frozen, "protection over after 4 s")
	check(world.stealth.suspicion > 0.0, "after protection the meter fills again (%.2f)" % world.stealth.suspicion)
	sensor.enabled = false
	await drv.frames(90)
	check(world.stealth.suspicion == 0.0, "decayed to 0 before the purchase")

# =====================================================================================
# 7. Покупка (вводом) и провал после покупки
# =====================================================================================

func _part_buy_and_fail_after() -> bool:
	print("--- purchase & fail after ---")
	var m := world.mission
	if not check(await drv.walk_path([Vector3(58.5, 0, -57), Vector3(59.3, 0, -66), _vendor_stand()]), "walked from the checkpoint to the kiosk window (%s)" % drv.last_error):
		return false
	check(m.state == &"BUY_BREAD", "entering the kiosk square on foot → BUY_BREAD (%s)" % m.state)
	m.add_money(m.money_missing())   # монеты — COINS: 35 ₽ собраны (сбор проверяет tests/coins_test.gd)
	await drv.interact()
	await drv.frames(5)
	for i in 8:
		if m.has_bread:
			break
		if not await _press_any(["КУПИТЬ ХЛЕБ", "ДАЛЬШЕ"]):
			break
	if not check(m.has_bread and m.state == &"RETURN_HOME", "bread bought → RETURN_HOME, has_bread true (%s)" % m.state):
		return false
	await drv.frames(10)
	var car_pos: Vector3 = world.car.global_position
	var p: Vector3 = world.player.global_position
	_aim(p + Vector3(4.0, 0, 0), p)
	sensor.enabled = true
	var fail_frame := await _wait_until(func(): return world.is_stealth_failing(), 240)
	check(fail_frame >= 0 and detected_signals == 2, "second detection after the purchase (frame %d, signals %d)" % [fail_frame, detected_signals])
	var respawn_frame := await _wait_until(func(): return not world.is_stealth_failing(), 240)
	check(respawn_frame >= 0, "fail screen closes again")
	await drv.frames(2)
	check(_near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "respawned at the checkpoint again")
	check(m.has_bread, "after purchase: has_bread is kept")
	check(m.state == &"RETURN_HOME", "FSM stays RETURN_HOME after the fail (%s)" % m.state)
	check(world.car.global_position.distance_to(car_pos) < 0.01, "car still untouched")
	sensor.enabled = false
	return true

# =====================================================================================
# 8. Чекпоинт вне любого конуса (все сенсоры мира включены на один опрос)
# =====================================================================================

func _part_checkpoint() -> void:
	print("--- checkpoint ---")
	await _place_player(Layout.STEALTH_CHECKPOINT, Layout.STEALTH_CHECKPOINT_YAW)
	await drv.frames(200)   # защита после респавна прошла
	var seen := []
	for s in _foreign:
		s.enabled = true
		if s.poll() > 0.0:
			seen.append("%s@%s" % [s.name, s.global_position])
		s.enabled = false
	print("INFO: checkpoint %s checked against %d world sensors" % [Layout.STEALTH_CHECKPOINT, _foreign.size()])
	check(seen.is_empty(), "no world sensor sees Ilyusha at the checkpoint (%s)" % [seen])
	check(_free(Layout.STEALTH_CHECKPOINT), "checkpoint spot is free of solids")
	check(world.stealth.suspicion == 0.0, "suspicion 0 at the checkpoint")

# =====================================================================================
# 9. Возвращение пешком и однократное завершение квеста
# =====================================================================================

func _part_complete() -> void:
	print("--- complete ---")
	var m := world.mission
	# POLISH-03 B: проезжая часть улицы Б перекрыта — пешком по западному тротуару через проход в ограждении.
	var path := [Vector3(62, 0, -46), Vector3(59.5, 0, -40), Vector3(59.5, 0, 30), Layout.ROUTE_WALK[3], Layout.ROUTE_WALK[2], Layout.ROUTE_WALK[1], _babka_stand()]
	if not check(await drv.walk_path(path), "walked back to Babka on foot (%s)" % drv.last_error):
		return
	check(m.has_bread and m.state == &"RETURN_HOME", "arrived with the bread (%s)" % m.state)
	await drv.interact()
	await drv.frames(10)
	# Цепочка реплик при возврате (EXT-01 L): «ДАЛЬШЕ» до кнопки «СДАТЬ ХЛЕБ».
	for i in 10:
		if m.state == &"COMPLETE":
			break
		if not await _press_any(["СДАТЬ ХЛЕБ", "ДАЛЬШЕ"]):
			break
	check(m.state == &"COMPLETE" and m.xp == 50, "E at Babka (+ chain) → COMPLETE, +50 (%s, xp %d)" % [m.state, m.xp])
	check(completed_signals == 1, "quest_completed emitted exactly once (%d)" % completed_signals)
	await drv.frames(60)
	check(completed_signals == 1 and m.state == &"COMPLETE", "still one completion a second later")
	check(world.stealth.state == &"safe", "stealth safe at the end")

# =====================================================================================
# 10. Участок у киоска: свежий мир, настоящие наблюдатели (приёмка EXT-01 28.10)
# =====================================================================================

func _part_kiosk_section() -> void:
	print("--- kiosk section: fresh world, real observers ---")
	drv.on_frame = Callable()
	main.start_game()
	await drv.frames(10)
	world = main.world
	_free_residents()
	var m := world.mission
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	var van: CityVan = patrols.van
	world.stealth.player_detected.connect(func(): _kiosk_detections += 1)
	drv.on_frame = _track
	check(officer.sensor.show_cone and van.sensor.show_cone, "officer and van sensors draw a cone (show_cone)")
	check(Layout.OFFICER_FACING.size() == 3, "officer has three facings (%s)" % [Layout.OFFICER_FACING])
	# [0] накрывает проход у гаражей (x = 51,2) и прямую x = 59,5; [1] — весь восточный проход x = 64,2 на z −60…−68,5.
	var o_range: float = officer.sensor.range_m
	var o_fov: float = officer.sensor.fov_deg
	var west_pts := [Vector3(51.2, 0, -66), Vector3(51.2, 0, -70), Vector3(51.2, 0, -73), Vector3(59.5, 0, -62), Vector3(59.5, 0, -69)]
	var east_pts := [Vector3(64.2, 0, -60), Vector3(64.2, 0, -63), Vector3(64.2, 0, -66), Vector3(64.2, 0, -68.5)]
	check(west_pts.all(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[0], q, o_fov, o_range)), "facing 0 covers the garages passage and the straight line x = 59.5")
	check(east_pts.all(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[1], q, o_fov, o_range)), "facing 1 covers the east passage x = 64.2, z −60…−68.5 entirely")
	check(not east_pts.any(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[0], q, o_fov, o_range)), "facing 0 leaves the east passage open (behind him)")
	check(not [Vector3(51.2, 0, -66), Vector3(51.2, 0, -72)].any(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[1], q, o_fov, o_range)), "facing 1 leaves the garages passage open")
	# Окно вне обоих конусов полицейского: по углу и дальности и настоящим опросом сенсора.
	var o_sensor: DetectionSensor = officer.sensor
	await _place_player(_vendor_stand(), 0.0)
	var window_seen := []
	for fi in Layout.OFFICER_FACING.size():
		var yaw: float = Layout.OFFICER_FACING[fi]
		var to := _vendor_stand() - Layout.OFFICER_POST
		var forward := Vector2(-sin(yaw), -cos(yaw))
		var angle := rad_to_deg(absf(forward.angle_to(Vector2(to.x, to.z))))
		o_sensor.rotation.y = yaw
		o_sensor.fov_deg = officer._fov_for(fi)
		var seen := o_sensor.poll()
		print("INFO: window from the officer post at yaw %.2f: %.1f°, %.1f m, seen %.0f" % [yaw, angle, Vector2(to.x, to.z).length(), seen])
		if seen > 0.0 or angle <= o_sensor.fov_deg * 0.5:
			window_seen.append(yaw)
	o_sensor.fov_deg = officer._fov_for(officer.facing_index())
	check(window_seen.is_empty(), "kiosk window is outside all officer cones (%.0f m, %.0f°) %s" % [o_sensor.range_m, o_sensor.fov_deg, window_seen])
	await drv.frames(30)

	# --- этап 3: учебный автобус на улице A ---
	m.interact(&"babka")
	m.accept()
	await _place_player(Vector3(16, 0, 32), -PI * 0.5)
	await drv.frames(20)
	check(not _cone_visible(o_sensor), "officer cone hidden while Ilyusha is far (%.0f m)" % o_sensor.distance_to_player())
	_reset_track()
	# Учебный круг 6 м (P3): у двери — по южному тротуару, между валом и фонарём (30, 42) / «военкомом».
	await _place_player(Vector3(16, 0, 40.7), -PI * 0.5)
	await drv.frames(5)
	_reset_track()
	var walked: bool = await drv.walk_to(Vector3(44, 0, 40.7))
	var van_cone_seen := _cone_visible(van.sensor)
	check(walked, "stage 3: walked along the south sidewalk of street A past the van door (%s)" % drv.last_error)
	check(is_equal_approx(van.sensor.range_m, CityVan.PARK_SENSOR_RANGE) and CityVan.PARK_SENSOR_RANGE <= 6.0 and van.sensor.cone_color.a < DetectionSensor.CONE_COLOR.a, "stage 3: tutorial circle 6 m, paler than a cone (alpha %.2f < %.2f)" % [van.sensor.cone_color.a, DetectionSensor.CONE_COLOR.a])
	check(_track_max > 0.15 and _track_max <= CityVan.TUTORIAL_CAP + 0.01 and _kiosk_detections == 0, "stage 3: on foot past the van the meter lights up (max %.2f ≤ cap %.2f), no fail" % [_track_max, CityVan.TUTORIAL_CAP])
	await _place_player(Layout.ACCOUNT_OFFICER + Vector3(1.5, 0, -0.5), PI * 0.5)
	await drv.frames(300)
	var hud := world.get_node("GameHUD")
	check(world.stealth.state == &"suspicious" and world.stealth.suspicion <= CityVan.TUTORIAL_CAP + 0.01 and world.stealth.suspicion >= CityVan.TUTORIAL_CAP - 0.05, "stage 3: 5 s next to the «военком» — meter holds at the cap (%.2f, %s)" % [world.stealth.suspicion, world.stealth.state])
	check(hud.suspicion_meter.is_showing() and _kiosk_detections == 0 and not world.is_stealth_failing(), "stage 3: indicator shown, no fail")
	check(van_cone_seen or _cone_visible(van.sensor), "stage 3: van cone shows on foot near the van")
	await _shot("k_stage3_van_cone")
	world.car.reset_to(Vector3(22, 0, 32), -PI * 0.5)
	await drv.frames(5)
	world.enter_car()
	await drv.frames(150)
	check(world.control_mode == &"in_car" and world.stealth.suspicion == 0.0 and van.sensor.poll() == 0.0, "stage 3: in the car next to the van — not seen, meter back to 0 (%.2f)" % world.stealth.suspicion)
	check(not _cone_visible(van.sensor), "stage 3: no cone while in the car")
	check(m.state == &"DRIVE_TO_KIOSK", "quest: in the car → DRIVE_TO_KIOSK (%s)" % m.state)

	# --- этап 4: парковка южнее павильона ---
	var park: Vector3 = Layout.ROUTE_DRIVE[-1]
	var d: Vector3 = park - Layout.ROUTE_DRIVE[-2]
	var park_yaw := atan2(-d.x, -d.z)
	world.car.reset_to(park, park_yaw)
	await drv.frames(10)
	check(m.state == &"BUY_BREAD", "car at the new parking → arrival, BUY_BREAD (%s)" % m.state)
	check(world.exit_car(), "E → out of the car at the parking")
	await drv.frames(30)
	var exit_spot: Vector3 = world.player.global_position
	print("INFO: exit spot at the kiosk parking %s, %.1f m to the window, %.1f m to the officer" % [exit_spot, _flat_d(exit_spot, Layout.VENDOR_WINDOW), _flat_d(exit_spot, Layout.OFFICER_POST)])
	check(_flat_d(exit_spot, Layout.VENDOR_WINDOW) > 20.0, "exit spot is > 20 m from the window")
	check(o_sensor.cone_wanted and _cone_visible(o_sensor), "officer cone shows when Ilyusha comes near (%.1f m < 25)" % o_sensor.distance_to_player())
	check(o_sensor.poll() == 0.0 and world.stealth.suspicion == 0.0, "exit spot is not seen by the officer")
	await _shot("k_parking_view")

	# «В лоб» (P2-1): от места выхода прямо к окну мимо поста — провал в любой фазе разворота: 0 / 2,5 / 5 / 7 с после
	# поворота на угол 0 (как в повторной приёмке).
	check(o_sensor.poll() == 0.0, "start of the straight line is not seen")
	var first_direct := true
	for phase in [0.0, 2.5, 5.0, 7.0]:
		await _place_player(exit_spot, PI)
		await drv.frames(260)
		await _sync_officer(0)
		await drv.frames(int(phase * 60))
		_reset_track()
		var before_direct := _kiosk_detections
		await _walk_path_until_fail([DIRECT_FROM, Vector3(DIRECT_FROM.x, 0, Layout.VENDOR_WINDOW.z + 4.0), _vendor_stand()], 900)
		print("INFO: straight line phase %.1f s after facing 0: fail at %.1f s, max suspicion %.2f" % [phase, _track_fail / 60.0 if _track_fail >= 0 else -1.0, _track_max])
		check(_track_fail >= 0 and _track_fail <= 480 and _kiosk_detections == before_direct + 1, "straight at the officer, phase %.1f s: detected within 8 s (%.1f s)" % [phase, _track_fail / 60.0 if _track_fail >= 0 else -1.0])
		var respawned: int = await _wait_until(func(): return not world.is_stealth_failing(), 300)
		await drv.frames(3)
		if first_direct:
			first_direct = false
			check(respawned >= 0 and _near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "respawned at the checkpoint by the parking (%s)" % world.player.global_position)
			check(absf(wrapf(world.camera_rig.yaw - Layout.STEALTH_CHECKPOINT_YAW, -PI, PI)) < 0.05 and absf(Layout.STEALTH_CHECKPOINT_YAW) < 0.01, "after the respawn the camera looks north, at the square (yaw %.2f)" % world.camera_rig.yaw)
			check(not Layout.KIOSK_ZONE.has_point(Layout.STEALTH_CHECKPOINT + Vector3.UP) and _flat_d(Layout.STEALTH_CHECKPOINT, Layout.ROUTE_DRIVE[-1]) < 8.0, "checkpoint is by the parking, outside KIOSK_ZONE")
			check(not m.has_bread and m.state == &"BUY_BREAD", "fail before the purchase: no bread, BUY_BREAD kept")
			await _shot("k_respawn_view")
		await drv.frames(260)

	# Честные пути: от места выхода, выждать разворот за укрытием.
	for route_name in ["east", "west"]:
		var route: Array = Layout.SNEAK_EAST if route_name == "east" else Layout.SNEAK_WEST
		await _place_player(exit_spot, 0.0)
		await drv.frames(260)   # защита после респавна прошла, шкала на нуле
		var before := _kiosk_detections
		_reset_track()
		var ok: bool = await drv.walk_path(route[0])
		var t_cover := _track_frames / 60.0
		ok = ok and await drv.wait_officer_turn(route[1])
		var t_wait := _track_frames / 60.0 - t_cover
		ok = ok and await drv.walk_path(route[2])
		if route.size() >= 5:   # fix4: SNEAK_WEST — у западной стены киоска выждать угол второго поста
			var t_hold := _track_frames
			ok = ok and await drv.wait_officer_turn(route[3], 1500, drv.officer2())
			t_wait += (_track_frames - t_hold) / 60.0
			ok = ok and await drv.walk_path(route[4])
		var seconds := _track_frames / 60.0
		print("INFO: honest %s path parking → window %.1f s (to cover %.1f, wait %.1f, open part %.1f), max suspicion %.2f" % [route_name, seconds, t_cover, t_wait, seconds - t_cover - t_wait, _track_max])
		check(ok and _kiosk_detections == before and not world.is_stealth_failing(), "honest %s path: parking → window without a fail (%s)" % [route_name, drv.last_error])
		check(seconds >= 12.0 and seconds <= 90.0 and t_wait >= 2.0, "honest %s path needs a wait behind cover: %.1f s, wait %.1f s" % [route_name, seconds, t_wait])
		check(_near2(world.player.global_position, _vendor_stand(), 0.6), "honest %s path ends at the window" % route_name)
		if route_name == "east":
			await _shot("k_east_path_window")
	# Тот же путь без ожидания — в неудобный угол: через гаражи, пока смотрит на запад, — провал.
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	_reset_track()
	var west_wrong := 1 - int(Layout.SNEAK_WEST[1])
	if await drv.walk_path(Layout.SNEAK_WEST[0]) and await drv.wait_officer_turn(west_wrong):
		await _walk_path_until_fail(Layout.SNEAK_WEST[2] + Layout.SNEAK_WEST[4], 900)
	# Сугроб (54; −66,5) и коробка «БАТОНЫ» (54,5; −73,2) EXT-02 затеняют проход у гаражей: открыто ~7 м (1,8 с) —
	# шкала почти полная, но провала может не быть (расчёт fix2). Провал или шкала ≥ 0,6.
	print("INFO: west path while the officer looks west-south-west: max suspicion %.2f, fail frame %d" % [_track_max, _track_fail])
	check(_track_fail >= 0 or _track_max >= 0.6, "west path while the officer looks west-south-west: seen (max %.2f, fail %.1f s)" % [_track_max, _track_fail / 60.0 if _track_fail >= 0 else -1.0])
	await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(260)
	# SNEAK_EAST (fix6: коридор и южная стена киоска при угле [1]), пока смотрит на запад-юго-запад, — видят.
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	_reset_track()
	if await drv.walk_path(Layout.SNEAK_EAST[0]) and await drv.wait_officer_turn(0):
		await _walk_path_until_fail(Layout.SNEAK_EAST[2], 900)
	print("INFO: east path while the officer looks west-south-west: max suspicion %.2f, fail frame %d" % [_track_max, _track_fail])
	check(_track_fail >= 0 or _track_max >= 0.6, "east path while the officer looks west-south-west: seen (max %.2f, fail %.1f s)" % [_track_max, _track_fail / 60.0 if _track_fail >= 0 else -1.0])
	if _track_fail >= 0:
		await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(260)
	# Обратно к окну честно (для покупки).
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	check(await drv.sneak(Layout.SNEAK_EAST[0], Layout.SNEAK_EAST[1], Layout.SNEAK_EAST[2]), "back at the window by the east path (%s)" % drv.last_error)

	# --- этап 7: покупка; «Лада» на пути автобуса ---
	var block_at := Vector3(73.5, 0, -20)
	world.car.reset_to(block_at, 0.0)
	await drv.frames(5)
	var lada_before: Vector3 = world.car.global_position
	var before_buy := _kiosk_detections
	m.add_money(m.money_missing())   # монеты — COINS: 35 ₽ собраны (сбор проверяет tests/coins_test.gd)
	await drv.interact()
	await drv.frames(5)
	for i in 8:
		if m.has_bread:
			break
		if not await _press_any(["КУПИТЬ ХЛЕБ", "ДАЛЬШЕ"]):
			break
	if not check(m.has_bread and m.state == &"RETURN_HOME", "bread bought at the window (%s)" % m.state):
		return
	_reset_track()
	var sensor_while_moving := false
	var cone_while_moving := false
	var moved := false
	for i in 600:
		await drv.frames(1)
		if officer.is_moving():
			moved = true
			sensor_while_moving = sensor_while_moving or o_sensor.enabled
			cone_while_moving = cone_while_moving or _cone_visible(o_sensor)
	check(moved and not sensor_while_moving and not cone_while_moving, "patrol walks to the new post with the sensor off and no cone")
	check(not officer.is_moving() and _near2(officer.global_position, Layout.OFFICER_POST_AFTER, 0.1) and o_sensor.enabled, "patrol at OFFICER_POST_AFTER, sensor on again (%s)" % officer.global_position)
	check(officer.facing_fovs == PatrolsScript.OFFICER_AFTER_FOVS and is_equal_approx(o_sensor.fov_deg, PatrolsScript.OFFICER_AFTER_FOVS[officer.facing_index()]), "fix7: after the purchase the officer views %s° (east 100°, window 27° outside), sensor %.0f° at facing %d" % [PatrolsScript.OFFICER_AFTER_FOVS, o_sensor.fov_deg, officer.facing_index()])
	check(_track_max <= 0.3 and _kiosk_detections == before_buy, "10 s at the window after the purchase: suspicion ≤ 0.3 (max %.2f)" % _track_max)
	# Автобус догоняет «Ладу» на своей полосе и ждёт, не сдвигая её. На B это и полоса встречных машин кольца
	# (ARENA-01 fix P2-2): между автобусом и «Ладой» может встать машина, которая сама ждёт «Ладу», — тоже очередь за ней.
	var waited: int = await _wait_until(func(): return van.blocked_by == world.car \
			or (van.blocked_by is PathVehicle and van.blocked_by.blocked_by == world.car), 2400)
	await drv.frames(180)
	var van_front: Vector3 = van.global_position - van.global_basis.z * CityVan.SIZE.z * 0.5
	check(waited >= 0 and van.is_driving(), "van stops behind the Lada on its path and waits (%s)" % van.global_position)
	check(world.car.global_position.distance_to(lada_before) <= 0.2, "van does not push the Lada (moved %.2f m)" % world.car.global_position.distance_to(lada_before))
	var gap := _flat_d(van_front, world.car.global_position) - Lada.SIZE.z * 0.5
	check(gap >= 1.0, "van keeps a gap to the Lada (%.1f m bumper to bumper)" % gap)
	world.car.reset_to(park, park_yaw)
	var arrived: int = await _wait_until(func(): return not van.is_driving(), 2400)
	await drv.frames(10)
	var stop: Vector3 = Layout.VAN_PATH[-1]
	check(arrived >= 0 and _near2(van.global_position, stop, 0.3) and van.stall_ends == 0, "van stops on the kiosk square at VAN_PATH end (%s)" % van.global_position)
	check(absf(wrapf(van.global_rotation.y - Layout.VAN_STOP_YAW, -PI, PI)) < 0.05 and absf(Layout.VAN_STOP_YAW) < 0.01, "van stands nose north, door east (yaw %.2f)" % van.global_rotation.y)
	check(van.sensor.enabled and is_equal_approx(van.sensor.range_m, CityVan.SENSOR_RANGE) and is_equal_approx(van.sensor.suspicion_cap, 1.0), "van door sensor on at the stop (14 m, full scale)")
	check(_van_clear(van), "van body at the stop overlaps no solid (pavilion, pole, kiosk)")
	check(world.car.global_position.distance_to(park) < 0.3, "Lada still at the parking")
	await _place_player(_vendor_stand(), PI)
	await drv.frames(30)
	await _shot("k_van_after_purchase")

	# Чекпоинт вне всех конусов (посты после покупки, автобус на площадке).
	await _place_player(Layout.STEALTH_CHECKPOINT, Layout.STEALTH_CHECKPOINT_YAW)
	var seen := []
	for s in get_nodes_in_group(&"detection_sensors"):
		if s.enabled and s.poll() > 0.0:
			seen.append("%s@%s" % [s.get_parent().name, s.global_position])
	check(seen.is_empty(), "checkpoint is outside every cone after the purchase (%s)" % [seen])

	# --- этап 8: обратно к машине между постом и автобусом ---
	await _place_player(_vendor_stand(), PI)
	await drv.frames(30)
	var before_back := _kiosk_detections
	_reset_track()
	var back_ok: bool = await drv.sneak(Layout.SNEAK_BACK[0], Layout.SNEAK_BACK[1], Layout.SNEAK_BACK[2])
	back_ok = back_ok and await drv.walk_to(_car_stand())
	print("INFO: honest way back window → car %.1f s, max suspicion %.2f" % [_track_frames / 60.0, _track_max])
	check(back_ok and _kiosk_detections == before_back, "honest way back to the car without a fail (%s)" % drv.last_error)
	await _shot("k_way_back")
	await drv.interact()
	await drv.frames(10)
	check(world.control_mode == &"in_car" and m.has_bread, "second entry into the car with the bread")
	drv.on_frame = Callable()

# =====================================================================================
# 11. EXT-01 fix2: разговор с полицейским, «Лада» на площадке, автобус на полосе, сектор лучами
# =====================================================================================

func _part_fix2() -> void:
	print("--- fix2: officer talk, Lada on the square, van stall, ray cone ---")
	drv.on_frame = Callable()
	main.start_game()
	await drv.frames(10)
	world = main.world
	_free_residents()
	var m := world.mission
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	var van: CityVan = patrols.van
	var o_sensor: DetectionSensor = officer.sensor
	_kiosk_detections = 0
	world.stealth.player_detected.connect(func(): _kiosk_detections += 1)
	drv.on_frame = _track
	m.interact(&"babka")
	m.accept()
	await drv.frames(5)

	# Сектор лучами (P3): луч на павильон короче дальности, свободный — во всю дальность.
	officer.place_at(Layout.OFFICER_POST)
	o_sensor.rotation.y = Layout.OFFICER_FACING[1]
	var to_pav := Vector2(Layout.KIOSK_PAVILION[0].x - Layout.OFFICER_POST.x, Layout.KIOSK_PAVILION[0].y - Layout.OFFICER_POST.z)
	var a_pav := Vector2(-sin(Layout.OFFICER_FACING[1]), -cos(Layout.OFFICER_FACING[1])).angle_to(to_pav)
	var l_pav := o_sensor.cone_ray_length(-a_pav)
	var l_free := o_sensor.cone_ray_length(deg_to_rad(40.0))
	print("INFO: cone ray towards the pavilion %.1f m, free ray %.1f m (range %.0f)" % [l_pav, l_free, o_sensor.range_m])
	check(l_pav < to_pav.length() + 1.0 and l_pav < o_sensor.range_m - 2.0 and l_free > o_sensor.range_m - 0.1, "cone is cut by the pavilion (ray %.1f m) and full elsewhere (%.1f m)" % [l_pav, l_free])
	check(DetectionSensor.CONE_COLOR.a >= 0.10 and DetectionSensor.CONE_COLOR.a <= 0.12, "cone alpha 0.10…0.12 (%.2f)" % DetectionSensor.CONE_COLOR.a)
	officer.place_at(Layout.OFFICER_POST)

	# Подсказка E: со спины — нет, сбоку — есть (угол 0).
	await _place_player(BEHIND_SPOT, PI * 0.5)
	await drv.frames(10)
	var behind_prompt: String = world.get_hud_state()["prompt"]
	await _place_player(TALK_SPOT, PI)
	await drv.frames(10)
	var side_prompt: String = world.get_hud_state()["prompt"]
	check(behind_prompt != "E — ПОГОВОРИТЬ" and side_prompt == "E — ПОГОВОРИТЬ", "officer: no E prompt from behind ('%s'), prompt from the side ('%s')" % [behind_prompt, side_prompt])
	var talk_vis := o_sensor.poll()
	check(talk_vis == 1.0 and o_sensor.near_rise_factor == DetectionSensor.NEAR_RISE_FACTOR, "fix6: talk spot (2.1 m) is inside the 3 m proximity radius — heard, rise ×3")
	await _shot("f_talk_spot")

	# Разговор с полицейским (этап 5): уйти сразу, через 1 с — без провала; уйти сразу на юг к парковке мимо его второго
	# угла (fix3, P3: защита OFFICER_GRACE 5 с) — без провала; стоять — провал.
	for variant in ["leave_at_once", "leave_after_1s", "leave_south", "stand"]:
		await _place_player(_vendor_stand(), 0.0)
		await drv.frames(260)
		check(await drv.wait_officer_turn(0), "%s: officer on facing 0 (%s)" % [variant, drv.last_error])
		var before := _kiosk_detections
		_reset_track()
		# fix6: ближе 3 м рост ×3 — E жмётся, как только появилась подсказка (как игрок), а не после остановки.
		var talk: Array = await _walk_and_talk(TALK_SPOT)
		print("INFO: %s: E at %.2f m from the officer, suspicion at E %.2f" % [variant, talk[2], talk[1]])
		if not check(talk[0], "%s: walking up from the window, E at the prompt opens the officer dialog (suspicion %.2f)" % [variant, talk[1]]):
			return
		for i in 8:
			if not world.quest_flow.is_dialog_open():
				break
			await _press_any([QuestLines.BUTTON_OFFICER_LEAVE, "ДАЛЬШЕ"])
		await drv.frames(2)
		var o_seen_after := o_sensor.poll()
		check(not world.quest_flow.is_dialog_open() and world.stealth.protection_left() > QuestFlowScript.OFFICER_GRACE - 0.5 and QuestFlowScript.OFFICER_GRACE >= 5.0, "%s: dialog closed, grace %.1f s (OFFICER_GRACE %.0f)" % [variant, world.stealth.protection_left(), QuestFlowScript.OFFICER_GRACE])
		# fix4 (P3): все углы без Илюши — из них дальше всего от парковки (fix5: восток, [2]), а не юг, куда уходят.
		check(officer.facing_index() == 2 and officer.away_facing(world.player.global_position) == 2, "%s: officer turns to the facing without Ilyusha, away from the parking (%d)" % [variant, officer.facing_index()])
		var closed_at := _track_frames
		if variant == "stand":
			var failed: int = await _wait_until(func(): return world.is_stealth_failing(), 600)
			var t := (_track_frames - closed_at) / 60.0
			print("INFO: officer talk, standing still after the dialog: fail after %.1f s (watching %s)" % [t, officer.is_watching()])
			check(failed >= 0 and t >= 5.0 and t <= 9.0, "stand: still next to the officer after the dialog — detected after 5…9 s (%.1f s)" % t)
			await _wait_until(func(): return not world.is_stealth_failing(), 300)
		elif variant == "leave_south":
			# Как SNEAK_BACK: вдоль x = 59,3 на юг мимо поста к парковке — через сектор угла 1 под защитой.
			var south: bool = await drv.walk_path([Vector3(59.3, 0, -66), Vector3(59.3, 0, -61), Vector3(61.5, 0, -57.8), Layout.KIOSK_STAGING])
			var walk_s := (_track_frames - closed_at) / 60.0
			await drv.frames(360)
			print("INFO: officer talk, leave_south: at the parking %s in %.1f s, max suspicion %.2f, officer facing %d" % [south, walk_s, _track_max, officer.facing_index()])
			check(south and _kiosk_detections == before and not world.is_stealth_failing(), "leave_south: walked away south to the parking without a fail (%.1f s, max %.2f)" % [walk_s, _track_max])
		else:
			if variant == "leave_after_1s":
				await drv.frames(60)
			var gone: bool = await drv.walk_to(_vendor_stand())
			await drv.frames(360)
			print("INFO: officer talk, %s: back at the window %s, max suspicion %.2f, seen right after %.0f" % [variant, gone, _track_max, o_seen_after])
			check(gone and _kiosk_detections == before and not world.is_stealth_failing(), "%s: walked away to the window without a fail (max %.2f)" % [variant, _track_max])

	# «Лада» с Илюшей: на проезжей части B у поста — не видят; на площадке — провал, машина на парковке.
	m.notify_entered_car()
	m.notify_arrived_kiosk()
	await _place_player(_vendor_stand(), 0.0)
	await drv.frames(260)
	m.add_money(m.money_missing())   # монеты — COINS
	if not check(m.buy_bread() and m.has_bread, "bread bought (%s)" % m.state):
		return
	await _wait_until(func(): return not officer.is_moving(), 900)
	await drv.frames(30)
	# fix3: KIOSK_SQUARE включает проезжую часть B у окна; машину замечают, только когда почти стоит. Проезд по B на
	# север без остановки (≈10 м/с) через всю область — шкала 0.
	world.car.reset_to(Vector3(70, 0, -36), 0.0)
	await drv.frames(3)
	world.enter_car()
	await drv.frames(30)
	var before_car := _kiosk_detections
	_reset_track()
	var min_speeds := [INF]   # массив: лямбда не меняет захваченную локальную переменную
	var on_b := func():
		var c: Vector3 = world.car.global_position
		if Layout.KIOSK_SQUARE.has_point(Vector2(c.x, c.z)):
			min_speeds[0] = minf(min_speeds[0], world.car.speed_kmh() / 3.6)
		return c.z < -96.5
	var passed: bool = await drv.drive_path([Vector3(70, 0, -60), Vector3(70, 0, -100), Vector3(50, 0, -100)], 10.0, 5.0, on_b)
	await drv.brake()
	var min_speed: float = min_speeds[0]
	print("INFO: Lada through street B past the kiosk: min speed on KIOSK_SQUARE %.1f m/s, max suspicion %.2f, ends %s" % [min_speed, _track_max, world.car.global_position])
	check(passed and min_speed >= DetectionSensor.CAR_STILL_SPEED and _track_max == 0.0 and _kiosk_detections == before_car, "Lada drives through street B past the kiosk without stopping: meter 0 (min %.1f m/s, max %.2f)" % [min_speed, _track_max])
	_reset_track()
	var square_at := Vector3(61.5, 0, -82)
	world.car.reset_to(square_at, 0.0)
	await drv.frames(3)
	check(Layout.KIOSK_SQUARE.has_point(Vector2(square_at.x, square_at.z)) and o_sensor.watches_car(), "Lada at %s is on KIOSK_SQUARE, the officer watches it" % square_at)
	check(van.sensor.poll() == 0.0 and not van.sensor.watches_car(), "van sensor does not see the Lada")
	var fail_frame: int = await _wait_until(func(): return world.is_stealth_failing(), 360)
	check(fail_frame >= 0 and fail_frame <= 200 and world.stealth.detected_in_car and _kiosk_detections == before_car + 1, "Lada with Ilyusha on the square: detected (%.1f s, in car %s)" % [fail_frame / 60.0, world.stealth.detected_in_car])
	await drv.frames(25)
	check(_hud_has(FAIL_TEXT), "HUD: «%s» shown for the car" % FAIL_TEXT)
	await _shot("f_car_square_fail")
	await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(3)
	var park: Vector3 = Layout.ROUTE_DRIVE[-1]
	var d: Vector3 = park - Layout.ROUTE_DRIVE[-2]
	check(world.control_mode == &"on_foot" and _near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5), "after the car fail: on foot at the checkpoint (%s)" % world.player.global_position)
	check(_near2(world.car.global_position, park, 0.3) and absf(wrapf(world.car.global_rotation.y - atan2(-d.x, -d.z), -PI, PI)) < 0.05, "car towed to the parking (%s, yaw %.2f)" % [world.car.global_position, world.car.global_rotation.y])
	check(m.has_bread and m.state == &"RETURN_HOME", "has_bread kept, RETURN_HOME (%s)" % m.state)
	check(_hud_has(CAR_TOAST), "HUD: toast «%s»" % CAR_TOAST)
	check(world.player.input_enabled and world.player.visible, "Ilyusha can walk after the car fail")
	await _shot("f_car_towed_checkpoint")
	await drv.frames(200)

	await _part_van_stall(patrols, van)
	drv.on_frame = Callable()

## fix3 (третья приёмка, P3): автобус ГСУМ без телепорта. (A) «Лада» на полосе машин B впереди — стоит; после 12 с
## съехать некуда (путь занят) — ждёт; перенос вне полос — только после 60 с и только вперёд по пути (fix4, push_warning).
## (B) Илюша на месте стоянки — автобус встаёт на повороте на полосе кольца; после 12 с своим ходом доезжает до
## ближайшей точки пути вне полос. (C) «Лада» на обочине A (не полоса) — ждёт 20 с и объезжает по полосе машин.
## Везде: «Ладу» не сдвигает, скачков за кадр нет (кроме крайнего случая A).
func _part_van_stall(patrols: Node, van: CityVan) -> void:
	# POLISH-03 B: здесь проверяется поведение автобуса на полосах кольца — перекрытие улицы Б (с ним — пробка у
	# ограждения) снимаем, как если бы Илюша уже был дома.
	world.mission.notify_home_reached()
	await drv.frames(2)
	var sensors_off := []
	for s in get_nodes_in_group(&"detection_sensors"):
		if s.enabled:
			sensors_off.append(s)
			s.enabled = false
	# (A) хвост VAN_PATH от x = 73,5, z −40 (полоса машин x = 73): «Лада» стоит на пути в 12 м впереди.
	patrols.reset_positions()
	patrols.officer.place_at(Layout.OFFICER_POST_AFTER)   # как после покупки: стоянка автобуса свободна
	await drv.frames(5)
	var block_at := Vector3(73.5, 0, -52)
	world.car.reset_to(block_at, 0.0)
	var tail: Array = [Vector3(73.5, 0, -40)]
	for i in Layout.VAN_PATH.size():
		if Layout.VAN_PATH[i].z < -40.0:
			tail.append(Layout.VAN_PATH[i])
	van.park(tail[0], 0.0)
	for s in sensors_off:
		s.enabled = false
	await drv.frames(5)
	var lada_before: Vector3 = world.car.global_position
	van.drive(tail, Layout.VAN_STOP_YAW)
	var blocked: int = await _wait_until(func(): return van.blocked_by == world.car and van.stall_seconds > 0.0, 3000)
	var w: Array = await _van_watch(van, 4200, func(): return not van.is_driving())
	await drv.frames(10)
	print("INFO: van blocked by the Lada on the B lane at %s: stood %.1f s, largest jump before the end %.2f m, ended at %s (stall_drives %d, stall_ends %d, on lane %s)" % [block_at, w[0], w[1], van.global_position, van.stall_drives, van.stall_ends, van.on_lane()])
	check(blocked >= 0 and w[0] >= CityVan.STALL_TELEPORT_SECONDS - 0.5 and w[0] <= CityVan.STALL_TELEPORT_SECONDS + 1.5 and van.stall_drives == 0 and van.stall_ends == 1, "(A) van blocked on the lane with no way off: waits past 12 s, last-resort move only after 60 s (%.1f s)" % w[0])
	# fix4 (P3): крайний случай — только вперёд по пути (на север за «Ладу», к площадке), не назад на улицу A.
	check(van.global_position.z < block_at.z - 3.0 and van.global_position.x > 55.0, "(A) the last-resort move goes forward past the Lada, not back to street A (%s)" % van.global_position)
	check(w[1] <= 0.3, "(A) no jump while waiting (%.2f m per frame)" % w[1])
	check(not van.on_lane() and _van_clear(van), "(A) after the last resort the van is off the ring lanes, touching nothing (%s)" % van.global_position)
	check(world.car.global_position.distance_to(lada_before) <= 0.2, "(A) van does not push the Lada (moved %.2f m)" % world.car.global_position.distance_to(lada_before))
	check(van.sensor.enabled and is_equal_approx(van.sensor.range_m, CityVan.SENSOR_RANGE), "(A) van door sensor on after the early stop")
	# (B) Илюша на месте стоянки: автобус встаёт на повороте с полосы кольца; через 12 с доезжает своим ходом.
	world.car.reset_to(Layout.ROUTE_DRIVE[-1], 0.0)
	var stand := Vector3(61.5, 0, -71.6)
	await _place_player(stand, 0.0)
	van.park(Layout.VAN_PARK, Layout.VAN_PARK_YAW)   # весь путь от улицы A: на полосе B не ставим — там очередь машин кольца
	for s in sensors_off:
		s.enabled = false
	await drv.frames(5)
	var ends_before: int = van.stall_ends
	van.drive(Layout.VAN_PATH, Layout.VAN_STOP_YAW)
	var stalled: int = await _wait_until(func(): return van.stall_seconds > 0.5 and van.blocked_by == world.player, 4200)
	var stall_pos: Vector3 = van.global_position
	var stall_lane: bool = van.on_lane()
	var wb: Array = await _van_watch(van, 2400, func(): return not van.is_driving())
	await drv.frames(10)
	print("INFO: van blocked by Ilyusha at the stop: stalled at %s (on lane %s), %.1f s to the end, largest jump %.2f m, ended at %s (stall_drives %d, stall_ends %d, on lane %s)" % [stall_pos, stall_lane, wb[0], wb[1], van.global_position, van.stall_drives, van.stall_ends, van.on_lane()])
	check(stalled >= 0 and stall_lane, "(B) van stops on a ring lane behind Ilyusha (%s)" % stall_pos)
	check(van.stall_drives == 1 and van.stall_ends == ends_before and wb[1] <= 0.3 and wb[0] >= CityVan.STALL_SECONDS - 0.5 and wb[0] <= CityVan.STALL_SECONDS + 4.0, "(B) after 12 s the van drives on along its path off the lane, no jump (%.1f s, jump %.2f m)" % [wb[0], wb[1]])
	check(not van.on_lane() and _van_clear(van) and van.global_position.distance_to(world.player.global_position) > 1.5, "(B) van ends off the ring lanes, clear of Ilyusha (%s)" % van.global_position)
	# (C) «Лада» на обочине улицы A (не полоса) на пути автобуса от стоянки: ждёт ≤ 20 с, объезжает по полосе машин.
	await _place_player(Layout.STEALTH_CHECKPOINT, 0.0)
	var shoulder := Vector3(50.0, 0.0, 37.9)
	world.car.reset_to(shoulder, -PI * 0.5)
	van.park(Layout.VAN_PARK, Layout.VAN_PARK_YAW)
	for s in sensors_off:
		s.enabled = false
	await drv.frames(5)
	var lada_c: Vector3 = world.car.global_position
	var ends_c: int = van.stall_ends
	van.drive(Layout.VAN_PATH, Layout.VAN_STOP_YAW)
	var stall_c: int = await _wait_until(func(): return van.blocked_by == world.car and van.stall_seconds > 0.0, 1200)
	var stall_from := _track_frames
	var detoured: int = await _wait_until(func(): return van.detours > 0, 2400)
	var waited_c := (_track_frames - stall_from) / 60.0
	var wc: Array = await _van_watch(van, 6000, func(): return not van.is_driving())
	await drv.frames(10)
	print("INFO: van behind the Lada on the street A shoulder %s: waited %.1f s, detours %d, then %.1f s to the stop, largest jump %.2f m, ended at %s, Lada moved %.2f m (stall_ends %d)" % [shoulder, waited_c, van.detours, wc[0], wc[1], van.global_position, world.car.global_position.distance_to(lada_c), van.stall_ends])
	check(stall_c >= 0 and detoured >= 0 and waited_c >= CityVan.DETOUR_AFTER - 0.5 and waited_c <= CityVan.DETOUR_AFTER + 10.0, "(C) van behind the Lada on the shoulder waits ≥ 20 s, then detours by the car lane (%.1f s)" % waited_c)
	check(wc[1] <= 0.3 and world.car.global_position.distance_to(lada_c) <= 0.05, "(C) detour without jumps (%.2f m) and without touching the Lada (%.2f m)" % [wc[1], world.car.global_position.distance_to(lada_c)])
	check(not van.is_driving() and _near2(van.global_position, Layout.VAN_PATH[-1], 0.5) and van.stall_ends == ends_c, "(C) van reaches its stop on the kiosk square (%s)" % van.global_position)
	for s in sensors_off:
		s.enabled = true

## Ждать условие, следя за автобусом: [секунды, наибольший сдвиг за кадр, м].
func _van_watch(van: Node3D, max_frames: int, condition: Callable) -> Array:
	var last: Vector3 = van.global_position
	var jump := 0.0
	var n := 0
	while n < max_frames and not condition.call():
		await drv.frames(1)
		n += 1
		if van.is_driving():
			jump = maxf(jump, van.global_position.distance_to(last))
		last = van.global_position
	return [n / 60.0, jump]

# =====================================================================================
# 12. EXT-01 fix3 (третья приёмка): второй пост, «Лада» у окна на проезжей части, обход по дороге
# =====================================================================================

func _part_fix3() -> void:
	print("--- fix3: second officer, Lada stopped by the window, road bypass ---")
	drv.on_frame = Callable()
	main.start_game()
	await drv.frames(10)
	world = main.world
	_free_residents()
	var m := world.mission
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	var officer2: Node3D = patrols.officer2
	_kiosk_detections = 0
	world.stealth.player_detected.connect(func(): _kiosk_detections += 1)
	drv.on_frame = _track
	m.interact(&"babka")
	m.accept()
	await drv.frames(5)
	var s1: DetectionSensor = officer.sensor
	var s2: DetectionSensor = officer2.sensor
	_watch_sensor = s2

	# Пост, настройки, без диалога.
	check(officer2 != null and officer2.name == "Officer2" and officer2.interaction_id == &"officer2" and officer2.character == "guard", "Officer2: second observer NPC (id officer2, guard art — ART-08)")
	check(s2.is_in_group(&"detection_sensors") and s2.show_cone and is_equal_approx(s2.range_m, PatrolsScript.OFFICER2_RANGE) and is_equal_approx(s2.range_m, 14.0) and is_equal_approx(s2.fov_deg, PatrolsScript.OFFICER2_FOV) and is_equal_approx(s2.fov_deg, 100.0) and officer2.turn_every == officer.turn_every and officer2.facing_holds == [PatrolsScript.OFFICER2_HOLD_WEST, PatrolsScript.OFFICER2_HOLD_EAST], "Officer2 sensor: in the group, cone, %.0f m / %.0f°, west %s s (fix6), east-south-east %s s (fix7)" % [s2.range_m, s2.fov_deg, PatrolsScript.OFFICER2_HOLD_WEST, PatrolsScript.OFFICER2_HOLD_EAST])
	check(_near2(officer2.global_position, Layout.OFFICER2_POST, 0.05) and Layout.OFFICER2_FACING.size() == 2, "Officer2 at OFFICER2_POST %s, two facings" % Layout.OFFICER2_POST)
	check(s1.car_area == Layout.KIOSK_SQUARE and s2.car_area == Layout.KIOSK_SQUARE and Layout.KIOSK_SQUARE == Rect2(50, -94, 26, 34), "both officers watch cars on KIOSK_SQUARE x 50…76, z −94…−60")
	var road_stop := Vector3(66.9, 0, -75.8)
	var park: Vector3 = Layout.ROUTE_DRIVE[-1]
	check(Layout.KIOSK_SQUARE.has_point(Vector2(road_stop.x, road_stop.z)) and not Layout.KIOSK_SQUARE.has_point(Vector2(park.x, park.z)), "road B by the window %s is on KIOSK_SQUARE, the parking %s is not" % [road_stop, park])
	await _place_player(Layout.OFFICER2_POST + Vector3(-1.2, 0, 1.4), atan2(1.2, 1.4))
	await drv.frames(10)
	check(world.get_hud_state()["prompt"] != "E — ПОГОВОРИТЬ" and not officer2.interactable.enabled and officer2.interactable.prompt == "", "Officer2: no dialog and no E prompt (%s)" % world.get_hud_state()["prompt"])
	await _place_player(Layout.KIOSK_STAGING, 0.0)

	# Геометрия (fix4): окно и честные пути вне обоих конусов второго поста; SNEAK_WEST до западной стены киоска — вне
	# обоих, остаток — вне угла SNEAK_WEST[3] и в конусе другого угла (поэтому ждать); коридор x = 51,3 — в угле 0
	# (запад); дорога у окна и обход по ней — в угле 1.
	var honest := {}
	var routes := {"SNEAK_EAST": Layout.SNEAK_EAST, "SNEAK_WEST": Layout.SNEAK_WEST, "SNEAK_BACK": Layout.SNEAK_BACK, "SNEAK_AGAIN": Layout.SNEAK_AGAIN}
	for route_name in routes:
		var r: Array = routes[route_name]
		var pts: Array = []
		var start: Vector3 = Layout.VENDOR_WINDOW if route_name == "SNEAK_BACK" else Layout.KIOSK_STAGING
		pts.append(start)
		pts.append_array(r[0])
		pts.append_array(r[2])
		honest[route_name] = pts
	var hits := []
	for route_name in honest:
		var pts: Array = honest[route_name]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 0.25))
			for k in n + 1:
				var q := a.lerp(b, float(k) / n)
				for f in 2:
					# fix5: западная стена киоска в секторе [0] (пеленг 260°) геометрически — в тени киоска не считается
					if _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[f], q, s2.fov_deg, s2.range_m) and not _kiosk_shades(Layout.OFFICER2_POST, q):
						hits.append("%s %s f%d" % [route_name, q, f])
	check(hits.is_empty(), "all honest paths SNEAK_* (SNEAK_WEST up to the kiosk west wall) are outside both Officer2 cones or in the kiosk shadow (%s)" % [hits.slice(0, 4)])
	var west_tail: Array = [Layout.SNEAK_WEST[2][-1]]
	west_tail.append_array(Layout.SNEAK_WEST[4])
	var tail_safe := 0
	var tail_seen := 0
	for i in west_tail.size() - 1:
		var a: Vector3 = west_tail[i]
		var b: Vector3 = west_tail[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 0.25))
		for k in n + 1:
			var q := a.lerp(b, float(k) / n)
			tail_safe += 1 if _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[Layout.SNEAK_WEST[3]], q, s2.fov_deg, s2.range_m) else 0
			tail_seen += 1 if _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[1 - Layout.SNEAK_WEST[3]], q, s2.fov_deg, s2.range_m) else 0
	check(tail_safe == 0 and tail_seen > 8, "SNEAK_WEST past the kiosk: outside Officer2 facing %d, in facing %d for %d points (wait needed)" % [Layout.SNEAK_WEST[3], 1 - Layout.SNEAK_WEST[3], tail_seen])
	# fix6: с поста (58; −86) угол 0 (пеленг 235°) — коридор z −87…−77 и проход вдоль северной стены киоска.
	var corridor := []
	for k in 11:
		corridor.append(Vector3(51.3, 0, -87.0 + k))
	for k in 6:
		corridor.append(Vector3(51.5 + k, 0, -79.5))
	check(corridor.all(func(q): return _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[0], q, s2.fov_deg, s2.range_m)) and not corridor.any(func(q): return _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[1], q, s2.fov_deg, s2.range_m)), "facing 0 (south-west) covers the corridor x = 51.3, z −87…−77 and the passage z = −79.5 to x 56.5; facing 1 leaves them")
	# Настоящим опросом: Илюша в коридоре — видят при угле 0 (луч свободен), у западной стены киоска — киоск закрывает.
	var corridor_seen := []
	for q in [Vector3(51.3, 0, -86), Vector3(51.3, 0, -81), Vector3(54.5, 0, -79.5)]:
		await _place_player(q, 0.0)
		s2.rotation.y = Layout.OFFICER2_FACING[0]
		corridor_seen.append(s2.poll())
	await _place_player(Layout.SNEAK_WEST[2][-1], 0.0)
	var hold_seen := []
	for f in 2:
		s2.rotation.y = Layout.OFFICER2_FACING[f]
		hold_seen.append(s2.poll())
	for f in Layout.OFFICER_FACING.size():
		s1.rotation.y = Layout.OFFICER_FACING[f]
		hold_seen.append(s1.poll())
	s1.rotation.y = officer.body_yaw()
	s2.rotation.y = officer2.body_yaw()
	print("INFO: corridor x = 51.3 seen by Officer2 facing 0: %s; kiosk west wall %s seen by Officer2 f0/f1, Officer f0/f1/f2: %s (blocker %s)" % [corridor_seen, Layout.SNEAK_WEST[2][-1], hold_seen, s1.last_blocker])
	check(corridor_seen.all(func(v): return v > 0.0), "Officer2 at facing 0 really sees the corridor (%s)" % [corridor_seen])
	check(hold_seen.all(func(v): return v == 0.0), "the kiosk west wall (SNEAK_WEST hold) is hidden from both posts in all facings (%s)" % [hold_seen])
	await _place_player(_vendor_stand(), 0.0)
	var window_seen := []
	for f in 2:
		s2.rotation.y = Layout.OFFICER2_FACING[f]
		if s2.poll() > 0.0 or _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[f], _vendor_stand(), s2.fov_deg, s2.range_m):
			window_seen.append(f)
	check(window_seen.is_empty(), "kiosk window is outside both Officer2 cones %s" % [window_seen])
	var leg := [Vector3(71, 0, -84), Vector3(68, 0, -84), Vector3(65, 0, -84)]
	check(_in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[1], road_stop, s2.fov_deg, s2.range_m) and leg.all(func(q): return _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[1], q, s2.fov_deg, s2.range_m)), "facing 1 covers the road stop by the window and the road bypass leg z = −84")
	check(not leg.any(func(q): return _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[0], q, s2.fov_deg, s2.range_m)), "facing 0 leaves the road bypass leg open")
	await drv.frames(10)

	# Кадры: второй полицейский с парковки и с дороги, конусы обоих.
	await _place_player(Layout.KIOSK_STAGING, _yaw_to(Layout.KIOSK_STAGING, Layout.OFFICER2_POST))
	await _shot("x3_officer2_from_parking")
	var road_eye := Vector3(70.5, 0, -70)   # fix4: ближе 25 м к обоим постам (второй — на (59, −87))
	await _place_player(road_eye, _yaw_to(road_eye, (Layout.OFFICER_POST + Layout.OFFICER2_POST) * 0.5))
	await drv.frames(30)
	check(_cone_visible(s1) and _cone_visible(s2), "from the road both officer cones are drawn")
	await _shot("x3_cones_both_from_road")
	var corridor_eye := Vector3(51.3, 0, -84)
	await _place_player(corridor_eye, _yaw_to(corridor_eye, Layout.OFFICER2_POST))
	await drv.frames(30)
	await _shot("x4_officer2_from_corridor")

	await _part_fix4_corridor(officer, officer2)
	await _part_fix4_trolley()

	# «Лада» встаёт на проезжей части B у окна: вышел и пошёл к окну — провал сразу (машину видят при выходе); в машине —
	# fix4: на проезжей части замечают после CAR_ROAD_STILL_SECONDS (8 с) стоянки, провал через ~10 с, на 6 с шкала 0.
	var susp_at_6 := [0.0]
	for variant in ["exit_and_walk", "stay_in_car"]:
		await _place_player(Layout.STEALTH_CHECKPOINT, 0.0)
		world.car.reset_to(Vector3(70, 0, -36), 0.0)
		await drv.frames(250)
		await _sync_npc(officer2, 0)
		world.enter_car()
		await drv.frames(5)
		var before := _kiosk_detections
		_reset_track()
		var ok: bool = await drv.drive_path([Vector3(70, 0, -55), Vector3(68, 0, -70), Vector3(66.5, 0, -78)], 8.0, 2.5, func(): return world.is_stealth_failing())
		var slow_at := -1
		for i in 300:
			if world.is_stealth_failing():
				break
			var v: float = drv.forward_speed()
			if slow_at < 0 and absf(v) < DetectionSensor.CAR_STILL_SPEED:
				slow_at = _track_frames
			if absf(v) < 0.3:
				break
			drv._axis(&"move_forward", &"move_back", -signf(v))
			await drv.frames(1)
		drv.release_all()
		var stop_pos: Vector3 = world.car.global_position
		if variant == "exit_and_walk" and not world.is_stealth_failing():
			await drv.interact()
			await drv.frames(2)
			await _walk_path_until_fail([_vendor_stand()], 600)
		else:
			var t_stop := _track_frames
			susp_at_6[0] = -1.0
			while not world.is_stealth_failing() and _track_frames - t_stop < 900:
				await drv.frames(1)
				if susp_at_6[0] < 0.0 and _track_frames - slow_at >= 360:
					susp_at_6[0] = _track_max
		var t_fail := (_track_fail - slow_at) / 60.0 if _track_fail >= 0 and slow_at >= 0 else -1.0
		print("INFO: Lada stopped on road B by the window (%s): at %s, %.1f m from the window, fail %.1f s after < 2 m/s, max suspicion at 6 s %.2f, on foot %s at %s" % [variant, stop_pos, _flat_d(stop_pos, Layout.VENDOR_WINDOW), t_fail, susp_at_6[0], world.control_mode == &"on_foot", world.player.global_position])
		var on_road := stop_pos.x >= Layout.KIOSK_ROAD_X
		if variant == "exit_and_walk":
			check(ok and slow_at >= 0 and Layout.KIOSK_SQUARE.has_point(Vector2(stop_pos.x, stop_pos.z)) and t_fail >= 0.0 and t_fail <= 3.0 and _kiosk_detections == before + 1, "%s: Lada stopped on road B by the window — fail within 3 s (%.1f s)" % [variant, t_fail])
		else:
			check(ok and slow_at >= 0 and on_road and t_fail >= DetectionSensor.CAR_ROAD_STILL_SECONDS and t_fail <= DetectionSensor.CAR_ROAD_STILL_SECONDS + 3.0 and susp_at_6[0] == 0.0 and _kiosk_detections == before + 1, "%s: Lada standing on road B by the window — meter 0 for 6 s, fail after 8…11 s (%.1f s)" % [variant, t_fail])
		if variant == "exit_and_walk":
			check(not _near2(world.player.global_position, _vendor_stand(), 0.8), "exit_and_walk: the fail comes before the window (%s)" % world.player.global_position)
			await drv.frames(25)
			await _shot("x3_fail_window_from_road")
		await _wait_until(func(): return not world.is_stealth_failing(), 300)
		await drv.frames(3)
		if variant == "exit_and_walk":   # fix4 (P3): после alert_now подсказка индикатора после респавна не висит
			check(not world.get_node("GameHUD").suspicion_meter.is_hint_showing() and not _hud_has(HINT_TEXT), "exit_and_walk: after the respawn the «%s» hint is not shown" % HINT_TEXT)
		check(world.control_mode == &"on_foot" and _near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5) and _near2(world.car.global_position, park, 0.3) and _hud_has(CAR_TOAST), "%s: after the fail on foot at the checkpoint, car towed to the parking, toast «%s»" % [variant, CAR_TOAST])
		if variant == "exit_and_walk":
			await drv.frames(10)
			await _shot("x3_respawn_view")
		check(not m.has_bread and m.state == &"BUY_BREAD", "%s: mission untouched (BUY_BREAD)" % variant)
		await drv.frames(200)

	# Обход пешком по дороге x = 74,6 и к окну с севера (как в третьей приёмке).
	var road_a := [Vector3(62, 0, -51), Vector3(74.6, 0, -51), Vector3(74.6, 0, -78)]
	var road_b := [Vector3(74.6, 0, -84), Vector3(64, 0, -84), Vector3(60.5, 0, -79.5), _vendor_stand()]
	# Без ожидания: от парковки сразу, в 12 фазах разворота второго поста (0…16,5 с после поворота на угол 0).
	var road_fails := 0
	var road_seen := 0
	var road_results := []
	for phase in [0.0, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0, 10.5, 12.0, 13.5, 15.0, 16.5]:
		await _place_player(Vector3(62, 0, -51), PI * 0.5)
		await drv.frames(250)
		await _sync_npc(officer2, 0)
		await drv.frames(int(phase * 60))
		var before := _kiosk_detections
		_reset_track()
		var path: Array = road_a.duplicate()
		path.append_array(road_b)
		await _walk_path_until_fail(path, 1800)
		var failed := _kiosk_detections > before
		road_fails += 1 if failed else 0
		road_seen += 1 if failed or _track_max >= 0.6 else 0
		road_results.append("%.1f s: %s (max %.2f, at %s)" % [phase, "fail" if failed else ("window" if _near2(world.player.global_position, _vendor_stand(), 0.8) else "stopped"), _track_max, world.player.global_position])
		if failed:
			await _wait_until(func(): return not world.is_stealth_failing(), 300)
		await drv.frames(200)
	# Сводка для отчёта: удача без ожидания зависит от фазы разворота (как у честных путей), проверки — ниже.
	print("INFO: road bypass x = 74.6 without waiting from the parking, by Officer2 phase after facing 0: fails %d of %d, fail or max ≥ 0.6 in %d of %d: %s" % [road_fails, road_results.size(), road_seen, road_results.size(), road_results])
	# В неудобный угол: дойти до (74,6; −78), дождаться, пока второй пост только что встал в угол 1, и идти — провал.
	# fix7: отрезок x = 74,6 (z −64…−76) — в секторах [1] и [2] первого поста (fix6); к (74,6; −78) — от ROAD_NEAR (17,4 м от
	# поста, вне дальности) сразу после его поворота на запад-юго-запад (≈5 с ходу при удержании ≥ 7 с), иначе провал от
	# первого поста ещё до проверки второго (зависело от фазы).
	await _place_player(ROAD_NEAR, PI)
	await drv.frames(250)
	await _sync_officer(0)
	_reset_track()
	var before_wrong := _kiosk_detections
	var got: bool = await drv.walk_path([road_a[-1]])
	if not got:   # транспорт кольца мог встать на пути — переждать и дойти
		print("INFO: road bypass (wrong phase): %s, retry" % drv.last_error)
		await drv.frames(120)
		got = await drv.walk_path([road_a[-1]])
	await _sync_npc(officer2, 1)
	_reset_track()
	var seen_wrong := _watch_frames
	await _walk_path_until_fail(road_b, 900)
	print("INFO: road bypass right after Officer2 turned to facing 1 (east-south-east): fail %s, max %.2f, Officer2 saw %.1f s" % [_kiosk_detections > before_wrong, _track_max, (_watch_frames - seen_wrong) / 60.0])
	# Луч на отрезке z = −84 идёт почти вдоль полос: машины и троллейбус кольца иногда его перекрывают — провал или
	# шкала ≥ 0,6 (как путь у гаражей в части 10).
	check(got and _watch_frames > seen_wrong and (_kiosk_detections == before_wrong + 1 or _track_max >= 0.6), "road bypass while Officer2 looks east-south-east: seen (fail %s, max %.2f)" % [_kiosk_detections > before_wrong, _track_max])
	await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(250)
	# С ожиданием: у (74,6; −78) вне конусов дождаться угла 0 (запад) — проходит к окну.
	await _place_player(ROAD_NEAR, PI)   # fix7: как выше — отрезок x = 74,6 при угле [0] первого поста
	await drv.frames(250)
	await _sync_officer(0)
	_reset_track()
	var before_ok := _kiosk_detections
	var t0 := _track_frames
	var road_ok: bool = await drv.walk_path([road_a[-1]])
	if not road_ok:
		print("INFO: road bypass (wait): %s, retry" % drv.last_error)
		await drv.frames(120)
		road_ok = await drv.walk_path([road_a[-1]])
	var t_cover := (_track_frames - t0) / 60.0
	await _sync_npc(officer2, 0)
	var t_wait := (_track_frames - t0) / 60.0 - t_cover
	road_ok = road_ok and await drv.walk_path(road_b)
	var t_road := (_track_frames - t0) / 60.0
	print("INFO: road bypass with a wait for Officer2 facing 0: %.1f s (to the wait spot %.1f, wait %.1f), max suspicion %.2f, fails %d" % [t_road, t_cover, t_wait, _track_max, _kiosk_detections - before_ok])
	# fix6: дальность первого 14 м — отрезок x = 74,6 (11,6 м от поста) в его секторах [1] и [2]; обход по дороге больше
	# не честный путь (итог прохода — в лог).
	var x74 := [Vector3(74.6, 0, -64), Vector3(74.6, 0, -70), Vector3(74.6, 0, -76)]
	check(x74.all(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[2], q, officer._fov_for(2), s1.range_m)) and x74.slice(0, 2).all(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[1], q, officer._fov_for(1), s1.range_m)), "fix6: road bypass leg x = 74.6 is within the officer's 14 m in facing 2 (z −64…−76) and facing 1 (z −64…−70)")
	await _shot("x3_road_bypass_window")

	# Честные пути с двумя постами — прежние: от чекпоинта, с ожиданием разворота первого, 15–30 с, второй не видит.
	for route_name in ["east", "west"]:
		var route: Array = Layout.SNEAK_EAST if route_name == "east" else Layout.SNEAK_WEST
		await _place_player(Layout.STEALTH_CHECKPOINT, 0.0)
		await drv.frames(260)
		var before := _kiosk_detections
		_reset_track()
		var seen_before := _watch_frames
		var ok: bool = await drv.sneak_route(route)
		var seconds := _track_frames / 60.0
		var limit := 75.0 if route.size() >= 5 else 45.0   # fix4: SNEAK_WEST ждёт оба поста; fix5: цикл первого — три угла (~27 с); fix6: второй — до 21 с
		print("INFO: fix4 honest %s path checkpoint → window %.1f s, max suspicion %.2f, Officer2 saw %d frames (%s)" % [route_name, seconds, _track_max, _watch_frames - seen_before, drv.last_error if not ok else ""])
		check(ok and _kiosk_detections == before and seconds >= 12.0 and seconds <= limit and _watch_frames == seen_before, "fix4 honest %s path with both posts: no fail, %.1f s (12…%.0f), Officer2 never sees" % [route_name, seconds, limit])

	# После покупки второй пост стоит на месте; обратный путь SNEAK_BACK — без провала, второй не видит.
	m.notify_entered_car()
	m.notify_arrived_kiosk()
	await _place_player(_vendor_stand(), 0.0)
	await drv.frames(30)
	var post2: Vector3 = officer2.global_position
	m.add_money(m.money_missing())   # монеты — COINS
	if not check(m.buy_bread() and m.has_bread, "fix3: bread bought (%s)" % m.state):
		return
	await drv.frames(600)
	await _wait_until(func(): return not patrols.van.is_driving(), 3000)
	check(not officer2.is_moving() and _near2(officer2.global_position, post2, 0.01) and s2.enabled, "after the purchase Officer2 stays at OFFICER2_POST (%s)" % officer2.global_position)
	_reset_track()
	var seen_back := _watch_frames
	var before_back := _kiosk_detections
	var back_ok: bool = await drv.sneak(Layout.SNEAK_BACK[0], Layout.SNEAK_BACK[1], Layout.SNEAK_BACK[2])
	print("INFO: fix4 way back SNEAK_BACK: ok %s (%s), detections %d, Officer2 saw %d frames, max %.2f, at %s" % [back_ok, drv.last_error, _kiosk_detections - before_back, _watch_frames - seen_back, _track_max, world.player.global_position])
	check(back_ok and _kiosk_detections == before_back and _watch_frames == seen_back, "fix3: way back SNEAK_BACK without a fail, Officer2 never sees (%.1f s)" % (_track_frames / 60.0))
	_watch_sensor = null
	drv.on_frame = Callable()

## EXT-01 fix4 (четвёртая приёмка P1): коридор между гаражами (x ≤ 50) и киоском (x ≥ 52,5). (1) «Лада» с Илюшей у
## западной стены киоска (51,2; −77): луч к центру кузова закрыт киоском, к углам — свободен: провал, машину отгоняют.
## (2) Вышел из машины в северной части коридора — провал сразу. (3) Пешком с улицы C через вырез вала и коридор к окну:
## сразу после поворота второго поста на запад — провал или шкала ≥ 0,6; сразу после поворота на восток-юго-восток —
## проходит.
func _part_fix4_corridor(officer: Node3D, officer2: Node3D) -> void:
	var m := world.mission
	var s1: DetectionSensor = officer.sensor
	var s2: DetectionSensor = officer2.sensor
	var park: Vector3 = Layout.ROUTE_DRIVE[-1]
	var corridor_car := Vector3(51.2, 0, -77)
	await _place_player(Layout.STEALTH_CHECKPOINT, 0.0)
	await drv.frames(250)
	world.car.reset_to(corridor_car, 0.0)
	await drv.frames(3)
	world.enter_car()
	await drv.frames(2)
	var rays := []
	for s in [s1, s2]:
		var eye: Vector3 = s.global_position + Vector3.UP * DetectionSensor.EYE_HEIGHT
		var free := []
		for t in DetectionSensor.car_targets(world.car):
			var ex: Array[RID] = s._exclude.duplicate()
			ex.append(world.car.get_rid())
			free.append(world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, t, 1, ex)).is_empty())
		rays.append(free)
	print("INFO: Lada in the corridor %s: rays free [center, 4 corners] Officer %s, Officer2 %s" % [world.car.global_position, rays[0], rays[1]])
	check(not rays[0][0] and not rays[1][0] and (rays[0].slice(1).has(true) or rays[1].slice(1).has(true)), "Lada in the corridor: the ray to the body centre is blocked for both posts, a corner ray is free")
	var before := _kiosk_detections
	_reset_track()
	var fail_at: int = await _wait_until(func(): return world.is_stealth_failing(), 360)
	print("INFO: Lada with Ilyusha in the corridor: fail after %.1f s, in car %s" % [fail_at / 60.0, world.stealth.detected_in_car])
	check(fail_at >= 0 and fail_at <= 200 and world.stealth.detected_in_car and _kiosk_detections == before + 1, "Lada with Ilyusha standing in the corridor (51.2, −77): detected (%.1f s)" % [fail_at / 60.0])
	await drv.frames(25)
	await _shot("x4_car_corridor_fail")
	await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(3)
	check(world.control_mode == &"on_foot" and _near2(world.player.global_position, Layout.STEALTH_CHECKPOINT, 0.5) and _near2(world.car.global_position, park, 0.3) and _hud_has(CAR_TOAST), "corridor: after the fail on foot at the checkpoint, car towed to the parking")
	# Сетка площадки (x 50…64, z −94…−61 — край z = −60 уже парковка, Rect2 его не включает; шаг 1 м, носом на север и на восток): где кузов помещается, видит ли «Ладу»
	# хоть один пост (лучи к центру и углам, без скорости — как при выходе из машины).
	world.enter_car()
	var box := BoxShape3D.new()
	box.size = Lada.SIZE - Vector3(0.1, 0.3, 0.1)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	var total := 0
	var hidden := []
	for yaw in [0.0, PI * 0.5]:
		for xi in 15:
			for zi in 34:
				var p := Vector3(50.0 + xi, 0, -94.0 + zi)
				q.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * (Lada.SIZE.y * 0.5 + 0.15))
				if not world.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
					continue
				world.car.reset_to(p, yaw)
				total += 1
				if not (s1.sees_car_now() or s2.sees_car_now()):
					hidden.append("(%.0f, %.0f, yaw %.2f)" % [p.x, p.z, yaw])
	print("INFO: Lada on the square x 50…64, z −94…−61 (grid 1 m, yaw 0 and π/2): %d positions fit, %d not seen by any post: %s" % [total, hidden.size(), hidden])
	check(total > 300 and hidden.size() * 50 <= total, "Lada on the square: seen by a post at ≥ 98 %% of grid positions (%d hidden of %d)" % [hidden.size(), total])
	world.car.reset_to(park, 0.0)
	world.exit_car()
	await drv.frames(2)
	await _place_player(Layout.STEALTH_CHECKPOINT, 0.0)
	await drv.frames(250)
	# (2) Выйти из машины в северной части коридора (там выйти есть куда) — провал сразу.
	world.car.reset_to(Vector3(51.2, 0, -85), 0.0)
	await drv.frames(3)
	world.enter_car()
	await drv.frames(2)
	before = _kiosk_detections
	var exited := world.exit_car()
	await drv.frames(2)
	print("INFO: exit from the Lada in the corridor at %s: exited %s, failing %s" % [world.car.global_position, exited, world.is_stealth_failing()])
	check(exited and world.is_stealth_failing() and _kiosk_detections == before + 1, "corridor: getting out of the Lada in sight — fail at once")
	await _wait_until(func(): return not world.is_stealth_failing(), 300)
	await drv.frames(250)
	check(_near2(world.car.global_position, park, 0.3) and not m.has_bread, "corridor: car towed, mission untouched")
	# (3) Пешком с улицы C через вырез вала (x 40…52) и коридор к окну.
	var c_start := Vector3(46, 0, -93.5)
	var c_path := [Vector3(51.3, 0, -93.5), Vector3(51.3, 0, -80), Vector3(58.5, 0, -80.5), _vendor_stand()]
	for variant in ["no_wait", "wait"]:
		await _place_player(c_start, PI)
		await drv.frames(250)
		await _sync_npc(officer2, 0 if variant == "no_wait" else 1)
		check(s2.poll() == 0.0 and s1.poll() == 0.0, "street C start %s is not seen (%s)" % [c_start, variant])
		before = _kiosk_detections
		_reset_track()
		var seen0 := _watch_frames
		await _walk_path_until_fail(c_path, 1200)
		var failed := _kiosk_detections > before
		var at_window := _near2(world.player.global_position, _vendor_stand(), 0.8)
		print("INFO: on foot from street C through the corridor (%s): fail %s at %.1f s, at the window %s in %.1f s, max suspicion %.2f, Officer2 saw %.1f s" % [variant, failed, _track_fail / 60.0 if _track_fail >= 0 else -1.0, at_window, _track_frames / 60.0, _track_max, (_watch_frames - seen0) / 60.0])
		if variant == "no_wait":
			check(failed or _track_max >= 0.6, "street C → corridor right after Officer2 turned west: seen (fail %s, max %.2f)" % [failed, _track_max])
			if failed:
				await _wait_until(func(): return not world.is_stealth_failing(), 300)
		else:
			check(not failed and at_window, "street C → corridor right after Officer2 turned east-south-east: at the window without a fail (%.1f s, max %.2f)" % [_track_frames / 60.0, _track_max])
		await drv.frames(200)

## EXT-01 fix4 (четвёртая приёмка P2): «Лада» едет по B на юг за троллейбусом и стоит за ним на остановке (67, −62)
## внутри KIOSK_SQUARE на проезжей части — не «у киоска»: шкала 0 (CAR_ROAD_STILL_SECONDS 8 с). Как в приёмке (X).
func _part_fix4_trolley() -> void:
	var tb: Node3D = world.get_node("LevelGeometry/Traffic").trolleybus
	var n := 0
	while not (absf(tb.global_position.x - 67.0) < 0.5 and tb.global_position.z > -90.0 and tb.global_position.z < -84.0) and n < 30000:
		await drv.frames(1)
		n += 1
	print("INFO: trolleybus on B heading south at %s after %.1f s" % [tb.global_position, n / 60.0])
	await _place_player(Layout.STEALTH_CHECKPOINT, 0.0)
	world.car.reset_to(tb.global_position + Vector3(0, 0, -15.0), PI)
	await drv.frames(2)
	world.enter_car()
	await drv.frames(2)
	var before := _kiosk_detections
	_reset_track()
	var still := 0
	var still_max := 0
	var halt := 0
	var halt_max := 0
	var where := Vector3.ZERO
	var shot := false
	for i in 3600:
		var tp: Vector3 = tb.global_position
		var cp: Vector3 = world.car.global_position
		var gap := _flat_d(tp, cp) - 5.95 - 2.05
		var v: float = drv.forward_speed()
		drv._steer_and_throttle(Vector3(67.0, 0, cp.z + 12.0), clampf((gap - 3.0) * 1.2, 0.0, 9.0))
		if gap < 4.0 and v > 0.3:
			drv._axis(&"move_forward", &"move_back", -1.0)
		await drv.frames(1)
		if Layout.KIOSK_SQUARE.has_point(Vector2(cp.x, cp.z)) and absf(v) < DetectionSensor.CAR_STILL_SPEED:
			still += 1
			if still > still_max:
				still_max = still
				where = cp
			if not shot and still == 240:
				shot = true
				await _shot("x4_lada_behind_trolley")
		else:
			still = 0
		if Layout.KIOSK_SQUARE.has_point(Vector2(cp.x, cp.z)) and cp.x >= Layout.KIOSK_ROAD_X and absf(v) < DetectionSensor.CAR_ROAD_STILL_SPEED:
			halt += 1
			halt_max = maxi(halt_max, halt)
		else:
			halt = 0
		if world.is_stealth_failing() or tp.z > -40.0:
			break
	drv.release_all()
	await drv.brake()
	print("INFO: Lada following the trolleybus south on B: longest < %.0f m/s on KIOSK_SQUARE %.1f s at %s, longest < %.1f m/s on the road (x ≥ %.0f) %.1f s (limit %.0f s), max suspicion %.2f, fail %s" % [DetectionSensor.CAR_STILL_SPEED, still_max / 60.0, where, DetectionSensor.CAR_ROAD_STILL_SPEED, Layout.KIOSK_ROAD_X, halt_max / 60.0, DetectionSensor.CAR_ROAD_STILL_SECONDS, _track_max, _kiosk_detections > before])
	check(halt_max >= 300 and halt_max < int(DetectionSensor.CAR_ROAD_STILL_SECONDS * 60.0) and where.x >= Layout.KIOSK_ROAD_X and _track_max == 0.0 and _kiosk_detections == before, "Lada standing behind the trolleybus at the stop on road B (%.1f s stopped): meter 0, no fail" % [halt_max / 60.0])
	if world.is_stealth_failing():
		await _wait_until(func(): return not world.is_stealth_failing(), 300)
	if world.control_mode == &"in_car":
		world.exit_car()
	await drv.frames(10)

# =====================================================================================
# 13. EXT-01 fix5: три угла первого поста, диагональ с дороги B, крыши
# =====================================================================================

func _part_fix5() -> void:
	print("--- fix5: three officer facings, south-east diagonal from road B, roofs ---")
	_out = OUT5
	drv.on_frame = Callable()
	main.start_game()
	await drv.frames(10)
	world = main.world
	_free_residents()
	var m := world.mission
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	var officer2: Node3D = patrols.officer2
	var s1: DetectionSensor = officer.sensor
	var s2: DetectionSensor = officer2.sensor
	_kiosk_detections = 0
	world.stealth.player_detected.connect(func(): _kiosk_detections += 1)
	drv.on_frame = _track
	m.interact(&"babka")
	m.accept()
	world.car.reset_to(Vector3(22, 0, 32), -PI * 0.5)
	await drv.frames(5)
	world.enter_car()
	await drv.frames(10)
	var park: Vector3 = Layout.ROUTE_DRIVE[-1]
	var d: Vector3 = park - Layout.ROUTE_DRIVE[-2]
	world.car.reset_to(park, atan2(-d.x, -d.z))
	await drv.frames(10)
	check(m.state == &"BUY_BREAD" and world.exit_car(), "fix5: at the parking, BUY_BREAD, out of the car")
	await drv.frames(30)
	var exit_spot: Vector3 = world.player.global_position

	# --- Геометрия: три угла, обзор, восток на диагонали, окно вне всех ---
	check(Layout.OFFICER_FACING.size() == 3 and officer.facing_fovs == PatrolsScript.OFFICER_FOVS and PatrolsScript.OFFICER_FOVS == [100.0, 150.0, 150.0] and is_equal_approx(s1.range_m, 14.0) and not is_nan(officer.avoid_yaw), "Officer: three facings, 14 m (fix6), view %s°, turns avoid the window (avoid_yaw %.2f)" % [PatrolsScript.OFFICER_FOVS, officer.avoid_yaw])
	check(is_equal_approx(s1.fov_deg, officer._fov_for(officer.facing_index())), "sensor view follows the facing (%.0f° at facing %d)" % [s1.fov_deg, officer.facing_index()])
	var diag_pts := [Vector3(68, 0, -69), Vector3(66, 0, -72), Vector3(71, 0, -64.5), Vector3(70, 0, -66)]
	check(diag_pts.all(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[2], q, officer._fov_for(2), s1.range_m)), "facing 2 (east) covers the diagonal %s" % [diag_pts])
	var second_leg := [Vector3(70.5, 0, -66.5), Vector3(69.5, 0, -67.5)]
	check(second_leg.all(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[1], q, officer._fov_for(1), s1.range_m)) and [Vector3(59.5, 0, -60), Vector3(59.5, 0, -66)].all(func(q): return _in_cone(Layout.OFFICER_POST, Layout.OFFICER_FACING[1], q, officer._fov_for(1), s1.range_m)), "facing 1 covers the diagonal second leg and the straight line x = 59.5 to z −66")
	var window_off := []
	for f in Layout.OFFICER_FACING.size():
		var yaw: float = Layout.OFFICER_FACING[f]
		var to := Layout.VENDOR_WINDOW - Layout.OFFICER_POST
		window_off.append(snappedf(rad_to_deg(absf(Vector2(-sin(yaw), -cos(yaw)).angle_to(Vector2(to.x, to.z)))) - officer._fov_for(f) * 0.5, 0.1))
	print("INFO: window beyond the officer sector edges by %s°" % [window_off])
	check(window_off.all(func(v): return v > 20.0), "window is ≥ 20° outside each of the three sectors %s" % [window_off])
	# Контейнеры отодвинуты, сугроб и SNEAK_WEST не задеты.
	var garages := _solid("Garages_Kiosk")
	var bins := _solid("KioskBins")
	var gap: float = (bins[0].x - bins[1].x * 0.5) - (garages[0].x + garages[1].x * 0.5)
	var bins_s: float = bins[0].y - bins[1].z * 0.5
	var bins_n: float = bins[0].y + bins[1].z * 0.5
	var drift_s: float = Layout.HIDE_SNOWDRIFT.z + SnowSpotScript.SIZE.z * 0.5   # южный край сугроба (z — на юг)
	var west_min := INF
	var west_pts: Array = [Layout.KIOSK_STAGING] + Layout.SNEAK_WEST[0] + Layout.SNEAK_WEST[2] + Layout.SNEAK_WEST[4]
	for i in west_pts.size() - 1:
		var a: Vector3 = west_pts[i]
		var b: Vector3 = west_pts[i + 1]
		for k in 41:
			var q := a.lerp(b, k / 40.0)
			var dx := maxf(absf(q.x - bins[0].x) - bins[1].x * 0.5, 0.0)
			var dz := maxf(absf(q.z - bins[0].y) - bins[1].z * 0.5, 0.0)
			west_min = minf(west_min, Vector2(dx, dz).length())
	print("INFO: KIOSK_BINS x %.1f…%.1f z %.1f…%.1f; gap to the garages %.2f m; to the snowdrift %.2f m; SNEAK_WEST min %.2f m" % [bins[0].x - bins[1].x * 0.5, bins[0].x + bins[1].x * 0.5, bins_s, bins_n, gap, bins_s - drift_s, west_min])
	check(gap >= 3.8 and bins_s - drift_s >= 1.5 and west_min >= 1.0, "bins 3.9 m off the garages wall, ≥ 1.5 m from the snowdrift, SNEAK_WEST ≥ 1 m away (%.2f / %.2f / %.2f)" % [gap, bins_s - drift_s, west_min])

	# --- Окно 30 с при трёх углах: ни одного кадра видимости ---
	await _place_player(_vendor_stand(), PI * 0.5)
	await drv.frames(30)
	var seen_frames := 0
	var facings_seen := {}
	for i in 1800:
		await drv.frames(1)
		facings_seen[officer.facing_index()] = true
		for s in get_nodes_in_group(&"detection_sensors"):
			if s.get("enabled") != false and s.visibility() > 0.0:
				seen_frames += 1
				break
	check(seen_frames == 0 and facings_seen.size() == 3, "30 s at the window: 0 frames seen (%d) while the officer cycles all three facings %s" % [seen_frames, facings_seen.keys()])

	# Кадр: третий угол (восток) с парковки.
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	await _sync_officer(2)
	await _place_player(Vector3(62, 0, -55), _yaw_to(Vector3(62, 0, -55), Layout.OFFICER_POST + Vector3(4, 0, 0)))
	await drv.frames(20)
	await _shot("f5_east_facing_from_parking")

	# --- Диагональ без ожидания: 12 фаз 0…16,5 с после поворота на угол 0 (сетка пятой приёмки) ---
	var summary := {}
	# Транспорт кольца (троллейбус у остановки B, машины) — естественное укрытие: кадры, когда Илюша в секторе первого
	# поста, а луч перекрыт машиной или троллейбусом, считаются отдельно.
	var traffic := {}
	for v in world.find_children("*", "", true, false):
		if v is PathVehicle or v is Trolleybus or v is TrafficCar:
			traffic[String(v.name)] = true
	print("INFO: fix5 traffic bodies: %d %s" % [traffic.size(), traffic.keys().slice(0, 6)])
	for route_name in ["diag_long", "diag_short"]:
		var pts: Array = (DIAG_LONG if route_name == "diag_long" else DIAG_SHORT).duplicate()
		pts.append(_vendor_stand())
		var clean := 0
		var clean_traffic := 0
		var fails := 0
		var maxes := []
		for k in 12:
			var phase := 1.5 * k
			await _place_player(exit_spot, PI)
			await drv.frames(260)
			await _sync_officer(0)
			await drv.frames(int(phase * 60))
			_reset_track()
			var before := _kiosk_detections
			var trace := []
			var verbose := "--fix5-verbose" in OS.get_cmdline_user_args()
			var covered := [0]
			drv.on_frame = func():
				_track()
				if s1.visibility() == 0.0 and traffic.has(s1.last_blocker) and _in_cone(officer.global_position, officer.body_yaw(), world.player.global_position, s1.fov_deg, s1.range_m):
					covered[0] += 1
				if verbose and _track_frames % 15 == 0:
						trace.append("%.2f:%d%s%s(%.0f,%.0f)%.2f" % [_track_frames / 60.0, officer.facing_index(), "t" if officer.is_turning() else "", "*" if s1.visibility() > 0.0 else ("[%s]" % s1.last_blocker if s1.last_blocker != "" and _in_cone(officer.global_position, officer.body_yaw(), world.player.global_position, s1.fov_deg, s1.range_m) else ""), world.player.global_position.x, world.player.global_position.z, world.stealth.suspicion])
			await _walk_path_until_fail(pts, 3600)
			await drv.frames(20)
			drv.on_frame = _track
			if not trace.is_empty():
				print("TRACE ", " ".join(trace))
			var failed := _kiosk_detections > before or world.is_stealth_failing()
			var at_window := _near2(world.player.global_position, _vendor_stand(), 0.8)
			maxes.append(snappedf(_track_max, 0.01))
			if failed:
				fails += 1
			elif at_window and _track_max < 0.6:
				clean += 1
				if covered[0] >= 30:
					clean_traffic += 1
			print("INFO: fix5 %s no wait, phase %.1f s after facing 0: %s in %.1f s, max %.2f, covered by traffic %.1f s" % [route_name, phase, "FAIL" if failed else ("window" if at_window else "stopped at %s" % world.player.global_position), _track_frames / 60.0, _track_max, covered[0] / 60.0])
			if failed:
				if route_name == "diag_long" and k == 6 and capture:
					await _shot("f5_diag_fail_screen")
				await _wait_until(func(): return not world.is_stealth_failing(), 300)
		summary[route_name] = clean
		print("INFO: fix5 %s without a wait: clean (window, no fail, max < 0.6) %d of 12 (of them behind traffic ≥ 0.5 s: %d), fails %d, max by phase %s" % [route_name, clean, clean_traffic, fails, maxes])
		check(clean - clean_traffic <= 2, "%s without a wait: clean in ≤ 2 of 12 phases, not counting cover by traffic (%d, behind traffic %d)" % [route_name, clean, clean_traffic])

	# Справочно (без проверки): те же пути и «в лоб» по полному циклу первого поста (12 фаз на длину цикла).
	await _sync_officer(0)
	var c0 := _track_frames
	await _sync_officer(0)
	var cycle := (_track_frames - c0) / 60.0
	for route_name in ["diag_long", "diag_short", "direct"]:
		var pts: Array
		if route_name == "direct":
			pts = [DIRECT_FROM, Vector3(DIRECT_FROM.x, 0, Layout.VENDOR_WINDOW.z + 4.0), _vendor_stand()]
		else:
			pts = (DIAG_LONG if route_name == "diag_long" else DIAG_SHORT).duplicate()
			pts.append(_vendor_stand())
		var clean := 0
		var maxes := []
		for k in 12:
			await _place_player(exit_spot, PI)
			await drv.frames(260)
			await _sync_officer(0)
			await drv.frames(int(cycle * k / 12.0 * 60))
			_reset_track()
			var before := _kiosk_detections
			await _walk_path_until_fail(pts, 3600)
			await drv.frames(20)
			var failed := _kiosk_detections > before or world.is_stealth_failing()
			maxes.append(snappedf(_track_max, 0.01))
			if not failed and _near2(world.player.global_position, _vendor_stand(), 0.8) and _track_max < 0.6:
				clean += 1
			if failed:
				await _wait_until(func(): return not world.is_stealth_failing(), 300)
		print("INFO: fix5 full cycle %.1f s, %s without a wait: clean %d of 12, max by phase %s" % [cycle, route_name, clean, maxes])

	# Кадр: диагональ под восточным конусом.
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	await _sync_officer(2)
	await _place_player(Vector3(70, 0, -66.5), _yaw_to(Vector3(70, 0, -66.5), Layout.VENDOR_WINDOW))
	await drv.frames(15)
	await _shot("f5_diag_under_east_cone")
	await _wait_until(func(): return world.is_stealth_failing(), 240)
	await _wait_until(func(): return not world.is_stealth_failing(), 300)

	# --- Диагональ с ожиданием угла 0 (fix5 — честная) — fix6: её второе колено идёт в 3,2 м от поста, в кольце близости
	# 6 м (угол не проверяется) — провал и с ожиданием.
	await _place_player(exit_spot, PI)
	await drv.frames(260)
	_reset_track()
	var before_w := _kiosk_detections
	var ok: bool = await drv.walk_path([Vector3(62, 0, -53), Vector3(75, 0, -53), DIAG_WAIT])
	var t_cover := _track_frames / 60.0
	ok = ok and await drv.wait_officer_turn(0)
	var t_wait := _track_frames / 60.0 - t_cover
	if ok:
		await _walk_path_until_fail([Vector3(68, 0, -69), Vector3(62.5, 0, -73.2), Vector3(60.5, 0, -75.3), _vendor_stand()], 900)
	await drv.frames(20)
	print("INFO: fix5 diagonal with a wait for facing 0 at %s: %.1f s (to the wait spot %.1f, wait %.1f), max %.2f, fail %s" % [DIAG_WAIT, _track_frames / 60.0, t_cover, t_wait, _track_max, _kiosk_detections > before_w])
	check(ok and (_kiosk_detections == before_w + 1 or _track_max >= 0.6), "fix6: diagonal with a wait for facing 0 passes 3.2 m from the post — heard in the 6 m ring (fail %s, max %.2f)" % [_kiosk_detections > before_w, _track_max])
	if world.is_stealth_failing() or _kiosk_detections > before_w:
		await _wait_until(func(): return not world.is_stealth_failing(), 300)

	# --- Честные пути с ожиданием: проход, время в лог ---
	for route_name in ["SNEAK_EAST", "SNEAK_WEST"]:
		var route: Array = Layout.SNEAK_EAST if route_name == "SNEAK_EAST" else Layout.SNEAK_WEST
		await _place_player(exit_spot, 0.0)
		await drv.frames(260)
		_reset_track()
		var before := _kiosk_detections
		var passed: bool = await drv.sneak_route(route)
		await drv.frames(20)
		print("INFO: fix5 honest %s with waits: %.1f s, max %.2f" % [route_name, _track_frames / 60.0, _track_max])
		check(passed and _kiosk_detections == before and not world.is_stealth_failing(), "%s with waits: window without a fail (%.1f s; %s)" % [route_name, _track_frames / 60.0, drv.last_error])
		if world.is_stealth_failing():
			await _wait_until(func(): return not world.is_stealth_failing(), 300)

	# --- SNEAK_WEST без ожидания: 4 фазы 0 / 2,5 / 5 / 7 с после поворота первого на угол 0 ---
	var west_all: Array = Layout.SNEAK_WEST[0] + Layout.SNEAK_WEST[2] + Layout.SNEAK_WEST[4]
	var west_clean := 0
	var west_max := []
	for phase in [0.0, 2.5, 5.0, 7.0]:
		await _place_player(exit_spot, PI)
		await drv.frames(260)
		await _sync_officer(0)
		await drv.frames(int(phase * 60))
		_reset_track()
		var before := _kiosk_detections
		await _walk_path_until_fail(west_all, 3600)
		await drv.frames(20)
		var failed := _kiosk_detections > before or world.is_stealth_failing()
		var at_window := _near2(world.player.global_position, _vendor_stand(), 0.8)
		west_max.append(snappedf(_track_max, 0.01))
		if not failed and at_window and _track_max < 0.6:
			west_clean += 1
		print("INFO: fix5 SNEAK_WEST no wait, phase %.1f s: %s, max %.2f, Officer2 facing %d" % [phase, "FAIL" if failed else ("window" if at_window else "stopped"), _track_max, officer2.facing_index()])
		if failed:
			await _wait_until(func(): return not world.is_stealth_failing(), 300)
	print("INFO: fix5 SNEAK_WEST without a wait: clean %d of 4, max %s" % [west_clean, west_max])
	# fix6: по 12 фазам полного цикла — часть 14 (норма ≤ 6 из 12); здесь — не все четыре.
	check(west_clean <= 3, "SNEAK_WEST without a wait: clean in ≤ 3 of 4 phases (%d, max %s; 12 phases — part 14)" % [west_clean, west_max])

	# --- Крыши ---
	# Прыжок с контейнеров на крышу гаражей: зазор 3,9 м не берётся (три точки толчка у западного края крышки).
	var best_y := 0.0
	for edge in [54.3, 54.1, 53.95]:
		await _place_player(Vector3(54.5, 1.6, -62.0), PI * 0.5)
		await drv.frames(30)
		var on_bins: float = world.player.global_position.y
		var jumped := false
		for f in 120:
			drv._walk_axes(Vector3(-1, 0, 0))
			if not jumped and world.player.global_position.x <= edge:
				jumped = true
				await drv.tap(&"jump", 2)
			else:
				await drv.frames(1)
		drv.release_all()
		await drv.frames(30)
		var y_end: float = world.player.global_position.y
		best_y = maxf(best_y, y_end)
		print("INFO: fix5 jump from the bins (y %.2f) west at x ≤ %.2f: landed at %s" % [on_bins, edge, world.player.global_position])
		if world.is_stealth_failing():
			await _wait_until(func(): return not world.is_stealth_failing(), 300)
	check(best_y < 2.5, "jump from KIOSK_BINS does not reach the garage roof (best landing y %.2f)" % best_y)
	# На контейнерах (1,3 м) и в прыжке с земли — не «на крыше».
	await _place_player(Vector3(54.5, 1.6, -62.0), 0.0)
	await drv.frames(30)
	var bins_roof := DetectionSensor.player_on_roof(world.player)
	var y_bins: float = world.player.global_position.y
	await _place_player(Vector3(59.5, 0.0, -66.0), 0.0)
	await drv.frames(20)
	var jump_roof := false
	var y_jump := 0.0
	await drv.tap(&"jump", 2)
	for f in 70:
		await drv.frames(1)
		y_jump = maxf(y_jump, world.player.global_position.y)
		jump_roof = jump_roof or DetectionSensor.player_on_roof(world.player)
	check(not bins_roof and y_bins > 1.0 and not jump_roof and y_jump > 1.5, "on the bins (y %.2f) and in a jump from the ground (apex %.2f) — not on a roof" % [y_bins, y_jump])
	await _wait_until(func(): return not world.is_stealth_failing(), 300)
	# Крыша гаражей и крыша киоска: провал за ≤ 2,5 с.
	for roof in [["garage_roof", Vector3(46.0, 3.4, -70.0)], ["garage_roof_north", Vector3(46.0, 3.4, -90.0)], ["kiosk_roof", Vector3(55.0, 3.6, -77.0)]]:
		await _place_player(exit_spot, 0.0)
		await drv.frames(30)
		await _wait_until(func(): return not world.is_stealth_failing() and world.stealth.protection_left() <= 0.0 and world.stealth.suspicion <= 0.0, 900)
		_reset_track()
		var before := _kiosk_detections
		var p: Vector3 = roof[1]
		await _place_player(p, _yaw_to(p, Layout.OFFICER_POST))
		var t: int = await _wait_until(func(): return world.is_stealth_failing(), 300)
		var who := []
		for s in get_nodes_in_group(&"detection_sensors"):
			if s.get("on_roof") == true:
				who.append(String(s.get_parent().name))
		print("INFO: fix5 on the %s %s (y %.2f): fail after %.2f s, seen on the roof by %s" % [roof[0], p, world.player.global_position.y, t / 60.0 if t >= 0 else -1.0, who])
		check(t >= 0 and t <= 150 and _kiosk_detections == before + 1 and world.player.global_position.y > 2.5, "%s: Ilyusha on the roof → fail within 2.5 s (%.2f s, y %.2f)" % [roof[0], t / 60.0 if t >= 0 else -1.0, world.player.global_position.y])
		if roof[0] == "garage_roof" and capture:
			await drv.frames(20)
			await _shot("f5_garage_roof_fail")
		await _wait_until(func(): return not world.is_stealth_failing(), 300)
	# Кадр: Илюша на крыше гаражей до провала.
	await _place_player(exit_spot, 0.0)
	await drv.frames(30)
	await _wait_until(func(): return not world.is_stealth_failing() and world.stealth.protection_left() <= 0.0 and world.stealth.suspicion <= 0.0, 900)
	await _place_player(Vector3(47.0, 3.4, -66.0), _yaw_to(Vector3(47.0, 0, -66.0), Layout.OFFICER_POST))
	await drv.frames(40)
	await _shot("f5_on_garage_roof")
	await _wait_until(func(): return not world.is_stealth_failing(), 400)
	drv.on_frame = Callable()
	_out = OUT

## Ждать, пока наблюдатель o только что встал в угол index (после разворота).
# =====================================================================================
# 14. EXT-01 fix6: правило близости, дальность 14 м, второй пост ближе к коридору, маршруты шестой приёмки
# =====================================================================================

var _f6_frame := 0
var _f6_f0 := -1          # кадр, когда первый пост последний раз встал в угол 0
var _f6_prev_ok := false
var _f7_f0 := -1          # fix7: кадр, когда второй пост последний раз встал в угол 0
var _f7_prev_ok := false

func _f6_monitor() -> void:
	_track()
	_f6_frame += 1
	var o: Node3D = world.get_node("LevelGeometry/Patrols").officer
	var ok: bool = o.facing_index() == 0 and not o.is_turning() and not o.is_moving()
	if ok and not _f6_prev_ok:
		_f6_f0 = _f6_frame
	_f6_prev_ok = ok
	var o2: Node3D = world.get_node("LevelGeometry/Patrols").officer2
	var ok2: bool = o2.facing_index() == 0 and not o2.is_turning()
	if ok2 and not _f7_prev_ok:
		_f7_f0 = _f6_frame
	_f7_prev_ok = ok2

## Кадр последнего поворота на угол 0: sync 1 — первый пост, 2 — второй (fix7).
func _f0_of(sync: int) -> int:
	return _f6_f0 if sync == 1 else _f7_f0

## Средний цикл второго поста по nc циклам, кадры (fix7: удержания случайны).
func _f7_cycle2(nc := 3) -> int:
	var a := _f7_f0
	await _wait_until(func(): return _f7_f0 != a, 2400)
	var b := _f7_f0
	for i in nc:
		var c := _f7_f0
		await _wait_until(func(): return _f7_f0 != c, 2400)
	return int((_f7_f0 - b) / nc)

## Идти по точкам (вводом); застрял у вала — прыжок. Стоп — экран провала или max_frames. [дошёл, причина].
func _f6_walk(points: Array, max_frames := 3600) -> Array:
	var f := 0
	var slow := 0
	for p in points:
		while _flat_d(world.player.global_position, p) > 0.45:
			if world.is_stealth_failing():
				drv.release_all()
				return [false, "fail"]
			var to: Vector3 = p - world.player.global_position
			to.y = 0.0
			drv._walk_axes(to.normalized() * clampf(to.length() / 1.2, 0.35, 1.0))
			var v: Vector3 = world.player.velocity
			slow = slow + 1 if Vector2(v.x, v.z).length() < 1.5 and world.player.is_on_floor() else 0
			if slow >= 8:
				slow = 0
				var down := InputEventAction.new()
				down.action = &"jump"
				down.pressed = true
				Input.parse_input_event(down)
				await drv.frames(2)
				var up := InputEventAction.new()
				up.action = &"jump"
				up.pressed = false
				Input.parse_input_event(up)
			await drv.frames(1)
			f += 1
			if f > max_frames:
				drv.release_all()
				return [false, "timeout before %s" % p]
	drv.release_all()
	return [true, ""]

## Путь без ожидания по n фазам цикла первого поста: фаза k — старт через k/n цикла после поворота на угол 0. Фазы идут
## в порядке ближайшего старта (без лишнего ожидания). Чистая фаза — дошёл до окна без провала.
func _f6_phases(label: String, start: Vector3, points: Array, cycle_f: int, n := 12, sync := 1) -> Dictionary:
	var pending := range(n)
	var res := {"clean": 0, "fails": 0, "other": 0, "maxes": {}, "times": [], "start_seen": 0}
	while not pending.is_empty():
		await _place_player(start, _yaw_to(start, points[0]))
		await drv.frames(250)
		var since := _f6_frame - _f0_of(sync)
		var best := -1
		var best_wait := 1 << 30
		for k in pending:
			var want := int(cycle_f * k / n)
			var wait := want - since if want >= since else cycle_f - since + want
			if wait < best_wait:
				best_wait = wait
				best = k
		pending.erase(best)
		var target_f0 := _f0_of(sync) if int(cycle_f * best / n) >= since else -1
		if target_f0 < 0:
			var old := _f0_of(sync)
			await _wait_until(func(): return _f0_of(sync) != old, cycle_f + 900)
			target_f0 = _f0_of(sync)
		await _wait_until(func(): return _f6_frame - target_f0 >= int(cycle_f * best / n), cycle_f + 60)
		if world.is_stealth_failing() or world.stealth.suspicion > 0.0:
			res["start_seen"] += 1
		var o1: Node3D = world.get_node("LevelGeometry/Patrols").officer
		var o2: Node3D = world.get_node("LevelGeometry/Patrols").officer2
		var f1: int = o1.facing_index()
		var f2: int = o2.facing_index()
		var before := _kiosk_detections
		_reset_track()
		var r: Array = await _f6_walk(points)
		await drv.frames(15)
		var failed := _kiosk_detections > before or world.is_stealth_failing()
		var at_window := _flat_d(world.player.global_position, _vendor_stand()) < 0.9
		res["maxes"][best] = snappedf(_track_max, 0.01)
		if failed:
			res["fails"] += 1
		elif at_window:
			res["clean"] += 1
			res["times"].append(snappedf(_track_frames / 60.0, 0.1))
		else:
			res["other"] += 1
		print("INFO: fix6 %s phase %d/%d (%.1f s after facing 0 of Officer%s; Officer %d, Officer2 %d): %s, %.1f s, max %.2f" % [label, best, n, cycle_f * best / n / 60.0, "" if sync == 1 else "2", f1, f2, "FAIL" if failed else ("window" if at_window else r[1]), _track_frames / 60.0, _track_max])
		if failed:
			await _wait_until(func(): return not world.is_stealth_failing(), 400)
	var maxes := []
	for k in n:
		maxes.append(res["maxes"].get(k, -1.0))
	print("INFO: fix6 %s SUMMARY: clean (window, no fail) %d of %d, fails %d, other %d, start seen %d; max by phase %s; times %s" % [label, res["clean"], n, res["fails"], res["other"], res["start_seen"], maxes, res["times"]])
	return res

## Идти к target вводом и нажать E, как только у полицейского появилась подсказка «E — ПОГОВОРИТЬ».
## [диалог открыт, шкала в момент E, расстояние до поста].
func _walk_and_talk(target: Vector3) -> Array:
	var officer_node: Node3D = world.get_node("LevelGeometry/Patrols").officer
	var post: Vector3 = officer_node.global_position
	for i in 600:
		if world.is_stealth_failing():
			break
		# Подсказка у окна та же («E — ПОГОВОРИТЬ», продавщица) — ждать зону самого полицейского.
		if world.player.current_interactable() == officer_node.interactable and world.get_hud_state()["prompt"] == "E — ПОГОВОРИТЬ":
			var at := world.stealth.suspicion
			var dist := _flat_d(world.player.global_position, post)
			drv.release_all()
			await drv.interact()
			await drv.frames(5)
			return [world.quest_flow.is_dialog_open(), at, dist]
		var to: Vector3 = target - world.player.global_position
		to.y = 0.0
		if to.length() < 0.3:
			break
		drv._walk_axes(to.normalized())
		await drv.frames(1)
	drv.release_all()
	return [false, world.stealth.suspicion, _flat_d(world.player.global_position, post)]

func _part_fix6() -> void:
	print("--- fix6: proximity rule, officer range 14 m, second post near the corridor, sixth acceptance routes ---")
	_out = OUT6
	drv.on_frame = Callable()
	main.start_game()
	await drv.frames(10)
	world = main.world
	_free_residents()
	var m := world.mission
	var patrols: Node = world.get_node("LevelGeometry/Patrols")
	var officer: Node3D = patrols.officer
	var officer2: Node3D = patrols.officer2
	var s1: DetectionSensor = officer.sensor
	var s2: DetectionSensor = officer2.sensor
	_kiosk_detections = 0
	world.stealth.player_detected.connect(func(): _kiosk_detections += 1)
	_f6_f0 = -1
	_f6_prev_ok = false
	_f7_f0 = -1
	_f7_prev_ok = false
	drv.on_frame = _f6_monitor

	# --- Константы и посты ---
	check(is_equal_approx(DetectionSensor.NEAR_RADIUS, 3.0) and is_equal_approx(DetectionSensor.NEAR_RING, 6.0) and is_equal_approx(DetectionSensor.NEAR_RISE_FACTOR, 3.0), "proximity rule: 3 m (no angle, no ray, ×3), 6 m (no angle)")
	check(is_equal_approx(s1.range_m, 14.0) and is_equal_approx(PatrolsScript.OFFICER_RANGE, 14.0) and is_equal_approx(s2.range_m, 14.0), "Officer range 14 m like Officer2 (%.0f / %.0f)" % [s1.range_m, s2.range_m])
	check(_near2(officer.global_position, Layout.OFFICER_POST, 0.05) and _near2(officer2.global_position, Layout.OFFICER2_POST, 0.05), "posts at OFFICER_POST %s and OFFICER2_POST %s" % [Layout.OFFICER_POST, Layout.OFFICER2_POST])
	var deep := [Vector3(50.8, 0, -79.5), Vector3(50.8, 0, -80.5)]
	var deep_d := deep.map(func(q): return snappedf(_flat_d(q, Layout.OFFICER2_POST), 0.01))
	check(deep_d.all(func(v): return v <= 10.0) and deep.all(func(q): return _in_cone(Layout.OFFICER2_POST, Layout.OFFICER2_FACING[0], q, s2.fov_deg, s2.range_m)), "deep corridor %s: ≤ 10 m from Officer2 %s, in its facing 0" % [deep, deep_d])
	var win_d := [_flat_d(_vendor_stand(), Layout.OFFICER_POST), _flat_d(_vendor_stand(), Layout.OFFICER2_POST), _flat_d(Layout.VENDOR_WINDOW, Layout.OFFICER_POST), _flat_d(Layout.VENDOR_WINDOW, Layout.OFFICER2_POST)]
	print("INFO: fix6 window to the posts %s m" % [win_d])
	check(win_d.all(func(v): return v > DetectionSensor.NEAR_RING + 0.5), "kiosk window is ≥ 6.5 m from both posts (%s)" % [win_d])
	# Честные пути — вне колец близости обоих постов (до покупки) и вне кольца поста после покупки и двери автобуса.
	var ring_min := {}
	var routes := {"SNEAK_EAST": [Layout.SNEAK_EAST, [Layout.OFFICER_POST, Layout.OFFICER2_POST]], "SNEAK_WEST": [Layout.SNEAK_WEST, [Layout.OFFICER_POST, Layout.OFFICER2_POST]],
			"SNEAK_BACK": [Layout.SNEAK_BACK, [Layout.OFFICER_POST_AFTER, Layout.OFFICER2_POST]], "SNEAK_AGAIN": [Layout.SNEAK_AGAIN, [Layout.OFFICER_POST_AFTER, Layout.OFFICER2_POST]]}
	for route_name in routes:
		var r: Array = routes[route_name][0]
		var pts: Array = []
		for part in r:
			if part is Array:
				pts.append_array(part)
		var best := INF
		for i in pts.size() - 1:
			for k in 41:
				var q: Vector3 = (pts[i] as Vector3).lerp(pts[i + 1], k / 40.0)
				for post in routes[route_name][1]:
					best = minf(best, _flat_d(q, post))
		ring_min[route_name] = snappedf(best, 0.01)
	print("INFO: fix6 honest paths, nearest approach to a post: %s m" % [ring_min])
	check(ring_min.values().all(func(v): return v > DetectionSensor.NEAR_RING + 0.1), "honest paths SNEAK_* stay outside the 6 m proximity ring of every post (%s)" % [ring_min])
	# fix7: восток первого — 150° (после покупки 100°), второй держит восток, как запад; окно — ≥ 10° за краями секторов.
	check(PatrolsScript.OFFICER_FOVS[2] == 150.0 and PatrolsScript.OFFICER_AFTER_FOVS == [100.0, 150.0, 100.0] and officer.facing_fovs == PatrolsScript.OFFICER_FOVS, "fix7: Officer east view 150° (%s), after the purchase %s" % [PatrolsScript.OFFICER_FOVS, PatrolsScript.OFFICER_AFTER_FOVS])
	check(PatrolsScript.OFFICER2_HOLD_EAST == PatrolsScript.OFFICER2_HOLD_WEST and PatrolsScript.OFFICER2_HOLD_EAST == Vector2(10.0, 12.0), "fix7: Officer2 holds east as long as west (%s / %s s)" % [PatrolsScript.OFFICER2_HOLD_EAST, PatrolsScript.OFFICER2_HOLD_WEST])
	var margins := []
	for q in [_vendor_stand(), Layout.VENDOR_WINDOW]:
		for post_set in [[Layout.OFFICER_POST, Layout.OFFICER_FACING, PatrolsScript.OFFICER_FOVS], [Layout.OFFICER_POST_AFTER, Layout.OFFICER_FACING, PatrolsScript.OFFICER_AFTER_FOVS],
				[Layout.OFFICER2_POST, Layout.OFFICER2_FACING, [PatrolsScript.OFFICER2_FOV, PatrolsScript.OFFICER2_FOV]]]:
			var to := Vector2(q.x - post_set[0].x, q.z - post_set[0].z)
			for i in post_set[1].size():
				var yaw: float = post_set[1][i]
				margins.append(snappedf(rad_to_deg(absf(Vector2(-sin(yaw), -cos(yaw)).angle_to(to))) - post_set[2][i] * 0.5, 0.1))
	print("INFO: fix7 window outside the sectors by (stand / window × Officer [0..2], after [0..2], Officer2 [0..1]) %s°" % [margins])
	check(margins.all(func(m): return m >= 10.0), "fix7: kiosk window ≥ 10° outside every sector of both posts and of the post after the purchase (min %.1f°)" % margins.min())

	# --- Правило близости тестовым сенсором (двор, как часть 1): спиной к Илюше ---
	if not is_instance_valid(sensor) or sensor.get_parent() != world:
		sensor = SensorScript.new()
		sensor.name = "TestSensor"
		world.add_child(sensor)
	sensor.enabled = true
	sensor.range_m = 9.0
	sensor.fov_deg = 75.0
	var p := Layout.SPAWN + Vector3(10.0, 0.0, -12.0)
	await _place_player(p, 0.0)
	var rows := []
	for dist in [2.5, 4.5, 8.0]:
		_aim(p + Vector3(0, 0, -dist), p + Vector3(0, 0, -dist - 10.0))   # смотрит от Илюши
		var v := sensor.poll()
		rows.append([dist, v, sensor.near_rise_factor, sensor.near])
	print("INFO: fix6 sensor facing away: [distance, visibility, rise factor, near] %s" % [rows])
	check(rows[0][1] == 1.0 and rows[0][2] == 3.0, "facing away, 2.5 m: seen (heard steps), rise ×3")
	check(rows[1][1] == 1.0 and rows[1][2] == 1.0, "facing away, 4.5 m, open ray: seen without the angle, rise ×1")
	check(rows[2][1] == 0.0, "facing away, 8 m: not seen")
	# Кольцо 3…6 м — луч нужен: киоск (5 × 4 м) между сенсором и Илюшей; ближе 3 м — луч не нужен (сквозь киоск).
	var qk := Vector3(52.0, 0, -77.0)
	await _place_player(qk, 0.0)
	_aim(Vector3(57.9, 0, -77.0), Vector3(67.9, 0, -77.0))   # 5,9 м, спиной, киоск между
	var wall := sensor.poll()
	var wall_blocker := sensor.last_blocker
	await _place_player(Vector3(61.25, 0, -63.2), 0.0)
	_aim(Vector3(63.75, 0, -63.2), Vector3(73.75, 0, -63.2))   # 2,5 м сквозь павильон остановки, спиной
	var near_wall := sensor.poll()
	print("INFO: fix6 5.9 m behind the kiosk: %.0f (blocker %s); 2.5 m through the bus-stop pavilion, facing away: %.0f" % [wall, wall_blocker, near_wall])
	check(wall == 0.0 and wall_blocker != "" and near_wall == 1.0, "ring 3…6 m needs the ray (the kiosk covers), < 3 m ignores it (heard through the pavilion)")
	# Рост ×3: ближе 3 м спиной — провал за ~0,67 с; в 4,5 м — за ~2 с.
	await _place_player(p, 0.0)
	_aim(p + Vector3(0, 0, -2.0), p + Vector3(0, 0, -12.0))
	_reset_track()
	var before := detected_signals + _kiosk_detections
	var t_near: int = await _wait_until(func(): return world.is_stealth_failing(), 300)
	print("INFO: fix6 2 m behind the sensor: fail after %.2f s" % (t_near / 60.0))
	check(t_near >= 0 and t_near <= 60, "2 m behind the sensor: fail within 1 s (%.2f s; rise ×3 → 0.67 s)" % (t_near / 60.0))
	await _wait_until(func(): return not world.is_stealth_failing(), 400)
	await drv.frames(250)
	await _place_player(p, 0.0)   # после провала — на чекпоинте
	_aim(p + Vector3(0, 0, -4.5), p + Vector3(0, 0, -14.5))
	var t_ring: int = await _wait_until(func(): return world.is_stealth_failing(), 400)
	print("INFO: fix6 4.5 m behind the sensor: fail after %.2f s" % (t_ring / 60.0))
	check(t_ring >= 100 and t_ring <= 160, "4.5 m behind the sensor: fail after ≈2 s (%.2f s; rise ×1)" % (t_ring / 60.0))
	await _wait_until(func(): return not world.is_stealth_failing(), 400)
	await drv.frames(250)
	# Укрытия EXT-02: множитель заметности остаётся. Коробка стоя ≤ 1,5 м — 0,5 (×3), в 2 м — 0 (таблица 5.3, CLOSE_RADIUS
	# 1,5 м), на ходу — 0,75; сугроб — 0 вплотную.
	var player: Node3D = world.player
	await _place_player(p, 0.0)
	var hide := []
	for row in [[&"box", 1.2], [&"box", 2.0], [&"snowdrift", 1.2], [&"barrel", 1.2], [&"barrel", 2.0]]:
		player.force_hide_mode(row[0])
		await drv.frames(3)
		_aim(p + Vector3(0, 0, -row[1]), p + Vector3(0, 0, -row[1] - 10.0))
		var v := sensor.poll()
		hide.append([row[0], row[1], v, sensor.near_rise_factor])
	player.force_hide_mode(&"none")
	await drv.frames(3)
	print("INFO: fix6 hide modes at the sensor (standing, facing away): [mode, m, visibility, factor] %s" % [hide])
	check(is_equal_approx(hide[0][2], 0.5) and hide[0][3] == 3.0, "box standing 1.2 m behind the sensor: visibility 0.5 (table), rise ×3")
	check(hide[1][2] == 0.0, "box standing 2 m behind the sensor: visibility 0 (table: ≥ 1.5 m — 0)")
	check(hide[2][2] == 0.0, "snowdrift 1.2 m: visibility 0")
	check(is_equal_approx(hide[3][2], 0.5) and hide[4][2] == 0.0, "barrel standing 1.2 m: 0.5, 2 m: 0")
	sensor.enabled = false
	sensor.range_m = 9.0
	sensor.fov_deg = 75.0
	await drv.frames(30)

	# --- К парковке, круг близости на земле, три конуса с парковки ---
	m.interact(&"babka")
	m.accept()
	world.car.reset_to(Vector3(22, 0, 32), -PI * 0.5)
	await drv.frames(5)
	world.enter_car()
	await drv.frames(10)
	var park: Vector3 = Layout.ROUTE_DRIVE[-1]
	var d: Vector3 = park - Layout.ROUTE_DRIVE[-2]
	world.car.reset_to(park, atan2(-d.x, -d.z))
	await drv.frames(10)
	check(m.state == &"BUY_BREAD" and world.exit_car(), "fix6: at the parking, BUY_BREAD, out of the car")
	await drv.frames(30)
	var exit_spot: Vector3 = world.player.global_position
	check(s1.poll() == 0.0 and s2.poll() == 0.0, "exit spot %s is not seen (%.1f m / %.1f m to the posts)" % [exit_spot, _flat_d(exit_spot, Layout.OFFICER_POST), _flat_d(exit_spot, Layout.OFFICER2_POST)])
	check(_cone_visible(s1) and s1.near_circle_visible() and s1.near_color.a < s1.cone_color.a, "from the parking the officer cone and the paler 6 m circle are drawn (alpha %.2f < %.2f)" % [s1.near_color.a, s1.cone_color.a])
	# С места выхода из машины (машина стоит на (60; −54), сам этот пункт занят кузовом) — фигура и три сектора.
	for f in 3:
		await _sync_officer(f)
		await drv.frames(20)
		await _place_player(exit_spot, _yaw_to(exit_spot, Layout.OFFICER_POST))
		await drv.frames(10)
		await _shot("k_parking_cone_facing%d" % f)
	var c2 := Vector3(57.5, 0, -73.0)   # к югу от окна: виден круг второго поста и сектор
	await _place_player(c2, _yaw_to(c2, Layout.OFFICER2_POST))
	await drv.frames(20)
	check(s2.near_circle_visible(), "Officer2 near circle drawn when Ilyusha is near")
	await _shot("near_circle_officer2")
	var c1 := Vector3(55.0, 0, -62.0)
	await _place_player(c1, _yaw_to(c1, Layout.OFFICER_POST))
	await drv.frames(20)
	await _shot("near_circle_officer")
	if "--fix6-frames" in OS.get_cmdline_user_args():   # только кадры части 14
		drv.on_frame = Callable()
		return

	# --- Подойти поговорить (этап 5): от окна к полицейскому, E — как только появилась подсказка ---
	for attempt in 2:
		await _place_player(_vendor_stand(), 0.0)
		await drv.frames(260)
		await _sync_officer(0)
		_reset_track()
		var before_t := _kiosk_detections
		var talk: Array = await _walk_and_talk(TALK_SPOT)
		var opened: bool = talk[0]
		var at_open: float = talk[1]
		var dist_open: float = talk[2]
		print("INFO: fix6 walk up to the officer to talk (#%d): dialog %s at %.2f m, suspicion at E %.2f, fail %s" % [attempt, opened, dist_open, at_open, _kiosk_detections > before_t])
		check(opened and _kiosk_detections == before_t, "fix6: walking up to the officer from the window and pressing E at the prompt opens the dialog before a fail (suspicion %.2f)" % at_open)
		for i in 8:
			if not world.quest_flow.is_dialog_open():
				break
			await _press_any([QuestLines.BUTTON_OFFICER_LEAVE, "ДАЛЬШЕ"])
		await drv.walk_to(_vendor_stand())
		await drv.frames(300)
		if world.is_stealth_failing():
			await _wait_until(func(): return not world.is_stealth_failing(), 400)

	# --- Окно 30 с: ни одного кадра видимости ---
	await _place_player(_vendor_stand(), PI * 0.5)
	await drv.frames(30)
	var seen_frames := 0
	for i in 1800:
		await drv.frames(1)
		for sn in get_nodes_in_group(&"detection_sensors"):
			if sn.get("enabled") != false and sn.visibility() > 0.0:
				seen_frames += 1
	check(seen_frames == 0 and world.stealth.suspicion == 0.0, "30 s at the window: 0 frames seen by any sensor (%d)" % seen_frames)
	await _place_player(Layout.STEALTH_CHECKPOINT, 0.0)
	var chk := []
	for sn in get_nodes_in_group(&"detection_sensors"):
		if sn.get("enabled") != false and sn.poll() > 0.0:
			chk.append(sn.get_parent().name)
	check(chk.is_empty(), "checkpoint %s outside every sensor (%s)" % [Layout.STEALTH_CHECKPOINT, chk])

	# --- Длина цикла первого поста ---
	await _sync_officer(0)
	var f_a := _f6_frame
	await _sync_officer(0)
	var cycle_f := _f6_frame - f_a
	print("INFO: fix6 Officer cycle %.1f s" % (cycle_f / 60.0))

	# --- Шесть маршрутов шестой приёмки без ожидания, 12 фаз ---
	var v := _vendor_stand()
	var six := {
		"dij_south": [exit_spot, [Vector3(74.25, 0, -58.0), Vector3(74.25, 0, -68.75), Vector3(74.0, 0, -71.75), Vector3(73.25, 0, -74.75), Vector3(71.25, 0, -77.75), Vector3(70.0, 0, -80.75), Vector3(68.5, 0, -82.25), Vector3(67.0, 0, -83.5), Vector3(65.5, 0, -84.25), Vector3(63.0, 0, -85.5), Vector3(61.5, 0, -85.5), Vector3(60.0, 0, -84.25), Vector3(60.0, 0, -81.25), Vector3(60.0, 0, -78.25), v]],
		"dij_east": [Vector3(77.8, 0, -81.75), [Vector3(74.25, 0, -81.75), Vector3(71.25, 0, -81.75), Vector3(69.75, 0, -82.5), Vector3(68.25, 0, -83.0), Vector3(66.75, 0, -83.75), Vector3(65.25, 0, -84.25), Vector3(64.25, 0, -85.25), Vector3(62.75, 0, -85.5), Vector3(61.25, 0, -85.5), Vector3(60.0, 0, -84.0), Vector3(60.0, 0, -81.0), Vector3(60.0, 0, -78.0), v]],
		"dij_north": [Vector3(70.25, 0, -100.0), [Vector3(70.25, 0, -98.5), Vector3(65.75, 0, -94.0), Vector3(63.0, 0, -91.0), Vector3(61.5, 0, -89.5), Vector3(60.0, 0, -88.0), Vector3(60.0, 0, -86.5), Vector3(59.5, 0, -85.0), Vector3(59.5, 0, -79.0), v]],
		"N1": [Vector3(70, 0, -99), [Vector3(60.25, 0, -95), Vector3(60.25, 0, -83), v]],
		"N2": [Vector3(48, 0, -99), [Vector3(57.8, 0, -95), Vector3(57.8, 0, -83), v]],
		"dij_west": [Vector3(45.0, 0, -95.0), [Vector3(48.0, 0, -97.75), Vector3(49.5, 0, -97.75), Vector3(52.5, 0, -95.0), Vector3(55.25, 0, -93.0), Vector3(57.25, 0, -90.5), Vector3(58.0, 0, -89.0), Vector3(57.75, 0, -86.0), Vector3(58.5, 0, -84.5), Vector3(58.5, 0, -81.5), Vector3(59.0, 0, -78.5), v]],
	}
	var table := []
	for route_name in six:
		var r := await _f6_phases(route_name, six[route_name][0], six[route_name][1], cycle_f)
		table.append("%s %d/12" % [route_name, r["clean"]])
		check(r["fails"] >= 9 and r["clean"] < 12, "%s without a wait: fail in ≥ 9 of 12 phases (fails %d, clean %d)" % [route_name, r["fails"], r["clean"]])
	print("INFO: fix6 sixth acceptance routes, clean phases: %s" % [table])

	# --- «В лоб», диагонали, SNEAK_WEST без ожидания: 12 фаз, число чистых ---
	var others := {
		"direct": [exit_spot, [DIRECT_FROM, Vector3(DIRECT_FROM.x, 0, -73.0), v], 4],
		"diag_long": [exit_spot, DIAG_LONG + [v], 4],
		"diag_short": [exit_spot, DIAG_SHORT + [v], 4],
		"sneak_west_nowait": [exit_spot, Layout.SNEAK_WEST[0] + Layout.SNEAK_WEST[2] + Layout.SNEAK_WEST[4], 6],
		# SNEAK_EAST — одно ожидание (угол [1] или [2] первого): без него открыт ~2/3 цикла; в лог, не норма.
		"sneak_east_nowait": [exit_spot, Layout.SNEAK_EAST[0] + Layout.SNEAK_EAST[2], 12],
	}
	table = []
	for route_name in others:
		var r := await _f6_phases(route_name, others[route_name][0], others[route_name][1], cycle_f)
		table.append("%s %d/12" % [route_name, r["clean"]])
		check(r["clean"] <= others[route_name][2], "%s without a wait: clean in ≤ %d of 12 phases (%d)" % [route_name, others[route_name][2], r["clean"]])
	print("INFO: fix6 other routes, clean phases: %s" % [table])

	# --- Честные пути с ожиданием — проход ---
	for route_name in ["SNEAK_EAST", "SNEAK_WEST"]:
		var route: Array = Layout.SNEAK_EAST if route_name == "SNEAK_EAST" else Layout.SNEAK_WEST
		for attempt in 2:
			await _place_player(exit_spot, 0.0)
			await drv.frames(260)
			var before_h := _kiosk_detections
			_reset_track()
			var ok: bool = await drv.sneak_route(route)
			print("INFO: fix6 honest %s #%d: %s, %.1f s, max suspicion %.2f (%s)" % [route_name, attempt, ok, _track_frames / 60.0, _track_max, drv.last_error])
			check(ok and _kiosk_detections == before_h and not world.is_stealth_failing() and _near2(world.player.global_position, _vendor_stand(), 0.6), "honest %s #%d with the waits: window without a fail (%.1f s, max %.2f)" % [route_name, attempt, _track_frames / 60.0, _track_max])
			check(_track_frames <= 3600, "fix7: honest %s #%d with the waits ≤ 60 s (%.1f s)" % [route_name, attempt, _track_frames / 60.0])

	# --- fix7: подходы с востока без ожидания — 12 фаз цикла каждого поста ---
	var cycle2_f: int = await _f7_cycle2(3)
	print("INFO: fix7 Officer2 mean cycle %.1f s (3 cycles)" % (cycle2_f / 60.0))
	var east := {}
	for z in [-76.0, -77.0, -78.0, -80.0]:   # с дороги B (x = 75,3 — вне дальности обоих постов) на запад вдоль z
		east["E_z%d" % int(-z)] = [Vector3(75.3, 0, -96), [Vector3(75.3, 0, z), Vector3(61.0, 0, z), v]]
	for x in [64.0, 65.0, 66.0, 67.0, 68.0]:   # с улицы C, 6–10 м восточнее второго поста
		east["C_e%d" % int(x)] = [Vector3(x, 0, -99), [Vector3(x, 0, -80), Vector3(61.0, 0, -78), v]]
	table = []
	var total := [0, 0]
	for route_name in east:
		var c := []
		for sync in [1, 2]:
			var r := await _f6_phases("%s sync O%d" % [route_name, sync], east[route_name][0], east[route_name][1], cycle_f if sync == 1 else cycle2_f, 12, sync)
			c.append(r["clean"])
			total[sync - 1] += r["clean"]
		table.append("%s %d+%d/24" % [route_name, c[0], c[1]])
		check(c[0] < 12 and c[1] < 12, "fix7 %s without a wait: not clean in all 12 phases of either post (Officer %d/12, Officer2 %d/12)" % [route_name, c[0], c[1]])
	print("INFO: fix7 approaches from the east, clean phases (Officer + Officer2 of 24): %s; total %d + %d of %d" % [table, total[0], total[1], east.size() * 24])
	drv.on_frame = Callable()

func _sync_npc(o: Node3D, index: int) -> void:
	var n := 0
	while o.facing_index() == index and n < 1200:
		await drv.frames(1)
		n += 1
	while (o.facing_index() != index or o.is_turning()) and n < 2400:
		await drv.frames(1)
		n += 1

## Угол камеры/Илюши (yaw) из from на to.
func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)

## Ждать, пока полицейский только что встал в угол index (после разворота), как в повторной приёмке.
func _sync_officer(index: int) -> void:
	var o: Node3D = world.get_node("LevelGeometry/Patrols").officer
	var n := 0
	while o.facing_index() == index and n < 1200:
		await drv.frames(1)
		n += 1
	while (o.facing_index() != index or o.is_turning()) and n < 2400:
		await drv.frames(1)
		n += 1

## Отрезок пост → q в плоскости XZ проходит через коробку киоска (Layout SOLIDS «Kiosk»), fix5.
func _kiosk_shades(post: Vector3, q: Vector3) -> bool:
	var k := _solid("Kiosk")
	var c: Vector2 = k[0]
	var half := Vector2(k[1].x, k[1].z) * 0.5
	var a := Vector2(post.x, post.z)
	var b := Vector2(q.x, q.z)
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		if absf(p.x - c.x) < half.x and absf(p.y - c.y) < half.y:
			return true
	return false

## Точка q в секторе (yaw, fov, дальность) от поста — без луча.
func _in_cone(post: Vector3, yaw: float, q: Vector3, fov: float, rng: float) -> bool:
	var to := Vector2(q.x - post.x, q.z - post.z)
	if to.length() > rng:
		return false
	return rad_to_deg(absf(Vector2(-sin(yaw), -cos(yaw)).angle_to(to))) <= fov * 0.5

func _track() -> void:
	_track_frames += 1
	if world and is_instance_valid(world):
		_track_max = maxf(_track_max, world.stealth.suspicion)
		if _track_fail < 0 and world.is_stealth_failing():
			_track_fail = _track_frames
	if is_instance_valid(_watch_sensor) and _watch_sensor.visibility() > 0.0:
		_watch_frames += 1

func _reset_track() -> void:
	_track_max = 0.0
	_track_frames = 0
	_track_fail = -1

## Идти к точке, пока не начнётся экран провала (или не дойдёт / не кончатся кадры).
func _walk_until_fail(target: Vector3, max_frames: int) -> void:
	for i in max_frames:
		if world.is_stealth_failing():
			break
		var to := target - world.player.global_position
		to.y = 0.0
		if to.length() < 0.4:
			break
		drv._walk_axes(to.normalized())
		await drv.frames(1)
	drv.release_all()

func _walk_path_until_fail(points: Array, max_frames: int) -> void:
	for p in points:
		if world.is_stealth_failing() or max_frames <= 0:
			break
		var start := _track_frames
		await _walk_until_fail(p, max_frames)
		max_frames -= _track_frames - start

func _cone_visible(s: DetectionSensor) -> bool:
	var cone := s.get_node_or_null("VisionCone")
	return cone != null and (cone as Node3D).visible

func _van_clear(van: Node3D) -> bool:
	var box := BoxShape3D.new()
	box.size = CityVan.SIZE - Vector3(0.05, 0.4, 0.05)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	query.exclude = [van.get_rid()]
	query.transform = Transform3D(van.global_basis, van.global_position + Vector3.UP * (CityVan.SIZE.y * 0.5 + 0.1))
	var hits := world.get_world_3d().direct_space_state.intersect_shape(query, 4)
	for h in hits:
		print("INFO: van overlaps ", h["collider"].name)
	return hits.is_empty()

func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# =====================================================================================
# Помощники
# =====================================================================================

## LIFE-01: жители (по цепочкам целей) — движущиеся тела на слое Car, как в STUCK: в стелс они не входят (не в
## detection_sensors, не укрывают — C7), к постам ближе 8 м и на площадку киоска не ходят (life01_test, данные), но их
## шаги сдвигали бы тайминг сценариев и фазы второго полицейского (счёт «чистых фаз» прыгал 4 → 7 из 12 без связи
## со стелсом). Свои наборы — RESIDENTS и LIFE01.
func _free_residents() -> void:
	var residents := world.get_node_or_null("LevelGeometry/Residents")
	if residents:
		residents.free()

func _place_player(p: Vector3, yaw: float) -> void:
	world.player.place(p, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await drv.frames(2)

## Сенсор в точку at, «лицом» (−Z) на look_at.
func _aim(at: Vector3, look_at: Vector3) -> void:
	sensor.global_position = Vector3(at.x, 0.0, at.z)
	var d := look_at - at
	sensor.rotation.y = atan2(-d.x, -d.z)

func _vis() -> float:
	return sensor.poll()

func _solid(name: String) -> Array:
	for s in Layout.all_solids():
		if s[0] == name:
			return [s[2], s[3]]
	push_error("no solid " + name)
	return [Vector2.ZERO, Vector3.ZERO]

## Ближайшая к точке тропинка: плоскость PlaneMesh на y = 0,024 прямо в LevelGeometry, без коллизии
## (дубли имени «Trail» Godot переименовывает в @MeshInstance3D@N, поэтому ищем по признакам, не по имени).
func _trail_near(p: Vector3) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_d := INF
	for mesh in world.get_node("LevelGeometry").get_children():
		if not (mesh is MeshInstance3D) or not (mesh.mesh is PlaneMesh) or absf(mesh.position.y - 0.024) > 0.002:
			continue
		if mesh.find_children("*", "CollisionObject3D", true, false).size() > 0:
			continue
		var d: float = Vector2(mesh.global_position.x - p.x, mesh.global_position.z - p.z).length()
		if d < best_d:
			best = mesh
			best_d = d
	return best

func _free(p: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.8)
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Ждать условие не дольше max_frames; возвращает номер кадра или −1.
func _wait_until(condition: Callable, max_frames: int) -> int:
	for i in max_frames:
		if condition.call():
			return i
		await drv.frames(1)
	return -1

## Нажать первую видимую кнопку из списка (цепочки реплик). false — ни одной нет.
func _press_any(texts: Array) -> bool:
	for text in texts:
		if _visible_button(text):
			var ok: bool = await drv.press_button(text, &"ui_left")
			if not ok:
				ok = await drv.press_button(text, &"ui_right")
			await drv.frames(3)
			return ok
	return false

func _babka_stand() -> Vector3:
	return Layout.BABKA + Vector3(0.6, 0.0, -2.0)

func _vendor_stand() -> Vector3:
	return Layout.VENDOR_WINDOW + Vector3(0.6, 0.0, 0.0)

func _car_stand() -> Vector3:
	var best := Vector3.INF
	for offset in [Vector3(-2.2, 0, 0), Vector3(2.2, 0, 0)]:
		var p: Vector3 = world.car.global_transform * offset
		p.y = 0.0
		if best == Vector3.INF or p.distance_to(world.player.global_position) < best.distance_to(world.player.global_position):
			best = p
	return best

func _near2(a: Vector3, b: Vector3, tol: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= tol

func _visible_texts() -> Array:
	var out := []
	for n in ["GameHUD", "QuestFlow", "Babka", "Vendor"]:
		if not world.has_node(n):
			continue
		for child in world.get_node(n).find_children("*", "", true, false):
			if (child is Label or child is Button) and (child as CanvasItem).is_visible_in_tree():
				out.append(child.text)
			elif child is Label3D and (child as Node3D).is_visible_in_tree():
				out.append(child.text)
	return out

func _hud_has(text: String) -> bool:
	return _visible_texts().has(text)

func _visible_button(text: String) -> Button:
	for child in world.find_children("*", "Button", true, false):
		if child.text == text and child.is_visible_in_tree():
			return child
	return null

func _shot(label: String) -> void:
	if not capture:
		return
	await drv.frames(20)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_out, label])
	image.save_png(path)
	print("SHOT ", path, " ", image.get_size())

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish(code := -1) -> void:
	print("STEALTH: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

extends SceneTree
## COINS-01: монеты — 35 рублей до батона (решение владельца 29.10; стартовых денег нет).
## Раскладка Layout: ≥ 60 точек, ни одной внутри коробок Layout.all_solids() и на полосах кольца Layout.ring_lane(),
## не у постов и чекпоинта; 35 набираются по ROUTE_WALK (пешком, 0,9 м) и по двору + ROUTE_DRIVE (машиной, 1,6 м) без
## крюка — и расчётом, и в мире проходом по маршруту. MissionDirector: START_MONEY 0, add_money + money_changed, строка
## денежная подсказка в objective()["coins_task"] только после принятия поручения; 34 → отказ продавщицы «Не хватает: ещё 1 ₽» и
## выключенная «КУПИТЬ ХЛЕБ», 35 → покупка. Мир: подбор пешком (0,9 м), магнит (1,5 м), на машине (1,6 м от центра),
## один счётчик HUD «N / 35» с пульсом после принятия, до него кошелёк, звон с чередованием высоты, spawn_burst (в полёте не подбирается),
## респавн на чекпоинте монеты не возвращает, reset() — возвращает.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/coins_test.gd
## Кадры: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/coins_test.gd -- --capture
##   → builds/screenshots/COINS-01/

const Layout = preload("res://game/world/layout.gd")
const CoinsScript = preload("res://game/world/coins.gd")
const CoinLines = preload("res://game/mission/coin_lines.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const OUT := "res://builds/screenshots/COINS-01"

const SOLID_PAD := 0.6     # м: от края коробки до центра монеты
const LANE_MIN := 2.5      # м: до оси полосы кольца (кузов троллейбуса 1,25 от оси)
const POST_MIN := 2.0
const POSTS := ["OFFICER_POST", "OFFICER_POST_AFTER", "OFFICER2_POST", "STEALTH_CHECKPOINT", "ACCOUNT_OFFICER"]

var failures: Array[String] = []
var checks := 0
var main: Node
var drv
var world: DemoWorld
var coins: Node
var capture := false

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: coins test exceeded 900 simulated seconds")
		_finish(2))
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_part_layout()
	_part_route_math()
	_part_director()
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	if not await _fresh_world():
		_finish()
		return
	await _part_start_hud()
	await _part_foot_and_magnet()
	await _part_car()
	await _part_sound()
	await _part_burst()
	await _part_respawn_and_reset()
	await _part_vendor()
	await _part_route_walk_world()
	await _part_route_drive_world()
	_finish()

func _fresh_world() -> bool:
	main.start_game()
	await drv.frames(10)
	world = main.world
	coins = world.get_node_or_null("LevelGeometry/Coins") if world else null
	if not check(world != null and coins != null, "world and LevelGeometry/Coins are up"):
		return false
	# Наблюдатели EXT-01 не мешают проверкам денег: их сенсоры выключены на время прогона.
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	return true

# =====================================================================================
# 1. Раскладка: точки вне коробок, полос, постов
# =====================================================================================

func _part_layout() -> void:
	var pts := Layout.COIN_POINTS
	check(pts.size() >= 60, "layout: ≥ 60 coins (%d)" % pts.size())
	# POLISH-03 B: монеты на крышах («ракушки») — на высоте крыши, не внутри коробки; с земли не достать (REACH_HEIGHT).
	var roof := pts.filter(func(p: Vector3) -> bool: return p.y > 0.0)
	check(roof.size() == 3 and roof.all(func(p: Vector3) -> bool: return p.y > CoinsScript.REACH_HEIGHT), "layout: 3 roof coins above REACH_HEIGHT %.1f m (%s)" % [CoinsScript.REACH_HEIGHT, roof])
	var direct := 0
	for g in Layout.COIN_DIRECT_GROUPS:
		direct += Layout.COIN_GROUPS[g][1]
	check(direct >= 25 and direct < MissionDirector.BREAD_PRICE, "layout: the direct route has %d coins (< 35 — the rest is a hunt)" % direct)
	var lanes := [Layout.ring_lane(), Layout.ring_lane(6.0, 6, true)]
	var in_solid := []
	var on_lane := []
	var near_post := []
	var outside := []
	var min_lane := INF
	for i in pts.size():
		var p: Vector3 = pts[i]
		if not Layout.BOUNDS.has_point(Vector2(p.x, p.z)):
			outside.append(i)
		for s in Layout.all_solids():
			var c: Vector2 = s[2]
			var size: Vector3 = s[3]
			if p.y < size.y and absf(p.x - c.x) < size.x * 0.5 + SOLID_PAD and absf(p.z - c.y) < size.z * 0.5 + SOLID_PAD:
				in_solid.append("%d %s@%s" % [i, s[0], c])
		for lane in lanes:
			var d := _polyline_distance(p, lane, true)
			min_lane = minf(min_lane, d)
			if d < LANE_MIN:
				on_lane.append("%d (%.2f m)" % [i, d])
		for k in POSTS:
			var post: Vector3 = Layout.new().get(k)
			if Vector2(p.x - post.x, p.z - post.z).length() < POST_MIN:
				near_post.append("%d %s" % [i, k])
	check(in_solid.is_empty(), "layout: no coin inside Layout.all_solids() boxes (+%.1f m) %s" % [SOLID_PAD, in_solid])
	check(on_lane.is_empty(), "layout: no coin on ring lanes (≥ %.1f m from both lane axes; min %.2f) %s" % [LANE_MIN, min_lane, on_lane])
	check(near_post.is_empty(), "layout: no coin within %.0f m of posts / checkpoint %s" % [POST_MIN, near_post])
	check(outside.is_empty(), "layout: all coins inside BOUNDS %s" % [outside])
	var covered := 0
	for g in Layout.COIN_GROUPS:
		covered += Layout.COIN_GROUPS[g][1]
	check(covered == pts.size(), "layout: groups cover all %d points (%d)" % [pts.size(), covered])
	var dup := []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if pts[i].distance_to(pts[j]) < 1.2:
				dup.append([i, j])
	check(dup.is_empty(), "layout: coins at least 1.2 m apart %s" % [dup])
	var road := 0
	for p in pts:
		if Layout.ROUTE_DRIVE.size() > 0 and _polyline_distance(p, Layout.ROUTE_DRIVE, false) <= CoinsScript.PICKUP_CAR:
			road += 1
	check(road >= 10, "layout: coins on the road for the car (%d)" % road)

# =====================================================================================
# 2. Расчёт: 35 по маршруту без крюка
# =====================================================================================

func _part_route_math() -> void:
	# POLISH-03 B: прямой путь не набирает 35 — нужна вылазка или охота (критик 30.10: «35 ₽ набираются сами»).
	var walk := _picked(Layout.ROUTE_WALK, CoinsScript.PICKUP_FOOT)
	check(walk.size() >= 15 and walk.size() < MissionDirector.BREAD_PRICE, "route: ROUTE_WALK at 0.9 m picks %d — 15…34, the walker hunts for the rest" % walk.size())
	var yard: Array = [Layout.SPAWN, Layout.BABKA + Vector3(0, 0, -2.2), Layout.CAR_SPAWN + Vector3(1.7, 0, 0)]
	var foot := _picked(yard, CoinsScript.PICKUP_FOOT)
	# От парковки к окну пешком честным путём SNEAK_EAST — так покупатель доходит до продавщицы.
	var window: Array = [Layout.ROUTE_DRIVE[-1]] + Layout.SNEAK_EAST[0] + Layout.SNEAK_EAST[2]
	for i in _picked(window, CoinsScript.PICKUP_FOOT):
		if not foot.has(i):
			foot.append(i)
	var car := _picked(Layout.ROUTE_DRIVE, CoinsScript.PICKUP_CAR)
	var both := foot.duplicate()
	for i in car:
		if not both.has(i):
			both.append(i)
	check(both.size() >= 18 and both.size() <= 27, "route: yard + ROUTE_DRIVE + walk to the window picks %d — 18…27, no 35 without a detour" % both.size())
	var hunt := foot.duplicate()
	for i in _picked(Layout.ROUTE_DRIVE_HUNT, CoinsScript.PICKUP_CAR):
		if not hunt.has(i):
			hunt.append(i)
	check(hunt.size() >= MissionDirector.BREAD_PRICE + 2, "route: yard + ROUTE_DRIVE_HUNT (one detour behind the yard garages) + walk to the window picks %d ≥ 37" % hunt.size())
	var all := Layout.COIN_POINTS.size()
	check(all - walk.size() >= 30 and all - both.size() >= 30, "route: most coins are off the direct routes (%d / %d off)" % [all - walk.size(), all - both.size()])

func _picked(path: Array, radius: float) -> Array:
	var out := []
	for i in Layout.COIN_POINTS.size():
		if _polyline_distance(Layout.COIN_POINTS[i], path, false) <= radius:
			out.append(i)
	return out

# =====================================================================================
# 3. MissionDirector: деньги, строка задачи, покупка
# =====================================================================================

func _part_director() -> void:
	var d := MissionDirector.new()
	var log := []
	d.money_changed.connect(func(m, delta): log.append([m, delta]))
	check(MissionDirector.START_MONEY == 0 and d.money == 0, "director: START_MONEY 0, no money at start")
	check(d.objective()["task"] == "Подойди к Бабке" and d.objective()["coins_task"] == "", "director: before accepting, no future bread money goal")
	d.add_money(0)
	d.add_money(-3)
	check(d.money == 0 and log.is_empty(), "director: add_money(≤ 0) changes nothing, no signal")
	d.add_money(1)
	check(d.money == 1 and log == [[1, 1]], "director: add_money(1) → 1 and money_changed(1, 1) (%s)" % [log])
	d.add_money(33)
	check(d.money == 34 and d.money_missing() == 1 and d.coins_task() == "", "director: collecting 34 before the offer does not reveal a future goal")
	d.interact(&"babka")
	check(d.coins_task() == "", "director: offered but unaccepted quest has no money goal")
	d.decline()
	check(d.coins_task() == "", "director: declining keeps the future goal hidden")
	d.interact(&"babka")
	d.accept()
	var earning := d.coins_task().to_lower()
	check(earning.contains("монет") and earning.contains("дрон") and (earning.contains("хлам") or earning.contains("предмет")), "director: accepting explains all three earning sources")
	check(not earning.contains("34") and not earning.contains("35"), "director: earning sources do not duplicate the money counter")
	d.notify_entered_car()
	d.notify_arrived_kiosk()
	check(d.state == MissionDirector.BUY_BREAD and not d.can_buy_bread() and not d.buy_bread(), "director: 34 at the kiosk → no purchase")
	check(d.state == MissionDirector.BUY_BREAD and not d.has_bread and d.money == 34, "director: refused purchase changes nothing")
	check(d.objective()["task"] == "Поговори с продавщицей" and d.objective()["coins_task"] != "", "director: BUY_BREAD task kept, coins line still shown")
	d.add_money(1)
	check(d.objective()["coins_task"] == "", "director: 35 → coins line gone")
	log.clear()
	check(d.buy_bread() and d.has_bread and d.money == 0, "director: 35 → purchase, money 0")
	check(log == [[0, -35]], "director: purchase emits money_changed(0, −35) (%s)" % [log])
	d.add_money(5)
	check(d.objective()["coins_task"] == "", "director: no coins line after the purchase even with money")
	log.clear()
	d.reset()
	check(d.money == 0 and log == [[0, -5]], "director: reset → money 0, one money_changed (%s)" % [log])
	check(CoinLines.vendor_short(12) == CoinLines.VENDOR_SHORT % 12 and CoinLines.vendor_short(12).contains("12"), "lines: vendor refusal «%s»" % CoinLines.vendor_short(12))
	d.free()

# =====================================================================================
# 4. Мир: старт, HUD
# =====================================================================================

func _part_start_hud() -> void:
	var hud := world.get_node("GameHUD")
	check(coins.layout_count() == Layout.COIN_POINTS.size() and coins.remaining() == Layout.COIN_POINTS.size(), "world: all %d coins in place (%d)" % [Layout.COIN_POINTS.size(), coins.remaining()])
	check(world.mission.money == 0, "world: no money at start")
	var mm: MultiMesh = coins.multimesh_instance.multimesh
	check(mm.instance_count >= Layout.COIN_POINTS.size() and coins.multimesh_instance.material_override is StandardMaterial3D, "world: coins drawn by one MultiMesh (%d instances)" % mm.instance_count)
	var no_bodies := coins.find_children("*", "CollisionObject3D", true, false).is_empty()
	check(no_bodies, "world: coins have no collision bodies")
	var aabb: AABB = mm.mesh.get_aabb()
	check(absf(aabb.size.x - CoinsScript.DIAMETER) < 0.01 and absf(aabb.size.y - CoinsScript.DIAMETER) < 0.01, "world: coin Ø 0.4 m (%s)" % aabb.size)
	var a: float = coins.instance_transform(0).basis.get_euler().y
	await drv.frames(10)
	var b: float = coins.instance_transform(0).basis.get_euler().y
	check(absf(wrapf(b - a, -PI, PI)) > 0.2, "world: coins spin (%.2f → %.2f rad)" % [a, b])
	await drv.frames(2)
	check(not hud.coins_row.visible, "HUD: no future money objective before Babka offers the quest")
	check(hud.task_label.text == "Подойди к Бабке", "HUD: task line unchanged ('%s')" % hud.task_label.text)
	check(hud.coin_counter.visible and hud.coin_counter_label.text == "0 ₽", "HUD: initial wallet «0 ₽» without future purchase target")
	var card_end: float = hud.card.position.x + hud.card.size.x
	check(hud.coin_counter.position.x >= card_end and hud.coin_counter.position.y < 60.0, "HUD: counter right of the task card (x %.0f ≥ %.0f)" % [hud.coin_counter.position.x, card_end])
	if capture:
		await _shot_at(Layout.SPAWN, Layout.SPAWN_YAW, "01_yard_coins")

# =====================================================================================
# 5. Подбор пешком и магнит
# =====================================================================================

func _part_foot_and_magnet() -> void:
	var hud := world.get_node("GameHUD")
	var log := []
	coins.collected.connect(func(p, total): log.append(total), CONNECT_ONE_SHOT)
	var i := _index(&"garages_yard", 3)   # (20; 95): соседи в 5 м
	var c: Vector3 = Layout.COIN_POINTS[i]
	world.player.place(c + Vector3(-1.9, 0, 0), 0.0)   # западнее: восточнее — стена гаражей
	await drv.frames(30)
	check(coins.is_available(i) and world.mission.money == 0, "foot: 1.9 m away — coin stays (outside magnet 1.5)")
	world.player.place(c + Vector3(-1.3, 0, 0), 0.0)
	await drv.frames(2)
	check(coins.is_available(i) and world.mission.money == 0, "foot: 1.3 m — not collected at once (pickup 0.9)")
	var moved := false
	for f in 40:
		await drv.frames(1)
		if coins.is_available(i):
			moved = moved or coins._pos[i].distance_to(c + Vector3.UP * CoinsScript.HOVER) > 0.05
	check(moved or not coins.is_available(i), "foot: magnet pulls the coin toward Ilyusha")
	check(not coins.is_available(i) and world.mission.money == 1 and coins.collected_count == 1, "foot: magnet coin collected without stepping in (money %d)" % world.mission.money)
	check(log == [1], "foot: collected(total 1) emitted once (%s)" % [log])
	await drv.frames(2)
	check(hud.coin_counter_label.text == "1 ₽" and not hud.coins_row.visible, "HUD: pre-quest pickup changes the wallet only")
	var j := _index(&"garages_yard", 4)
	world.player.place(Layout.COIN_POINTS[j] + Vector3(-0.6, 0, 0.3), 0.0)
	await drv.frames(2)
	check(not coins.is_available(j) and world.mission.money == 2, "foot: within 0.9 m — collected on the spot")
	await drv.frames(1)
	check(hud.coin_counter.scale.x > 1.05, "HUD: counter pulses on a pickup (scale %.2f)" % hud.coin_counter.scale.x)
	await drv.frames(30)
	check(is_equal_approx(hud.coin_counter.scale.x, 1.0), "HUD: pulse settles back to 1 (%.2f)" % hud.coin_counter.scale.x)
	# По высоте дальше REACH_HEIGHT — не подбирается (крыша, прыжок): Илюша над монетой на 3 м.
	var k := _index(&"garages_yard", 0)
	world.player.place(Layout.COIN_POINTS[k] + Vector3(0, 3.0, 0), 0.0)
	world.player.set_physics_process(false)
	await drv.frames(3)
	check(coins.is_available(k), "foot: 3 m above the coin — not collected")
	world.player.set_physics_process(true)
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await drv.frames(3)

# =====================================================================================
# 6. Подбор на машине
# =====================================================================================

func _part_car() -> void:
	var start := world.mission.money
	var car := world.car
	var i := _index(&"road_b", 1)   # (70; −12)
	var c: Vector3 = Layout.COIN_POINTS[i]
	car.reset_to(c + Vector3(0, 0, 3.0), 0.0)
	world.enter_car()
	await drv.frames(3)
	check(world.control_mode == &"in_car", "car: Ilyusha at the wheel")
	check(coins.is_available(i), "car: 3 m from the car centre — not collected yet")
	car.reset_to(c + Vector3(1.4, 0, 0.3), 0.0)
	await drv.frames(2)
	check(not coins.is_available(i) and world.mission.money == start + 1 and coins.collected_in_car == 1, "car: within 1.6 m of the car centre — collected in the car")
	# Проезд вдоль оси B: машина шагами по 0,5 м с z 26 до −38 собирает все монеты проезжей части.
	var row: Array = Layout.COIN_GROUPS[&"road_b"]
	var before := world.mission.money
	if capture:
		car.reset_to(Vector3(70, 0, 26), 0.0)
		world.camera_rig.yaw = 0.0
		world.camera_rig.snap()
	var z := 26.0
	var shot_done := false
	while z > -38.0:
		car.reset_to(Vector3(70, 0, z), 0.0)   # носом на север, по ходу
		await drv.frames(1)
		if capture and not shot_done and z < 12.6:
			shot_done = true
			await _shot("03_car_pickup")
		z -= 0.5
	await drv.frames(15)
	check(world.mission.money - before == row[1] - 1, "car: driving B axis collects the other %d road coins (%d)" % [row[1] - 1, world.mission.money - before])
	world.exit_car()
	await drv.frames(3)
	check(world.control_mode == &"on_foot", "car: out of the car")

# =====================================================================================
# 7. Звук
# =====================================================================================

func _part_sound() -> void:
	var sound := world.get_node("SoundDirector")
	check(sound.played.has("coin") and sound.played["coin"] == coins.collected_count, "sound: one chime per coin (%s / %d)" % [sound.played.get("coin"), coins.collected_count])
	check(sound.coin_player != null and sound.coin_player.stream != null and sound.coin_player.stream.resource_path.ends_with("coin_pickup.wav"), "sound: coin_pickup.wav synth")
	# Две монеты подряд — второй звон выше; после паузы — снова с первой высоты.
	var row: Array = Layout.COIN_GROUPS[&"street_a"]
	await drv.frames(60)
	world.player.place(Layout.COIN_POINTS[row[0]], 0.0)
	await drv.frames(2)
	var p1: float = sound.coin_pitch
	world.player.place(Layout.COIN_POINTS[row[0] + 1], 0.0)
	await drv.frames(2)
	var p2: float = sound.coin_pitch
	check(is_equal_approx(p1, 1.0) and p2 > p1, "sound: quick pickups go up in pitch (%.3f → %.3f)" % [p1, p2])
	await drv.frames(60)
	world.player.place(Layout.COIN_POINTS[row[0] + 2], 0.0)
	await drv.frames(2)
	check(is_equal_approx(sound.coin_pitch, 1.0), "sound: after a pause the pitch starts over (%.3f)" % sound.coin_pitch)

# =====================================================================================
# 8. Выброс монет (PUNCH-01)
# =====================================================================================

func _part_burst() -> void:
	var at := Vector3(10.0, 1.5, 60.0)   # двор, пустой проезд у гаражей
	world.player.place(at + Vector3(0, -1.5, 0), 0.0)
	await drv.frames(3)
	var money := world.mission.money
	var before: int = coins.remaining()
	var made: int = coins.spawn_burst(at, 5)
	check(made == 5 and coins.remaining() == before + 5, "burst: spawn_burst(…, 5) adds 5 coins (%d)" % made)
	await drv.frames(2)
	check(world.mission.money == money, "burst: airborne coins are not collected even over Ilyusha")
	world.player.place(at + Vector3(-12.0, -1.5, 0), 0.0)   # отойти: приземлившиеся рядом поймал бы магнит
	await drv.frames(90)
	var loose: Array = coins.active_positions().filter(func(p: Vector3) -> bool: return p.distance_to(at) < 6.0)
	check(loose.size() == 5, "burst: 5 coins landed around the drop point (%d)" % loose.size())
	var spread := 0.0
	for p in loose:
		spread = maxf(spread, Vector2(p.x - at.x, p.z - at.z).length())
		check(absf(p.y - CoinsScript.HOVER) < 0.01, "burst: landed coin hovers at %.2f m (%.2f)" % [CoinsScript.HOVER, p.y])
	check(spread > 0.8, "burst: coins scatter (%.2f m)" % spread)
	for p in loose:
		world.player.place(Vector3(p.x, 0, p.z), 0.0)
		await drv.frames(3)
	check(world.mission.money == money + 5, "burst: all 5 picked up (+%d)" % (world.mission.money - money))
	coins.spawn_burst(at, 3)
	world.player.place(Layout.SPAWN, 0.0)
	await drv.frames(int((CoinsScript.LOOSE_LIFETIME + 1.0) * Engine.physics_ticks_per_second))
	check(coins.active_positions().filter(func(p: Vector3) -> bool: return p.distance_to(at) < 6.0).is_empty(), "burst: untouched loose coins vanish after %.0f s" % CoinsScript.LOOSE_LIFETIME)
	# BREAK-02: выброс с проверкой места приземления и монеты, летящие к собирающему (сломано «Ладой»)
	var drop := Vector3(10.0, 1.0, 60.0)
	world.player.place(drop + Vector3(-12.0, -1.0, 0), 0.0)
	await drv.frames(2)
	coins.spawn_burst(drop, 4, func(p: Vector3) -> bool: return p.x > drop.x + 0.3)
	await drv.frames(60)
	var east: Array = coins.active_positions().filter(func(p: Vector3) -> bool: return p.distance_to(drop) < 6.0)
	check(east.size() == 4 and east.all(func(p: Vector3) -> bool: return p.x > drop.x + 0.3), "burst with allowed(): all 4 coins land on allowed spots (%d)" % east.size())
	coins.spawn_burst(drop, 2, func(_p: Vector3) -> bool: return false)
	await drv.frames(60)
	var still: Array = coins.active_positions().filter(func(p: Vector3) -> bool: return Vector2(p.x - drop.x, p.z - drop.z).length() < 0.05)
	check(still.size() == 2, "burst with no allowed spot: coins fall at the drop point (%d)" % still.size())
	money = world.mission.money
	for p in east + still:
		world.player.place(Vector3(p.x, 0, p.z), 0.0)
		await drv.frames(3)
	check(world.mission.money == money + 6, "burst with allowed(): all picked up by walking (+%d)" % (world.mission.money - money))
	world.player.place(drop + Vector3(-3.0, -1.0, 0), 0.0)
	await drv.frames(2)
	money = world.mission.money
	before = coins.remaining()
	coins.spawn_to_collector(drop, 3)
	await drv.frames(2)
	check(world.mission.money == money and coins.remaining() == before, "spawn_to_collector: coins pop out, not loose, not yet counted")
	await drv.frames(int((CoinsScript.SUCK_SECONDS + 3.0 * CoinsScript.SUCK_STAGGER + 0.1) * Engine.physics_ticks_per_second))
	check(world.mission.money == money + 3 and coins.remaining() == before, "spawn_to_collector: 3 coins fly to the collector and count by themselves (+%d)" % (world.mission.money - money))

# =====================================================================================
# 9. Респавн и reset()
# =====================================================================================

func _part_respawn_and_reset() -> void:
	var left: int = coins.remaining()
	var money := world.mission.money
	check(world.respawn_at_checkpoint(), "respawn: Ilyusha on the checkpoint")
	await drv.frames(5)
	check(coins.remaining() <= left and world.mission.money >= money, "respawn: collected coins stay collected, money kept (%d → %d)" % [left, coins.remaining()])
	check(not coins.is_available(_index(&"garages_yard", 3)), "respawn: a collected coin does not come back")
	world.player.place(Layout.SPAWN, 0.0)
	await drv.frames(2)
	coins.spawn_burst(Vector3(10, 1.5, 60), 4)
	coins.reset()
	await drv.frames(2)
	check(coins.remaining() == Layout.COIN_POINTS.size() and coins.collected_count == 0, "reset: all layout coins back, loose gone (%d)" % coins.remaining())

# =====================================================================================
# 10. Продавщица: 34 → отказ с подсказкой, 35 → покупка
# =====================================================================================

func _part_vendor() -> void:
	if not await _fresh_world():
		return
	var m := world.mission
	var flow := world.quest_flow
	m.interact(&"babka")
	m.accept()
	m.notify_entered_car()
	m.notify_arrived_kiosk()
	check(m.state == MissionDirector.BUY_BREAD, "vendor: mission at BUY_BREAD")
	m.add_money(34 - m.money)
	world.player.place(Layout.VENDOR_WINDOW + Vector3(0.6, 0, 0), -PI * 0.5)
	await drv.frames(4)
	await drv.interact()
	await drv.frames(3)
	check(flow.is_dialog_open(), "vendor: dialog opens with 34 ₽")
	for n in 10:
		if flow.dialog.is_last_line():
			break
		flow.dialog.finish_typing()
		flow.dialog.advance()
		await drv.frames(2)
	flow.dialog.finish_typing()
	check(flow.dialog.text_label.text == CoinLines.vendor_short(1) and flow.dialog.speaker_label.text == "ПРОДАВЩИЦА", "vendor: last line is the refusal «%s» ('%s')" % [CoinLines.vendor_short(1), flow.dialog.text_label.text])
	check(flow.dialog.buttons.has(&"buy") and flow.dialog.buttons[&"buy"].disabled, "vendor: КУПИТЬ ХЛЕБ disabled at 34")
	flow.dialog.buttons[&"buy"].pressed.emit()
	await drv.frames(2)
	check(m.state == MissionDirector.BUY_BREAD and not m.has_bread and m.money == 34, "vendor: forced press buys nothing at 34")
	if capture:
		await _shot("04_vendor_short")
	flow.dialog.buttons[&"leave"].pressed.emit()
	await drv.frames(3)
	# Последняя монета — из выброса у окна (PUNCH-01 по 5): ловит магнит, пока Илюша стоит.
	coins.spawn_burst(world.player.global_position + Vector3(0, 1.5, 0), 1)
	await drv.frames(90)
	for p in coins.active_positions():
		if p.distance_to(world.player.global_position) < 5.0 and not _is_layout_point(p):
			world.player.place(Vector3(p.x, 0, p.z), -PI * 0.5)
			await drv.frames(3)
	check(m.money >= 35, "vendor: one more coin from a burst → 35 ₽ (%d)" % m.money)
	var paid := m.money
	world.player.place(Layout.VENDOR_WINDOW + Vector3(0.6, 0, 0), -PI * 0.5)
	await drv.frames(4)
	await drv.interact()
	await drv.frames(3)
	flow.dialog.finish_typing()
	check(flow.is_dialog_open() and flow.dialog.line_count() == 1 and flow.dialog.text_label.text == QuestLines.VENDOR_AGAIN, "vendor: at 35 — the short line, no refusal ('%s')" % flow.dialog.text_label.text)
	check(not flow.dialog.buttons[&"buy"].disabled, "vendor: КУПИТЬ ХЛЕБ enabled at 35")
	flow.dialog.buttons[&"buy"].pressed.emit()
	await drv.frames(3)
	check(m.state == MissionDirector.RETURN_HOME and m.has_bread and m.money == paid - 35, "vendor: 35 → bread bought for 35 (left %d)" % m.money)
	var hud := world.get_node("GameHUD")
	await drv.frames(2)
	check(not hud.coins_row.visible and hud.coin_counter_label.text == "%d ₽" % m.money, "HUD: after the purchase no coins line, counter «0 ₽» ('%s')" % hud.coin_counter_label.text)

# =====================================================================================
# 11. В мире: проход по ROUTE_WALK и по двору + ROUTE_DRIVE
# =====================================================================================

func _part_route_walk_world() -> void:
	if not await _fresh_world():
		return
	var pts: Array = _sample(Layout.ROUTE_WALK, 0.3)
	for p in pts:
		world.player.place(p, 0.0)
		await drv.frames(1)
	await drv.frames(20)
	var m := world.mission.money
	check(m >= 15 and m < MissionDirector.BREAD_PRICE, "world route: walking ROUTE_WALK collects %d — 15…34, the rest is a hunt (POLISH-03 B)" % m)

func _part_route_drive_world() -> void:
	for hunt in [false, true]:
		if not await _fresh_world():
			return
		var yard: Array = _sample([Layout.SPAWN, Layout.BABKA + Vector3(0, 0, -2.2), Layout.CAR_SPAWN + Vector3(1.7, 0, 0)], 0.3)
		for p in yard:
			world.player.place(p, 0.0)
			await drv.frames(1)
		await drv.frames(10)
		var foot := world.mission.money
		world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
		world.enter_car()
		await drv.frames(2)
		var route: Array = _sample(Layout.ROUTE_DRIVE_HUNT if hunt else Layout.ROUTE_DRIVE, 0.5)
		for i in route.size():
			var p: Vector3 = route[i]
			var next: Vector3 = route[mini(i + 1, route.size() - 1)]
			var d := next - p
			world.car.reset_to(p, atan2(-d.x, -d.z) if d.length() > 0.01 else world.car.rotation.y)
			await drv.frames(1)
		await drv.frames(15)
		var in_car: int = coins.collected_in_car
		world.exit_car()
		await drv.frames(3)
		for p in _sample([Layout.ROUTE_DRIVE[-1]] + Layout.SNEAK_EAST[0] + Layout.SNEAK_EAST[2], 0.3):
			world.player.place(p, 0.0)
			await drv.frames(1)
		await drv.frames(15)
		var total := world.mission.money
		if hunt:
			check(total >= MissionDirector.BREAD_PRICE, "world route: yard on foot (%d) + ROUTE_DRIVE_HUNT by car + walk to the window collects %d ≥ 35" % [foot, total])
		else:
			check(total >= 18 and total < MissionDirector.BREAD_PRICE, "world route: yard on foot (%d) + direct ROUTE_DRIVE + walk to the window collects %d — 18…34, no 35 without a detour" % [foot, total])
			check(in_car >= 10, "world route: most of it from the car (%d)" % in_car)
	if capture:
		await _shot("02_counter_after_drive")

# --- помощники ---

func _is_layout_point(p: Vector3) -> bool:
	for q in Layout.COIN_POINTS:
		if Vector2(p.x - q.x, p.z - q.z).length() < 0.3:
			return true
	return false

func _index(group: StringName, k: int) -> int:
	return Layout.COIN_GROUPS[group][0] + k

func _sample(path: Array, step: float) -> Array:
	var out := []
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var n := maxi(1, int(ceil(a.distance_to(b) / step)))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(path[-1])
	return out

func _polyline_distance(p: Vector3, pts: Array, closed: bool) -> float:
	var best := INF
	var q := Vector3(p.x, 0, p.z)
	var n := pts.size()
	for i in (n if closed else n - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % n]
		var c := Geometry3D.get_closest_point_to_segment(q, Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z))
		best = minf(best, c.distance_to(q))
	return best

func _shot_at(at: Vector3, yaw: float, label: String) -> void:
	world.player.place(at, yaw)
	world.camera_rig.yaw = yaw
	world.camera_rig.snap()
	await drv.frames(20)
	await _shot(label)

func _shot(label: String) -> void:
	if not capture:
		return
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + "/" + label + ".png"))
	print("SHOT: ", label)

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish(code := -1) -> void:
	if drv:
		drv.release_all()
	print("COINS: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

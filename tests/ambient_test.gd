extends SceneTree
## CITY-01, часть A: живность и звуковой фон на настоящей сцене main.tscn (набор AMBIENT).
## Проверки: состав (6–10 ворон, собака, кошка, 5–8 мусоринок у контейнеров); коллизия только у собаки (слой Car,
## маска 0); слои фона играют, циклы зациклены, уровни (RMS файла + volume_db) не выше заданных и тише фона двора;
## сигнал машины — только при ожидании > 3 с и не чаще раза в 10 с на машину; вороны взлетают от транспорта, «Лады»
## и Илюши ближе 6 м и садятся обратно на свой насест; собака не выходит из своей площадки за гаражами (на дорогу и
## тротуары), лает раз в 20–40 с, отходит от Илюши и не толкает его; хлопок двери подъезда раз в 60–120 с; кошка
## шевелит хвостом; мусор не мешает идти. Детерминизм: фиксированные seed в Ambient и SoundDirector, --fixed-fps 60.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/ambient_test.gd

const Layout = preload("res://game/world/layout.gd")
const AmbientScript = preload("res://game/world/ambient.gd")

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var ambient: Node3D
var sound: Node
var traffic: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: ambient test exceeded 900 simulated seconds")
		_finish(2))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(10)
	world = main.world
	if not check(world != null, "DemoWorld exists"):
		_finish()
		return
	ambient = world.get_node_or_null("LevelGeometry/Ambient")
	sound = world.get_node("SoundDirector")
	traffic = world.get_node_or_null("LevelGeometry/Traffic")
	if not check(ambient != null, "LevelGeometry/Ambient attached"):
		_finish()
		return
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false   # наблюдатели не мешают: Илюша ходит у дорог
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	_part_structure()
	await _part_levels()
	await _part_horn()
	await _part_crows()
	await _part_dog()
	await _part_cat_and_litter()
	_part_door_slam()
	_finish()

# --- 1. Состав и коллизии ---

func _part_structure() -> void:
	print("--- structure ---")
	var crows: Array = ambient.crows
	check(crows.size() >= 6 and crows.size() <= 10, "6–10 crows (%d)" % crows.size())
	check(ambient.dog != null and ambient.cat != null, "dog and cat exist")
	check(ambient.litter.size() >= 5 and ambient.litter.size() <= 8, "5–8 litter items (%d)" % ambient.litter.size())
	var bodies := ambient.find_children("*", "CollisionObject3D", true, false)
	check(bodies.size() == 1 and bodies[0] == ambient.dog_body, "only the dog has a collision body (%d bodies)" % bodies.size())
	var dog_body: AnimatableBody3D = ambient.dog_body
	check(dog_body.collision_layer == 4 and dog_body.collision_mask == 0, "dog body: layer Car (4), mask 0, like residents")
	check(world.car.collision_mask & 4 == 0, "Lada does not collide with the Car layer (passes the dog)")
	check(not dog_body.is_in_group(&"detection_sensors") and not ambient.dog.is_in_group(&"detection_sensors"), "dog is not a stealth sensor")
	var sitting := 0
	for crow in crows:
		if crow.state == &"sit" and crow.position.distance_to(crow.perch) < 0.01:
			sitting += 1
	check(sitting == crows.size(), "all crows start on their perches (%d/%d)" % [sitting, crows.size()])
	var near_ab := 0
	for crow in crows:
		if _flat(crow.perch).distance_to(Vector3(70, 0, 32)) < 25.0:
			near_ab += 1
	check(near_ab >= 6, "crows perch at A∩B (%d within 25 m)" % near_ab)
	var bins := [Layout.BINS, Layout.H10_BINS, Layout.KIOSK_BINS]
	var stray := []
	var bread := RegEx.create_from_string("(?i)(bread|loaf|baton|bag|bun|хлеб|батон|пакет)")
	for item: Node3D in ambient.litter:
		var p := item.global_position
		var close := false
		for b in bins:
			var c: Vector2 = b[0]
			var size: Vector3 = b[1]
			var d := Vector2(maxf(absf(p.x - c.x) - size.x * 0.5, 0.0), maxf(absf(p.z - c.y) - size.z * 0.5, 0.0)).length()
			close = close or d <= 2.0
		if not close or p.y > 0.05 or bread.search(String(item.name)):
			stray.append(String(item.name))
	check(stray.is_empty(), "litter lies on the ground within 2 m of the bins, no bread-like names %s" % [stray])
	var cat_p: Vector3 = ambient.cat.global_position
	check(absf(cat_p.z - 108.0) < 0.4 and cat_p.y > 0.8 and cat_p.y < 1.0 and absf(cat_p.x + 31.5) < 0.8, "cat sits on a ground-floor window sill of H1 %s" % cat_p)

# --- 2. Слои фона и уровни ---

func _part_levels() -> void:
	print("--- sound layers and levels ---")
	check(sound.wind.playing and sound.city_traffic.playing and sound.window_music.playing, "wind, distant traffic and window music play from the start")
	for s: AudioStreamWAV in [sound.WIND, sound.CITY_TRAFFIC, sound.WINDOW_MUSIC]:
		check(s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % s.resource_path.get_file())
	var yard: float = _file_rms("yard_ambience_loop.wav") + sound.ambience.volume_db
	var wind: float = _file_rms("wind_gust_loop.wav") + sound.wind.volume_db
	var city: float = _file_rms("distant_traffic_loop.wav") + sound.city_traffic.volume_db
	var music: float = _file_rms("window_music_loop.wav") + sound.window_music.volume_db
	print("INFO: beds dBFS: yard %.1f, wind %.1f, distant traffic %.1f; window music at source %.1f" % [yard, wind, city, music])
	check(wind <= -36.0 and wind < yard, "wind bed ≤ −36 dB and under the yard bed (%.1f vs %.1f)" % [wind, yard])
	check(city <= -36.0 and city < yard, "distant traffic bed ≤ −36 dB and under the yard bed (%.1f vs %.1f)" % [city, yard])
	var total := 10.0 * log(pow(10.0, yard / 10.0) + pow(10.0, wind / 10.0) + pow(10.0, city / 10.0)) / log(10.0)
	var quest: float = _file_rms("bread_get.wav") + sound.chime.volume_db
	check(total <= -30.0, "all beds together ≤ −30 dB (%.1f)" % total)
	check(quest - total >= 6.0, "quest chime stays ≥ 6 dB above the beds (%.1f vs %.1f)" % [quest, total])
	check(music <= -34.0, "window music ≤ −34 dB at the window (%.1f)" % music)
	var engine_top: float = _file_rms("engine_idle_loop.wav") - 1.0
	for spec in [["crow_caw_1.wav", sound.CROW_DB], ["crow_caw_2.wav", sound.CROW_DB], ["dog_bark.wav", sound.DOG_DB],
			["door_slam.wav", sound.DOOR_SLAM_DB], ["car_horn_short.wav", sound.HORN_DB]]:
		var level: float = _file_rms(spec[0]) + spec[1]
		check(level <= -24.0 and level < engine_top, "%s at source %.1f dB ≤ −24 and under the engine top %.1f" % [spec[0], level, engine_top])
	await _frames(2)

## Среднеквадратичная громкость WAV (16 бит) в дБ полной шкалы — по исходному файлу в assets/audio.
func _file_rms(file: String) -> float:
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/" + file)
	var at := 12
	while at + 8 <= bytes.size():
		var id := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		if id == "data":
			var sum := 0.0
			var n := int(size / 2)
			for i in n:
				var v := bytes.decode_s16(at + 8 + i * 2) / 32767.0
				sum += v * v
			return 10.0 * log(sum / maxf(n, 1)) / log(10.0)
		at += 8 + size + (size & 1)
	push_error("no data chunk in " + file)
	return 0.0

# --- 3. Сигнал машины ---

func _part_horn() -> void:
	print("--- car horn ---")
	if not check(traffic != null and traffic.cars.size() >= 2, "ring traffic exists"):
		return
	traffic.reset_positions()
	await _frames(2)
	# Короткая задержка (≈ 2 с): гудка нет.
	var short: PathVehicle = traffic.cars[1]
	var horns_before: int = sound.played["horn"]
	await _block(short, 2.0)
	check(_horns_of(short).is_empty(), "%s blocked ≈ 2 s: no horn" % short.name)
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	await _frames(240)
	# Долгая задержка: первый гудок после 3 с, второй — не раньше чем через 10 с.
	var car: PathVehicle = traffic.cars[0]
	await _block(car, 14.0)
	var mine := _horns_of(car)
	check(mine.size() == 2, "%s blocked 14 s: two horns (%d)" % [car.name, mine.size()])
	if mine.size() >= 1:
		check(mine[0][2] > 3.0 and mine[0][2] < 3.2, "first horn right after 3 s of waiting (%.2f s)" % mine[0][2])
	if mine.size() >= 2:
		check(mine[1][0] - mine[0][0] >= 10.0 and mine[1][0] - mine[0][0] < 10.2, "second horn 10 s after the first (%.2f s)" % (mine[1][0] - mine[0][0]))
	check(sound.played["horn"] >= horns_before + 2 and sound.played["horn"] == sound.horn_times.size(), "horn counter matches (%d)" % sound.played["horn"])
	var player: AudioStreamPlayer3D = car.get_node_or_null("Horn")
	check(player != null and player.stream == sound.CAR_HORN, "horn plays from the car body (3D)")
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	await _frames(120)

## Поставить «Лану» на полосу машины в 6 м перед бампером и держать seconds с от начала её ожидания.
func _block(vehicle: PathVehicle, seconds: float) -> void:
	var lane: PathVehicle.LanePath = vehicle.path
	var at := vehicle.s + vehicle.size.z * 0.5 + 6.5
	var p := lane.position_at(at)
	var dir := lane.direction_at(at)
	world.car.reset_to(p, atan2(-dir.x, -dir.z))
	var frames := 0
	while vehicle.blocked_time <= 0.0 and frames < 600:
		await physics_frame
		frames += 1
	check(vehicle.blocked_by == world.car, "%s stops for the Lada" % vehicle.name)
	while vehicle.blocked_time < seconds and frames < 2400:
		await physics_frame
		frames += 1

func _horns_of(vehicle: Node) -> Array:
	return sound.horn_times.filter(func(h: Array) -> bool: return h[1] == vehicle)

# --- 4. Вороны ---

func _part_crows() -> void:
	print("--- crows ---")
	# Транспорт уже ездил под проводами у A∩B — вороны взлетали от него.
	await _frames(60 * 40)
	check(int(ambient.flushes[&"traffic"]) >= 1, "crows take off from passing traffic (%d)" % ambient.flushes[&"traffic"])
	check(sound.played["crow"] >= 1, "crow caws sound (%d)" % sound.played["crow"])
	traffic.free()   # дальше — без транспорта: вороны пугаются только тем, кого ставит тест
	traffic = null
	await _frames(2)
	check(await _all_crows_settle(60.0), "all crows back on their perches once traffic is gone")
	# Илюша у вороны на валу.
	var bank: Node3D = ambient.crows[7]
	world.player.place(bank.perch + Vector3(0, 0, 3.0) - Vector3(0, bank.perch.y, 0), 0.0)
	await _frames(120)
	check(bank.state != &"sit" and bank.position.y > bank.perch.y + 1.0, "bank crow flies up from Ilyusha at 3 m (y %.1f)" % bank.position.y)
	var player_flushes: int = ambient.flushes[&"player"]
	check(player_flushes >= 1, "flush counted for Ilyusha (%d)" % player_flushes)
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var back := await _wait_crow_sit(bank, 30.0)
	check(back >= AmbientScript.FLY_MIN, "bank crow lands back after ≥ %.0f s in the air (%.1f s)" % [AmbientScript.FLY_MIN, back])
	check(bank.position.distance_to(bank.perch) < 0.01, "bank crow sits exactly on its perch")
	# «Лада» под проводом A.
	var wire: Node3D = ambient.crows[3]
	world.car.reset_to(Vector3(wire.perch.x, 0, 33.5), -PI * 0.5)
	await _frames(90)
	check(wire.state != &"sit" and wire.position.y > wire.perch.y + 1.0, "wire crow flies up from the Lada below (y %.1f)" % wire.position.y)
	check(int(ambient.flushes[&"car"]) >= 1, "flush counted for the Lada")
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)
	back = await _wait_crow_sit(wire, 30.0)
	check(back >= AmbientScript.FLY_MIN, "wire crow lands back on the wire (%.1f s)" % back)
	var caws := 0
	for crow in ambient.crows:
		caws += crow.caws
	check(sound.played["crow"] == caws, "every caw is heard once (%d sounds, %d caws)" % [sound.played["crow"], caws])
	# Сидящие не дрейфуют.
	await _frames(60)
	var drift := 0.0
	for crow in ambient.crows:
		if crow.state == &"sit":
			drift = maxf(drift, crow.position.distance_to(crow.perch))
	check(drift < 0.001, "sitting crows stay on the perch (max %.4f m)" % drift)

func _all_crows_settle(seconds: float) -> bool:
	var frames := 0
	while frames < int(seconds * 60):
		var ok := true
		for crow in ambient.crows:
			ok = ok and crow.state == &"sit"
		if ok:
			return true
		await physics_frame
		frames += 1
	return false

## Длительность полёта до посадки, с (−1 — не сел за timeout с).
func _wait_crow_sit(crow: Node3D, timeout: float) -> float:
	var frames := 0
	while crow.state != &"sit" and frames < int(timeout * 60):
		await physics_frame
		frames += 1
	return crow.last_flight if crow.state == &"sit" else -1.0

# --- 5. Собака ---

func _part_dog() -> void:
	print("--- dog ---")
	var dog: Node3D = ambient.dog
	var area: Rect2 = AmbientScript.DOG_AREA
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	var barks_before: int = ambient.dog_barks
	var outside := 0
	var on_street := 0
	var travelled := 0.0
	var last := dog.global_position
	for i in 130 * 60:
		await physics_frame
		var p := dog.global_position
		travelled += _flat(p).distance_to(_flat(last))
		last = p
		if not area.grow(0.01).has_point(Vector2(p.x, p.z)):
			outside += 1
		if _on_street(p, 0.5):
			on_street += 1
	check(outside == 0, "dog never leaves its patch behind the garages (%d frames outside)" % outside)
	check(on_street == 0, "dog never steps on a road or sidewalk (%d frames)" % on_street)
	check(travelled > 30.0, "dog walks its loop (%.0f m in 130 s)" % travelled)
	var times: Array[float] = ambient.dog_bark_times
	var barks: int = ambient.dog_barks - barks_before
	check(barks >= 3 and barks <= 7, "dog barks 3–7 times in 130 s (%d)" % barks)
	var bad := []
	for i in range(1, times.size()):
		var gap := times[i] - times[i - 1]
		if gap < 20.0 or gap > 40.0:
			bad.append(snappedf(gap, 0.01))
	check(times.size() >= 2 and bad.is_empty() and times[0] <= 40.0, "barks every 20–40 s (first at %.1f s, bad gaps %s)" % [times[0] if times.size() > 0 else -1.0, bad])
	check(sound.played["dog"] == ambient.dog_barks, "every bark is heard (%d / %d)" % [sound.played["dog"], ambient.dog_barks])
	# Илюша стоит в 3 м от собаки: собака отходит, Илюша не сдвигается.
	var here := dog.global_position
	var spot := here + Vector3(0, 0, -3.0) if here.z > -84.0 else here + Vector3(0, 0, 3.0)
	spot = Vector3(clampf(spot.x, area.position.x + 0.5, area.end.x - 0.5), 0, spot.z)
	world.player.place(spot, 0.0)
	await _frames(2)
	var player_at := world.player.global_position
	var start_d := _flat(dog.global_position).distance_to(_flat(player_at))
	var min_d := INF
	var pushed := 0.0
	for i in 20 * 60:
		await physics_frame
		min_d = minf(min_d, _flat(dog.global_position).distance_to(_flat(world.player.global_position)))
		pushed = maxf(pushed, _flat(world.player.global_position).distance_to(_flat(player_at)))
	var end_d := _flat(dog.global_position).distance_to(_flat(world.player.global_position))
	check(end_d >= AmbientScript.DOG_FLEE_DISTANCE - 0.1 or end_d > start_d + 0.8, "dog moves away from Ilyusha (%.1f → %.1f m)" % [start_d, end_d])
	check(min_d >= 1.0, "dog never comes closer than 1 m to Ilyusha (%.2f m)" % min_d)
	check(pushed < 0.02, "dog does not push Ilyusha (moved %.3f m)" % pushed)
	# Илюша идёт прямо на собаку: упирается, собака не толкает его назад.
	world.player.place(dog.global_position + Vector3(0, 0, 2.5) if dog.global_position.z < -70.0 else dog.global_position + Vector3(0, 0, -2.5), 0.0)
	var to_dog := _flat(dog.global_position - world.player.global_position)
	world.camera_rig.yaw = atan2(-to_dog.x, -to_dog.z)
	await _frames(3)
	Input.action_press(&"move_forward")
	min_d = INF
	for i in 4 * 60:
		await physics_frame
		min_d = minf(min_d, _flat(dog.global_position).distance_to(_flat(world.player.global_position)))
	Input.action_release(&"move_forward")
	check(min_d > 0.3, "walking at the dog: bodies never overlap (closest %.2f m)" % min_d)
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _frames(10)

## Точка на проезжей части или тротуаре (Layout.SURFACES road/sidewalk) с запасом margin.
func _on_street(p: Vector3, margin: float) -> bool:
	for s in Layout.SURFACES:
		if s[1] != "road" and s[1] != "sidewalk":
			continue
		var c: Vector2 = s[2]
		var size: Vector2 = s[3]
		if absf(p.x - c.x) <= size.x * 0.5 + margin and absf(p.z - c.y) <= size.y * 0.5 + margin:
			return true
	return false

# --- 6. Кошка и мусор ---

func _part_cat_and_litter() -> void:
	print("--- cat and litter ---")
	var tail: Node3D = ambient._cat_tail
	var a := tail.rotation.y
	await _frames(30)
	check(absf(tail.rotation.y - a) > 0.01, "cat tail sways")
	# Илюша проходит по мусору у дворовых контейнеров: ничто не мешает.
	world.player.place(Vector3(-37.0, 0, 67.2), -PI * 0.5)
	world.camera_rig.yaw = -PI * 0.5
	await _frames(3)
	var from := world.player.global_position
	Input.action_press(&"move_forward")
	await _frames(90)
	Input.action_release(&"move_forward")
	var moved := world.player.global_position.x - from.x
	check(moved > 3.0, "Ilyusha walks over the litter by the yard bins (%.1f m in 1.5 s)" % moved)
	world.player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await _frames(5)

# --- 7. Дверь подъезда ---

func _part_door_slam() -> void:
	print("--- entrance door ---")
	var times: Array[float] = sound.door_slam_times
	check(times.size() >= 2, "entrance door slams during the run (%d)" % times.size())
	var bad := []
	for i in range(1, times.size()):
		var gap := times[i] - times[i - 1]
		if gap < 60.0 or gap > 120.0:
			bad.append(snappedf(gap, 0.01))
	check(times.size() > 0 and times[0] >= 60.0 and times[0] <= 120.0 and bad.is_empty(), "door slams every 60–120 s (first %.1f s, bad gaps %s)" % [times[0] if times.size() > 0 else -1.0, bad])
	check(sound.played["door_slam"] == times.size() and sound.door_slam.stream == sound.DOOR_SLAM, "door slam counter and stream")
	check(_flat(sound.door_slam.global_position).distance_to(Vector3(-40, 0, 108)) < 0.5, "door slam sounds at the entrance door")

# --- общее ---

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
	return condition

func _finish(code := -1) -> void:
	print("AMBIENT: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

extends SceneTree
## POLISH-01, застревания (seed 2610, всё детерминировано).
## Часть 1 — случайные свободные точки по карте: Илюша уходит хотя бы в одну из 8 сторон; машина едет вперёд или назад,
##   а после езды с рулём стоит на земле в пределах карты и выезжает с места остановки.
## Часть 2 — сценарии у геометрии (ревью 27.10): углы зданий, стыки коробок, валы и кучи снега, края карты, гаражи,
##   киоск, столбы и берёзы, мелкие препятствия. Илюша идёт в препятствие под разными углами и должен отойти от него;
##   машина упирается носом или задом и должна выехать прямо и с рулём.
## Часть 3 — упор в каждый угол коробок и валов под 7 углами: Илюша не проваливается в землю (найдено 27.10).
## Часть 4 (ARENA-01, C8) — полный круг по кольцу на «Ладе» по правой полосе: A на запад, D на север, C на восток,
##   B на юг, углы скруглены (Layout.ring_lane), задним ходом не ездим. Без упоров в стены, без схода с полосы.
## Опрокидывание не проверяется: машина вращается только вокруг вертикали (lada.gd, rotate_y и reset_to),
##   вместо этого — «на земле, не в коробке, сдвигается с места».

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/quest01_driver.gd")
const WALK_POINTS := 60
const CAR_POINTS := 30
const CATS := ["building_corner", "building_face", "junction", "snow", "edge", "garage", "kiosk", "post", "prop"]
const WALK_CAP := 30            # сценариев на категорию
const CAR_CAP := 10
const MIN_PER_CAT := 4          # меньше — генератор сценариев сломан, проверка ничего не покрывает
const FACE_ANGLES := [0.0, PI / 4, -PI / 4, PI * 5 / 12, -PI * 5 / 12]   # 0°, ±45°, ±75° (вдоль стены)
const CORNER_ANGLES := [0.0, PI / 6, -PI / 6]
const SINK_SWEEP_DEG := [-36, -24, -12, 0, 12, 24, 36]   # подход к каждому углу коробок и валов, от диагонали
const SINK_TOLERANCE := 0.05    # м ниже земли
const JUNCTION_GAP := 1.0       # м: углы ближе этого к другой коробке — стык или щель
const END_INSET := 1.0          # м от края грани до крайней точки удара
const WALK_RUN := 1.6           # м от старта до точки удара
const WALK_PUSH := 45           # кадров упора (0,75 с)
const WALK_ESCAPE := 40         # кадров отхода (0,67 с)
const WALK_ESCAPE_MIN := 1.0    # м в сторону от препятствия
const WALK_ESCAPES := [0.0, PI / 4, -PI / 4, PI / 2, -PI / 2]           # прямо назад, затем наискось и вбок
const CAR_GAP := 2.5            # м от бампера до препятствия на старте
const CAR_PUSH := 60            # кадров газа в препятствие (1 с)
const CAR_TAIL_PUSH := 80       # кадров заднего хода в препятствие
const CAR_ESCAPE := 90          # кадров выезда (1,5 с)
const CAR_ESCAPE_MIN := 1.5     # м за CAR_ESCAPE
const CAR_TURN_MIN := 0.2       # рад поворота за манёвр с рулём
const CAR_MANEUVER_MIN := 3.0   # м отъезда за манёвр с рулём
const RING_SPEED := 8.0         # м/с: медленнее машин кольца (9 м/с, C8) — не догоняет транспорт
const RING_TOL := 3.0           # м до точки, после которых водитель берёт следующую
# м от оси полосы: дальше — съехал с полосы. 1,5 → 2,0 (ARENA-01 fix P3): худшее отклонение 1,48–1,49 м — у (68,5; −84,5),
# в 12 м после выхода из дуги C∩B, то есть занос «Лады» водителя тестов на 8 м/с при наборе после правого поворота, а
# не геометрия: дуга C∩B — та же 6 м, что на трёх других углах. От полосы x = 67 до вала B (x 64) — 3 м, до встречной
# полосы машин (x 73, борт ≥ 72) — 6 м: 2,0 м отклонения держат «Ладу» на своей половине.
const RING_STRAY := 2.0
const RING_FRAMES := 60 * 150   # кадров на круг (≈ 520 м)

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var rng := RandomNumberGenerator.new()
var car_low := 0.0              # самая низкая точка машины в _drive и манёврах с начала сценария

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Сторож от зависания, не критерий. Время растёт с числом твёрдых коробок (обход углов): ART-05/06
	# добавили тополя, машины и павильоны, 3000 с перестало хватать; ARENA-01 — улицы C и D и круг по кольцу.
	# 4500 → 6000 (BREAK-01, 29.10): сценарии у тяжёлых разрушаемых и коробок PROPS-01 не укладывались в 4500 с.
	create_timer(6000.0, true, false, true).timeout.connect(func():
		push_error("FAIL: stuck sweep exceeded 6000 simulated seconds")
		quit(2)
	)
	var started := Time.get_ticks_msec()
	rng.seed = 2610
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.start_game()
	await _frames(10)
	world = main.world
	# Застревания — про неподвижную геометрию; движущийся транспорт кольца (ARENA-01, часть T) проверяет свой набор.
	var traffic := world.get_node_or_null("LevelGeometry/Traffic")
	if traffic:
		traffic.free()
	# Жители (PEOPLE-01) — тоже движущиеся тела на слое Car: пробы _free (маска World|Car) считали бы их препятствиями
	# и меняли выборку сценариев (интегратор 28.10: H10_NorthWest 2,4 м из-за жителя на маршруте 7). Свой набор — RESIDENTS.
	var residents := world.get_node_or_null("LevelGeometry/Residents")
	if residents:
		residents.free()
	# Наблюдатели стелса (EXT-01): провал переставляет Илюшу на чекпоинт, а «Ладу» на площадке киоска — на парковку
	# (fix2, P1), и сценарий у павильона и опор площадки ломался бы не из-за геометрии. Свой набор — STEALTH.
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	_park_car_away(true)  # машина вне карты, чтобы не мешала пешеходу ни в одном сценарии
	await _sweep_walk()
	var scenarios := _scenarios()
	await _geometry_walk(scenarios)
	await _corner_sink_sweep()
	await _breakable_walk()
	await _props_walk()   # PROPS-01: новые коробки арены
	_park_car_away(false)
	await _sweep_car()
	await _geometry_car(scenarios)
	await _breakable_car()
	await _props_car()
	await _rink_gates()
	_patrol_bodies(true)
	await _ring_lap()
	print("INFO: stuck test wall time %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	_finish()

func _park_car_away(away: bool) -> void:
	world.car.set_physics_process(not away)
	world.car.reset_to(Vector3(0, 0, 400) if away else Layout.CAR_SPAWN, 0.0)

# --- часть 1: случайные свободные точки ---

func _sweep_walk() -> void:
	var player := world.player
	var trapped := []
	var escaped := []
	var tested := 0
	while tested < WALK_POINTS:
		var point := _random_point(0.5)
		if not _free(point, _capsule(0.4), 0.8):
			continue
		tested += 1
		var free_directions := 0
		for k in 8:
			player.place(point, 0.0)
			world.camera_rig.yaw = k * TAU / 8.0
			await _frames(2)
			Input.action_press(&"move_forward")
			await _frames(15)
			Input.action_release(&"move_forward")
			var p := player.global_position
			if Vector2(p.x - point.x, p.z - point.z).length() > 0.3:
				free_directions += 1
			if p.y < -0.5 or not Layout.BOUNDS.has_point(Vector2(p.x, p.z)):
				escaped.append(point)
		if free_directions == 0:
			trapped.append(point)
	print("INFO: walk sweep %d points, trapped %d, escaped %d" % [tested, trapped.size(), escaped.size()])
	check(trapped.is_empty(), "Ilyusha is never trapped at a random free spot (%s)" % [trapped.slice(0, 5)])
	check(escaped.is_empty(), "Ilyusha never falls or leaves the map (%s)" % [escaped.slice(0, 5)])

func _sweep_car() -> void:
	var car := world.car
	world.enter_car()
	await _frames(3)
	var trapped := []
	var broken := []
	var stuck_after_ride := []
	var tested := 0
	while tested < CAR_POINTS:
		var point := _random_point(2.5)
		var yaw := rng.randf_range(-PI, PI)
		if not _free(point, _car_box(0.3), Lada.SIZE.y * 0.5 + 0.1, yaw):
			continue
		tested += 1
		var moved := false
		for action in [&"move_forward", &"move_back"]:
			car.reset_to(point, yaw)
			await _frames(2)
			Input.action_press(action)
			await _frames(45)
			Input.action_release(action)
			if car.global_position.distance_to(point) > 0.5:
				moved = true
		if not moved:
			trapped.append(point)
		# 2 с с рулём в случайную сторону, торможение — и машина должна выехать с того места, где встала.
		car.reset_to(point, yaw)
		Input.action_press(&"move_forward")
		Input.action_press(&"move_left" if rng.randf() < 0.5 else &"move_right")
		await _frames(120)
		_release_all()
		await _brake_to_stop()
		var stop := car.global_position
		if _car_issue() != "":
			broken.append("(%.1f,%.1f)%s" % [stop.x, stop.z, _car_issue()])
		if not await _car_leaves(stop, car.rotation.y, 45, 1.0):
			stuck_after_ride.append(stop)
	print("INFO: car sweep %d points, trapped %d, broken %d, stuck after ride %d" % [tested, trapped.size(), broken.size(), stuck_after_ride.size()])
	check(trapped.is_empty(), "Lada can always drive forward or back from a free spot (%s)" % [trapped.slice(0, 5)])
	check(broken.is_empty(), "Lada stays on the ground, outside solids and inside the map after a steering ride (%s)" % [broken.slice(0, 3)])
	check(stuck_after_ride.is_empty(), "Lada drives off from wherever a steering ride stopped it (%s)" % [stuck_after_ride.slice(0, 3)])

# --- часть 2: сценарии у геометрии ---

## Коробки уровня в плане: Layout.all_solids(), Бабка и невидимые стены по краю карты (как в level_geometry.gd).
func _boxes() -> Array:
	var boxes := []
	for spec in Layout.all_solids():
		var size: Vector3 = spec[3]
		boxes.append({"name": spec[0], "cat": _category(spec[1]), "c": spec[2], "h": Vector2(size.x, size.z) * 0.5})
	boxes.append({"name": "Babka", "cat": "prop", "c": Vector2(Layout.BABKA.x, Layout.BABKA.z), "h": Vector2(0.7, 0.7)})  # npc.gd body_radius
	var b := Layout.BOUNDS
	var mid := b.get_center()
	boxes.append({"name": "Bound_West", "cat": "edge", "c": Vector2(b.position.x - 1.0, mid.y), "h": Vector2(1.0, b.size.y * 0.5)})
	boxes.append({"name": "Bound_East", "cat": "edge", "c": Vector2(b.end.x + 1.0, mid.y), "h": Vector2(1.0, b.size.y * 0.5)})
	boxes.append({"name": "Bound_North", "cat": "edge", "c": Vector2(mid.x, b.position.y - 1.0), "h": Vector2(b.size.x * 0.5, 1.0)})
	boxes.append({"name": "Bound_South", "cat": "edge", "c": Vector2(mid.x, b.end.y + 1.0), "h": Vector2(b.size.x * 0.5, 1.0)})
	return boxes

func _category(kind: String) -> String:
	match kind:
		"panel", "panel_low": return "building"
		"garage": return "garage"
		"kiosk": return "kiosk"
		"snow", "snow_bank": return "snow"
		"lamp", "tree", "sign_post": return "post"
	return "prop"

## Сценарий — точка удара на контуре коробки и направление подхода в плане (x, z).
## Углы — подход к углу по диагонали ±30°; грани — края и середина (у длинных и четверти), 0°, ±45°, ±75°;
## стыки — углы коробок, лежащие ближе JUNCTION_GAP к соседней коробке, подход с 8 сторон.
func _scenarios() -> Dictionary:
	var boxes := _boxes()
	var by_cat := {}
	for cat in CATS:
		by_cat[cat] = []
	for box in boxes:
		var c: Vector2 = box.c
		var h: Vector2 = box.h
		var corner_cat: String = "building_corner" if box.cat == "building" else box.cat
		var face_cat: String = "building_face" if box.cat == "building" else box.cat
		for corner_sign in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			var corner: Vector2 = c + corner_sign * h
			for a in CORNER_ANGLES:
				by_cat[corner_cat].append(_scenario(box.name, corner, (-corner_sign.normalized()).rotated(a)))
		for n in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var tangent: Vector2 = Vector2(-n.y, n.x)
			var half_len: float = absf(tangent.x) * h.x + absf(tangent.y) * h.y
			var face_mid: Vector2 = c + n * (absf(n.x) * h.x + absf(n.y) * h.y)
			var offsets := [0.0]
			if half_len > END_INSET * 2.0:
				offsets = [-(half_len - END_INSET), 0.0, half_len - END_INSET]
			if half_len > 15.0:
				offsets += [-half_len * 0.5, half_len * 0.5]
			for o in offsets:
				for a in FACE_ANGLES:
					by_cat[face_cat].append(_scenario(box.name, face_mid + tangent * o, (-n).rotated(a)))
	var seen := {}
	for i in boxes.size():
		for j in boxes.size():
			if i == j:
				continue
			for corner_sign in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
				var corner: Vector2 = boxes[i].c + corner_sign * boxes[i].h
				if not _near_box(corner, boxes[j], JUNCTION_GAP) or _near_box(corner, boxes[j], -0.05):
					continue
				var key := Vector2i(roundi(corner.x * 2.0), roundi(corner.y * 2.0))
				if seen.has(key):
					continue
				seen[key] = true
				for k in 8:
					by_cat["junction"].append(_scenario("%s/%s" % [boxes[i].name, boxes[j].name], corner, Vector2(0, -1).rotated(k * TAU / 8.0)))
	return by_cat

func _scenario(name: String, target: Vector2, dir: Vector2) -> Dictionary:
	return {"name": name, "target": target, "dir": dir.normalized()}

func _near_box(p: Vector2, box: Dictionary, margin: float) -> bool:
	var d: Vector2 = (p - box.c).abs()
	return d.x <= box.h.x + margin and d.y <= box.h.y + margin

## Из категории — только сценарии с допустимым стартом, затем перемешать своим rng и взять cap.
func _pick(pool: Array, cap: int, valid: Callable) -> Array:
	var ok := pool.filter(valid)
	for i in range(ok.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ok[i]
		ok[i] = ok[j]
		ok[j] = t
	return ok.slice(0, cap)

func _walk_start(s: Dictionary) -> Vector3:
	var p: Vector2 = s.target - s.dir * WALK_RUN
	return Vector3(p.x, 0.0, p.y)

func _car_start(s: Dictionary) -> Vector3:
	var p: Vector2 = s.target - s.dir * (CAR_GAP + Lada.SIZE.z * 0.5)
	return Vector3(p.x, 0.0, p.y)

func _geometry_walk(by_cat: Dictionary) -> void:
	var player := world.player
	var inner := Layout.BOUNDS.grow(-0.5)
	var total := 0
	for cat in CATS:
		var picked := _pick(by_cat[cat], WALK_CAP, func(s):
			var p := _walk_start(s)
			return inner.has_point(Vector2(p.x, p.z)) and _free(p, _capsule(0.4), 0.8))
		var touched := 0
		var trapped := []
		var reverse_blocked := []
		var broken := []
		for s in picked:
			var start := _walk_start(s)
			var dir: Vector2 = s.dir
			player.place(start, 0.0)
			world.camera_rig.yaw = _yaw(dir)
			await _frames(2)
			Input.action_press(&"move_forward")
			var hit := false
			var top := 0.0
			var low := 0.0
			for f in WALK_PUSH:
				await physics_frame
				hit = hit or player.is_on_wall()
				top = maxf(top, player.global_position.y)
				low = minf(low, player.global_position.y)
			Input.action_release(&"move_forward")
			var contact := player.global_position
			if hit:
				touched += 1
			var why := ""
			if top > 0.3:
				why = " lifted %.2f" % top
			elif low < -SINK_TOLERANCE:
				why = " sunk %.3f from (%.2f,%.2f) dir (%.3f,%.3f)" % [low, start.x, start.z, dir.x, dir.y]
			elif contact.y < -0.5 or not Layout.BOUNDS.has_point(Vector2(contact.x, contact.z)):
				why = " off map"
			elif not _free(contact, _capsule(0.25), 0.8):
				why = " inside %s at (%.3f,%.3f,%.3f) from (%.2f,%.2f) dir (%.3f,%.3f)" % [_hit_name(contact, _capsule(0.25), 0.8),
					contact.x, contact.y, contact.z, start.x, start.z, dir.x, dir.y]
			if why != "":
				broken.append(_where(s, contact) + why)
			var escaped := -1
			for e in WALK_ESCAPES.size():
				var away := (-dir).rotated(WALK_ESCAPES[e])
				player.place(contact, 0.0)
				world.camera_rig.yaw = _yaw(away)
				await _frames(2)
				Input.action_press(&"move_forward")
				await _frames(WALK_ESCAPE)
				Input.action_release(&"move_forward")
				var p := player.global_position
				if Vector2(p.x - contact.x, p.z - contact.z).dot(away) >= WALK_ESCAPE_MIN:
					escaped = e
					break
			if escaped < 0:
				trapped.append(_where(s, contact))
			elif escaped > 0:
				reverse_blocked.append(_where(s, contact))
		total += picked.size()
		print("INFO: walk geo %-15s pool %3d, tested %2d, touched %2d, trapped %d, reverse blocked %d, broken %d %s %s" % [
			cat, by_cat[cat].size(), picked.size(), touched, trapped.size(), reverse_blocked.size(), broken.size(),
			trapped.slice(0, 3), reverse_blocked.slice(0, 3)])
		check(picked.size() >= MIN_PER_CAT, "walk geometry '%s' has scenarios (%d)" % [cat, picked.size()])
		check(touched * 10 >= picked.size() * 7, "walk geometry '%s' actually reaches the obstacle (%d of %d)" % [cat, touched, picked.size()])
		check(trapped.is_empty(), "Ilyusha walks away from '%s' within %.2f s (%s)" % [cat, WALK_ESCAPE / 60.0, trapped.slice(0, 3)])
		check(broken.is_empty(), "Ilyusha stays on the ground, outside solids and in the map at '%s' (%s)" % [cat, broken.slice(0, 3)])
	print("INFO: walk geometry %d scenarios" % total)

## Найдено 27.10: упор в вертикальное ребро коробки под некоторыми углами проваливал Илюшу в землю до 0,3 м
## (привязка к полу floor_snap_length = 0,3, цикл -0,30 / -0,04 / 0,00 м). Каждый угол коробок SOLIDS и валов снега,
## подход под SINK_SWEEP_DEG от диагонали: ниже SINK_TOLERANCE опускаться нельзя.
func _corner_sink_sweep() -> void:
	var player := world.player
	var inner := Layout.BOUNDS.grow(-0.5)
	var tested := 0
	var sunk := []
	var worst := 0.0
	for spec in Layout.all_solids():
		if spec[1] in ["lamp", "tree", "sign_post"]:
			continue
		var c: Vector2 = spec[2]
		var h := Vector2(spec[3].x, spec[3].z) * 0.5
		for corner_sign in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			var corner: Vector2 = c + corner_sign * h
			for deg in SINK_SWEEP_DEG:
				var dir: Vector2 = (-corner_sign.normalized()).rotated(deg_to_rad(deg))
				var start := corner - dir * 1.2
				var start3 := Vector3(start.x, 0.0, start.y)
				if not inner.has_point(start) or not _free(start3, _capsule(0.4), 0.8):
					continue
				tested += 1
				player.place(start3, 0.0)
				world.camera_rig.yaw = _yaw(dir)
				await _frames(2)
				Input.action_press(&"move_forward")
				var low := 0.0
				for f in 40:
					await physics_frame
					low = minf(low, player.global_position.y)
				Input.action_release(&"move_forward")
				worst = minf(worst, low)
				if low < -SINK_TOLERANCE:
					sunk.append("%s@(%.1f,%.1f) %+d° %.2f" % [spec[0], corner.x, corner.y, deg, low])
	print("INFO: corner sink sweep %d approaches, sunk %d, lowest y %.3f %s" % [tested, sunk.size(), worst, sunk.slice(0, 6)])
	check(tested >= 300, "corner sink sweep covers the corners (%d approaches)" % tested)
	check(sunk.is_empty(), "Ilyusha never sinks into the ground pushing into a corner (%s)" % [sunk.slice(0, 6)])

func _geometry_car(by_cat: Dictionary) -> void:
	var car := world.car
	var inner := Layout.BOUNDS.grow(-2.5)
	var total := 0
	for cat in CATS:
		_patrol_bodies(true)
		var picked := _pick(by_cat[cat], CAR_CAP, func(s):
			var p := _car_start(s)
			return inner.has_point(Vector2(p.x, p.z)) and _free(p, _car_box(0.3), Lada.SIZE.y * 0.5 + 0.1, _yaw(s.dir)))
		# EXT-01 fix6: полицейские у киоска — люди, как жители (их убирают выше): «Лада», упёртая носом в угол павильона
		# остановки, не отъезжала назад на 1,5 м из-за тела первого на посту (62; −70). Тела выключены только на заездах —
		# выборка сценариев (rng) та же, что с телами.
		_patrol_bodies(false)
		var touched := 0
		var stuck := []
		var no_turn := []
		var broken := []
		for s in picked:
			var start := _car_start(s)
			var yaw := _yaw(s.dir)
			car_low = 0.0
			# Нос в препятствие, затем прямо назад.
			car.reset_to(start, yaw)
			await _frames(2)
			var hit := await _drive(&"move_forward", &"", CAR_PUSH)
			var contact := car.global_position
			var contact_yaw := car.rotation.y
			if _car_issue() != "":
				broken.append(_where(s, contact) + _car_issue())
			if hit:
				touched += 1
			if not await _car_leaves(contact, contact_yaw, CAR_ESCAPE, CAR_ESCAPE_MIN, [&"move_back"]):
				stuck.append(_where(s, contact) + " nose/back")
			# С того же упора: назад с рулём, затем вперёд с обратным рулём.
			car.reset_to(contact, contact_yaw)
			await _frames(2)
			var side := &"move_left" if rng.randf() < 0.5 else &"move_right"
			var other := &"move_right" if side == &"move_left" else &"move_left"
			var farthest := 0.0
			Input.action_press(&"move_back")
			Input.action_press(side)
			for f in CAR_ESCAPE:
				await physics_frame
				farthest = maxf(farthest, _flat(car.global_position - contact))
				car_low = minf(car_low, car.global_position.y)
			_release_all()
			Input.action_press(&"move_forward")
			Input.action_press(other)
			for f in CAR_ESCAPE:
				await physics_frame
				farthest = maxf(farthest, _flat(car.global_position - contact))
				car_low = minf(car_low, car.global_position.y)
			_release_all()
			await _brake_to_stop()
			if farthest < CAR_MANEUVER_MIN or absf(angle_difference(contact_yaw, car.rotation.y)) < CAR_TURN_MIN:
				no_turn.append(_where(s, contact) + " %.1fm %.2frad" % [farthest, angle_difference(contact_yaw, car.rotation.y)])
			if _car_issue() != "":
				broken.append(_where(s, car.global_position) + " after steer" + _car_issue())
			# Задом в препятствие, затем вперёд.
			car.reset_to(start, yaw + PI)
			await _frames(2)
			await _drive(&"move_back", &"", CAR_TAIL_PUSH)
			var tail := car.global_position
			if _car_issue() != "":
				broken.append(_where(s, tail) + " tail" + _car_issue())
			if not await _car_leaves(tail, car.rotation.y, CAR_ESCAPE, CAR_ESCAPE_MIN, [&"move_forward"]):
				stuck.append(_where(s, tail) + " tail/forward")
			if car_low < -SINK_TOLERANCE:
				broken.append(_where(s, start) + " sunk %.3f" % car_low)
		total += picked.size()
		print("INFO: car geo %-15s pool %3d, tested %2d, touched %2d, stuck %d, no turn %d, broken %d %s %s %s" % [
			cat, by_cat[cat].size(), picked.size(), touched, stuck.size(), no_turn.size(), broken.size(),
			stuck.slice(0, 3), no_turn.slice(0, 3), broken.slice(0, 3)])
		check(picked.size() >= MIN_PER_CAT, "car geometry '%s' has scenarios (%d)" % [cat, picked.size()])
		check(touched * 10 >= picked.size() * 7, "car geometry '%s' actually reaches the obstacle (%d of %d)" % [cat, touched, picked.size()])
		check(stuck.is_empty(), "Lada backs off / pulls away from '%s' by %.1f m in %.1f s (%s)" % [cat, CAR_ESCAPE_MIN, CAR_ESCAPE / 60.0, stuck.slice(0, 3)])
		check(no_turn.is_empty(), "Lada steers out from '%s': >= %.0f m and >= %.1f rad (%s)" % [cat, CAR_MANEUVER_MIN, CAR_TURN_MIN, no_turn.slice(0, 3)])
		check(broken.is_empty(), "Lada stays on the ground, outside solids and in the map at '%s' (%s)" % [cat, broken.slice(0, 3)])
	print("INFO: car geometry %d scenarios" % total)

# --- часть 2б (BREAK-01): целые тяжёлые разрушаемые объекты ---
## Layout.BREAKABLES с class heavy — не в all_solids(), поэтому сценарии части 2 их не видят. Илюша идёт в каждую грань
## и угол и отходит; «Лада» медленно (с 0,3 м: до упора меньше 3 м/с — объект стоит стеной) упирается носом в каждую
## грань и выезжает назад, затем назад с рулём и вперёд с обратным рулём. Сломанный объект — возвращается целым.

func _heavy_breakables() -> Array:
	var out := []
	var root := world.get_node_or_null("LevelGeometry/Breakables")
	if root == null:
		return out
	for b in root.objects:
		if b.heavy:
			out.append(b)
	return out

func _heavy_sides(b) -> Array:
	var h := Vector2(b.size.x, b.size.z) * 0.5
	var c: Vector2 = b.center
	var out := []
	for n in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		out.append([c + n * (absf(n.x) * h.x + absf(n.y) * h.y), -n])
	for k in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		out.append([c + k * h, -k.normalized()])
	return out

func _breakable_walk() -> void:
	var player := world.player
	var heavy := _heavy_breakables()
	var trapped := []
	var inside := []
	var tested := 0
	for b in heavy:
		for side in _heavy_sides(b):
			var dir: Vector2 = side[1]
			var start := Vector3(side[0].x - dir.x * WALK_RUN, 0.0, side[0].y - dir.y * WALK_RUN)
			if not _free(start, _capsule(0.4), 0.8):
				continue
			tested += 1
			player.place(start, 0.0)
			world.camera_rig.yaw = _yaw(dir)
			await _frames(2)
			Input.action_press(&"move_forward")
			await _frames(WALK_PUSH)
			Input.action_release(&"move_forward")
			var contact := player.global_position
			if b.rect().grow(0.2).has_point(Vector2(contact.x, contact.z)) or contact.y < -SINK_TOLERANCE:
				inside.append("%s@(%.1f,%.1f)" % [b.id, contact.x, contact.z])
			var escaped := false
			for e in WALK_ESCAPES:
				var away: Vector2 = (-dir).rotated(e)
				player.place(contact, 0.0)
				world.camera_rig.yaw = _yaw(away)
				await _frames(2)
				Input.action_press(&"move_forward")
				await _frames(WALK_ESCAPE)
				Input.action_release(&"move_forward")
				var p := player.global_position
				if Vector2(p.x - contact.x, p.z - contact.z).dot(away) >= WALK_ESCAPE_MIN:
					escaped = true
					break
			if not escaped:
				trapped.append("%s@(%.1f,%.1f)" % [b.id, contact.x, contact.z])
	print("INFO: walk heavy breakables %d objects, %d scenarios, trapped %d, inside %d" % [heavy.size(), tested, trapped.size(), inside.size()])
	check(heavy.is_empty() or tested >= heavy.size() * 4, "walk scenarios at heavy breakables (%d)" % tested)
	check(trapped.is_empty(), "Ilyusha walks away from heavy breakables (%s)" % [trapped.slice(0, 3)])
	check(inside.is_empty(), "Ilyusha never ends inside a heavy breakable (%s)" % [inside.slice(0, 3)])

## Коробка машины на старте не задевает разрушаемых (слой 32; _free их не видит): у качелей и карусели 4,2 м между
## гранями — машина длиной 4,1 м, поставленная туда носом в одну, стояла бы в другой.
func _clear_of_breakables(point: Vector3, yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _car_box(0.1)
	query.collision_mask = 32
	query.transform = Transform3D(Basis(Vector3.UP, yaw), point + Vector3.UP * (Lada.SIZE.y * 0.5 + 0.1))
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Выезд тараном: сдать назад до упора, затем газ в тяжёлый объект; true — объект сломан и машина ушла на CAR_ESCAPE_MIN.
func _car_rams_out(b, contact: Vector3, yaw: float) -> bool:
	var car := world.car
	car.reset_to(contact, yaw)
	await _frames(2)
	await _drive(&"move_back", &"", 60)
	await _drive(&"move_forward", &"", CAR_ESCAPE)
	return not b.is_intact() and _flat(car.global_position - contact) >= CAR_ESCAPE_MIN

func _breakable_car() -> void:
	var car := world.car
	if world.control_mode != &"in_car":
		world.enter_car()
		await _frames(3)
	var root := world.get_node_or_null("LevelGeometry/Breakables")
	var heavy := _heavy_breakables()
	var stuck := []
	var no_turn := []
	var broken := []
	var rammed_out := []
	var tested := 0
	for b in heavy:
		for side in _heavy_sides(b).slice(0, 4):
			var dir: Vector2 = side[1]
			var start := Vector3(side[0].x - dir.x * (Lada.SIZE.z * 0.5 + 0.3), 0.0, side[0].y - dir.y * (Lada.SIZE.z * 0.5 + 0.3))
			var yaw := _yaw(dir)
			if not _free(start, _car_box(0.1), Lada.SIZE.y * 0.5 + 0.1, yaw) or not _clear_of_breakables(start, yaw):
				continue
			tested += 1
			car_low = 0.0
			car.reset_to(start, yaw)
			await _frames(2)
			await _drive(&"move_forward", &"", CAR_PUSH)
			var contact := car.global_position
			var contact_yaw := car.rotation.y
			if not b.is_intact():
				broken.append("%s broke at slow push" % b.id)
				root.reset_positions()
			if _car_issue() != "":
				broken.append("%s@(%.1f,%.1f)%s" % [b.id, contact.x, contact.z, _car_issue()])
			var rammed := false
			if not await _car_leaves(contact, contact_yaw, CAR_ESCAPE, CAR_ESCAPE_MIN, [&"move_back"]):
				# Сзади нет места (полоса между тяжёлым и коробкой уже машины с запасом выезда, например качели/карусель —
				# оградка Playground, 5,25 / 4,8 м): выход — сдать до упора и разогнаться в объект (≥ 3 м/с — ломается).
				rammed = await _car_rams_out(b, contact, contact_yaw)
				if not rammed:
					stuck.append("%s@(%.1f,%.1f)" % [b.id, contact.x, contact.z])
				else:
					rammed_out.append("%s@(%.1f,%.1f)" % [b.id, contact.x, contact.z])
					root.reset_positions()
			car.reset_to(contact, contact_yaw)
			await _frames(2)
			var side_key := &"move_left" if rng.randf() < 0.5 else &"move_right"
			var other := &"move_right" if side_key == &"move_left" else &"move_left"
			var farthest := 0.0
			Input.action_press(&"move_back")
			Input.action_press(side_key)
			for f in CAR_ESCAPE:
				await physics_frame
				farthest = maxf(farthest, _flat(car.global_position - contact))
			_release_all()
			Input.action_press(&"move_forward")
			Input.action_press(other)
			for f in CAR_ESCAPE:
				await physics_frame
				farthest = maxf(farthest, _flat(car.global_position - contact))
			_release_all()
			await _brake_to_stop()
			if not rammed and (farthest < CAR_MANEUVER_MIN or absf(angle_difference(contact_yaw, car.rotation.y)) < CAR_TURN_MIN):
				no_turn.append("%s@(%.1f,%.1f) %.1fm" % [b.id, contact.x, contact.z, farthest])
			if root:
				root.reset_positions()   # манёвр с рулём мог разогнаться и сломать объект — следующий сценарий с целым
	print("INFO: car heavy breakables %d scenarios, stuck %d, no turn %d, broken %d, rammed out %s" % [tested, stuck.size(), no_turn.size(), broken.size(), rammed_out])
	check(heavy.is_empty() or tested >= heavy.size() * 2, "car scenarios at heavy breakables (%d)" % tested)
	check(stuck.is_empty(), "Lada backs off from heavy breakables (%s)" % [stuck.slice(0, 3)])
	check(no_turn.is_empty(), "Lada steers out from heavy breakables (%s)" % [no_turn.slice(0, 3)])
	check(broken.is_empty(), "slow push leaves heavy breakables intact, Lada on the ground (%s)" % [broken.slice(0, 3)])

# --- часть 4: круг по кольцу (ARENA-01) ---

## Водитель тестов (quest01_driver.gd) ведёт «Ладу» вводом по точкам оси правой полосы: прямые между дугами углов
## подразумеваются, на дугах точки через 15°. Старт — на улице A за углом A∩B, финиш — там же после полного круга.
func _ring_lap() -> void:
	var car := world.car
	if world.control_mode != &"in_car":
		world.enter_car()
	var lane := Layout.ring_lane()
	var corner := 6 + 1   # точек на дугу
	# Точки круга: от конца дуги A∩B — дуги A∩D, C∩D, C∩B, A∩B — и снова до старта.
	var start: Vector3 = lane[corner - 1] + Vector3(-12, 0, 0)
	var points: Array[Vector3] = []
	for i in range(corner, lane.size()):
		points.append(lane[i])
	for i in corner:
		points.append(lane[i])
	points.append(start)
	car.reset_to(start, PI * 0.5)   # на запад по улице A
	await _frames(3)
	var drv = Driver.new(self, world)
	var frames := 0
	var hits := []
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var stuck := 0
	var done := true
	for p in points:
		while drv.steer_to(p, RING_SPEED) > RING_TOL:
			await physics_frame
			frames += 1
			var here := car.global_position
			if car.is_on_wall() and hits.size() < 5:
				hits.append("(%.1f,%.1f)" % [here.x, here.z])
			var stray := _lane_distance(here, lane)
			if stray > worst:
				worst = stray
				worst_at = here
			stuck = stuck + 1 if absf(drv.speed()) < 0.3 else 0
			if stuck > 120 or frames > RING_FRAMES:
				done = false
				break
		if not done:
			break
	drv.release_all()
	await drv.stop()
	print("INFO: ring lap %.1f s, worst lane offset %.2f m at (%.1f,%.1f), wall contacts %s" % [frames / 60.0, worst, worst_at.x, worst_at.z, hits])
	check(done, "Lada drives a full lap of the ring on the right lane without getting stuck (stopped at %s after %.1f s)" % [car.global_position, frames / 60.0])
	check(hits.is_empty(), "ring lap: no wall contact (banks, lamps, parked cars) %s" % [hits])
	check(worst <= RING_STRAY, "ring lap: Lada stays within %.1f m of the lane axis, corners included (%.2f m)" % [RING_STRAY, worst])
	check(_car_issue() == "", "ring lap: Lada ends on the ground, outside solids%s" % _car_issue())

## Расстояние в плане от точки до замкнутой оси полосы (дуги углов и прямые между ними).
func _lane_distance(p: Vector3, lane: Array[Vector3]) -> float:
	var best := INF
	var flat := Vector2(p.x, p.z)
	for i in lane.size():
		var a: Vector3 = lane[i]
		var b: Vector3 = lane[(i + 1) % lane.size()]
		var q := Geometry2D.get_closest_point_to_segment(flat, Vector2(a.x, a.z), Vector2(b.x, b.z))
		best = minf(best, q.distance_to(flat))
	return best

# --- помощники ---

## Держать действия кадры подряд; true, если машина хоть раз упёрлась в стену.
func _drive(action: StringName, steer: StringName, frames: int) -> bool:
	var car := world.car
	Input.action_press(action)
	if steer != &"":
		Input.action_press(steer)
	var hit := false
	for f in frames:
		await physics_frame
		hit = hit or car.is_on_wall()
		car_low = minf(car_low, car.global_position.y)
	_release_all()
	return hit

## Может ли машина уехать с точки: хотя бы одно из действий сдвигает её на min_distance за frames кадров.
func _car_leaves(point: Vector3, yaw: float, frames: int, min_distance: float, actions := [&"move_forward", &"move_back"]) -> bool:
	var car := world.car
	for action in actions:
		car.reset_to(point, yaw)
		await _frames(2)
		await _drive(action, &"", frames)
		if _flat(car.global_position - point) >= min_distance:
			return true
	return false

func _brake_to_stop() -> void:
	var car := world.car
	for f in 120:
		if car.speed_kmh() < 1.0:
			break
		Input.action_press(&"handbrake")
		await physics_frame
	_release_all()
	await _frames(2)

## Пусто, если машина стоит на земле, внутри карты и не сидит в чужой коробке; иначе — причина.
func _car_issue() -> String:
	var car := world.car
	var p := car.global_position
	if not car.is_on_floor() or p.y < -0.05 or p.y > 0.3:
		return " off ground y=%.2f" % p.y
	if not Layout.BOUNDS.has_point(Vector2(p.x, p.z)):
		return " off map"
	if not _free(p, _car_box(-0.3), Lada.SIZE.y * 0.5, car.rotation.y):
		return " inside %s" % _hit_name(p, _car_box(-0.3), Lada.SIZE.y * 0.5, car.rotation.y)
	return ""

func _where(s: Dictionary, p: Vector3) -> String:
	return "%s@(%.1f,%.1f)" % [s.name, p.x, p.z]

func _yaw(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)

func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

func _random_point(margin: float) -> Vector3:
	var b := Layout.BOUNDS
	return Vector3(rng.randf_range(b.position.x + margin, b.end.x - margin), 0.0, rng.randf_range(b.position.y + margin, b.end.y - margin))

func _capsule(radius: float) -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 1.5
	return capsule

## Коробка машины с запасом margin по x/z (отрицательный — меньше машины, для проверки «не в коробке»).
func _car_box(margin: float) -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Lada.SIZE + Vector3(margin * 2.0, -0.2, margin * 2.0)
	return box

func _free(point: Vector3, shape: Shape3D, lift: float, yaw := 0.0) -> bool:
	return _overlaps(point, shape, lift, yaw).is_empty()

## Имя первого пересечённого тела — для отчёта о найденном месте.
func _hit_name(point: Vector3, shape: Shape3D, lift: float, yaw := 0.0) -> String:
	var hits := _overlaps(point, shape, lift, yaw)
	return String(hits[0].collider.name) if not hits.is_empty() else "?"

func _overlaps(point: Vector3, shape: Shape3D, lift: float, yaw: float) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 4
	query.exclude = [world.car.get_rid(), world.player.get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP, yaw), point + Vector3.UP * lift)
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1)

func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"handbrake"]:
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
	print("STUCK: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)

## EXT-01 fix6: тела полицейских у киоска (слой World) включить / выключить.
func _patrol_bodies(on: bool) -> void:
	var patrols := world.get_node_or_null("LevelGeometry/Patrols")
	if patrols == null:
		return
	for npc in [patrols.officer, patrols.officer2]:
		var body: CollisionObject3D = npc.get_node_or_null("Body")
		if body:
			body.collision_layer = 1 if on else 0

# --- часть 2в (PROPS-01): новые неразрушаемые коробки арены ---
## Layout.PROPS_SOLIDS попадают в общий пул части 2 (категория prop), но выборка там случайная — здесь каждая коробка
## проверяется сама: Илюша идёт в середину каждой грани и в каждый угол и отходит; «Лада» упирается носом в середину
## каждой грани (со стартом на CAR_GAP) и выезжает назад, затем назад с рулём и вперёд с обратным рулём, затем задом.
## Отдельно — въезд в хоккейную коробку через проходы 4 м и выезд задом (щели 0 или ≥ 3 м, ARENA-02).

func _props_sides(spec: Array) -> Array:
	var c: Vector2 = spec[2]
	var h := Vector2(spec[3].x, spec[3].z) * 0.5
	var out := []
	for n in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		out.append([c + n * (absf(n.x) * h.x + absf(n.y) * h.y), -n, "face"])
	if minf(h.x, h.y) > 0.3:
		for k in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			out.append([c + k * h, -k.normalized(), "corner"])
	return out

func _props_walk() -> void:
	var player := world.player
	var trapped := []
	var broken := []
	var tested := 0
	for spec in Layout.PROPS_SOLIDS:
		for side in _props_sides(spec):
			var dir: Vector2 = side[1]
			var start := Vector3(side[0].x - dir.x * WALK_RUN, 0.0, side[0].y - dir.y * WALK_RUN)
			if not Layout.BOUNDS.grow(-0.5).has_point(Vector2(start.x, start.z)) or not _free(start, _capsule(0.4), 0.8):
				continue
			tested += 1
			player.place(start, 0.0)
			world.camera_rig.yaw = _yaw(dir)
			await _frames(2)
			Input.action_press(&"move_forward")
			var low := 0.0
			for f in WALK_PUSH:
				await physics_frame
				low = minf(low, player.global_position.y)
			Input.action_release(&"move_forward")
			var contact := player.global_position
			var where := "%s@(%.1f,%.1f)" % [spec[0], contact.x, contact.z]
			if low < -SINK_TOLERANCE or not _free(contact, _capsule(0.25), 0.8):
				broken.append(where)
			var escaped := false
			for e in WALK_ESCAPES:
				var away: Vector2 = (-dir).rotated(e)
				player.place(contact, 0.0)
				world.camera_rig.yaw = _yaw(away)
				await _frames(2)
				Input.action_press(&"move_forward")
				await _frames(WALK_ESCAPE)
				Input.action_release(&"move_forward")
				var p := player.global_position
				if Vector2(p.x - contact.x, p.z - contact.z).dot(away) >= WALK_ESCAPE_MIN:
					escaped = true
					break
			if not escaped:
				trapped.append(where)
	print("INFO: walk props %d boxes, %d scenarios, trapped %d, broken %d %s %s" % [Layout.PROPS_SOLIDS.size(), tested, trapped.size(), broken.size(), trapped.slice(0, 3), broken.slice(0, 3)])
	check(tested >= Layout.PROPS_SOLIDS.size() * 3, "walk scenarios at PROPS-01 boxes (%d)" % tested)
	check(trapped.is_empty(), "Ilyusha walks away from PROPS-01 boxes (%s)" % [trapped.slice(0, 3)])
	check(broken.is_empty(), "Ilyusha stays on the ground and outside PROPS-01 boxes (%s)" % [broken.slice(0, 3)])

func _props_car() -> void:
	var car := world.car
	if world.control_mode != &"in_car":
		world.enter_car()
		await _frames(3)
	var inner := Layout.BOUNDS.grow(-2.5)
	var stuck := []
	var no_turn := []
	var broken := []
	var tested := 0
	for spec in Layout.PROPS_SOLIDS:
		for side in _props_sides(spec):
			if side[2] != "face":
				continue
			var dir: Vector2 = side[1]
			var p2: Vector2 = side[0] - dir * (CAR_GAP + Lada.SIZE.z * 0.5)
			var start := Vector3(p2.x, 0.0, p2.y)
			var yaw := _yaw(dir)
			if not inner.has_point(p2) or not _free(start, _car_box(0.3), Lada.SIZE.y * 0.5 + 0.1, yaw):
				continue
			tested += 1
			car_low = 0.0
			car.reset_to(start, yaw)
			await _frames(2)
			await _drive(&"move_forward", &"", CAR_PUSH)
			var contact := car.global_position
			var contact_yaw := car.rotation.y
			var where := "%s@(%.1f,%.1f)" % [spec[0], contact.x, contact.z]
			if _car_issue() != "":
				broken.append(where + _car_issue())
			if not await _car_leaves(contact, contact_yaw, CAR_ESCAPE, CAR_ESCAPE_MIN, [&"move_back"]):
				stuck.append(where + " nose/back")
			car.reset_to(contact, contact_yaw)
			await _frames(2)
			var side_key := &"move_left" if rng.randf() < 0.5 else &"move_right"
			var other := &"move_right" if side_key == &"move_left" else &"move_left"
			var farthest := 0.0
			Input.action_press(&"move_back")
			Input.action_press(side_key)
			for f in CAR_ESCAPE:
				await physics_frame
				farthest = maxf(farthest, _flat(car.global_position - contact))
			_release_all()
			Input.action_press(&"move_forward")
			Input.action_press(other)
			for f in CAR_ESCAPE:
				await physics_frame
				farthest = maxf(farthest, _flat(car.global_position - contact))
			_release_all()
			await _brake_to_stop()
			if farthest < CAR_MANEUVER_MIN or absf(angle_difference(contact_yaw, car.rotation.y)) < CAR_TURN_MIN:
				no_turn.append(where + " %.1fm" % farthest)
			if _car_issue() != "":
				broken.append(where + " after steer" + _car_issue())
			car.reset_to(start, yaw + PI)
			await _frames(2)
			await _drive(&"move_back", &"", CAR_TAIL_PUSH)
			var tail := car.global_position
			if not await _car_leaves(tail, car.rotation.y, CAR_ESCAPE, CAR_ESCAPE_MIN, [&"move_forward"]):
				stuck.append(where + " tail/forward")
			if car_low < -SINK_TOLERANCE:
				broken.append(where + " sunk %.3f" % car_low)
	print("INFO: car props %d scenarios, stuck %d, no turn %d, broken %d %s %s %s" % [tested, stuck.size(), no_turn.size(), broken.size(), stuck.slice(0, 3), no_turn.slice(0, 3), broken.slice(0, 3)])
	check(tested >= 30, "car scenarios at PROPS-01 boxes (%d)" % tested)
	check(stuck.is_empty(), "Lada backs off / pulls away from PROPS-01 boxes (%s)" % [stuck.slice(0, 3)])
	check(no_turn.is_empty(), "Lada steers out from PROPS-01 boxes (%s)" % [no_turn.slice(0, 3)])
	check(broken.is_empty(), "Lada stays on the ground and outside solids at PROPS-01 boxes (%s)" % [broken.slice(0, 3)])

## Въезд в хоккейную коробку через каждый проход (Layout.RINK_GATE, x 60…64) и выезд задом тем же путём.
func _rink_gates() -> void:
	var car := world.car
	var c: Vector2 = Layout.RINK[0]
	var half: float = Layout.RINK[1].z * 0.5
	var gate_x: float = (Layout.RINK_GATE[0] + Layout.RINK_GATE[1]) * 0.5
	var failed := []
	for side: float in [-1.0, 1.0]:   # −1 — северный борт, +1 — южный
		var outside := Vector3(gate_x, 0.0, c.y + side * (half + 5.0))
		var yaw := 0.0 if side > 0.0 else PI   # носом к центру коробки
		car.reset_to(outside, yaw)
		await _frames(3)
		await _drive(&"move_forward", &"", 75)
		await _brake_to_stop()
		var inside := car.global_position
		var entered: bool = (inside.z - c.y) * side < half - 2.5
		await _drive(&"move_back", &"", 110)
		await _brake_to_stop()
		var back := car.global_position
		var left: bool = (back.z - c.y) * side > half + 1.0
		if not entered or not left or _car_issue() != "":
			failed.append("gate %s: in (%.1f,%.1f) out (%.1f,%.1f)%s" % ["north" if side < 0.0 else "south", inside.x, inside.z, back.x, back.z, _car_issue()])
	print("INFO: rink gates %s" % [failed])
	check(failed.is_empty(), "Lada drives into the hockey rink through both 4 m gates and backs out (%s)" % [failed])

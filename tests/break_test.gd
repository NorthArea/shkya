extends SceneTree
## BREAK-01: разрушаемые объекты на настоящей сцене main.tscn (набор BREAK; контракт — ARENA-02.md, «BREAK-01 контракт»).
## 1. Запасы каждого объекта Layout.BREAKABLES, как в builds/checks/ARENA-02/scripts/check.py: ROUTE_WALK 2, ROUTE_DRIVE
##    и ROUTE_LEAVE_KIOSK 3,5, VAN_PATH 3, полосы кольца 2,5 / 2,3, жители 1,2, SNEAK 1,5, посты 8 (Бабка, спавн и
##    прочие точки — 3), монеты 1, петли дронов 1,5 (у объектов выше 1,6 м); вне KIOSK_SQUARE / ROOF_AREA и проезжей
##    части; у heavy нет щелей 0,05…3 м до коробок all_solids(), края карты и других heavy; light не внутри коробок.
##    Устройство: слой 6 «Breakable» (32), маски «Лады», Илюши и удара его видят, транспорт кольца, автобус ГСУМ,
##    лучи стелса и пружина камеры — нет; облик — MultiMesh по виду, без теней ниже 1 м, детали гаснут дальше 60 м,
##    остаток ниже 0,15 м.
## 2. «Лада» на 5 м/с ломает light и heavy (после heavy скорость × 0,8, тряска камеры); на 0,5 м/с heavy держит её 2 с с
##    газом, light без газа держит, с газом ломается после упора 0,3 с; коллизия выключена в том же кадре; ходьба не ломает.
## 3. Удар Илюши: light — с одного раза, heavy — с трёх (hp 3 → 2 → 1, покачивание), обломки: пул 96, не больше 4 поломок
##    разом, лежат 1,5–3 с и тают; полёт сбитого жителя упирается в целый объект и не упирается в сломанный.
## 4. Восстановление через 60–120 с, только если Илюша и «Лада» дальше 20 м и объект вне кадра; рост 0,5 с.
## 5. После восстановления коллизия на месте и ни с кем не пересекается; на занятое место (Илюша стоит) не возвращается.
## 6. Жители: ближайший ближе 8 м оглядывается и говорит реплику BREAK_LINES, не чаще раза в 15 с на всех, и идёт
##    дальше; квестовая Бабка ближе 15 м — пузырь, не диалог; reset_positions() — всё целое.
##
## Headless: tools/run.command --headless --fixed-fps 60 --script tests/break_test.gd
## Кадры: tools/run.command --fixed-fps 60 --resolution 1920x1080 --script tests/break_test.gd -- --capture
##   → builds/screenshots/BREAK-01/

const Layout = preload("res://game/world/layout.gd")
const Driver = preload("res://tests/playthrough_driver.gd")
const OUT := "res://builds/screenshots/BREAK-01"

var failures: Array[String] = []
var checks := 0
var main: Node
var drv
var world: DemoWorld
var bk: Breakables
var residents_node: Node
var sound: Node
var capture := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(900.0, true, false, true).timeout.connect(func():
		push_error("FAIL: break test exceeded 900 simulated seconds")
		_finish(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	drv = Driver.new(self, main)
	await drv.frames(3)
	main.start_game()
	await drv.frames(10)
	world = main.world
	if not check(world != null, "DemoWorld exists"):
		_finish()
		return
	bk = world.get_node_or_null("LevelGeometry/Breakables")
	if not check(bk != null and bk.is_in_group(Breakables.GROUP_ROOT), "LevelGeometry/Breakables attached, group breakables_root"):
		_finish()
		return
	residents_node = world.get_node_or_null("LevelGeometry/Residents")
	sound = world.get_node("SoundDirector")
	for s in get_nodes_in_group(&"detection_sensors"):
		s.enabled = false
	_part_margins()
	_part_setup()
	await _shot("01_intact_yard", Vector3(-30, 0, 101), Vector3(-0.6, 0, 0.1))
	await _shot("01_intact_playground", Vector3(-59.5, 0, 96.5), Vector3(0, 0, -1))
	await _shot("01_intact_dig", Vector3(20, 0, 44.5), Vector3(0, 0, 1))
	await _part_car()
	await _part_punch()
	await _part_restore()
	await _part_residents()
	await _part_reset()
	_finish()

# --- 1. Запасы и устройство ---

func _part_margins() -> void:
	print("--- margins (check.py rules) ---")
	check(Layout.BREAKABLES.size() == 10, "10 objects in the first step (%d)" % Layout.BREAKABLES.size())
	var lines := []   # [имя, точки Vector2, замкнута, запас]
	lines.append(["ROUTE_WALK", _pts(Layout.ROUTE_WALK), false, 2.0])
	lines.append(["ROUTE_DRIVE", _pts(Layout.ROUTE_DRIVE), false, 3.5])
	lines.append(["ROUTE_LEAVE_KIOSK", _pts(Layout.ROUTE_LEAVE_KIOSK), false, 3.5])
	lines.append(["VAN_PATH", _pts(Layout.VAN_PATH), false, 3.0])
	lines.append(["RING_TROLLEY", _pts(Layout.ring_lane(6.0, 8, false)), true, 2.5])
	lines.append(["RING_CARS", _pts(Layout.ring_lane(4.0, 8, true)), true, 2.3])
	for s in [["SNEAK_EAST", Layout.SNEAK_EAST], ["SNEAK_WEST", Layout.SNEAK_WEST], ["SNEAK_BACK", Layout.SNEAK_BACK], ["SNEAK_AGAIN", Layout.SNEAK_AGAIN]]:
		var pts: Array = []
		for e in s[1]:
			if e is Array:
				pts += _pts(e)
		lines.append([s[0], pts, false, 1.5])
	for i in Layout.RESIDENT_ROUTES.size():
		lines.append(["RESIDENT_%d" % i, _pts(Layout.RESIDENT_ROUTES[i]), Layout.RESIDENT_ROUTES[i].size() > 2, 1.2])
	lines.append(["RIDER_B", _pts(Layout.RESIDENT_RIDER_B_PATH), false, 1.2])
	var loops := []
	for l in Layout.DRONE_LOOPS:
		var pts: Array = []
		for p: Vector2 in l[0]:
			pts.append(p)
		loops.append(pts)
	var posts8 := [Layout.OFFICER_POST, Layout.OFFICER_POST_AFTER, Layout.OFFICER2_POST, Layout.STEALTH_CHECKPOINT, Layout.ACCOUNT_OFFICER]
	var posts3 := [Layout.BABKA, Layout.SPAWN, Layout.CAR_SPAWN, Layout.VENDOR_WINDOW, Layout.VAN_PARK, Layout.TROLLEY_STOPS[0], Layout.TROLLEY_STOPS[1]]
	var heavy_rects := []
	for spec: Array in Layout.BREAKABLES:
		if spec[5] == &"heavy":
			heavy_rects.append([spec[0], Breakables.spec_rect(spec)])
	var b := Layout.BOUNDS
	var bounds := [Rect2(b.position.x - 2, b.position.y, 2, b.size.y), Rect2(b.end.x, b.position.y, 2, b.size.y),
		Rect2(b.position.x, b.position.y - 2, b.size.x, 2), Rect2(b.position.x, b.end.y, b.size.x, 2)]
	var solids := []
	for spec in Layout.all_solids():
		var c: Vector2 = spec[2]
		var size: Vector3 = spec[3]
		solids.append([String(spec[0]), Rect2(c - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))])
	for spec: Array in Layout.BREAKABLES:
		var r := Breakables.spec_rect(spec)
		var h: float = (spec[3] as Vector3).y
		var issues := []
		var nearest := {}
		for line in lines:
			var d := _rect_poly(r, line[1], line[2])
			if d < line[3]:
				issues.append("%s %.2f<%.1f" % [line[0], d, line[3]])
			nearest[line[0]] = d
		if h > 1.6:
			for i in loops.size():
				var d := _rect_poly(r, loops[i], true)
				if d < 1.5:
					issues.append("DRONE_LOOP_%d %.2f" % [i, d])
		for p: Vector3 in posts8:
			if _rect_point(r, Vector2(p.x, p.z)) < 8.0:
				issues.append("post (%.0f,%.0f) %.1f" % [p.x, p.z, _rect_point(r, Vector2(p.x, p.z))])
		for p: Vector3 in posts3:
			if _rect_point(r, Vector2(p.x, p.z)) < 3.0:
				issues.append("point (%.0f,%.0f) %.1f" % [p.x, p.z, _rect_point(r, Vector2(p.x, p.z))])
		for p: Vector3 in Layout.COIN_POINTS:
			if _rect_point(r, Vector2(p.x, p.z)) < 1.0:
				issues.append("coin (%.1f,%.1f)" % [p.x, p.z])
		if r.intersects(Layout.KIOSK_SQUARE) or r.intersects(Layout.ROOF_AREA):
			issues.append("in KIOSK_SQUARE/ROOF_AREA")
		for s in Layout.SURFACES:
			if s[1] == "road":
				var sc: Vector2 = s[2]
				var ss: Vector2 = s[3]
				if Rect2(sc - ss * 0.5, ss).has_point(spec[2]):
					issues.append("on road %s" % s[0])
		if spec[5] == &"heavy":
			for other in solids + heavy_rects.filter(func(o): return o[0] != spec[0]).map(func(o): return [String(o[0]), o[1]]) \
					+ bounds.map(func(br): return ["Bound", br]):
				var g := _rect_gap(r, other[1])
				if g > 0.05 and g < 3.0:
					issues.append("gap %.2f to %s" % [g, other[0]])
				elif g == 0.0 and _overlap_area(r, other[1]) > 0.0001:
					issues.append("overlaps %s" % other[0])
		else:
			for s in solids:
				if _overlap_area(r, s[1]) > 0.0001:
					issues.append("inside %s" % s[0])
		var close := []
		for k in nearest:
			if nearest[k] < 6.0:
				close.append("%s %.1f" % [k, nearest[k]])
		print("INFO: %s %s %s at (%.2f; %.2f) %s: near %s" % [spec[0], spec[5], spec[1], spec[2].x, spec[2].y, spec[3], ", ".join(close)])
		check(issues.is_empty(), "%s keeps the check.py margins %s" % [spec[0], issues])

func _part_setup() -> void:
	print("--- setup ---")
	check(ProjectSettings.get_setting("layer_names/3d_physics/layer_6") == "Breakable" and Breakables.LAYER == 32, "physics layer 6 «Breakable» = 32")
	check(bk.objects.size() == Layout.BREAKABLES.size() and get_nodes_in_group(Breakables.GROUP).size() == Layout.BREAKABLES.size(), "one Breakable per record (%d)" % bk.objects.size())
	var bad := []
	for b: Breakables.Breakable in bk.objects:
		if b.body.collision_layer != 32 or b.body.collision_mask != 0 or not b.is_intact() or b.hp != (3 if b.heavy else 1):
			bad.append(b.id)
	check(bad.is_empty(), "every object: StaticBody3D layer 32, mask 0, intact, hp 1 / 3 (bad %s)" % [bad])
	var car: Lada = world.car
	check(car.collision_mask & 32 != 0 and world.player.collision_mask & 32 != 0 and Ilyusha.PUNCH_MASK & 32 != 0, "Lada, Ilyusha and the punch see layer 32")
	check(PathVehicle.SENSOR_MASK & 32 == 0 and CityVan.OBSTACLE_MASK & 32 == 0, "ring traffic sensors and the GSUM van do not see layer 32")
	check((DetectionSensor.WORLD_MASK | DetectionSensor.SIGHT_CAR_MASK) & 32 == 0 and world.camera_rig.arm.collision_mask & 32 == 0, "stealth rays and the camera spring arm ignore layer 32")
	var mms := bk.find_children("MM_*", "MultiMeshInstance3D", false, false)
	var kinds := {}
	var shadow_bad := []
	for node: MultiMeshInstance3D in mms:
		var kind := String(node.name).split("_")[1]
		kinds[kind] = true
	for b: Breakables.Breakable in bk.objects:
		if b.size.y < 1.0:
			for node: MultiMeshInstance3D in mms:
				if String(node.name).begins_with("MM_%s_" % b.kind) and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shadow_bad.append(node.name)
	check(kinds.size() == 7, "MultiMesh per kind: %s (%d instances nodes)" % [kinds.keys(), mms.size()])
	check(shadow_bad.is_empty(), "no shadows on objects lower than 1 m (%s)" % [shadow_bad])
	var detail_ok := true
	for node: MultiMeshInstance3D in mms:
		if String(node.name).ends_with("_detail") and node.visibility_range_end != Breakables.FAR_DETAIL:
			detail_ok = false
	check(detail_ok, "small details fade beyond 60 m (visibility_range_end)")
	var tall := {}
	for kind in [&"bin", &"planter", &"snowman", &"seesaw", &"carousel", &"barrier", &"cones"]:
		var top := 0.0
		for part: Array in Breakables.Looks.parts(kind, _size_of(kind)):
			if part[4] == "remnant" or part[4] == "base":
				var xf: Transform3D = part[1]
				var half := 0.125 if part[0] == "torus" else 0.5
				var aabb := xf * AABB(Vector3(-0.5, -half, -0.5), Vector3(1.0, half * 2.0, 1.0))
				top = maxf(top, aabb.end.y)
		tall[kind] = snappedf(top, 0.001)
	check(tall.values().all(func(t): return t < 0.15), "remnants lower than 0.15 m %s" % [tall])
	check(bk.debris_count() == 0 and bk._debris.size() == Breakables.DEBRIS_POOL and bk._debris_mm.instance_count == 96, "debris pool: one MultiMesh, 96 instances, empty")

func _size_of(kind: StringName) -> Vector3:
	for spec in Layout.BREAKABLES:
		if spec[1] == kind:
			return spec[3]
	return Vector3.ONE

# --- 2. «Лада» ---

func _part_car() -> void:
	print("--- car ---")
	var car: Lada = world.car
	world.enter_car()
	await drv.frames(5)
	# light на 5 м/с: конус 1 с юга (-z вперёд)
	var cone: Breakables.Breakable = bk.get_by_id(&"Z7_cone1")
	var res := await _ram(cone, Vector3(0, 0, 1), 5.0)
	check(res[0] >= 0 and not cone.is_intact() and cone.last_by == &"car", "Lada at 5 m/s breaks light %s (frame %d)" % [cone.id, res[0]])
	check(res[1] > 4.8, "light: no slowdown after the break (%.2f m/s)" % res[1])
	check(res[2], "collision off in the same physics frame as the break (layer %d)" % cone.body.collision_layer)
	check(bk.debris_count() > 0 and bk.debris_breaks() == 1, "debris flies (%d pieces)" % bk.debris_count())
	if capture:
		await _capture_at("03_debris_cone", car.global_position + Vector3(-5, 0, -2), cone.global_position)
	await drv.frames(30)
	# heavy на 5 м/с: качели с севера (+z → -z)
	var seesaw: Breakables.Breakable = bk.get_by_id(&"Z3_seesaw")
	var played: int = sound.played["break"]
	res = await _ram(seesaw, Vector3(0, 0, -1), 5.0, true)
	check(res[0] >= 0 and not seesaw.is_intact(), "Lada at 5 m/s breaks heavy %s (frame %d)" % [seesaw.id, res[0]])
	check(res[1] > 3.7 and res[1] < 4.2, "heavy: speed × 0.8 after the hit (%.2f m/s)" % res[1])
	check(res[3], "camera shakes after the heavy hit")
	check(sound.played["break"] > played and sound.played["break_wood"] > 0, "break sound (wood) played")
	if capture:
		await _capture_at("02_car_hit_seesaw", car.global_position + Vector3(4, 0, 5), seesaw.global_position)
		await drv.frames(50)
		await _capture_at("04_remnant_seesaw", seesaw.global_position + Vector3(2.5, 0, 4.0), seesaw.global_position)
	# heavy на 0,5 м/с с газом держит «Ладу»
	var carousel: Breakables.Breakable = bk.get_by_id(&"Z3_carousel")
	var start := carousel.global_ground() + Vector3(0, 0, carousel.size.z * 0.5 + Lada.SIZE.z * 0.5 + 0.6)
	car.reset_to(start, 0.0)
	await drv.frames(2)
	Input.action_press(&"move_forward")
	var closest := INF
	for i in 120:
		car.velocity = Vector3(0, 0, -0.5) + Vector3(0, car.velocity.y, 0)
		await physics_frame
		closest = minf(closest, car.global_position.z - carousel.global_ground().z)
	Input.action_release(&"move_forward")
	check(carousel.is_intact(), "heavy at 0.5 m/s with throttle for 2 s stays (state %s)" % carousel.state)
	check(closest > carousel.size.z * 0.5 + Lada.SIZE.z * 0.5 - 0.1, "heavy holds the Lada like a wall (closest %.2f m)" % closest)
	# light на 0,5 м/с без газа держит, с газом — ломается после 0,3 с упора
	var cone2: Breakables.Breakable = bk.get_by_id(&"Z7_cone2")
	start = cone2.global_ground() + Vector3(0, 0, -(cone2.size.z * 0.5 + Lada.SIZE.z * 0.5 + 0.3))
	car.reset_to(start, PI)
	await drv.frames(2)
	for i in 60:
		car.velocity = Vector3(0, 0, 0.5)
		await physics_frame
	check(cone2.is_intact(), "light at 0.5 m/s without throttle does not break")
	var touch := -1
	var broke := -1
	Input.action_press(&"move_forward")
	for i in 90:
		car.velocity = Vector3(0, 0, 0.5)
		await physics_frame
		if touch < 0 and _touching(car, cone2):
			touch = i
		if broke < 0 and not cone2.is_intact():
			broke = i
			break
	Input.action_release(&"move_forward")
	var pushed := (broke - touch) / 60.0
	check(broke >= 0 and pushed >= Breakables.PUSH_SECONDS - 0.02 and pushed <= Breakables.PUSH_SECONDS + 0.15, "light breaks after pushing with throttle %.2f s (touch %d, broke %d)" % [pushed, touch, broke])
	# Реакции без разрушения: толчок припаркованной машины ≥ 2 м/с — сигнализация, дворового контейнера — крышки.
	var alarms: int = sound.played["car_alarm"]
	car.reset_to(Vector3(0.6, 0, 66.0), -PI * 0.5)   # к машине (5; 66) с запада, носом на восток
	await drv.frames(2)
	for i in 60:
		car.velocity = Vector3(3.0, car.velocity.y, 0)
		await physics_frame
		if bk.alarms > 0:
			break
	check(bk.alarms == 1 and bk.alarm_on(7) and sound.played["car_alarm"] == alarms + 1, "bumping a parked car at 3 m/s starts its alarm (alarms %d)" % bk.alarms)
	await drv.frames(int(Breakables.ALARM_SECONDS * 60) + 10)
	check(not bk.alarm_on(7), "the alarm stops after 6 s")
	var lids: int = sound.played["bin_lid"]
	car.reset_to(Vector3(-33.0, 0, 69.6), 0.0)   # к контейнерам (−33; 65,5) с юга, носом на −z
	await drv.frames(2)
	for i in 60:
		car.velocity = Vector3(0, car.velocity.y, -2.0)
		await physics_frame
		if bk.lid_slams > 0:
			break
	check(bk.lid_slams >= 1 and sound.played["bin_lid"] > lids, "bumping the yard bins slams the lids (%d)" % bk.lid_slams)
	_park()
	world.exit_car()
	await drv.frames(5)
	# ходьба не ломает: Илюша идёт в урну 2 с
	var bin: Breakables.Breakable = bk.get_by_id(&"Z1_bin")
	var player := world.player
	player.place(bin.global_ground() + Vector3(0, 0, -1.5), PI)
	world.camera_rig.yaw = 0.0
	await drv.frames(5)
	await _walk_dir(Vector3(0, 0, 1), 120)
	check(bin.is_intact() and player.global_position.z < bin.global_ground().z - bin.size.z * 0.5, "walking into the bin does not break it and it blocks (z %.2f)" % player.global_position.z)

## Подвести «Лаю» к объекту по dir и держать скорость speed; [кадр поломки, скорость сразу после, коллизия выключена
## в кадре поломки, камера тряслась].
func _ram(b: Breakables.Breakable, dir: Vector3, speed: float, heavy := false, max_frames := 90) -> Array:
	var car: Lada = world.car
	var half := absf(dir.x) * b.size.x * 0.5 + absf(dir.z) * b.size.z * 0.5
	car.reset_to(b.global_ground() - dir * (half + Lada.SIZE.z * 0.5 + 1.2), atan2(-dir.x, -dir.z))
	world.camera_rig.yaw = car.rotation.y
	world.camera_rig.snap()
	await physics_frame
	for i in max_frames:
		car.velocity = dir * speed + Vector3(0, car.velocity.y, 0)
		await physics_frame
		if not b.is_intact():
			var after := Vector2(car.velocity.x, car.velocity.z).length()
			var off := b.body.collision_layer == 0 and _query(b.global_ground() + Vector3.UP * 0.4, 32).is_empty()
			var shook := bk.shake_left > 0.0
			if heavy:
				await process_frame
				shook = shook and world.camera_rig.camera.h_offset != 0.0
			return [i, after, off, shook]
	return [-1, 0.0, false, false]

func _touching(car: Lada, b: Breakables.Breakable) -> bool:
	for i in car.get_slide_collision_count():
		var c := car.get_slide_collision(i).get_collider()
		if c == b.body:
			return true
	return false

func _query(at: Vector3, mask: int) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.15
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = mask
	return world.get_world_3d().direct_space_state.intersect_shape(q, 4)

func _walk_dir(dir: Vector3, frames: int) -> void:
	world.camera_rig.yaw = atan2(-dir.x, -dir.z)
	Input.action_press(&"move_forward")
	await drv.frames(frames)
	Input.action_release(&"move_forward")

func _park() -> void:
	world.car.reset_to(Layout.CAR_SPAWN, Layout.CAR_SPAWN_YAW)

# --- 3. Удар ---

func _part_punch() -> void:
	print("--- punch ---")
	var player := world.player
	var bin: Breakables.Breakable = bk.get_by_id(&"Z1_bin")
	await _wait_until(func(): return bk.debris_count() == 0, 6 * 60)   # обломки прошлых поломок растаяли
	player.place(bin.global_ground() + Vector3(0, 0, -1.0), PI)   # лицом на +z, к урне
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await drv.frames(10)
	check(player.punch(), "punch the bin")
	await drv.frames(25)
	check(not bin.is_intact() and bin.last_by == &"punch" and bin.hits == 1, "light breaks with one punch (state %s, hits %d)" % [bin.state, bin.hits])
	var spawned := bk.debris_count()
	check(spawned >= 8 and spawned <= Breakables.DEBRIS_PER_BREAK, "bin debris %d pieces (≤ 24 per break)" % spawned)
	var pieces := bk.debris_pieces()
	var low := pieces.all(func(p): return (p[0] as Vector3).y > -0.01)
	check(low, "debris above the snow")
	await drv.frames(int(1.6 * 60))
	check(bk.debris_count() == spawned, "debris still lies on the snow after 1.6 s (%d of %d)" % [bk.debris_count(), spawned])
	check(bk.debris_pieces().all(func(p): return p[2]), "all pieces landed")
	await drv.frames(int(2.6 * 60))
	check(bk.debris_count() == 0, "debris melted within 4.2 s (%d left)" % bk.debris_count())
	# heavy: карусель с трёх ударов
	var carousel: Breakables.Breakable = bk.get_by_id(&"Z3_carousel")
	player.place(carousel.global_ground() + Vector3(0, 0, 1.9), 0.0)   # лицом на −z
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await drv.frames(10)
	var wobbles: int = sound.played["break_wobble"]
	for k in 3:
		check(player.punch(), "punch %d at the carousel" % (k + 1))
		await drv.frames(10)
		if k < 2:
			check(carousel.is_intact() and carousel.hp == 2 - k and carousel._wobble > 0.0, "heavy after punch %d: intact, hp %d, wobbles" % [k + 1, carousel.hp])
			if capture and k == 0:
				await _capture_at("06_punch_carousel", player.global_position + Vector3(2.5, 0, 3.0), carousel.global_position)
		await drv.frames(25)
	check(not carousel.is_intact() and carousel.hits == 3 and carousel.last_by == &"punch", "heavy breaks with the third punch (state %s, hits %d)" % [carousel.state, carousel.hits])
	check(sound.played["break_wobble"] >= wobbles + 2, "wobble sound on the first two punches")
	# не больше 4 поломок разом: ломаем 4 конуса и клумбу подряд
	bk.reset_positions()
	await drv.frames(2)
	for id in [&"Z7_cone1", &"Z7_cone2", &"Z7_cone3", &"Z7_cone4", &"Z1_planter"]:
		bk.get_by_id(id).smash(&"test", Vector3.FORWARD)
		await drv.frames(2)
	check(bk.debris_breaks() <= Breakables.DEBRIS_MAX_BREAKS and bk.debris_count() <= Breakables.DEBRIS_POOL, "at most 4 breaks give debris at once (%d breaks, %d pieces)" % [bk.debris_breaks(), bk.debris_count()])
	bk.reset_positions()
	await drv.frames(2)
	# полёт сбитого жителя упирается в целый объект
	var cone3: Breakables.Breakable = bk.get_by_id(&"Z7_cone3")
	var from := Vector3(cone3.center.x, 0, cone3.center.y - 5.0)
	var cut := Resident.flight_distance(from, Vector3(0, 0, 1), 9.0)
	check(cut < 5.0 - cone3.size.z * 0.5 - Resident.BODY_RADIUS - Resident.KNOCK_SOLID_PAD + 0.01, "knocked resident flight stops before an intact object (%.2f m)" % cut)
	cone3.smash(&"test", Vector3.FORWARD)
	check(Resident.flight_distance(from, Vector3(0, 0, 1), 7.0) > 6.9, "and flies over a broken one (%.2f of 7 m)" % Resident.flight_distance(from, Vector3(0, 0, 1), 7.0))
	bk.reset_positions()

# --- 4–5. Восстановление ---

func _part_restore() -> void:
	print("--- restore ---")
	var player := world.player
	var cone: Breakables.Breakable = bk.get_by_id(&"Z7_cone1")
	player.place(cone.global_ground() + Vector3(0, 0, -1.0), PI)
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await drv.frames(5)
	player.punch()
	await drv.frames(20)
	check(not cone.is_intact(), "cone broken for the restore check")
	check(cone.restore_left >= 59.0 and cone.restore_left <= 120.0, "restore delay 60–120 s (%.1f)" % cone.restore_left)
	if capture:
		await drv.frames(60)
		await _capture_at("04_remnant_cone", cone.global_position + Vector3(-2.0, 0, -2.5), cone.global_position)
	cone.restore_left = 0.05
	await drv.frames(90)
	check(not cone.is_intact(), "no restore while Ilyusha is within 20 m")
	var far := cone.global_ground() + Vector3(-10.5, 0, 22.0)   # 24 м
	var to := (cone.global_ground() - far).normalized()
	player.place(far, atan2(-to.x, -to.z))
	world.camera_rig.yaw = atan2(-to.x, -to.z)
	world.camera_rig.snap()
	await drv.frames(10)
	check(bk.in_view(cone), "the cone is in the camera frustum from 24 m")
	await drv.frames(150)
	check(not cone.is_intact(), "no restore while the object is in view (state %s)" % cone.state)
	world.camera_rig.yaw = atan2(to.x, to.z)
	world.camera_rig.snap()
	var grew := -1
	for i in 180:
		await physics_frame
		if cone.state == &"growing" and grew < 0:
			grew = i
		if cone.is_intact():
			break
	check(cone.is_intact() and cone.restores == 1, "restored once far away and out of view (growth from frame %d)" % grew)
	check(not bk.in_view(cone), "restored out of the frame")
	# 5. коллизия вернулась, ни с кем не пересекается
	check(cone.body.collision_layer == 32 and not (cone.body.get_child(0) as CollisionShape3D).disabled, "collision back after restore")
	check(bk.overlaps(cone).is_empty() and _box_hits(cone, 1 | 2 | 4).is_empty(), "restored box overlaps nobody (Ilyusha, Lada, residents, world)")
	if capture:
		await _capture_at("05_restored_cone", cone.global_position + Vector3(-2.0, 0, -2.5), cone.global_position)
	# занятое место: Илюша стоит на месте сломанного конуса — не восстанавливается
	var cone4: Breakables.Breakable = bk.get_by_id(&"Z7_cone4")
	cone4.smash(&"test", Vector3.FORWARD)
	player.place(cone4.global_ground(), 0.0)
	await drv.frames(5)
	check(not bk.place_free(cone4), "a body on the spot blocks the restore")
	bk.reset_positions()
	player.place(Layout.SPAWN, Layout.SPAWN_YAW)
	await drv.frames(5)

func _box_hits(b: Breakables.Breakable, mask: int) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = b.body_size() - Vector3(0.1, 0.1, 0.1)
	q.shape = box
	q.transform = b.base_xf() * Transform3D(Basis.IDENTITY, Vector3(0, b.body_size().y * 0.5, 0))
	q.collision_mask = mask
	q.exclude = [b.body.get_rid()]
	return world.get_world_3d().direct_space_state.intersect_shape(q, 4)

# --- 6. Жители и Бабка ---

func _part_residents() -> void:
	print("--- residents ---")
	if not check(residents_node != null, "Residents attached"):
		return
	residents_node.reset_positions()
	var r: Resident = residents_node.residents[0]   # двор H1, z 103,4, от x −36 на восток
	var snowman: Breakables.Breakable = bk.get_by_id(&"Z1_snowman")
	var player := world.player
	player.place(snowman.global_ground() + Vector3(0, 0, -1.0), PI)   # лицом на +z
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await _wait_until(func(): return absf(r.global_position.x - snowman.center.x) < 3.0 and r.state == &"walk", 40 * 60)
	var glances := r.glance_count
	var bubbles: int = residents_node.break_bubbles
	var walked := r.distance_walked
	player.punch()
	await drv.frames(20)
	check(not snowman.is_intact(), "snowman broken by a punch near resident 0")
	check(r.glance_count > glances and r.state == &"glance", "resident within 8 m glances at the break (state %s)" % r.state)
	var lines := []
	for l in QuestLines.BREAK_LINES:
		lines.append(l["text"])
	check(r.bubble_kind == &"break" and r.bubble_text in lines and r.bubble_visible(), "resident says a BREAK_LINES line «%s»" % r.bubble_text)
	check(residents_node.break_bubbles == bubbles + 1, "one break bubble")
	if capture:
		await _capture_at("07_resident_reacts", snowman.global_position + Vector3(4.0, 0, -4.0), r.global_position)
	await drv.frames(6 * 60)
	check(r.distance_walked > walked + 2.0 and r.state != &"glance", "resident walks on after the glance (+%.1f m)" % (r.distance_walked - walked))
	# через ≤ 15 с — новой реплики нет; Бабка ближе 15 м — пузырь
	var bin: Breakables.Breakable = bk.get_by_id(&"Z1_bin")
	player.place(bin.global_ground() + Vector3(0, 0, -1.0), PI)
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await drv.frames(10)
	player.punch()
	await drv.frames(20)
	check(not bin.is_intact(), "bin broken near Babka")
	check(residents_node.break_bubbles == bubbles + 1, "no second resident break bubble within 15 s")
	check(bk.babka_bubble_text() == QuestLines.break_line(&"babka", 0) and bk.babka_bubbles == 1, "Babka within 15 m: bubble «%s»" % bk.babka_bubble_text())
	check(not world.quest_flow.is_dialog_open(), "Babka's reaction is a bubble, not a dialog")
	if capture:
		await _capture_at("07_babka_reacts", Layout.BABKA + Vector3(5.0, 0, -5.0), Layout.BABKA)
	var stuck := []
	await drv.frames(10 * 60)
	for res: Resident in residents_node.residents:
		if res.state == &"walk" and res.speed > 0.0:
			pass
	for res: Resident in residents_node.residents:
		for b: Breakables.Breakable in bk.objects:
			if b.blocks() and b.rect().grow(Resident.BODY_RADIUS).has_point(Vector2(res.global_position.x, res.global_position.z)):
				stuck.append([res.name, b.id])
	check(stuck.is_empty(), "no resident inside an intact object (%s)" % [stuck])

# --- reset ---

func _part_reset() -> void:
	print("--- reset ---")
	for b: Breakables.Breakable in bk.objects:
		b.smash(&"test", Vector3.FORWARD)
	bk.reset_positions()
	var intact: Array = bk.objects.filter(func(b): return b.is_intact() and b.body.collision_layer == 32)
	check(intact.size() == bk.objects.size() and bk.debris_count() == 0 and bk.breaks == 0, "reset_positions(): all intact, no debris, counters zero")

# --- кадры ---

func _shot(name: String, at: Vector3, look: Vector3) -> void:
	if not capture:
		return
	await _capture_at(name, at, at + look * 5.0)

## Кадр с камеры, поставленной в at на высоте 1,7 м и смотрящей на target.
func _capture_at(name: String, at: Vector3, target: Vector3) -> void:
	if not capture:
		return
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = at + Vector3.UP * 1.7
	cam.look_at(target + Vector3.UP * 0.6, Vector3.UP)
	cam.fov = 60.0
	cam.current = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, name]))
	print("INFO: frame %s/%s.png" % [OUT, name])
	cam.current = false
	cam.queue_free()
	world.camera_rig.camera.current = true

# --- геометрия ---

func _pts(a: Array) -> Array:
	var out := []
	for p in a:
		out.append(Vector2(p.x, p.z) if p is Vector3 else p)
	return out

func _rect_point(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()

func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - a.end.y, a.position.y - b.end.y), 0.0)
	return Vector2(dx, dz).length()

func _overlap_area(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.get_area() if a.intersects(b) else 0.0

## Расстояние от прямоугольника до ломаной (точно: отрезок пересекает — 0, иначе минимум концов и углов).
func _rect_poly(r: Rect2, pts: Array, closed: bool) -> float:
	if pts.size() == 1:
		return _rect_point(r, pts[0])
	var best := INF
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var n := pts.size() if closed else pts.size() - 1
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		if _seg_hits_rect(a, b, r):
			return 0.0
		best = minf(best, minf(_rect_point(r, a), _rect_point(r, b)))
		for c: Vector2 in corners:
			best = minf(best, c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)))
	return best

func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false

func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await physics_frame
	return false

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		print("FAIL: ", label)
	return condition

func _finish(code := -1) -> void:
	print("BREAK: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	quit(code if code >= 0 else (0 if failures.is_empty() else 1))

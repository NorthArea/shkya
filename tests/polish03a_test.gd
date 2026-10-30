extends SceneTree
## POLISH-03 A — читаемость (критик 30.10, рекомендации 1, 3, 4, 8). Проверки:
## 1. Посты у киоска предупреждают о развороте за PatrolNpc.WARN_LEAD с — сигнал до начала поворота; субтитр, если
##    следующий угол накроет Илюшу; силуэт сквозь стены — только ближе XRAY_RADIUS.
## 2. Мини-карта: конусы обзора — только у постов (PatrolNpc) и только в районе киоска.
## 3. Короб «ХЛЕБ» на крыше киоска смотрит на юг и виден с парковки (луч по World и валам свободен); ромб «Доедь до
##    киоска» — над ним.
## 5. Камера диалога (владелец 30.10: «у Бабки и продавщицы камера застревает и дёргается»): поворот к говорящему и
##    возврат — без рывков (изменение шага камеры между кадрами ≤ TALK_DSTEP м и ≤ TALK_DTURN°), доходит до цели.
## 4. Ромб цели подписан расстоянием в метрах; «!» над Бабкой покачивается, с ореолом и издалека крупнее.
## Честный путь не проще: удержания углов постов те же (их проверяет STEALTH, здесь — что предупреждение их не сдвигает).
## Итог — строка «POLISH03A: N checks, M failures».

const Layout = preload("res://game/world/layout.gd")
const HudScript = preload("res://game/ui/game_hud.gd")
const PatrolNpcScript = preload("res://game/npc/patrol_npc.gd")
const XRAY_NEAR := Vector3(66.0, 0.0, -78.0)

var failures: Array[String] = []
var checks := 0
var main: Node
var world: DemoWorld
var hud: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func():
		push_error("FAIL: polish03a test exceeded 240 simulated seconds")
		quit(2))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.menu.start_button.pressed.emit()
	await _frames(20)
	world = main.world
	hud = world.get_node("GameHUD")
	await _markers()
	await _talk_camera_babka()
	await _diamond_meters()
	await _kiosk_sign()
	await _minimap_cones()
	await _talk_camera_vendor()
	await _turn_warning()
	_finish()

# --- 4. маркер над Бабкой ---

func _markers() -> void:
	print("--- marker ---")
	var flow: Node = world.get_node("QuestFlow")
	var rig: CameraRig = world.camera_rig
	world.player.place(Layout.BABKA + Vector3(0, 0, -6), 0.0)
	rig.yaw = 0.0
	rig.snap()
	await _frames(10)
	check(flow.marker.visible and flow.marker.text == "!", "marker: ! above Babka at start")
	check(flow.marker_halo != null and flow.marker_halo.get_parent() == flow.marker and flow.marker_halo.no_depth_test, "marker: soft halo behind ! (child, through walls)")
	var ys := []
	var near_px := []
	for i in 60:
		await process_frame
		ys.append(flow.marker.position.y)
		near_px.append(flow.marker.pixel_size)
	check(ys.max() - ys.min() > 0.2, "marker: bobs (%.2f m)" % (ys.max() - ys.min()))
	check(near_px.min() >= 0.0075, "marker: bigger than before (pixel %.4f ≥ 0.0075, was 0.006)" % near_px.min())
	world.player.place(Layout.BABKA + Vector3(14, 0, -26), 0.0)
	rig.snap()
	await _frames(10)
	var far: float = flow.marker_distance_scale()
	check(far > 1.8 and flow.marker.pixel_size > near_px.max() * 1.6, "marker: grows with distance to stay readable (scale %.2f, pixel %.4f)" % [far, flow.marker.pixel_size])

# --- 5. камера диалога ---

const TALK_DSTEP := 0.03    # м/кадр: изменение шага положения камеры между соседними кадрами
const TALK_DTURN := 0.4     # °/кадр: изменение шага поворота
var _cam_log: Array = []

func _record(frames: int) -> void:
	for i in frames:
		await physics_frame
		_cam_log.append(world.camera_rig.camera.global_transform)

## Наибольшие шаг и изменение шага камеры по журналу [м, °, Δм, Δ°].
func _cam_jerk() -> Array:
	var out := [0.0, 0.0, 0.0, 0.0]
	var prev_step := -1.0
	var prev_turn := 0.0
	for i in range(1, _cam_log.size()):
		var a: Transform3D = _cam_log[i - 1]
		var b: Transform3D = _cam_log[i]
		var step := a.origin.distance_to(b.origin)
		var turn := rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()))
		out[0] = maxf(out[0], step)
		out[1] = maxf(out[1], turn)
		if prev_step >= 0.0:
			out[2] = maxf(out[2], absf(step - prev_step))
			out[3] = maxf(out[3], absf(turn - prev_turn))
		prev_step = step
		prev_turn = turn
	return out

func _talk_series(label: String, open: Callable, close: Callable) -> void:
	var rig: CameraRig = world.camera_rig
	await _frames(20)
	var yaw0 := rig.yaw
	_cam_log.clear()
	await _record(5)
	open.call()
	await _record(85)
	var j := _cam_jerk()
	print("INFO: %s open — step ≤ %.3f m, turn ≤ %.2f°, Δstep ≤ %.3f, Δturn ≤ %.2f°" % [label, j[0], j[1], j[2], j[3]])
	check(j[2] <= TALK_DSTEP and j[3] <= TALK_DTURN, "talk camera: %s — one smooth turn, no jerks (Δstep %.3f m, Δturn %.2f°)" % [label, j[2], j[3]])
	check(rig.is_talk_framing() and absf(angle_difference(rig.yaw, rig._talk_goal.x)) < 0.01, "talk camera: %s — reached its framing, not stuck (yaw %.3f, goal %.3f)" % [label, rig.yaw, rig._talk_goal.x])
	_cam_log.clear()
	await _record(5)
	close.call()
	await _record(85)
	j = _cam_jerk()
	print("INFO: %s close — step ≤ %.3f m, turn ≤ %.2f°, Δstep ≤ %.3f, Δturn ≤ %.2f°" % [label, j[0], j[1], j[2], j[3]])
	check(j[2] <= TALK_DSTEP and j[3] <= TALK_DTURN, "talk camera: %s — smooth return (Δstep %.3f m, Δturn %.2f°)" % [label, j[2], j[3]])
	check(not rig.is_talk_framing() and absf(angle_difference(rig.yaw, yaw0)) < 0.01, "talk camera: %s — back to the previous view (%.3f vs %.3f)" % [label, rig.yaw, yaw0])

func _press_interact() -> void:
	var down := InputEventAction.new()
	down.action = &"interact"
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = &"interact"
	Input.parse_input_event(up)

func _talk_camera_babka() -> void:
	print("--- talk camera: Babka ---")
	var flow: Node = world.get_node("QuestFlow")
	# Камера смотрит от подъезда во двор — разворот почти на 180°, мимо скамейки и машин у подъезда.
	world.player.place(Layout.BABKA + Vector3(0.6, 0, -2.0), 0.0)
	world.camera_rig.yaw = 0.3
	world.camera_rig.snap()
	await _talk_series("Babka", func(): _press_interact(), func(): flow.dialog.buttons[&"decline"].pressed.emit())
	check(world.mission.state == MissionDirector.NOT_STARTED, "talk camera: Babka offer declined, mission untouched")

func _talk_camera_vendor() -> void:
	print("--- talk camera: vendor ---")
	var flow: Node = world.get_node("QuestFlow")
	world.stealth.grant_grace(60.0)
	world.player.place(Layout.VENDOR_WINDOW, 0.0)
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await _talk_series("vendor", func(): _press_interact(), func(): flow._on_choice(&"leave"))
	check(world.mission.state == MissionDirector.BUY_BREAD, "talk camera: vendor dialog left, mission BUY_BREAD")

# --- 4. ромб с расстоянием ---

func _diamond_meters() -> void:
	print("--- diamond ---")
	var m := world.mission
	m.interact(&"babka")
	m.accept()
	m.notify_entered_car()
	check(m.state == MissionDirector.DRIVE_TO_KIOSK, "diamond: mission DRIVE_TO_KIOSK")
	world.player.place(Layout.SPAWN, 0.0)
	world.camera_rig.yaw = PI
	world.camera_rig.snap()
	await _frames(6)
	var hero := Vector2(world.player.global_position.x, world.player.global_position.z)
	var expected := "%d м" % roundi(hero.distance_to(Vector2(Layout.KIOSK.x, Layout.KIOSK.z)))
	check(hud.diamond_visible and hud.diamond_clamped, "diamond: target far behind — diamond on the edge")
	check(hud.diamond_distance_text == expected, "diamond: distance in metres '%s' (expected '%s')" % [hud.diamond_distance_text, expected])
	var anchor: Vector3 = HudScript.diamond_anchor(Layout.KIOSK)
	var sign_top := Layout.KIOSK_ROOF_SIGN.y + Layout.KIOSK_ROOF_SIGN_SIZE.y * 0.5
	check(anchor.y > sign_top + 0.5 and Vector2(anchor.x - Layout.KIOSK_ROOF_SIGN.x, anchor.z - Layout.KIOSK_ROOF_SIGN.z).length() < 0.01, "diamond: «Доедь до киоска» — above the roof sign (%s)" % anchor)
	check(HudScript.diamond_anchor(Layout.BABKA) == Layout.BABKA + Vector3.UP * 3.8, "diamond: other targets keep 3.8 m")
	check(HudScript.diamond_anchor(Layout.BABKA, true).y > 3.8 + 1.0, "diamond: above Babka's !/? it is lifted over the marker")

# --- 3. короб «ХЛЕБ» ---

func _kiosk_sign() -> void:
	print("--- kiosk sign ---")
	var geometry := world.get_node("LevelGeometry")
	var sign: Label3D = geometry.get_node_or_null("KioskRoofSign")
	var box: Node3D = geometry.get_node_or_null("KioskRoofSignBox")
	if not check(sign != null and box != null, "sign: roof light box «ХЛЕБ» exists"):
		return
	check(sign.text == "ХЛЕБ" and sign.global_basis.z.dot(Vector3(0, 0, 1)) > 0.99, "sign: letters face south, to the parking")
	var mat := (box as MeshInstance3D).material_override as StandardMaterial3D
	check(mat != null and mat.emission_enabled and mat.emission_energy_multiplier >= 1.0, "sign: box glows warm")
	check(geometry.get_node_or_null("KioskRoofSignLight") is OmniLight3D, "sign: warm spill light")
	var top := Layout.KIOSK_ROOF_SIGN.y - Layout.KIOSK_ROOF_SIGN_SIZE.y * 0.5
	check(top > Layout.SOLIDS.filter(func(s): return s[0] == "Kiosk")[0][3].y, "sign: sits on the roof (bottom %.2f m above the 3.2 m kiosk)" % top)
	var space := world.get_world_3d().direct_space_state
	var spots := [Layout.ROUTE_DRIVE[-1], Layout.KIOSK_ZONE.get_center() * Vector3(1, 0, 1), Layout.STEALTH_CHECKPOINT,
		Vector3(Layout.KIOSK_ZONE.position.x + 1.0, 0, Layout.KIOSK_ZONE.end.z - 1.0), Vector3(Layout.KIOSK_ZONE.end.x - 1.0, 0, Layout.KIOSK_ZONE.end.z - 1.0)]
	for spot: Vector3 in spots:
		for eye_h in [1.6, 2.6]:   # глаза пешком и камера в машине
			var from: Vector3 = spot + Vector3.UP * eye_h
			var query := PhysicsRayQueryParameters3D.create(from, Layout.KIOSK_ROOF_SIGN, 1 | 64)
			var hit := space.intersect_ray(query)
			check(hit.is_empty(), "sign: seen from the parking %s at %.1f m (ray blocked by %s)" % [spot, eye_h, hit.get("collider").name if not hit.is_empty() else "nothing"])

# --- 2. конусы на мини-карте ---

func _minimap_cones() -> void:
	print("--- minimap cones ---")
	world.mission.notify_arrived_kiosk()
	world.stealth.grant_grace(60.0)
	world.player.place(Layout.STEALTH_CHECKPOINT, 0.0)
	await _frames(6)
	var cones: Array = hud.minimap.cones
	var posts := []
	var other := 0
	for sensor in world.get_tree().get_nodes_in_group(&"detection_sensors"):
		if sensor.get_parent().get_script() == PatrolNpcScript:
			posts.append(sensor.get_parent())
		else:
			other += 1
	check(posts.size() == 2 and cones.size() == posts.size(), "cones: one per post at the kiosk (%d cones, %d posts, %d other sensors)" % [cones.size(), posts.size(), other])
	for cone in cones:
		var at: Vector2 = cone[0]
		var hit := posts.filter(func(p): return Vector2(p.global_position.x, p.global_position.z).distance_to(at) < 0.5)
		check(hit.size() == 1, "cones: cone at %s is a post" % at)
		check(cone[2] >= 9.0 and cone[3] >= 75.0 and cone[3] < 360.0, "cones: sector of the post's range and field of view (%.0f m, %.0f°)" % [cone[2], cone[3]])
	world.player.place(Layout.SPAWN, 0.0)
	await _frames(6)
	check(hud.minimap.cones.is_empty(), "cones: none away from the kiosk (yard)")
	for p in posts:
		check(not p.xray_shown(), "xray: %s silhouette hidden far away" % p.name)
	world.player.place(XRAY_NEAR, 0.0)   # в 9–11 м от обоих постов
	await _frames(6)
	for p in posts:
		check(p.xray_shown(), "xray: %s silhouette shown within %.0f m" % [p.name, PatrolNpcScript.XRAY_RADIUS])

# --- 1. предупреждение о развороте ---

func _turn_warning() -> void:
	print("--- turn warning ---")
	var patrols := world.get_node("LevelGeometry/Patrols")
	for officer in [patrols.officer, patrols.officer2]:
		officer.place_at(officer.global_position)
		var hold: float = officer.seconds_to_turn()
		var from_index: int = officer.facing_index()
		var warned_at := -1.0
		var got := {"index": -1, "turning": true}   # лямбда захватывает локальные по значению — состояние в словаре
		var cb := func(next_index: int):
			got["index"] = next_index
			got["turning"] = officer.is_turning()
		officer.turn_warning.connect(cb)
		var t := 0.0
		var turn_at := -1.0
		while t < hold + 2.0:
			await physics_frame
			t += 1.0 / 60.0
			if got["index"] >= 0 and warned_at < 0.0:
				warned_at = t
			if officer.is_turning() and turn_at < 0.0:
				turn_at = t
				break
		officer.turn_warning.disconnect(cb)
		var lead: float = turn_at - warned_at
		check(warned_at >= 0.0 and turn_at > 0.0 and not got["turning"], "warn: %s signals before the turn (warn %.2f s, turn %.2f s)" % [officer.name, warned_at, turn_at])
		check(absf(lead - PatrolNpcScript.WARN_LEAD) < 0.1, "warn: %s lead %.2f s ≈ %.1f s" % [officer.name, lead, PatrolNpcScript.WARN_LEAD])
		check(got["index"] == (from_index + 1) % officer.facings.size(), "warn: %s names the next facing (%d)" % [officer.name, got["index"]])
		check(absf(turn_at - hold) < 0.1, "warn: %s hold unchanged by the warning (%.2f s vs %.2f s)" % [officer.name, turn_at, hold])
	# Субтитр — когда следующий угол накроет Илюшу: встать в секторе следующего угла первого поста.
	var officer: Node3D = patrols.officer
	officer.place_at(officer.global_position)
	world.stealth.grant_grace(60.0)
	var next: int = (officer.facing_index() + 1) % officer.facings.size()
	var yaw: float = float(officer.facings[next]) + officer.global_rotation.y
	var spot: Vector3 = officer.global_position + Vector3(-sin(yaw), 0, -cos(yaw)) * 8.0
	world.player.place(Vector3(spot.x, 0, spot.z), 0.0)
	check(officer.will_face(world.player.global_position, next), "warn: Ilyusha stands in the next facing's sector")
	var sound: Node = world.get_node("SoundDirector")
	sound.clear_gag_queue()
	var gags_before: int = sound.gags_started
	var texts_before: int = officer.warning_texts
	var warnings_before: int = officer.warnings
	var t2 := 0.0
	while officer.warnings == warnings_before or t2 < 0.2:
		await physics_frame
		t2 += 1.0 / 60.0
		if t2 > 15.0:
			break
	var warned_ok: bool = officer.warning_texts == texts_before + 1 and sound.gags_started > gags_before
	check(warned_ok, "warn: subtitle when the post is about to turn to Ilyusha (texts %d, gags %d → %d)" % [officer.warning_texts, gags_before, sound.gags_started])
	check(sound.subtitle_label.text == QuestLines.PATROL_TURN[0], "warn: subtitle text «%s»" % sound.subtitle_label.text)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures.append(label)
		print("FAIL: ", label)
	return condition

func _finish() -> void:
	print("POLISH03A: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

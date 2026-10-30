extends SceneTree
## 10 минут натурального наблюдения выхода, затем проход настоящим вводом.
## NPC, транспорт и их часы не меняются. Метрики дополняют независимый просмотр кадров.

const Layout = preload("res://game/world/layout.gd")
const OBSERVE_SECONDS := 600
const OVERLAP_SECONDS := 2.0
const STOP_SECONDS := 30.0
const NPC_BLOCK_FRAMES := 30
const NPC_SIDESTEP_METERS := 1.1
const NPC_PASS_METERS := 1.8
const NPC_DETOUR_LIMIT := 4
## playthrough_driver.walk_to ведёт к цели с замедлением, но не обходит людей.
## Здесь подтверждён физический взаимный стоп Player↔Resident43 (REVIEW-01/exit-walk-only.log).
## Обход только тела Resident, настоящим вводом по проверенному тротуару; исходная цель/бюджет сохраняются.
var main: Node
var world: DemoWorld
var people: Node
var output := "res://builds/screenshots/ARENA-03/exit"
var failures: Array[String] = []
var previous := {}
var close_seconds := {}
var stopped_seconds := {}
var max_close := 0.0
var max_stopped := 0.0
var max_reservations := 0
var sample := 0
var walk_only := false
var walk_leg := 0
var walk_trace: Array[Dictionary] = []
var steering_target := Vector3.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--walk-only":
			walk_only = true
		elif not arg.begins_with("--"):
			output = arg
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.start_game()
	await _frames(12)
	world = main.world
	people = world.get_node("LevelGeometry/Residents")
	world.stealth.grant_grace(1500.0)
	var at: Vector2 = Layout.LIFE_NODES[&"dw_s"]
	var exit: Vector3 = people.life.spots[&"edge_d_n"].pos
	world.player.place(Vector3(at.x, 0.0, exit.z + 3.0), 0.0)
	world.camera_rig.follow(world.player, &"on_foot")
	world.camera_rig.yaw = 0.0
	world.camera_rig.snap()
	await _frames(8)
	var start := Engine.get_physics_frames()
	var next_shot := 0
	var shots := [30, 180, 360, 600]
	while not walk_only and Engine.get_physics_frames() - start < OBSERVE_SECONDS * Engine.physics_ticks_per_second:
		await physics_frame
		_observe()
		var elapsed := float(Engine.get_physics_frames() - start) / Engine.physics_ticks_per_second
		if next_shot < shots.size() and elapsed >= shots[next_shot]:
			await _shot("t%03d_north" % shots[next_shot])
			next_shot += 1
	if walk_only:
		print("ARENA03_EXIT_OBSERVE: NOT_RUN (--walk-only diagnostic mode)")
	else:
		print("ARENA03_EXIT_OBSERVE seconds=", OBSERVE_SECONDS, " samples=", sample, " max_reserved=", max_reservations, " max_overlap_s=", max_close, " max_stopped_s=", max_stopped)
	_check_durations()
	# Дойти до северной улицы и обратно, затем мимо жилого дома к аптеке.
	for id in [&"dw_s", &"dw_c", &"cn_w", &"dw_c", &"dw_s", &"dw_out", &"dw_s", &"dw_h11", &"dw_h11n", &"dw_n", &"dw_top", &"dw_back", &"dw_gate", &"a_n_apt"]:
		if not await _walk_to(id): break
		await _shot("walk_%02d_%s" % [sample, id])
	_check_durations()
	for audio in main.find_children("*", "AudioStreamPlayer", true, false) + main.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	main.queue_free()
	await _frames(6)
	print("ARENA03_EXIT_CAPTURE: %d failures; visual review pending" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _north(p: Vector3) -> bool:
	var south: Vector2 = Layout.LIFE_NODES[&"dw_s"]
	return p.z < south.y and p.x < south.x + 4.0

func _observe() -> void:
	sample += 1
	var delta := 1.0 / Engine.physics_ticks_per_second
	if people.residents.size() != 64: _fail("resident count changed")
	var held: int = people.life.reserved.get(&"edge_d_n", []).size()
	max_reservations = maxi(max_reservations, held)
	if held > 1: _fail("multiple reservations at the northern exit")
	var nearby: Array = []
	for resident: Resident in people.residents:
		var p := resident.global_position
		var old: Dictionary = previous.get(resident, {})
		if _north(p) and not resident.hidden:
			nearby.append(resident)
			var still: bool = not old.is_empty() and not old.hidden and p.distance_to(old.pos) < 0.001
			stopped_seconds[resident] = float(stopped_seconds.get(resident, 0.0)) + delta if still else 0.0
			max_stopped = maxf(max_stopped, stopped_seconds[resident])
		else:
			stopped_seconds[resident] = 0.0
		if not old.is_empty() and _north(old.pos):
			if not old.hidden and resident.hidden and resident.state == &"away" and people.life.on_screen(old.pos):
				_fail("visible exit disappearance: " + resident.name)
			if not old.hidden and not resident.hidden and resident.state == &"walk" and resident.knock_phase == &"" and p.distance_to(old.pos) > 0.2:
				_fail("northern walking jump: " + resident.name)
		previous[resident] = {"pos": p, "hidden": resident.hidden}
	var active := {}
	for a in nearby.size():
		for b in range(a + 1, nearby.size()):
			var first: Resident = nearby[a]
			var second: Resident = nearby[b]
			var key := "%d:%d" % [first.index, second.index]
			if first.global_position.distance_to(second.global_position) < Resident.BODY_RADIUS * 2.0:
				active[key] = float(close_seconds.get(key, 0.0)) + delta
				max_close = maxf(max_close, active[key])
	close_seconds = active

func _walk_to(id: StringName) -> bool:
	var target: Vector2 = Layout.LIFE_NODES[id]
	walk_leg += 1
	walk_trace.clear()
	var detour: Array[Vector3] = []
	var detours := 0
	var blocked_frames := 0
	var blocked_by: Resident = null
	for frame in 7200:
		var to := Vector3(target.x, 0.0, target.y) - world.player.global_position
		to.y = 0.0
		if to.length() < 0.8:
			_walk_diagnostic(id, frame, "arrived")
			Input.action_release(&"move_forward")
			return true
		if not detour.is_empty() and _player_distance(detour[0]) < 0.15:
			detour.pop_front()
			if detour.is_empty():
				_walk_diagnostic(id, frame, "sidestep_finished")
		steering_target = detour[0] if not detour.is_empty() else Vector3(target.x, 0.0, target.y)
		var steer := steering_target - world.player.global_position
		steer.y = 0.0
		world.camera_rig.yaw = atan2(-steer.x, -steer.z)
		var strength := clampf(steer.length() / 1.2, 0.35, 1.0) if not detour.is_empty() else 1.0
		Input.action_press(&"move_forward", strength)
		await physics_frame
		_observe()
		if detour.is_empty():
			var blocker := _blocking_resident(to.normalized())
			blocked_frames = blocked_frames + 1 if blocker != null and blocker == blocked_by else 0
			blocked_by = blocker
			if blocked_frames >= NPC_BLOCK_FRAMES and detours < NPC_DETOUR_LIMIT:
				blocked_frames = 0
				var candidate := _npc_detour(to.normalized())
				if not candidate.is_empty():
					detour = candidate
					detours += 1
					var note := _walk_diagnostic(id, frame, "sidestep_started")
					note["blocker"] = str(blocker.get_path())
					note["detour"] = [_v3(detour[0]), _v3(detour[1])]
					note["detour_basis"] = "30 stationary physics frames against Resident body; actual capsule/mask test_move and pedestrian surface footprint; original endpoint/tolerance/frame budget retained"
					print("ARENA03_EXIT_SIDESTEP ", JSON.stringify(note))
					var detour_label := "sidestep_%02d_%02d" % [walk_leg, detours]
					_write_json(detour_label, note)
					await _shot(detour_label)
		if frame % 600 == 0:
			_walk_diagnostic(id, frame, "walking")
	# Сначала сохранить фактическое управление на неуспешном физическом шаге.
	var diagnostic := _walk_diagnostic(id, 7200, "timeout")
	var label := "failure_%02d_%s" % [walk_leg, id]
	_write_json(label, {"timeout": diagnostic, "trace": walk_trace})
	Input.action_release(&"move_forward")
	await _shot(label)
	_fail("ordinary walking blocked before " + String(id))
	return false

func _player_distance(point: Vector3) -> float:
	var to := point - world.player.global_position
	return Vector2(to.x, to.z).length()

## Только подтверждённый горизонтальный упор в тело жителя; стена не запускает обход.
func _blocking_resident(direction: Vector3) -> Resident:
	var velocity: Vector3 = world.player.get_real_velocity()
	if Vector2(velocity.x, velocity.z).length() > 0.15: return null
	for i in world.player.get_slide_collision_count():
		var collision: KinematicCollision3D = world.player.get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is Node and collider.get_parent() is Resident and collision.get_normal().dot(direction) < -0.3:
			return collider.get_parent() as Resident
	return null

## Два коротких отрезка обычной ходьбы, затем снова исходная цель.
func _npc_detour(direction: Vector3) -> Array[Vector3]:
	var side := Vector3(-direction.z, 0.0, direction.x)
	var start: Transform3D = world.player.global_transform
	for sign in [1.0, -1.0]:
		var across: Vector3 = side * NPC_SIDESTEP_METERS * sign
		var ahead := direction * NPC_PASS_METERS
		var shifted := start
		shifted.origin += across
		if not _pedestrian_segment(start.origin, shifted.origin): continue
		if not _pedestrian_segment(shifted.origin, shifted.origin + ahead): continue
		if world.player.test_move(start, across): continue
		if world.player.test_move(shifted, ahead): continue
		var points: Array[Vector3] = [shifted.origin, shifted.origin + ahead]
		return points
	return []

func _pedestrian_segment(from: Vector3, to: Vector3) -> bool:
	var shape: CapsuleShape3D = world.player.get_node("CollisionShape3D").shape as CapsuleShape3D
	var radius := shape.radius
	var steps := maxi(1, ceili(from.distance_to(to) / radius))
	for step in steps + 1:
		var point := from.lerp(to, float(step) / steps)
		for offset in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
			if not _pedestrian_point(Vector2(point.x, point.z) + offset): return false
	return true

func _pedestrian_point(point: Vector2) -> bool:
	for ground in Layout.LIFE_GROUNDS:
		if ground.has_point(point): return true
	for surface in Layout.SURFACES:
		if surface[1] == "sidewalk" and Rect2(surface[2] - surface[3] * 0.5, surface[3]).has_point(point):
			return true
	return false

func _walk_diagnostic(id: StringName, frame: int, status: String) -> Dictionary:
	var player: Ilyusha = world.player
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape as CapsuleShape3D
	var target: Vector2 = Layout.LIFE_NODES[id]
	var to := Vector3(target.x, 0.0, target.y) - player.global_position
	to.y = 0.0
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var input_direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, world.camera_rig.input_yaw)
	var collisions: Array[Dictionary] = []
	for i in player.get_slide_collision_count():
		var collision := player.get_slide_collision(i)
		var collider := collision.get_collider()
		var collider_info := {
			"path": str(collider.get_path()) if collider is Node else str(collider),
			"class": collider.get_class() if collider else "null",
			"layer": collider.collision_layer if collider is CollisionObject3D else -1,
			"position": _v3(collision.get_position()), "normal": _v3(collision.get_normal()),
			"travel": _v3(collision.get_travel()), "remainder": _v3(collision.get_remainder()),
		}
		collisions.append(collider_info)
	var actions := {}
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"look_left", &"look_right", &"look_up", &"look_down"]:
		actions[String(action)] = Input.get_action_strength(action)
	var diagnostic := {
		"status": status, "leg": walk_leg, "frame": frame, "target_id": String(id),
		"position": _v3(player.global_position), "target": [target.x, 0.0, target.y],
		"remaining": to.length(), "velocity": _v3(player.velocity),
		"steering_target": _v3(steering_target),
		"real_velocity": _v3(player.get_real_velocity()), "speed_limit": player.speed_limit(),
		"input_enabled": player.input_enabled, "hide_mode": String(player.hide_mode),
		"input": [input.x, input.y], "actions": actions,
		"desired_direction": _v3(to.normalized()), "input_direction": _v3(input_direction),
		"desired_yaw": atan2(-to.x, -to.z), "camera_yaw": world.camera_rig.yaw,
		"input_yaw": world.camera_rig.input_yaw, "follow_heading": world.camera_rig.follow_heading,
		"visual_yaw": player.visual.rotation.y, "control_mode": String(world.control_mode),
		"player_layer": player.collision_layer, "player_mask": player.collision_mask,
		"capsule": {"radius": shape.radius, "height": shape.height},
		"collisions": collisions,
	}
	walk_trace.append(diagnostic)
	print("ARENA03_EXIT_WALK ", JSON.stringify(diagnostic))
	return diagnostic

func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _write_json(label: String, data: Dictionary) -> void:
	var file := FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t") + "\n")
	else:
		_fail("cannot save walking diagnostic: " + label)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(label + ".png")))
	if error != OK: _fail("cannot save " + label)
	print("ARENA03_EXIT_FRAME ", label)

func _fail(message: String) -> void:
	if failures.has(message): return
	failures.append(message)
	push_error("ARENA03_EXIT: " + message)

func _check_durations() -> void:
	if max_close > OVERLAP_SECONDS: _fail("residents overlap for more than %.1f seconds" % OVERLAP_SECONDS)
	if max_stopped > STOP_SECONDS: _fail("a visible northern resident stops for more than %.1f seconds" % STOP_SECONDS)

func _frames(count: int) -> void:
	for frame in count: await physics_frame

extends SceneTree
## CHAR3D-01/02 (набор CHAR3D, headless): объёмный облик по паспорту assets/art/characters/passports.json.
## CHAR3D-02: облик по умолчанию — 3D (LOOK_3D = true в npc.gd/ilyusha.gd), --sprites/force_sprites — спрайты.
## Проверки: паспорт читается и есть у всех 22 персонажей игры (Илюша, Бабка, продавщица, полицейский, «военком»,
## росгвардеец, 16 силуэтов жителей); у каждого — детали, сводка, три рисунка деколи; облик строится, рост фигуры
## совпадает с ростом спрайта (верх фронтального SVG при том же height_m) в пределах 5 %; деталей = паспорт; детали
## собраны в ≤ 5 мешей групп, у каждого меша оболочка-контур (cull front + grow), отрисовок ≤ 10; ходьба качает ноги
## в противофазе и затихает в стойке; set_flail разводит руки и ноги (полёт KNOCK-01); выбор облика: по умолчанию 3D,
## force_sprites — спрайт; в мире все персонажи (Илюша, Бабка, продавщица, посты, «военком», жители) — 3D; Илюша
## шагает через физику.
## Запуск: ./tools/run.command --headless --fixed-fps 60 --script tests/char3d_test.gd

const LookScript = preload("res://game/characters/character_body3d.gd")
const SpriteScript = preload("res://game/characters/character_sprite.gd")
const ResidentsScript = preload("res://game/world/residents.gd")
## Персонаж → height_m в игре (ilyusha.gd, demo_world.tscn, patrols.gd, residents.gd).
const CASES := {"ilyusha": 2.0, "babka": 2.17, "vendor": 1.95, "police": 2.05, "officer": 2.2, "guard": 2.05}

var failures: Array[String] = []
var checks := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func():
		push_error("FAIL: char3d test exceeded 240 simulated seconds")
		quit(2)
	)
	var cases := CASES.duplicate()
	for look in ResidentsScript.SILHOUETTES:
		cases[ResidentsScript.character_for(look)] = ResidentsScript.SILHOUETTES[look][1]
	check(cases.size() == 22, "22 characters in the game (%d)" % cases.size())
	_check_passports(cases)
	_check_choice()
	await _check_looks(cases)
	await _check_world()
	_finish()

func _check_passports(cases: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(LookScript.PASSPORTS)
	var data = JSON.parse_string(text)
	check(data is Dictionary and data.has("characters") and int(data.get("version", 0)) == 2, "passports.json v2 parses")
	var characters: Dictionary = LookScript.passports()
	for name in cases:
		var p: Dictionary = characters.get(name, {})
		check(not p.is_empty() and p.has("parts") and p.has("summary") and p.has("decal") and p.has("pivots"),
			"%s: passport with parts, summary, decal and pivots" % name)
		if p.is_empty():
			continue
		var exist := true
		for view in ["front", "back", "side"]:
			exist = exist and ResourceLoader.exists(p["decal"]["textures"][view])
		check(exist, "%s: front/back/side decal textures exist" % name)
		var decal_parts := 0
		for spec in p["parts"]:
			decal_parts += 1 if spec.get("decal", false) else 0
		check(decal_parts >= 3 and p["parts"][0]["name"] == "head", "%s: head first, %d/%d parts carry the drawing" % [name, decal_parts, p["parts"].size()])

func _check_choice() -> void:
	check(LookScript.wanted(true, "babka") and LookScript.wanted(true, "resident_dog"), "default: 3D look when the passport exists")
	check(not LookScript.wanted(true, "no_such_character"), "no passport → sprite")
	LookScript.force_sprites = true
	check(not LookScript.wanted(true, "babka"), "force_sprites (as --sprites) → sprite")
	LookScript.force_sprites = false

func _check_looks(cases: Dictionary) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var x := 0.0
	for name in cases:
		if not LookScript.has_passport(name):
			continue
		var look: CharacterBody3DLook = LookScript.new()
		look.character = name
		look.height_m = cases[name]
		look.position = Vector3(x, 0, 0)
		x += 3.0
		stage.add_child(look)
		await _physics(2)
		var passport: Dictionary = LookScript.passports()[name]
		check(look.mesh_count() == passport["parts"].size() and look.mesh_count() >= 3,
			"%s: %d parts built (passport %d)" % [name, look.mesh_count(), passport["parts"].size()])
		var sprite_h := _sprite_height(name, cases[name])
		var h := look.figure_height()
		check(absf(h - sprite_h) <= sprite_h * 0.05, "%s: figure height %.3f m vs sprite %.3f m (±5 %%)" % [name, h, sprite_h])
		var hulls := 0
		for mi: MeshInstance3D in look.meshes.values():
			var hull := mi.material_override.next_pass as StandardMaterial3D
			if hull and hull.cull_mode == BaseMaterial3D.CULL_FRONT and hull.grow and hull.grow_amount > 0.005:
				hulls += 1
		check(hulls == look.meshes.size() and look.meshes.size() <= 5 and look.draw_calls() <= 10,
			"%s: %d group meshes with the outline hull, %d draw calls" % [name, hulls, look.draw_calls()])
		var head: MeshInstance3D = look.parts["head"]
		var mat := head.material_override as ShaderMaterial
		check(mat != null and mat.get_shader_parameter("tex_front") != null, "%s: the drawing is projected on the body" % name)
		check(look.groups.has("leg_r") and look.groups.has("leg_l"), "%s: both legs are separate groups" % name)
		# Ходьба: ноги качаются в противофазе, при остановке возвращаются в стойку.
		look.set_walk_speed(1.6)
		var leg_r: Node3D = look.groups["leg_r"]
		var leg_l: Node3D = look.groups["leg_l"]
		var seen_max := 0.0
		var seen_min := 0.0
		var opposite := true
		for i in 60:
			await physics_frame
			seen_max = maxf(seen_max, leg_r.rotation.x)
			seen_min = minf(seen_min, leg_r.rotation.x)
			if absf(leg_r.rotation.x) > 0.05 and signf(leg_r.rotation.x) == signf(leg_l.rotation.x):
				opposite = false
		check(seen_max > deg_to_rad(8.0) and seen_min < -deg_to_rad(8.0), "%s: walking swings the legs (%.0f…%.0f°)" % [name, rad_to_deg(seen_min), rad_to_deg(seen_max)])
		check(opposite and look.frame >= 0, "%s: legs in antiphase, walk frame %d" % [name, look.frame])
		look.set_walk_speed(0.0)
		await _physics(40)
		check(absf(leg_r.rotation.x) < 0.01 and look.frame == -1, "%s: stopping returns to the idle pose" % name)
		look.set_flail(1.0)
		await _physics(2)
		var spread := absf(leg_r.rotation.z) > 0.3 and absf(leg_l.rotation.z) > 0.3 and signf(leg_r.rotation.z) != signf(leg_l.rotation.z)
		for arm in ["arm_r", "arm_l"]:
			if look.groups.has(arm):
				spread = spread and absf((look.groups[arm] as Node3D).rotation.z) > 0.8
		check(spread, "%s: flail spreads arms and legs" % name)
		look.set_flail(0.0)
		look.set_walk_speed(-1.0)
		check(look.lie_center() > 0.05 and look.lie_center() < 0.6, "%s: lying half-depth %.2f m" % [name, look.lie_center()])
	stage.queue_free()
	await _physics(2)

## Рост спрайта: верх рисунка (первая строка с альфой > 0,5) фронтального SVG до линии ног y=590 при height_m.
## SVG объявлен с масштабом 2 к холсту — строка переводится в единицы холста.
func _sprite_height(name: String, height_m: float) -> float:
	var image := Image.new()
	var bytes := FileAccess.get_file_as_bytes("res://assets/art/characters/%s_front_idle.svg" % name)
	if image.load_svg_from_buffer(bytes, 1.0) != OK:
		return -1.0
	for y in image.get_height():
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).a > 0.5:
				return (590.0 - y * 600.0 / image.get_height()) / 600.0 * height_m
	return -1.0

func _check_world() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _physics(2)
	main.start_game()
	await _physics(10)
	var world: DemoWorld = main.world
	check(world.player.get_node("Visual/Look") is CharacterBody3DLook, "world: Ilyusha has the 3D look")
	check(world.babka.get_node("Visual/Look") is CharacterBody3DLook, "world: Babka has the 3D look")
	check(world.vendor.get_node("Visual/Look") is CharacterBody3DLook, "world: vendor has the 3D look")
	var patrols := world.find_child("Patrols", true, false)
	for npc in [patrols.officer, patrols.officer2, patrols.account_officer]:
		var look = npc.get_node("Visual/Look")
		check(look is CharacterBody3DLook and look.character == npc.character, "world: %s (%s) has the 3D look" % [npc.name, npc.character])
	var residents := world.find_child("Residents", true, false)
	var all_3d: bool = residents != null and residents.residents.size() == 14
	if residents:
		for r in residents.residents:
			all_3d = all_3d and r.get_node("Visual/Look") is CharacterBody3DLook
	check(all_3d, "world: all 14 residents have the 3D look")
	# Илюша идёт через физику: облик сам переходит в ходьбу по пройденному пути.
	var look: CharacterBody3DLook = world.player.get_node("Visual/Look")
	Input.action_press(&"move_forward")
	var walked := false
	for i in 40:
		await physics_frame
		walked = walked or look.frame >= 0
	Input.action_release(&"move_forward")
	check(walked, "world: Ilyusha walking through physics drives the 3D walk cycle")

func _physics(count: int) -> void:
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
	print("CHAR3D: %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.queue_free()
	for i in 3:
		await process_frame
	quit(0 if failures.is_empty() else 1)

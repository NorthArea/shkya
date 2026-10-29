extends SceneTree
## CHAR3D-01 (набор CHAR3D, headless): объёмный облик по паспорту assets/art/characters/passports.json.
## 3D включается принудительно (CharacterBody3DLook.force_3d), константы LOOK_3D в npc.gd/ilyusha.gd не трогаются.
## Проверки: паспорт читается; четыре персонажа строятся; рост фигуры совпадает с ростом спрайта (верх рисунка
## фронтального SVG при том же height_m) в пределах 5 %; число деталей = паспорт; у каждой детали с контуром есть
## оболочка (cull front + grow); ходьба качает ноги в противофазе и затихает в стойке; в мире Илюша, Бабка,
## полицейский и бабка в шубе получают 3D-облик, персонаж без паспорта (продавщица) остаётся спрайтом.
## Запуск: ./tools/run.command --headless --fixed-fps 60 --script tests/char3d_test.gd

const LookScript = preload("res://game/characters/character_body3d.gd")
const SpriteScript = preload("res://game/characters/character_sprite.gd")
## Персонаж → height_m в игре (ilyusha.gd, npc.gd, patrols.gd, residents.gd).
const CASES := {"ilyusha": 2.0, "babka": 2.17, "police": 2.05, "resident_shuba": 2.0}

var failures: Array[String] = []
var checks := 0
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("FAIL: char3d test exceeded 120 simulated seconds")
		quit(2)
	)
	_check_passports()
	await _check_looks()
	await _check_world()
	_finish()

func _check_passports() -> void:
	var text := FileAccess.get_file_as_string(LookScript.PASSPORTS)
	var data = JSON.parse_string(text)
	check(data is Dictionary and data.has("characters"), "passports.json parses")
	var characters: Dictionary = LookScript.passports()
	for name in CASES:
		var p: Dictionary = characters.get(name, {})
		check(not p.is_empty() and p.has("parts") and p.has("summary") and p["decals"].has("head"),
			"%s: passport with parts, summary and head decal" % name)
		if p.is_empty():
			continue
		for view in ["front", "back", "side"]:
			check(ResourceLoader.exists(p["decals"]["head"]["textures"][view]), "%s: %s decal texture exists" % [name, view])

func _check_looks() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var x := 0.0
	for name in CASES:
		var look: CharacterBody3DLook = LookScript.new()
		look.character = name
		look.height_m = CASES[name]
		look.position = Vector3(x, 0, 0)
		x += 3.0
		stage.add_child(look)
		await _physics(2)
		var passport: Dictionary = LookScript.passports()[name]
		check(look.mesh_count() == passport["parts"].size() and look.mesh_count() >= 7,
			"%s: %d meshes built (passport %d)" % [name, look.mesh_count(), passport["parts"].size()])
		var sprite_h := _sprite_height(name, CASES[name])
		var h := look.figure_height()
		check(absf(h - sprite_h) <= sprite_h * 0.05, "%s: figure height %.3f m vs sprite %.3f m (±5 %%)" % [name, h, sprite_h])
		var hulls := 0
		var wanted := 0
		for spec in passport["parts"]:
			var mi: MeshInstance3D = look.parts[spec["name"]]
			if not spec.get("outline", true):
				continue
			wanted += 1
			var hull := mi.material_override.next_pass as StandardMaterial3D
			if hull and hull.cull_mode == BaseMaterial3D.CULL_FRONT and hull.grow and hull.grow_amount > 0.005:
				hulls += 1
		check(hulls == wanted and wanted > 0, "%s: inverted-hull outline on %d/%d parts" % [name, hulls, wanted])
		var head: MeshInstance3D = look.parts["head"]
		check((head.material_override as ShaderMaterial).get_shader_parameter("use_decal") == true, "%s: head has the face decal" % name)
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
		look.set_walk_speed(-1.0)
	stage.queue_free()
	await _physics(2)

## Рост спрайта: верх рисунка (первая строка с альфой > 0,5) фронтального SVG до линии ног y=590 при height_m.
## SVG объявлен 800×1200 при холсте 400×600 — строка переводится в единицы холста.
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
	LookScript.force_3d = true
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _physics(2)
	main.start_game()
	await _physics(10)
	var world: DemoWorld = main.world
	check(world.player.get_node("Visual/Look") is CharacterBody3DLook, "world: Ilyusha has the 3D look")
	check(world.babka.get_node("Visual/Look") is CharacterBody3DLook, "world: Babka has the 3D look")
	check(world.vendor.get_node("Visual/Look") is CharacterSprite, "world: vendor without passport stays a sprite")
	var patrols := world.find_child("Patrols", true, false)
	check(patrols != null and patrols.officer.get_node("Visual/Look") is CharacterBody3DLook, "world: police officer has the 3D look")
	var shuba: Node = null
	var residents := world.find_child("Residents", true, false)
	if residents:
		for r in residents.residents:
			if r.character == "resident_shuba":
				shuba = r
	check(shuba != null and shuba.get_node("Visual/Look") is CharacterBody3DLook, "world: resident in the fur coat has the 3D look")
	# Илюша идёт через физику: облик сам переходит в ходьбу по пройденному пути.
	var look: CharacterBody3DLook = world.player.get_node("Visual/Look")
	Input.action_press(&"move_forward")
	var walked := false
	for i in 40:
		await physics_frame
		walked = walked or look.frame >= 0
	Input.action_release(&"move_forward")
	check(walked, "world: Ilyusha walking through physics drives the 3D walk cycle")
	LookScript.force_3d = false

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

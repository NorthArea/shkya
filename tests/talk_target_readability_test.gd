extends SceneTree
## POLISH-03: target identity and prompt layout; headless is not pixel acceptance.
const Director = preload("res://game/mission/mission_director.gd")
const HUD = preload("res://game/ui/game_hud.gd")
const Pad = preload("res://game/ui/pad_input.gd")
const EXPECTED := "E — ПОГОВОРИТЬ С ПРОДАВЩИЦЕЙ"
var checks := 0
var prompt_draws := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in count:
		await process_frame

func run() -> void:
	var director := Director.new()
	for state: StringName in [Director.NOT_STARTED, Director.OFFERED, Director.GO_TO_CAR, Director.DRIVE_TO_KIOSK, Director.BUY_BREAD, Director.RETURN_HOME, Director.COMPLETE]:
		director.state = state
		check(director.prompt_for(&"vendor") == (EXPECTED if state == Director.BUY_BREAD else ""), "vendor target and availability in %s" % state)
		check(director.prompt_for(&"officer") == "E — ПОГОВОРИТЬ" and director.prompt_for(&"account_officer") == "E — ПОГОВОРИТЬ", "observer prompts unchanged in %s" % state)
	check(director.prompt_for(&"car") == "E — СЕСТЬ В МАШИНУ", "car prompt unchanged")
	director.state = Director.BUY_BREAD
	check(director.interact(&"vendor") == Director.R_VENDOR_DIALOG and director.state == Director.BUY_BREAD, "named prompt preserves vendor conversation command and state")
	check(director.prompt_for(&"babka") == "E — ПОГОВОРИТЬ", "Babka conversation prompt unchanged")
	director.state = Director.RETURN_HOME
	director.has_bread = true
	check(director.prompt_for(&"babka") == "E — СДАТЬ ЗАДАНИЕ", "bread handover prompt unchanged")
	var hud := HUD.new()
	root.add_child(hud)
	hud.prompt_plate.draw.connect(func(): prompt_draws += 1)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for gamepad in [false, true]:
			var previous_draws := prompt_draws
			Pad.pad_active = gamepad
			director.state = Director.BUY_BREAD
			var text := Pad.hint(director.prompt_for(&"vendor"))
			check(text == ("X — ПОГОВОРИТЬ С ПРОДАВЩИЦЕЙ" if gamepad else EXPECTED), "target identity survives E/X mapping at %s" % resolution)
			hud.prompt_label.text = text
			hud.prompt_plate.visible = true
			hud._center_plate()
			hud.prompt_plate.queue_redraw()
			await frames(3)
			var plate: Rect2 = hud.prompt_plate.get_global_rect()
			var viewport: Rect2 = root.get_visible_rect()
			var minimum: Vector2 = hud.prompt_plate.get_combined_minimum_size()
			check(minimum.x < resolution.x, "prompt minimum width fits %s: %.1f" % [resolution, minimum.x])
			check(viewport.encloses(plate), "centered prompt bounds fit logical viewport at %s" % resolution)
			check(prompt_draws > previous_draws, "actual prompt/keycap draw callback runs for E/X mapping")
			print("PROMPT_LAYOUT resolution=%s pad=%s minimum=%s plate=%s viewport=%s" % [resolution, gamepad, minimum, plate, viewport])
	Pad.pad_active = false
	director.free()
	hud.queue_free()
	await frames(3)
	print("NATIVE TALK TARGET READABILITY: NOT RUN (headless layout only)")
	call_deferred("finish")

func finish() -> void:
	print("TALK_TARGET_READABILITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

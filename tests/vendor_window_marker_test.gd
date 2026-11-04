extends SceneTree
## Exercises the real HUD marker decision and Camera3D projection, without Main.
const HUD = preload("res://game/ui/game_hud.gd")
const Rig = preload("res://game/camera/camera_rig.gd")
const Layout = preload("res://game/world/layout.gd")
class MarkerWorld extends Node3D:
	var camera_rig: Node
var checks := 0
var failures: Array[String] = []
var world: MarkerWorld
var hud: Node
var rig: Node
var actor: Node3D

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

func view(focus: Vector3, target: Vector3, in_car: bool, away := false) -> void:
	actor.position = focus
	rig.position = target + Vector3(0, 2.0, 6.0)
	rig.rotation = Vector3.ZERO
	rig.camera.look_at(target + Vector3.UP * 1.5 + (Vector3.BACK * 12.0 if away else Vector3.ZERO))
	await frames(2)  # Camera3D API transform commits at the frame boundary.
	hud._update_map_and_diamond(world, target, in_car)

func check_anchor(target: Vector3, height: float, message: String) -> void:
	# Independent Camera3D API reference, not the HUD's manual projection formula.
	var projected: Vector2 = rig.camera.unproject_position(target + Vector3.UP * height)
	check(hud.diamond_position.distance_to(projected) < 1.0, message + " actual anchor projects to window-height point")

func run() -> void:
	root.size = Vector2i(1920, 1080)
	world = MarkerWorld.new()
	root.add_child(world)
	actor = Node3D.new()
	world.add_child(actor)
	rig = Rig.new()
	world.add_child(rig)
	rig.set_physics_process(false)
	rig.target = actor
	rig.arm.spring_length = 0.0
	world.camera_rig = rig
	hud = HUD.new()
	world.add_child(hud)
	await frames(3)
	var target: Vector3 = Layout.VENDOR_WINDOW
	await view(target + Vector3.BACK, target, false)
	check(hud.diamond_visible and hud.diamond.visible and not hud.diamond_near_hidden, "near vendor window retains the actual marker")
	check(hud.diamond_distance_text == "ОКНО КИОСКА", "near window marker names its target even below 2m")
	check_anchor(target, 1.75, "near window")
	await view(target + Vector3.BACK * 3.0, target, false)
	check(hud.diamond_visible and hud.diamond_distance_text == "ОКНО КИОСКА · 3 м", "window marker keeps useful metres and identity")
	check_anchor(target, 1.75, "window 3m")
	await view(target + Vector3.BACK, target, false, true)
	check(hud.diamond_visible and hud.diamond_clamped and hud.diamond_distance_text == "ОКНО КИОСКА", "free camera looking away gets the same labelled edge marker")
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(Rect2(hud.diamond_position - Vector2.ONE * 24, Vector2.ONE * 48)), "edge marker remains inside logical viewport")
	await view(target + Vector3.BACK, target, true)
	check(hud.diamond_near_hidden and not hud.diamond_visible and hud.diamond_distance_text == "", "car mode retains old near suppression and metre policy")
	check_anchor(target, 3.8, "car target")
	for distance in [15.0, 20.0]:
		await view(target + Vector3.BACK * distance, target, false)
		check(not hud.diamond_near_hidden and hud.diamond_visible and hud.diamond_distance_text == "%d м" % int(distance), "window at %.0fm retains old distant policy" % distance)
		check_anchor(target, 3.8, "far window")
	await view(Layout.BABKA + Vector3.BACK, Layout.BABKA, false)
	check(hud.diamond_near_hidden and not hud.diamond_visible and hud.diamond_distance_text == "", "other near target keeps suppression")
	check_anchor(Layout.BABKA, 3.8, "Babka target")
	await view(Layout.BABKA + Vector3.BACK * 20.0, Layout.BABKA, false)
	check(hud.diamond_visible and hud.diamond_distance_text == "20 м", "other far target keeps distance marker")
	check(HUD.diamond_anchor(Layout.KIOSK) != Layout.KIOSK + Vector3.UP * 3.8, "existing kiosk roof-sign anchor stays distinct")
	world.queue_free()
	await frames(4)
	print("NATIVE WINDOW MARKER PIXELS: NOT RUN (Dummy projection/layout only)")
	call_deferred("finish")

func finish() -> void:
	print("VENDOR_WINDOW_MARKER: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

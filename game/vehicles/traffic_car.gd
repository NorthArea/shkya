class_name TrafficCar
extends PathVehicle
## Машина на кольце (ARENA-01, часть T; облик — CITY-02 V): «Жигули» (ВАЗ-2106), «Волга» (ГАЗ-24) или «Газель»
## (ГАЗ-3302 с промтоварным фургоном). Седаны — общие меши LadaVisual (лофт сечений, свои силуэты и передки),
## «Газель» — кабина с капотом-«мордой», рама и высокий фургон. Колёса с дисками и протектором крутятся, фары горят,
## габариты ярче при торможении, снег на крыше, выхлоп на морозе. kind задаётся до добавления в дерево.
## Скорость 9 м/с (C8). Перед — −Z.

const VehicleMesh = preload("res://game/vehicles/vehicle_mesh.gd")
const LadaVisual = preload("res://game/vehicles/lada_visual.gd")

const KINDS := {
	&"zhiguli": {"size": Vector3(1.62, 1.44, 4.07), "wheelbase": 2.42, "radius": 0.32, "paint": Color(0.62, 0.12, 0.08), "plate": "в417ам 54"},
	&"volga": {"size": Vector3(1.8, 1.48, 4.74), "wheelbase": 2.8, "radius": 0.34, "paint": Color(0.80, 0.72, 0.52), "plate": "к208ро 154"},
	&"gazelle": {"size": Vector3(2.05, 2.25, 5.5), "wheelbase": 2.9, "radius": 0.36, "paint": Color(0.16, 0.30, 0.55), "plate": "т655ес 54"},
}

var kind: StringName = &"zhiguli"

func _init() -> void:
	super._init()
	cruise_speed = 9.0
	corner_speed = 5.0
	can_yield = true   # POLISH-03 C: встречной «Ладе» уступает, прижимаясь к обочине

func _ready() -> void:
	var spec: Dictionary = KINDS[kind]
	size = spec["size"]
	wheelbase = spec["wheelbase"]
	wheel_radius = spec["radius"]
	super._ready()

func _build_visual() -> Node3D:
	if kind == &"gazelle":
		return _gazelle()
	return _sedan(&"volga" if kind == &"volga" else &"vaz2106")

func _head() -> StandardMaterial3D:
	return VehicleMesh.lamp(Color(1.0, 0.95, 0.80), Color(1.0, 0.90, 0.66), 2.2)

## Седан: кузов LadaVisual в цвете машины, свои фары и габариты (_tail ярче при торможении).
func _sedan(model: StringName) -> Node3D:
	var root := Node3D.new()
	var spec: Dictionary = KINDS[kind]
	var paint := VehicleMesh.paint(spec["paint"], 0.3, 0.85, 0.35, 0.65)
	LadaVisual.dress(root, model, paint, VehicleMesh.glass(0.04), _head(), _tail, spec["plate"], 0.1)
	var sedan: Dictionary = LadaVisual.SEDANS[model]
	for spot in LadaVisual.wheel_spots(model):
		_wheels.append(VehicleMesh.add_wheel(root, spot, wheel_radius, sedan["wheel_w"], sedan["wheel_style"]))
	VehicleMesh.exhaust(root, Vector3(-0.45, 0.29, float(sedan["length"]) * 0.5 + 0.1))
	return root

## «Газель»: синяя кабина с капотом, чёрная рама, белый фургон с синей полосой; передняя ось под кабиной.
func _gazelle() -> Node3D:
	var root := Node3D.new()
	var spec: Dictionary = KINDS[kind]
	var meshes := _gazelle_meshes()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var overrides := {
		"paint": VehicleMesh.paint(spec["paint"], 0.25, 0.9, 0.35, 0.6),
		"paint2": VehicleMesh.paint(Color(0.86, 0.86, 0.84), 0.2, 0.8, 0.45, 0.4),
		"head": _head(), "tail": _tail,
	}
	VehicleMesh.instance(body, "BodyMesh", meshes["body"], overrides)
	VehicleMesh.instance(body, "Glass", meshes["glass"], {"glass": VehicleMesh.glass(0.04)}, false)
	var cabin := VehicleMesh.instance(body, "Interior", meshes["interior"], {}, false)
	cabin.visibility_range_end = 45.0
	VehicleMesh.instance(body, "Snow", meshes["snow"])
	var hl := size.z * 0.5
	_gazelle_plate(body, Vector3(0, 0.5, -hl - 0.13), PI, spec["plate"])
	_gazelle_plate(body, Vector3(0, 0.62, hl + 0.09), 0.0, spec["plate"])
	for x in [-1.0, 1.0]:
		for z in [-wheelbase * 0.5 - 0.45, wheelbase * 0.5 - 0.45]:   # передняя ось — под кабиной
			_wheels.append(VehicleMesh.add_wheel(root, Vector3(x * (size.x * 0.5 - 0.17), wheel_radius, z), wheel_radius, 0.21, "truck"))
	VehicleMesh.exhaust(root, Vector3(-0.62, 0.32, hl - 0.25))
	return root

func _gazelle_plate(parent: Node3D, at: Vector3, yaw: float, text: String) -> void:
	var label := _label(text, 48, Color(0.05, 0.05, 0.05))
	label.pixel_size = 0.0016
	label.position = at
	label.rotation.y = yaw
	label.visibility_range_end = 30.0
	parent.add_child(label)

func _gazelle_meshes() -> Dictionary:
	var found: Variant = VehicleMesh.cached("gazelle")
	if found != null:
		return found
	var b := VehicleMesh.Builder.new()
	var glass := VehicleMesh.Builder.new()
	var cabin := VehicleMesh.Builder.new()
	var snow := VehicleMesh.Builder.new()
	var hl := 2.75
	var w := 1.0
	var r := 0.36
	var arch := r + 0.08
	var front_axle := -2.9 * 0.5 - 0.45
	var rear_axle := 2.9 * 0.5 - 0.45
	var cab_back := -0.85
	# Кабина: нижняя часть лофтом с капотом-«мордой» и аркой передних колёс.
	var stations := VehicleMesh.hull_stations(hl * 2.0, w, [[-hl, 0.95], [-hl + 0.05, 1.06], [-2.25, 1.15], [-2.1, 1.2], [cab_back, 1.22]],
		[[-hl, 0.48], [-hl + 0.15, 0.42], [cab_back, 0.44]], [front_axle], r, arch, 0.14, 0.02, 0.02, 0.05, 0.08, 0.08)
	var cab_stations: Array = []
	for s in stations:
		if float(s[0]) <= cab_back + 0.001:
			cab_stations.append(s)
	b.loft("paint", cab_stations)
	# Верх кабины: стойки, крыша, задняя стенка; стёкла.
	var wsb := Vector2(1.21, -2.12)
	var wst := Vector2(2.0, -1.66)
	var gw := 0.96
	var rw := 0.9
	b.loft("paint", [
		[wst.y - 0.03, 1.97, 2.07, rw - 0.02, rw - 0.05, 0.01, 0.04],
		[wst.y + 0.04, 1.96, 2.1, rw + 0.02, rw, 0.01, 0.08],
		[cab_back, 1.96, 2.1, rw + 0.02, rw, 0.01, 0.08],
	], true, 3)
	b.box("paint", Vector3(rw * 2.0, 0.9, 0.04), Vector3(0, 1.66, cab_back - 0.02))
	for side in [-1.0, 1.0]:
		var s: float = side
		b.tube("paint", Vector3(s * gw, wsb.x, wsb.y), Vector3(s * rw, wst.x, wst.y), 0.04, 6)
		b.tube("paint", Vector3(s * (gw + 0.01), 1.22, cab_back + 0.05), Vector3(s * (rw + 0.01), 1.98, cab_back + 0.05), 0.05, 6)
		var out := Vector3(s, 0.08, 0).normalized()
		glass.pane("glass", Vector3(s * (gw - 0.005), 1.24, wsb.y + 0.12), Vector3(s * (gw - 0.005), 1.24, cab_back - 0.1),
			Vector3(s * (rw + 0.005), 1.94, cab_back - 0.1), Vector3(s * (rw + 0.005), 1.94, wst.y + 0.08), out, 0.0, 2, 1)
		# Большие зеркала на кронштейнах, ручка двери, подножка.
		var mirror := Vector3(s * (w + 0.2), 1.62, wsb.y + 0.15)
		b.tube("trim", Vector3(s * (w - 0.02), 1.3, wsb.y + 0.12), mirror + Vector3(0, -0.12, 0), 0.014, 4)
		b.tube("trim", Vector3(s * (w - 0.02), 1.85, wsb.y + 0.2), mirror + Vector3(0, 0.12, 0), 0.014, 4)
		b.rbox("trim", Vector3(0.06, 0.3, 0.16), mirror, 0.03)
		b.rbox("chrome", Vector3(0.014, 0.024, 0.12), Vector3(s * (w + 0.008), 1.12, cab_back - 0.2), 0.008)
		b.rbox("trim", Vector3(0.12, 0.04, 0.5), Vector3(s * (w - 0.02), 0.42, cab_back - 0.45), 0.015)
	var front_out := Vector3(0.0, wst.y - wsb.y, -(wst.x - wsb.x)).normalized()
	glass.pane("glass", Vector3(-gw + 0.04, wsb.x, wsb.y), Vector3(gw - 0.04, wsb.x, wsb.y),
		Vector3(rw - 0.03, wst.x - 0.01, wst.y), Vector3(-rw + 0.03, wst.x - 0.01, wst.y), front_out, 0.03, 6, 2)
	for x0 in [-0.8, -0.1]:
		b.tube("trim", Vector3(x0, wsb.x + 0.03, wsb.y + 0.03), Vector3(x0 + 0.6, wsb.x + 0.05, wsb.y + 0.05), 0.01, 4)
	# Перед: решётка, прямоугольные фары, поворотники, тяжёлый пластиковый бампер, номер.
	var fz := -hl
	b.rbox("trim", Vector3(0.86, 0.22, 0.03), Vector3(0, 0.8, fz - 0.01), 0.02)
	for y in [0.74, 0.8, 0.86]:
		b.box("chrome", Vector3(0.82, 0.014, 0.012), Vector3(0, y, fz - 0.03))
	for s in [-1.0, 1.0]:
		b.rbox("trim", Vector3(0.3, 0.19, 0.03), Vector3(s * 0.66, 0.8, fz - 0.006), 0.02)
		b.rbox("head", Vector3(0.25, 0.15, 0.02), Vector3(s * 0.65, 0.8, fz - 0.02), 0.02)
		b.rbox("lens_amber", Vector3(0.12, 0.06, 0.02), Vector3(s * 0.7, 0.64, fz - 0.07), 0.01)
	b.rbox("trim", Vector3(w * 2.0 + 0.06, 0.22, 0.14), Vector3(0, 0.55, fz - 0.05), 0.04)
	b.box("trim", Vector3(0.53, 0.122, 0.006), Vector3(0, 0.5, fz - 0.122))
	b.box("plate", Vector3(0.52, 0.112, 0.008), Vector3(0, 0.5, fz - 0.126))
	# Рама, бензобак, крылья над задними колёсами.
	for s in [-1.0, 1.0]:
		b.rbox("dark", Vector3(0.09, 0.16, hl - cab_back + 0.1), Vector3(s * 0.45, 0.62, (cab_back + hl) * 0.5 - 0.05), 0.02)
		b.rbox("dark", Vector3(0.3, 0.05, 1.0), Vector3(s * (w - 0.17), 0.84, rear_axle), 0.02)
		b.box("dark", Vector3(0.2, 0.26, 0.01), Vector3(s * (w - 0.17), 0.3, rear_axle + 0.52))
	b.rbox("steel", Vector3(0.3, 0.3, 0.7), Vector3(0.7, 0.55, 0.1), 0.08)
	b.box("dark", Vector3(1.0, 0.08, hl * 2.0 - 1.0), Vector3(0, 0.36, 0))
	# Фургон: короб со скруглёнными рёбрами, синяя полоса, задние двери с петлями и ручками, фонари на раме.
	b.loft("paint2", [
		[cab_back + 0.05, 0.98, 2.22, w, w - 0.01, 0.03, 0.04],
		[cab_back + 0.12, 0.95, 2.25, w + 0.02, w + 0.01, 0.03, 0.07],
		[hl - 0.06, 0.95, 2.25, w + 0.02, w + 0.01, 0.03, 0.07],
		[hl, 0.98, 2.22, w, w - 0.01, 0.03, 0.04],
	], true, 3)
	for s in [-1.0, 1.0]:
		b.rbox("paint", Vector3(0.012, 0.18, hl - cab_back - 0.3), Vector3(s * (w + 0.026), 1.35, (cab_back + hl) * 0.5), 0.005)
		b.box("chrome", Vector3(0.04, 0.12, 0.012), Vector3(s * 0.94, 1.35, hl + 0.006))
		b.box("chrome", Vector3(0.04, 0.12, 0.012), Vector3(s * 0.94, 1.9, hl + 0.006))
		b.rbox("trim", Vector3(0.22, 0.12, 0.05), Vector3(s * 0.78, 0.62, hl - 0.08), 0.015)
		b.rbox("tail", Vector3(0.12, 0.09, 0.02), Vector3(s * 0.82, 0.63, hl - 0.045), 0.01)
		b.rbox("lens_amber", Vector3(0.07, 0.09, 0.02), Vector3(s * 0.71, 0.63, hl - 0.045), 0.01)
	b.box("trim", Vector3(0.02, 1.2, 0.012), Vector3(0, 1.6, hl + 0.006))
	b.rbox("chrome", Vector3(0.03, 0.2, 0.03), Vector3(0.08, 1.45, hl + 0.016), 0.01)
	b.rbox("dark", Vector3(w * 2.0 - 0.1, 0.1, 0.1), Vector3(0, 0.55, hl - 0.04), 0.02)
	b.box("trim", Vector3(0.53, 0.122, 0.006), Vector3(0, 0.62, hl + 0.075))
	b.box("plate", Vector3(0.52, 0.112, 0.008), Vector3(0, 0.62, hl + 0.08))
	# Салон кабины: торпедо, руль, сиденья с подголовниками.
	cabin.rbox("dark", Vector3(gw * 2.0 - 0.1, 0.16, 0.32), Vector3(0, 1.3, wsb.y + 0.2), 0.04)
	var center := Vector3(-0.45, 1.45, wsb.y + 0.45)
	for k in 12:
		var t0 := TAU * k / 12.0
		var t1 := TAU * (k + 1) / 12.0
		var ay := Vector3(0, 0.6, -0.8)
		cabin.tube("dark", center + (Vector3.RIGHT * cos(t0) + ay * sin(t0)) * 0.2, center + (Vector3.RIGHT * cos(t1) + ay * sin(t1)) * 0.2, 0.016, 4)
	for x in [-0.45, 0.1, 0.55]:
		cabin.rbox("cloth", Vector3(0.42, 0.5, 0.12), Vector3(x, 1.45, cab_back - 0.2), 0.05)
		cabin.rbox("cloth", Vector3(0.24, 0.16, 0.1), Vector3(x, 1.8, cab_back - 0.18), 0.04)
	cabin.box("dark", Vector3(gw * 2.0 - 0.06, 0.004, cab_back - wsb.y), Vector3(0, 1.226, (wsb.y + cab_back) * 0.5))
	# Снег на крыше кабины, на фургоне и на капоте.
	snow.pillow("snow", Vector3(0, 0, (wst.y + cab_back) * 0.5), rw * 2.0 - 0.15, cab_back - wst.y - 0.1, 0.07, 2.1, 2.1, 5)
	snow.pillow("snow", Vector3(0, 0, (cab_back + hl) * 0.5), w * 2.0 - 0.1, hl - cab_back - 0.2, 0.13, 2.25, 2.25, 6, 9, 9)
	snow.pillow("snow", Vector3(0, 0, -2.42), w * 2.0 - 0.3, 0.5, 0.05, 1.12, 1.18, 7)
	var meshes := {
		"body": VehicleMesh.finish(b, {"paint": VehicleMesh.paint(KINDS[&"gazelle"]["paint"]), "paint2": VehicleMesh.paint(Color.WHITE),
			"head": VehicleMesh.mat("lens_white"), "tail": VehicleMesh.mat("lens_red")}),
		"glass": VehicleMesh.finish(glass, {"glass": VehicleMesh.glass()}),
		"interior": VehicleMesh.finish(cabin),
		"snow": VehicleMesh.finish(snow),
	}
	return VehicleMesh.store("gazelle", meshes)

class_name TrafficCar
extends PathVehicle
## Машина на кольце (ARENA-01, часть T): «Жигули», «Волга» или «Газель» из простых объёмов, как припаркованные
## машины квартала, но едущие: колёса крутятся, фары горят, габариты ярче при торможении, снег на крыше.
## kind задаётся до добавления в дерево. Скорость 9 м/с (C8). Перед — −Z.

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

func _ready() -> void:
	var spec: Dictionary = KINDS[kind]
	size = spec["size"]
	wheelbase = spec["wheelbase"]
	wheel_radius = spec["radius"]
	super._ready()

func _build_visual() -> Node3D:
	match kind:
		&"volga":
			return _sedan(true)
		&"gazelle":
			return _gazelle()
	return _sedan(false)

## «Жигули» — короткий угловатый седан; «Волга» — длиннее и ниже, с хромом и длинным багажником.
func _sedan(volga: bool) -> Node3D:
	var root := Node3D.new()
	var spec: Dictionary = KINDS[kind]
	var paint := _paint(spec["paint"])
	var glass := Materials.plain(Color(0.07, 0.08, 0.10), 0.1)
	var trim := Materials.plain(Color(0.10, 0.10, 0.11), 0.6)
	var chrome := Materials.plain(Color(0.60, 0.61, 0.63), 0.3)
	var snow := Materials.snow(0.0)
	var w := size.x
	var hl := size.z * 0.5
	var r := wheel_radius
	var belt := 0.95 if volga else 0.98            # верх нижнего пояса
	_box(root, "Body", Vector3(w, belt - r * 0.6, size.z), Vector3(0, r * 0.6 + (belt - r * 0.6) * 0.5, 0), paint)
	# Салон: стёкла и крыша; у «Волги» кабина длиннее и сдвинута назад, у «Жигулей» — ровно посередине.
	var cabin_len := 2.1 if volga else 1.9
	var cabin_z := 0.15 if volga else 0.2
	var roof_y := size.y
	_box(root, "Glass", Vector3(w - 0.12, roof_y - belt - 0.06, cabin_len), Vector3(0, belt + (roof_y - belt - 0.06) * 0.5, cabin_z), glass, false)
	_box(root, "Roof", Vector3(w - 0.16, 0.06, cabin_len - 0.4), Vector3(0, roof_y - 0.03, cabin_z), paint)
	for x in [-1.0, 1.0]:
		_box(root, "Pillar", Vector3(0.05, roof_y - belt, 0.08), Vector3(x * (w * 0.5 - 0.05), belt + (roof_y - belt) * 0.5, cabin_z), paint, false)
	_box(root, "Hood", Vector3(w - 0.06, 0.05, hl - cabin_len * 0.5 - 0.1), Vector3(0, belt + 0.02, -(hl + cabin_len * 0.5 - cabin_z) * 0.5 - 0.05), paint)
	_box(root, "SnowRoof", Vector3(w - 0.3, 0.1, cabin_len - 0.55), Vector3(0, roof_y + 0.05, cabin_z), snow)
	_box(root, "SnowTrunk", Vector3(w - 0.4, 0.05, 0.6), Vector3(0, belt + 0.03, hl - 0.55), snow)
	# Решётка, бамперы, номера, молдинги.
	_box(root, "Grille", Vector3(w * 0.55, 0.18, 0.04), Vector3(0, belt - 0.2, -hl - 0.01), chrome if volga else trim, false)
	if volga:
		_box(root, "Deer", Vector3(0.06, 0.08, 0.2), Vector3(0, belt + 0.07, -hl + 0.25), chrome, false)   # «олень» на капоте
	for z in [-hl - 0.04, hl + 0.04]:
		_box(root, "Bumper", Vector3(w + 0.08, 0.1, 0.1), Vector3(0, r + 0.12, z), chrome)
	for x in [-1.0, 1.0]:
		_box(root, "Molding", Vector3(0.02, 0.04, size.z - 0.4), Vector3(x * (w * 0.5 + 0.01), belt - 0.18, 0), chrome if volga else trim, false)
	_lights(root, w * 0.36, belt - 0.2, -hl - 0.02, hl + 0.02, Vector2(0.26, 0.16) if not volga else Vector2(0.2, 0.2))
	_plate(root, r + 0.25, -hl - 0.05, PI, spec["plate"])
	_plate(root, r + 0.3, hl + 0.05, 0.0, spec["plate"])
	for x in [-1.0, 1.0]:
		for z in [-wheelbase * 0.5, wheelbase * 0.5]:
			_wheel(root, Vector3(x * (w * 0.5 - 0.12), r, z), r, 0.2)
	return root

## «Газель» — кабина с капотом-«мордой» и высокий кузов-фургон.
func _gazelle() -> Node3D:
	var root := Node3D.new()
	var spec: Dictionary = KINDS[kind]
	var cab_paint := _paint(spec["paint"])
	var box_paint := _paint(Color(0.86, 0.86, 0.84), 0.6)
	var glass := Materials.plain(Color(0.07, 0.08, 0.10), 0.1)
	var trim := Materials.plain(Color(0.10, 0.10, 0.11), 0.6)
	var snow := Materials.snow(0.0)
	var w := size.x
	var hl := size.z * 0.5
	var r := wheel_radius
	# Кабина спереди (длина 1,9 м) с коротким капотом, кузов-фургон сзади.
	var cab_back := -hl + 1.9
	_box(root, "Nose", Vector3(w - 0.1, 0.55, 0.7), Vector3(0, r + 0.55, -hl + 0.35), cab_paint)
	_box(root, "Cab", Vector3(w - 0.06, 0.95, 1.25), Vector3(0, r + 0.5 + 0.475, cab_back - 0.62), cab_paint)
	var windshield := _box(root, "Windshield", Vector3(w - 0.2, 0.7, 0.04), Vector3(0, r + 1.25, -hl + 0.78), glass, false)
	windshield.rotation.x = deg_to_rad(-20.0)
	_box(root, "CabRoof", Vector3(w - 0.1, 0.5, 1.15), Vector3(0, r + 1.6, cab_back - 0.6), cab_paint)
	for x in [-1.0, 1.0]:
		_box(root, "SideWindow", Vector3(0.03, 0.5, 0.75), Vector3(x * (w * 0.5 - 0.02), r + 1.3, cab_back - 0.7), glass, false)
		_box(root, "Mirror", Vector3(0.08, 0.28, 0.14), Vector3(x * (w * 0.5 + 0.12), r + 1.25, -hl + 0.95), trim, false)
	_box(root, "Van", Vector3(w, size.y - r - 0.15, hl * 2.0 - 1.95), Vector3(0, r + 0.15 + (size.y - r - 0.15) * 0.5, (cab_back + hl) * 0.5 + 0.03), box_paint)
	_box(root, "VanStripe", Vector3(w + 0.02, 0.18, hl * 2.0 - 2.0), Vector3(0, r + 0.75, (cab_back + hl) * 0.5 + 0.03), cab_paint, false)
	_box(root, "SnowVan", Vector3(w - 0.3, 0.12, hl * 2.0 - 2.3), Vector3(0, size.y + 0.06, (cab_back + hl) * 0.5), snow)
	_box(root, "SnowCab", Vector3(w - 0.5, 0.06, 0.8), Vector3(0, r + 1.88, cab_back - 0.6), snow)
	_box(root, "Grille", Vector3(w * 0.5, 0.2, 0.04), Vector3(0, r + 0.5, -hl - 0.01), trim, false)
	for z in [-hl - 0.04, hl + 0.04]:
		_box(root, "Bumper", Vector3(w + 0.06, 0.14, 0.12), Vector3(0, r + 0.1, z), trim)
	_box(root, "RearDoorSeam", Vector3(0.02, size.y - r - 0.4, 0.02), Vector3(0, r + 0.15 + (size.y - r - 0.15) * 0.5, hl + 0.04), trim, false)
	_lights(root, w * 0.36, r + 0.5, -hl - 0.02, hl + 0.02)
	_plate(root, r + 0.12, -hl - 0.1, PI, spec["plate"])
	_plate(root, r + 0.35, hl + 0.06, 0.0, spec["plate"])
	for x in [-1.0, 1.0]:
		for z in [-wheelbase * 0.5 - 0.45, wheelbase * 0.5 - 0.45]:   # передняя ось — под кабиной
			_wheel(root, Vector3(x * (w * 0.5 - 0.14), r, z), r, 0.22)
	return root

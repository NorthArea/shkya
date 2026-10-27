extends RefCounted
## C1 — единственный источник координат квартала. Метры; x — восток, z — юг, y — вверх.
## Сцены и тесты берут точки только отсюда.

const BOUNDS := Rect2(-100.0, -125.0, 200.0, 250.0)  # x, z, ширина по x, длина по z

# Точки на земле (y = 0) и направления взгляда (yaw: 0 — на север, PI — на юг).
const SPAWN := Vector3(-40.0, 0.0, 99.0)
const SPAWN_YAW := PI
const BABKA := Vector3(-41.5, 0.0, 106.0)
const CAR_SPAWN := Vector3(-48.0, 0.0, 100.0)
const CAR_SPAWN_YAW := 0.0
const KIOSK := Vector3(55.0, 0.0, -77.0)
const VENDOR := Vector3(55.5, 0.0, -77.0)          # внутри киоска, за окном
const VENDOR_WINDOW := Vector3(59.0, 0.0, -77.0)   # где стоит покупатель
const KIOSK_ZONE := AABB(Vector3(56.0, 0.0, -87.0), Vector3(16.0, 3.0, 20.0))

# Маршруты для тестов: пешком от появления до окна киоска, на машине от стоянки до площадки.
const ROUTE_WALK: Array[Vector3] = [
	Vector3(-40, 0, 99), Vector3(-20, 0, 85), Vector3(-5, 0, 62), Vector3(0, 0, 32),
	Vector3(66, 0, 32), Vector3(66, 0, -70), Vector3(59, 0, -77),
]
const ROUTE_DRIVE: Array[Vector3] = [
	Vector3(-48, 0, 100), Vector3(-30, 0, 80), Vector3(-5, 0, 60), Vector3(0, 0, 32),
	Vector3(70, 0, 32), Vector3(70, 0, -70), Vector3(64, 0, -77),
]

# Коллизионные коробки: [имя, вид, центр по x/z, размер (x, высота, z)]. Низ всех коробок — на земле.
const SOLIDS := [
	# Двор
	["H1_South", "panel", Vector2(-40, 115), Vector3(100, 27, 14)],
	["H2_West", "panel", Vector2(-85, 76), Vector3(14, 27, 64)],
	["H3_North", "panel_low", Vector2(-51, 52), Vector3(54, 15, 12)],
	["Garages_Yard", "garage", Vector2(26, 85), Vector3(8, 3, 38)],
	["Fence_Yard", "fence", Vector2(16, 108), Vector3(12, 1.5, 0.3)],
	["Bench", "prop", Vector2(-34, 105), Vector3(3, 0.5, 0.8)],
	["Playground", "prop", Vector2(-60, 80), Vector3(12, 1, 10)],
	["Snow_YardWest", "snow", Vector2(-75, 80), Vector3(3, 0.8, 30)],
	# Вдоль улицы A
	["H4_SouthEast", "panel", Vector2(65, 66), Vector3(50, 27, 12)],
	["H5_North", "panel", Vector2(-50, 7), Vector3(80, 27, 14)],
	["H7_Middle", "panel_low", Vector2(10, -15), Vector3(30, 15, 40)],
	["Snow_StreetA", "snow", Vector2(-50, 22), Vector3(60, 0.8, 2)],
	["Zhiguli_A", "parked_car", Vector2(40, 37), Vector3(4.1, 1.4, 1.7)],
	# Вдоль улицы B
	["H6_West", "panel", Vector2(43, -14), Vector3(26, 27, 52)],
	["Garages_Kiosk", "garage", Vector2(46, -81), Vector3(8, 3, 38)],
	["Kiosk", "kiosk", Vector2(55, -77), Vector3(5, 3.2, 4)],
	["H8_East", "panel", Vector2(89, -47.5), Vector3(14, 27, 125)],
	["H9_NorthEnd", "panel_low", Vector2(65, -118.5), Vector3(70, 15, 13)],
	["H10_NorthWest", "panel", Vector2(-20, -80), Vector3(60, 27, 14)],
	["Zhiguli_B", "parked_car", Vector2(74, -30), Vector3(1.7, 1.4, 4.1)],
	# Столбы фонарей
	["Lamp_Yard", "lamp", Vector2(-52, 100), Vector3(0.25, 6, 0.25)],
	["Lamp_A1", "lamp", Vector2(-10, 41), Vector3(0.25, 6, 0.25)],
	["Lamp_A2", "lamp", Vector2(30, 41), Vector3(0.25, 6, 0.25)],
	["Lamp_B1", "lamp", Vector2(61, 0), Vector3(0.25, 6, 0.25)],
	["Lamp_B2", "lamp", Vector2(61, -50), Vector3(0.25, 6, 0.25)],
]

# Козырёк подъезда: висит над землёй, поэтому задан отдельно (центр, размер).
const CANOPY := [Vector3(-40, 3.1, 106.5), Vector3(4, 0.25, 3)]

# Плоские покрытия без коллизий: [имя, вид, центр по x/z, размер по x/z].
const SURFACES := [
	["Street_A", "road", Vector2(0, 32), Vector2(200, 14)],
	["Street_B", "road", Vector2(70, -42.5), Vector2(12, 135)],
	["Walk_A_North", "sidewalk", Vector2(0, 22.5), Vector2(200, 5)],
	["Walk_A_South", "sidewalk", Vector2(0, 41.5), Vector2(200, 5)],
	["Walk_B_West", "sidewalk", Vector2(61, -45), Vector2(6, 130)],
	["Walk_B_East", "sidewalk", Vector2(78.5, -45), Vector2(5, 130)],
	["Yard_Drive", "yard_road", Vector2(-20, 78), Vector2(56, 44)],
]

# Освещённые точки для greybox: [позиция, энергия].
const LAMPS := [
	[Vector3(-40, 2.9, 106.5), 2.0],   # подъезд
	[Vector3(-52, 5.8, 100), 3.0],
	[Vector3(-10, 5.8, 41), 3.0],
	[Vector3(30, 5.8, 41), 3.0],
	[Vector3(61, 5.8, 0), 3.0],
	[Vector3(61, 5.8, -50), 3.0],
	[Vector3(58.5, 3.0, -77), 2.5],    # окно киоска
]

static func ground_point(id: StringName) -> Vector3:
	match id:
		&"spawn": return SPAWN
		&"babka": return BABKA
		&"car": return CAR_SPAWN
		&"kiosk": return KIOSK
		&"vendor": return VENDOR_WINDOW
	return Vector3.INF

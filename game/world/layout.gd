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
	# Столб фонаря во дворе; уличные фонари строит street_lamps()
	["Lamp_Yard", "lamp", Vector2(-52, 100), Vector3(0.25, 6, 0.25)],
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

# Тёплые точки, кроме уличных фонарей: [позиция, энергия].
const LAMPS := [
	[Vector3(-40, 2.9, 106.5), 2.0],   # подъезд
	[Vector3(-52, 5.8, 100), 3.0],     # двор
	[Vector3(58.5, 3.0, -77), 2.5],    # окно киоска
]

# --- Декор с коллизиями (ART-02, ART-05): фонари, валы снега у обочин, берёзы, тополя, машины, указатель. Мини-карта их не рисует. ---

const LAMP_HEIGHT := 6.0
# Восточные фонари улицы B стоят у бордюра, в валу снега: между столбом и стеной H8 остаётся ~4,9 м,
# машина не зажимается в щели (ART-05, тест застреваний).
const LAMP_B_WEST := 61.0
const LAMP_B_EAST := 77.0
const BANK := Vector2(1.2, 0.9)        # ширина и высота вала снега
const TREES: Array[Vector2] = [
	Vector2(-66, 98), Vector2(-70, 64), Vector2(-56, 66), Vector2(-12, 102), Vector2(4, 96), Vector2(12, 76),
	Vector2(-80, 17), Vector2(-65, 17), Vector2(-35, 17), Vector2(-20, 17),
]
const STREET_SIGN := Vector2(60.5, 22.5)
# Тополя (ART-05, сверка ART-04: крупные тополя во дворах и вдоль улиц, кроны выше 4-этажек).
const POPLARS: Array[Vector2] = [
	Vector2(-95, 17), Vector2(-50, 17), Vector2(-5, 17), Vector2(20, 17), Vector2(40, 17), Vector2(90, 18),
	Vector2(34, 50), Vector2(52, 51), Vector2(72, 50), Vector2(92, 51),
	Vector2(-70, 102), Vector2(-64, 61), Vector2(-40, 62), Vector2(6, 104), Vector2(16, 90),
]
const POPLAR_TRUNK := Vector3(0.8, 10.0, 0.8)
# Опоры контактной сети без фонаря там, где фонари пропущены (выезд со двора, площадка киоска):
# поперечины висят на парах опор через каждые 24 м (сверка ART-04, черта 13).
const TROLLEY_POLES: Array[Vector2] = [Vector2(-18, 42), Vector2(6, 42), Vector2(61, -62), Vector2(61, -86)]
const POLE_HEIGHT := 8.0        # видимая высота столба фонаря и опоры; коллизия — LAMP_HEIGHT
# Припаркованные машины со снегом на крыше (ART-05, сверка ART-04): статичный декор, без поведения.
# [центр x/z, вдоль x — true]. От валов у бордюра — больше 1 м: ближе тест застреваний считает это щелью.
const PARKED: Array = [
	[Vector2(-56.5, 100), false], [Vector2(-60.5, 100.5), false], [Vector2(17, 80), false], [Vector2(17, 71.5), false],
	[Vector2(-2, 103), false], [Vector2(-60, 27.0), true], [Vector2(-45, 27.0), true],
	[Vector2(-75, 37.1), true], [Vector2(-50, 37.1), true],
	[Vector2(73.9, -5), false], [Vector2(73.9, -55), false], [Vector2(73.9, -100), false],
]

## Уличные фонари вдоль тротуаров, с пропусками у переходов маршрута. [центр x/z].
static func street_lamps() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for x in range(-90, 100, 24):
		points.append(Vector2(x, 22.0))                    # улица A, север
		if absf(x) > 26:
			points.append(Vector2(x, 42.0))                # улица A, юг (без выезда со двора)
	for z in range(10, -112, -24):
		if z > -60 or z < -94:
			points.append(Vector2(LAMP_B_WEST, z))         # улица B, запад (без площадки киоска)
		points.append(Vector2(LAMP_B_EAST, z))             # улица B, восток, у бордюра
	return points

## Валы снега вдоль обочин: [центр x/z, размер x/z]. Разрывы — выезд со двора, перекрёсток, площадка киоска.
static func snow_banks() -> Array:
	var banks := []
	var w := BANK.x
	for span in [[-100.0, 56.0, 24.4], [-100.0, -26.0, 39.6], [24.0, 100.0, 39.6]]:   # улица A: [x от, x до, z]
		var x: float = span[0]
		while x < span[1]:
			var length := minf(26.0, span[1] - x)
			banks.append([Vector2(x + length * 0.5, span[2]), Vector2(length, w)])
			x += length + 3.0
	for span in [[63.4, -110.0, -94.0], [63.4, -60.0, 19.0], [76.6, -110.0, 19.0]]:    # улица B: [x, z от, z до]
		var z: float = span[1]
		while z < span[2]:
			var length := minf(26.0, span[2] - z)
			banks.append([Vector2(span[0], z + length * 0.5), Vector2(w, length)])
			z += length + 3.0
	return banks

## Консоль уличного фонаря: смещение светильника от столба к проезжей части (сверка ART-04, черта 14).
const LAMP_ARM := 1.8
static func lamp_arm(p: Vector2) -> Vector2:
	if absf(p.y - 22.0) < 0.1:
		return Vector2(0, LAMP_ARM)       # улица A, север — к югу
	if absf(p.y - 42.0) < 0.1:
		return Vector2(0, -LAMP_ARM)      # улица A, юг — к северу
	if absf(p.x - LAMP_B_WEST) < 0.1:
		return Vector2(LAMP_ARM, 0)       # улица B, запад — к востоку
	return Vector2(-LAMP_ARM, 0)          # улица B, восток — к западу

## Все декоративные твёрдые коробки в формате SOLIDS.
static func decor_solids() -> Array:
	var solids := []
	for p in street_lamps():
		solids.append(["StreetLamp", "lamp", p, Vector3(0.25, LAMP_HEIGHT, 0.25)])
	for bank in snow_banks():
		solids.append(["SnowBank", "snow_bank", bank[0], Vector3(bank[1].x, BANK.y, bank[1].y)])
	for p in TREES:
		solids.append(["Birch", "tree", p, Vector3(0.3, 7.0, 0.3)])
	solids.append(["StreetSign", "sign_post", STREET_SIGN, Vector3(0.12, 3.2, 0.12)])
	for p in TROLLEY_POLES:
		solids.append(["TrolleyPole", "lamp", p, Vector3(0.25, LAMP_HEIGHT, 0.25)])
	for p in POPLARS:
		solids.append(["Poplar", "poplar", p, POPLAR_TRUNK])
	for car in PARKED:
		solids.append(["ParkedCar", "parked_car", car[0], Vector3(4.1, 1.4, 1.7) if car[1] else Vector3(1.7, 1.4, 4.1)])
	return solids

## SOLIDS + декор: для геометрии и проверок свободного места.
static func all_solids() -> Array:
	return SOLIDS + decor_solids()

static func ground_point(id: StringName) -> Vector3:
	match id:
		&"spawn": return SPAWN
		&"babka": return BABKA
		&"car": return CAR_SPAWN
		&"kiosk": return KIOSK
		&"vendor": return VENDOR_WINDOW
	return Vector3.INF

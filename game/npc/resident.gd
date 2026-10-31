class_name Resident
extends "res://game/npc/npc.gd"
## Житель города Н. (PEOPLE-01, часть B): ходит по замкнутому маршруту из точек (Layout.RESIDENT_*, C1)
## со скоростью SPEEDS[index], на отмеченных точках стоит PAUSES[index] с. Илюша ближе NOTICE_DISTANCE — житель
## останавливается на STARE_SECONDS и смотрит на него (look_at_target из npc.gd), потом идёт дальше; пока Илюша
## не отошёл дальше RELEASE_DISTANCE, второй раз не останавливается. Илюша прямо по ходу ближе BLOCK_DISTANCE — ждёт.
## Тело — AnimatableBody3D на слое Car (3-й, значение 4), маска 0: Илюша (маска World|Car) упирается в него и
## обходит, не толкает; транспорт кольца (датчик World|Player|Car) тормозит; луч наблюдателей (DetectionSensor,
## WORLD_MASK = 1) и пружина камеры (маска 1) его не видят — житель не укрытие (C7). «Лада» (маска World) сквозь
## тело проходит: при касании житель встаёт на ближайшую свободную точку маршрута (place), без рэгдолла; «Лада»
## стоит поперёк пути — житель разворачивается. Без случайностей: всё задаётся индексом и маршрутом.
##
## CITY-01 (часть P) — город живее. Роли задаёт Residents: пара (follower ходит «жёстко» за leader со сдвигом
## follow_offset — маршрут первого, сдвинутый на постоянный вектор; на разворотах впереди оказывается второй; всё, что
## касается пары — «Лада», Илюша, остановки, — решает первый), курящий (smoke_point: стоит SMOKE_SECONDS, время от
## времени поворачивается, потом уходит по маршруту и возвращается), пассажир (rider: ждёт троллейбус у wait_point, по
## doors_opened идёт к двери и исчезает, на другой остановке выходит из двери — Layout.RESIDENT_RIDER_B_PATH).
## Реакции: гудок (Residents → glance_at) — остановиться и посмотреть GLANCE_SECONDS. Пузыри-реплики над головой
## (как пузыри квеста) — TEXT-01: пулы QuestLines.street_lines(voice, событие), у каждого голоса (бабка, мужик, тётка,
## ребёнок — voice) свои. События: hit — «Лада» задела (_dodge_lada) или сбила (после подъёма); push — Илюша толкнул
## (on_pushed, не чаще PUSH_COOLDOWN); car — «Лада» с водителем ближе LADA_REACT_DISTANCE (и взгляд на неё) или гудок
## (Residents); walk — Илюша ближе PASS_PLAYER_DISTANCE; break — рядом сломали объект (Residents); idle — тихий пузырь
## (меньше и бледнее) стоящего (IDLE_STATES) раз в IDLE_SECONDS. Показ — bubble_seconds(): не меньше BUBBLE_SECONDS и
## QuestLines.read_seconds(). Не чаще BUBBLE_COOLDOWN на жителя (hit, push и break — вне очереди); видимый пузырь
## перебивает только более важное событие (KIND_PRIORITY); car/walk/idle ещё проходят общий лимит улицы (chatter —
## Residents.allow_chatter). Реплика — pick_line: общий «мешок» улицы (bag, LineBag), без повтора подряд.
## Случайности — только свой RandomNumberGenerator с seed SEED + индекс (реплики его не трогают).
##
## KNOCK-01 (решение владельца 29.10, идея Hit & Run, без крови и увечий): «Лада» быстрее KNOCK_MIN_SPEED сбивает
## жителя — состояние knocked, фазы fly → down → getup → back. Полёт — у узла Resident (парабола от точки удара: по ходу
## машины и от её центра, высота KNOCK_HEIGHT и дальность по скорости машины, скорость полёта не больше KNOCK_FLY_MAX;
## перед коробкой Layout.all_solids() полёт укорачивается — flight_distance), облик кувыркается (спрайт: billboard
## выключен, облик лицом к камере и вращается в плоскости экрана; 3D-тело: вокруг оси поперёк полёта) и ложится на снег:
## облако снежной пыли, «пуф»; лежит KNOCK_DOWN_SECONDS со снежинками над головой, встаёт KNOCK_RISE_SECONDS,
## отряхивается, говорит реплику HIT и возвращается на маршрут той же дорогой (back), дальше — как шёл.
## Пара: сбитый возвращается на своё место, второй тем временем стоит и смотрит на него. Медленнее KNOCK_MIN_SPEED —
## прежний отход (_dodge_lada).
## KNOCK-02 (жалобы владельца 30.10): сбивается любой видимый житель в любом состоянии — у дверей троллейбуса, только что
## вышедший на B, на переходе и на пути от остановки (board/alight/transit — после подъёма продолжает тот же путь; к
## двери, которая уже закрылась, — снова к остановке), сидящий (удар — по облику на сиденье), на занятии, в паре. Скрытые
## (подъезд, магазин, салон троллейбуса, за краем карты) — нет. Сбитый не бесплотен: тело включено и в полёте, и лёжа
## (капсула лежит вдоль полёта, KNOCK_LIE_RADIUS), и вставая — Илюша о него спотыкается, машины кольца тормозят;
## «Лада» быстрее KNOCK_MIN_SPEED сбивает его снова (новый подлёт с текущей высоты; между ударами не меньше
## KNOCK_REHIT_SECONDS — против двойного срабатывания одного удара), медленнее — толкает бампером (_lada_push) и
## притормаживает о него. Неуязвимости после подъёма нет.
## Очков, денег и штрафов нет. Звук — сигналы knock_launched/knock_landed (Residents → SoundDirector).
##
## LIFE-01 (решение владельца 29.10, вечер: «у каждого NPC цель и маршрут»): errand = true — житель живёт не по петле,
## а по цепочке целей. Residents даёт ему планировщик life (game/world/life.gd) и персону (дом и шаги). Маршрут route —
## текущий отрезок пути (открытая ломаная из life.path) с флагами route_flags: перед переходом проезжей части
## (&"cross") ждёт на бордюре (wait_cross), пока машины и автобус не дальше CROSS_CLEAR, «Лада» — не ближе и не едет,
## и идёт не останавливаясь; перед коридором пути игрока (&"route") ждёт, пока Илюша и «Лада» не дальше ROUTE_YIELD.
## Дошёл — занятие точки (_arrive): подъезд и магазин — скрыт (inside) и выходит из той же двери; окно, контейнеры,
## «козёл», капот, раскопка, ковёр — стоит лицом к объекту с короткой анимацией облика; лавка — сидит (облик на сиденье,
## тело выключено); дворник метёт вдоль дома; дети катаются с горки по петле Layout.LIFE_SLIDE_LOOP; остановка — ждёт
## троллейбус (дальше как пассажир CITY-01: выходит на B и уходит в «ГАСТРОНОМ», откуда выйдет позже); край карты —
## уходит, когда место вне кадра, и возвращается вне кадра или троллейбусом. Потом — следующий шаг цепочки.
## Сбит — встаёт, возвращается на точку удара и идёт к той же цели; «Лада» поперёк пути — разворот и новая цель.
## Второй в паре идёт по следу первого (FOLLOW_GAP позади, сбоку FOLLOW_SIDE). Дальше LOD_DISTANCE и вне кадра —
## обновление раз в LOD_STEP шагов физики с накопленным временем.
##
## PEOPLE-03 (P2, ARENA-02 «Жизнь»): занятия-точки той же цепочки целей. hockey — катается по коробке (Layout.
## LIFE_RINK_AREA) с клюшкой, шайба общая (life.hockey_step: ведёт, пас, бросок, отскок от ворот); snowball — лепит и
## кидает снежок в того, кто у крепости напротив (нет никого — в крепость), попавший вздрагивает, без вреда; trade —
## торговка стоит у прилавка лицом к тротуару (банки на прилавке — LifeProps); sled — тянет санки с внуком по петле
## Layout.LIFE_SLED_LOOP. Санки (carry = &"sled") всегда при жителе: едут позади на верёвке и прячутся с ним. Сбитый
## на хоккее или с санками (RESUME_KINDS) встаёт и продолжает занятие с места. Звуки занятий — сигнал activity_sound
## (Residents → SoundDirector): стук костяшки (domino), взмах метлы (sweep), скрип санок (sled), скрип горки (slide),
## клюшка (stick), шайба о борт (board). Реплики занятий — пулы QuestLines.activity_lines(вид) вместо idle и walk
## своего голоса (тот же «мешок» pick_line).

const DialogPanelScript = preload("res://game/ui/dialog_panel.gd")
const LineBagScript = preload("res://game/npc/line_bag.gd")
const Layout = preload("res://game/world/layout.gd")
const LifeScript = preload("res://game/world/life.gd")   # PEOPLE-03: константы хоккея

const SPEEDS: Array[float] = [1.2, 1.45, 1.35, 1.6, 1.3, 1.25, 1.5, 1.4, 1.5, 1.4, 1.3, 1.35, 1.25, 1.45,
	1.75, 1.4, 1.15, 1.3, 1.45, 1.8,
	1.7, 1.75, 1.65, 1.2, 1.15,
	1.3, 1.25, 1.2, 1.35, 1.3, 1.4, 1.35,
	1.25, 1.4, 1.6, 1.2, 1.3, 1.3, 1.15, 1.35, 1.2, 1.45, 1.55, 1.3,
	1.25, 1.4, 1.3, 1.2, 1.6, 1.45, 1.35, 1.25, 1.3, 1.2, 1.15, 1.3,
	1.25, 1.45, 1.3, 1.2, 1.15, 1.25, 1.35, 1.5]   # м/с; ARENA-03: 32 новых жителя, личные дела тихих улиц и дворов
const PAUSES: Array[float] = [4.0, 2.5, 3.5, 2.0, 3.0, 4.5, 2.5, 5.0, 2.5, 5.0, 3.0, 4.0, 5.0, 3.5, 2.0, 3.0, 4.0, 3.0, 3.5, 2.0,
	2.0, 2.5, 2.0, 4.0, 3.5, 3.0, 3.5, 4.0, 2.5, 3.0, 3.0, 3.5,
	3.0, 2.5, 2.0, 4.0, 3.0, 3.5, 4.0, 3.0, 3.5, 2.5, 2.0, 3.0,
	4.0, 3.0, 3.0, 3.5, 2.0, 2.5, 3.0, 3.5, 3.0, 4.0, 4.0, 3.5,
	3.0, 2.5, 3.0, 3.5, 4.0, 4.0, 3.0, 2.5]   # с, 2–5
const NOTICE_DISTANCE := 3.0
const RELEASE_DISTANCE := 4.0
const STARE_SECONDS := 2.0
const BLOCK_DISTANCE := 1.5
const BODY_LAYER := 4          # Car
const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.7
const LADA_MARGIN := 0.1       # м сверх габарита «Лады» и радиуса тела — касание
const LADA_CLEAR := 1.0        # м от габарита «Лады» до точки, куда встаёт житель
const LADA_LOOKAHEAD := 0.9    # м впереди по ходу: «Лада» там — разворот
const REVERSE_COOLDOWN := 2.0
# CITY-01 (часть P)
const SEED := 2910
const SMOKE_SECONDS := Vector2(40.0, 60.0)       # перекур у подъезда
const SMOKE_TURN_SECONDS := Vector2(3.0, 7.0)    # раз в столько курящий поворачивается
const GLANCE_SECONDS := 2.0                      # оглянуться на гудок или «Ладу»
const HORN_RADIUS := 20.0
const LADA_REACT_DISTANCE := 5.0
const BUBBLE_SECONDS := 2.0                      # минимум показа пузыря; длинная реплика — по QuestLines.read_seconds
const BUBBLE_COOLDOWN := 15.0
const PUSH_COOLDOWN := 2.6                       # толчки подряд: новая реплика не раньше, чем дочитана прошлая (≤ 2,55 с)
## TEXT-01: видимый пузырь перебивает только событие важнее; hit, push и break — вне очереди BUBBLE_COOLDOWN и лимита улицы.
const KIND_PRIORITY := {&"hit": 5, &"push": 4, &"break": 3, &"car": 2, &"walk": 1, &"idle": 0}
const EVENT_KINDS: Array[StringName] = [&"hit", &"push", &"break"]
const PASS_PLAYER_DISTANCE := 1.5                # Илюша вплотную — пузырь walk
const IDLE_SECONDS := Vector2(25.0, 45.0)        # бубнёж стоящего — раз в столько
const IDLE_STATES: Array[StringName] = [&"pause", &"smoke", &"wait_trolley", &"activity"]
const IDLE_SCALE := 0.8                          # тихий пузырь: меньше
const IDLE_ALPHA := 0.75                         # и бледнее
const BUBBLE_TIP_Y := 2.1                        # кончик хвостика — над шапкой (рост жителей 1,35–1,83 м)
const STOP_CATCH_DISTANCE := 8.0                 # пассажир ближе к месту ожидания — успевает на троллейбус
const BOARD_SPEED_FACTOR := 1.3                  # к двери — быстрым шагом
const DOOR_OUT := 0.45                           # м от борта: где пассажир исчезает и появляется
const CURB_BACK := 3.0                           # м от двери к тротуару: первая точка пути к двери
const BUS_CLEAR_DISTANCE := 14.0                 # троллейбус отъехал на столько — можно переходить улицу за ним
const CROSS_CLEAR := 12.0                        # м от середины перехода до ближайшей машины кольца — можно идти
## Двери троллейбуса в осях Trolleybus (перед −Z, двери +X): z передней, средней и задней (trolleybus.gd, _build_visual).
const DOOR_Z: Array[float] = [-4.1, -0.2, 4.05]
# Пузыри — как у QuestFlow (_build_bubble/_bubble_texture): бумага, чернильная кайма, хвостик вниз-влево, шрифт интерфейса.
const PAPER := Color(0.93, 0.87, 0.72)
const INK := Color(0.12, 0.10, 0.08)
const BUBBLE_FONT := 80
const BUBBLE_PIXEL := 0.0035
const BUBBLE_PAD := 34.0
const BUBBLE_TAIL := 56.0
const BUBBLE_DOWNSCALE := 2.0
const BUBBLE_WIDTH_STEP := 48.0                  # шаг ширины подложки, px шрифта
# KNOCK-01: сбивание «Ладой» без вреда.
const SNOW_PUFF_SHADER := preload("res://game/vehicles/slush_spray.gdshader")   # частицы пыли — как брызги PLAY-03
const KNOCK_MIN_SPEED := 3.0              # м/с «Лады»: медленнее — прежний отход (_dodge_lada)
const KNOCK_FULL_AT := 15.0               # м/с «Лады»: полная высота, больше оборотов, дольше лежит
const KNOCK_FLY_BASE := 1.5               # м/с полёта по горизонтали: BASE + GAIN · скорость машины,
const KNOCK_FLY_GAIN := 0.7
const KNOCK_FLY_MAX := 9.0                # но не больше
const KNOCK_HEIGHT := Vector2(1.5, 3.0)   # м подъёма ног: от KNOCK_MIN_SPEED до KNOCK_FULL_AT
const KNOCK_TURNS := Vector2(1.0, 1.75)   # оборотов в полёте, плюс четверть — лечь
const KNOCK_AWAY := 0.6                   # вес направления «от центра машины» к направлению её хода
const KNOCK_GRAVITY := 9.8
const KNOCK_SOLID_PAD := 0.2              # м сверх BODY_RADIUS до коробки all_solids(): там полёт кончается
const KNOCK_DOWN_SECONDS := Vector2(1.5, 2.5)   # лежит: от KNOCK_MIN_SPEED до KNOCK_FULL_AT
const KNOCK_RISE_SECONDS := 0.8
const KNOCK_SHAKE_SECONDS := 0.6          # отряхивается: два покачивания
const KNOCK_SHAKE_ANGLE := 0.16           # рад
const KNOCK_REHIT_SECONDS := 0.25        # KNOCK-02: между ударами — один удар не срабатывает дважды
const KNOCK_REHIT_POP := 0.6              # м: снова сбит в воздухе выше высоты подлёта — подскок хотя бы на столько
const KNOCK_LIE_RADIUS := 0.6             # м: лежащий и встающий занимают больше места, чем стоящий
const KNOCK_PUSH_PAD := 0.05              # м: бампер выталкивает лежащего на столько дальше габарита
const KNOCK_PUSH_DRAG := 2.5              # 1/с: «Лада», толкающая человека, теряет скорость
const KNOCK_TRANSIT: Array[StringName] = [&"board", &"alight", &"transit"]   # путь к двери и от двери: после — продолжить
const KNOCK_DOWN_CENTER := 0.42           # м: центр лежащего спрайта над снегом (3D-тело — KNOCK_DOWN_CENTER_3D)
const KNOCK_DOWN_CENTER_3D := 0.2
const KNOCK_HEAD := 0.5                   # м от центра облика до головы
const KNOCK_STARS := 4                    # снежинки над головой лежащего
const KNOCK_STAR_RADIUS := 0.3
const KNOCK_STAR_SPIN := 4.0              # рад/с
const KNOCK_STAR_LIFT := 0.3              # м над головой
const KNOCK_SNOW := Color(0.9, 0.93, 0.98)
const KNOCK_PHASES: Array[StringName] = [&"fly", &"down", &"getup"]   # облик под управлением сбивания
# LIFE-01: цели и маршруты.
const ROUTE_YIELD := 20.0                 # м: Илюша или «Лада» ближе к коридору пути игрока — ждать
const LADA_MOVING := 1.0                  # м/с: «Лада» быстрее — едет
const LOD_DISTANCE := 60.0                # м от камеры: дальше и вне кадра — упрощённое обновление
const LOD_STEP := 4                       # раз в столько шагов физики
const LOD_NEAR := 20.0                    # м: Илюша или «Лада» ближе — полное обновление и вне кадра
const FOLLOW_SIDE := 0.45                 # м: второй в паре — сбоку от следа первого
const TRAIL_STEP := 0.15                  # м между точками следа первого в паре
const SIT_DROP := 0.42                    # м: облик сидящего ниже (ноги за лавкой в снегу); сдвиг — Layout.LIFE_SIT
const SWEEP_SPEED := 0.45                 # м/с: дворник с метлой
const WORK_PERIODS := {&"dig": 1.8, &"carpet": 1.2, &"hood": 2.1}
const WORK_CONTACT := 0.55
const STEALTH_STAY := 30.0                # м: Илюша ближе к троллейбусу на остановке B — пассажир едет дальше, до A
const EDGE_RETRY := 3.0                   # с: край карты в кадре — подождать и проверить снова
const EDGE_VISIBLE_WAIT := 8.0            # с: на наблюдаемом краю оглядеться и продолжить свои дела пешком
const BUSY_KINDS: Array[StringName] = [&"slide", &"hockey", &"sled"]   # занятие в движении: на Илюшу и гудок не останавливается
# PEOPLE-03 (P2)
const HOCKEY_SPEED := 2.4                 # м/с: на коньках
const HOCKEY_REACH := Vector2(6.0, 4.0)   # м: катается не дальше от своего места (x, z)
const STICK_LEAD := 0.65                  # м: крюк клюшки впереди
const STICK_SIDE := 0.25                  # м: и правее
const SLED_SPEED := 0.85                  # м/с: тянет санки по петле
const SLED_BACK := 1.4                    # м: санки позади на верёвке
const SLED_CREAK_STEP := 1.2              # м пути санок между скрипами
const SNOWBALL_EVERY := Vector2(2.2, 4.2) # с между бросками
const SNOWBALL_FLIGHT := 0.9              # с полёта
const SNOWBALL_ARC := 1.6                 # м над прямой
const SNOWBALL_MOLD := 0.6                # с: лепит, присев, перед броском
const RESUME_KINDS: Array[StringName] = [&"hockey", &"sled"]   # сбитый — продолжает занятие с места
const SNOW_FORT_TOP := Vector3(-69.75, 1.1, 80.0)              # крепость Z3_5: снежок без адресата — сюда

@export var index := 0
var route: Array = []          # Vector3, замкнутая ломаная
var pause_points: Array = []   # индексы точек с паузой
var start_point := 0
var speed := 1.3
var pause_seconds := 3.0
## Илюша и «Лада» — задаёт Residents (в отдельном тесте могут быть null).
var player: Node3D
var lada: Node3D

var body: AnimatableBody3D
var state: StringName = &"walk"    # walk, pause, stare
var target_point := 0
var direction := 1
var distance_walked := 0.0
var stare_count := 0
var lada_bumps := 0
var turnarounds := 0
var _wait := 0.0
var _resume_state: StringName = &"walk"
var _resume_wait := 0.0
var _met := false
var _reverse_cooldown := 0.0

# CITY-01 (часть P): роли (задаёт Residents до add_child) и состояние.
var leader: Resident               # второй в паре: его двигает leader
var follower: Resident             # первый в паре: двигает второго
var follow_offset := Vector3.ZERO  # второй = первый + сдвиг (XZ)
var smoke_point := -1              # точка маршрута, где курит
var smoke_partner: Resident
var rider := false
var wait_point := -1               # точка маршрута, где пассажир ждёт троллейбус
var trolley: Node3D                # Trolleybus (может не быть — тогда ожидание = обычная пауза)
var rng := RandomNumberGenerator.new()
var voice: StringName = &"babka"   # голос реплик: &"babka", &"man", &"woman", &"kid" (QuestLines.VOICES)
var babka_voice: bool:              # совместимость: бабкин ли голос
	get:
		return voice == QuestLines.VOICE_BABKA
var bag: RefCounted                # LineBag — общий у Residents; нет — свой (pick_line)
var chatter: Node                  # Residents: общий лимит пузырей car/walk/idle на экране; нет — без лимита
var pushes := 0
var hidden := false                # в троллейбусе или в магазине
var glance_count := 0
var bubble_times: Array[float] = []
var bubble_text := ""
var bubble_kind: StringName = &""  # &"hit", &"push", &"car", &"walk", &"break", &"idle" — последний пузырь
var bubble_log: Array = []         # [время, вид, текст, состояние] — каждый пузырь
var events: Array = []             # пассажир: [время, &"board" / &"alight", остановка]
var clock := 0.0
var _bubble_left := 0.0
var _bubble_ready_at := 0.0
var _bubble_back: Sprite3D
var _bubble_label: Label3D
var _line_count := 0
var _last_text := ""
var _hit_ready_at := 0.0
var _push_ready_at := 0.0
var _idle_at := 0.0
var _turn_left := 0.0
var _transit: Array = []
var _transit_i := 0
var _transit_end: StringName = &""
var _transit_body_from := 0
var _transit_speed := 1.3
var _transit_yield_leg := -1
static var _bubble_cache := {}     # текст → ImageTexture
static var _bubble_shapes := {}    # округлённый размер текста → ImageTexture

# KNOCK-01
signal knock_launched(resident: Resident)
signal knock_landed(resident: Resident)
var knocks := 0
var knock_phase: StringName = &""  # &"fly", &"down", &"getup", &"back" (state == &"knocked"); &"" — не сбит
var knock_roll := 0.0              # угол облика: спрайт — в плоскости экрана, 3D — вокруг оси поперёк полёта, рад
var knock_from := Vector3.ZERO     # точка удара (на маршруте)
var knock_to := Vector3.ZERO       # точка приземления
var knock_car_speed := 0.0         # м/с «Лады» в момент удара
var knock_peak := 0.0              # м: высшая точка полёта
var knock_log: Array = []          # [время, фаза, позиция XZ]
var knock_dust: CPUParticles3D
# LIFE-01
var errand := false                # true — цепочка целей (Residents.LIFE), false — прежняя петля
var life                           # game/world/life.gd
var home := &""                    # подъезд персоны
var plan: Array = []               # шаги цепочки
var plan_start := 0                # начальная фаза личной цепочки (Life.PERSONAS), сохраняется при reset
var plan_i := 0
var spot_id := &""                 # текущая цель (точка интереса)
var route_flags: Array = []        # флаг отрезка route[i] → route[i + 1]
var visits: Array = []             # [время, точка] — дошёл
var activity_log: Array = []       # [время, вид занятия]
var goals := 0                     # сколько целей выбрано
var start_leg: Array = []          # стартовый отрезок (Layout.RESIDENT_ROUTES): после него — первая цель
var _act_kind := &""               # занятие на месте (activity, smoke, wait_trolley, inside, away)
var _acting := false
var _act_t := 0.0
var _social_token := ""
var _social_pose := {}
var _act_i := 0                    # точка петли горки / направление метлы
var _cross_ok := -1                # отрезок перехода, на который уже разрешено ступить
var _lod_acc := 0.0
var _lod_n := 0
var _trail: Array = []             # след первого в паре (Vector3, новые в конце)
var _broom: Node3D
var _work_tool: Node3D
# PEOPLE-03 (P2)
signal activity_sound(resident: Resident, kind: StringName)
signal entrance_used(resident: Resident, at: Vector3, entering: bool)
var carry := &""                   # всегда при себе: &"sled" — санки с внуком
var puck_timer := 0.0              # с до паса или броска, пока шайба у него (life.hockey_step)
var snowballs := 0                 # брошено снежков
var snow_hits := 0                 # попали в него
var resumes := 0                   # сбит на занятии и продолжил с места
var sound_counts := {}             # вид звука → сколько раз
var _act_target := Vector3.INF     # хоккей: куда катится
var _stick: Node3D
var _stick_swing := 0.0
var _sled: Node3D
var _sled_rope: MeshInstance3D
var _sled_moved := 0.0
var _ball: MeshInstance3D
var _ball_flight := {}
var _throw_in := 0.0
var _flinch := 0.0
var _resume_act := {}
var _knock_t := 0.0
var _knock_time := 1.0             # с полёта
var _knock_vy := 0.0
var _knock_dir := Vector3.FORWARD
var _knock_dist := 0.0
var _knock_spin := 0.0             # рад за полёт
var _knock_sign := 1.0             # +1 — летит вправо по экрану
var _knock_down := 2.0             # с лежит
var _knock_center := 0.0           # м: центр облика над узлом
var _knock_squash := Vector2.ONE
var _knock_last := -INF            # KNOCK-02: время прошлого удара
var _knock_roll0 := 0.0            # угол облика в начале полёта
var _knock_c0 := 0.0               # м: центр облика в начале полёта
var _knock_h0 := 0.0               # м: высота, с которой начался полёт (снова сбит в воздухе)
var _knock_prior: StringName = &""   # состояние до первого удара серии (board/alight/transit — продолжить путь)
var car_pushes := 0                # KNOCK-02: кадров, когда «Лада» толкала жителя бампером (для проверок)
var _knock_path: Array = []        # обратно на маршрут: точки XZ (последняя — на маршруте)
var _knock_resume := [0, 1]        # target_point, direction — куда шёл до удара
var _knock_waiting := false        # первый в паре ждёт сбитого второго
var _knock_stars: Node3D
var _knock_shadow: MeshInstance3D
static var _solid_rects: Array = []

func setup(resident_index: int, points: Array, pauses: Array, start: int) -> void:
	index = resident_index
	route = points
	pause_points = pauses
	start_point = start
	speed = SPEEDS[index % SPEEDS.size()]
	pause_seconds = PAUSES[index % PAUSES.size()]
	interaction_id = StringName("resident_%d" % index)   # только для фазы дыхания npc.gd; зона E выключена
	rng.seed = SEED + index * 7919
	_idle_at = _idle_interval()

func _ready() -> void:
	solid = false   # своё тело ниже: не StaticBody на слое World, как у npc.gd
	body_radius = BODY_RADIUS
	if not route.is_empty():
		position = _flat(route[start_point])
		target_point = _wrap(start_point + 1)
		facing_yaw = _yaw_to(route[target_point])
	super()
	interactable.enabled = false
	interactable.prompt = ""
	interactable.monitorable = false
	body = AnimatableBody3D.new()
	body.name = "Body"
	body.collision_layer = BODY_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = BODY_HEIGHT * 0.5
	body.add_child(collider)
	add_child(body)
	if smoke_point == start_point and not route.is_empty():
		_start_smoke()
	if errand:
		_errand_begin()

func _physics_process(delta: float) -> void:
	if route.size() < 2 or delta <= 0.0:
		return
	delta = _lod_delta(delta)
	if delta <= 0.0:
		return   # LIFE-01: далеко и вне кадра — копит время до следующего обновления
	clock += delta
	_tick_bubble(delta)
	if hidden:
		if errand and leader == null:
			_tick_hidden(delta)
		return   # в троллейбусе или в магазине: ждёт doors_opened
	_check_knock(delta)
	if state == &"knocked":
		_tick_knock(delta)
		return
	_react()
	if leader != null:
		if leader.state == &"knocked":
			look_at_target(leader)   # первого сбили: стоит и смотрит, пока тот не вернётся
		return   # второй в паре: его ставит первый (_mirror)
	_tick(delta)
	if carry != &"":
		_update_carry()
	_flinch = maxf(_flinch - delta, 0.0)
	if follower != null and errand:
		_record_trail()
	if follower != null and follower.state != &"knocked":
		follower._mirror(self)

func _tick(delta: float) -> void:
	_reverse_cooldown = maxf(_reverse_cooldown - delta, 0.0)
	if state == &"alight":
		_tick_alight()
		return
	if state == &"board" or state == &"transit":
		_tick_transit(delta)
		return
	if errand and spot_id != &"" and not life.anchor_intact(spot_id):
		_activity_done()
		return
	if _lada_touches_pair(global_position, LADA_MARGIN) and _lada_speed() < KNOCK_MIN_SPEED:
		_dodge_lada()
		return
	if follower != null and follower.state == &"knocked":
		look_at_target(follower)   # второго сбили: ждёт его на месте
		_knock_waiting = true
		return
	if _knock_waiting:
		_knock_waiting = false
		stop_looking()
	var to_player := _player_distance()
	if to_player > RELEASE_DISTANCE:
		_met = false
	if state == &"stare":
		_wait -= delta
		if _wait <= 0.0:
			_met = true
			stop_looking()
			state = _resume_state
			_wait = _resume_wait
		return
	if to_player < NOTICE_DISTANCE and not _met and not _busy():
		if state != &"glance":   # из оглядки — вернуться туда, откуда оглядывался
			_resume_state = state
			_resume_wait = _wait
		state = &"stare"
		_wait = STARE_SECONDS
		stare_count += 1
		look_at_target(player)
		return
	if state == &"glance":
		_wait -= delta
		if _wait <= 0.0:
			stop_looking()
			state = _resume_state
			_wait = _resume_wait
		return
	if state == &"pause":
		_wait -= delta
		if _wait <= 0.0:
			state = &"walk"
			target_point = _wrap(target_point + direction)
		return
	if state == &"smoke":
		_wait -= delta
		_turn_left -= delta
		if _turn_left <= 0.0:
			_turn_left = rng.randf_range(SMOKE_TURN_SECONDS.x, SMOKE_TURN_SECONDS.y)
			facing_yaw = _smoke_yaw()
		if _wait <= 0.0:
			if errand:
				_activity_done()
				return
			state = &"walk"
			target_point = _wrap(target_point + direction)
		return
	if state == &"wait_trolley":
		return   # уходит только по doors_opened (on_doors_opened)
	if state == &"activity":
		_tick_activity(delta)
		return
	if state == &"wait_cross":
		_tick_wait_cross()
		return
	_walk(delta, to_player)

func _walk(delta: float, to_player: float) -> void:
	var here := _flat(global_position)
	if errand and _crossing_ahead(here):
		return
	var goal := _flat(route[target_point])
	var to := goal - here
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.ZERO
	if dir != Vector3.ZERO:
		facing_yaw = atan2(-dir.x, -dir.z)
	# Илюша прямо по ходу: стоим и смотрим, пока не отойдёт (он обходит, житель в него не входит).
	if to_player < BLOCK_DISTANCE and dir != Vector3.ZERO and _player_in_way(dir):
		look_at_target(player)
		return
	if _look_target == player and to_player >= BLOCK_DISTANCE:
		stop_looking()
	# «Лада» стоит поперёк пути: разворот к предыдущей точке.
	if dir != Vector3.ZERO and _lada_touches_pair(here + dir * LADA_LOOKAHEAD, LADA_MARGIN):
		if _reverse_cooldown <= 0.0:
			direction = -direction
			target_point = _wrap(target_point + direction)
			_reverse_cooldown = REVERSE_COOLDOWN
			turnarounds += 1
		return
	var step := speed * delta
	if dist <= step:
		global_position = goal
		distance_walked += dist
		if errand:
			_on_errand_point()
			return
		if target_point == smoke_point:
			_start_smoke()
		elif target_point == wait_point and rider and is_instance_valid(trolley):
			state = &"wait_trolley"
			facing_yaw = _yaw_to(trolley_from())
		elif pause_points.has(target_point):
			state = &"pause"
			_wait = pause_seconds
		else:
			target_point = _wrap(target_point + direction)
		return
	global_position = here + dir * step
	distance_walked += step

## Поставить на точку маршрута (касание «Лады», перезапуск): без скорости и без интерполяции рывка.
func place(point: Vector3) -> void:
	global_position = _flat(point)
	reset_physics_interpolation()

## Перезапуск: на старт, к следующей точке, счётчики — с нуля.
func reset_to_start() -> void:
	if errand:
		_act_stop()
		route = start_leg.duplicate()
		route_flags = [&""]
	state = &"walk"
	direction = 1
	_met = false
	_wait = 0.0
	_reverse_cooldown = 0.0
	stop_looking()
	target_point = _wrap(start_point + 1)
	place(route[start_point])
	facing_yaw = _yaw_to(route[target_point])
	distance_walked = 0.0
	rng.seed = SEED + index * 7919
	_show()
	_transit.clear()
	events.clear()
	glance_count = 0
	bubble_times.clear()
	bubble_log.clear()
	bubble_text = ""
	bubble_kind = &""
	_bubble_left = 0.0
	_bubble_ready_at = clock
	_hit_ready_at = clock
	_push_ready_at = clock
	pushes = 0
	_line_count = 0
	_last_text = ""
	_idle_at = clock + _idle_interval()
	if _bubble_back:
		_bubble_back.visible = false
	_knock_reset()
	if smoke_point == start_point:
		_start_smoke()
	if errand:
		_errand_reset()
	if follower != null:
		follower._mirror(self)

## Длина замкнутого маршрута, м.
func loop_length() -> float:
	var total := 0.0
	for i in route.size():
		total += _flat(route[i]).distance_to(_flat(route[_wrap(i + 1)]))
	return total

## «Лада» задела: на ближайшую точку маршрута (шаг 0,5 м), свободную от её габарита на LADA_CLEAR, и дальше — от неё.
func _dodge_lada() -> void:
	if errand:
		_act_stop()
	var found := _nearest_free_point(_flat(global_position))
	var best: Vector3 = found[0]
	var best_seg: int = found[1]
	lada_bumps += 1
	if clock >= _hit_ready_at:
		_hit_ready_at = clock + BUBBLE_COOLDOWN
		_speak(&"hit")
	stop_looking()
	state = &"walk"
	if best_seg < 0:
		direction = 1
		target_point = _wrap(start_point + 1)
		place(route[start_point])
		return
	place(best)
	var resume := _resume_from(best, best_seg)
	target_point = resume[0]
	direction = resume[1]

## Ближайшая к here точка маршрута (шаг 0,5 м), свободная от габарита «Лады» на LADA_CLEAR: [точка, отрезок] или [INF, −1].
func _nearest_free_point(here: Vector3) -> Array:
	var best := Vector3.INF
	var best_d := INF
	var best_seg := -1
	for k in (route.size() - 1 if errand else route.size()):   # LIFE-01: отрезок пути открыт
		var a := _flat(route[k])
		var b := _flat(route[_wrap(k + 1)])
		var n := maxi(1, ceili(a.distance_to(b) / 0.5))
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			if _lada_touches_pair(p, LADA_CLEAR):
				continue
			var d := p.distance_to(here)
			if d < best_d:
				best_d = d
				best = p
				best_seg = k
	return [best, best_seg]

## С точки best на отрезке best_seg — дальше от «Лады»: [target_point, direction].
func _resume_from(best: Vector3, best_seg: int) -> Array:
	var away := best - _flat(lada.global_position)
	if (_flat(route[_wrap(best_seg + 1)]) - best).dot(away) >= 0.0:
		return [_wrap(best_seg + 1), 1]
	return [best_seg, -1]

## Точка p (XZ) ближе margin + BODY_RADIUS к габариту «Лады».
func _lada_touches(p: Vector3, margin: float, radius := BODY_RADIUS) -> bool:
	if not is_instance_valid(lada):
		return false
	var local := lada.global_transform.affine_inverse() * Vector3(p.x, lada.global_position.y, p.z)
	var half := Lada.SIZE * 0.5
	return absf(local.x) < half.x + radius + margin and absf(local.z) < half.z + radius + margin

## До Илюши; у первого в паре — до ближнего из двоих.
func _player_distance() -> float:
	if not is_instance_valid(player) or not player.is_visible_in_tree():
		return INF
	var p := player.global_position
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	if follower != null:
		var f := global_position + follow_offset
		d = minf(d, Vector2(p.x - f.x, p.z - f.z).length())
	return d

## Илюша прямо по ходу (dir) у жителя или у второго в паре — ближе BLOCK_DISTANCE.
func _player_in_way(dir: Vector3) -> bool:
	var spots: Array[Vector3] = [_flat(global_position)]
	if follower != null:
		spots.append(_flat(global_position + follow_offset))
	for here in spots:
		var to_him := _flat(player.global_position) - here
		if to_him.length() < BLOCK_DISTANCE and (to_him.length() < 0.01 or dir.dot(to_him.normalized()) > 0.3):
			return true
	return false

## Точка p (XZ) или место второго в паре при первом в p — касается «Лады».
func _lada_touches_pair(p: Vector3, margin: float) -> bool:
	return _lada_touches(p, margin) or (follower != null and _lada_touches(p + follow_offset, margin))

func _wrap(i: int) -> int:
	return posmod(i, route.size())

func _yaw_to(point: Vector3) -> float:
	var to := _flat(point) - _flat(position)
	return atan2(-to.x, -to.z) if to.length() > 0.001 else facing_yaw

static func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)

# =====================================================================================
# CITY-01 (часть P): пары, перекур, троллейбус, реакции, пузыри
# =====================================================================================

## Второй в паре: место первого + сдвиг, то же состояние, тот же взгляд.
func _mirror(lead: Resident) -> void:
	if errand and lead.errand:
		_mirror_trail(lead)
		return
	global_position = _flat(lead.global_position) + Vector3(follow_offset.x, 0.0, follow_offset.z)
	state = lead.state
	direction = lead.direction
	target_point = lead.target_point
	facing_yaw = lead.facing_yaw
	_look_target = lead._look_target
	distance_walked = lead.distance_walked
	stare_count = lead.stare_count
	lada_bumps = lead.lada_bumps
	turnarounds = lead.turnarounds

func _start_smoke() -> void:
	state = &"smoke"
	target_point = smoke_point   # стоит на ней; после перекура — к следующей (и со старта тоже)
	_wait = rng.randf_range(SMOKE_SECONDS.x, SMOKE_SECONDS.y)
	_turn_left = rng.randf_range(SMOKE_TURN_SECONDS.x, SMOKE_TURN_SECONDS.y)
	facing_yaw = _smoke_yaw()

## Куда смотрит курящий: на напарника, если тот тоже курит (чаще), во двор, на дверь, вдоль дома; не туда же, где был.
func _smoke_yaw() -> float:
	var options: Array[float] = [PI, PI * 0.5, -PI * 0.5]
	if is_instance_valid(smoke_partner) and smoke_partner.state == &"smoke" and not smoke_partner.hidden:
		var to := _flat(smoke_partner.global_position) - _flat(global_position)
		if to.length() > 0.1:
			options.append(atan2(-to.x, -to.z))
			options.append(atan2(-to.x, -to.z))
	var yaw := facing_yaw
	for attempt in 4:
		yaw = options[rng.randi_range(0, options.size() - 1)] + rng.randf_range(-0.25, 0.25)
		if absf(angle_difference(yaw, facing_yaw)) > 0.5:
			break
	return yaw

## Оглянуться на target (гудок, «Лада») на seconds: остановиться и смотреть, потом дальше. Второй в паре — через первого.
func glance_at(target: Node3D, seconds := GLANCE_SECONDS) -> bool:
	if leader != null:
		return leader.glance_at(target, seconds)
	if hidden or _busy() or not state in [&"walk", &"pause", &"smoke", &"wait_trolley", &"glance", &"activity", &"wait_cross"]:
		return false
	if state != &"glance":
		_resume_state = state
		_resume_wait = _wait
	state = &"glance"
	_wait = seconds
	look_at_target(target)
	glance_count += 1
	if follower != null:
		follower._mirror(self)
	return true

## Пузыри car, walk и idle, не чаще BUBBLE_COOLDOWN. Касание «Лады» — не здесь: hit говорит _dodge_lada (первый в паре).
func _react() -> void:
	if clock < _bubble_ready_at:
		return
	if _lada_touches_pair(global_position, LADA_MARGIN):
		return
	if is_instance_valid(lada) and lada.get("driver") != null:
		var to := lada.global_position - global_position
		if Vector2(to.x, to.z).length() <= LADA_REACT_DISTANCE:
			if _speak(&"car"):
				glance_at(lada)
			return
	if _acting and _act_kind in [&"chat", &"domino"]:
		return   # реплика занятия — только партнёру и в свою очередь; реакции на события остаются выше
	if _player_distance() < PASS_PLAYER_DISTANCE:
		_speak(&"walk")
		return
	if state in IDLE_STATES and clock >= _idle_at:
		_speak(&"idle")

## Пузырь события kind из пула своего голоса; idle — тихий. false — не показан (перебить нечем или лимит улицы).
func _speak(kind: StringName) -> bool:
	if not can_show(kind):
		return false
	say(pick_line(kind), kind == &"idle")
	bubble_kind = kind
	bubble_log.append([clock, kind, bubble_text, state])
	_bubble_ready_at = clock + BUBBLE_COOLDOWN
	_idle_at = clock + _idle_interval()
	if chatter != null and chatter.has_method(&"note_bubble"):
		chatter.note_bubble(self, kind)
	return true

## Можно ли сейчас показать пузырь kind: видимый недочитанный перебивается только более важным событием;
## car/walk/idle ещё спрашивают общий лимит улицы.
func can_show(kind: StringName) -> bool:
	if _bubble_left > 0.0 and KIND_PRIORITY.get(kind, 0) <= KIND_PRIORITY.get(bubble_kind, 0):
		return false
	if not kind in EVENT_KINDS and chatter != null and chatter.has_method(&"allow_chatter"):
		return chatter.allow_chatter(self)
	return true

## Внешнее событие (Residents): break — поломка рядом, car — гудок. car ждёт BUBBLE_COOLDOWN, break — нет.
func speak_event(kind: StringName) -> bool:
	if hidden or state == &"knocked":
		return false
	if not kind in EVENT_KINDS and clock < _bubble_ready_at:
		return false
	return _speak(kind)

## Илюша толкнул (удар пешком, Residents по Ilyusha.punch_landed): обернуться и сказать реплику push, не чаще
## PUSH_COOLDOWN. Механики сверх реплики и взгляда нет.
func on_pushed() -> bool:
	if hidden or state == &"knocked":
		return false
	pushes += 1
	if clock < _push_ready_at:
		return false
	if not _speak(&"push"):
		return false
	_push_ready_at = clock + PUSH_COOLDOWN
	if is_instance_valid(player):
		glance_at(player)
	return true

## Реплика события kind своего голоса из «мешка» (общего у улицы или своего); подряд у жителя не повторяется.
## PEOPLE-03: на занятии со своим пулом (QuestLines.activity_lines: домино, торговка, санки, хоккей, снежки) idle и
## walk берутся из него — тот же мешок под ключом «activity/вид».
func pick_line(kind: StringName) -> String:
	var lines := QuestLines.street_lines(voice, kind)
	var key := StringName("%s/%s" % [voice, kind])
	if _acting and (kind == &"idle" or kind == &"walk"):
		var activity_kind := &"dig_watch" if _act_kind == &"dig" and spot_id != &"dig_1" else _act_kind
		var own: Array = QuestLines.activity_lines(activity_kind)
		if not own.is_empty():
			lines = own
			key = StringName("activity/%s" % activity_kind)
	if bag == null:
		bag = LineBagScript.new(SEED + index)
	var text: String = bag.next(key, lines)
	if text == _last_text and lines.size() > 1:
		text = bag.next(key, lines)
	_line_count += 1
	_last_text = text
	return text

## Через сколько секунд следующий бубнёж: IDLE_SECONDS по hash(SEED, индекс, счётчик).
func _idle_interval() -> float:
	var k := posmod(hash([SEED, index, _line_count, &"idle"]), 1000) / 999.0
	return lerpf(IDLE_SECONDS.x, IDLE_SECONDS.y, k)

## Пузырь над головой на bubble_seconds(text); quiet — тихий (IDLE_SCALE, IDLE_ALPHA).
func say(text: String, quiet := false) -> void:
	if _bubble_back == null:
		_bubble_back = Sprite3D.new()
		_bubble_back.name = "BubbleBack"
		_bubble_back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble_back.no_depth_test = true
		_bubble_back.shaded = false
		_bubble_back.pixel_size = BUBBLE_PIXEL * BUBBLE_DOWNSCALE
		_bubble_back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		_bubble_back.render_priority = 1
		add_child(_bubble_back)
		_bubble_label = Label3D.new()
		_bubble_label.name = "Bubble"
		_bubble_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble_label.no_depth_test = true
		_bubble_label.pixel_size = BUBBLE_PIXEL
		_bubble_label.font = DialogPanelScript.ui_font()
		_bubble_label.font_size = BUBBLE_FONT
		_bubble_label.outline_size = 0
		_bubble_label.modulate = INK
		_bubble_label.render_priority = 2
		_bubble_label.position = Vector3(0, BUBBLE_TAIL * 0.5 * BUBBLE_PIXEL, 0)   # в середине тела пузыря, над хвостиком
		_bubble_back.add_child(_bubble_label)
	var k := IDLE_SCALE if quiet else 1.0
	var alpha := IDLE_ALPHA if quiet else 1.0
	_bubble_back.texture = bubble_texture(text)
	_bubble_back.scale = Vector3.ONE * k
	_bubble_back.modulate = Color(1, 1, 1, alpha)
	_bubble_back.position = Vector3(0, BUBBLE_TIP_Y + _bubble_back.texture.get_height() * _bubble_back.pixel_size * 0.5 * k, 0)
	_bubble_label.modulate = Color(INK, alpha)
	_bubble_label.text = text
	_bubble_back.visible = true
	_bubble_left = bubble_seconds(text)
	bubble_text = text
	bubble_times.append(clock)

## Сколько висит пузырь с текстом text: не меньше BUBBLE_SECONDS и времени чтения (TEXT-01).
static func bubble_seconds(text: String) -> float:
	return maxf(BUBBLE_SECONDS, QuestLines.read_seconds(text))

func bubble_visible() -> bool:
	return _bubble_back != null and _bubble_back.visible and is_visible_in_tree()

func _tick_bubble(delta: float) -> void:
	if _bubble_left <= 0.0:
		return
	_bubble_left -= delta
	if _bubble_left <= 0.0 and _bubble_back:
		_bubble_back.visible = false

## Подложка пузыря с хвостиком — один раз на текст (рисуется по пикселям, как QuestFlow._bubble_texture).
## TEXT-01: подложки — по ширине текста, округлённой вверх до BUBBLE_WIDTH_STEP: сотни реплик дают пару десятков
## подложек (рисовка по пикселям дорогая), текст Label3D лежит по центру.
static func bubble_texture(text: String) -> ImageTexture:
	if _bubble_cache.has(text):
		return _bubble_cache[text]
	var font := DialogPanelScript.ui_font()
	var raw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT)
	var text_size := Vector2(ceilf(raw.x / BUBBLE_WIDTH_STEP) * BUBBLE_WIDTH_STEP, ceilf(raw.y))
	var shape_key := Vector2i(text_size)
	if _bubble_shapes.has(shape_key):
		_bubble_cache[text] = _bubble_shapes[shape_key]
		return _bubble_shapes[shape_key]
	var k := 1.0 / BUBBLE_DOWNSCALE
	var body_size := Vector2(text_size.x + 2.0 * BUBBLE_PAD, text_size.y + 2.0 * BUBBLE_PAD) * k
	var tail := BUBBLE_TAIL * k
	var w := int(ceil(body_size.x)) + 4
	var h := int(ceil(body_size.y + tail)) + 4
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var radius := 14.0 * k
	var border := 7.0 * k
	var half := body_size * 0.5
	var center := Vector2(w * 0.5, 2.0 + half.y)
	var t0 := Vector2(center.x - body_size.x * 0.16, center.y + half.y - border)
	var t1 := Vector2(center.x - body_size.x * 0.02, center.y + half.y - border)
	var t2 := Vector2(center.x - body_size.x * 0.22, center.y + half.y + tail - 1.0)
	var tri := PackedVector2Array([t0, t1, t2])
	var tail_box := Rect2(t0, Vector2.ZERO).expand(t1).expand(t2).grow(1.0)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - center).abs() - half + Vector2(radius, radius)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var in_tail := tail_box.has_point(p) and Geometry2D.is_point_in_polygon(p, tri)
			if d <= -border or (in_tail and d > -border and _tail_inner(p, tri, border)):
				image.set_pixel(x, y, PAPER)
			elif d <= 0.0 or in_tail:
				image.set_pixel(x, y, INK)
	var texture := ImageTexture.create_from_image(image)
	_bubble_cache[text] = texture
	_bubble_shapes[shape_key] = texture
	return texture

static func _tail_inner(p: Vector2, tri: PackedVector2Array, border: float) -> bool:
	for edge in [[tri[1], tri[2]], [tri[2], tri[0]]]:
		if Geometry2D.get_closest_point_to_segment(p, edge[0], edge[1]).distance_to(p) < border:
			return false
	return true

# --- троллейбус (пассажир) ---

## Откуда приходит троллейбус к месту ожидания — туда смотрит ждущий (на 20 м назад по ходу от остановки A — восток).
func trolley_from() -> Vector3:
	if errand:
		return _flat(global_position) + Vector3(20.0, 0.0, 0.0)
	return _flat(route[wait_point]) + Vector3(20.0, 0.0, 0.0)

## Точка у двери door (0 — передняя, 1 — средняя, 2 — задняя) снаружи борта, на земле.
static func door_point(bus: Node3D, door: int) -> Vector3:
	var local := Vector3(Trolleybus.BODY.z * 0.5 + DOOR_OUT, 0.0, DOOR_Z[door])
	return _flat(bus.global_transform * local)

func on_doors_opened(stop: int) -> void:
	if not rider or not is_instance_valid(trolley):
		return
	if errand:
		_errand_doors_opened(stop)
		return
	if stop == 0 and state == &"shop":
		_alight(0)
	elif stop == 0 and _wants_bus():
		_board()
	elif stop == 1 and state == &"ride":
		_alight(1)

func on_doors_closed(stop: int) -> void:
	if rider and stop == 0 and state == &"board":
		_hide(&"ride")   # не дошёл пару шагов — запрыгнул
		events.append([clock, &"board", 0])

func _wants_bus() -> bool:
	if hidden or wait_point < 0:
		return false
	if state == &"wait_trolley":
		return true
	return state in [&"walk", &"pause", &"glance", &"stare"] \
		and _flat(global_position).distance_to(_flat(route[wait_point])) <= STOP_CATCH_DISTANCE

## К ближайшей двери: с тротуара напротив неё — в дверь, там исчезает.
func _board() -> void:
	var best := 0
	for door in DOOR_Z.size():
		if door_point(trolley, door).distance_to(_flat(global_position)) < door_point(trolley, best).distance_to(_flat(global_position)):
			best = door
	var door_at := door_point(trolley, best)
	var out := _flat(trolley.global_transform.basis.x).normalized()
	stop_looking()
	_start_transit([door_at + out * CURB_BACK, door_at], &"ride", 0, speed * BOARD_SPEED_FACTOR)
	state = &"board"

## Выйти на остановке stop: B — из передней двери, ждать, пока троллейбус отъедет, перейти улицу и уйти в «ГАСТРОНОМ»;
## A — из задней двери на тротуар и обратно на маршрут.
func _alight(stop: int) -> void:
	var door_at := door_point(trolley, 0 if stop == 1 else 2)
	var out := _flat(trolley.global_transform.basis.x).normalized()
	_show()
	place(door_at)
	facing_yaw = atan2(-out.x, -out.z)
	events.append([clock, &"alight", stop])
	if stop == 1:
		body.collision_layer = 0   # у края парковки KIOSK_ZONE: тело выключено, пока не перешёл к первой точке пути
		state = &"alight"
		return
	if errand:
		_start_transit([door_at + out * CURB_BACK], &"route", 0, speed)
	else:
		_start_transit([door_at + out * CURB_BACK, _flat(route[0])], &"route", 0, speed)
	state = &"transit"

func _tick_alight() -> void:
	if trolley.get("doors_open") or _flat(trolley.global_position).distance_to(_flat(global_position)) < BUS_CLEAR_DISTANCE:
		return
	var path: Array = []
	for p in Layout.RESIDENT_RIDER_B_PATH:
		path.append(_flat(p))
	_start_transit(path, &"shop", 1, speed, 1)
	body.collision_layer = 0
	state = &"transit"

## yield_leg — отрезок через проезжую часть: перед ним на бордюре ждать, пока машины кольца не дальше CROSS_CLEAR от его
## середины; начав переход, не останавливаться (машины тормозят перед телом на слое Car — иначе оба ждали бы друг друга).
func _start_transit(points: Array, end: StringName, body_from: int, walk_speed: float, yield_leg := -1) -> void:
	_transit_yield_leg = yield_leg
	_transit = points
	_transit_i = 0
	_transit_end = end
	_transit_body_from = body_from
	_transit_speed = walk_speed
	body.collision_layer = BODY_LAYER if body_from <= 0 else 0

func _tick_transit(delta: float) -> void:
	var here := _flat(global_position)
	var goal: Vector3 = _transit[_transit_i]
	var to := goal - here
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.ZERO
	if dir != Vector3.ZERO:
		facing_yaw = atan2(-dir.x, -dir.z)
	if is_instance_valid(player) and _player_distance() < BLOCK_DISTANCE and dir != Vector3.ZERO and _player_in_way(dir):
		look_at_target(player)
		return
	if _look_target == player:
		stop_looking()
	if _transit_i == _transit_yield_leg and here.distance_to(_flat(_transit[_transit_i - 1])) < 0.01:
		var middle := here.lerp(goal, 0.5)
		for vehicle in get_tree().get_nodes_in_group(PathVehicle.GROUP):
			if _flat(vehicle.global_position).distance_to(middle) < CROSS_CLEAR:
				return
	var step := _transit_speed * delta
	if dist > step:
		global_position = here + dir * step
		return
	global_position = goal
	_transit_i += 1
	if _transit_i >= _transit_body_from:
		body.collision_layer = BODY_LAYER
	if _transit_i < _transit.size():
		return
	match _transit_end:
		&"ride":
			_hide(&"ride")
			events.append([clock, &"board", 0])
		&"shop":
			if errand:
				_enter_inside(&"gastro")
			else:
				_hide(&"shop")
		_:
			if errand:
				_activity_done()
				return
			state = &"walk"
			direction = 1
			target_point = _wrap(1)

func _hide(next_state: StringName) -> void:
	hidden = true
	visible = false
	body.collision_layer = 0
	stop_looking()
	state = next_state
	_bubble_left = 0.0
	if _bubble_back:
		_bubble_back.visible = false

func _show() -> void:
	hidden = false
	visible = true
	if body:
		body.collision_layer = BODY_LAYER

# =====================================================================================
# KNOCK-01: сбивание «Ладой» без вреда — полёт, кувырок, лежит, встаёт, обратно на маршрут
# =====================================================================================

## Скорость «Лады» по земле, м/с.
func _lada_speed() -> float:
	if not is_instance_valid(lada):
		return 0.0
	var v = lada.get("velocity")
	return Vector2(v.x, v.z).length() if v is Vector3 else 0.0

## KNOCK-02: «Лада» касается видимого жителя (по облику: у сидящего — на сиденье) в любом состоянии. Быстрее
## KNOCK_MIN_SPEED — удар (снова — не раньше KNOCK_REHIT_SECONDS после прошлого); медленнее — лежащего и встающего
## толкает бампером, идущего к двери, от двери и обратно после удара — если едет (стоящую он обходит насквозь, как раньше).
## Остальных на малой скорости решает _tick (_dodge_lada). Выше крыши (полёт, горка) машина не достаёт.
func _check_knock(delta: float) -> void:
	if not is_instance_valid(lada) or global_position.y > Lada.SIZE.y:
		return
	var radius := _hit_radius()
	if not _lada_touches(_hit_point(), LADA_MARGIN, radius):
		return
	var car_speed := _lada_speed()
	if car_speed >= KNOCK_MIN_SPEED:
		if clock >= _knock_last + KNOCK_REHIT_SECONDS:
			knock()
		return
	if knock_phase in [&"down", &"getup"] or ((knock_phase == &"back" or (state in KNOCK_TRANSIT and knock_phase == &"")) and car_speed > LADA_MOVING):
		_lada_push(delta, radius)

## Где «Лада» задевает жителя (XZ): узел, у сидящего — облик на сиденье (Layout.LIFE_SIT).
func _hit_point() -> Vector3:
	if _act_sit != 0.0 and _acting:
		return _flat(global_position) + _forward(_act_yaw) * _act_sit
	return _flat(global_position)

func _hit_radius() -> float:
	return KNOCK_LIE_RADIUS if knock_phase in [&"down", &"getup"] else BODY_RADIUS

## Медленная «Лада» толкает жителя: на ближайшую грань её габарита (с запасом radius), куда путь не через коробку;
## машина о него притормаживает, а если толкать некуда (стена) — упирается: скорость в его сторону гаснет.
func _lada_push(delta: float, radius: float) -> void:
	var p := _flat(global_position)
	var xf := lada.global_transform
	var local := xf.affine_inverse() * Vector3(p.x, lada.global_position.y, p.z)
	var hx := Lada.SIZE.x * 0.5 + radius + KNOCK_PUSH_PAD
	var hz := Lada.SIZE.z * 0.5 + radius + KNOCK_PUSH_PAD
	var exits := [[hx - local.x, Vector3(hx, local.y, local.z)], [local.x + hx, Vector3(-hx, local.y, local.z)],
		[hz - local.z, Vector3(local.x, local.y, hz)], [local.z + hz, Vector3(local.x, local.y, -hz)]]
	exits.sort_custom(func(a, b): return a[0] < b[0])
	var moved := false
	for e in exits:
		var q := _flat(xf * e[1])
		if segment_clear(p, q):
			if not _knock_path.is_empty() and not segment_clear(q, _knock_path[0]):
				_knock_path.push_front(p)   # обратно — тем же путём
			global_position = Vector3(q.x, global_position.y, q.z)
			moved = true
			break
	car_pushes += 1
	var car := lada as CharacterBody3D
	if car == null:
		return
	var v := Vector3(car.velocity.x, 0.0, car.velocity.z) * exp(-KNOCK_PUSH_DRAG * delta)
	if not moved:
		var n := (p - _flat(car.global_position)).normalized()
		var into := v.dot(n)
		if into > 0.0:
			v -= n * into
	car.velocity.x = v.x
	car.velocity.z = v.z

## Сбить: парабола от точки удара по ходу «Лады» и от её центра; дальность укорочена перед коробками all_solids().
## KNOCK-02: снова сбит в полёте, лёжа или вставая — новый полёт с текущей высоты и угла облика (вершина — та же
## высота подлёта, но не ниже KNOCK_REHIT_POP над ним); сидящий слетает с сиденья.
func knock() -> void:
	var lv: Vector3 = lada.get("velocity")
	var v := Vector3(lv.x, 0.0, lv.z)
	var car_speed := v.length()
	var f := clampf((car_speed - KNOCK_MIN_SPEED) / (KNOCK_FULL_AT - KNOCK_MIN_SPEED), 0.0, 1.0)
	var node_at := _flat(global_position)
	var here := _hit_point()
	var h0 := maxf(global_position.y, 0.0)   # в полёте, на раскате горки; лёжа и стоя — 0
	var away := here - _flat(lada.global_position)
	var dir := v / car_speed if car_speed > 0.01 else Vector3.ZERO
	if away.length() > 0.01:
		dir += away.normalized() * KNOCK_AWAY
	if dir.length() < 0.01:
		dir = -_flat(lada.global_basis.z)
	dir = dir.normalized()
	if errand and state != &"knocked":
		_resume_act = {}
		if _acting and state == &"activity" and _act_kind in RESUME_KINDS:
			_resume_act = {"kind": _act_kind, "wait": _wait, "i": _act_i, "spot": spot_id}
		_act_stop()
	if state != &"knocked":
		_knock_resume = [target_point, direction]
		_knock_prior = state
		_knock_path.clear()
		if here.distance_to(node_at) > 0.01:
			_knock_path.push_front(node_at)   # сидел: обратно — к месту у лавки, не в неё
	var rolling := knock_phase in KNOCK_PHASES
	if not rolling:
		_knock_begin_pose()
	if _knock_stars:
		_knock_stars.visible = false
	_set_lying(false)
	_knock_path.push_front(here)
	var height := lerpf(KNOCK_HEIGHT.x, KNOCK_HEIGHT.y, f)
	_knock_h0 = h0
	_knock_vy = sqrt(2.0 * KNOCK_GRAVITY * maxf(height - h0, KNOCK_REHIT_POP))
	_knock_time = (_knock_vy + sqrt(_knock_vy * _knock_vy + 2.0 * KNOCK_GRAVITY * h0)) / KNOCK_GRAVITY
	_knock_dir = dir
	_knock_dist = flight_distance(here, dir, minf(KNOCK_FLY_BASE + KNOCK_FLY_GAIN * car_speed, KNOCK_FLY_MAX) * _knock_time)
	_knock_down = lerpf(KNOCK_DOWN_SECONDS.x, KNOCK_DOWN_SECONDS.y, f)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	_knock_sign = -1.0 if camera and dir.dot(camera.global_basis.x) < 0.0 else 1.0
	_knock_roll0 = knock_roll if rolling else 0.0
	_knock_c0 = _knock_center if rolling else _look_center()
	# Кончить полёт лёжа (−знак · (обороты + ¼)): от текущего угла облика — не меньше полуоборота.
	_knock_spin = _knock_sign * _knock_roll0 + (lerpf(KNOCK_TURNS.x, KNOCK_TURNS.y, f) + 0.25) * TAU
	while _knock_spin < PI:
		_knock_spin += TAU
	_knock_t = 0.0
	_knock_center = _knock_c0
	_knock_squash = Vector2(0.92, 1.08)
	knock_roll = _knock_roll0
	global_position = here + Vector3.UP * h0
	knock_from = here
	knock_to = here + dir * _knock_dist
	knock_car_speed = car_speed
	knock_peak = 0.0
	knocks += 1
	_knock_last = clock
	state = &"knocked"
	knock_phase = &"fly"
	stop_looking()
	body.collision_layer = BODY_LAYER   # KNOCK-02: не бесплотен — Илюша и машины кольца его чувствуют
	knock_log.append([clock, &"fly", here])
	knock_launched.emit(self)

func _tick_knock(delta: float) -> void:
	match knock_phase:
		&"fly":
			_knock_t += delta
			var k := minf(_knock_t / _knock_time, 1.0)
			var t := k * _knock_time
			var y := maxf(_knock_h0 + _knock_vy * t - 0.5 * KNOCK_GRAVITY * t * t, 0.0)
			knock_peak = maxf(knock_peak, y)
			global_position = knock_from + _knock_dir * _knock_dist * k + Vector3(0.0, y, 0.0)
			knock_roll = _knock_roll0 - _knock_sign * _knock_spin * k
			_knock_center = lerpf(_knock_c0, _down_center(), k)
			if k >= 1.0:
				_knock_land()
		&"down":
			_wait -= delta
			var s := clampf((_knock_down - _wait) / 0.25, 0.0, 1.0)   # шлепок: сплющен и выпрямляется
			_knock_squash = Vector2(lerpf(1.12, 1.0, s), lerpf(0.86, 1.0, s))
			_place_stars()
			if _wait <= 0.0:
				knock_phase = &"getup"
				_knock_t = 0.0
				if _knock_stars:
					_knock_stars.visible = false
				_hit_ready_at = clock + BUBBLE_COOLDOWN
				_speak(&"hit")
				knock_log.append([clock, &"getup", _flat(global_position)])
		&"getup":
			_knock_t += delta
			var lie := -_knock_sign * PI * 0.5
			if _knock_t < KNOCK_RISE_SECONDS:
				var r := _knock_t / KNOCK_RISE_SECONDS
				r = 1.0 - (1.0 - r) * (1.0 - r)
				knock_roll = lie * (1.0 - r)
				_knock_center = lerpf(_down_center(), _look_center(), r)
				_knock_squash = Vector2(lerpf(1.0, 0.95, r), lerpf(1.0, 1.05, r))
			else:
				var s := minf((_knock_t - KNOCK_RISE_SECONDS) / KNOCK_SHAKE_SECONDS, 1.0)
				knock_roll = sin(s * 2.0 * TAU) * KNOCK_SHAKE_ANGLE * (1.0 - s)
				_knock_center = _look_center()
				_knock_squash = Vector2.ONE
			if _knock_t >= KNOCK_RISE_SECONDS + KNOCK_SHAKE_SECONDS:
				_knock_end_pose()
				_set_lying(false)
				knock_phase = &"back"
				body.collision_layer = BODY_LAYER
				_plan_back()
				knock_log.append([clock, &"back", _flat(global_position)])
		&"back":
			_tick_back(delta)

func _knock_land() -> void:
	global_position = _flat(knock_to)
	knock_roll = -_knock_sign * PI * 0.5   # лежит головой туда, куда летел
	_knock_center = _down_center()
	knock_phase = &"down"
	_set_lying(true)
	_wait = _knock_down
	_puff()
	_place_stars()
	knock_log.append([clock, &"down", _flat(global_position)])
	knock_landed.emit(self)

## Обратно на маршрут той же дорогой (полёт шёл мимо коробок). Одиночка, если на точке удара стоит «Лада», —
## на ближайшую свободную точку маршрута, если путь до неё не через коробку. Второй в паре — строго на своё место.
func _plan_back() -> void:
	# KNOCK-02: после серии ударов — не по всем полётам назад, а сразу к самой ранней точке, куда путь не через коробку.
	var here := _flat(global_position)
	for i in range(_knock_path.size() - 1, 0, -1):
		if segment_clear(here, _knock_path[i]):
			_knock_path = _knock_path.slice(i)
			break
	if leader != null or follower != null or not is_instance_valid(lada) or _knock_path.is_empty() or _knock_prior in KNOCK_TRANSIT:
		return
	var last: Vector3 = _knock_path[-1]
	if not _lada_touches(last, LADA_CLEAR):
		return
	var found := _nearest_free_point(_flat(global_position))
	var from: Vector3 = _knock_path[-2] if _knock_path.size() > 1 else _flat(global_position)
	if found[1] >= 0 and segment_clear(from, found[0]):
		_knock_path[-1] = found[0]
		_knock_resume = _resume_from(found[0], found[1])

func _tick_back(delta: float) -> void:
	if _knock_path.is_empty():
		_knock_finish()
		return
	var here := _flat(global_position)
	var goal: Vector3 = _knock_path[0]
	var to := goal - here
	var dist := to.length()
	if dist > 0.0001:
		facing_yaw = atan2(-to.x, -to.z)
	var step := speed * delta
	if dist > step:
		global_position = here + to / dist * step
		distance_walked += step
		return
	global_position = goal
	distance_walked += dist
	_knock_path.pop_front()
	if _knock_path.is_empty():
		_knock_finish()

## Снова на маршруте: куда шёл до удара (пауза, перекур, ожидание троллейбуса — дойдёт до своей точки и продолжит).
## KNOCK-02: шёл к двери троллейбуса, от двери или ждал у неё — тот же путь дальше (_resume_transit).
func _knock_finish() -> void:
	var prior := _knock_prior
	_knock_prior = &""
	if prior in KNOCK_TRANSIT:
		knock_phase = &""
		_resume_transit(prior)
		knock_log.append([clock, &"route", _flat(global_position)])
		return
	if errand and not _resume_act.is_empty():
		knock_phase = &""
		if not _resume_activity():
			_activity_done()
		knock_log.append([clock, &"route", _flat(global_position)])
		return
	_resume_act = {}
	state = &"walk"
	knock_phase = &""
	target_point = _knock_resume[0]
	direction = _knock_resume[1]
	knock_log.append([clock, &"route", _flat(global_position)])

## KNOCK-02: встал после удара по пути к двери или от неё. К двери: троллейбус ещё ждёт с открытыми дверями — к ней,
## уехал — снова на остановку (житель с целями — к свободному месту остановки, без целей — по маршруту). У двери на B
## (ждёт, пока троллейбус отъедет) и на пути от двери — дальше тем же путём; тело — как было на этом отрезке.
func _resume_transit(prior: StringName) -> void:
	if prior == &"board":
		if is_instance_valid(trolley) and trolley.get("doors_open") \
				and _flat(trolley.global_position).distance_to(_flat(global_position)) < BUS_CLEAR_DISTANCE:
			state = &"board"
			body.collision_layer = BODY_LAYER if _transit_i >= _transit_body_from else 0
			return
		if errand and life != null and leader == null:
			_go_to(_choose_next())
			return
		state = &"walk"
		target_point = _knock_resume[0]
		direction = _knock_resume[1]
		return
	state = prior
	if prior == &"alight":
		body.collision_layer = 0
	else:
		body.collision_layer = BODY_LAYER if _transit_i >= _transit_body_from else 0

## Лежит: капсула тела — вдоль полёта, у земли; иначе — стоя.
func _set_lying(on: bool) -> void:
	if body == null or body.get_child_count() == 0:
		return
	var collider := body.get_child(0) as CollisionShape3D
	var axis := Vector3.UP.cross(_knock_dir)
	if on and axis.length() > 0.01:
		collider.transform = Transform3D(Basis(axis.normalized(), PI * 0.5), Vector3(0.0, BODY_RADIUS, 0.0))
	else:
		collider.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, BODY_HEIGHT * 0.5, 0.0))

## Перезапуск: облик и тело — как до удара, счётчики — с нуля.
func _knock_reset() -> void:
	if knock_phase in KNOCK_PHASES:
		_knock_end_pose()
	_set_lying(false)
	knock_phase = &""
	knocks = 0
	car_pushes = 0
	knock_roll = 0.0
	knock_log.clear()
	_knock_path.clear()
	_knock_last = -INF
	_knock_prior = &""
	_knock_waiting = false
	if _knock_stars:
		_knock_stars.visible = false
	if body:
		body.collision_layer = BODY_LAYER

## Отрезок a→b (XZ) не задевает коробок all_solids() с запасом BODY_RADIUS + KNOCK_SOLID_PAD.
static func segment_clear(a: Vector3, b: Vector3) -> bool:
	var d := _flat(b) - _flat(a)
	if d.length() < 0.001:
		return true
	return flight_distance(a, d.normalized(), d.length()) >= d.length()

## Дальность полёта из from по dir (XZ): dist, а если по пути коробка all_solids() (с запасом BODY_RADIUS +
## KNOCK_SOLID_PAD) — до неё. Коробки, в запасе которых житель уже стоит, не учитываются. BREAK-01: целые разрушаемые
## объекты (Breakables.intact_rects) — такое же препятствие.
static func flight_distance(from: Vector3, dir: Vector3, dist: float) -> float:
	if _solid_rects.is_empty():
		var solids := Layout.all_solids()
		for index in solids.size():
			if not Layout.env_break_at(index).is_empty(): continue
			var spec: Array = solids[index]
			var c: Vector2 = spec[2]
			var size: Vector3 = spec[3]
			_solid_rects.append(Rect2(c - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)).grow(BODY_RADIUS + KNOCK_SOLID_PAD))
	var o := Vector2(from.x, from.z)
	var d := Vector2(dir.x, dir.z)
	var best := dist
	for rect: Rect2 in _solid_rects + Breakables.intact_rects(BODY_RADIUS + KNOCK_SOLID_PAD):
		if rect.has_point(o):
			continue
		var t := _ray_rect(o, d, rect)
		if t >= 0.0 and t < best:
			best = t
	return maxf(best - 0.05, 0.0) if best < dist else dist

## Где луч o + d·t (|d| = 1) входит в прямоугольник; −1 — не входит.
static func _ray_rect(o: Vector2, d: Vector2, rect: Rect2) -> float:
	var t_in := -INF
	var t_out := INF
	for axis in 2:
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(d[axis]) < 0.000001:
			if o[axis] < lo or o[axis] > hi:
				return -1.0
			continue
		var t1 := (lo - o[axis]) / d[axis]
		var t2 := (hi - o[axis]) / d[axis]
		t_in = maxf(t_in, minf(t1, t2))
		t_out = minf(t_out, maxf(t1, t2))
	if t_out < maxf(t_in, 0.0):
		return -1.0
	return maxf(t_in, 0.0)

# --- облик сбитого ---

func _look() -> Node:
	return visual.get_node_or_null("Look") if visual else null

## Спрайт облика (CharacterSprite) или null — 3D-тело.
func _look_sprite() -> Sprite3D:
	var look := _look()
	var sprite = look.get("sprite") if look else null
	return sprite as Sprite3D

## Высота центра облика над ногами стоящего, м.
func _look_center() -> float:
	var sprite := _look_sprite()
	return sprite.position.y if sprite else BODY_HEIGHT * 0.5

func _down_center() -> float:
	return KNOCK_DOWN_CENTER if _look_sprite() else KNOCK_DOWN_CENTER_3D

## Начало полёта: спрайт без billboard и развёрнут к камере лицом (иначе вращение не видно), тень облика — своя на снегу.
func _knock_begin_pose() -> void:
	var sprite := _look_sprite()
	if sprite:
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		var material = _look().get("look_material")
		if material is BaseMaterial3D:
			material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.rotation.y = PI   # облик (−Z) смотрит в камеру → вид front; лицевая сторона квада — тоже к камере
	elif _look() and _look().has_method("set_walk_speed"):
		_look().set_walk_speed(0.0)   # 3D-облик CHAR3D-01: в полёте и лёжа ноги не шагают
	var look_shadow := _look().find_child("Shadow", true, false) if _look() else null
	if look_shadow is Node3D:
		look_shadow.visible = false
	if _knock_shadow == null:
		_knock_shadow = _make_knock_shadow()
		add_child(_knock_shadow)
	_knock_shadow.visible = true

## Конец getup и перезапуск: облик — как у npc.gd (billboard по Y, поворот только по Y), тень облика на месте.
func _knock_end_pose() -> void:
	var sprite := _look_sprite()
	if sprite:
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		var material = _look().get("look_material")
		if material is BaseMaterial3D:
			material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.rotation = Vector3.ZERO
	elif _look() and _look().has_method("set_walk_speed"):
		_look().set_walk_speed(-1.0)
	var look_shadow := _look().find_child("Shadow", true, false) if _look() else null
	if look_shadow is Node3D:
		look_shadow.visible = true
	if _knock_shadow:
		_knock_shadow.visible = false
	if visual:
		visual.transform = Transform3D(Basis(Vector3.UP, facing_yaw), Vector3.ZERO)
	knock_roll = 0.0
	_knock_squash = Vector2.ONE

func _process(delta: float) -> void:
	if knock_phase in KNOCK_PHASES:
		_pose_knocked()
		return
	super(delta)
	if errand:
		_pose_activity()

## Облик в полёте, лёжа и вставая: вокруг своего центра (_knock_center над узлом) на угол knock_roll.
func _pose_knocked() -> void:
	var camera := get_viewport().get_camera_3d()
	var squash := Basis.from_scale(Vector3(_knock_squash.x, _knock_squash.y, 1.0))
	var b: Basis
	if _look_sprite() and camera:
		b = _knock_screen_basis(camera) * squash * Basis(Vector3.UP, PI)
	else:
		var axis := Vector3.UP.cross(_knock_dir).normalized()
		if axis.length() < 0.5:
			axis = Vector3.RIGHT
		# 3D-тело: лицом по полёту, кувырок назад вокруг оси поперёк полёта — ложится на спину.
		b = Basis(axis, knock_roll * _knock_sign) * Basis(Vector3.UP, atan2(-_knock_dir.x, -_knock_dir.z)) * squash
	var center := global_position + Vector3.UP * _knock_center
	var world := Transform3D(b, center - b * Vector3(0.0, _look_center(), 0.0))
	visual.transform = global_transform.affine_inverse() * world
	if _knock_shadow:
		var lift := global_position.y
		_knock_shadow.global_transform = Transform3D(Basis.from_scale(Vector3.ONE / (1.0 + lift * 0.35)), Vector3(global_position.x, 0.03, global_position.z))

## Плоскость экрана, повёрнутая на knock_roll вокруг взгляда камеры.
func _knock_screen_basis(camera: Camera3D) -> Basis:
	return camera.global_basis.orthonormalized() * Basis(Vector3(0, 0, 1), knock_roll)

## Снежинки кружат над головой лежащего (вызывается на шаге физики — детерминированно).
func _place_stars() -> void:
	if _knock_stars == null:
		_knock_stars = _make_stars()
		add_child(_knock_stars)
	_knock_stars.visible = true
	var head := Vector3.UP * (_knock_center + KNOCK_HEAD)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if _look_sprite() and camera:
		head = Vector3.UP * _knock_center + _knock_screen_basis(camera) * Vector3(0.0, KNOCK_HEAD, 0.0)
	elif knock_phase == &"down":
		head = Vector3.UP * _knock_center - _knock_dir * KNOCK_HEAD   # 3D-тело на спине: голова к машине
	_knock_stars.global_position = global_position + head + Vector3.UP * KNOCK_STAR_LIFT
	_knock_stars.global_basis = Basis.IDENTITY
	var n := _knock_stars.get_child_count()
	for i in n:
		var star: Node3D = _knock_stars.get_child(i)
		var a := clock * KNOCK_STAR_SPIN + TAU * i / n
		star.position = Vector3(cos(a) * KNOCK_STAR_RADIUS, sin(a * 2.0) * 0.04, sin(a) * KNOCK_STAR_RADIUS)
		star.rotation = Vector3(0.0, -a * 1.5, 0.0)

## Снежинка — три тонких бруска накрест (шесть лучей), белые без тени и тумана.
func _make_stars() -> Node3D:
	var ring := Node3D.new()
	ring.name = "KnockStars"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = KNOCK_SNOW
	material.disable_fog = true
	var bar := BoxMesh.new()
	bar.size = Vector3(0.22, 0.04, 0.04)
	bar.material = material
	for i in KNOCK_STARS:
		var star := Node3D.new()
		star.name = "Star%d" % i
		for k in 3:
			var ray := MeshInstance3D.new()
			ray.mesh = bar
			ray.rotation.z = PI / 3.0 * k
			ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			star.add_child(ray)
		ring.add_child(star)
	ring.visible = false
	return ring

## Тень на снегу под летящим: мягкое пятно, меньше с высотой.
func _make_knock_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.45))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.1, 0.75)
	mesh.material = material
	var shadow := MeshInstance3D.new()
	shadow.name = "KnockShadow"
	shadow.mesh = mesh
	shadow.top_level = true
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.visible = false
	return shadow

## Облако снежной пыли при падении — частицы как брызги PLAY-03 (тот же шейдер), разово.
func _puff() -> void:
	if knock_dust == null:
		var blob := Gradient.new()
		blob.set_color(0, Color(1, 1, 1, 1))
		blob.set_color(1, Color(1, 1, 1, 0))
		var dot := GradientTexture2D.new()
		dot.gradient = blob
		dot.fill = GradientTexture2D.FILL_RADIAL
		dot.fill_from = Vector2(0.5, 0.5)
		dot.fill_to = Vector2(1.0, 0.5)
		dot.width = 32
		dot.height = 32
		var look := ShaderMaterial.new()
		look.shader = SNOW_PUFF_SHADER
		look.set_shader_parameter("albedo", KNOCK_SNOW)
		look.set_shader_parameter("texture_albedo", dot)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.45, 0.45)
		quad.material = look
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0.95))
		fade.set_color(1, Color(1, 1, 1, 0.0))
		knock_dust = CPUParticles3D.new()
		knock_dust.name = "KnockDust"
		knock_dust.top_level = true
		knock_dust.one_shot = true
		knock_dust.explosiveness = 0.9
		knock_dust.amount = 40
		knock_dust.lifetime = 0.9
		knock_dust.mesh = quad
		knock_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		knock_dust.emission_sphere_radius = 0.45
		knock_dust.direction = Vector3.UP
		knock_dust.spread = 75.0
		knock_dust.initial_velocity_min = 1.2
		knock_dust.initial_velocity_max = 2.8
		knock_dust.gravity = Vector3(0, -3.0, 0)
		knock_dust.damping_min = 2.0
		knock_dust.damping_max = 3.5
		knock_dust.scale_amount_min = 0.8
		knock_dust.scale_amount_max = 2.0
		knock_dust.color_ramp = fade
		knock_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		knock_dust.emitting = false
		add_child(knock_dust)
	knock_dust.global_position = _flat(global_position) + Vector3.UP * 0.15
	knock_dust.restart()
	knock_dust.emitting = true

# =====================================================================================
# LIFE-01: цели и маршруты — цепочка точек интереса, путь по графу дорожек, занятия на местах
# =====================================================================================

var _on_start_leg := false
var _from_spot := &""
var _act_yaw := 0.0
var _act_sit := 0.0       # м: облик сидящего сдвинут по взгляду (минус — за спину), Layout.LIFE_SIT
var follow_gap := 1.2     # м позади по следу первого (Residents задаёт по стартовому сдвигу)
var follow_side := 0.45   # м вправо по ходу (минус — влево)

## Начало жизни (из _ready): стартовый отрезок Layout.RESIDENT_ROUTES, первая цель уже выбрана.
func _errand_begin() -> void:
	if start_leg.is_empty():
		start_leg = [_flat(route[start_point]), _flat(route[_wrap(start_point + 1)])]
	start_point = 0
	route = start_leg.duplicate()
	route_flags = [&""]
	target_point = 1
	direction = 1
	_errand_reset()

## Сброс цепочки: стартовый отрезок, первая цель (у второго в паре — нет, его ведёт первый).
func _errand_reset() -> void:
	plan_i = plan_start
	spot_id = &""
	visits = []
	activity_log = []
	goals = 0
	_cross_ok = -1
	_from_spot = &""
	_lod_acc = 0.0
	_lod_n = 0
	_on_start_leg = true
	state = &"walk"
	_resume_act = {}
	snowballs = 0
	snow_hits = 0
	resumes = 0
	sound_counts = {}
	_sled_moved = 0.0
	if _sled:
		_sled.global_position = _flat(global_position) - _forward(facing_yaw) * SLED_BACK
	_trail_seed((_flat(start_leg[1]) - _flat(start_leg[0])).normalized())
	if leader != null or life == null:
		return
	spot_id = _choose_next()
	life.reserve(spot_id, self)
	goals = 1
	if _flat(global_position).distance_to(life.spots[spot_id].pos) < 0.3:
		_on_start_leg = false
		_arrive()   # стоит на месте первой цели (курящий у подъезда)

## Следующая цель по цепочке: первый шаг, для которого есть свободная точка (кроме except); иначе — домой.
func _choose_next(except := &"") -> StringName:
	if plan.is_empty():
		return home
	for attempt in plan.size():
		var step: StringName = plan[plan_i % plan.size()]
		var id: StringName = life.choose(self, step, home, rng, except, follower != null)
		if id != &"":
			return id
		plan_i += 1
	return home if home != &"" and home != except else life.spots.keys()[0]

## Идти к точке id: путь по графу от места (или от узла точки, на месте которой стоит).
func _go_to(id: StringName) -> void:
	var s: Dictionary = life.spots[id]
	spot_id = id
	if not life.reserve(id, self) and s.kind == &"edge":
		plan_i += 1
		goals += 1
		_go_to(_choose_next(id))
		return
	state = &"walk"
	direction = 1
	_cross_ok = -1
	_on_start_leg = false
	var here := _flat(global_position)
	if here.distance_to(s.pos) < 0.3:
		route = [here, s.pos]
		route_flags = [&""]
		target_point = 1
		_arrive()
		return
	var p: Dictionary = life.path(here, id, _from_spot)
	route = p["points"]
	route_flags = p["flags"]
	if route.size() < 2:
		route = [here, s.pos]
		route_flags = [&""]
	target_point = 1
	_from_spot = &""
	facing_yaw = _yaw_to(route[1])

## Дошёл до точки отрезка: конец — цель (или конец стартового отрезка), начало при движении назад — новая цель.
func _on_errand_point() -> void:
	if direction > 0 and target_point >= route.size() - 1:
		if _on_start_leg:
			_on_start_leg = false
			_go_to(spot_id)
		else:
			_arrive()
	elif direction < 0 and target_point <= 0:
		# «Лада» стояла поперёк пути: вернулся к началу отрезка — другая цель.
		life.release(spot_id, self)
		plan_i += 1
		var next := _choose_next(spot_id)
		goals += 1
		_go_to(next)
	else:
		target_point += direction

## На месте точки: занятие по её виду.
func _arrive() -> void:
	if not life.anchor_intact(spot_id):
		_activity_done()
		return
	var s: Dictionary = life.spots[spot_id]
	if s.kind in [&"window", &"queue"]:
		if _flat(global_position).distance_to(s.pos) > life.AT_SPOT:
			_go_to(spot_id)
			return
		var admitted: StringName = life.window_arrival(self)
		if admitted == &"":
			_activity_done()
			return
		if admitted != spot_id:
			life.release(spot_id, self)
			_from_spot = spot_id
			_go_to(admitted)
			return
		if not life.reserve(spot_id, self):
			_activity_done()
			return
	place(s.pos)
	facing_yaw = s.yaw
	_act_yaw = s.yaw
	visits.append([clock, spot_id])
	activity_log.append([clock, s.kind])
	var dur: Vector2 = s.dur
	_wait = rng.randf_range(dur.x, dur.y)
	_act_kind = s.kind
	_act_t = 0.0
	_social_token = ""
	_social_pose = {}
	_act_i = 1
	_acting = true
	stop_looking()
	match s.kind:
		&"door", &"shop":
			if not hidden:
				entrance_used.emit(self, global_position, true)
			_hide(&"inside")
		&"stop":
			if is_instance_valid(trolley):
				state = &"wait_trolley"
				facing_yaw = _yaw_to(trolley_from())
			else:
				state = &"activity"
				_wait = 20.0
		&"smoke":
			state = &"smoke"
			_turn_left = rng.randf_range(SMOKE_TURN_SECONDS.x, SMOKE_TURN_SECONDS.y)
		&"carpet":
			state = &"activity"
			life.set_prop(&"carpet", true)
		&"hockey":
			state = &"activity"
			puck_timer = rng.randf_range(LifeScript.PASS_SECONDS.x, LifeScript.PASS_SECONDS.y)
			_act_target = Vector3.INF
		&"snowball":
			state = &"activity"
			_throw_in = rng.randf_range(1.0, SNOWBALL_EVERY.y)
		&"trade":
			state = &"activity"
			life.set_prop(&"jars", true)
		_:
			state = &"activity"
	_act_sit = Layout.LIFE_SIT.get(spot_id, 0.0)
	if _act_sit != 0.0 and not hidden:
		body.collision_layer = 0   # облик на сиденье, место в стороне — Илюша не упирается в пустоту

## Занятие кончилось: следующий шаг цепочки.
func _activity_done() -> void:
	_act_stop()
	life.release(spot_id, self)
	_from_spot = spot_id
	plan_i += 1
	var next := _choose_next(spot_id)
	goals += 1
	_go_to(next)

## Снять следы занятия: тело, ковёр, метла, высота горки, облик.
func _act_stop() -> void:
	if not _acting:
		return
	_acting = false
	_social_token = ""
	_social_pose = {}
	if _act_sit != 0.0 and body and not hidden:
		body.collision_layer = BODY_LAYER
	_act_sit = 0.0
	if _act_kind == &"carpet" and life:
		life.set_prop(&"carpet", false)
	if _act_kind == &"trade" and life:
		life.set_prop(&"jars", false)
	if _act_kind == &"hockey" and life:
		life.hockey_leave(self)
	if _broom:
		_broom.visible = false
	if _work_tool:
		_work_tool.visible = false
	if _stick:
		_stick.visible = false
	if _ball:
		_ball.visible = false
	_ball_flight = {}
	if global_position.y != 0.0:
		global_position.y = 0.0
	if visual:
		visual.position = Vector3.ZERO

func _busy() -> bool:
	return errand and _acting and state == &"activity" and _act_kind in BUSY_KINDS

func _tick_activity(delta: float) -> void:
	_act_t += delta
	if spot_id != &"" and not life.anchor_intact(spot_id):
		_activity_done()   # сломанный столик или лавка прекращают занятие до жеста и звука
		return
	var s: Dictionary = life.spots[spot_id]
	match _act_kind:
		&"queue":
			if not life.anchor_intact(s.service):
				_activity_done()
				return
			var next: StringName = life.queue_next(self)
			if next != &"" and life.reserve(next, self):
				_act_stop()
				life.release(spot_id, self)
				_from_spot = spot_id
				_go_to(next) # тот же шаг личного плана; обслужат только после прихода к окну
			return
		&"edge":
			if life.on_screen(s.pos):
				if _act_t >= EDGE_VISIBLE_WAIT:
					_activity_done()
				return
			_hide(&"away")
			_wait = rng.randf_range(s.dur.x, s.dur.y)
			return
		&"sweep":
			if _tick_sweep(delta, s):
				return
		&"slide":
			if _tick_slide(delta):
				return
		&"hockey":
			if _tick_hockey(delta, s):
				return
		&"sled":
			if _tick_sled(delta):
				return
		&"snowball":
			_tick_snowball(delta)
		&"domino", &"chat":
			_tick_social()
		&"dig", &"carpet", &"hood":
			_tick_work(delta)
	_wait -= delta
	if _wait <= 0.0:
		_activity_done()

func _tick_social() -> void:
	var turn: Dictionary = life.social_turn(self)
	_social_pose = turn
	if turn.is_empty():
		_social_token = ""
		return
	var others: Array = turn.members.filter(func(member): return member != self)
	var center := Vector3.ZERO
	for member in others:
		center += member.global_position
	facing_yaw = _yaw_to(center / float(others.size()))
	if turn.token == _social_token:
		return
	_social_token = turn.token
	if turn.speaker != self:
		return
	if _act_kind == &"domino":
		_emit_sound(&"domino")
	if clock >= _idle_at and clock >= _bubble_ready_at:
		for other in others:
			if other.bubble_visible():
				return
		_speak(&"idle")

## Дворник: вдоль дома от места до Layout.LIFE_SWEEP_END и обратно. true — занятие ещё не может кончиться.
func _tick_sweep(delta: float, s: Dictionary) -> bool:
	var a: float = s.pos.x
	var to: float = Layout.LIFE_SWEEP_END if _act_i > 0 else a
	var x := move_toward(global_position.x, to, SWEEP_SPEED * delta)
	distance_walked += absf(x - global_position.x)
	global_position.x = x
	facing_yaw = PI * 0.5 if to < x or (to == x and _act_i > 0) else -PI * 0.5
	if absf(x - to) < 0.001:
		_act_i = -_act_i
	var t := _act_t + index * 0.37
	if floori(t * 4.0 / PI) != floori((t - delta) * 4.0 / PI):
		_emit_sound(&"sweep")   # взмах метлы — крайняя точка размаха (_pose_activity: sin(t · 4))
	_wait -= delta
	return _wait > 0.0 or absf(global_position.x - a) > 0.05

## Горка: по петле Layout.LIFE_SLIDE_LOOP (лесенка, скат, раскат, обратно). true — занятие ещё не может кончиться.
func _tick_slide(delta: float) -> bool:
	var loop: Array = Layout.LIFE_SLIDE_LOOP
	var prev: Array = loop[_act_i - 1]
	var next: Array = loop[_act_i]
	var a := Vector3(prev[0], 0.0, prev[1])
	var b := Vector3(next[0], 0.0, next[1])
	var here := _flat(global_position)
	var flat := move_toward_v(here, b, float(next[3]) * delta)
	distance_walked += here.distance_to(flat)
	var span := a.distance_to(b)
	var k := 1.0 - flat.distance_to(b) / span if span > 0.001 else 1.0
	global_position = flat + Vector3.UP * lerpf(prev[2], next[2], k)
	if b.distance_to(flat) > 0.001:
		var d := b - flat
		facing_yaw = atan2(-d.x, -d.z)
	_wait -= delta
	if flat.distance_to(b) > 0.001:
		return true
	_act_i += 1
	if _act_i == 3:
		_emit_sound(&"slide")   # с площадки — вниз по скату
	if _act_i < loop.size():
		return true
	_act_i = 1   # снова у лесенки
	return _wait > 0.0

static func move_toward_v(from: Vector3, to: Vector3, step: float) -> Vector3:
	var d := to - from
	return to if d.length() <= step else from + d.normalized() * step

## Скрыт в подъезде, магазине или за краем карты: время вышло — выходит там же (край — только вне кадра).
func _tick_hidden(delta: float) -> void:
	if _acting and spot_id != &"" and not life.anchor_intact(spot_id):
		_show()
		_activity_done()
		return
	if get_tree().paused:
		return
	if state != &"inside" and state != &"away":
		return   # в троллейбусе: ждёт остановку
	_wait -= delta
	if _wait > 0.0:
		return
	var s: Dictionary = life.spots[spot_id]
	if state == &"away" and life.on_screen(s.pos):
		_wait = EDGE_RETRY
		return
	place(s.pos)
	if state == &"inside":
		entrance_used.emit(self, global_position, false)
	_show()
	facing_yaw = s.yaw + PI
	_trail = [_flat(global_position)]   # второй в паре выходит из той же двери следом
	_activity_done()

## Вышел из троллейбуса на B и дошёл до «ГАСТРОНОМА»: внутри, выйдет оттуда же.
func _enter_inside(id: StringName) -> void:
	_act_stop()
	life.release(spot_id, self)
	spot_id = id
	life.reserve(id, self)
	var s: Dictionary = life.spots[id]
	visits.append([clock, id])
	activity_log.append([clock, s.kind])
	_act_kind = s.kind
	_acting = true
	_wait = rng.randf_range(s.dur.x, s.dur.y)
	place(s.pos)
	if not hidden:
		entrance_used.emit(self, global_position, true)
	_hide(&"inside")

## Троллейбус открыл двери: ждущий на остановке A садится, едущий выходит на B, ушедший за край карты (почти пора
## вернуться) приезжает на A и выходит из задней двери.
func _errand_doors_opened(stop: int) -> void:
	if stop == 0 and state == &"wait_trolley":
		_act_stop()
		life.release(spot_id, self)
		_board()
	elif stop == 1 and state == &"ride":
		# Илюша у площадки киоска (стелс, C7) — пассажир не выходит у парковки, едет до A.
		if not (is_instance_valid(player) and player.is_visible_in_tree() \
				and _flat(player.global_position).distance_to(_flat(trolley.global_position)) < STEALTH_STAY):
			_alight(1)
	elif stop == 0 and state == &"ride":
		_alight(0)
	elif stop == 0 and state == &"away" and _wait <= 20.0:
		life.release(spot_id, self)
		_alight(0)

# --- переходы ---

## Перед отрезком-переходом: ждать (wait_cross), пока нельзя. true — стоит.
func _crossing_ahead(here: Vector3) -> bool:
	if direction <= 0 or target_point < 1 or target_point - 1 >= route_flags.size():
		return false
	var flag: StringName = route_flags[target_point - 1]
	if flag == &"" or _cross_ok == target_point or here.distance_to(_flat(route[target_point - 1])) > 0.05:
		return false
	if _crossing_clear(_flat(route[target_point - 1]), _flat(route[target_point]), flag):
		_cross_ok = target_point
		return false
	state = &"wait_cross"
	facing_yaw = _yaw_to(route[target_point])
	return true

func _tick_wait_cross() -> void:
	var a := _flat(route[target_point - 1])
	var b := _flat(route[target_point])
	if _crossing_clear(a, b, route_flags[target_point - 1]):
		_cross_ok = target_point
		state = &"walk"

## Можно идти по отрезку a→b: переход — машины кольца и автобус ГСУМ дальше CROSS_CLEAR от середины; коридор пути
## игрока — Илюша дальше ROUTE_YIELD; оба — «Лада» с водителем или на ходу не ближе своего радиуса.
func _crossing_clear(a: Vector3, b: Vector3, flag: StringName) -> bool:
	var radius := CROSS_CLEAR if flag == &"cross" else ROUTE_YIELD
	if is_instance_valid(lada) and (_lada_speed() > LADA_MOVING or lada.get("driver") != null):
		if _segment_distance(_flat(lada.global_position), a, b) < radius:
			return false
	if flag == &"cross":
		var middle := a.lerp(b, 0.5)
		var cars: Array = life.vehicles if life else []
		for v in cars:
			if is_instance_valid(v) and _flat(v.global_position).distance_to(middle) < CROSS_CLEAR:
				return false
	elif is_instance_valid(player) and player.is_visible_in_tree():
		if _segment_distance(_flat(player.global_position), a, b) < ROUTE_YIELD:
			return false
	return true

## Занят горкой (лесенка внутри коробки горки — для тестов).
func on_slide() -> bool:
	return _acting and _act_kind == &"slide" and state == &"activity"

## Идёт по переходу проезжей части (для тестов: там проезжая часть разрешена).
func on_crossing() -> bool:
	if leader != null:
		return leader.on_crossing()
	if not errand or state in [&"wait_cross", &"activity", &"inside", &"away"]:
		return false
	return target_point >= 1 and target_point - 1 < route_flags.size() and route_flags[target_point - 1] == &"cross"

static func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
	return q.distance_to(Vector2(p.x, p.z))

static func _forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

# --- пара: второй идёт по следу первого ---

func _trail_seed(dir: Vector3) -> void:
	var p := _flat(global_position)
	if dir.length() < 0.001:
		dir = _forward(facing_yaw)
	_trail = [p - dir * 4.0, p]

func _record_trail() -> void:
	var p := _flat(global_position)
	if _trail.is_empty() or _trail[-1].distance_to(p) >= TRAIL_STEP:
		_trail.append(p)
		if _trail.size() > 60:
			_trail.pop_front()

## Точка на следе в gap м позади и направление хода там: [точка, направление].
func trail_point(gap: float) -> Array:
	var p := _flat(global_position)
	var remaining := gap
	var dir := _forward(facing_yaw)
	for i in range(_trail.size() - 1, -1, -1):
		var q: Vector3 = _trail[i]
		var d := p.distance_to(q)
		if d > 0.0001:
			dir = (p - q) / d
			if d >= remaining:
				return [p.lerp(q, remaining / d), dir]
			remaining -= d
		p = q
	return [p, dir]

func _mirror_trail(lead: Resident) -> void:
	var at: Array = lead.trail_point(follow_gap)
	var dir: Vector3 = at[1]
	# У цели первого и у двери, из которой он вышел, — прямо за ним, без шага вбок: места у стен и киосков тесные.
	var near := INF
	if lead.spot_id != &"" and lead.life:
		near = _flat(lead.global_position).distance_to(lead.life.spots[lead.spot_id].pos)
	if not lead._trail.is_empty():
		near = minf(near, _flat(lead.global_position).distance_to(lead._trail[0]))
	var side := follow_side * clampf(near / 3.0, 0.0, 1.0)
	global_position = at[0] + Vector3(-dir.z, 0.0, dir.x) * side
	hidden = lead.hidden
	visible = lead.visible
	if body:
		body.collision_layer = 0 if hidden else BODY_LAYER
	state = lead.state
	direction = lead.direction
	facing_yaw = lead.facing_yaw
	_look_target = lead._look_target
	distance_walked = lead.distance_walked
	stare_count = lead.stare_count
	lada_bumps = lead.lada_bumps
	turnarounds = lead.turnarounds
	spot_id = lead.spot_id
	visits = lead.visits
	activity_log = lead.activity_log
	follow_offset = _flat(global_position) - _flat(lead.global_position)

# --- облик на занятии ---

## Сидит — облик на сиденье за спиной и ниже; «козёл» — стук костяшкой; капот и раскопка — наклоны; ковёр — удары;
## дворник — метла перед собой качается.
func _pose_activity() -> void:
	if visual == null:
		return
	if _work_tool:
		_work_tool.visible = WORK_PERIODS.has(_act_kind) and _working_now()
	var offset := Vector3.ZERO
	if _acting and not hidden:
		var t := _act_t + index * 0.37
		if _act_sit != 0.0:
			offset = _forward(_act_yaw) * _act_sit + Vector3.DOWN * SIT_DROP
		match _act_kind:
			&"domino":
				var turn: Dictionary = _social_pose
				var k: float = turn.get("phase", 1.0)
				if state == &"activity" and turn.get("speaker") == self and k < 0.25:
					var s := sin(k / 0.25 * PI)
					offset.y -= 0.07 * s
					visual.scale.y *= 1.0 - 0.05 * s
			&"chat":
				var turn: Dictionary = _social_pose
				var k: float = turn.get("phase", 1.0)
				if state == &"activity" and turn.get("speaker") == self and k < 0.8:
					var nod := sin(k / 0.8 * PI)
					offset.y -= 0.035 * nod
					visual.scale.y *= 1.0 - 0.025 * nod
			&"hood", &"dig", &"carpet":
				if _working_now():
					var stroke := _work_stroke()
					visual.scale.y *= 1.0 - 0.09 * stroke
					offset.y -= 0.04 * stroke
					_pose_work_tool(stroke)
			&"sweep":
				if _broom == null:
					_broom = _make_broom()
					add_child(_broom)
				_broom.visible = true
				var f := _forward(facing_yaw)
				_broom.position = f * 0.55 + Vector3(-f.z, 0.0, f.x) * 0.15
				_broom.rotation = Vector3(0.0, facing_yaw + sin(t * 4.0) * 0.45, 0.0)
			&"hockey":
				offset.y += 0.03 * sin(t * 6.0)   # толкается коньками
				if _stick == null:
					_stick = _make_stick()
					add_child(_stick)
				_stick.visible = true
				var f := _forward(facing_yaw)
				_stick.position = f * STICK_LEAD + Vector3(-f.z, 0.0, f.x) * STICK_SIDE
				_stick.rotation = Vector3(0.0, facing_yaw - 0.35 * (_stick_swing / 0.25), 0.0)
			&"snowball":
				if _ball_flight.is_empty() and _throw_in < SNOWBALL_MOLD:
					offset.y -= 0.14 * sin(clampf(_throw_in / SNOWBALL_MOLD, 0.0, 1.0) * PI)   # присел лепить
			&"trade":
				var k := fmod(t, 7.0)
				if k < 0.6:
					offset.y -= 0.05 * sin(k / 0.6 * PI)   # поправляет банки
		if _flinch > 0.0:
			offset.x += 0.06 * sin(_flinch * 40.0)   # снежок попал — вздрогнул
	visual.position = offset

func _work_stroke() -> float:
	var phase := fposmod(_act_t / float(WORK_PERIODS[_act_kind]) + index * 0.17, 1.0)
	return 0.5 + 0.5 * cos((phase - WORK_CONTACT) * TAU)

## У раскопки одна рабочая позиция; двое остальных смотрят, а не копают воздух сбоку.
func _working_now() -> bool:
	return is_playing(_act_kind) and (_act_kind != &"dig" or spot_id == &"dig_1")

func _tick_work(delta: float) -> void:
	if not _working_now():
		return
	var period: float = WORK_PERIODS[_act_kind]
	var now := _act_t / period + index * 0.17 - WORK_CONTACT
	var before := (_act_t - delta) / period + index * 0.17 - WORK_CONTACT
	if floori(now) != floori(before):
		_pose_work_tool(_work_stroke())
		_emit_sound(_act_kind)

func _pose_work_tool(stroke: float) -> void:
	if _work_tool == null:
		_work_tool = Node3D.new()
		_work_tool.name = "WorkTool"
		add_child(_work_tool)
	if _work_tool.get_meta(&"kind", &"") != _act_kind:
		for child in _work_tool.get_children():
			child.free()
		_work_tool.set_meta(&"kind", _act_kind)
		_build_work_tool()
	_work_tool.visible = true
	var f := _forward(facing_yaw)
	_work_tool.position = f * 0.45 + Vector3(-f.z, 0.0, f.x) * 0.33 + Vector3.UP * 1.05
	var tilt := lerpf(-0.65, 0.35, stroke) if _act_kind == &"dig" else lerpf(-0.1, -1.4, stroke)
	_work_tool.rotation = Vector3(0.0, facing_yaw, 0.0)
	_work_tool.rotate_object_local(Vector3.RIGHT, tilt)

func _build_work_tool() -> void:
	var wood := Color(0.44, 0.30, 0.17)
	var steel := Color(0.58, 0.61, 0.59)
	match _act_kind:
		&"dig":
			_work_part(Vector3(0.05, 1.15, 0.05), Vector3(0, -0.05, 0), wood)
			_work_part(Vector3(0.32, 0.38, 0.05), Vector3(0, -0.76, -0.04), steel)
			_work_part(Vector3(0.20, 0.045, 0.05), Vector3(0, 0.54, 0), wood)
		&"carpet":
			_work_part(Vector3(0.045, 0.52, 0.045), Vector3(0, 0.18, 0), wood)
			var ring := TorusMesh.new()
			ring.inner_radius = 0.17
			ring.outer_radius = 0.21
			ring.rings = 16
			ring.ring_segments = 6
			var head := MeshInstance3D.new()
			head.mesh = ring
			head.position.y = 0.64
			head.rotation.x = PI * 0.5
			head.material_override = _work_material(wood)
			head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_work_tool.add_child(head)
			_work_part(Vector3(0.04, 0.35, 0.04), Vector3(0, 0.64, 0), wood)
		&"hood":
			_work_part(Vector3(0.07, 0.40, 0.05), Vector3(0, 0.1, 0), steel)
			for side in [-1.0, 1.0]:
				_work_part(Vector3(0.07, 0.16, 0.06), Vector3(side * 0.075, 0.34, 0), steel)
			_work_part(Vector3(0.20, 0.07, 0.06), Vector3(0, 0.25, 0), steel)

func _work_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func _work_part(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = _work_material(color)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_work_tool.add_child(part)

## Метла: черенок (наклонён к дворнику) и веник у снега — своя простая геометрия.
func _make_broom() -> Node3D:
	var root := Node3D.new()
	root.name = "Broom"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.72, 0.6, 0.32)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.02
	stick.bottom_radius = 0.02
	stick.height = 1.35
	stick.material = wood
	var handle := MeshInstance3D.new()
	handle.mesh = stick
	handle.rotation.x = -0.6
	handle.position = Vector3(0.0, 0.58, 0.38)
	root.add_child(handle)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.12, 0.16)
	head_mesh.material = straw
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.06, 0.0)
	root.add_child(head)
	for m in [handle, head]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.visible = false
	return root

# --- LOD ---

## Дальше LOD_DISTANCE от камеры и вне кадра — обновление раз в LOD_STEP шагов с накопленным временем (0 — пропуск).
func _lod_delta(delta: float) -> float:
	if not errand or leader != null or state == &"knocked" or life == null or not is_instance_valid(life.camera):
		return delta
	var cam: Camera3D = life.camera
	var far := cam.global_position.distance_to(global_position) > LOD_DISTANCE and not cam.is_position_in_frustum(global_position + Vector3.UP)
	for near in [player, lada]:   # Илюша или «Лада» рядом (в тестах их ставят куда угодно) — полное обновление
		if far and is_instance_valid(near) and _flat(near.global_position).distance_to(_flat(global_position)) < LOD_NEAR:
			far = false
	if not far:
		if _lod_acc > 0.0:
			delta += _lod_acc
			_lod_acc = 0.0
			_lod_n = 0
		return delta
	_lod_acc += delta
	_lod_n += 1
	if _lod_n < LOD_STEP:
		return 0.0
	var d := _lod_acc
	_lod_acc = 0.0
	_lod_n = 0
	return d

# =====================================================================================
# PEOPLE-03 (P2): хоккей, снежки, санки, звуки и реплики занятий
# =====================================================================================

## Играет ли сейчас в kind (на занятии, не уходит, не скрыт, не сбит): life.players и шайба.
func is_playing(kind: StringName) -> bool:
	return _acting and _act_kind == kind and state == &"activity" and (kind == &"queue" or _wait > 0.0) and not hidden and knock_phase == &""

func is_hockey_active() -> bool:
	return is_playing(&"hockey")

## Крюк клюшки (там шайба, пока она у него).
func stick_point() -> Vector3:
	var f := _forward(facing_yaw)
	return _flat(global_position) + f * STICK_LEAD + Vector3(-f.z, 0.0, f.x) * STICK_SIDE

func _emit_sound(kind: StringName) -> void:
	sound_counts[kind] = int(sound_counts.get(kind, 0)) + 1
	activity_sound.emit(self, kind)

## Хоккей: катается к случайным точкам у своего места внутри LIFE_RINK_AREA, шайба — life.hockey_step. Время вышло —
## подкатывается к своему месту (оттуда путь по графу через проход). true — занятие ещё не может кончиться.
func _tick_hockey(delta: float, s: Dictionary) -> bool:
	_stick_swing = maxf(_stick_swing - delta, 0.0)
	var here := _flat(global_position)
	var ending := _wait <= 0.0
	if ending and life.puck_holder == self:
		life.hockey_leave(self)
	var goal: Vector3 = s.pos
	if not ending:
		if _act_target == Vector3.INF or here.distance_to(_act_target) < 0.3:
			_act_target = _hockey_target(s.pos)
		goal = _act_target
	var next := move_toward_v(here, goal, HOCKEY_SPEED * delta)
	distance_walked += here.distance_to(next)
	global_position = next
	var d := goal - next
	if d.length() > 0.01:
		facing_yaw = atan2(-d.x, -d.z)
	if not ending:
		var ev: StringName = life.hockey_step(self, delta, rng)
		if ev != &"":
			_emit_sound(ev)
			if ev == &"stick":
				_stick_swing = 0.25
	_wait -= delta
	return not ending or next.distance_to(s.pos) > 0.05

func _hockey_target(center: Vector3) -> Vector3:
	var area: Rect2 = Layout.LIFE_RINK_AREA
	var x := clampf(center.x + rng.randf_range(-HOCKEY_REACH.x, HOCKEY_REACH.x), area.position.x, area.end.x)
	var z := clampf(center.z + rng.randf_range(-HOCKEY_REACH.y, HOCKEY_REACH.y), area.position.y, area.end.y)
	return Vector3(x, 0.0, z)

## Санки: по петле Layout.LIFE_SLED_LOOP от места и обратно к нему. true — занятие ещё не может кончиться.
func _tick_sled(delta: float) -> bool:
	var loop: Array = Layout.LIFE_SLED_LOOP
	var p: Vector2 = loop[_act_i]
	var b := Vector3(p.x, 0.0, p.y)
	var here := _flat(global_position)
	var next := move_toward_v(here, b, SLED_SPEED * delta)
	distance_walked += here.distance_to(next)
	global_position = next
	var d := b - next
	if d.length() > 0.001:
		facing_yaw = atan2(-d.x, -d.z)
	_wait -= delta
	if next.distance_to(b) > 0.001:
		return true
	_act_i += 1
	if _act_i < loop.size():
		return true
	_act_i = 1
	return _wait > 0.0

## Снежки: лицом к тому, кто у крепости напротив (или к крепости), раз в SNOWBALL_EVERY лепит и кидает.
func _tick_snowball(delta: float) -> void:
	var foe: Resident = _snow_foe()
	var aim: Vector3 = foe.global_position + Vector3.UP * 1.0 if foe else SNOW_FORT_TOP
	facing_yaw = _yaw_to(aim)
	if not _ball_flight.is_empty():
		_ball_flight.t += delta
		var k := clampf(_ball_flight.t / SNOWBALL_FLIGHT, 0.0, 1.0)
		var to: Vector3 = _ball_flight.to
		if is_instance_valid(_ball_flight.who):
			to = _ball_flight.who.global_position + Vector3.UP * 1.0
		_ball.global_position = _ball_flight.from.lerp(to, k) + Vector3.UP * SNOWBALL_ARC * 4.0 * k * (1.0 - k)
		if k >= 1.0:
			if is_instance_valid(_ball_flight.who) and _ball_flight.who.is_playing(&"snowball"):
				_ball_flight.who.snow_hit()
			_ball.visible = false
			_ball_flight = {}
		return
	_throw_in -= delta
	if _throw_in > 0.0:
		return
	_throw_in = rng.randf_range(SNOWBALL_EVERY.x, SNOWBALL_EVERY.y)
	if _ball == null:
		_ball = _make_ball()
		add_child(_ball)
	var from := _flat(global_position) + _forward(facing_yaw) * 0.3 + Vector3.UP * 1.45
	var miss := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6)) if foe == null else Vector3.ZERO
	_ball_flight = {"from": from, "to": aim + miss, "t": 0.0, "who": foe}
	_ball.global_position = from
	_ball.visible = true
	snowballs += 1

func _snow_foe() -> Resident:
	for r in life.players(&"snowball"):
		if r != self:
			return r
	return null

## В него попали снежком: вздрогнул (_pose_activity), без вреда.
func snow_hit() -> void:
	snow_hits += 1
	_flinch = 0.35

## Сбит на хоккее или с санками — встал и продолжил занятие с того места, где его сбили (_resume_act).
func _resume_activity() -> bool:
	if _resume_act.is_empty(): return false
	var saved_spot: StringName = _resume_act.spot
	# За время падения опору могли сломать и восстановить, а освобождённое место — занять.
	# Своя прежняя бронь идемпотентна; чужая cap1 не даёт вернуть сохранённое занятие.
	if saved_spot != spot_id or not life.is_free(saved_spot, self) or not life.reserve(saved_spot, self):
		life.release(saved_spot, self)
		_resume_act = {}
		return false
	state = &"activity"
	_acting = true
	_act_kind = _resume_act.kind
	_wait = _resume_act.wait
	_act_i = _resume_act.i
	_act_t = 0.0
	_act_target = Vector3.INF
	_resume_act = {}
	resumes += 1
	return true

## Санки с внуком: позади на верёвке SLED_BACK, разворачиваются за жителем; телепорт (дверь, сброс) — сразу за спиной.
## Сбитый — санки стоят, где были. Скрип — через каждые SLED_CREAK_STEP м пути санок.
func _update_carry() -> void:
	if _sled == null:
		_sled = _make_sled()
		add_child(_sled)
		_sled.global_position = _flat(global_position) - _forward(facing_yaw) * SLED_BACK
	if state == &"knocked":
		return
	var here := _flat(global_position)
	var at := _flat(_sled.global_position)
	var to := here - at
	var dist := to.length()
	var was := at
	if dist > SLED_BACK * 2.5:
		at = here - _forward(facing_yaw) * SLED_BACK
	elif dist > SLED_BACK:
		at = here - to / dist * SLED_BACK
	if at.distance_to(was) < SLED_BACK * 2.0:
		_sled_moved += at.distance_to(was)
	if _sled_moved >= SLED_CREAK_STEP:
		_sled_moved = 0.0
		_emit_sound(&"sled")
	var dir := here - at
	_sled.global_position = at
	if dir.length() > 0.05:
		_sled.global_rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	# Верёвка: от передка санок к руке.
	var front := at + Vector3.UP * 0.2
	if dir.length() > 0.05:
		front += dir.normalized() * 0.5
	var hand := here + Vector3.UP * 0.75
	var rope := hand - front
	if rope.length() > 0.05:
		_sled_rope.global_transform = Transform3D(Basis.looking_at(rope.normalized()).scaled(Vector3(1.0, 1.0, rope.length())), (front + hand) * 0.5)

func sled_node() -> Node3D:
	return _sled

## Детские санки с внуком в санках — своя простая геометрия: полозья, рейки, спинка; внук — пуховик, шарф, шапка
## в цветах пацана ШКЯ (облик kid, CHARACTERS.md). Ноль коллизий, без теней от мелочи.
func _make_sled() -> Node3D:
	var root := Node3D.new()
	root.name = "Sled"
	root.top_level = true
	var metal := _plain(Color(0.20, 0.22, 0.26))
	var wood := _plain(Color(0.62, 0.42, 0.24))
	var jacket := _plain(Color(0.58, 0.84, 0.74))
	var scarf := _plain(Color(0.92, 0.48, 0.62))
	var skin := _plain(Color(0.97, 0.80, 0.70))
	var pants := _plain(Color(0.48, 0.16, 0.22))
	for x in [-0.17, 0.17]:
		_part3(root, _boxm(Vector3(0.025, 0.025, 0.95)), Vector3(x, 0.03, 0.0), metal)
		_part3(root, _boxm(Vector3(0.025, 0.025, 0.16)), Vector3(x, 0.08, -0.5), metal, Vector3(-0.8, 0.0, 0.0))   # загиб полоза
		for z in [-0.3, 0.3]:
			_part3(root, _boxm(Vector3(0.02, 0.14, 0.02)), Vector3(x, 0.1, z), metal)
	for k in 6:
		_part3(root, _boxm(Vector3(0.42, 0.02, 0.09)), Vector3(0.0, 0.18, -0.33 + k * 0.13), wood)
	_part3(root, _boxm(Vector3(0.42, 0.22, 0.03)), Vector3(0.0, 0.3, 0.38), wood, Vector3(0.25, 0.0, 0.0))   # спинка
	# Внук: сидит лицом вперёд (−Z), ноги вытянуты.
	_part3(root, _boxm(Vector3(0.24, 0.1, 0.34)), Vector3(0.0, 0.25, -0.12), pants)
	var body := CapsuleMesh.new()
	body.radius = 0.14
	body.height = 0.42
	_part3(root, body, Vector3(0.0, 0.42, 0.18), jacket)
	_part3(root, _torusm(0.1, 0.04), Vector3(0.0, 0.6, 0.18), scarf)
	_part3(root, _spherem(0.1), Vector3(0.0, 0.72, 0.17), skin)
	var hat := _part3(root, _spherem(0.105), Vector3(0.0, 0.77, 0.18), jacket)
	hat.scale = Vector3(1.0, 0.75, 1.0)
	_part3(root, _spherem(0.035), Vector3(0.0, 0.86, 0.2), scarf)   # помпон
	_sled_rope = MeshInstance3D.new()
	_sled_rope.name = "Rope"
	_sled_rope.mesh = _boxm(Vector3(0.012, 0.012, 1.0))
	_sled_rope.material_override = _plain(Color(0.75, 0.70, 0.6))
	_sled_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sled_rope.top_level = true
	root.add_child(_sled_rope)
	return root

## Клюшка: черенок наклонён к хоккеисту, крюк лежит на льду (корень — у крюка, как веник у метлы).
func _make_stick() -> Node3D:
	var root := Node3D.new()
	root.name = "Stick"
	var shaft := _part3(root, _boxm(Vector3(0.03, 0.03, 1.25)), Vector3(0.0, 0.48, 0.42), _plain(Color(0.55, 0.38, 0.22)), Vector3(0.82, 0.0, 0.0))
	shaft.name = "Shaft"
	_part3(root, _boxm(Vector3(0.28, 0.06, 0.035)), Vector3(-0.1, 0.05, 0.0), _plain(Color(0.12, 0.12, 0.14)))   # крюк, обмотан изолентой
	root.visible = false
	return root

func _make_ball() -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	ball.name = "Snowball"
	ball.mesh = _spherem(0.075)
	ball.material_override = _plain(Color(0.95, 0.97, 1.0))
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.top_level = true
	ball.visible = false
	return ball

static func _plain(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m

static func _boxm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

static func _spherem(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m

static func _torusm(r: float, thickness: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = r - thickness * 0.5
	m.outer_radius = r + thickness * 0.5
	m.rings = 10
	m.ring_segments = 4
	return m

func _part3(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

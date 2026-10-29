class_name StealthDirector
extends Node
## C7 (EXT-01 S): единственный владелец suspicion 0…1, state (safe / suspicious / alert) и frozen.
## Каждые POLL_SECONDS берёт max visibility() 0…1 по группе `detection_sensors`; рост до 1 за RISE_SECONDS × 1/видимость
## (EXT-02: коробка на ходу 0,75 → 2,67 с), «видят» — видимость > 0;
## спад в DECAY_FACTOR раза быстрее. Рост — не выше suspicion_cap видящих сенсоров (учебный автобус на улице A
## доводит шкалу до SUSPICIOUS, но не до провала); выше потолка шкала стоит, пока видят.
## Секторы видимости (show_cone) включаются, пока Илюша пешком ближе CONE_DISTANCE к сенсору (STEALTH_DESIGN). suspicion ≥ 1 — alert и сигнал player_detected один раз; дальше мир
## показывает провал и зовёт notify_respawned(): suspicion = 0, защита PROTECTION_SECONDS.
## frozen — набор причин (диалог, пауза, экран провала, защита после респавна): рост остановлен, спад идёт.
## Узел PAUSABLE: на паузе не тикает, а frozen читает get_tree().paused.
## Обнаружение не меняет MissionDirector (C5).
## EXT-01 fix2: detected_in_car — обнаружили «Ладу» с Илюшей на площадке киоска (сенсор с car_area, P1): мир
## отгоняет машину на парковку. grant_grace(seconds) — защита после диалога с полицейским (P2-3, этап 5).
## EXT-01 fix6: правило близости (DetectionSensor.NEAR_RADIUS): рост delta / RISE_SECONDS × видимость × near_rise_factor —
## множитель того сенсора, у которого видимость × множитель больше (ближе 3 м — ×3, провал за 0,67 с).

signal player_detected
signal state_changed(old: StringName, new: StringName)

const SAFE := &"safe"
const SUSPICIOUS := &"suspicious"
const ALERT := &"alert"

const POLL_SECONDS := 0.15
const RISE_SECONDS := 2.0
const DECAY_FACTOR := 1.5
const PROTECTION_SECONDS := 4.0
const CONE_DISTANCE := 25.0

var suspicion := 0.0
var state: StringName = SAFE
var frozen: bool:
	get:
		return not _reasons.is_empty() or _protection_left > 0.0 or (is_inside_tree() and get_tree().paused)
## Сколько раз сработал player_detected за мир.
var detections := 0
## Последнее обнаружение — в машине (сенсор с car_area видел «Ладу»); сбрасывает notify_respawned().
var detected_in_car := false

var _reasons := {}            # StringName -> true
var _protection_left := 0.0
var _poll_left := 0.0
var _visible_now := 0.0
var _near_now := 1.0          # fix6: множитель роста по последнему опросу
var _cap_now := 1.0
var _alerted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _physics_process(delta: float) -> void:
	_protection_left = maxf(_protection_left - delta, 0.0)
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left += POLL_SECONDS
		_visible_now = _max_visibility()
	if _alerted:
		return  # обнаружен: ждём респавна, шкала стоит на 1
	if _visible_now > 0.0 and not frozen:
		if suspicion < _cap_now:
			suspicion = minf(suspicion + delta / RISE_SECONDS * _visible_now * _near_now, _cap_now)
	else:
		suspicion = maxf(suspicion - delta * DECAY_FACTOR / RISE_SECONDS, 0.0)
	if suspicion >= 1.0:
		_alert()
	else:
		_set_state(SUSPICIOUS if suspicion > 0.0 else SAFE)

## Добавить или снять причину заморозки; причины могут перекрываться (диалог + пауза + провал).
func set_frozen(on: bool, reason: StringName) -> void:
	if on:
		_reasons[reason] = true
	else:
		_reasons.erase(reason)

## Мир поставил Илюшу на чекпоинт: шкала в ноль, защита от повторного обнаружения.
func notify_respawned() -> void:
	suspicion = 0.0
	_alerted = false
	_visible_now = 0.0
	_near_now = 1.0
	_poll_left = POLL_SECONDS
	_protection_left = PROTECTION_SECONDS
	detected_in_car = false
	_set_state(SAFE)

## Защита от роста шкалы на seconds (после диалога с полицейским: «может спокойно уйти», P2-3). Шкалу не сбрасывает —
## она спадает; уже идущая защита не укорачивается.
func grant_grace(seconds: float) -> void:
	_protection_left = maxf(_protection_left, seconds)

## Обнаружить сразу (fix3: вышел из машины на площадке киоска на глазах у полицейского): шкала в 1, провал — в
## ближайшем кадре. Во время заморозки (диалог, защита после респавна) не действует.
func alert_now() -> void:
	if frozen or _alerted:
		return
	suspicion = 1.0
	_alert()

func _alert() -> void:
	_alerted = true
	detections += 1
	detected_in_car = not _on_foot()
	_set_state(ALERT)
	player_detected.emit()

## Видит ли машину на площадке (car_area) хоть один включённый сенсор — при любой скорости.
func car_seen_now() -> bool:
	for sensor in get_tree().get_nodes_in_group(&"detection_sensors"):
		if sensor.get("enabled") != false and sensor.has_method("sees_car_now") and sensor.sees_car_now():
			return true
	return false

## Видит ли кто-то Илюшу сейчас (по кэшу сенсоров).
func visible_now() -> bool:
	return _visible_now > 0.0

func protection_left() -> float:
	return _protection_left

## Снимок для HUD и тестов.
func snap() -> Dictionary:
	return {
		"suspicion": suspicion,
		"state": state,
		"frozen": frozen,
		"reasons": _reasons.keys(),
		"protection_left": _protection_left,
		"visible": _visible_now > 0.0,
		"visibility": _visible_now,
		"near_rise_factor": _near_now,
		"detections": detections,
	}

func _max_visibility() -> float:
	var best := 0.0
	var best_rate := 0.0
	var cap := 0.0
	var on_foot := _on_foot()
	for sensor in get_tree().get_nodes_in_group(&"detection_sensors"):
		if sensor.get("enabled") == false:
			continue
		var seen: float = sensor.visibility()
		if seen > 0.0:
			cap = maxf(cap, float(sensor.get("suspicion_cap")) if sensor.get("suspicion_cap") != null else 1.0)
			var factor: float = float(sensor.get("near_rise_factor")) if sensor.get("near_rise_factor") != null else 1.0
			best_rate = maxf(best_rate, seen * factor)   # fix6: близость — быстрее
		best = maxf(best, seen)
		sensor.set("cone_wanted", on_foot and sensor.has_method("distance_to_player") and sensor.distance_to_player() < CONE_DISTANCE)   # в машине сектор не рисуется
	_cap_now = cap if best > 0.0 else 1.0
	_near_now = best_rate / best if best > 0.0 else 1.0
	return best

func _on_foot() -> bool:
	var world := get_parent()
	return world != null and world.get("control_mode") != &"in_car"

func _set_state(new_state: StringName) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(old, new_state)

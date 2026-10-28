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

var _reasons := {}            # StringName -> true
var _protection_left := 0.0
var _poll_left := 0.0
var _visible_now := 0.0
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
			suspicion = minf(suspicion + delta / RISE_SECONDS * _visible_now, _cap_now)
	else:
		suspicion = maxf(suspicion - delta * DECAY_FACTOR / RISE_SECONDS, 0.0)
	if suspicion >= 1.0:
		_alerted = true
		detections += 1
		_set_state(ALERT)
		player_detected.emit()
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
	_poll_left = POLL_SECONDS
	_protection_left = PROTECTION_SECONDS
	_set_state(SAFE)

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
		"detections": detections,
	}

func _max_visibility() -> float:
	var best := 0.0
	var cap := 0.0
	var on_foot := _on_foot()
	for sensor in get_tree().get_nodes_in_group(&"detection_sensors"):
		if sensor.get("enabled") == false:
			continue
		var seen: float = sensor.visibility()
		if seen > 0.0:
			cap = maxf(cap, float(sensor.get("suspicion_cap")) if sensor.get("suspicion_cap") != null else 1.0)
		best = maxf(best, seen)
		sensor.set("cone_wanted", on_foot and sensor.has_method("distance_to_player") and sensor.distance_to_player() < CONE_DISTANCE)
	_cap_now = cap if best > 0.0 else 1.0
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

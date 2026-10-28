class_name HideSpot
extends Interactable
## EXT-02 (docs/extension/HIDE_SPOTS.md, C7а): общий предок укрытий — коробка «БАТОНЫ», сугроб, бочка.
## Узел — зона E (Interactable) в группе &"hide_spots" с методом reset(); облик объекта в мире строит наследник
## в _build_look() (простые объёмы, как у павильона/контейнеров), облик на Илюше кладёт в player.hide_visual.
## Вход/выход — только через player.set_hide_mode(MODE, self) / set_hide_mode(&"none"); подсказку выставляет сам.
## Точки — только Layout (C1). Мир ищется вверх по дереву (как DetectionSensor): узел живёт под LevelGeometry/HideSpots.

const HideTuning = preload("res://game/stealth/hide_tuning.gd")

## Режим Илюши, который включает это укрытие: &"box", &"snowdrift", &"barrel" — задаёт наследник.
var mode: StringName = HideTuning.NONE
## Подсказки входа/выхода — задаёт наследник из HideTuning.PROMPT_*.
var prompt_enter := ""
var prompt_exit := ""
## Облик объекта в мире (виден, пока Илюша не внутри).
var look: Node3D
## Исходная точка (Layout), куда объект возвращается при reset().
var home := Vector3.ZERO
var home_yaw := 0.0

var _world: Node = null

func _init() -> void:
	add_to_group(&"hide_spots")

func _ready() -> void:
	super._ready()
	look = _build_look()
	if look:
		add_child(look)
	interacted.connect(_on_interacted)
	prompt = prompt_enter

## Мир (DemoWorld) — по классу, вверх по дереву; null в фоне меню.
func world() -> Node:
	if _world == null:
		var node := get_parent()
		while node:
			if node is DemoWorld:
				_world = node
				break
			node = node.get_parent()
	return _world

func player() -> Ilyusha:
	var w := world()
	return w.player if w else null

func is_occupied() -> bool:
	var p := player()
	return p != null and p.hide_mode == mode and p.hide_owner == self

func _on_interacted(_actor: Node) -> void:
	if is_occupied():
		exit()
	else:
		enter()

## Войти: наследник может переопределить (сугроб переставляет Илюшу на якорь). Возвращает успех.
func enter() -> bool:
	var p := player()
	if p == null or p.hide_mode != HideTuning.NONE:
		return false
	if not p.set_hide_mode(mode, self):
		return false
	_on_entered(p)
	prompt = prompt_exit
	if look:
		look.visible = false
	return true

## Выйти: наследник проверяет свободную точку выхода; при занятой — подсказка «ВЫХОД ЗАНЯТ» и false.
func exit() -> bool:
	var p := player()
	if p == null or not is_occupied():
		return false
	if not _exit_allowed(p):
		var w := world()
		if w and w.has_method("show_hide_hint"):
			w.show_hide_hint(HideTuning.HINT_EXIT_BLOCKED)
		return false
	if not p.set_hide_mode(HideTuning.NONE):
		return false
	_on_exited(p)
	prompt = prompt_enter
	_place_look_at_player(p)
	if look:
		look.visible = true
	return true

## Сброс при провале/респавне/перезапуске (DemoWorld.reset_hide): объект на исходной точке, подсказка входа.
func reset() -> void:
	prompt = prompt_enter
	global_position = home
	rotation.y = home_yaw
	if look:
		look.visible = true
		look.position = Vector3.ZERO
		look.rotation = Vector3.ZERO
	var hub := get_parent()
	if hub and hub.has_method(&"reset_gags"):
		hub.reset_gags()   # новая попытка: общий счётчик гэгов и их очередь — заново
	_on_reset()

## Гэг укрытия (раздел 11) — через общий лимит узла HideSpots (не больше HideTuning.GAG_LIMIT за попытку) в очередь
## SoundDirector.show_gag. true — гэг принят к показу; false — лимит попытки исчерпан (флаг «показан» наследник
## ставит сам: гэг в этой попытке больше не пробуется). Без узла HideSpots (тестовые укрытия) — прямо в SoundDirector.
func say_gag(id: StringName, lines: Array, seconds := HideTuning.GAG_PAGE_SECONDS) -> bool:
	var hub := get_parent()
	if hub and hub.has_method(&"request_gag"):
		return hub.request_gag(id, lines, seconds)
	var w := world()
	var sound: Node = w.get_node_or_null("SoundDirector") if w else null
	if sound == null or not sound.has_method(&"show_gag"):
		return false
	sound.show_gag(lines, seconds)
	return true

## EXT-02 P2-2 (вызывает DemoWorld.refuse_in_hide): в укрытии E у квестовой зоны (машина, диалог, покупка) —
## действие не выполняется, укрытие снимается обычным выходом (сугроб — со своей проверкой точки выхода: занята —
## «ВЫХОД ЗАНЯТ», Илюша внутри), и строка подсказки объясняет отказ (у окна в коробке — реплика продавщицы).
## Следующий E — обычное действие. Без своего укрытия (режим выставлен напрямую) — режим &"none".
static func leave_refused(w: Node, p: Ilyusha, interaction_id: StringName) -> void:
	var text := HideTuning.refusal_for(p.hide_mode, interaction_id)
	var own: Node = p.hide_owner
	var out := false
	if is_instance_valid(own) and own.has_method(&"exit"):
		out = own.exit()   # false — выход занят (подсказку уже выставил exit) или запрет перехода
	else:
		out = p.set_hide_mode(HideTuning.NONE)
	if out or not is_instance_valid(own):
		w.show_hide_hint(text)

# --- переопределяемые наследником ---
func _build_look() -> Node3D:
	return null
func _on_entered(_p: Ilyusha) -> void:
	pass
func _on_exited(_p: Ilyusha) -> void:
	pass
func _on_reset() -> void:
	pass
func _exit_allowed(_p: Ilyusha) -> bool:
	return true
## Куда ставить объект после выхода: по умолчанию — туда, где Илюша его снял (коробка/бочка остаются рядом),
## сугроб переопределяет (не двигается).
func _place_look_at_player(p: Ilyusha) -> void:
	global_position = Vector3(p.global_position.x, home.y, p.global_position.z) + p.global_basis.z * -1.2

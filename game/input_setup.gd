extends RefCounted
## Раскладка управления из канона (docs/DEMO.md, раздел 7) плюс решения владельца 28.10.2026 (вечер):
## прыжок Илюши и геймпад Xbox. Мышь для камеры пешком читается напрямую из InputEventMouseMotion,
## правый стик — через действия look_*.

static var installed := false
const PEDAL_DEADZONE := 0.05

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"car_gas": [KEY_W],
	"car_brake": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"interact": [KEY_E],      # взаимодействие, вход и выход из машины
	"handbrake": [KEY_SPACE], # ручник в машине
	"sprint": [KEY_SHIFT],   # быстрый бег пешком (PLAY-04)
	"jump": [KEY_SPACE],      # прыжок пешком (та же клавиша: пешком ручника нет)
	"punch": [KEY_F],         # удар пешком (PUNCH-01); ещё ЛКМ — MOUSE
	"pause": [KEY_ESCAPE],    # пауза, перезапуск, сброс автомобиля
	"phone": [KEY_P],        # телефон пешком (PHONE-01)
	"radio_station": [KEY_R], # станции приёмника только в машине (RADIO-01)
	"look_left": [], "look_right": [], "look_up": [], "look_down": [],
}

## Мышь (PUNCH-01): левая кнопка — удар пешком; при свободной мыши клик только захватывает её (Main, Ilyusha).
const MOUSE := {
	"punch": [MOUSE_BUTTON_LEFT],
}

## Геймпад Xbox: левый стик — ходьба и руль, правый — камера, A — прыжок, X — действие,
## B — ручник, RT/LT — газ и задний ход, Start — пауза. [действие, кнопка или [ось, направление]].
## В меню и диалогах (PAD-01): A — выбрать, B — назад (пауза: продолжить; диалог: выход, если он есть), крестовина и левый
## стик — по пунктам; в диалоге X, как E, листает реплики.
const JOY := {
	"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [[JOY_AXIS_LEFT_Y, 1.0]],
	"car_gas": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"car_brake": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	"interact": [JOY_BUTTON_X],
	"sprint": [JOY_BUTTON_LEFT_SHOULDER],
	"jump": [JOY_BUTTON_A],
	"handbrake": [JOY_BUTTON_B],
	"punch": [JOY_BUTTON_B],   # PUNCH-01: пешком B — удар, в машине — ручник (Илюша в машине ввод не читает)
	"pause": [JOY_BUTTON_START],
	"phone": [JOY_BUTTON_BACK],
	"radio_station": [JOY_BUTTON_DPAD_RIGHT],
}

static func install() -> void:
	if installed:
		return
	installed = true
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, PEDAL_DEADZONE if action in ["car_gas", "car_brake"] else 0.25)
		for code in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)
	for action in MOUSE:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for index in MOUSE[action]:
			var click := InputEventMouseButton.new()
			click.button_index = index
			InputMap.action_add_event(action, click)
	for action in JOY:
		for spec in JOY[action]:
			var event: InputEvent
			if spec is Array:
				var motion := InputEventJoypadMotion.new()
				motion.axis = spec[0]
				motion.axis_value = spec[1]
				event = motion
			else:
				var button := InputEventJoypadButton.new()
				button.button_index = spec
				event = button
			InputMap.action_add_event(action, event)
	# Меню и диалоги (PAD-01): во встроенных ui_accept и ui_cancel Godot 4.7 геймпада нет — только Enter/пробел и Esc,
	# поэтому кнопку меню и диалога с геймпада можно было выделить, но не нажать. A подтверждает, B отменяет.
	# Крестовина и левый стик в ui_up/ui_down/ui_left/ui_right есть у самого Godot (один толчок — один пункт).
	for action in UI_JOY:
		for index in UI_JOY[action]:
			var button := InputEventJoypadButton.new()
			button.button_index = index
			if not InputMap.action_has_event(action, button):
				InputMap.action_add_event(action, button)

## Геймпад для встроенных действий интерфейса (PAD-01).
const UI_JOY := {
	"ui_accept": [JOY_BUTTON_A],
	"ui_cancel": [JOY_BUTTON_B],
}

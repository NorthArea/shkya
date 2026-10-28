extends RefCounted
## Раскладка управления из канона (docs/DEMO.md, раздел 7) плюс решения владельца 28.10.2026 (вечер):
## прыжок Илюши и геймпад Xbox. Мышь для камеры пешком читается напрямую из InputEventMouseMotion,
## правый стик — через действия look_*.

static var installed := false

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"interact": [KEY_E],      # взаимодействие, вход и выход из машины
	"handbrake": [KEY_SPACE], # ручник в машине
	"jump": [KEY_SPACE],      # прыжок пешком (та же клавиша: пешком ручника нет)
	"pause": [KEY_ESCAPE],    # пауза, перезапуск, сброс автомобиля
	"look_left": [], "look_right": [], "look_up": [], "look_down": [],
}

## Геймпад Xbox: левый стик — ходьба и руль, правый — камера, A — прыжок, X — действие,
## B — ручник, RT/LT — газ и задний ход, Start — пауза. [действие, кнопка или [ось, направление]].
const JOY := {
	"move_forward": [[JOY_AXIS_LEFT_Y, -1.0], [JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"move_back": [[JOY_AXIS_LEFT_Y, 1.0], [JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	"interact": [JOY_BUTTON_X],
	"jump": [JOY_BUTTON_A],
	"handbrake": [JOY_BUTTON_B],
	"pause": [JOY_BUTTON_START],
}

static func install() -> void:
	if installed:
		return
	installed = true
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for code in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)
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
	# Меню и диалоги: A подтверждает, B отменяет, крестовина и левый стик ходят по кнопкам (ui_* уже знают геймпад).

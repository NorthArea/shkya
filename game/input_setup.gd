extends RefCounted
## Раскладка управления из канона (docs/DEMO.md, раздел 7).
## Мышь для камеры пешком читается напрямую из InputEventMouseMotion.

static var installed := false

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"interact": [KEY_E],      # взаимодействие, вход и выход из машины
	"handbrake": [KEY_SPACE], # ручник в машине
	"pause": [KEY_ESCAPE],    # пауза, перезапуск, сброс автомобиля
}

static func install() -> void:
	if installed:
		return
	installed = true
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.25)
		for code in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)

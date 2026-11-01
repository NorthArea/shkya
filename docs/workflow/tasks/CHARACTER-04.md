# CHARACTER-04 — стояние, посадка и выход из машины

Статус — [backlog](../backlog.md); объём MSG-0141 — [CHARACTER-01](CHARACTER-01.md).

- **Результат:** standing → подход/ориентация/дверь/рука/посадка → seat → безопасный выход/standing, своим движением/rig. Это переход тела и передачи управления, не смена настроенной автомобильной физики.
- **Первичный источник:** [3UR c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6, `src/game/ai/state.cpp`883–1109,1166–1294,1532–1702](https://github.com/3UR/Simpsons-Hit-Run/blob/c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6/src/game/ai/state.cpp#L883): approach/orient/open/seat/change locomotion/close и blocked fallback. Точные оригинальные клипы/траектории UNKNOWN, используются наши модели и анимации.
- **Текущий пробел:** `DemoWorld.enter_car/exit_car/_set_player_active` сразу скрывают/показывают героя и передают контроль; LadaDriver уже даёт сидячую модель, но переход тела/кистей не сделан.
- **Владение до назначения:** проектируется DemoWorld ↔ Ilyusha ↔ Lada/LadaDriver ↔ pose-контракт; исполнитель не назначен. Root владеет `game/world/demo_world.gd` и точкой передачи режима/сигналов; production только после контракта и стабильных CHARACTER-02/IP-01 seat/rig.
- **Совместная работа:** CHARACTER-02 владеет player air/helper; до параллельного кода согласовать единый air cancel/reset при enter/exit/place. Автор04 не добавляет второго владельца состояния в `ilyusha.gd`; общую player-интеграцию root сериализует.
- **Контракт/ошибки:** ровно одна передача control/driver/коллизии/видимости и одни enter/exit сигналы на переход; безопасные отмена/retry/blocked exit. Прежние публичные on_foot/in_car, C3-взаимодействие и C4 сохраняют смысл для потребителей; промежуточный переход не должен выдавать ложный успешный въезд/выход.
- **Настоящие потребители:** CameraRig, Main/пауза/Phone, радио и звуки двигателя, MissionDirector, сенсоры/укрытия, посадка LadaDriver. Тело проходит вокруг реального кузова без клиппинга; стоячую модель не сжимать ради салона.
- **Независимая QA:** repeated E/X, заблокированный выход, пауза/телефон, reset/fail/input lock в каждой фазе, одна driver/occupant-модель, вход после air и отмена без pending jump/hit. Реальные Main/C4/PAD/PHONE/RADIO/DEMO/seat/камера/стелс; authored animation не принимать по одному pose helper.
- **Ограничения/evidence:** камера/миссии/маршруты/число жителей и канон сохраняются; свои код/ассеты. `builds/checks/CHARACTER-04/`; только headless/Dummy, реальный игровой вид/ощущения/GPU/FPS открыты. Реализация/приёмка не начаты.

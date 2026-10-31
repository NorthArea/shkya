# VEHICLE-01

Статус — только в [backlog](../backlog.md).

Результат: Реальный slide contact -> общий impulse resolver -> скорости/смещение и уникальный повреждённый кузов игрока/traffic/parked.

Область: vehicle_collision_damage: vehicles; world_edges_signs: parked adapter; root: независимая проверка/коммит.

Критерии: Нормальная относительная скорость/масса/точка; без пробоя стен; скольжение не даёт вмятин; накопление и reset; сохранено движение и возврат трафика.

Проверка: Developer physics test + независимый contact acceptance root; DRIVE/TRAFFIC/PLAY04_CAR/BREAK, затронутые укрытия; изображение/FPS отдельно.

Открыто: реализация/проверки и ручная проба по границам задачи. Чужой WIP не откатывать.

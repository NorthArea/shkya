# VEHICLE-01

Статус — только в [backlog](../backlog.md).

Результат: Реальный slide contact -> общий impulse resolver -> скорости/смещение и уникальный повреждённый кузов игрока/traffic/parked.

Область: vehicle_collision_damage: vehicles; world_edges_signs: parked adapter; root: независимая проверка/коммит.

Критерии: Нормальная относительная скорость/масса/точка; без пробоя стен; скольжение не даёт вмятин; накопление и reset; сохранено движение и возврат трафика.

Проверка: Developer physics test + независимый contact acceptance root; DRIVE/TRAFFIC/PLAY04_CAR/BREAK, затронутые укрытия; изображение/FPS отдельно.

Проверено: developer18/0, independent actual contacts32/0; DRIVE51/0 CAR147/0 TRAFFIC160/0 DRIVE02 48/0 BREAK182/0, BOX112/0 SNOW94/0 BARREL102/0 clean. Native WORLD36/0 и22 кадра без generic debris поверх вмятин. C9 текущей сцены118,5/67,4. Открыто: ручная проба силы удара/вмятин владельцем.

Первичные источники 3UR@c84f9ff: [solver](https://github.com/3UR/Simpsons-Hit-Run/blob/c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6/src/libs/sim/simcollision/impulsebasedcollisionsolver.cpp#L156) — относительная скорость и mass matrices, normal/tangent response; [physicsobject](https://github.com/3UR/Simpsons-Hit-Run/blob/c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6/src/libs/sim/simphysics/physicsobject.cpp#L526) — mass/inertia/плечо; [vehicle damage](https://github.com/3UR/Simpsons-Hit-Run/blob/c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6/src/game/worldsim/redbrick/vehicle.cpp#L4568) — решённый impulse, локальная сторона кузова и меньшая severity инициатора; [traffic recovery](https://github.com/3UR/Simpsons-Hit-Run/blob/c84f9ff9ae9b27a5d34dca7985ac819e70f62bc6/src/game/worldsim/traffic/trafficmanager.cpp#L1795) — rest/free path и непрерывный возврат из actual pose.

Реализация своя: planar contact, normal/tangent friction, общий same-frame guard, отдельная косметическая задержка; impulse-based локальные private-mesh вмятины. Массы/пороги/аркадные пределы — tuning Города Н, значения только в коде. Полное совпадение ощущениям эталона source review не доказывает.

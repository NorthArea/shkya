# WORLD-02

Статус — только в [backlog](../backlog.md).

Результат: Layout/perimeter -> видимая граница и контакт; дорожные таблички; parked alarm -> реальные световые точки.

Область: world_edges_signs: layout/perimeter/skyline/level_geometry/breakables/road_closure; root карта/приёмка.

Критерии: А1/Г5/Д5 остановка до текстур, дороги имеют конец; таблички не пересекаются; мигание следует yaw/смещению реальной машины.

Проверка: Headless WORLD02/PERIMETER и адресные ROAD/CROSS/TRAFFIC; графические кадры отдельно.

Проверено: WORLD37/0 CPU (envelope RED37/1), native38/0 с envelope; final22 реальных кадра, независимый review границ/знаков/сигнализации. Табличка целиком вынесена из фасада, контраст/опора P2 закрыты на native-final. Вмятины без generic steel-debris; это не подтверждение формы dent при свете фар. Карта актуальна. Открыто: ручной проезд владельцем; свет и пластика — отдельные LIGHT/VEHICLE.

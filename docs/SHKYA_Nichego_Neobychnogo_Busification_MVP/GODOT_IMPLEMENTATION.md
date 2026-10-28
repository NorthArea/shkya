# План интеграции в Godot

## Предположение о существующем коде
Уже работают пешее управление, машина, проезд до киоска, диалог и покупка хлеба. **Не переписывать эти системы**. Добавить независимый модуль наблюдения, патрулей и реакции миссии на обнаружение.

## Архитектура сцен (пример, адаптировать под репозиторий)
```
World/CityN
  Patrols/Officer01 (CharacterBody3D or Node3D)
  Patrols/AccountOfficer01 (Node3D)
  Patrols/Guard01 (Node3D, optional P1)
  Vehicles/CityVan01 (Node3D with Path3D / PathFollow3D)
  Stealth/DetectionCoordinator (Node)
  Stealth/StealthCheckpoint (Area3D)
  UI/SuspicionMeter (CanvasLayer)
  UI/DetectionToast (CanvasLayer)
```

## Скрипты
- `detection_sensor.gd` — чистая логика distance/angle/line-of-sight/accumulator; компонент для разных типов патрулей.
- `patrol_route.gd` — обход фиксированных точек или поворот на месте.
- `city_van.gd` — движение по PathFollow3D, состояние stop/drive, видимость через DetectionSensor; не использовать сложный VehicleBody3D без нужды.
- `stealth_coordinator.gd` — агрегирует сенсоры, одна шкала обнаружения и сигнал `player_detected`.
- `mission_extension.gd` — реакция на покупку и обнаружение, checkpoint, переключение состояния патруля после хлеба.
- `suspicion_meter.gd` — индикатор, плавное заполнение; подсказка при первом появлении.

## Состояния существующего квеста
```
NOT_STARTED
  -> ACCEPTED
  -> DRIVING_TO_KIOSK
  -> APPROACHING_KIOSK
  -> BREAD_BOUGHT
  -> RETURNING_HOME
  -> READY_TO_TURN_IN
  -> COMPLETED
```
**Обнаружение не меняет бизнес-состояние квеста.** Только возвращает к нужному checkpoint. `has_bread` хранится устойчиво.

## Порядок реализации
1. Ввести `DetectionSensor` для неподвижного полицейского; тестовый сектор видимости.
2. Добавить suspicion meter и плавное снижение тревоги.
3. Проверить укрытия raycast и две проходимые альтернативы.
4. Чекпоинт/рестарт без потери прогресса покупки.
5. Автобус как PathFollow3D с постановочной остановкой.
6. Реплики и короткий fail screen.
7. Патруль смещается после покупки хлеба; тест на softlock.
8. Только после полировки включать росгвардейца как второй patrol, если необходимо.

## Перформанс
- Частота LOS 5–10 Гц, не обязательно каждый physics frame.
- Деактивировать сенсоры вдали от игрока.
- Стационарные коллизии укрытий и заранее заданные маршруты — без симуляции толпы.
- Сетевой мультиплеер, сложные NPC-диалоги, procedural AI, полномасштабный транспорт НЕ нужны.

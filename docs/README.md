# Документация ШКЯ: Ничего необычного

## Порядок приоритета

При расхождении действует источник выше по списку.

1. [DECISIONS.md](DECISIONS.md) — действующие решения владельца по темам (и отдельный блок решений интегратора, которые владелец может отменить). Новое решение записывается только сюда.
2. [extension/](extension/README.md) — канон расширения «Ничего необычного», 6 файлов без правок: README, MISSION_EXTENSION, STEALTH_DESIGN, GODOT_IMPLEMENTATION, DIALOGUES_AND_JOKES, ACCEPTANCE_TESTS. Перекрывает раздел 3 DEMO («Не входит») там, где расходится с ним.
3. [extension/HIDE_SPOTS.md](extension/HIDE_SPOTS.md) — ТЗ трёх укрытий у киоска и коэффициента заметности; правится только по решению владельца.
4. [DEMO.md](DEMO.md) — ТЗ демо «За хлебом» 1.0 от 27.10.2026, файл из `SHKYA_NOVOSIBIRSK_DEMO.zip` без изменений: художественные требования, границы MVP, десять экранов, FSM квеста (раздел 6), приёмочные сценарии (раздел 8), лицензии (раздел 9).
5. [Концепты](art/README.md) — кадры 01–10 и e01–e05; текст важнее кадра. Итоговый облик: [персонажи](art/CHARACTERS.md), [город](art/CITY.md).
6. [SHKYA_NOVOSIBIRSK_AGENT_REFERENCES.md](SHKYA_NOVOSIBIRSK_AGENT_REFERENCES.md) — единственный набор внешних референсов, без правок; запреты его раздела 6 действуют наравне с каноном.

Значения констант — только в коде. Контракты кода — [workflow/README.md](workflow/README.md).

[Карта арены — PNG](maps/arena.png) · [SVG для увеличения](maps/arena.svg). Геометрия, проходы, улицы и ориентиры берутся из данных игры. Обновление — `make map`, проверка актуальности — `python3 tools/generate_arena_map.py --check`; перед запуском игры и проверок карта обновляется автоматически.

## Процесс

- [workflow/README.md](workflow/README.md) — как брать работу, статусы, общие контракты C1–C11.
- [workflow/backlog.md](workflow/backlog.md) — очередь и единственный живой статус задач, открытые вопросы владельцу.
- [requests/OWNER_MESSAGES.md](requests/OWNER_MESSAGES.md) — дословный архив просьб, уточнений и команд владельца; [JSON](requests/owner_messages.json) сохраняет исходные записи и связи с задачами для продолжения после перезапуска.
- `workflow/tasks/` — карточки открытых задач.
- [Запуск, управление, проверки](../README.md); правила для агентов — [AGENTS.md](../AGENTS.md).

Логи и кадры запусков — в игнорируемых `builds/checks/` и `builds/screenshots/`. `docs/.gdignore` исключает документацию из импорта Godot.

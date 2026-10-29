# CANON-01 — Канон в одной структуре, чистый репозиторий

Статус: review (29.10) — ждёт подтверждения удалений владельцем. Поручение владельца 29.10: «Критерий приёмки: чёткий, ясный, структурированный канон и чистый репозиторий».

**Структура.** `AGENTS.md` — правила и карта источников; `docs/README.md` — порядок приоритета; `docs/DECISIONS.md` — решения владельца по темам (+ блок интегратора); `docs/art/CHARACTERS.md`, `CITY.md`, `README.md` — облик и индекс концептов; `docs/workflow/README.md` — процесс и контракты C1–C11; `backlog.md` — статус; `tasks/` — только открытые задачи; `assets/README.md` — источники и лицензии.

**Противоречия аудита (раздел B) → где теперь одно значение.**

| № | Где | № | Где |
|---|---|---|---|
| 1, 2 контур, лицо Бабки | DECISIONS «Персонажи: облик», CHARACTERS | 14 V04 | DECISIONS «Референсы», art/README |
| 3 куржак | DECISIONS «Город: приметы», CITY | 15 слои | C2 |
| 4, 5 3D-персонажи | DECISIONS «Персонажи: форма»; backlog CHAR3D | 16 `officer2` | C7, CHARACTERS |
| 6 порядок канона | DECISIONS, docs/README, AGENTS | 17 C9–C11 | workflow/README |
| 7 деньги | DECISIONS «Идеи Hit & Run», C5 | 18 закрытые карточки | удалены |
| 8 подвеска | DECISIONS «Машина» | 19, 20 статусы | backlog, карточки |
| 9 полиция, прохожие, очередь | DECISIONS «Расширение», «Прохожие»; блок интегратора | 21 статус в README | убран |
| 10 реплики | DECISIONS «Реплики прохожих», «Тексты» | 22 управление | README ← `CONTROLS` |
| 11 механики, двор | DECISIONS «Сбивание»; интегратор «Двор» | 23 `lada_raycast` | строка убрана |
| 12 ёлка, гирлянды | интегратор «Сезон»; ARENA-02 Z5 | 24 город Н. | DECISIONS «Город» |
| 13 коробки у киоска | интегратор «Площадка киоска» | 25 платформа | DECISIONS «Платформа» |

**Объём.** Markdown в Git: 80 911 → ≈ 27 900 слов (из них ≈ 8 400 — неизменяемый канон); карточек в `tasks/`: 40 → 17; AGENTS.md: 1 784 → 429 слов.

**Решения исполнителя.** `make pack` и `tools/pack.gd` убраны: сборки сняты владельцем 28.10 (BUILD-01), пакер писал имя прежнего названия и не клал SVG и шрифты. DRIVE-03 — review: прототип D ждёт пробы владельца. В HIDE_SPOTS.md исправлен только мёртвый путь набора (`hide_spots_test.gd` → четыре набора `hide_*`). Импорт `resident_ushanka_walk_*` — мипмапы включены (как у остальных SVG, LOOK-01). Комментарии «ART-06, Н4» у труб ТЭЦ → Н7 (номер в каталоге).

**Проверка.** Ссылки (относительные Markdown, `res://`, `docs/…md` и `--script` в коде): 0 мёртвых. `make test`: 23 набора из 25 — 0 failures; STUCK (5) и DRIVE02 (2) падают так же на базе 1210406 без CANON-01 (проверено отдельным worktree) — это DRIVE-02 поверх E, записано в карточке DRIVE-02.

**Удалённые файлы — подтверждает владелец.**
- Карточки закрытых задач (25): `docs/workflow/tasks/` BOOT-01, GREY-01, MISSION-01, DRIVE-01, QUEST-01, POLISH-01, QA-01, BUILD-01, ART-01, ART-02, ART-03, ART-04, ART-05, ART-06, PLAY-01, PLAY-02, EXT-01, EXT-02, ARENA-01, CITY-01, PEOPLE-01, PEOPLE-02, LOOK-01, CHAR3D-01, CHAR3D-02 (`.md`).
- Каталог (1): `docs/art/shkya_characters.md` → CHARACTERS.md.
- Прототип 3D-персонажей (8): `game/characters/character_body3d.gd` и `.uid`, `character_look.gdshader` и `.uid`, `tests/char3d_test.gd` и `.uid`, `tools/character_passports.py`, `assets/art/characters/passports.json`; история — 7514774 и ветка `char3d-02-wip`.
- Мусор (4): `game/world/coin_layout.gd.uid`, `drone_layout.gd.uid`, `tools/pack.gd` и `.uid`.
- Перенесены, не удалены: съёмщики кадров и пробники → `tools/capture/` (`capture`, `capture_art01`, `capture_intro`, `quest01_capture`, `polish01_quit`, `city02e_frames`, `e_probe`, `e_window`, `d2_frames`).

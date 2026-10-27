# BOOT-01 — Каркас проекта

Результат: репозиторий устроен как last-signal; канон и кадры на месте; проект открывается в Godot 4.7.2 и запускается `make run`; `make test` проходит.

Владелец: root. Файлы: `AGENTS.md`, `CLAUDE.md`, `README.md`, `Makefile`, `.gitignore`, `project.godot`, `docs/`, `assets/README.md`, `game/main.tscn`, `game/main.gd`, `game/input_setup.gd`, `tests/smoke_runner.gd`, `tools/run.command`, `tools/godot.sh`, `tools/pack.gd`.

Источник: `SHKYA_NOVOSIBIRSK_DEMO.zip` от 27.10.2026. `DEMO_TASK.md` скопирован в `docs/DEMO.md` без изменений (SHA-256 `479f8e2e…72492`), десять PNG — в `docs/art/concepts/` без изменений. `tools/run.command` и `tools/godot.sh` взяты из last-signal как есть, `tools/pack.gd` — с другим именем PCK.

Технические выборы: GDScript, Forward+ (канон: ПК Windows/Linux, «обычный игровой ПК»), viewport 1920×1080 как в last-signal, слои физики World/Player/Car/Interact. Раскладка — только клавиши из раздела 7 канона, задаётся кодом в `game/input_setup.gd`.

Граница: главная сцена — заглушка с названием, без меню, мира и миссии.

Проверка 27.10.2026:

- `make test` — **10/10**, exit 0, без ERROR/WARNING: главная сцена загружается, все семь действий раскладки установлены, `interact` = `E`. Лог `builds/checks/boot01/smoke.log`.
- `tools/run.command --quit-after 90` — окно открылось, `Metal 4.0 - Forward+`, Apple M5 Pro, exit 0, без ошибок. Лог `builds/checks/boot01/window.log`.

Это проверка каркаса, не приёмка демо.

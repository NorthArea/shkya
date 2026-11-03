# STARTUP-01 — простая заставка загрузки

Статус — только [backlog](../backlog.md). Поручение MSG-0235.

- Результат: лёгкий экран в стиле тёплого окна в зимнем городе, реальная полоса загрузки и доступная после готовности кнопка. Сохраняет прежнее меню/settings/intro/profile.
- Владение: startup_loading_screen — новая boot сцена/скрипт, точка входа project.godot и developer tests; startup_screen_qa — независимый acceptance; root — канон/Makefile/Git.
- Контракт: без preload тяжёлой Main из boot; ResourceLoader threaded progress, ошибка/retry, защита повторной активации, keyboard/gamepad и focus, освобождение boot после handoff. Загрузка ресурсов не является прогрессом процедурной сборки мира.
- Проверка: реальная main.tscn без предварительного preload; изолированные profile paths до Main._ready; прежнее единственное меню/фон и world=null после перехода. Dummy/NoFocus native только адресно, сам закрывается.
- Кадры: builds/screenshots/STARTUP-01/startup-1920x1080.png и startup-1920x1200.png; root просмотрел 1080p.
- Evidence: builds/checks/STARTUP-01/: gamepad blocker исправлен; independent handoff22headless/23native, новые aggregate developer19/0 и acceptance22/0 headless. В lifecycle-final пять циклов не показали роста objects/resources/orphans после одинаковой очистки; shutdown warning74RefCounted0 сохраняется. Это не clean teardown и не доказанная причина FPS. Native2resources ещё требуют отдельной проверки.

# STARTUP-01 — заставка после меню

Статус — только [backlog](../backlog.md). Поручение MSG-0235/0263.

- Результат: главное меню → реальная загрузка demo_world → кнопка готовности → прежнее вступление и геймплей.
- Точка входа Main; меню, пауза и финальная карточка запускают встроенный loading screen. Прямой start_game сохраняет hook headless-проверок.
- Контракт: ResourceLoader threaded progress, ошибка/retry, защита повторного старта, keyboard/gamepad focus; возврат в меню отменяет pending handoff. Ресурсная загрузка не выдаётся за прогресс процедурной сборки мира.
- Evidence: builds/checks/STARTUP-01/menu-order-before.log (5/1), menu-order-after.log (26/0), startup01_test-development.log (19/0). Независимая QA и проверка чистого clone — TRANSFER-01.
- Визуальная/ручная приёмка открыта; headless не подтверждает рендер/FPS. Старые startup-before-menu evidence остаются историческими. Известное предупреждение ObjectDB при teardown мира не объявляется исправленным.

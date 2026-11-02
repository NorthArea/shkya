# MOTION-01 — рывки героя, камеры и нестабильный кадр

Статус — [backlog](../backlog.md); исходные MSG-0145/0146 — [архив](../../requests/OWNER_MESSAGES.md).

- **Результат:** стабильное относительное движение героя и камеры при беге; измеренный источник дорогих кадров устранён, если подтверждён. Отдельно разобрать ошибку softshadow при смене мира.
- **Исходный срез:** владелец запускал основной city-03 с LOCOMOTION-01; CHARACTER02/03/05/07 ещё изолированы и причиной этого native-прогона не объявляются.
- **Владение:** root интеграция; car02_independent_acceptance — камера/короткая проба; shkya_likeness_director — персонажный temporal pipeline/CPU; native_warning_triage — native softshadow/world teardown. До доказательства причины production не менять.
- **Проверка:** postphysics/render sampling raw/interpolated transforms, SpringArm/reset, pose timing, краткий CPU profile. Background-test contention учитывать отдельно. Headless не доказывает GPU/FPS/восприятие; видимая проверка только по отдельному разрешению.
- **Ограничения:** не менять настроенную камеру/скорости/сходство ради маскировки рывков; сохранить чужие WIP. Длинные фоновые прогоны во время просмотра владельцем не запускать.
- **Evidence:** `builds/checks/MOTION-01/`; production-патч только после причинного воспроизведения, затем адресные проверки и ручная оценка.

- **Проверенный CPU-срез:** `BonePoseBuffer` только у героя, restore current перед физикой и render-blend после неё; короткий sprint contact при прежнем общем contact. Независимый RED14/1→GREEN14/0, основной LOC476/0. Кадровый FPS/GPU и ошибка softshadow ещё не приняты.

- **Повторный отзыв MSG-0148:** actual Player на плоском полу4/8м/с не прыгает (rootY=0). На4м/с hip/head p2p≈9.6см; на8м/с реальные стопы одновременно выше2.5см≈85% physics-кадров. Источник — планирование позы, а не физический прыжок; прежний8-only hip-step oracle этого не исключал. Логи `hero_bounce_probe`/`pelvis_duty_probe` в MOTION-01.

- **Новый основной срез c23a4a1:** плавный hero-only профиль короткого низкого шага на4/8м/с; свободная нога не задаёт снижение опорного тела. RealPlayer RED24/5→GREEN24/0, LOC476/0, SMOKE23/0, source-review без замечаний. При переносе CHARACTER02/03/05 не перекрывать новым старым планировщиком из рабочей ветки; повторить24оракула.

- **Диагностика MSG-0155 (fps_walk_camera):** `tools/motion01_walk_cpu_probe.gd`, `walk-cpu.log` в Evidence; основной срез66453cf, Dummy/fixed60, idle/turn/walk/walk+turn по120 измеренных кадров. Камера≈0.064–0.067мс (max0.107), физическая фаза≈1.91–2.01мс (max3.32); короткий CPU-spike не воспроизведён. Прогон камеры не меняет production.
- **CPU и пределы замера:** прямые вызовы77 CharacterSprite≈0.752мс,64 Resident≈0.320мс; это отдельный microbench, не сумма кадра. NPC LOD зависит от направления камеры, но causal spike не подтверждён; сценарии идут последовательно, время мира и позиции различаются. Сценография:1904 MeshInstance,906 MultiMeshInstance,60 источников с shadow_enabled. Их реальная видимость/стоимость GPU не измерена. Native walk+turn/frame pacing/GPU и softshadow teardown — NOT_RUN; прежний drive-only FPS-test их не покрывает.

- **Новый запуск MSG-0174:** владелец выполнил `make run`; exit0 не означает исправления native: снова `_instance_unpair`, `geom->softshadow_count==0 - BUG!`, `renderer_scene_cull.cpp:348`, `_swap_world` (`game/main.gd:96`). MSG-0176 отвергает согнутую позу imported hero и стопы как «лыжи»; quick08 98/0 не является визуальной приёмкой. По MSG-0177 сначала новая mesh-only модель из04 в чистой сессии, затем анимация. Точка продолжения и сохранение перед перезапуском — IP-01; новые проверки до возобновления не запускать.

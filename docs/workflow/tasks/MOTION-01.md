# MOTION-01 — рывки героя, камеры и нестабильный кадр

Статус — [backlog](../backlog.md); исходные MSG-0145/0146 — [архив](../../requests/OWNER_MESSAGES.md).

- **Результат:** стабильное относительное движение героя и камеры при беге; измеренный источник дорогих кадров устранён, если подтверждён. Отдельно разобрать ошибку softshadow при смене мира.
- **Исходный срез:** владелец запускал основной city-03 с LOCOMOTION-01; CHARACTER02/03/05/07 ещё изолированы и причиной этого native-прогона не объявляются.
- **Владение:** root интеграция; car02_independent_acceptance — камера/короткая проба; shkya_likeness_director — персонажный temporal pipeline/CPU; native_warning_triage — native softshadow/world teardown. До доказательства причины production не менять.
- **Проверка:** postphysics/render sampling raw/interpolated transforms, SpringArm/reset, pose timing, краткий CPU profile. Background-test contention учитывать отдельно. Headless не доказывает GPU/FPS/восприятие; видимая проверка только по отдельному разрешению.
- **Ограничения:** не менять настроенную камеру/скорости/сходство ради маскировки рывков; сохранить чужие WIP. Длинные фоновые прогоны во время просмотра владельцем не запускать.
- **Evidence:** `builds/checks/MOTION-01/`; production-патч только после причинного воспроизведения, затем адресные проверки и ручная оценка.

- **Проверенный CPU-срез:** `BonePoseBuffer` только у героя, restore current перед физикой и render-blend после неё; короткий sprint contact при прежнем общем contact. Независимый RED14/1→GREEN14/0, основной LOC476/0. Кадровый FPS/GPU и ошибка softshadow ещё не приняты.

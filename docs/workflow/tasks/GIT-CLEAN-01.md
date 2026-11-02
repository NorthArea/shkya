# GIT-CLEAN-01 — очистка веток Git

- Поручение: MSG-0185; рабочая ветка master, лишние ветки удалить с сохранением истории.
- Локально оставлена master; она отслеживает origin/master. Удалены 10 старых веток и 6 записей отсутствующих worktree.
- На GitHub удалены 10 старых веток после проверки архивных тегов.
- Отдельная история сохранена в тегах archive/2026-11-02/{break-03,char3d-02-wip,polish-03c,wip/character-boarding,wip/character-mechanics}.
- Остаток: GitHub default branch пока main; она сохранена до смены настройки. Доступен Git по SSH, GitHub API-авторизации нет.
- Действие владельца: https://github.com/NorthArea/shkya/settings → Default branch → master.
- После смены проверить remote HEAD и удалить origin/main; обновить origin/HEAD. Не переписывать историю и не удалять архивные теги.
- Живой статус — только в backlog.md. Файлы проекта при очистке веток не удаляются.

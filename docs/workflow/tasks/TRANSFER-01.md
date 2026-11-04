# TRANSFER-01 — сохранность работы и перенос через Git

Статус — только [backlog](../backlog.md). Поручения MSG-0263–0268.

- Основной путь — clone из Git, инструкция docs/TRANSFER.md. Код, ресурсы и исходные сообщения сохранены атомарными коммитами; push разрешён владельцем.
- Полный архив builds/transfer/2026-11-04/repository.tar.gz: 35082 entries, SHA256/readback и сравнение с исходниками; изменялся только .idea/workspace.xml. Внешний manifest, verify_backup.py. Финальные коммиты — также final-history.bundle; проверены bundle verify и clone/fsck.
- Чистый clone: 41 PASS-набор. Итоги/исходные failure attempts — builds/checks/TRANSFER-01/shkya-transfer-headless-aggregate.json и clean-clone-make-test/. Нельзя заявлять общий make PASS: ART01 требует прежние3D/150см, STUCK sweep остановлен; 5native/65прочих NOT_RUN. HERO2D27/0; relevant startup19/26, intro141, settings346, controls224, mission410, quest259, audio112/55 — всё0failures. Известные ObjectDB/audio teardown warnings не объявлены исправленными.
- Блокер: GitHub отказывает publickey и владельцу в обычном git push. Ключ id_ed25519 есть в публичных Authentication keys аккаунта NorthArea, загружен через macOS Keychain; изолированный конфиг и порт443 также отклонены. Секреты не выводились. Причина серверного отказа не установлена. HTTPS читает публичный repo, но writeauth отсутствует.
- Все пять archive/2026-11-02/* тегов совпадают с remote. После восстановления доступа: git push origin main; сверить удалённый refs/heads/main с локальным HEAD, затем закрыть задачу и обновить final-history.bundle. Force push не нужен.

- Проверка 04.11 15:22 Алматы: официальный githubstatus.com сообщает ongoing incident Git Operations/Issues/Pull Requests с09:49UTC(14:49Алматы), статус investigating. https://stspg.io/18blsgwnbyy6. Возможная причина publickey отказов; именно SSH инцидентом отдельно не подтверждён. Ключи не переиздавать без новых свидетельств.

# RADIO-02

Статус — только в [backlog](../backlog.md).

Результат: От входа за руль до настройки, музыки и новости; CarRadio/RadioMusic/SoundDirector, closure и broken.

Область: radio_news_v2: audio и радио sections тестов; root: интеграция и Makefile.

Критерии: Слышная настройка; ≥5с фактической музыки перед одной погодой; urgent duck внутри трека; ordinary только finished gap; классика без диктора.

Проверка: Headless RADIO02/RADIO01, AUDIO, STORY02; тайминги/пауза/выход/станции, реальные события и отсутствие ложных новостей.

Проверено: RADIO02 30/0, независимые interleaving19/0, native RADIO01 55/0, AUDIO52/0, STORY02 51/0; clean logs `builds/checks/RADIO-02/`, `INTEGRATION-02/verified/` и `retry/story02_test.log`. Сохранён остаток обычной передачи при urgent/паузе/смене станции. Ручной слуховой баланс и художественная проба открыты.

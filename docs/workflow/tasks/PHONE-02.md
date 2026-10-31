# PHONE-02

Статус — в [backlog](../backlog.md).

Результат: реальный левый стик перемещает фокус между новостями/СМС, A выбирает; LB/RB напрямую выбирают раздел. ↑/↓ открывают/закрывают, ←/→ листают.

Причина: Phone._input поглощал все JoypadMotion до GUI. Исправление пропускает их в GUI и явно связывает горизонтальные focus-соседи.

Область: root — phone.gd и phone02_navigation_test.gd; подсказка внутри телефона.

Проверка: RED9/3→GREEN9/0 на реальных JoypadMotion/Button, пешком и за рулём. PHONE01/PAD03/independent navigation regression и внешний вид подсказки открыты.

# COINS-01 — Монетки: 35 рублей до батона

Статус: review (29.10) — ждёт игры владельца.

**Результат.** Стартовых денег нет; по городу разложены монеты-рубли, Илюша собирает их касанием пешком и на «Ладе». В HUD — строка «Собери монеты: N/35» и счётчик; продавщица продаёт батон только при ≥ 35 ₽, иначе «Не хватает: ещё N ₽». Сбитый дрон (PUNCH-01) рассыпается 5 монетами. Решение владельца 29.10 (идея монет *Hit & Run*, без ассетов; перекрывает стартовые деньги канона).

**Файлы.** `game/mission/mission_director.gd`, `game/mission/coin_lines.gd`, `game/mission/quest_flow.gd`, `game/world/coins.gd`, точки — `Layout.COIN_POINTS`/`COIN_GROUPS`, `game/ui/game_hud.gd`, `game/audio/sound_director.gd`, `tools/generate_audio.py` (`coin_pickup`), `tests/coins_test.gd`.

**Интерфейсы.** C5а/C6а в `docs/workflow/README.md`: `START_MONEY` 0, `MissionDirector.add_money(n)`, сигнал `money_changed(money, delta)`, `money_missing()`, `objective()["coins_task"]`; поля HUD `money`, `money_goal`, `coins_task`. `Coins.spawn_burst(at, count)` — выброс монет (в полёте не подбираются, гаснут через 30 с). Респавн монеты не трогает; `reset()` возвращает все.

**Критерии.** 35 ₽ набираются по пути к киоску без обязательного крюка и пешком (ROUTE_WALK), и на машине (ROUTE_DRIVE), плюс соблазны в стороне. Монеты не на дороге кольца, не в полосах, не внутри коробок. При < 35 — отказ с подсказкой, при ≥ 35 — покупка.

**Проверка.** COINS, MISSION, QUEST01, DEMO_ACCEPTANCE, STEALTH, HIDE_CORE, HIDE_BOX, GREY01, STUCK, AUDIO.

**Сделано / открыто.**
- a0f8e35: 90 монет (подъезд, двор, выезд, улица A, тротуар и проезжая часть B, парковка, площадка, соблазны); диск с «₽» одним MultiMesh, вращение и свечение, подбор с магнитом; счётчик в HUD; звон с ростом высоты при подборе подряд.
- 3415c95: точки перенесены в Layout (C1). ae89355: выброс из дрона ниже; при ≥ 35 счётчик показывает «N ₽».
- Открыто: игра владельца.

# Иллюстрации достижений

Восемь оригинальных растровых минииллюстраций, созданных 31.10.2026 встроенным
`image_gen` по отдельному запросу для каждого файла. Исходники сгенерированы в
`CODEX_HOME/generated_images`, итоговые PNG скопированы сюда. Сторонние изображения,
лица персонажей чужих мультфильмов и изображения реальных людей не использовались.
PNG сохраняют прозрачность. Названия, условия и шутки выводит интерфейс игры.

Общий промпт: `Use case: illustration-story. Original square game achievement UI
illustration, genuinely transparent cutout. Humorous hand-painted gouache, warm
imperfect charcoal outlines, chunky readable shapes, restrained mustard yellow,
brick red, powder blue and ivory, matte paper texture. Centered compact scene,
generous transparent padding, readable at 96px. Gentle deadpan winter absurdity.
No text, letters, numbers, logos, watermark, border, existing cartoon references,
violence or injuries.`

| Файл | Сюжет отдельного запроса |
|---|---|
| `double_granny.png` | Two indignant original elderly neighbors in different winter coats and headscarves pop weightlessly above a soft snow cloud like a municipal choir hitting a high note. Shopping bags and slippers, annoyed but unharmed, no car impact shown. |
| `timber_delivery.png` | A squat battered generic beige Soviet-era compact sedan proudly delivers an absurdly oversized fallen birch trunk balanced across its roof; a snowy stump beside one wheel. No people, no car logos. |
| `standing_room.png` | A winter park bench with its seat broken into two halves; earnest winter boots stand in the gap as if converted into a standing-only amenity. No body, just boots, bench and snow. |
| `bread_zero.png` | An empty shabby open coin purse holds a majestic golden loaf on a tiny pillow of bread crumbs: a financial cushion made of bread. No currency symbols. |
| `good_boy_certificate.png` | A friendly scruffy honey-brown courtyard dog seriously inspects a mittened hand, with a paw on a blank certificate bearing a pawprint stamp; one small broken board hints at the applicant's record. Ordinary affectionate dog, no uniform. |
| `bread_box.png` | A walking cardboard bread box, with winter boots beneath and a golden loaf peeking from its open top, looks proudly like a complete human-sized retail package. No labels. |
| `cold_storage.png` | A golden loaf tucked into a snowdrift as if in a freezer; two wool-mittened hands and a tiny winter hat peek out beside it. Funny cozy refrigerated person, no harm. |
| `professional_ditcher.png` | Two oversized winter mittens belonging to one unseen person: one palm refuses a loaf while the other secretly accepts it behind the first. An awkward self-contradiction, only mittens and loaf. |

Устойчивые идентификаторы и игровые условия находятся в
`game/progression/achievements.gd`; картинки не определяют семантику события.

`drone_silence.svg` и `alarm_clock.svg` — две оригинальные векторные пиктограммы интегратора (31.10.2026): упавший дрон и разбудившая район машина. Нарисованы кодом в палитре существующей коллекции, сторонних ассетов нет. Коллекция содержит десять достижений; повторяемые условия определяет каталог в коде, ранее полученные ID сохранены.

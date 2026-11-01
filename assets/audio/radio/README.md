# Радиостанции города Н.

«Радио Н.» чередует **Cold Funk**, **Local Forecast - Elevator**,
**Monkeys Spinning Monkeys** и **Sneaky Snitch** Kevin MacLeod. Порядок задан
в `game/audio/radio_music.gd`. Оба эфира идут по времени мира, даже когда
игрок их не слушает; при настройке приёмник присоединяется к текущей позиции.
Станция «Классика» чередует первую часть «Лунной сонаты» Бетховена и
«Полёт валькирий» Вагнера. Третье положение выключает радио.
В меню и на паузе остаётся отдельная прежняя запись Шопена Op. 9 № 2.

| Файл | Композиция и конкретная запись | Источник и права |
|---|---|---|
| `cold_funk.ogg` | **Cold Funk**, Kevin MacLeod; ISRC USUAN1100499 | [Каталог автора](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100499), [исходный MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Cold%20Funk.mp3). Автор публикует композицию и запись по **CC BY 4.0**. Коммерческое использование и обработка разрешены с атрибуцией; отдельная покупка не требуется. Это не public domain. |
| `local_forecast_elevator.ogg` | **Local Forecast - Elevator**, Kevin MacLeod; ISRC USUAN1300012 | [Каталог автора](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300012), [исходный MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Local%20Forecast%20-%20Elevator.mp3). Композиция и запись — **CC BY 4.0**, с той же атрибуцией автора. |
| `monkeys_spinning_monkeys.ogg` | **Monkeys Spinning Monkeys**, Kevin MacLeod; ISRC USUAN1400011 | [Каталог автора](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400011), [исходный MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Monkeys%20Spinning%20Monkeys.mp3). Композиция и запись — **CC BY 4.0**, с той же атрибуцией автора. |
| `sneaky_snitch.ogg` | **Sneaky Snitch**, Kevin MacLeod; ISRC USUAN1100772 | [Каталог автора](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100772), [исходный MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Sneaky%20Snitch.mp3). Композиция и запись — **CC BY 4.0**, с той же атрибуцией автора. |
| `beethoven_moonlight_1.ogg` | Ludwig van Beethoven, Piano Sonata № 14, Op. 27 № 2, I. Adagio sostenuto; **Paul Pitman**, Musopen | [Точная запись](https://commons.wikimedia.org/wiki/File:Ludwig_van_Beethoven_-_sonata_no._14_in_c_sharp_minor_%27moonlight%27,_op._27_no._2_-_i._adagio_sostenuto.ogg). Композиция — public domain; запись предоставлена Musopen как **PD-author** (разрешение VRT 2008012110017088). Страница цитирует разрешение на переработку и коммерческие производные, с просьбой указать Musopen. PDM/PD не выдаются здесь за точную CC0-лицензию. |
| `ride_of_the_valkyries.ogg` | Richard Wagner, **Ride of the Valkyries**; дирижёр **Philip Milman**, проект **Lud and Schlatts Musical Emporium**, 2022; финансирование Ludwig и Schlatt | [Первичная публикация и CC BY 3.0](https://www.youtube.com/watch?v=uNkRW_9pHRQ), [каталог автора](https://pmmusic.pro/downloads/), [WAV-мастер](https://pmmusic.pro/wp-content/uploads/2023/09/Ride-of-the-Valkyries-PM-Music.wav), [точная запись на Commons](https://commons.wikimedia.org/wiki/File:Ride_of_the_Valkyries.ogg). Композиция — public domain; конкретная современная запись — **[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)**. Сохранена вся опубликованная автором короткая версия; это не полная оперная сцена. Перекодирование, адаптация громкости и короткие фейды по краям; темп сохранён. |
| `chopin_nocturne_1.ogg` | Frédéric Chopin, Nocturne Op. 9 № 1; **Olga Gurevich**, Musopen / Set Chopin Free | [Точный FLAC](https://commons.wikimedia.org/wiki/File:Chopin_-_Nocturne_No._1_in_B-flat_minor,_Op._9_No._1_(Olga_Gurevich).flac), [публикация кампании](https://www.kickstarter.com/projects/Musopen/set-chopin-free/posts/1193714). Композиция — public domain; фонограмма опубликована с **PD-author Musopen**, как и остальные записи кампании Set Chopin Free. Это исполнение Olga Gurevich, а не Frank Lévy. |
| `radio_tune.wav` | Короткая ручная настройка: шум эфира, проход частоты и затихание | Собственный детерминированный синтез `tools/prepare_radio_audio.py`; чужие передачи, голоса или фонограммы не использованы. |

Обязательная атрибуция конкретной записи, опубликованная автором:

> "Cold Funk", "Local Forecast - Elevator", "Monkeys Spinning Monkeys", "Sneaky Snitch"
> Kevin MacLeod (incompetech.com)
> Licensed under Creative Commons: By Attribution 4.0 License
> http://creativecommons.org/licenses/by/4.0/

В игре атрибуция также доступна в настройках. Изменения: перекодирование в
стерео Ogg Vorbis, 48 кГц, адаптация громкости без компрессии динамики, короткие
фейды только на краях. Темп и высота нот не менялись. Сжатый исходник Beethoven
был декодирован перед обработкой; новые FLAC/MP3-мастера в Git не включены.

«Полёт валькирий»: Philip Milman (https://pmmusic.pro/), Lud and Schlatts Musical
Emporium; funded by Ludwig and Schlatt. CC BY 3.0, ссылка выше. Условия записи
подтверждены описанием первичной публикации, а не только возрастом композиции.
Ноктюрн Op. 9 № 1 сохранён как прежний ассет, в текущий эфир не входит.

[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) разрешает распространение
и переработку, включая коммерческое использование. При распространении сохраняются
авторство, ссылки на источник и лицензию, отметка об обработке. Дополнительные
правовые или технические ограничения на эти фонограммы не накладываются.

Генератор проверяет SHA-256 исходных файлов и отсутствие клиппинга после
декодирования результата. Точные исходные и итоговые хэши, громкость и длительность
— `builds/checks/RADIO-01/asset-audio.json`. Первичные сведения Commons сохранены
при проверке во временной папке; их ссылки приведены выше.

Для трёх добавленных записей первичные страницы, каталог автора, MP3 и SHA-256 —
в `builds/checks/RADIO-01/playlist/`; подготовка использует существующий
`tools/prepare_radio_audio.py`. Итоговые измерения — `prepared-audio.json` в той же
папке. У Local Forecast пик ограничил усиление: средний уровень ниже Cold Funk,
динамика сохранена. Эти проверки подтверждают декодирование и отсутствие клиппинга;
художественное прослушивание и баланс в игре остаются за владельцем.

Для RADIO-03 WAV-мастер, первичная лицензия и страницы источников сохранены в
`builds/checks/RADIO-03/valkyries/`; измерения результата — `prepared-audio.json`.
Подготовка: `tools/prepare_radio_audio.py <masters> --tracks ride_of_the_valkyries
--skip-tuning --report builds/checks/RADIO-03/valkyries/prepared-audio.json`.

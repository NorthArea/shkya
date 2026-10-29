# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Звуки демо «За хлебом» (POLISH-01): синтез без чужих записей, только стандартная библиотека.

Запуск из корня репозитория: uv run tools/generate_audio.py
Пишет WAV 44,1 кГц моно в assets/audio/. Генерация детерминирована (фиксированный seed).
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"


def samples(seconds: float) -> int:
    return max(1, round(seconds * RATE))


def lowpass(signal: list[float], cutoff: float, stages: int = 1) -> list[float]:
    """Однополюсный фильтр нижних частот; stages — сколько раз подряд (крутизна 6 дБ/окт на каждый)."""
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out = signal
    for _ in range(stages):
        nxt, y = [], 0.0
        for x in out:
            y += alpha * (x - y)
            nxt.append(y)
        out = nxt
    return out


def highpass(signal: list[float], cutoff: float) -> list[float]:
    low = lowpass(signal, cutoff)
    return [x - l for x, l in zip(signal, low)]


def normalize(signal: list[float], peak: float = 0.8) -> list[float]:
    top = max(abs(x) for x in signal) or 1.0
    return [x * peak / top for x in signal]


def write(name: str, signal: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767)) for x in signal))
    print(f"AUDIO: {path.relative_to(ROOT)} {len(signal) / RATE:.2f} s")


def loop_crossfade(signal: list[float], fade_seconds: float) -> list[float]:
    """Сшить конец с началом, чтобы цикл не щёлкал."""
    n = samples(fade_seconds)
    body = signal[:-n]
    tail = signal[-n:]
    for i in range(n):
        w = i / n
        body[i] = body[i] * w + tail[i] * (1.0 - w)
    return body


def footstep(rng: random.Random) -> list[float]:
    """Хруст снега: шумовой всплеск с зернистыми щелчками, 0,16 с."""
    n = samples(0.16)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    noise = highpass(lowpass(noise, rng.uniform(2600, 3600)), 300)
    out = []
    for i, x in enumerate(noise):
        t = i / RATE
        env = (1 - math.exp(-t / 0.006)) * math.exp(-t / 0.045)
        grain = 1.0 + (2.5 if rng.random() < 0.012 else 0.0)
        out.append(x * env * grain)
    return normalize(out, 0.7)


def engine_loop() -> list[float]:
    """Холостой ход «Жигулей»: 4-тактный пульс 25 Гц с гармониками и шумом, 2 с, ровно целое число циклов.

    Генерируется 2,1 с: последние 0,1 с вшиваются в начало (фильтр стартует с нуля, без сшивки стык щёлкал)."""
    rng = random.Random(7)
    n = samples(2.1)
    base = 25.0
    out = []
    for i in range(n):
        t = i / RATE
        phase = 2 * math.pi * base * t
        pulse = sum(math.sin(k * phase + k * 0.7) / k ** 1.2 for k in range(1, 9))
        out.append(pulse + rng.uniform(-0.35, 0.35))
    out = lowpass(out, 900)
    return normalize(loop_crossfade(out, 0.1), 0.6)


def slush_loop() -> list[float]:
    """Шипение мокрой каши под колёсами при заносе, цикл 1,5 с."""
    rng = random.Random(11)
    n = samples(1.7)
    noise = highpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 2200), 400)
    out = [x * (0.8 + 0.2 * math.sin(2 * math.pi * 3.0 * i / RATE)) for i, x in enumerate(noise)]
    return normalize(loop_crossfade(out, 0.2), 0.6)


def door(close: bool) -> list[float]:
    """Дверь: глухой удар и металлический щелчок замка."""
    rng = random.Random(3 if close else 5)
    n = samples(0.45)
    out = []
    for i in range(n):
        t = i / RATE
        thump = math.sin(2 * math.pi * (70 if close else 95) * t) * math.exp(-t / (0.09 if close else 0.05))
        click_t = t - (0.02 if close else 0.0)
        click = rng.uniform(-1, 1) * math.exp(-max(click_t, 0) / 0.008) * (1 if click_t >= 0 else 0)
        out.append(thump * (1.0 if close else 0.5) + click * 0.35)
    return normalize(out, 0.75)


def ui_click() -> list[float]:
    n = samples(0.06)
    return normalize([math.sin(2 * math.pi * 1800 * i / RATE) * math.exp(-(i / RATE) / 0.012) for i in range(n)], 0.5)


def chime(notes: list[float], spacing: float, length: float) -> list[float]:
    n = samples(spacing * (len(notes) - 1) + length)
    out = [0.0] * n
    for k, freq in enumerate(notes):
        start = samples(spacing * k)
        for i in range(samples(length)):
            if start + i >= n:
                break
            t = i / RATE
            env = (1 - math.exp(-t / 0.004)) * math.exp(-t / (length * 0.35))
            out[start + i] += (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(4 * math.pi * freq * t)) * env
    return normalize(out, 0.6)


def yard_ambience() -> list[float]:
    """Двор зимним вечером: ветер, далёкий гул города, редкий далёкий сигнал. Цикл 10 с."""
    rng = random.Random(21)
    n = samples(11.0)
    # Ветер и гул — шум через четыре однополюсных фильтра (24 дБ/окт). С одним фильтром (6 дБ/окт)
    # оставалось шипение выше 2 кГц всего на 11 дБ тише фона — владелец слышал его постоянно (28.10).
    wind = lowpass([rng.uniform(-1, 1) for _ in range(n)], 350, stages=4)
    gusts = lowpass([rng.uniform(-1, 1) for _ in range(n)], 0.4)
    hum = lowpass([rng.uniform(-1, 1) for _ in range(n)], 120, stages=2)
    out = []
    for i in range(n):
        t = i / RATE
        g = 0.6 + 2.5 * abs(gusts[i])
        horn = 0.0
        if 6.2 < t < 6.7:
            horn = 0.08 * math.sin(2 * math.pi * 410 * t) * math.sin(math.pi * (t - 6.2) / 0.5)
        out.append(wind[i] * g * 4.0 + hum[i] * 6.0 + horn)
    return normalize(loop_crossfade(out, 1.0), 0.45)


def to_rms(signal: list[float], rms_db: float, peak: float = 0.95) -> list[float]:
    """Выставить среднеквадратичную громкость (дБ полной шкалы), не выходя за peak."""
    rms = math.sqrt(sum(x * x for x in signal) / len(signal)) or 1.0
    gain = 10 ** (rms_db / 20) / rms
    top = max(abs(x) for x in signal) * gain
    if top > peak:
        gain *= peak / top
    return [x * gain for x in signal]


def resonator(signal: list[float], freq: float, bandwidth: float) -> list[float]:
    """Двухполюсный резонатор (форманта гласной)."""
    r = math.exp(-math.pi * bandwidth / RATE)
    c1 = 2 * r * math.cos(2 * math.pi * freq / RATE)
    c2 = -r * r
    gain = 1 - r
    out, y1, y2 = [], 0.0, 0.0
    for x in signal:
        y = gain * x + c1 * y1 + c2 * y2
        out.append(y)
        y2, y1 = y1, y
    return out


# Форманты гласных (F1, F2), Гц: а, о, у, э, и, ы.
VOWELS = [(750, 1200), (500, 900), (350, 700), (550, 1700), (300, 2200), (380, 1500)]


def voice(seed: int, pitch: float, seconds: float, rate: float, wobble: float) -> list[float]:
    """«Бормотание» персонажа (POLISH-02): короткие слоги-гласные на импульсах голосовой щели.

    pitch — основной тон, Гц; rate — слогов в секунду; wobble — разброс высоты между слогами (доля).
    Не речь и не слова: только ритм и тембр голоса под печать реплики."""
    rng = random.Random(seed)
    n = samples(seconds)
    out = [0.0] * n
    t = 0.0
    while t < seconds - 0.08:
        length = rng.uniform(0.6, 1.0) / rate
        start = samples(t)
        f0 = pitch * (1 + rng.uniform(-wobble, wobble))
        f1, f2 = rng.choice(VOWELS)
        count = samples(length)
        source, phase = [], 0.0
        for i in range(count):
            u = i / count
            freq = f0 * (1.04 - 0.08 * u)  # слог чуть «падает» к концу
            phase += freq / RATE
            if phase >= 1.0:
                phase -= 1.0
            pulse = (1.0 - 2.0 * phase) + 0.08 * rng.uniform(-1, 1)  # пила + немного дыхания
            env = math.sin(math.pi * u) ** 0.7
            source.append(pulse * env)
        syllable = [a + 0.6 * b for a, b in zip(resonator(source, f1, 90), resonator(source, f2, 130))]
        for i, x in enumerate(syllable):
            if start + i < n:
                out[start + i] += x
        t += length + rng.uniform(0.02, 0.06)
    out = lowpass(out, 3500)
    fade = samples(0.02)
    for i in range(fade):
        out[-1 - i] *= i / fade
    return to_rms(out, -17.0)


def radio_mumble(seed: int, seconds: float) -> list[float]:
    """Радио в «Жигулях» (EXT-01, этап 2): тот же голос-бормотание диктора, но через узкую полосу
    приёмника (≈400…2500 Гц) с шорохом эфира и лёгким дрожанием громкости. Не речь и не слова."""
    rng = random.Random(seed)
    speech = voice(seed, 112.0, seconds, 6.0, 0.05)
    # Узкая полоса: верх срезан дважды, низ один раз — «коробочный» тембр динамика.
    narrow = highpass(lowpass(speech, 2500, stages=2), 400)
    n = len(narrow)
    hiss = highpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 4000), 1200)
    flutter = lowpass([rng.uniform(-1, 1) for _ in range(n)], 1.5)
    out = []
    for i in range(n):
        t = i / RATE
        crackle = 1.0 + (1.8 if rng.random() < 0.0004 else 0.0)
        gain = 0.75 + 1.2 * abs(flutter[i])
        out.append(narrow[i] * gain * crackle + hiss[i] * 0.05)
    fade = samples(0.15)
    for i in range(fade):
        out[i] *= i / fade
        out[-1 - i] *= i / fade
    return to_rms(out, -21.0)


def trolley_hum_loop() -> list[float]:
    """Троллейбус (ARENA-01): тихий гул тягового двигателя и преобразователя — 100 Гц с гармониками,
    призвук 400 Гц и мягкий шум, 2 с ровно целым числом периодов. Генерируется 2,1 с, хвост вшивается в начало."""
    rng = random.Random(61)
    n = samples(2.1)
    out = []
    for i in range(n):
        t = i / RATE
        hum = sum(math.sin(2 * math.pi * 100.0 * k * t + k * 0.4) / k ** 1.5 for k in range(1, 6))
        whine = 0.12 * math.sin(2 * math.pi * 400.0 * t) * (0.8 + 0.2 * math.sin(2 * math.pi * 0.5 * t))
        out.append(hum + whine + rng.uniform(-0.25, 0.25))
    out = lowpass(out, 1200, stages=2)
    return normalize(loop_crossfade(out, 0.1), 0.5)


def trolley_doors(seed: int) -> list[float]:
    """Двери троллейбуса (ARENA-01): пневматический выдох и глухой удар створок — door() с шипением впереди, 0,9 с."""
    rng = random.Random(seed)
    hiss_n = samples(0.45)
    hiss = highpass(lowpass([rng.uniform(-1, 1) for _ in range(hiss_n)], 3000), 600)
    hiss = [x * math.sin(math.pi * i / hiss_n) ** 0.5 * 0.5 for i, x in enumerate(hiss)]
    thump = door(True)
    out = hiss + [0.0] * (samples(0.9) - hiss_n)
    start = samples(0.35)
    for i, x in enumerate(thump):
        if start + i < len(out):
            out[start + i] += x * 0.8
    return normalize(out, 0.7)


# --- CITY-01 (A): фон живого города и живность. Каждая функция детерминирована (свой фиксированный seed). ---


def wind_gust_loop() -> list[float]:
    """Ветер с порывами: глухой шум ниже 450 Гц, порывы раз в 3–5 с (медленная огибающая), на пике порыва —
    тихое «завывание» узкой полосой у 600–750 Гц. Цикл 12 с; 13 с генерации, хвост 1 с вшивается в начало."""
    rng = random.Random(71)
    n = samples(13.0)
    base = lowpass([rng.uniform(-1, 1) for _ in range(n)], 450, stages=4)
    howl_src = [rng.uniform(-1, 1) for _ in range(n)]
    howl = resonator(resonator(howl_src, 680, 60), 680, 60)
    # Огибающая порывов: сумма двух медленных синусов с фазами от seed, только положительная часть.
    p1, p2 = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
    out = []
    for i in range(n):
        t = i / RATE
        g = 0.55 * math.sin(2 * math.pi * t / 4.0 + p1) + 0.45 * math.sin(2 * math.pi * t / 6.5 + p2)
        gust = max(0.0, g) ** 1.5
        out.append(base[i] * (0.35 + 1.4 * gust) * 6.0 + howl[i] * gust * 0.25)
    out = highpass(out, 60)
    return to_rms(loop_crossfade(out, 1.0), -24.0)


def distant_traffic_loop() -> list[float]:
    """Далёкий трафик за домами: ровный низкий гул ниже 160 Гц и три далёких «проезда» — полоса шума до 700 Гц,
    нарастает и спадает за 3–4 с, с тихим шинным тоном, чуть падающим (Доплер). Цикл 14 с."""
    rng = random.Random(73)
    n = samples(15.0)
    rumble = lowpass([rng.uniform(-1, 1) for _ in range(n)], 160, stages=2)
    hiss = highpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 700, stages=2), 120)
    passes = [(1.5, 3.5, 92.0), (6.0, 4.0, 84.0), (10.2, 3.2, 98.0)]   # начало, длительность, тон шин, Гц
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        swell, tone = 0.0, 0.0
        for start, length, freq in passes:
            u = (t - start) / length
            if 0.0 < u < 1.0:
                env = math.sin(math.pi * u) ** 2
                swell += env
                tone += env * math.sin(2 * math.pi * freq * (1.03 - 0.06 * u) * t)
        out.append(rumble[i] * 5.0 + hiss[i] * swell * 1.6 + tone * 0.05)
    return to_rms(loop_crossfade(out, 1.0), -26.0)


def crow_caw(seed: int, count: int) -> list[float]:
    """Серая ворона: count хриплых «кар» по 0,22–0,3 с — пила 480…560 Гц с падением тона, шероховатость шумом,
    носовые форманты 1250 и 2300 Гц."""
    rng = random.Random(seed)
    gap = 0.14
    out: list[float] = []
    for k in range(count):
        length = rng.uniform(0.22, 0.30)
        f0 = rng.uniform(480, 560)
        m = samples(length)
        source, phase = [], 0.0
        for i in range(m):
            u = i / m
            freq = f0 * (1.05 - 0.22 * u)
            phase += freq * (1 + 0.05 * rng.uniform(-1, 1)) / RATE
            phase -= math.floor(phase)
            env = min(1.0, u / 0.08) * (1.0 - max(0.0, u - 0.6) / 0.4)
            source.append(((1.0 - 2.0 * phase) * 0.8 + rng.uniform(-1, 1) * 0.45) * env)
        caw = [a + 0.7 * b for a, b in zip(resonator(source, 1250, 220), resonator(source, 2300, 300))]
        out += caw + [0.0] * samples(gap if k < count - 1 else 0.05)
    out = highpass(out, 250)
    return to_rms(out, -18.0)


def dog_bark(seed: int) -> list[float]:
    """Дворняга: «гав-гав» — два коротких лая по 0,13–0,16 с, тон 330→230 Гц, резкая атака, форманты 700 и 1500 Гц."""
    rng = random.Random(seed)
    out: list[float] = []
    for k in range(2):
        length = rng.uniform(0.13, 0.16)
        f0 = rng.uniform(320, 360) * (1.0 if k == 0 else 0.93)
        m = samples(length)
        source, phase = [], 0.0
        for i in range(m):
            u = i / m
            freq = f0 * (1.0 - 0.3 * u)
            phase += freq / RATE
            phase -= math.floor(phase)
            env = min(1.0, u / 0.04) * math.exp(-u * 3.0)
            source.append(((1.0 - 2.0 * phase) + rng.uniform(-1, 1) * 0.6) * env)
        bark = [a + 0.6 * b for a, b in zip(resonator(source, 700, 180), resonator(source, 1500, 260))]
        out += bark + [0.0] * samples(0.22 if k == 0 else 0.08)
    out = highpass(lowpass(out, 4000), 150)
    return to_rms(out, -18.0)


def door_slam() -> list[float]:
    """Железная дверь подъезда: глухой удар 55 Гц, звон полотна (негармонические 310, 517, 845 Гц), щелчок замка
    и короткое эхо подъезда (две задержки 70 и 140 мс). 1,2 с."""
    rng = random.Random(79)
    n = samples(1.2)
    dry = []
    for i in range(n):
        t = i / RATE
        thump = math.sin(2 * math.pi * 55 * t) * math.exp(-t / 0.12)
        ring = sum(a * math.sin(2 * math.pi * f * t) for f, a in ((310, 0.35), (517, 0.25), (845, 0.15))) * math.exp(-t / 0.28)
        latch_t = t - 0.03
        latch = rng.uniform(-1, 1) * math.exp(-latch_t / 0.006) if latch_t >= 0 else 0.0
        dry.append(thump + ring * 0.6 + latch * 0.3)
    out = list(dry)
    for delay, gain in ((0.07, 0.35), (0.14, 0.18)):
        d = samples(delay)
        for i in range(d, n):
            out[i] += dry[i - d] * gain
    out = lowpass(out, 3000)
    fade = samples(0.1)
    for i in range(fade):
        out[-1 - i] *= i / fade
    return to_rms(out, -18.0)


def car_horn_short() -> list[float]:
    """Короткий сигнал легковушки: два тона 410 и 515 Гц (как два рожка), мягкий прямоугольник через ФНЧ, 0,35 с."""
    n = samples(0.35)
    out = []
    for i in range(n):
        t = i / RATE
        tone = 0.0
        for f in (410.0, 515.0):
            tone += sum(math.sin(2 * math.pi * f * k * t) / k for k in (1, 3, 5))
        env = min(1.0, t / 0.012) * min(1.0, (0.35 - t) / 0.04)
        out.append(tone * env)
    out = lowpass(out, 2200, stages=2)
    return to_rms(out, -16.0)


def window_music_loop() -> list[float]:
    """Музыка из форточки во дворе: собственный короткий мотив (ля минор, 96 уд/мин, 4 такта), мягкий треугольник
    и бас, приглушённый «через стекло» (полоса 180…900 Гц). Цикл ровно 4 такта = 10 с; ноты гаснут до шва."""
    beat = 60.0 / 96.0
    total = beat * 16
    n = samples(total)
    out = [0.0] * n
    # Мелодия: (доля начала, длительность в долях, частота). Мотив свой: A4 C5 E5 D5 | C5 A4 G4 A4 | ...
    a4, b4, c5, d5, e5, g4, f4 = 440.0, 493.9, 523.3, 587.3, 659.3, 392.0, 349.2
    melody = [(0, 1, a4), (1, 1, c5), (2, 1, e5), (3, 1, d5), (4, 1, c5), (5, 1, a4), (6, 1.5, g4), (7.5, 0.5, a4),
              (8, 1, f4), (9, 1, a4), (10, 1, c5), (11, 1, b4), (12, 1, a4), (13, 1, g4), (14, 1.6, a4)]
    bass = [(0, 4, 110.0), (4, 4, 98.0), (8, 4, 87.3), (12, 4, 110.0)]

    def add(notes: list, gain: float, decay: float) -> None:
        for start_beat, length_beats, freq in notes:
            start = samples(start_beat * beat)
            m = min(samples(length_beats * beat), n - start)
            for i in range(m):
                t = i / RATE
                u = i / m
                tri = 2.0 * abs(2.0 * ((freq * t) % 1.0) - 1.0) - 1.0
                env = min(1.0, t / 0.01) * math.exp(-t / decay) * min(1.0, (1.0 - u) / 0.1)
                out[start + i] += tri * env * gain

    add(melody, 0.5, 0.5)
    add(bass, 0.35, 1.2)
    muffled = highpass(lowpass(out, 900, stages=2), 180)
    return to_rms(muffled, -24.0)


def barrel_roll_loop() -> list[float]:
    """Бочка катится (EXT-02 E): пустая ржавая бочка — гулкий рокот корпуса (резонансы 95 и 160 Гц на шуме ниже
    250 Гц), шов стучит о землю дважды за оборот (металлические щелчки 430, 700, 1150 Гц), внутри дребезжит мусор
    (частые мелкие тики через резонанс 2,3 кГц). Цикл 2 с, ровно четыре удара шва; громкость задаёт игра по скорости."""
    rng = random.Random(101)
    cycle = 2.0
    fade = 0.1
    n = samples(cycle + fade)
    noise = lowpass([rng.uniform(-1, 1) for _ in range(n)], 250, stages=2)
    body = resonator(noise, 95, 18)
    body2 = resonator(noise, 160, 25)
    out = [0.0] * n
    for i in range(n):
        t = i / RATE
        swell = 0.75 + 0.25 * math.sin(2 * math.pi * t / 0.5)
        out[i] = (body[i] * 1.0 + body2[i] * 0.6) * swell
    out = normalize(out, 0.5)

    def strike(at: float, gain: float, decay: float, freqs: tuple) -> None:
        start = samples(at)
        for j in range(samples(decay * 6)):
            if start + j >= n:
                break
            t = j / RATE
            env = math.exp(-t / decay)
            ring = sum(a * math.sin(2 * math.pi * f * t) for f, a in freqs)
            out[start + j] += gain * env * (ring + rng.uniform(-1, 1) * 0.4 * math.exp(-t / 0.004))

    seam = ((430, 0.5), (700, 0.35), (1150, 0.2))
    for k in range(int((cycle + fade) / 0.5) + 1):
        strike(k * 0.5 + rng.uniform(-0.02, 0.02), 0.45, 0.035, seam)
    t = 0.0
    while t < cycle + fade:
        strike(t, rng.uniform(0.04, 0.12), 0.006, ((2300, 0.6), (3100, 0.3)))
        t += rng.uniform(0.02, 0.07)
    out = loop_crossfade(lowpass(out, 5000), fade)
    return to_rms(out, -20.0)


def barrel_bump() -> list[float]:
    """«БУМ» (EXT-02 E): бочка с разгона в стену — глухой удар 58→45 Гц, гулкий звон пустого корпуса (негармонические
    112, 176, 254, 347 Гц, долгий хвост), шлепок жести в начале. 1,3 с."""
    rng = random.Random(103)
    n = samples(1.3)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (45 + 13 * math.exp(-t / 0.08)) / RATE
        thump = math.sin(phase) * math.exp(-t / 0.18)
        ring = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t / d)
                   for f, a, d in ((112, 0.5, 0.55), (176, 0.35, 0.45), (254, 0.25, 0.35), (347, 0.15, 0.25)))
        slap = rng.uniform(-1, 1) * math.exp(-t / 0.012)
        out.append(thump * 1.0 + ring * 0.7 + slap * 0.35)
    out = lowpass(out, 3500)
    fade = samples(0.15)
    for i in range(fade):
        out[-1 - i] *= i / fade
    return to_rms(out, -16.0)


def phone_swipe() -> list[float]:
    """Свайп по экрану телефона (INTRO-01): касание — тихий щелчок 2,4 кГц, затем короткий «шурх» пальца — шум
    в полосе, которая скользит вверх 1,2 → 4 кГц, атака 20 мс, спад 60 мс; всего 0,22 с."""
    rng = random.Random(101)
    out, low, high = [], 0.0, 0.0
    for i in range(samples(0.22)):
        t = i / RATE
        freq = 1200.0 + 2800.0 * min(t / 0.18, 1.0)
        low += (1.0 - math.exp(-2.0 * math.pi * freq / RATE)) * (rng.uniform(-1, 1) - low)
        high += (1.0 - math.exp(-2.0 * math.pi * freq * 0.4 / RATE)) * (low - high)
        env = (1.0 - math.exp(-t / 0.02)) * math.exp(-t / 0.06)
        tick = 0.5 * math.sin(2.0 * math.pi * 2400.0 * t) * math.exp(-t / 0.004)
        out.append((low - high) * env * 6.0 + tick)
    return normalize(out, 0.5)


def coin_pickup() -> list[float]:
    """Монета (COINS-01): аркадный «дзынь» из двух нот — си 5-й октавы 0,055 с и ми 6-й с затуханием 0,3 с.
    Мягкий прямоугольник (нечётные гармоники 1, 3, 5 с убыванием) и короткий металлический призвук 3,1 кГц на атаке.
    Собственный синтез; высоту при подборе подряд меняет SoundDirector (pitch_scale)."""
    n = samples(0.36)
    out = [0.0] * n
    notes = [(987.8, 0.0, 0.055, 0.02), (1318.5, 0.055, 0.30, 0.09)]
    for freq, start, length, decay in notes:
        s0 = samples(start)
        for i in range(samples(length)):
            if s0 + i >= n:
                break
            t = i / RATE
            env = (1 - math.exp(-t / 0.002)) * math.exp(-t / decay)
            w = 2 * math.pi * freq * t
            tone = math.sin(w) + math.sin(3 * w) / 3.0 * 0.6 + math.sin(5 * w) / 5.0 * 0.35
            out[s0 + i] += tone * env
    for i in range(samples(0.03)):
        t = i / RATE
        out[i] += 0.25 * math.sin(2 * math.pi * 3100 * t) * math.exp(-t / 0.008)
    fade = samples(0.02)
    for i in range(fade):
        out[-1 - i] *= i / fade
    return to_rms(lowpass(out, 9000), -18.0)


def drone_buzz_loop() -> list[float]:
    """Мини-дрон (PUNCH-01): высокое жужжание четырёх винтов — пилообразные тона 196, 201, 206,5 и 212 Гц (каждый
    с гармониками до 2 кГц, чуть расстроены — биения «вжжж»), лёгкий шум воздуха выше 1,5 кГц, медленная волна
    громкости. Цикл 2 с: частоты кратны 0,5 Гц — ровное число периодов; хвост 0,1 с сшит с началом (шум и ФНЧ)."""
    rng = random.Random(131)
    seconds = 2.0
    fade = 0.1
    n = samples(seconds + fade)
    rotors = (196.0, 201.0, 206.5, 212.0)
    out = [0.0] * n
    for k, f in enumerate(rotors):
        for h in range(1, 10):
            amp = 1.0 / h
            ph = rng.uniform(0, 2 * math.pi)
            w = 2 * math.pi * f * h / RATE
            for i in range(n):
                out[i] += amp * math.sin(w * i + ph) * (0.8 + 0.2 * k / 3)
    air = highpass([rng.uniform(-1, 1) for _ in range(n)], 1500)
    for i in range(n):
        t = i / RATE
        swell = 0.85 + 0.15 * math.sin(2 * math.pi * t / seconds)   # одна волна за цикл — шов совпадает
        out[i] = out[i] * swell + air[i] * 0.6
    out = loop_crossfade(lowpass(out, 4200), fade)
    return to_rms(out, -20.0)


def punch_whoosh() -> list[float]:
    """Взмах рукой (PUNCH-01): «вжух» — шум в полосе, скользящей вниз 2,2 → 0,6 кГц, нарастание 60 мс, спад 0,18 с,
    всего 0,3 с; без удара — удар по дрону озвучивает drone_pop."""
    rng = random.Random(137)
    out, low, high = [], 0.0, 0.0
    for i in range(samples(0.3)):
        t = i / RATE
        freq = 2200.0 - 1600.0 * min(t / 0.22, 1.0)
        low += (1.0 - math.exp(-2.0 * math.pi * freq / RATE)) * (rng.uniform(-1, 1) - low)
        high += (1.0 - math.exp(-2.0 * math.pi * freq * 0.35 / RATE)) * (low - high)
        env = min(t / 0.06, 1.0) * math.exp(-max(t - 0.06, 0.0) / 0.07)
        out.append((low - high) * env)
    return to_rms(out, -20.0)


def drone_pop() -> list[float]:
    """Сбитый дрон (PUNCH-01): сухой пластиковый хлопок (шумовой щелчок 4 мс и короткий тон 900→300 Гц), треск
    рассыпающегося корпуса (8 мелких щелчков за 0,25 с через резонанс 2,8 кГц) и короткий электрический «пиу» —
    тон 1600→400 Гц, 0,15 с. Всего 0,6 с."""
    rng = random.Random(139)
    n = samples(0.6)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (300 + 600 * math.exp(-t / 0.02)) / RATE
        out[i] += math.sin(phase) * math.exp(-t / 0.035) * 0.9
        out[i] += rng.uniform(-1, 1) * math.exp(-t / 0.004) * 1.2
    clicks = [0.0] * n
    for k in range(8):
        start = samples(0.03 + k * 0.03 + rng.uniform(-0.01, 0.01))
        gain = rng.uniform(0.3, 0.7) * (1.0 - k / 10)
        for j in range(samples(0.012)):
            if start + j < n:
                clicks[start + j] += gain * rng.uniform(-1, 1) * math.exp(-j / RATE / 0.002)
    clicks = resonator(clicks, 2800, 900)
    clicks = normalize(clicks, 0.5)
    zap = 0.0
    for i in range(n):
        t = i / RATE - 0.05
        if 0.0 <= t < 0.15:
            zap += 2 * math.pi * (1600 - 1200 * t / 0.15) / RATE
            out[i] += 0.25 * (1.0 if math.sin(zap) > 0 else -1.0) * (1.0 - t / 0.15)
        out[i] += clicks[i]
    out = lowpass(out, 7000)
    fade = samples(0.08)
    for i in range(fade):
        out[-1 - i] *= i / fade
    return to_rms(out, -16.0)


def drone_beep() -> list[float]:
    """Дрон ГСУМ заметил Илюшу (PUNCH-02): служебный «бип-бип» — два коротких тона 1,76 кГц по 0,07 с с паузой 0,06 с,
    второй на кварту выше (2,35 кГц); мягкий прямоугольник (гармоники 1, 3, 5), атака 3 мс, спад 25 мс, всего 0,3 с.
    Собственный синтез."""
    n = samples(0.3)
    out = [0.0] * n
    for freq, start in ((1760.0, 0.02), (2349.3, 0.15)):
        s0 = samples(start)
        length = samples(0.07)
        for i in range(length):
            if s0 + i >= n:
                break
            t = i / RATE
            env = min(1.0, t / 0.003) * min(1.0, (length - i) / RATE / 0.025)
            w = 2 * math.pi * freq * t
            out[s0 + i] += (math.sin(w) + math.sin(3 * w) / 3.0 * 0.5 + math.sin(5 * w) / 5.0 * 0.3) * env
    return to_rms(lowpass(out, 7000), -20.0)


def knock_whoosh() -> list[float]:
    """Сбитый «Ладой» житель взлетает (KNOCK-01): комичный «вжу-ух» — шум в полосе, которая идёт вверх 0,5 → 1,6 кГц
    и снова вниз к 0,7 кГц, нарастание 0,12 с, мягкий спад; 0,55 с. Ни криков, ни удара — только воздух."""
    rng = random.Random(149)
    out, low, high = [], 0.0, 0.0
    n = samples(0.55)
    for i in range(n):
        t = i / RATE
        u = t / 0.55
        freq = 500.0 + 1100.0 * math.sin(math.pi * min(u / 0.8, 1.0)) ** 2 + 200.0 * u
        low += (1.0 - math.exp(-2.0 * math.pi * freq / RATE)) * (rng.uniform(-1, 1) - low)
        high += (1.0 - math.exp(-2.0 * math.pi * freq * 0.4 / RATE)) * (low - high)
        env = min(t / 0.12, 1.0) * (1.0 - u) ** 1.5
        out.append((low - high) * env)
    return to_rms(out, -20.0)


def knock_thud() -> list[float]:
    """Падение в снег (KNOCK-01): глухой мягкий «пуф» — низкий толчок 75 → 48 Гц (спад 0,09 с) и шорох снега: шум
    через фильтр 900 Гц со спадом 0,16 с, короткий хруст наста в начале. 0,5 с."""
    rng = random.Random(151)
    n = samples(0.5)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (48 + 27 * math.exp(-t / 0.05)) / RATE
        thump = math.sin(phase) * math.exp(-t / 0.09)
        hiss = rng.uniform(-1, 1) * min(t / 0.008, 1.0) * math.exp(-t / 0.16)
        crunch = rng.uniform(-1, 1) * math.exp(-t / 0.02)
        out.append(thump + hiss * 0.55 + crunch * 0.25)
    out = lowpass(out, 900, 2)
    fade = samples(0.1)
    for i in range(fade):
        out[-1 - i] *= i / fade
    return to_rms(out, -16.0)


def _fade_out(out: list[float], seconds: float) -> list[float]:
    fade = samples(seconds)
    for i in range(min(fade, len(out))):
        out[-1 - i] *= i / fade
    return out


def break_wood() -> list[float]:
    """Поломка деревянного (BREAK-01: качели, ограждение раскопки): сухой треск — три-четыре щелчка-излома с
    резонансами доски 380, 720, 1150 Гц (короткий спад), хруст волокон шумом и глухой стук доски о снег. 0,6 с."""
    rng = random.Random(161)
    n = samples(0.6)
    crack = [0.0] * n
    for at, gain in ((0.0, 1.0), (0.045, 0.7), (0.11, 0.5), (0.19, 0.35)):
        start = samples(at)
        for i in range(samples(0.03)):
            if start + i < n:
                crack[start + i] += rng.uniform(-1, 1) * gain * math.exp(-i / samples(0.006))
    body = [0.0] * n
    for f, bw, g in ((380, 60, 1.0), (720, 90, 0.7), (1150, 140, 0.45)):
        for i, y in enumerate(resonator(crack, f, bw)):
            body[i] += y * g * 6.0
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        fiber = rng.uniform(-1, 1) * math.exp(-t / 0.09) * 0.25
        thud_t = max(t - 0.28, 0.0)
        phase += 2 * math.pi * 70 / RATE
        thud = math.sin(phase) * math.exp(-thud_t / 0.06) * (0.5 if t >= 0.28 else 0.0)
        out.append(crack[i] * 0.5 + body[i] + fiber + thud)
    out = lowpass(out, 6000)
    return to_rms(_fade_out(out, 0.1), -18.0)


def break_metal() -> list[float]:
    """Поломка металлического (BREAK-01: урна, карусель): лязг и звон — удар шумом и негармонический звон тонкого листа
    и трубы 410, 1030, 1720, 2480, 3300 Гц с разным спадом, второй удар о землю через 0,2 с. 0,9 с."""
    rng = random.Random(163)
    n = samples(0.9)
    out = []
    partials = ((410, 0.6, 0.35), (1030, 0.45, 0.25), (1720, 0.35, 0.18), (2480, 0.25, 0.12), (3300, 0.15, 0.08))
    for i in range(n):
        t = i / RATE
        ring = sum(a * math.sin(2 * math.pi * f * t + f) * math.exp(-t / d) for f, a, d in partials)
        t2 = t - 0.2
        ring2 = 0.0
        if t2 > 0:
            ring2 = sum(a * math.sin(2 * math.pi * f * 1.06 * t2) * math.exp(-t2 / (d * 0.7)) for f, a, d in partials) * 0.5
        hit = rng.uniform(-1, 1) * (math.exp(-t / 0.01) + (0.6 * math.exp(-t2 / 0.01) if t2 > 0 else 0.0))
        out.append(ring + ring2 + hit * 0.6)
    out = lowpass(out, 8000)
    return to_rms(_fade_out(out, 0.15), -18.0)


def break_plastic() -> list[float]:
    """Поломка пластика и резины (BREAK-01: конусы, клумба-покрышка): хруст — частые сухие щелчки шума через
    полосу 1,2–4 кГц, гулкий «бум» пустого корпуса 160 Гц и шорох обломков. 0,45 с."""
    rng = random.Random(167)
    n = samples(0.45)
    clicks = [0.0] * n
    t = 0.0
    while t < 0.3:
        start = samples(t)
        gain = math.exp(-t / 0.12)
        for i in range(samples(0.004)):
            if start + i < n:
                clicks[start + i] += rng.uniform(-1, 1) * gain
        t += rng.uniform(0.008, 0.03)
    clicks = highpass(lowpass(clicks, 4000), 1200)
    out = []
    for i in range(n):
        tt = i / RATE
        boom = math.sin(2 * math.pi * 160 * tt) * math.exp(-tt / 0.05) * 0.5
        rustle = rng.uniform(-1, 1) * math.exp(-tt / 0.15) * 0.08
        out.append(clicks[i] * 2.5 + boom + rustle)
    return to_rms(_fade_out(out, 0.08), -18.0)


def car_alarm() -> list[float]:
    """Сигнализация припаркованной машины (BREAK-01, реакция на толчок «Ладой»): двухтональная сирена 880 / 660 Гц,
    смена тона каждые 0,3 с, звук пищалки (квадрат через фильтр 3 кГц), 6 с с мягким концом."""
    n = samples(6.0)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        freq = 880.0 if int(t / 0.3) % 2 == 0 else 660.0
        phase += 2 * math.pi * freq / RATE
        square = 1.0 if math.sin(phase) > 0 else -1.0
        out.append(square * 0.6 + math.sin(phase) * 0.4)
    out = lowpass(out, 3000, 2)
    for i in range(samples(0.01)):
        out[i] *= i / samples(0.01)
    return to_rms(_fade_out(out, 0.3), -22.0)


def bin_lid() -> list[float]:
    """Хлопок крышек мусорного контейнера (BREAK-01, реакция на толчок «Ладой»): два глухих удара жести 0 и 0,12 с —
    низкий толчок 90 Гц и звон крышки 240, 530, 910 Гц с коротким спадом. 0,6 с."""
    rng = random.Random(173)
    n = samples(0.6)
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for at, g in ((0.0, 1.0), (0.12, 0.7)):
            u = t - at
            if u < 0:
                continue
            s += g * (math.sin(2 * math.pi * 90 * u) * math.exp(-u / 0.06)
                      + sum(a * math.sin(2 * math.pi * f * u) * math.exp(-u / d) for f, a, d in ((240, 0.5, 0.12), (530, 0.35, 0.08), (910, 0.2, 0.05)))
                      + rng.uniform(-1, 1) * math.exp(-u / 0.008) * 0.4)
        out.append(s)
    out = lowpass(out, 5000)
    return to_rms(_fade_out(out, 0.1), -18.0)


def snow_drive_loop() -> list[float]:
    """Колёса в рыхлом снегу (DRIVE-02): глухое шуршание (шум ниже 1,4 кГц) с хрустом — частые зёрна-щелчки через
    резонанс 1,9 кГц — и низкий гул снега под днищем 70 Гц. Цикл 2 с; громкость и высоту задаёт игра по глубине и
    скорости."""
    rng = random.Random(211)
    cycle = 2.0
    fade = 0.15
    n = samples(cycle + fade)
    hiss = highpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 1400, stages=2), 120)
    grains = [0.0] * n
    i = 0
    while i < n:
        i += int(RATE * rng.uniform(0.004, 0.022))
        if i < n:
            grains[i] = rng.uniform(-1, 1) * rng.uniform(0.4, 1.0)
    crunch = resonator(grains, 1900, 900)
    rumble = resonator(lowpass([rng.uniform(-1, 1) for _ in range(n)], 200), 70, 30)
    hiss = normalize(hiss, 0.6)
    crunch = normalize(crunch, 0.7)
    rumble = normalize(rumble, 0.5)
    out = []
    for k in range(n):
        t = k / RATE
        swell = 0.8 + 0.2 * math.sin(2 * math.pi * t / 0.5)
        out.append((hiss[k] * 0.7 + crunch[k] * 0.6 + rumble[k] * 0.5) * swell)
    return to_rms(loop_crossfade(out, fade), -18.0)


def skid_squeak_loop() -> list[float]:
    """Скрип шин по укатанному снегу при заносе (DRIVE-02, «вкус» аркады): тон 820–1000 Гц с медленным плаванием
    и дрожанием сцепления 31 Гц, гармоники 2× и 3×, поверх — шорох. Цикл 1,5 с; громкость — по боковой скорости."""
    rng = random.Random(223)
    cycle = 1.5
    fade = 0.15
    n = samples(cycle + fade)
    drift = lowpass([rng.uniform(-1, 1) for _ in range(n)], 3, stages=2)
    drift = normalize(drift, 1.0)
    noise = highpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 4000), 900)
    noise = normalize(noise, 0.5)
    out = []
    phase = 0.0
    for k in range(n):
        t = k / RATE
        freq = 910.0 + 90.0 * drift[k]
        phase += 2 * math.pi * freq / RATE
        chatter = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * 31.0 * t + 1.3 * math.sin(2 * math.pi * 3.0 * t)))
        tone = math.sin(phase) + 0.35 * math.sin(2 * phase + 0.4) + 0.15 * math.sin(3 * phase + 1.1)
        out.append(tone * chatter * 0.7 + noise[k] * 0.3)
    out = lowpass(out, 5000)
    return to_rms(loop_crossfade(out, fade), -20.0)


def _impulses(n: int, starts: list[tuple[float, float]], length: float, decay: float, rng: random.Random) -> list[float]:
    """Шумовые щелчки: [(момент, громкость)], каждый length с со спадом decay с."""
    out = [0.0] * n
    for at, gain in starts:
        start = samples(at)
        for i in range(samples(length)):
            if start + i < n:
                out[start + i] += rng.uniform(-1, 1) * gain * math.exp(-i / samples(decay))
    return out


def domino_clack() -> list[float]:
    """Костяшка домино об стол (PEOPLE-03): сухой щелчок кости — резонансы 2,3 и 3,6 кГц со спадом 15 мс, глухой стук
    столешницы 170 Гц и короткий «дребезг» костяшки, легшей через 60 мс. 0,3 с."""
    rng = random.Random(211)
    n = samples(0.3)
    click = _impulses(n, [(0.0, 1.0), (0.06, 0.35)], 0.004, 0.0012, rng)
    tile = [a * 5.0 + b * 3.5 for a, b in zip(resonator(click, 2300, 300), resonator(click, 3600, 420))]
    out = []
    for i in range(n):
        t = i / RATE
        table = math.sin(2 * math.pi * 170 * t) * math.exp(-t / 0.035) * 0.6
        out.append(click[i] * 0.4 + tile[i] + table)
    return to_rms(_fade_out(highpass(out, 90), 0.05), -22.0)


def broom_swish() -> list[float]:
    """Взмах метлы-голика по снегу (PEOPLE-03): шорох — шум в полосе 1,4–6 кГц, нарастание 70 мс, спад 0,22 с, редкий
    хруст прутьев (сухие щелчки). 0,42 с."""
    rng = random.Random(223)
    n = samples(0.42)
    noise = highpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 6000), 1400)
    twigs = _impulses(n, [(rng.uniform(0.04, 0.3), rng.uniform(0.3, 0.7)) for _ in range(9)], 0.003, 0.0008, rng)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.07) * math.exp(-max(t - 0.07, 0.0) / 0.22)
        out.append(noise[i] * env * 2.0 + twigs[i] * env * 0.5)
    return to_rms(_fade_out(out, 0.06), -24.0)


def sled_creak() -> list[float]:
    """Санки по морозному снегу (PEOPLE-03): скрип полозьев — шум «рывками» (трение с проскальзыванием 55 Гц) через
    резонансы 1,1 и 2,4 кГц, плавное нарастание и спад. 0,5 с; тот же скрип — у ската ледяной горки."""
    rng = random.Random(227)
    n = samples(0.5)
    source = []
    for i in range(n):
        t = i / RATE
        stick = (0.5 + 0.5 * math.sin(2 * math.pi * (55 + 8 * math.sin(2 * math.pi * 3 * t)) * t)) ** 6
        source.append(rng.uniform(-1, 1) * stick)
    out = [a * 4.0 + b * 3.0 for a, b in zip(resonator(source, 1100, 160), resonator(source, 2400, 260))]
    for i in range(n):
        t = i / RATE
        out[i] *= math.sin(math.pi * min(1.0, t / 0.5)) ** 0.7
    return to_rms(_fade_out(highpass(out, 400), 0.05), -24.0)


def hockey_stick() -> list[float]:
    """Клюшка по шайбе (PEOPLE-03): деревянный «клац» — щелчок 1,5 мс, резонансы крюка 520 и 1350 Гц со спадом 30 мс
    и звонкий «тик» шайбы по льду 4,2 кГц. 0,25 с; ниже по высоте — шайба в борт."""
    rng = random.Random(229)
    n = samples(0.25)
    click = _impulses(n, [(0.0, 1.0)], 0.0015, 0.0005, rng)
    wood = [a * 6.0 + b * 4.0 for a, b in zip(resonator(click, 520, 70), resonator(click, 1350, 150))]
    out = []
    for i in range(n):
        t = i / RATE
        tick = math.sin(2 * math.pi * 4200 * t) * math.exp(-t / 0.012) * 0.15
        out.append(click[i] * 0.5 + wood[i] + tick)
    return to_rms(_fade_out(out, 0.05), -20.0)


def pigeon_coo(seed: int) -> list[float]:
    """Воркование голубя (PEOPLE-03): «гу-урр-гу» — три слога, тон 300–380 Гц с подъёмом и спадом, горловое дрожание
    28 Гц, мягкие гармоники через ФНЧ 1,5 кГц. ≈ 1,2 с."""
    rng = random.Random(seed)
    out: list[float] = []
    for k, (length, f0, rise) in enumerate(((0.22, 330, 0.12), (0.5, 300, 0.25), (0.26, 345, -0.1))):
        f0 *= rng.uniform(0.95, 1.05)
        m = samples(length)
        phase = 0.0
        for i in range(m):
            u = i / m
            freq = f0 * (1.0 + rise * math.sin(math.pi * u))
            phase += freq / RATE
            env = math.sin(math.pi * u) ** 1.5
            trem = 0.7 + 0.3 * math.sin(2 * math.pi * 28 * i / RATE)
            tone = math.sin(2 * math.pi * phase) + 0.35 * math.sin(4 * math.pi * phase) + 0.15 * math.sin(6 * math.pi * phase)
            out.append(tone * env * trem + rng.uniform(-1, 1) * 0.03 * env)
        out += [0.0] * samples(0.05 if k < 2 else 0.08)
    return to_rms(lowpass(out, 1500), -24.0)


def wings_flap(seed: int) -> list[float]:
    """Стайка взлетает (PEOPLE-03): хлопанье крыльев трёх птиц — шумовые взмахи 35 мс в полосе 0,3–2,5 кГц, по 9–11 у
    каждой с частотой 9–12 Гц и разбросом, общий спад. 1,1 с."""
    rng = random.Random(seed)
    n = samples(1.1)
    starts = []
    for _ in range(3):
        t = rng.uniform(0.0, 0.08)
        rate = rng.uniform(9.0, 12.0)
        for _k in range(rng.randint(9, 11)):
            starts.append((t, math.exp(-t / 0.55)))
            t += 1.0 / rate * rng.uniform(0.85, 1.15)
    out = [0.0] * n
    for at, gain in starts:
        start = samples(at)
        m = samples(0.035)
        for i in range(m):
            if start + i < n:
                u = i / m
                out[start + i] += rng.uniform(-1, 1) * gain * math.sin(math.pi * u) ** 2
    out = highpass(lowpass(out, 2500, 2), 300)
    return to_rms(_fade_out(out, 0.1), -20.0)


def main() -> None:
    rng = random.Random(1)
    for k in range(1, 5):
        write(f"step_snow_{k}.wav", footstep(rng))
    write("engine_idle_loop.wav", engine_loop())
    write("slush_skid_loop.wav", slush_loop())
    write("door_open.wav", door(False))
    write("door_close.wav", door(True))
    write("ui_click.wav", ui_click())
    write("bread_get.wav", chime([784.0, 1046.5], 0.09, 0.5))
    write("quest_complete.wav", chime([523.3, 659.3, 784.0, 1046.5], 0.14, 0.8))
    write("yard_ambience_loop.wav", yard_ambience())
    # POLISH-02: бормотание под печать реплик (Бабка ниже и медленнее, продавщица выше и бойче) и сигнал «ПРИНЯТЬ».
    write("voice_babka.wav", voice(31, 165.0, 1.2, 7.0, 0.12))
    write("voice_vendor.wav", voice(37, 245.0, 1.2, 8.5, 0.15))
    write("quest_accept.wav", to_rms(chime([659.3, 987.8], 0.07, 0.3), -17.0))
    # EXT-01 (L): Илюша — между Бабкой и продавщицей, ровнее; полицейский ниже и размереннее;
    # «военком» ещё ниже и почти без интонации. Радио — бубнёж диктора через узкую полосу приёмника, 4,5 с.
    write("voice_ilyusha.wav", voice(41, 205.0, 1.2, 7.5, 0.08))
    write("voice_officer.wav", voice(43, 125.0, 1.2, 5.5, 0.06))
    write("voice_account_officer.wav", voice(47, 108.0, 1.2, 5.0, 0.03))
    write("radio_mumble.wav", radio_mumble(53, 4.5))
    # ARENA-01 (T): троллейбус на кольце — тихий гул (цикл) и пневматические двери на остановках.
    write("trolley_hum_loop.wav", trolley_hum_loop())
    write("trolley_doors.wav", trolley_doors(67))
    # CITY-01 (A): слои фона и живность — ветер с порывами, далёкий трафик, музыка из окна (циклы), вороны,
    # собака, дверь подъезда, короткий сигнал машины (разовые).
    write("wind_gust_loop.wav", wind_gust_loop())
    write("distant_traffic_loop.wav", distant_traffic_loop())
    write("window_music_loop.wav", window_music_loop())
    write("crow_caw_1.wav", crow_caw(83, 2))
    write("crow_caw_2.wav", crow_caw(89, 3))
    write("dog_bark.wav", dog_bark(97))
    write("door_slam.wav", door_slam())
    write("car_horn_short.wav", car_horn_short())
    # EXT-02 (E): бочка — дребезжание качения (цикл, громкость по скорости) и «БУМ» удара о стену.
    write("barrel_roll_loop.wav", barrel_roll_loop())
    write("barrel_bump.wav", barrel_bump())
    # COINS-01: звон подобранной монеты (высоту чередует SoundDirector).
    write("coin_pickup.wav", coin_pickup())
    # INTRO-01: свайп ленты новостей на телефоне во вступительной заставке.
    write("phone_swipe.wav", phone_swipe())
    # PUNCH-01: дроны ГСУМ — жужжание (цикл, 3D по удалению), взмах удара и хлопок сбитого дрона.
    write("drone_buzz_loop.wav", drone_buzz_loop())
    write("punch_whoosh.wav", punch_whoosh())
    write("drone_pop.wav", drone_pop())
    # PUNCH-02: «бип-бип» дрона при подлёте к Илюше.
    write("drone_beep.wav", drone_beep())
    # KNOCK-01: сбитый «Ладой» житель — «вжух» взлёта и глухой «пуф» в снег.
    write("knock_whoosh.wav", knock_whoosh())
    write("knock_thud.wav", knock_thud())
    # BREAK-01: поломка разрушаемых объектов — треск дерева, лязг металла, хруст пластика, снежный «пуф» (тот же синтез,
    # что падение сбитого жителя KNOCK-01); реакции без разрушения — сигнализация машины и хлопок крышек контейнера.
    write("break_wood.wav", break_wood())
    write("break_metal.wav", break_metal())
    write("break_plastic.wav", break_plastic())
    write("break_snow.wav", knock_thud())
    write("car_alarm.wav", car_alarm())
    write("bin_lid.wav", bin_lid())
    # DRIVE-02: колёса в рыхлом снегу (цикл, громкость по глубине) и скрип шин при заносе (цикл, по боковой скорости).
    write("snow_drive_loop.wav", snow_drive_loop())
    write("skid_squeak_loop.wav", skid_squeak_loop())
    # PEOPLE-03: звуки занятий жителей и птиц — стук костяшки домино, взмах метлы, скрип санок (и горки), клюшка по
    # шайбе, воркование голубей, хлопанье крыльев взлетающей стайки (разовые, 3D у источника).
    write("domino_clack.wav", domino_clack())
    write("broom_swish.wav", broom_swish())
    write("sled_creak.wav", sled_creak())
    write("hockey_stick.wav", hockey_stick())
    write("pigeon_coo.wav", pigeon_coo(233))
    write("wings_flap.wav", wings_flap(239))


if __name__ == "__main__":
    main()

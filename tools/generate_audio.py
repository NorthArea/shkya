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


if __name__ == "__main__":
    main()

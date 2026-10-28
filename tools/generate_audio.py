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


if __name__ == "__main__":
    main()

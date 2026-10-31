# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy==2.5.4", "scipy==1.18.1", "soundfile==0.14.0"]
# ///
"""MUSIC-03: uv run tools/prepare_menu_nocturne.py /path/to/original.flac.

Источник и условия фонограммы — assets/README.md. Загруженный FLAC хранится
вне репозитория; принимается только проверенная версия Wikimedia Commons.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

SOURCE_SHA256 = "d286d06381db63d05cb3b971e3b39132866efade1dd94f514c1d83ff9d42de70"
RATE = 48000
PEAK_DB = -1.5
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/audio/chopin_op9_no2_frank_levy.ogg"


def rms_db(samples: np.ndarray) -> float:
    return float(10 * np.log10(np.mean(np.square(samples, dtype=np.float64))))


def prepare(source: Path) -> dict:
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    if source_hash != SOURCE_SHA256:
        raise ValueError(f"Unexpected source SHA256: {source_hash}")
    samples, rate = sf.read(source, dtype="float32", always_2d=True)
    if rate != 96000 or samples.shape[1] != 2:
        raise ValueError("Expected the original 96 kHz stereo FLAC")
    # Антиалиасинг до понижения частоты, без изменения темпа и высоты нот.
    samples = resample_poly(samples, 1, 2, axis=0, window=("kaiser", 12.0))
    samples *= float(10 ** (PEAK_DB / 20)) / float(np.abs(samples).max())
    # Только край записи: не обрезать последний аккорд и его реверберацию.
    for seconds, head in ((0.02, True), (0.15, False)):
        count = round(seconds * RATE)
        ramp = np.linspace(0, 1, count, dtype=np.float32)[:, None]
        if head:
            samples[:count] *= ramp
        else:
            samples[-count:] *= ramp[::-1]
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # libsndfile: compression 0.1 соответствует Vorbis quality 0.9.
    # Длинный единственный sf.write вызывает native crash libsndfile 1.2.2;
    # секундные блоки дают тот же непрерывный поток кодека без переполнения.
    with sf.SoundFile(OUTPUT, mode="w", samplerate=RATE, channels=2,
                      format="OGG", subtype="VORBIS", compression_level=0.1) as audio:
        for offset in range(0, len(samples), RATE):
            audio.write(samples[offset:offset + RATE])
    decoded, decoded_rate = sf.read(OUTPUT, dtype="float32", always_2d=True)
    peak = float(np.abs(decoded).max())
    if decoded_rate != RATE or decoded.shape != samples.shape or peak >= 1:
        raise ValueError("Encoded audio changed duration/channels or clips")
    return {
        "source_sha256": source_hash,
        "output_sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "bytes": OUTPUT.stat().st_size,
        "rate": decoded_rate,
        "channels": decoded.shape[1],
        "seconds": decoded.shape[0] / decoded_rate,
        "rms_db": rms_db(decoded),
        "peak_db": float(20 * np.log10(peak)),
        "clipped_samples": int(np.count_nonzero(np.abs(decoded) >= 1)),
        "loop_boundary_step": float(np.max(np.abs(decoded[0] - decoded[-1]))),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.source), indent=2))

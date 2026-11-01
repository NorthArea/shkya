# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy==2.5.4", "soundfile==0.13.1"]
# ///
"""Prepare verified radio masters and an original deterministic tuning effect.

uv run tools/prepare_radio_audio.py /path/to/downloaded/masters
Sources and permissions: assets/audio/radio/README.md. No network downloads here.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/radio"
RATE = 48000
TARGET_RMS_DB = -20.0
PEAK_DB = -1.5
MASTERS = {
    "cold_funk": ("cold_funk_original.mp3", "a7d0b772f05b99c4ac3df28cb2feaa5190781c2b87bceef5052cc45408b6fc75"),
    "local_forecast_elevator": ("local_forecast_elevator.mp3", "8c46b44e65324bc339fbbc3e770611d671f6c74a40f3ec8dd50332c082b25cc9"),
    "monkeys_spinning_monkeys": ("monkeys_spinning_monkeys.mp3", "a5bb345c23849ad0786aa0bc5157a9f2d4039660fe00282e55754d475f36dc14"),
    "sneaky_snitch": ("sneaky_snitch.mp3", "db1710333d68a215277f77e4e17e1a64bf4ed38f87c70f8d0f56b16b6aa4f884"),
    "beethoven_moonlight_1": ("beethoven_moonlight_1.ogg", "035a31b8d67de4b0574110592a6f8ce2f6e51dfc7f884e16f918e47e327d7d66"),
    "chopin_nocturne_1": ("chopin_nocturne_1.flac", "30fa44a60dc09033b7be9d381a3344d93099cef746a3faf9cf1eafe54d53c398"),
    "ride_of_the_valkyries": ("ride_of_the_valkyries_milman.wav", "14c81cb9f4e733aff6ec510e5794c37823093994b77186739be0d00857f074bc"),
}

def rms_db(samples: np.ndarray) -> float:
    return float(10 * np.log10(np.mean(np.square(samples, dtype=np.float64))))

def stats(path: Path) -> dict:
    audio, rate = sf.read(path, dtype="float32", always_2d=True)
    peak = float(np.abs(audio).max())
    if not np.isfinite(audio).all() or peak >= 1.0:
        raise ValueError(f"Non-finite or clipped decoded asset: {path}")
    return {"file": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "rate": rate, "channels": audio.shape[1], "seconds": len(audio) / rate,
            "rms_db": rms_db(audio), "peak_db": float(20 * np.log10(peak)), "clipped_samples": 0}

def prepare(source_dir: Path, name: str, source_spec: tuple[str, str]) -> dict:
    filename, expected = source_spec
    source = source_dir / filename
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != expected:
        raise ValueError(f"Unexpected master hash: {filename}")
    samples, rate = sf.read(source, dtype="float32", always_2d=True)
    if rate != RATE:
        # Feed CoreAudio PCM WAV; macOS does not decode every Ogg source directly.
        native = source_dir / (name + "_native.wav")
        decoded = source_dir / (name + "_48k.wav")
        sf.write(native, samples, rate, subtype="FLOAT")
        subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEF32@48000", "-c", "2", "-q", "127", str(native), str(decoded)], check=True)
        samples, rate = sf.read(decoded, dtype="float32", always_2d=True)
    if rate != RATE:
        raise ValueError("CoreAudio did not produce the requested sample rate")
    gain_db = min(TARGET_RMS_DB - rms_db(samples), PEAK_DB - float(20 * np.log10(np.abs(samples).max())))
    samples *= float(10 ** (gain_db / 20))
    for seconds, head in ((0.015, True), (0.08, False)):
        count = round(seconds * RATE)
        ramp = np.linspace(0, 1, count, dtype=np.float32)[:, None]
        if head:
            samples[:count] *= ramp
        else:
            samples[-count:] *= ramp[::-1]
    path = OUT / f"{name}.ogg"
    # Short blocks avoid the known large-write libsndfile failure in our menu pipeline.
    with sf.SoundFile(path, mode="w", samplerate=RATE, channels=samples.shape[1], format="OGG", subtype="VORBIS", compression_level=0.1) as target:
        for offset in range(0, len(samples), RATE):
            target.write(samples[offset:offset + RATE])
    result = stats(path)
    result.update(source_sha256=digest, applied_gain_db=gain_db)
    return result

def tuning() -> dict:
    count = round(RATE * 1.25)
    time = np.arange(count, dtype=np.float64) / RATE
    rng = np.random.default_rng(104201)
    spectrum = np.fft.rfft(rng.normal(0, 1, count))
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    band = np.clip((frequencies - 250) / 200, 0, 1) * np.clip((6500 - frequencies) / 1200, 0, 1)
    noise = np.fft.irfft(spectrum * band, n=count)
    envelope = (0.38 + 0.62 * np.sin(2 * np.pi * (3.2 * time + 0.9 * time**2)) ** 2)
    frequency = 780 + 2150 * time + 220 * np.sin(time * 2 * np.pi * 4.5)
    whistle = np.sin(2 * np.pi * np.cumsum(frequency) / RATE)
    bursts = np.exp(-((time - 0.32) / 0.055)**2) + 0.7 * np.exp(-((time - 0.76) / 0.08)**2)
    signal = noise * envelope + whistle * bursts * 0.25
    signal *= np.minimum(1, time / 0.025) * np.minimum(1, np.maximum(0, 1.22 - time) / 0.16)
    signal *= 10**(-19 / 20) / np.sqrt(np.mean(signal**2))
    signal *= min(1.0, 10**(-3 / 20) / np.abs(signal).max())
    path = OUT / "radio_tune.wav"
    sf.write(path, signal, RATE, subtype="PCM_16")
    return stats(path)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("--tracks", nargs="+", choices=MASTERS, help="Prepare only these masters; keep the other assets unchanged")
    parser.add_argument("--skip-tuning", action="store_true", help="Keep the existing original tuning effect")
    parser.add_argument("--report", type=Path, default=ROOT / "builds/checks/RADIO-01/asset-audio.json")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    names = args.tracks or list(MASTERS)
    report = {"tracks": [prepare(args.source_dir, name, MASTERS[name]) for name in names]}
    if not args.skip_tuning:
        report["tuning"] = tuning()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))

#!/usr/bin/env python3
"""Generates a synthesized alarm-clock buzzer tone as a loopable WAV file.

Deliberately does NOT reuse or download any existing audio -- this repo's
other audio assets (Night_Firepit.mp3, Ocean_Waves.mp3, Rain_Sounds.mp3,
Forest_Birds.mp3) are calm ambient/meditation sounds and are wrong for an
urgent wake-up alarm. This generates a distinct tone instead.
"""
import math
import struct
import wave

SAMPLE_RATE = 44100
AMPLITUDE = 0.6  # of full scale, to avoid clipping distortion
FADE_SAMPLES = 200  # ~4.5ms fade in/out per beep, avoids clicking


def _tone(freq_hz: float, duration_s: float) -> list[float]:
    total = int(SAMPLE_RATE * duration_s)
    samples = []
    for i in range(total):
        t = i / SAMPLE_RATE
        value = AMPLITUDE * math.sin(2 * math.pi * freq_hz * t)
        if i < FADE_SAMPLES:
            value *= i / FADE_SAMPLES
        elif i > total - FADE_SAMPLES:
            value *= (total - i) / FADE_SAMPLES
        samples.append(value)
    return samples


def _silence(duration_s: float) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * duration_s)


def build_clip() -> list[float]:
    # Classic three-beep alarm cadence, the third beep pitched up for
    # urgency, totalling exactly 2.0s so it loops seamlessly.
    samples: list[float] = []
    samples += _tone(1000, 0.20)
    samples += _silence(0.10)
    samples += _tone(1000, 0.20)
    samples += _silence(0.10)
    samples += _tone(1300, 0.30)
    samples += _silence(1.10)
    return samples


def write_wav(path: str, samples: list[float]) -> None:
    with wave.open(path, "w") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", max(-32768, min(32767, int(s * 32767))))
            for s in samples
        )
        wav_file.writeframes(frames)


if __name__ == "__main__":
    write_wav("assets/audio/sleep_alarm.wav", build_clip())
    print("Wrote assets/audio/sleep_alarm.wav")

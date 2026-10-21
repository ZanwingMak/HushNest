#!/usr/bin/env python3
"""生成无外部版权依赖的确定性助眠音与渐强提醒。"""
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / "HushNest" / "Resources"
RATE = 22050


def write_wave(name, values):
    """以单声道 PCM 保存并限制峰值，避免数字削波。"""
    with wave.open(str(ROOT / f"{name}.wav"), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(b"".join(struct.pack("<h", int(max(-0.9, min(0.9, v)) * 32767)) for v in values))


def ambience(name):
    """以确定随机种子合成可循环的雨声、潮汐和棕噪音。"""
    rng = random.Random(20261021)
    low = 0.0
    values = []
    for i in range(RATE * 12):
        t = i / RATE
        white = rng.uniform(-1, 1)
        low = 0.985 * low + 0.015 * white
        if name == "rain":
            value = white * 0.12 + low * 0.5
        elif name == "ocean":
            value = (white * 0.08 + low * 1.2) * (0.6 + 0.4 * math.sin(2 * math.pi * t / 12) ** 2)
        else:
            value = low * 2
        values.append(value)
    # 交叉淡化为闭合循环，避免音轨接缝出现突变。
    blend = RATE // 2
    for i in range(blend):
        mix = i / blend
        values[-blend + i] = values[-blend + i] * (1 - mix) + values[i] * mix
    return values[blend:]


def alarm(name):
    """合成三种和弦音型，前十二秒渐强并平滑每个音符的包络。"""
    notes = {"dawn": [523.25, 659.25, 783.99], "bell": [659.25, 880, 987.77], "orbit": [440, 554.37, 659.25]}[name]
    values = []
    for i in range(RATE * 60):
        t = i / RATE
        beat = t % 1.5
        note = notes[int(t / 1.5) % 3]
        envelope = min(1, beat / 0.025) * math.exp(-beat * 3)
        fade = min(1, t / 12)
        value = (math.sin(2 * math.pi * note * t) + 0.2 * math.sin(2 * math.pi * note * 2 * t)) * 0.4 * envelope * fade
        values.append(value)
    return values


def main():
    """重新生成所有随应用离线分发的音频资源。"""
    ROOT.mkdir(parents=True, exist_ok=True)
    for name in ["rain", "ocean", "brown"]:
        write_wave(name, ambience(name))
    for name in ["dawn", "bell", "orbit"]:
        write_wave(name, alarm(name))
    print("Generated six original PCM audio resources.")


if __name__ == "__main__":
    main()

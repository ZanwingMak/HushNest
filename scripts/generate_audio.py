#!/usr/bin/env python3
"""生成原创离线音景：44.1kHz、频谱整形、立体声及柔和乐器包络；需要 numpy。"""
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1] / 'HushNest' / 'Resources'
RATE = 44100
RNG = np.random.default_rng(20261021)


def noise(count, slope=0.0, cutoff=6000):
    """在频域构造周期性带限噪音，抑制刺耳高频和直流分量。"""
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    spectrum = np.fft.rfft(RNG.normal(size=count))
    weight = np.maximum(frequencies, 45) ** (-slope / 2)
    weight *= np.exp(-(frequencies / cutoff) ** 4)
    weight *= 1 - np.exp(-(frequencies / 28) ** 4)
    spectrum *= weight
    spectrum[0] = 0
    result = np.fft.irfft(spectrum, n=count)
    return result / max(np.std(result), 1e-8)


def ambience(name):
    """分层合成连续音景，周期调制与尾首交叉淡化避免突然接缝。"""
    count = RATE * 32
    t = np.arange(count) / RATE
    channels = []
    for channel in range(2):
        phase = channel * 0.2
        base = noise(count, 1.2, 4300)
        low = noise(count, 2.0, 1600)
        if name == 'rain':
            value = 0.8 * base + 0.2 * noise(count, 0.4, 6500)
            value *= 0.85 + 0.15 * np.sin(2 * np.pi * t / 16 + phase)
        elif name == 'ocean':
            surge = (0.5 + 0.5 * np.sin(2 * np.pi * t / 8 + phase)) ** 1.7
            value = (0.65 * low + 0.35 * base) * (0.35 + 0.65 * surge)
        elif name == 'brown':
            value = noise(count, 2.2, 2400)
        elif name == 'pink':
            value = noise(count, 1.0, 5200)
        elif name == 'stream':
            value = 0.5 * base + 0.25 * noise(count, 0.3, 4000)
            for frequency in [720, 1060, 1380]:
                envelope = np.maximum(0, np.sin(2 * np.pi * t / 3.2 + frequency)) ** 8
                value += 0.10 * np.sin(2 * np.pi * frequency * t + 3 * np.sin(2 * np.pi * t / 2)) * envelope
        elif name == 'forest':
            value = low * 0.6 * (0.7 + 0.3 * np.sin(2 * np.pi * t / 16))
            for onset in [3, 11, 22, 27]:
                dt = t - onset - channel * 0.07
                envelope = np.exp(-((dt - 0.25) / 0.15) ** 2)
                value += 0.18 * np.sin(2 * np.pi * (1800 * dt + 450 * dt ** 2)) * envelope
        elif name == 'fireplace':
            value = 0.7 * low
            for onset in RNG.uniform(0, 32, 65):
                dt = t - onset
                envelope = np.where(dt >= 0, np.exp(-np.maximum(dt, 0) * 65), 0)
                value += noise(count, 0, 5200) * envelope * 0.25
        else:
            value = 0.4 * low
            chirp = np.maximum(0, np.sin(2 * np.pi * 2 * t + phase)) ** 10
            phrase = np.maximum(0, np.sin(2 * np.pi * t / 8)) ** 2
            value += 0.12 * np.sin(2 * np.pi * 2600 * t) * chirp * phrase
        channels.append(value)
    values = np.column_stack(channels)
    blend = RATE * 2
    mix = np.linspace(0, 1, blend)[:, None]
    values[-blend:] = values[-blend:] * (1 - mix) + values[:blend] * mix
    values = values[blend:]
    values *= 0.17 / np.sqrt(np.mean(values ** 2))
    return np.tanh(values * 0.9) * 0.78


def alarm(name):
    """以独立乐器音色和五声音阶旋律生成渐强提醒，避免旧版单调尖锐正弦。"""
    recipes = {
        'dawn': ([60, 64, 67, 72, 67, 64], 0.055, 1.5, [1, .20, .06]),
        'bell': ([76, 79, 83, 79, 74, 76], .012, 2.5, [1, .28, .10]),
        'orbit': ([57, 64, 69, 76, 69, 64], .12, 1.3, [1, .15, .04]),
        'piano': ([60, 67, 72, 64, 69, 67], .015, 2.0, [1, .35, .13, .05]),
        'marimba': ([60, 64, 67, 69, 67, 64], .008, 5, [1, .03, .12]),
        'harp': ([60, 62, 67, 72, 74, 79], .009, 2.8, [1, .30, .13]),
        'bamboo': ([69, 72, 76, 72, 67, 69], .08, 2.2, [1, .07, .02]),
        'aurora': ([53, 60, 65, 69, 72, 69], .3, .9, [1, .16, .08]),
    }
    notes, attack, decay, harmonics = recipes[name]
    values = np.zeros(RATE * 60)
    for index, onset in enumerate(np.arange(0, 58, 1.8)):
        n = min(RATE * 6, len(values) - int(onset * RATE))
        dt = np.arange(n) / RATE
        frequency = 440 * 2 ** ((notes[index % len(notes)] - 69) / 12)
        tone = sum(amp * np.sin(2 * np.pi * frequency * (harmonic + 1) * dt)
                   for harmonic, amp in enumerate(harmonics))
        envelope = (1 - np.exp(-dt / attack)) * np.exp(-dt * decay)
        tone *= envelope
        # 柔和短混响和微弱低八度增加空间感，延迟不改变开始时间。
        delay = int(.11 * RATE)
        tone[delay:] += tone[:-delay].copy() * .18
        values[int(onset * RATE):int(onset * RATE) + n] += tone
    t = np.arange(len(values)) / RATE
    values *= np.minimum(1, t / 12) * np.minimum(1, (60 - t) / 2)
    values *= .72 / max(np.max(np.abs(values)), 1e-8)
    return values


def write_wave(name, values):
    """保存无削波的 16 位 PCM，保持循环样本与精确时长。"""
    samples = (np.clip(values, -.95, .95) * 32767).astype('<i2')
    with wave.open(str(ROOT / f'{name}.wav'), 'wb') as output:
        output.setparams((1 if samples.ndim == 1 else samples.shape[1], 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(samples.tobytes())


def main():
    """可重复生成八种音景和八种提醒，不下载第三方版权素材。"""
    ROOT.mkdir(parents=True, exist_ok=True)
    for name in ['rain', 'ocean', 'brown', 'pink', 'stream', 'forest', 'fireplace', 'night']:
        write_wave(name, ambience(name))
    for name in ['dawn', 'bell', 'orbit', 'piano', 'marimba', 'harp', 'bamboo', 'aurora']:
        write_wave(name, alarm(name))
    print('Generated 16 original 44.1kHz soundscapes and melodies.')


if __name__ == '__main__':
    main()

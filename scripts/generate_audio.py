#!/usr/bin/env python3
"""生成两种噪音和十四种原创铃声；六种实录音景由 prepare_recordings.py 单独处理。"""
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


def noise_ambience(name):
    """仅合成名称准确的棕噪音和粉红噪音，不覆盖实地录制的自然音景。"""
    count = RATE * 32
    slope, cutoff = (2.2, 2400) if name == 'brown' else (1.0, 5200)
    values = np.column_stack([noise(count, slope, cutoff) for _ in range(2)])
    blend = RATE * 2
    mix = np.linspace(0, 1, blend)[:, None]
    values[-blend:] = values[-blend:] * (1 - mix) + values[:blend] * mix
    values = values[blend:]
    values *= 0.17 / np.sqrt(np.mean(values ** 2))
    # 噪音音量对齐约 -25 LUFS 的实录音景，避免切换时突然变响。
    return np.tanh(values * 0.9) * 0.78 * (0.5 if name == 'brown' else 0.35)


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


def strong_alarm(name):
    """用鲜明节奏及带限谐波合成六种起床提醒，峰值留出安全余量。"""
    t = np.arange(RATE * 60) / RATE
    period = {'classic': 1.2, 'twinbell': .22, 'digital': .8, 'pulse': .48, 'beacon': 1.0, 'reveille': .38}[name]
    phase = np.mod(t, period)
    if name == 'classic':
        gate = ((phase < .18) | ((phase > .28) & (phase < .46))).astype(float)
        frequency = np.full_like(t, 880)
    elif name == 'twinbell':
        gate = (phase < .16).astype(float)
        frequency = np.where(np.mod(t, .44) < .22, 1350, 1720)
    elif name == 'digital':
        gate = (phase < .12).astype(float) + ((phase > .2) & (phase < .32)).astype(float) + ((phase > .4) & (phase < .52)).astype(float)
        frequency = np.full_like(t, 1046.5)
    elif name == 'pulse':
        gate = (phase < .26).astype(float)
        frequency = np.where(np.mod(t, .96) < .48, 660, 990)
    elif name == 'beacon':
        gate = (phase < .75).astype(float)
        frequency = np.where(np.mod(t, 2) < 1, 740, 1110)
    else:
        gate = (phase < .3).astype(float)
        frequency = np.take([523.25, 659.25, 783.99, 1046.5, 783.99, 659.25], (t / period).astype(int) % 6)
    # 十毫秒包络平滑，避免矩形门限造成点击声。
    gate = np.convolve(gate, np.ones(441) / 441, mode='same')
    angle = 2 * np.pi * np.cumsum(frequency) / RATE
    values = (np.sin(angle) + .25 * np.sin(3 * angle) + .10 * np.sin(5 * angle)) * gate
    values *= np.minimum(1, .22 + t / 6) * np.minimum(1, (60 - t) / .15)
    return values * (.78 / max(np.max(np.abs(values)), 1e-8))


def write_wave(name, values):
    """保存无削波的 16 位 PCM，保持循环样本与精确时长。"""
    samples = (np.clip(values, -.95, .95) * 32767).astype('<i2')
    with wave.open(str(ROOT / f'{name}.wav'), 'wb') as output:
        output.setparams((1 if samples.ndim == 1 else samples.shape[1], 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(samples.tobytes())


def main():
    """可重复生成两种噪音和十四种提醒，保留已有实地录音。"""
    ROOT.mkdir(parents=True, exist_ok=True)
    for name in ['brown', 'pink']:
        write_wave(name, noise_ambience(name))
    for name in ['dawn', 'bell', 'orbit', 'piano', 'marimba', 'harp', 'bamboo', 'aurora']:
        write_wave(name, alarm(name))
    for name in ['classic', 'twinbell', 'digital', 'pulse', 'beacon', 'reveille']:
        write_wave(name, strong_alarm(name))
    print('Generated 2 noise textures and 14 alarms; field recordings were preserved.')


if __name__ == '__main__':
    main()

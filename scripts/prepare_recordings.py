#!/usr/bin/env python3
"""下载公有领域实地录音，统一响度并生成可无缝循环的离线 PCM；需要 ffmpeg 和 numpy。"""
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request
from urllib.parse import urlparse
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'HushNest' / 'Resources'
CACHE = ROOT / 'build' / 'FieldRecordings'
RATE = 44100


def prepare(recording):
    """验证作者许可及源文件摘要，保留实录细节并交叉衔接尾首，始终不播放音频。"""
    cached = CACHE / (recording['id'] + Path(urlparse(recording['download']).path).suffix)
    if not cached.exists():
        page = urllib.request.urlopen(recording['source'], timeout=60).read().decode()
        marker = 'Public Domain' if recording['license'] == 'Public Domain' else 'creativecommons.org/publicdomain/zero/1.0'
        if marker not in page:
            raise ValueError('Source no longer confirms its public-domain license: ' + recording['id'])
        data = urllib.request.urlopen(recording['download'], timeout=90).read()
        cached.write_bytes(data)
    digest = hashlib.sha256(cached.read_bytes()).hexdigest()
    if recording.get('sourceSHA256') and digest != recording['sourceSHA256']:
        raise ValueError('Source audio checksum changed: ' + recording['id'])
    raw = subprocess.check_output([
        'ffmpeg', '-v', 'error', '-i', str(cached),
        '-af', f"atrim=start={recording['start']}:duration={recording['seconds'] + recording['crossfade']},"
               'asetpts=PTS-STARTPTS,highpass=f=40,lowpass=f=12000,loudnorm=I=-25:TP=-8:LRA=8',
        '-ar', str(RATE), '-ac', '2', '-f', 'f32le', '-'
    ])
    values = np.frombuffer(raw, dtype='<f4').reshape(-1, 2).astype(np.float64)
    count = int(RATE * recording['seconds'])
    blend = int(RATE * recording['crossfade'])
    if len(values) < count + blend:
        raise ValueError('Recording is shorter than the selected excerpt: ' + recording['id'])
    values = values[:count + blend]
    values -= values.mean(axis=0)
    # EBU R128 响度处理抑制孤立尖峰，保持各场景的感知音量接近，并给循环交叉留出余量。
    values *= min(1, 0.48 / max(np.max(np.abs(values)), 1e-8))
    result = values[blend:].copy()
    phase = np.linspace(0, np.pi / 2, blend)[:, None]
    result[-blend:] = values[-blend:] * np.cos(phase) + values[:blend] * np.sin(phase)
    samples = np.round(result * 32767).astype('<i2')
    destination = RESOURCES / (recording['id'] + '.wav')
    with wave.open(str(destination), 'wb') as output:
        output.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(samples.tobytes())
    return {
        'id': recording['id'], 'sourceSHA256': digest,
        'outputSHA256': hashlib.sha256(destination.read_bytes()).hexdigest(),
        'seconds': len(result) / RATE, 'peak': float(np.max(np.abs(result))),
        'rms': float(np.sqrt(np.mean(result ** 2))),
        'seamDelta': float(np.max(np.abs(result[-1] - result[0])))
    }


def main():
    """只重建清单中的六种实录音景，将审计结果保存在忽略的构建目录。"""
    CACHE.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((RESOURCES / 'FieldRecordings.json').read_text())
    results = [prepare(recording) for recording in catalog['recordings']]
    (CACHE / 'verification.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()

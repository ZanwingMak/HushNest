#!/usr/bin/env python3
"""下载 CC0 长实录，统一响度并生成带无间隙时长信息的离线 M4A；需要 ffmpeg 和 numpy。"""
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import urlparse
import tempfile
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'HushNest' / 'Resources'
CACHE = ROOT / 'build' / 'LongRecordings'
RATE = 44100


def prepare(recording):
    """处理连续长录音，以内存映射交叉衔接尾首并压缩保存，全程不播放音频。"""
    sound_id = Path(urlparse(recording['source']).path).name
    cached = CACHE / f"{recording['id']}-{sound_id}.mp3"
    if not cached.exists():
        page = subprocess.check_output(['curl', '--fail', '--location', '--silent', '--show-error',
                                        '--connect-timeout', '15', '--max-time', '60', recording['source']]).decode()
        if 'creativecommons.org/publicdomain/zero/1.0' not in page:
            raise ValueError('Source no longer confirms its public-domain license: ' + recording['id'])
        partial = cached.with_suffix('.part')
        for attempt in range(12):
            result = subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--connect-timeout', '15',
                                     '--max-time', '180', '--continue-at', '-', recording['download'], '--output', str(partial)])
            if result.returncode == 0:
                break
            if result.returncode not in [16, 18, 28, 35, 56]:
                result.check_returncode()
        else:
            raise RuntimeError('Download did not complete: ' + recording['id'])
        partial.replace(cached)
    digest = hashlib.sha256(cached.read_bytes()).hexdigest()
    if recording.get('sourceSHA256') and digest != recording['sourceSHA256']:
        raise ValueError('Source audio checksum changed: ' + recording['id'])
    count = int(RATE * recording['seconds'])
    blend = int(RATE * recording['crossfade'])
    if recording['seconds'] < 300 or blend < RATE * 10:
        raise ValueError('Sleep recordings need at least five minutes and a ten-second crossfade')
    with tempfile.TemporaryDirectory(prefix='hushnest-recording-', dir=CACHE) as temporary:
        raw = Path(temporary) / 'audio.f32'
        subprocess.run([
            'ffmpeg', '-v', 'error', '-y', '-i', str(cached),
            '-af', f"atrim=start={recording['start']}:duration={recording['seconds'] + recording['crossfade']},"
                   'asetpts=PTS-STARTPTS,highpass=f=40,lowpass=f=12000,loudnorm=I=-25:TP=-8:LRA=8',
            '-ar', str(RATE), '-ac', '2', '-f', 'f32le', str(raw)
        ], check=True)
        values = np.memmap(raw, dtype='<f4', mode='r+').reshape(-1, 2)
        if len(values) < count + blend:
            raise ValueError('Recording is shorter than the selected excerpt: ' + recording['id'])
        values = values[:count + blend]
        result = values[blend:]
        # 等功率的长交叉衔接保持接缝附近能量，循环末尾接回原录音的相邻样本。
        phase = np.linspace(0, np.pi / 2, blend, dtype=np.float32)[:, None]
        result[-blend:] = values[-blend:] * np.cos(phase) + values[:blend] * np.sin(phase)
        peak = max(float(np.max(np.abs(result[i:i + RATE * 10]))) for i in range(0, count, RATE * 10))
        gain = min(1, 0.48 / max(peak, 1e-8))
        for i in range(0, count, RATE * 10):
            result[i:i + RATE * 10] *= gain
        values.flush()
        destination = RESOURCES / (recording['id'] + '.m4a')
        encoding = ['-c:a', 'alac', '-sample_fmt', 's16p'] if recording.get('codec') == 'alac' else ['-c:a', 'aac', '-b:a', '192k']
        subprocess.run([
            'ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(RATE), '-ac', '2', '-i', str(raw),
            '-af', f'atrim=start_sample={blend}:end_sample={blend + count},asetpts=PTS-STARTPTS',
            *encoding, '-movflags', '+faststart', str(destination)
        ], check=True)
        return {
            'id': recording['id'], 'sourceSHA256': digest,
            'outputSHA256': hashlib.sha256(destination.read_bytes()).hexdigest(),
            'seconds': count / RATE, 'peakBeforeEncoding': peak * gain,
            'seamDeltaBeforeEncoding': float(np.max(np.abs(result[-1] - result[0])))
        }


def main():
    """重建六种长实录并同步成品摘要，原始许可与来源保持在资源清单中。"""
    CACHE.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((RESOURCES / 'FieldRecordings.json').read_text())
    results = [prepare(recording) for recording in catalog['recordings']]
    for recording, result in zip(catalog['recordings'], results):
        recording['outputSHA256'] = result['outputSHA256']
    (RESOURCES / 'FieldRecordings.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    (CACHE / 'verification.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()

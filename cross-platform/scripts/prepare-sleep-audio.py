#!/usr/bin/env python3
"""Rebuild only the cross-platform sleep pack; never writes iOS resources.

Requires numpy and ffmpeg (or imageio-ffmpeg). Sources are full-length public
CC0 preview downloads, not the short recordings in HushNest/Resources.
Usage: python scripts/prepare-sleep-audio.py [--download] [--verify]
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import urllib.request
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "assets" / "sleep"
CACHE = ROOT.parent / "build" / "long-sleep-sources"
MANIFEST = PACK / "FieldRecordings.json"


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def audit(file):
    with wave.open(str(file), "rb") as reader:
        rate, channels, frames = reader.getframerate(), reader.getnchannels(), reader.getnframes()
        assert reader.getsampwidth() == 2 and reader.getcomptype() == "NONE"
        pcm = np.frombuffer(reader.readframes(frames), dtype="<i2").reshape(-1, channels)
    values = pcm.astype(np.float32) / 32768
    # Compare the wrap to normal neighboring samples, and levels either side.
    differences = np.abs(values[1::8] - values[::8])
    seam = float(np.max(np.abs(values[-1] - values[0])))
    ordinary = float(np.quantile(differences, .99))
    levels = np.sqrt(np.mean(values.reshape(-1, rate, channels) ** 2, axis=(1, 2)))
    edge_levels = [float(np.sqrt(np.mean(edge ** 2))) for edge in (values[:rate], values[-rate:])]
    blocks = [hashlib.sha256(pcm[n:n + rate].tobytes()).digest() for n in range(0, frames, rate)]
    # Old loop lengths and other short periods must not occur inside the new file.
    mono = values[::8].mean(axis=1)
    probe = mono[:rate * 20 // 8]
    correlations = []
    for seconds in [10, 15, 20, 22, 30, 44, 55, 65, 70, 85, 120]:
        offset = seconds * rate // 8
        correlations.append(abs(float(np.corrcoef(probe, mono[offset:offset + len(probe)])[0, 1])))
    result = dict(seconds=frames / rate, sampleRate=rate, channels=channels,
                  peak=float(np.max(np.abs(values))), rms=float(np.sqrt(np.mean(values ** 2))),
                  minimumSecondRMS=float(levels.min()), seamDelta=seam,
                  seamToTypicalDelta=seam / max(ordinary, 1e-8),
                  seamLevelDB=float(abs(20 * np.log10(max(edge_levels) / max(min(edge_levels), 1e-8)))),
                  uniqueSecondBlocks=len(set(blocks)), maxShortLagCorrelation=max(correlations))
    assert result["seconds"] >= 300, result
    assert .005 < result["rms"] < .2 and result["peak"] < .75, result
    assert result["minimumSecondRMS"] > .0001, result
    assert result["seamToTypicalDelta"] < 2 and result["seamLevelDB"] < 6, result
    assert len(set(blocks)) == len(blocks) and max(correlations) < .4, result
    return result


def write(file, values, rate):
    with wave.open(str(file), "wb") as writer:
        writer.setparams((values.shape[1], 2, rate, 0, "NONE", "not compressed"))
        writer.writeframes(np.round(values * 32767).astype("<i2").tobytes())


def prepare_recording(item, rate, ffmpeg, download):
    cached = CACHE / (item["id"] + ".mp3")
    if download and not cached.exists():
        page = urllib.request.urlopen(item["source"], timeout=60).read().decode()
        assert "creativecommons.org/publicdomain/zero/1.0" in page, item["id"]
        partial = cached.with_suffix(".download")
        with urllib.request.urlopen(item["download"], timeout=90) as source, partial.open("wb") as out:
            shutil.copyfileobj(source, out)
        partial.replace(cached)
    source_hash = digest(cached)
    if "sourceSHA256" in item:
        assert source_hash == item["sourceSHA256"], "Changed source: " + item["id"]
    raw = subprocess.check_output([
        ffmpeg, "-v", "error", "-i", str(cached), "-af",
        f"atrim=start={item['start']}:duration={item['seconds'] + item['crossfade']},"
        "asetpts=PTS-STARTPTS,highpass=f=35,lowpass=f=10000,loudnorm=I=-25:TP=-8:LRA=9",
        "-ar", str(rate), "-ac", str(item["channels"]), "-f", "f32le", "-",
    ])
    values = np.frombuffer(raw, dtype="<f4").reshape(-1, item["channels"]).copy()
    count, blend = rate * item["seconds"], rate * item["crossfade"]
    assert len(values) >= count + blend, "Truncated source: " + item["id"]
    values = values[:count + blend]
    values -= values.mean(axis=0)
    values *= min(1, .48 / max(float(np.max(np.abs(values))), 1e-8))
    result = values[blend:].copy()
    phase = np.linspace(0, np.pi / 2, blend, dtype=np.float32)[:, None]
    result[-blend:] = values[-blend:] * np.cos(phase) + values[:blend] * np.sin(phase)
    write(PACK / (item["id"] + ".wav"), result, rate)
    item["sourceSHA256"] = source_hash


def prepare_noise(item, rate):
    count = rate * item["seconds"]
    # One FFT spans the entire ten minutes. Periodicity exists only at the
    # full-file boundary, so there is no reused short noise loop inside it.
    rng = np.random.default_rng(item["seed"])
    frequency = np.fft.rfftfreq(count, 1 / rate)
    spectrum = np.fft.rfft(rng.standard_normal(count).astype(np.float32))
    weight = np.maximum(frequency, 1) ** (-item["spectrumPower"] / 2)
    weight *= 1 / np.sqrt(1 + (35 / np.maximum(frequency, .01)) ** 4)
    weight *= 1 / np.sqrt(1 + (frequency / 10000) ** 8)
    spectrum *= weight
    spectrum[0] = 0
    values = np.fft.irfft(spectrum, n=count).astype(np.float32)
    values *= min(.08 / float(np.sqrt(np.mean(values ** 2))), .48 / float(np.max(np.abs(values))))
    write(PACK / (item["id"] + ".wav"), values[:, None], rate)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--verify", action="store_true", help="Audit existing outputs without rebuilding")
    parser.add_argument("--only", nargs="+", help="Rebuild/audit only the named sounds")
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    catalog = json.loads(MANIFEST.read_text(encoding="utf8"))
    if not args.verify:
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            import imageio_ffmpeg
            ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
        catalog["ffmpegVersion"] = subprocess.check_output([ffmpeg, "-version"], text=True).splitlines()[0]
        catalog["numpyVersion"] = np.__version__
        for item in catalog["recordings"]:
            if args.only and item["id"] not in args.only:
                continue
            prepare_recording(item, catalog["sampleRate"], ffmpeg, args.download)
            print("Prepared", item["id"], flush=True)
        for item in catalog["generated"]:
            if args.only and item["id"] not in args.only:
                continue
            prepare_noise(item, catalog["sampleRate"])
            print("Prepared", item["id"], flush=True)
    for item in catalog["recordings"] + catalog["generated"]:
        if args.only and item["id"] not in args.only:
            continue
        file = PACK / (item["id"] + ".wav")
        actual_hash = digest(file)
        if args.verify:
            assert item["outputSHA256"] == actual_hash, item["id"]
        else:
            item["outputSHA256"] = actual_hash
        item["analysis"] = audit(file)
        print(item["id"], json.dumps(item["analysis"]), flush=True)
    if not args.verify:
        MANIFEST.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    main()

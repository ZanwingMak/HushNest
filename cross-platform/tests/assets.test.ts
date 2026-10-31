import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { alarmSounds, sleepSounds } from '../src/core/model.ts';
import { stageAudio } from '../scripts/stage-audio.mjs';

test('all cross-platform built-in sounds are real PCM WAV resources', async () => {
  const ids = [...sleepSounds.filter(s => s[0] !== 'none'), ...alarmSounds].map(s => s[0]);
  for (const id of ids) {
    const isSleep = sleepSounds.some(sound => sound[0] === id);
    const resource = isSleep ? `../assets/sleep/${id}.wav` : `../../HushNest/Resources/${id}.wav`;
    const bytes = await readFile(new URL(resource, import.meta.url));
    assert.equal(bytes.subarray(0, 4).toString(), 'RIFF'); assert.equal(bytes.subarray(8, 12).toString(), 'WAVE'); assert.ok(bytes.length > 1000);
  }
  assert.equal(ids.length, 22);
});

function pcm(bytes: Buffer) {
  assert.equal(bytes.subarray(0, 4).toString(), 'RIFF');
  assert.equal(bytes.subarray(8, 12).toString(), 'WAVE');
  let channels = 0, rate = 0, offset = 12;
  while (offset + 8 <= bytes.length) {
    const type = bytes.subarray(offset, offset + 4).toString(), length = bytes.readUInt32LE(offset + 4);
    if (type === 'fmt ') {
      assert.equal(bytes.readUInt16LE(offset + 8), 1, 'linear PCM');
      channels = bytes.readUInt16LE(offset + 10); rate = bytes.readUInt32LE(offset + 12);
      assert.equal(bytes.readUInt16LE(offset + 22), 16);
    }
    if (type === 'data') {
      assert.ok(channels && rate && offset + 8 + length <= bytes.length);
      return { channels, rate, data: bytes.subarray(offset + 8, offset + 8 + length), seconds: length / channels / 2 / rate };
    }
    offset += 8 + length + length % 2;
  }
  throw new Error('Missing PCM data');
}

test('long sleep pack has continuous non-repeated audio with smooth, audible loop boundaries', async () => {
  const root = new URL('../assets/sleep/', import.meta.url);
  const manifest = JSON.parse(await readFile(new URL('FieldRecordings.json', root), 'utf8'));
  const expected = { rain: 600, ocean: 600, stream: 360, forest: 480, fireplace: 300, night: 480, brown: 600, pink: 600 };
  const items = [...manifest.recordings, ...manifest.generated];
  assert.deepEqual(items.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of items) {
    const bytes = await readFile(new URL(`${item.id}.wav`, root));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.outputSHA256, item.id);
    const { data, rate, channels, seconds } = pcm(bytes);
    assert.equal(seconds, expected[item.id]); assert.equal(rate, 24000); assert.equal(channels, item.channels);
    let peak = 0, energy = 0;
    for (let n = 0; n < data.length; n += 2) {
      const value = data.readInt16LE(n) / 32768; peak = Math.max(peak, Math.abs(value)); energy += value * value;
    }
    assert.ok(peak < .75 && Math.sqrt(energy / (data.length / 2)) > .005, `${item.id}: level and clipping`);
    let head = 0, tail = 0;
    for (let n = 0; n < rate * channels; n++) {
      head += (data.readInt16LE(n * 2) / 32768) ** 2;
      tail += (data.readInt16LE(data.length - (n + 1) * 2) / 32768) ** 2;
    }
    assert.ok(Math.abs(10 * Math.log10(head / tail)) < 6, `${item.id}: no level jump at wrap`);
    for (let channel = 0; channel < channels; channel++) {
      const seam = Math.abs(data.readInt16LE(channel * 2) - data.readInt16LE(data.length - channels * 2 + channel * 2));
      const deltas = [];
      for (let frame = 1; frame < rate * 20; frame += 8) {
        const at = (frame * channels + channel) * 2;
        deltas.push(Math.abs(data.readInt16LE(at) - data.readInt16LE(at - channels * 2)));
      }
      deltas.sort((a, b) => a - b);
      assert.ok(seam < Math.max(2, 2 * deltas[Math.floor(deltas.length * .99)]), `${item.id}: no wrap click`);
    }
    const blocks = new Set();
    for (let at = 0; at < data.length; at += rate * channels * 2) blocks.add(createHash('sha256').update(data.subarray(at, at + rate * channels * 2)).digest('hex'));
    assert.equal(blocks.size, seconds, `${item.id}: no tiled one-second segments`);
    assert.ok(item.analysis.minimumSecondRMS > .0001 && item.analysis.maxShortLagCorrelation < .4);
  }
});

test('both build paths stage the new sleep files, current manifest and original alarms', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'hushnest-audio-stage-'));
  try {
    await stageAudio(directory);
    for (const [id] of [...sleepSounds.filter(s => s[0] !== 'none'), ...alarmSounds]) {
      const source = sleepSounds.some(s => s[0] === id) ? `../assets/sleep/${id}.wav` : `../../HushNest/Resources/${id}.wav`;
      const expected = await readFile(new URL(source, import.meta.url));
      const actual = await readFile(path.join(directory, `${id}.wav`));
      assert.equal(createHash('sha256').update(actual).digest('hex'), createHash('sha256').update(expected).digest('hex'), id);
    }
    assert.equal(await readFile(path.join(directory, 'FieldRecordings.json'), 'utf8'), await readFile(new URL('../assets/sleep/FieldRecordings.json', import.meta.url), 'utf8'));
  } finally { await rm(directory, { recursive: true, force: true }); }
});
test('iOS field recordings retain their upstream manifest checksums', async () => {
  const root = new URL('../../HushNest/Resources/', import.meta.url);
  const manifest = JSON.parse(await readFile(new URL('FieldRecordings.json', root), 'utf8'));
  for (const item of manifest.recordings) {
    const extension = item.codec === 'aac' ? 'm4a' : 'wav';
    const bytes = await readFile(new URL(`${item.id}.${extension}`, root));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.outputSHA256, item.id);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { alarmSounds, sleepSounds } from '../src/core/model.ts';

test('all shared built-in sounds are real PCM WAV resources', async () => {
  const ids = [...sleepSounds.filter(s => s[0] !== 'none'), ...alarmSounds].map(s => s[0]);
  for (const id of ids) {
    const bytes = await readFile(new URL(`../../HushNest/Resources/${id}.wav`, import.meta.url));
    assert.equal(bytes.subarray(0, 4).toString(), 'RIFF'); assert.equal(bytes.subarray(8, 12).toString(), 'WAVE'); assert.ok(bytes.length > 1000);
  }
  assert.equal(ids.length, 22);
});
test('reused field recordings retain their source checksums', async () => {
  const root = new URL('../../HushNest/Resources/', import.meta.url);
  const manifest = JSON.parse(await readFile(new URL('FieldRecordings.json', root), 'utf8'));
  for (const item of manifest.recordings) {
    const bytes = await readFile(new URL(`${item.id}.wav`, root));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.outputSHA256, item.id);
  }
});

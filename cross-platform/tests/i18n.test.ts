import test from 'node:test';
import assert from 'node:assert/strict';
import { translator } from '../src/i18n.ts';
import { sleepSounds } from '../src/core/model.ts';
import type { Language } from '../src/core/model.ts';

test('all eight sleep descriptions remain translated without relying on removed iOS keys', () => {
  for (const language of ['zh-Hant', 'en', 'ja', 'ko', 'es'] as Language[]) {
    const t = translator(language, {});
    for (const [sound, , description] of sleepSounds.filter(sound => sound[0] !== 'none')) {
      assert.notEqual(t(description), description, `${language}: ${sound}`);
      assert.ok(t(description).length > 3);
    }
  }
});

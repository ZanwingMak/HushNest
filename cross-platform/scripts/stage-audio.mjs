import { access, copyFile, mkdir, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

export async function stageAudio(destination) {
  const pack = path.join(root, 'assets/sleep');
  const manifest = JSON.parse(await readFile(path.join(pack, 'FieldRecordings.json'), 'utf8'));
  const replacements = [...manifest.recordings, ...manifest.generated].map(item => `${item.id}.wav`);
  // Fail a partial checkout/build instead of silently falling back to short loops.
  if (replacements.length !== 8) throw new Error('Incomplete long sleep audio manifest');
  for (const file of replacements) await access(path.join(pack, file));
  await mkdir(destination, { recursive: true });
  const original = path.resolve(root, '../HushNest/Resources');
  for (const file of await readdir(original)) {
    if (file.endsWith('.wav') && !replacements.includes(file)) await copyFile(path.join(original, file), path.join(destination, file));
  }
  for (const file of [...replacements, 'FieldRecordings.json']) await copyFile(path.join(pack, file), path.join(destination, file));
}

import { copyFile, mkdir, readFile, writeFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import sharp from 'sharp';
const root = fileURLToPath(new URL('../', import.meta.url));
const resources = path.resolve(root, '../HushNest/Resources');
await mkdir(path.join(root, 'public/audio'), { recursive: true });
await mkdir(path.join(root, 'public/locales'), { recursive: true });
for (const file of await readdir(resources)) {
  if (file.endsWith('.wav')) await copyFile(path.join(resources, file), path.join(root, 'public/audio', file));
}
await copyFile(path.join(resources, 'FieldRecordings.json'), path.join(root, 'public/audio/FieldRecordings.json'));
await copyFile(path.join(resources, 'Assets.xcassets/AppIcon.appiconset/AppIcon.png'), path.join(root, 'public/icon.png'));
// The Android launcher derives from the same existing icon, at each native density.
const androidRes = path.join(root, 'android/app/src/main/res');
for (const [density, size] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) {
  const directory = path.join(androidRes, `mipmap-${density}`);
  await mkdir(directory, { recursive: true });
  for (const name of ['ic_launcher', 'ic_launcher_round']) await sharp(path.join(root, 'public/icon.png')).resize(size, size).png().toFile(path.join(directory, `${name}.png`));
  // Adaptive icon background supplies the full bleed; inset artwork stays inside the safe zone.
  const icon = await sharp(path.join(root, 'public/icon.png')).resize(size, size).png().toBuffer();
  await sharp({ create: { width: Math.round(size * 2.25), height: Math.round(size * 2.25), channels: 4, background: '#246b60' } }).composite([{ input: icon, gravity: 'centre' }]).png().toFile(path.join(directory, 'ic_launcher_foreground.png'));
}
const decode = (s) => s.replace(/\\(["\\nr])/g, (_, c) => ({ n: '\n', r: '\r' }[c] ?? c));
for (const language of ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'es']) {
  const source = await readFile(path.join(resources, `${language}.lproj/Localizable.strings`), 'utf8');
  const dictionary = {};
  for (const match of source.matchAll(/"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";/g)) dictionary[decode(match[1])] = decode(match[2]);
  await writeFile(path.join(root, `public/locales/${language}.json`), JSON.stringify(dictionary));
}
await copyFile(path.resolve(root, '../LICENSE'), path.join(root, 'public/LICENSE.txt'));
console.log('Prepared the original audio, icon, licenses and six translations.');

import { readdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const directory = new URL('../dist/', import.meta.url);
const files = [];
/** 收集离线界面文件，音频按需独立缓存。 */
async function scan(prefix = '') {
  for (const entry of await readdir(new URL(prefix, directory), { withFileTypes: true })) {
    const file = `${prefix}${entry.name}`;
    if (entry.isDirectory()) { if (entry.name !== 'audio') await scan(`${file}/`); }
    else if (file !== 'sw.js') files.push(`./${file}`);
  }
}
await scan();
// Version audio separately so an upgrade cannot serve the previous short loops.
const audioHash = createHash('sha256');
for (const file of (await readdir(new URL('audio/', directory))).sort()) {
  audioHash.update(file); audioHash.update(await readFile(new URL(`audio/${file}`, directory)));
}
const audioCache = `hushnest-audio-${audioHash.digest('hex').slice(0, 12)}`;
const runtime = await readFile(new URL('./service-worker-runtime.js', import.meta.url), 'utf8');
const hash = createHash('sha256').update(runtime); for (const file of files) hash.update(await readFile(new URL(file, directory)));
hash.update(audioCache);
const version = `hushnest-${hash.digest('hex').slice(0, 12)}`;
await writeFile(new URL('sw.js', directory), `
const CACHE = ${JSON.stringify(version)};
const AUDIO_CACHE = ${JSON.stringify(audioCache)};
const FILES = ${JSON.stringify(files)};
${runtime}
`);
console.log(`Created offline shell (${files.length} files); audio is cached after first use.`);

import { readdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const directory = new URL('../dist/', import.meta.url);
const files = [];
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
const hash = createHash('sha256'); for (const file of files) hash.update(await readFile(new URL(file, directory)));
hash.update(audioCache);
const version = `hushnest-${hash.digest('hex').slice(0, 12)}`;
await writeFile(new URL('sw.js', directory), `
const CACHE = ${JSON.stringify(version)};
const AUDIO_CACHE = ${JSON.stringify(audioCache)};
const FILES = ${JSON.stringify(files)};
self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(FILES))); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('hushnest-') && k !== CACHE && k !== AUDIO_CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (event.request.mode === 'navigate') {
    event.respondWith(caches.match(new URL('index.html', self.registration.scope).href).then(cached => cached || fetch(event.request))); return;
  }
  if (url.pathname.endsWith('.wav')) {
    event.respondWith((async () => {
      const cache = await caches.open(AUDIO_CACHE);
      const key = new Request(url.href); let full = await cache.match(key);
      if (!full) {
        // Always cache the complete file, even when the player requests a byte range.
        full = await fetch(key); if (!full.ok) return full;
        await cache.put(key, full.clone()).catch(() => {});
      }
      const range = event.request.headers.get('range');
      if (!range) return full;
      const bytes = await full.arrayBuffer();
      const match = /^bytes=(\\d+)-(\\d*)$/.exec(range);
      if (!match) return new Response(null, { status: 416 });
      const start = Number(match[1]), end = match[2] ? Math.min(Number(match[2]), bytes.byteLength - 1) : bytes.byteLength - 1;
      if (start > end || start >= bytes.byteLength) return new Response(null, { status: 416 });
      return new Response(bytes.slice(start, end + 1), { status: 206, headers: { 'Content-Type': 'audio/wav', 'Content-Range': 'bytes ' + start + '-' + end + '/' + bytes.byteLength, 'Content-Length': String(end - start + 1), 'Accept-Ranges': 'bytes' } });
    })()); return;
  }
  event.respondWith(caches.match(event.request).then(cached => cached || fetch(event.request)));
});
`);
console.log(`Created offline shell (${files.length} files); audio is cached after first use.`);

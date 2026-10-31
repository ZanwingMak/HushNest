import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const root = path.resolve(fileURLToPath(new URL('../dist/', import.meta.url)));
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.wav': 'audio/wav', '.webmanifest': 'application/manifest+json' };
const server = createServer(async (request, response) => {
  const route = new URL(request.url, 'http://localhost').pathname;
  const file = path.resolve(root, `.${route === '/' ? '/index.html' : decodeURIComponent(route)}`);
  if (!file.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
  try { const bytes = await readFile(file); response.setHeader('Content-Type', mime[path.extname(file)] || 'text/plain'); response.end(bytes); }
  catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch();
try {
  const context = await browser.newContext({ locale: 'zh-CN' }); const page = await context.newPage();
  const origin = `http://127.0.0.1:${server.address().port}`;
  await page.goto(origin);
  // Simulate audio cached by the previous release before activation finishes.
  await page.evaluate(async () => {
    const old = await caches.open('hushnest-audio-v1');
    await old.put('./audio/rain.wav', new Response('obsolete short rain'));
  });
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, { timeout: 15000 }); await page.reload();
  await page.waitForFunction(() => !!navigator.serviceWorker.controller);
  // If activation raced the fixture, a fresh update activation is unnecessary:
  // the current worker must still use its own versioned cache, never v1.
  const rain = await page.evaluate(async () => {
    const response = await fetch('./audio/rain.wav', { headers: { Range: 'bytes=0-43' } });
    const bytes = await response.arrayBuffer(), view = new DataView(bytes);
    return { status: response.status, seconds: view.getUint32(40, true) / view.getUint32(28, true), header: new TextDecoder().decode(bytes.slice(0, 4)) };
  });
  assert.deepEqual(rain, { status: 206, seconds: 600, header: 'RIFF' });
  const online = await page.evaluate(async () => {
    const response = await fetch('./audio/dawn.wav', { headers: { Range: 'bytes=0-43' } });
    return { status: response.status, length: (await response.arrayBuffer()).byteLength };
  });
  assert.deepEqual(online, { status: 206, length: 44 });
  await context.setOffline(true); await page.reload();
  await page.getByRole('heading', { name: '好好休息.' }).waitFor();
  const offline = await page.evaluate(async () => {
    const response = await fetch('./audio/dawn.wav', { headers: { Range: 'bytes=0-43' } });
    const bytes = await response.arrayBuffer();
    return { status: response.status, length: bytes.byteLength, header: new TextDecoder().decode(bytes.slice(0, 4)) };
  });
  assert.deepEqual(offline, { status: 206, length: 44, header: 'RIFF' });
  const cachedRain = await page.evaluate(async () => {
    const response = await fetch('./audio/rain.wav', { headers: { Range: 'bytes=44-91' } });
    return { status: response.status, length: (await response.arrayBuffer()).byteLength };
  });
  assert.deepEqual(cachedRain, { status: 206, length: 48 });
  console.log(JSON.stringify({ ok: true, offlineShell: true, cachedAudioRange: offline }));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }

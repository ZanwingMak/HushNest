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
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, { timeout: 15000 }); await page.reload();
  await page.waitForFunction(() => !!navigator.serviceWorker.controller);
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
  console.log(JSON.stringify({ ok: true, offlineShell: true, cachedAudioRange: offline }));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }

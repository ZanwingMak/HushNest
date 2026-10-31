import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '../cross-platform/node_modules/playwright/index.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const site = path.join(root, 'build/site');
const output = path.join(root, 'build/site-qa');
const downloads = JSON.parse(await readFile(path.join(root, 'website/downloads.json'), 'utf8'));
const prefix = '/HushNest/';
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.wav': 'audio/wav', '.webmanifest': 'application/manifest+json' };
const server = createServer(async (request, response) => {
  const route = new URL(request.url, 'http://localhost').pathname;
  if (!route.startsWith(prefix)) { response.writeHead(404).end(); return; }
  const relative = decodeURIComponent(route.slice(prefix.length));
  const file = path.resolve(site, relative.endsWith('/') || relative === '' ? `${relative}index.html` : relative);
  if (!file.startsWith(site + path.sep)) { response.writeHead(403).end(); return; }
  try { const bytes = await readFile(file); response.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream'); response.end(bytes); }
  catch { response.writeHead(404).end(); }
});
await mkdir(output, { recursive: true });
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch();
try {
  const context = await browser.newContext({ locale: 'zh-CN', reducedMotion: 'reduce' });
  await context.addInitScript(() => { HTMLMediaElement.prototype.play = async function () {}; });
  const page = await context.newPage();
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  const origin = `http://127.0.0.1:${server.address().port}`;
  await page.goto(origin + prefix);
  assert.equal(await page.locator('[data-platform]').count(), 5);
  const releaseBase = `https://github.com/${downloads.repository}/releases/download/${downloads.release.tag}/`;
  const expected = {
    windows: [releaseBase + downloads.release.assets.windows, releaseBase + downloads.release.assets.windowsPortable],
    macos: [releaseBase + downloads.release.assets.macos],
    android: [releaseBase + downloads.release.assets.android],
    ios: [downloads.ios.testFlight, `https://github.com/${downloads.repository}/releases/download/${downloads.ios.tag}/${downloads.ios.ipa}`],
    web: ['app/', releaseBase + downloads.release.assets.web],
  };
  const readme = await readFile(path.join(root, 'README.md'), 'utf8');
  const guide = await readFile(path.join(root, 'docs/DOWNLOADS.md'), 'utf8');
  for (const [platform, urls] of Object.entries(expected)) {
    const hrefs = await page.locator(`[data-platform="${platform}"] a`).evaluateAll(links => links.map(link => link.getAttribute('href')));
    for (const url of urls) {
      assert.ok(hrefs.includes(url), `${platform}: missing official download`);
      if (url !== 'app/') { assert.ok(readme.includes(url)); assert.ok(guide.includes(url)); }
    }
  }
  await page.getByRole('button', { name: '45 分', exact: true }).click();
  assert.equal(await page.locator('#duration-display').textContent(), '45');
  await page.getByRole('button', { name: '海湾', exact: true }).click();
  assert.equal(await page.getByRole('button', { name: '海湾', exact: true }).getAttribute('aria-pressed'), 'true');
  await page.getByRole('button', { name: '松林', exact: true }).click();
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    const dimensions = await page.evaluate(() => ({ actual: document.documentElement.scrollWidth, viewport: innerWidth }));
    assert.ok(dimensions.actual <= dimensions.viewport, `Horizontal overflow at ${width}: ${JSON.stringify(dimensions)}`);
    if (width === 390 || width === 1440) await page.locator('#downloads').screenshot({ path: path.join(output, width === 390 ? 'mobile-downloads.png' : 'desktop-downloads.png') });
  }
  await page.goto(origin + prefix + 'privacy.html');
  assert.match(await page.locator('main').innerText(), /Web/);
  await page.goto(origin + prefix + 'terms.html');
  assert.match(await page.locator('main').innerText(), /调试签名/);
  await page.goto(origin + prefix + 'app/');
  await page.getByRole('heading', { name: '好好休息.' }).waitFor();
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, { timeout: 15000 });
  const app = await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.getRegistration();
    const manifest = await (await fetch('./manifest.webmanifest')).json();
    const response = await fetch('./audio/rain.wav', { headers: { Range: 'bytes=0-43' } });
    const bytes = await response.arrayBuffer(), header = new DataView(bytes);
    return { scope: new URL(registration.scope).pathname, start: new URL(manifest.start_url, location.href).pathname, status: response.status, seconds: header.getUint32(40, true) / header.getUint32(28, true) };
  });
  assert.deepEqual(app, { scope: prefix + 'app/', start: prefix + 'app/', status: 206, seconds: 600 });
  await context.setOffline(true); await page.reload();
  await page.getByRole('heading', { name: '好好休息.' }).waitFor();
  const cached = await page.evaluate(async () => {
    const response = await fetch('./audio/rain.wav', { headers: { Range: 'bytes=44-91' } });
    return { status: response.status, bytes: (await response.arrayBuffer()).byteLength };
  });
  assert.deepEqual(cached, { status: 206, bytes: 48 });
  await context.setOffline(false);
  const landing = await context.newPage(); await landing.goto(origin + prefix);
  assert.equal(await landing.evaluate(() => navigator.serviceWorker.controller === null), true, 'The Web app must not control the website');
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ ok: true, platforms: 5, viewports: [320, 390, 768, 1440], matchingReadmeLinks: true, subpathApp: app, offlineRange: cached, websiteOutsideAppScope: true }));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }

import { _electron as electron } from 'playwright';
import electronPath from 'electron';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
const profile = await mkdtemp(path.join(tmpdir(), 'hushnest-smoke-'));
const executablePath = process.env.HUSHNEST_PACKAGED_EXE || electronPath;
const args = process.env.HUSHNEST_PACKAGED_EXE ? [`--user-data-dir=${profile}`] : ['.', `--user-data-dir=${profile}`];
const application = await electron.launch({ executablePath, args, env: { ...process.env, HUSHNEST_SMOKE: '1' }, timeout: 30000 });
try {
  const page = await application.firstWindow();
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.waitForFunction(() => window.hushnestDesktop && window.hushnestAudio);
  assert.equal(await page.title(), '耳憩 HushNest');
  const result = await page.evaluate(async () => {
    const route = await window.hushnestDesktop.route();
    const manifest = await fetch('./audio/FieldRecordings.json').then(r => r.json());
    const locale = await fetch('./locales/en.json').then(r => r.json());
    let rejected = false;
    try { await window.hushnestAudio.play({ sound: '../../not-a-sound', volume: 0, alarm: false, preview: false }); }
    catch { rejected = true; }
    let pathRejected = false;
    try { await window.hushnestAudio.cacheMedia({ id: '../outside', name: 'x', bytes: new ArrayBuffer(1) }); }
    catch { pathRejected = true; }
    await window.hushnestDesktop.keepAwake(true); await window.hushnestDesktop.keepAwake(false);
    await window.hushnestAudio.stop();
    return { route, recordings: manifest.recordings.length, translated: locale['好好休息'], rejected, pathRejected, nodeExposed: typeof window.require !== 'undefined' };
  });
  assert.equal(typeof result.route.connected, 'boolean'); assert.equal(result.recordings, 6);
  assert.ok(result.translated); assert.ok(result.rejected); assert.ok(result.pathRejected); assert.equal(result.nodeExposed, false);
  const security = await application.evaluate(({ BrowserWindow }) => {
    const prefs = BrowserWindow.getAllWindows()[0].webContents.getLastWebPreferences();
    return { sandbox: prefs.sandbox, contextIsolation: prefs.contextIsolation, nodeIntegration: prefs.nodeIntegration };
  });
  assert.deepEqual(security, { sandbox: true, contextIsolation: true, nodeIntegration: false });
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ ok: true, mode: process.env.HUSHNEST_PACKAGED_EXE ? 'packaged' : 'development', ...result, security }));
} finally { await application.close(); }

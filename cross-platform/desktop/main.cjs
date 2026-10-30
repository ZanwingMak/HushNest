const { app, BrowserWindow, ipcMain, powerSaveBlocker, powerMonitor, Tray, Menu, nativeImage, dialog, protocol, net } = require('electron');
const { spawn } = require('node:child_process');
const { createInterface } = require('node:readline');
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

protocol.registerSchemesAsPrivileged([{ scheme: 'hushnest', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } }]);
let window, tray, helper, blocker, quit = false, sequence = 0;
const pending = new Map();
const dist = path.join(__dirname, '../dist');
const safeSound = /^(rain|ocean|stream|forest|fireplace|night|brown|pink|dawn|bell|orbit|piano|marimba|harp|bamboo|aurora|classic|twinbell|digital|pulse|beacon|reveille|custom:[\da-f-]{36})$/;
function guard(action, data = {}) {
  return new Promise((resolve, reject) => {
    if (!helper || helper.killed || !helper.stdin.writable) return reject(new Error('audio-service-unavailable'));
    const id = ++sequence;
    const timeout = setTimeout(() => { pending.delete(id); reject(new Error('audio-service-timeout')); }, 10000);
    pending.set(id, { resolve, reject, timeout });
    helper.stdin.write(JSON.stringify({ id, action, ...data }) + '\n');
  });
}
function startHelper() {
  const executable = app.isPackaged ? path.join(process.resourcesPath, 'audio-guard/AudioGuard.exe') : path.join(__dirname, 'bin/AudioGuard.exe');
  helper = spawn(executable, [app.isPackaged ? path.join(process.resourcesPath, 'audio') : path.join(dist, 'audio'), path.join(app.getPath('userData'), 'media')], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  createInterface({ input: helper.stdout }).on('line', line => {
    try {
      const data = JSON.parse(line);
      if (data.eventType === 'routeLost') { window?.webContents.send('hushnest:routeLost'); return; }
      const command = pending.get(data.id); if (!command) return;
      pending.delete(data.id); clearTimeout(command.timeout);
      if (data.error) command.reject(new Error(data.error)); else command.resolve(data.result);
    } catch { }
  });
  const failed = () => {
    for (const command of pending.values()) { clearTimeout(command.timeout); command.reject(new Error('audio-service-stopped')); }
    pending.clear(); window?.webContents.send('hushnest:routeLost');
  };
  helper.on('error', failed); helper.on('exit', failed);
  helper.stderr.on('data', () => {});
}
function sender(event) {
  if (!window || event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame || !event.senderFrame.url.startsWith('hushnest://app/')) throw new Error('untrusted-sender');
}
function handle(name, callback) { ipcMain.handle(`hushnest:${name}`, (event, ...args) => { sender(event); return callback(...args); }); }
function mediaPath(id) {
  if (typeof id !== 'string' || !/^[\da-f-]{36}$/.test(id)) throw new Error('invalid-id');
  return path.join(app.getPath('userData'), 'media', `${id}.media`);
}
function show() { window?.show(); window?.focus(); }
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', show);
  app.whenReady().then(async () => {
    protocol.handle('hushnest', request => {
      const url = new URL(request.url);
      if (url.hostname !== 'app') return new Response('', { status: 403 });
      const relative = decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname);
      const root = app.isPackaged && relative.startsWith('/audio/') ? path.join(process.resourcesPath, 'audio') : dist;
      const file = path.resolve(root, `.${root === dist ? relative : relative.slice(6)}`);
      if (!file.startsWith(root + path.sep)) return new Response('', { status: 403 });
      return net.fetch(pathToFileURL(file).href);
    });
    await fs.mkdir(path.join(app.getPath('userData'), 'media'), { recursive: true });
    startHelper();
    window = new BrowserWindow({ show: process.env.HUSHNEST_SMOKE !== '1', width: 1280, height: 900, minWidth: 420, minHeight: 650, title: '耳憩 HushNest', backgroundColor: '#f5f5f0',
      icon: path.join(dist, 'icon.png'), webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false, backgroundThrottling: false, spellcheck: false } });
    window.removeMenu();
    window.webContents.session.setPermissionRequestHandler((_web, _permission, callback) => callback(false));
    window.webContents.session.setPermissionCheckHandler(() => false);
    // External pages are not given a renderer or OS bridge. Product links open in a sandboxed window.
    window.webContents.setWindowOpenHandler(({ url }) => {
      if (!url.startsWith('https://github.com/ZanwingMak/HushNest') && !url.startsWith('hushnest://app/audio/FieldRecordings.json') && !url.startsWith('hushnest://app/LICENSE.txt')) return { action: 'deny' };
      return { action: 'allow', overrideBrowserWindowOptions: { webPreferences: { sandbox: true, nodeIntegration: false, contextIsolation: true } } };
    });
    window.webContents.on('will-navigate', (event, url) => { if (!url.startsWith('hushnest://app/')) event.preventDefault(); });
    window.webContents.on('render-process-gone', () => { void guard('stop').catch(() => {}); if (blocker !== undefined && powerSaveBlocker.isStarted(blocker)) powerSaveBlocker.stop(blocker); blocker = undefined; });
    window.on('close', event => { if (!quit && blocker !== undefined && powerSaveBlocker.isStarted(blocker)) { event.preventDefault(); window.hide(); } });
    tray = new Tray(nativeImage.createFromPath(path.join(dist, 'icon.png')).resize({ width: 20, height: 20 })); tray.setToolTip('HushNest');
    tray.setContextMenu(Menu.buildFromTemplate([{ label: '打开 / Open HushNest', click: show }, { label: '退出 / Quit', click: async () => {
      if (blocker !== undefined && powerSaveBlocker.isStarted(blocker)) {
        const result = await dialog.showMessageBox(window, { type: 'question', message: '退出会停止当前提醒。Quit and stop the current rest?', buttons: ['继续休息 / Keep resting', '退出 / Quit'], defaultId: 0, cancelId: 0 });
        if (result.response !== 1) return;
      }
      quit = true; app.quit();
    } }])); tray.on('double-click', show);
    handle('route', () => guard('route'));
    handle('play', data => {
      if (!data || !safeSound.test(data.sound) || !Number.isFinite(data.volume) || data.volume < 0 || data.volume > 1) throw new Error('invalid-audio');
      return guard('play', { sound: data.sound, volume: data.volume, alarm: data.alarm === true, preview: data.preview === true });
    });
    handle('stop', () => guard('stop'));
    handle('volume', value => { if (!Number.isFinite(value) || value < 0 || value > 1) throw new Error('invalid-volume'); return guard('volume', { value }); });
    handle('awake', active => {
      if (active === true && blocker === undefined) blocker = powerSaveBlocker.start('prevent-app-suspension');
      if (active !== true && blocker !== undefined) { if (powerSaveBlocker.isStarted(blocker)) powerSaveBlocker.stop(blocker); blocker = undefined; }
    });
    handle('cache', async data => {
      const file = mediaPath(data?.id);
      if (!(data.bytes instanceof ArrayBuffer) || data.bytes.byteLength > 200 * 1024 * 1024 || !data.bytes.byteLength) throw new Error('invalid-media');
      try { if ((await fs.stat(file)).size === data.bytes.byteLength) return; } catch { }
      await fs.writeFile(file, Buffer.from(data.bytes));
    });
    handle('delete', async id => { await fs.rm(mediaPath(id), { force: true }); });
    powerMonitor.on('suspend', () => { void guard('stop').catch(() => {}); window?.webContents.send('hushnest:suspend'); });
    await window.loadURL('hushnest://app/');
  }).catch(error => { dialog.showErrorBox('HushNest', String(error)); app.quit(); });
  app.on('before-quit', () => { quit = true; helper?.stdin.end(); helper?.kill(); if (blocker !== undefined && powerSaveBlocker.isStarted(blocker)) powerSaveBlocker.stop(blocker); });
  app.on('window-all-closed', () => app.quit());
}

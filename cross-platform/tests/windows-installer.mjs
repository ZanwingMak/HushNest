import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { access, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

// NSIS registers the app and its Start menu shortcut. Keep these tests on a
// disposable runner so a developer's actual installation is never replaced.
assert.equal(process.platform, 'win32');
assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Run installer tests on a disposable Windows Actions runner');
const config = JSON.parse(await readFile('mygo.json', 'utf8'));
const packaged = path.resolve('release/mygo-native/windows-amd64');
const installer = path.join(packaged, `hushnest-setup-${config.version}-amd64.exe`);
const directory = await mkdtemp(path.join(tmpdir(), 'hushnest-installer-'));
const installed = path.join(directory, 'HushNest 安装测试');
const marker = path.join(installed, 'upgrade-preservation.txt');
function run(executable, args, env = process.env) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { windowsHide: true, windowsVerbatimArguments: executable === installer, env, stdio: 'inherit', timeout: 90000 });
    child.once('error', reject);
    child.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`Installer validation failed: ${path.basename(executable)} exit ${code}, signal ${signal}`)));
  });
}
const files = ['HushNest.exe', 'HushNest.LICENSE.txt', 'MyGo.LICENSE.txt', 'audio/dawn.wav', 'audio/FieldRecordings.json', 'audio-guard/AudioGuard.exe', ...['rain', 'ocean', 'stream', 'forest', 'fireplace', 'night', 'brown', 'pink'].map(id => `audio/${id}.wav`)];
const hash = async file => createHash('sha256').update(await readFile(file)).digest('hex');
for (const pass of ['install', 'upgrade']) {
  // NSIS requires /D= to be the final, unquoted argument, including spaces.
  await run(installer, ['/S', `/D=${installed}`]);
  for (const file of files) {
    assert.equal(await hash(path.join(installed, file)), await hash(path.join(packaged, file)), `${pass}: ${file}`);
  }
  await access(path.join(installed, 'HushNest.LICENSE.txt'), constants.W_OK);
  if (pass === 'install') await writeFile(marker, 'preserve on upgrade', 'utf8');
  else assert.equal(await readFile(marker, 'utf8'), 'preserve on upgrade');
}
await run(process.execPath, ['tests/desktop-smoke.mjs'], { ...process.env, HUSHNEST_PACKAGED_EXE: path.join(installed, 'HushNest.exe') });
console.log('NSIS install, upgrade, writable license, Unicode/space path and installed native application: passed.');

import { spawn, spawnSync } from 'node:child_process';
import { copyFile, cp, mkdir, mkdtemp, readdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import sharp from 'sharp';

const root = fileURLToPath(new URL('../', import.meta.url));
const mode = process.argv[2] || 'build';
const target = process.argv[3] || (process.platform === 'win32' ? 'windows' : 'macos');
const go = process.env.HUSHNEST_GO || 'go';
const env = { ...process.env, PATH: `${path.dirname(go)}${path.delimiter}${process.env.PATH}`, CGO_ENABLED: '0' };
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, env, stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})`);
}
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const mygo = path.join(root, 'node_modules/mygo-cli/bin/mygo.js');
const shell = process.platform === 'win32';
run(process.execPath, [mygo, 'generate']);
if (process.env.npm_execpath) run(process.execPath, [process.env.npm_execpath, 'run', 'build']);
else run(npm, ['run', 'build'], { shell });
await mkdir(path.join(root, 'desktop/frontend'), { recursive: true });
for (const entry of await readdir(path.join(root, 'dist'), { withFileTypes: true })) {
  if (entry.name === 'audio' || entry.name === 'sw.js') continue;
  await cp(path.join(root, 'dist', entry.name), path.join(root, 'desktop/frontend', entry.name), { recursive: true });
}
await mkdir(path.join(root, 'desktop/frontend/audio'), { recursive: true });
await copyFile(path.join(root, 'dist/audio/FieldRecordings.json'), path.join(root, 'desktop/frontend/audio/FieldRecordings.json'));
await mkdir(path.join(root, 'resources'), { recursive: true });
await mkdir(path.join(root, 'desktop/bin'), { recursive: true });
await sharp(path.join(root, 'public/icon.png')).resize(32, 32).png().toFile(path.join(root, 'resources/tray.png'));
await copyFile(path.join(root, 'THIRD_PARTY_NOTICES.md'), path.join(root, 'resources/THIRD_PARTY_NOTICES.md'));
await copyFile(path.join(root, 'desktop/licenses/MyGo.LICENSE.txt'), path.join(root, 'resources/MyGo.LICENSE.txt'));
let platform;
if (target === 'windows') {
  if (process.platform !== 'win32') throw new Error('Build the Windows audio helper on Windows.');
  run(process.execPath, ['scripts/build-windows-helper.mjs']);
  const destination = path.join(root, 'resources/windows/audio-guard');
  await mkdir(destination, { recursive: true });
  await copyFile(path.join(root, 'desktop/bin/AudioGuard.exe'), path.join(destination, 'AudioGuard.exe'));
  await copyFile(path.join(root, 'desktop/bin/NAudio.LICENSE.txt'), path.join(destination, 'NAudio.LICENSE.txt'));
  platform = 'windows/amd64';
} else {
  if (process.platform !== 'darwin') throw new Error('macOS packaging and the audio helper require macOS and Xcode.');
  const destination = path.join(root, 'resources/darwin'); await mkdir(destination, { recursive: true });
  const sdk = spawnSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).stdout.trim();
  for (const arch of ['arm64', 'x86_64']) run('xcrun', ['swiftc', '-O', '-swift-version', '5', '-sdk', sdk, '-target', `${arch}-apple-macos12.0`, 'desktop/macos/AudioGuard.swift', '-o', `desktop/bin/AudioGuard-${arch}`]);
  run('xcrun', ['lipo', '-create', 'desktop/bin/AudioGuard-arm64', 'desktop/bin/AudioGuard-x86_64', '-output', 'resources/darwin/AudioGuard']);
  platform = 'darwin/universal';
}
// Package on the OS temporary filesystem: some Windows workspace drives reject
// MyGo's final atomic directory rename. Copy completed artifacts to the workspace.
const buildOutput = await mkdtemp(path.join(tmpdir(), 'hushnest-mygo-build-'));
const args = ['build', '-platform', platform, '-skip-build-command', '-o', buildOutput];
run(process.execPath, [mygo, ...args]);
await mkdir(path.join(root, 'release/mygo'), { recursive: true });
for (const entry of await readdir(buildOutput, { withFileTypes: true })) {
  await cp(path.join(buildOutput, entry.name), path.join(root, 'release/mygo', entry.name), { recursive: true });
}
if (mode === 'dev') {
  const executable = target === 'windows' ? 'release/mygo/windows-amd64/HushNest.exe' : 'release/mygo/darwin-universal/HushNest.app/Contents/MacOS/HushNest';
  const child = spawn(path.join(root, executable), [], { cwd: root, env, stdio: 'inherit', windowsHide: true });
  child.on('exit', code => process.exit(code ?? 1));
} else await writeFile(path.join(root, 'release/mygo/BUILD.txt'), `HushNest MyGo 0.7.3\nTarget: ${platform}\n`);

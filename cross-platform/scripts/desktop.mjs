import { spawn, spawnSync } from 'node:child_process';
import { chmod, copyFile, cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
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
const mygo = path.join(root, 'node_modules/mygo-cli/bin/mygo.js');
// Native desktop builds only stage Go UI assets, never the React frontend.
const original = path.resolve(root, '../HushNest/Resources');
await mkdir(path.join(root, 'resources/audio'), { recursive: true });
await mkdir(path.join(root, 'resources/locales'), { recursive: true });
for (const file of await readdir(original)) {
  if (file.endsWith('.wav') || file === 'FieldRecordings.json') await copyFile(path.join(original, file), path.join(root, 'resources/audio', file));
}
const decode = s => s.replace(/\\(["\\nr])/g, (_, c) => ({ n: '\n', r: '\r' }[c] ?? c));
for (const language of ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'es']) {
  const source = await readFile(path.join(original, `${language}.lproj/Localizable.strings`), 'utf8');
  const dictionary = {};
  for (const match of source.matchAll(/"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";/g)) dictionary[decode(match[1])] = decode(match[2]);
  await writeFile(path.join(root, 'resources/locales', `${language}.json`), JSON.stringify(dictionary));
}
await mkdir(path.join(root, 'desktop/bin'), { recursive: true });
await copyFile(path.join(original, 'Assets.xcassets/AppIcon.appiconset/AppIcon.png'), path.join(root, 'resources/icon.png'));
await sharp(path.join(root, 'resources/icon.png')).resize(32, 32).png().toFile(path.join(root, 'resources/tray.png'));
await copyFile(path.join(root, 'THIRD_PARTY_NOTICES.md'), path.join(root, 'resources/THIRD_PARTY_NOTICES.md'));
await copyFile(path.join(root, 'desktop/licenses/MyGo.LICENSE.txt'), path.join(root, 'resources/MyGo.LICENSE.txt'));
await copyFile(path.resolve(root, '../LICENSE'), path.join(root, 'resources/HushNest.LICENSE.txt'));
run(go, ['mod', 'download']);
const moduleCache = spawnSync(go, ['env', 'GOMODCACHE'], { cwd: root, env, encoding: 'utf8' });
if (moduleCache.status !== 0) throw new Error('Could not locate the pinned Go module licenses.');
await mkdir(path.join(root, 'resources/licenses'), { recursive: true });
for (const [module, filename] of [
  ['github.com/ebitengine/purego@v0.11.1', 'purego'],
  ['github.com/go-text/typesetting@v0.3.5', 'typesetting'],
  ['golang.org/x/image@v0.46.0', 'x-image'],
  ['golang.org/x/net@v0.59.0', 'x-net'],
  ['golang.org/x/text@v0.43.0', 'x-text'],
]) {
  const destination = path.join(root, 'resources/licenses', `${filename}.LICENSE.txt`);
  // Go's module cache is read-only. CopyFile preserves that Windows attribute,
  // so write fresh bytes and normalize any previously staged license instead.
  await chmod(destination, 0o644).catch(error => { if (error.code !== 'ENOENT') throw error; });
  await writeFile(destination, await readFile(path.join(moduleCache.stdout.trim(), module, 'LICENSE')));
}
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
await mkdir(path.join(root, 'release/mygo-native'), { recursive: true });
for (const entry of await readdir(buildOutput, { withFileTypes: true })) {
  const outputRoot = path.resolve(root, 'release/mygo-native');
  const destination = path.resolve(outputRoot, entry.name);
  if (path.dirname(destination) !== outputRoot || entry.name !== platform.replace('/', '-')) throw new Error(`Unexpected desktop output: ${entry.name}`);
  // Replace only this validated platform's generated output. This also removes
  // obsolete resources and read-only licenses from earlier development builds.
  await rm(destination, { recursive: entry.isDirectory(), force: true });
  await cp(path.join(buildOutput, entry.name), destination, { recursive: true });
}
const resolvedBuild = path.resolve(buildOutput);
if (path.dirname(resolvedBuild) === path.resolve(tmpdir()) && /^hushnest-mygo-build-/.test(path.basename(resolvedBuild))) {
  await rm(resolvedBuild, { recursive: true, force: true }).catch(() => {});
}
console.log(`Native desktop artifacts: ${path.join(root, 'release/mygo-native', platform.replace('/', '-'))}`);
if (mode === 'dev') {
  const executable = target === 'windows' ? 'release/mygo-native/windows-amd64/HushNest.exe' : 'release/mygo-native/darwin-universal/HushNest.app/Contents/MacOS/HushNest';
  const child = spawn(path.join(root, executable), [], { cwd: root, env, stdio: 'inherit', windowsHide: true });
  child.on('exit', code => process.exit(code ?? 1));
} else await writeFile(path.join(root, 'release/mygo-native/BUILD.txt'), `HushNest 0.2.0 / MyGo 0.7.3 native Go UI\nTarget: ${platform}\nNo HTML, JavaScript or WebView\n`);

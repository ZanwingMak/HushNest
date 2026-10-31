import { spawn } from 'node:child_process';
import { cp, mkdir, mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const directory = await mkdtemp(path.join(tmpdir(), 'hushnest-mygo-smoke-'));
const report = path.join(directory, 'report.json');
const defaultExecutable = process.platform === 'darwin' ? 'release/mygo-native/darwin-universal/HushNest.app/Contents/MacOS/HushNest' : 'release/mygo-native/windows-amd64/HushNest.exe';
const executable = path.resolve(process.env.HUSHNEST_PACKAGED_EXE || defaultExecutable);
const child = spawn(executable, [], { windowsHide: true, env: { ...process.env, HUSHNEST_DATA_DIR: path.join(directory, 'profile'), HUSHNEST_SMOKE: report }, stdio: ['ignore', 'pipe', 'pipe'] });
let output = ''; child.stdout.on('data', bytes => { output += bytes; }); child.stderr.on('data', bytes => { output += bytes; });
const timeout = setTimeout(() => { child.kill(); }, 60000);
try {
  const code = await new Promise((resolve, reject) => { child.on('exit', resolve); child.on('error', reject); });
  assert.equal(code, 0, output);
  const result = JSON.parse(await readFile(report, 'utf8'));
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(result.framework, 'MyGo'); assert.equal(result.nativeUI, true); assert.equal(result.webview, false);
  assert.equal(result.renderedPages, 4); assert.equal(result.languages, 6); assert.equal(result.noWebAssets, true);
  assert.equal(result.invalidPath, true); assert.equal(result.invalidSound, true);
  assert.equal(result.nativeImport, true); assert.equal(result.deletedMedia, true);
  assert.equal(result.staleConfirmationRejected, true); assert.equal(result.manualConfirmation, true);
  const qa = path.resolve('release/mygo-native/qa', process.platform);
  await mkdir(qa, { recursive: true });
  await cp(report, path.join(qa, 'report.json'));
  const screenshots = new Set();
  for (const page of ['rest', 'library', 'history', 'settings']) {
    const file = path.join(directory, `native-${page}.png`);
    screenshots.add(createHash('sha256').update(await readFile(file)).digest('hex'));
    await cp(file, path.join(qa, `${page}.png`));
  }
  assert.equal(screenshots.size, 4, 'Each native page must render a distinct frame');
  console.log(JSON.stringify(result));
} finally { clearTimeout(timeout); if (child.exitCode === null) child.kill(); }

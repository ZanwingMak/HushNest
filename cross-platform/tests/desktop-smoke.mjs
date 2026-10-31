import { spawn } from 'node:child_process';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
const directory = await mkdtemp(path.join(tmpdir(), 'hushnest-mygo-smoke-'));
const report = path.join(directory, 'report.json');
const defaultExecutable = process.platform === 'darwin' ? 'release/mygo/darwin-universal/HushNest.app/Contents/MacOS/HushNest' : 'release/mygo/windows-amd64/HushNest.exe';
const executable = path.resolve(process.env.HUSHNEST_PACKAGED_EXE || defaultExecutable);
const child = spawn(executable, [], { windowsHide: true, env: { ...process.env, HUSHNEST_DATA_DIR: path.join(directory, 'profile'), HUSHNEST_SMOKE: report }, stdio: ['ignore', 'pipe', 'pipe'] });
let output = ''; child.stdout.on('data', bytes => { output += bytes; }); child.stderr.on('data', bytes => { output += bytes; });
const timeout = setTimeout(() => { child.kill(); }, 60000);
try {
  const code = await new Promise((resolve, reject) => { child.on('exit', resolve); child.on('error', reject); });
  assert.equal(code, 0, output);
  const result = JSON.parse(await readFile(report, 'utf8'));
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(result.framework, 'MyGo'); assert.equal(result.nodeExposed, false);
  assert.equal(result.recordings, 6); assert.equal(result.invalidPath, true); assert.equal(result.invalidSound, true);
  console.log(JSON.stringify(result));
} finally { clearTimeout(timeout); if (child.exitCode === null) child.kill(); }

// The verified Actions artifacts become durable public downloads. Published
// releases are immutable here; uploads/repairs are limited to our own draft.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cp, mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const config = JSON.parse(await readFile(path.join(root, 'website/downloads.json'), 'utf8'));
const { repository, release, ios } = config;
const apiRoot = `repos/${repository}`;
const input = path.join(root, 'build/release-input');
const output = path.join(root, 'build/multiplatform-release');
const proofName = 'HushNest-release-manifest.json';
const checksumName = 'SHA256SUMS.txt';
const mode = process.argv[2];

function command(program, args, options = {}) {
  const result = spawnSync(program, args, { cwd: root, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024, ...options });
  if (result.status !== 0) throw new Error(`${program} failed: ${result.stderr || result.error || result.status}`);
  return result.stdout;
}
function api(endpoint, method = 'GET', body) {
  const args = ['api', endpoint];
  if (method !== 'GET') args.push('--method', method);
  if (body !== undefined) args.push('--input', '-');
  const result = command('gh', args, body === undefined ? {} : { input: JSON.stringify(body) });
  return result.trim() ? JSON.parse(result) : null;
}
async function sha256(file) { return createHash('sha256').update(await readFile(file)).digest('hex'); }
function assetURL(name, tag = release.tag) { return `https://github.com/${repository}/releases/download/${tag}/${name}`; }
async function report(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) { const result = await report(file); if (result) return result; }
    else if (entry.name === 'report.json') return JSON.parse(await readFile(file, 'utf8'));
  }
}
async function verifyNative(name, platform) {
  const result = await report(path.join(input, name));
  if (!result?.ok || result.webview || !result.nativeUI || !result.noWebAssets || result.platform !== platform || result.alarmPreviews?.length !== 14 || result.sleepAudio?.length !== 16) throw new Error(`Missing native QA: ${platform}`);
}
function existingRelease() {
  const releases = api(`${apiRoot}/releases?per_page=100`);
  const tagged = releases.find(item => item.tag_name === release.tag);
  if (tagged) return tagged;
  // GitHub may give an unpublished draft an untagged-* URL until its tag
  // exists. Identify only our named draft for this exact verified source.
  return releases.filter(item => item.draft && item.name === release.name && item.target_commitish === release.sourceCommit)
    .sort((a, b) => b.assets.length - a.assets.length || b.id - a.id)[0];
}
async function verifiedExisting(item) {
  if (!item || item.target_commitish !== release.sourceCommit || !item.prerelease) return false;
  const marker = item.assets.find(asset => asset.name === proofName);
  if (!marker) return false;
  const proof = JSON.parse(command('gh', ['api', `${apiRoot}/releases/assets/${marker.id}`, '-H', 'Accept: application/octet-stream']));
  if (proof.sourceCommit !== release.sourceCommit || proof.sourceRun !== release.sourceRun) return false;
  if (proof.releaseTag && proof.releaseTag !== release.tag) return false;
  const required = [...Object.values(release.assets), checksumName];
  if (proof.files?.length !== required.length || required.some(name => !proof.files.some(file => file.name === name))) return false;
  return proof.files.every(file => item.assets.some(asset => asset.name === file.name && asset.size === file.size && asset.digest === `sha256:${file.sha256}`));
}

if (!['preflight', 'stage', 'publish'].includes(mode)) throw new Error('Usage: prepare-multiplatform-release.mjs preflight|stage|publish');
if (!/^[a-zA-Z0-9._-]+$/.test(release.tag) || Object.values(release.assets).some(name => path.basename(name) !== name)) throw new Error('Invalid release filenames');
const run = api(`${apiRoot}/actions/runs/${release.sourceRun}`);
if (run.status !== 'completed' || run.conclusion !== 'success' || run.head_sha !== release.sourceCommit || run.path !== '.github/workflows/multiplatform.yml' || run.head_branch !== 'main') throw new Error('The pinned main build must pass all four platforms before release');
const jobs = api(`${apiRoot}/actions/runs/${release.sourceRun}/jobs?per_page=100`).jobs;
for (const name of ['web', 'android', 'windows', 'macos']) if (!jobs.some(job => job.name === name && job.conclusion === 'success')) throw new Error(`Missing successful build: ${name}`);
const current = existingRelease();
const reusable = await verifiedExisting(current);
if (current && !current.draft && !reusable) throw new Error('Refusing to modify an existing published release');
if (current && current.target_commitish !== release.sourceCommit) throw new Error('Release tag targets a different source commit');
if (mode === 'preflight') {
  if (process.env.GITHUB_ENV) await writeFile(process.env.GITHUB_ENV, `HUSHNEST_SOURCE_RUN=${release.sourceRun}\nHUSHNEST_RELEASE_READY=${reusable}\n`, { flag: 'a' });
  console.log(JSON.stringify({ sourceRun: release.sourceRun, sourceCommit: release.sourceCommit, reuseVerifiedDraft: reusable }));
} else if (mode === 'publish') {
  if (!current || !reusable) throw new Error('Publish requires a complete draft with verified server-side file digests');
  if (current.draft) {
    const reference = `refs/tags/${release.tag}`;
    const refs = api(`${apiRoot}/git/matching-refs/tags/${release.tag}`);
    const tag = refs.find(item => item.ref === reference);
    if (tag && tag.object.sha !== release.sourceCommit) throw new Error('The release tag already points to another commit');
    if (!tag) api(`${apiRoot}/git/refs`, 'POST', { ref: reference, sha: release.sourceCommit });
  }
  const result = current.draft ? api(`${apiRoot}/releases/${current.id}`, 'PATCH', { tag_name: release.tag, target_commitish: release.sourceCommit, draft: false, prerelease: true, make_latest: 'false' }) : current;
  if (result.draft || result.tag_name !== release.tag) throw new Error('The release was not published at its configured tag');
  console.log(`Published verified preview: ${result.html_url}`);
} else if (reusable) {
  console.log(`All release files already verified: ${current.html_url}`);
} else {
  if (process.platform !== 'linux') throw new Error('Assemble the release on the Linux Actions runner');
  await mkdir(output, { recursive: true });
  await verifyNative('HushNest-Windows-Native-QA', 'windows');
  await verifyNative('HushNest-macOS-Native-QA', 'darwin');
  const sleep = JSON.parse(await readFile(path.join(root, 'cross-platform/assets/sleep/FieldRecordings.json'), 'utf8'));
  const sounds = [...sleep.recordings, ...sleep.generated];
  const windows = path.join(input, 'HushNest-Windows-MyGo-Native');
  const web = path.join(input, 'HushNest-Web');
  for (const item of sounds) {
    for (const folder of [path.join(windows, 'audio'), path.join(web, 'audio')]) {
      if (await sha256(path.join(folder, `${item.id}.wav`)) !== item.outputSHA256) throw new Error(`Incorrect packaged audio: ${item.id}`);
    }
  }
  const desktop = JSON.parse(await readFile(path.join(root, 'cross-platform/mygo.json'), 'utf8'));
  const installer = path.join(windows, `hushnest-setup-${desktop.version}-amd64.exe`);
  if ((await readFile(installer)).subarray(0, 2).toString() !== 'MZ') throw new Error('Invalid Windows installer');
  await cp(installer, path.join(output, release.assets.windows));
  const portable = path.join(output, 'portable/HushNest-windows-x64');
  await mkdir(portable, { recursive: true });
  for (const entry of await readdir(windows)) if (entry !== path.basename(installer)) await cp(path.join(windows, entry), path.join(portable, entry), { recursive: true });
  command('zip', ['-q', '-r', '-6', path.join(output, release.assets.windowsPortable), 'HushNest-windows-x64'], { cwd: path.dirname(portable) });
  const macFolder = path.join(input, 'HushNest-macOS-MyGo-Native');
  const dmgs = (await readdir(macFolder)).filter(file => file.endsWith('.dmg'));
  if (dmgs.length !== 1) throw new Error('Expected one verified universal macOS disk image');
  await cp(path.join(macFolder, dmgs[0]), path.join(output, release.assets.macos));
  const apk = path.join(input, 'HushNest-Android-debug/app-debug.apk');
  // Check ZIP integrity and the audio actually installed by Android, silently.
  command('python3', ['-c', `import json,zipfile,hashlib,sys
with zipfile.ZipFile(sys.argv[1]) as z:
 assert z.testzip() is None, 'Damaged APK'
 m=json.load(open(sys.argv[2]))
 for s in m['recordings']+m['generated']:
  assert hashlib.sha256(z.read('assets/public/audio/'+s['id']+'.wav')).hexdigest()==s['outputSHA256'],s['id']
`, apk, path.join(root, 'cross-platform/assets/sleep/FieldRecordings.json')]);
  await cp(apk, path.join(output, release.assets.android));
  const webFolder = path.join(output, 'static/HushNest-web');
  await cp(web, webFolder, { recursive: true });
  await writeFile(path.join(webFolder, 'README.txt'), `HushNest Web 0.1.0\nOnline: ${config.webApp}\n\nServe this directory with an HTTP/HTTPS static server; do not open index.html with file://.\nUse HTTPS (or localhost) for offline/PWA support. Audio caches after first use.\nKeep the browser and device awake for reminders. Web does not check headphones.\n`);
  command('zip', ['-q', '-r', '-6', path.join(output, release.assets.web), 'HushNest-web'], { cwd: path.dirname(webFolder) });
  const files = [];
  for (const name of Object.values(release.assets)) files.push({ name, size: (await stat(path.join(output, name))).size, sha256: await sha256(path.join(output, name)) });
  await writeFile(path.join(output, checksumName), files.map(file => `${file.sha256}  ${file.name}`).join('\n') + '\n');
  files.push({ name: checksumName, size: (await stat(path.join(output, checksumName))).size, sha256: await sha256(path.join(output, checksumName)) });
  await writeFile(path.join(output, proofName), JSON.stringify({ schemaVersion: 1, releaseTag: release.tag, sourceCommit: release.sourceCommit, sourceRun: release.sourceRun, files }, null, 2) + '\n');
  const notes = `HushNest 多平台预览：Windows / macOS 0.4.0，Android / Web 0.1.0。所有功能免费。\n\n` +
    `| 平台 | 下载 / 使用 | 安装条件 |\n| --- | --- | --- |\n` +
    `| Windows x64 | [安装器](${assetURL(release.assets.windows)}) · [完整便携包](${assetURL(release.assets.windowsPortable)}) | 未签名测试包；安装器默认使用当前用户目录。便携版需保留整个解压目录。 |\n` +
    `| macOS 12+ | [通用 DMG](${assetURL(release.assets.macos)}) | Apple Silicon / Intel；当前未公证，系统可能要求确认打开。 |\n` +
    `| Android 9+ | [测试 APK](${assetURL(release.assets.android)}) | 调试签名，非商店正式包；不同签名的旧版可能无法覆盖安装。 |\n` +
    `| Web / PWA | [在线使用](${config.webApp}) · [静态包](${assetURL(release.assets.web)}) | 不检查耳机；需保持浏览器打开及设备唤醒。静态包通过 HTTP / HTTPS 部署。 |\n` +
    `| iPhone · iOS 17+ | [TestFlight](${ios.testFlight}) · [iOS ${ios.version} IPA](${assetURL(ios.ipa, ios.tag)}) | TestFlight 名额及外部开放由 Apple 管理；unsigned IPA 需自行签名。 |\n\n` +
    `桌面使用 MyGo 原生 Go UI 与系统音频播放。无法自动识别耳机时，可二次确认当前输出后继续；没有输出设备不能放行。试听可再次点击停止，内置闹铃采用正常音量片段试听。\n\n` +
    `助眠音为独立长音包：细雨、潮汐、棕噪音及粉红噪音各 10 分钟，林间及夏夜 8 分钟，溪流 6 分钟，炉火 5 分钟。自然音首尾交叉渐变，噪音整段重新生成。原 iOS 保留独立版本及音包。\n\n` +
    `验证：[固定的主分支构建](https://github.com/${repository}/actions/runs/${release.sourceRun})全部四个平台通过；Windows 实际安装及覆盖升级、Windows/macOS 原生窗口和无声解码、Web 离线缓存、Android lint 均已验证。附件由该次 CI 的产物组装，源码提交为 \`${release.sourceCommit}\`。本预览不宣称正式签名、公证或商店上架。\n\n` +
    `[安装与平台说明](${config.homepage}#downloads) · [需求与交付记录](https://github.com/${repository}/blob/main/docs/requirements/2026-11-01-multiplatform.md) · [音源与许可](https://github.com/${repository}/blob/${release.sourceCommit}/cross-platform/THIRD_PARTY_NOTICES.md)\n\n` +
    `所有附件摘要见 [SHA256SUMS.txt](${assetURL(checksumName)})，来源及逐文件校验见 [发行清单](${assetURL(proofName)})。GitHub 自动生成的 Source code 为此发行标签对应源码。\n`;
  await writeFile(path.join(output, 'RELEASE_NOTES.md'), notes);
  const draft = current ?? api(`${apiRoot}/releases`, 'POST', { tag_name: release.tag, target_commitish: release.sourceCommit, name: release.name, body: notes, draft: true, prerelease: true, make_latest: 'false' });
  if (!api(`${apiRoot}/releases/${draft.id}`).draft) throw new Error('The draft was published during assembly; do not overwrite it');
  api(`${apiRoot}/releases/${draft.id}`, 'PATCH', { name: release.name, body: notes });
  for (const name of [...Object.values(release.assets), checksumName, proofName]) {
    const file = path.join(output, name), hash = await sha256(file);
    const latestDraft = api(`${apiRoot}/releases/${draft.id}`);
    if (!latestDraft.draft) throw new Error('The draft was published during upload; do not overwrite it');
    const previous = latestDraft.assets.find(asset => asset.name === name);
    if (previous?.digest === `sha256:${hash}`) continue;
    if (previous) api(`${apiRoot}/releases/assets/${previous.id}`, 'DELETE');
    const bytes = await readFile(file);
    const response = await fetch(`https://uploads.github.com/${apiRoot}/releases/${draft.id}/assets?name=${encodeURIComponent(name)}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${process.env.GH_TOKEN}`, 'Content-Type': 'application/octet-stream', 'Content-Length': String(bytes.length), 'User-Agent': 'HushNest-release' },
      body: bytes,
    });
    const uploaded = await response.json();
    if (!response.ok || uploaded.name !== name || uploaded.size !== bytes.length) throw new Error(`Release upload failed for ${name}: ${response.status} ${uploaded.message || ''}`);
  }
  if (!await verifiedExisting(api(`${apiRoot}/releases/${draft.id}`))) throw new Error('Server-side release digest verification failed');
  console.log(`Draft complete and all downloads verified: ${draft.html_url}`);
}

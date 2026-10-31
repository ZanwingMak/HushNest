import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.join(root, 'build/site');
const manifest = JSON.parse(await readFile(path.join(root, 'website/downloads.json'), 'utf8'));
const app = path.join(root, 'cross-platform/dist');
await readFile(path.join(app, 'index.html')); // Refuse to deploy a download page with a missing app.
if (path.dirname(output) !== path.join(root, 'build')) throw new Error('Unexpected site output directory');
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await cp(path.join(root, 'website'), output, { recursive: true });
await cp(app, path.join(output, 'app'), { recursive: true });
await writeFile(path.join(output, '.nojekyll'), '');
console.log(`Prepared the website and Web app for ${manifest.homepage} (app/).`);

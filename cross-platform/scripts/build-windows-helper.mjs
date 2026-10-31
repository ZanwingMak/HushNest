import { spawnSync } from 'node:child_process';
import { copyFile } from 'node:fs/promises';
if (process.platform !== 'win32') throw new Error('Build the Windows helper on Windows with the .NET 8 SDK.');
const executable = process.env.HUSHNEST_DOTNET || 'dotnet';
const result = spawnSync(executable, ['publish', 'desktop/native/AudioGuard.csproj', '-c', 'Release', '-o', 'desktop/bin', '--nologo'], { stdio: 'inherit' });
if (result.status !== 0) throw new Error('Install the .NET 8 SDK, or set HUSHNEST_DOTNET to its dotnet.exe.');
await copyFile(new URL('../desktop/native/NAudio.LICENSE.txt', import.meta.url), new URL('../desktop/bin/NAudio.LICENSE.txt', import.meta.url));

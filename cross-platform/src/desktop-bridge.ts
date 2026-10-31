import { isMyGo, runtime } from 'mygo-runtime';
import { Desktop, events } from './mygo';
import type { CommandInput } from './mygo';
import type { NativeSnapshot } from './platform';
import type { Route } from './core/model';

export interface DesktopBridge {
  platform: 'windows' | 'darwin';
  snapshot(): Promise<NativeSnapshot>;
  command(input: CommandInput): Promise<NativeSnapshot>;
  route(): Promise<Route>;
  keepAwake(active: boolean): Promise<void>;
  onSuspend(callback: () => void): () => void;
}
declare global {
  interface Window {
    hushnestDesktop?: DesktopBridge;
    hushnestAudio?: {
      cacheMedia(data: { id: string; name: string; bytes: ArrayBuffer }): Promise<void>;
      deleteMedia(id: string): Promise<void>;
    };
  }
}
export function connectMyGoDesktop() {
  if (!isMyGo()) return;
  const platform = runtime().platform;
  if (platform !== 'win32' && platform !== 'darwin') throw new Error('unsupported-desktop-platform');
  window.hushnestDesktop = {
    platform: platform === 'win32' ? 'windows' : 'darwin', snapshot: Desktop.snapshot, command: Desktop.command, route: Desktop.route,
    keepAwake: Desktop.keepAwake, onSuspend: callback => events.desktopSuspend.on(callback),
  };
  window.hushnestAudio = {
    async cacheMedia({ id, bytes }) {
      if (bytes.byteLength < 1 || bytes.byteLength > 200 * 1024 * 1024) throw new Error('media-size');
      if (await Desktop.hasMedia(id, bytes.byteLength)) return;
      for (let offset = 0; offset < bytes.byteLength; offset += 1024 * 1024) {
        const chunk = new Uint8Array(bytes, offset, Math.min(1024 * 1024, bytes.byteLength - offset));
        const parts: string[] = [];
        for (let part = 0; part < chunk.length; part += 32768) parts.push(String.fromCharCode(...chunk.subarray(part, part + 32768)));
        await Desktop.cacheMedia({ id, offset, data: btoa(parts.join('')), final: offset + chunk.byteLength === bytes.byteLength });
      }
    },
    deleteMedia: Desktop.deleteMedia,
  };
}

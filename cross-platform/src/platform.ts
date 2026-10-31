import { Capacitor, registerPlugin } from '@capacitor/core';
import type { MediaItem, Preferences, Route, Session, RestRecord } from './core/model';
import { connectMyGoDesktop } from './desktop-bridge';
export interface NativeSnapshot { session: Session | null; route: Route; records: RestRecord[] }
interface RestNative {
  snapshot(): Promise<NativeSnapshot>;
  command(data: { action: string; session?: Session; preferences?: Preferences; sound?: string; volume?: number }): Promise<NativeSnapshot>;
  importMedia(): Promise<MediaItem>;
  deleteMedia(data: { id: string }): Promise<void>;
  listMedia(): Promise<{ items: MediaItem[] }>;
  requestNotifications(): Promise<{ granted: boolean }>;
}
export const native = registerPlugin<RestNative>('HushNest');
export const isAndroid = Capacitor.getPlatform() === 'android';
connectMyGoDesktop();
export const isDesktop = !!window.hushnestDesktop;
export const isMacOS = window.hushnestDesktop?.platform === 'darwin';
export const isWindows = isDesktop && !isMacOS;
export const isWeb = !isAndroid && !isDesktop;
export const platformName = isAndroid ? 'Android' : isMacOS ? 'macOS' : isWindows ? 'Windows' : 'Web';
export const unknownRoute: Route = { connected: false, verified: false, name: '', token: '' };

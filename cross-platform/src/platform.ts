import { Capacitor, registerPlugin } from '@capacitor/core';
import type { MediaItem, Preferences, Route, Session, RestRecord } from './core/model';
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
declare global {
  interface Window { hushnestDesktop?: {
    route(): Promise<Route>;
    keepAwake(active: boolean): Promise<void>;
    onSuspend(callback: () => void): () => void;
  } }
}
export const isWindows = !!window.hushnestDesktop;
export const platformName = isAndroid ? 'Android' : isWindows ? 'Windows' : 'Web';
export const unknownRoute: Route = { connected: false, verified: false, name: '', token: '' };

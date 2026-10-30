import { getMedia } from './core/storage';
import type { Preferences } from './core/model';
import { isWindows } from './platform';
declare global {
  interface Window { hushnestAudio?: {
    play(data: { sound: string; volume: number; alarm: boolean; preview: boolean }): Promise<void>;
    stop(): Promise<void>; volume(value: number): Promise<void>;
    cacheMedia(data: { id: string; name: string; bytes: ArrayBuffer }): Promise<void>;
    deleteMedia(id: string): Promise<void>;
    onRouteLost(callback: () => void): () => void;
  } }
}
export class AudioEngine {
  private player: HTMLAudioElement | null = null;
  private objectUrl: string | null = null;
  private generation = 0;
  private previewTimeout: ReturnType<typeof setTimeout> | null = null;
  private onFailure: () => void;
  constructor(onFailure: () => void) { this.onFailure = onFailure; }
  stop() {
    this.generation++;
    if (this.previewTimeout) clearTimeout(this.previewTimeout);
    if (this.player) { this.player.pause(); this.player.removeAttribute('src'); this.player.load(); this.player = null; }
    if (this.objectUrl) { URL.revokeObjectURL(this.objectUrl); this.objectUrl = null; }
    if (isWindows) void window.hushnestAudio?.stop().catch(this.onFailure);
    navigator.vibrate?.(0);
  }
  async play(sound: string, volume: number, alarm = false, preview = false) {
    this.stop();
    if (sound === 'none') return;
    const generation = this.generation;
    let url: string;
    if (sound.startsWith('custom:')) {
      const item = await getMedia(sound.slice(7));
      if (!item?.blob) throw new Error('missing-media');
      if (isWindows) await window.hushnestAudio!.cacheMedia({ id: item.id, name: item.name, bytes: await item.blob.arrayBuffer() });
      if (generation !== this.generation) return;
      url = URL.createObjectURL(item.blob); this.objectUrl = url;
    } else url = new URL(`audio/${sound}.wav`, document.baseURI).href;
    if (isWindows) {
      await window.hushnestAudio!.play({ sound, volume, alarm, preview });
      return;
    }
    const player = new Audio(url); this.player = player; player.loop = true; player.volume = alarm && !preview ? 0.01 : volume;
    player.onerror = () => { if (generation === this.generation) { this.stop(); this.onFailure(); } };
    if (alarm && sound.startsWith('custom:')) player.ontimeupdate = () => { if (player.currentTime >= 60) player.currentTime = 0; };
    await player.play();
    if (generation !== this.generation) { player.pause(); return; }
    if (preview) this.previewTimeout = setTimeout(() => this.stop(), 2000);
  }
  update(preferences: Preferences, alarm: boolean, elapsedSeconds = 15) {
    const volume = alarm ? preferences.alarmVolume * Math.min(1, Math.max(0.01, elapsedSeconds / 15)) : preferences.sleepVolume;
    if (this.player) this.player.volume = volume;
    if (isWindows) void window.hushnestAudio?.volume(volume).catch(this.onFailure);
  }
}

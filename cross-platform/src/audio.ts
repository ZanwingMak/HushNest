import { getMedia } from './core/storage';
import type { Preferences } from './core/model';
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
      if (generation !== this.generation) return;
      url = URL.createObjectURL(item.blob); this.objectUrl = url;
    } else url = new URL(`audio/${sound}.wav`, document.baseURI).href;
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
  }
}

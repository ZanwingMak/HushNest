import sleepPack from '../../assets/sleep/FieldRecordings.json' with { type: 'json' };

export const sleepSoundSeconds: Record<string, number> = Object.fromEntries([...sleepPack.recordings, ...sleepPack.generated].map(item => [item.id, item.seconds]));

export const sleepSounds = [
  ['rain', '细雨', '庭院细雨，真实录音'], ['ocean', '潮汐', '真实海浪，缓慢起落'],
  ['stream', '溪流', '自然溪水，连续流淌'], ['forest', '林间', '林间鸟鸣，清晨实录'],
  ['fireplace', '炉火', '柴火燃烧，真实噼啪'], ['night', '夏夜', '夜间蟋蟀，自然虫鸣'],
  ['brown', '棕噪音', '深沉平稳，减轻沙沙声'], ['pink', '粉红噪音', '均衡柔和的声音毯'],
  ['none', '不播放助眠音', '片刻安静，自在醒来。'],
] as const;
export const alarmSounds = [
  ['dawn', '晨光'], ['bell', '风铃'], ['orbit', '星轨'], ['piano', '柔钢琴'],
  ['marimba', '木琴'], ['harp', '竖琴'], ['bamboo', '竹语'], ['aurora', '极光'],
  ['classic', '经典滴滴'], ['twinbell', '机械双铃'], ['digital', '数字闹钟'],
  ['pulse', '急促脉冲'], ['beacon', '交替信号'], ['reveille', '起床号角'],
] as const;
export type Phase = 'resting' | 'paused' | 'ringing' | 'blocked';
export type Language = 'zh-Hans' | 'zh-Hant' | 'en' | 'ja' | 'ko' | 'es';
export interface Preferences {
  duration: number; presets: number[]; sleepSound: string; alarmSound: string;
  sleepVolume: number; alarmVolume: number; snoozeMinutes: number;
  repeatAlarm: boolean; vibration: boolean; theme: 'forest' | 'ocean' | 'dusk' | 'rose';
  appearance: 'system' | 'light' | 'dark'; language: Language; largeText: boolean;
}
export interface Session {
  id: string; startedAt: number; deadline: number; duration: number; phase: Phase;
  pausedRemaining: number | null; snoozeCount: number; accumulatedRest: number;
  restingSince: number | null; reason: string | null;
}
export interface RestRecord { id: string; startedAt: number; endedAt: number; seconds: number; completed: boolean; sound: string }
export interface MediaItem { id: string; name: string; duration: number; size: number; blob?: Blob }
export interface Route { connected: boolean; verified: boolean; name: string; token: string; requiresConfirmation?: boolean }
export const defaultPreferences: Preferences = {
  duration: 1800, presets: [900, 1800, 2700, 3600], sleepSound: 'rain', alarmSound: 'dawn',
  sleepVolume: 0.18, alarmVolume: 0.55, snoozeMinutes: 5, repeatAlarm: false, vibration: false,
  theme: 'forest', appearance: 'system', language: 'zh-Hans', largeText: false,
};
function finite(value: unknown, fallback: number, min: number, max: number) {
  return typeof value === 'number' && Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;
}
function choice<T extends string>(value: unknown, options: readonly T[], fallback: T): T {
  return options.includes(value as T) ? value as T : fallback;
}
export function normalizePreferences(raw: unknown): Preferences {
  const p = raw && typeof raw === 'object' ? raw as Partial<Preferences> : {};
  const sound = (value: unknown, options: readonly (readonly string[])[], fallback: string) =>
    typeof value === 'string' && (options.some(s => s[0] === value) || /^custom:[\da-f-]{36}$/.test(value)) ? value : fallback;
  return {
    duration: Math.round(finite(p.duration, 1800, 1, 43200)),
    presets: Array.isArray(p.presets) ? [...new Set(p.presets.filter(n => Number.isInteger(n) && n >= 1 && n <= 43200))].sort((a, b) => a - b) : [...defaultPreferences.presets],
    sleepSound: sound(p.sleepSound, sleepSounds, 'rain'), alarmSound: sound(p.alarmSound, alarmSounds, 'dawn'),
    sleepVolume: finite(p.sleepVolume, 0.18, 0.01, 0.6), alarmVolume: finite(p.alarmVolume, 0.55, 0.05, 1),
    snoozeMinutes: Math.round(finite(p.snoozeMinutes, 5, 1, 30)), repeatAlarm: p.repeatAlarm === true, vibration: p.vibration === true,
    theme: choice(p.theme, ['forest', 'ocean', 'dusk', 'rose'], 'forest'),
    appearance: choice(p.appearance, ['system', 'light', 'dark'], 'system'),
    language: choice(p.language, ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'es'], 'zh-Hans'), largeText: p.largeText === true,
  };
}
export function createSession(now: number, duration: number): Session {
  duration = Math.min(43200, Math.max(1, Math.round(duration)));
  return { id: crypto.randomUUID(), startedAt: now, deadline: now + duration * 1000, duration,
    phase: 'resting', pausedRemaining: null, snoozeCount: 0, accumulatedRest: 0, restingSince: now, reason: null };
}
export const remaining = (s: Session, now: number) => Math.max(0, s.pausedRemaining ?? (s.deadline - now) / 1000);
export const rested = (s: Session, now: number) => s.accumulatedRest + (s.restingSince === null ? 0 : Math.max(0, (Math.min(now, s.deadline) - s.restingSince) / 1000));
function settle(s: Session, now: number): Session { return { ...s, accumulatedRest: rested(s, now), restingSince: null }; }
export function tick(s: Session, now: number, repeat: boolean): { session: Session; expired: boolean } {
  if (s.phase === 'resting' && now >= s.deadline) s = { ...settle(s, now), phase: 'ringing' };
  const expired = (s.phase === 'ringing' || s.phase === 'blocked') && s.pausedRemaining === null && !repeat && now >= s.deadline + 180000;
  return { session: s, expired };
}
export function pause(s: Session, now: number): Session {
  return s.phase === 'resting' ? { ...settle(s, now), phase: 'paused', pausedRemaining: remaining(s, now), reason: null } : s;
}
export function block(s: Session, now: number, reason: string): Session {
  return s.phase === 'paused' ? s : { ...settle(s, now), phase: 'blocked', reason };
}
export function resume(s: Session, now: number): Session {
  if (s.phase !== 'paused' && s.phase !== 'blocked') return s;
  const deadline = s.pausedRemaining === null ? s.deadline : now + s.pausedRemaining * 1000;
  return { ...s, deadline, phase: deadline <= now ? 'ringing' : 'resting',
    pausedRemaining: null, reason: null, restingSince: deadline > now ? now : null };
}
export function snooze(s: Session, now: number, minutes: number): Session {
  if (s.phase !== 'ringing') return s;
  const duration = Math.min(30, Math.max(1, minutes)) * 60;
  return { ...s, duration, deadline: now + duration * 1000, phase: 'resting', restingSince: now,
    pausedRemaining: null, snoozeCount: s.snoozeCount + 1, reason: null };
}
export function finish(s: Session, now: number, completed: boolean, sound: string): RestRecord {
  return { id: s.id, startedAt: s.startedAt, endedAt: now, seconds: Math.floor(rested(s, now)), completed, sound };
}
export function restoreSession(raw: unknown, now: number): Session | null {
  if (!raw || typeof raw !== 'object') return null;
  const s = raw as Session;
  if (typeof s.id !== 'string' || !['resting', 'paused', 'ringing', 'blocked'].includes(s.phase) ||
    ![s.startedAt, s.deadline, s.duration, s.accumulatedRest, s.snoozeCount].every(Number.isFinite) ||
    s.duration < 1 || s.duration > 43200 || s.accumulatedRest < 0 ||
    (s.pausedRemaining !== null && (!Number.isFinite(s.pausedRemaining) || s.pausedRemaining < 0 || s.pausedRemaining > 43200)) ||
    (s.restingSince !== null && !Number.isFinite(s.restingSince))) return null;
  // A closed process cannot have rested or played audio: never count the unobserved interval.
  return s.phase === 'paused' ? { ...s, restingSince: null } : { ...s, phase: 'blocked', restingSince: null, reason: 'restored', deadline: Math.min(s.deadline, now + 43200000) };
}
export function nextOccurrence(time: string, now: number): number {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) throw new Error('invalid-time');
  const [hours, minutes] = time.split(':').map(Number);
  const date = new Date(now); date.setHours(hours, minutes, 0, 0);
  if (date.getTime() <= now) date.setDate(date.getDate() + 1);
  return date.getTime();
}
export function formatDuration(seconds: number): string {
  const n = Math.max(0, Math.ceil(seconds));
  return `${Math.floor(n / 60).toString().padStart(2, '0')}:${(n % 60).toString().padStart(2, '0')}`;
}

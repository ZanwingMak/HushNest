import { useEffect, useRef, useState } from 'react';
import { appendRecord, getMedia, loadJSON, loadRecords, saveJSON } from './core/storage';
import { block, createSession, defaultPreferences, finish, normalizePreferences, pause, restoreSession, resume, rested, snooze, tick } from './core/model';
import type { Preferences, RestRecord, Route, Session } from './core/model';
import { AudioEngine } from './audio';
import { isAndroid, isDesktop, isWeb, native, unknownRoute } from './platform';
const nativeSessions = isAndroid || isDesktop;
const nativeController = isAndroid ? native : window.hushnestDesktop;
async function cacheDesktopSound(sound: string) {
  if (!isDesktop || !sound.startsWith('custom:')) return;
  const media = await getMedia(sound.slice(7));
  if (!media?.blob) throw new Error('missing-media');
  await window.hushnestAudio!.cacheMedia({ id: media.id, name: media.name, bytes: await media.blob.arrayBuffer() });
}

function initialPreferences() {
  const stored = loadJSON('preferences');
  if (stored) return normalizePreferences(stored);
  const lang = navigator.language;
  return normalizePreferences({ ...defaultPreferences, language: lang.startsWith('zh') ? /TW|HK|Hant/.test(lang) ? 'zh-Hant' : 'zh-Hans' : lang.split('-')[0] });
}
export function useNest() {
  const [preferences, setPreferences] = useState<Preferences>(initialPreferences);
  const [session, setSession] = useState<Session | null>(() => nativeSessions ? null : restoreSession(loadJSON('session'), Date.now()));
  const [records, setRecords] = useState<RestRecord[]>(loadRecords);
  const [route, setRoute] = useState<Route>(unknownRoute);
  const [error, setError] = useState(''); const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(Date.now()); const [ready, setReady] = useState(!nativeSessions);
  const [exclusive, setExclusive] = useState(true);
  const state = useRef({ session, preferences, records, route });
  state.current = { session, preferences, records, route };
  const engine = useRef<AudioEngine | null>(null);
  const audioKey = useRef('');
  const save = (key: string, data: unknown) => { try { saveJSON(key, data); } catch { setError('storageError'); } };
  const commit = (s: Session | null) => { state.current.session = s; setSession(s); if (!nativeSessions) save('session', s); };
  const stopRecord = (s: Session, completed: boolean) => {
    const next = appendRecord(state.current.records, finish(s, Date.now(), completed, state.current.preferences.sleepSound));
    state.current.records = next; setRecords(next); save('records', next); commit(null); engine.current?.stop(); audioKey.current = '';
  };
  useEffect(() => {
    if (nativeSessions) return;
    engine.current = new AudioEngine(() => {
      const s = state.current.session;
      if (s) commit(block(s, Date.now(), 'audioError')); setError('audioError');
    });
    return () => engine.current?.stop();
  }, []);
  useEffect(() => { save('preferences', preferences); }, [preferences]);
  // A browser lock prevents independent windows from overwriting one session or playing twice.
  useEffect(() => {
    if (isAndroid || !navigator.locks) return;
    let release: (() => void) | undefined; let disposed = false;
    void navigator.locks.request('hushnest-active-window', { ifAvailable: true }, async lock => {
      if (disposed) return;
      if (!lock) { setExclusive(false); return; }
      await new Promise<void>(resolve => { release = resolve; });
    });
    return () => { disposed = true; release?.(); };
  }, []);
  const ingest = (snapshot: Awaited<ReturnType<typeof native.snapshot>>) => {
    commit(snapshot.session); setRoute(snapshot.route); state.current.route = snapshot.route;
    const merged = [...snapshot.records, ...state.current.records.filter(r => !snapshot.records.some(n => n.id === r.id))].sort((a, b) => b.endedAt - a.endedAt).slice(0, 365);
    state.current.records = merged; setRecords(merged); save('records', merged); setReady(true);
  };
  useEffect(() => {
    let polling = false; let disposed = false; let lastNative = 0; let lastCheckpoint = Date.now();
    const interval = setInterval(() => {
      const time = Date.now(); setNow(time);
      if (!exclusive) return;
      if (nativeSessions) {
        if (!polling && time - lastNative >= 1000) {
          polling = true; lastNative = time;
          void nativeController!.snapshot().then(snapshot => { if (!disposed) ingest(snapshot); }).catch(() => setError('audioError')).finally(() => { polling = false; });
        }
        return;
      }
      const current = state.current;
      if (current.session) {
        const result = tick(current.session, time, current.preferences.repeatAlarm);
        if (result.expired) stopRecord(result.session, true);
        else if (result.session !== current.session) commit(result.session);
        else if (current.session.phase === 'resting' && time - lastCheckpoint >= 10000) {
          commit({ ...current.session, accumulatedRest: rested(current.session, time), restingSince: time }); lastCheckpoint = time;
        }
      }
    }, 250);
    return () => { disposed = true; clearInterval(interval); };
  }, [exclusive]);
  useEffect(() => {
    if (!isDesktop) return;
    return window.hushnestDesktop!.onSuspend(() => {
      void nativeController!.snapshot().then(ingest).catch(() => setError('audioError'));
    });
  }, []);
  useEffect(() => {
    if (nativeSessions || !engine.current) return;
    const active = session && ['resting', 'ringing'].includes(session.phase) && exclusive;
    const key = active ? `${session.id}:${session.phase}:${session.phase === 'ringing' ? preferences.alarmSound : preferences.sleepSound}` : '';
    if (key === audioKey.current) return;
    audioKey.current = key;
    if (!active) { engine.current.stop(); return; }
    const alarm = session.phase === 'ringing';
    void engine.current.play(alarm ? preferences.alarmSound : preferences.sleepSound, alarm ? preferences.alarmVolume : preferences.sleepVolume, alarm).catch(() => {
      if (audioKey.current !== key) return;
      engine.current?.stop(); commit(block(state.current.session!, Date.now(), 'audioError')); setError('audioError');
    });
  }, [session?.phase, session?.id, preferences.sleepSound, preferences.alarmSound, exclusive]);
  useEffect(() => {
    if (nativeSessions || !session) return;
    engine.current?.update(preferences, session.phase === 'ringing', (now - session.deadline) / 1000);
    if (session.phase === 'ringing' && preferences.vibration && Math.floor(now / 1000) % 3 === 0) navigator.vibrate?.(250);
  }, [now, preferences, session?.phase]);
  const running = !!session && ['resting', 'ringing', 'blocked'].includes(session.phase);
  useEffect(() => {
    if (nativeSessions) return;
    let lock: WakeLockSentinel | undefined; let disposed = false;
    const acquire = async () => {
      if (!running || document.visibilityState !== 'visible') return;
      try {
        const acquired = await navigator.wakeLock.request('screen');
        if (disposed) await acquired.release(); else lock = acquired;
      } catch { if (!disposed) setError('wakeLock'); }
    };
    void acquire(); document.addEventListener('visibilitychange', acquire);
    return () => { disposed = true; void lock?.release(); document.removeEventListener('visibilitychange', acquire); };
  }, [running]);
  useEffect(() => {
    const handler = (event: BeforeUnloadEvent) => { if (state.current.session) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', handler); return () => window.removeEventListener('beforeunload', handler);
  }, []);
  async function command(action: string, duration?: number) {
    if (busy || !ready || !exclusive) return;
    setError(''); setBusy(true);
    try {
      const { preferences: p, session: s, route: r } = state.current;
      if (!isWeb && ['start', 'resume', 'snooze'].includes(action) && !r.connected) throw new Error('routeLost');
      if (nativeSessions) {
        if (isAndroid && action === 'start') await native.requestNotifications();
        if (['start', 'resume', 'snooze'].includes(action)) {
          for (const sound of new Set([p.sleepSound, p.alarmSound])) await cacheDesktopSound(sound);
        }
        ingest(await nativeController!.command({ action, preferences: p, session: action === 'start' ? createSession(Date.now(), duration ?? p.duration) : undefined }));
        return;
      }
      if (action === 'start') commit(createSession(Date.now(), duration ?? p.duration));
      else if (s && action === 'pause') commit(pause(s, Date.now()));
      else if (s && action === 'resume') commit(resume(s, Date.now()));
      else if (s && action === 'snooze') commit(snooze(s, Date.now(), p.snoozeMinutes));
      else if (s && action === 'stop') stopRecord(s, s.phase === 'ringing' || Date.now() >= s.deadline && s.pausedRemaining === null);
    } catch (e) { setError(e instanceof Error && ['routeLost', 'otherTab'].includes(e.message) ? e.message : 'audioError'); }
    finally { setBusy(false); }
  }
  async function preview(sound: string, alarm = false) {
    if (session || busy || !exclusive) return;
    if (!isWeb && !route.connected) { setError('routeLost'); return; }
    setBusy(true); setError('');
    try {
      if (nativeSessions) { await cacheDesktopSound(sound); await nativeController!.command({ action: 'preview', sound, volume: alarm ? preferences.alarmVolume : preferences.sleepVolume }); }
      else await engine.current!.play(sound, Math.min(0.18, alarm ? preferences.alarmVolume : preferences.sleepVolume), alarm, true);
    } catch { setError('audioError'); } finally { setBusy(false); }
  }
  async function checkRoute() {
    if (nativeSessions) ingest(await nativeController!.snapshot());
  }
  async function clearRecords() {
    if (nativeSessions) await nativeController!.command({ action: 'clearRecords' });
    state.current.records = []; setRecords([]); save('records', []);
  }
  function updatePreferences(patch: Partial<Preferences>) {
    const next = normalizePreferences({ ...state.current.preferences, ...patch }); state.current.preferences = next; setPreferences(next);
    if (nativeSessions && session) void nativeController!.command({ action: 'volume', preferences: next }).catch(() => setError('audioError'));
  }
  return { preferences, updatePreferences, session, records, route, error: !exclusive ? 'otherTab' : error, setError,
    busy, ready, now, command, preview, checkRoute, clearRecords, exclusive };
}

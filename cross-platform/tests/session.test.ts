import test from 'node:test';
import assert from 'node:assert/strict';
import { block, createSession, defaultPreferences, finish, formatDuration, nextOccurrence, normalizePreferences, pause, remaining, restoreSession, resume, rested, snooze, tick } from '../src/core/model.ts';
import { appendRecord } from '../src/core/storage.ts';

test('absolute deadline survives delayed ticks without drifting', () => {
  const session = createSession(1000, 30);
  assert.equal(remaining(session, 15000), 16);
  assert.equal(tick(session, 31000, false).session.phase, 'ringing');
  assert.equal(tick(session, 211000, false).expired, true);
});
test('a throttled timer beyond its alarm window expires instead of starting a stale alarm', () => {
  const result = tick(createSession(0, 5), 600000, false);
  assert.equal(result.expired, true); assert.equal(result.session.accumulatedRest, 5);
});
test('continuous ringing has no three-minute expiry', () => {
  const result = tick(createSession(0, 1), 1000000, true);
  assert.equal(result.session.phase, 'ringing'); assert.equal(result.expired, false);
});
test('manual pause freezes remaining time and excludes paused time from records', () => {
  const original = createSession(0, 60);
  const paused = pause(original, 10000);
  assert.equal(remaining(paused, 100000), 50);
  const running = resume(paused, 100000);
  assert.equal(running.deadline, 150000); assert.equal(rested(running, 120000), 30);
  assert.equal(finish(running, 120000, false, 'rain').seconds, 30);
});
test('interruption preserves the deadline and excludes blocked time', () => {
  const interrupted = block(createSession(0, 60), 10000, 'routeLost');
  assert.equal(interrupted.deadline, 60000);
  const resumed = resume(interrupted, 50000);
  assert.equal(rested(resumed, 60000), 20);
  assert.equal(resume(interrupted, 65000).phase, 'ringing');
});
test('resuming an overdue blocked alarm never resets its original ringing window', () => {
  const session = resume(block(createSession(0, 1), 500, 'routeLost'), 300000);
  assert.equal(session.deadline, 1000); assert.equal(tick(session, 300000, false).expired, true);
});
test('disconnect does not unpause a manually paused timer', () => {
  const paused = pause(createSession(0, 60), 1000);
  assert.equal(block(paused, 5000, 'routeLost'), paused);
});
test('paused sessions never expire because wall time passed', () => {
  const paused = pause(createSession(0, 60), 1000);
  assert.equal(tick(paused, 9999999, false).expired, false);
});
test('snooze updates the deadline and accumulates only actual resting time', () => {
  const ringing = tick(createSession(0, 10), 10000, false).session;
  const snoozed = snooze(ringing, 15000, 5);
  assert.equal(snoozed.deadline, 315000); assert.equal(snoozed.snoozeCount, 1);
  assert.equal(rested(snoozed, 45000), 40); assert.equal(snooze(snoozed, 50000, 5), snoozed);
});
test('restoration requires manual confirmation and never counts downtime', () => {
  const session = restoreSession(createSession(0, 60), 30000)!;
  assert.equal(session.phase, 'blocked'); assert.equal(session.reason, 'restored');
  assert.equal(rested(session, 50000), 0);
  assert.equal(restoreSession({ ...session, deadline: 'bad' }, 30000), null);
  assert.equal(restoreSession({ ...session, pausedRemaining: -1 }, 30000), null);
  assert.equal(restoreSession(null, 0), null);
});
test('preferences enforce media, duration, volume and preset boundaries', () => {
  const p = normalizePreferences({ duration: Infinity, sleepSound: '../../secret', alarmVolume: 9, sleepVolume: 0,
    presets: [0, 1, 1, -5, 43200, 43201, 1.1, '60'], theme: 'evil', snoozeMinutes: 99 });
  assert.equal(p.duration, 1800); assert.equal(p.sleepSound, 'rain'); assert.equal(p.alarmVolume, 1);
  assert.equal(p.sleepVolume, 0.01); assert.deepEqual(p.presets, [1, 43200]); assert.equal(p.snoozeMinutes, 30);
  assert.equal(p.theme, 'forest'); assert.deepEqual(normalizePreferences(null), defaultPreferences);
});
test('calendar scheduling crosses midnight and rejects invalid times', () => {
  const now = new Date(2026, 9, 31, 23, 59).getTime();
  const next = new Date(nextOccurrence('00:10', now));
  assert.equal(next.getDate(), 1); assert.equal(next.getMonth(), 10); assert.equal(next.getHours(), 0); assert.equal(next.getMinutes(), 10);
  assert.throws(() => nextOccurrence('24:00', now)); assert.throws(() => nextOccurrence('x', now));
});
test('records are idempotent and capped at 365', () => {
  const r = finish(createSession(0, 1), 1000, true, 'none');
  const records = Array.from({ length: 365 }, (_, i) => ({ ...r, id: String(i) }));
  const next = appendRecord(records, r);
  assert.equal(next.length, 365); assert.equal(next[0].id, r.id);
  assert.equal(appendRecord(next, r).filter(item => item.id === r.id).length, 1);
});
test('timer formatting rounds remaining fractions up and supports 12 hours', () => {
  assert.equal(formatDuration(0.1), '00:01'); assert.equal(formatDuration(-1), '00:00'); assert.equal(formatDuration(43200), '720:00');
});

import type { MediaItem, RestRecord } from './model';
export function loadJSON(key: string): unknown {
  try { return JSON.parse(localStorage.getItem(`hushnest:${key}`) ?? 'null'); } catch { return null; }
}
export function saveJSON(key: string, value: unknown) {
  // Propagate quota/security errors so the UI never claims unsaved settings are saved.
  localStorage.setItem(`hushnest:${key}`, JSON.stringify(value));
}
export function loadRecords(): RestRecord[] {
  const value = loadJSON('records');
  return Array.isArray(value) ? value.filter((r): r is RestRecord => r && typeof r.id === 'string' &&
    [r.startedAt, r.endedAt, r.seconds].every(Number.isFinite) && r.seconds >= 0 && typeof r.completed === 'boolean' && typeof r.sound === 'string').slice(0, 365) : [];
}
export function appendRecord(records: RestRecord[], record: RestRecord): RestRecord[] {
  return [record, ...records.filter(r => r.id !== record.id)].slice(0, 365);
}
let connection: Promise<IDBDatabase> | undefined;
function db() {
  return connection ??= new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open('hushnest-media', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('media', { keyPath: 'id' });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => { connection = undefined; reject(request.error); };
    request.onblocked = () => { connection = undefined; reject(new Error('storage-blocked')); };
  });
}
async function transaction<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const database = await db();
  return new Promise((resolve, reject) => {
    const tx = database.transaction('media', mode); const request = run(tx.objectStore('media'));
    let result: T; request.onsuccess = () => { result = request.result; };
    tx.oncomplete = () => resolve(result); tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error ?? new Error('storage-failed'));
  });
}
export const listMedia = () => transaction<MediaItem[]>('readonly', store => store.getAll());
export const getMedia = (id: string) => transaction<MediaItem | undefined>('readonly', store => store.get(id));
export const putMedia = (item: MediaItem) => transaction('readwrite', store => store.put(item));
export const deleteMedia = (id: string) => transaction('readwrite', store => store.delete(id));
export async function importFile(file: File): Promise<MediaItem> {
  if (file.size > 200 * 1024 * 1024 || file.size === 0) throw new Error('media-size');
  if ((await listMedia()).length >= 20) throw new Error('media-count');
  const url = URL.createObjectURL(file);
  const element = document.createElement('video'); element.preload = 'metadata'; element.muted = true;
  try {
    const duration = await new Promise<number>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('media-format')), 15000);
      element.onloadedmetadata = () => { clearTimeout(timeout); resolve(element.duration); };
      element.onerror = () => { clearTimeout(timeout); reject(new Error('media-format')); };
      element.src = url;
    });
    if (!Number.isFinite(duration) || duration <= 0 || duration > 7200) throw new Error('media-duration');
    const item: MediaItem = { id: crypto.randomUUID(), name: file.name.slice(0, 200), duration, size: file.size, blob: file };
    await putMedia(item); return item;
  } finally { element.removeAttribute('src'); element.load(); URL.revokeObjectURL(url); }
}

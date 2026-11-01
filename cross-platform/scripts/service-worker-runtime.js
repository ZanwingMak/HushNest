const audioDownloads = new Map();

/** 为完整响应流生成单段 Range，已收到的数据立即返回，不等待文件尾部。 */
function audioRange(response, range) {
  if (!range || response.status !== 200 || !response.body || response.headers.has('Content-Encoding')) return response;
  const size = Number(response.headers.get('Content-Length'));
  if (!Number.isSafeInteger(size) || size <= 0) return response;
  const match = /^bytes=(\d*)-(\d*)$/.exec(range);
  const start = match?.[1] ? Number(match[1]) : Math.max(0, size - Number(match?.[2]));
  const end = match?.[1] && match[2] ? Math.min(size - 1, Number(match[2])) : size - 1;
  if (!match || !match[1] && !match[2] || !Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= size) {
    void response.body.cancel().catch(() => {});
    return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}` } });
  }
  let offset = 0;
  const body = response.body.pipeThrough(new TransformStream({
    transform(chunk, controller) {
      const next = offset + chunk.byteLength;
      if (next > start && offset <= end) controller.enqueue(chunk.subarray(Math.max(0, start - offset), Math.min(chunk.byteLength, end + 1 - offset)));
      offset = next;
      if (offset > end) controller.terminate();
    },
  }));
  const headers = new Headers(response.headers);
  headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
  headers.set('Content-Length', String(end - start + 1));
  headers.set('Accept-Ranges', 'bytes');
  return new Response(body, { status: 206, headers });
}

/** 后台只缓存完整 200 响应；同一音轨合并下载，失败不影响在线播放。 */
function cacheAudio(cache, key, response) {
  if (audioDownloads.has(key.url)) return audioDownloads.get(key.url);
  const pending = (async () => {
    let full = response ? response.clone() : await fetch(key);
    if (full.status === 206) {
      const headers = new Headers(full.headers);
      const size = headers.get('Content-Range').split('/')[1];
      headers.delete('Content-Range'); headers.set('Content-Length', size);
      full = new Response(full.body, { headers });
    }
    if (full.status !== 200) return;
    if (!full.headers.has('Content-Length')) {
      const bytes = await full.blob();
      const headers = new Headers(full.headers); headers.set('Content-Length', String(bytes.size));
      full = new Response(bytes, { headers });
    }
    await cache.put(key, full);
  })().catch(() => {}).finally(() => audioDownloads.delete(key.url));
  audioDownloads.set(key.url, pending);
  return pending;
}

/** 缓存命中支持离线 Range，未命中先流式响应，再完成整轨缓存。 */
async function respondAudio(event, background) {
  const cache = await caches.open(AUDIO_CACHE);
  const key = new Request(event.request.url);
  const full = await cache.match(key);
  if (full) return audioRange(full, event.request.headers.get('range'));
  const response = await fetch(event.request);
  if (response.status === 200) background.push(cacheAudio(cache, key, response));
  else if (response.status === 206) {
    const match = /^bytes 0-(\d+)\/(\d+)$/.exec(response.headers.get('Content-Range') ?? '');
    if (match && Number(match[1]) + 1 === Number(match[2])) {
      background.push(cacheAudio(cache, key, response));
    } else background.push(cacheAudio(cache, key));
  }
  return audioRange(response, event.request.headers.get('range'));
}

self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(FILES))); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('hushnest-') && k !== CACHE && k !== AUDIO_CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (event.request.mode === 'navigate') {
    event.respondWith(caches.match(new URL('index.html', self.registration.scope).href).then(cached => cached || fetch(event.request))); return;
  }
  if (url.pathname.endsWith('.wav')) {
    const background = [];
    const response = respondAudio(event, background);
    // 必须在事件回调内注册生命周期，页面停止播放后完整缓存仍可继续。
    event.waitUntil(response.then(() => Promise.all(background)).catch(() => {}));
    event.respondWith(response);
    return;
  }
  event.respondWith(caches.match(event.request).then(cached => cached || fetch(event.request)));
});

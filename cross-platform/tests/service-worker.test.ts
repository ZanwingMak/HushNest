import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const runtime = readFileSync(new URL('../scripts/service-worker-runtime.js', import.meta.url), 'utf8');
const url = 'https://example.test/app/audio/rain.wav';

/** 在真实流与 Cache 语义的无声替身中运行正式 worker，不创建浏览器播放器。 */
function worker(fetcher: (request: Request) => Promise<Response>) {
  const handlers: Record<string, (event: unknown) => void> = {};
  const entries = new Map<string, Response>();
  const cache = {
    match: async (key: Request) => entries.get(key.url)?.clone(),
    put: async (key: Request, response: Response) => {
      assert.equal(response.status, 200);
      const bytes = await response.arrayBuffer();
      entries.set(key.url, new Response(bytes, { headers: response.headers }));
    },
  };
  vm.runInNewContext(`const AUDIO_CACHE='test-audio';\n${runtime}`, {
    self: { location: { origin: 'https://example.test' }, addEventListener: (kind: string, handler: (event: unknown) => void) => { handlers[kind] = handler; } },
    URL, Request, Response, Headers, TransformStream,
    caches: { open: async () => cache }, fetch: fetcher,
  });
  return {
    entries, cache,
    request(range: string) {
      let response!: Promise<Response>;
      const background: Promise<unknown>[] = [];
      handlers.fetch({ request: new Request(url, { headers: { Range: range } }),
        respondWith: (result: Promise<Response>) => { response = result; },
        waitUntil: (job: Promise<unknown>) => background.push(job) });
      return { response, done: () => Promise.all(background) };
    },
  };
}

/** 文件头立即到达，尾部由测试显式放行，用于检测等待整轨下载的回归。 */
function delayedAudio() {
  let complete!: () => void;
  const response = new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(44).fill(7));
      complete = () => { controller.enqueue(new Uint8Array(980).fill(9)); controller.close(); };
    },
  }), { headers: { 'Content-Length': '1024', 'Content-Type': 'audio/wav' } });
  return { response, complete: () => complete() };
}

test('first audio bytes stream before the complete download, then remain available offline', async () => {
  const audio = delayedAudio(); let offline = false;
  const app = worker(async () => { if (offline) throw new Error('offline'); return audio.response; });
  const request = app.request('bytes=0-43');
  try {
    const first = request.response.then(async response => ({ status: response.status, bytes: [...new Uint8Array(await response.arrayBuffer())] }));
    const result = await Promise.race([first, new Promise<null>(resolve => setTimeout(() => resolve(null), 500))]);
    assert.deepEqual(result, { status: 206, bytes: new Array(44).fill(7) });
    assert.equal(app.entries.size, 0, 'full cache is still downloading');
  } finally { audio.complete(); await request.done(); }
  offline = true;
  const cached = await app.request('bytes=44-91').response;
  assert.equal(cached.status, 206); assert.equal((await cached.arrayBuffer()).byteLength, 48);
  assert.equal(app.entries.get(url)?.headers.get('Content-Range'), null);
});

test('a partial network response returns while one full download is shared by concurrent requests', async () => {
  const audio = delayedAudio(); let downloads = 0;
  const app = worker(async request => {
    if (!request.headers.has('range')) { downloads++; return audio.response; }
    return new Response(new Uint8Array(44), { status: 206, headers: { 'Content-Range': 'bytes 0-43/1024', 'Content-Length': '44' } });
  });
  const first = app.request('bytes=0-43'), second = app.request('bytes=0-43');
  assert.equal((await first.response).status, 206); assert.equal((await second.response).status, 206);
  assert.equal(downloads, 1); assert.equal(app.entries.size, 0);
  audio.complete(); await Promise.all([first.done(), second.done()]);
  assert.equal((await app.entries.get(url)!.arrayBuffer()).byteLength, 1024);
});

test('a complete 206 response is cached as a full 200 without downloading the audio twice', async () => {
  let downloads = 0;
  const app = worker(async () => {
    downloads++;
    return new Response(new Uint8Array(1024), { status: 206, headers: { 'Content-Range': 'bytes 0-1023/1024' } });
  });
  const request = app.request('bytes=0-');
  assert.equal((await request.response).status, 206); await request.done();
  assert.equal(downloads, 1); assert.equal(app.entries.get(url)?.status, 200);
  assert.equal(app.entries.get(url)?.headers.get('Content-Length'), '1024');
});

test('offline ranges support suffixes and reject unsatisfiable or multiple ranges', async () => {
  const app = worker(async () => { throw new Error('network must not be used'); });
  app.entries.set(url, new Response(new Uint8Array(1024), { headers: { 'Content-Length': '1024' } }));
  const suffix = await app.request('bytes=-8').response;
  assert.equal(suffix.headers.get('Content-Range'), 'bytes 1016-1023/1024');
  assert.equal((await suffix.arrayBuffer()).byteLength, 8);
  for (const range of ['bytes=1024-', 'bytes=10-5', 'bytes=-0', 'bytes=0-1,3-4']) {
    const response = await app.request(range).response;
    assert.equal(response.status, 416); assert.equal(response.headers.get('Content-Range'), 'bytes */1024');
  }
});

test('cache quota failure does not prevent online audio playback', async () => {
  const app = worker(async () => new Response(new Uint8Array(1024), { headers: { 'Content-Length': '1024' } }));
  app.cache.put = async () => { throw new Error('quota exceeded'); };
  const request = app.request('bytes=0-43');
  assert.equal((await request.response).status, 206); await request.done();
  assert.equal(app.entries.size, 0);
});

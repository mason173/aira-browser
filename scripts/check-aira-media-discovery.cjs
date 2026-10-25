// Execute the generated page scripts: ArkTS compilation alone cannot catch broken
// escaping inside injected JavaScript. All fixtures are synthetic; no device capture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
function load(relative) {
  const filename = path.resolve(root, relative);
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(code, { exports, $r: key => key, require(name) {
    if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name + '.ets'));
  } }, { filename });
  return exports;
}
const feature = 'features/mediaDiscovery/';
const { MediaResourceDomProbeScript } = load(feature + 'MediaResourceDomProbeScript.ets');
const { MediaVideoDomProbeScript, extractMediaUrlsFromText } = load(feature + 'MediaVideoDomProbeScript.ets');
const { MediaVideoDeepProbeScript } = load(feature + 'MediaVideoDeepProbeScript.ets');
const { normalizeMediaLocatorText, MEDIA_LOCATOR_TEXT_RUNTIME } = load(feature + 'MediaLocatorText.ets');
const scripts = [new MediaResourceDomProbeScript().build(), new MediaVideoDomProbeScript().build(),
  new MediaVideoDeepProbeScript().build()];
const signed = 'https://cdn.example.test/a%2Fb/movie.mp4?token=a%2Bb%26c%3Dd&path=%252F&expires=123#part';
function element(attrs = {}, fields = {}) {
  return { tagName: 'DIV', getAttribute: key => attrs[key] || '', querySelectorAll: () => [],
    getBoundingClientRect: () => ({ width: 640, height: 360 }), ...fields };
}
function page(options = {}) {
  const location = new URL('https://page.example.test/watch');
  let styles = 0, queries = 0;
  const timers = new Map();
  const document = {
    baseURI: options.baseURI || location.href,
    title: options.title || '',
    documentElement: {}, body: {},
    querySelector(selector) {
      queries++;
      return options.meta?.[selector] || null;
    },
    querySelectorAll(selector) {
      queries++;
      if (options.select) return options.select(selector);
      if (selector === 'video, audio' || selector === 'video') return options.media || [];
      if (selector === 'script:not([src])') return options.scripts || [];
      return [];
    },
    createElement: () => element({}, { canPlayType: () => '' }),
    addEventListener() {}
  };
  class PageURL extends URL {}
  PageURL.createObjectURL = () => 'blob:https://page.example.test/fixture';
  class XHR {
    open() {} addEventListener(type, fn) { this.listener = fn; }
    removeEventListener() {} getResponseHeader(key) { return this.headers?.[key] || ''; }
  }
  const context = {
    document, location, URL: PageURL, navigator: { userAgent: 'fixture-UA' },
    performance: { getEntriesByType: () => options.entries || [] },
    Date: options.Date || { now: () => 1000 },
    Blob, TextEncoder, TextDecoder, XMLHttpRequest: XHR,
    atob: value => Buffer.from(value, 'base64').toString('binary'),
    setTimeout(fn) { const id = Symbol(); timers.set(id, fn); return id; },
    clearTimeout(id) { timers.delete(id); },
    addEventListener() {},
    getComputedStyle() { styles++; return { backgroundImage: 'none', display: 'block', visibility: 'visible' }; },
    fetch: options.fetch || (() => Promise.reject(new Error('unexpected network request')))
  };
  context.window = context; context.self = context; context.top = context;
  vm.createContext(context);
  return { context, timers, stats: () => ({ styles, queries }), run(script = scripts[0]) {
    const payload = JSON.parse(vm.runInContext(script, context, { timeout: options.timeout || 2000 }));
    assert.equal(payload.ok, true, payload.error);
    return payload.results;
  } };
}
const checks = [];
function check(name, action) { checks.push([name, action]); }
const flush = () => new Promise(resolve => setImmediate(resolve));

check('all generated scripts parse and execute, including deep probe with user intent', () => {
  for (const script of [...scripts, new MediaVideoDeepProbeScript().build(true)]) {
    new vm.Script(script);
    page().run(script);
  }
});
check('signed URLs survive plain, escaped, percent-wrapped, and base64 script sources', () => {
  const texts = [JSON.stringify({ url: signed }), JSON.stringify({ url: signed }).replaceAll('/', '\\/'),
    JSON.stringify({ url: encodeURIComponent(signed) }),
    JSON.stringify({ url: encodeURIComponent(encodeURIComponent(signed)) }),
    JSON.stringify({ url: Buffer.from(signed).toString('base64') })];
  for (const text of texts) {
    assert.ok(extractMediaUrlsFromText(text).includes(signed), text);
    for (const script of scripts) {
      const found = page({ scripts: [{ textContent: text }] }).run(script);
      assert.ok(found.some(item => item.url === signed), text);
      assert.ok(!found.some(item => item.url.includes('token=a+b&c=d')), 'signed query was decoded');
    }
  }
});
check('native and injected locator normalization agree; raw nested URLs stay intact', () => {
  const normalize = vm.runInNewContext(MEDIA_LOCATOR_TEXT_RUNTIME + '\nnormalizeMediaLocatorText');
  for (const value of [signed, encodeURIComponent(signed), encodeURIComponent(encodeURIComponent(signed)),
    'https://cdn.example.test/file.mp4?redirect=' + encodeURIComponent(signed),
    JSON.stringify({ raw: signed, encoded: encodeURIComponent(signed) }),
    'https://cdn.example.test/a%ZZ/movie.mp4?token=%2F', '//cdn.example.test/a.mp4?q=%2526']) {
    assert.equal(normalize(value), normalizeMediaLocatorText(value));
  }
  assert.equal(normalize(signed), signed);
  const wrapper = 'https://page.example.test/player?url=' + encodeURIComponent(signed);
  assert.equal(normalize(wrapper), wrapper);
});
check('embedded player query unwraps only its URL value and keeps the full signature', () => {
  const wrapper = 'https://page.example.test/player?url=' + encodeURIComponent(signed) + '&autoplay=1';
  const text = JSON.stringify({ player: wrapper });
  assert.ok(extractMediaUrlsFromText(text).includes(signed));
  for (const script of scripts) {
    assert.ok(page({ scripts: [{ textContent: text }] }).run(script).some(item => item.url === signed));
  }
  const relative = 'movie.mp4?token=' + encodeURIComponent(signed);
  assert.equal(normalizeMediaLocatorText(relative), relative);
});
check('configured player query fields still work and overlong values are not truncated', () => {
  const { mediaLocatorQueryValues } = load(feature + 'MediaLocatorText.ets');
  const wrapper = 'https://page.example.test/player?Asset=' + encodeURIComponent(signed);
  const configured = new MediaVideoDeepProbeScript().build(false, {
    strategyIds: ['inline_scripts'], globalConfigNames: [], mediaFieldNames: [],
    mediaQueryParameterNames: ['Asset'], playerMethodNames: []
  });
  assert.ok(page({ scripts: [{ textContent: JSON.stringify({ player: wrapper }) }] }).run(configured)
    .some(item => item.url === signed));
  const overlong = 'url=' + encodeURIComponent(signed) + 'x'.repeat(20000);
  assert.equal(mediaLocatorQueryValues(overlong).length, 0);
  const query = vm.runInNewContext(MEDIA_LOCATOR_TEXT_RUNTIME + '\nmediaLocatorQueryValues');
  assert.equal(query(overlong).length, 0);
});
check('relative sources use the document base and preserve signed values', () => {
  const media = element({}, { tagName: 'VIDEO', currentSrc: '../movie.mp4?token=%2B%252F', duration: 60 });
  for (const script of scripts) {
    const found = page({ baseURI: 'https://cdn.example.test/folder/sub/', media: [media] }).run(script);
    assert.ok(found.some(item => item.url === 'https://cdn.example.test/folder/movie.mp4?token=%2B%252F'));
  }
});
check('bounded title reads keep distinct player titles attached to their own sources', () => {
  const first = element({ title: '海边日落' }, { tagName: 'VIDEO', currentSrc: signed, duration: 60 });
  const secondUrl = 'https://cdn.example.test/123456789.mp4';
  const second = element({ 'aria-label': 'Video player', 'data-title': '山间清晨' },
    { tagName: 'VIDEO', currentSrc: secondUrl, duration: 60 });
  const unrelated = 'https://cdn.example.test/987654321.mp4';
  for (const script of scripts.slice(0, 2)) {
    const p = page({ media: [first, second], title: '站点标题',
      meta: { 'meta[property="og:title"]': element({ content: '页面视频的标题' }) },
      scripts: [{ textContent: JSON.stringify({ url: unrelated }) }] });
    const payload = JSON.parse(vm.runInContext(script, p.context));
    assert.equal(payload.pageTitle, '页面视频的标题');
    assert.equal(payload.results.find(item => item.url === signed).mediaTitle, '海边日落');
    assert.equal(payload.results.find(item => item.url === secondUrl).mediaTitle, '山间清晨');
    assert.equal(payload.results.find(item => item.url === unrelated).mediaTitle, undefined);
    const fallback = page({ title: '文'.repeat(2000) });
    const fallbackPayload = JSON.parse(vm.runInContext(script, fallback.context));
    assert.equal(fallbackPayload.pageTitle.length, 512);
  }
});
check('a 42-second player cannot lend its duration to another playlist or inactive source', () => {
  const previewUrl = 'https://cdn.example.test/preview.mp4';
  const fullUrl = 'https://cdn.example.test/complete.m3u8';
  const alternateUrl = 'https://cdn.example.test/alternate.mp4';
  const source = element({ src: alternateUrl, type: 'video/mp4' }, { src: alternateUrl });
  const media = element({ 'data-hls': fullUrl }, { tagName: 'VIDEO', currentSrc: previewUrl, duration: 42,
    querySelectorAll: selector => selector === 'source' ? [source] : [] });
  for (const script of scripts) {
    const found = page({ media: [media], scripts: [{ textContent: JSON.stringify({ url: fullUrl }) }] }).run(script);
    assert.equal(found.find(item => item.url === previewUrl).durationMs, 42000);
    assert.equal(found.find(item => item.url === alternateUrl).durationMs, undefined);
    assert.equal(found.find(item => item.url === fullUrl).durationMs, undefined);
  }
});
check('recent network media and inline player URLs survive image-heavy pages', () => {
  const images = Array.from({ length: 1000 }, (_, i) => element({ src: `https://img.example.test/${i}.png`,
    'data-original': `https://img.example.test/original-${i}.png` }));
  const entries = Array.from({ length: 800 }, (_, i) => ({ name: `https://site.example.test/${i}.js`, initiatorType: 'script' }));
  entries.push({ name: signed, initiatorType: 'fetch', encodedBodySize: 456 });
  const p = page({ entries, select: selector => {
    if (selector === 'script:not([src])') return [{ textContent: 'var file="https://cdn.example.test/second.m3u8?key=%26";' }];
    return selector.startsWith('img') || selector.startsWith('iframe') ? images : [];
  } });
  const found = p.run();
  assert.ok(found.some(item => item.url === signed && item.totalBytes === 456));
  assert.ok(found.some(item => item.url.endsWith('second.m3u8?key=%26')));
  assert.ok(found.length <= 160);
});
check('extensionless MIME observations, lazy images, and named HLS attributes are collected', () => {
  const p = page({ entries: [{ name: 'https://cdn.example.test/opaque?id=1', contentType: 'video/mp4', initiatorType: 'fetch', transferSize: 500 }],
    select: selector => selector.startsWith('iframe') ? [element({ 'data-hls': '/opaque?key=%26' })] :
      selector.startsWith('img') ? [element({ 'data-src': '/image?id=8' })] : [] });
  const found = p.run();
  assert.ok(found.some(item => item.url.includes('/opaque?id=1') && item.mimeType === 'video/mp4' && !item.totalBytes));
  assert.ok(found.some(item => item.url.endsWith('/opaque?key=%26') && item.mimeType === 'application/vnd.apple.mpegurl'));
  assert.ok(found.some(item => item.url.endsWith('/image?id=8') && item.signal === 'image_element'));
});
check('scan work has a deadline, style cap, script budget, and no truncated URL output', () => {
  const nodes = Array.from({ length: 1000 }, () => element());
  const p = page({ select: selector => selector.startsWith('[style]') ? nodes : [] });
  p.run(); assert.equal(p.stats().styles, 48);
  let now = 0;
  const expired = page({ Date: { now: () => now++ * 25 }, select: () => { throw new Error('expired scan continued'); } });
  assert.equal(expired.run().length, 0);
  let readScripts = 0;
  const large = Array.from({ length: 24 }, () => ({ get textContent() {
    readScripts++; return ' '.repeat(32760) + '"https://cdn.example.test/truncated.mp4?token=' + 'x'.repeat(10000);
  } }));
  const results = page({ scripts: large }).run();
  assert.ok(!results.some(item => item.url.includes('truncated')));
  assert.ok(readScripts <= 5, 'script character budget exceeded');
});
check('long malformed URL tokens cannot trap the probe in suffix-regex backtracking', () => {
  const malformed = 'https://'.repeat(16000);
  const text = `var payload = "${malformed}";`;
  assert.ok(extractMediaUrlsFromText(text + JSON.stringify({ url: signed })).includes(signed));
  for (const script of scripts) {
    const p = page({ timeout: 1000, scripts: [{ textContent: text }, { textContent: JSON.stringify({ url: signed }) }] });
    assert.ok(p.run(script).some(item => item.url === signed));
  }
});
check('deep response metadata identifies opaque media without cloning binary or event streams', async () => {
  let clones = 0;
  let response = { url: 'https://cdn.example.test/opaque', status: 200, headers: { get: key => key === 'content-type' ? 'video/mp4' : null },
    body: { getReader() {} }, clone() { clones++; throw new Error('must not clone'); } };
  const p = page({ fetch: () => Promise.resolve(response) }); p.run(scripts[2]);
  assert.equal(await p.context.fetch(response.url), response);
  assert.equal(clones, 0);
  assert.ok(p.run(scripts[2]).some(item => item.url === response.url && item.mimeType === 'video/mp4'));
  for (const mime of ['text/event-stream', 'application/x-ndjson', 'application/stream+json']) {
    response = { ...response, url: 'https://cdn.example.test/stream.m3u8', headers: { get: key => key === 'content-type' ? mime : '32' } };
    assert.equal(await p.context.fetch(response.url), response);
  }
  assert.equal(clones, 0);
});
check('deep body reads cap concurrency, cancel stalled clones, and return the original response', async () => {
  let clones = 0, cancellations = 0;
  const response = { url: 'https://cdn.example.test/list.m3u8', status: 200,
    headers: { get: key => key === 'content-type' ? 'application/vnd.apple.mpegurl' : null }, body: { getReader() {} },
    clone() { clones++; return { body: { getReader: () => ({ read: () => new Promise(() => {}),
      cancel() { cancellations++; return Promise.resolve(); } }) } }; } };
  const p = page({ fetch: () => Promise.resolve(response) }); p.run(scripts[2]);
  const results = await Promise.all(Array.from({ length: 20 }, () => p.context.fetch(response.url)));
  assert.ok(results.every(item => item === response)); assert.equal(clones, 2);
  for (const fn of [...p.timers.values()]) fn();
  assert.equal(cancellations, 2);
  await p.context.fetch(response.url); assert.equal(clones, 3);
  for (const fn of [...p.timers.values()]) fn();
});
check('oversize chunks are discarded before decoding; bounded JSON still discovers a signed URL', async () => {
  let cancelled = 0;
  let chunk = new TextEncoder().encode('x'.repeat(100001) + signed);
  const response = { url: 'https://page.example.test/video/config', status: 200,
    headers: { get: key => key === 'content-type' ? 'application/json' : null }, body: { getReader() {} },
    clone() { let read = false; return { body: { getReader: () => ({ read: () => {
      if (read) return Promise.resolve({ done: true }); read = true;
      return Promise.resolve({ done: false, value: chunk });
    }, cancel() { cancelled++; return Promise.resolve(); } }) } }; } };
  const p = page({ fetch: () => Promise.resolve(response) }); p.run(scripts[2]);
  await p.context.fetch(response.url); await flush();
  assert.equal(cancelled, 1); assert.ok(!p.run(scripts[2]).some(item => item.url === signed));
  chunk = new TextEncoder().encode(JSON.stringify({ url: signed }));
  await p.context.fetch(response.url); await flush();
  assert.ok(p.run(scripts[2]).some(item => item.url === signed));
});
check('runtime results and deduplication stay bounded and manifest metadata upgrades', async () => {
  let response;
  const p = page({ fetch: () => Promise.resolve(response) }); p.run(scripts[2]);
  for (let i = 0; i < 100; i++) {
    response = { url: `https://cdn.example.test/opaque-${i}`, status: 200,
      headers: { get: key => key === 'content-type' ? 'video/mp4' : null } };
    await p.context.fetch(response.url);
  }
  assert.equal(p.context.__airaVideoDeepProbeResults.length, 80);
  assert.equal(Object.keys(p.context.__airaVideoDeepProbeSeen).length, 80);
  for (let i = 0; i < 100; i++) {
    response = { url: `https://cdn.example.test/segment-${i}.m4s`, status: 200,
      headers: { get: key => key === 'content-type' ? 'video/mp4' : null } };
    await p.context.fetch(response.url);
  }
  assert.ok(p.context.__airaVideoDeepProbeResults.every(item => item.url.includes('opaque-')),
    'segment metadata must not evict useful media targets');
  const manifest = '#EXTM3U\n#EXTINF:1,\npart.ts\n#EXT-X-ENDLIST';
  response = { url: 'https://cdn.example.test/playlist', status: 200,
    headers: { get: key => key === 'content-type' ? 'application/vnd.apple.mpegurl' : null },
    body: { getReader() {} }, clone() { let read = false; return { body: { getReader: () => ({
      read: () => { const result = read ? { done: true } : { done: false, value: new TextEncoder().encode(manifest) };
        read = true; return Promise.resolve(result); }, cancel: () => Promise.resolve()
    }) } }; } };
  await p.context.fetch(response.url); await flush();
  assert.ok(p.run(scripts[2]).some(item => item.url === response.url && item.manifestText === manifest));
});
check('Blob bursts share the response read budget and preserve small manifest evidence', async () => {
  const p = page(); p.run(scripts[2]);
  let slices = 0;
  const completions = [];
  const blob = new Blob(['#EXTM3U'], { type: 'application/vnd.apple.mpegurl' });
  blob.slice = () => { slices++; return { text: () => new Promise(resolve => completions.push(resolve)) }; };
  for (let i = 0; i < 20; i++) p.context.URL.createObjectURL(blob);
  assert.equal(slices, 2);
  completions.forEach(resolve => resolve('#EXTM3U\n#EXTINF:1,\npart.ts\n#EXT-X-ENDLIST'));
  await flush();
  assert.ok(p.run(scripts[2]).some(item => item.manifestText?.includes('#EXTM3U')));
  p.context.URL.createObjectURL(blob); assert.equal(slices, 3);
  for (const fn of [...p.timers.values()]) fn();
});
check('POST or failed media responses do not become GET targets; binary XHR uses only headers', async () => {
  let response = { url: 'https://cdn.example.test/opaque-post', status: 200,
    headers: { get: key => key === 'content-type' ? 'video/mp4' : null } };
  const p = page({ fetch: () => Promise.resolve(response) }); p.run(scripts[2]);
  await p.context.fetch(response.url, { method: 'POST' });
  assert.ok(!p.run(scripts[2]).some(item => item.url === response.url));
  response = { ...response, status: 403 };
  await p.context.fetch(response.url);
  assert.ok(!p.run(scripts[2]).some(item => item.url === response.url));
  const xhr = new p.context.XMLHttpRequest();
  xhr.open('GET', 'https://cdn.example.test/opaque-xhr');
  xhr.readyState = 4; xhr.status = 200; xhr.responseType = 'arraybuffer';
  xhr.responseURL = 'https://cdn.example.test/opaque-xhr'; xhr.headers = { 'content-type': 'video/mp4' };
  Object.defineProperty(xhr, 'response', { get() { throw new Error('binary response was read'); } });
  xhr.listener();
  assert.ok(p.run(scripts[2]).some(item => item.url === xhr.responseURL && item.mimeType === 'video/mp4'));
});
check('creating a large object URL never reads the whole Blob', () => {
  const p = page(); p.run(scripts[2]);
  const blob = new Blob(['x'.repeat(300001)], { type: 'application/vnd.apple.mpegurl' });
  blob.text = () => { throw new Error('unbounded Blob.text'); };
  blob.slice = () => { throw new Error('oversize blob sampled'); };
  let reads = 0;
  blob.text = () => { reads++; return Promise.resolve(''); };
  p.context.URL.createObjectURL(blob); assert.equal(reads, 0);
});
check('DOM discovery keeps page UA/referer and request observation reads native headers once', async () => {
  const { BrowserMediaProbeBridge } = load('core/browser/media/BrowserMediaProbeBridge.ets');
  const { MediaResourceTypeRules } = load(feature + 'MediaResourceTypeRules.ets');
  const bridge = Object.create(BrowserMediaProbeBridge.prototype);
  bridge.resourceTypeRules = new MediaResourceTypeRules();
  bridge.signalClassifier = { buildResourceDomSignal: input => input, buildResourceNetworkSignal: input => input };
  bridge.resourceDomScanService = { scan: async () => ({ ok: true, pageTitle: '当前页面标题',
    results: [{ url: signed, mediaTitle: '播放器标题', frameUrl: 'https://frame.example.test/player', fromBlob: false }] }) };
  const input = { tabId: 'tab', pageUrl: 'https://page.example.test/watch', pageTitle: 'fixture', privacyMode: 'normal',
    controller: { getCustomUserAgent: () => 'site-UA', getUserAgent: () => 'default-UA' } };
  let result = await bridge.runResourceDomScan(input);
  assert.equal(result.signals[0].userAgent, 'site-UA');
  assert.equal(result.signals[0].pageTitle, '当前页面标题');
  assert.equal(result.signals[0].mediaTitle, '播放器标题');
  assert.equal(result.signals[0].referer, 'https://frame.example.test/player');
  result = await bridge.runResourceDomScan({ ...input, controller: { getCustomUserAgent() { throw new Error(); }, getUserAgent: () => 'fallback-UA' } });
  assert.equal(result.signals[0].userAgent, 'fallback-UA');
  let reads = 0;
  const observation = bridge.observeResourceIntercept({ ...input, request: { getRequestUrl: () => signed, isMainFrame: () => false,
    getRequestHeader() { reads++; return [{ headerKey: 'rEfErEr', headerValue: 'https://frame.example.test/' },
      { headerKey: 'User-Agent', headerValue: 'captured-UA' }, { headerKey: 'Authorization', headerValue: 'Bearer fixture' }]; } } });
  assert.equal(reads, 1); assert.equal(observation.userAgent, 'captured-UA');
  assert.equal(observation.referer, 'https://frame.example.test/');
  assert.equal(observation.requestHeaders.Authorization, 'Bearer fixture');
});
(async () => {
  for (const [name, action] of checks) { await action(); console.log('PASS ' + name); }
  console.log(`Media discovery: ${checks.length} executable regression groups passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });

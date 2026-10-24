// Exercise the production cast service at the AVSession boundary. Native discovery and receiver
// playback still require device validation; these checks verify the app's configuration and ordering.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/services/video/VideoAssistantCastSessionService.ets');
const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
}).outputText;

function fixture(options = {}) {
  const calls = [];
  const hooks = {};
  const messages = [];
  const snapshots = [];
  const submitted = [];
  let metadata = { assetId: 'web-video', title: 'Keep title', drmSchemes: ['keep-drm'],
    filter: options.filter, extras: { marker: 'keep-metadata' } };
  let extras = { requireAbilityList: ['existing-ability'], marker: 'keep-extras' };
  let active = options.active !== false;
  const mediaUri = 'https://example.com/video.mp4';
  const borrowedQueueItem = { itemId: 7, description: {
    assetId: 'web-video', mediaUri, mediaType: 'video', title: 'Queue title',
    drmScheme: 'keep-drm', extras: { marker: 'keep-queue' }
  } };
  async function step(name) {
    calls.push(name);
    if (hooks[name]) await hooks[name]();
    if (options.failAt === name) throw { code: 6600101, message: name + ' failed' };
  }
  const remote = {
    on() {}, off() {},
    async prepare(item) { submitted.push(item); await step('prepare'); },
    async start(item) { submitted.push(item); await step('start'); },
    async getAVPlaybackState() { return { state: 2 }; }
  };
  const controller = {
    on() {}, off() {},
    async getExtras() { await step('getExtras'); return structuredClone(extras); },
    async getAVMetadata() { await step('getAVMetadata'); return structuredClone(metadata); },
    async isActive() { await step('isActive'); return active; },
    async getAVPlaybackState() { return { state: 2, activeItemId: 7 }; },
    async getAVQueueItems() { await step('getAVQueueItems'); return options.borrowedQueue ? [borrowedQueueItem] : []; },
    async getOutputDevice() {
      return { devices: options.connected ? [{ deviceId: 'fixture-tv', castCategory: 1 }] : [] };
    }
  };
  const session = {
    sessionType: options.sessionType ?? 'video',
    async getController() { return controller; },
    async setExtras(value) { await step('setExtras'); extras = structuredClone(value); },
    async setAVMetadata(value) { await step('setAVMetadata'); metadata = structuredClone(value); },
    async activate() { await step('activate'); active = true; },
    async getAVCastController() { return remote; },
    async destroy() { await step('destroy'); },
    async deactivate() { await step('deactivate'); }
  };
  class Picker {
    on() {} off() {}
    async select(options) {
      await step('select');
      snapshots.push({ metadata: structuredClone(metadata), extras: structuredClone(extras), active, options });
    }
  }
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports, $r: key => key,
    require(name) {
      if (name === '@kit.AVSessionKit') return { avSession: {
        async getAVSession() {
          await step('getAVSession');
          if (options.missingSession) throw { code: 6600102, message: 'Session does not exist' };
          return session;
        },
        AVCastPickerHelper: Picker,
        ProtocolType: { TYPE_LOCAL: 0, TYPE_CAST_PLUS_STREAM: 2, TYPE_DLNA: 4 },
        AVCastCategory: { CATEGORY_REMOTE: 1 },
        ConnectionState: { STATE_CONNECTED: 1, STATE_DISCONNECTED: 0 },
        PlaybackState: { PLAYBACK_STATE_PLAY: 2, PLAYBACK_STATE_ERROR: 6 }
      } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {} } };
      if (name === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
      if (name.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: {
        hasUIAbilityContext: () => true, getUIAbilityContext: () => ({})
      } };
      if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
      if (name.endsWith('/UrlUtils')) return { isLikelyLocalUrlHost: host => host === 'localhost' };
      throw new Error('Unexpected dependency: ' + name);
    }
  }, { filename });
  const service = new module.exports.VideoAssistantCastSessionService();
  const item = {
    sessionKey: 'web-video', title: 'Video', pageUrl: 'https://example.com', mediaUri,
    mediaFormat: 'mp4', durationSeconds: 60, positionSeconds: 10,
    requiresWebRequestContext: false, requestHeaderCount: 0
  };
  const handler = {
    isCurrent: () => true, isPlaying: () => true,
    pause: async () => { calls.push('pauseLocal'); return true; },
    resume: async () => { calls.push('resumeLocal'); return true; },
    showMessage: message => messages.push(message)
  };
  return { service, calls, hooks, messages, snapshots, submitted, borrowedQueueItem,
    request: overrides => service.requestCast({ ...item, ...overrides }, handler) };
}

const tests = [];
function test(name, run) { tests.push({ name, run }); }
for (const filter of [undefined, 0, 2, 4, 6, 10]) {
  test(`enable Cast+ and DLNA before selecting, inherited filter=${filter}`, async () => {
    const f = fixture({ filter, active: false });
    assert.equal((await f.request()).opened, true);
    const snapshot = f.snapshots[0];
    assert.equal(snapshot.metadata.filter, (filter ?? 0) | 6);
    assert.equal(snapshot.active, true);
    assert.equal(snapshot.options.sessionType, 'video');
    assert.equal(snapshot.metadata.title, 'Keep title');
    assert.deepEqual(snapshot.metadata.drmSchemes, ['keep-drm']);
    assert.equal(snapshot.metadata.extras.marker, 'keep-metadata');
    assert.deepEqual(snapshot.extras.requireAbilityList, ['existing-ability', 'url-cast']);
    assert.equal(snapshot.extras.marker, 'keep-extras');
    assert.ok(f.calls.indexOf('setAVMetadata') < f.calls.indexOf('select'));
    await f.service.release();
    assert.ok(!f.calls.includes('destroy') && !f.calls.includes('deactivate'),
      'releasing casting must not destroy the borrowed Web session');
  });
}
test('do not reactivate an already active session', async () => {
  const f = fixture();
  await f.request();
  assert.ok(!f.calls.includes('activate'));
});
for (const options of [{ missingSession: true }, { sessionType: 'audio' }]) {
  test(`unavailable video session: ${JSON.stringify(options)}`, async () => {
    const f = fixture(options);
    const result = await f.request();
    assert.equal(result.reason, 'session_unavailable');
    assert.equal(result.opened, false);
    assert.equal(f.snapshots.length, 0);
    assert.ok(!f.calls.includes('setExtras'));
  });
}
for (const failAt of ['getAVMetadata', 'setAVMetadata', 'getExtras', 'setExtras', 'isActive', 'activate']) {
  test(`do not open an unprepared picker after ${failAt} fails`, async () => {
    const f = fixture({ failAt, active: false });
    assert.equal((await f.request()).opened, false);
    assert.equal(f.snapshots.length, 0);
  });
}
for (const boundary of ['getAVQueueItems', 'getAVMetadata', 'setAVMetadata', 'getExtras', 'setExtras', 'isActive', 'activate']) {
  test(`released request cannot open picker after ${boundary}`, async () => {
    const f = fixture({ active: false });
    f.hooks[boundary] = () => f.service.release();
    assert.equal((await f.request()).opened, false);
    assert.equal(f.snapshots.length, 0);
  });
}
for (const borrowedQueue of [false, true]) {
  test(`remote video uses VIDEO, borrowed queue=${borrowedQueue}`, async () => {
    const f = fixture({ connected: true, borrowedQueue });
    await f.request();
    assert.equal(f.submitted.length, 2);
    assert.equal(f.submitted[0].description.mediaType, 'VIDEO');
    assert.equal(f.submitted[1].description.mediaType, 'VIDEO');
    assert.ok(f.calls.indexOf('prepare') < f.calls.indexOf('start'));
    assert.ok(f.calls.indexOf('start') < f.calls.indexOf('pauseLocal'));
    if (borrowedQueue) {
      assert.equal(f.submitted[0].description.drmScheme, 'keep-drm');
      assert.equal(f.submitted[0].description.extras.marker, 'keep-queue');
      assert.equal(f.borrowedQueueItem.description.mediaType, 'video', 'do not mutate borrowed queue metadata');
    }
  });
}
test('prepare failure does not start remote playback or pause local video', async () => {
  const f = fixture({ connected: true, failAt: 'prepare' });
  await f.request();
  assert.ok(f.calls.includes('prepare'));
  assert.ok(!f.calls.includes('start'));
  assert.ok(!f.calls.includes('pauseLocal'));
  assert.ok(f.messages.includes('app.string.video_cast_start_failed'));
});
test('release during prepare prevents remote start', async () => {
  const f = fixture({ connected: true });
  f.hooks.prepare = () => f.service.release();
  await f.request();
  assert.ok(!f.calls.includes('start'));
  assert.ok(!f.calls.includes('pauseLocal'));
});
test('authenticated media remains blocked before configuring discovery', async () => {
  const f = fixture();
  assert.equal((await f.request({ requiresWebRequestContext: true })).reason, 'media_unavailable');
  assert.ok(!f.calls.includes('setAVMetadata'));
  assert.equal(f.snapshots.length, 0);
});

(async () => {
  let failed = 0;
  for (const { name, run } of tests) {
    try { await run(); }
    catch (error) { failed++; console.error(`FAIL ${name}: ${error.message}`); }
  }
  console.log(`Video cast session: ${tests.length - failed}/${tests.length} checks passed.`);
  if (failed) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; });

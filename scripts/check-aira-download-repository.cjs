#!/usr/bin/env node
'use strict';

// Real repository, entity and preferences codec; only timers and platform storage are modeled.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

async function settle() { for (let i = 0; i < 20; i++) await Promise.resolve(); }
function environment(config) {
  let now = 0, nextTimer = 0;
  const timers = new Map(), cache = new Map(), logs = [], values = new Map();
  const preferencesState = { openFailures: 0, flushFailures: 0, openAttempts: 0 };
  const clock = {
    pending: () => timers.size,
    async tick(ms) {
      const target = now + ms;
      for (;;) {
        const next = [...timers].filter(([, t]) => t.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        now = next[1].at; timers.delete(next[0]); next[1].callback(); await settle();
      }
      now = target; await settle();
    }
  };
  const preferences = {
    getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value),
    flushSync() {
      if (preferencesState.flushFailures-- > 0) throw Error('preferences flush unavailable');
    }
  };
  function load(filename) {
    if (cache.has(filename)) return cache.get(filename);
    const module = { exports: {} };
    cache.set(filename, module.exports);
    vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, {
      module, exports: module.exports, $r: value => value,
      setTimeout(callback, delay) { const id = ++nextTimer; timers.set(id, { callback, at: now + delay }); return id; },
      clearTimeout: id => timers.delete(id),
      require(id) {
        if (id === '@kit.PerformanceAnalysisKit') return { hilog: {
          info: (...args) => logs.push(args), warn: (...args) => logs.push(args), error: (...args) => logs.push(args)
        } };
        if (id === '@kit.ArkData') return { preferences: { getPreferences: async () => {
          preferencesState.openAttempts++;
          if (preferencesState.openFailures-- > 0) throw Error('preferences open unavailable');
          return preferences;
        } } };
        if (id.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: { getApplicationContext: () => ({}) } };
        if (id.startsWith('.')) return load(path.resolve(path.dirname(filename), `${id}.ets`));
        throw Error(`Unmodeled dependency ${id}`);
      }
    }, { filename });
    return module.exports;
  }
  const repositoryModule = load(path.join(sourceRoot, 'data/downloadv2/DownloadV2Repository.ets'));
  const storeModule = load(path.join(sourceRoot, 'data/downloadv2/DownloadV2RecordStore.ets'));
  const model = load(path.join(sourceRoot, 'domain/downloadv2/DownloadV2TaskEntity.ets'));
  const queue = load(path.join(sourceRoot, 'services/download/DownloadQueuePolicyService.ets'));
  const saves = [], stored = [], state = { saveHook: undefined, failNext: false, inFlight: 0, maxInFlight: 0 };
  const recordStore = {
    loadRecords: async () => stored,
    async saveRecords(records) {
      state.inFlight++; state.maxInFlight = Math.max(state.maxInFlight, state.inFlight);
      try {
        saves.push(JSON.parse(JSON.stringify(records)));
        await state.saveHook?.(records);
        if (state.failNext) { state.failNext = false; throw Error('disk unavailable'); }
        stored.splice(0, stored.length, ...JSON.parse(JSON.stringify(records)));
      } finally { state.inFlight--; }
    }
  };
  const repository = new repositoryModule.PersistentDownloadV2Repository(recordStore, undefined, config);
  function task(guid = 'file', extra = {}) {
    return model.createDownloadV2TaskEntity({
      guid, suggestedFileName: 'file.bin', profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent',
      request: { url: 'https://example.test/final', originalUrl: 'https://example.test/original', method: 'GET', headers: { Cookie: 'synthetic' } },
      status: 'running', progress: { totalBytes: 1000, receivedBytes: 0 },
      persistence: { tempFilePath: '/sandbox/file', downloadDriver: 'arkweb', expectedTotalBytes: 1000 },
      runtime: { platformTaskId: 'arkweb:file', platformTaskToken: 'synthetic-token', resumeCapability: 'live_resume', pauseReason: 'none' },
      timing: { createdAt: 1, updatedAt: 2 }, ...extra
    });
  }
  return { ...repositoryModule, ...storeModule, ...queue, repository, recordStore, model, task, saves, stored, state, clock,
    logs, values, preferencesState };
}

async function run() {
  const failures = [];
  async function check(name, body) {
    try { await body(); console.log(`PASS ${name}`); }
    catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.stack}`); }
  }
  await check('repository copies keep original URL, validation bytes and recovery metadata without aliases', async () => {
    const f = environment(); const repository = new f.InMemoryDownloadV2Repository();
    const original = f.task(); const written = repository.upsert(original);
    assert.equal(written.request.originalUrl, original.request.originalUrl);
    assert.equal(written.persistence.expectedTotalBytes, 1000);
    assert.equal(written.runtime.pauseReason, 'none');
    assert.equal(written.timing.updatedAt, 2);
    original.request.headers.Cookie = 'mutated input'; written.request.headers.Cookie = 'mutated output';
    const read = repository.findOne({ guid: 'file' });
    assert.equal(read.request.headers.Cookie, 'synthetic');
    const patched = repository.patch({ guid: 'file' }, { progress: { receivedBytes: 50 } });
    assert.equal(patched.request.originalUrl, 'https://example.test/original');
    assert.equal(patched.persistence.expectedTotalBytes, 1000);
  });
  await check('controller identity and explicit native capability survive entity, repository and preferences', async () => {
    const f = environment(); const store = new f.ArkDownloadV2RecordStore();
    const task = f.task();
    task.request.sourceId = 'session-nonce:source-tab:controller-generation';
    task.request.nativeReason = 'custom_headers';
    task.request.fileNameLocked = true;
    f.repository.upsert(task);
    const patched = f.repository.patch({ guid: task.guid }, { progress: { receivedBytes: 24 } });
    assert.equal(patched.request.sourceId, task.request.sourceId);
    assert.equal(patched.request.nativeReason, 'custom_headers');
    await store.saveRecords([patched]);
    const restored = (await store.loadRecords())[0];
    assert.equal(restored.request.sourceId, task.request.sourceId);
    assert.equal(restored.request.nativeReason, 'custom_headers');
    assert.equal(restored.request.fileNameLocked, true);
    const raw = JSON.parse(f.values.get('download_v2_records'));
    raw[0].request.nativeReason = 'unrecognized-policy';
    f.values.set('download_v2_records', JSON.stringify(raw));
    assert.equal((await store.loadRecords())[0].request.nativeReason, undefined);
  });
  await check('preferences codec round trips recovery intent and safely defaults legacy pauses', async () => {
    const f = environment(); const store = new f.ArkDownloadV2RecordStore();
    const task = f.task('file', { status: 'paused', runtime: { platformTaskToken: 'synthetic-token', pauseReason: 'network' } });
    await store.saveRecords([task]); let records = await store.loadRecords();
    assert.equal(records[0].request.originalUrl, 'https://example.test/original');
    assert.equal(records[0].persistence.expectedTotalBytes, 1000);
    assert.equal(records[0].runtime.pauseReason, 'network');
    const raw = JSON.parse(f.values.get('download_v2_records'));
    delete raw[0].runtime.pauseReason;
    f.values.set('download_v2_records', JSON.stringify(raw)); records = await store.loadRecords();
    assert.equal(records[0].runtime.pauseReason, 'user');
    raw[0].status = 'running'; f.values.set('download_v2_records', JSON.stringify(raw));
    assert.equal((await store.loadRecords())[0].runtime.pauseReason, 'none');
    assert.equal(JSON.stringify(f.logs).includes('synthetic-token'), false);
    assert.equal(JSON.stringify(f.logs).includes('https://example.test'), false);
  });
  await check('progress bursts coalesce at 500 ms without delaying in-memory progress', async () => {
    const f = environment(); f.repository.upsert(f.task()); await f.repository.flushPersistence();
    for (let receivedBytes = 1; receivedBytes <= 50; receivedBytes++) f.repository.patch({ guid: 'file' }, { progress: { receivedBytes } });
    assert.equal(f.repository.findOne({ guid: 'file' }).progress.receivedBytes, 50);
    assert.equal(f.clock.pending(), 1); assert.equal(f.saves.length, 1);
    await f.clock.tick(499); assert.equal(f.saves.length, 1);
    await f.clock.tick(1); assert.equal(f.saves.length, 2); assert.equal(f.stored[0].progress.receivedBytes, 50);
  });
  await check('actual preferences store propagates open and flush failures and can retry both', async () => {
    const f = environment(); const store = new f.ArkDownloadV2RecordStore();
    f.preferencesState.openFailures = 1;
    await assert.rejects(store.loadRecords(), /preferences open unavailable/);
    assert.equal((await store.loadRecords()).length, 0);
    assert.equal(f.preferencesState.openAttempts, 2, 'a rejected open must not poison every future store operation');
    f.preferencesState.flushFailures = 1;
    await assert.rejects(store.saveRecords([f.task()]), /preferences flush unavailable/);
    await store.saveRecords([f.task('retried')]);
    assert.equal((await store.loadRecords())[0].guid, 'retried');
  });
  await check('continuous progress does not postpone the first pending checkpoint', async () => {
    const f = environment(); f.repository.upsert(f.task()); await f.repository.flushPersistence();
    f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 1 } }); await f.clock.tick(250);
    f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 2 } }); await f.clock.tick(250);
    assert.equal(f.saves.length, 2); assert.equal(f.stored[0].progress.receivedBytes, 2);
  });
  await check('pause, completion and metadata preempt progress timers', async () => {
    const f = environment(); f.repository.upsert(f.task()); await f.repository.flushPersistence();
    f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 200 } });
    f.repository.patch({ guid: 'file' }, { status: 'paused', runtime: { pauseReason: 'user' } }); await settle();
    assert.equal(f.clock.pending(), 0); assert.equal(f.stored[0].status, 'paused');
    assert.equal(f.stored[0].progress.receivedBytes, 200); assert.equal(f.stored[0].runtime.pauseReason, 'user');
    const current = f.repository.findOne({ guid: 'file' });
    f.repository.patch({ guid: 'file' }, { request: { ...current.request, originalUrl: 'https://example.test/new-origin' } }); await settle();
    assert.equal(f.stored[0].request.originalUrl, 'https://example.test/new-origin');
    f.repository.patch({ guid: 'file' }, { status: 'completed', progress: { receivedBytes: 1000 } }); await settle();
    assert.equal(f.stored[0].status, 'completed'); assert.equal(f.stored[0].progress.receivedBytes, 1000);
  });
  await check('explicit flush forces and awaits the latest pending progress', async () => {
    const f = environment(); f.repository.upsert(f.task()); await f.repository.flushPersistence();
    f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 42 } });
    await f.repository.flushPersistence(); assert.equal(f.clock.pending(), 0);
    assert.equal(f.stored[0].progress.receivedBytes, 42); await f.clock.tick(1000); assert.equal(f.saves.length, 2);
  });
  await check('slow writes retain only the latest snapshot and flush includes in-flight mutations', async () => {
    const f = environment(); let release;
    const gate = new Promise(resolve => { release = resolve; });
    f.state.saveHook = () => gate;
    f.repository.upsert(f.task()); await settle();
    for (let receivedBytes = 1; receivedBytes <= 100; receivedBytes++) f.repository.patch({ guid: 'file' }, { progress: { receivedBytes } });
    f.repository.patch({ guid: 'file' }, { status: 'completed' });
    const flushing = f.repository.flushPersistence();
    assert.equal(f.saves.length, 1); release(); await flushing;
    assert.equal(f.saves.length, 2); assert.equal(f.state.maxInFlight, 1);
    assert.equal(f.stored[0].progress.receivedBytes, 100); assert.equal(f.stored[0].status, 'completed');
  });
  await check('reentrant store callbacks do not create concurrent writers or lose the last write', async () => {
    const f = environment(); let once = false;
    f.state.saveHook = () => {
      if (once) return; once = true;
      f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 71 } });
    };
    f.repository.upsert(f.task()); await f.repository.flushPersistence();
    assert.equal(f.state.maxInFlight, 1); assert.equal(f.saves.length, 2); assert.equal(f.stored[0].progress.receivedBytes, 71);
  });
  await check('private, ephemeral, unconfirmed, canceled and removed records stay out of storage', async () => {
    const f = environment(); f.repository.upsert(f.task('public'));
    f.repository.upsert(f.task('private', { privacyMode: 'private', dataScope: 'session_ephemeral' }));
    f.repository.upsert(f.task('ephemeral', { dataScope: 'session_ephemeral' }));
    for (const status of ['awaiting_confirmation', 'canceled', 'removed']) f.repository.upsert(f.task(status, { status }));
    await f.repository.flushPersistence(); assert.deepEqual(f.stored.map(t => t.guid), ['public']);
    const writes = f.saves.length; f.repository.remove({ guid: 'private' }); await f.repository.flushPersistence();
    assert.equal(f.saves.length, writes);
    f.repository.patch({ guid: 'public' }, { status: 'canceled' }); await f.repository.flushPersistence();
    assert.deepEqual(f.stored, []);
  });
  await check('explicit persistence failure rejects, preserves dirty data and can be retried', async () => {
    const f = environment(); f.state.failNext = true; f.repository.upsert(f.task());
    await assert.rejects(f.repository.flushPersistence(), /disk unavailable/);
    await f.repository.flushPersistence(); assert.equal(f.stored[0].guid, 'file'); assert.equal(f.saves.length, 2);
  });
  await check('timer-driven failures are reported by the next barrier and retry saves newest data', async () => {
    const f = environment(); f.repository.upsert(f.task()); await f.repository.flushPersistence();
    f.state.failNext = true; f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 17 } });
    await f.clock.tick(500); await assert.rejects(f.repository.flushPersistence(), /disk unavailable/);
    f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 18 } }); await f.repository.flushPersistence();
    assert.equal(f.stored[0].progress.receivedBytes, 18); assert.equal(f.clock.pending(), 0);
    assert.ok(f.logs.some(args => args.some(arg => typeof arg === 'string' && arg.includes('save failed'))));
  });
  await check('checkpoint interval is configurable and zero opts into immediate persistence', async () => {
    const f = environment({ progressIntervalMs: 25 }); f.repository.upsert(f.task()); await f.repository.flushPersistence();
    f.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 1 } }); await f.clock.tick(24); assert.equal(f.saves.length, 1);
    await f.clock.tick(1); assert.equal(f.saves.length, 2);
    const immediate = environment({ progressIntervalMs: 0 }); immediate.repository.upsert(immediate.task()); await immediate.repository.flushPersistence();
    immediate.repository.patch({ guid: 'file' }, { progress: { receivedBytes: 2 } }); await settle();
    assert.equal(immediate.stored[0].progress.receivedBytes, 2); assert.equal(immediate.clock.pending(), 0);
  });
  await check('file finalization checkpoints survive preferences and preempt progress timers', async () => {
    const f = environment(); const task = f.task();
    f.repository.upsert(task); await f.repository.flushPersistence();
    f.repository.patch({ guid: task.guid }, { progress: { receivedBytes: 1000 } });
    assert.equal(f.clock.pending(), 1);
    f.repository.patch({ guid: task.guid }, { persistence: { ...task.persistence, completionState: 'finalizing' } });
    await settle(); assert.equal(f.clock.pending(), 0);
    assert.equal(f.stored[0].persistence.completionState, 'finalizing');
    const store = new f.ArkDownloadV2RecordStore();
    await store.saveRecords(f.repository.list());
    const restored = await store.loadRecords();
    assert.equal(restored[0].persistence.completionState, 'finalizing');
    assert.equal(restored[0].status, 'running');
    f.repository.patch({ guid: task.guid }, { persistence: { ...task.persistence, completionState: 'export_failed' }, status: 'failed' });
    await f.repository.flushPersistence();
    await store.saveRecords(f.repository.list());
    assert.equal((await store.loadRecords())[0].persistence.completionState, 'export_failed');
  });
  await check('saving files frees a network slot without scheduling an export as another request', () => {
    const f = environment(), policy = new f.DownloadQueuePolicyService({ maxConcurrentDownloads: 1 });
    const saving = f.task('saving', { persistence: { tempFilePath: '/sandbox/file', downloadDriver: 'arkweb', completionState: 'finalizing' } });
    const next = f.task('next', { status: 'queued' });
    const exportFailure = f.task('export', { status: 'queued', persistence: { tempFilePath: '/sandbox/export', downloadDriver: 'arkweb', completionState: 'export_failed' } });
    const admission = policy.buildSchedulePlan([saving, next, exportFailure]);
    assert.equal(admission.runningCount, 0); assert.equal(admission.queuedCount, 1);
    assert.equal(admission.nextGuid, 'next'); assert.equal(admission.canStartNow, true);
    assert.equal(policy.resolveStartAdmission([exportFailure], 'export').canStartNow, false);
  });
  await check('each task keeps its selected destination across clones and preference reloads', async () => {
    const f = environment(); const destination = { kind: 'directory', uri: 'file://docs/storage/Users/currentUser/Download/First', label: 'Download/First' };
    const task = f.task('destination', { persistence: { tempFilePath: '/sandbox/data', downloadDriver: 'arkweb', destination } });
    f.repository.upsert(task);
    destination.uri = 'file://docs/storage/Users/currentUser/Download/Changed';
    task.persistence.destination.label = 'changed';
    const copy = f.repository.findOne({ guid: 'destination' });
    assert.equal(copy.persistence.destination.label, 'Download/First');
    assert.ok(copy.persistence.destination.uri.endsWith('/First'));
    const store = new f.ArkDownloadV2RecordStore(); await store.saveRecords(f.repository.list());
    const records = await store.loadRecords();
    assert.deepEqual(JSON.parse(JSON.stringify(records[0].persistence.destination)), {
      kind: 'directory', uri: 'file://docs/storage/Users/currentUser/Download/First', label: 'Download/First'
    });
    await f.repository.flushPersistence(); const writes = f.saves.length;
    f.repository.patch({ guid: 'destination' }, { persistence: { ...copy.persistence, destination: { kind: 'file', uri: 'file://docs/saved.pdf', label: 'saved.pdf' } } });
    await settle(); assert.equal(f.saves.length, writes + 1);
    assert.equal(f.stored[0].persistence.destination.kind, 'file');
  });
  if (failures.length) throw Error(`${failures.length} repository scenarios failed`);
}
run().catch(error => { console.error(error.message); process.exitCode = 1; });

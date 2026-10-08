#!/usr/bin/env node
'use strict';

// Run the production ArkTS throttle/codec with deterministic per-record work costs.
// This measures uninterrupted main-thread work, not network latency or device FPS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function scenario() {
  let now = 1000;
  let uninterrupted = 0;
  let longest = 0;
  const sleeps = [];
  let workerOutcome;
  const modules = new Map();
  const clock = {
    now: () => now,
    work(ms) { now += ms; uninterrupted += ms; longest = Math.max(longest, uninterrupted); },
    async sleep(ms) { sleeps.push(ms); now += ms; uninterrupted = 0; },
    longest: () => longest,
    sleeps
  };
  class ControlledDate extends Date { static now() { return now; } }
  function load(relativePath) {
    if (modules.has(relativePath)) return modules.get(relativePath);
    const filename = path.join(root, relativePath);
    const module = { exports: {} };
    modules.set(relativePath, module.exports);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
      fileName: filename
    }).outputText;
    vm.runInNewContext(code, {
      module, exports: module.exports, Date: ControlledDate, ArrayBuffer, Uint8Array,
      setTimeout(callback, delay) { void clock.sleep(delay).then(callback); },
      JSON: {
        parse(value) { clock.work(value.length / 8192); return JSON.parse(value); },
        stringify(value) { const json = JSON.stringify(value); clock.work(json.length / 8192); return json; }
      },
      require(name) {
        if (name === '@kit.ArkTS') return {
          util: {
            TextEncoder: { create: () => ({ encodeInto(text) {
              clock.work(0.1 + text.length / 8192); return new TextEncoder().encode(text);
            } }) },
            TextDecoder: { create: () => ({ decodeToString(bytes) {
              clock.work(0.1 + bytes.length / 8192); return new TextDecoder().decode(bytes);
            } }) }
          },
          taskpool: {
            Task: class { setTransferList() {} }, Priority: { LOW: 2 },
            async execute(_task, priority) { assert.equal(priority, 2); return workerOutcome; }
          }
        };
        if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, error() {} } };
        if (name === '@kit.BasicServicesKit' || name === '@kit.ArkData') return {};
        if (name === '@kit.AbilityKit') return { application: { getApplicationContext: () => ({}) } };
        if (name.endsWith('/HuaweiSpaceHistorySnapshotCodec') || name.endsWith('/HistorySyncMergeService')) {
          return {}; // These worker-side algorithms are outside this transfer test.
        }
        if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
        return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
      }
    }, { filename });
    return module.exports;
  }
  const { AiraSyncWorkThrottleService } = load('services/sync/AiraSyncWorkThrottleService.ets');
  const { sharedBrowsingActivitySignal } = load('common/activity/BrowsingActivitySignal.ets');
  return { clock, load, signal: sharedBrowsingActivitySignal,
    setWorkerOutcome(value) { workerOutcome = value; },
    throttle: new AiraSyncWorkThrottleService(clock) };
}

test('a seven-item sync burst gives the event loop a turn within one frame plus one item', async () => {
  const { clock, throttle } = scenario();
  for (let i = 1; i <= 7; i++) {
    clock.work(10);
    await throttle.afterBatchItem(i);
  }
  assert.ok(clock.longest() <= 26, `small sync blocked for ${clock.longest()} ms without yielding`);
});

test('a full batch does not monopolize the main thread for hundreds of milliseconds', async () => {
  const { clock, throttle } = scenario();
  for (let i = 1; i <= 250; i++) {
    clock.work(1);
    await throttle.afterBatchItem(i);
  }
  assert.ok(clock.longest() <= 17, `full batch blocked for ${clock.longest()} ms without yielding`);
});

test('scrolling that begins inside a small batch is noticed before the next record', async () => {
  const { clock, throttle, signal } = scenario();
  await throttle.afterBatchItem(1);
  signal.markBrowsingInteraction();
  await throttle.afterBatchItem(2);
  assert.ok(clock.sleeps.length > 0, 'in-flight sync ignored the active scroll');
});

test('native settings scroll callbacks reach the same throttle as Web gestures', async () => {
  // Execute the callbacks wired on both real Scroll shells; ArkUI rendering itself is verified
  // by the native build/device repro. Testing the signal alone would miss absent UI wiring.
  const source = fs.readFileSync(path.join(root, 'app/components/settings/SettingsLayout.ets'), 'utf8');
  const callbacks = [...source.matchAll(/\.onDidScroll\(([\s\S]*?)\n    \}\)/g)];
  assert.equal(callbacks.length, 2, 'both native settings Scroll shells must report motion');
  for (const [, body] of callbacks) {
    const s = scenario();
    const js = ts.transpileModule(`const callback = ${body}\n};`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const callback = vm.runInNewContext(`${js}\ncallback`, { sharedBrowsingActivitySignal: s.signal });
    callback(0, 0);
    assert.equal(s.signal.isBrowsingRecently(), false, 'layout-only callbacks must stay quiet');
    callback(0, 12);
    assert.equal(s.signal.isBrowsingRecently(), true);
    await s.throttle.afterBatchItem(1);
    assert.ok(s.clock.sleeps.length > 0, 'native scrolling did not defer in-flight sync');
    assert.equal(s.signal.isBrowsingRecently(), true, 'sync must make progress without waiting for the gesture to end');
    callback(0, -12);
    assert.equal(s.signal.isBrowsingRecently(), true, 'reverse/fling motion must refresh the signal');
  }
});

function historyState() {
  return {
    visits: Array.from({ length: 512 }, (_, i) => ({ visitId: `visit-${i}`, clientId: 'device',
      nativeVisitId: String(i), url: `https://example.invalid/${i}`, title: '中文🙂\\\"'.repeat(80),
      visitedAt: 10000 + i, transition: 'link', referrer: '', deviceName: 'phone', source: 'local' })),
    tombstones: [{ visitId: 'deleted', deletedAt: 8000 }],
    deleteRanges: [{ rangeId: 'range', url: 'https://example.invalid/', startedAt: 1, endedAt: 100, seq: 9000 }],
    clearBefore: 500,
    retentionFrontier: { cutoffAt: 500, boundaryVisitedAt: 600, boundaryVisitId: 'boundary', updatedAt: 700 }
  };
}

test('preparing a worker task yields during encoding, not only after the entire snapshot', async () => {
  const s = scenario();
  const { AiraSyncComputeExecutor } = s.load('services/sync/AiraSyncComputeExecutor.ets');
  s.setWorkerOutcome({ errorMessage: '', remoteWriteRequired: false });
  await new AiraSyncComputeExecutor().planHuaweiHistoryReplicaPacked('uid', 'device', new ArrayBuffer(4), historyState());
  assert.ok(s.clock.longest() <= 26, `worker input packing blocked for ${s.clock.longest().toFixed(1)} ms`);
});

test('receiving a changed worker result yields while decoding the snapshot', async () => {
  const s = scenario();
  const { AiraHistoryTaskpoolTransferCodec: Codec } = s.load('services/sync/AiraHistoryTaskpoolTransferCodec.ets');
  const state = historyState();
  const packed = Codec.encodeState(state);
  const decode = scenario();
  const { AiraSyncComputeExecutor } = decode.load('services/sync/AiraSyncComputeExecutor.ets');
  decode.setWorkerOutcome({ errorMessage: '', mergedBuffer: packed,
    localApplyRequired: true, remoteWriteRequired: true });
  const empty = { ...state, visits: [] };
  const result = await new AiraSyncComputeExecutor().planHuaweiHistoryInitialMerge(empty, empty);
  assert.deepEqual(JSON.parse(JSON.stringify(result.merged)), state);
  assert.ok(decode.clock.longest() <= 26, `worker result decoding blocked for ${decode.clock.longest().toFixed(1)} ms`);
});

test('an unchanged merge yields during preflight and does not decode or apply a result', async () => {
  const s = scenario();
  const { AiraSyncComputeExecutor } = s.load('services/sync/AiraSyncComputeExecutor.ets');
  s.setWorkerOutcome({ errorMessage: '', mergedBuffer: new ArrayBuffer(0),
    localApplyRequired: false, remoteWriteRequired: false });
  const state = historyState();
  const plan = await new AiraSyncComputeExecutor().planHuaweiHistoryInitialMerge(state, state);
  assert.equal(plan.merged, state);
  assert.equal(plan.localApplyRequired, false);
  assert.equal(plan.remoteWriteRequired, false);
  assert.ok(s.clock.longest() <= 26, `unchanged sync blocked for ${s.clock.longest().toFixed(1)} ms`);
});

test('state frames preserve Unicode, visits, deletions and retention in both transfer directions', async () => {
  const s = scenario();
  const { AiraHistoryTaskpoolTransferCodec: Codec } = s.load('services/sync/AiraHistoryTaskpoolTransferCodec.ets');
  for (const state of [historyState(), { ...historyState(), visits: [], tombstones: [], deleteRanges: [] }]) {
    const syncBytes = Codec.encodeState(state);
    const asyncBytes = await Codec.encodeStateCooperatively(state, s.throttle);
    assert.deepEqual(Buffer.from(asyncBytes), Buffer.from(syncBytes));
    assert.deepEqual(JSON.parse(JSON.stringify(Codec.decodeState(asyncBytes))), state);
    const received = await Codec.decodeStateCooperatively(syncBytes, s.throttle);
    assert.deepEqual(JSON.parse(JSON.stringify(received)), state);
    assert.throws(() => Codec.decodeState(syncBytes.slice(0, syncBytes.byteLength - 1)), /truncated/);
    const trailing = new Uint8Array(syncBytes.byteLength + 1);
    trailing.set(new Uint8Array(syncBytes));
    assert.throws(() => Codec.decodeState(trailing.buffer), /trailing/);
    const badMagic = syncBytes.slice(0);
    new Uint8Array(badMagic)[0] = 0;
    assert.throws(() => Codec.decodeState(badMagic), /format/);
  }
});

test('row transfer preserves its existing binary format and yields inside encode and decode', async () => {
  const rows = Array.from({ length: 100 }, (_, i) => ({ rowId: `row-${i}`, recordKind: 'snapshot_block',
    logicalId: `logical-${i}`, data: '中文🙂'.repeat(100), updatedAt: 1700000000000 + i }));
  // Independent consumer for the existing wire layout: row count, four length-prefixed UTF-8
  // strings, then one big-endian u64 timestamp. This catches a coordinated encoder/decoder error.
  const header = Buffer.alloc(4);
  header.writeUInt32BE(rows.length);
  const expected = [header];
  for (const row of rows) {
    for (const value of [row.rowId, row.recordKind, row.logicalId, row.data]) {
      const bytes = Buffer.from(value);
      const length = Buffer.alloc(4);
      length.writeUInt32BE(bytes.length);
      expected.push(length, bytes);
    }
    const timestamp = Buffer.alloc(8);
    timestamp.writeBigUInt64BE(BigInt(row.updatedAt));
    expected.push(timestamp);
  }
  const s = scenario();
  const { AiraHistoryTaskpoolTransferCodec: Codec } = s.load('services/sync/AiraHistoryTaskpoolTransferCodec.ets');
  const packed = await Codec.encodeRowsCooperatively(rows, s.throttle);
  assert.deepEqual(Buffer.from(packed), Buffer.concat(expected));
  const decoded = await Codec.decodeRowsCooperatively(packed, s.throttle);
  assert.deepEqual(JSON.parse(JSON.stringify(decoded)), rows);
  const copied = await Codec.copyBufferCooperatively(packed, s.throttle);
  assert.notEqual(copied, packed);
  assert.deepEqual(Buffer.from(copied), Buffer.from(packed));
  assert.ok(s.clock.longest() <= 26, `row transfer blocked for ${s.clock.longest().toFixed(1)} ms`);
  assert.throws(() => Codec.decodeRows(packed.slice(0, packed.byteLength - 1)), /truncated/);
});

test('continuous scrolling yields a frame without imposing seconds of delay on every slice', async () => {
  const s = scenario();
  const sleep = s.clock.sleep;
  s.clock.sleep = async (ms) => { await sleep(ms); s.signal.markBrowsingInteraction(); };
  s.signal.markBrowsingInteraction();
  await s.throttle.afterBatchItem(1);
  const heldMs = s.clock.sleeps.reduce((a, b) => a + b, 0);
  assert.ok(heldMs > 0 && heldMs <= 16);
  const sleeps = s.clock.sleeps.length;
  s.clock.work(1);
  await s.throttle.afterBatchItem(2);
  assert.equal(s.clock.sleeps.length, sleeps, 'every record must not pay another browsing hold');
  s.clock.work(16);
  await s.throttle.afterBatchItem(3);
  assert.ok(s.clock.sleeps.length > sleeps);
  for (let i = 4; i < 14; i++) {
    s.clock.work(8);
    await s.throttle.afterBatchItem(i);
    await s.throttle.afterStage();
  }
  assert.ok(s.clock.sleeps.every(ms => ms <= 16), 'continuous gestures must not trigger polling holds');
  assert.ok(s.clock.sleeps.reduce((a, b) => a + b, 0) <= 400,
    'small multi-stage work must not accumulate tens of seconds of gesture waiting');
});

test('ordinary manual sync stays navigable while preventing duplicate requests and late dialogs', async () => {
  const source = fs.readFileSync(path.join(root, 'app/components/sync/SyncExperienceHost.ets'), 'utf8');
  const methods = ['syncNow', 'onBackPress'].map(name => {
    const match = source.match(new RegExp(`  (?:private )?${name}\\(\\): (?:void|boolean) \\{([\\s\\S]*?)\\n  \\}`));
    assert.ok(match, `missing ${name}`);
    return `${name}() {${match[1]}\n}`;
  }).join('\n');
  for (const visible of [true, false]) {
    let resolve;
    let requests = 0;
    const pending = new Promise(r => { resolve = r; });
    const js = ts.transpileModule(`class Host { ${methods} }; Host;`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const Host = vm.runInNewContext(js, { sharedSyncExperienceCoordinator: {
      syncNow() { requests++; return pending; }
    } });
    const host = new Host();
    let dialogs = 0;
    Object.assign(host, { isBusy: false, isSyncing: false, hostVisible: true,
      boundary: { privacyMode: 'normal' }, refreshState() {},
      renderOutcome() { dialogs++; }, completeProgressOutcome() { dialogs++; },
      syncProgressController: { begin() { throw new Error('manual sync opened a blocking progress modal'); } }
    });
    host.syncNow();
    assert.equal(host.isSyncing, true);
    assert.equal(host.onBackPress(), false, 'ordinary sync must permit Back');
    host.syncNow();
    assert.equal(requests, 1, 'repeat taps must not enqueue duplicate work');
    host.hostVisible = visible;
    resolve({ type: 'failed', title: 'failed', message: 'test' });
    await pending;
    await Promise.resolve();
    await Promise.resolve();
    assert.equal(dialogs, visible ? 1 : 0, 'do not open a result dialog after leaving the screen');
    assert.equal(host.isBusy, false);
    assert.equal(host.isSyncing, false);
  }
});

test('small batch boundaries during scrolling do not each incur a full-frame sleep', async () => {
  const s = scenario();
  const sleep = s.clock.sleep;
  s.clock.sleep = async ms => { await sleep(ms); s.signal.markBrowsingInteraction(); };
  s.signal.markBrowsingInteraction();
  for (let batch = 1; batch <= 180; batch++) {
    s.clock.work(1);
    await s.throttle.afterBatchItem(batch * 250);
  }
  assert.ok(s.clock.sleeps.length >= 180, 'each batch must still admit pending event-loop work');
  const sleptMs = s.clock.sleeps.reduce((a, b) => a + b, 0);
  assert.ok(sleptMs <= 400, `tiny batches accumulated ${sleptMs} ms of artificial frame waiting`);
  assert.ok(s.clock.longest() <= 8);
});

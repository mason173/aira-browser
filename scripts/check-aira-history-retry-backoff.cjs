#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceAutomaticRuntime.ets');
const moduleOutput = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, { module: moduleOutput, exports: moduleOutput.exports, require(name) {
  if (name === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
  if (name.endsWith('/AiraSyncJankProbe')) return { AiraSyncJankProbe: {
    beginStage() { return 1; }, markExtra() {}, endExtra() {}, endStage() {}
  } };
  return {};
} });

test('membership and local-change signals cannot replace a failed history retry with a five-second loop', async () => {
  // Run actual failure handling and scheduling, with only external services and the clock controlled.
  const runtime = Object.create(moduleOutput.exports.SyncExperienceAutomaticRuntime.prototype);
  let now = 100000;
  let id = 0;
  const timers = new Map();
  Object.assign(runtime, {
    historyChangeRevision: 0, historyConsecutiveFailureCount: 0, manualHistoryCoverageCount: 0,
    historyAutomaticNotBefore: 0, historyStartupQuietUntil: 0, historyTimerId: -1,
    clock: { now: () => now, setTimeout(fn, delay) { timers.set(++id, { fn, at: now + delay }); return id; },
      clearTimeout(key) { timers.delete(key); } },
    historySyncService: { async runNow() { return { ok: false, message: 'synthetic validation error' }; } },
    resolveHistoryProviderIdentity: () => 'huawei_space:test',
    isHistoryAutomaticSyncActive: () => true,
    stopNetworkRecoveryIfInactive() {}
  });
  for (const expectedDelay of [20000, 40000, 80000]) {
    await runtime.executeHistoryDomain(true, 'membership');
    const retryAt = [...timers.values()][0].at;
    assert.equal(retryAt, now + expectedDelay);
    now += 1000;
    for (const reason of ['membership', 'foreground', 'local_change', 'network_recovery']) {
      runtime.scheduleHistoryIfActive(reason, 5000);
      assert.equal(timers.size, 1);
      assert.ok([...timers.values()][0].at >= retryAt, `${reason} bypassed failure backoff`);
    }
    now = retryAt;
  }
  // A healthy local change must still bypass the normal periodic freshness delay.
  runtime.historyConsecutiveFailureCount = 0;
  runtime.historyAutomaticNotBefore = now + 180000;
  runtime.scheduleHistoryIfActive('local_change', 5000);
  assert.equal([...timers.values()][0].at, now + 5000);
});

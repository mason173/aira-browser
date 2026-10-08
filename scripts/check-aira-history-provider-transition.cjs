#!/usr/bin/env node
'use strict';

// Execute the production Provider operation and History transition with controlled
// transport results. No Huawei account, device, or production endpoint is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const modules = new Map();

function load(relativePath) {
  if (modules.has(relativePath)) return modules.get(relativePath);
  const filename = path.join(root, relativePath);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, Error,
    require(name) {
      if (name === '@kit.PerformanceAnalysisKit') {
        return { hilog: { warn() {} } };
      }
      if (name.endsWith('/AiraDistributionCapabilityOwner')) {
        return { AIRA_DISTRIBUTION_CAPABILITY_OWNER: { isAvailable: () => true } };
      }
      if (name.endsWith('/HistorySyncService')) {
        return {
          resolveHistorySyncProviderKind: (provider) =>
            ['aira_cloud', 'huawei_space', 'self_hosted'].includes(provider) ? provider : undefined
        };
      }
      if (name.endsWith('/AiraSyncModels') || name.endsWith('/MembershipFeatureKeys')) {
        return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
      }
      // All other dependencies are outside this orchestration test's execution path.
      return new Proxy({}, { get(_target, key) { throw new Error(`Unexpected dependency: ${name}.${String(key)}`); } });
    }
  }, { filename });
  modules.set(relativePath, module.exports);
  return module.exports;
}

const { SyncExperienceAutomaticRuntime } = load('core/sync/SyncExperienceAutomaticRuntime.ets');
const { SyncExperienceProviderOperations } = load('core/sync/SyncExperienceProviderOperations.ets');
const sourceError = '华为云空间历史记录同步不可用，请确认系统云空间同步已开启。';

function result(ok, message) {
  return { ok, message, appliedChangeCount: 0, uploadedMutationCount: 0 };
}

function scenario({ source = 'huawei_space', target = 'aira_cloud', sourceFails = true,
  sourceThrows = false, targetFails = false, historySelected = true } = {}) {
  const calls = [];
  const settings = {
    remoteKind: source, bookmarkSyncEnabled: true, personalizationSyncEnabled: true,
    huaweiCloud: { uid: 'same-account', displayName: '', photoUrl: '', lastAuthAt: 1 },
    huaweiSpace: { uid: 'same-account', displayName: '', photoUrl: '', lastAuthAt: 1 },
    webdav: { endpoint: 'https://example.invalid/dav' }
  };
  const local = new Set(['local-visit']);
  const oldRemote = new Set(['old-cloud-only-visit']);
  const targetRemote = new Set(['target-cloud-only-visit']);
  let bound = false;
  const runtime = Object.create(SyncExperienceAutomaticRuntime.prototype);
  runtime.experienceStateStore = {
    getState: () => ({ historySelected }),
    async setHistorySelected(selected, uid) {
      assert.equal(selected, true);
      assert.equal(uid, 'same-account');
      bound = true;
      calls.push('bind');
    }
  };
  runtime.syncConfigStore = { getSettings: () => settings };
  runtime.historySyncService = {
    async runForProvider(provider, mode) {
      calls.push(`${provider}:${mode}`);
      assert.equal(settings.remoteKind, source, 'Provider must not commit before target confirmation');
      if (mode === 'source_transition') {
        if (sourceThrows) throw new Error(sourceError);
        if (sourceFails) return result(false, sourceError);
        for (const visit of oldRemote) local.add(visit);
        return { ...result(true, '旧源同步成功'), appliedChangeCount: 1 };
      }
      assert.equal(provider, target);
      if (targetFails) return result(false, '目标历史记录同步失败');
      // The transport seam receives the existing local state, not an empty replacement.
      for (const visit of local) targetRemote.add(visit);
      for (const visit of targetRemote) local.add(visit);
      return { ...result(true, '历史记录已完成增量同步。'), uploadedMutationCount: 1 };
    }
  };
  runtime.runProviderTransition = async (operation) => operation();
  runtime.notifyHistoryProviderChanged = () => calls.push('notify');
  runtime.clearHistorySelectionForWebdav = async () => calls.push('disable-history');
  runtime.schedulePendingBookmarkSync = () => calls.push('pending-bookmarks');
  const syncService = {
    async initializeAiraSyncSettings() {},
    getAiraSyncSettings: () => settings,
    async checkHuaweiSpaceCapability() {},
    async syncBookmarksToProvider(provider, intent) {
      calls.push('bookmarks');
      assert.equal(provider, target);
      assert.equal(intent, 'provider-switch');
      return { blocked: false, conflictCount: 0, summary: '书签已同步' };
    },
    async selectActiveProvider(provider) { calls.push('commit'); settings.remoteKind = provider; },
    async selectActiveProviderWithPendingBookmarkSync(provider) { calls.push('commit'); settings.remoteKind = provider; }
  };
  const operations = new SyncExperienceProviderOperations(syncService, {
    async syncToProvider() { calls.push('personalization'); return result(true, '个性化已同步'); }
  }, { async canUse() { return { allowed: true }; }, async recordUsage() {} }, {}, runtime, {});
  return { calls, settings, local, oldRemote, targetRemote, isBound: () => bound,
    run: () => operations.selectProvider(target) };
}

test('old Huawei History failure does not block Aira selection after bookmarks succeeded', async () => {
  const s = scenario();
  const outcome = await s.run();
  assert.equal(outcome.type, 'provider-selected');
  assert.equal(s.settings.remoteKind, 'aira_cloud');
  assert.equal(s.isBound(), true);
  assert.deepEqual(s.calls, ['personalization', 'bookmarks', 'huawei_space:source_transition',
    'aira_cloud:target_transition', 'bind', 'commit', 'notify']);
  assert.deepEqual([...s.targetRemote].sort(), ['local-visit', 'target-cloud-only-visit']);
  assert.deepEqual([...s.oldRemote], ['old-cloud-only-visit']);
  assert.match(outcome.message, /原同步方式.*未.*取回/);
  assert.doesNotMatch(outcome.message, /请确认系统云空间/);
});

test('a rejected source run also falls back to local History', async () => {
  const s = scenario({ sourceThrows: true });
  assert.equal((await s.run()).type, 'provider-selected');
  assert.equal(s.settings.remoteKind, 'aira_cloud');
});

for (const sourceFails of [true, false]) {
  test(`target failure preserves old Provider and binding (sourceFails=${sourceFails})`, async () => {
    const s = scenario({ sourceFails, targetFails: true });
    const outcome = await s.run();
    assert.equal(outcome.type, 'failed');
    assert.equal(outcome.message, '目标历史记录同步失败');
    assert.equal(s.settings.remoteKind, 'huawei_space');
    assert.equal(s.isBound(), false);
    assert.equal(s.calls.includes('commit'), false);
    assert.equal(s.local.has('local-visit'), true);
    assert.deepEqual([...s.oldRemote], ['old-cloud-only-visit']);
  });
}

test('successful source refresh contributes old-cloud records before target confirmation', async () => {
  const s = scenario({ sourceFails: false });
  const outcome = await s.run();
  assert.equal(outcome.type, 'provider-selected');
  assert.deepEqual([...s.targetRemote].sort(), ['local-visit', 'old-cloud-only-visit', 'target-cloud-only-visit']);
  assert.doesNotMatch(outcome.message, /未.*取回/);
});

test('History opt-out skips both source and target runs', async () => {
  const s = scenario({ historySelected: false });
  assert.equal((await s.run()).type, 'provider-selected');
  assert.equal(s.calls.some((call) => call.includes('_transition')), false);
  assert.equal(s.isBound(), false);
});

test('WebDAV target skips unsupported History', async () => {
  const s = scenario({ target: 'webdav' });
  assert.equal((await s.run()).type, 'provider-selected');
  assert.equal(s.calls.some((call) => call.includes('_transition')), false);
  assert.equal(s.calls.includes('disable-history'), true);
});

test('returning to Huawei also tolerates an unavailable old Aira source', async () => {
  const s = scenario({ source: 'aira_cloud', target: 'huawei_space' });
  assert.equal((await s.run()).type, 'provider-selected');
  assert.equal(s.settings.remoteKind, 'huawei_space');
  assert.ok(s.calls.indexOf('huawei_space:target_transition') < s.calls.indexOf('commit'));
});

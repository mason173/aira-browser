// Regression replay of the real cold-start repositories. Only platform Preferences/files/hash APIs
// are replaced by deterministic in-memory storage; no user data or device access is performed.
// Measurements are host CPU observations, not phone startup timings. Counts expose work still
// performed for installed-but-disabled scripts before the first-paint readiness promise settles.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { performance } = require('node:perf_hooks');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const compiled = new Map();
const MiB = 1024 * 1024;
const platformRoot = '/fixture/userscript-values';
const startupStore = 'aira_browser_userscript_startup';
const startupKey = 'user_script_startup_hint';

function installed(id, enabled, sourceBytes, dependencyBytes, resourceBytes) {
  const header = '// ==UserScript==\n// @name Fixture\n// ==/UserScript==\n';
  return { id, name: id, namespace: 'fixture', version: '1', description: '', iconUrl: '',
    source: header + ' '.repeat(Math.max(0, sourceBytes - header.length)),
    sourceUrl: 'https://fixture.invalid/script.user.js', updateUrl: '', downloadUrl: '', enabled,
    matches: ['https://example.com/*'], includes: [], excludeMatches: [], excludes: [], grants: ['GM_getValue'],
    requireUrls: ['https://fixture.invalid/dependency.js'], requireSources: ['/'.repeat(dependencyBytes)],
    resources: [{ name: 'fixture', url: 'https://fixture.invalid/resource', text: 'r'.repeat(resourceBytes), mimeType: 'text/plain' }],
    connectRules: [], noframes: false, runAt: 'document-start', installSource: 'url',
    createdAt: 1, updatedAt: 1, lastCheckedAt: 0 };
}

function storage(options = {}) {
  const count = options.count ?? 4;
  const scripts = Array.from({ length: count }, (_, index) => installed('script-' + index,
    options.enabled !== false, options.sourceBytes ?? MiB, options.dependencyBytes ?? MiB,
    options.resourceBytes ?? MiB / 2));
  const entries = scripts.map(script => ({ scriptId: script.id,
    token: crypto.createHash('sha256').update(script.id).digest('hex') }));
  const manifest = { schemaVersion: 1, migrationState: 'complete', legacySource: 'none', entries,
    stateRevision: 1, stateUpdatedAt: 1, skippedScriptCount: 0, skippedUnattributedRecordCount: 0,
    unreadableLegacySnapshot: false, updatedAt: 1, completedAt: 1 };
  const files = new Map([[platformRoot + '/manifest.json', Buffer.from(JSON.stringify(manifest))]]);
  for (const entry of entries) {
    const values = [{ scriptId: entry.scriptId, key: 'fixture-value',
      valueJson: JSON.stringify('v'.repeat(options.valueBytes ?? 2 * MiB)), updatedAt: 1 }];
    files.set(platformRoot + '/scripts/' + entry.token + '.json', Buffer.from(JSON.stringify({
      schemaVersion: 1, scriptId: entry.scriptId, revision: 1, values, updatedAt: 1
    })));
    if (options.journalEntries) {
      const lines = Array.from({ length: options.journalEntries }, (_, index) => JSON.stringify({
        schemaVersion: 1, scriptId: entry.scriptId, revision: index + 2, updatedAt: index + 2,
        mutations: [{ operation: 'set', key: 'journal-value', valueJson: JSON.stringify('j'.repeat(1024)), updatedAt: index + 2 }]
      }));
      files.set(platformRoot + '/scripts/' + entry.token + '.journal', Buffer.from('\n' + lines.join('\n') + '\n'));
    }
  }
  const records = scripts.map(script => ({ scriptId: script.id, status: 'executed', lastUrl: 'https://example.com/',
    lastInjectionPhase: 'document-start', lastErrorMessage: '', lastSkipReason: '', lastBridgeCapability: '',
    lastBridgeRejectReason: '', lastRunAt: 1, lastSuccessAt: 1, lastFailureAt: 0, runCount: 1, failureCount: 0 }));
  const data = { scripts, files, preferences: new Map([
    ['aira_browser_userscripts', new Map([['user_script_settings', JSON.stringify({ scripts, autoUpdateEnabled: false, updatedAt: 1 })]])],
    ['aira_browser_userscript_risk_consent', new Map([['accepted_version', 1], ['accepted_version_at', 1]])],
    ['aira_browser_userscript_runtime_state', new Map([['user_script_runtime_state', JSON.stringify({ records, updatedAt: 1 })],
      ['user_script_value_diagnostics', '[]']])]
  ]) };
  if (options.hint !== undefined) data.preferences.set(startupStore, new Map([[startupKey,
    typeof options.hint === 'string' ? options.hint : JSON.stringify({ schemaVersion: 1, hasEnabledScripts: options.hint })]]));
  return data;
}

function environment(data, options = {}) {
  const cache = new Map();
  const metrics = { preferenceReads: [], fileReads: [], json: {}, iconSourceChars: 0, metadataClones: 0,
    fileAccesses: 0, hashCalls: 0, writes: 0, preferenceOpens: [], persistenceEvents: [], logs: [] };
  let fdSerial = 0;
  const handles = new Map();
  const dirs = new Set([platformRoot, platformRoot + '/scripts']);
  const preferences = { async getPreferences(_context, name) {
    metrics.preferenceOpens.push(name);
    if (name === 'aira_browser_userscript_runtime_state' && options.diagnosticsGate) await options.diagnosticsGate;
    if (name === startupStore && !data.preferences.has(name)) data.preferences.set(name, new Map());
    const durableValues = data.preferences.get(name);
    assert.ok(durableValues, 'unexpected preference store: ' + name);
    const values = new Map(durableValues);
    return {
      getSync(key, fallback) {
        const value = values.get(key) ?? fallback;
        metrics.preferenceReads.push({ name, key, chars: typeof value === 'string' ? value.length : 0 });
        return value;
      },
      putSync(key, value) { metrics.writes += 1; values.set(key, value);
        metrics.persistenceEvents.push({ operation: 'put', name, key, value }); },
      flushSync() { metrics.writes += 1;
        options.beforeFlush?.(name, values, metrics);
        data.preferences.set(name, new Map(values));
        metrics.persistenceEvents.push({ operation: 'flush', name }); }
    };
  } };
  const fileIo = {
    OpenMode: { READ_ONLY: 0 },
    async access(filename) { metrics.fileAccesses += 1; return dirs.has(filename) || data.files.has(filename); },
    async stat(filename) { return { size: data.files.get(filename).length }; },
    async open(filename) { const fd = ++fdSerial; handles.set(fd, filename); return { fd }; },
    async read(fd, target) {
      if (options.valuesGate) await options.valuesGate;
      const filename = handles.get(fd), bytes = data.files.get(filename);
      new Uint8Array(target).set(bytes);
      metrics.fileReads.push({ filename: filename.slice(platformRoot.length + 1), bytes: bytes.length });
      return bytes.length;
    },
    async close(file) { handles.delete(file.fd); },
    async mkdir() { assert.fail('complete manifests must not need writes'); },
    async listFile() { assert.fail('complete manifests must not need recovery scans'); }
  };
  const native = {
    '@kit.ArkData': { preferences },
    '@kit.NetworkKit': { http: {}, connection: {} },
    '@kit.CoreFileKit': { fileIo },
    '@kit.ArkTS': { buffer: Buffer, util: { TextEncoder: { create: () => ({ encodeInto: text => new Uint8Array(Buffer.from(text)) }) } } },
    '@kit.PerformanceAnalysisKit': { hilog: Object.fromEntries(['info', 'warn', 'error', 'debug'].map(level =>
      [level, (...args) => metrics.logs.push({ level, args })])) },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd() {
      metrics.hashCalls += 1;
      const hash = crypto.createHash('sha256');
      return { updateSync: blob => hash.update(blob.data), digestSync: () => ({ data: new Uint8Array(hash.digest()) }) };
    } } }
  };
  function load(relative) {
    const filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
    if (cache.has(filename)) return cache.get(filename).exports;
    if (filename.endsWith('/services/userscripts/UserScriptSourceFetchService.ets')) return { UserScriptSourceFetchService: class {} };
    if (filename.endsWith('/app/runtime/AppRuntimeContext.ets')) return { AppRuntimeContext: { getApplicationContext: () => ({ filesDir: '/fixture' }) } };
    if (filename.endsWith('/core/resources/AppResourceText.ets')) return { resolveAppResourceText: value => value };
    const module = { exports: {} }; cache.set(filename, module);
    if (!compiled.has(filename)) compiled.set(filename, ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
    }).outputText);
    const label = path.basename(filename, '.ets');
    const stat = metrics.json[label] = { parseCalls: 0, parseChars: 0, parseMs: 0, stringifyCalls: 0, stringifyChars: 0, stringifyMs: 0 };
    const trackedJson = {
      parse(value, reviver) {
        stat.parseCalls += 1; stat.parseChars += String(value).length;
        const start = performance.now();
        try { return JSON.parse(value, reviver); } finally { stat.parseMs += performance.now() - start; }
      },
      stringify(value, replacer, space) {
        stat.stringifyCalls += 1;
        const start = performance.now(), result = JSON.stringify(value, replacer, space);
        stat.stringifyMs += performance.now() - start; stat.stringifyChars += result?.length ?? 0;
        return result;
      }
    };
    vm.runInNewContext(compiled.get(filename), { module, exports: module.exports, JSON: trackedJson,
      Buffer, Uint8Array, ArrayBuffer, Error, Date, setTimeout, clearTimeout, $r: value => value,
      require(name) {
        if (name in native) return native[name];
        if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name));
        throw new Error('unexpected native import: ' + name);
      }
    }, { filename });
    if (label === 'UserScriptMetadataModels') {
      const original = module.exports.cloneInstalledUserScriptState;
      module.exports.cloneInstalledUserScriptState = value => { metrics.metadataClones += 1; return original(value); };
    }
    if (label === 'UserScriptIconService') {
      const proto = module.exports.UserScriptIconService.prototype, original = proto.recoverIconUrl;
      proto.recoverIconUrl = function (source, ...rest) { metrics.iconSourceChars += source.length; return original.call(this, source, ...rest); };
    }
    return module.exports;
  }
  const { UserScriptRepository } = load('data/userscripts/UserScriptRepository');
  const { UserScriptRiskConsentRepository } = load('data/userscripts/UserScriptRiskConsentRepository');
  const { UserScriptValueFileAdapter } = load('data/userscripts/UserScriptValueFileAdapter');
  const { UserScriptValueStateStore } = load('data/userscripts/UserScriptValueStateStore');
  const { UserScriptRuntimeStateRepository } = load('data/userscripts/UserScriptRuntimeStateRepository');
  const { UserScriptRuntimeReadinessCoordinator } = load('core/userscripts/UserScriptRuntimeReadinessCoordinator');
  const repository = new UserScriptRepository(), risk = new UserScriptRiskConsentRepository();
  const adapter = new UserScriptValueFileAdapter(platformRoot + '/values.json');
  const values = new UserScriptValueStateStore(adapter), diagnostics = new UserScriptRuntimeStateRepository();
  const readiness = new UserScriptRuntimeReadinessCoordinator(repository, risk, values, diagnostics);
  function lifecycle() {
    const { UserScriptPackageLifecycleCoordinator } = load('core/userscripts/UserScriptPackageLifecycleCoordinator');
    return new UserScriptPackageLifecycleCoordinator(repository, values, undefined,
      { canUse: async () => ({ allowed: true }), recordUsage: async () => undefined }, {}, undefined,
      { materialize: async () => ({ dependencies: { requireSources: [], resources: [] }, warnings: [] }) });
  }
  return { readiness, repository, values, metrics, lifecycle };
}

function counts(metrics) {
  return {
    preferenceChars: metrics.preferenceReads.reduce((sum, item) => sum + item.chars, 0),
    gmFileBytes: metrics.fileReads.reduce((sum, item) => sum + item.bytes, 0),
    gmFiles: metrics.fileReads.length,
    jsonParseChars: Object.values(metrics.json).reduce((sum, item) => sum + item.parseChars, 0),
    jsonStringifyChars: Object.values(metrics.json).reduce((sum, item) => sum + item.stringifyChars, 0),
    jsonParseCalls: Object.values(metrics.json).reduce((sum, item) => sum + item.parseCalls, 0),
    iconSourceChars: metrics.iconSourceChars, metadataClones: metrics.metadataClones, hashCalls: metrics.hashCalls
  };
}

async function boot(options, nativeOptions = {}) {
  const data = storage(options), e = environment(data, nativeOptions);
  const start = performance.now();
  await e.readiness.initializeExecutionState();
  const elapsedMs = Math.round((performance.now() - start) * 100) / 100;
  return { ...e, data, elapsedMs, counts: counts(e.metrics) };
}

const small = { count: 1, sourceBytes: 64, dependencyBytes: 1, resourceBytes: 0, valueBytes: 0 };
const turns = async () => { for (let turn = 0; turn < 100; turn += 1) await Promise.resolve(); };

function assertNoExecutionPayload(e) {
  assert.equal(e.metrics.fileAccesses, 0, 'disabled startup must not touch GM manifest, values or journals');
  assert.equal(e.metrics.preferenceOpens.includes('aira_browser_userscripts'), false,
    'a separate disabled hint avoids opening the large package Preferences store');
  assert.equal(e.metrics.preferenceOpens.includes('aira_browser_userscript_runtime_state'), false,
    'execution readiness does not initialize diagnostics');
  assert.equal(e.values.readReadiness().status, 'idle');
  assert.equal(e.readiness.listExecutionReadyScripts().length, 0);
}

test('indexed disabled cold boot reads no package payload or GM values while enabled scripts keep their first execution data', async () => {
  const enabled = await boot({ enabled: true, hint: true });
  const disabled = await boot({ enabled: false, hint: false });
  const clean = await boot({ count: 0, hint: false });
  assertNoExecutionPayload(disabled); assertNoExecutionPayload(clean);
  assert.ok(enabled.counts.preferenceChars > 10 * MiB && enabled.counts.preferenceChars < 16 * MiB &&
    enabled.counts.gmFileBytes > 8 * MiB, 'fixture respects the platform 16 MiB per-value Preferences limit');
  assert.equal(enabled.values.readReadiness().status, 'ready');
  assert.equal(enabled.readiness.listExecutionReadyScripts().length, 4);
  assert.equal(enabled.values.readCommittedValueJson('script-0', 'fixture-value'), JSON.stringify('v'.repeat(2 * MiB)));
  assert.ok(disabled.counts.preferenceChars < 1024);
  for (const [scenario, result] of Object.entries({ enabled, disabled, clean })) {
    console.log(JSON.stringify({ scenario, hostElapsedMs: result.elapsedMs, ...result.counts }));
  }
});

test('legacy disabled startup migrates only metadata once and does not replay retained journals', async () => {
  const result = await boot({ ...small, enabled: false, journalEntries: 2000 });
  assert.equal(result.repository.listScripts().length, 1);
  assert.equal(result.metrics.fileAccesses, 0);
  assert.equal(result.values.readReadiness().status, 'idle');
  const hint = JSON.parse(result.data.preferences.get(startupStore).get(startupKey));
  assert.equal(hint.hasEnabledScripts, false);
  const second = environment(result.data);
  await second.readiness.initializeExecutionState();
  assertNoExecutionPayload(second);
});

test('unknown, malformed and unsupported startup hints fall back to authoritative metadata', async () => {
  for (const hint of ['{', '{}', '{"schemaVersion":2,"hasEnabledScripts":false}',
    '{"schemaVersion":1,"hasEnabledScripts":"false"}']) {
    const result = await boot({ ...small, enabled: true, hint });
    assert.equal(result.readiness.findExecutionReadyScript('script-0').enabled, true);
    assert.equal(result.values.readReadiness().status, 'ready');
  }
});

test('slow diagnostics are independent of enabled or disabled execution readiness', async () => {
  const diagnosticsGate = new Promise(() => {});
  for (const enabled of [false, true]) {
    const e = environment(storage({ ...small, enabled, hint: enabled }), { diagnosticsGate });
    let settled = false;
    e.readiness.initializeExecutionState().then(() => { settled = true; });
    await turns();
    assert.equal(settled, true, 'unresolved diagnostics must not hold execution readiness');
    assert.equal(e.metrics.preferenceOpens.includes('aira_browser_userscript_runtime_state'), false);
  }
});

test('enabling a lazily loaded package restores committed GM values before publishing enabled state', async () => {
  let release;
  const valuesGate = new Promise(resolve => { release = resolve; });
  const e = environment(storage({ ...small, enabled: false, hint: false, journalEntries: 20 }), { valuesGate });
  await e.readiness.initializeExecutionState();
  const lifecycle = e.lifecycle();
  let settled = false;
  const pending = lifecycle.setScriptEnabled('script-0', true).then(() => { settled = true; });
  await turns();
  assert.equal(e.repository.findScript('script-0').enabled, false);
  assert.equal(settled, false);
  release(); await pending;
  await e.readiness.initializeExecutionState();
  assert.equal(e.repository.findScript('script-0').enabled, true);
  assert.equal(e.readiness.findExecutionReadyScript('script-0').enabled, true);
  assert.equal(e.values.readCommittedValueJson('script-0', 'journal-value'), JSON.stringify('j'.repeat(1024)));
  const fileReadCount = e.metrics.fileReads.length;
  await lifecycle.setScriptEnabled('script-0', false);
  await e.readiness.initializeExecutionState();
  await lifecycle.setScriptEnabled('script-0', true);
  await e.readiness.initializeExecutionState();
  assert.equal(e.metrics.fileReads.length, fileReadCount, 'same authoritative store is retained across toggles');
});

test('readiness rechecks a previously empty execution state after repository changes', async () => {
  const e = environment(storage({ ...small, enabled: false, hint: false }));
  await e.readiness.initializeExecutionState();
  await e.repository.initialize();
  const script = e.repository.findScript('script-0'); script.enabled = true;
  await e.repository.saveInstalledState(script);
  const first = e.readiness.initializeExecutionState(), second = e.readiness.initializeExecutionState();
  assert.equal(first, second, 'concurrent execution initialization is coalesced');
  await first;
  assert.equal(e.values.readReadiness().status, 'ready');
  assert.equal(e.readiness.findExecutionReadyScript('script-0').enabled, true);
});

test('payload persistence invalidates the hint before commit and a failed final hint remains safely unknown', async () => {
  const data = storage({ ...small, enabled: false, hint: false });
  let failFinal = false;
  const e = environment(data, { beforeFlush(name, values) {
    if (failFinal && name === startupStore && JSON.parse(values.get(startupKey)).hasEnabledScripts === true) {
      throw new Error('synthetic hint flush failure');
    }
  } });
  await e.repository.initialize();
  const script = e.repository.findScript('script-0'); script.enabled = true;
  failFinal = true;
  await e.repository.saveInstalledState(script);
  const hint = JSON.parse(data.preferences.get(startupStore).get(startupKey));
  assert.equal(hint.hasEnabledScripts, undefined);
  const writes = e.metrics.persistenceEvents.filter(event => event.operation === 'put');
  const payloadIndex = writes.findIndex(event => event.name === 'aira_browser_userscripts');
  assert.ok(payloadIndex > 0);
  assert.equal(JSON.parse(writes[payloadIndex - 1].value).hasEnabledScripts, undefined);
  const second = environment(data); await second.readiness.initializeExecutionState();
  assert.equal(second.readiness.findExecutionReadyScript('script-0').enabled, true);
});

test('failed hint invalidation leaves package and durable disabled hint unchanged', async () => {
  const data = storage({ ...small, enabled: false, hint: false });
  let failUnknown = false;
  const e = environment(data, { beforeFlush(name, values) {
    if (failUnknown && name === startupStore && JSON.parse(values.get(startupKey)).hasEnabledScripts === undefined) {
      throw new Error('synthetic invalidation flush failure');
    }
  } });
  await e.repository.initialize();
  const script = e.repository.findScript('script-0'); script.enabled = true;
  failUnknown = true;
  await assert.rejects(e.repository.saveInstalledState(script), /invalidation/);
  assert.equal(e.repository.findScript('script-0').enabled, false);
  assert.equal(JSON.parse(data.preferences.get('aira_browser_userscripts').get('user_script_settings')).scripts[0].enabled, false);
  assert.equal(JSON.parse(data.preferences.get(startupStore).get(startupKey)).hasEnabledScripts, false);
});

test('invalid authoritative metadata is preserved and never cached as all-disabled', async () => {
  const data = storage({ ...small, enabled: true });
  const broken = '{"scripts":';
  data.preferences.get('aira_browser_userscripts').set('user_script_settings', broken);
  const e = environment(data);
  await assert.rejects(e.readiness.initializeExecutionState(), /userscript-metadata-invalid-state/);
  assert.equal(data.preferences.get('aira_browser_userscripts').get('user_script_settings'), broken);
  assert.equal(data.preferences.get(startupStore).has(startupKey), false);
  assert.equal(e.metrics.fileAccesses, 0);
  assert.equal(e.readiness.listExecutionReadyScripts().length, 0);
});

test('failed package flush leaves the startup hint unknown and preserves the previous durable packages', async () => {
  const data = storage({ ...small, enabled: false, hint: false });
  let failPayload = false;
  const e = environment(data, { beforeFlush(name) {
    if (failPayload && name === 'aira_browser_userscripts') throw new Error('synthetic package flush failure');
  } });
  await e.repository.initialize();
  const script = e.repository.findScript('script-0'); script.enabled = true;
  failPayload = true;
  await assert.rejects(e.repository.saveInstalledState(script), /package flush/);
  assert.equal(e.repository.findScript('script-0').enabled, false);
  assert.equal(JSON.parse(data.preferences.get(startupStore).get(startupKey)).hasEnabledScripts, undefined);
  const second = environment(data); await second.readiness.initializeExecutionState();
  assert.equal(second.repository.findScript('script-0').enabled, false);
  assert.equal(second.metrics.fileAccesses, 0);
});

test('an unreadable retained GM document is preserved and cannot become an empty executable state', async () => {
  const data = storage({ ...small, enabled: true, hint: true });
  const filename = Array.from(data.files.keys()).find(name => name.endsWith('.json') && name.includes('/scripts/'));
  const broken = Buffer.from('{"schemaVersion":');
  data.files.set(filename, broken);
  const e = environment(data); await e.readiness.initializeExecutionState();
  assert.equal(e.readiness.findExecutionReadyScript('script-0'), undefined);
  assert.equal(e.readiness.listExecutionReadyScripts().length, 0);
  assert.equal(data.files.get(filename), broken);
});

test('install and overwrite load retained disabled metadata before duplicate checks or first enabled execution', async () => {
  const data = storage({ ...small, enabled: false, hint: false, valueBytes: 32 });
  const e = environment(data); await e.readiness.initializeExecutionState();
  const source = name => '// ==UserScript==\n// @name ' + name + '\n// @namespace fixture\n' +
    '// @match https://example.com/*\n// @run-at document-start\n// @grant GM_getValue\n// ==/UserScript==\nvoid 0;';
  const lifecycle = e.lifecycle();
  const overwrite = await lifecycle.saveInteractiveSource({ source: source('script-0'), sourceUrl: '',
    installSource: 'paste', existingScriptId: '' });
  assert.equal(overwrite.status, 'updated');
  assert.equal(overwrite.scriptId, 'script-0');
  assert.equal(e.repository.listScripts().length, 1);
  assert.equal(e.repository.findScript('script-0').enabled, false);
  assert.equal(e.metrics.fileAccesses, 0, 'overwriting a disabled package does not initialize GM values');
  const installed = await lifecycle.saveInteractiveSource({ source: source('new-script'), sourceUrl: '',
    installSource: 'paste', existingScriptId: '' });
  assert.equal(installed.status, 'installed');
  assert.equal(e.repository.listScripts().length, 2);
  assert.equal(e.readiness.findExecutionReadyScript(installed.scriptId).runAt, 'document-start');
  assert.equal(e.values.readCommittedValueJson('script-0', 'fixture-value'), JSON.stringify('v'.repeat(32)));
});

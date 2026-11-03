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
  const metrics = { preferenceReads: [], fileReads: [], packageFileReads: [], json: {}, iconSourceChars: 0, metadataClones: 0,
    fileAccesses: 0, hashCalls: 0, scalarBufferReads: 0, writes: 0, preferenceOpens: [], persistenceEvents: [], fileWrites: [], logs: [], regexCompiles: {} };
  let fdSerial = 0;
  const handles = new Map();
  const handleModes = new Map();
  const dirs = new Set([platformRoot, platformRoot + '/scripts']);
  if (Array.from(data.files.keys()).some(name => name.startsWith('/fixture/userscript-packages/'))) dirs.add('/fixture/userscript-packages');
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
    OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, CREATE: 2, TRUNC: 4, SYNC: 8, APPEND: 16 },
    async access(filename) { if (filename.startsWith(platformRoot + '/') || filename === platformRoot) metrics.fileAccesses += 1; return dirs.has(filename) || data.files.has(filename); },
    async stat(filename) { return { size: data.files.get(filename).length }; },
    async open(filename, mode = 0) {
      if ((mode & 4) !== 0) data.files.set(filename, Buffer.alloc(0));
      const fd = ++fdSerial; handles.set(fd, filename); handleModes.set(fd, mode); return { fd };
    },
    async write(fd, text) {
      const filename = handles.get(fd);
      options.beforeWrite?.(filename);
      const bytes = Buffer.from(text);
      data.files.set(filename, (handleModes.get(fd) & 16) !== 0
        ? Buffer.concat([data.files.get(filename) ?? Buffer.alloc(0), bytes]) : bytes);
      metrics.fileWrites.push({ filename, bytes: bytes.length });
      return bytes.length;
    },
    async fsync(fd) {
      if (handles.get(fd).endsWith('/manifest.json.pending') && options.manifestWriteGate) {
        await options.manifestWriteGate;
      }
    },
    async rename(from, to) {
      assert.ok(data.files.has(from));
      data.files.set(to, data.files.get(from)); data.files.delete(from);
    },
    async unlink(filename) { options.beforeUnlink?.(filename); data.files.delete(filename); },
    async read(fd, target) {
      if (options.valuesGate && handles.get(fd).startsWith(platformRoot + '/')) await options.valuesGate;
      const filename = handles.get(fd), bytes = data.files.get(filename);
      new Uint8Array(target).set(bytes);
      (filename.startsWith(platformRoot + '/') ? metrics.fileReads : metrics.packageFileReads).push({ filename: filename.slice(platformRoot.length + 1), bytes: bytes.length });
      return bytes.length;
    },
    async close(file) { handles.delete(file.fd); handleModes.delete(file.fd); },
    async mkdir(name) { assert.equal(name, '/fixture/userscript-packages'); dirs.add(name); },
    async listFile(name) { assert.equal(name, '/fixture/userscript-packages'); return Array.from(data.files.keys()).filter(p => p.startsWith(name + '/')).map(p => p.slice(name.length + 1)); }
  };
  // HarmonyOS Buffer indexing crosses a native boundary. Count those calls rather
  // than comparing V8 wall time with phone timings; bulk conversion must avoid them.
  const platformBuffer = options.countBufferIndexReads ? { from(...args) {
    const result = Buffer.from(...args);
    return new Proxy(result, { get(target, property) {
      if (typeof property === 'string' && /^\d+$/.test(property)) metrics.scalarBufferReads += 1;
      const value = Reflect.get(target, property, target);
      return typeof value === 'function' ? value.bind(target) : value;
    } });
  } } : Buffer;
  const native = {
    '@kit.ArkData': { preferences },
    '@ohos.url': { default: { URL: { parseURL: value => new URL(value) } } },
    '@kit.NetworkKit': { http: {}, connection: {} },
    '@kit.CoreFileKit': { fileIo },
    '@kit.ArkTS': { buffer: platformBuffer, util: { generateRandomUUID: () => crypto.randomUUID(), TextEncoder: { create: () => ({ encodeInto: text => new Uint8Array(Buffer.from(text)) }) } } },
    '@kit.PerformanceAnalysisKit': { hilog: Object.fromEntries(['info', 'warn', 'error', 'debug'].map(level =>
      [level, (...args) => metrics.logs.push({ level, args })])) },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createRandom: () => ({ generateRandomSync: size => ({ data: new Uint8Array(crypto.randomBytes(size)) }) }), createMd() {
      metrics.hashCalls += 1;
      const hash = crypto.createHash('sha256');
      return { updateSync: blob => hash.update(blob.data), digestSync: () => ({ data: new Uint8Array(hash.digest()) }) };
    } } }
  };
  function load(relative) {
    const filename = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
    if (cache.has(filename)) return cache.get(filename).exports;
    const nativeService = path.basename(filename).match(/^(UserScriptNative(?:Clipboard|Download|XmlHttpRequest|Cookie)Service)\.ets$/);
    if (nativeService) return { [nativeService[1]]: class {} };
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
      RegExp: new Proxy(RegExp, { construct(target, args) {
        metrics.regexCompiles[label] = (metrics.regexCompiles[label] || 0) + 1;
        return Reflect.construct(target, args);
      } }),
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
  function runtime() {
    const { UserScriptRuntimeCoordinator } = load('core/userscripts/UserScriptRuntimeCoordinator');
    const bridge = { tokenSuffix: '', setAutomaticDocumentSignalListener() {},
      resolveAutomaticDocumentSignalSecret: () => 'fixture-secret',
      registerScriptToken(id) { return 'fixture-token-' + id + this.tokenSuffix; } };
    return { bridge, coordinator: new UserScriptRuntimeCoordinator(values, diagnostics, bridge, {}, {}, readiness,
      { getPreferences: () => ({ general: { allowUserScriptsInPrivateMode: false } }) }) };
  }
  function nativeBridge() {
    const { UserScriptNativeBridgeCoordinator } = load('core/userscripts/UserScriptNativeBridgeCoordinator');
    return new UserScriptNativeBridgeCoordinator(values, { recordBridgeRejected: async () => {} }, readiness, { showMessage() {} });
  }
  const matchService = () => new (load('services/userscripts/UserScriptMatchService').UserScriptMatchService)();
  return { readiness, repository, values, metrics, lifecycle, runtime, nativeBridge, matchService,
    createValueStore: (adapter, limits) => new UserScriptValueStateStore(adapter, 0, () => 1, limits) };
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
const turns = async () => { for (let turn = 0; turn < 300; turn += 1) await Promise.resolve(); };

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
  assert.ok(enabled.counts.preferenceChars > 10 * MiB && enabled.metrics.preferenceReads.every(item => item.chars < 16 * MiB) &&
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
  assert.equal(JSON.parse(data.preferences.get('aira_browser_userscripts').get('user_script_settings')).packages[0].metadata.enabled, false);
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


test('large retained GM cache reaches first execution without per-byte native Buffer reads', async () => {
  const data = storage({ ...small, enabled: true, hint: true, valueBytes: 5 * MiB });
  const filename = Array.from(data.files.keys()).find(name => name.includes('/scripts/'));
  const document = JSON.parse(data.files.get(filename).toString());
  // JSON includes CJK, astral Unicode, NUL, escapes and an unpaired surrogate.
  const expected = JSON.stringify('中文🌏\u0000\n\"\\\ud800' + 'v'.repeat(5 * MiB));
  document.values[0].valueJson = expected;
  data.files.set(filename, Buffer.from(JSON.stringify(document)));
  const originalBytes = data.files.get(filename);
  const e = environment(data, { countBufferIndexReads: true });
  await e.readiness.initializeExecutionState();
  assert.equal(e.values.readReadiness().status, 'ready');
  assert.equal(e.readiness.findExecutionReadyScript('script-0').runAt, 'document-start');
  assert.equal(e.values.readCommittedValueJson('script-0', 'fixture-value'), expected);
  assert.equal(data.files.get(filename), originalBytes, 'startup must not rewrite retained state');
  assert.equal(e.metrics.scalarBufferReads, 0,
    'cold startup must not copy the retained cache through millions of native Buffer index reads');
});


test('GM commits keep exact UTF-8 bytes and byte capacity without per-byte native Buffer reads', async () => {
  const e = environment(storage({ count: 0 }), { countBufferIndexReads: true });
  let committed;
  const adapter = {
    readCommitted: async () => committed,
    replaceCommitted: async bytes => { committed = bytes; }
  };
  const store = e.createValueStore(adapter);
  await store.initialize();
  const expected = JSON.stringify('中文🌏\u0000\n\"\\\ud800'.repeat(10000));
  await store.commitMutations('fixture', [{ operation: 'set', key: 'cache', valueJson: expected }]);
  const document = JSON.parse(Buffer.from(committed).toString('utf8'));
  assert.equal(document.values[0].valueJson, expected);
  assert.deepEqual(Buffer.from(committed), Buffer.from(JSON.stringify(document), 'utf8'));
  const reopened = e.createValueStore(adapter);
  await reopened.initialize();
  assert.equal(reopened.readCommittedValueJson('fixture', 'cache'), expected);
  assert.equal(e.metrics.scalarBufferReads, 0);

  const limited = e.createValueStore(adapter, { maxValueBytes: MiB, maxStateBytes: committed.byteLength });
  await limited.initialize();
  const before = committed;
  await assert.rejects(limited.commitMutations('fixture', [
    { operation: 'set', key: 'extra', valueJson: JSON.stringify('中文🌏'.repeat(20)) }
  ]), /state-too-large/);
  assert.equal(committed, before, 'byte-limit rejection preserves the committed document');
});


test('deleting one package does not serialize or reparse another script large GM cache', async () => {
  const data = storage({ ...small, count: 2, enabled: true, hint: true, valueBytes: 5 * MiB });
  const e = environment(data);
  await e.readiness.initializeExecutionState();
  const retainedFile = platformRoot + '/scripts/' + crypto.createHash('sha256').update('script-1').digest('hex') + '.json';
  const retainedBytes = data.files.get(retainedFile);
  const before = counts(e.metrics);
  await e.lifecycle().deleteScript('script-0');
  const after = counts(e.metrics);
  assert.equal(e.repository.findScript('script-0'), undefined);
  assert.equal(e.values.readCommittedKeys('script-0').length, 0);
  assert.equal(e.values.readCommittedValueJson('script-1', 'fixture-value'), JSON.stringify('v'.repeat(5 * MiB)));
  assert.equal(data.files.get(retainedFile), retainedBytes);
  const reopened = environment(data);
  await reopened.readiness.initializeExecutionState();
  assert.equal(reopened.repository.findScript('script-0'), undefined);
  assert.equal(reopened.values.readCommittedKeys('script-0').length, 0);
  assert.equal(reopened.values.readCommittedValueJson('script-1', 'fixture-value'), JSON.stringify('v'.repeat(5 * MiB)));
  const work = { parseChars: after.jsonParseChars - before.jsonParseChars,
    stringifyChars: after.jsonStringifyChars - before.jsonStringifyChars };
  console.log(JSON.stringify({ scenario: 'delete-with-unrelated-5MiB-cache', ...work }));
  assert.ok(work.parseChars < 64 * 1024 && work.stringifyChars < 64 * 1024,
    'deleting a package must not encode or decode unrelated GM payloads: ' + JSON.stringify(work));
});


test('package deletion waits for durable manifest ACK before publishing and survives reopening', async () => {
  let release;
  const manifestWriteGate = new Promise(resolve => { release = resolve; });
  const data = storage({ ...small, count: 2, enabled: true, hint: true, valueBytes: 8 });
  const e = environment(data, { manifestWriteGate });
  await e.readiness.initializeExecutionState();
  let completed = false;
  const pending = e.lifecycle().deleteScript('script-0').then(() => { completed = true; });
  await new Promise(resolve => setTimeout(resolve, 25));
  await turns();
  assert.equal(completed, false);
  assert.ok(e.metrics.fileWrites.some(write => write.filename.endsWith('/manifest.json.pending')));
  assert.ok(e.repository.findScript('script-0'));
  assert.equal(e.values.readCommittedValueJson('script-0', 'fixture-value'), JSON.stringify('v'.repeat(8)));
  release(); await pending;
  const reopened = environment(data); await reopened.readiness.initializeExecutionState();
  assert.equal(reopened.repository.findScript('script-0'), undefined);
  assert.equal(reopened.values.readCommittedKeys('script-0').length, 0);
  assert.equal(reopened.values.readCommittedValueJson('script-1', 'fixture-value'), JSON.stringify('v'.repeat(8)));
});

test('failed manifest write keeps package and GM values available for retry', async () => {
  const data = storage({ ...small, count: 2, enabled: true, hint: true, valueBytes: 8 });
  let rejectWrites = true;
  const e = environment(data, { beforeWrite(filename) { if (rejectWrites && filename.startsWith(platformRoot + '/')) throw new Error('fixture-write-failed'); } });
  await e.readiness.initializeExecutionState();
  await assert.rejects(e.lifecycle().deleteScript('script-0'));
  assert.ok(e.repository.findScript('script-0'));
  assert.equal(e.values.readCommittedKeys('script-0').length, 1);
  const reopened = environment(data); await reopened.readiness.initializeExecutionState();
  assert.ok(reopened.repository.findScript('script-0'));
  assert.equal(reopened.values.readCommittedKeys('script-0').length, 1);
  rejectWrites = false;
  await e.lifecycle().deleteScript('script-0');
  assert.equal(e.repository.findScript('script-0'), undefined);
});

test('deleting a package with an empty GM document removes its manifest entry without a value revision bump', async () => {
  const data = storage({ ...small, enabled: true, hint: true });
  const filename = Array.from(data.files.keys()).find(name => name.includes('/scripts/'));
  const document = JSON.parse(data.files.get(filename).toString()); document.values = [];
  data.files.set(filename, Buffer.from(JSON.stringify(document)));
  const e = environment(data); await e.readiness.initializeExecutionState();
  const revision = e.values.readReadiness().revision;
  await e.lifecycle().deleteScript('script-0');
  assert.equal(e.values.readReadiness().revision, revision);
  assert.equal(JSON.parse(data.files.get(platformRoot + '/manifest.json')).entries.length, 0);
  assert.equal(data.files.has(filename), false);
});

test('unchanged document-start bundle reuses its GM snapshot without rescanning a large value', async () => {
  const e = environment(storage({ ...small, enabled: true, hint: true, valueBytes: 5 * MiB }));
  await e.readiness.initializeExecutionState();
  let snapshots = 0;
  const readSnapshot = e.values.readCommittedRuntimeView.bind(e.values);
  e.values.readCommittedRuntimeView = id => { snapshots += 1; return readSnapshot(id); };
  const { coordinator } = e.runtime();
  const first = coordinator.buildDocumentStartScriptBundle(false);
  const coldSnapshots = snapshots;
  let scannedChars = 0;
  const fingerprint = coordinator.buildStringFingerprint.bind(coordinator);
  coordinator.buildStringFingerprint = value => { scannedChars += value.length; return fingerprint(value); };
  for (let n = 0; n < 3; n += 1) assert.deepEqual(coordinator.buildDocumentStartScriptBundle(false), first);
  console.log(JSON.stringify({ scenario: 'warm-document-start', snapshotReads: snapshots - coldSnapshots, scannedChars }));
  assert.equal(snapshots, coldSnapshots, 'cache hits must not rebuild the committed GM snapshot');
  assert.equal(scannedChars, 0, 'cache hits must not hash megabytes of unchanged values');
});

test('document-start cache refreshes committed values, equal-length source changes, token rotation and deletion', async () => {
  const e = environment(storage({ ...small, count: 2, enabled: true, hint: true, valueBytes: 8 }));
  await e.readiness.initializeExecutionState();
  const { coordinator, bridge } = e.runtime();
  let snapshots = 0;
  const readSnapshot = e.values.readCommittedRuntimeView.bind(e.values);
  e.values.readCommittedRuntimeView = id => { snapshots += 1; return readSnapshot(id); };
  const first = coordinator.buildDocumentStartScriptBundle(false);
  await e.values.commitMutations('script-1', [{ operation: 'set', key: 'fixture-value', valueJson: '"updated"' }]);
  const changed = coordinator.buildDocumentStartScriptBundle(false);
  assert.notEqual(changed.key, first.key);
  assert.ok(changed.items.some(item => item.script.includes('"fixture-value":"updated"')));
  assert.equal(changed.items[2].script, first.items[2].script, 'unrelated script keeps its prepared bytes');
  const afterRefresh = snapshots;
  assert.deepEqual(coordinator.buildDocumentStartScriptBundle(false), changed);
  assert.equal(snapshots, afterRefresh, 'an unrelated revision must not force repeated snapshot checks');

  const script = e.repository.findScript('script-0');
  script.source = script.source.slice(0, -1) + ';';
  await e.repository.saveInstalledState(script);
  const sourceChanged = coordinator.buildDocumentStartScriptBundle(false);
  assert.notEqual(sourceChanged.items[2].script, changed.items[2].script);
  bridge.tokenSuffix = '-rotated';
  const rotated = coordinator.buildDocumentStartScriptBundle(false);
  assert.notEqual(rotated.key, sourceChanged.key);
  assert.ok(rotated.items[2].script.includes('-rotated'));

  assert.equal(coordinator.buildDocumentStartScriptBundle(true).items.length, 0);
  assert.deepEqual(coordinator.buildDocumentStartScriptBundle(false), rotated);
  await e.lifecycle().deleteScript('script-0');
  const deleted = coordinator.buildDocumentStartScriptBundle(false);
  assert.equal(deleted.items.length, rotated.items.length - 1);
  assert.equal(deleted.items.some(item => item.script.includes('fixture-token-script-0')), false);
});

test('failed GM commit leaves the cached document-start snapshot at its committed revision', async () => {
  let failWrite = false;
  const e = environment(storage({ ...small, enabled: true, hint: true }), {
    beforeWrite() { if (failWrite) throw new Error('fixture-write-failed'); }
  });
  await e.readiness.initializeExecutionState();
  const { coordinator } = e.runtime();
  const first = coordinator.buildDocumentStartScriptBundle(false);
  failWrite = true;
  await assert.rejects(e.values.commitMutations('script-0', [
    { operation: 'set', key: 'fixture-value', valueJson: '"must-not-publish"' }
  ]));
  assert.deepEqual(coordinator.buildDocumentStartScriptBundle(false), first);
  failWrite = false;
  await e.values.commitMutations('script-0', [{ operation: 'set', key: 'fixture-value', valueJson: '"committed"' }]);
  assert.notEqual(coordinator.buildDocumentStartScriptBundle(false).key, first.key);
});

test('document-end preparation does not materialize unused GM snapshots', async () => {
  const e = environment(storage({ ...small, valueBytes: 5 * MiB }));
  await e.readiness.initializeExecutionState();
  let reads = 0;
  const read = e.values.readCommittedRuntimeView.bind(e.values);
  e.values.readCommittedRuntimeView = id => { reads++; return read(id); };
  const { coordinator } = e.runtime();
  assert.ok(coordinator.buildPreparedDocumentEndSource(e.repository.listScripts()).length > 0);
  assert.equal(reads, 0);
  const manual = coordinator.buildInjectionRequests(e.repository.listScripts(), true);
  assert.equal(reads, 1);
  assert.ok(manual[0].valueSnapshotLiteral.length > 5 * MiB);
});

test('repeated large GM writes keep journal replay bounded and preserve latest values', async () => {
  const data = storage(small), e = environment(data);
  await e.readiness.initializeExecutionState();
  for (let n = 0; n < 20; n++) await e.values.commitMutations('script-0', [
    { operation: 'set', key: 'cache', valueJson: JSON.stringify('x'.repeat(200 * 1024) + n) }
  ]);
  const bytes = Array.from(data.files).filter(([name]) => name.endsWith('.journal')).reduce((sum, [, b]) => sum + b.length, 0);
  assert.ok(bytes <= MiB, 'journal must not grow with total historical writes: ' + bytes);
  const reopened = environment(data); await reopened.readiness.initializeExecutionState();
  assert.equal(reopened.values.readCommittedValueJson('script-0', 'cache'), JSON.stringify('x'.repeat(200 * 1024) + 19));
});

function runtimeValueFixture(e) {
  const calls = [], saved = new Map(), pending = [];
  const window = {};
  let rejectWrites = false, deferWrites = false;
  const respond = payload => {
    if (payload.kind === 'getValues' || payload.kind === 'getValue') {
      const values = {};
      (payload.keys || [payload.key]).forEach(key => { if (saved.has(key)) values[key] = saved.get(key); });
      return { success: true, found: payload.kind === 'getValues' || saved.has(payload.key),
        valueJson: JSON.stringify(payload.kind === 'getValues' ? values : saved.get(payload.key)) };
    }
    if (rejectWrites) return { success: false, error: 'fixture-write-failed' };
    const mutations = payload.mutations || [{ key: payload.key, valueJson: payload.valueJson }];
    const transitions = mutations.map(m => ({ key: m.key, oldValueJson: saved.has(m.key) ? JSON.stringify(saved.get(m.key)) : undefined,
      newValueJson: m.valueJson, hasNewValue: true, hasOldValue: saved.has(m.key), scriptId: 'script-0' }));
    mutations.forEach(m => saved.set(m.key, JSON.parse(m.valueJson)));
    return { success: true, commit: { revision: calls.length, transitions } };
  };
  window.__airaUserScriptNativeBridge = {
    readValue(json) { const p = JSON.parse(json); calls.push(p); return JSON.stringify(respond(p)); },
    request(json) { const p = JSON.parse(json); calls.push(p);
      const ack = () => window.__airaUserScriptValueDispatch({ id: p.id, ...respond(p) });
      if (deferWrites && p.kind.startsWith('set')) pending.push(ack); else queueMicrotask(ack);
    }
  };
  let timerSerial = 0; const timers = new Map();
  const context = vm.createContext({ window, console, URL, setTimeout: (fn, ms) => {
    const id = ++timerSerial; timers.set(id, setTimeout(fn, ms)); return id;
  }, clearTimeout: id => { clearTimeout(timers.get(id)); timers.delete(id); } });
  const injection = e.runtime().coordinator.injectionService;
  vm.runInContext(injection.buildRuntimeFactoryInstallScript(), context);
  const routes = {};
  for (const name of ['getValue', 'getValues', 'setValue', 'setValues']) routes[name] = {
    requestKind: name, capability: 'GM_' + name
  };
  const api = window.__airaUserScriptRuntimeFactoryV1({ scriptId: 'script-0', nativeBridgeToken: 'token',
    grants: { getValue: true, getValues: true, setValue: true, setValues: true }, nativeRoutes: routes });
  return { api, calls, saved, pending, reject: value => { rejectWrites = value; }, defer: value => { deferWrites = value; } };
}

test('bulk GM APIs cross the bridge once and preserve defaults, cache, provisional writes and rollback', async () => {
  const e = environment(storage(small)), f = runtimeValueFixture(e);
  const keys = Array.from({ length: 20 }, (_, i) => 'key-' + i);
  keys.forEach((key, i) => f.saved.set(key, i));
  assert.equal(Object.keys(await f.api.GM.getValues(keys)).length, 20);
  assert.equal(f.calls.length, 1, 'one bulk native read');
  f.calls.length = 0;
  const values = Object.fromEntries(keys.map(key => [key, 'new-' + key]));
  f.defer(true);
  let settled = false;
  const write = f.api.GM.setValues(values).then(() => { settled = true; });
  assert.equal(f.calls.length, 1, 'one bulk native write');
  assert.equal(f.api.GM_getValue(keys[0]), values[keys[0]], 'provisional state is visible');
  await turns(); assert.equal(settled, false, 'wait for durable ack');
  f.pending.shift()(); await write;
  f.defer(false); f.reject(true);
  await assert.rejects(f.api.GM.setValues({ 'key-0': 'rejected', extra: true }));
  assert.equal(f.api.GM_getValue('key-0'), values['key-0']);
  assert.equal(f.api.GM_getValue('extra', 'absent'), 'absent');
  const defaults = await f.api.GM.getValues({ 'key-0': 0, absent: 'fallback' });
  assert.equal(defaults.absent, 'fallback');
  assert.equal(defaults['key-0'], values['key-0']);
  f.calls.length = 0;
  const g = runtimeValueFixture(e); keys.forEach(key => g.saved.set(key, 7));
  assert.equal(Object.keys(g.api.GM_getValues(keys)).length, 20);
  assert.equal(g.calls.length, 1, 'sync batch reads all missing keys in one request');
  g.api.GM_getValues(keys); assert.equal(g.calls.length, 1, 'sync batch reuses loaded keys');
});

test('metadata-only toggle and deletion do not serialize or rewrite installed source payloads', async () => {
  const data = storage({ ...small, count: 2, sourceBytes: 2 * MiB, dependencyBytes: MiB });
  const e = environment(data); await e.repository.initialize();
  const before = counts(e.metrics), filesBefore = e.metrics.fileWrites.length;
  const script = e.repository.findScript('script-0'); script.enabled = false;
  await e.repository.saveInstalledState(script);
  await e.repository.deleteScript('script-1');
  const chars = counts(e.metrics).jsonStringifyChars - before.jsonStringifyChars;
  assert.ok(chars < 64 * 1024, 'small settings must not encode megabytes of source: ' + chars);
  assert.equal(e.metrics.fileWrites.length, filesBefore, 'unchanged payload files stay untouched');
  const reopened = environment(data); await reopened.repository.initialize();
  assert.equal(reopened.repository.listScripts().length, 1);
  assert.equal(reopened.repository.findScript('script-0').enabled, false);
  assert.equal(reopened.repository.findScript('script-0').source, script.source);
  assert.equal(reopened.repository.findScript('script-0').requireSources[0], script.requireSources[0]);
});

test('journal compaction survives interrupted cleanup and rejects a snapshot write failure without losing the previous commit', async () => {
  for (const failure of ['snapshot', 'cleanup']) {
    const data = storage(small);
    let armed = false;
    const e = environment(data, {
      beforeWrite(name) { if (armed && failure === 'snapshot' && name.endsWith('.json.pending') && name.includes('/scripts/')) throw new Error('snapshot-failed'); },
      beforeUnlink(name) { if (armed && failure === 'cleanup' && name.endsWith('.journal')) throw new Error('cleanup-interrupted'); }
    });
    await e.readiness.initializeExecutionState();
    for (let n = 0; n < 5; n++) await e.values.commitMutations('script-0', [
      { operation: 'set', key: 'cache', valueJson: JSON.stringify('x'.repeat(200 * 1024) + n) }
    ]);
    armed = true;
    const write = e.values.commitMutations('script-0', [
      { operation: 'set', key: 'cache', valueJson: JSON.stringify('x'.repeat(200 * 1024) + 'latest') }
    ]);
    if (failure === 'snapshot') await assert.rejects(write); else await write;
    const reopened = environment(data); await reopened.readiness.initializeExecutionState();
    assert.equal(reopened.values.readCommittedValueJson('script-0', 'cache'),
      JSON.stringify('x'.repeat(200 * 1024) + (failure === 'snapshot' ? 4 : 'latest')));
    assert.equal(reopened.metrics.logs.some(log => log.args.some(arg => String(arg).includes('ignored invalid records'))), false);
    await reopened.values.commitMutations('script-0', [{ operation: 'set', key: 'after', valueJson: 'true' }]);
    const again = environment(data); await again.readiness.initializeExecutionState();
    assert.equal(again.values.readCommittedValueJson('script-0', 'after'), 'true');
  }
});

test('legacy package migration keeps its original document when payload or index persistence fails', async () => {
  for (const failure of ['payload', 'index']) {
    const data = storage(small), legacy = data.preferences.get('aira_browser_userscripts').get('user_script_settings');
    const e = environment(data, {
      beforeWrite(name) { if (failure === 'payload' && name.includes('/userscript-packages/')) throw new Error('payload-failed'); },
      beforeFlush(name) { if (failure === 'index' && name === 'aira_browser_userscripts') throw new Error('index-failed'); }
    });
    await assert.rejects(e.repository.initialize());
    assert.equal(data.preferences.get('aira_browser_userscripts').get('user_script_settings'), legacy);
    const reopened = environment(data); await reopened.repository.initialize();
    assert.equal(reopened.repository.findScript('script-0').source, data.scripts[0].source);
    assert.equal(JSON.parse(data.preferences.get('aira_browser_userscripts').get('user_script_settings')).schemaVersion, 2);
  }
});

test('failed source replacement keeps old payload authoritative and restart reclaims only orphan files', async () => {
  const data = storage(small);
  let failIndex = false;
  const e = environment(data, { beforeFlush(name) {
    if (failIndex && name === 'aira_browser_userscripts') throw new Error('index-failed');
  } });
  await e.repository.initialize();
  const original = e.repository.findScript('script-0');
  const changed = { ...original, source: original.source + '\n// newer' };
  failIndex = true;
  await assert.rejects(e.repository.saveInstalledState(changed));
  assert.equal(e.repository.findScript('script-0').source, original.source);
  assert.equal(Array.from(data.files.keys()).filter(name => name.includes('/userscript-packages/')).length, 2);
  const reopened = environment(data); await reopened.repository.initialize(); await turns();
  assert.equal(reopened.repository.findScript('script-0').source, original.source);
  assert.equal(Array.from(data.files.keys()).filter(name => name.includes('/userscript-packages/')).length, 1);
  await reopened.repository.saveInstalledState(changed); await turns();
  const again = environment(data); await again.repository.initialize();
  assert.equal(again.repository.findScript('script-0').source, changed.source);
});

test('invalid split package payload fails closed without deleting files or falling back to stale packages', async () => {
  const data = storage(small), e = environment(data); await e.repository.initialize();
  const path = Array.from(data.files.keys()).find(name => name.includes('/userscript-packages/'));
  const broken = Buffer.from('{"schemaVersion":1,"source":false}'); data.files.set(path, broken);
  const reopened = environment(data); await assert.rejects(reopened.repository.initialize());
  assert.deepEqual(data.files.get(path), broken);
});

test('concurrent package updates preserve independent scripts and auto-update settings', async () => {
  const data = storage({ ...small, count: 2 }), e = environment(data); await e.repository.initialize();
  const first = e.repository.findScript('script-0'); first.enabled = false;
  const second = e.repository.findScript('script-1'); second.source += '\n// changed';
  await Promise.all([e.repository.saveInstalledState(first), e.repository.saveInstalledState(second), e.repository.setAutoUpdateEnabled(true)]);
  const reopened = environment(data); await reopened.repository.initialize();
  assert.equal(reopened.repository.findScript('script-0').enabled, false);
  assert.equal(reopened.repository.findScript('script-1').source, second.source);
  assert.equal(reopened.repository.getSettings().autoUpdateEnabled, true);
});

test('native bulk routes enforce token, grant and page checks and commit the entire batch once', async () => {
  const data = storage(small), e = environment(data); await e.readiness.initializeExecutionState();
  const script = e.repository.findScript('script-0'); script.grants = ['GM_getValues', 'GM_setValues'];
  await e.repository.saveInstalledState(script);
  const bridge = e.nativeBridge(), token = bridge.registerScriptToken('script-0');
  assert.ok(token);
  const payload = { id: 'batch', scriptId: 'script-0', token, kind: 'getValues', capability: 'GM_getValues', keys: ['fixture-value', 'missing'] };
  const read = (overrides = {}, url = 'https://example.com/') => JSON.parse(bridge.handleSynchronousValueRead(JSON.stringify({ ...payload, ...overrides }), url));
  assert.equal(read().success, true);
  assert.deepEqual(JSON.parse(read().valueJson), { 'fixture-value': '' });
  assert.equal(read({ token: 'invalid' }).success, false);
  assert.equal(read({}, 'https://unmatched.invalid/').success, false);
  assert.equal(read({ keys: 'invalid' }).success, false);
  assert.equal(read({ capability: 'GM_getValue' }).success, false, 'bulk route cannot borrow the single-read grant');
  const send = (overrides = {}) => new Promise(resolve => {
    const controller = { runJavaScript(source) {
      vm.runInNewContext(source, { window: { __airaUserScriptValueDispatch: resolve } });
      return Promise.resolve('');
    } };
    bridge.handleRequest(JSON.stringify({ ...payload, kind: 'setValues', capability: 'GM_setValues',
      mutations: [{ operation: 'set', key: 'one', valueJson: '1' }, { operation: 'set', key: 'two', valueJson: '2' }], ...overrides
    }), controller, 'tab', 'https://example.com/');
  });
  const before = e.values.readReadiness().revision;
  assert.equal((await send()).success, true);
  assert.equal(e.values.readReadiness().revision, before + 1);
  assert.equal(e.values.readCommittedValueJson('script-0', 'two'), '2');
  assert.equal((await send({ mutations: [{ operation: 'set', key: 'one', valueJson: '9' },
    { operation: 'set', key: 'two', valueJson: 'broken-json' }] })).success, false);
  assert.equal(e.values.readCommittedValueJson('script-0', 'one'), '1');
  assert.equal((await send({ mutations: [{ operation: 'delete', key: 'one' }] })).success, false);
  script.grants = ['GM_getValue']; await e.repository.saveInstalledState(script);
  assert.equal(read().success, false, 'revoked bulk grant is rejected');
  assert.equal((await send()).success, false);
});

test('repeated native URL matching reuses compiled rules including invalid regex rules', () => {
  const e = environment(storage(small)), matcher = e.matchService();
  const script = installed('script-0', true, 64, 1, 0);
  script.matches = [];
  script.includes = Array.from({ length: 200 }, (_, i) => 'https://example.com/miss-' + i + '/*');
  script.includes.push('/[/g', 'https://example.com/actual/*');
  for (let n = 0; n < 20; n++) assert.equal(matcher.matchesScript(script, 'https://example.com/actual/' + n), true);
  const compiles = e.metrics.regexCompiles.UserScriptMatchService;
  console.log(JSON.stringify({ scenario: 'repeat-native-url-match', compiles }));
  assert.equal(compiles, 202, 'each distinct rule is compiled once rather than on every check');
});

test('GM reads and key listing do not traverse unrelated committed records', async () => {
  const e = environment(storage(small));
  const values = Array.from({ length: 5000 }, (_, i) => ({ scriptId: 'unrelated', key: 'key-' + i, valueJson: '1', updatedAt: 1 }));
  values.push({ scriptId: 'target', key: 'wanted', valueJson: '42', updatedAt: 1 });
  const bytes = Buffer.from(JSON.stringify({ schemaVersion: 1, revision: 1, values, updatedAt: 1 }));
  const store = e.createValueStore({ readCommitted: async () => bytes, replaceCommitted: async () => {} });
  await store.initialize();
  let visited = 0;
  store.document.values = new Proxy(store.document.values, { get(target, key, receiver) {
    if (typeof key === 'string' && /^\d+$/.test(key)) visited++;
    return Reflect.get(target, key, receiver);
  } });
  for (let n = 0; n < 100; n++) assert.equal(store.readCommittedValueJson('target', 'wanted'), '42');
  assert.deepEqual(Array.from(store.readCommittedKeys('target')), ['wanted']);
  assert.equal(store.readCommittedRuntimeView('target').snapshotLiteral, '{"wanted":42}');
  console.log(JSON.stringify({ scenario: 'indexed-gm-reads', visited }));
  assert.equal(visited, 0, 'read indexes must avoid scans of the full committed document');
});

test('one script writing a value does not rebuild another script large prepared snapshot', async () => {
  const data = storage({ ...small, count: 2, valueBytes: 5 * MiB });
  const e = environment(data); await e.readiness.initializeExecutionState();
  const { coordinator } = e.runtime(); coordinator.buildDocumentStartScriptBundle(false);
  const reads = [];
  const original = e.values.readCommittedRuntimeView.bind(e.values);
  e.values.readCommittedRuntimeView = id => { reads.push(id); return original(id); };
  await e.values.commitMutations('script-0', [{ operation: 'set', key: 'small', valueJson: '1' }]);
  coordinator.buildDocumentStartScriptBundle(false);
  console.log(JSON.stringify({ scenario: 'per-script-prepared-invalidation', reads }));
  assert.deepEqual(reads, ['script-0']);
});

test('a small GM mutation computes transitions with linear work as saved key count grows', async () => {
  const e = environment(storage(small));
  const records = Array.from({ length: 1000 }, (_, i) => ({ scriptId: 'script', key: 'key-' + i, valueJson: String(i), updatedAt: 1 }));
  const store = e.createValueStore({
    readCommitted: async () => Buffer.from(JSON.stringify({ schemaVersion: 1, revision: 1, values: records, updatedAt: 1 })),
    replaceCommitted: async () => {}
  });
  await store.initialize();
  let identities = 0;
  const original = store.buildRecordIdentity.bind(store);
  store.buildRecordIdentity = (...args) => { identities++; return original(...args); };
  const result = await store.commitMutations('script', [
    { operation: 'set', key: 'key-10', valueJson: '42' }, { operation: 'delete', key: 'key-20', valueJson: '' },
    { operation: 'set', key: 'key-30', valueJson: '30' }
  ]);
  assert.deepEqual(Array.from(result.transitions, t => [t.key, t.hasNewValue, t.newValueJson]), [
    ['key-10', true, '42'], ['key-20', false, '']
  ]);
  console.log(JSON.stringify({ scenario: 'small-write-with-1000-keys', identities }));
  assert.ok(identities <= records.length * 20, 'transition calculation must not scan every key for every record: ' + identities);
});

test('cached native rules preserve exclusions, global/sticky flags, edits and bounded eviction', () => {
  const e = environment(storage(small)), matcher = e.matchService();
  const script = installed('script-0', true, 64, 1, 0);
  const window = {};
  vm.runInNewContext(e.runtime().coordinator.injectionService.buildUrlMatcherInstallScript(), { window, URL });
  const cases = [
    { matches: ['*://*.example.com/*'], url: 'https://child.example.com/a?b=1#c', expected: true },
    { matches: ['*://*.example.com/*'], excludeMatches: ['*://child.example.com/private/*'], url: 'https://child.example.com/private/a', expected: false },
    { includes: ['/https:\\/\\/example\\.com\\/a/g'], url: 'https://example.com/a', expected: true },
    { includes: ['/https:\\/\\/example\\.com\\/a/y'], url: 'https://example.com/a', expected: true },
    { includes: ['https://example.com/*'], excludes: ['/private/g'], url: 'https://example.com/private', expected: false },
    { includes: ['/[/g'], url: 'https://example.com/a', expected: false },
    { matches: ['<all_urls>'], url: 'file://example.com/a', expected: false },
    { matches: ['*://wk.baidu.com/view/*'], url: 'https://wk.baidu.com/tfview/a', expected: true },
    { matches: ['*://example.com/new/*'], url: 'https://example.com/old/a', expected: false },
    { matches: ['*://example.com/old/*'], url: 'https://example.com/old/a', expected: true }
  ];
  for (const sample of cases) {
    Object.assign(script, { matches: [], includes: [], excludeMatches: [], excludes: [] }, sample);
    for (let n = 0; n < 3; n++) {
      assert.equal(matcher.matchesScript(script, sample.url), sample.expected);
      const web = !window.__airaUserScriptIsExcludedV1(sample.url, script.excludeMatches, script.excludes) &&
        window.__airaUserScriptMatchesV1(sample.url, script.matches, script.includes);
      assert.equal(web, sample.expected);
    }
  }
  for (let n = 0; n < 700; n++) {
    script.matches = []; script.includes = ['https://example.com/path-' + n];
    assert.equal(matcher.matchesScript(script, script.includes[0]), true);
  }
  assert.ok(matcher.regexCache.size <= 512);
  script.includes = ['https://example.com/path-0'];
  assert.equal(matcher.matchesScript(script, script.includes[0]), true, 'evicted rule can compile again');
  let parsed = 0;
  const parse = matcher.parseUrl.bind(matcher);
  matcher.parseUrl = url => { parsed++; return parse(url); };
  assert.equal(matcher.resolveMatchingScripts([script, { ...script, enabled: false }, { ...script, id: 'second' }], script.includes[0]).length, 2);
  assert.equal(parsed, 1, 'one URL parse per matching batch');
});

test('GM read indexes and per-script versions publish only after durable ACK, including deletion and recreation', async () => {
  const e = environment(storage(small));
  let release, rejectWrite, persist;
  const ready = Buffer.from(JSON.stringify({ schemaVersion: 1, revision: 5, updatedAt: 1, values: [
    { scriptId: 'target', key: 'key', valueJson: '1', updatedAt: 1 },
    { scriptId: 'other', key: 'same', valueJson: '2', updatedAt: 1 }
  ] }));
  const store = e.createValueStore({ readCommitted: async () => ready, replaceCommitted: bytes => persist(bytes) });
  await store.initialize();
  const oldVersion = store.readCommittedScriptRevision('target');
  let entered;
  const enteredWrite = new Promise(resolve => { entered = resolve; });
  persist = () => { entered(); return new Promise((yes, no) => { release = yes; rejectWrite = no; }); };
  const pending = store.commitMutations('target', [{ operation: 'set', key: 'key', valueJson: '3' }]);
  await enteredWrite;
  assert.equal(store.readCommittedValueJson('target', 'key'), '1');
  assert.equal(store.readCommittedScriptRevision('target'), oldVersion);
  rejectWrite(new Error('not durable')); await assert.rejects(pending);
  assert.equal(store.readCommittedValueJson('target', 'key'), '1');
  assert.equal(store.readCommittedScriptRevision('target'), oldVersion);
  persist = async () => {};
  await store.commitMutations('target', [{ operation: 'set', key: 'key', valueJson: '3' }]);
  assert.equal(store.readCommittedValueJson('target', 'key'), '3');
  assert.equal(store.readCommittedScriptRevision('target'), 6);
  assert.equal(store.readCommittedScriptRevision('other'), 5);
  await store.deletePackageValues('target');
  assert.equal(store.readCommittedRuntimeView('target').snapshotLiteral, '{}');
  assert.equal(store.readCommittedKeys('target').length, 0);
  await store.commitMutations('target', [{ operation: 'set', key: '__proto__', valueJson: '4' }]);
  assert.equal(store.readCommittedValueJson('target', '__proto__'), '4');
  assert.equal(store.readCommittedValueJson('target', 'key'), undefined);
  assert.equal(store.readCommittedScriptRevision('other'), 5);
  const projection = store.readScriptManagementProjection('other'); projection.records[0].valueJson = '999';
  assert.equal(store.readCommittedValueJson('other', 'same'), '2', 'management must receive detached records');
});

test('synchronous GM commits update the same indexed read projections and preserve them on failure', async () => {
  const e = environment(storage(small));
  let fail = false;
  const store = e.createValueStore({
    readCommitted: async () => Buffer.from('{"schemaVersion":1,"revision":0,"updatedAt":0,"values":[]}'),
    replaceCommitted: async () => {}, replaceCommittedSync: () => { if (fail) throw new Error('failed'); }
  });
  await store.initialize();
  await store.commitMutations('script', [{ operation: 'set', key: 'one', valueJson: '1' }]);
  assert.equal(store.readCommittedValueJson('script', 'one'), '1');
  fail = true;
  await assert.rejects(store.commitMutations('script', [{ operation: 'set', key: 'one', valueJson: '2' }]));
  assert.equal(store.readCommittedScriptRevision('script'), 1);
  assert.equal(store.readCommittedValueJson('script', 'one'), '1');
  fail = false;
  await store.deletePackageValues('script');
  assert.equal(store.readCommittedRuntimeView('script').snapshotLiteral, '{}');
});

test('clearing imported revision-zero values invalidates their snapshot token', async () => {
  const e = environment(storage(small));
  const store = e.createValueStore({
    readCommitted: async () => Buffer.from(JSON.stringify({ schemaVersion: 1, revision: 0, updatedAt: 0,
      values: [{ scriptId: 'script', key: 'saved', valueJson: '1', updatedAt: 0 }] })),
    replaceCommitted: async () => {}
  });
  await store.initialize();
  const token = store.readCommittedScriptRevision('script');
  const unchanged = await store.commitMutations('script', [{ operation: 'set', key: 'saved', valueJson: '1' }]);
  assert.equal(unchanged.changed, false);
  assert.equal(store.readCommittedScriptRevision('script'), token);
  await store.deletePackageValues('script');
  assert.notEqual(store.readCommittedScriptRevision('script'), token);
  assert.equal(store.readCommittedRuntimeView('script').snapshotLiteral, '{}');
});

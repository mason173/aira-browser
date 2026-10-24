// Replay the real cold-start owners with persisted metadata and retained native files.
// This measures which expensive boundaries are crossed, not HarmonyOS device timings.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const DAY = 24 * 60 * 60 * 1000;
const nativeRoot = '/fixture/files/adblock-native-provider-v1';
const ownerPaths = [
  'common/models/BrowserModels', 'features/adblock/AdBlockBuiltInRuleSource',
  'features/adblock/AdBlockThirdPartyRuleSourceCatalog', 'data/adblock/AdBlockRepository',
  'core/adblock/AdBlockRuntimeGenerationCoordinator', 'core/adblock/AdBlockNativeAuthorityMetrics',
  'core/adblock/AdBlockRuleSourceCoordinator', 'core/browser/BrowserAdBlockCoordinator',
  'services/adblock/AdBlockNativeRuleProviderService', 'services/adblock/AdBlockNativeAuthorityEngineService',
  'services/adblock/AdBlockLocalRuleFileService', 'services/adblock/AdBlockRuleListFetchService',
  'services/adblock/AdBlockRuleSourceMetadataService', 'services/adblock/AdBlockSubscriptionPolicyService',
  'services/adblock/AdBlockSubscriptionPreprocessorService'
];
const ownerSet = new Set(ownerPaths.map(value => path.join(root, value + '.ets')));
const compiled = new Map();

function fixture({ enabled = false, sourceEnabled = true, dueSources = 6 } = {}) {
  const events = { preferenceReads: [], preferenceBytes: 0, fileCalls: [], fileReads: [],
    nativeLoads: 0, nativeBuilds: [], nativeReleases: [], httpRequests: [], merges: 0, flushes: 0 };
  const values = new Map();
  const files = new Map();
  const opened = new Map();
  const modules = new Map();
  let requestHandler = async () => { throw new Error('Offline fixture'); };
  const store = {
    getSync(key, fallback) {
      events.preferenceReads.push(key);
      const value = values.has(key) ? values.get(key) : fallback;
      events.preferenceBytes += typeof value === 'string' ? Buffer.byteLength(value) : 0;
      return value;
    },
    putSync(key, value) { values.set(key, value); },
    deleteSync(key) { values.delete(key); },
    flushSync() { events.flushes++; }
  };
  const fileIo = new Proxy({
    OpenMode: { READ_ONLY: 0 },
    async access(address) { return address === nativeRoot || files.has(address); },
    async stat(address) {
      const file = files.get(address);
      if (!file) throw new Error('No fixture file: ' + address);
      return { size: file.size, isDirectory: () => false };
    },
    async open(address) {
      assert.ok(files.has(address), 'file must be present: ' + address);
      const fd = opened.size + 1;
      opened.set(fd, address);
      return { fd };
    },
    async read(fd, buffer) {
      const address = opened.get(fd);
      events.fileReads.push(address);
      const file = files.get(address);
      assert.notEqual(file.text, undefined, 'retained raw payload must not be read: ' + address);
      const bytes = Buffer.from(file.text);
      new Uint8Array(buffer).set(bytes);
      return bytes.length;
    },
    async close() {}
  }, {
    get(target, key) {
      if (key in target && typeof target[key] !== 'function') return target[key];
      return (...args) => {
        events.fileCalls.push({ operation: key, path: args[0] });
        if (!(key in target)) throw new Error('Unexpected file operation: ' + key);
        return target[key](...args);
      };
    }
  });
  const context = { hasApplicationContext: () => true,
    getApplicationContext: () => ({ filesDir: '/fixture/files' }) };
  const platform = {
    '@kit.ArkData': { preferences: { async getPreferences() { return store; } } },
    '@kit.ArkTS': {
      util: { TextEncoder: { create: () => ({ encodeInto: value => new TextEncoder().encode(value) }) },
        TextDecoder: { create: () => ({ decodeWithStream: value => new TextDecoder().decode(value) }) } },
      taskpool: { Task: class {}, Priority: { LOW: 0 }, async execute() { events.merges++; throw new Error('Unexpected merge'); } }
    },
    '@kit.CoreFileKit': { fileIo },
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
      createHttp: () => ({ async request(address) {
        events.httpRequests.push(address);
        return requestHandler(address);
      }, destroy() {} }) } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {} } },
    '@kit.BasicServicesKit': { systemDateTime: { getUptime: () => 0 } }
  };
  const native = { async buildEngine(address) {
    events.nativeBuilds.push(address);
    return { handle: events.nativeBuilds.length, networkRuleCount: 600000, cosmeticRuleCount: 0, ruleCount: 600000 };
  }, releaseEngine(handle) { events.nativeReleases.push(handle); }, backendVersion: () => 'fixture' };
  function load(filename) {
    if (modules.has(filename)) return modules.get(filename).exports;
    const module = { exports: {} };
    modules.set(filename, module);
    let code = compiled.get(filename);
    if (!code) {
      code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
      }).outputText;
      compiled.set(filename, code);
    }
    vm.runInNewContext(code, { module, exports: module.exports, Date, $r: name => name,
      require(name) {
        if (name in platform) return platform[name];
        if (name === 'libaira_adblock.so') { events.nativeLoads++; return { default: native }; }
        if (name.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: context };
        if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
        const dependency = path.resolve(path.dirname(filename), name + '.ets');
        if (ownerSet.has(dependency)) return load(dependency);
        // Browser instance-only services are not constructed by its static cold-start entry point.
        if (name.endsWith('/BrowserPrivacyEffectPolicyService')) return { BrowserPrivacyEffectPolicyService: class {} };
        if (name.endsWith('/BrowserProfileBoundaryService')) return { BrowserProfileBoundaryService: class {} };
        return {};
      }
    }, { filename });
    return module.exports;
  }
  const get = name => load(path.join(root, name + '.ets'));
  const catalog = get('features/adblock/AdBlockThirdPartyRuleSourceCatalog').getAdBlockThirdPartyRuleSources();
  const sources = catalog.map((source, index) => ({ ...source,
    sourceType: 'remote', enabled: sourceEnabled, payloadIdentity: 'raw-v1-' + String(index).padStart(16, '0'),
    ruleCount: 100000, nativeNetworkRuleCount: 100000, nativeCosmeticRuleCount: 0,
    createdAt: 1, updatedAt: 1, lastUpdatedAt: index < dueSources ? 1 : Date.now(),
    lastError: '', updateIntervalMs: DAY, lastAttemptAt: 0
  }));
  const settings = { preferences: { enabled, updateOnForeground: true }, siteExceptions: [], customRuleSources: sources,
    stats: { statisticsVersion: 2, dailyProtectionActivity: [] }, lastRuleUpdateAt: 1, updatedAt: 1 };
  values.set('ad_block_settings', JSON.stringify(settings));
  values.set('ad_block_runtime_boot_settings', JSON.stringify(settings));
  for (const key of ['ad_block_engine_epoch', 'ad_block_legacy_payload_cleanup_epoch', 'ad_block_native_artifact_cleanup_epoch']) {
    values.set(key, 'rust-v1');
  }
  // Retain 24 MiB of already-downloaded sources without allocating or parsing it in the harness.
  for (const source of sources) files.set(nativeRoot + '/source-' + source.id + '.txt', { size: 4 * 1024 * 1024 });
  files.set(nativeRoot + '/enabled-rules.txt', { size: 24 * 1024 * 1024 });
  const manifest = JSON.stringify({ schemaVersion: 5,
    identity: 'v5:' + sources.map(source => source.id + ':' + source.payloadIdentity).join('|'),
    sourceIds: sources.map(source => source.id), sourcePayloadIdentities: sources.map(source => source.payloadIdentity),
    ruleLineCount: 600000 });
  files.set(nativeRoot + '/manifest.json', { text: manifest, size: Buffer.byteLength(manifest) });
  const { AdBlockRepository } = get('data/adblock/AdBlockRepository');
  const repository = new AdBlockRepository();
  const { BrowserAdBlockCoordinator } = get('core/browser/BrowserAdBlockCoordinator');
  return { events, repository, settings, values, get,
    setRequestHandler(handler) { requestHandler = handler; },
    boot: () => BrowserAdBlockCoordinator.prepareRuntimeBootStateForRepository(repository),
    sourceCoordinator: () => new (get('core/adblock/AdBlockRuleSourceCoordinator').AdBlockRuleSourceCoordinator)(repository) };
}

test('disabled cold boot retains six downloaded sources without file I/O or native engine loading', async () => {
  const f = fixture();
  await f.boot();
  assert.equal(f.repository.getSettings().customRuleSources.length, 6);
  assert.equal(f.repository.getSettings().preferences.enabled, false);
  assert.equal(f.events.fileCalls.length, 0);
  assert.equal(f.events.nativeLoads, 0);
  assert.equal(f.events.httpRequests.length, 0);
  assert.equal(f.events.merges, 0);
  assert.ok(f.events.preferenceBytes < 32 * 1024, 'boot reads metadata, not downloaded lists');
});

test('disabled individual sources do not load payloads even with the global switch enabled', async () => {
  const f = fixture({ enabled: true, sourceEnabled: false });
  await f.boot();
  assert.equal(f.events.fileCalls.length, 0);
  assert.equal(f.events.nativeLoads, 0);
});

test('enabled cold boot with matching manifest reaches one native build without rereading source payloads', async () => {
  const f = fixture({ enabled: true });
  await f.boot();
  assert.equal(f.events.nativeLoads, 1);
  assert.deepEqual(f.events.nativeBuilds, [nativeRoot + '/enabled-rules.txt']);
  assert.deepEqual(f.events.fileReads, [nativeRoot + '/manifest.json']);
  assert.equal(f.events.merges, 0);
  assert.equal(f.events.httpRequests.length, 0);
});

test('automatic foreground maintenance stays idle when globally disabled despite retained enabled subscriptions', async () => {
  const f = fixture();
  await f.boot();
  await f.sourceCoordinator().autoUpdateDueRemoteSources();
  assert.equal(f.events.httpRequests.length, 0, 'disabled filtering must not refresh retained subscription payloads');
  assert.equal(f.events.nativeLoads, 0);
});

test('automatic updates still check all due subscriptions while globally enabled', async () => {
  const f = fixture({ enabled: true });
  await f.boot();
  await f.sourceCoordinator().autoUpdateDueRemoteSources();
  assert.equal(f.events.httpRequests.length, 6);
});

for (const outcome of ['success', 'failure', 'success with include']) {
  test('disabling during an automatic download preserves retained sources after late ' + outcome, async () => {
    const f = fixture({ enabled: true });
    await f.boot();
    const before = f.repository.getSettings().customRuleSources;
    let resolve, reject;
    const response = new Promise((yes, no) => { resolve = yes; reject = no; });
    let first = true;
    f.setRequestHandler(() => {
      if (first) { first = false; return response; }
      throw new Error('Later request should never start');
    });
    const refresh = f.sourceCoordinator().autoUpdateDueRemoteSources();
    for (let turn = 0; turn < 100 && f.events.httpRequests.length === 0; turn++) await Promise.resolve();
    assert.equal(f.events.httpRequests.length, 1, 'one request was already in flight');
    const runtime = f.get('core/adblock/AdBlockRuntimeGenerationCoordinator')
      .AdBlockRuntimeGenerationCoordinator.forRepository(f.repository);
    await runtime.updatePreferences({ enabled: false, updateOnForeground: true });
    const fileCallsBeforeResponse = f.events.fileCalls.length;
    if (outcome === 'failure') reject(new Error('Late download failure'));
    else resolve({ responseCode: 200, result: outcome === 'success with include'
      ? '!#include child.txt\n||new-ad.example^' : '||new-ad.example^' });
    await refresh;
    assert.equal(f.events.httpRequests.length, 1, 'disable must stop subsequent sources');
    assert.equal(f.events.fileCalls.length, fileCallsBeforeResponse, 'late payload must not stage or validate');
    assert.equal(f.events.nativeBuilds.length, 1, 'only the original enabled boot may build an engine');
    assert.equal(f.events.nativeReleases.length, 1, 'disabling releases that engine');
    assert.deepEqual(f.repository.getSettings().customRuleSources, before,
      'late success/failure cannot replace rules, error status, or retry timestamps');
  });
}

test('explicit manual refresh remains available while filtering is disabled', async () => {
  const f = fixture({ sourceEnabled: false });
  await f.boot();
  const source = f.repository.getSettings().customRuleSources[0];
  await f.sourceCoordinator().fetchAndStore(source.url, source);
  assert.equal(f.events.httpRequests.length, 1);
});

test('disabling one in-flight subscription stops its child requests and preserves its retained metadata', async () => {
  const f = fixture({ enabled: true, dueSources: 1 });
  await f.boot();
  let resolve;
  const response = new Promise(yes => { resolve = yes; });
  f.setRequestHandler(() => response);
  const refresh = f.sourceCoordinator().autoUpdateDueRemoteSources();
  for (let turn = 0; turn < 100 && f.events.httpRequests.length === 0; turn++) await Promise.resolve();
  assert.equal(f.events.httpRequests.length, 1);
  const runtime = f.get('core/adblock/AdBlockRuntimeGenerationCoordinator')
    .AdBlockRuntimeGenerationCoordinator.forRepository(f.repository);
  const sourceId = f.repository.getSettings().customRuleSources[0].id;
  await runtime.updateCustomRuleSourceEnabled(sourceId, false);
  const disabled = f.repository.getSettings().customRuleSources;
  const fileCallsBeforeResponse = f.events.fileCalls.length;
  resolve({ responseCode: 200, result: '!#include child.txt\n||new-ad.example^' });
  await refresh;
  assert.equal(f.repository.getSettings().preferences.enabled, true);
  assert.equal(f.events.httpRequests.length, 1, 'disabled sources must stop their include expansion');
  assert.equal(f.events.fileCalls.length, fileCallsBeforeResponse);
  assert.deepEqual(f.repository.getSettings().customRuleSources, disabled);
});

for (const pausedPhase of ['stage', 'validation', 'commit']) {
  test('disable during automatic ' + pausedPhase + ' discards the candidate and preserves active payload metadata', async () => {
    const f = fixture({ enabled: true });
    await f.boot();
    const before = f.repository.getSettings().customRuleSources;
    const coordinator = f.sourceCoordinator();
    let release;
    const pause = new Promise(resolve => { release = resolve; });
    let waiting = false, validations = 0, commits = 0, rollbacks = 0, discards = 0;
    let activePayload = 'retained';
    async function pauseAt(phase) {
      if (phase === pausedPhase) { waiting = true; await pause; }
    }
    // Control only the provider transaction boundary; the caller, generations,
    // repository and runtime preference mutation remain production code.
    coordinator.nativeRuleProvider = {
      async stageSourcePayload() { await pauseAt('stage'); },
      async validateStagedSourcePayload() {
        validations++;
        await pauseAt('validation');
        return { identity: 'raw-v1-ffffffffffffffff', networkRuleCount: 1, cosmeticRuleCount: 0, ruleCount: 1 };
      },
      async commitStagedSourcePayload() { commits++; activePayload = 'candidate'; await pauseAt('commit'); },
      async rollbackStagedSourcePayload() { rollbacks++; activePayload = 'retained'; },
      async discardStagedSourcePayload() { discards++; },
      async reconcile() { assert.fail('a cancelled candidate must not reconcile'); }
    };
    f.setRequestHandler(async () => ({ responseCode: 200, result: '||new-ad.example^' }));
    const refresh = coordinator.autoUpdateDueRemoteSources();
    for (let turn = 0; turn < 100 && !waiting; turn++) await Promise.resolve();
    assert.ok(waiting, 'the requested asynchronous boundary was reached');
    const runtime = f.get('core/adblock/AdBlockRuntimeGenerationCoordinator')
      .AdBlockRuntimeGenerationCoordinator.forRepository(f.repository);
    await runtime.updatePreferences({ enabled: false, updateOnForeground: true });
    release();
    await refresh;
    assert.equal(f.events.httpRequests.length, 1);
    assert.equal(validations, pausedPhase === 'stage' ? 0 : 1, 'disable must not start a new native validation');
    assert.equal(commits, pausedPhase === 'commit' ? 1 : 0);
    assert.equal(rollbacks, pausedPhase === 'commit' ? 1 : 0);
    assert.equal(discards, pausedPhase === 'commit' ? 0 : 1);
    assert.equal(activePayload, 'retained');
    assert.equal(f.events.nativeBuilds.length, 1);
    assert.deepEqual(f.repository.getSettings().customRuleSources, before);
  });
}

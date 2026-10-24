// Replay the production session owners after disabled startup deliberately leaves script data unloaded.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/core/userscripts');
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
function load(name) {
  const module = { exports: {} };
  const filename = path.join(root, name + '.ets');
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  const imports = {
    './UserScriptsSettingsViewModel': { UserScriptsSettingsViewModel: class {
      buildState(scripts, autoUpdateEnabled) { return { scripts, autoUpdateEnabled }; }
      buildValueRecoveryState(projection) { return projection; }
    } },
    './UserScriptDetailViewModel': { UserScriptDetailViewModel: class {} },
    '../../data/preferences/SettingsNoticeDismissalRepository': { SETTINGS_NOTICE_USER_SCRIPTS: 'userscripts' },
    '../resources/AppResourceText': { resolveAppResourceText: text => text },
    '../../features/userscripts/UserScriptMetadataModels': { resolveUserScriptPackageSource: value => value },
    '../../services/userscripts/UserScriptSourceFetchService': { USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE: 'download failed' }
  };
  new Function('module', 'exports', 'require', '$r', code)(module, module.exports, id => imports[id] ?? {}, text => text);
  return module.exports;
}
const management = load('UserScriptManagementSessionCoordinator');
const install = load('UserScriptInstallSessionCoordinator');
const script = { id: 'installed-disabled', name: 'Disabled fixture', version: '1', enabled: false,
  source: '// fixture', sourceUrl: 'https://fixture.invalid/script.user.js', installSource: 'url' };

function managementFixture(options = {}) {
  const calls = [], events = [];
  let loaded = options.preloaded === true, accepted = false, blocked = false;
  const repository = {
    listScripts: () => loaded ? [script] : [], getSettings: () => ({ autoUpdateEnabled: false })
  };
  const lifecycle = { async initializeMetadata() { calls.push('metadata'); await options.metadataGate;
    if (options.metadataError) throw new Error('metadata unavailable'); loaded = true; } };
  const risk = {
    async initialize() { calls.push('risk'); await options.riskGate;
      if (options.riskError) throw new Error('consent unavailable'); accepted = options.accepted !== false; },
    hasAcceptedCurrentVersion: () => accepted
  };
  const values = {
    async initialize() { calls.push('values'); await options.valuesGate; if (options.valueError) { blocked = true; throw new Error('GM unavailable'); } },
    readManagementProjection: () => ({ blocked })
  };
  const runtime = { async initialize() { calls.push('diagnostics'); await options.diagnosticsGate;
    if (options.diagnosticsError) throw new Error('diagnostics unavailable'); } };
  const notice = { async initialize() { calls.push('notice'); }, hasDismissed: () => false };
  const session = new management.UserScriptManagementSessionCoordinator(repository, runtime, values, risk, notice,
    lifecycle, {}, {});
  session.setObserver(event => events.push(event));
  const activate = visible => session.activate(new management.UserScriptManagementSurfaceFacts(visible));
  return { session, activate, calls, events };
}

test('management lazily loads all disabled scripts and saved consent before deciding the risk sheet', async () => {
  const metadata = deferred(), values = deferred();
  const fixture = managementFixture({ metadataGate: metadata.promise, valuesGate: values.promise });
  fixture.activate(false);
  assert.deepEqual(fixture.calls, []);
  fixture.activate(true);
  await settle();
  assert.ok(fixture.calls.includes('metadata'));
  assert.ok(fixture.calls.includes('risk'));
  assert.equal(fixture.session.snapshot().activeSheet, 'none');
  metadata.resolve(); await settle();
  assert.deepEqual(fixture.session.snapshot().settings.scripts.map(item => item.id), [script.id]);
  assert.equal(fixture.session.snapshot().settings.scripts[0].enabled, false);
  assert.equal(fixture.session.snapshot().activeSheet, 'none');
  assert.ok(fixture.calls.includes('values'));
  assert.ok(fixture.calls.includes('diagnostics'));
  values.resolve(); await settle();
});

test('GM and diagnostics failure preserves the loaded management list and blocked recovery state', async () => {
  const fixture = managementFixture({ valueError: true, diagnosticsError: true });
  fixture.activate(true); await settle(); await settle();
  assert.equal(fixture.session.snapshot().settings.scripts.length, 1);
  assert.equal(fixture.session.snapshot().valueRecovery.blocked, true);
});

test('management metadata or consent failure retains known metadata and reports a handled load error', async () => {
  for (const options of [{ metadataError: true, preloaded: true }, { riskError: true }]) {
    const fixture = managementFixture(options);
    fixture.activate(true); await settle(); await settle();
    assert.equal(fixture.session.snapshot().settings.scripts.length, 1);
    assert.ok(fixture.events.some(event => event.effects.some(effect =>
      effect.kind === 'message' && effect.message === 'app.string.user_script_read_failed')));
    assert.equal(fixture.session.snapshot().activeSheet, options.riskError ? 'riskConsent' : 'none');
  }
});

test('management still requests consent when the loaded consent record is unaccepted', async () => {
  const fixture = managementFixture({ accepted: false });
  fixture.activate(true); await settle();
  assert.equal(fixture.session.snapshot().activeSheet, 'riskConsent');
  assert.equal(fixture.session.snapshot().settings.scripts[0].id, script.id);
});

test('management hidden during metadata loading cannot reopen consent or publish stale results', async () => {
  const gate = deferred();
  const fixture = managementFixture({ metadataGate: gate.promise, accepted: false });
  fixture.activate(true); fixture.activate(false);
  const eventsAfterHide = fixture.events.length;
  gate.resolve(); await settle(); await settle();
  assert.equal(fixture.events.length, eventsAfterHide);
  assert.equal(fixture.session.snapshot().activeSheet, 'none');
});

test('management auxiliary completion belongs only to the latest visible activation', async () => {
  const gate = deferred();
  const fixture = managementFixture({ valuesGate: gate.promise });
  fixture.activate(true); await settle();
  fixture.activate(false); fixture.activate(true); await settle();
  const before = fixture.events.length;
  gate.resolve(); await settle(); await settle();
  assert.equal(fixture.events.length, before + 1);
});

function installFixture(options = {}) {
  let loaded = false;
  const calls = [], previews = [];
  const lifecycle = {
    async initializeMetadata() { calls.push('metadata'); await options.metadataGate;
      if (options.metadataError) throw new Error('metadata unavailable'); loaded = true; },
    findInstalledScript: id => loaded && id === script.id ? script : undefined,
    previewSource(input) {
      previews.push({ ...input, metadataLoaded: loaded });
      return loaded && input.existingScriptId !== script.id ?
        { status: 'duplicate', duplicate: { scriptId: script.id }, candidate: {}, warnings: [] } :
        { status: 'ready', candidate: {}, warnings: [] };
    }
  };
  const fetcher = { async fetchSource() { calls.push('fetch'); return { ok: true, source: '// new version', sourceUrl: script.sourceUrl }; } };
  const files = { async readScriptFile() { calls.push('file'); return '// new version'; } };
  const session = new install.UserScriptInstallSessionCoordinator(lifecycle, fetcher, files, {});
  return { session, calls, previews };
}

test('install observer refreshes duplicate preview only for the current observer after metadata loads', async () => {
  const gate = deferred(), a = [], b = [];
  const fixture = installFixture({ metadataGate: gate.promise });
  fixture.session.begin({ source: '// new version' });
  fixture.session.observeInstallSurface(state => a.push(state));
  fixture.session.observeInstallSurface(state => b.push(state));
  gate.resolve(); await settle();
  assert.equal(a.length, 1);
  assert.equal(b.length, 2);
  assert.equal(b[1].preview.status, 'duplicate');
});

test('cleared install observer receives no delayed metadata refresh', async () => {
  const gate = deferred(), events = [];
  const fixture = installFixture({ metadataGate: gate.promise });
  const token = fixture.session.observeInstallSurface(state => events.push(state));
  fixture.session.clearInstallSurfaceObserver(token);
  gate.resolve(); await settle();
  assert.equal(events.length, 1);
});

for (const type of ['url', 'file_uri']) {
  test(`${type} import waits for metadata and targets the installed disabled script for replacement`, async () => {
    const gate = deferred();
    const fixture = installFixture({ metadataGate: gate.promise });
    let settled = false;
    const pending = fixture.session.loadSource({ type, url: script.sourceUrl, uri: '/fixture/script.user.js' })
      .then(result => { settled = true; return result; });
    await settle();
    assert.equal(settled, false);
    assert.equal(fixture.previews.length, 0);
    gate.resolve();
    const result = await pending;
    assert.equal(result.status, 'loaded');
    assert.equal(result.state.existingTarget.scriptId, script.id);
    assert.equal(result.state.existingTarget.enabled, false);
    assert.ok(fixture.previews.every(preview => preview.metadataLoaded));
  });
}

test('import cancelled while waiting for metadata cannot overwrite the current draft', async () => {
  const gate = deferred();
  const fixture = installFixture({ metadataGate: gate.promise });
  const pending = fixture.session.loadSource({ type: 'url', url: script.sourceUrl });
  fixture.session.cancelImport(); fixture.session.editSource('// user replacement');
  gate.resolve();
  assert.equal((await pending).status, 'cancelled');
  assert.equal(fixture.session.getState().source, '// user replacement');
  assert.equal(fixture.calls.includes('fetch'), false);
});

test('metadata failure is a visible handled error for install observation and import', async () => {
  const fixture = installFixture({ metadataError: true }), events = [];
  fixture.session.observeInstallSurface(state => events.push(state));
  await settle();
  assert.equal(events.at(-1).helperMessage, 'app.string.user_script_read_failed');
  const result = await fixture.session.loadSource({ type: 'url', url: script.sourceUrl });
  assert.equal(result.status, 'failed');
  assert.equal(fixture.session.getState().importBusy, false);
});

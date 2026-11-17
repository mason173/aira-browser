#!/usr/bin/env node
'use strict';

// Replay the original regression cases from download-related commits on today's
// production owners. Platform storage/logging and resource lookup are host seams;
// these checks do not claim device, network, or screen coverage.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src');
const strings = new Map(JSON.parse(fs.readFileSync(path.join(root,
  'main/resources/base/element/string.json'), 'utf8')).string.map(item => [item.name, item.value]));
const cases = [], suites = [];
let suiteName = '';
const hypium = {
  describe(name, body) { const parent = suiteName; suiteName = name; body(); suiteName = parent; },
  it(name, _flags, body) { cases.push({ name: suiteName + ': ' + name, body }); },
  expect(value) { return {
    assertEqual: expected => assert.equal(value, expected),
    assertTrue: () => assert.equal(value, true),
    assertFalse: () => assert.equal(value, false),
    assertUndefined: () => assert.equal(value, undefined),
    assertNull: () => assert.equal(value, null),
    assertContain: expected => assert.ok(value.includes(expected))
  }; }
};
function resource(name, ...args) {
  if (!name.startsWith('app.string.')) return { id: name };
  const value = strings.get(name.slice('app.string.'.length));
  assert.notEqual(value, undefined, 'Missing string: ' + name);
  return value.replace(/%(\d+)\$[dsf]/g, (_match, index) => String(args[Number(index) - 1]));
}
const cache = new Map();
function load(filename) {
  if (cache.has(filename)) return cache.get(filename).exports;
  const module = { exports: {} };
  cache.set(filename, module);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  });
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, $r: resource, URL, setTimeout, clearTimeout, Observed: value => value,
    require(name) {
      if (name === '@ohos/hypium') return hypium;
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {}, debug() {} } };
      if (name === '@ohos.url') return { default: { URL: { parseURL: (value, base) => new URL(value, base) } } };
      if (name === '@kit.ArkTS') return { util: { generateRandomUUID: require('node:crypto').randomUUID, Base64Helper: class {} } };
      if (name === '@kit.ArkWeb') return { webview: { WebDownloadDelegate: class {} } };
      if (name === '@kit.CoreFileKit') return { fileShare: { OperationMode: { READ_MODE: 1, WRITE_MODE: 2 } } };
      if (['@kit.ArkData', '@kit.NetworkKit', '@kit.FileManagerServiceKit', '@kit.DeviceCertificateKit',
        '@kit.PreviewKit', '@kit.ShareKit', '@ohos.app.ability.wantConstant'].includes(name)) return {};
      if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (name.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: { getContext: () => undefined } };
      if (name.endsWith('/AiraNavForensicsProbe')) return { AiraNavForensicsProbe: { record() {} } };
      if (name.endsWith('/BrowserNonRestorableNavigationGuardStore')) return {
        ArkBrowserNonRestorableNavigationGuardStore: class {
          constructor() { throw new Error('History checks must inject their navigation storage'); }
        }
      };
      if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name + '.ets'));
      throw new Error('Unmodeled platform dependency: ' + name + ' from ' + filename);
    }
  }, { filename });
  return module.exports;
}

function methods(relative, className, names) {
  const filename = path.join(root, 'main/ets', relative + '.ets');
  const source = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
  const owner = source.statements.find(item => ts.isClassDeclaration(item) && item.name.text === className);
  assert.ok(owner);
  const body = owner.members.filter(item => names.includes(item.name?.text)).map(item => item.getText(source)).join('\n');
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule('export class Owner { ' + body + ' }', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { module, exports: module.exports }, { filename });
  return module.exports.Owner;
}

function registerPromptIntegrationCases() {
  const Runtime = methods('services/download/DownloadRuntimeService', 'DownloadRuntimeService',
    ['getPendingDownloadPrompt', 'toPendingDownloadPromptFromV2', 'withPromptLocation',
      'isPlatformDownloadPrompt', 'isUserInitiatedDownloadPrompt']);
  const Overlay = methods('core/browser/BrowserDownloadConfirmOverlayCoordinator',
    'BrowserDownloadConfirmOverlayCoordinator', ['present', 'resolveInlineDocumentPrompt']);
  const { BrowserDownloadNavigationStateCoordinator: Navigation } = load(path.join(root,
    'main/ets/core/browser/BrowserDownloadNavigationStateCoordinator.ets'));
  for (const platform of [false, true]) for (const mime of ['', 'application/pdf']) {
    cases.push({ name: `PDF prompt survives Runtime → Overlay (platform=${platform}, MIME=${mime || 'unknown'})`, body() {
      const prompt = { guid: 'pdf-intent', url: 'https://files.example/export.pdf', fileName: 'export.pdf', mimeType: mime };
      const request = { ...prompt, method: 'GET', sourceId: 'page-source',
        platformSnapshot: platform ? { guid: 'native-pdf' } : undefined };
      const runtime = new Runtime();
      runtime.downloadV2Service = { getPendingPrompt: () => prompt, getCapturedRequest: () => request };
      runtime.resolvePendingPromptLocation = () => ({ path: '/Downloads', canChange: true });
      for (const state of [runtime.getPendingDownloadPrompt(), runtime.toPendingDownloadPromptFromV2(prompt)]) {
        const navigation = new Navigation({ loadRecords: async () => [], saveRecords: async () => {} });
        const abandoned = [], published = [], documentChanges = [];
        navigation.markDownloadUrlHandled = () => documentChanges.push('mark');
        navigation.resetPromptNavigationState = () => documentChanges.push('rewind');
        navigation.markVisibleDocumentNavigationCommitted = () => documentChanges.push('promote');
        const overlay = new Overlay();
        Object.assign(overlay, {
          navigationStateCoordinator: navigation,
          host: { resolveFacts: () => ({ activeTabId: 'source-tab' }) },
          downloadService: { abandonPendingDownload: guid => abandoned.push(guid) },
          leaseCoordinator: { acquire: value => ({ shouldPresent: true, lease: { id: 1 }, prompt: value }) },
          rewoundPromptGuids: {}, reset() {}, publishPendingPrompt: value => published.push(value),
          webPageLifecycleApplicationCoordinator: { pulseDownloadHandoffVisualFeedback() {} }
        });
        overlay.present(state);
        assert.deepEqual(abandoned, [], 'An explicit download cannot be abandoned as inline PDF navigation');
        assert.equal(published.length, 1);
        if (!platform) assert.deepEqual(documentChanges, [], 'A manual download must not change the page document');
      }
    } });
  }
}

(async () => {
  for (const name of ['BrowserDownloadInlineDocumentPrompt', 'DownloadV2StateMachine',
    'DownloadToolbarIndicatorViewModel', 'DownloadRecentRecordsViewModel', 'DownloadSelectionMode',
    'AdBlockBlockedResourcePolicy', 'AdBlockNavigationResourceType', 'SubframeAdBlockNavigation',
    'DownloadPrivacyPolicy']) {
    load(path.join(root, 'test', name + '.test.ets')).default();
    suites.push(name);
  }
  registerPromptIntegrationCases();
  let failed = 0;
  for (const entry of cases) {
    try { await entry.body(); console.log('PASS ' + entry.name); }
    catch (error) { failed++; console.error('FAIL ' + entry.name + ': ' + error.stack); }
  }
  console.log(`Historical download suites: ${suites.length}; cases: ${cases.length}; failed: ${failed}`);
  assert.equal(failed, 0);
})().catch(error => { console.error(error); process.exitCode = 1; });

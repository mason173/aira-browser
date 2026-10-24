// Exercise the production native adapter and window-open owner without a device or screen capture.
// Rust matching semantics are covered by the crate's popup_rules_tests; this checks the handoff seam.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function load(relative) {
  const filename = path.join(root, relative + '.ets');
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports,
    // Constructor dependencies are explicitly supplied by fixtures below.
    require() { return {}; }
  }, { filename });
  return module.exports;
}

const { BrowserWindowOpenApplicationCoordinator } = load('core/browser/BrowserWindowOpenApplicationCoordinator');
const { AdBlockNativeAuthorityEngineService } = load('services/adblock/AdBlockNativeAuthorityEngineService');

function windowFixture(options = {}) {
  const calls = [];
  const records = [];
  const opener = { id: 'opener', url: 'https://publisher.example/article' };
  const child = { id: 'child', openedByNewWindow: true, openerTabId: opener.id };
  let tabs = [opener];
  let activeTabId = opener.id;
  const event = {
    targetUrl: options.url || 'https://ads.example/offer',
    isUserTrigger: options.userTriggered !== false,
    isAlert: false
  };
  const windowOwner = {
    buildPlan(request) {
      calls.push('build_plan');
      assert.equal(request.targetUrl, event.targetUrl);
      assert.equal(request.openerTab, opener);
      return {
        type: options.planType || 'new_tab', targetUrl: request.targetUrl, helperMessage: '',
        runtimeEventType: 'fixture_plan', runtimeEventMessage: '', createOptions: {},
        deviceFormFactor: 'phone', deviceUiMode: 'touch', windowOpenSurface: 'tab', deviceFormFactorSummary: ''
      };
    },
    rejectImmediateEvent(actual) {
      assert.equal(actual, event);
      calls.push('reject_event');
      return true;
    },
    openManagedTab(request) {
      assert.equal(request.event, event);
      calls.push('create_child');
      return {
        transition: { tabs: [opener, child], tabSequence: 2, helperMessage: '' },
        targetTabId: child.id, eventDisposition: 'stored_for_controller_handoff', eventTargetTabId: child.id
      };
    },
    claimStoredEvent(tabId, controller) {
      assert.equal(tabId, child.id);
      assert.ok(controller);
      calls.push('claim_controller');
      return true;
    }
  };
  const host = {
    getWebRuntimeBridge: () => ({}), findTabById: id => tabs.find(tab => tab.id === id),
    buildCreateOptions: () => ({}), hasRecentAction: () => true,
    shouldBlockAdPopup(tabId, targetUrl) {
      calls.push('filter_popup');
      assert.equal(tabId, opener.id);
      assert.equal(targetUrl, event.targetUrl);
      return options.enabled !== false && options.matches !== false;
    },
    recordRuntimeEvent: (type, message, tabId) => records.push({ type, message, tabId }),
    setHelperMessage() {}, showManualDownloadConfirmSheet() { calls.push('download_sheet'); },
    getTabs: () => tabs, setTabs(value) { tabs = value; },
    getTabSequence: () => 1, setTabSequence() {}, getHomeUrl: () => 'about:blank',
    getActiveTabId: () => activeTabId, setActiveTabId(value) { activeTabId = value; },
    resolveManagedTabController() { calls.push('resolve_controller'); return {}; },
    captureOpenerPreviewBeforeManagedTabOpen: async () => { calls.push('preview'); },
    retainWindowOpenOpener() { calls.push('retain_opener'); },
    syncTabPreviewCacheWithTabs() {}, requestCloseTabsOverview() {}, syncActiveTabToView() {},
    recordRecentCreate() {}, persistTabs() {}, syncPrivateModeLockForCurrentBoundary() {}
  };
  if (options.omitFilter) delete host.shouldBlockAdPopup;
  const coordinator = new BrowserWindowOpenApplicationCoordinator({}, host, windowOwner, {
    resolveWindowOpenInputSync: () => ({})
  });
  return { coordinator, event, calls, records, getTabs: () => tabs };
}

test('matching popup rules reject the original event before any download or child handoff', async () => {
  for (const userTriggered of [true, false]) {
    const fixture = windowFixture({ userTriggered, planType: 'download' });
    await fixture.coordinator.handle('opener', fixture.event);
    assert.deepEqual(fixture.calls, ['filter_popup', 'reject_event']);
    assert.equal(fixture.getTabs().length, 1);
    assert.equal(fixture.records.filter(record => record.type === 'window_open_adblock_blocked').length, 1);
    assert.equal(fixture.records.some(record => record.type.endsWith('_failed')), false);
  }
});

test('unmatched, disabled and absent popup filtering preserve the normal controller handoff', async () => {
  for (const options of [{ matches: false }, { enabled: false }, { omitFilter: true }]) {
    const fixture = windowFixture(options);
    await fixture.coordinator.handle('opener', fixture.event);
    const expected = ['build_plan', 'create_child', 'resolve_controller', 'claim_controller', 'preview', 'retain_opener'];
    if (!options.omitFilter) expected.unshift('filter_popup');
    assert.deepEqual(fixture.calls, expected);
    assert.equal(fixture.getTabs().length, 2);
    assert.equal(fixture.records.some(record => record.type.endsWith('_failed')), false);
  }
});

test('unmatched OAuth targets retain the attached-window plan and controller claim before preview', async () => {
  const fixture = windowFixture({
    matches: false, planType: 'attached_window_tab', url: 'https://accounts.google.com/o/oauth2/v2/auth'
  });
  await fixture.coordinator.handle('opener', fixture.event);
  assert.deepEqual(fixture.calls, [
    'filter_popup', 'build_plan', 'create_child', 'resolve_controller', 'claim_controller', 'preview', 'retain_opener'
  ]);
  assert.equal(fixture.records.some(record => record.type.endsWith('_failed')), false);
});

test('an unmatched popup still follows the existing non-user-trigger policy', async () => {
  const fixture = windowFixture({ matches: false, userTriggered: false, planType: 'blocked_popup' });
  await fixture.coordinator.handle('opener', fixture.event);
  assert.deepEqual(fixture.calls, ['filter_popup', 'build_plan', 'reject_event']);
  assert.equal(fixture.getTabs().length, 1);
});

test('native adapter preserves explicit popup type, opener URL and disables response evaluation', () => {
  const service = new AdBlockNativeAuthorityEngineService();
  const calls = [];
  const decision = { shouldBlock: true, cspDirectives: '', redirectDataUrl: '', rewrittenUrl: '' };
  service.nativeModule = { checkRequest(...args) { calls.push(args); return decision; } };
  const input = {
    url: 'https://ads.example/offer', pageUrl: 'https://publisher.example/article', method: ' get ',
    isMainFrame: true, resourceType: 'popup', enabled: true, includeResponseEvaluation: true
  };
  assert.equal(service.evaluate(7, input), decision);
  assert.deepEqual(calls, [[7, input.url, input.pageUrl, 'popup', 'GET', false]]);
  const disabled = service.evaluate(7, { ...input, enabled: false });
  assert.equal(disabled.shouldBlock, false);
  assert.equal(calls.length, 1);
  const nonHttp = service.evaluate(7, { ...input, url: 'about:blank' });
  assert.equal(nonHttp.shouldBlock, false);
  assert.equal(calls.length, 1);
});

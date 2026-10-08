// Execute the production reload coordinators; this does not emulate ArkWeb BFCache.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
function load(relative) {
  const filename = path.join(root, relative);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports,
    require(specifier) {
      if (specifier.endsWith('/NavigationController')) return { NavigationController: class {} };
      if (specifier.endsWith('/AiraNavForensicsProbe')) return { AiraNavForensicsProbe: { logLoadIssued() {} } };
      if (specifier.endsWith('/BrowserNativeTabSceneService')) {
        return { browserNativeTabSceneService: { isNativeTabUrl: url => url.startsWith('aira://') } };
      }
      if (specifier.endsWith('/BrowserDownloadNavigationStateCoordinator')) {
        return { BrowserDownloadNavigationStateCoordinator: class {} };
      }
      if (specifier.endsWith('/BrowserWebActiveSurfaceCoordinator')) {
        return { WEB_ACTIVE_SURFACE_SCROLL_SOURCE_NAVIGATION_RESTORE: 'navigation_restore' };
      }
      throw new Error(`Unexpected runtime dependency: ${specifier}`);
    }
  }, { filename });
  return module.exports;
}
const { BrowserRestoreCoordinator } = load('core/browser/BrowserRestoreCoordinator.ets');
const { BrowserWebLoadFailureSurfaceCoordinator } = load('core/browser/BrowserWebLoadFailureSurfaceCoordinator.ets');
const { BrowserActiveTabRuntimeRestoreCoordinator } = load('services/web/BrowserActiveTabRuntimeRestoreCoordinator.ets');
function fixture({
  attached = true, hosted = true, errorSurface = false, refreshSucceeds = true, prepareIdentitySucceeds = true
} = {}) {
  const calls = [];
  const tab = {
    id: 'tab', url: 'https://example.test/detail', pendingUrl: '', isHome: false,
    scrollOffsetY: 720, navigationHistory: ['https://example.test/list', 'https://example.test/detail'],
    navigationIndex: 1, webStatePath: 'old-snapshot', webStateUpdatedAt: 42
  };
  const facts = {
    activeTabId: tab.id, tabs: [tab], controllerAttached: attached, currentUrl: tab.url,
    showHomePage: false, showTabsSheet: false, holdPageErrorSurfaceDuringReload: false
  };
  const states = [];
  const failures = new BrowserWebLoadFailureSurfaceCoordinator();
  if (errorSurface) failures.markFailure(tab.id, 'network failed', tab.url);
  const coordinator = new BrowserActiveTabRuntimeRestoreCoordinator({
    tabManager: { getTab: (tabs, id) => tabs.find(tab => tab.id === id) },
    restoreCoordinator: new BrowserRestoreCoordinator(),
    loadFailureSurfaceCoordinator: failures,
    hostedRuntimeSurfacePort: {
      isHostedControllerAttached: () => hosted,
      ensureActiveWebSurfaceForNavigation: () => calls.push('sync_surface')
    },
    primeNavigationVisualFeedback() {},
    webpageTranslationCoordinator: { handleRefreshOrBackForwardForRuntimeTab() {} },
    tabSwitchCoordinator: { applyTabPatch: (_id, patch) => Object.assign(tab, patch) },
    runtimeLifecyclePort: { refreshControllerPage: () => { calls.push('refresh'); return refreshSucceeds; } },
    webLoadRuntimeCoordinator: {
      prepareIdentityBeforeLiveRefresh: (...args) => {
        calls.push(['prepare_identity', ...args]);
        return prepareIdentitySucceeds;
      },
      syncEventContext: (...args) => calls.push(['context', ...args]),
      loadUrlForTab: (...args) => { calls.push(['load', ...args]); return true; }
    }
  }, {
    resolveFacts: () => facts,
    applyState: state => states.push(state),
    recordRuntimeEvent() {}
  });
  return { coordinator, calls, tab, facts, states, failures };
}
{
  const f = fixture();
  f.coordinator.reloadActive('user_manual_reload');
  assert.deepEqual(f.calls, [
    ['prepare_identity', 'tab', f.tab.url],
    ['context', 'tab', f.tab.url, true],
    'refresh'
  ]);
  assert.equal(f.calls.findIndex(call => Array.isArray(call) && call[0] === 'prepare_identity'), 0);
  assert.equal(f.calls[2], 'refresh');
  assert.equal(f.tab.scrollOffsetY, 720, 'live refresh must preserve the last observed scroll position');
  assert.equal(f.tab.navigationIndex, 1);
  assert.deepEqual(f.tab.navigationHistory, ['https://example.test/list', 'https://example.test/detail']);
  assert.equal(f.tab.webStatePath, '', 'a pre-refresh disk snapshot is stale and must be invalidated');
}
for (const options of [{ attached: false }, { hosted: false }, { errorSurface: true }]) {
  const f = fixture(options);
  f.coordinator.reloadActive('user_manual_reload');
  assert.equal(f.calls[0], 'sync_surface');
  assert.equal(f.calls[1][0], 'load');
  assert.equal(f.calls[1][2], f.tab.url, 'retry must load the intended URL');
  assert.equal(f.calls[1][4], false, 'manual retry must preserve surviving native history');
  assert.equal(f.calls.includes('refresh'), false);
}
{
  const f = fixture();
  f.facts.holdPageErrorSurfaceDuringReload = true;
  f.coordinator.reloadActive('user_manual_reload', false);
  assert.equal(f.calls[1][0], 'load', 'dismissed error UI is still a document retry');
  assert.equal(f.calls[1][4], false);
}
for (const committed of [false, true]) {
  const f = fixture({ errorSurface: true });
  f.failures.markWebDocumentLoading(f.tab.id);
  if (committed) f.failures.markWebDocumentCommitted(f.tab.id);
  assert.equal(f.failures.shouldShowNativeSurface(f.tab.id), false);
  assert.equal(f.facts.holdPageErrorSurfaceDuringReload, false);
  f.coordinator.reloadActive('user_manual_reload', false);
  assert.equal(f.calls[0], 'sync_surface');
  assert.equal(f.calls[1][0], 'load', 'a Web error document must retry its target, not refresh the error HTML');
  assert.equal(f.calls[1][2], f.tab.url);
  assert.equal(f.calls[1][4], false);
  assert.equal(f.calls.includes('refresh'), false);
  assert.equal(f.failures.shouldShow(f.tab.id), false);
}
for (const reason of ['user_agent_changed', 'site_permission_apply']) {
  const f = fixture();
  f.coordinator.reloadActive(reason);
  assert.equal(f.calls[0], 'sync_surface');
  assert.equal(f.calls[1][0], 'load');
  assert.equal(f.calls[1][4], true);
  assert.equal(f.tab.scrollOffsetY, 0);
}
{
  const f = fixture({ refreshSucceeds: false });
  f.coordinator.reloadActive('user_manual_reload');
  assert.equal(f.calls.includes('sync_surface'), false, 'failed live refresh must not silently rebuild Web');
  assert.equal(f.calls.some(call => Array.isArray(call) && call[0] === 'load'), false);
  assert.equal(f.calls[0][0], 'prepare_identity');
  assert.ok(f.states.some(state => state.errorMessage?.startsWith('刷新下发失败')));
}
{
  const f = fixture({ prepareIdentitySucceeds: false });
  f.coordinator.reloadActive('user_manual_reload');
  assert.equal(f.calls.includes('refresh'), false, 'a refused identity change must not refresh under the old identity');
  assert.equal(f.calls.some(call => Array.isArray(call) && call[0] === 'load'), false);
  assert.ok(f.states.some(state => state.errorMessage?.startsWith('刷新下发失败')));
}
for (const home of [true, false]) {
  const f = fixture();
  f.tab.isHome = home;
  if (!home) f.facts.currentUrl = 'aira://settings';
  f.coordinator.reloadActive('user_manual_reload');
  assert.deepEqual(f.calls, []);
}
console.log('Page-refresh runtime contract passed (13 cases; native BFCache requires device validation).');

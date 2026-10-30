#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function evaluate(code, globals = {}) {
  const compiled = ts.transpileModule(code, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    reportDiagnostics: true
  });
  assert.equal(compiled.diagnostics.length, 0);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, $r: value => value, ...globals,
    require: id => {
      for (const relative of [
        'common/models/BrowserModels', 'core/browser/BrowserProfileBoundaryService',
        'services/privacy/BrowserPrivacyEffectPolicyService'
      ]) {
        if (id.endsWith('/' + path.basename(relative))) return evaluate(source(relative + '.ets'));
      }
      if (id.endsWith('/SiteIconService')) return { SiteIconService: class { peekUri() { return ''; } } };
      if (id.endsWith('/BrowserNativeTabSceneService')) return { browserNativeTabSceneService: {
        isNativeTabUrl: value => value.startsWith('aira://system/')
      } };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      throw new Error(`Unexpected runtime dependency: ${id}`);
    }
  });
  return module.exports;
}
function source(relative) { return fs.readFileSync(path.join(root, relative), 'utf8'); }
function methods(relative, className, names, globals = {}) {
  const ast = ts.createSourceFile(relative, source(relative), ts.ScriptTarget.Latest, true);
  const declaration = ast.statements.find(node => node.name?.text === className);
  return evaluate(`export class ${className} { ${names.map(name => {
    const member = declaration.members.find(node => node.name?.text === name);
    assert.ok(member, `${className}.${name}`);
    return member.getText(ast);
  }).join('\n')} }`, globals)[className];
}
const { BrowserHomeForwardReturnState } = evaluate(source('core/browser/BrowserHomeForwardReturnState.ets'));
function tab(id, extra = {}) {
  return {
    id, url: `https://${id}.example.test`, title: id, isHome: false,
    profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent',
    navigationHistory: [`https://${id}.example.test`], navigationIndex: 0,
    pendingUrl: '', lastGoodUrl: '', lastGoodTitle: '', lastRestorableUrl: '', lastRestorableTitle: '',
    webStatePath: '', lastRestoreReason: '', launchContext: { sourceType: '', sourceId: '', sourceUrl: '', key: '' },
    ...extra
  };
}
function harness() {
  let state = {
    tabs: [tab('previous'), tab('current')], activeTabId: 'current', showHomePage: false,
    showTabsSheet: false, currentProfileId: 'profile-main', currentPrivacyMode: 'regular',
    currentDataScope: 'profile_persistent', runtimeDegradedMessage: ''
  };
  let records = [];
  let webForwards = 0;
  let restores = 0;
  const Home = methods('core/browser/BrowserTabHomeCoordinator.ets', 'BrowserTabHomeCoordinator', [
    'rememberHomeForwardTab', 'prepareHomeForwardForNewTab', 'bindHomeForwardTab', 'canGoForwardFromHome', 'forwardFromHome', 'resolveHomeForwardTarget',
    'showHomeSurface', 'applyTabsOverviewHomeTabCreation', 'applyGoHomeApplicationResult', 'findTabById'
  ], evaluate(source('common/models/BrowserModels.ets')));
  const home = Object.assign(new Home(), {
    homeForwardReturnState: new BrowserHomeForwardReturnState(), homeForwardInFlight: false,
    shell: {
      readState: () => state,
      applyState: application => {
        if (application.tabsForOverviewPreviewSync) state.tabs = application.tabsForOverviewPreviewSync;
        if (application.activeTabId !== undefined) state.activeTabId = application.activeTabId;
        if (application.visualState) state.showHomePage = application.visualState.showHomePage;
      },
      cancelBottomPanelBackdropFocusTransition() {}, restoreHomeBottomPanel() {}
    },
    shellStateCoordinator: { buildHomeState: () => ({ showHomePage: true }) },
    prepareHomePresentation() {},
    applyBoundary: (profileId, privacyMode, dataScope) => Object.assign(state, {
      currentProfileId: profileId, currentPrivacyMode: privacyMode, currentDataScope: dataScope
    }),
    scheduleDeferredWork() {},
    persistActiveTabSnapshot() {}, clearWebEventContext() {},
    dependencies: {
      recentlyClosedApplicationCoordinator: { getHomeForwardRecords: () => records },
      restoreRecentlyClosedRecord: recordId => {
        const record = records.find(record => record.id === recordId);
        assert.ok(record, 'restore the exact closed tab');
        state.tabs.push(record.tab);
        state.activeTabId = record.tab.id;
        state.showHomePage = false;
        records = records.filter(record => record.id !== recordId);
        restores++;
      },
      hostedRuntimeSurfacePort: { detachActive() {} },
      tabSwitchCoordinator: {
        synchronizeWebTabsAndPreviewAssets() {},
        commitTabs: tabs => { state.tabs = tabs; },
        switchToTab: async (id, canApply) => {
          if (canApply && !canApply()) return;
          assert.ok(state.tabs.some(tab => tab.id === id));
          state.activeTabId = id;
          state.showHomePage = false;
        }
      },
      resolveTabsOverviewSessionCoordinator: () => ({ handle() {} }),
      resolveRootBottomPanelSessionCoordinator: () => ({ showTransientMessage() {} }),
      resolveHomePresentationSessionCoordinator: () => ({ playReveal() {} })
    }
  });
  const { BrowserWebHistoryCommandRuntimeCoordinator: History } = evaluate(
    source('core/browser/BrowserWebHistoryCommandRuntimeCoordinator.ets'));
  const history = new History({
    webTabsController: {
      goActivePageForward: () => { webForwards++; return { status: 'native_issued' }; }
    }
  }, { forwardFromHome: () => home.forwardFromHome(), showNativeToast() {} });
  const Header = methods('core/browser/BrowserRootBottomPanelActionApplication.ets',
    'BrowserRootBottomPanelFixedActionApplication', ['applyHeaderAction', 'canActiveTabGoForward', 'findActiveTab']);
  const header = Object.assign(new Header(), {
    dependencies: { tabHomeCoordinator: home, webHistoryCommandRuntimeCoordinator: history }
  });
  const Close = methods('core/browser/BrowserTabCloseCoordinator.ets', 'BrowserTabCloseCoordinator', [
    'recordRecentlyClosedTabForAction', 'closeCurrentTabForUserReturnHome', 'findTabById'
  ]);
  const closeHost = {
    readState: () => state, restoreHomeBottomPanelForDirectHomeNavigation() {}, setHelperMessage() {}
  };
  const close = Object.assign(new Close(), {
    resolveApplicationHost: () => closeHost,
    resolveRecentlyClosedSkipReason: () => '',
    buildCloseTabCleanupPlan: () => ({}),
    applyCloseTabsToHomeMutation: mutation => Object.assign(state, mutation),
    removeClosedTabPreview() {}, refreshPostCloseBoundaryState() {}, scheduleDeferredCloseTabCleanup() {},
    tabManager: {
      closeActiveTabToHome: (tabs, id) => ({ tabs: tabs.filter(tab => tab.id !== id), activeTabId: '' })
    },
    dependencies: {
      resolveTabHomeCoordinator: () => home,
      resolveWebPageLifecycleCoordinator: () => ({ prepareTabForTerminalClose() {} }),
      recentlyClosedApplicationCoordinator: {
        recordClosedTab: tab => {
          records.unshift({ id: `closed-${tab.id}`, originalTabId: tab.id, tab });
          return { recorded: true };
        }
      },
      backgroundOpenPromptCoordinator: { dismissTab() {} }
    }
  });
  return {
    home, header, history, recordClosure: id => close.recordRecentlyClosedTabForAction(id), get state() { return state; }, get restores() { return restores; },
    get webForwards() { return webForwards; },
    seedOldRecord: () => records.push({ id: 'old', originalTabId: 'unrelated', tab: tab('unrelated') }),
    async closeToHome() {
      await close.closeCurrentTabForUserReturnHome({
        activeTab: state.tabs.find(tab => tab.id === state.activeTabId), helperMessage: '',
        homeOptions: {}, shouldPlayDirectHomeReveal: false
      });
    },
    openHome() {
      home.applyTabsOverviewHomeTabCreation({
        tabs: state.tabs.concat(tab('home', { isHome: true })), activeTabId: 'home',
        tabSequence: 3, helperMessage: '', options: {}, playHomeReveal: false
      });
    },
    forward: () => header.applyHeaderAction('webForward', state.showHomePage),
    available: () => header.canActiveTabGoForward(state),
    clearRecords: () => { records = []; }
  };
}

test('close to home -> Forward restores that closed tab even when another live tab remains', async () => {
  const h = harness();
  h.seedOldRecord();
  await h.closeToHome();
  assert.equal(h.state.showHomePage, true);
  assert.equal(h.state.tabs.length, 1);
  assert.equal(h.available(), true);
  h.forward();
  assert.equal(h.state.activeTabId, 'current');
  assert.equal(h.state.showHomePage, false);
  assert.equal(h.restores, 1);
  assert.equal(h.webForwards, 0);
});
test('new home -> Forward switches to the previously viewed tab without duplicating it', async () => {
  const h = harness();
  h.openHome();
  assert.equal(h.available(), true);
  h.forward();
  await Promise.resolve();
  assert.equal(h.state.activeTabId, 'current');
  assert.equal(h.state.showHomePage, false);
  assert.equal(h.state.tabs.filter(tab => tab.id === 'current').length, 1);
  assert.equal(h.restores, 0);
  assert.equal(h.webForwards, 0);
});
test('repeated new-home actions keep the page the user last viewed', async () => {
  const h = harness();
  h.openHome();
  h.openHome();
  h.forward();
  await Promise.resolve();
  assert.equal(h.state.activeTabId, 'current');
});
test('home preserving its active page can return to that same tab', () => {
  const h = harness();
  h.home.applyGoHomeApplicationResult({
    tabId: 'current', nextActiveTabId: 'current', tabs: h.state.tabs,
    visualState: { showHomePage: true }
  });
  assert.equal(h.available(), true);
  h.forward();
  assert.equal(h.state.showHomePage, false);
});
test('fresh home never falls back to unrelated old closed records', () => {
  const h = harness();
  h.seedOldRecord();
  h.state.showHomePage = true;
  assert.equal(h.available(), false);
  h.forward();
  assert.equal(h.restores, 0);
  assert.equal(h.webForwards, 0);
});
test('deleted closed record disables Forward; it does not restore a different record', async () => {
  const h = harness();
  h.seedOldRecord();
  await h.closeToHome();
  h.clearRecords();
  assert.equal(h.available(), false);
  h.forward();
  assert.equal(h.restores, 0);
});
for (const [key, value] of [['currentProfileId', 'other'], ['currentPrivacyMode', 'private'],
  ['currentDataScope', 'session_ephemeral'], ['showTabsSheet', true]]) {
  test(`home return respects ${key}`, () => {
    const h = harness();
    h.openHome();
    h.state[key] = value;
    assert.equal(h.available(), false);
    h.forward();
    assert.equal(h.state.showHomePage, true);
    assert.equal(h.webForwards, 0);
  });
}
test('ordinary Web Forward still uses Web history', () => {
  const h = harness();
  h.forward();
  assert.equal(h.webForwards, 1);
});


test('new home from a native tab returns to that tab', async () => {
  const h = harness();
  h.state.tabs[1] = tab('current', { isHome: true, url: 'aira://system/bookmarks' });
  h.openHome();
  assert.equal(h.available(), true);
  h.forward();
  await Promise.resolve();
  assert.equal(h.state.activeTabId, 'current');
});

test('switching to an unrelated existing home does not borrow the latest return target', () => {
  const h = harness();
  h.state.tabs.unshift(tab('old-home', { isHome: true, url: 'aira://home' }));
  h.openHome();
  assert.equal(h.available(), true);
  h.state.activeTabId = 'old-home';
  assert.equal(h.available(), false);
  h.forward();
  assert.equal(h.state.activeTabId, 'old-home');
  assert.equal(h.webForwards, 0);
});

function hiddenRecentOwner() {
  const Owner = methods('core/browser/BrowserRecentlyClosedApplicationCoordinator.ets',
    'BrowserRecentlyClosedApplicationCoordinator', [
      'recordClosedTab', 'getHomeForwardRecords', 'prepareRestoreByRecordId', 'acceptRestoredRecords'
    ]);
  const { BrowserRecentlyClosedTabsService: Service } = evaluate(source('core/browser/BrowserRecentlyClosedTabsService.ets'));
  let mutations = 0;
  const owner = Object.assign(new Owner(), {
    records: [], homeForwardRecord: undefined,
    isRecentlyClosedEnabled: () => false,
    hasRecordsForCurrentBoundary: () => false,
    shell: { resolveFacts: () => ({ currentWindowId: 'window-test' }) },
    dependencies: { tabsService: new Service({
      shouldTreatAsNonRestorableNavigation: () => false, allowExplicitPageRestore() {},
      resolveRestorableNavigation: tab => ({ url: tab.url, title: tab.title })
    }) },
    applyMutation: () => { mutations++; }
  });
  return { owner, mutations: () => mutations };
}

test('hiding recently closed preserves one memory-only home return without publishing history', () => {
  const h = hiddenRecentOwner();
  const result = h.owner.recordClosedTab(tab('current'), true);
  assert.equal(result.recorded, false, 'persistent history remains disabled');
  assert.equal(h.mutations(), 0);
  const [record] = h.owner.getHomeForwardRecords();
  assert.equal(record.originalTabId, 'current');
  const restored = h.owner.prepareRestoreByRecordId([], '', record.id);
  assert.equal(restored.restored, true);
  assert.equal(restored.tabs[0].url, 'https://current.example.test');
  h.owner.acceptRestoredRecords(restored.remainingRecords);
  assert.equal(h.owner.getHomeForwardRecords().length, 0);
});

test('a background close cannot replace the memory-only home return', () => {
  const h = hiddenRecentOwner();
  h.owner.recordClosedTab(tab('current'), true);
  h.owner.recordClosedTab(tab('background'), false);
  assert.equal(h.owner.getHomeForwardRecords()[0].originalTabId, 'current');
});

test('private closed tabs stay excluded by the existing recording policy', () => {
  const h = hiddenRecentOwner();
  h.owner.recordClosedTab(tab('private', { privacyMode: 'private', dataScope: 'session_ephemeral' }), true);
  assert.equal(h.owner.getHomeForwardRecords().length, 0);
});

test('desktop direct new-tab creation remembers and binds its outgoing source', async () => {
  const h = harness();
  const Creation = methods('core/browser/BrowserForegroundTabCreationCoordinator.ets',
    'BrowserForegroundTabCreationCoordinator', ['createNewTabNow', 'applyForegroundTabCreation']);
  h.state.homeUrl = 'aira://home';
  // Previous home was private; the currently viewed page and new home are regular.
  h.state.currentPrivacyMode = 'private';
  h.state.currentDataScope = 'session_ephemeral';
  const creator = Object.assign(new Creation(), {
    resolveHost: () => ({
      resolveForegroundTabCreationState: () => h.state,
      persistActiveTabSnapshot() {},
      applyTabCreationState: patch => Object.assign(h.state, patch)
    }),
    transitionCoordinator: {
      createTab: () => ({
        tabs: h.state.tabs.concat(tab('direct-home', { isHome: true, url: 'aira://home' })),
        activeTabId: 'direct-home', tabSequence: 3
      })
    },
    dependencies: {
      resolveTabHomeCoordinator: () => h.home,
      resolveTabSwitchCoordinator: () => ({
        synchronizeWebTabsAndPreviewAssets() {}, synchronizeActiveTab: () => { h.state.showHomePage = true; }
      }),
      resolveTabsOverviewSessionCoordinator: () => ({ handle() {} }),
      resolveTabSessionPersistenceCoordinator: () => ({ persist() {} })
    }
  });
  creator.createNewTabNow({
    initialUrl: 'aira://home', initialTitle: 'Home', options: {},
    runtimeOptions: { skipCurrentTabPreviewForForegroundOpen: true }
  });
  assert.equal(h.available(), true);
  h.forward();
  await Promise.resolve();
  assert.equal(h.state.activeTabId, 'current');
});

test('desktop home projection enables Forward and clears it when its record disappears', () => {
  const Presentation = methods('core/browser/BrowserLargeScreenPresentationViewModel.ets',
    'BrowserLargeScreenPresentationViewModel', ['resolvePresentationForTabs'], {
      isBrowserTabTerminalBackAvailable: () => false,
      STRUCTURAL_TAB_STRIP_POLICY: {},
      createEmptyActiveTabChrome: () => ({}),
      browserNativeTabSceneService: { resolveSceneForTab: () => undefined }
    });
  const viewModel = Object.assign(new Presentation(), {
    resolvePresentationFromTabStates: () => ({ topChrome: { actions: [
      { id: 'back', enabled: true }, { id: 'forward', enabled: false }
    ] } })
  });
  for (const available of [true, false]) {
    const presentation = viewModel.resolvePresentationForTabs({}, [], '', {
      visible: true, canGoForward: available
    });
    assert.equal(presentation.activeTabChrome.scene, 'home');
    assert.equal(presentation.activeTabChrome.canGoForward, available);
    assert.equal(presentation.topChrome.actions[1].enabled, available);
    assert.equal(presentation.topChrome.actions[0].enabled, false);
  }
  assert.match(source('app/pages/BrowserShellPage.ets'),
    /this\.recentlyClosedApplicationSnapshot = snapshot;\s*this\.reconcileShellTabPresentation\(\)/,
    'recent-record changes must refresh the desktop projection');
});


test('new home from an unrelated existing home cannot revive a stale source', () => {
  const h = harness();
  h.state.tabs.unshift(tab('old-home', { isHome: true, url: 'aira://home' }));
  h.openHome();
  h.state.activeTabId = 'old-home';
  h.openHome();
  assert.equal(h.available(), false);
  h.forward();
  assert.equal(h.state.showHomePage, true);
  assert.equal(h.webForwards, 0);
});


test('a close that stays on another page does not replace an existing home return source', () => {
  const h = harness();
  h.openHome();
  h.state.tabs.push(tab('other'));
  h.state.activeTabId = 'other';
  h.state.showHomePage = false;
  h.recordClosure('other');
  h.state.tabs = h.state.tabs.filter(tab => tab.id !== 'other');
  h.state.activeTabId = 'home';
  h.state.showHomePage = true;
  h.forward();
  assert.equal(h.state.activeTabId, 'current');
});

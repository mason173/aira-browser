#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
function evaluate(source, globals = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText, {
    module, exports: module.exports, ...globals,
    setTimeout: () => 1, clearTimeout() {},
    require(specifier) {
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
      throw new Error(`Unexpected dependency: ${specifier}`);
    }
  });
  return module.exports;
}
function load(relative) {
  if (cache.has(relative)) return cache.get(relative);
  const source = fs.readFileSync(path.join(root, relative + '.ets'), 'utf8');
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText, {
    module, exports: module.exports, setTimeout: () => 1, clearTimeout() {},
    require(specifier) {
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
      assert.ok(specifier.startsWith('.'), `Unexpected dependency: ${specifier}`);
      return load(path.relative(root, path.resolve(root, path.dirname(relative), specifier)));
    }
  });
  cache.set(relative, module.exports);
  return module.exports;
}
const policy = load('core/browser/BrowserToolbarChromeStylePolicy');
const { BrowserWebViewportCoordinator } = load('core/browser/BrowserWebViewportCoordinator');
const { BrowserWebTopImmersionSessionCoordinator } = load('core/browser/BrowserWebTopImmersionSessionCoordinator');
const source = fs.readFileSync(path.join(root, 'app/pages/BrowserShellPage.ets'), 'utf8');
const tokens = fs.readFileSync(path.join(root,
  'app/components/browser/BrowserShellPresentationTokens.ets'), 'utf8');
const gap = tokens.match(/export const WEB_TOP_CHROME_CONTENT_GAP_VP: number = (\d+);/);
assert.ok(gap, 'Missing top chrome content gap');
// Execute the real shell adapter and row geometry, rather than a fixture that
// silently assumes hiding the system status bar also hides the split address row.
function method(name) {
  const result = source.match(new RegExp(`^  private ${name}\\([\\s\\S]*?^  }`, 'm'));
  assert.ok(result, `Missing shell method ${name}`);
  return result[0];
}
const host = source.match(/^  private browserWebTopImmersionSessionHost:[\s\S]*?= (\{[\s\S]*?^  });/m);
assert.ok(host, 'Missing shell top-immersion host');
const { Shell } = evaluate(`export class Shell {
${['getWebTopChromeStableInsetPx', 'resolveChromeRowTopReservePx', 'isSplitToolbarChromeActiveHere',
  'resolveTargetWebViewportVisualTopInsetPx', 'getWebViewportVisualTopInsetPx',
  'noteSplitAddressBarScroll', 'syncSplitToolbarScrollViewport'].map(method).join('\n')}
  createHost() { return ${host[1]}; }
}`, { ...policy, WEB_TOP_CHROME_CONTENT_GAP_VP: Number(gap[1]), Curve: { EaseOut: 'easeOut' } });
function fixture(style = 'split', safeInset = 39, quickSearchHeight = 0) {
  const shell = new Shell();
  const updates = [];
  Object.assign(shell, {
    browserPageForeground: true, showHomePage: false, showTabsSheet: false,
    webStatusBarVisible: true, webViewportVisualTopInsetInitialized: true,
    homeTopSafeInsetVp: safeInset, homeBottomSafeInsetVp: 12,
    quickSearchSwitchingPresentation: { occupiedHeightPx: quickSearchHeight },
    splitAddressBarCollapsedByImmersion: false,
    splitAddressBarImmersionScrollCoordinator: new policy.SplitAddressBarImmersionScrollCoordinator(),
    shouldUseSplitToolbarChrome: () => style !== 'floating',
    usesDockToolbarChrome: () => style === 'dock',
    shouldCollapseSplitToolbarBars: () => false,
    canCollapseSplitAddressBarForTopImmersion: () => style === 'split',
    isWebAppSurfaceActive: () => false, isLargeScreenShellFamilyActive: () => false,
    resolveStatusBarStripInsetPx: () => safeInset,
    resolveBottomChromeBlockVp: () => policy.SPLIT_TOOLBAR_BOTTOM_BAR_VP,
    browserStatusBarStyleService: { applyVisibility: async () => true },
    getAbilityContext: () => ({}), scheduleWebSafeInsetSettleSync() {},
    getUIContext: () => ({ animateTo(_options, apply) { apply(); } }),
    refreshWebViewportPresentation(inset) {
      this.webViewportPresentation = BrowserWebViewportCoordinator.resolvePresentation({
        hostHeightPx: 760, visualTopInsetPx: inset, fullViewport: false,
        largeScreenShellActive: false, nativeVideoTakeoverActive: false
      });
      updates.push({ visible: this.webStatusBarVisible, inset,
        contentTop: this.webViewportPresentation.contentTopPx,
        rowPainted: !this.splitAddressBarCollapsedByImmersion && style === 'split' });
    }
  });
  shell.webViewportVisualTopInset = shell.resolveTargetWebViewportVisualTopInsetPx();
  shell.refreshWebViewportPresentation(shell.webViewportVisualTopInset);
  const coordinator = new BrowserWebTopImmersionSessionCoordinator({
    resolveFacts: () => ({
      activeTabId: 'new-tab', browserShellVisible: true, webPageVisible: true,
      homePageVisible: shell.showHomePage, tabsSheetVisible: shell.showTabsSheet,
      scrollTopImmersionEnabled: true, alwaysTopImmersionEnabled: false,
      fullScreenModeEnabled: false, webAppTopSafeAreaHidden: false,
      assistantVideoTakeoverActive: false, scrollOffsetY: 0,
      addressFocused: false, bottomPanelInteractive: false,
      statusBarVisible: shell.webStatusBarVisible
    }), host: shell.createHost()
  });
  return { shell, coordinator, updates };
}

function firstNavigationScroll(item, offset = 40) {
  // Navigation has reset the status-bar scroll baseline before the new document's
  // first nonzero scroll callback. The split address-row tracker has not seen this tab.
  item.coordinator.resetScrollBaseline('new-tab', 0);
  item.coordinator.handleScroll('new-tab', offset);
  item.shell.noteSplitAddressBarScroll('new-tab', offset, true);
}

for (const safeInset of [0, 16, 39, 60]) {
  for (const quickSearchHeight of [0, 48]) {
    for (const firstOffset of [24, 40, 72]) {
      const item = fixture('split', safeInset, quickSearchHeight);
      firstNavigationScroll(item, firstOffset);
      const beforeOverview = item.shell.webViewportPresentation.contentTopPx;
      const addressRowPainted = !item.shell.splitAddressBarCollapsedByImmersion;
      // This is why the user can recover by opening tabs and returning: that entry
      // requests visible chrome, even though an address row was already painted.
      item.shell.showTabsSheet = true;
      item.coordinator.requestVisible('tabs-overview-entry');
      item.shell.showTabsSheet = false;
      item.coordinator.syncPolicy('tabs-overview-return');
      const afterOverview = item.shell.webViewportPresentation.contentTopPx;
      assert.equal(addressRowPainted, true);
      assert.equal(beforeOverview, afterOverview,
        `Opening tabs must not repair a covered web top: before=${beforeOverview}vp, after=${afterOverview}vp`);
      for (const update of item.updates) {
        if (update.rowPainted) assert.ok(update.contentTop >=
          policy.resolveSplitToolbarTopRowHeightVp(safeInset) + quickSearchHeight,
          `Painted split search row must not cover content (content top=${update.contentTop}vp)`);
      }
    }
  }
}

// Once a subsequent tracked scroll actually removes the address row, release
// its space. Reversing that scroll must restore the row and its reserve together.
const collapsed = fixture();
firstNavigationScroll(collapsed);
collapsed.coordinator.handleScroll('new-tab', 80);
collapsed.shell.noteSplitAddressBarScroll('new-tab', 80, true);
assert.equal(collapsed.shell.splitAddressBarCollapsedByImmersion, true);
assert.equal(collapsed.shell.webViewportPresentation.contentTopPx, 0);
collapsed.coordinator.handleScroll('new-tab', 0);
collapsed.shell.noteSplitAddressBarScroll('new-tab', 0, true);
assert.equal(collapsed.shell.splitAddressBarCollapsedByImmersion, false);
assert.equal(collapsed.shell.webViewportPresentation.contentTopPx, policy.resolveSplitToolbarTopRowHeightVp(39));
for (const update of collapsed.updates) {
  if (update.rowPainted) assert.ok(update.contentTop >= policy.resolveSplitToolbarTopRowHeightVp(39));
}

// The dock has no top search row; the existing floating immersion keeps its
// zero-inset contract. A stacked quick-search row still owns its own space.
for (const style of ['floating', 'dock']) {
  const item = fixture(style);
  firstNavigationScroll(item);
  assert.equal(item.shell.webViewportPresentation.contentTopPx, 0, `${style} must still immerse`);
}
const dockQuickSearch = fixture('dock', 39, 48);
firstNavigationScroll(dockQuickSearch);
assert.equal(dockQuickSearch.shell.webViewportPresentation.contentTopPx, 48);
console.log('Split toolbar immersion frame: first navigation scroll clears the painted search row without a tabs round trip.');

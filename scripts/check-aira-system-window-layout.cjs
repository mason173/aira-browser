#!/usr/bin/env node
'use strict';

// Execute the production root-area/lifecycle callbacks and layout model. The
// UIContext mock supplies only native measured geometry; no device is captured.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();

function evaluate(source, filename, globals = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText, {
    module, exports: module.exports,
    require(specifier) {
      assert.ok(specifier.startsWith('.'), `Unexpected platform dependency: ${specifier}`);
      return load(path.resolve(path.dirname(filename), `${specifier}.ets`));
    },
    ...globals
  }, { filename });
  return module.exports;
}

function load(filename) {
  if (!cache.has(filename)) cache.set(filename, evaluate(fs.readFileSync(filename, 'utf8'), filename));
  return cache.get(filename);
}

const shellFile = path.join(sourceRoot, 'app/pages/BrowserShellPage.ets');
const source = fs.readFileSync(shellFile, 'utf8');
function method(name) {
  const match = source.match(new RegExp(`  (?:private )?${name}\\([^]*?\\n  }`));
  assert.ok(match, `Missing production method ${name}`);
  return match[0];
}
const areaCallback = source.match(/\.onAreaChange\(\(_oldArea: Area, newArea: Area\) => \{([^]*?)\n    \}\)/);
assert.ok(areaCallback, 'Browser root must report its measured area');
const Shell = evaluate(`class Shell {
  onRootArea(newArea) { ${areaCallback[1]} }
  ${['onPageShow', 'refreshRootBottomPanelLayoutState', 'syncMeasuredRootViewport',
    'parseAreaDimension', 'parseAreaPosition'].map(method).join('\n')}
}
module.exports = Shell;`, shellFile, {
  buildBrowserTabPreviewVisibleSurfaceSnapshotId: id => `root:${id}`
});
const { BrowserRootBottomPanelLayoutModel } = load(
  path.join(sourceRoot, 'core/browser/BrowserRootBottomPanelLayoutModel.ets'));
const noop = () => {};

function createShell(showHomePage) {
  const layout = new BrowserRootBottomPanelLayoutModel();
  const shell = Object.assign(new Shell(), {
    density: 3, measuredSizePx: { width: 1170, height: 2532 }, measuredPositionVp: { x: 0, y: 0 },
    rootMounted: true,
    browserPageForeground: true, showHomePage, activeTabId: 'test-tab',
    rootViewportLeft: 0, rootViewportTop: 0, rootViewportWidth: 390, rootViewportHeight: 844,
    browserWindowDisplayViewportWidth: 390, browserWindowDisplayViewportHeight: 844,
    browserSearchSuggestionSnapshot: { homeSearchFocused: false }, webBottomAddressFocused: false,
    browserRootBottomPanelSessionCoordinator: { buildLayoutState: input => layout.buildState(input) },
    syncWindowSafeInsetsForShell: noop, scheduleWebSafeInsetSettleSync: noop,
    refreshWebViewportPresentation: noop, syncWebToolbarClearance: noop,
    browserTabHomeCoordinator: { refreshWallpaperPresentation: noop },
    browserAddressBarTabSwipeCoordinator: { cancel: noop },
    browserWebBottomSafeAreaCoordinator: { requestCheck: noop, setVisible: noop },
    homeWallpaperPlaybackGate: { handlePageShow: noop }, browserVolumeKeyAudioService: { start: noop },
    browserWebTopImmersionSessionCoordinator: { holdCoveredStatusBarForPageReturn: noop },
    browserShellLifecycleCoordinator: { handlePageShow: noop },
    syncBottomPanelStatusBarStyle: noop, noteBottomToolbarGuideBrowsingSurface: noop,
    checkClientUpdatePolicy: noop
  });
  shell.getUIContext = () => ({
    px2vp: value => value / shell.density,
    getFrameNodeById(id) {
      assert.equal(id, 'root:test-tab', 'Re-measure the mounted browser root');
      return shell.rootMounted ? {
        getMeasuredSize: () => shell.measuredSizePx,
        getPositionToWindow: () => shell.measuredPositionVp
      } : null;
    }
  });
  const onRootArea = shell.onRootArea.bind(shell);
  shell.onRootArea = nextArea => {
    measure(shell, nextArea);
    onRootArea(nextArea);
  };
  return shell;
}

function area(width, height, top = 0, left = 0) {
  return { width, height, globalPosition: { x: left, y: top } };
}

function measure(shell, nextArea) {
  shell.measuredSizePx = { width: nextArea.width * shell.density, height: nextArea.height * shell.density };
  shell.measuredPositionVp = nextArea.globalPosition;
}

let scenarios = 0;
for (const home of [true, false]) {
  for (const hiddenDuringResize of [false, true]) {
    for (const split of [area(390, 400), area(390, 300, 544), area(195, 844), area(300, 649, 195, 90)]) {
      const shell = createShell(home);
      let visibleEffects = 0;
      let viewportRefreshes = 0;
      shell.syncWindowSafeInsetsForShell = () => visibleEffects++;
      shell.refreshWebViewportPresentation = () => viewportRefreshes++;
      const hostKey = home ? 'homeHostHeight' : 'webHostHeight';
      shell.onRootArea(area(390, 844));
      for (let cycle = 0; cycle < 3; cycle++) {
        shell.browserPageForeground = !hiddenDuringResize;
        const effectsBeforeResize = visibleEffects;
        shell.onRootArea(split);
        assert.equal(shell.rootBottomPanelLayoutState[hostKey], split.height,
          'The toolbar host must follow the actual system split window height');
        assert.equal(shell.rootViewportTop, split.globalPosition.y);
        assert.equal(shell.rootViewportLeft, split.globalPosition.x);
        if (hiddenDuringResize) assert.equal(visibleEffects, effectsBeforeResize,
          'Hidden-page geometry updates must not run foreground window effects');
        shell.onPageShow();
        shell.browserPageForeground = !hiddenDuringResize;
        shell.onRootArea(area(390, 844));
        shell.onPageShow();
        assert.equal(shell.rootBottomPanelLayoutState[hostKey], 844,
          `After exiting system split screen, the ${home ? 'home' : 'web'} toolbar must return to the ` +
          `full-height bottom edge (resize before foreground=${hiddenDuringResize})`);
        assert.equal(shell.rootViewportTop, 0, 'Restoring full screen resets the split-window origin');
        scenarios++;
      }
      assert.equal(viewportRefreshes, 13, 'Web geometry must follow root resizes and foreground recovery');
      shell.browserPageForeground = false;
      for (const invalid of [area(0, 0), area(390, 0), area(-1, 844), area('invalid', 844)]) {
        shell.onRootArea(invalid);
      }
      shell.onPageShow();
      assert.equal(shell.rootBottomPanelLayoutState[hostKey], 844,
        'Transient empty/invalid measurements must not replace the last valid frame');
      assert.equal(viewportRefreshes, 14);
    }
  }
}

// Returning from Settings or a system transition must recover even when ArkUI
// did not deliver a root-area callback while the page was hidden.
for (const home of [true, false]) {
  const shell = createShell(home);
  shell.onRootArea(area(390, 400));
  shell.browserPageForeground = false;
  measure(shell, area(390, 844));
  shell.onPageShow();
  assert.equal(shell.rootViewportHeight, 844, 'Foreground must re-read the current measured root');

  // A real density change keeps the measured pixel size; conversion must use
  // the window UIContext density, rather than assuming a full-display window.
  shell.onRootArea(area(300, 649, 12, 8));
  shell.browserPageForeground = false;
  shell.density = 4;
  shell.browserWindowDisplayViewportWidth = 293;
  shell.browserWindowDisplayViewportHeight = 633;
  shell.onPageShow();
  assert.equal(shell.rootViewportWidth, 225);
  assert.equal(shell.rootViewportHeight, 487);
  assert.equal(shell.rootViewportLeft, 8, 'FrameNode positions already use vp');
  assert.equal(shell.rootViewportTop, 12);

  // System visual scaling can leave layout unchanged. Repeated display
  // refreshes must not infer another viewport from physical screen dimensions.
  for (let refresh = 0; refresh < 3; refresh++) shell.refreshRootBottomPanelLayoutState();
  assert.equal(shell.rootViewportHeight, 487);
  shell.rootMounted = false;
  shell.onPageShow();
  assert.equal(shell.rootViewportHeight, 487, 'An unmounted root retains its last valid geometry');
}

console.log(`system window layout: ok (${scenarios} home/web resize round trips, resume and density recovery)`);

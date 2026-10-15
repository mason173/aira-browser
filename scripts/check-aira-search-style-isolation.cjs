#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');

const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const read = relative => fs.readFileSync(path.join(sourceRoot, relative), 'utf8');
const cache = new Map();

function evaluate(source, globals = {}) {
  const module = { exports: {} };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports, ...globals });
  return module.exports;
}

function load(relative) {
  if (!cache.has(relative)) {
    cache.set(relative, evaluate(read(relative), {
      require: id => load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), `${id}.ets`)))
    }));
  }
  return cache.get(relative);
}

// Run the shell's real host wiring and the component's real layout predicate,
// excluding native UI initialization and unrelated page responsibilities.
function method(source, name) {
  const match = source.match(new RegExp(`  private ${name}\\([^]*?\\n  }`));
  assert.ok(match, `Missing production method ${name}`);
  return match[0];
}

const shellSource = read('app/pages/BrowserShellPage.ets');
const chromeSource = read('app/components/browser/BrowserSplitToolbarChrome.ets');
const hostPolicy = load('core/search/BrowserSearchInvocationHostPolicy.ets');
const toolbarPolicy = load('core/browser/BrowserToolbarChromeStylePolicy.ets');
const { SearchShell } = evaluate(`export class SearchShell {
  ${method(shellSource, 'resolveSearchInvocationHostKind')}
  ${method(shellSource, 'usesCenteredHomeSearchGeometry')}
  ${method(shellSource, 'openCenteredHomeSearch')}
}`, { ...hostPolicy, ...toolbarPolicy, curves: { interpolatingSpring: () => 'spring' } });

const dockBranch = chromeSource.match(/if \(([^\n]+)\) \{\s*this\.buildDockSearchPage\(\)/);
assert.ok(dockBranch, 'The search surface must select its dock page explicitly');
const layoutMethods = ['usesHomeSearchGeometry', 'shouldShowTopBar',
  'shouldMountCenteredSearchGeometryHost']
  .filter(name => chromeSource.includes(`private ${name}(`))
  .map(name => method(chromeSource, name)).join('\n');
const { SearchChrome } = evaluate(`export class SearchChrome {
  ${layoutMethods}
  layout(): string { return (${dockBranch[1]}) ? 'dock' : 'split'; }
}`, { ...toolbarPolicy });

const failures = [];
function check(actual, expected, message) {
  try { assert.equal(actual, expected, message); } catch (error) { failures.push(error.message); }
}

// A homepage flag can still be present when search opens during navigation.
// Neither that flag nor the chosen homepage frame may change the toolbar's editor.
for (const chromeStyle of ['split', 'dock']) {
  for (const homeScene of [true, false]) {
    for (const homeSearchGeometry of [true, false]) {
      const chrome = Object.assign(new SearchChrome(), { chromeStyle, homeScene, homeSearchGeometry });
      check(chrome.layout(), chromeStyle,
        `${chromeStyle} search must keep its own layout (home=${homeScene}, centered=${homeSearchGeometry})`);
      if (chromeStyle === 'dock') {
        check(chrome.shouldShowTopBar(), false, 'Dock must never mount a split top editor');
        check(chrome.shouldMountCenteredSearchGeometryHost(), false,
          'Dock must never mount the split geometry editor alongside its bottom editor');
      }
    }
  }
}

// Replay switching toolbar styles while the previous search overlay is still
// mounted/closing. Its stale flags must not select the next search host.
for (const previousStyle of ['floating', 'split', 'dock']) {
  for (const toolbarChromeStyle of ['floating', 'split', 'dock']) {
    for (const staleOverlay of [false, true]) {
      const shell = Object.assign(new SearchShell(), {
        toolbarChromeStyle: previousStyle,
        splitSearchOverlayPrepared: staleOverlay,
        centeredHomeSearchSessionMounted: staleOverlay,
        centeredHomeSearchGeometryOpen: staleOverlay,
        isLargeScreenShellFamilyActive: () => false,
        shouldUseSplitToolbarChrome: () => toolbarChromeStyle !== 'floating'
      });
      shell.toolbarChromeStyle = toolbarChromeStyle;
      check(shell.resolveSearchInvocationHostKind(), toolbarChromeStyle === 'floating' ? 'floating' : 'split',
        `${previousStyle} -> ${toolbarChromeStyle} must ignore old overlay flags (${staleOverlay})`);
    }
  }
}

// Exercise the real home click handler, including the animation branch. A dock
// home click must publish an open without preparing a split geometry transition.
for (const toolbarChromeStyle of ['floating', 'split', 'dock']) {
  let opens = 0;
  let animations = 0;
  const shell = Object.assign(new SearchShell(), {
    toolbarChromeStyle,
    floatingToolbarSearchOpenRequestVersion: 0,
    centeredHomeSearchGeometryOpen: false,
    isCenteredHomePageStyleActive: () => true,
    isLargeScreenShellFamilyActive: () => false,
    shouldUseSplitToolbarChrome: () => toolbarChromeStyle !== 'floating',
    getUIContext: () => ({ animateTo: (_options, apply) => { animations++; apply(); } }),
    requestSplitToolbarSearchOpen: () => { opens++; }
  });
  shell.openCenteredHomeSearch();
  check(animations, toolbarChromeStyle === 'split' ? 1 : 0, `${toolbarChromeStyle} home animation`);
  check(opens, toolbarChromeStyle === 'floating' ? 0 : 1, `${toolbarChromeStyle} home open`);
  check(shell.floatingToolbarSearchOpenRequestVersion, toolbarChromeStyle === 'floating' ? 1 : 0,
    `${toolbarChromeStyle} floating home entry`);
}

async function replaySessions() {
  const session = load('core/search/BrowserSearchInvocationSessionCoordinator.ets');
  const { BrowserSearchInvocationHostRouter } = load('core/search/BrowserSearchInvocationHostRouter.ets');
  const { BrowserSplitToolbarSearchInvocationAdapter } = load('core/browser/BrowserSplitToolbarSearchInvocationAdapter.ets');
  const shell = Object.assign(new SearchShell(), {
    toolbarChromeStyle: 'floating',
    isLargeScreenShellFamilyActive: () => false,
    shouldUseSplitToolbarChrome: () => shell.toolbarChromeStyle !== 'floating'
  });
  let homeScene = true;
  let painted = '';
  const floating = {
    resolveScene: () => new session.BrowserSearchSceneSnapshot(homeScene ? 'home' : 'web', true, '', 'caret_end'),
    present: async () => { painted = 'floating'; return new session.BrowserSearchPresentationCommitResult('committed'); },
    suspend: () => {}, end: () => {}
  };
  const split = new BrowserSplitToolbarSearchInvocationAdapter({
    beginSearchSession: () => {}, cancelPendingWork: () => {}
  }, {
    resolveSceneFacts: () => ({ homeScene, webSceneVisible: !homeScene, editableWebAddress: 'https://example.org' }),
    canPresent: () => shell.resolveSearchInvocationHostKind() === 'split',
    ensureHomeScene: () => { homeScene = true; },
    publishPresentation: presentation => {
      if (!presentation.editing) return;
      painted = Object.assign(new SearchChrome(), {
        chromeStyle: shell.toolbarChromeStyle, homeScene, homeSearchGeometry: true
      }).layout();
    },
    dismissPresentation: () => {}, suspendPresentation: () => {}
  });
  const router = new BrowserSearchInvocationHostRouter({
    resolveHostKind: () => shell.resolveSearchInvocationHostKind()
  }, floating, split, floating);
  const coordinator = new session.BrowserSearchInvocationSessionCoordinator();
  coordinator.registerSurfaceAdapter(router);
  let count = 0;
  for (let round = 0; round < 25; round++) {
    for (const style of ['dock', 'split', 'floating', 'dock', 'floating', 'split']) {
      shell.toolbarChromeStyle = style;
      for (const home of [true, false]) {
        homeScene = home;
        shell.centeredHomeSearchGeometryOpen = true; // old overlay may still be closing
        const receipt = coordinator.open('browser_chrome');
        const result = await receipt.presentation;
        check(result.kind, 'presentation_committed', 'Search must commit after a toolbar switch');
        check(painted, style, `${style} ${home ? 'home' : 'web'} session selected the wrong search page`);
        const repeated = await coordinator.open('browser_chrome').presentation;
        check(repeated.kind, 'presentation_committed', 'Tapping an open search again must reinforce it');
        check(painted, style, 'Reinforcing a search must keep its toolbar style');
        coordinator.end(receipt.authorityId, 'explicit_exit');
        count++;
      }
    }
  }
  if (failures.length) throw new Error(failures.join('\n'));
  console.log(`search style isolation: ok (layout/entry matrices, toolbar switches, ${count} home/web sessions)`);
}

replaySessions().catch(error => { console.error(error.message); process.exitCode = 1; });

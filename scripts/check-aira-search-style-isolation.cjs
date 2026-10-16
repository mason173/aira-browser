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
const dockSource = read('app/components/browser/BrowserDockSearchSurface.ets');
const splitSource = read('app/components/browser/BrowserSplitSearchSurface.ets');
const hostPolicy = load('core/search/BrowserSearchInvocationHostPolicy.ets');
const toolbarPolicy = load('core/browser/BrowserToolbarChromeStylePolicy.ets');
const { SearchShell } = evaluate(`export class SearchShell {
  isCenteredHomePageStyleActive(): boolean { return false; }
  ${method(shellSource, 'resolveSearchPresentationTarget')}
  ${method(shellSource, 'resolveSearchInvocationHostKind')}
  ${method(shellSource, 'usesCenteredHomeSearchGeometry')}
  ${method(shellSource, 'openCenteredHomeSearch')}
  ${method(shellSource, 'applySplitToolbarSearchPresentation')}
  ${method(shellSource, 'clearSplitToolbarSearchOpen')}
  ${method(shellSource, 'dismissSplitToolbarSearch')}
  ${method(shellSource, 'suspendSplitToolbarSearchPresentation')}
  ${method(shellSource, 'finishSplitToolbarSearchClose')}
  ${method(shellSource, 'reverseCenteredHomeSearchGeometry')}
  ${method(shellSource, 'syncSearchInvocationPresentationHost')}
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

// The actual mount must consume the same decision as routing and home geometry.
const appearanceBinding = shellSource.match(/chromeStyle: ([^\n]+),/);
assert.ok(appearanceBinding, 'Missing search appearance binding');
const { boundAppearance } = evaluate(`export function boundAppearance() { return ${appearanceBinding[1]}; }`);
for (const toolbarChromeStyle of ['floating', 'split', 'dock']) {
  for (const largeScreen of [false, true]) {
    for (const centeredHome of [false, true]) {
      for (const visible of [false, true]) {
        for (const prepared of [false, true]) {
          const shell = Object.assign(new SearchShell(), {
            toolbarChromeStyle, splitSearchOverlayPrepared: prepared,
            isLargeScreenShellFamilyActive: () => largeScreen,
            isCenteredHomePageStyleActive: () => centeredHome,
            shouldUseSplitToolbarChrome: () => visible && toolbarChromeStyle !== 'floating'
          });
          const target = shell.resolveSearchPresentationTarget();
          check(boundAppearance.call(shell), largeScreen ? 'large_screen' : toolbarChromeStyle,
            'Mounted appearance must come from the selected toolbar, including unavailable hosts');
          check(target.hostKind, largeScreen ? 'large_screen' : toolbarChromeStyle === 'floating' ?
            'floating' : visible || prepared ? 'split' : 'unavailable', 'Runtime host availability');
          check(shell.usesCenteredHomeSearchGeometry(),
            toolbarChromeStyle === 'split' && centeredHome && !largeScreen,
            'Only the split appearance uses the centered-home flight');
        }
      }
    }
  }
}

const { BrowserToolbarSearchPresentationCoordinator } =
  load('core/browser/BrowserToolbarSearchPresentationCoordinator.ets');
function presentationShell(style, home, centered = false) {
  const finishedAnimations = [];
  let resets = 0;
  const shell = Object.assign(new SearchShell(), {
    toolbarChromeStyle: style, showHomePage: home,
    toolbarSearchPresentationCoordinator: new BrowserToolbarSearchPresentationCoordinator(),
    splitToolbarSearchDismissVersion: 0,
    isLargeScreenShellFamilyActive: () => false,
    isCenteredHomePageStyleActive: () => centered,
    shouldUseSplitToolbarChrome: () => style !== 'floating',
    // Shell must consume the adapter's normalized draft; it must not reconstruct it.
    resolveEditableWebBottomAddress: () => { throw new Error('Shell recomputed the accepted draft'); },
    browserSearchSuggestionCoordinator: { reset: () => { resets++; } },
    getUIContext: () => ({ animateTo: (options, apply) => {
      apply();
      if (options.onFinish) finishedAnimations.push(options.onFinish);
    } })
  });
  return { shell, finishedAnimations, resets: () => resets };
}

// Drive the real Shell close wiring, not only the generation predicate. A stale
// native animation must not clear a newly accepted presentation or its draft.
for (const style of ['split', 'dock']) {
  for (const home of [false, true]) {
    const fixture = presentationShell(style, home, true);
    const { shell, finishedAnimations } = fixture;
    const present = draft => shell.applySplitToolbarSearchPresentation({
      editing: true, draft, selection: 'caret_end', authorityId: 'authority', scene: home ? 'home' : 'web'
    });
    present('');
    check(shell.splitToolbarSearchOpen.draft, '', 'An accepted empty draft stays empty');
    shell.dismissSplitToolbarSearch();
    const oldCompletion = finishedAnimations.shift();
    present('new draft');
    const version = shell.splitToolbarSearchOpen.version;
    const resetCount = fixture.resets();
    if (oldCompletion) oldCompletion();
    check(shell.splitToolbarSearchActive, true, 'Old close cannot end the newer search');
    check(shell.splitToolbarSearchOpen.draft, 'new draft', 'Old close cannot clear the newer draft');
    check(shell.splitToolbarSearchOpen.version, version, 'Old close cannot publish another open');
    check(fixture.resets(), resetCount, 'Old close cannot reset the new suggestions');
    shell.suspendSplitToolbarSearchPresentation();
    check(shell.splitToolbarSearchActive, false, 'Suspension closes the native surface');
    check(shell.splitToolbarSearchOpen.draft, '', 'Suspension clears the presentation draft');
  }
}

// Split <-> dock changes keep the same runtime host, but still require an
// explicit re-presentation. Unchanged content must never trigger that refresh.
{
  let refreshes = 0;
  const { SearchHostSync } = evaluate(`export class SearchHostSync {
    ${method(shellSource, 'syncSearchInvocationPresentationHost')}
  }`, { BrowserSearchInvocationRuntime: {
    isSurfaceAdapterRegistered: () => true,
    refreshPresentation: () => { refreshes++; }
  } });
  const shell = Object.assign(new SearchHostSync(), {
    boundSearchInvocationHostKind: 'split', boundSearchAppearance: 'split',
    resolveSearchPresentationTarget: () => ({ hostKind: 'split', appearance: 'dock' }),
    getWindowScopeId: () => 'window'
  });
  shell.syncSearchInvocationPresentationHost();
  check(refreshes, 1, 'Changing appearance within the shared host refreshes presentation');
  shell.syncSearchInvocationPresentationHost();
  check(refreshes, 1, 'The same appearance does not refresh on content updates');
}

// Execute the real dock builder against a recording tree. Only ArkUI's container
// block syntax is rewritten; its conditionals and layout modifiers run unchanged.
// This checks the editor's position, not merely which search builder was selected.
function recordableBuilder(source) {
  const edits = [];
  for (const match of source.matchAll(/\b(Stack|Column)\(([^\n]*)\) \{/g)) {
    const opening = match.index + match[0].length - 1;
    const scanner = ts.createScanner(ts.ScriptTarget.Latest, true,
      ts.LanguageVariant.Standard, source.slice(opening));
    let depth = 0;
    let closing = -1;
    for (let token = scanner.scan(); token !== ts.SyntaxKind.EndOfFileToken; token = scanner.scan()) {
      if (token === ts.SyntaxKind.OpenBraceToken) depth++;
      if (token === ts.SyntaxKind.CloseBraceToken && --depth === 0) {
        closing = opening + scanner.getTokenPos() + 1;
        break;
      }
    }
    assert.ok(closing > opening, 'Unclosed ArkUI container');
    edits.push([closing, 0, ')']);
    edits.push([match.index, match[0].length,
      `${match[1]}(${match[2]}${match[2] ? ', ' : ''}() => {`]);
  }
  for (const [at, length, replacement] of edits.sort((a, b) => b[0] - a[0])) {
    source = source.slice(0, at) + replacement + source.slice(at + length);
  }
  return source;
}

const { DockContent } = evaluate(`export class DockContent {
  ${method(dockSource, 'shouldShowDockSuggestions')}
  ${method(dockSource, 'resolveDockQuerySuggestions')}
}`);
const dockBuilder = method(dockSource, 'buildDockSurface');
const dockBody = dockBuilder.slice(dockBuilder.indexOf('{') + 1, dockBuilder.lastIndexOf('}'));
const dockConstants = Object.fromEntries([...dockSource.matchAll(
  /const (DOCK_SEARCH_\w+): number = ([\d.]+);/g)].map(match => [match[1], Number(match[2])]));
const historyBuilder = method(dockSource, 'buildDockSearchHistory');
assert.match(historyBuilder, /\n    \.layoutWeight\(1\)/,
  'The history viewport must occupy the space above the dock editor');
assert.ok(!/toolbarChromeStyle|chromeStyle/.test(dockSource + splitSource),
  'Fixed search layouts must not choose another toolbar appearance');
assert.match(splitSource, /layoutMode: 'topDown'/, 'Split suggestions stay below the top editor');

function recordDockPage(chrome) {
  let current;
  let root;
  const component = name => (...args) => {
    const node = { name, children: [], attrs: {} };
    if (current) current.children.push(node); else root = node;
    const callback = args.find(arg => typeof arg === 'function');
    if (callback) {
      const parent = current;
      current = node;
      callback();
      current = parent;
    }
    const proxy = new Proxy({}, {
      get: (_, attr) => value => { node.attrs[attr] = value; return proxy; }
    });
    return proxy;
  };
  const { draw } = evaluate(`export function draw() { ${recordableBuilder(dockBody)} }`, {
    ...dockConstants,
    Stack: component('Stack'), Column: component('Column'),
    BrowserSearchSuggestionsPanel: component('suggestions'),
    BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT: 36,
    Alignment: { Bottom: 'bottom' }, FlexAlign: { End: 'end', Start: 'start' },
    HitTestMode: { Default: 'default' }
  });
  Object.assign(chrome, {
    buildDockSearchHistory: () => component('history')().layoutWeight(1),
    editor: () => component('editor')(), engineMenu: () => component('engineMenu')(),
    topSafeInsetVp: 24, bottomSafeInsetVp: 20
  });
  draw.call(chrome);
  return root;
}

// Replay first open, each keystroke, asynchronous suggestions, clearing history
// and clearing input. A history-only suggestion is filtered out by the real policy.
// None of these content changes may move the dock editor to the split top position.
let dockLayoutFrames = 0;
for (const keyboardInsetVp of [0, 300]) {
  for (const homeScene of [true, false]) {
    const chrome = Object.assign(new DockContent(), {
      chromeStyle: 'dock', homeScene, keyboardInsetVp, engineMenuOpen: false
    });
    for (const [query, sources, history] of [
      ['', [], false], ['a', [], false], ['a', ['remote'], false],
      ['ab', [], false], ['ab', ['bookmark'], false], ['abc', ['history'], false],
      ['abc', ['remote'], false], ['', [], true], ['', [], false],
      ['d', ['remote'], false], ['de', [], false], ['', [], false]
    ]) {
      Object.assign(chrome, { query, suggestions: sources.map(source => ({ source })),
        dockSearchHistory: history ? [{ source: 'search_history' }] : [] });
      const tree = recordDockPage(chrome);
      const column = tree.children[0];
      check(column.attrs.height, '100%', 'Dock content must fill the available viewport');
      check(column.children.length, 2, 'Dock keeps separate content and editor regions');
      check(column.children[0].attrs.layoutWeight, 1, 'Empty dock content still reserves remaining space');
      check(column.children[1].children[0].name, 'editor', 'Editor is a stable sibling of content');
      const editorHeight = dockConstants.DOCK_SEARCH_EDITOR_HEIGHT +
        dockConstants.DOCK_SEARCH_EDITOR_TOP_GAP + dockConstants.DOCK_SEARCH_EDITOR_BOTTOM_GAP;
      const viewportHeight = 800;
      const availableHeight = viewportHeight - tree.attrs.padding.top - tree.attrs.padding.bottom;
      const weightedContent = column.children.some(child => child.attrs.layoutWeight > 0);
      // Column defaults to Start. End alignment or a weighted content viewport
      // must reserve all free space before the editor, including empty states.
      const editorTop = tree.attrs.padding.top +
        (weightedContent || column.attrs.justifyContent === 'end' ? availableHeight - editorHeight : 0);
      check(editorTop, viewportHeight - tree.attrs.padding.bottom - editorHeight,
        `Dock editor jumped on ${homeScene ? 'home' : 'web'} input=${JSON.stringify(query)} ` +
        `suggestions=${sources.join(',')} history=${history} keyboard=${keyboardInsetVp}`);
      dockLayoutFrames++;
    }
  }
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
    toolbarSearchPresentationCoordinator: new BrowserToolbarSearchPresentationCoordinator(),
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
      shell.showHomePage = homeScene;
      shell.applySplitToolbarSearchPresentation(presentation);
      painted = Object.assign(new SearchChrome(), {
        chromeStyle: shell.resolveSearchPresentationTarget().appearance, homeScene, homeSearchGeometry: true
      }).layout();
    },
    dismissPresentation: () => {}, suspendPresentation: () => {}
  });
  const router = new BrowserSearchInvocationHostRouter({
    resolveHostKind: () => shell.resolveSearchInvocationHostKind()
  }, floating, split, floating);
  const coordinator = new session.BrowserSearchInvocationSessionCoordinator();
  coordinator.registerSurfaceAdapter(router);
  // Re-present an edited and then completely cleared draft while changing
  // appearances in the same session. Neither case may restore the page URL.
  for (const draft of ['typed query', '']) {
    homeScene = false;
    shell.toolbarChromeStyle = 'split';
    const opened = coordinator.open('browser_chrome');
    await opened.presentation;
    coordinator.updateDraft(opened.authorityId, draft);
    for (const style of ['dock', 'split', 'floating', 'dock']) {
      shell.toolbarChromeStyle = style;
      coordinator.refreshPresentation();
      await new Promise(resolve => setImmediate(resolve));
      check(coordinator.currentAuthorityId(), opened.authorityId, 'Appearance changes preserve authority');
      check(coordinator.snapshot().draft, draft, 'Appearance changes preserve the canonical draft');
      check(painted, style, 'The active session uses the explicitly selected appearance');
      if (style !== 'floating') {
        check(shell.splitToolbarSearchOpen.draft, draft, 'Native open preserves edited or empty draft');
        check(shell.splitToolbarSearchOpen.selectAll, false, 'Re-presentation does not reselect the address');
      }
    }
    coordinator.end(opened.authorityId, 'explicit_exit');
  }
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
  console.log(`search style isolation: ok (layout/entry matrices, toolbar switches, ` +
    `${count} home/web sessions, ${dockLayoutFrames} dock input layout frames)`);
}

replaySessions().catch(error => { console.error(error.message); process.exitCode = 1; });

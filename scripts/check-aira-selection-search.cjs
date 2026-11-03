'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const engines = [
  { id: 'bing', searchUrlTemplate: 'https://www.bing.com/search?q={searchTerms}' },
  { id: 'custom_docs', searchUrlTemplate: 'https://docs.example/search?query=%s&lang=zh' }
];
const ids = Object.fromEntries(['SEARCH', 'COPY', 'CUT', 'PASTE', 'SELECT_ALL', 'TRANSLATE'].map(value =>
  [value, { value, equals(other) { return other.value === value; } }]));
const searchItem = { id: ids.SEARCH };

// Run the production menu, generation guard, submission owner and URL template
// service; substitute only platform services and downstream navigation/history.
function fixture() {
  const modules = new Map();
  const opened = [], history = [], displayed = [], quickSearch = [], effects = [];
  let selectedEngine = 'bing', generation = 1;
  const facts = {
    activeTabId: 'tab-a', availableSearchEngines: engines,
    searchEngineSettings: { defaultSearchEngineId: 'bing' }, experiments: {},
    boundary: { profileId: 'profile-a', privacyMode: 'regular', dataScope: 'profile_persistent' },
    searchSuggestionPreferences: { searchHistoryEnabled: true }
  };
  const stubs = {
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
    SearchEngineRoutingService: { SearchEngineRoutingService: class {} },
    ExternalAppSearchService: { ExternalAppSearchService: class {} },
    ExternalNavigationLaunchService: { ExternalNavigationLaunchService: class {} },
    BrowserAddressDisplayCoordinator: { BrowserAddressDisplayCoordinator: class {
      recordSubmission(submission) { displayed.push(submission); }
    } },
    BrowserHttpsFirstNavigationService: { sharedBrowserHttpsFirstNavigationService: {
      resolveRememberedHttpFallbackUrl: () => ''
    } },
    BrowserWebNavigationGuardService: { sharedBrowserWebNavigationGuardService: {} },
    BrowserModels: { DEFAULT_SEARCH_ENGINE_ID: 'bing', SEARCH_ENGINE_OPTIONS: engines },
    UrlUtils: {},
    AppResourceText: { resolveAppResourceText: value => value },
    AddressDisplayFormatter: { normalizeNavigationTarget: value => value, resolveSearchNavigationQuery: () => '' }
  };
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative);
    const filename = path.join(root, relative);
    const module = { exports: {} };
    modules.set(relative, module.exports);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
    }).outputText;
    vm.runInNewContext(code, { module, exports: module.exports, TextMenuItemId: ids, require(name) {
      const stub = stubs[name] ?? stubs[path.basename(name)];
      if (stub !== undefined) return stub;
      if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
      return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
    } }, { filename });
    return module.exports;
  }
  const routing = { resolve() { throw new Error('Selection search must not infer a navigation from its text'); } };
  const { BrowserAddressSubmissionCoordinator } = load('core/navigation/BrowserAddressSubmissionCoordinator.ets');
  const coordinator = new BrowserAddressSubmissionCoordinator({
    resolveSessionFacts: () => facts,
    completeSearchSession: () => effects.push('complete'),
    prepareForNavigation: () => effects.push('prepare'),
    present: () => effects.push('present')
  }, routing, { async recordSubmittedSearch(input) { history.push(input); return true; } }, undefined,
  { open: request => opened.push(request),
    openCurrentAppUi: () => assert.fail('Selection search must preserve the source tab') },
  { recordAddressSubmission: (input, tabId) => quickSearch.push({ ...input, tabId }) });
  const { BrowserWebEventHostCoordinator } = load('core/browser/BrowserWebEventHostCoordinator.ets');
  const callbacks = new BrowserWebEventHostCoordinator().buildCallbacks({
    onSearchSelectedText: (tabId, text) => coordinator.submitSelectedText(tabId, text, selectedEngine)
  });
  const { buildGenerationBoundHostedWebNodeCallbacks } = load('core/browser/BrowserHostedWebNodeGenerationCallbacks.ets');
  const guarded = buildGenerationBoundHostedWebNodeCallbacks('tab-a', 1, callbacks,
    (tabId, candidate) => tabId === 'tab-a' && candidate === generation);
  const { WebTextSelectionMenuController } = load('core/web/WebTextSelectionMenuController.ets');
  function menuFor(tabId) {
    const menu = new WebTextSelectionMenuController();
    menu.bindSearch(text => guarded.onSearchSelectedText(tabId, text));
    return menu;
  }
  return { coordinator, routing, menu: menuFor('tab-a'), menuFor, facts, opened, history, displayed, load,
    quickSearch, effects, setEngine: value => { selectedEngine = value; },
    setGeneration: value => { generation = value; } };
}

test('Search uses the engine selected at click time, including custom templates and encoded Unicode', () => {
  const f = fixture();
  f.menu.updateSelection('  鸿蒙 & Aira + 100%  ');
  for (const engine of engines) {
    f.setEngine(engine.id);
    assert.equal(f.menu.handleMenuItemClick(searchItem), true);
    const expectedUrl = engine.searchUrlTemplate.replace('%s', '{searchTerms}')
      .replace('{searchTerms}', encodeURIComponent('鸿蒙 & Aira + 100%'));
    assert.equal(f.opened.at(-1).url, expectedUrl);
    f.opened.at(-1).prepareCreatedTab('tab-result');
    assert.equal(f.history.at(-1).submission.searchEngineId, engine.id);
    assert.equal(f.displayed.at(-1).submittedText, '鸿蒙 & Aira + 100%');
    assert.equal(f.quickSearch.at(-1).resolvedUrl, expectedUrl);
  }
  assert.deepEqual(f.effects, ['complete', 'prepare', 'present', 'complete', 'prepare', 'present']);
});

test('URL-shaped selections remain search terms', () => {
  const f = fixture();
  const query = 'https://example.com/path?x=1&y=2';
  f.menu.updateSelection(query);
  f.menu.handleMenuItemClick(searchItem);
  assert.equal(f.opened[0].url, `https://www.bing.com/search?q=${encodeURIComponent(query)}`);
  assert.equal(f.history[0].submission.intent, 'search');
  assert.equal(f.history[0].submission.searchQuery, query);
});

test('foreground results preserve the source tab, opener and profile/privacy boundary', () => {
  for (const privacyMode of ['regular', 'private']) {
    const f = fixture();
    f.facts.boundary = { profileId: 'profile-b', privacyMode,
      dataScope: privacyMode === 'private' ? 'session_ephemeral' : 'profile_persistent' };
    f.menu.updateSelection('selected words');
    f.menu.handleMenuItemClick(searchItem);
    assert.equal(f.opened[0].intent, 'new_tab');
    assert.equal(f.opened[0].source, 'web_context_menu');
    assert.equal(f.opened[0].openerTabId, 'tab-a');
    assert.equal(f.opened[0].createOptions, f.facts.boundary);
    assert.equal(f.history[0].boundary, f.facts.boundary);
    assert.equal(f.history[0].preferences, f.facts.searchSuggestionPreferences);
  }
});

test('search display and engine-switch context bind only after the destination tab is created', () => {
  const f = fixture();
  f.menu.updateSelection('new query');
  f.menu.handleMenuItemClick(searchItem);
  assert.equal(f.displayed.length, 0);
  assert.equal(f.quickSearch.length, 0);
  f.opened[0].prepareCreatedTab('tab-result');
  assert.equal(f.displayed[0].submittedText, 'new query');
  assert.equal(f.quickSearch[0].query, 'new query');
  assert.equal(f.quickSearch[0].tabId, 'tab-result');
});

test('a result tab owns its new search without replacing the source tab engine-switch context', () => {
  const f = fixture();
  const { BrowserQuickSearchSwitchingCoordinator } = f.load('core/search/BrowserQuickSearchSwitchingCoordinator.ets');
  let activeTabId = 'tab-a';
  const quick = new BrowserQuickSearchSwitchingCoordinator(
    { listEngines: () => engines }, { isEnabled: () => true }, { resolveController: () => undefined }, {},
    { refreshVisibleInset() {} }, {
      resolveActiveTabId: () => activeTabId,
      resolveTabIds: () => ['tab-a', 'tab-result'],
      resolveCurrentBoundary: () => f.facts.boundary,
      isWebPageVisible: () => true, isWebAppActive: () => false, publishPresentation() {}
    });
  quick.recordAddressSubmission({ intent: 'search', query: 'source query', searchEngineId: 'bing',
    resolvedUrl: 'https://www.bing.com/search?q=source%20query' });
  quick.recordAddressSubmission({ intent: 'search', query: 'selected words', searchEngineId: 'custom_docs',
    resolvedUrl: 'https://docs.example/search?query=selected%20words' }, 'tab-result');
  assert.equal(quick.getPresentation().query, 'source query');
  activeTabId = 'tab-result';
  quick.syncActivePresentation('test-new-tab');
  assert.equal(quick.getPresentation().query, 'selected words');
  assert.equal(quick.getPresentation().selectedEngineId, 'custom_docs');
  activeTabId = 'tab-a';
  quick.syncActivePresentation('test-source-tab');
  assert.equal(quick.getPresentation().query, 'source query');
});

test('copy, paste, select all and translation retain their system actions', () => {
  const f = fixture();
  f.menu.updateSelection('selected words');
  for (const name of ['COPY', 'CUT', 'PASTE', 'SELECT_ALL', 'TRANSLATE']) {
    assert.equal(f.menu.handleMenuItemClick({ id: ids[name] }), false);
  }
  assert.equal(f.opened.length, 0);
});

test('empty, cleared and inactive selections never open a result or fall through to system search', () => {
  const f = fixture();
  for (const text of ['', ' \n ', 'old selection']) {
    f.menu.updateSelection(text);
    if (text === 'old selection') f.menu.clearSelection();
    assert.equal(f.menu.handleMenuItemClick(searchItem), true);
  }
  f.menu.updateSelection('background selection');
  f.facts.activeTabId = 'tab-b';
  assert.equal(f.menu.handleMenuItemClick(searchItem), true);
  assert.equal(f.opened.length, 0);
  assert.equal(f.history.length, 0);
});

test('a changed selection replaces the previous text and separate Web instances do not share text', () => {
  const f = fixture();
  f.menu.updateSelection('old words');
  f.menu.updateSelection('new words');
  const otherMenu = f.menuFor('tab-a');
  otherMenu.handleMenuItemClick(searchItem);
  assert.equal(f.opened.length, 0);
  f.menu.handleMenuItemClick(searchItem);
  assert.equal(f.history[0].submission.searchQuery, 'new words');
  f.menu.unbind();
  assert.equal(f.menu.handleMenuItemClick(searchItem), false);
});

test('obsolete Web generations and mismatched tab callbacks cannot navigate', () => {
  const f = fixture();
  f.menu.updateSelection('obsolete words');
  f.setGeneration(2);
  assert.equal(f.menu.handleMenuItemClick(searchItem), true);
  f.setGeneration(1);
  const otherMenu = f.menuFor('tab-b');
  otherMenu.updateSelection('other tab');
  assert.equal(otherMenu.handleMenuItemClick(searchItem), true);
  assert.equal(f.opened.length, 0);
});

test('a pending address submission cannot replace a newer selection search', async () => {
  const f = fixture();
  let resolve;
  f.routing.resolve = () => new Promise(done => { resolve = done; });
  const pending = f.coordinator.submitAddress('old query', 'bing');
  f.menu.updateSelection('new query');
  f.menu.handleMenuItemClick(searchItem);
  resolve({ rawInput: 'old query', submittedText: 'old query', resolvedUrl: 'https://old.example/',
    intent: 'search', searchQuery: 'old query', searchEngineId: 'bing', primarySearchEngineId: 'bing',
    fallbackApplied: false, fallbackMessage: '', httpFallbackUrl: '' });
  await pending;
  assert.equal(f.opened.length, 1);
  assert.equal(f.history[0].submission.searchQuery, 'new query');
});

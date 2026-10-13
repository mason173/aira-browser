#!/usr/bin/env node
'use strict';

// Production ArkTS, synthetic repositories and deterministic timers. No user data or UI capture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
async function settle() { for (let i = 0; i < 12; i++) await Promise.resolve(); }
function environment() {
  let now = 0, sequence = 0;
  const timers = new Map();
  const modules = new Map();
  const requests = [];
  class Remote {
    fetchSuggestions(query) {
      const gate = deferred(); requests.push({ query, ...gate }); return gate.promise;
    }
  }
  function load(relative) {
    const filename = path.resolve(root, relative);
    if (modules.has(filename)) return modules.get(filename);
    const module = { exports: {} };
    modules.set(filename, module.exports);
    const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
      reportDiagnostics: true
    });
    assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
    vm.runInNewContext(result.outputText, {
      module, exports: module.exports, Date,
      $r: (name, ...args) => ({ name, args }),
      setTimeout(fn, delay) { timers.set(++sequence, { fn, at: now + delay }); return sequence; },
      clearTimeout(id) { timers.delete(id); },
      require(name) {
        if (name.endsWith('/BrowserModels')) return { buildBrowserDataBoundary: input => ({
          profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent', ...input
        }) };
        if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: resource => resource?.name ?? 'seed' };
        if (name === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
        if (name.endsWith('/UrlUtils')) return { looksLikeUrl: value => /^https?:\/\//.test(value) };
        if (name.endsWith('/SearchQueryHistoryService')) return { SEARCH_QUERY_HISTORY_VISIBLE_LIMIT: 8 };
        if (name.endsWith('/ExternalAppSearchService')) return { ExternalAppSearchService: class { listVisibleTargets() { return []; } } };
        if (name.endsWith('/QihooSearchSuggestionService')) return { QihooSearchSuggestionService: Remote };
        if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
        return load(path.relative(root, path.resolve(path.dirname(filename), name + '.ets')));
      }
    }, { filename });
    return module.exports;
  }
  async function advance(to) {
    for (;;) {
      const due = [...timers].filter(([, timer]) => timer.at <= to).sort((a, b) => a[1].at - b[1].at)[0];
      if (due === undefined) break;
      now = due[1].at; timers.delete(due[0]); due[1].fn(); await settle();
    }
    now = to; await settle();
  }
  return { load, advance, requests, timers };
}
function suggestion(id, source = 'bookmarks') {
  return { id, refId: id, source, title: id, target: `https://${id}.invalid`, subtitle: '', icon: '' };
}
function fixture(options = {}) {
  const env = environment();
  const { BrowserSearchSuggestionCoordinator } = env.load('core/browser/BrowserSearchSuggestionCoordinator.ets');
  const calls = { bookmarks: 0, history: 0, searchHistory: 0, loads: 0 };
  const historyLoad = deferred(), searchHistoryLoad = deferred();
  const publications = [], opened = [];
  const facts = { query: options.query ?? 'aira', addressFocused: false, tabs: options.tabs ?? [], activeTabId: '',
    currentPageSuggestionEnabled: false, profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent',
    preferences: { regularEnabled: true, historyEnabled: true, browsingHistoryEnabled: true,
      bookmarksEnabled: true, openTabsEnabled: true, remoteEnabled: true } };
  const coordinator = new BrowserSearchSuggestionCoordinator({
    resolveFacts: () => facts, publishSnapshot: snapshot => publications.push(snapshot),
    protectAddressKeyboardSession() {}, openAddressSuggestion(target) { opened.push(target); }
  }, {
    buildSuggestions(input) {
      calls.searchHistory++;
      return input.preferences.historyEnabled && input.privacyMode !== 'private' &&
        input.dataScope !== 'session_ephemeral' ? (options.searchHistory ?? [suggestion('query', 'search_history')]) : [];
    },
    hydrateSuggestions: () => searchHistoryLoad.promise,
    deleteSearchHistoryById: async () => ({ removedCount: 1 }),
    clearRegularProfileSearchHistory: async () => ({ removedCount: 1 })
  }, {}, {
    buildSuggestions(query, limit) { calls.history++; return (options.history ?? [suggestion('visited', 'history')]).slice(0, limit); },
    ensureLoaded() { calls.loads++; return historyLoad.promise; }
  }, options.bookmarkService ?? {
    buildSuggestions(query, scope, limit) {
      calls.bookmarks++;
      return options.buildBookmarks ? options.buildBookmarks(query, scope, limit) : [suggestion(`${scope}-${query}`)];
    },
    ensureLoaded: async () => false,
    prewarm: async () => false
  });
  return { ...env, coordinator, calls, facts, publications, opened, historyLoad, searchHistoryLoad };
}

test('local suggestions refresh before the remote debounce, including continuous typing', async () => {
  const f = fixture(); f.coordinator.beginSearchSession('test');
  assert.ok(f.publications.at(-1).searchSuggestions.some(s => s.source === 'bookmarks'));
  f.facts.query = 'air'; f.coordinator.refreshDeferred(); await f.advance(0);
  assert.equal(f.calls.bookmarks, 2, 'local source must update without waiting 96ms');
  assert.equal(f.requests.length, 0, 'network alone is debounced');
  await f.advance(80); f.facts.query = 'aira'; f.coordinator.refreshDeferred(); await f.advance(80);
  assert.equal(f.calls.bookmarks, 3);
  await f.advance(160); f.facts.query = 'aira browser'; f.coordinator.refreshDeferred(); await f.advance(160);
  assert.equal(f.calls.bookmarks, 4);
  await f.advance(255); assert.equal(f.requests.length, 0);
  await f.advance(256); assert.equal(f.requests.length, 1); assert.equal(f.requests[0].query, 'aira browser');
});

test('source hydration and remote completion never rerun unrelated local sources', async () => {
  const f = fixture(); f.coordinator.beginSearchSession('test');
  const initial = { ...f.calls };
  f.searchHistoryLoad.resolve({ hydrated: true }); await settle();
  assert.equal(f.calls.bookmarks, initial.bookmarks, 'query history must not rescan bookmarks');
  assert.equal(f.calls.history, initial.history);
  f.historyLoad.resolve(true); await settle();
  assert.equal(f.calls.bookmarks, initial.bookmarks, 'browsing history must not rescan bookmarks');
  assert.equal(f.calls.searchHistory, initial.searchHistory + 1);
  await f.advance(96); f.requests[0].resolve(['aira news']); await settle();
  assert.equal(f.calls.bookmarks, initial.bookmarks, 'network must only merge cached local results');
  assert.equal(f.calls.history, initial.history + 1);
  assert.equal(f.calls.searchHistory, initial.searchHistory + 1);
  assert.deepEqual(Array.from(f.publications.at(-1).searchSuggestions, s => s.source),
    ['bookmarks', 'history', 'search_history', 'suggestions']);
});

test('disabled or empty browsing-history source does not load its index', () => {
  for (const change of [f => { f.facts.preferences.browsingHistoryEnabled = false; }, f => { f.facts.query = ''; }]) {
    const f = fixture(); change(f); f.coordinator.beginSearchSession('test'); assert.equal(f.calls.loads, 0);
  }
});

test('old remote results cannot publish across query, session, privacy, profile, or preference changes', async () => {
  for (const change of [
    f => { f.facts.query = 'changed'; },
    f => { f.coordinator.beginSearchSession('replacement'); },
    f => { f.facts.privacyMode = 'private'; f.facts.dataScope = 'session_ephemeral'; },
    f => { f.facts.profileId = 'other-profile'; },
    f => { f.facts.preferences.remoteEnabled = false; },
    f => { f.coordinator.beginClosingOverlay(); }
  ]) {
    const f = fixture(); f.coordinator.beginSearchSession('test'); await f.advance(96);
    change(f); const count = f.publications.length;
    f.requests[0].resolve(['obsolete']); await settle();
    assert.equal(f.publications.length, count);
  }
});

test('stale local hydration cannot publish in a changed scope or preference context', async () => {
  for (const change of [
    f => { f.facts.privacyMode = 'private'; f.facts.dataScope = 'session_ephemeral'; },
    f => { f.facts.preferences.historyEnabled = false; },
    f => { f.facts.profileId = 'other-profile'; }
  ]) {
    const f = fixture(); f.coordinator.beginSearchSession('test'); change(f);
    const count = f.publications.length;
    f.searchHistoryLoad.resolve({ hydrated: true }); f.historyLoad.resolve(true); await settle();
    assert.equal(f.publications.length, count);
  }
});

test('reset cancels local, remote and hydration work', async () => {
  const f = fixture(); f.coordinator.beginSearchSession('test');
  f.coordinator.refreshDeferred(); f.coordinator.reset(); const count = f.publications.length;
  f.searchHistoryLoad.resolve({ hydrated: true }); f.historyLoad.resolve(true); await f.advance(1000);
  assert.equal(f.requests.length, 0); assert.equal(f.publications.length, count);
});

function bookmark(id, title, url, scope = 'regular') {
  return { id, title, url, scope, type: 'bookmark', sync: { source: 'local' } };
}
function bookmarkFixture(nodes) {
  const env = environment();
  const { InMemoryBookmarkRepository } = env.load('data/repositories/BookmarkRepositoryCore.ets');
  const repo = Object.create(InMemoryBookmarkRepository.prototype);
  repo.suggestionCandidates = nodes; repo.bookmarkChangeGeneration = 1;
  let enumerations = 0;
  const list = repo.listSuggestionCandidates.bind(repo);
  repo.listSuggestionCandidates = (...args) => { enumerations++; return list(...args); };
  const { BookmarkOmniboxSuggestionService } = env.load('services/search/BookmarkOmniboxSuggestionService.ets');
  return { ...env, repo, service: new BookmarkOmniboxSuggestionService(repo), enumerations: () => enumerations };
}
const plain = value => JSON.parse(JSON.stringify(value));

test('indexed bookmark results preserve full-scan ranking, deduplication, Chinese and long-field recall', async () => {
  const nodes = [
    bookmark('substring', '银行发票', 'https://late.invalid'),
    bookmark('prefix', '发票中心', 'https://invoice.invalid'),
    bookmark('exact', '发票', 'https://exact.invalid'),
    bookmark('duplicate-first', '发票查询', 'https://duplicate.invalid'),
    bookmark('duplicate-second', '发票', 'https://duplicate.invalid'),
    bookmark('mixed', 'GitHub Aira', 'https://www.GitHub.com/aira/'),
    bookmark('spaces', 'Some Book Title', 'https://spaces.invalid'),
    bookmark('late-field', 'x'.repeat(200) + '后缀书签', 'https://long.invalid/' + 'a'.repeat(150) + '/tail-query'),
    bookmark('empty-title', ' ', 'https://empty-title.invalid'),
    { ...bookmark('seed', '发票', 'https://seed.invalid'), sync: { source: 'seed' } },
    bookmark('private', '发票', 'https://private.invalid', 'private')
  ];
  for (let i = 0; i < 500; i++) nodes.push(bookmark(`filler-${i}`, `文档 ${i}`, `https://filler${i}.invalid/page`));
  const f = bookmarkFixture(nodes);
  const { matchBookmarkSuggestions } = f.load('services/search/LocalOmniboxSuggestionMatcher.ets');
  for (const scope of ['regular', 'private']) {
    const pending = f.service.ensureLoaded(scope); await f.advance(0); assert.equal(await pending, true);
    for (const query of ['发', '票', '发票', 'github', ' GitHub ', 'https://www.github.com/', 'some book',
      'book', '后缀', 'tail-query', 'empty-title', 'not-present', ' ', '文档']) {
      for (const limit of [0, 1, 2, 8]) {
        const expected = matchBookmarkSuggestions(f.repo.listSuggestionCandidates(undefined, scope), query, limit);
        assert.deepEqual(plain(f.service.buildSuggestions(query, scope, limit)), plain(expected), `${scope}: ${query}, limit=${limit}`);
      }
    }
  }
});

test('warm indexed queries and repeated cold queries never re-enumerate the full repository', async () => {
  const nodes = Array.from({ length: 5000 }, (_, id) => bookmark(String(id), `书签 ${id}`, `https://entry${id}.invalid`));
  nodes.push(bookmark('unique', '独特稀有命中', 'https://unique.invalid'));
  const f = bookmarkFixture(nodes);
  f.service.buildSuggestions('独特', 'regular');
  f.service.buildSuggestions('独特', 'regular');
  assert.equal(f.enumerations(), 1, 'a repeated cold query must reuse its result');
  const pending = f.service.ensureLoaded('regular'); await f.advance(0); assert.equal(await pending, true);
  const before = f.enumerations();
  for (const query of ['稀有', 'unique', 'entry350', '书签', '不存在']) f.service.buildSuggestions(query, 'regular');
  assert.equal(f.enumerations(), before, 'warm queries must not copy/filter all bookmark nodes');
  const { BookmarkOmniboxIndex } = f.load('services/search/BookmarkOmniboxIndex.ets');
  const index = new BookmarkOmniboxIndex();
  const build = index.replaceYielding(nodes, () => false); await f.advance(0); await build;
  assert.equal(index.match('稀有', 2)[0].refId, 'unique');
  assert.equal(index.lastQueryCandidateCount(), 1, 'rare queries examine postings, not the full corpus');
});

test('bookmark edits, deletion and scope changes invalidate cached results and in-flight builds', async () => {
  const f = bookmarkFixture([
    bookmark('old', 'Aira old', 'https://old.invalid'),
    bookmark('secret', 'Aira private', 'https://secret.invalid', 'private')
  ]);
  assert.equal(f.service.buildSuggestions('aira', 'regular')[0].refId, 'old');
  const obsoleteBuild = f.service.ensureLoaded('regular');
  f.repo.suggestionCandidates = [bookmark('new', 'Aira new', 'https://new.invalid'),
    bookmark('secret', 'Aira private', 'https://secret.invalid', 'private')];
  f.repo.bookmarkChangeGeneration++;
  assert.equal(f.service.buildSuggestions('aira', 'regular')[0].refId, 'new');
  assert.equal(f.service.buildSuggestions('aira', 'private')[0].refId, 'secret');
  await f.advance(0); assert.equal(await obsoleteBuild, true, 'readiness retries the latest revision');
  assert.equal(f.service.buildSuggestions('aira', 'regular')[0].refId, 'new');
  f.repo.suggestionCandidates = []; f.repo.bookmarkChangeGeneration++;
  assert.deepEqual(plain(f.service.buildSuggestions('aira', 'regular')), []);
  assert.deepEqual(plain(f.service.buildSuggestions('aira', 'private')), []);
  await f.advance(0);
  assert.deepEqual(plain(f.service.buildSuggestions('aira', 'regular')), []);
});

test('history clear/delete refreshes only current content and keeps remote cache for the same context', async () => {
  const f = fixture(); f.coordinator.beginSearchSession('test'); await f.advance(96);
  f.requests[0].resolve(['aira news']); await settle();
  assert.equal(await f.coordinator.deleteHistorySuggestion(suggestion('query', 'search_history')), true);
  assert.equal(await f.coordinator.clearHistorySuggestions(), true);
  await f.advance(1000);
  assert.equal(f.requests.length, 1, 'local mutations must not refetch the unchanged remote query');
});

test('invalidation refreshes an active empty list so a newly added bookmark becomes visible', () => {
  const f = fixture(); f.facts.preferences.bookmarksEnabled = false;
  f.facts.preferences.historyEnabled = false; f.facts.preferences.browsingHistoryEnabled = false;
  f.coordinator.beginSearchSession('test'); assert.equal(f.coordinator.hasVisibleSuggestions(), false);
  f.facts.preferences.bookmarksEnabled = true; f.coordinator.invalidate();
  assert.equal(f.coordinator.hasVisibleSuggestions(), true);
});

test('coalesced draft changes honor session input and discard earlier hydration for the same query', async () => {
  const f = fixture();
  f.facts.query = 'shell-query';
  f.coordinator.beginSearchSession('test', { query: 'draft', focused: true, protectKeyboardSession: false });
  assert.equal(f.publications.at(-1).searchSuggestions[0].refId, 'regular-draft');
  assert.equal(f.coordinator.updateSearchSessionInput('other-authority', { query: 'ignored', focused: true }), false);
  f.coordinator.updateSearchSessionInput('test', { query: 'changed', focused: true });
  f.coordinator.refreshDeferred();
  f.coordinator.updateSearchSessionInput('test', { query: 'draft', focused: true });
  f.coordinator.refreshDeferred();
  const count = f.publications.length;
  f.searchHistoryLoad.resolve({ hydrated: true }); f.historyLoad.resolve(true); await settle();
  assert.equal(f.publications.length, count, 'input-time cancellation must reject an A→B→A callback');
  await f.advance(0);
  assert.equal(f.calls.bookmarks, 2, 'rapid same-task input is coalesced once');
  assert.equal(f.publications.at(-1).searchSuggestions[0].refId, 'regular-draft');
});

test('changing privacy refreshes the scoped local snapshot without cached regular results', async () => {
  const f = fixture(); f.coordinator.beginSearchSession('test'); await f.advance(96);
  f.requests[0].resolve(['regular remote']); await settle();
  f.facts.privacyMode = 'private'; f.facts.dataScope = 'session_ephemeral';
  f.coordinator.refreshDeferred(); await f.advance(96);
  const results = f.publications.at(-1).searchSuggestions;
  assert.equal(results[0].refId, 'private-aira');
  assert.ok(!results.some(s => s.source === 'history' || s.source === 'search_history' || s.source === 'suggestions'));
  await f.advance(1000); assert.equal(f.requests.length, 1);
});

test('bookmark index construction yields and never blocks the initial local result', async () => {
  const nodes = Array.from({ length: 450 }, (_, id) => bookmark(String(id), `Aira ${id}`, `https://entry${id}.invalid`));
  const f = bookmarkFixture(nodes);
  const results = f.service.buildSuggestions('aira', 'regular', 2);
  assert.equal(results.length, 2);
  assert.ok(f.timers.size > 0, 'index work is scheduled after the immediate fallback');
  const pending = f.service.ensureLoaded('regular');
  await f.advance(0); assert.equal(await pending, true);
  assert.equal(f.service.buildSuggestions('aira', 'regular', 2).length, 2);
});

function matchingSuggestions(count, source = 'bookmarks') {
  return Array.from({ length: count }, (_, id) => ({ ...suggestion(`${source}-${id}`, source), title: `技术文档 ${id}`, score: 600 }));
}
function matchingTab(id, title, url, lastActiveAt = Date.now()) {
  return { id, title, url, pendingUrl: '', lastGoodTitle: title, lastGoodUrl: url, lastActiveAt, isHome: false,
    profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' };
}
const regularResults = f => f.publications.at(-1).searchSuggestions.filter(s => s.source !== 'bookmark_search');

test('5000-bookmark corpus fills eight results and exposes scoped full bookmark search', () => {
  const b = bookmarkFixture(Array.from({ length: 5000 }, (_, id) => bookmark(String(id), `技术文档 ${id}`, `https://fixture${id}.test/doc`)));
  const f = fixture({ query: '技术文档', history: [], searchHistory: [],
    buildBookmarks: (query, scope, limit) => b.service.buildSuggestions(query, scope, limit) });
  f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test');
  assert.equal(regularResults(f).length, 8);
  assert.ok(regularResults(f).every(s => s.source === 'bookmarks'));
  const action = f.publications.at(-1).searchSuggestions.find(s => s.source === 'bookmark_search');
  assert.ok(action, 'more than eight matches need a full-results action');
  const route = new URL(action.target);
  assert.equal(route.protocol, 'aira:'); assert.equal(route.hostname, 'system');
  assert.equal(route.pathname, '/bookmarks');
  assert.equal(route.searchParams.get('q'), '技术文档');
  assert.equal(route.searchParams.get('scope'), 'regular');
  f.coordinator.openSuggestion(action); assert.equal(f.opened[0], action.target);
});

test('elastic allocation uses six local plus two terms, borrowing every unused slot in either direction', async () => {
  for (const [localCount, termCount, expectedLocal, expectedTerms] of [[12, 12, 6, 2], [12, 1, 7, 1],
    [12, 0, 8, 0], [1, 12, 1, 7], [0, 12, 0, 8], [2, 1, 2, 1]]) {
    const f = fixture({ query: '技术文档', history: [], searchHistory: matchingSuggestions(termCount, 'search_history'),
      buildBookmarks: (query, scope, limit) => matchingSuggestions(localCount).slice(0, limit) });
    f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test');
    const results = regularResults(f);
    assert.equal(results.filter(s => s.source === 'bookmarks').length, expectedLocal, `${localCount}/${termCount}: local`);
    assert.equal(results.filter(s => s.source === 'search_history').length, expectedTerms, `${localCount}/${termCount}: terms`);
  }
});

test('exact local matches outrank weaker sources and history signals break matching-quality ties', () => {
  const f = fixture({ query: '技术文档', searchHistory: [],
    tabs: [matchingTab('weak-tab', '其他技术文档参考', 'https://weak-tab.invalid')],
    buildBookmarks: () => [{ ...suggestion('exact-bookmark'), title: '技术文档', score: 800 }],
    history: [{ ...suggestion('history-prefix', 'history'), title: '技术文档 最新访问', score: 688, rankingBoost: 88 }] });
  f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test');
  assert.deepEqual(Array.from(regularResults(f), s => s.refId), ['exact-bookmark', 'history-prefix', 'weak-tab']);
  const g = fixture({ query: '技术文档', searchHistory: [],
    buildBookmarks: () => [{ ...suggestion('prefix-bookmark'), title: '技术文档 收藏', score: 600 }],
    history: [{ ...suggestion('exact-history', 'history'), title: '技术文档', score: 888, rankingBoost: 88 }] });
  g.facts.preferences.remoteEnabled = false; g.coordinator.beginSearchSession('test');
  assert.equal(regularResults(g)[0].refId, 'exact-history');
});

test('late remote results fill reserved slots without evicting visible local results or rescanning bookmarks', async () => {
  const f = fixture({ query: '技术文档', history: [], searchHistory: [],
    buildBookmarks: (query, scope, limit) => matchingSuggestions(12).slice(0, limit) });
  f.coordinator.beginSearchSession('test');
  const before = regularResults(f).map(s => s.id);
  assert.equal(before.length, 6); const scans = f.calls.bookmarks;
  await f.advance(96); f.requests[0].resolve(['技术文档 介绍', '技术文档 模板', '技术文档 规范']); await settle();
  const after = regularResults(f);
  assert.deepEqual(after.slice(0, 6).map(s => s.id), before);
  assert.equal(after.length, 8); assert.equal(after.filter(s => s.source === 'suggestions').length, 2);
  assert.equal(f.calls.bookmarks, scans);
});

test('empty remote response releases reserved slots to bookmarks', async () => {
  const f = fixture({ query: '技术文档', history: [], searchHistory: [],
    buildBookmarks: (query, scope, limit) => matchingSuggestions(12).slice(0, limit) });
  f.coordinator.beginSearchSession('test'); assert.equal(regularResults(f).length, 6);
  await f.advance(96); f.requests[0].resolve([]); await settle();
  assert.equal(regularResults(f).length, 8);
});

test('cross-source duplicates retain a switch-tab action and do not leave holes in the eight results', () => {
  const books = matchingSuggestions(16);
  const duplicates = books.slice(0, 6).map((b, i) => matchingTab(`tab-${i}`, b.title, b.target));
  const f = fixture({ query: '技术文档', tabs: duplicates, searchHistory: [], history: [],
    buildBookmarks: (query, scope, limit) => books.slice(0, limit) });
  f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test');
  const results = regularResults(f);
  assert.equal(results.length, 8); assert.equal(new Set(results.map(s => s.target)).size, 8);
  assert.equal(results.filter(s => s.source === 'tabs').length, 6);
});

test('full bookmark search action preserves private scope and encodes query delimiters', () => {
  const query = '技术文档 &scope=regular#片段';
  const f = fixture({ query, history: [], searchHistory: [],
    buildBookmarks: (q, scope, limit) => matchingSuggestions(16).slice(0, limit) });
  f.facts.privacyMode = 'private'; f.facts.dataScope = 'session_ephemeral'; f.coordinator.beginSearchSession('test');
  const action = f.publications.at(-1).searchSuggestions.find(s => s.source === 'bookmark_search'); assert.ok(action);
  const route = new URL(action.target);
  assert.equal(route.searchParams.get('q'), query); assert.equal(route.searchParams.get('scope'), 'private');
  assert.equal(route.hash, '');
});

test('full bookmark search stays visible and keyboard selectable on large screens', () => {
  const env = environment();
  const model = env.load('core/browser/BrowserLargeScreenOmniboxSearchViewModel.ets');
  const action = { id: 'more-bookmarks', source: 'bookmark_search', title: 'View all matching bookmarks',
    target: 'aira://system/bookmarks?q=docs&scope=regular' };
  const input = { editing: true, inputFocused: true, surfaceWidthVp: 600, suggestions: [action],
    externalAppSearchPreferences: { enabled: false, selectedTargetIds: [], targetOrder: [], updatedAt: 0 } };
  const presentation = new model.BrowserLargeScreenOmniboxSearchViewModel().resolve(input);
  assert.equal(presentation.searchSuggestions.length, 1);
  const key = model.omniboxSuggestionSelectionKey(action);
  assert.equal(model.moveOmniboxSuggestionSelection([action], '', 'down'), key);
  assert.equal(model.retainOmniboxSuggestionSelection([action], key), key);
});

test('history retrieval uses shared prefix quality before truncating candidates', () => {
  const env = environment();
  const { HistoryOmniboxIndex } = env.load('services/search/HistoryOmniboxIndex.ets');
  const index = new HistoryOmniboxIndex(), now = Date.now();
  const entries = Array.from({ length: 16 }, (_, id) => ({ id: `title-${id}`, title: `docs reference ${id}`,
    url: `https://old-${id}.invalid`, host: `old-${id}.invalid`, lastVisitAt: now - 365 * 86400000, visitCount: 0, typedCount: 0 }));
  entries.push({ id: 'frequent-url-prefix', title: 'Latest', url: 'https://docs.example.test/current',
    host: 'example.test', lastVisitAt: now, visitCount: 1000, typedCount: 100 });
  index.replace(entries, now);
  const matches = index.match('docs', 16, now);
  assert.equal(matches[0].entry.id, 'frequent-url-prefix');
  assert.ok(matches[0].rankingBoost > matches[1].rankingBoost);
});

test('search history and engine suggestions both get a useful slot without duplicate terms', async () => {
  const recent = matchingSuggestions(12, 'search_history'); recent[0].target = '技术文档 模板';
  const f = fixture({ query: '技术文档', history: [], searchHistory: recent,
    buildBookmarks: (query, scope, limit) => matchingSuggestions(12).slice(0, limit) });
  f.coordinator.beginSearchSession('test'); await f.advance(96);
  f.requests[0].resolve(['技术文档 模板', '技术文档 规范', '技术文档 介绍']); await settle();
  const results = regularResults(f);
  assert.equal(results.filter(s => s.source === 'bookmarks').length, 6);
  assert.equal(results.filter(s => s.source === 'search_history').length, 1);
  assert.equal(results.filter(s => s.source === 'suggestions').length, 1);
  assert.equal(new Set(results.map(s => s.target)).size, results.length);
});

test('failed remote request releases reserved slots without rerunning local matching', async () => {
  const f = fixture({ query: '技术文档', history: [], searchHistory: [],
    buildBookmarks: (query, scope, limit) => matchingSuggestions(12).slice(0, limit) });
  f.coordinator.beginSearchSession('test'); const scans = f.calls.bookmarks;
  await f.advance(96); f.requests[0].reject(new Error('synthetic timeout')); await settle();
  assert.equal(regularResults(f).length, 8); assert.equal(f.calls.bookmarks, scans);
});

test('full-results handoff preserves omnibox matching for whitespace and normalized URLs', () => {
  const nodes = Array.from({ length: 20 }, (_, id) => bookmark(String(id), `技术文档 ${id}`, `https://docs.example.test?i=${id}`));
  const b = bookmarkFixture(nodes);
  const { filterBookmarkSearchCandidates } = b.load('data/repositories/BookmarkRepositoryCore.ets');
  for (const query of ['技术 文档', 'https://www.docs.example.test/']) {
    const f = fixture({ query, history: [], searchHistory: [],
      buildBookmarks: (q, scope, limit) => b.service.buildSuggestions(q, scope, limit) });
    f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test');
    const action = f.publications.at(-1).searchSuggestions.find(s => s.source === 'bookmark_search'); assert.ok(action);
    const route = new URL(action.target);
    assert.equal(filterBookmarkSearchCandidates(nodes, route.searchParams.get('q'), 100).length, 20,
      `full search must retain the matching bookmarks for ${query}`);
  }
});

test('phone native-bookmark handoff forwards the keyword and keeps the current authorized scope', () => {
  const env = environment();
  const native = env.load('core/browser/BrowserNativeTabSceneService.ets').browserNativeTabSceneService;
  const filename = path.join(root, 'core/browser/BrowserShellRouteCoordinator.ets');
  const source = ts.createSourceFile(filename + '.ts', fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
  const owner = source.statements.find(node => node.name?.text === 'BrowserShellRouteCoordinator');
  const names = ['reconcilePhoneNativeTabHandoff', 'buildPhoneNativeTabRouteRequest'];
  const members = names.map(name => owner.members.find(node => node.name?.text === name).getText(source)).join('\n');
  const compiled = ts.transpileModule(`export class Subject { ${members} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  const output = { exports: {} };
  vm.runInNewContext(compiled.outputText, { module: output, exports: output.exports,
    browserNativeTabSceneService: native, BOOKMARK_MANAGER_ROUTE: 'pages/BookmarkManagerPage',
    resolveAppResourceText: () => 'message', $r: name => name });
  const subject = new output.exports.Subject(), requests = [];
  subject.phoneNativeTabHandoffKey = '';
  subject.boundaryNavigationService = { buildRouteParams: (dataScope, privacyMode) => ({ dataScope, privacyMode }) };
  subject.bookmarkScopeService = { buildRouteParams: (dataScope, privacyMode) => ({ dataScope, privacyMode,
    boundarySource: 'private_session', bookmarkScope: privacyMode === 'private' ? 'private' : 'regular' }) };
  subject.pushRoute = (url, params) => requests.push({ url, params });
  const tab = matchingTab('native-tab', 'Bookmarks', native.buildBookmarkRoute({ folderId: '', query: '技术 文档', scope: 'regular' }));
  tab.privacyMode = 'private'; tab.dataScope = 'session_ephemeral';
  subject.reconcilePhoneNativeTabHandoff('phone', [tab], tab.id, false);
  assert.equal(requests[0].params.query, '技术 文档');
  assert.equal(requests[0].params.bookmarkScope, 'private', 'route query cannot change the current privacy authority');
});

test('phone bookmark search initializes from the routed keyword once and survives data reloads', () => {
  const env = environment();
  const { BookmarkManagerSearchViewModel } = env.load('core/bookmarks/BookmarkManagerSearchViewModel.ets');
  const { filterBookmarkSearchCandidates } = env.load('data/repositories/BookmarkRepositoryCore.ets');
  const nodes = Array.from({ length: 20 }, (_, id) => bookmark(String(id), `技术文档 ${id}`, `https://docs${id}.test`));
  const feature = { searchBookmarks: (query, limit) => filterBookmarkSearchCandidates(nodes, query, limit) };
  const model = new BookmarkManagerSearchViewModel(feature);
  const initial = model.initializeRouteQuery('技术 文档');
  assert.equal(initial.state.isSearchMode, true); assert.equal(initial.state.query, '技术 文档');
  assert.equal(initial.nodes.length, 20);
  assert.equal(model.setCurrentFolderNodes([]).nodes.length, 20, 'folder reload must preserve routed global search');
  model.setQuery('docs1.test');
  assert.equal(model.initializeRouteQuery('技术 文档').state.query, 'docs1.test', 'route reappearance must preserve user edits');
  const page = fs.readFileSync(path.join(root, 'app/pages/BookmarkManagerPage.ets'), 'utf8');
  assert.match(page, /initializeRouteQuery\(params\?\.query\)/, 'phone shell must forward the route query');
});

function coldBookmarkFixture(nodes) {
  const b = bookmarkFixture([]), gate = deferred();
  let ready = false, initializations = 0;
  b.repo.isInitialized = () => ready;
  b.repo.initialize = () => {
    initializations++;
    return gate.promise.then(() => {
      b.repo.suggestionCandidates = nodes;
      b.repo.bookmarkChangeGeneration++;
      ready = true;
    });
  };
  return { ...b, gate, initializations: () => initializations };
}

test('cold bookmark index waits for persisted records and never treats an unloaded repository as empty', async () => {
  const b = coldBookmarkFixture([bookmark('cold', '冷启动书签', 'https://cold.test')]);
  assert.deepEqual(plain(b.service.buildSuggestions('冷启动', 'regular')), []);
  const loading = b.service.ensureLoaded('regular'); await settle();
  assert.equal(b.initializations(), 1, 'first search must initiate persisted repository loading');
  b.gate.resolve(); await settle(); await b.advance(0);
  assert.equal(await loading, true);
  assert.equal(b.service.buildSuggestions('冷启动', 'regular')[0].refId, 'cold');
  assert.equal(await b.service.ensureLoaded('regular'), false, 'subsequent queries reuse the index');
  assert.equal(b.initializations(), 1);
});

test('cold search automatically publishes bookmarks after load without opening the bookmark page or changing input', async () => {
  const b = coldBookmarkFixture(Array.from({ length: 5000 }, (_, id) => bookmark(String(id), `冷启动技术文档 ${id}`, `https://cold${id}.test`)));
  const f = fixture({ query: '冷启动技术文档', history: [], searchHistory: [], bookmarkService: b.service });
  f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test'); await settle();
  assert.equal(regularResults(f).length, 0); assert.equal(b.initializations(), 1);
  b.gate.resolve(); await settle(); await b.advance(0); await settle();
  assert.equal(regularResults(f).length, 8, 'the current search must hydrate itself when bookmarks become ready');
  assert.ok(regularResults(f).every(s => s.source === 'bookmarks'));
  assert.equal(f.facts.query, '冷启动技术文档');
  const enumerations = b.enumerations();
  f.facts.query = '技术文档'; f.coordinator.refreshDeferred(); await f.advance(0);
  assert.equal(regularResults(f).length, 8); assert.equal(b.enumerations(), enumerations);
  assert.equal(b.initializations(), 1);
});

test('startup prewarm, empty search and disabled bookmarks never initialize a cold repository', async () => {
  for (const mode of ['prewarm', 'empty', 'disabled']) {
    const b = coldBookmarkFixture([bookmark('cold', '冷启动书签', 'https://cold.test')]);
    const f = fixture({ query: mode === 'empty' ? '' : '冷启动', history: [], searchHistory: [], bookmarkService: b.service });
    f.facts.preferences.remoteEnabled = false; f.facts.preferences.browsingHistoryEnabled = false;
    if (mode === 'prewarm') {
      f.coordinator.prewarm(); await f.advance(1000);
    } else {
      if (mode === 'disabled') f.facts.preferences.bookmarksEnabled = false;
      f.coordinator.beginSearchSession('test'); await f.advance(1000);
    }
    await b.advance(1000);
    assert.equal(b.initializations(), 0, mode);
    assert.equal(b.enumerations(), 0, `${mode}: cold seed candidates must not be enumerated/indexed`);
  }
});

test('concurrent cold requests and privacy scopes share one repository initialization', async () => {
  const b = coldBookmarkFixture([bookmark('regular', '共享加载书签', 'https://regular.test'),
    bookmark('private', '共享加载书签', 'https://private.test', 'private')]);
  const requests = [b.service.ensureLoaded('regular'), b.service.ensureLoaded('regular'), b.service.ensureLoaded('private')];
  await settle(); assert.equal(b.initializations(), 1);
  b.gate.resolve(); await settle(); await b.advance(0); await Promise.all(requests);
  assert.equal(b.service.buildSuggestions('共享', 'regular')[0].refId, 'regular');
  assert.equal(b.service.buildSuggestions('共享', 'private')[0].refId, 'private');
  assert.equal(b.enumerations(), 2, 'one candidate enumeration/build for each scope');
});

test('cold completion hydrates only the latest query and cannot publish after session close or privacy change', async () => {
  for (const mode of ['query', 'close', 'private', 'disabled']) {
    const b = coldBookmarkFixture([bookmark('first', '第一关键词', 'https://first.test'),
      bookmark('latest', '最新关键词', 'https://latest.test'), bookmark('secret', '最新关键词', 'https://secret.test', 'private')]);
    const f = fixture({ query: '第一', history: [], searchHistory: [], bookmarkService: b.service });
    f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test'); await settle();
    if (mode === 'close') f.coordinator.reset();
    else if (mode === 'query') { f.facts.query = '最新'; f.coordinator.refreshDeferred(); await f.advance(0); }
    else if (mode === 'private') { f.facts.privacyMode = 'private'; f.facts.dataScope = 'session_ephemeral'; }
    else f.facts.preferences.bookmarksEnabled = false;
    const publications = f.publications.length;
    b.gate.resolve(); await settle(); await b.advance(0); await settle();
    if (mode === 'query') assert.equal(regularResults(f)[0].refId, 'latest');
    else assert.equal(f.publications.length, publications, mode);
    assert.equal(b.initializations(), 1);
  }
});

test('failed cold initialization remains retryable and does not cache an empty index', async () => {
  const b = coldBookmarkFixture([bookmark('retry', '重试书签', 'https://retry.test')]);
  const first = b.service.ensureLoaded('regular');
  const rejection = assert.rejects(first, /synthetic cold read/);
  b.gate.reject(new Error('synthetic cold read')); await rejection; await settle();
  const gate = deferred();
  b.repo.initialize = () => gate.promise.then(() => {
    b.repo.suggestionCandidates = [bookmark('retry', '重试书签', 'https://retry.test')];
    b.repo.bookmarkChangeGeneration++; b.repo.isInitialized = () => true;
  });
  const retry = b.service.ensureLoaded('regular'); gate.resolve(); await settle(); await b.advance(0);
  assert.equal(await retry, true); assert.equal(b.service.buildSuggestions('重试', 'regular')[0].refId, 'retry');
});

test('native cold search reads persisted bookmarks even when manager initialization cannot finish', async () => {
  const b = coldBookmarkFixture([]);
  const StoreService = b.load('services/search/BookmarkOmniboxSuggestionService.ets').BookmarkOmniboxSuggestionService;
  let reads = 0;
  const store = {
    readRevision: async () => '1', load: async () => undefined,
    readSource: async () => { reads++; return { revision: '1', records: [{ id: 'disk', title: '磁盘技术文档', url: 'https://disk.test' }] }; },
    save: async () => true
  };
  const service = new StoreService(b.repo, store);
  const f = fixture({ query: '磁盘技术文档', history: [], searchHistory: [], bookmarkService: service });
  f.facts.preferences.remoteEnabled = false; f.coordinator.beginSearchSession('test'); await settle();
  assert.equal(b.initializations(), 0, 'search must not depend on full manager initialization');
  await b.advance(0); await settle();
  assert.equal(reads, 1);
  assert.equal(regularResults(f)[0]?.refId, 'disk', 'cold input must publish database bookmarks without opening manager');
});

function storeBackedFixture(nodes, store) {
  const b = bookmarkFixture(nodes);
  const StoreService = b.load('services/search/BookmarkOmniboxSuggestionService.ets').BookmarkOmniboxSuggestionService;
  return { ...b, service: new StoreService(b.repo, store) };
}

test('repository cache churn never cancels or discards a persisted bookmark index', async () => {
  const churn = { revision: '7', records: [{ id: 'churned', title: '同步期间书签', url: 'https://churn.test' }] };
  let bumps = 0;
  const store = {
    readRevision: async () => { bumps++; return churn.revision; },
    load: async () => undefined,
    readSource: async () => { bumps++; return { revision: churn.revision, records: churn.records.slice() }; },
    save: async () => true
  };
  const b = storeBackedFixture([], store);
  const pending = b.service.ensureLoaded('regular');
  b.repo.bookmarkChangeGeneration += 3;
  await settle(); await b.advance(0);
  assert.equal(await pending, true, 'startup/sync cache churn must not cancel the persisted load');
  assert.equal(b.service.buildSuggestions('同步', 'regular')[0].refId, 'churned');
  b.repo.bookmarkChangeGeneration += 5;
  assert.equal(b.service.buildSuggestions('同步', 'regular')[0].refId, 'churned',
    'cache churn without a revision change must not blank the persisted index');
  assert.ok(bumps > 0);
});

test('launch prewarm restores the persisted snapshot before any search', async () => {
  const b = bookmarkFixture([]);
  const { BookmarkOmniboxIndex } = b.load('services/search/BookmarkOmniboxIndex.ets');
  const built = new BookmarkOmniboxIndex();
  const replacing = built.replaceRecordsYielding(
    [{ id: 'prewarmed', title: '预热书签', url: 'https://prewarm.test' }], () => false);
  await b.advance(0); assert.equal(await replacing, true);
  const exporting = built.exportChunksYielding();
  await b.advance(0);
  const chunks = await exporting;
  assert.ok(chunks.length > 0);
  const cold = coldBookmarkFixture([]);
  const StoreService = cold.load('services/search/BookmarkOmniboxSuggestionService.ets').BookmarkOmniboxSuggestionService;
  const store = {
    readRevision: async () => '3',
    load: async () => ({ revision: '3', chunks: chunks }),
    readSource: async () => { throw new Error('the restored snapshot must satisfy the prewarm load'); },
    save: async () => true
  };
  const service = new StoreService(cold.repo, store);
  const f = fixture({ query: '预热', history: [], searchHistory: [], bookmarkService: service });
  f.coordinator.prewarm(); await f.advance(48); await cold.advance(0); await settle();
  assert.equal(cold.initializations(), 0, 'prewarm restores the snapshot without initializing the repository');
  f.coordinator.beginSearchSession('test');
  assert.equal(regularResults(f)[0]?.refId, 'prewarmed', 'the first explicit search answers from the restored index');
});

test('an initialized repository still answers while the persisted index restores', async () => {
  const gate = deferred();
  const store = {
    readRevision: () => gate.promise.then(() => '9'),
    load: async () => undefined,
    readSource: async () => ({ revision: '9', records: [] }),
    save: async () => true
  };
  const b = storeBackedFixture([bookmark('memory', '内存书签', 'https://memory.test')], store);
  const loading = b.service.ensureLoaded('regular');
  assert.equal(b.service.buildSuggestions('内存', 'regular')[0]?.refId, 'memory',
    'a restoring index must not blank initialized repository results');
  gate.resolve(); await settle(); await b.advance(0); await loading;
});

test('a persisted index reloads when the database revision moves', async () => {
  const data = { revision: '1', records: [{ id: 'v1', title: '第一版书签', url: 'https://v1.test' }] };
  const store = {
    readRevision: async () => data.revision,
    load: async () => undefined,
    readSource: async () => ({ revision: data.revision, records: data.records.slice() }),
    save: async () => true
  };
  const b = storeBackedFixture([], store);
  const first = b.service.ensureLoaded('regular'); await settle(); await b.advance(0); assert.equal(await first, true);
  assert.equal(b.service.buildSuggestions('第一版', 'regular')[0].refId, 'v1');
  data.revision = '2';
  data.records = [{ id: 'v2', title: '第二版书签', url: 'https://v2.test' }];
  b.repo.bookmarkChangeGeneration++;
  assert.equal(b.service.buildSuggestions('第一版', 'regular')[0]?.refId, 'v1',
    'the carried-over index answers until ensureLoaded revalidates the revision');
  const reload = b.service.ensureLoaded('regular'); await settle(); await b.advance(0); assert.equal(await reload, true);
  assert.equal(b.service.buildSuggestions('第二版', 'regular')[0].refId, 'v2',
    'a moved revision must replace the stale index');
});

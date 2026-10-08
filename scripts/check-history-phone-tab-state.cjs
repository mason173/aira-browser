#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
global.ListScroller = class {
  scrollToIndex() {}
  closeAllSwipeActions() {}
};
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();

function load(relative) {
  if (cache.has(relative)) return cache.get(relative);
  const filename = path.join(root, relative);
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename, reportDiagnostics: true
  });
  assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
  const module = { exports: {} };
  const context = {
    module, exports: module.exports, require: name => {
      if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
      return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
    },
    // ArkTS resource references are resolved by the ArkUI runtime; the harness
    // only needs the resource identity, never a localized value.
    $r: (value) => ({ id: -1, params: [], value }),
    ListScroller: class {
      scrollToIndex() {}
      closeAllSwipeActions() {}
    }
  };
  vm.runInNewContext(result.outputText, context, { filename });
  cache.set(relative, module.exports);
  return module.exports;
}

const { HistoryManagerScreenController } = load('features/history/HistoryManagerScreenController.ets');
const { HistorySitePageController } = load('features/history/HistorySitePageController.ets');
const { HistoryViewModel } = load('features/history/HistoryViewModel.ets');
const screen = fs.readFileSync(path.join(root, 'app/components/history/HistoryManagerScreen.ets'), 'utf8');
const timelineList = fs.readFileSync(path.join(root, 'app/components/history/HistoryTimelineList.ets'), 'utf8');
const siteList = fs.readFileSync(path.join(root, 'app/components/history/HistorySiteList.ets'), 'utf8');

function deferred() {
  let resolve; let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function fixture() {
  const reads = [];
  const state = { revision: 4, pending: false };
  const feature = {
    getDataRevision: () => state.revision,
    isMutationPending: () => state.pending,
    listVisitsForManagement: () => [{
      id: 'cached', title: 'Cached', url: 'https://cached.invalid/', host: 'cached.invalid',
      visitedAt: 9, dayBucketLabel: 'synthetic', visitCount: 1
    }],
    refreshPageForManagement: offset => request('timeline', '', offset),
    refreshSearchPageForManagement: (query, offset) => request('search', query, offset),
    refreshSitePageForManagement: (query, offset) => request('sites', query, offset)
  };
  function request(kind, query, offset) {
    const item = { kind, query, offset, ...deferred() };
    reads.push(item);
    return item.promise;
  }
  const controller = new HistoryManagerScreenController(feature);
  controller.setManagementBoundary({ dataScope: 'profile_persistent', privacyMode: 'regular' });
  return { feature, controller, reads, state, sites: new HistorySitePageController(feature) };
}

test('timeline first page queries instead of trusting the untracked visit cache', async () => {
  const f = fixture();
  const published = [];
  f.controller.loadTimelineFirstPage('', 2, visits => published.push(visits.map(visit => visit.id)));
  assert.equal(f.reads.at(-1).kind, 'timeline');
  assert.equal(f.reads.at(-1).offset, 0);
  f.reads.at(-1).resolve([{ id: 'fresh', url: 'https://fresh.invalid', visitedAt: 8 }]);
  await f.reads.at(-1).promise;
  await Promise.resolve();
  assert.deepEqual(published, [['fresh']]);
  assert.equal(f.controller.canReuseTimeline(''), true);
});

test('site first page blocks pagination and resumes from the committed offset', async () => {
  const f = fixture();
  const published = [];
  f.sites.loadFirstPage('', 2, {}, (sites, append) => published.push([append, sites.length]));
  const first = f.reads.at(-1);
  f.sites.loadNextPage(2, {}, () => published.push('late'));
  assert.equal(f.reads.length, 1);
  first.resolve([
    { host: 'a.invalid', key: 'a', latestVisitedAt: 2, visitCount: 1, uniqueUrlCount: 1 },
    { host: 'b.invalid', key: 'b', latestVisitedAt: 1, visitCount: 1, uniqueUrlCount: 1 }
  ]);
  await first.promise;
  await Promise.resolve();
  f.sites.loadNextPage(2, {}, (sites, append) => published.push([append, sites.length]));
  assert.equal(f.reads.at(-1).offset, 2);
  assert.deepEqual(published, [[false, 2]]);
});

test('timeline presentation no longer rebuilds site aggregates', () => {
  const model = new HistoryViewModel();
  const state = model.buildTimelineViewState([
    { id: 'a', title: 'A', url: 'https://a.invalid/1', host: 'a.invalid', visitedAt: 2, dayBucketLabel: 'd' },
    { id: 'b', title: 'B', url: 'https://a.invalid/1', host: 'a.invalid', visitedAt: 1, dayBucketLabel: 'd' }
  ], '');
  assert.equal(state.visits.length, 1);
  assert.equal(state.visits[0].duplicateCount, 2);
  assert.equal(state.sites.length, 0);
});

test('a site request deferred during deletion resumes when the mutation finishes', async () => {
  const f = fixture();
  const published = [];
  f.sites.beginMutation();
  f.sites.loadFirstPage('', 2, {}, (sites, append) => published.push([append, sites.length]));
  assert.equal(f.reads.length, 0);
  f.sites.finishMutation();
  assert.equal(f.reads.at(-1).kind, 'sites');
  f.reads.at(-1).resolve([{ host: 'a.invalid', key: 'a', latestVisitedAt: 1 }]);
  await f.reads.at(-1).promise;
  await Promise.resolve();
  assert.deepEqual(published, [[false, 1]]);
});

test('phone screen contracts keep modes, menus, and deletions isolated', () => {
  assert.match(screen, /enabled: canEdit/);
  assert.match(screen, /!this\.isViewModeEmpty\(this\.viewMode\)/);
  assert.doesNotMatch(screen, /enabled: hasVisits|hasLoadedTimelineVisits\(\)|siteReloadSequence/);
  assert.match(screen, /buildTimelineViewState\(this\.rawVisits/);
  assert.doesNotMatch(screen, /historySiteListDataSource\.replaceSites\(state\.sites\)/);
  assert.match(screen, /this\.sitePageController\.beginMutation\(\)/);
  assert.match(screen, /this\.sitePageController\.finishMutation\(\)/);
  assert.match(screen, /if \(allowReuse && this\.controller\.canReuseTimeline\(this\.searchQuery\)\)/);
  assert.match(screen, /if \(allowReuse && this\.sitePageController\.canReuse\(this\.searchQuery\)\)/);
  assert.match(screen, /if \(this\.viewMode !== 'timeline' \|\| !this\.isActive/);
  assert.match(screen, /if \(this\.viewMode !== 'sites' \|\| !this\.isActive/);
  assert.match(screen, /if \(!\(offset > 0\)\)/);
  assert.match(screen, /prefetchInactiveHistoryMode\(/);
  assert.match(screen, /Visibility\.None/);
  assert.doesNotMatch(screen, /Visibility\.Hidden/);
  assert.match(screen, /icons: this\.timelineIconStates/);
  assert.match(screen, /icons: this\.siteIconStates/);
  assert.doesNotMatch(screen, /icons: this\.iconStates/);
  assert.match(screen, /selectedVisitIds\.length === 0/);
  assert.match(timelineList, /freezeWhenInactive: true/);
  assert.match(siteList, /freezeWhenInactive: true/);
  assert.match(screen, /allowReuse && this\.isSiteLoading/);
  assert.match(screen, /allowReuse && this\.isTimelineLoading/);
});

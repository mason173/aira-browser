#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
const resource = (id) => id;

function evaluate(source, globals = {}, requireModule = () => ({})) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText, { module, exports: module.exports, require: requireModule, $r: resource, setTimeout, ...globals });
  return module.exports;
}

function load(relative) {
  const filename = path.resolve(root, relative + '.ets');
  if (cache.has(filename)) return cache.get(filename);
  if (filename.endsWith('/AppResourceText.ets')) return { resolveAppResourceText: (text) => text };
  if (filename.endsWith('/BookmarkFolderSelectionViewModel.ets')) {
    return { BookmarkFolderSelectionViewModel: class {} };
  }
  const exports = evaluate(fs.readFileSync(filename, 'utf8'), {}, (id) => {
    assert.ok(id.startsWith('.'), `Unexpected platform dependency: ${id}`);
    return load(path.relative(root, path.resolve(path.dirname(filename), id)));
  });
  cache.set(filename, exports);
  return exports;
}

const core = load('data/repositories/BookmarkRepositoryCore');
const { BrowserDesktopBookmarkBarViewModel } = load('core/browser/BrowserDesktopBookmarkBarViewModel');
const { BrowserDesktopBookmarkBarDragCoordinator, planDesktopBookmarkBarReorder } =
  load('core/browser/BrowserDesktopBookmarkBarDragCoordinator');
const { BrowserDesktopBookmarkBarActionCoordinator } = load('core/browser/BrowserDesktopBookmarkBarActionCoordinator');
const { BookmarkMutationService } = load('services/bookmarks/BookmarkMutationService');
const regularRoot = core.BOOKMARK_TOOLBAR_ROOT_ID;
const privateRoot = core.PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID;

function node(id, index, type = 'bookmark', scope = 'regular', parentId) {
  return {
    id, type, scope, parentId: parentId ?? (scope === 'private' ? privateRoot : regularRoot),
    title: id, url: type === 'bookmark' ? `https://${id}.example` : undefined,
    position: index, createdAt: 1, updatedAt: 1,
    sync: { state: 'synced', source: 'local', lastModifiedAt: 1, deviceId: 'fixture' }
  };
}

const repositorySource = fs.readFileSync(path.join(root, 'data/repositories/BrowserRepositories.ets'), 'utf8');
const reorderStart = repositorySource.indexOf('  async reorderChildren(command:');
const reorderEnd = repositorySource.indexOf('\n  }', reorderStart) + 4;
const { PersistentReorder } = evaluate(`export class PersistentReorder {
  ${repositorySource.slice(reorderStart, reorderEnd)}
}`, { markBookmarkRepositioned: core.markBookmarkRepositioned });

async function fixture(nodes = [node('a', 0, 'folder'), node('b', 1), node('c', 2), node('d', 3, 'folder')]) {
  const repository = new core.InMemoryBookmarkRepository();
  const storage = { nodes: structuredClone(nodes), writes: 0, signals: 0, fail: false };
  const reload = async () => repository.replaceAllScopes(
    { roots: [], nodes: storage.nodes.filter((item) => core.resolveBookmarkScope(item.scope) === 'regular') },
    { roots: [], nodes: storage.nodes.filter((item) => item.scope === 'private') }
  );
  await reload();
  repository.database = { async updateBookmarkPositions(updates) {
    if (storage.fail) throw new Error('disk failure');
    storage.writes += 1;
    storage.nodes = storage.nodes.map((item) => updates.find((update) => update.id === item.id) ?? item);
  } };
  repository.resolveParentScope = (id) => id === privateRoot ? 'private' : 'regular';
  repository.refresh = reload;
  repository.recordBookmarkActivity = () => {};
  repository.bumpBookmarkStatsVersion = () => { storage.signals += 1; };
  repository.reorderChildren = PersistentReorder.prototype.reorderChildren;
  const model = new BrowserDesktopBookmarkBarViewModel(repository);
  const drag = new BrowserDesktopBookmarkBarDragCoordinator(model);
  const toasts = [];
  const sync = [];
  BookmarkMutationService.configureDefaultSyncPendingMarker(async (changedAt) => { sync.push(changedAt); });
  const actions = new BrowserDesktopBookmarkBarActionCoordinator({ repository, preferencesRepository: {} }, {
    showToast: (text) => toasts.push(text)
  });
  return { repository, model, drag, actions, storage, toasts, sync, reload,
    snapshot: (width = 1200, scope = 'regular') => model.buildSnapshot(scope, width),
    ids: (scope = 'regular') => Array.from(repository.listChildren(scope === 'private' ? privateRoot : regularRoot, scope), (n) => n.id),
    async apply(action) { actions.handleReorder(action); await actions.reorderQueue; }
  };
}

test('folders and bookmarks reorder in both directions, persist, notify chrome and become sync pending', async () => {
  const f = await fixture();
  const before = f.snapshot();
  assert.equal(f.drag.begin(before, 'a'), true);
  assert.ok(f.drag.update(before, 1000), 'hover shows an insertion target');
  assert.equal(f.storage.writes, 0, 'hover never saves');
  const action = f.drag.finish(before, 1000);
  await f.apply(action);
  assert.deepEqual(f.ids(), ['b', 'c', 'd', 'a']);
  assert.equal(f.storage.signals, 1);
  assert.equal(f.sync.length, 1);
  assert.ok(f.storage.nodes.every((n) => n.sync.state === 'pending_push'));
  await f.reload();
  assert.deepEqual(f.ids(), ['b', 'c', 'd', 'a']);
  assert.equal(f.drag.begin(f.snapshot(), 'c'), true);
  await f.apply(f.drag.finish(f.snapshot(), 0));
  assert.deepEqual(f.ids(), ['c', 'b', 'd', 'a']);
  assert.ok(f.storage.nodes.every((n) => n.parentId === regularRoot));
});

test('midpoints use each title width, and dropping on a gap does not lose overflow siblings', async () => {
  const f = await fixture([node('a', 0), { ...node('b', 1), title: 'A much longer bookmark title' }, node('c', 2), node('d', 3)]);
  const snapshot = f.snapshot(430);
  assert.equal(snapshot.visibleItems.length, 2);
  assert.equal(snapshot.overflowItems.length, 2);
  const firstLeft = 50;
  assert.equal(f.model.resolveDropTarget(snapshot, firstLeft + 41).anchorId, 'a');
  assert.equal(f.model.resolveDropTarget(snapshot, firstLeft + 43).anchorId, 'b');
  const trailing = f.model.resolveDropTarget(snapshot, 400);
  assert.equal(trailing.anchorId, 'c');
  assert.equal(trailing.placement, 'before');
  f.drag.begin(snapshot, 'a');
  await f.apply(f.drag.finish(snapshot, 400));
  assert.deepEqual(f.ids(), ['b', 'a', 'c', 'd']);
  assert.equal(f.model.resolveDropTarget(snapshot, NaN), undefined);
});

test('cancel, a drop back at the original position, and unrelated external drops never save', async () => {
  const f = await fixture();
  const snapshot = f.snapshot();
  assert.equal(f.drag.finish(snapshot, 1000), undefined);
  f.drag.begin(snapshot, 'a');
  assert.equal(f.drag.finish(snapshot, 135), undefined);
  f.drag.begin(snapshot, 'b');
  f.drag.update(snapshot, 0);
  f.drag.cancel();
  assert.equal(f.drag.finish(snapshot, 0), undefined);
  assert.equal(f.storage.writes, 0);
  assert.deepEqual(f.ids(), ['a', 'b', 'c', 'd']);
});

test('scope changes, deletion and moving a source to a different folder invalidate the drag', async () => {
  const f = await fixture();
  for (const alter of [
    (s) => ({ ...s, scope: 'private', rootId: privateRoot }),
    (s) => ({ ...s, allItems: s.allItems.filter((n) => n.id !== 'a') }),
    (s) => ({ ...s, allItems: s.allItems.map((n) => n.id === 'a' ? { ...n, parentId: 'other' } : n) }),
    (s) => ({ ...s, allItems: s.allItems.map((n) => n.id === 'a' ? { ...n, sync: { deletedAt: 2 } } : n) })
  ]) {
    const snapshot = f.snapshot();
    f.drag.begin(snapshot, 'a');
    assert.equal(f.drag.finish(alter(snapshot), 1000), undefined);
  }
  assert.equal(f.drag.begin(f.snapshot(), 'missing'), false);
  f.drag.begin(f.snapshot(), 'd');
  assert.equal(f.drag.finish(f.snapshot(280), 1000), undefined, 'a resize removing the source cancels its drag');
});

test('private reorders stay within their toolbar root and preserve folder descendants', async () => {
  const child = node('child', 0, 'bookmark', 'private', 'p');
  const f = await fixture([node('a', 0), node('p', 0, 'folder', 'private'), node('q', 1, 'bookmark', 'private'), child]);
  const snapshot = f.snapshot(1200, 'private');
  assert.equal(f.drag.begin(snapshot, 'p'), true);
  await f.apply(f.drag.finish(snapshot, 1000));
  assert.deepEqual(f.ids('private'), ['q', 'p']);
  assert.deepEqual(f.ids(), ['a']);
  assert.equal(f.storage.nodes.find((n) => n.id === 'child').parentId, 'p');
  await f.apply({ kind: 'reorder_node', scope: 'regular', nodeId: 'p', anchorId: 'a', placement: 'before' });
  assert.equal(f.storage.writes, 1, 'cross-scope payload cannot write');
});

test('drop commands rebase on current siblings and serialize writes without resurrecting deleted nodes', async () => {
  const f = await fixture();
  const first = { kind: 'reorder_node', scope: 'regular', nodeId: 'a', anchorId: 'd', placement: 'after' };
  const second = { ...first, nodeId: 'b', anchorId: 'a', placement: 'after' };
  f.actions.handleReorder(first);
  f.actions.handleReorder(second);
  await f.actions.reorderQueue;
  assert.deepEqual(f.ids(), ['c', 'd', 'a', 'b']);
  f.storage.nodes.push(node('new', 4));
  f.storage.nodes = f.storage.nodes.map((n) => n.id === 'd' ? { ...n, sync: { ...n.sync, deletedAt: 2 } } : n);
  await f.reload();
  await f.apply({ ...first, nodeId: 'new', anchorId: 'c', placement: 'before' });
  assert.deepEqual(f.ids(), ['new', 'c', 'a', 'b']);
  await f.apply(first);
  assert.equal(f.storage.writes, 3, 'a deleted anchor is ignored');
  assert.equal(f.storage.nodes.find((n) => n.id === 'd').sync.deletedAt, 2);
});

test('failed saving retains the committed order, reports failure, and allows the next drag', async () => {
  const f = await fixture();
  const action = { kind: 'reorder_node', scope: 'regular', nodeId: 'a', anchorId: 'd', placement: 'after' };
  f.storage.fail = true;
  await f.apply(action);
  assert.deepEqual(f.ids(), ['a', 'b', 'c', 'd']);
  assert.equal(f.toasts.length, 1);
  assert.equal(f.sync.length, 0);
  f.storage.fail = false;
  await f.apply(action);
  assert.deepEqual(f.ids(), ['b', 'c', 'd', 'a']);
});

test('legacy regular bookmarks without an explicit scope still reorder', async () => {
  const legacy = node('legacy', 0);
  delete legacy.scope;
  const f = await fixture([legacy, node('b', 1)]);
  f.drag.begin(f.snapshot(), 'legacy');
  await f.apply(f.drag.finish(f.snapshot(), 1000));
  assert.deepEqual(f.ids(), ['b', 'legacy']);
});

const barSource = fs.readFileSync(path.join(root, 'app/components/browser/BrowserLargeScreenBookmarkBar.ets'), 'utf8');
const entrySource = barSource.slice(barSource.indexOf('struct BrowserLargeScreenBookmarkBarEntry'),
  barSource.indexOf('export struct BrowserLargeScreenBookmarkBar'));
function entryMethod(name) {
  const start = entrySource.indexOf(`  private ${name}(`);
  const end = entrySource.indexOf('\n  }', start) + 4;
  return entrySource.slice(start, end).replace('private ', '');
}

test('bar event handlers translate window coordinates, dispatch once on drop, and cancel on Escape', async () => {
  const f = await fixture();
  const parentSource = barSource.slice(barSource.indexOf('export struct BrowserLargeScreenBookmarkBar'));
  const names = ['startBookmarkDrag', 'updateBookmarkDrag', 'dropBookmarkDrag', 'cancelBookmarkDrag', 'handleKeyEvent'];
  const methods = names.map((name) => {
    const start = parentSource.indexOf(`  private ${name}(`);
    return parentSource.slice(start, parentSource.indexOf('\n  }', start) + 4).replace('private ', '');
  }).join('\n');
  const { Bar } = evaluate(`export class Bar { ${methods} }`, {
    DragBehavior: { MOVE: 1 }, KeyType: { Down: 0 }, KeyCode: { KEYCODE_ESCAPE: 27 },
    DragResult: { DROP_ENABLED: 3, DROP_DISABLED: 4, DRAG_SUCCESSFUL: 0, DRAG_CANCELED: 2 }
  });
  let dispatches = 0;
  const bar = Object.assign(new Bar(), {
    snapshot: f.snapshot(), dragCoordinator: f.drag, barLeftVp: 220,
    onAction: (action) => { dispatches += 1; f.actions.handleReorder(action); }
  });
  const event = { getWindowX: () => 220, setResult(result) { this.result = result; } };
  assert.equal(bar.startBookmarkDrag(bar.snapshot.allItems[1]), true);
  bar.updateBookmarkDrag(event);
  assert.equal(bar.dropIndicatorLeftVp, 49);
  assert.equal(event.dragBehavior, 1);
  assert.equal(event.result, 3);
  bar.dropBookmarkDrag(event);
  await f.actions.reorderQueue;
  assert.deepEqual(f.ids(), ['b', 'a', 'c', 'd']);
  assert.equal(dispatches, 1);
  assert.equal(bar.draggingNodeId, '');
  assert.equal(bar.dropIndicatorLeftVp, -1);
  bar.dropBookmarkDrag(event);
  assert.equal(dispatches, 1, 'the native end/drop sequence cannot save twice');
  bar.snapshot = f.snapshot();
  bar.startBookmarkDrag(bar.snapshot.allItems[1]);
  assert.equal(bar.handleKeyEvent({ type: 0, keyCode: 27 }), true);
  assert.equal(f.drag.finish(bar.snapshot, 1000), undefined);
});

test('mouse and touch share native dragging, close the menu, and suppress the release click', () => {
  const click = entrySource.match(/\.onClick\(\(event: ClickEvent\): void => \{([\s\S]*?)\n    \}\)/)[1];
  const { Entry } = evaluate(`export class Entry { ${entryMethod('startDrag')} ${entryMethod('endDrag')}
    click(event: ClickEvent): void { ${click} }
  }`, {
    BOOKMARK_BAR_LONG_PRESS_CLICK_SUPPRESS_MS: 500,
    isBookmarkBarLongPressRelease: () => false,
    DragResult: { DRAG_CANCELED: 2 }
  });
  for (const source of ['mouse', 'touch']) {
    let opened = 0;
    let closed = 0;
    let ended = 0;
    const entry = Object.assign(new Entry(), { node: node('a', 0), onStartDrag: () => true,
      onEndDrag: () => { ended += 1; }, getUIContext: () => ({ getContextMenuController: () => ({ close: () => { closed += 1; } }) }),
      onOpenBookmark: () => { opened += 1; }, onOpenFolderMenu: () => { opened += 1; }
    });
    entry.startDrag({});
    entry.click({ source });
    entry.endDrag();
    entry.click({ source });
    assert.equal(opened, 0);
    assert.equal(closed, 1);
    assert.equal(ended, 1);
    entry.suppressClickUntilMs = 0;
    entry.click({ source });
    assert.equal(opened, 1);
  }
  assert.match(entrySource, /\.draggable\(true\)/);
  assert.match(entrySource, /\.onDragStart\(.*this\.startDrag\(event\)/);
  assert.match(entrySource, /\.onDragEnd\(.*this\.endDrag\(\)/);
  assert.match(entrySource, /bindContextMenuWithResponse/);
});

test('the reorder planner treats stale targets and already adjacent placements as no-ops', () => {
  const nodes = [node('a', 0), node('b', 1), node('c', 2)];
  for (const [source, target, placement] of [['a', 'a', 'after'], ['a', 'b', 'before'], ['b', 'a', 'after'], ['a', 'missing', 'before']]) {
    assert.equal(planDesktopBookmarkBarReorder(nodes, source, target, placement), undefined);
  }
});

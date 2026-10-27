'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const resource = id => ({ id });
function evaluate(relative, requireModule) {
  const module = { exports: {} };
  const source = fs.readFileSync(path.join(root, relative + '.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { module, exports: module.exports, require: requireModule, $r: resource, setTimeout });
  return module.exports;
}
const cache = new Map();
function load(relative) {
  const filename = path.resolve(root, relative);
  if (cache.has(filename)) return cache.get(filename);
  if (filename.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
  if (filename.endsWith('/BookmarkStatsVersionSignal')) return { BookmarkStatsVersionSignal: { bumpVersion() {} } };
  if (filename.endsWith('/BrowserPrivacyEffectPolicyService')) return { BrowserPrivacyEffectPolicyService: class { decide() { return { outcome: 'allow' }; } } };
  if (filename.endsWith('/BrowserBookmarkScopeService')) return { BrowserBookmarkScopeService: class { resolveScopeForBoundary() { return 'regular'; } } };
  if (filename.endsWith('/BrowserProfileBoundaryService')) return { BrowserProfileBoundaryService: class { buildBoundary() { return {}; } } };
  const realModules = ['BrowserRepositories', 'BookmarkRepositoryCore', 'NavigationSearchText', 'BookmarkMutationService', 'BookmarkAddDraft', 'UrlUtils', 'BrowserBookmarkActionCoordinator', 'HistoryBookmarkAddCoordinator'];
  if (!realModules.includes(path.basename(filename))) return {};
  const result = evaluate(path.relative(root, filename), id => {
    if (id === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
    return load(path.relative(root, path.resolve(path.dirname(filename), id)));
  });
  cache.set(filename, result);
  return result;
}
const { RdbBookmarkRepository } = load('data/repositories/BrowserRepositories');
const { BookmarkMutationService } = load('services/bookmarks/BookmarkMutationService');
const core = load('data/repositories/BookmarkRepositoryCore');
const { BrowserBookmarkActionCoordinator } = load('core/browser/BrowserBookmarkActionCoordinator');
const tick = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }
function fixture({ slowFullRead = false, slowSync = false, failSync = false, failWrite = false, start = true } = {}) {
  const fullRead = deferred(), sync = deferred();
  let rows = core.buildSeedBookmarkNodes(), fullReads = 0, commits = 0, syncStarted = 0;
  const database = {
    async upsertBookmarkNode(node) { if (failWrite) throw new Error('disk unavailable'); rows.push(node); commits += 1; },
    async listBookmarkNodes() { fullReads += 1; if (slowFullRead) await fullRead.promise; return rows.slice(); }
  };
  const repository = new RdbBookmarkRepository(database);
  repository.initializationPromise = Promise.resolve();
  repository.initialized = true;
  BookmarkMutationService.configureDefaultSyncPendingMarker(async () => { syncStarted += 1; if (slowSync) await sync.promise; if (failSync) throw new Error('sync metadata unavailable'); });
  const folders = [{ id: core.BOOKMARK_TOOLBAR_ROOT_ID, title: 'Bookmarks' }];
  const snapshots = [], toasts = [];
  let token;
  const coordinator = new BrowserBookmarkActionCoordinator({
    repository,
    folderPreparationCoordinator: {
      getCachedOptions: () => folders, getResponsiveOptions: () => folders, prepare: async () => folders, invalidate() {}
    },
    searchSuggestionCoordinator: { invalidate() {} },
    homeShortcutToggleService: { addIfMissing: async () => ({ added: true }) },
    transientSurfaceCoordinator: {
      present: () => { token = {}; return token; }, isCurrent: current => current === token,
      dismiss: () => { token = undefined; }, reset: () => { token = undefined; }
    }
  }, { applySnapshot: snapshot => snapshots.push(snapshot), showToast: message => toasts.push(message),
    presentPersistentWriteBlocked() {}, confirmRemove() {}, refreshHomeShortcuts() {} });
  if (start) {
  coordinator.startAdd({ source: 'current_page', title: 'Fast feedback', url: 'https://feedback.example/page', dataScope: 'regular', privacyMode: 'normal', enabled: true, homeShortcutScenarioId: 'page' });
  coordinator.handleFolderSelectionAction({ type: 'set_folder_picker', selected: true });
  coordinator.handleFolderSelectionAction({ type: 'select_folder', folderId: core.BOOKMARK_TOOLBAR_ROOT_ID });
  coordinator.handleFolderSelectionAction({ type: 'set_folder_picker', selected: false });
  coordinator.handleFolderSelectionAction({ type: 'confirm_add' });
  }
  return { coordinator, repository, toasts, folders, mutationService: new BookmarkMutationService(repository), commits: () => commits, fullReads: () => fullReads,
    syncStarted: () => syncStarted, release: () => { fullRead.resolve(); sync.resolve(); } };
}
test('after choosing a folder, a locally saved bookmark closes the form without rereading the entire bookmark database', async () => {
  const h = fixture({ slowFullRead: true }); await tick();
  const before = h.coordinator.getSnapshot(); const reads = h.fullReads();
  h.release(); await tick();
  assert.equal(h.commits(), 1, 'the bookmark is already persisted');
  assert.equal(before.active, false, 'a durable save must immediately dismiss the editing form');
  assert.equal(reads, 0, 'single-bookmark creation must patch the existing cache instead of a full database reload');
});
test('after choosing a folder, slow sync preparation does not delay local save feedback', async () => {
  const h = fixture({ slowSync: true }); await tick();
  const before = h.coordinator.getSnapshot(); const hadFeedback = h.toasts.length > 0;
  h.release(); await tick();
  assert.equal(h.commits(), 1); assert.equal(h.syncStarted(), 1);
  assert.equal(before.active, false, 'sync preparation must not keep an already saved bookmark form open');
  assert.equal(hadFeedback, true, 'show local save confirmation before sync preparation finishes');
});

test('a real local write failure retains the editing form and does not start sync', async () => {
  const h = fixture({ failWrite: true }); await tick();
  assert.equal(h.commits(), 0); assert.equal(h.syncStarted(), 0);
  assert.equal(h.coordinator.getSnapshot().active, true);
  assert.equal(h.coordinator.getSnapshot().draft.saving, false);
  assert.equal(h.coordinator.getSnapshot().draft.saveError.id, 'app.string.bottom_panel_bookmark_add_failed');
});
test('a later sync preparation failure never reports a durable bookmark as unsaved', async () => {
  const h = fixture({ slowSync: true, failSync: true }); await tick();
  assert.equal(h.coordinator.getSnapshot().active, false);
  h.release(); await tick();
  assert.equal(h.commits(), 1);
  assert.equal(h.toasts.some(message => message.id === 'app.string.bottom_panel_bookmark_add_failed'), false);
  assert.equal(h.toasts.some(message => message.id === 'app.string.bookmark_add_saved_sync_pending'), true);
});
test('incremental creation keeps the new bookmark visible in its folder and URL lookup', async () => {
  const h = fixture(); await tick();
  const node = h.repository.findBookmarkByUrl('https://feedback.example/page', 'regular');
  assert.ok(node); assert.equal(node.parentId, core.BOOKMARK_TOOLBAR_ROOT_ID);
  assert.equal(node.sync.state, 'pending_push');
  assert.ok(h.repository.listChildren(core.BOOKMARK_TOOLBAR_ROOT_ID, 'regular').some(item => item.id === node.id));
  assert.equal(h.fullReads(), 0);
});
test('single-history-item save feedback uses the same local commit boundary', async () => {
  const h = fixture({ slowSync: true, start: false });
  const { HistoryBookmarkAddCoordinator } = load('core/bookmarks/HistoryBookmarkAddCoordinator');
  let saved = 0, draft;
  const history = new HistoryBookmarkAddCoordinator({
    applyDraft: value => { draft = value; }, resolveFolders: () => h.folders,
    hasBookmark: url => h.repository.findBookmarkByUrl(url, 'regular') !== undefined,
    isFolderAvailable: id => h.repository.findNodeById(id)?.type === 'folder', previewFolder() {}, dismiss() {},
    beginSave: (title, url, folderId) => h.mutationService.beginCreateBookmarkIfMissing({ type: 'bookmark', title, url, parentId: folderId, scope: 'regular' }),
    refreshBookmarks() {}, onSyncPreparationFailed() {}, onSaved: () => { saved += 1; }
  });
  history.begin('History save', 'https://history-feedback.example/page');
  history.handleAction({ type: 'confirm_add' }); await tick();
  assert.equal(saved, 1); assert.equal(draft.saving, false);
  assert.equal(h.commits(), 1); assert.equal(h.syncStarted(), 1); assert.equal(h.fullReads(), 0);
  h.release(); await tick();
});

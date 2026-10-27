'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const resource = (id) => ({ id });
function load(relative, imports = {}) {
  const scope = { exports: {} };
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    module: scope, exports: scope.exports, $r: resource, setTimeout,
    require: id => {
      assert.ok(id in imports, `Unexpected import: ${id}`);
      return imports[id];
    }
  });
  return scope.exports;
}
const utils = load('common/utils/UrlUtils.ets');
const drafts = load('core/bookmarks/BookmarkAddDraft.ets', {
  '@ohos.url': { default: { URL: { parseURL: input => new URL(input) } } },
  '../../common/utils/UrlUtils': utils
});
const tick = () => new Promise(resolve => setImmediate(resolve));
function harness({ fail = false, delayed = false, blocked = false, scope = 'regular', existingUrl = '' } = {}) {
  const folders = [{ id: 'folder', type: 'folder', title: 'Bookmarks' }, { id: 'other', type: 'folder', title: 'Other' }];
  const writes = [], home = [], snapshots = [], resets = [], toasts = [];
  let rejectWrite = fail, resolveWrite;
  const { BrowserBookmarkActionCoordinator } = load('core/browser/BrowserBookmarkActionCoordinator.ets', {
    '../bookmarks/BookmarkAddDraft': drafts,
    '../../services/bookmarks/BookmarkMutationService': { BookmarkMutationService: class {
      beginCreateBookmarkIfMissing(command) {
        const localCommit = this.createBookmarkIfMissing(command);
        return { localCommit, completion: localCommit };
      }
      async createBookmarkIfMissing(command) {
        writes.push(command);
        if (rejectWrite) throw new Error('storage unavailable');
        if (delayed) await new Promise(resolve => { resolveWrite = resolve; });
        return { id: 'new', ...command };
      }
    } },
    '../../services/privacy/BrowserPrivacyEffectPolicyService': { BrowserPrivacyEffectPolicyService: class {
      decide() { return { outcome: blocked ? 'deny' : 'allow' }; }
    } },
    './BrowserBookmarkScopeService': { BrowserBookmarkScopeService: class { resolveScopeForBoundary() { return scope; } } },
    './BrowserProfileBoundaryService': { BrowserProfileBoundaryService: class { buildBoundary() { return {}; } } }
  });
  let token;
  const coordinator = new BrowserBookmarkActionCoordinator({
    repository: { findBookmarkByUrl: url => url === existingUrl ? { id: 'existing' } : undefined, findNodeById: id => folders.find(folder => folder.id === id) },
    folderPreparationCoordinator: {
      getCachedOptions: () => folders, getResponsiveOptions: () => folders,
      prepare: async () => folders, prepareFolderPreview: async () => folders, invalidate() {}
    },
    searchSuggestionCoordinator: { invalidate() {} },
    homeShortcutToggleService: { addIfMissing: async command => { home.push(command); return { added: true }; } },
    transientSurfaceCoordinator: {
      present: () => { token = {}; return token; }, isCurrent: current => current === token,
      dismiss: () => { token = undefined; }, reset: id => { resets.push(id); token = undefined; }
    }
  }, {
    applySnapshot: snapshot => snapshots.push(snapshot), showToast: message => toasts.push(message),
    presentPersistentWriteBlocked: () => {}, confirmRemove: () => {}, refreshHomeShortcuts: () => {}
  });
  const target = { source: 'current_page', title: 'Original', url: 'https://original.example/page', dataScope: scope, privacyMode: 'normal', enabled: true, homeShortcutScenarioId: 'page' };
  return { coordinator, target, writes, home, snapshots, resets, toasts, folders,
    action: action => coordinator.handleFolderSelectionAction(action),
    snapshot: () => coordinator.getSnapshot(), retry: () => { rejectWrite = false; }, finish: () => resolveWrite() };
}
test('opening, typing, and choosing a folder do not write; cancel discards the draft', async () => {
  const h = harness(); h.coordinator.startAdd(h.target);
  h.action({ type: 'edit_title', value: 'Custom' });
  h.action({ type: 'select_folder', folderId: 'other' });
  await tick(); assert.equal(h.snapshot().draft.title, 'Custom'); assert.equal(h.writes.length, 0);
  h.action({ type: 'dismiss' }); h.action({ type: 'confirm_add' });
  assert.equal(h.writes.length, 0);
  h.coordinator.startAdd(h.target); assert.equal(h.snapshot().draft.title, 'Original');
});
test('save commits edited title, normalized URL and folder, and home uses the edited values', async () => {
  const h = harness(); h.coordinator.openAnchored(h.target);
  h.action({ type: 'edit_title', value: ' Custom name ' }); h.action({ type: 'edit_url', value: 'changed.example/new' });
  h.action({ type: 'select_folder', folderId: 'other' }); h.action({ type: 'set_add_to_home', selected: true });
  h.action({ type: 'confirm_add' }); await tick();
  assert.equal(h.writes.length, 1); assert.equal(h.writes[0].title, 'Custom name');
  assert.equal(h.writes[0].url, 'https://changed.example/new'); assert.equal(h.writes[0].parentId, 'other');
  assert.equal(h.home[0].title, 'Custom name'); assert.equal(h.home[0].url, 'https://changed.example/new');
  assert.equal(h.snapshot().active, false);
});
test('missing names and invalid URLs leave the form open with field errors and no write', async () => {
  const h = harness(); h.coordinator.startAdd(h.target);
  h.action({ type: 'edit_title', value: ' ' }); h.action({ type: 'edit_url', value: 'not a website' });
  h.action({ type: 'confirm_add' }); await tick();
  assert.equal(h.writes.length, 0); assert.equal(h.snapshot().active, true);
  assert.equal(h.snapshot().draft.titleError.id, 'app.string.bookmark_name_required');
  assert.equal(h.snapshot().draft.urlError.id, 'app.string.bookmark_add_url_invalid');
});
test('a failed save keeps edited fields and selected folder for retry', async () => {
  const h = harness({ fail: true }); h.coordinator.startAdd(h.target);
  h.action({ type: 'edit_title', value: 'Retry me' }); h.action({ type: 'select_folder', folderId: 'other' });
  h.action({ type: 'confirm_add' }); await tick();
  assert.equal(h.snapshot().active, true); assert.equal(h.snapshot().draft.saving, false);
  assert.equal(h.snapshot().draft.title, 'Retry me'); assert.equal(h.snapshot().draft.folderId, 'other');
  assert.ok(h.snapshot().draft.saveError); assert.equal(h.resets.length, 0);
  h.retry(); h.action({ type: 'confirm_add' }); await tick(); assert.equal(h.snapshot().active, false);
});
test('repeated save clicks create one write while saving', async () => {
  const h = harness({ delayed: true }); h.coordinator.startAdd(h.target);
  h.action({ type: 'confirm_add' }); h.action({ type: 'confirm_add' });
  assert.equal(h.writes.length, 1); assert.equal(h.snapshot().draft.saving, true);
  h.finish(); await tick(); assert.equal(h.snapshot().active, false);
});
test('completion of an earlier save cannot close a later add session', async () => {
  const h = harness({ delayed: true }); h.coordinator.startAdd(h.target); h.action({ type: 'confirm_add' });
  h.coordinator.startAdd({ ...h.target, title: 'Next page' }); h.finish(); await tick();
  assert.equal(h.snapshot().active, true); assert.equal(h.snapshot().draft.title, 'Next page');
  assert.equal(h.resets.length, 0);
});
test('blocked persistent writes cannot save; private bookmarks keep their scope', async () => {
  const blocked = harness({ blocked: true }); blocked.coordinator.startAdd(blocked.target);
  blocked.action({ type: 'confirm_add' }); assert.equal(blocked.writes.length, 0);
  const h = harness({ scope: 'private' }); h.coordinator.startAdd(h.target);
  h.action({ type: 'set_add_to_home', selected: true }); h.action({ type: 'confirm_add' }); await tick();
  assert.equal(h.writes[0].scope, 'private'); assert.equal(h.home.length, 0);
});
test('a folder removed before Save cannot silently redirect the bookmark', () => {
  const h = harness(); h.coordinator.startAdd(h.target); h.folders.splice(0, 1);
  h.action({ type: 'confirm_add' }); assert.equal(h.writes.length, 0);
  assert.equal(h.snapshot().draft.saveError.id, 'app.string.bookmark_add_choose_folder');
});
function historyHarness() {
  const { HistoryBookmarkAddCoordinator } = load('core/bookmarks/HistoryBookmarkAddCoordinator.ets', {
    './BookmarkAddDraft': drafts
  });
  const writes = [], folders = [{ id: 'folder' }, { id: 'other' }];
  let draft, fail = false, saved = 0;
  const coordinator = new HistoryBookmarkAddCoordinator({
    applyDraft: value => { draft = value; }, resolveFolders: () => folders, hasBookmark: () => false,
    isFolderAvailable: id => folders.some(folder => folder.id === id),
    previewFolder() {}, dismiss() {},
    beginSave: (title, url, folderId) => {
      const localCommit = (async () => {
        writes.push({ title, url, folderId }); if (fail) throw new Error('no storage');
      })();
      return { localCommit, completion: localCommit };
    },
    refreshBookmarks() {}, onSyncPreparationFailed() {},
    onSaved: () => { saved += 1; }
  });
  return { coordinator, writes, folders, draft: () => draft, saved: () => saved,
    fail: value => { fail = value; }, action: action => coordinator.handleAction(action) };
}
test('single history additions save the edited URL and name only after confirmation', async () => {
  const h = historyHarness(); h.coordinator.begin('History', 'https://history.example');
  h.action({ type: 'edit_title', value: 'Edited history' }); h.action({ type: 'edit_url', value: 'edited.example' });
  h.action({ type: 'select_folder', folderId: 'other' });
  h.coordinator.refreshFolders(); assert.equal(h.draft().title, 'Edited history'); assert.equal(h.writes.length, 0);
  h.action({ type: 'confirm_add' }); h.action({ type: 'confirm_add' }); await tick();
  assert.equal(h.writes.length, 1); assert.equal(h.writes[0].url, 'https://edited.example');
  assert.equal(h.writes[0].folderId, 'other'); assert.equal(h.saved(), 1);
});
test('history cancellation discards the draft; save failures retain it for retry', async () => {
  const h = historyHarness(); h.coordinator.begin('History', 'https://history.example');
  h.action({ type: 'dismiss' }); h.action({ type: 'confirm_add' }); assert.equal(h.writes.length, 0);
  h.coordinator.begin('Retry', 'https://retry.example'); h.fail(true);
  h.action({ type: 'confirm_add' }); await tick();
  assert.equal(h.saved(), 0); assert.equal(h.draft().saving, false); assert.equal(h.draft().title, 'Retry');
  assert.ok(h.draft().saveError); h.fail(false); h.action({ type: 'confirm_add' }); await tick(); assert.equal(h.saved(), 1);
});

test('an edited URL that already exists reports the duplicate without silently losing the edits', () => {
  const h = harness({ existingUrl: 'https://existing.example' }); h.coordinator.startAdd(h.target);
  h.action({ type: 'edit_url', value: 'https://existing.example' }); h.action({ type: 'edit_title', value: 'Keep me' });
  h.action({ type: 'confirm_add' }); assert.equal(h.writes.length, 0); assert.equal(h.snapshot().active, true);
  assert.equal(h.snapshot().draft.title, 'Keep me'); assert.equal(h.snapshot().draft.saveError.id, 'app.string.history_already_bookmarked');
});

test('system Back from folder selection returns to the edited form before canceling', () => {
  for (const isHistory of [false, true]) {
    const h = isHistory ? historyHarness() : harness();
    if (isHistory) h.coordinator.begin('History', 'https://history.example'); else h.coordinator.startAdd(h.target);
    h.action({ type: 'edit_title', value: 'Keep draft' }); h.action({ type: 'set_folder_picker', selected: true });
    h.action({ type: 'back' });
    const draft = isHistory ? h.draft() : h.snapshot().draft;
    assert.equal(draft.choosingFolder, false); assert.equal(draft.title, 'Keep draft');
    if (!isHistory) assert.equal(h.snapshot().active, true);
    assert.equal(h.writes.length, 0);
  }
});
test('history rejects a folder removed from live data before Save', () => {
  const h = historyHarness(); h.coordinator.begin('History', 'https://history.example'); h.folders.splice(0, 1);
  h.action({ type: 'confirm_add' }); assert.equal(h.writes.length, 0);
  assert.equal(h.draft().saveError.id, 'app.string.bookmark_add_choose_folder');
});
test('a departed history session ignores the completion of its pending save', async () => {
  const { HistoryBookmarkAddCoordinator } = load('core/bookmarks/HistoryBookmarkAddCoordinator.ets', { './BookmarkAddDraft': drafts });
  let complete, updates = 0, saved = 0;
  const coordinator = new HistoryBookmarkAddCoordinator({
    applyDraft: () => { updates += 1; }, resolveFolders: () => [{ id: 'folder' }],
    isFolderAvailable: () => true, hasBookmark: () => false, previewFolder() {}, dismiss() {},
    beginSave: () => {
      const localCommit = new Promise(resolve => { complete = resolve; });
      return { localCommit, completion: localCommit };
    },
    refreshBookmarks() {}, onSyncPreparationFailed() {}, onSaved: () => { saved += 1; }
  });
  coordinator.begin('History', 'https://history.example'); coordinator.handleAction({ type: 'confirm_add' });
  coordinator.cancel(); const priorUpdates = updates; complete(); await tick();
  assert.equal(updates, priorUpdates); assert.equal(saved, 0);
});

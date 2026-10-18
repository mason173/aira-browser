'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

const source = fs.readFileSync(path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/core/bookmarks/BookmarkRecordActionViewModel.ets'), 'utf8');
const moduleScope = { exports: {} };
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, {
  module: moduleScope, exports: moduleScope.exports,
  $r: (id, ...params) => ({ id, params }),
  require: id => {
    assert.ok(id.endsWith('/BookmarkRepositoryCore'), `Unexpected runtime import: ${id}`);
    return { isBookmarkRootNodeId: nodeId => nodeId === 'root' };
  }
});
const model = new moduleScope.exports.BookmarkRecordActionViewModel();
const bookmark = { id: 'bookmark', type: 'bookmark' };
const folder = { id: 'folder', type: 'folder' };
const root = { id: 'root', type: 'folder' };
const groups = (node, selectionMode = false, selectedNodeIds = [node.id]) =>
  model.buildDesktopGroups(node, { selectionMode, selectedNodeIds });
const actions = (...args) => groups(...args).flatMap(group => Array.from(group.actions));
const ids = (...args) => actions(...args).map(action => action.id).join(',');

test('a bookmark keeps all five commands, including navigation, selection, and deletion', () => {
  assert.equal(ids(bookmark), 'open,open_new_tab,edit,enter_selection,delete');
  assert.equal(actions(bookmark)[1].title.id, 'app.string.history_open_new_tab');
  assert.equal(groups(bookmark).length, 4);
  for (const group of groups(bookmark)) assert.ok(group.actions.length > 0);
});

test('a folder opens itself and keeps editing, selection, and deletion', () => {
  assert.equal(ids(folder), 'open,edit,enter_selection,delete');
  assert.equal(actions(folder)[0].title.id, 'app.string.bookmark_open_folder');
});

test('a collection root offers opening without editing or deleting the root', () => {
  assert.equal(ids(root, false, []), 'open');
});

test('selection mode offers deselect or add selection and hides editing', () => {
  assert.equal(ids(bookmark, true), 'open,open_new_tab,toggle_selection,delete');
  const selected = actions(bookmark, true).find(action => action.id === 'toggle_selection');
  assert.equal(selected.title.id, 'app.string.history_deselect');
  const unselected = actions(bookmark, true, ['other']).find(action => action.id === 'toggle_selection');
  assert.equal(unselected.title.id, 'app.string.history_add_selection');
});

test('multiple selection deletes the full selection and never edits a single item', () => {
  assert.equal(ids(bookmark, true, ['bookmark', 'other']),
    'open,open_new_tab,toggle_selection,delete_selection');
  const deletion = actions(bookmark, true, ['bookmark', 'other']).at(-1);
  assert.equal(deletion.title.id, 'app.string.bookmark_delete_selected');
  assert.equal(deletion.title.params[0], 2);
  assert.equal(ids(bookmark, false, ['bookmark', 'other']),
    'open,open_new_tab,enter_selection,delete_selection');
});

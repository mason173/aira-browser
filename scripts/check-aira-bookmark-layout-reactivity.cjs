'use strict';

// Run after Hvigor compilation: replay the emitted ArkUI creation/update callback.
// A source-only scroll-controller mock cannot catch a captured @Builder argument.
// Usage: node scripts/check-aira-bookmark-layout-reactivity.cjs [debug|release]
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '..');
const mode = process.argv[2] || 'debug';
assert.ok(['debug', 'release'].includes(mode), 'Expected a Hvigor build mode');
const etsRoot = path.join(root, 'AiraBrowser/entry/src/main/ets');
const compiledPage = path.join(root, 'AiraBrowser/entry/build/default/cache/default',
  `default@CompileArkTS/esmodule/${mode}/entry/src/main/ets/app/pages/BookmarkManagerPage.ts`);
assert.ok(fs.existsSync(compiledPage), 'Compile the app with Hvigor before replaying its ArkUI updates');
const source = fs.readFileSync(compiledPage, 'utf8');
const method = source.match(/    private buildList\([\s\S]*?(?=\n    private )/);
assert.ok(method, 'The compiled page must expose its list presentation builder');
const layout = fs.readFileSync(path.join(etsRoot, 'app/components/bookmarks/BookmarkManagerImmersiveHost.ets'), 'utf8');
const scaffold = fs.readFileSync(path.join(etsRoot, 'app/components/common/ManagementHdsScaffold.ets'), 'utf8');
const titleLayout = [
  scaffold.match(/const MANAGEMENT_TITLE_ACTION_TOP_INSET[^;]+;/)[0],
  scaffold.match(/const MANAGEMENT_IMMERSIVE_TITLE_HEIGHT[^;]+;/)[0],
  scaffold.match(/export function resolveManagementImmersiveTitleBottomInset[\s\S]*?\n\}/)[0]
].join('\n');
const layoutFunctions = layout.slice(layout.indexOf('const BOOKMARK_IMMERSIVE'), layout.indexOf('@Component'));
const compiledProbe = ts.transpileModule(`${titleLayout}\n${layoutFunctions}\nexport class Probe {\n${method[0]}\n}`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;

function mount(folderId, isSearchMode = false) {
  let update;
  let presentation;
  const module = { exports: {} };
  const record = props => {
    presentation = {
      showRootTabs: props.showRootTabs,
      isSearchMode: props.isSearchMode,
      contentTopInset: props.contentTopInset,
      tabsTopInset: props.tabsTopInset
    };
  };
  vm.runInNewContext(compiledProbe, {
    module, exports: module.exports,
    BookmarkManagerPages: class { constructor(_parent, props) { record(props); } },
    ViewPU: { create() {} }, ObservedObject: { GetRawObject: value => value }
  }, { filename: compiledPage });
  const page = new module.exports.Probe();
  page.topSafeInsetVp = 39;
  page.currentFolderId = folderId;
  page.bookmarkSearchState = { isSearchMode };
  page.shouldShowRootTabs = () => page.currentFolderId.length === 0 && !page.bookmarkSearchState.isSearchMode;
  page.observeComponentCreation2 = callback => { update = callback; callback(1, true); };
  page.updateStateVarsOfChildByElmtId = (_id, props) => record(props);
  // Also supports replaying the old compiled builder to demonstrate the regression:
  // the parent updates, but the callback retains this initial by-value layout object.
  if (/buildList\(layout:/.test(method[0])) {
    page.buildList({
      contentTopInset: module.exports.resolveBookmarkManagerContentTopInset(
        page.topSafeInsetVp, isSearchMode, page.shouldShowRootTabs()),
      tabsTopInset: 99
    });
  } else {
    page.buildList();
  }
  return { page, read: () => presentation, refresh: () => update(1, false) };
}

test('compiled page adds tab clearance when leaving a restored bookmark folder', () => {
  const view = mount('restored-folder');
  assert.equal(view.read().contentTopInset, 107);
  view.page.currentFolderId = '';
  view.refresh();
  assert.equal(view.read().showRootTabs, true);
  assert.equal(view.read().contentTopInset, 147, 'root list must gain the missing 40vp below its tabs');
  assert.equal(view.read().contentTopInset - view.read().tabsTopInset, 48);
});

for (const folderId of ['', 'restored-folder']) {
  test(`compiled ${folderId ? 'folder' : 'root'} page updates clearance when opening and closing search`, () => {
    const view = mount(folderId);
    view.page.bookmarkSearchState = { isSearchMode: true };
    view.refresh();
    assert.equal(view.read().showRootTabs, false);
    assert.equal(view.read().contentTopInset, 119);
    view.page.bookmarkSearchState = { isSearchMode: false };
    view.refresh();
    assert.equal(view.read().contentTopInset, folderId ? 107 : 147);
  });
}

test('compiled page updates both tab and list positions when the top safe area changes', () => {
  const view = mount('');
  view.page.topSafeInsetVp = 55;
  view.refresh();
  assert.equal(view.read().tabsTopInset, 115);
  assert.equal(view.read().contentTopInset, 163);
});

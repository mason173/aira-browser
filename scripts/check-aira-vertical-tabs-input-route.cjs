#!/usr/bin/env node
'use strict';

// Replay Hvigor's emitted component tree, not a device or screenshot. ArkUI None
// excludes only the node itself; its hit-testable children still block siblings.
// https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-hit-test-behavior
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const mode = process.argv[2] || 'debug';
assert.ok(['debug', 'release'].includes(mode));
const compiled = path.resolve(__dirname, '../AiraBrowser/entry/build/default/cache/default',
  `default@CompileArkTS/esmodule/${mode}/entry/src/main/ets/app/components/browser/BrowserLargeScreenVerticalTabsSidebar.ts`);
assert.ok(fs.existsSync(compiled), 'Compile with Hvigor before checking the emitted input route');
const source = fs.readFileSync(compiled, 'utf8');
const methodNames = ['initialRender', 'buildSidebarHoverShield', 'buildTabHoverPlate', 'buildTab',
  'buildRowActivator', 'buildTabHighlight', 'buildTabIconSlot', 'closeTabFromDoubleClick',
  'dispatchRowAction', 'dispatchRowKind', 'isPrimaryPointerDown', 'activateTabFromPointer',
  'activateTabFromTouch', 'buildSidebarContextMenuResponse', 'resolvePointerMenuTab'];
const methods = methodNames.map(name => source.match(
  new RegExp(`    (?:private )?${name}\\([^]*?\\n    }`))?.[0]).filter(Boolean).join('\n');
const constants = fs.readFileSync(path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserLargeScreenVerticalTabsSidebar.ets'), 'utf8')
  .match(/^const [A-Z_]+: number = [^;]+;/gm).join('\n');

function mount(expanded = false) {
  const roots = [], stack = [], nodes = [], gestures = [], menuCalls = [], intents = [];
  let origin = '';
  const current = () => stack.at(-1);
  const api = name => new Proxy({}, { get(_target, property) {
    if (property === 'create' || property === 'createWithChild') return () => {
      const node = { name, origin, parent: current(), children: [], attrs: {}, gestures: [] };
      (current()?.children ?? roots).push(node);
      nodes.push(node); stack.push(node);
    };
    if (property === 'pop') return () => { assert.equal(current().name, name); stack.pop(); };
    return (...args) => { current().attrs[property] = args[0]; };
  } });
  const enumValues = new Proxy({}, { get: (_target, key) => key });
  const globals = { exports: {},
    BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP: 56,
    BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP: 248,
    BROWSER_LARGE_SCREEN_TAB_TITLE_FONT_SIZE_VP: 14,
    resolveAppResourceText: value => value,
    buildBrowserDesktopMenuOptions: () => ({}),
    resolveBrowserLargeScreenVerticalTabsDoubleClickCloseTarget: (enabled, id, tabs) =>
      enabled !== false && tabs.some(tab => tab.id === id && tab.closable) ? id : '',
    Gesture: { create() {}, pop() {} }, GestureGroup: { create() {}, pop() {} },
    TapGesture: {
      create(options) { const gesture = { ...options }; current().gestures.push(gesture); gestures.push(gesture); },
      onAction(callback) { gestures.at(-1).action = callback; }, pop() { gestures.pop(); }
    },
    If: { create() {}, pop() {} }, ForEach: { create() {}, pop() {} }
  };
  for (const name of ['Stack', 'Column', 'Row', 'Scroll', 'Divider', 'Text', 'Button']) globals[name] = api(name);
  // Divider has no child scope and thus no emitted pop.
  globals.Divider = new Proxy({}, { get: () => () => {} });
  for (const name of ['Alignment', 'HorizontalAlign', 'VerticalAlign', 'FlexAlign', 'BarState', 'EdgeEffect',
    'ScrollDirection', 'HitTestMode', 'MouseAction', 'MouseButton', 'TouchType', 'SourceType', 'ResponseType',
    'ButtonType', 'Color', 'HoverEffect', 'FontWeight', 'TextAlign', 'TextOverflow', 'EllipsisMode', 'WordBreak',
    'GesturePriority', 'GestureMode', 'MenuPreviewMode']) globals[name] = enumValues;
  vm.runInNewContext(ts.transpileModule(`${constants}\nexport class Probe { ${methods} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, globals, { filename: compiled });
  const view = new globals.exports.Probe();
  const tab = { id: 'test-tab', title: 'Test', closable: true, pinned: false, muted: false };
  Object.assign(view, {
    tabStrip: { allTabs: [tab], selectedTabId: tab.id }, storedDoubleClickCloseEnabled: true,
    sidebarWidthVp: expanded ? 248 : 56, lastRowActionKey: '', lastRowActionAtMs: 0,
    observeComponentCreation2: callback => callback(1, true),
    ifElseBranchUpdateFunction: (_branch, callback) => callback(),
    forEachUpdateFunction: (_id, items, callback) => items.forEach(callback),
    buildHeader() {}, buildNewTabHoverPlate() {}, buildTabIcon() {}, buildTabActions() {},
    sidebarBorderWidthVp: () => 1, overlayShadowRadius: () => 0, overlayShadowOffsetX: () => 0,
    detailActionsVisible: () => expanded, isRailWidth: () => !expanded, detailOpacity: () => expanded ? 1 : 0,
    resolveTabTitle: () => 'Test', resolveTabBackground: () => '#fff',
    buildBlankContextMenuResponse: () => menuCalls.push('blank'),
    buildTabContextMenuResponse: () => menuCalls.push('tab'),
    buildBlankContextMenu: () => menuCalls.push('blank'),
    buildTabContextMenu: () => menuCalls.push('tab'),
    pointerMenuTabId: '',
    onIntent: intent => intents.push(intent)
  });
  for (const name of methodNames) {
    if (typeof view[name] !== 'function') continue;
    const original = view[name].bind(view);
    view[name] = (...args) => { const previous = origin; origin = name;
      try { return original(...args); } finally { origin = previous; } };
  }
  view.initialRender();
  const icon = nodes.find(node => node.origin === 'buildTabIconSlot' && node.name === 'Stack');
  assert.ok(icon, 'Use the actual icon slot in the emitted component tree');
  const route = [];
  for (let node = icon; node; node = node.parent) {
    if (node.attrs.hitTestBehavior !== 'None') route.push(node);
    // A Transparent content container also exposes the full-size backdrop behind
    // it. None still tests children, but a hit child blocks that lower sibling.
    if (node.attrs.hitTestBehavior === 'Transparent' && node.parent?.name === 'Stack') {
      for (const sibling of node.parent.children.slice(0, node.parent.children.indexOf(node))) {
        if (sibling.attrs.width === '100%' && sibling.attrs.height === '100%') route.push(sibling);
      }
    }
  }
  return { view, route, intents, menuCalls };
}

function pressIcon(h, source) {
  for (const node of [...h.route].reverse()) node.attrs.onTouchIntercept?.({ type: 'Down' });
  for (const node of h.route) {
    if (source === 'TouchScreen') node.attrs.onTouch?.({ type: 'Down' });
    else node.attrs.onMouse?.({ action: 'Press', button: 'Left' });
  }
}

function doubleClick(h, source) {
  for (const node of h.route) {
    for (const gesture of node.gestures.filter(item => item.count === 2)) gesture.action({ source });
  }
}

test('double-tapping the visible icon reaches the close handler in collapsed and expanded sidebars', () => {
  for (const expanded of [false, true]) {
    for (const source of ['TouchScreen', 'Mouse']) {
      const h = mount(expanded);
      pressIcon(h, source);
      pressIcon(h, source);
      doubleClick(h, source);
      assert.equal(h.intents.filter(intent => intent.kind === 'close_tab').length, 1,
        `The icon's hit path must reach double-click close (${source}, expanded=${expanded})`);
    }
  }
});

test('switch-off and child button actions cannot trigger the ancestor double-click close', () => {
  for (const action of ['mute:test-tab', 'close:test-tab', 'select_tab:test-tab']) {
    const h = mount(true);
    h.view.lastRowActionKey = action;
    if (action.startsWith('select_tab:')) h.view.storedDoubleClickCloseEnabled = false;
    doubleClick(h, 'TouchScreen');
    assert.equal(h.intents.filter(intent => intent.kind === 'close_tab').length, 0);
  }
});

test('long-pressing a tab has one menu owner, and cannot select the blank-area menu', () => {
  const h = mount();
  pressIcon(h, 'TouchScreen');
  const bindings = h.route.map(node => node.attrs.bindContextMenuWithResponse).filter(Boolean);
  assert.equal(bindings.length, 1, 'The blank-area menu must not compete on the tab ancestor chain');
  bindings[0].builder('LongPress');
  assert.deepEqual(h.menuCalls, ['tab']);
  // A subsequent blank-area press must discard the previous target.
  const sidebar = h.route.find(node => node.origin === 'initialRender' && node.name === 'Stack');
  sidebar.attrs.onTouchIntercept?.({ type: 'Down' });
  bindings[0].builder('LongPress');
  assert.deepEqual(h.menuCalls, ['tab', 'blank']);
});

test('the scroll container stays in the touch route', () => {
  assert.ok(mount().route.some(node => node.name === 'Scroll'),
    'Fixing menu routing must not disable vertical scrolling');
});

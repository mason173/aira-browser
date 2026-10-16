#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');

const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserSearchSuggestionsPanel.ets');
const source = fs.readFileSync(filename, 'utf8');
function method(name) {
  const match = source.match(new RegExp(`  private ${name}\\([^]*?\\n  }`));
  assert.ok(match, `Missing production method ${name}`);
  return match[0];
}
// Replace only ArkUI container block syntax. Production ordering, conditionals,
// row keys and scroll attributes execute unchanged against a recording tree.
function recordable(body) {
  const edits = [];
  for (const match of body.matchAll(/\b(Scroll|List|ListItem|Column)\(([^\n]*)\) \{/g)) {
    const opening = match.index + match[0].length - 1;
    const scanner = ts.createScanner(ts.ScriptTarget.Latest, true, ts.LanguageVariant.Standard, body.slice(opening));
    let depth = 0;
    let closing = -1;
    for (let token = scanner.scan(); token !== ts.SyntaxKind.EndOfFileToken; token = scanner.scan()) {
      if (token === ts.SyntaxKind.OpenBraceToken) depth++;
      if (token === ts.SyntaxKind.CloseBraceToken && --depth === 0) {
        closing = opening + scanner.getTokenPos() + 1;
        break;
      }
    }
    assert.ok(closing > opening);
    edits.push([closing, 0, ')']);
    edits.push([match.index, match[0].length,
      `${match[1]}(${match[2]}${match[2] ? ', ' : ''}() => {`]);
  }
  for (const [at, length, value] of edits.sort((a, b) => b[0] - a[0])) {
    body = body.slice(0, at) + value + body.slice(at + length);
  }
  return body;
}
let root;
let current;
const component = name => (...args) => {
  const node = { name, attrs: {}, children: [] };
  if (current) current.children.push(node); else root = node;
  const callback = args.find(value => typeof value === 'function');
  if (callback) {
    const parent = current;
    current = node;
    callback();
    current = parent;
  }
  const proxy = new Proxy({}, { get: (_, attr) => value => { node.attrs[attr] = value; return proxy; } });
  return proxy;
};
const methods = ['buildVisualRows', 'buildVisualGridRows', 'appendRegularVisualGridRows', 'resolveColumnCount',
  'buildVisualGridRowKey', 'resolveRowGap', 'resolveRegularRowHeight', 'appendSuggestionRow',
  'appendRegularSuggestionRow', 'isCurrentTabVisualRow', 'isCurrentTabSuggestion',
  'resolvePinnedCurrentSuggestionBottomPadding', 'resolveBottomUpContentHeight'];
const scroll = method('buildScrollableSuggestionList');
const modelSource = `class Panel {
  ${methods.map(method).join('\n')}
  ${recordable(scroll)}
  buildSuggestionList() { this.recordRows(this.buildVisualGridRows()); }
  buildSuggestionGroup(group) { this.recordRows([group]); }
}
module.exports = Panel;`;
const moduleObject = { exports: {} };
vm.runInNewContext(ts.transpileModule(modelSource, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, {
  module: moduleObject,
  Scroll: component('Scroll'), List: component('List'), ListItem: component('ListItem'), Column: component('Column'),
  ForEach: (rows, draw) => rows.forEach(draw), Alignment: { TopStart: 'top', BottomStart: 'bottom' },
  EdgeEffect: { Spring: 'spring' }, BarState: { Off: 'off' },
  CURRENT_SUGGESTION_CARD_HEIGHT: 76
});
const Panel = moduleObject.exports;
const history = count => Array.from({ length: count }, (_, index) => ({
  id: `history-${index}`, source: 'search_history', title: `record ${index}`, target: `query ${index}`
}));
const panel = Object.assign(new Panel(), {
  layoutMode: 'bottomUp', columns: 1, rowGap: 0, regularRowHeight: 54, horizontalPadding: 0,
  currentTabSuggestionRefId: '', currentPageSuggestion: undefined,
  recordRows: groups => { component('rows')().height(groups.length * 54); }
});
let frames = 0;
for (const layoutMode of ['bottomUp', 'topDown']) {
  for (const columns of [1, 2, 3]) {
    for (const viewportHeight of [96, 162, 270, 540]) {
      for (const count of [0, 1, 3, 8, 12]) {
        for (const pinned of [false, true]) {
          Object.assign(panel, { layoutMode, columns, suggestions: history(count),
            currentPageSuggestion: pinned ? { id: 'current' } : undefined });
          const bottomPadding = panel.resolvePinnedCurrentSuggestionBottomPadding();
          panel.buildScrollableSuggestionList('100%', bottomPadding);
          const groups = panel.buildVisualGridRows();
          if (layoutMode === 'bottomUp') {
            assert.equal(root.name, 'List', 'Bottom-up search needs the native end-anchored list');
            assert.equal(root.attrs.stackFromEnd, true, 'Initial history viewport starts nearest the input');
            assert.equal(root.attrs.contentEndOffset, bottomPadding, 'Pinned current card has its own reserve');
            assert.equal(root.children.length, groups.length, 'Each visual grid row is a separate native ListItem');
            const contentHeight = panel.resolveBottomUpContentHeight();
            // Native List.stackFromEnd defaults to its last item, with the last
            // item ending at the viewport bottom minus the pinned-card reserve.
            const initialOffset = Math.max(0, contentHeight - viewportHeight);
            if (count > 0) {
              const newestIndex = groups.findIndex(group =>
                group.rows.some(row => row.suggestion.id === 'history-0'));
              const newestBottom = (newestIndex + 1) * panel.regularRowHeight - initialOffset;
              assert.ok(newestBottom <= viewportHeight - bottomPadding,
                `Newest history hidden: count=${count}, columns=${columns}, viewport=${viewportHeight}`);
              assert.ok(newestBottom > 0 || bottomPadding >= viewportHeight,
                'Latest history must be visible whenever room remains above the pinned card');
            }
          } else {
            assert.equal(root.name, 'Scroll', 'Top-down split search retains its original scroll host');
            assert.equal(root.attrs.stackFromEnd, undefined, 'Top-down search must not start at the bottom');
            if (count > 0) assert.equal(groups[0].rows[0].suggestion.id, 'history-0');
          }
          frames++;
        }
      }
    }
  }
}
// No timers, controller scroll commands, or query/content keys may reset a
// user's scroll on asynchronous hydration or routine suggestion publications.
assert.doesNotMatch(scroll, /scrollTo|scrollEdge|setTimeout|onAppear|\.id\(/);
assert.match(scroll, /gridRow\.key/);
console.log(`search list viewport: ok (${frames} overflow/empty/column/pinned-card frames)`);

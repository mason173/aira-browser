#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function evaluate(source, globals = {}) {
  const module = { exports: {} };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, require: () => ({}), ...globals
  });
  return module.exports;
}

const { HomeShortcutGridPolicy } = evaluate(read('features/newtab/HomeShortcutGridPolicy.ets'));
const { HomeShortcutLogicService } = evaluate(read('services/shortcuts/HomeShortcutLogicService.ets'));
const { HomeShortcutViewModel } = evaluate(read('features/newtab/HomeShortcutViewModel.ets'));
const surface = read('app/components/browser/HomeShortcutSurface.ets');
const methods = ['resolveShortcutColumnGap', 'resolvePresentationItemCount',
  'resolveShortcutLaneCount', 'resolvePartialRowCenterShift', 'resolveShortcutListWidth',
  'resolveShortcutCardWidth', 'resolveShortcutLaneWidth'].map(name => {
  const match = surface.match(new RegExp(`  private ${name}\\([^]*?\\n  }`));
  assert.ok(match, `Missing production method ${name}`);
  return match[0];
}).join('\n');
const { SurfaceLayout } = evaluate(`export class SurfaceLayout { ${methods} }`);
const logic = new HomeShortcutLogicService();
const viewModel = new HomeShortcutViewModel(logic);
const { applyCenteredHomeShortcutLayout } = evaluate(read('features/newtab/CenteredHomeShortcutLayoutPolicy.ets'));
const metrics = applyCenteredHomeShortcutLayout({ shortcutMetrics: {
  columns: 5, rowGap: 16, columnGap: 6, targetTileSize: 52,
  minimumTileSize: 44, fallbackColumnWidth: 72, titleTopGap: 4, titleBlockHeight: 18
}}).shortcutMetrics;

// Exercise the real List lane/card calculations, including the add tile and short rows.
// Labels must receive the column budget rather than being squeezed into the small icon.
for (const gridWidth of [320, 360, 412, 800]) {
  for (const itemCount of [1, 2, 5, 7, 11]) {
    const layout = Object.assign(new SurfaceLayout(), {
      viewModel, metrics, gridWidth, contentInset: 0, centerPartialRows: true, containerParentId: '',
      liveShortcuts: Array.from({ length: itemCount - 1 }, (_, index) => ({id: `item-${index}`})),
      gridPolicy: new HomeShortcutGridPolicy(),
      containerShortcuts() { return this.liveShortcuts; },
      hasAddEntry() { return this.showAddEntry; },
      showAddEntry: true, showPinnedSettingsEntry: false
    });
    const labelWidth = layout.resolveShortcutCardWidth();
    const expected = (gridWidth - metrics.columnGap * (metrics.columns - 1)) / metrics.columns;
    assert.ok(Math.abs(labelWidth - expected) < 0.001,
      `Short names such as ChatGPT / Perplexity need the column width: ${labelWidth} vs ${expected}`);
    assert.ok(labelWidth > logic.getTileSize(gridWidth, metrics));
    assert.ok(labelWidth <= layout.resolveShortcutLaneWidth());
    const columns = layout.resolveShortcutLaneCount();
    const gap = layout.resolveShortcutColumnGap();
    const remainder = itemCount % columns;
    const lastRowCount = remainder || columns;
    const end = layout.resolvePartialRowCenterShift(itemCount - 1) +
      lastRowCount * labelWidth + (lastRowCount - 1) * gap;
    assert.ok(end <= layout.resolveShortcutListWidth() + 0.001, 'The trailing add tile must remain inside the rail');
  }
}
assert.match(surface, /Text\(this\.resolveShortcutDisplayTitle\(shortcut\)\)\s*\.width\('100%'\)/);
console.log('Home shortcut labels use their column width; short rows and the trailing add tile fit.');

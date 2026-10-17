#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const page = read('app/pages/BrowserToolbarCustomizationPage.ets');
const screen = read('app/components/settings/BrowserToolbarCustomizationScreen.ets');

function evaluate(source, globals = {}) {
  const module = { exports: {} };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports, $r: name => name, ...globals });
  return module.exports;
}
const modules = new Map();
function load(relative) {
  if (!modules.has(relative)) {
    modules.set(relative, evaluate(read(relative), {
      require: id => load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), `${id}.ets`)))
    }));
  }
  return modules.get(relative);
}
function method(source, name) {
  return source.match(new RegExp(`  (?:private )?${name}\\([^]*?\\n  }`))?.[0] ?? '';
}

const { BrowserToolbarScrollBehaviorSettingsViewModel } =
  load('core/settings/BrowserToolbarScrollBehaviorSettingsViewModel.ets');
let preferences;
const { ToolbarPage, ToolbarScreen } = evaluate(`
  export class ToolbarPage { ${method(page, 'onPageShow')} }
  export class ToolbarScreen {
    ${method(screen, 'refreshState')}
    ${method(screen, 'refreshScrollBehaviorCopy')}
  }
`, { sharedPreferencesRepository: { getPreferences: () => preferences } });
// Follow the actual page-to-component binding and @Watch target. No component
// remount or aboutToAppear is allowed when returning from the options page.
const revisionField = page.match(/refreshRevision:\s*this\.(\w+)/)?.[1];
const watcher = screen.match(/@Prop\s+@Watch\('([^']+)'\)\s+refreshRevision:/)?.[1];
for (const style of ['floating', 'split', 'dock']) {
  for (const initial of ['fixed', 'compact', 'hidden']) {
    preferences = { toolbarLayout: {}, experiments: { webBottomSafeAreaEnabled: false },
      appearance: { toolbarChromeStyle: style, bottomToolbarScrollBehavior: initial,
        globalImmersionEnabled: false, alwaysTopImmersionEnabled: false } };
    const route = new ToolbarPage();
    if (revisionField) route[revisionField] = 0;
    const mounted = Object.assign(new ToolbarScreen(), {
      viewModel: { buildState: settings => settings },
      scrollBehaviorViewModel: new BrowserToolbarScrollBehaviorSettingsViewModel()
    });
    mounted.refreshState();
    for (const selected of ['hidden', 'fixed', 'compact']) {
      preferences.appearance.bottomToolbarScrollBehavior = selected;
      const before = route[revisionField];
      route.onPageShow?.();
      if (revisionField && watcher && route[revisionField] !== before) mounted[watcher]();
      const actual = mounted.scrollBehaviorViewModel.formatBehaviorTitle(
        mounted.scrollBehavior, mounted.toolbarChromeStyle);
      const expected = mounted.scrollBehaviorViewModel.formatBehaviorTitle(selected, style);
      assert.equal(actual, expected,
        `Returning to the mounted toolbar page must update its summary: ${style}, ${initial} -> ${selected}`);
    }
  }
}
console.log('Toolbar settings return refresh passed: retained page, all styles and scroll options.');

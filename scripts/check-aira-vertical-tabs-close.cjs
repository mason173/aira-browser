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
const read = relative => fs.readFileSync(path.join(root, relative + '.ets'), 'utf8');

function evaluate(source, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, $r: id => id, ...globals });
  return exports;
}

function load(relative) {
  if (cache.has(relative)) return cache.get(relative);
  const result = evaluate(read(relative), { require(id) {
    if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (id === '@ohos.url') return { default: { URL } };
    if (id === '@kit.ArkData' || id.endsWith('/AppRuntimeContext')) return {};
    assert.ok(id.startsWith('.'), `Unexpected platform import: ${id}`);
    return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), id)));
  } });
  cache.set(relative, result);
  return result;
}

const { PreferencesRepository, DEFAULT_BROWSER_APPEARANCE_SETTINGS: defaults } =
  load('data/preferences/PreferencesRepository');
const { ArkPreferencesStorageAdapter } = load('data/preferences/ArkPreferencesStorageAdapter');
const { SettingsDetailActionResolver } = load('core/settings/SettingsDetailActionResolver');
const policy = load('core/browser/BrowserLargeScreenVerticalTabsPolicy');
const preference = 'verticalTabsDoubleClickCloseEnabled';
const action = 'toggle_vertical_tabs_double_click_close';

test('new installs and old preferences enable double-click close while explicit false remains disabled', () => {
  assert.equal(defaults[preference], true);
  const repository = new PreferencesRepository();
  const adapter = new ArkPreferencesStorageAdapter();
  for (const value of [undefined, null, false, 'true', 1, true]) {
    const settings = { ...defaults, [preference]: value };
    assert.equal(repository.normalizeAppearanceSettings(settings)[preference], value !== false);
    assert.equal(adapter.parseAppearanceSettings(JSON.stringify(settings))[preference], value !== false);
  }
});

test('the setting survives persistence and unrelated appearance changes, and can be disabled again', async () => {
  const values = new Map();
  const store = { getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value), flush: async () => {} };
  const adapter = new ArkPreferencesStorageAdapter();
  adapter.store = store;
  const repository = new PreferencesRepository(adapter);
  const resolver = new SettingsDetailActionResolver();
  await repository.updateAppearanceSettings(resolver.buildAppearanceSettingsForAction(action, true, defaults));
  await repository.updateVerticalTabsPresentation(true, false);
  await repository.updateToolbarChromeStyle('split');
  await repository.updateBottomToolbarScrollBehavior('fixed');
  await repository.updateTopImmersionSettings(false, true);
  await repository.updateTabsOverviewPresentation('grid', true);
  await repository.updateAppearanceSettings(resolver.buildAppearanceSettingsForAction(
    'toggle_force_dark_web_content', true, repository.getPreferences().appearance));
  const reopened = new ArkPreferencesStorageAdapter();
  reopened.store = store;
  const restored = await reopened.readAppearanceSettings(defaults);
  assert.equal(restored[preference], true);
  await repository.updateAppearanceSettings(resolver.buildAppearanceSettingsForAction(action, false, restored));
  assert.equal((await reopened.readAppearanceSettings(defaults))[preference], false);
});

test('desktop settings reflect the persisted switch and respect preference write restrictions', () => {
  const { SettingsDetailViewModel } = load('core/settings/SettingsDetailViewModel');
  const model = new SettingsDetailViewModel();
  for (const enabled of [undefined, false, true]) {
    for (const canEdit of [false, true]) {
      for (const desktop of [false, true]) {
        const state = model.buildAppearanceToolbarState('system', { ...defaults, [preference]: enabled },
          canEdit, false, false, '', desktop);
        const row = state.groups.flatMap(group => group.rows).find(item => item.action === action);
        assert.equal(!!row, desktop);
        if (row) {
          assert.equal(row.checked, enabled !== false);
          assert.equal(row.isEnabled, canEdit);
        }
      }
    }
  }
});

test('a double-click closes only its live, closable target, never the tab that replaces it', () => {
  const resolve = policy.resolveBrowserLargeScreenVerticalTabsDoubleClickCloseTarget;
  const tabs = [{ id: 'first', closable: true }, { id: 'protected', closable: false },
    { id: 'neighbor', closable: true }];
  assert.equal(resolve(false, 'first', tabs), '');
  assert.equal(resolve(undefined, 'first', tabs), 'first');
  assert.equal(resolve(true, 'protected', tabs), '');
  assert.equal(resolve(true, 'first', tabs), 'first');
  tabs.shift();
  assert.equal(resolve(true, 'first', tabs), '');
  assert.equal(resolve(true, '', tabs), '');
});

test('selection preserves the native gesture node and expanded background tabs expose close', () => {
  const source = read('app/components/browser/BrowserLargeScreenVerticalTabsSidebar');
  const keyExpression = source.match(/\(tab: BrowserLargeScreenTabProjection\): string =>\s*(`[^`]+`)/)?.[1];
  assert.ok(keyExpression, 'Locate the actual ForEach row identity');
  const { key } = evaluate(`export const key = (tab) => ${keyExpression};`);
  const tab = { id: 'target', title: 'Page', pinned: false, muted: false, closable: true };
  assert.equal(key({ ...tab, active: false }), key({ ...tab, active: true }),
    'The first press must not replace the recognizer before the second press');
  const visibility = source.match(/  private shouldShowClose\([^]*?\n  }/)?.[0];
  const { Sidebar } = evaluate(`export class Sidebar { ${visibility} }`);
  const sidebar = new Sidebar();
  assert.equal(sidebar.shouldShowClose({ ...tab, active: false }), true);
  assert.equal(sidebar.shouldShowClose({ ...tab, closable: false }), false);
  const menu = source.slice(source.indexOf('  private buildTabContextMenu(tab:'),
    source.indexOf('  private buildTabContextMenuItem('));
  assert.match(menu.match(/this\.buildTabContextMenuItem\([^\n]+/)?.[0] ?? '', /tab, 'close',/);
});

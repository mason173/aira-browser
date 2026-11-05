#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

// Execute the production policy and preference methods without native UI initialization.
function ast(relative) {
  const file = path.join(root, relative + '.ets');
  return ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
}

function evaluate(source, globals = {}) {
  const module = { exports: {} };
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
    reportDiagnostics: true
  });
  assert.equal(result.diagnostics.length, 0);
  vm.runInNewContext(result.outputText, { module, exports: module.exports, ...globals });
  return module.exports;
}

function methods(relative, className, names, globals = {}) {
  const tree = ast(relative);
  const declaration = tree.statements.find(node => node.name?.text === className);
  const members = names.map(name => {
    const member = declaration.members.find(node => node.name?.text === name);
    assert.ok(member, `${className}.${name}`);
    return member.getText(tree);
  });
  return evaluate(`export class Subject { ${members.join('\n')} }`, globals).Subject;
}

const repositoryFile = 'data/preferences/PreferencesRepository';
const tree = ast(repositoryFile);
const defaultDeclaration = tree.statements.find(node => ts.isVariableStatement(node) &&
  node.declarationList.declarations.some(item => item.name.text === 'DEFAULT_BROWSER_GENERAL_SETTINGS'));
const defaults = evaluate(defaultDeclaration.getText(tree)).DEFAULT_BROWSER_GENERAL_SETTINGS;
const normalizers = ['normalizeStartupRestorePolicy', 'normalizeTabAutoClosePolicy', 'normalizePrivateTabRestorePolicy'];
const Adapter = methods('data/preferences/ArkPreferencesStorageAdapter', 'ArkPreferencesStorageAdapter',
  ['readGeneralSettings', 'writeGeneralSettings', 'parseGeneralSettings', ...normalizers], {
    DEFAULT_BROWSER_GENERAL_SETTINGS: defaults, GENERAL_SETTINGS_KEY: 'general'
  });
const Repository = methods(repositoryFile, 'PreferencesRepository',
  ['updateGeneralSettings', 'normalizeGeneralSettings', ...normalizers], {
    DEFAULT_BROWSER_GENERAL_SETTINGS: defaults
  });
const models = evaluate(fs.readFileSync(path.join(root, 'common/models/BrowserModels.ets'), 'utf8'));
const ProfileBoundary = methods('core/browser/BrowserProfileBoundaryService', 'BrowserProfileBoundaryService',
  ['buildBoundary', 'toBoundaryInput', 'isSessionEphemeral'], {
    buildBrowserDataBoundary: models.buildBrowserDataBoundary
  });
const Audio = methods('core/browser/BrowserTabSwitchCoordinator', 'BrowserTabSwitchCoordinator',
  ['automaticAudioMuteByTabId', 'audioProfileBoundaryService', 'resolveTabSnapshot', 'setTabMuted',
    'unmuteActiveAutomaticallyMutedTab', 'applyTabAudioPolicy', 'applyTabAudioMuted'],
  { BrowserProfileBoundaryService: ProfileBoundary });
const WebTabs = methods('core/browser/BrowserWebTabsController', 'BrowserWebTabsController', ['setTabAudioMuted']);
const ViewModel = methods('core/settings/SettingsDetailViewModel', 'SettingsDetailViewModel',
  ['buildPrivateModeState', 'switchRow', 'staticRow', 'navigationRow'], { $r: value => value });
const Interaction = methods('core/settings/SettingsDetailInteractionCoordinator', 'SettingsDetailInteractionCoordinator',
  ['commitPrivateModeAutoMuteEnabled', 'commitGeneralSettings', 'ensureDevicePreferenceWriteAllowed']);

function preferencesFixture() {
  let disk;
  let failWrite = false;
  const adapter = new Adapter();
  adapter.getStore = async () => ({
    getSync: (_key, fallback) => disk ?? fallback,
    putSync: (_key, value) => { if (failWrite) throw new Error('storage failed'); disk = value; },
    flushSync() {}
  });
  const repository = new Repository();
  repository.cachedPreferences = { general: { ...defaults } };
  repository.storageAdapter = adapter;
  repository.mergeCachedPreferences = patch => Object.assign(repository.cachedPreferences, patch);
  repository.notifyChanged = () => {};
  const interaction = new Interaction();
  interaction.preferencesRepository = {
    getPreferences: () => repository.cachedPreferences,
    updateGeneralSettings: settings => repository.updateGeneralSettings(settings)
  };
  interaction.profileBoundaryService = { buildBoundary: value => value };
  interaction.privacyEffectPolicy = { decide: () => ({ outcome: 'allow' }) };
  return { adapter, repository, interaction, failWrites: () => { failWrite = true; } };
}

function audioFixture(tabs = [
  { id: 'regular', privacyMode: 'regular', muted: false, lastActiveAt: 123 },
  { id: 'private', privacyMode: 'private', muted: false, lastActiveAt: 456 }
]) {
  const calls = [];
  const policy = new Audio();
  const state = { tabs, activeTabId: 'regular' };
  const webTabs = new WebTabs();
  webTabs.dependencies = {
    resolveWebController: id => ({ setAudioMuted: muted => calls.push({ id, muted }) })
  };
  webTabs.host = { recordRuntimeEvent() {} };
  policy.tabManager = { getTab: (items, id) => items.find(tab => tab.id === id) };
  policy.dependencies = {
    sink: { resolveFacts: () => state },
    resolveWebTabsController: () => webTabs
  };
  policy.applyTabPatch = (id, patch, options) => {
    assert.equal(options.persistTabs, false);
    const tab = tabs.find(item => item.id === id);
    assert.equal(patch.lastActiveAt, tab.lastActiveAt);
    Object.assign(tab, patch);
  };
  return { policy, tabs, calls, state };
}

function volumeFixture(policy) {
  const listeners = [];
  const state = { foreground: true, failRegistration: false };
  const manager = {
    on(type, usage, callback) {
      assert.equal(type, 'streamVolumeChange');
      if (state.failRegistration && usage === 10) throw new Error('registration failed');
      if (listeners.some(item => item.callback === callback && item.usage !== usage)) {
        throw new Error('callback exists for another streamUsage');
      }
      listeners.push({ usage, callback });
    },
    off(type, callback) {
      assert.equal(type, 'streamVolumeChange');
      assert.equal(typeof callback, 'function', 'remove only this service callback');
      for (let i = listeners.length - 1; i >= 0; i--) {
        if (listeners[i].callback === callback) listeners.splice(i, 1);
      }
    }
  };
  const { BrowserVolumeKeyAudioService: Service } = evaluate(fs.readFileSync(
    path.join(root, 'services/web/BrowserVolumeKeyAudioService.ets'), 'utf8'
  ), {
    require(id) {
      if (id === '@kit.AudioKit') return { audio: {
        StreamUsage: { STREAM_USAGE_MUSIC: 1, STREAM_USAGE_MOVIE: 10 },
        getAudioManager: () => ({ getVolumeManager: () => manager })
      } };
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
      throw new Error(`Unexpected dependency: ${id}`);
    }
  });
  const service = new Service({
    isWebPageForeground: () => state.foreground,
    unmuteActiveAutomaticallyMutedTab: () => policy.unmuteActiveAutomaticallyMutedTab()
  });
  return { service, state, listeners, emit(event = {}) {
    const payload = { streamUsage: 1, volume: 6, previousVolume: 5, updateUi: true, ...event };
    for (const { usage, callback } of listeners.slice()) {
      if (usage === payload.streamUsage) callback(payload);
    }
  } };
}

test('new installs and old or malformed preferences default to automatic muting off', () => {
  assert.equal(defaults.privateModeAutoMuteEnabled, false);
  const { adapter } = preferencesFixture();
  for (const value of ['{}', 'null', '{', '{"privateModeAutoMuteEnabled":"true"}']) {
    assert.equal(adapter.parseGeneralSettings(value).privateModeAutoMuteEnabled, false);
  }
});

test('the switch survives storage reload and other general-setting edits, and can be disabled', async () => {
  const { adapter, repository, interaction } = preferencesFixture();
  repository.cachedPreferences.general.enhancedTrackingProtectionEnabled = true;
  await interaction.commitPrivateModeAutoMuteEnabled({}, true);
  assert.equal((await adapter.readGeneralSettings(defaults)).privateModeAutoMuteEnabled, true);
  assert.equal(repository.cachedPreferences.general.enhancedTrackingProtectionEnabled, true);
  const unrelated = { ...defaults, startupRestorePolicy: 'open_home' };
  delete unrelated.privateModeAutoMuteEnabled;
  await repository.updateGeneralSettings(unrelated);
  assert.equal((await adapter.readGeneralSettings(defaults)).privateModeAutoMuteEnabled, true);
  await interaction.commitPrivateModeAutoMuteEnabled({}, false);
  assert.equal((await adapter.readGeneralSettings(defaults)).privateModeAutoMuteEnabled, false);
  assert.equal(repository.cachedPreferences.general.startupRestorePolicy, 'open_home');
});

test('a failed switch save keeps the previously committed preference', async () => {
  const fixture = preferencesFixture();
  fixture.failWrites();
  await assert.rejects(fixture.interaction.commitPrivateModeAutoMuteEnabled({}, true), /storage failed/);
  assert.equal(fixture.repository.cachedPreferences.general.privateModeAutoMuteEnabled, false);
});

test('privacy settings show the saved switch value and its matching action', () => {
  const viewModel = new ViewModel();
  for (const enabled of [false, true]) {
    const state = viewModel.buildPrivateModeState({ ...defaults, privateModeAutoMuteEnabled: enabled }, {}, true);
    const row = state.groups.flatMap(group => group.rows).find(row => row.id === 'private_auto_mute');
    assert.equal(row.kind, 'switch');
    assert.equal(row.checked, enabled);
    assert.equal(row.action, 'toggle_private_mode_auto_mute');
    assert.equal(row.isEnabled, true);
  }
});

for (const enabled of [false, true]) {
  test(`automatic muting ${enabled ? 'enabled' : 'disabled'} respects each tab's own privacy boundary`, () => {
    const { policy, tabs, calls } = audioFixture();
    for (const tab of tabs) policy.applyTabAudioPolicy(tab.id, enabled);
    assert.deepEqual(calls, [
      { id: 'regular', muted: false }, { id: 'private', muted: enabled }
    ]);
  });
}

test('manual unmute survives controller reattachment; the next private webpage uses the default again', () => {
  const { policy, tabs, calls } = audioFixture();
  policy.applyTabAudioPolicy('private', true);
  assert.equal(tabs[1].muted, true);
  policy.setTabMuted('private', false);
  policy.applyTabAudioPolicy('private', true);
  assert.equal(calls.at(-1).muted, false);
  policy.applyTabAudioPolicy('private', true, true);
  assert.equal(calls.at(-1).muted, true);
});

test('turning off the setting clears automatic muting on the next webpage while preserving manual mute', () => {
  const { policy, tabs } = audioFixture();
  policy.applyTabAudioPolicy('private', true);
  policy.setTabMuted('regular', true);
  policy.applyTabAudioPolicy('private', false, true);
  policy.applyTabAudioPolicy('regular', false, true);
  assert.equal(tabs[1].muted, false);
  assert.equal(tabs[0].muted, true);
});

test('restored private tabs apply the setting on first attach and missing tabs cause no audio operation', () => {
  const { policy, calls } = audioFixture();
  policy.applyTabAudioPolicy('private', true);
  policy.applyTabAudioPolicy('missing', true, true);
  assert.deepEqual(calls, [{ id: 'private', muted: true }]);
});

test('a Web-incognito tab must be muted even when its private boundary comes from session data scope', () => {
  const tab = {
    id: 'private-scope', privacyMode: 'regular', dataScope: 'session_ephemeral',
    muted: false, lastActiveAt: 456
  };
  assert.equal(new ProfileBoundary().isSessionEphemeral(tab), true,
    'the existing Web privacy owner classifies this tab as incognito');
  const { policy, calls } = audioFixture([tab]);
  policy.applyTabAudioPolicy(tab.id, true);
  assert.deepEqual(calls, [{ id: tab.id, muted: true }]);
});

test('volume keys unmute only the active automatic mute; the next private page defaults to mute again', () => {
  const f = audioFixture();
  f.state.activeTabId = 'private';
  f.tabs.push({ id: 'background-private', privacyMode: 'private', muted: false, lastActiveAt: 789 });
  f.policy.applyTabAudioPolicy('private', true);
  f.policy.applyTabAudioPolicy('background-private', true);
  const volume = volumeFixture(f.policy);
  volume.service.start();
  volume.emit();
  assert.equal(f.tabs[1].muted, false);
  assert.equal(f.tabs[2].muted, true);
  assert.deepEqual(f.calls.at(-1), { id: 'private', muted: false });
  f.policy.applyTabAudioPolicy('private', true);
  assert.equal(f.tabs[1].muted, false, 'reattachment preserves the user request');
  f.policy.applyTabAudioPolicy('private', true, true);
  assert.equal(f.tabs[1].muted, true, 'a new page still uses the enabled default');
  volume.service.stop();
});

test('programmatic volume changes and changes while the page is hidden do not release automatic mute', () => {
  const f = audioFixture();
  f.state.activeTabId = 'private';
  f.policy.applyTabAudioPolicy('private', true);
  const volume = volumeFixture(f.policy);
  volume.service.start();
  volume.emit({ updateUi: false });
  assert.equal(f.tabs[1].muted, true);
  volume.state.foreground = false;
  volume.emit();
  assert.equal(f.tabs[1].muted, true);
  volume.state.foreground = true;
  volume.emit({ streamUsage: 10, volume: 5, previousVolume: 6 });
  assert.equal(f.tabs[1].muted, false, 'volume-down and movie streams also express a user request');
  volume.service.stop();
});

test('volume keys preserve explicit manual mute in both ordinary and private tabs', () => {
  for (const id of ['regular', 'private']) {
    const f = audioFixture();
    f.state.activeTabId = id;
    f.policy.setTabMuted(id, true);
    const count = f.calls.length;
    const volume = volumeFixture(f.policy);
    volume.service.start();
    volume.emit();
    assert.equal(f.tabs.find(tab => tab.id === id).muted, true);
    assert.equal(f.calls.length, count);
    volume.service.stop();
  }
});

test('volume listener is idempotent, removes its own callbacks, and ignores queued events after stop', () => {
  const f = audioFixture();
  f.state.activeTabId = 'private';
  f.policy.applyTabAudioPolicy('private', true);
  const volume = volumeFixture(f.policy);
  volume.service.start();
  const queued = volume.listeners[0].callback;
  volume.service.start();
  assert.equal(volume.listeners.length, 2);
  volume.service.stop();
  assert.equal(volume.listeners.length, 0);
  queued({ streamUsage: 1, volume: 6, updateUi: true });
  assert.equal(f.tabs[1].muted, true);
  volume.service.start();
  volume.emit();
  assert.equal(f.tabs[1].muted, false);
  volume.service.stop();
});

test('partial volume listener registration is cleaned up and can be retried', () => {
  const f = audioFixture();
  const volume = volumeFixture(f.policy);
  volume.state.failRegistration = true;
  volume.service.start();
  assert.equal(volume.listeners.length, 0);
  volume.state.failRegistration = false;
  volume.service.start();
  assert.equal(volume.listeners.length, 2);
  volume.service.stop();
});

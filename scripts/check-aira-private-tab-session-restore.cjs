#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const probe = new Proxy({}, { get: () => () => {} });
const cache = new Map();

function evaluate(source, filename, globals = {}, requireModule) {
  const result = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    reportDiagnostics: true,
    fileName: filename
  });
  assert.equal((result.diagnostics || []).length, 0, filename);
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports, ...globals,
    require: requireModule || (id => load(path.resolve(path.dirname(filename), `${id}.ets`)))
  }, { filename });
  return module.exports;
}

function load(filename) {
  if (!cache.has(filename)) {
    cache.set(filename, evaluate(fs.readFileSync(filename, 'utf8'), filename));
  }
  return cache.get(filename);
}

// Extract production declarations to exclude unrelated repository domains and
// native ability initialization. No session filtering or flush logic is mocked.
function declarations(relative, names) {
  const filename = path.join(root, relative);
  const source = fs.readFileSync(filename, 'utf8');
  const ast = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  return names.map(name => {
    const declaration = ast.statements.find(node => node.name?.text === name);
    assert.ok(declaration, `Missing production declaration: ${name}`);
    return declaration.getText(ast);
  }).join('\n');
}

const models = load(path.join(root, 'common/models/BrowserModels.ets'));
const { BrowserTabSessionRuntime: runtime } = load(path.join(root, 'app/runtime/BrowserTabSessionRuntime.ets'));
const { BrowserTabSessionRestoreService: RestoreService } = load(
  path.join(root, 'core/browser/BrowserTabSessionRestoreService.ets')
);
const service = new RestoreService();
const { RdbTabSessionRepository: Repository } = evaluate(declarations(
  'data/repositories/BrowserRepositories.ets',
  ['RdbTabSessionRepository', 'filterPersistentTabSessionRecords', 'normalizeTabSessionOrder', 'compareTabSessionOrder']
), 'TabSessionRepository.ts', { ...models, AiraTabSessionProbe: probe });

const abilityFile = path.join(root, 'app/abilities/EntryAbility.ets');
const abilityAst = ts.createSourceFile(abilityFile, fs.readFileSync(abilityFile, 'utf8'), ts.ScriptTarget.Latest, true);
const ability = abilityAst.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'EntryAbility');
assert.ok(ability, 'Missing EntryAbility');
const flush = ability.members.find(node => node.name?.text === 'flushLastKnownTabSession');
assert.ok(flush, 'Missing lifecycle session flush');
const abilitySource = `export class AbilityFlush { currentWindowId = 'window-main'; ${flush.getText(abilityAst)} }`;

function record(id, isPrivate) {
  return {
    id, windowId: 'window-main', profileId: 'profile-main', title: id,
    url: `https://${id}.example`, isActive: isPrivate, isPinned: false,
    lastActiveAt: Date.now(), privacyMode: isPrivate ? 'private' : 'regular',
    dataScope: isPrivate ? 'session_ephemeral' : 'profile_persistent'
  };
}

async function scenario(source, privatePolicy, onlyPrivate = false, disableBeforeFlush = false) {
  let disk = [];
  const database = {
    initialize: async () => {},
    listTabRecords: async () => structuredClone(disk),
    replaceTabRecords: async (_window, records) => { disk = structuredClone(records); }
  };
  const repository = new Repository(database);
  const general = { privateTabRestorePolicy: privatePolicy, tabAutoClosePolicy: 'manual' };
  const records = (onlyPrivate ? [] : [record('regular', false)])
    .concat([record('private-1', true), record('private-2', true)]);
  const options = service.buildOptions(general.tabAutoClosePolicy, general.privateTabRestorePolicy);
  const prepared = service.prepareRecordsForPersistence(records, options).records;
  runtime.remember('window-main', 'profile-main', prepared);
  await repository.replaceTabs(prepared, 'window-main', 'profile-main', {
    allowPrivateTabs: options.persistPrivateTabs
  });
  assert.equal(disk.length, prepared.length, 'ordinary persistence must save permitted records');
  assert.equal(service.prepareRecordsForColdRestore(disk, options).records.length, prepared.length,
    'startup filtering must restore permitted records before the lifecycle write');
  if (disableBeforeFlush) {
    general.privateTabRestorePolicy = 'never_restore';
  }

  // Await the real repository operation launched by the void lifecycle callback.
  const pending = [];
  const sharedRepository = {
    replaceTabs: (...args) => {
      const operation = repository.replaceTabs(...args);
      pending.push(operation);
      return operation;
    }
  };
  const { AbilityFlush } = evaluate(abilitySource, 'AbilityFlush.ts', {
    BrowserTabSessionRuntime: runtime,
    BrowserTabSessionRestoreService: RestoreService,
    sharedTabSessionRepository: sharedRepository,
    sharedPreferencesRepository: { getPreferences: () => ({ general }) },
    AiraTabSessionProbe: probe, hilog: probe, DOMAIN: 0, TAG: 'test'
  });
  new AbilityFlush().flushLastKnownTabSession(source);
  await Promise.all(pending);
  // Cold process: use a new repository, so the runtime cache cannot hide loss.
  const restartedRepository = new Repository(database);
  const expected = disableBeforeFlush ? prepared.filter(tab => tab.privacyMode === 'regular') : prepared;
  // Check disk before cold-restore filtering: revoking consent must remove stale
  // private records from persistent storage, not merely hide them at startup.
  assert.equal(JSON.stringify(disk.map(tab => tab.id)), JSON.stringify(expected.map(tab => tab.id)),
    `${source}: lifecycle writes must respect the current private-restore choice`);
  const restored = service.prepareRecordsForColdRestore(
    await restartedRepository.refresh('window-main', 'profile-main'),
    service.buildOptions(general.tabAutoClosePolicy, general.privateTabRestorePolicy)
  ).records;
  assert.equal(
    JSON.stringify(restored.map(tab => tab.id)),
    JSON.stringify(expected.map(tab => tab.id)),
    `${source}: ${privatePolicy}, onlyPrivate=${onlyPrivate}: restart must preserve every permitted tab`
  );
  console.log(`PASS ${source}: ${privatePolicy}, onlyPrivate=${onlyPrivate}, disabledBeforeFlush=${disableBeforeFlush}`);
}

async function main() {
  let failures = 0;
  for (const source of ['ability-background', 'window-stage-destroy']) {
    for (const policy of ['restore_private_tabs', 'never_restore']) {
      for (const onlyPrivate of [false, true]) {
        try {
          await scenario(source, policy, onlyPrivate);
        } catch (error) {
          failures++;
          console.error(error.message);
        }
      }
    }
    await scenario(source, 'restore_private_tabs', false, true);
    await scenario(source, 'restore_private_tabs', true, true);
  }
  assert.equal(failures, 0, `${failures} private tab lifecycle restore scenarios failed`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });

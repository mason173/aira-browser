#!/usr/bin/env node
'use strict';

// Execute the production classifier and presentation methods. These are application-policy
// checks; transport recovery and native ArkWeb callbacks still need device validation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function load(relative, dependencies = {}) {
  const filename = path.join(sourceRoot, relative);
  const exports = {};
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
      experimentalDecorators: true }
  }).outputText;
  vm.runInNewContext(output, {
    exports,
    Observed: value => value,
    $r: (key, ...values) => values.length ? `${key}:${values.join(',')}` : key,
    require(id) {
      if (Object.hasOwn(dependencies, id)) return dependencies[id];
      throw new Error(`Unexpected runtime dependency: ${id}`);
    }
  }, { filename });
  return exports;
}

const { classifyDownloadV2Failure, classifyHttpDownloadFailure } =
  load('domain/downloadv2/DownloadV2FailureMapper.ets');

// An equal numeric value must not leak from one transport's error namespace to another.
assert.equal(classifyDownloadV2Failure('arkweb', 3).reason, 'storage');
assert.equal(classifyDownloadV2Failure('libcurl', 3).reason, 'unsupported');
assert.equal(classifyDownloadV2Failure('arkweb', 22).shouldPauseForNetwork, true);
assert.equal(classifyDownloadV2Failure('libcurl', 22).code, 'server');
assert.equal(classifyDownloadV2Failure('libcurl', 22).shouldPauseForNetwork, false);
assert.equal(classifyDownloadV2Failure('arkweb', 35).reason, 'certificate');
assert.equal(classifyDownloadV2Failure('libcurl', 35).reason, 'network');
assert.equal(classifyDownloadV2Failure('arkweb', 23).reason, 'network');
assert.equal(classifyDownloadV2Failure('libcurl', 23).reason, 'file_system');
console.log('PASS equal ArkWeb and libcurl codes keep different meanings');

// A network interruption can preserve a browser task. This is not an HLS retry policy.
for (const code of [20, 21, 22]) {
  const failure = classifyDownloadV2Failure('arkweb', code);
  assert.equal(failure.code, 'network');
  assert.equal(failure.retriable, true);
  assert.equal(failure.shouldPauseForNetwork, true);
}
for (const code of [5, 6, 7, 18, 28, 52, 55, 56, 92]) {
  const failure = classifyDownloadV2Failure('libcurl', code);
  assert.equal(failure.code, 'network');
  assert.equal(failure.shouldPauseForNetwork, false);
}
console.log('PASS only browser network interruption suggests a network pause');

// Correcting storage or permissions must allow a deliberate user retry.
for (const code of [2, 3, 31]) {
  const failure = classifyDownloadV2Failure('arkweb', code);
  assert.equal(failure.retriable, true);
  assert.equal(failure.shouldPauseForNetwork, false);
}
assert.equal(classifyDownloadV2Failure('libcurl', 23).reason, 'file_system',
  'A write failure must not falsely claim disk-full or permission-denied');
assert.equal(classifyDownloadV2Failure('libcurl', 60).reason, 'certificate');
assert.equal(classifyDownloadV2Failure('arkweb', 40).retriable, false);
console.log('PASS recoverable local causes retain user retry without guessed diagnosis');

// HTTP metadata is separate and optional. Do not treat it as ArkWeb or CURLcode.
for (const status of [301, 401, 403, 404, 408, 416, 429, 500, 503]) {
  assert.equal(classifyHttpDownloadFailure(status).code, 'server');
  assert.equal(classifyDownloadV2Failure('libcurl', 22, status).code, 'server');
}
for (const invalid of [0, 200, 600, NaN, Infinity, 403.5]) {
  assert.equal(classifyHttpDownloadFailure(invalid).code, 'unknown');
}
assert.equal(classifyDownloadV2Failure('arkweb', 22, 403).code, 'network');
assert.equal(classifyDownloadV2Failure('libcurl', 403).code, 'unknown');
assert.equal(classifyDownloadV2Failure('arkweb', 999).code, 'unknown');
console.log('PASS HTTP statuses require their own namespace and unknown codes stay unknown');

const { DownloadManagerViewModel } = load('core/download/DownloadManagerViewModel.ets', {
  '../../domain/downloadv2/DownloadV2Progress': {},
  '../resources/AppResourceText': { resolveAppResourceText: value => value },
  './DownloadSelectionViewModel': { canSelectDownloadTask: () => true },
  '../../domain/download/DownloadTypes': {},
  // Keep the domain permission decision independent of this presentation test.
  '../../domain/downloadv2/DownloadV2TaskEntity': { canContinueDownloadV2Task: task => task.resumeAvailable },
  './DownloadFileTypeResolver': {}
});
const model = new DownloadManagerViewModel();
const task = {
  status: 'failed', failure: { code: 'network', sourceCode: 20, message: ' Check your connection. ' },
  progress: { speedBytesPerSecond: 0 }, runtime: {}, persistence: {}, resumeAvailable: true
};
assert.equal(model.buildTaskStatusText(task), 'Check your connection.');
assert.equal(model.buildManagementStatusText(task, { statusText: model.buildTaskStatusText(task) }),
  'Check your connection.');
assert.equal(model.buildManagementTrailingText(task), 'app.string.settings_sync_paused');
task.status = 'paused';
assert.equal(model.buildManagementStatusText(task, { statusText: model.buildTaskStatusText(task) }),
  'Check your connection.');
task.failure.message = '';
assert.equal(model.buildTaskStatusText(task), 'app.string.download_status_paused');
assert.equal(model.buildManagementStatusText(task, { statusText: model.buildTaskStatusText(task) }), '');
task.status = 'failed';
task.resumeAvailable = false;
assert.equal(model.buildTaskStatusText(task), 'app.string.download_status_failed_code:20');
task.failure.message = 'Choose another save folder.';
assert.equal(model.buildTaskStatusText(task), 'Choose another save folder.');
assert.equal(model.resolvePrimaryAction({ allowedActions: ['resume', 'cancel'] }), 'resume');
console.log('PASS actionable messages remain visible without changing continue semantics');

for (const status of ['paused', 'queued']) {
  task.status = status; task.failure.message = '';
  for (const [pauseReason, resource] of [['wifi_policy', 'download_network_cellular'], ['network', 'download_network_offline']]) {
    task.runtime.pauseReason = pauseReason; task.persistence.restartReason = undefined;
    const text = `app.string.${resource}`;
    assert.equal(model.buildTaskStatusText(task), text);
    assert.equal(model.buildManagementStatusText(task, { statusText: text }), text);
  }
  task.persistence.restartReason = 'network_unknown';
  assert.equal(model.buildTaskStatusText(task), 'app.string.download_network_unknown');
}
task.status = 'paused'; task.runtime.pauseReason = 'user';
assert.equal(model.buildTaskStatusText(task), 'app.string.download_status_paused');
assert.equal(model.buildManagementTrailingText(task), 'app.string.settings_sync_paused');
assert.equal(model.resolvePrimaryAction({ allowedActions: ['resume', 'cancel'] }), 'resume');
console.log('PASS queued and paused network conditions are visible without changing actions');

task.status = 'running'; task.persistence.completionState = 'finalizing';
assert.equal(model.buildTaskStatusText(task), 'app.string.download_status_finalizing');
assert.equal(model.buildManagementStatusText(task, { statusText: model.buildTaskStatusText(task) }), 'app.string.download_status_finalizing');
assert.equal(model.buildManagementTrailingText(task), '');
console.log('PASS file finalization has an explicit saving presentation');

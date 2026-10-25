#!/usr/bin/env node
'use strict';
// Execute the production projection, persistence and native-adapter code without a device.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const resources = new Map(JSON.parse(fs.readFileSync(path.join(root,
  '../resources/base/element/string.json'), 'utf8')).string.map(item => [item.name, item.value]));
const cache = new Map();
const log = { info() {}, warn() {}, error() {} };
function load(relative) {
  const filename = path.resolve(root, relative);
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true }
  }).outputText, {
    exports, Observed: value => value, setInterval: () => 1, clearInterval() {},
    $r: (key, ...args) => ({ key, args }),
    require(id) {
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: log };
      if (id.startsWith('@kit.')) return {};
      if (id.endsWith('/AppRuntimeContext')) return {};
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: ({ key, args }) => {
        let index = 0;
        return (resources.get(key.replace('app.string.', '')) || key).replace(/%[sd]/g, () => args[index++]);
      } };
      if (id.endsWith('/BrowserModels')) return {
        normalizeBrowserSessionPrivacyMode: value => value || 'normal',
        normalizeBrowserProfileId: value => value || 'main',
        normalizeBrowserDataScope: value => value || 'persistent'
      };
      if (id.endsWith('/RecentlyClosedRecordTimeViewModel')) return {
        RecentlyClosedRecordTimeViewModel: class { formatClosedTime() { return 'now'; } }
      };
      if (id.endsWith('/RuntimeDiagnosticModels')) return {};
      if (id.endsWith('/DownloadRuntimeService')) return {};
      return load(path.resolve(path.dirname(filename), id + '.ets'));
    }
  }, { filename });
  return exports;
}
const progress = load('domain/downloadv2/DownloadV2Progress.ets');
const entity = load('domain/downloadv2/DownloadV2TaskEntity.ets');
const { DownloadManagerViewModel } = load('core/download/DownloadManagerViewModel.ets');
const { DownloadRecentRecordsViewModel } = load('core/download/DownloadRecentRecordsViewModel.ets');
const { DownloadToolbarIndicatorViewModel } = load('core/download/DownloadToolbarIndicatorViewModel.ets');
const { DownloadV2SystemNotificationService } = load('services/downloadv2/DownloadV2SystemNotificationService.ets');
const { ArkDownloadV2RecordStore } = load('data/downloadv2/DownloadV2RecordStore.ets');
const { InMemoryDownloadV2Repository } = load('data/downloadv2/DownloadV2Repository.ets');
const { LibcurlDownloadAdapter } = load('platform/download/LibcurlDownloadAdapter.ets');
const task = (patch = {}) => entity.createDownloadV2TaskEntity({
  guid: 'hls', profileId: 'main', privacyMode: 'normal', dataScope: 'persistent', status: 'running',
  suggestedFileName: 'video.ts', request: { url: 'https://example.test/video.m3u8', method: 'GET' },
  progress: { totalBytes: 0, receivedBytes: 400, speedBytesPerSecond: 20,
    progressFraction: 0.45, estimatedTotalBytes: 1500, ...patch }
});

test('HLS percentage follows segment progress independently of changing size estimates', () => {
  const sample = task();
  assert.equal(progress.resolveDownloadProgressPercent(sample.progress, sample.status), 45);
  for (const estimate of [800, 1500, 5000]) {
    sample.progress.estimatedTotalBytes = estimate;
    assert.equal(progress.resolveDownloadProgressPercent(sample.progress, sample.status), 45);
  }
  sample.progress.progressFraction = 1;
  assert.equal(progress.resolveDownloadProgressPercent(sample.progress, 'running'), 99);
  assert.equal(progress.resolveDownloadProgressPercent(sample.progress, 'failed'), 99);
  assert.equal(progress.resolveDownloadProgressPercent(sample.progress, 'completed'), 100);
  assert.equal(progress.resolveDownloadProgressPercent(task({ progressFraction: -1, totalBytes: 1000 }).progress,
    'running'), 40, 'ordinary HTTP keeps its byte-based progress');
  assert.equal(progress.resolveDownloadProgressFraction(task({ progressFraction: -1 }).progress), -1);
});

test('list, recent popup, toolbar and notification share HLS percentage and estimated labeling', () => {
  const sample = task();
  const list = new DownloadManagerViewModel();
  assert.equal(list.buildTaskProgressValue(sample), 45);
  assert.match(list.buildTaskProgressText(sample), /预计/);
  const recent = new DownloadRecentRecordsViewModel().buildRecord(sample, Date.now());
  assert.equal(recent.progressValue, 45);
  assert.equal(recent.progressKnown, true);
  assert.match(recent.subtitle, /预计/);
  assert.equal(new DownloadToolbarIndicatorViewModel().buildState([sample]).progressValue, 45);
  const service = new DownloadV2SystemNotificationService();
  const notification = service.buildAggregateProgress([sample]);
  assert.equal(notification.progressPercent, 45);
  assert.equal(notification.progressDeterminate, true);
  assert.match(service.buildProgressAdditionalText(notification), /预计/);
  sample.status = 'completed';
  sample.progress = { receivedBytes: 1600, totalBytes: 1600, speedBytesPerSecond: 0,
    progressFraction: 1, estimatedTotalBytes: 0 };
  assert.doesNotMatch(list.buildTaskProgressText(sample), /预计/);
});

test('progress and estimates survive persistence, while old records remain unknown', () => {
  const store = new ArkDownloadV2RecordStore();
  const sample = task();
  const repository = new InMemoryDownloadV2Repository();
  repository.upsert(sample);
  repository.patch({ guid: sample.guid }, { progress: { speedBytesPerSecond: 0 } });
  assert.equal(repository.findOne({ guid: sample.guid }).progress.progressFraction, 0.45);
  assert.equal(repository.list()[0].progress.estimatedTotalBytes, 1500);
  const saved = JSON.parse(JSON.stringify(store.toPersistedRecord(sample)));
  const restored = store.toTaskEntity(saved);
  assert.equal(restored.progress.progressFraction, 0.45);
  assert.equal(restored.progress.estimatedTotalBytes, 1500);
  const paused = entity.patchDownloadV2TaskEntity(restored, { status: 'paused' });
  assert.equal(paused.progress.progressFraction, 0.45);
  delete saved.progress.progressFraction;
  delete saved.progress.estimatedTotalBytes;
  assert.equal(store.toTaskEntity(saved).progress.progressFraction, -1);
  saved.progress.progressFraction = NaN;
  saved.progress.estimatedTotalBytes = Infinity;
  assert.equal(store.toTaskEntity(saved).progress.progressFraction, -1);
  assert.equal(store.toTaskEntity(saved).progress.estimatedTotalBytes, 0);
});

test('adapter publishes progress-only changes without treating the manifest length as video size', () => {
  const adapter = new LibcurlDownloadAdapter();
  const events = [];
  adapter.setCallbacks({ onDownloadEvent: event => events.push(event) });
  let snapshot = { state: 'running', receivedBytes: 400, totalBytes: 0, speedBytesPerSecond: 20,
    progressFraction: 0.45, estimatedTotalBytes: 1500, errorCode: 0, errorMessage: '', fileExtension: '.ts' };
  adapter.nativeModule = { getSnapshot: () => snapshot };
  const binding = { guid: 'hls', handle: 1, hls: true, lastState: 'RUNNING', lastReceivedBytes: 400,
    snapshot: { guid: 'hls', suggestedFileName: 'video.ts', url: 'https://example.test/video.m3u8',
      state: 'RUNNING', totalBytes: 26000, receivedBytes: 400 } };
  adapter.pollBinding(binding);
  assert.equal(events[0].snapshot.totalBytes, 0);
  assert.equal(events[0].snapshot.progressFraction, 0.45);
  assert.equal(events[0].snapshot.estimatedTotalBytes, 1500);
  adapter.pollBinding(binding);
  assert.equal(events.length, 1, 'unchanged snapshots are not published repeatedly');
  snapshot = { ...snapshot, progressFraction: 0.5, estimatedTotalBytes: 1600 };
  adapter.pollBinding(binding);
  assert.equal(events.length, 2);
  assert.equal(events[1].snapshot.progressFraction, 0.5);
});

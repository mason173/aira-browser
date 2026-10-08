#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const { analyze } = require('./analyze-aira-sync-diagnostics.cjs');
const ts = require('./lib/deveco-typescript.cjs');

function probe(enabled = true) {
  let now = 1000;
  let wall = 1700000000000;
  let seq = 0;
  const timers = new Map();
  const records = [];
  const module = { exports: {} };
  const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/common/debug/AiraSyncJankProbe.ets');
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  class FakeDate extends Date { static now() { return wall; } }
  vm.runInNewContext(code, { module, exports: module.exports, Date: FakeDate,
    setTimeout(fn, delay) { const id = ++seq; timers.set(id, { fn, at: now + delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    require(name) {
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info(_d, _t, _f, _p, json) { records.push(JSON.parse(json)); } } };
      if (name === '@kit.BasicServicesKit') return { systemDateTime: { TimeType: { ACTIVE: 1 }, getUptime: () => now } };
      if (name.endsWith('/AiraSyncDiagnostics')) return { AIRA_ENABLE_SYNC_DIAGNOSTICS: enabled };
      if (name.endsWith('/BrowsingActivitySignal')) return { sharedBrowsingActivitySignal: { isBrowsingRecently: () => true } };
      throw new Error(name);
    }
  });
  return { api: module.exports.AiraSyncJankProbe, records, timers,
    work(ms) { now += ms; wall += ms; },
    changeWall(ms) { wall += ms; },
    tick() { const due = [...timers].filter(([, t]) => t.at <= now); for (const [id, t] of due) { timers.delete(id); t.fn(); } }
  };
}

test('ordinary builds emit no diagnostics and allocate no timers', async () => {
  const p = probe(false);
  p.api.startCapture('cold_start');
  const run = p.api.beginRun('manual', 'huawei_space', 'sync');
  assert.equal(await p.api.measure('test', async () => 42), 42);
  p.api.mark('test'); p.api.endRun(run);
  assert.equal(p.records.length, 0);
  assert.equal(p.timers.size, 0);
});

test('a real blocked interval is attributed even when the run ends before the timer resumes', () => {
  const p = probe();
  const run = p.api.beginRun('automatic', 'huawei_space', 'sync');
  const span = p.api.beginStage('bookmark_merge');
  p.work(180); p.api.endStage(span); p.api.endRun(run); p.tick();
  const report = analyze(p.records);
  assert.equal(report.maxLateMs, 130);
  assert.equal(report.lags[0].browsing, true);
  assert.equal(report.lags[0].overlapping[0].stage, 'bookmark_merge');
  assert.match(report.lags[0].runs[0], /source=automatic/);
});

test('a long asynchronous cloud wait does not count as main-thread blocking', () => {
  const p = probe();
  p.api.beginRun('manual', 'huawei_space', 'sync');
  const span = p.api.beginStage('cloud_sync');
  for (let i = 0; i < 100; i++) { p.work(50); p.tick(); }
  p.api.endStage(span);
  const report = analyze(p.records);
  assert.equal(report.lags.length, 0);
  assert.equal(report.slowestStages[0].durationMs, 5000);
  assert.equal(report.samplesPresent, true);
});

test('wall-clock corrections do not create timer lag and background cancels sampling', () => {
  const p = probe();
  p.api.startCapture('foreground');
  p.changeWall(3600000); p.work(50); p.tick();
  assert.equal(analyze(p.records).lags.length, 0);
  p.api.stopCapture('background');
  p.work(300000); p.tick();
  assert.equal(p.timers.size, 0);
  assert.equal(analyze(p.records).lags.length, 0);
});

test('capture is bounded, exception-safe spans close, and detailed log floods are counted', async () => {
  const p = probe(); p.api.startCapture('cold_start');
  await assert.rejects(p.api.measure('failed_stage', async () => { throw new Error('original'); }), /original/);
  for (let i = 0; i < 1000; i++) p.api.markExtra('record', 'count=1');
  assert.ok(p.records.length <= 48);
  p.work(1000); p.tick();
  assert.ok(analyze(p.records).suppressed > 900);
  p.work(180000); p.tick();
  assert.equal(p.timers.size, 0);
  assert.match(p.records.at(-1).detail, /reason=time_limit/);
});

test('probe never prints private text or numeric account ids from existing extra fields', () => {
  const p = probe(); p.api.startCapture('cold_start');
  p.api.markExtra('payload', 'uid=123456789 token=secret url=https://private.invalid title=private commit=123 count=4 provider=huawei_space');
  const detail = p.records.at(-1).detail;
  assert.equal(detail, 'count=4 provider=huawei_space');
  const timings = 'unpackMs=1 decodeMs=2 mergeMs=3 compareMs=4 projectionMs=5 encodeMs=6 totalMs=21 visits=1000';
  p.api.markExtra('history_replica_full_compute', `${timings} uid=123456789`);
  assert.equal(p.records.at(-1).detail, timings);
});

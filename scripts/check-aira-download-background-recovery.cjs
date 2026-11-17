#!/usr/bin/env node
'use strict';
// Execute the production notification service with a controlled clock and platform boundary.
// Device background-task admission and suspension remain part of on-device QA.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function environment(options = {}) {
  let now = 10000;
  let timerId = 0;
  let activeStartCalls = 0;
  const timers = new Map();
  const calls = { starts: [], stops: [], published: [], canceled: [], permissionRequests: 0, maxConcurrentStarts: 0 };
  const context = { abilityInfo: { bundleName: 'org.aira.browser', name: 'EntryAbility' } };
  const platform = {
    hasContext: options.hasContext !== false,
    notificationsEnabled: options.notificationsEnabled !== false,
    start: options.start || (async () => ({ notificationId: 71, continuousTaskId: 72 })),
    wantAgent: options.wantAgent || (async () => ({})),
    templateSupport: options.templateSupport || (async () => false)
  };
  const cache = new Map();
  function load(filename) {
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} };
    cache.set(filename, module);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    vm.runInNewContext(code, {
      module, exports: module.exports, Date: { now: () => now },
      $r: (name, ...args) => `${name}:${args.join(',')}`,
      setTimeout(fn, delay) { const id = ++timerId; timers.set(id, { fn, at: now + delay }); return id; },
      clearTimeout(id) { timers.delete(id); },
      require(id) {
        if (id === '@kit.AbilityKit') return { wantAgent: {
          OperationType: { START_ABILITY: 0 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 },
          async getWantAgent() { return platform.wantAgent(); }
        } };
        if (id === '@kit.BackgroundTasksKit') return { backgroundTaskManager: {
          async startBackgroundRunning(...args) {
            calls.starts.push({ at: now, args });
            activeStartCalls++;
            calls.maxConcurrentStarts = Math.max(calls.maxConcurrentStarts, activeStartCalls);
            try { return await platform.start(); } finally { activeStartCalls--; }
          },
          async stopBackgroundRunning(...args) { calls.stops.push(args); }
        } };
        if (id === '@kit.NotificationKit') return { notificationManager: {
          SlotType: { LIVE_VIEW: 1, CONTENT_INFORMATION: 2 },
          ContentType: { NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW: 1, NOTIFICATION_CONTENT_BASIC_TEXT: 2 },
          async isNotificationEnabled() { return platform.notificationsEnabled; },
          isNotificationEnabledSync() { return platform.notificationsEnabled; },
          async requestEnableNotification() {
            calls.permissionRequests++;
            if (!platform.notificationsEnabled) throw { code: 1600020, message: 'denied' };
          },
          async isSupportTemplate() { return platform.templateSupport(); },
          async publish(request) { calls.published.push(request); },
          async cancel(id) { calls.canceled.push(id); }
        } };
        if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
        if (id.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: {
          hasUIAbilityContext: () => platform.hasContext,
          getUIAbilityContext: () => context
        } };
        if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
        if (id.startsWith('.')) return load(path.resolve(path.dirname(filename), `${id}.ets`));
        throw new Error(`Unexpected dependency ${id}`);
      }
    }, { filename });
    return module.exports;
  }
  const { DownloadV2SystemNotificationService } = load(path.join(sourceRoot,
    'services/downloadv2/DownloadV2SystemNotificationService.ets'));
  const service = new DownloadV2SystemNotificationService();
  async function drain() {
    for (let index = 0; index < 100 && service.reconcileRunning; index++) await Promise.resolve();
    assert.equal(service.reconcileRunning, false, 'reconcile did not settle');
  }
  async function advance(ms) {
    const target = now + ms;
    while (true) {
      const entry = [...timers.entries()].sort((left, right) => left[1].at - right[1].at)[0];
      if (!entry || entry[1].at > target) break;
      now = entry[1].at;
      timers.delete(entry[0]);
      entry[1].fn();
      await drain();
    }
    now = target;
  }
  return { service, calls, platform, timers, drain, advance, now: () => now };
}

function task(guid, overrides = {}) {
  return { guid, status: 'running', privacyMode: 'regular', suggestedFileName: `${guid}.bin`,
    persistence: {},
    progress: { totalBytes: 1000, receivedBytes: 200, speedBytesPerSecond: 100, progressFraction: 0.2 },
    timing: { updatedAt: 10000 }, ...overrides };
}

test('saving publishes a distinct progress phase immediately and retains background work until completion', async () => {
  const env = environment();
  const received = { totalBytes: 1000, receivedBytes: 1000, speedBytesPerSecond: 0, progressFraction: 1 };
  env.service.handleTaskChanged(task('saving', { progress: received }));
  await env.drain(); const published = env.calls.published.length;
  env.service.handleTaskChanged(task('saving', { progress: received, persistence: { completionState: 'finalizing' } }), 'running');
  await env.drain();
  assert.equal(env.calls.published.length, published + 1, 'phase transition bypasses progress throttle');
  assert.ok(JSON.stringify(env.calls.published.at(-1)).includes('download_status_finalizing'));
  assert.equal(env.calls.stops.length, 0);
  assert.equal(env.calls.published.filter(x => x.id >= 340000).length, 0, 'no premature completion notification');
  env.service.handleTaskChanged(task('saving', { status: 'completed', progress: received, persistence: { completionState: 'available' } }), 'running');
  await env.drain();
  assert.equal(env.calls.stops.length, 1);
  assert.equal(env.calls.published.filter(x => x.id >= 340000).length, 1);
});

test('a failed background start retries without a new progress tick and removes the fallback on success', async () => {
  let attempts = 0;
  const env = environment({ start: async () => {
    if (++attempts === 1) throw { code: 9800002, message: 'temporarily unavailable' };
    return { notificationId: 71, continuousTaskId: 72 };
  } });
  env.service.handleTaskChanged(task('one'));
  await env.drain();
  assert.equal(env.calls.starts.length, 1);
  assert.equal(env.calls.published[0].id, 240000);
  assert.equal(env.calls.published[0].notificationSlotType, 2);
  for (let tick = 0; tick < 4; tick++) {
    await env.advance(250);
    env.service.handleTaskChanged(task('one'), 'running');
    await env.drain();
  }
  assert.equal(env.calls.starts.length, 1, 'progress events must not bypass retry delay');
  await env.advance(1000);
  assert.equal(env.calls.starts.length, 2);
  assert.deepEqual(env.calls.canceled, [240000]);
  assert.equal(env.calls.published.at(-1).id, 71);
  assert.equal(env.calls.published.at(-1).notificationSlotType, 1);
  assert.equal(env.timers.size, 0);
  env.service.handleTaskChanged(task('one', { status: 'completed' }), 'running');
  await env.drain();
  assert.equal(env.calls.stops.length, 1);
  assert.equal(env.calls.stops[0][1], 72);
  await env.advance(60000);
  assert.equal(env.calls.starts.length, 2);
});

test('repeated failures back off to a bounded interval and ending the batch clears the retry', async () => {
  const env = environment({ start: async () => { throw { code: 9800002 }; } });
  env.service.handleTaskChanged(task('one'));
  await env.drain();
  for (const expectedDelay of [2000, 4000, 8000, 16000, 30000, 30000]) {
    assert.equal(env.timers.size, 1);
    assert.equal([...env.timers.values()][0].at - env.now(), expectedDelay);
    await env.advance(expectedDelay);
  }
  const attempts = env.calls.starts.length;
  env.service.handleTaskRemoved('one');
  await env.drain();
  assert.equal(env.timers.size, 0);
  assert.deepEqual(env.calls.canceled, [240000]);
  assert.equal(env.calls.stops.length, 0, 'a rejected start has no continuous task to stop');
  await env.advance(60000);
  assert.equal(env.calls.starts.length, attempts);
  env.service.handleTaskChanged(task('next-batch'));
  await env.drain();
  assert.equal([...env.timers.values()][0].at - env.now(), 2000, 'a new batch resets backoff');
});

test('concurrent task changes share one start and the last task leaving stops it', async () => {
  let release;
  const env = environment({ start: () => new Promise(resolve => { release = resolve; }) });
  env.service.handleTaskChanged(task('first'));
  for (let tick = 0; tick < 15; tick++) await Promise.resolve();
  assert.equal(env.calls.starts.length, 1);
  env.service.handleTaskChanged(task('second'));
  env.service.handleTaskChanged(task('first'), 'running');
  release({ notificationId: 71, continuousTaskId: 72 });
  await env.drain();
  assert.equal(env.calls.starts.length, 1);
  assert.equal(env.calls.maxConcurrentStarts, 1);
  env.service.handleTaskChanged(task('first', { status: 'paused' }), 'running');
  await env.drain();
  assert.equal(env.calls.stops.length, 0);
  env.service.handleTaskRemoved('second');
  await env.drain();
  assert.equal(env.calls.stops.length, 1);
});

test('a task becoming private during admission never publishes its stale progress', async () => {
  let release;
  const env = environment({ start: () => new Promise(resolve => { release = resolve; }) });
  env.service.handleTaskChanged(task('sensitive'));
  for (let tick = 0; tick < 15; tick++) await Promise.resolve();
  env.service.handleTaskChanged(task('sensitive', { privacyMode: 'private' }), 'running');
  release({ notificationId: 71, continuousTaskId: 72 });
  await env.drain();
  assert.equal(env.calls.published.length, 0);
  assert.equal(env.calls.stops.length, 1);
  assert.equal(env.timers.size, 0);
  env.service.handleTaskChanged(task('private-only', { privacyMode: 'private' }));
  await env.drain();
  assert.equal(env.calls.starts.length, 1);
});

test('removing the last task during progress WantAgent creation skips the stale publish and stops background work', async () => {
  let release, started, wantCalls = 0;
  const blocked = new Promise(resolve => { release = resolve; });
  const building = new Promise(resolve => { started = resolve; });
  const env = environment({ wantAgent: async () => {
    if (++wantCalls === 2) { started(); await blocked; }
    return {};
  } });
  env.service.handleTaskChanged(task('removed'));
  await building;
  env.service.handleTaskRemoved('removed');
  release();
  await env.drain();
  assert.equal(env.calls.published.length, 0);
  assert.equal(env.calls.stops.length, 1);
});

test('a task becoming private during template lookup never publishes its already-built public content', async () => {
  let release, started;
  const blocked = new Promise(resolve => { release = resolve; });
  const building = new Promise(resolve => { started = resolve; });
  const env = environment({ templateSupport: async () => { started(); await blocked; return true; } });
  env.service.handleTaskChanged(task('sensitive'));
  await building;
  env.service.handleTaskChanged(task('sensitive', { privacyMode: 'private' }), 'running');
  release();
  await env.drain();
  assert.equal(env.calls.published.length, 0);
  assert.equal(env.calls.stops.length, 1);
});

test('removing a member while building an aggregate publishes only the rebuilt remaining task', async () => {
  let release, started, wantCalls = 0;
  const blocked = new Promise(resolve => { release = resolve; });
  const building = new Promise(resolve => { started = resolve; });
  const env = environment({ wantAgent: async () => {
    if (++wantCalls === 2) { started(); await blocked; }
    return {};
  } });
  env.service.handleTaskChanged(task('first'));
  env.service.handleTaskChanged(task('remaining'));
  await building;
  env.service.handleTaskRemoved('first');
  release();
  await env.drain();
  assert.equal(env.calls.published.length, 1);
  assert.equal(env.calls.published[0].content.systemLiveView.text, 'remaining.bin');
  assert.equal(env.calls.starts.length, 1);
  assert.equal(env.calls.stops.length, 0);
});

test('denied notification permission does not discard running tasks or prevent background recovery', async () => {
  let attempts = 0;
  const env = environment({ notificationsEnabled: false, start: async () => {
    if (++attempts === 1) throw { code: 9800002 };
    return { notificationId: 71, continuousTaskId: 72 };
  } });
  const running = task('one');
  env.service.handleTaskChanged(running);
  await env.drain();
  assert.equal(running.status, 'running');
  assert.equal(env.calls.permissionRequests, 1);
  await env.advance(2000);
  assert.equal(env.calls.starts.length, 2);
  assert.equal(env.calls.permissionRequests, 1, 'permission denial must not trigger repeated prompts');
  assert.equal(env.calls.published.length, 0);
  assert.equal(running.status, 'running');
  env.service.handleTaskRemoved('one');
  await env.drain();
  assert.equal(env.calls.stops.length, 1);
});

test('temporarily missing ability context recovers and queued tasks do not acquire background ownership', async () => {
  const env = environment({ hasContext: false });
  env.service.handleTaskChanged(task('queued', { status: 'queued' }));
  await env.drain();
  assert.equal(env.timers.size, 0);
  env.service.handleTaskChanged(task('one'));
  await env.drain();
  assert.equal(env.calls.starts.length, 0);
  assert.equal(env.timers.size, 1);
  env.platform.hasContext = true;
  await env.advance(2000);
  assert.equal(env.calls.starts.length, 1);
  env.service.handleTaskRemoved('one');
  await env.drain();
  assert.equal(env.calls.stops.length, 1);
});

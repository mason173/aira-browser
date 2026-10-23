// Exercises the production health reader and logger without a device or live stream.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
let now = 10000;
const lines = [];
function load(relative) {
  const filename = path.join(root, relative);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, $r: key => key,
    Date: { now: () => now },
    require(specifier) {
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { info: (...args) => lines.push(args.at(-1)) } };
      if (specifier.endsWith('/WebVideoRuntimeProtocol')) return load('services/video/WebVideoRuntimeProtocol.ets');
      if (specifier.endsWith('/WebVideoPlaybackDiagnosticsService')) return load('services/video/WebVideoPlaybackDiagnosticsService.ets');
      if (specifier.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
      throw new Error(`Unexpected dependency: ${specifier}`);
    }
  }, { filename });
  return module.exports;
}
const { WEB_VIDEO_PLAYBACK_HEALTH_SCRIPT: script, WebVideoPlaybackDiagnosticsService } =
  load('services/video/WebVideoPlaybackDiagnosticsService.ets');
const read = vm.runInNewContext(`${script}\nreadAiraVideoPlaybackHealth`);
function ranges(values) {
  return { length: values.length, start: i => values[i][0], end: i => values[i][1] };
}
const video = Object.freeze({
  currentTime: 10, playbackRate: 1.2, readyState: 2, networkState: 2, duration: Infinity,
  paused: false, seeking: false, ownerDocument: { hidden: false },
  buffered: ranges([[0, 5], [9, 10.1], [12, 25]]), seekable: ranges([[5, 18]]),
  getVideoPlaybackQuality: () => ({ droppedVideoFrames: 3, totalVideoFrames: 90 }),
  __airaVideoAssistantLivePresentation: { active: true, diagnosticSeeks: 4, diagnosticPlays: 2,
    diagnosticStyles: 3, diagnosticReplacements: 1 }
});
const health = read(video);
assert.equal(health.aheadMs, 100, 'a future range must not hide starvation at the current position');
assert.equal(health.nextBufferMs, 2000);
assert.equal(health.liveLagMs, 8000);
assert.equal(health.live, true);
assert.equal(health.rate, 1.2);
assert.equal(health.dropped, 3);
assert.equal(health.airaSeeks, 4);
assert.equal(health.airaReplacements, 1);
assert.equal(read({ ...video, buffered: ranges([[12, 25]]) }).aheadMs, 0);
assert.equal(read({ ...video, seekable: ranges([]) }).liveLagMs, -1);
assert.doesNotThrow(() => read({ ...video, get buffered() { throw Error('MSE detached'); } }));
assert.doesNotMatch(script, /setTimeout|setInterval|fetch\(|\.play\(|\.pause\(/);

const logger = new WebVideoPlaybackDiagnosticsService();
const payload = (name, metrics = health, id = 'private-runtime?token=SECRET') => JSON.stringify({
  frameRuntimeId: 'private-frame?token=SECRET',
  videoEvent: { eventName: name, runtimeId: id, source: 'https://private.invalid/?token=SECRET',
    playbackHealth: metrics }
});
logger.observe('tab', payload('waiting'), false, 'frame_proxy');
now += 1250;
logger.observe('tab', payload('playing'), false, 'frame_proxy');
assert.match(lines.at(-1), /waits=1 recoveredMs=1250/);
assert.match(lines[0], /takeover=true.*aheadMs=100/);
assert.doesNotMatch(lines.join('\n'), /SECRET|private|token|https/);

let before = lines.length;
logger.observe('tab', payload('timeupdate'), false, 'frame_proxy');
assert.equal(lines.length, before, 'heartbeat must be throttled');
now += 5000;
logger.observe('tab', payload('timeupdate'), false, 'frame_proxy');
assert.equal(lines.length, before + 1);
now += 5000;
logger.observe('tab', payload('timeupdate', { ...health, takeover: false }), false, 'frame_proxy');
assert.equal(lines.length, before + 1, 'no idle telemetry heartbeat outside takeover');

before = lines.length;
for (let i = 0; i < 100; i++) logger.observe('tab', payload('waiting'), false, 'frame_proxy');
assert.equal(lines.length, before + 8, 'event storms must have a hard per-target rate limit');
now += 1000;
logger.observe('tab', payload('playing'), false, 'frame_proxy');
assert.match(lines.at(-1), /waits=101 recoveredMs=1000 suppressed=92/);
before = lines.length;
logger.observe('tab', payload('waiting'), true, 'frame_proxy');
logger.observe('tab', payload('waiting'), true, 'document_direct');
assert.equal(lines.length, before, 'private tabs never produce diagnostics');
logger.observe('tab', payload('playing'), false, 'frame_proxy');
assert.match(lines.at(-1), /waits=0 recoveredMs=-1/, 'private transition clears prior state');

logger.observe('tab', payload('error', { ...health, aheadMs: 'SECRET', rate: 'SECRET' }), false, 'document_direct');
assert.match(lines.at(-1), /aheadMs=-1.*rate=-1/);
before = lines.length;
logger.observe('tab', payload('SECRET'), false, 'document_direct');
logger.observe('tab', '{bad json', false, 'document_direct');
logger.observe('tab', payload('waiting', null), false, 'document_direct');
assert.equal(lines.length, before);
logger.clearTab('tab');
now += 1000;
logger.observe('tab', payload('playing'), false, 'frame_proxy');
assert.match(lines.at(-1), /waits=0 recoveredMs=-1/);
assert.doesNotMatch(lines.join('\n'), /SECRET|private|token|https/);

const { MediaVideoFrameProbeScript } = load('features/mediaDiscovery/MediaVideoFrameProbeScript.ets');
const frame = new MediaVideoFrameProbeScript().buildDocumentStartScriptItem().script;
new vm.Script(frame);
assert.ok(frame.includes(script), 'child frames must use the same health reader');
assert.match(frame, /playbackHealth: readAiraVideoPlaybackHealth\(video\)/);
assert.match(frame, /diagnosticSampleAt.*5000/);
const hosted = fs.readFileSync(path.join(root, 'core/web/HostedWebNode.ets'), 'utf8');
assert.match(hosted, /playbackHealth: readAiraVideoPlaybackHealth\(node\)/);
const observation = fs.readFileSync(path.join(root,
  'core/browser/media/BrowserMediaRuntimeObservationApplicationCoordinator.ets'), 'utf8');
assert.match(observation, /acceptsProbeChannel[\s\S]*hasReadyFrame[\s\S]*playbackDiagnostics.observe\(tabId/,
  'child diagnostics must be behind the document channel and ready-frame checks');
console.log('Video playback diagnostics passed (ranges, recovery timing, throttling, privacy, and probe wiring).');

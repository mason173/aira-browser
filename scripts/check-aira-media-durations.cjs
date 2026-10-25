#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
function load(relative) {
  const filename = path.resolve(root, relative);
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(code, { exports, $r: key => key, console, require(name) {
    if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
    if (name.startsWith('@')) return {};
    return load(path.resolve(path.dirname(filename), name + '.ets'));
  } }, { filename });
  return exports;
}
const { MediaManifestProcessingService } = load('services/media/MediaManifestProcessingService.ets');
const { MediaCandidateValidationService } = load('services/media/MediaCandidateValidationService.ets');
const { MediaCandidateProjector } = load('services/media/MediaCandidateProjector.ets');
const { MediaSignalClassificationService } = load('services/media/MediaSignalClassificationService.ets');
const { MediaDiscoveryStore } = load('services/media/MediaDiscoveryStore.ets');
const parser = new MediaManifestProcessingService({});
const validator = new MediaCandidateValidationService(parser, {}, {});
const projector = new MediaCandidateProjector();
const mediaUrl = 'https://cdn.example.test/movie/index.m3u8';
function playlist(count, duration, end = true, tags = '') {
  return '#EXTM3U\n#EXT-X-TARGETDURATION:10\n' + tags +
    Array.from({ length: count }, (_, i) => `#EXTINF:${duration},\npart${i}.ts\n`).join('') +
    (end ? '#EXT-X-ENDLIST\n' : '');
}
function candidate(patch = {}) {
  return { id: 'media-1', tabId: 'tab', url: mediaUrl, pageUrl: 'https://page.example.test/watch',
    pageTitle: '分片视频', kind: 'hls', family: 'manifest', source: 'resource_dom',
    confidence: 90, playabilityState: 'candidate', downloadabilityState: 'downloadable',
    actionHints: ['download', 'copy'], evidence: [], playbackMetadata: { durationMs: 42000 }, ...patch };
}
const checks = [];
function check(name, action) { checks.push([name, action]); }

check('complete HLS duration sums every segment, including decimals, independently of sample limits', async () => {
  const { summary } = await parser.parseText(playlist(120, 7.5), mediaUrl);
  assert.equal(summary.durationSeconds, 900);
  assert.equal(summary.sampleSegments.length, 5);
  assert.equal(summary.segmentCount, 120);
  assert.equal(summary.live, false);
  assert.equal(validator.graphFromManifestSummary(summary).durationSeconds, 900);
});
check('a rolling or growing playlist window is not reported as a full movie duration', async () => {
  for (const tags of ['', '#EXT-X-PLAYLIST-TYPE:EVENT\n', '#EXT-X-MEDIA-SEQUENCE:200\n']) {
    const { summary } = await parser.parseText(playlist(5, 8.5, false, tags), mediaUrl);
    assert.equal(summary.durationSeconds, 0);
    assert.equal(summary.live, true);
    const graph = validator.graphFromManifestSummary(summary);
    assert.equal(graph.durationSeconds, undefined);
    assert.equal(graph.live, true);
    assert.equal(projector.projectedMediaMetrics(candidate({ validation: { graph } }), []).durationMs, undefined);
  }
  const { summary } = await parser.parseText(playlist(120, 7.5, true, '#EXT-X-PLAYLIST-TYPE:EVENT\n'), mediaUrl);
  assert.equal(summary.durationSeconds, 900);
});
check('incomplete segment metadata and delta playlists do not claim a total duration', async () => {
  for (const text of [playlist(5, 8.5, true, '#EXT-X-SKIP:SKIPPED-SEGMENTS=115\n'),
    playlist(5, 8.5, false) + '#EXTINF:10,\n#EXT-X-ENDLIST',
    playlist(5, 8.5).replace('#EXTINF:8.5,', '#EXTINF:bad,'),
    playlist(5, 8.5).replace('#EXTINF:8.5,\n', '')]) {
    assert.equal((await parser.parseText(text, mediaUrl)).summary.durationSeconds, 0);
  }
});
check('validated full duration replaces a stale 42-second player value in both list and download', () => {
  assert.equal(projector.projectedMediaMetrics(candidate(), []).durationMs, undefined,
    'a provisional player value must not masquerade as a complete HLS duration');
  const media = candidate({ validation: { graph: { role: 'media', durationSeconds: 900, live: false } } });
  const snapshot = { tabId: 'tab', records: [{ identityKey: 'media', candidate: media }] };
  assert.equal(projector.projectResourceList(snapshot, false).items[0].durationMs, 900000);
  assert.equal(projector.projectDownloadCandidateById(snapshot, media.id).durationMs, 900000);
  media.playbackMetadata.durationMs = 900000;
  media.validation.graph.durationSeconds = 42;
  assert.equal(projector.projectedMediaMetrics(media, []).durationMs, 42000, 'use evidence, not Math.max');
});
check('master variants carry only their own completed duration and size estimates', async () => {
  const local = new MediaManifestProcessingService({});
  const masterUrl = 'https://cdn.example.test/master.m3u8';
  let requests = 0;
  local.fetchText = async url => { requests++; return { ok: true,
    text: url.includes('complete') ? playlist(120, 7.5) : playlist(5, 8.5, false), errorMessage: '' }; };
  const { summary } = await local.parseText('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\ncomplete.m3u8\n' +
    '#EXT-X-STREAM-INF:BANDWIDTH=400000\ngrowing.m3u8', masterUrl);
  assert.equal(requests, 2);
  const graph = validator.graphFromManifestSummary(summary);
  assert.equal(graph.hlsVariants[0].durationSeconds, 900);
  assert.equal(graph.hlsVariants[0].estimatedTotalBytes, 900 * 800000 / 8);
  assert.equal(graph.hlsVariants[1].durationSeconds, undefined);
  assert.equal(graph.hlsVariants[1].estimatedTotalBytes, undefined);
  assert.equal(graph.hlsVariants[1].live, true);
  const parent = candidate({ id: 'parent', url: masterUrl, validation: { graph } });
  const complete = candidate({ url: graph.hlsVariants[0].url });
  const growing = candidate({ url: graph.hlsVariants[1].url });
  assert.equal(projector.projectedMediaMetrics(complete, [parent, complete]).durationMs, 900000);
  assert.equal(projector.projectedMediaMetrics(growing, [parent, growing]).durationMs, undefined);
});
check('a later observation replaces provisional duration and can correct it downwards', () => {
  const classifier = new MediaSignalClassificationService();
  const store = new MediaDiscoveryStore();
  const input = { tabId: 'tab', pageUrl: 'https://page.example.test/watch', pageTitle: '视频',
    privacyMode: 'normal', url: 'https://cdn.example.test/movie.mp4', fromBlob: false,
    signal: 'video_element' };
  for (const duration of [42000, 900000, 870000]) {
    const signal = classifier.buildResourceDomSignal({ ...input, durationMs: duration },
      { signalKind: 'dom_probe', cost: 'normal' });
    const mutation = store.ingestSignals({ tabId: 'tab', signals: [signal] });
    assert.equal(mutation.presentationRelevantChange, true);
    assert.equal(projector.projectResourceList(store.getTabSnapshot('tab'), false).items[0].durationMs, duration);
  }
  for (const duration of [undefined, NaN, Infinity, -100]) {
    const signal = classifier.buildResourceDomSignal({ ...input, durationMs: duration },
      { signalKind: 'dom_probe', cost: 'normal' });
    store.ingestSignals({ tabId: 'tab', signals: [signal] });
    assert.equal(projector.projectResourceList(store.getTabSnapshot('tab'), false).items[0].durationMs, 870000);
  }
});
check('a completed captured playlist replaces the early window without probing every live update', async () => {
  const classifier = new MediaSignalClassificationService();
  const store = new MediaDiscoveryStore();
  const input = { tabId: 'tab', pageUrl: 'https://page.example.test/watch', pageTitle: '视频',
    privacyMode: 'normal', url: mediaUrl, fromBlob: false, signal: 'script_text', mimeType: 'application/vnd.apple.mpegurl' };
  const ingest = text => store.ingestSignals({ tabId: 'tab', signals: [classifier.buildResourceDomSignal({ ...input,
    manifestText: text, manifestBaseUrl: mediaUrl }, { signalKind: 'deep_probe', cost: 'normal' })] });
  const early = playlist(5, 8.5, false);
  ingest(early);
  const record = store.getTabSnapshot('tab').records[0].candidate;
  const fingerprint = validator.buildFingerprint(record);
  const graph = validator.graphFromManifestSummary((await parser.parseText(early, mediaUrl)).summary);
  record.validation = { state: 'validated_playable', kind: 'hls_resource_graph', fingerprint,
    validatedAt: Date.now(), graph, evidence: [] };
  assert.equal(ingest(playlist(6, 8.5, false)).validationRelevantChange, false);
  const full = playlist(120, 7.5);
  assert.equal(ingest(full).validationRelevantChange, true);
  assert.equal(record.manifestContext.manifestText, full);
  assert.equal(record.validation, undefined);
  assert.notEqual(validator.buildFingerprint(record), fingerprint);
  const fullGraph = validator.graphFromManifestSummary((await parser.parseText(record.manifestContext.manifestText, mediaUrl)).summary);
  record.validation = { graph: fullGraph };
  assert.equal(projector.projectedMediaMetrics(record, [record]).durationMs, 900000);
});
(async () => {
  let failed = 0;
  for (const [name, action] of checks) {
    try { await action(); console.log('PASS ' + name); }
    catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.message); }
  }
  assert.equal(failed, 0, `${failed} media duration contracts failed`);
  console.log(`Media duration: ${checks.length} regression groups passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });

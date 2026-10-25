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
    if (name === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    return load(path.resolve(path.dirname(filename), name + '.ets'));
  } }, { filename });
  return exports;
}
const { resolveMediaResourceName } = load('features/mediaDiscovery/MediaResourceNamePolicy.ets');
const { MediaCandidateProjector } = load('services/media/MediaCandidateProjector.ets');
const { MediaSignalClassificationService } = load('services/media/MediaSignalClassificationService.ets');
const { MediaDiscoveryStore } = load('services/media/MediaDiscoveryStore.ets');
const { DownloadV2RequestCapture } = load('features/downloadv2/DownloadV2RequestCapture.ets');
const { DownloadFileNameService } = load('services/download/DownloadFileNameService.ets');
const projector = new MediaCandidateProjector();
const candidate = (name, extra = {}) => ({ id: 'media-1', tabId: 'tab', family: 'video', kind: 'mp4',
  url: 'https://cdn.example.test/' + encodeURIComponent(name) + '?token=a%2Bb%26c', pageTitle: '城市漫游 第三集',
  pageUrl: 'https://page.example.test/watch', actionHints: ['download', 'copy'], confidence: 90,
  playabilityState: 'candidate', downloadabilityState: 'downloadable', evidence: [], ...extra });
function check(name, action) { action(); console.log('PASS ' + name); }

check('opaque CDN names get a readable title; ordinary filenames stay intact', () => {
  for (const name of ['2b7e151628aed2a6abf7158809cf4f3c.mp4', '1729852340123456.mp4',
    '550e8400-e29b-41d4-a716-446655440000.mp4', 'j8x2m6n9P7q1r5s3T8u4.mp4', 'video_1080.mp4']) {
    assert.equal(resolveMediaResourceName(candidate(name), name).fileName, '城市漫游 第三集.mp4');
  }
  for (const name of ['旅行日记-第03集.mp4', 'The-Matrix-1999.mp4', '1984.mp4', 'lesson-2026-10-25.mp4',
    'IntroductionToHarmonyOS2026.mp4']) {
    assert.equal(resolveMediaResourceName(candidate(name), name).fileName, name);
  }
});
check('specific video and native titles take precedence; page title is only a fallback', () => {
  const media = candidate('video.mp4', { playbackMetadata: { mediaTitle: '海边日落' } });
  assert.equal(resolveMediaResourceName(media, 'video.mp4').fileName, '海边日落.mp4');
  assert.equal(resolveMediaResourceName({ ...media, nativeIdentity: { title: '站点返回的视频名称' } }, 'video.mp4')
    .fileName, '站点返回的视频名称.mp4');
  assert.equal(resolveMediaResourceName({ ...media, playbackMetadata: { mediaTitle: 'Video player' } }, 'video.mp4')
    .fileName, '城市漫游 第三集.mp4');
  for (const title of ['', '视频播放器', 'https://page.example.test/watch']) {
    assert.equal(resolveMediaResourceName(candidate('index.mp4', { pageTitle: title }), 'index.mp4').usesTitle, false);
  }
});
check('titles cannot alter format, inject paths, overflow UTF-8 limits, or lose episode suffixes', () => {
  const hls = candidate('index.m3u8', { kind: 'hls', family: 'manifest', pageTitle: '课程.EP01' });
  assert.equal(resolveMediaResourceName(hls, 'index.m3u8').fileName, '课程.EP01.ts');
  const webm = candidate('play', { kind: 'webm', playbackMetadata: { mimeType: 'video/webm' } });
  assert.equal(resolveMediaResourceName(webm, 'play').fileName, '城市漫游 第三集.webm');
  const dirty = candidate('video.mp4', { pageTitle: '../课程: 第一集? / 片段\u0000\u202e' });
  const clean = resolveMediaResourceName(dirty, 'video.mp4').fileName;
  assert.doesNotMatch(clean, /[\\/:*?"<>|\u0000\u202e]/);
  assert.ok(clean.endsWith('.mp4'));
  const long = resolveMediaResourceName(candidate('video.mp4', { pageTitle: '中🙂'.repeat(200) }), 'video.mp4').fileName;
  assert.ok(Buffer.byteLength(long) <= 204);
  assert.equal(Buffer.from(long).toString('utf8'), long);
  assert.equal(resolveMediaResourceName(candidate('video.mp4', { pageTitle: '讲座.mp4' }), 'video.mp4').fileName, '讲座.mp4');
});
check('image, audio and document filenames do not inherit an unrelated page title', () => {
  for (const [family, kind, name] of [['image', 'image', '123456789.jpg'], ['audio', 'audio', '123456789.mp3'],
    ['document', 'document', '123456789.pdf']]) {
    const result = resolveMediaResourceName(candidate(name, { family, kind }), name);
    assert.equal(result.fileName, name);
    assert.equal(result.usesTitle, false);
  }
});
check('list, download prompt and final filename agree even with an opaque Content-Disposition', () => {
  const name = '2b7e151628aed2a6abf7158809cf4f3c.mp4';
  const media = candidate(name, { playbackMetadata: { displayName: name, mimeType: 'video/mp4',
    contentDisposition: 'attachment; filename="' + name + '"' } });
  const snapshot = { tabId: 'tab', records: [{ identityKey: 'fixture', candidate: media }] };
  const list = projector.projectResourceList(snapshot, false);
  const download = projector.projectDownloadCandidateById(snapshot, media.id);
  assert.equal(list.items[0].displayName, '城市漫游 第三集');
  assert.equal(download.displayName, '城市漫游 第三集.mp4');
  assert.equal(download.contentDisposition, undefined);
  const capture = new DownloadV2RequestCapture();
  const request = capture.createManualRequest(download.url, {}, download.displayName, download.sourceHost, false, download);
  assert.equal(request.suggestedFileName, download.displayName);
  assert.equal(new DownloadFileNameService().resolveFileName(request), download.displayName);
  assert.equal(request.url, media.url);
  assert.ok(media.playbackMetadata.contentDisposition.includes(name), 'original evidence must be retained');
  const descriptive = { ...media, playbackMetadata: { displayName: '课程第三集.mp4',
    contentDisposition: 'attachment; filename="课程第三集.mp4"' } };
  const original = projector.projectDownloadCandidate(descriptive, [descriptive]);
  assert.equal(original.displayName, '课程第三集.mp4');
  assert.equal(original.contentDisposition, descriptive.playbackMetadata.contentDisposition);
});
check('later DOM titles enrich an existing network candidate and trigger a list refresh', () => {
  const classifier = new MediaSignalClassificationService();
  const store = new MediaDiscoveryStore();
  const input = { tabId: 'tab', pageUrl: 'https://page.example.test/watch', pageTitle: 'Loading...',
    privacyMode: 'normal', requestUrl: 'https://cdn.example.test/123456789.mp4' };
  const network = classifier.buildResourceNetworkSignal(input);
  store.ingestSignals({ tabId: 'tab', signals: [network] });
  const dom = classifier.buildResourceDomSignal({ ...input, url: input.requestUrl, fromBlob: false,
    signal: 'video_element', pageTitle: '页面视频标题', mediaTitle: '播放器对应的视频' }, { signalKind: 'dom_probe', cost: 'normal' });
  const mutation = store.ingestSignals({ tabId: 'tab', signals: [dom] });
  assert.equal(mutation.presentationRelevantChange, true);
  store.ingestSignals({ tabId: 'tab', signals: [network] });
  const snapshot = store.getTabSnapshot('tab');
  assert.equal(snapshot.records.length, 1);
  const record = snapshot.records[0].candidate;
  assert.equal(record.pageTitle, '页面视频标题');
  assert.equal(record.playbackMetadata.mediaTitle, '播放器对应的视频');
  assert.equal(projector.projectDownloadCandidateById(snapshot, record.id).displayName, '播放器对应的视频.mp4');
  const update = { ...dom, playbackMetadata: { ...dom.playbackMetadata, mediaTitle: '更新后的视频标题' } };
  assert.equal(store.ingestSignals({ tabId: 'tab', signals: [update] }).presentationRelevantChange, true);
  assert.equal(projector.projectResourceList(store.getTabSnapshot('tab'), false).items[0].displayName, '更新后的视频标题');
});
check('a later descriptive server filename supersedes the earlier opaque URL name', () => {
  const classifier = new MediaSignalClassificationService();
  const store = new MediaDiscoveryStore();
  const input = { tabId: 'tab', pageUrl: 'https://page.example.test/watch', pageTitle: '页面标题',
    privacyMode: 'normal', requestUrl: 'https://cdn.example.test/123456789.mp4',
    contentDisposition: 'attachment; filename="123456789.mp4"' };
  store.ingestSignals({ tabId: 'tab', signals: [classifier.buildResourceNetworkSignal(input)] });
  store.ingestSignals({ tabId: 'tab', signals: [classifier.buildResourceNetworkSignal({ ...input,
    contentDisposition: 'attachment; filename="Travel-Diary.mp4"' })] });
  const snapshot = store.getTabSnapshot('tab');
  const download = projector.projectDownloadCandidateById(snapshot, snapshot.records[0].candidate.id);
  assert.equal(download.displayName, 'Travel-Diary.mp4');
  assert.equal(new DownloadFileNameService().resolveFileName({ ...download, suggestedFileName: download.displayName }),
    'Travel-Diary.mp4');
});
console.log('Media resource naming contracts passed.');

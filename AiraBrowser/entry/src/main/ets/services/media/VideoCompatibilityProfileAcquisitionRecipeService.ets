import { webview } from '@kit.ArkWeb';
import urlUtils from '@ohos.url';
import { BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { MediaEvidenceScope } from '../../features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaVideoDeepProbeResult } from '../../features/mediaDiscovery/MediaVideoDeepProbeScript';
import { YoutubeUrlMatcher } from '../../features/youtubeTakeover/YoutubeUrlMatcher';
import {
  YoutubeFormat,
  YoutubePlaybackPlan
} from '../../features/youtubeTakeover/YoutubeModels';
import { YoutubeFormatSelection } from '../../features/youtubeTakeover/YoutubeFormatSelector';
import { YoutubeExtractorService } from '../youtube/YoutubeExtractorService';
import {
  VIDEO_COMPATIBILITY_XLPLAYER_LINES_RUNTIME_FRAGMENT
} from './VideoCompatibilityProfileXlPlayerLinesRecipeScript';

export type VideoCompatibilityAcquisitionResourceFamily = 'video' | 'audio';
export type VideoCompatibilityAcquisitionResourceKind = 'dash' | 'progressive';
export type VideoCompatibilityAcquisitionResourceProvenance = 'profile_acquisition';
export type VideoCompatibilityReplacedGenericDeepProbeStrategyId = 'vendor_adapters';

/**
 * A site-neutral resource fact emitted by an Acquisition Recipe. It is deliberately not a MediaSignal or
 * MediaCandidate: callers cannot use it to create Session, route, eligibility, or candidate authority.
 */
export interface VideoCompatibilityAcquisitionResource {
  url: string;
  family: VideoCompatibilityAcquisitionResourceFamily;
  kind: VideoCompatibilityAcquisitionResourceKind;
  mimeType: string;
  codecs?: string;
  bandwidth?: number;
  contentLength?: number;
  fps?: number;
  audioSampleRate?: number;
  audioChannels?: number;
  initializationRange?: string;
  indexRange?: string;
  width?: number;
  height?: number;
  durationMs?: number;
  provenance: VideoCompatibilityAcquisitionResourceProvenance;
  profileAttribution: string;
  observedAt: number;
}

/**
 * Ephemeral access facts emitted by a compiled Recipe. They are applied to the current MediaSignal only;
 * the Profile Catalog, diagnostics, and persisted data never receive headers, cookies, or credentials.
 */
export interface VideoCompatibilityAcquisitionAccessContext {
  pageUrl: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
}

export interface VideoCompatibilityAcquisitionReport {
  resources: VideoCompatibilityAcquisitionResource[];
  accessContext?: VideoCompatibilityAcquisitionAccessContext;
}

export interface VideoCompatibilityAcquisitionShadowComparison {
  recipeResourceCount: number;
  legacyResourceCount: number;
  recipeVideoCount: number;
  legacyVideoCount: number;
  recipeAudioCount: number;
  legacyAudioCount: number;
  trackFactsMatch: boolean;
  resourceIdentityMatch: boolean;
}

export interface VideoCompatibilityProfileAcquisitionInterceptInput {
  tabId: string;
  pageUrl: string;
  requestUrl: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
}

export interface VideoCompatibilityProfileAcquisitionProbeInput {
  tabId: string;
  pageUrl: string;
  privacyMode: BrowserSessionPrivacyMode;
  controller: webview.WebviewController | undefined;
  delayedProbeDelayMs?: number;
}

export interface VideoCompatibilityProfileAcquisitionProbeTrigger {
  pageUrl: string;
  delayedProbeDelayMs: number;
}

export interface VideoCompatibilityProfileAcquisitionProbeHost {
  shouldRunDelayedProbe: (tabId: string, pageUrl: string, expectedMediaId: string) => boolean;
  onReport: (input: VideoCompatibilityProfileAcquisitionProbeInput, report: VideoCompatibilityAcquisitionReport) => void;
  onProbeSettled: (tabId: string) => void;
}

/**
 * A compiled Recipe may own bounded matching and scheduling when acquisition depends on a site runtime.
 * It still returns observations only; the caller owns its scope lease and decides whether output is ingested.
 */
export interface VideoCompatibilityProfileAcquisitionScheduler {
  observeIntercept(input: VideoCompatibilityProfileAcquisitionInterceptInput): VideoCompatibilityProfileAcquisitionProbeTrigger | undefined;
  schedulePageProbe(input: VideoCompatibilityProfileAcquisitionProbeInput, host: VideoCompatibilityProfileAcquisitionProbeHost): void;
  scheduleSpaRouteProbe(input: VideoCompatibilityProfileAcquisitionProbeInput, host: VideoCompatibilityProfileAcquisitionProbeHost): void;
  runTakeoverProbe(input: VideoCompatibilityProfileAcquisitionProbeInput, host: VideoCompatibilityProfileAcquisitionProbeHost): Promise<void>;
  clearTab(tabId: string): void;
}

export interface VideoCompatibilityProfileAcquisitionCapability {
  acquire(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    observedAt: number,
    privacyMode?: BrowserSessionPrivacyMode
  ): Promise<VideoCompatibilityAcquisitionReport | undefined>;
  getScheduler(): VideoCompatibilityProfileAcquisitionScheduler | undefined;
  getReplacedGenericDeepProbeStrategyIds(): VideoCompatibilityReplacedGenericDeepProbeStrategyId[];
}

export class VideoCompatibilityProfileAcquisitionLease {
  private readonly scope: MediaEvidenceScope;
  private readonly pageUrl: string;
  private readonly profileAttribution: string;

  constructor(scope: MediaEvidenceScope, pageUrl: string, profileAttribution: string) {
    this.scope = {
      tabId: scope.tabId,
      generationId: scope.generationId,
      routeEpochId: scope.routeEpochId
    };
    this.pageUrl = pageUrl;
    this.profileAttribution = profileAttribution;
  }

  isCurrent(scope: MediaEvidenceScope, pageUrl: string, profileAttribution: string): boolean {
    return this.scope.tabId === scope.tabId &&
      this.scope.generationId === scope.generationId &&
      this.scope.routeEpochId === scope.routeEpochId &&
      this.pageUrl === pageUrl &&
      this.profileAttribution === profileAttribution;
  }
}

interface VideoCompatibilityBilibiliAcquisitionRawResource {
  url?: string;
  family?: string;
  kind?: string;
  mimeType?: string;
  codecs?: string;
  bandwidth?: number;
  initializationRange?: string;
  indexRange?: string;
  width?: number;
  height?: number;
  durationMs?: number;
}

interface VideoCompatibilityBilibiliAcquisitionRawPayload {
  ok?: boolean;
  origin?: string;
  resources?: VideoCompatibilityBilibiliAcquisitionRawResource[];
}

const MAX_ACQUISITION_RESOURCE_COUNT: number = 16;
const MAX_RESOURCE_URL_LENGTH: number = 4096;
const MAX_MIME_TYPE_LENGTH: number = 128;
const MAX_CODEC_LENGTH: number = 256;
const MAX_RANGE_LENGTH: number = 64;
const MAX_BANDWIDTH: number = 500000000;
const MAX_CONTENT_LENGTH: number = 9007199254740991;
const MAX_DIMENSION: number = 16384;
const MAX_DURATION_MS: number = 172800000;
const MAX_RAW_PAYLOAD_LENGTH: number = 131072;

/**
 * The compiled Bilibili play-info Acquisition Recipe. The injected script is App-authored, has a closed
 * read-only input set, and returns only bounded resource facts. It never receives Profile content or identity.
 */
export class VideoCompatibilityBilibiliAcquisitionRecipeService {
  async probe(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    profileAttribution: string,
    observedAt: number = Date.now()
  ): Promise<VideoCompatibilityAcquisitionReport | undefined> {
    if (controller === undefined || profileAttribution.trim().length <= 0) {
      return undefined;
    }
    try {
      const raw = await controller.runJavaScript(this.buildScript());
      if (raw === null || raw === undefined || raw.length <= 0 || raw.length > MAX_RAW_PAYLOAD_LENGTH) {
        return undefined;
      }
      return this.normalizePayload(
        this.unwrapJsonString(raw),
        pageUrl,
        profileAttribution,
        observedAt
      );
    } catch (_error) {
      return undefined;
    }
  }

  /**
   * This fixture seam normalizes the bounded payload shape that the compiled page script returns. It accepts
   * no page objects and has no side effects, which keeps parity fixtures outside an ArkWeb runtime.
   */
  normalizePayload(
    raw: string,
    pageUrl: string,
    profileAttribution: string,
    observedAt: number
  ): VideoCompatibilityAcquisitionReport | undefined {
    if (raw.length <= 0 || raw.length > MAX_RAW_PAYLOAD_LENGTH) {
      return undefined;
    }
    const expectedOrigin = this.resolveOrigin(pageUrl);
    const attribution = profileAttribution.trim();
    if (expectedOrigin.length <= 0 || attribution.length <= 0 || attribution.length > 96) {
      return undefined;
    }
    const payload = this.parsePayload(raw);
    if (payload === undefined || payload.ok !== true || payload.origin !== expectedOrigin ||
      payload.resources === undefined || payload.resources.length > MAX_ACQUISITION_RESOURCE_COUNT) {
      return undefined;
    }
    const normalizedObservedAt = this.normalizeObservedAt(observedAt);
    const resources: VideoCompatibilityAcquisitionResource[] = [];
    for (let index: number = 0; index < payload.resources.length; index += 1) {
      const resource = this.normalizeResource(payload.resources[index], attribution, normalizedObservedAt);
      if (resource === undefined || this.containsResourceIdentity(resources, resource)) {
        continue;
      }
      resources.push(resource);
    }
    return { resources: resources };
  }

  /**
   * Compares only sanitized aggregate and equality facts with a frozen migration fixture representing the
   * previous Bilibili extraction shape. It returns no resource URL or other private browsing data.
   */
  compareWithLegacyBilibiliDeepProbe(
    recipeReport: VideoCompatibilityAcquisitionReport,
    legacyBilibiliResults: MediaVideoDeepProbeResult[]
  ): VideoCompatibilityAcquisitionShadowComparison {
    const recipeResources = recipeReport.resources.slice();
    const legacyResources = this.normalizeLegacyBilibiliResults(legacyBilibiliResults);
    const recipeVideoCount = this.countFamily(recipeResources, 'video');
    const legacyVideoCount = this.countFamily(legacyResources, 'video');
    const recipeAudioCount = this.countFamily(recipeResources, 'audio');
    const legacyAudioCount = this.countFamily(legacyResources, 'audio');
    return {
      recipeResourceCount: recipeResources.length,
      legacyResourceCount: legacyResources.length,
      recipeVideoCount: recipeVideoCount,
      legacyVideoCount: legacyVideoCount,
      recipeAudioCount: recipeAudioCount,
      legacyAudioCount: legacyAudioCount,
      trackFactsMatch: this.haveEquivalentResources(recipeResources, legacyResources, false),
      resourceIdentityMatch: this.haveEquivalentResources(recipeResources, legacyResources, true)
    };
  }

  private buildScript(): string {
    return [
      '(function(){',
      'try {',
      'var output = [];',
      'function isHttpUrl(value) { return /^https?:\\/\\//i.test(String(value || "").trim()); }',
      'function boundedText(value, maximum) {',
      '  if (typeof value !== "string") return "";',
      '  var text = value.trim();',
      '  return text.length > 0 && text.length <= maximum ? text : "";',
      '}',
      'function boundedInteger(value, minimum, maximum) {',
      '  if (typeof value !== "number" || !isFinite(value)) return undefined;',
      '  var integer = Math.floor(value);',
      '  return integer >= minimum && integer <= maximum ? integer : undefined;',
      '}',
      'function boundedRange(value) {',
      '  var text = boundedText(value, 64);',
      '  return /^\\d+-\\d+$/.test(text) ? text : undefined;',
      '}',
      'function firstString(item, names) {',
      '  if (!item) return "";',
      '  for (var i = 0; i < names.length; i++) {',
      '    var value = item[names[i]];',
      '    if (typeof value === "string" && value.length > 0) return value;',
      '  }',
      '  return "";',
      '}',
      'function firstMediaUrl(item) {',
      '  var direct = firstString(item, ["baseUrl", "base_url", "url"]);',
      '  if (direct) return direct;',
      '  if (!item) return "";',
      '  var backup = item.backupUrl || item.backup_url || item.backup_url_list;',
      '  if (!Array.isArray(backup)) return "";',
      '  for (var i = 0; i < backup.length; i++) {',
      '    if (typeof backup[i] === "string" && backup[i].length > 0) return backup[i];',
      '  }',
      '  return "";',
      '}',
      'function numberValue(item, name) {',
      '  var value = item && item[name];',
      '  return typeof value === "number" && isFinite(value) ? value : 0;',
      '}',
      'function segmentRange(item, name) {',
      '  var base = item && (item.SegmentBase || item.segmentBase || item.segment_base);',
      '  var value = base && base[name];',
      '  return typeof value === "string" ? value : "";',
      '}',
      'function append(item) {',
      '  if (!item || output.length >= 16) return false;',
      '  var url = boundedText(item.url, 4096);',
      '  var family = item.family === "video" ? "video" : item.family === "audio" ? "audio" : "";',
      '  var kind = item.kind === "dash" ? "dash" : item.kind === "progressive" ? "progressive" : "";',
      '  var mimeType = boundedText(item.mimeType, 128);',
      '  if (!isHttpUrl(url) || !family || !kind || !mimeType) return false;',
      '  output.push({',
      '    url: url, family: family, kind: kind, mimeType: mimeType,',
      '    codecs: boundedText(item.codecs, 256) || undefined,',
      '    bandwidth: boundedInteger(item.bandwidth, 1, 500000000),',
      '    initializationRange: boundedRange(item.initializationRange),',
      '    indexRange: boundedRange(item.indexRange),',
      '    width: family === "video" ? boundedInteger(item.width, 1, 16384) : undefined,',
      '    height: family === "video" ? boundedInteger(item.height, 1, 16384) : undefined,',
      '    durationMs: boundedInteger(item.durationMs, 1, 172800000)',
      '  });',
      '  return true;',
      '}',
      'function bestVideo(items) {',
      '  if (!Array.isArray(items)) return undefined;',
      '  var best; var score = -1;',
      '  for (var i = 0; i < items.length; i++) {',
      '    var item = items[i] || {};',
      '    if (!firstMediaUrl(item)) continue;',
      '    var candidateScore = numberValue(item, "id") * 1000000 + numberValue(item, "bandwidth") +',
      '      numberValue(item, "height") * 1000 + numberValue(item, "width");',
      '    if (!best || candidateScore > score) { best = item; score = candidateScore; }',
      '  }',
      '  return best;',
      '}',
      'function bestAudio(items) {',
      '  if (!Array.isArray(items)) return undefined;',
      '  var best; var score = -1;',
      '  for (var i = 0; i < items.length; i++) {',
      '    var item = items[i] || {};',
      '    if (!firstMediaUrl(item)) continue;',
      '    var candidateScore = numberValue(item, "bandwidth") + numberValue(item, "id");',
      '    if (!best || candidateScore > score) { best = item; score = candidateScore; }',
      '  }',
      '  return best;',
      '}',
      'function appendDash(data) {',
      '  var dash = data && (data.dash || data);',
      '  if (!dash || !dash.video) return false;',
      '  var video = bestVideo(dash.video);',
      '  var audio = bestAudio(dash.audio || (dash.dolby && dash.dolby.audio));',
      '  if (!audio && dash.flac && dash.flac.audio) audio = dash.flac.audio;',
      '  var videoUrl = firstMediaUrl(video); var audioUrl = firstMediaUrl(audio);',
      '  if (!videoUrl || !audioUrl) return false;',
      '  append({url: videoUrl, family: "video", kind: "dash",',
      '    mimeType: firstString(video, ["mimeType", "mime_type"]) || "video/mp4",',
      '    codecs: firstString(video, ["codecs"]), bandwidth: numberValue(video, "bandwidth") || undefined,',
      '    initializationRange: segmentRange(video, "Initialization") || undefined,',
      '    indexRange: segmentRange(video, "indexRange") || undefined,',
      '    width: numberValue(video, "width") || undefined, height: numberValue(video, "height") || undefined,',
      '    durationMs: numberValue(data, "timelength") || undefined});',
      '  append({url: audioUrl, family: "audio", kind: "dash",',
      '    mimeType: firstString(audio, ["mimeType", "mime_type"]) || "audio/mp4",',
      '    codecs: firstString(audio, ["codecs"]), bandwidth: numberValue(audio, "bandwidth") || undefined,',
      '    initializationRange: segmentRange(audio, "Initialization") || undefined,',
      '    indexRange: segmentRange(audio, "indexRange") || undefined,',
      '    durationMs: numberValue(data, "timelength") || undefined});',
      '  return true;',
      '}',
      'function appendDurl(data) {',
      '  if (!data || !Array.isArray(data.durl)) return false;',
      '  var added = false;',
      '  for (var i = 0; i < data.durl.length && i < 8; i++) {',
      '    var item = data.durl[i] || {}; var url = firstMediaUrl(item);',
      '    if (!url) continue;',
      '    added = append({url: url, family: "video", kind: "progressive",',
      '      mimeType: url.toLowerCase().indexOf(".mp4") >= 0 ? "video/mp4" : "video/x-flv",',
      '      durationMs: numberValue(item, "length") || numberValue(data, "timelength") || undefined}) || added;',
      '  }',
      '  return added;',
      '}',
      'function parseObject(value) {',
      '  if (typeof value !== "string") return value;',
      '  try { return JSON.parse(value); } catch (_error) { return undefined; }',
      '}',
      'function collect(root, depth, found, seen) {',
      '  if (!root || found.length >= 8 || depth > 5) return;',
      '  root = parseObject(root);',
      '  if (!root || typeof root !== "object" || seen.indexOf(root) >= 0) return;',
      '  seen.push(root);',
      '  if ((root.dash && root.dash.video) || Array.isArray(root.durl)) found.push(root);',
      '  else if (root.video && root.audio) found.push({dash: root});',
      '  var keys = Object.keys(root);',
      '  for (var i = 0; i < keys.length && i < 120 && found.length < 8; i++) {',
      '    var key = keys[i];',
      '    if (key === "window" || key === "document" || key === "parent" || key === "top") continue;',
      '    var value = root[key];',
      '    if (!value || (typeof value !== "object" && typeof value !== "string")) continue;',
      '    if (key === "playinfo" || key === "playInfo" || key === "playUrlInfo" || key === "data" ||',
      '      key === "result" || key === "videoData" || key === "epInfo") collect(value, depth, found, seen);',
      '    else if (depth < 4) collect(value, depth + 1, found, seen);',
      '  }',
      '}',
      'var roots = [window.__playinfo__, window.__INITIAL_STATE__, window.__INITIAL_DATA__, window.__NEXT_DATA__];',
      'var found = []; var seen = [];',
      'for (var rootIndex = 0; rootIndex < roots.length; rootIndex++) collect(roots[rootIndex], 0, found, seen);',
      'for (var durlIndex = 0; durlIndex < found.length; durlIndex++) { if (appendDurl(found[durlIndex])) break; }',
      'if (output.length <= 0) {',
      '  for (var dashIndex = 0; dashIndex < found.length; dashIndex++) { if (appendDash(found[dashIndex])) break; }',
      '}',
      'return JSON.stringify({ok: true, origin: window.location.origin || "", resources: output.slice(0, 16)});',
      '} catch (_error) {',
      'return JSON.stringify({ok: false, origin: "", resources: []});',
      '}',
      '})()'
    ].join('\n');
  }

  private parsePayload(raw: string): VideoCompatibilityBilibiliAcquisitionRawPayload | undefined {
    try {
      const parsed = JSON.parse(raw) as VideoCompatibilityBilibiliAcquisitionRawPayload;
      return parsed === undefined || parsed === null ? undefined : parsed;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeResource(
    raw: VideoCompatibilityBilibiliAcquisitionRawResource,
    profileAttribution: string,
    observedAt: number
  ): VideoCompatibilityAcquisitionResource | undefined {
    const url = raw.url?.trim() ?? '';
    const family = raw.family;
    const kind = raw.kind;
    const mimeType = this.normalizeText(raw.mimeType, MAX_MIME_TYPE_LENGTH);
    if (!this.isHttpUrl(url) || url.length > MAX_RESOURCE_URL_LENGTH ||
      (family !== 'video' && family !== 'audio') ||
      (kind !== 'dash' && kind !== 'progressive') || mimeType.length <= 0) {
      return undefined;
    }
    return {
      url: url,
      family: family,
      kind: kind,
      mimeType: mimeType,
      codecs: this.optionalText(raw.codecs, MAX_CODEC_LENGTH),
      bandwidth: this.optionalInteger(raw.bandwidth, 1, MAX_BANDWIDTH),
      initializationRange: this.optionalRange(raw.initializationRange),
      indexRange: this.optionalRange(raw.indexRange),
      width: family === 'video' ? this.optionalInteger(raw.width, 1, MAX_DIMENSION) : undefined,
      height: family === 'video' ? this.optionalInteger(raw.height, 1, MAX_DIMENSION) : undefined,
      durationMs: this.optionalInteger(raw.durationMs, 1, MAX_DURATION_MS),
      provenance: 'profile_acquisition',
      profileAttribution: profileAttribution,
      observedAt: observedAt
    };
  }

  private normalizeLegacyBilibiliResults(
    legacyResults: MediaVideoDeepProbeResult[]
  ): VideoCompatibilityAcquisitionResource[] {
    const resources: VideoCompatibilityAcquisitionResource[] = [];
    for (let index: number = 0; index < legacyResults.length && resources.length < MAX_ACQUISITION_RESOURCE_COUNT; index += 1) {
      const item = legacyResults[index];
      const video = this.fromLegacyResult(item, 'video');
      if (video !== undefined && !this.containsResourceIdentity(resources, video)) {
        resources.push(video);
      }
      if (resources.length >= MAX_ACQUISITION_RESOURCE_COUNT || item.pairedAudioUrl === undefined) {
        continue;
      }
      const audio = this.fromLegacyResult(item, 'audio');
      if (audio !== undefined && !this.containsResourceIdentity(resources, audio)) {
        resources.push(audio);
      }
    }
    return resources;
  }

  private fromLegacyResult(
    item: MediaVideoDeepProbeResult,
    family: VideoCompatibilityAcquisitionResourceFamily
  ): VideoCompatibilityAcquisitionResource | undefined {
    const isAudio = family === 'audio';
    const url = (isAudio ? item.pairedAudioUrl : item.url)?.trim() ?? '';
    const mimeType = (isAudio ? item.pairedAudioMimeType : item.mimeType)?.trim() ?? '';
    if (!this.isHttpUrl(url) || mimeType.length <= 0) {
      return undefined;
    }
    return {
      url: url,
      family: family,
      kind: item.pairedAudioUrl !== undefined ? 'dash' : 'progressive',
      mimeType: mimeType,
      codecs: isAudio ? item.pairedAudioCodecs : item.codecs,
      bandwidth: isAudio ? item.pairedAudioBandwidth : item.bandwidth,
      initializationRange: isAudio ? item.pairedAudioInitializationRange : item.initializationRange,
      indexRange: isAudio ? item.pairedAudioIndexRange : item.indexRange,
      width: isAudio ? undefined : item.width,
      height: isAudio ? undefined : item.height,
      durationMs: item.durationMs,
      provenance: 'profile_acquisition',
      profileAttribution: 'legacy_fixture',
      observedAt: 1
    };
  }

  private haveEquivalentResources(
    left: VideoCompatibilityAcquisitionResource[],
    right: VideoCompatibilityAcquisitionResource[],
    includeIdentity: boolean
  ): boolean {
    if (left.length !== right.length) {
      return false;
    }
    const consumed: boolean[] = [];
    for (let index: number = 0; index < right.length; index += 1) {
      consumed.push(false);
    }
    for (let leftIndex: number = 0; leftIndex < left.length; leftIndex += 1) {
      let matched = false;
      for (let rightIndex: number = 0; rightIndex < right.length; rightIndex += 1) {
        if (consumed[rightIndex] || !this.sameTrackFacts(left[leftIndex], right[rightIndex], includeIdentity)) {
          continue;
        }
        consumed[rightIndex] = true;
        matched = true;
        break;
      }
      if (!matched) {
        return false;
      }
    }
    return true;
  }

  private sameTrackFacts(
    left: VideoCompatibilityAcquisitionResource,
    right: VideoCompatibilityAcquisitionResource,
    includeIdentity: boolean
  ): boolean {
    return left.family === right.family && left.kind === right.kind && left.mimeType === right.mimeType &&
      left.codecs === right.codecs && left.bandwidth === right.bandwidth &&
      left.initializationRange === right.initializationRange && left.indexRange === right.indexRange &&
      left.width === right.width && left.height === right.height && left.durationMs === right.durationMs &&
      (!includeIdentity || left.url === right.url);
  }

  private countFamily(resources: VideoCompatibilityAcquisitionResource[], family: VideoCompatibilityAcquisitionResourceFamily): number {
    let count = 0;
    for (let index: number = 0; index < resources.length; index += 1) {
      if (resources[index].family === family) {
        count += 1;
      }
    }
    return count;
  }

  private containsResourceIdentity(
    resources: VideoCompatibilityAcquisitionResource[],
    candidate: VideoCompatibilityAcquisitionResource
  ): boolean {
    for (let index: number = 0; index < resources.length; index += 1) {
      if (resources[index].url === candidate.url && resources[index].family === candidate.family) {
        return true;
      }
    }
    return false;
  }

  private optionalText(value: string | undefined, maximumLength: number): string | undefined {
    const normalized = this.normalizeText(value, maximumLength);
    return normalized.length > 0 ? normalized : undefined;
  }

  private normalizeText(value: string | undefined, maximumLength: number): string {
    const normalized = value?.trim() ?? '';
    if (normalized.length <= 0 || normalized.length > maximumLength) {
      return '';
    }
    for (let index: number = 0; index < normalized.length; index += 1) {
      const code = normalized.charCodeAt(index);
      if (code < 32 || code > 126) {
        return '';
      }
    }
    return normalized;
  }

  private optionalInteger(value: number | undefined, minimum: number, maximum: number): number | undefined {
    if (value === undefined || !Number.isFinite(value)) {
      return undefined;
    }
    const normalized = Math.floor(value);
    return normalized >= minimum && normalized <= maximum ? normalized : undefined;
  }

  private optionalRange(value: string | undefined): string | undefined {
    const normalized = this.normalizeText(value, MAX_RANGE_LENGTH);
    if (normalized.length <= 0) {
      return undefined;
    }
    const divider = normalized.indexOf('-');
    if (divider <= 0 || divider !== normalized.lastIndexOf('-')) {
      return undefined;
    }
    const left = normalized.substring(0, divider);
    const right = normalized.substring(divider + 1);
    return this.isDigits(left) && this.isDigits(right) ? normalized : undefined;
  }

  private isDigits(value: string): boolean {
    if (value.length <= 0) {
      return false;
    }
    for (let index: number = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  private normalizeObservedAt(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : Date.now();
  }

  private isHttpUrl(value: string): boolean {
    const normalized = value.toLowerCase();
    return normalized.startsWith('https://') || normalized.startsWith('http://');
  }

  private resolveOrigin(pageUrl: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(pageUrl.trim());
      const protocol = parsed.protocol.trim().toLowerCase();
      const hostname = parsed.hostname.trim().toLowerCase();
      const port = parsed.port?.trim() ?? '';
      if ((protocol !== 'http:' && protocol !== 'https:') || hostname.length <= 0) {
        return '';
      }
      const isDefaultPort = (protocol === 'http:' && port === '80') ||
        (protocol === 'https:' && port === '443');
      return protocol + '//' + hostname + (port.length > 0 && !isDefaultPort ? ':' + port : '');
    } catch (_error) {
      return '';
    }
  }

  private unwrapJsonString(raw: string): string {
    if (raw.length >= 2 && raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') {
      try {
        const decoded = JSON.parse(raw) as string;
        return typeof decoded === 'string' ? decoded : raw;
      } catch (_error) {
      }
    }
    return raw;
  }
}

interface VideoCompatibilityXlPlayerRawResource {
  url?: string;
  mimeType?: string;
}

interface VideoCompatibilityXlPlayerRawPayload {
  ok?: boolean;
  origin?: string;
  resources?: VideoCompatibilityXlPlayerRawResource[];
  pendingAsyncWork?: boolean;
  userAgent?: string;
}

interface VideoCompatibilityXlPlayerProbeOutcome {
  report?: VideoCompatibilityAcquisitionReport;
  pendingAsyncWork: boolean;
}

const XLPLAYER_ASYNC_FOLLOWUP_DELAY_MS: number = 900;

/**
 * The compiled XlPlayer `/lines` Acquisition Recipe. The page script owns the bounded same-origin request,
 * signature, response cache, and precedence rules; this scheduler owns non-blocking automatic follow-up and
 * the user-triggered blocking fallback. It emits only site-neutral resource and access facts.
 */
class VideoCompatibilityXlPlayerAcquisitionRecipeService implements
  VideoCompatibilityProfileAcquisitionCapability, VideoCompatibilityProfileAcquisitionScheduler {
  private readonly profileAttribution: string;
  private readonly generationByTab: Map<string, number> = new Map();

  constructor(profileAttribution: string) {
    this.profileAttribution = profileAttribution.trim();
  }

  getScheduler(): VideoCompatibilityProfileAcquisitionScheduler | undefined {
    return this;
  }

  getReplacedGenericDeepProbeStrategyIds(): VideoCompatibilityReplacedGenericDeepProbeStrategyId[] {
    return ['vendor_adapters'];
  }

  async acquire(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    observedAt: number,
    _privacyMode: BrowserSessionPrivacyMode = 'regular'
  ): Promise<VideoCompatibilityAcquisitionReport | undefined> {
    const outcome = await this.probe(controller, pageUrl, observedAt, false);
    return outcome.report;
  }

  observeIntercept(
    _input: VideoCompatibilityProfileAcquisitionInterceptInput
  ): VideoCompatibilityProfileAcquisitionProbeTrigger | undefined {
    return undefined;
  }

  schedulePageProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): void {
    this.runScheduledProbe(input, host, true);
  }

  scheduleSpaRouteProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): void {
    this.runScheduledProbe({
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      privacyMode: input.privacyMode,
      controller: input.controller
    }, host, true);
  }

  async runTakeoverProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): Promise<void> {
    await this.runProbeAndPublish(input, host, false, true).catch((_error: Error): void => {});
  }

  clearTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.generationByTab.set(normalizedTabId, this.resolveGeneration(normalizedTabId) + 1);
  }

  private runScheduledProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost,
    allowAsyncFollowup: boolean
  ): void {
    void this.runProbeAndPublish(input, host, allowAsyncFollowup, false).catch((_error: Error): void => {});
  }

  private async runProbeAndPublish(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost,
    allowAsyncFollowup: boolean,
    allowBlockingFallback: boolean
  ): Promise<void> {
    const generation = this.resolveGeneration(input.tabId);
    try {
      const outcome = await this.probe(input.controller, input.pageUrl, Date.now(), allowBlockingFallback);
      if (generation !== this.resolveGeneration(input.tabId) ||
        !host.shouldRunDelayedProbe(input.tabId, input.pageUrl, input.pageUrl)) {
        return;
      }
      if (outcome.report !== undefined && outcome.report.resources.length > 0) {
        host.onReport(this.copyProbeInput(input), outcome.report);
      }
      if (allowAsyncFollowup && outcome.pendingAsyncWork) {
        this.scheduleAsyncFollowup(input, host, generation);
      }
    } finally {
      host.onProbeSettled(input.tabId);
    }
  }

  private scheduleAsyncFollowup(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost,
    generation: number
  ): void {
    setTimeout((): void => {
      if (generation !== this.resolveGeneration(input.tabId) ||
        !host.shouldRunDelayedProbe(input.tabId, input.pageUrl, input.pageUrl)) {
        return;
      }
      this.runScheduledProbe({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        privacyMode: input.privacyMode,
        controller: input.controller
      }, host, false);
    }, XLPLAYER_ASYNC_FOLLOWUP_DELAY_MS);
  }

  private async probe(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    observedAt: number,
    allowBlockingFallback: boolean
  ): Promise<VideoCompatibilityXlPlayerProbeOutcome> {
    if (controller === undefined || this.profileAttribution.length <= 0) {
      return { pendingAsyncWork: false };
    }
    try {
      const raw = await controller.runJavaScript(this.buildScript(allowBlockingFallback));
      if (raw === null || raw === undefined || raw.length <= 0 || raw.length > MAX_RAW_PAYLOAD_LENGTH) {
        return { pendingAsyncWork: false };
      }
      return this.normalizePayload(this.unwrapJsonString(raw), pageUrl, observedAt);
    } catch (_error) {
      return { pendingAsyncWork: false };
    }
  }

  private normalizePayload(
    raw: string,
    pageUrl: string,
    observedAt: number
  ): VideoCompatibilityXlPlayerProbeOutcome {
    if (raw.length <= 0 || raw.length > MAX_RAW_PAYLOAD_LENGTH) {
      return { pendingAsyncWork: false };
    }
    let payload: VideoCompatibilityXlPlayerRawPayload;
    try {
      payload = JSON.parse(raw) as VideoCompatibilityXlPlayerRawPayload;
    } catch (_error) {
      return { pendingAsyncWork: false };
    }
    const expectedOrigin = this.resolveOrigin(pageUrl);
    if (payload === undefined || payload === null || payload.ok !== true || expectedOrigin.length <= 0 ||
      payload.origin !== expectedOrigin || !Array.isArray(payload.resources) ||
      payload.resources.length > MAX_ACQUISITION_RESOURCE_COUNT) {
      return { pendingAsyncWork: false };
    }
    const normalizedObservedAt = this.normalizeObservedAt(observedAt);
    const resources: VideoCompatibilityAcquisitionResource[] = [];
    for (let index: number = 0; index < payload.resources.length; index += 1) {
      const rawResource = payload.resources[index];
      const url = rawResource.url?.trim() ?? '';
      const mimeType = rawResource.mimeType?.trim() ?? '';
      if (!this.isHttpUrl(url) || url.length > MAX_RESOURCE_URL_LENGTH ||
        mimeType.length <= 0 || mimeType.length > MAX_MIME_TYPE_LENGTH || this.containsUrl(resources, url)) {
        continue;
      }
      resources.push({
        url: url,
        family: 'video',
        kind: 'progressive',
        mimeType: mimeType,
        provenance: 'profile_acquisition',
        profileAttribution: this.profileAttribution,
        observedAt: normalizedObservedAt
      });
    }
    const userAgent = payload.userAgent?.trim() ?? '';
    return {
      report: resources.length > 0 ? {
        resources: resources,
        accessContext: {
          pageUrl: pageUrl,
          referer: pageUrl,
          userAgent: userAgent.length > 0 && userAgent.length <= 1024 ? userAgent : undefined,
          originUrl: expectedOrigin
        }
      } : undefined,
      pendingAsyncWork: payload.pendingAsyncWork === true
    };
  }

  private buildScript(allowBlockingFallback: boolean): string {
    const script = `(function(){
  try {
    var resources = [];
    var seen = Object.create(null);
    var pendingAsyncWork = false;
    var allowBlockingFallback = __AIRA_XLPLAYER_ALLOW_BLOCKING_FALLBACK__;

    function normalizeUrl(value) {
      var url = String(value || '').substring(0, 8000)
        .replace(/\\\\u002[fF]/g, '/')
        .replace(/\\\\+\\//g, '/')
        .replace(/&amp;/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\\\\u003[dD]/g, '=')
        .replace(/\\\\u003[fF]/g, '?');
      if (url.indexOf('//') === 0) url = location.protocol + url;
      try {
        if (!/^https?:/i.test(url)) url = new URL(url, location.href).href;
      } catch (e) {
        return '';
      }
      return /^https?:/i.test(url) ? url : '';
    }

    function inferMimeType(key, url) {
      var lowerKey = String(key || '').toLowerCase();
      var lowerUrl = String(url || '').toLowerCase();
      if (lowerKey.indexOf('m3u8') >= 0 || lowerKey.indexOf('hls') >= 0 ||
        /\\.m3u8(?:[?#]|$)/i.test(lowerUrl)) return 'application/vnd.apple.mpegurl';
      if (/\\.webm(?:[?#]|$)/i.test(lowerUrl)) return 'video/webm';
      return 'video/mp4';
    }

    function addXlPlayerLineUrl(value, key) {
      if (!value) return;
      var urls = String(value).substring(0, 120000).split(',');
      for (var i = 0; i < urls.length && i < 24 && resources.length < 16; i++) {
        var url = normalizeUrl(urls[i]);
        if (!url || seen[url]) continue;
        seen[url] = true;
        resources.push({ url: url, mimeType: inferMimeType(key, url) });
      }
    }

    function scanTextForUrls(value) {
      var text = String(value || '').substring(0, 300000);
      var pattern = /(?:https?:\\/\\/|\\/\\/)[^"'<>\\s]+?\\.(?:m3u8|m3u|mp4|m4v|mov|webm)(?=$|[?#"'<>\\s])(?:[?#][^"'<>\\s]*)?/ig;
      var match;
      while ((match = pattern.exec(text)) !== null && resources.length < 16) {
        addXlPlayerLineUrl(match[0], 'url');
      }
    }

__AIRA_XLPLAYER_LINES_RUNTIME_FRAGMENT__
    scanXlPlayerLinesEndpoint();
    return JSON.stringify({
      ok: true,
      origin: String(location.origin || ''),
      resources: resources.slice(0, 16),
      pendingAsyncWork: pendingAsyncWork,
      userAgent: String((navigator && navigator.userAgent) || '').substring(0, 1024)
    });
  } catch (e) {
    return JSON.stringify({ ok: false, origin: '', resources: [], pendingAsyncWork: false });
  }
})()`;
    return script.replace(
      '__AIRA_XLPLAYER_ALLOW_BLOCKING_FALLBACK__',
      allowBlockingFallback ? 'true' : 'false'
    ).replace(
      '__AIRA_XLPLAYER_LINES_RUNTIME_FRAGMENT__',
      VIDEO_COMPATIBILITY_XLPLAYER_LINES_RUNTIME_FRAGMENT
    );
  }

  private copyProbeInput(
    input: VideoCompatibilityProfileAcquisitionProbeInput
  ): VideoCompatibilityProfileAcquisitionProbeInput {
    return {
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      privacyMode: input.privacyMode,
      controller: input.controller
    };
  }

  private containsUrl(resources: VideoCompatibilityAcquisitionResource[], url: string): boolean {
    for (let index: number = 0; index < resources.length; index += 1) {
      if (resources[index].url === url) {
        return true;
      }
    }
    return false;
  }

  private resolveGeneration(tabId: string): number {
    return this.generationByTab.get(tabId) ?? 0;
  }

  private normalizeObservedAt(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : Date.now();
  }

  private isHttpUrl(value: string): boolean {
    const normalized = value.toLowerCase();
    return normalized.startsWith('https://') || normalized.startsWith('http://');
  }

  private resolveOrigin(pageUrl: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(pageUrl.trim());
      const protocol = parsed.protocol.trim().toLowerCase();
      const hostname = parsed.hostname.trim().toLowerCase();
      const port = parsed.port?.trim() ?? '';
      if ((protocol !== 'http:' && protocol !== 'https:') || hostname.length <= 0) {
        return '';
      }
      const isDefaultPort = (protocol === 'http:' && port === '80') ||
        (protocol === 'https:' && port === '443');
      return protocol + '//' + hostname + (port.length > 0 && !isDefaultPort ? ':' + port : '');
    } catch (_error) {
      return '';
    }
  }

  private unwrapJsonString(raw: string): string {
    if (raw.length >= 2 && raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') {
      try {
        const decoded = JSON.parse(raw) as string;
        return typeof decoded === 'string' ? decoded : raw;
      } catch (_error) {
      }
    }
    return raw;
  }
}

const YOUTUBE_SPA_ROUTE_REPROBE_DELAY_MS: number = 1200;
const YOUTUBE_REQUEST_PROBE_REPROBE_DELAY_MS: number = 900;
const YOUTUBE_REQUEST_PROBE_THROTTLE_MS: number = 2500;

interface VideoCompatibilityYoutubeRequestContext {
  referer?: string;
  userAgent?: string;
  originUrl?: string;
}

interface VideoCompatibilityYoutubePendingProbe {
  input: VideoCompatibilityProfileAcquisitionProbeInput;
}

/**
 * The compiled YouTube Acquisition Recipe. It owns only recipe-local matching, extraction, throttling,
 * expected-video freshness, and late-result rejection. It cannot publish a candidate or decide any Video
 * Assistant authority; the Profile caller receives only a bounded resource report.
 */
class VideoCompatibilityYoutubeAcquisitionRecipeService implements
  VideoCompatibilityProfileAcquisitionCapability, VideoCompatibilityProfileAcquisitionScheduler {
  private readonly profileAttribution: string;
  private readonly urlMatcher: YoutubeUrlMatcher = new YoutubeUrlMatcher();
  private readonly extractor: YoutubeExtractorService = new YoutubeExtractorService();
  private readonly requestContextByTab: Map<string, VideoCompatibilityYoutubeRequestContext> = new Map();
  private readonly currentExpectedMediaIdByTab: Map<string, string> = new Map();
  private readonly pendingProbeByTab: Map<string, VideoCompatibilityYoutubePendingProbe> = new Map();
  private readonly inflightTabs: Set<string> = new Set();
  private readonly lastRequestProbeAtByTab: Map<string, number> = new Map();
  private readonly generationByTab: Map<string, number> = new Map();

  constructor(profileAttribution: string) {
    this.profileAttribution = profileAttribution.trim();
  }

  getScheduler(): VideoCompatibilityProfileAcquisitionScheduler | undefined {
    return this;
  }

  getReplacedGenericDeepProbeStrategyIds(): VideoCompatibilityReplacedGenericDeepProbeStrategyId[] {
    return [];
  }

  async acquire(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    observedAt: number,
    privacyMode: BrowserSessionPrivacyMode = 'regular'
  ): Promise<VideoCompatibilityAcquisitionReport | undefined> {
    if (controller === undefined || this.profileAttribution.length <= 0) {
      return undefined;
    }
    const match = this.urlMatcher.match(pageUrl);
    if (!match.isYoutubePage || (match.videoId?.trim().length ?? 0) <= 0) {
      return undefined;
    }
    return this.extractReport(
      controller,
      pageUrl,
      match.videoId ?? '',
      privacyMode,
      observedAt,
      undefined
    );
  }

  observeIntercept(
    input: VideoCompatibilityProfileAcquisitionInterceptInput
  ): VideoCompatibilityProfileAcquisitionProbeTrigger | undefined {
    if (input.requestUrl.trim().length <= 0 || !this.urlMatcher.match(input.requestUrl).isVideoplayback) {
      return undefined;
    }
    this.rememberRequestContext(input);
    const pageUrl = this.resolveRequestDrivenProbePageUrl(input);
    const match = this.urlMatcher.match(pageUrl);
    if (!match.isYoutubePage || (match.videoId?.trim().length ?? 0) <= 0) {
      return undefined;
    }
    this.handleExpectedMediaChange(input.tabId, match.videoId ?? '');
    const now = Date.now();
    const lastProbeAt = this.lastRequestProbeAtByTab.get(input.tabId) ?? 0;
    if (now - lastProbeAt < YOUTUBE_REQUEST_PROBE_THROTTLE_MS) {
      return undefined;
    }
    this.lastRequestProbeAtByTab.set(input.tabId, now);
    return {
      pageUrl: pageUrl,
      delayedProbeDelayMs: YOUTUBE_REQUEST_PROBE_REPROBE_DELAY_MS
    };
  }

  schedulePageProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): void {
    const match = this.urlMatcher.match(input.pageUrl);
    if (!match.isYoutubePage || (match.videoId?.trim().length ?? 0) <= 0) {
      return;
    }
    this.handleExpectedMediaChange(input.tabId, match.videoId ?? '');
    this.runScheduledProbe(input, host);
    const delayMs = Math.max(0, Math.floor(input.delayedProbeDelayMs ?? 0));
    if (delayMs <= 0) {
      return;
    }
    const expectedMediaId = match.videoId ?? '';
    setTimeout((): void => {
      if (!host.shouldRunDelayedProbe(input.tabId, input.pageUrl, expectedMediaId)) {
        return;
      }
      this.runScheduledProbe({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        privacyMode: input.privacyMode,
        controller: input.controller
      }, host);
    }, delayMs);
  }

  scheduleSpaRouteProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): void {
    this.schedulePageProbe({
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      privacyMode: input.privacyMode,
      controller: input.controller,
      delayedProbeDelayMs: YOUTUBE_SPA_ROUTE_REPROBE_DELAY_MS
    }, host);
  }

  async runTakeoverProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): Promise<void> {
    this.schedulePageProbe(input, host);
  }

  clearTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.generationByTab.set(normalizedTabId, this.resolveGeneration(normalizedTabId) + 1);
    this.requestContextByTab.delete(normalizedTabId);
    this.currentExpectedMediaIdByTab.delete(normalizedTabId);
    this.pendingProbeByTab.delete(normalizedTabId);
    this.inflightTabs.delete(normalizedTabId);
    this.lastRequestProbeAtByTab.delete(normalizedTabId);
  }

  private runScheduledProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): void {
    void this.runPageProbe(input, host).then((): void => {
      host.onProbeSettled(input.tabId);
    }).catch((_error: Error): void => {});
  }

  private async runPageProbe(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    host: VideoCompatibilityProfileAcquisitionProbeHost
  ): Promise<void> {
    if (input.controller === undefined) {
      return;
    }
    const match = this.urlMatcher.match(input.pageUrl);
    const expectedMediaId = match.videoId?.trim() ?? '';
    if (!match.isYoutubePage || expectedMediaId.length <= 0) {
      return;
    }
    this.handleExpectedMediaChange(input.tabId, expectedMediaId);
    const generation = this.resolveGeneration(input.tabId);
    if (this.inflightTabs.has(input.tabId)) {
      this.pendingProbeByTab.set(input.tabId, {
        input: this.copyProbeInput(input)
      });
      return;
    }
    this.inflightTabs.add(input.tabId);
    try {
      const report = await this.extractReport(
        input.controller,
        input.pageUrl,
        expectedMediaId,
        input.privacyMode,
        Date.now(),
        this.requestContextByTab.get(input.tabId)
      );
      if (report === undefined || generation !== this.resolveGeneration(input.tabId) ||
        this.currentExpectedMediaIdByTab.get(input.tabId) !== expectedMediaId ||
        !host.shouldRunDelayedProbe(input.tabId, input.pageUrl, expectedMediaId)) {
        return;
      }
      host.onReport(this.copyProbeInput(input), report);
    } finally {
      this.inflightTabs.delete(input.tabId);
      this.runPendingProbe(input.tabId, host);
    }
  }

  private runPendingProbe(tabId: string, host: VideoCompatibilityProfileAcquisitionProbeHost): void {
    const pending = this.pendingProbeByTab.get(tabId);
    if (pending === undefined) {
      return;
    }
    this.pendingProbeByTab.delete(tabId);
    const expectedMediaId = this.urlMatcher.match(pending.input.pageUrl).videoId?.trim() ?? '';
    if (expectedMediaId.length <= 0 || this.currentExpectedMediaIdByTab.get(tabId) !== expectedMediaId) {
      return;
    }
    void this.runPageProbe(pending.input, host);
  }

  private async extractReport(
    controller: webview.WebviewController,
    pageUrl: string,
    expectedMediaId: string,
    privacyMode: BrowserSessionPrivacyMode,
    observedAt: number,
    requestContext: VideoCompatibilityYoutubeRequestContext | undefined
  ): Promise<VideoCompatibilityAcquisitionReport> {
    const extraction = await this.extractor.extract(
      controller,
      pageUrl,
      expectedMediaId,
      privacyMode === 'private'
    );
    return this.buildReport(extraction.plan, extraction.selection, observedAt, requestContext);
  }

  private buildReport(
    plan: YoutubePlaybackPlan,
    selection: YoutubeFormatSelection,
    observedAt: number,
    requestContext: VideoCompatibilityYoutubeRequestContext | undefined
  ): VideoCompatibilityAcquisitionReport {
    const normalizedObservedAt = this.normalizeObservedAt(observedAt);
    const expiredByPlan = (plan.expiresAtMs ?? 0) > 0 && (plan.expiresAtMs ?? 0) <= normalizedObservedAt;
    const resources: VideoCompatibilityAcquisitionResource[] = [];
    if (!expiredByPlan && this.extractor.isProgressivePlayable(plan, selection)) {
      const progressive = this.fromYoutubeFormat(selection.progressive, 'video', 'progressive', normalizedObservedAt);
      if (progressive !== undefined) {
        resources.push(progressive);
      }
    } else if (!expiredByPlan && this.extractor.isAdaptiveOnly(plan, selection)) {
      const video = this.fromYoutubeFormat(selection.video, 'video', 'dash', normalizedObservedAt);
      const audio = this.fromYoutubeFormat(selection.audio, 'audio', 'dash', normalizedObservedAt);
      if (video !== undefined && audio !== undefined) {
        resources.push(video);
        resources.push(audio);
      }
    } else if (!expiredByPlan && plan.status === 'ok' && this.isHttpUrl(plan.hlsManifestUrl ?? '')) {
      resources.push({
        url: (plan.hlsManifestUrl ?? '').trim(),
        family: 'video',
        kind: 'progressive',
        mimeType: 'application/vnd.apple.mpegurl',
        durationMs: this.optionalInteger(plan.durationMs, 1, MAX_DURATION_MS),
        provenance: 'profile_acquisition',
        profileAttribution: this.profileAttribution,
        observedAt: normalizedObservedAt
      });
    }
    return {
      resources: resources,
      accessContext: this.buildAccessContext(plan, requestContext)
    };
  }

  private fromYoutubeFormat(
    format: YoutubeFormat | undefined,
    family: VideoCompatibilityAcquisitionResourceFamily,
    kind: VideoCompatibilityAcquisitionResourceKind,
    observedAt: number
  ): VideoCompatibilityAcquisitionResource | undefined {
    const url = format?.url.trim() ?? '';
    const mimeType = this.normalizeMimeType(format?.mimeType);
    if (!this.isHttpUrl(url) || mimeType.length <= 0) {
      return undefined;
    }
    return {
      url: url,
      family: family,
      kind: kind,
      mimeType: mimeType,
      codecs: this.optionalText(format?.codecs, MAX_CODEC_LENGTH),
      bandwidth: this.optionalInteger(format?.bitrate, 1, MAX_BANDWIDTH),
      contentLength: this.optionalInteger(format?.contentLength, 1, MAX_CONTENT_LENGTH),
      fps: family === 'video' ? this.optionalInteger(format?.fps, 1, 240) : undefined,
      audioSampleRate: family === 'audio' ? this.optionalInteger(format?.audioSampleRate, 1, 384000) : undefined,
      audioChannels: family === 'audio' ? this.optionalInteger(format?.audioChannels, 1, 32) : undefined,
      initializationRange: this.optionalRange(format?.initializationRange),
      indexRange: this.optionalRange(format?.indexRange),
      width: family === 'video' ? this.optionalInteger(format?.width, 1, MAX_DIMENSION) : undefined,
      height: family === 'video' ? this.optionalInteger(format?.height, 1, MAX_DIMENSION) : undefined,
      durationMs: this.optionalInteger(format?.durationMs, 1, MAX_DURATION_MS),
      provenance: 'profile_acquisition',
      profileAttribution: this.profileAttribution,
      observedAt: observedAt
    };
  }

  private buildAccessContext(
    plan: YoutubePlaybackPlan,
    requestContext: VideoCompatibilityYoutubeRequestContext | undefined
  ): VideoCompatibilityAcquisitionAccessContext {
    return {
      pageUrl: plan.pageUrl,
      referer: requestContext?.referer ?? 'https://www.youtube.com/',
      userAgent: plan.userAgent ?? requestContext?.userAgent,
      originUrl: requestContext?.originUrl ?? 'https://www.youtube.com'
    };
  }

  private rememberRequestContext(input: VideoCompatibilityProfileAcquisitionInterceptInput): void {
    const existing = this.requestContextByTab.get(input.tabId) ?? {};
    this.requestContextByTab.set(input.tabId, {
      referer: input.referer ?? existing.referer,
      userAgent: input.userAgent ?? existing.userAgent,
      originUrl: input.originUrl ?? existing.originUrl
    });
  }

  private resolveRequestDrivenProbePageUrl(input: VideoCompatibilityProfileAcquisitionInterceptInput): string {
    const referer = input.referer?.trim() ?? '';
    if (referer.length > 0 && this.urlMatcher.match(referer).isYoutubePage) {
      return referer;
    }
    const pageUrl = input.pageUrl.trim();
    return pageUrl.length > 0 ? pageUrl : 'https://www.youtube.com/';
  }

  private handleExpectedMediaChange(tabId: string, expectedMediaId: string): void {
    const normalizedId = expectedMediaId.trim();
    if (normalizedId.length > 0) {
      this.currentExpectedMediaIdByTab.set(tabId, normalizedId);
    }
  }

  private resolveGeneration(tabId: string): number {
    return this.generationByTab.get(tabId) ?? 0;
  }

  private copyProbeInput(input: VideoCompatibilityProfileAcquisitionProbeInput): VideoCompatibilityProfileAcquisitionProbeInput {
    return {
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      privacyMode: input.privacyMode,
      controller: input.controller
    };
  }

  private normalizeMimeType(value: string | undefined): string {
    const raw = value?.split(';')[0].trim() ?? '';
    return this.optionalText(raw, MAX_MIME_TYPE_LENGTH) ?? '';
  }

  private optionalText(value: string | undefined, maximumLength: number): string | undefined {
    const normalized = value?.trim() ?? '';
    return normalized.length > 0 && normalized.length <= maximumLength ? normalized : undefined;
  }

  private optionalInteger(value: number | undefined, minimum: number, maximum: number): number | undefined {
    if (value === undefined || !Number.isFinite(value)) {
      return undefined;
    }
    const normalized = Math.floor(value);
    return normalized >= minimum && normalized <= maximum ? normalized : undefined;
  }

  private optionalRange(value: string | undefined): string | undefined {
    const normalized = value?.trim() ?? '';
    if (normalized.length <= 0 || normalized.length > MAX_RANGE_LENGTH) {
      return undefined;
    }
    const divider = normalized.indexOf('-');
    if (divider <= 0 || divider !== normalized.lastIndexOf('-')) {
      return undefined;
    }
    return this.isDigits(normalized.substring(0, divider)) && this.isDigits(normalized.substring(divider + 1)) ?
      normalized : undefined;
  }

  private isDigits(value: string): boolean {
    if (value.length <= 0) {
      return false;
    }
    for (let index: number = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  private normalizeObservedAt(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : Date.now();
  }

  private isHttpUrl(value: string): boolean {
    const normalized = value.trim().toLowerCase();
    return normalized.startsWith('https://') || normalized.startsWith('http://');
  }
}

class VideoCompatibilityBilibiliAcquisitionCapability implements VideoCompatibilityProfileAcquisitionCapability {
  private readonly profileAttribution: string;
  private readonly recipeService: VideoCompatibilityBilibiliAcquisitionRecipeService =
    new VideoCompatibilityBilibiliAcquisitionRecipeService();

  constructor(profileAttribution: string) {
    this.profileAttribution = profileAttribution;
  }

  async acquire(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    observedAt: number,
    _privacyMode?: BrowserSessionPrivacyMode
  ): Promise<VideoCompatibilityAcquisitionReport | undefined> {
    const report = await this.recipeService.probe(
      controller,
      pageUrl,
      this.profileAttribution,
      observedAt
    );
    if (report === undefined) {
      return undefined;
    }
    return report;
  }

  getScheduler(): VideoCompatibilityProfileAcquisitionScheduler | undefined {
    return undefined;
  }

  getReplacedGenericDeepProbeStrategyIds(): VideoCompatibilityReplacedGenericDeepProbeStrategyId[] {
    return [];
  }
}

export function createVideoCompatibilityProfileAcquisitionCapability(
  recipeIdentity: string | undefined,
  profileAttribution: string
): VideoCompatibilityProfileAcquisitionCapability | undefined {
  const attribution = profileAttribution.trim();
  if (attribution.length <= 0) {
    return undefined;
  }
  if (recipeIdentity === 'bilibili_play_info') {
    return new VideoCompatibilityBilibiliAcquisitionCapability(attribution);
  }
  if (recipeIdentity === 'youtube_player') {
    return new VideoCompatibilityYoutubeAcquisitionRecipeService(attribution);
  }
  if (recipeIdentity === 'xlplayer_lines') {
    return new VideoCompatibilityXlPlayerAcquisitionRecipeService(attribution);
  }
  return undefined;
}

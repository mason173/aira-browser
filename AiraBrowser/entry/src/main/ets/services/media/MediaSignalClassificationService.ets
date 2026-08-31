import { BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import {
  MediaActionHint,
  MediaAuthContext,
  MediaCandidateFamily,
  MediaCandidateKind,
  MediaDetectionState,
  MediaDownloadabilityState,
  MediaEvidence,
  MediaFrameContext,
  MediaManifestContext,
  MediaPlaybackMetadata,
  MediaPlayabilityState
} from '../../features/mediaDiscovery/MediaCandidateModels';
import {
  MediaSignal,
  MediaSignalCost,
  MediaSignalKind
} from '../../features/mediaDiscovery/MediaSignalModels';
import { MediaResourceScoring } from '../../features/mediaDiscovery/MediaResourceScoring';
import {
  MediaResourceDomSignal,
  MediaResourceEvidence,
  MediaResourceFrameType
} from '../../features/mediaDiscovery/MediaResourceClassificationModels';
import {
  MediaResourceClassification,
  MediaResourceTypeRules
} from '../../features/mediaDiscovery/MediaResourceTypeRules';
import { MediaVideoScoring } from '../../features/mediaDiscovery/MediaVideoScoring';
import { MediaVideoTypeRules } from '../../features/mediaDiscovery/MediaVideoTypeRules';

export interface MediaSignalClassificationOptions {
  signalKind: MediaSignalKind;
  cost: MediaSignalCost;
}

export interface MediaResourceNetworkObservation {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  requestUrl: string;
  frameType?: MediaResourceFrameType;
  frameUrl?: string;
  isMainFrame?: boolean;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
  mimeType?: string;
  contentDisposition?: string;
  contentLength?: number;
  contentRange?: string;
  responseHeaders?: Record<string, string>;
}

export interface MediaResourceDomObservation {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  url: string;
  signal?: MediaResourceDomSignal;
  frameType?: MediaResourceFrameType;
  frameUrl?: string;
  isMainFrame?: boolean;
  mimeType?: string;
  posterUrl?: string;
  manifestText?: string;
  manifestBaseUrl?: string;
  pairedAudioUrl?: string;
  pairedAudioMimeType?: string;
  codecs?: string;
  bandwidth?: number;
  initializationRange?: string;
  indexRange?: string;
  pairedAudioCodecs?: string;
  pairedAudioBandwidth?: number;
  pairedAudioInitializationRange?: string;
  pairedAudioIndexRange?: string;
  durationMs?: number;
  width?: number;
  height?: number;
  fromBlob: boolean;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
  contentDisposition?: string;
  contentLength?: number;
  contentRange?: string;
  responseHeaders?: Record<string, string>;
}

export interface MediaVideoNetworkObservation {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  requestUrl: string;
  frameType?: MediaResourceFrameType;
  frameUrl?: string;
  isMainFrame?: boolean;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
  mimeType?: string;
}

export interface MediaVideoDomObservation {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  url: string;
  frameType?: MediaResourceFrameType;
  frameUrl?: string;
  isMainFrame?: boolean;
  signal?: MediaResourceDomSignal;
  mimeType?: string;
  posterUrl?: string;
  durationMs?: number;
  width?: number;
  height?: number;
  isPlaying?: boolean;
  hasPlayed?: boolean;
  readyState?: number;
  visible?: boolean;
  manifestText?: string;
  manifestBaseUrl?: string;
  pairedAudioUrl?: string;
  pairedAudioMimeType?: string;
  codecs?: string;
  bandwidth?: number;
  contentLength?: number;
  fps?: number;
  initializationRange?: string;
  indexRange?: string;
  pairedAudioCodecs?: string;
  pairedAudioBandwidth?: number;
  pairedAudioContentLength?: number;
  pairedAudioSampleRate?: number;
  pairedAudioChannels?: number;
  pairedAudioInitializationRange?: string;
  pairedAudioIndexRange?: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
  fromBlob: boolean;
}

interface ResourceSignalInput extends MediaResourceDomObservation {
  source: 'network' | 'dom';
  url: string;
  options: MediaSignalClassificationOptions;
}

interface VideoSignalInput extends MediaVideoDomObservation {
  source: 'network' | 'dom';
  url: string;
  extension?: string;
  options: MediaSignalClassificationOptions;
}

export class MediaSignalClassificationService {
  private resourceRules: MediaResourceTypeRules = new MediaResourceTypeRules();
  private resourceScoring: MediaResourceScoring = new MediaResourceScoring();
  private videoRules: MediaVideoTypeRules = new MediaVideoTypeRules();
  private videoScoring: MediaVideoScoring = new MediaVideoScoring();

  buildResourceNetworkSignal(observation: MediaResourceNetworkObservation): MediaSignal | undefined {
    return this.buildResourceSignal({
      tabId: observation.tabId,
      pageUrl: observation.pageUrl,
      pageTitle: observation.pageTitle,
      privacyMode: observation.privacyMode,
      url: observation.requestUrl,
      source: 'network',
      fromBlob: false,
      frameType: observation.frameType,
      frameUrl: observation.frameUrl,
      isMainFrame: observation.isMainFrame,
      referer: observation.referer,
      userAgent: observation.userAgent,
      originUrl: observation.originUrl,
      requestHeaders: observation.requestHeaders,
      mimeType: observation.mimeType,
      contentDisposition: observation.contentDisposition,
      contentLength: observation.contentLength,
      contentRange: observation.contentRange,
      responseHeaders: observation.responseHeaders,
      options: {
        signalKind: 'network_request',
        cost: 'cheap'
      }
    });
  }

  buildVideoNetworkSignal(observation: MediaVideoNetworkObservation): MediaSignal | undefined {
    if (observation.requestUrl.length <= 0) {
      return undefined;
    }
    const classification = this.videoRules.classifyByUrl(observation.requestUrl);
    if (classification.kind === 'unknown') {
      return undefined;
    }
    const score = this.videoScoring.computeScore({
      kind: classification.kind,
      source: 'network',
      isNoiseUrl: classification.noise,
      fromBlob: false,
      inferredFromUrlHint: classification.urlHint !== undefined
    });
    if (score <= 0) {
      return undefined;
    }
    return this.buildVideoSignal({
      tabId: observation.tabId,
      pageUrl: observation.pageUrl,
      pageTitle: observation.pageTitle,
      privacyMode: observation.privacyMode,
      url: observation.requestUrl,
      source: 'network',
      fromBlob: false,
      extension: classification.extension,
      frameType: observation.frameType,
      frameUrl: observation.frameUrl,
      isMainFrame: observation.isMainFrame,
      mimeType: observation.mimeType,
      referer: observation.referer,
      userAgent: observation.userAgent,
      originUrl: observation.originUrl,
      requestHeaders: observation.requestHeaders,
      options: {
        signalKind: 'network_request',
        cost: 'cheap'
      }
    });
  }

  buildResourceDomSignal(
    observation: MediaResourceDomObservation,
    options: MediaSignalClassificationOptions
  ): MediaSignal | undefined {
    return this.buildResourceSignal({
      tabId: observation.tabId,
      pageUrl: observation.pageUrl,
      pageTitle: observation.pageTitle,
      privacyMode: observation.privacyMode,
      url: observation.url,
      source: 'dom',
      fromBlob: observation.fromBlob,
      signal: observation.signal,
      frameType: observation.frameType,
      frameUrl: observation.frameUrl,
      isMainFrame: observation.isMainFrame,
      mimeType: observation.mimeType,
      posterUrl: observation.posterUrl,
      manifestText: observation.manifestText,
      manifestBaseUrl: observation.manifestBaseUrl,
      pairedAudioUrl: observation.pairedAudioUrl,
      pairedAudioMimeType: observation.pairedAudioMimeType,
      codecs: observation.codecs,
      bandwidth: observation.bandwidth,
      initializationRange: observation.initializationRange,
      indexRange: observation.indexRange,
      pairedAudioCodecs: observation.pairedAudioCodecs,
      pairedAudioBandwidth: observation.pairedAudioBandwidth,
      pairedAudioInitializationRange: observation.pairedAudioInitializationRange,
      pairedAudioIndexRange: observation.pairedAudioIndexRange,
      durationMs: observation.durationMs,
      width: observation.width,
      height: observation.height,
      referer: observation.referer,
      userAgent: observation.userAgent,
      originUrl: observation.originUrl,
      requestHeaders: observation.requestHeaders,
      contentDisposition: observation.contentDisposition,
      contentLength: observation.contentLength,
      contentRange: observation.contentRange,
      responseHeaders: observation.responseHeaders,
      options: options
    });
  }

  buildVideoDomSignal(
    observation: MediaVideoDomObservation,
    options: MediaSignalClassificationOptions
  ): MediaSignal | undefined {
    if (observation.url.length <= 0) {
      return undefined;
    }
    const mimeKind = this.videoRules.classifyByMime(observation.mimeType);
    const classification = this.videoRules.classifyByDomMediaMetadata(
      observation.url,
      observation.fromBlob,
      observation.durationMs,
      observation.width,
      observation.height
    );
    const pairedAudioUrl = observation.pairedAudioUrl?.trim() ?? '';
    const kind: MediaCandidateKind = pairedAudioUrl.length > 0 ? 'dash' : observation.fromBlob ? 'unknown' :
      (mimeKind !== 'unknown' ? mimeKind : classification.kind);
    if (kind === 'unknown') {
      return undefined;
    }
    const score = this.videoScoring.computeScore({
      kind: kind,
      source: 'dom',
      isNoiseUrl: classification.noise,
      fromBlob: observation.fromBlob,
      inferredFromUrlHint: classification.urlHint !== undefined
    });
    if (score <= 0) {
      return undefined;
    }
    return this.buildVideoSignal({
      tabId: observation.tabId,
      pageUrl: observation.pageUrl,
      pageTitle: observation.pageTitle,
      privacyMode: observation.privacyMode,
      url: observation.url,
      source: 'dom',
      fromBlob: observation.fromBlob,
      extension: classification.extension,
      frameType: observation.frameType,
      frameUrl: observation.frameUrl,
      isMainFrame: observation.isMainFrame,
      signal: observation.signal,
      mimeType: observation.mimeType,
      posterUrl: observation.posterUrl,
      durationMs: observation.durationMs,
      width: observation.width,
      height: observation.height,
      manifestText: observation.manifestText,
      manifestBaseUrl: observation.manifestBaseUrl,
      pairedAudioUrl: pairedAudioUrl.length > 0 ? pairedAudioUrl : undefined,
      pairedAudioMimeType: observation.pairedAudioMimeType,
      codecs: observation.codecs,
      bandwidth: observation.bandwidth,
      contentLength: observation.contentLength,
      fps: observation.fps,
      initializationRange: observation.initializationRange,
      indexRange: observation.indexRange,
      pairedAudioCodecs: observation.pairedAudioCodecs,
      pairedAudioBandwidth: observation.pairedAudioBandwidth,
      pairedAudioContentLength: observation.pairedAudioContentLength,
      pairedAudioSampleRate: observation.pairedAudioSampleRate,
      pairedAudioChannels: observation.pairedAudioChannels,
      pairedAudioInitializationRange: observation.pairedAudioInitializationRange,
      pairedAudioIndexRange: observation.pairedAudioIndexRange,
      referer: observation.referer,
      userAgent: observation.userAgent,
      originUrl: observation.originUrl,
      requestHeaders: observation.requestHeaders,
      options: options
    });
  }

  private buildResourceSignal(input: ResourceSignalInput): MediaSignal | undefined {
    if (input.url.length <= 0) {
      return undefined;
    }
    const classification = this.classifyResourceInput(input);
    if (classification.family === 'unknown') {
      return undefined;
    }
    const evidence = this.resolveResourceEvidence(input, classification.evidence);
    const score = this.resourceScoring.computeScore({
      family: classification.family,
      source: input.source,
      evidence: evidence,
      domSignal: input.signal,
      isNoiseUrl: classification.noise,
      fromBlob: input.fromBlob
    });
    if (score <= 0) {
      return undefined;
    }
    const actionHints = this.resolveResourceActionHints(input.url, classification.family, classification.kind, evidence);
    const signal: MediaSignal = {
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      source: input.source === 'network' ? 'resource_network' : 'resource_dom',
      signalKind: input.options.signalKind,
      url: input.url,
      family: this.mediaFamilyForResource(classification.family),
      kind: this.mediaKindForResource(classification.kind),
      evidence: this.buildResourceEvidence(input, evidence),
      confidence: score,
      detectionState: this.resourceDetectionState(classification.family, classification.kind),
      playabilityState: this.videoPlayabilityState(this.mediaKindForResource(classification.kind)),
      downloadabilityState: this.resourceDownloadabilityState(actionHints, input),
      actionHints: actionHints,
      frameContext: this.buildFrameContext(input),
      authContext: this.buildResourceAuthContext(input),
      manifestContext: this.buildMediaManifestContext(input),
      playbackMetadata: this.buildResourcePlaybackMetadata(input, classification),
      cost: input.options.cost,
      observedAt: Date.now()
    };
    return signal;
  }

  private buildVideoSignal(input: VideoSignalInput): MediaSignal | undefined {
    const classification = input.source === 'network' ?
      this.videoRules.classifyByUrl(input.url) :
      this.videoRules.classifyByDomMediaMetadata(input.url, input.fromBlob, input.durationMs, input.width, input.height);
    const pairedAudioUrl = input.pairedAudioUrl?.trim() ?? '';
    const mimeKind = this.videoRules.classifyByMime(input.mimeType);
    const kind: MediaCandidateKind = pairedAudioUrl.length > 0 ? 'dash' : input.source === 'dom' && mimeKind !== 'unknown' ?
      mimeKind : classification.kind;
    if (kind === 'unknown') {
      return undefined;
    }
    const score = this.videoScoring.computeScore({
      kind: kind,
      source: input.source,
      isNoiseUrl: classification.noise,
      fromBlob: input.fromBlob,
      inferredFromUrlHint: classification.urlHint !== undefined
    });
    const actionHints = this.resolveVideoActionHints(input.url, kind);
    const signal: MediaSignal = {
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      source: input.source === 'network' ? 'video_network' : 'video_dom',
      signalKind: input.options.signalKind,
      url: input.url,
      family: this.mediaFamilyForVideo(kind),
      kind: this.mediaKindForVideo(kind),
      evidence: this.buildVideoEvidence(input, kind),
      confidence: score,
      detectionState: 'detected',
      playabilityState: this.videoPlayabilityState(kind),
      downloadabilityState: this.videoDownloadabilityState(input.url, kind, input.requestHeaders),
      actionHints: actionHints,
      frameContext: input.frameType === undefined && input.frameUrl === undefined && input.isMainFrame === undefined ?
        undefined : {
          frameType: input.frameType,
          frameUrl: input.frameUrl,
          isMainFrame: input.isMainFrame
        },
      authContext: this.buildVideoAuthContext(input),
      manifestContext: this.buildVideoManifestContext(input),
      playbackMetadata: this.buildVideoPlaybackMetadata(input, input.extension ?? classification.extension),
      cost: input.options.cost,
      observedAt: Date.now()
    };
    return signal;
  }

  private classifyResourceInput(input: ResourceSignalInput): MediaResourceClassification {
    if ((input.pairedAudioUrl?.trim() ?? '').length > 0) {
      const urlClassification = this.resourceRules.classifyByUrl(input.url);
      return {
        family: 'manifest',
        kind: 'dash',
        extension: urlClassification.extension,
        evidence: input.source === 'dom' ? 'media_element' : 'mime',
        noise: urlClassification.noise
      };
    }
    const mimeClassification = this.resourceRules.classifyByMime(this.resolveMimeType(input));
    if (mimeClassification !== undefined && mimeClassification.family !== 'unknown') {
      const urlClassification = this.resourceRules.classifyByUrl(input.url);
      return {
        family: mimeClassification.family,
        kind: mimeClassification.kind,
        extension: urlClassification.extension,
        evidence: mimeClassification.evidence,
        noise: mimeClassification.noise || urlClassification.noise
      };
    }
    if (mimeClassification !== undefined && mimeClassification.noise) {
      return mimeClassification;
    }
    const urlClassification = this.resourceRules.classifyByUrl(input.url);
    const embeddedPlayerClassification = this.classifyEmbeddedPlayerFrame(input);
    if (embeddedPlayerClassification !== undefined) {
      return embeddedPlayerClassification;
    }
    if (urlClassification.family !== 'unknown' || input.source !== 'dom') {
      return urlClassification;
    }
    const domClassification = this.resourceRules.classifyByDomSignal(
      input.url,
      input.signal,
      this.hasMediaMetadata(input)
    );
    if (domClassification !== undefined) {
      return domClassification;
    }
    return urlClassification;
  }

  private classifyEmbeddedPlayerFrame(input: ResourceSignalInput): MediaResourceClassification | undefined {
    if (input.signal !== 'embedded_attribute' &&
      input.frameType !== 'dom_frame') {
      return undefined;
    }
    return this.resourceRules.classifyEmbeddedPlayerUrl(input.url);
  }

  private resolveResourceActionHints(
    url: string,
    family: MediaCandidateFamily,
    kind: MediaCandidateKind,
    evidence: MediaResourceEvidence
  ): MediaActionHint[] {
    const actions: MediaActionHint[] = [];
    if (!this.isHttpUrl(url)) {
      return actions;
    }
    if (family === 'manifest') {
      if (kind === 'hls') {
        this.pushAction(actions, 'download');
      } else {
        this.pushAction(actions, 'parse_manifest');
      }
      this.pushAction(actions, 'copy');
      return actions;
    }
    if (evidence === 'streaming_url_hint' || evidence === 'weak_text_match' || evidence === 'generic_url_hint') {
      this.pushAction(actions, 'copy');
      return actions;
    }
    if (family !== 'segment') {
      this.pushAction(actions, 'download');
    }
    this.pushAction(actions, 'copy');
    return actions;
  }

  private resolveVideoActionHints(url: string, kind: MediaCandidateKind): MediaActionHint[] {
    const actions: MediaActionHint[] = [];
    if (kind === 'hls') {
      if (this.isHttpUrl(url)) {
        this.pushAction(actions, 'download');
        this.pushAction(actions, 'copy');
      }
      return actions;
    }
    if (kind === 'dash') {
      if (this.isHttpUrl(url)) {
        this.pushAction(actions, 'parse_manifest');
        this.pushAction(actions, 'copy');
      }
      return actions;
    }
    if (this.isHttpUrl(url) && kind !== 'segment') {
      this.pushAction(actions, 'download');
      this.pushAction(actions, 'copy');
    } else if (this.isHttpUrl(url)) {
      this.pushAction(actions, 'copy');
    }
    return actions;
  }

  private resourceDetectionState(family: MediaCandidateFamily, kind: MediaCandidateKind): MediaDetectionState {
    return family === 'manifest' && kind !== 'hls' ? 'needs_processing' : 'detected';
  }

  private videoPlayabilityState(kind: MediaCandidateKind): MediaPlayabilityState {
    if (kind === 'hls' || kind === 'dash' || kind === 'mp4' || kind === 'webm') {
      return 'candidate';
    }
    return 'unknown';
  }

  private resourceDownloadabilityState(
    actionHints: MediaActionHint[],
    input: ResourceSignalInput
  ): MediaDownloadabilityState {
    if (actionHints.indexOf('download') >= 0) {
      return input.requestHeaders !== undefined ? 'needs_headers' : 'downloadable';
    }
    if (actionHints.indexOf('parse_manifest') >= 0) {
      return 'manifest';
    }
    if (actionHints.indexOf('copy') >= 0) {
      return 'copy_only';
    }
    return 'unknown';
  }

  private videoDownloadabilityState(
    url: string,
    kind: MediaCandidateKind,
    requestHeaders: Record<string, string> | undefined
  ): MediaDownloadabilityState {
    if (kind === 'hls') {
      return requestHeaders !== undefined ? 'needs_headers' : 'downloadable';
    }
    if (kind === 'dash') {
      return 'manifest';
    }
    if (this.isHttpUrl(url)) {
      return requestHeaders !== undefined ? 'needs_headers' : 'downloadable';
    }
    return 'unknown';
  }

  private buildResourceEvidence(input: ResourceSignalInput, evidence: MediaResourceEvidence): MediaEvidence[] {
    const items: MediaEvidence[] = [];
    this.appendEvidence(items, 'resource_source', input.source);
    this.appendEvidence(items, 'resource_evidence', evidence);
    if (input.signal !== undefined) {
      this.appendEvidence(items, 'dom_signal', input.signal);
    }
    const mimeType = this.resolveMimeType(input);
    if (mimeType !== undefined) {
      this.appendEvidence(items, 'mime', mimeType);
    }
    return items;
  }

  private buildVideoEvidence(input: VideoSignalInput, kind: MediaCandidateKind): MediaEvidence[] {
    const items: MediaEvidence[] = [];
    this.appendEvidence(items, 'video_source', input.source);
    this.appendEvidence(items, 'video_kind', kind);
    const projectionEvidence = this.resolveVideoProjectionEvidence(input);
    if (projectionEvidence !== undefined) {
      this.appendEvidence(items, 'resource_evidence', projectionEvidence);
    }
    if (input.signal !== undefined) {
      this.appendEvidence(items, 'dom_signal', input.signal);
    }
    if (input.mimeType !== undefined) {
      this.appendEvidence(items, 'mime', input.mimeType);
    }
    if (input.isPlaying === true) {
      this.appendEvidence(items, 'playback_state', 'playing');
    } else if (input.hasPlayed === true) {
      this.appendEvidence(items, 'playback_state', 'started');
    }
    if (input.visible === true) {
      this.appendEvidence(items, 'playback_visibility', 'visible');
    }
    if (input.readyState !== undefined && input.readyState >= 2) {
      this.appendEvidence(items, 'playback_readiness', 'current_data');
    }
    const urlClassification = this.videoRules.classifyByUrl(input.url);
    if (urlClassification.urlHint !== undefined) {
      this.appendEvidence(items, 'video_url_hint', urlClassification.urlHint);
    }
    if (urlClassification.noise) {
      this.appendEvidence(items, 'url_quality', 'noise');
    }
    return items;
  }

  private resolveVideoProjectionEvidence(input: VideoSignalInput): MediaResourceEvidence | undefined {
    if (input.source === 'dom') {
      switch (input.signal) {
        case 'video_element':
        case 'audio_element': return 'media_element';
        case 'embedded_attribute':
        case 'performance_entry': {
          const mimeKind = this.videoRules.classifyByMime(input.mimeType);
          return mimeKind !== 'unknown' ? 'mime' : 'streaming_url_hint';
        }
        case 'script_text':
        case 'location':
        case 'text_match': return 'weak_text_match';
        default:
          break;
      }
      if (input.mimeType !== undefined && this.videoRules.classifyByMime(input.mimeType) !== 'unknown') {
        return 'mime';
      }
      return input.extension !== undefined ? 'explicit_extension' : undefined;
    }
    if (input.mimeType !== undefined && this.videoRules.classifyByMime(input.mimeType) !== 'unknown') {
      return 'mime';
    }
    return input.extension !== undefined ? 'explicit_extension' : undefined;
  }

  private buildFrameContext(input: ResourceSignalInput): MediaFrameContext | undefined {
    if (input.frameType === undefined && input.frameUrl === undefined && input.isMainFrame === undefined) {
      return undefined;
    }
    return {
      frameType: input.frameType,
      frameUrl: input.frameUrl,
      isMainFrame: input.isMainFrame
    };
  }

  private buildResourceAuthContext(input: ResourceSignalInput): MediaAuthContext {
    return {
      pageUrl: input.pageUrl,
      referer: input.referer,
      userAgent: input.userAgent,
      originUrl: input.originUrl,
      requestHeaders: input.requestHeaders,
      responseHeaders: input.responseHeaders
    };
  }

  private buildVideoAuthContext(input: VideoSignalInput): MediaAuthContext {
    return {
      pageUrl: input.pageUrl,
      referer: input.referer,
      userAgent: input.userAgent,
      originUrl: input.originUrl,
      requestHeaders: input.requestHeaders
    };
  }

  private buildMediaManifestContext(input: ResourceSignalInput): MediaManifestContext | undefined {
    if (!this.hasManifestContext(input.manifestText, input.manifestBaseUrl, input.pairedAudioUrl, input.codecs)) {
      return undefined;
    }
    return {
      manifestText: input.manifestText,
      manifestBaseUrl: input.manifestBaseUrl,
      pairedAudioUrl: input.pairedAudioUrl,
      pairedAudioMimeType: input.pairedAudioMimeType,
      codecs: input.codecs,
      bandwidth: input.bandwidth,
      initializationRange: input.initializationRange,
      indexRange: input.indexRange,
      pairedAudioCodecs: input.pairedAudioCodecs,
      pairedAudioBandwidth: input.pairedAudioBandwidth,
      pairedAudioInitializationRange: input.pairedAudioInitializationRange,
      pairedAudioIndexRange: input.pairedAudioIndexRange
    };
  }

  private buildVideoManifestContext(input: VideoSignalInput): MediaManifestContext | undefined {
    if (!this.hasManifestContext(input.manifestText, input.manifestBaseUrl, input.pairedAudioUrl, input.codecs)) {
      return undefined;
    }
    return {
      manifestText: input.manifestText,
      manifestBaseUrl: input.manifestBaseUrl,
      pairedAudioUrl: input.pairedAudioUrl,
      pairedAudioMimeType: input.pairedAudioMimeType,
      codecs: input.codecs,
      bandwidth: input.bandwidth,
      contentLength: input.contentLength,
      fps: input.fps,
      initializationRange: input.initializationRange,
      indexRange: input.indexRange,
      pairedAudioCodecs: input.pairedAudioCodecs,
      pairedAudioBandwidth: input.pairedAudioBandwidth,
      pairedAudioContentLength: input.pairedAudioContentLength,
      pairedAudioSampleRate: input.pairedAudioSampleRate,
      pairedAudioChannels: input.pairedAudioChannels,
      pairedAudioInitializationRange: input.pairedAudioInitializationRange,
      pairedAudioIndexRange: input.pairedAudioIndexRange
    };
  }

  private buildResourcePlaybackMetadata(
    input: ResourceSignalInput,
    classification: MediaResourceClassification
  ): MediaPlaybackMetadata {
    return {
      displayName: this.resolveDisplayName(input),
      sourceHost: this.resourceRules.resolveHost(input.url),
      extension: classification.extension,
      mimeType: this.resolveMimeType(input),
      contentDisposition: this.resolveContentDisposition(input),
      totalBytes: this.resolveTotalBytes(input),
      durationMs: input.durationMs,
      width: input.width,
      height: input.height,
      posterUrl: input.posterUrl
    };
  }

  private buildVideoPlaybackMetadata(
    input: VideoSignalInput,
    extension: string | undefined
  ): MediaPlaybackMetadata {
    return {
      extension: extension,
      mimeType: input.mimeType,
      durationMs: input.durationMs,
      width: input.width,
      height: input.height,
      posterUrl: input.posterUrl
    };
  }

  private hasManifestContext(
    manifestText: string | undefined,
    manifestBaseUrl: string | undefined,
    pairedAudioUrl: string | undefined,
    codecs: string | undefined
  ): boolean {
    return (manifestText?.length ?? 0) > 0 || (manifestBaseUrl?.length ?? 0) > 0 ||
      (pairedAudioUrl?.length ?? 0) > 0 || (codecs?.length ?? 0) > 0;
  }

  private resolveMimeType(input: ResourceSignalInput): string | undefined {
    const explicit = input.mimeType?.trim() ?? '';
    if (explicit.length > 0) {
      return explicit;
    }
    return this.getHeader(input.responseHeaders, 'content-type');
  }

  private resolveContentDisposition(input: ResourceSignalInput): string | undefined {
    const explicit = input.contentDisposition?.trim() ?? '';
    if (explicit.length > 0) {
      return explicit;
    }
    return this.getHeader(input.responseHeaders, 'content-disposition');
  }

  private resolveTotalBytes(input: ResourceSignalInput): number | undefined {
    const rangeTotal =
      this.resolveTotalBytesFromContentRange(input.contentRange ?? this.getHeader(input.responseHeaders, 'content-range') ?? '');
    if (rangeTotal > 0) {
      return rangeTotal;
    }
    if (input.contentLength !== undefined && input.contentLength > 0) {
      return Math.floor(input.contentLength);
    }
    const contentLength = Number(this.getHeader(input.responseHeaders, 'content-length') ?? '');
    return Number.isFinite(contentLength) && contentLength > 0 ? Math.floor(contentLength) : undefined;
  }

  private resolveDisplayName(input: ResourceSignalInput): string {
    const dispositionFileName = this.resolveFileNameFromContentDisposition(this.resolveContentDisposition(input) ?? '');
    if (dispositionFileName.length > 0) {
      return dispositionFileName;
    }
    return this.resourceRules.resolveDisplayName(input.url);
  }

  private resolveFileNameFromContentDisposition(value: string): string {
    const normalized = value.trim();
    if (normalized.length <= 0) {
      return '';
    }
    const encodedMatch = /filename\*\s*=\s*([^;]+)/i.exec(normalized);
    if (encodedMatch !== null) {
      const decoded = this.decodeRfc5987FileName(this.stripQuotes(encodedMatch[1]));
      if (decoded.length > 0) {
        return decoded;
      }
    }
    const plainMatch = /filename\s*=\s*([^;]+)/i.exec(normalized);
    if (plainMatch !== null) {
      return this.safeDecodeURIComponent(this.stripQuotes(plainMatch[1]));
    }
    return '';
  }

  private decodeRfc5987FileName(value: string): string {
    const marker = value.indexOf("''");
    const encoded = marker >= 0 ? value.substring(marker + 2) : value;
    return this.safeDecodeURIComponent(encoded);
  }

  private resolveTotalBytesFromContentRange(value: string): number {
    const match = /^bytes\s+\d+-\d+\/(\d+|\*)$/i.exec(value.trim());
    if (match === null || match[1] === '*') {
      return 0;
    }
    const total = Number(match[1]);
    return Number.isFinite(total) && total > 0 ? Math.floor(total) : 0;
  }

  private getHeader(headers: Record<string, string> | undefined, name: string): string | undefined {
    if (headers === undefined) {
      return undefined;
    }
    const target = name.trim().toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].trim().toLowerCase() === target) {
        const value = headers[keys[i]]?.trim() ?? '';
        return value.length > 0 ? value : undefined;
      }
    }
    return undefined;
  }

  private stripQuotes(value: string): string {
    const trimmed = value.trim();
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  private safeDecodeURIComponent(value: string): string {
    try {
      return decodeURIComponent(value).trim();
    } catch (_error) {
      return value.trim();
    }
  }

  private resolveResourceEvidence(
    input: ResourceSignalInput,
    evidence: MediaResourceEvidence
  ): MediaResourceEvidence {
    if (input.source !== 'dom') {
      return evidence;
    }
    if (evidence === 'explicit_extension' || evidence === 'generic_url_hint') {
      switch (input.signal) {
        case 'video_element':
        case 'audio_element': return 'media_element';
        case 'image_element': return 'image_element';
        case 'script_text':
        case 'location':
        case 'text_match': return 'weak_text_match';
        default: return evidence;
      }
    }
    if (evidence === 'streaming_url_hint' && input.signal === 'script_text') {
      return 'weak_text_match';
    }
    return evidence;
  }

  private hasMediaMetadata(input: ResourceSignalInput): boolean {
    return (input.durationMs !== undefined && input.durationMs > 0) ||
      (input.width !== undefined && input.width > 0) ||
      (input.height !== undefined && input.height > 0);
  }

  private mediaFamilyForResource(family: MediaCandidateFamily): MediaCandidateFamily {
    switch (family) {
      case 'video': return 'video';
      case 'audio': return 'audio';
      case 'image': return 'image';
      case 'file': return 'file';
      case 'manifest': return 'manifest';
      case 'segment': return 'segment';
      default: return 'unknown';
    }
  }

  private mediaFamilyForVideo(kind: MediaCandidateKind): MediaCandidateFamily {
    switch (kind) {
      case 'hls':
      case 'dash': return 'manifest';
      case 'audio': return 'audio';
      case 'segment': return 'segment';
      case 'mp4':
      case 'webm': return 'video';
      default: return 'unknown';
    }
  }

  private mediaKindForResource(kind: MediaCandidateKind): MediaCandidateKind {
    switch (kind) {
      case 'hls': return 'hls';
      case 'dash': return 'dash';
      case 'mp4': return 'mp4';
      case 'webm': return 'webm';
      case 'mov': return 'mov';
      case 'flv': return 'flv';
      case 'mkv': return 'mkv';
      case 'avi': return 'avi';
      case 'mpeg': return 'mpeg';
      case 'wmv': return 'wmv';
      case 'ogv': return 'ogv';
      case 'audio': return 'audio';
      case 'image': return 'image';
      case 'document': return 'document';
      case 'archive': return 'archive';
      case 'package': return 'package';
      case 'segment': return 'segment';
      default: return 'unknown';
    }
  }

  private mediaKindForVideo(kind: MediaCandidateKind): MediaCandidateKind {
    switch (kind) {
      case 'hls': return 'hls';
      case 'dash': return 'dash';
      case 'mp4': return 'mp4';
      case 'webm': return 'webm';
      case 'audio': return 'audio';
      case 'segment': return 'segment';
      default: return 'unknown';
    }
  }

  private appendEvidence(items: MediaEvidence[], kind: string, value: string): void {
    const normalized = value.trim();
    if (normalized.length <= 0) {
      return;
    }
    items.push({
      kind: kind,
      value: normalized
    });
  }

  private pushAction(actions: MediaActionHint[], action: MediaActionHint): void {
    if (actions.indexOf(action) < 0) {
      actions.push(action);
    }
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
  }
}

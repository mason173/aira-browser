import { webview } from '@kit.ArkWeb';
import { BrowserSessionPrivacyMode } from '../../../common/models/BrowserModels';
import { MediaSignal } from '../../../features/mediaDiscovery/MediaSignalModels';
import {
  MediaAcquisitionFacts,
  MediaAcquisitionTrack,
  MediaAcquisitionTrackRole
} from '../../../features/mediaDiscovery/MediaCandidateModels';
import { buildVideoPlaybackDiagnosticSummary } from '../../../features/mediaDiscovery/MediaVideoDeepProbeScript';
import { MediaResourceDomProbeService } from '../../../services/media/MediaResourceDomProbeService';
import { MediaVideoDeepProbeService } from '../../../services/media/MediaVideoDeepProbeService';
import { MediaVideoDomProbeService } from '../../../services/media/MediaVideoDomProbeService';
import { VideoCompatibilityProfileSelectorProbeService } from '../../../services/media/VideoCompatibilityProfileSelectorProbeService';
import {
  VideoCompatibilityProfileSelectorPlan
} from '../../../services/media/VideoCompatibilityProfileCatalog';
import {
  MediaCompatibilitySelectorEvidenceObservation
} from '../../../features/mediaDiscovery/MediaEvidenceGraphModels';
import {
  MediaSignalClassificationOptions,
  MediaSignalClassificationService
} from '../../../services/media/MediaSignalClassificationService';
import {
  VideoCompatibilityAcquisitionReport,
  VideoCompatibilityAcquisitionResource,
  VideoCompatibilityReplacedGenericDeepProbeStrategyId
} from '../../../services/media/VideoCompatibilityProfileAcquisitionRecipeService';

export type BrowserMediaProbeDomSignalKind = 'dom_probe' | 'userscript_request';
export type BrowserMediaDeepProbeIntent = 'scheduled' | 'user_intent';

export interface BrowserMediaProbeInterceptInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  request: WebResourceRequest;
}

export interface BrowserMediaProbePageInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  controller: webview.WebviewController | undefined;
  signalKind?: BrowserMediaProbeDomSignalKind;
}

export interface BrowserMediaDeepProbeInput extends BrowserMediaProbePageInput {
  intent: BrowserMediaDeepProbeIntent;
  replacedGenericDeepProbeStrategyIds?: VideoCompatibilityReplacedGenericDeepProbeStrategyId[];
}

export interface BrowserMediaProbeReport {
  signals: MediaSignal[];
}

export interface BrowserMediaDeepProbeReport {
  diagnosticSummary: string;
  pendingAsyncWork: boolean;
  resultCount: number;
  signals: MediaSignal[];
}

export interface BrowserMediaProfileAcquisitionProjectionInput extends BrowserMediaProbePageInput {
  report: VideoCompatibilityAcquisitionReport;
  profileAttribution: string;
}

export class BrowserMediaProbeBridge {
  private resourceDomScanService: MediaResourceDomProbeService;
  private videoDomScanService: MediaVideoDomProbeService;
  private videoDeepProbeService: MediaVideoDeepProbeService;
  private selectorProbeService: VideoCompatibilityProfileSelectorProbeService =
    new VideoCompatibilityProfileSelectorProbeService();
  private signalClassifier: MediaSignalClassificationService;

  constructor(
    resourceDomScanService: MediaResourceDomProbeService,
    videoDomScanService: MediaVideoDomProbeService,
    videoDeepProbeService: MediaVideoDeepProbeService,
    signalClassifier: MediaSignalClassificationService = new MediaSignalClassificationService()
  ) {
    this.resourceDomScanService = resourceDomScanService;
    this.videoDomScanService = videoDomScanService;
    this.videoDeepProbeService = videoDeepProbeService;
    this.signalClassifier = signalClassifier;
  }

  observeResourceIntercept(input: BrowserMediaProbeInterceptInput): MediaSignal | undefined {
    try {
      const url = input.request.getRequestUrl();
      if (url.length === 0) {
        return undefined;
      }
      const isMainFrame = this.safeIsMainFrame(input.request);
      return this.signalClassifier.buildResourceNetworkSignal({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        requestUrl: url,
        frameType: isMainFrame ? 'main_frame' : 'sub_frame',
        frameUrl: isMainFrame ? input.pageUrl : this.safeHeader(input.request, 'Referer'),
        isMainFrame: isMainFrame,
        referer: this.safeHeader(input.request, 'Referer'),
        userAgent: this.safeHeader(input.request, 'User-Agent'),
        originUrl: this.safeHeader(input.request, 'Origin'),
        requestHeaders: this.safeHeaders(input.request)
      });
    } catch (_error) {
      return undefined;
    }
  }

  observeVideoIntercept(input: BrowserMediaProbeInterceptInput): MediaSignal | undefined {
    try {
      const url = input.request.getRequestUrl();
      if (url.length === 0) {
        return undefined;
      }
      const referer = this.safeHeader(input.request, 'Referer');
      const userAgent = this.safeHeader(input.request, 'User-Agent');
      const origin = this.safeHeader(input.request, 'Origin');
      return this.signalClassifier.buildVideoNetworkSignal({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        requestUrl: url,
        frameType: 'unknown',
        referer: referer,
        userAgent: userAgent,
        originUrl: origin,
        requestHeaders: this.safeHeaders(input.request)
      });
    } catch (_error) {
      return undefined;
    }
  }

  async runResourceDomScan(input: BrowserMediaProbePageInput): Promise<BrowserMediaProbeReport> {
    const signals: MediaSignal[] = [];
    if (input.controller === undefined) {
      return this.emptySignalReport();
    }
    const payload = await this.resourceDomScanService.scan(input.controller);
    if (!payload.ok) {
      return this.emptySignalReport();
    }
    const options = this.probeSignalOptions(input.signalKind ?? 'dom_probe');
    for (let i = 0; i < payload.results.length; i++) {
      const item = payload.results[i];
      const signal = this.signalClassifier.buildResourceDomSignal({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        url: item.url,
        signal: item.signal,
        frameType: item.frameType,
        frameUrl: item.frameUrl,
        mimeType: item.mimeType,
        posterUrl: item.posterUrl,
        durationMs: item.durationMs,
        width: item.width,
        height: item.height,
        contentLength: item.totalBytes,
        fromBlob: item.fromBlob === true
      }, options);
      if (signal !== undefined) {
        signals.push(signal);
      }
    }
    return this.buildSignalReport(signals);
  }

  async runVideoDomScan(input: BrowserMediaProbePageInput): Promise<BrowserMediaProbeReport> {
    const signals: MediaSignal[] = [];
    if (input.controller === undefined) {
      return this.emptySignalReport();
    }
    const payload = await this.videoDomScanService.scan(input.controller);
    if (!payload.ok) {
      return this.emptySignalReport();
    }
    const options = this.probeSignalOptions(input.signalKind ?? 'dom_probe');
    for (let i = 0; i < payload.results.length; i++) {
      const item = payload.results[i];
      const signal = this.signalClassifier.buildVideoDomSignal({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        url: item.url,
        signal: item.signal,
        mimeType: item.mimeType,
        posterUrl: item.posterUrl,
        durationMs: item.durationMs,
        width: item.width,
        height: item.height,
        isPlaying: item.isPlaying,
        hasPlayed: item.hasPlayed,
        readyState: item.readyState,
        visible: item.visible,
        fromBlob: item.fromBlob === true
      }, options);
      if (signal !== undefined) {
        signals.push(signal);
      }
    }
    return this.buildSignalReport(signals);
  }

  async runDeepProbe(input: BrowserMediaDeepProbeInput): Promise<BrowserMediaDeepProbeReport> {
    if (input.controller === undefined) {
      return this.emptyDeepProbeReport();
    }
    const payload = await this.videoDeepProbeService.probe(
      input.controller,
      input.intent === 'user_intent',
      input.replacedGenericDeepProbeStrategyIds ?? []
    );
    if (!payload.ok) {
      return this.emptyDeepProbeReport();
    }
    const signals: MediaSignal[] = [];
    const deepOptions: MediaSignalClassificationOptions = {
      signalKind: 'deep_probe',
      cost: 'expensive'
    };
    for (let i = 0; i < payload.results.length; i++) {
      const item = payload.results[i];
      const manifestBaseUrl = item.manifestBaseUrl ?? item.url;
      const effectiveUrl = item.fromBlob === true && this.isHttpUrl(manifestBaseUrl) ? manifestBaseUrl : item.url;
      if (item.fromBlob !== true) {
        const videoSignal = this.signalClassifier.buildVideoDomSignal({
          tabId: input.tabId,
          pageUrl: input.pageUrl,
          pageTitle: input.pageTitle,
          privacyMode: input.privacyMode,
          url: effectiveUrl,
          signal: item.signal,
          mimeType: item.mimeType,
          posterUrl: item.posterUrl,
          manifestText: item.manifestText,
          manifestBaseUrl: manifestBaseUrl,
          pairedAudioUrl: item.pairedAudioUrl,
          pairedAudioMimeType: item.pairedAudioMimeType,
          codecs: item.codecs,
          bandwidth: item.bandwidth,
          initializationRange: item.initializationRange,
          indexRange: item.indexRange,
          pairedAudioCodecs: item.pairedAudioCodecs,
          pairedAudioBandwidth: item.pairedAudioBandwidth,
          pairedAudioInitializationRange: item.pairedAudioInitializationRange,
          pairedAudioIndexRange: item.pairedAudioIndexRange,
          durationMs: item.durationMs,
          width: item.width,
          height: item.height,
          referer: item.referer ?? input.pageUrl,
          userAgent: item.userAgent,
          originUrl: item.originUrl,
          fromBlob: false
        }, deepOptions);
        if (videoSignal !== undefined) {
          signals.push(videoSignal);
        }
      }
      const resourceSignal = this.signalClassifier.buildResourceDomSignal({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        url: effectiveUrl,
        signal: item.signal,
        frameType: 'dom_document',
        frameUrl: input.pageUrl,
        mimeType: item.mimeType,
        posterUrl: item.posterUrl,
        manifestText: item.manifestText,
        manifestBaseUrl: manifestBaseUrl,
        pairedAudioUrl: item.pairedAudioUrl,
        pairedAudioMimeType: item.pairedAudioMimeType,
        codecs: item.codecs,
        bandwidth: item.bandwidth,
        initializationRange: item.initializationRange,
        indexRange: item.indexRange,
        pairedAudioCodecs: item.pairedAudioCodecs,
        pairedAudioBandwidth: item.pairedAudioBandwidth,
        pairedAudioInitializationRange: item.pairedAudioInitializationRange,
        pairedAudioIndexRange: item.pairedAudioIndexRange,
        durationMs: item.durationMs,
        width: item.width,
        height: item.height,
        referer: item.referer ?? input.pageUrl,
        userAgent: item.userAgent,
        originUrl: item.originUrl,
        fromBlob: item.fromBlob === true && effectiveUrl === item.url
      }, deepOptions);
      if (resourceSignal !== undefined) {
        signals.push(resourceSignal);
      }
    }
    return {
      diagnosticSummary: buildVideoPlaybackDiagnosticSummary(payload.diagnostics),
      pendingAsyncWork: payload.pendingAsyncWork === true,
      resultCount: payload.results.length,
      signals: signals
    };
  }

  /**
   * Projects a bounded Profile Acquisition report into ordinary site-neutral Media Signals. The Profile
   * contributes only attributed observations; Session, Route, Reachability, and Entry Eligibility remain
   * owned by the existing generic evidence/runtime owners.
   */
  projectProfileAcquisitionReport(
    input: BrowserMediaProfileAcquisitionProjectionInput
  ): BrowserMediaProbeReport {
    const signals: MediaSignal[] = [];
    const audioResources: VideoCompatibilityAcquisitionResource[] = [];
    for (let index: number = 0; index < input.report.resources.length; index += 1) {
      const resource = input.report.resources[index];
      if (this.isCurrentProfileResource(resource, input.profileAttribution) &&
        resource.family === 'audio' && resource.kind === 'dash') {
        audioResources.push(resource);
      }
    }
    const pairedAudio = audioResources.length > 0 ? audioResources[0] : undefined;
    for (let index: number = 0; index < input.report.resources.length; index += 1) {
      const resource = input.report.resources[index];
      if (!this.isCurrentProfileResource(resource, input.profileAttribution)) {
        continue;
      }
      if (resource.family === 'video') {
        const paired = resource.kind === 'dash' ? pairedAudio : undefined;
        const accessContext = input.report.accessContext;
        const signal = this.signalClassifier.buildVideoDomSignal({
          tabId: input.tabId,
          pageUrl: input.pageUrl,
          pageTitle: input.pageTitle,
          privacyMode: input.privacyMode,
          url: resource.url,
          signal: 'video_element',
          frameType: 'dom_document',
          frameUrl: input.pageUrl,
          isMainFrame: true,
          mimeType: resource.mimeType,
          pairedAudioUrl: paired?.url,
          pairedAudioMimeType: paired?.mimeType,
          codecs: resource.codecs,
          bandwidth: resource.bandwidth,
          contentLength: resource.contentLength,
          fps: resource.fps,
          initializationRange: resource.initializationRange,
          indexRange: resource.indexRange,
          pairedAudioCodecs: paired?.codecs,
          pairedAudioBandwidth: paired?.bandwidth,
          pairedAudioContentLength: paired?.contentLength,
          pairedAudioSampleRate: paired?.audioSampleRate,
          pairedAudioChannels: paired?.audioChannels,
          pairedAudioInitializationRange: paired?.initializationRange,
          pairedAudioIndexRange: paired?.indexRange,
          durationMs: resource.durationMs,
          width: resource.width,
          height: resource.height,
          referer: accessContext?.referer ?? input.pageUrl,
          userAgent: accessContext?.userAgent,
          originUrl: accessContext?.originUrl,
          fromBlob: false
        }, {
          signalKind: 'site_extractor',
          cost: 'expensive'
        });
        if (signal !== undefined) {
          signal.authContext = {
            pageUrl: accessContext?.pageUrl ?? input.pageUrl,
            referer: accessContext?.referer ?? input.pageUrl,
            userAgent: accessContext?.userAgent,
            originUrl: accessContext?.originUrl
          };
          signal.acquisition = this.buildProfileAcquisitionFacts(resource, paired);
          this.appendProfileAttribution(signal, resource);
          signals.push(signal);
        }
        continue;
      }
      if (resource.family !== 'audio' || resource.kind === 'dash' && pairedAudio !== undefined) {
        continue;
      }
      const audioSignal = this.signalClassifier.buildResourceDomSignal({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        url: resource.url,
        signal: 'audio_element',
        frameType: 'dom_document',
        frameUrl: input.pageUrl,
        isMainFrame: true,
        mimeType: resource.mimeType,
        durationMs: resource.durationMs,
        contentLength: resource.contentLength,
        referer: input.report.accessContext?.referer ?? input.pageUrl,
        userAgent: input.report.accessContext?.userAgent,
        originUrl: input.report.accessContext?.originUrl,
        fromBlob: false
      }, {
        signalKind: 'site_extractor',
        cost: 'expensive'
      });
      if (audioSignal !== undefined) {
        audioSignal.authContext = {
          pageUrl: input.report.accessContext?.pageUrl ?? input.pageUrl,
          referer: input.report.accessContext?.referer ?? input.pageUrl,
          userAgent: input.report.accessContext?.userAgent,
          originUrl: input.report.accessContext?.originUrl
        };
        audioSignal.acquisition = this.buildProfileAcquisitionFacts(resource, undefined);
        this.appendProfileAttribution(audioSignal, resource);
        audioSignal.source = 'site_extractor';
        signals.push(audioSignal);
      }
    }
    return this.buildSignalReport(signals);
  }

  private appendProfileAttribution(
    signal: MediaSignal,
    resource: VideoCompatibilityAcquisitionResource
  ): void {
    signal.source = 'site_extractor';
    signal.evidence.push({
      kind: 'profile_provenance',
      value: resource.provenance
    });
    signal.evidence.push({
      kind: 'profile_attribution',
      value: resource.profileAttribution
    });
  }

  /**
   * Profile Acquisition Recipes report independent resources. This projects them into the shared
   * site-neutral progressive/paired-track facts without granting the Profile any downstream decision authority.
   */
  private buildProfileAcquisitionFacts(
    resource: VideoCompatibilityAcquisitionResource,
    pairedAudio: VideoCompatibilityAcquisitionResource | undefined
  ): MediaAcquisitionFacts | undefined {
    if (resource.family === 'video') {
      const videoTrack = this.buildProfileAcquisitionTrack(resource, resource.kind === 'dash' ? 'video' : 'combined');
      if (videoTrack === undefined) {
        return undefined;
      }
      if (resource.kind !== 'dash') {
        return {
          mode: 'progressive',
          primaryTrack: videoTrack
        };
      }
      const audioTrack = this.buildProfileAcquisitionTrack(pairedAudio, 'audio');
      if (audioTrack === undefined) {
        return undefined;
      }
      return {
        mode: 'paired_adaptive',
        primaryTrack: videoTrack,
        pairedTrack: audioTrack
      };
    }
    if (resource.family !== 'audio' || resource.kind !== 'progressive') {
      return undefined;
    }
    const audioTrack = this.buildProfileAcquisitionTrack(resource, 'audio');
    if (audioTrack === undefined) {
      return undefined;
    }
    return {
      mode: 'progressive',
      primaryTrack: audioTrack
    };
  }

  private buildProfileAcquisitionTrack(
    resource: VideoCompatibilityAcquisitionResource | undefined,
    role: MediaAcquisitionTrackRole
  ): MediaAcquisitionTrack | undefined {
    if (resource === undefined || !this.isHttpUrl(resource.url)) {
      return undefined;
    }
    return {
      role: role,
      url: resource.url,
      mimeType: resource.mimeType,
      codecs: resource.codecs,
      bitrate: resource.bandwidth,
      contentLength: resource.contentLength,
      width: resource.width,
      height: resource.height,
      fps: resource.fps,
      audioSampleRate: resource.audioSampleRate,
      audioChannels: resource.audioChannels,
      initializationRange: resource.initializationRange,
      indexRange: resource.indexRange
    };
  }

  private isCurrentProfileResource(
    resource: VideoCompatibilityAcquisitionResource,
    profileAttribution: string
  ): boolean {
    return resource.provenance === 'profile_acquisition' &&
      resource.profileAttribution === profileAttribution && profileAttribution.length > 0;
  }

  async runVideoCompatibilitySelectorProbe(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    profileAttribution: string,
    plans: VideoCompatibilityProfileSelectorPlan[]
  ): Promise<MediaCompatibilitySelectorEvidenceObservation[]> {
    return this.selectorProbeService.probe(controller, pageUrl, profileAttribution, plans);
  }

  private emptyDeepProbeReport(): BrowserMediaDeepProbeReport {
    return {
      diagnosticSummary: '',
      pendingAsyncWork: false,
      resultCount: 0,
      signals: []
    };
  }

  private emptySignalReport(): BrowserMediaProbeReport {
    return {
      signals: []
    };
  }

  private buildSignalReport(signals: MediaSignal[]): BrowserMediaProbeReport {
    return {
      signals: signals
    };
  }

  private probeSignalOptions(signalKind: BrowserMediaProbeDomSignalKind): MediaSignalClassificationOptions {
    return {
      signalKind: signalKind === 'userscript_request' ? 'userscript_request' : 'dom_probe',
      cost: signalKind === 'userscript_request' ? 'normal' : 'normal'
    };
  }

  private safeHeader(request: WebResourceRequest, name: string): string | undefined {
    try {
      const headers = request.getRequestHeader();
      if (headers === undefined || headers === null) {
        return undefined;
      }
      const lowerTarget = name.toLowerCase();
      for (let i = 0; i < headers.length; i++) {
        const headerName = headers[i].headerKey ?? '';
        if (headerName.toLowerCase() === lowerTarget) {
          const value = headers[i].headerValue;
          return value !== undefined && value.length > 0 ? value : undefined;
        }
      }
      return undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private safeIsMainFrame(request: WebResourceRequest): boolean {
    try {
      return request.isMainFrame();
    } catch (_error) {
      return false;
    }
  }

  private safeHeaders(request: WebResourceRequest): Record<string, string> | undefined {
    try {
      const headers = request.getRequestHeader();
      if (headers === undefined || headers === null || headers.length <= 0) {
        return undefined;
      }
      const result: Record<string, string> = {};
      for (let i = 0; i < headers.length; i++) {
        const key = headers[i].headerKey?.trim() ?? '';
        const value = headers[i].headerValue?.trim() ?? '';
        if (key.length > 0 && value.length > 0) {
          result[key] = value;
        }
      }
      return Object.keys(result).length > 0 ? result : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
  }
}

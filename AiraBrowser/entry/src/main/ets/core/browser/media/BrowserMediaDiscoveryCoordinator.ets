import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserMediaProbeBridge
} from './BrowserMediaProbeBridge';
import {
  MediaProbePolicyContext,
  MediaProbePolicyService,
  MediaProbeUserIntent
} from '../../../services/media/MediaProbePolicyService';
import { MediaEvidenceGraph } from '../../../services/media/MediaEvidenceGraph';
import {
  MediaEvidenceGenerationCloseReason,
  MediaEvidenceGenerationIngress,
  MediaEvidenceProducerKind,
  MediaPlaybackObservationEvent,
  MediaPlaybackTargetObservation,
  MediaEvidenceSemanticObservation,
  MediaWebLiveReachabilityObservation,
  MediaEvidenceScope,
  MediaCompatibilitySelectorEvidenceObservation,
  MediaSessionPlaybackTargetEvidence,
  MediaSessionEvidenceProjection
} from '../../../features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaDiscoveryTabSnapshot } from '../../../services/media/MediaDiscoveryStore';
import {
  BrowserMediaInteractionQuietTaskHost,
  BrowserMediaProbeScheduler,
  BrowserMediaProbeSchedulerHost
} from './BrowserMediaProbeScheduler';
import {
  BrowserMediaDiscoveryHost,
  BrowserMediaDiscoveryInterceptInput,
  BrowserMediaDiscoveryLaunchProbeInput,
  BrowserMediaDiscoveryPageInput,
  BrowserMediaDiscoveryRuntimeContext,
  BrowserMediaDiscoverySurfaceInput,
  BrowserMediaDiscoveryUserScriptScanInput
} from './BrowserMediaDiscoveryModels';
import {
  BrowserMediaDiscoveryDownloadActionCandidateResolution,
  BrowserMediaDiscoveryHlsManifestTargetResolution,
  BrowserMediaDiscoverySurfaceBuildInput,
  BrowserMediaDiscoverySurfaceCoordinator
} from './BrowserMediaDiscoverySurfaceCoordinator';
import { BrowserMediaDiscoverySurfaceState } from './BrowserMediaDiscoveryModels';
import { MediaSignal } from '../../../features/mediaDiscovery/MediaSignalModels';
import { MediaHlsManifestTarget } from '../../../features/mediaDiscovery/MediaHlsProjectionModels';
import { MediaDownloadCandidate } from '../../../features/mediaDiscovery/MediaDownloadProjectionModels';
import { MediaCandidateValidationResult } from '../../../features/mediaDiscovery/MediaCandidateValidationModels';
import {
  MediaActionHint,
  MediaCandidate
} from '../../../features/mediaDiscovery/MediaCandidateModels';
import { ManualDownloadRequestInput } from '../../../services/download/DownloadRuntimeService';
import { MediaCandidateValidationService } from '../../../services/media/MediaCandidateValidationService';
import { MediaArkWebMediaInfoEvidenceAdapter } from '../../../services/media/MediaArkWebMediaInfoEvidenceAdapter';
import {
  MediaPageBehaviorEvidenceAdaptResult,
  MediaPageBehaviorEvidenceAdapter
} from '../../../services/media/MediaPageBehaviorEvidenceAdapter';
import { MediaEvidenceLocatorIdentityService } from '../../../services/media/MediaEvidenceLocatorIdentityService';
import { ArkWebMediaAssistantSignalSource } from './sources/ArkWebMediaAssistantSignalSource';
import { BrowserRuntimeLifecyclePort } from '../../../services/web/BrowserRuntimeLifecyclePort';
import {
  MediaCastRequestContextPolicy
} from '../../../services/media/MediaCastRequestContextPolicy';
import {
  sharedVideoCompatibilityProfileCatalog,
  VideoCompatibilityHeuristicSource,
  VideoCompatibilityProfileCatalog
} from '../../../services/media/VideoCompatibilityProfileCatalog';
import {
  VideoCompatibilityProfileAcquisitionLease,
  VideoCompatibilityAcquisitionReport,
  VideoCompatibilityProfileAcquisitionInterceptInput,
  VideoCompatibilityProfileAcquisitionProbeHost,
  VideoCompatibilityProfileAcquisitionProbeInput,
  VideoCompatibilityProfileAcquisitionScheduler,
  VideoCompatibilityReplacedGenericDeepProbeStrategyId
} from '../../../services/media/VideoCompatibilityProfileAcquisitionRecipeService';

const MEDIA_DISCOVERY_LOG_DOMAIN: number = 0xA1A0;
const MEDIA_DISCOVERY_LOG_TAG: string = 'MediaDiscovery';
const RESOURCE_DOM_SCAN_MIN_INTERVAL_MS: number = 8000;
const MEDIA_DISCOVERY_SURFACE_REFRESH_COALESCE_MS: number = 48;
const MEDIA_DEEP_PROBE_ASYNC_FOLLOWUP_DELAY_MS: number = 900;

interface BrowserMediaDiscoveryProjectionSummary {
  mediaCandidateCount: number;
  projectedVideoCount: number;
  projectedResourceCount: number;
}

interface BrowserMediaDiscoveryVideoMediaCounts {
  visibleVideoMediaCount: number;
  videoMediaCount: number;
}

interface BrowserMediaResourceDomScanState {
  inProgress: boolean;
  tabId: string;
  pageUrl: string;
  startedAt: number;
}

export interface BrowserMediaEvidenceCapture {
  readonly tabId: string;
  readonly ingress: MediaEvidenceGenerationIngress;
  readonly scope: MediaEvidenceScope;
  readonly capturedAt: number;
}

export interface BrowserMediaSemanticRouteAdvanceInput {
  capture: BrowserMediaEvidenceCapture;
  pageUrl: string;
  pageTitle: string;
  transitionKey: string;
  observedAt: number;
}

export interface BrowserMediaDiscoveryHlsManifestTargetResolveResult {
  state: BrowserMediaDiscoverySurfaceState;
  target?: MediaHlsManifestTarget;
  candidateSummary: string;
}

export interface BrowserMediaDiscoveryDownloadCandidateResolveResult {
  state: BrowserMediaDiscoverySurfaceState;
  candidate?: MediaDownloadCandidate;
  candidateSummary: string;
}

export type BrowserMediaResourceActionResolutionKind =
  | 'none'
  | 'parse_manifest'
  | 'download'
  | 'copy';

export interface BrowserMediaResourceActionResolution {
  kind: BrowserMediaResourceActionResolutionKind;
  state?: BrowserMediaDiscoverySurfaceState;
  hlsTarget?: MediaHlsManifestTarget;
  downloadRequest?: ManualDownloadRequestInput;
  copyUrl?: string;
  candidateSummary: string;
}

export type BrowserActivePlaybackDownloadReason =
  | 'ready'
  | 'missing_target'
  | 'missing_locator'
  | 'missing_resource'
  | 'ambiguous_resource'
  | 'unsupported_resource';

export interface BrowserActivePlaybackDownloadResolution {
  reason: BrowserActivePlaybackDownloadReason;
  state?: BrowserMediaDiscoverySurfaceState;
  downloadRequest?: ManualDownloadRequestInput;
  message: string;
}

export type BrowserActivePlaybackCastMediaReason =
  'ready' |
  'missing_target' |
  'missing_locator' |
  'missing_resource' |
  'ambiguous_resource' |
  'web_context_required' |
  'unsupported_resource';

export interface BrowserActivePlaybackCastMediaResolution {
  reason: BrowserActivePlaybackCastMediaReason;
  mediaUri?: string;
  mediaFormat: string;
  requestHeaderCount: number;
}

export class BrowserMediaDiscoveryCoordinator {
  private mediaProbeBridge: BrowserMediaProbeBridge;
  private probePolicy: MediaProbePolicyService = new MediaProbePolicyService();
  private probeScheduler: BrowserMediaProbeScheduler = new BrowserMediaProbeScheduler();
  private surfaceCoordinator: BrowserMediaDiscoverySurfaceCoordinator = new BrowserMediaDiscoverySurfaceCoordinator();
  private mediaEvidenceGraph: MediaEvidenceGraph = new MediaEvidenceGraph();
  private mediaEvidenceIngressByTab: Map<string, MediaEvidenceGenerationIngress> = new Map();
  private validationService: MediaCandidateValidationService = new MediaCandidateValidationService();
  private validationGenerationByTab: Map<string, number> = new Map();
  private validationJobsByKey: Map<string, boolean> = new Map();
  private surfaceRefreshTimerByTab: Map<string, number> = new Map();
  private publishedSurfaceTabId: string = '';
  private publishedSurfaceSignature: string = '';
  private arkWebMediaAssistantSignalSource: ArkWebMediaAssistantSignalSource = new ArkWebMediaAssistantSignalSource();
  private arkWebMediaInfoEvidenceAdapter: MediaArkWebMediaInfoEvidenceAdapter =
    new MediaArkWebMediaInfoEvidenceAdapter();
  private pageBehaviorEvidenceAdapter: MediaPageBehaviorEvidenceAdapter = new MediaPageBehaviorEvidenceAdapter();
  private locatorIdentityService: MediaEvidenceLocatorIdentityService = new MediaEvidenceLocatorIdentityService();
  private castRequestContextPolicy: MediaCastRequestContextPolicy = new MediaCastRequestContextPolicy();
  private readonly videoCompatibilityProfileCatalog: VideoCompatibilityProfileCatalog;
  private runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private resourceDomScanState: BrowserMediaResourceDomScanState = {
    inProgress: false,
    tabId: '',
    pageUrl: '',
    startedAt: 0
  };

  constructor(
    mediaProbeBridge: BrowserMediaProbeBridge,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    videoCompatibilityProfileCatalog: VideoCompatibilityProfileCatalog = sharedVideoCompatibilityProfileCatalog
  ) {
    this.mediaProbeBridge = mediaProbeBridge;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.videoCompatibilityProfileCatalog = videoCompatibilityProfileCatalog;
  }

  clearTabForNavigation(tabId: string): void {
    this.bumpValidationGeneration(tabId);
    this.probeScheduler.cancelTab(tabId);
    this.clearSurfacePublicationForTab(tabId);
    this.closeMediaEvidenceGeneration(tabId, 'superseded_navigation');
    this.clearSignalSourcesForTab(tabId);
    this.clearResourceDomScanStateForTab(tabId);
    this.clearProfileAcquisitionScheduler(tabId);
  }

  clearTab(tabId: string): void {
    this.bumpValidationGeneration(tabId);
    this.probeScheduler.clearTab(tabId);
    this.clearSurfacePublicationForTab(tabId);
    this.closeMediaEvidenceGeneration(tabId, 'tab_closed');
    this.mediaEvidenceGraph.closeTab(tabId);
    this.clearSignalSourcesForTab(tabId);
    this.clearResourceDomScanStateForTab(tabId);
    this.clearProfileAcquisitionScheduler(tabId);
  }

  handleInterceptRequest(input: BrowserMediaDiscoveryInterceptInput, host: BrowserMediaDiscoveryHost): void {
    const signals: MediaSignal[] = [];
    if (this.probePolicy.shouldObserveVideoRequest(input.runtime)) {
      const videoSignal = this.mediaProbeBridge.observeVideoIntercept({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        request: input.request
      });
      if (videoSignal !== undefined) {
        signals.push(videoSignal);
      }
      this.observeProfileAcquisitionIntercept(input, host);
    }
    if (this.probePolicy.shouldObserveGenericResourceRequest(input.runtime)) {
      const resourceSignal = this.mediaProbeBridge.observeResourceIntercept({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        request: input.request
      });
      if (resourceSignal !== undefined) {
        signals.push(resourceSignal);
      }
    }
    this.ingestSignals(input.tabId, signals, host);
  }

  captureSemanticEvidence(tabId: string): BrowserMediaEvidenceCapture | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return undefined;
    }
    return this.captureMediaEvidence(normalizedTabId);
  }

  advanceSemanticEvidenceRoute(
    input: BrowserMediaSemanticRouteAdvanceInput
  ): BrowserMediaEvidenceCapture | undefined {
    if (this.mediaEvidenceIngressByTab.get(input.capture.tabId) !== input.capture.ingress) {
      return undefined;
    }
    const nextScope = input.capture.ingress.advanceRouteEpoch({
      currentScope: input.capture.scope,
      routeTransitionKey: input.transitionKey,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      observedAt: input.observedAt
    });
    if (nextScope.routeEpochId === input.capture.scope.routeEpochId) {
      return undefined;
    }
    this.bumpValidationGeneration(input.capture.tabId);
    this.clearSurfacePublicationForTab(input.capture.tabId);
    this.clearResourceDomScanStateForTab(input.capture.tabId);
    this.clearProfileAcquisitionScheduler(input.capture.tabId);
    const capture: BrowserMediaEvidenceCapture = {
      tabId: input.capture.tabId,
      ingress: input.capture.ingress,
      scope: nextScope,
      capturedAt: input.observedAt > 0 ? input.observedAt : Date.now()
    };
    return capture;
  }

  observePageBehaviorEvidence(capture: BrowserMediaEvidenceCapture, payloadJson: string): boolean {
    const result: MediaPageBehaviorEvidenceAdaptResult = this.pageBehaviorEvidenceAdapter.adapt(
      payloadJson,
      Date.now()
    );
    if (result.observedAt < capture.capturedAt) {
      return false;
    }
    return this.ingestSemanticEvidence(capture, 'playback_event', result.observedAt, result.observations);
  }

  observeArkWebMediaInfoEvidence(capture: BrowserMediaEvidenceCapture, mediaInfo: webview.MediaInfo): boolean {
    return this.ingestSemanticEvidence(
      capture,
      'arkweb_media_info',
      Date.now(),
      this.arkWebMediaInfoEvidenceAdapter.adapt(mediaInfo)
    );
  }

  observeFrameRuntimeEvidence(
    capture: BrowserMediaEvidenceCapture,
    observedAt: number,
    observations: MediaEvidenceSemanticObservation[]
  ): boolean {
    if (observedAt < capture.capturedAt) {
      return false;
    }
    return this.ingestSemanticEvidence(capture, 'dom_runtime', observedAt, observations);
  }

  observeWebLiveReachabilityEvidence(
    capture: BrowserMediaEvidenceCapture,
    targetKey: string,
    state: 'reachable' | 'unreachable',
    observedAt: number,
    expiresAt: number
  ): boolean {
    if (observedAt < capture.capturedAt) {
      return false;
    }
    const observation: MediaWebLiveReachabilityObservation = {
      kind: 'web_live_reachability',
      targetKey: targetKey,
      state: state,
      expiresAt: expiresAt,
      commandProtocolVersion: 1,
      restoreProtocolVersion: 1,
      quality: 'direct'
    };
    return this.ingestSemanticEvidence(
      capture,
      'web_live_reachability',
      observedAt,
      [observation]
    );
  }

  observeWebLivePlaybackEvidence(
    capture: BrowserMediaEvidenceCapture,
    targetKey: string,
    event: MediaPlaybackObservationEvent,
    observedAt: number,
    currentTimeSeconds: number,
    durationSeconds: number
  ): boolean {
    if (observedAt < capture.capturedAt) {
      return false;
    }
    const observation: MediaPlaybackTargetObservation = {
      kind: 'playback_target',
      targetKey: targetKey,
      targetIdentityQuality: 'stable',
      event: event,
      sourceLocators: [],
      currentTimeSeconds: this.nonNegativeFinite(currentTimeSeconds),
      durationSeconds: this.nonNegativeFinite(durationSeconds),
      quality: 'direct'
    };
    return this.ingestSemanticEvidence(
      capture,
      'playback_event',
      observedAt,
      [observation]
    );
  }

  projectSessionEvidence(tabId: string, now: number): MediaSessionEvidenceProjection | undefined {
    if (tabId.trim().length <= 0) {
      return undefined;
    }
    const ingress = this.mediaEvidenceIngressByTab.get(tabId);
    if (ingress === undefined) {
      return undefined;
    }
    return ingress.compatibilityReader().projectSessionEvidence(now);
  }

  runPageEndProbes(
    input: BrowserMediaDiscoveryPageInput,
    host: BrowserMediaDiscoveryHost,
    profileAcquisitionReason: string = 'page_end'
  ): void {
    const policyContext = this.buildProbePolicyContext(input, 'page_end');
    const decision = this.probePolicy.decideVideoPageEndProbes(policyContext);
    const hasController = input.controller !== undefined;
    if (!decision.enabled) {
      this.requestMediaDiscoverySurfaceRefresh(input.tabId, host);
      return;
    }
    if (!hasController) {
      return;
    }
    const profileEvidenceCapture = this.captureMediaEvidence(input.tabId);
    this.videoCompatibilityProfileCatalog.resolve({
      scope: profileEvidenceCapture.scope,
      pageUrl: input.pageUrl
    });
    void this.requestArkWebMediaAssistantSnapshot(input, host, 'page_end');
    this.scheduleDeepProbes(input, host);
    this.schedulePageEndDomProbe(input, host);
    this.runProfileSelectorProbe(input, host);
    this.scheduleProfileAcquisition(input, host, profileAcquisitionReason);
  }

  scheduleSpaRouteProbeIfNeeded(
    tabId: string,
    pageUrl: string,
    pageTitle: string,
    host: BrowserMediaDiscoveryHost
  ): void {
    this.requestMediaDiscoverySurfaceRefresh(tabId, host);
    // A SPA route may replace a player without a new onPageEnd. Re-run the complete observation set whether
    // or not a Profile Recipe is scheduled; Recipe success, failure, absence, or disablement never blocks it.
    if (this.probePolicy.shouldRunSpaRouteReprobe(this.buildRuntimePolicyContext(
      host.buildRuntimeContext(),
      'scheduled_page_end'
    ))) {
      this.runPageEndProbesForTab(tabId, pageUrl, pageTitle, host, 'history_api_url_change');
    }
  }

  runPageEndProbesForTab(
    tabId: string,
    pageUrl: string,
    pageTitle: string,
    host: BrowserMediaDiscoveryHost,
    profileAcquisitionReason: string = 'page_end'
  ): void {
    this.runPageEndProbes({
      tabId: tabId,
      pageUrl: pageUrl,
      pageTitle: pageTitle,
      privacyMode: host.resolvePrivacyModeForTab(tabId),
      controller: this.resolveControllerForTab(tabId),
      runtime: host.buildRuntimeContext()
    }, host, profileAcquisitionReason);
  }

  runUserScriptMediaScan(input: BrowserMediaDiscoveryUserScriptScanInput, host: BrowserMediaDiscoveryHost): void {
    if (input.controller === undefined) {
      return;
    }
    const evidenceCapture = this.captureMediaEvidence(input.tabId);
    const policyContext = this.buildProbePolicyContext(input, 'userscript', input.isPrivateTab);
    if (this.probePolicy.shouldRunManualMediaVideoProbe(policyContext)) {
      void this.mediaProbeBridge.runVideoDomScan({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        controller: input.controller,
        signalKind: 'userscript_request'
      }).then((report) => {
        this.ingestSignals(input.tabId, report.signals, host, evidenceCapture);
      }).catch((_error: Error) => {});
    }
    if (!this.probePolicy.shouldRunManualMediaResourceProbe(policyContext)) {
      return;
    }
    void this.mediaProbeBridge.runResourceDomScan({
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      privacyMode: input.privacyMode,
      controller: input.controller,
      signalKind: 'userscript_request'
    }).then((report) => {
      this.ingestSignals(input.tabId, report.signals, host, evidenceCapture);
      host.showToast('已扫描页面媒体资源');
    }).catch((_error: Error) => {});
  }

  runUserScriptMediaScanForTab(
    tabId: string,
    sourcePageUrl: string,
    host: BrowserMediaDiscoveryHost
  ): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return;
    }
    const normalizedSourcePageUrl = sourcePageUrl.trim();
    const pageUrl = normalizedSourcePageUrl.length > 0
      ? normalizedSourcePageUrl
      : host.resolvePageUrlForTab(normalizedTabId);
    const privacyMode = host.resolvePrivacyModeForTab(normalizedTabId);
    this.runUserScriptMediaScan({
      tabId: normalizedTabId,
      pageUrl: pageUrl,
      pageTitle: host.resolvePageTitleForTab(normalizedTabId),
      privacyMode: privacyMode,
      controller: this.resolveControllerForTab(normalizedTabId),
      runtime: host.buildRuntimeContext(),
      isPrivateTab: privacyMode === 'private'
    }, host);
  }

  async runManualResourceScan(
    input: BrowserMediaDiscoveryPageInput,
    host: BrowserMediaDiscoveryHost
  ): Promise<void> {
    if (!this.probePolicy.shouldRunExplicitResourceScan(this.buildProbePolicyContext(input, 'resource_panel'))) {
      this.refreshMediaDiscoverySurface({
        tabId: input.tabId,
        runtime: input.runtime,
        resourcePanelOpen: input.runtime.mediaResourcesPanelOpen
      }, host);
      return;
    }
    if (input.tabId.length <= 0 || input.controller === undefined) {
      return;
    }
    const evidenceCapture = this.captureMediaEvidence(input.tabId);
    const now = Date.now();
    if (this.shouldSkipResourceDomScan(input.tabId, input.pageUrl, now)) {
      this.refreshMediaDiscoverySurface({
        tabId: input.tabId,
        runtime: input.runtime,
        resourcePanelOpen: input.runtime.mediaResourcesPanelOpen
      }, host);
      return;
    }
    this.beginResourceDomScan(input.tabId, input.pageUrl, now);
    this.requestMediaDiscoverySurfaceRefresh(input.tabId, host);
    try {
      const report = await this.mediaProbeBridge.runResourceDomScan({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        controller: input.controller
      });
      this.ingestSignals(input.tabId, report.signals, host, evidenceCapture);
      this.finishResourceDomScanIfCurrent(input.tabId, input.pageUrl);
      this.requestMediaDiscoverySurfaceRefresh(input.tabId, host);
    } catch (_error) {
      this.finishResourceDomScanIfCurrent(input.tabId, input.pageUrl);
      this.requestMediaDiscoverySurfaceRefresh(input.tabId, host);
    }
  }

  async runTakeoverLaunchProbeForTab(tabId: string, host: BrowserMediaDiscoveryHost): Promise<void> {
    await this.runTakeoverLaunchProbe({
      tabId: tabId,
      pageUrl: host.resolvePageUrlForTab(tabId),
      pageTitle: host.resolvePageTitleForTab(tabId),
      privacyMode: host.resolvePrivacyModeForTab(tabId),
      controller: this.resolveControllerForTab(tabId),
      runtime: host.buildRuntimeContext()
    }, host);
  }

  async runManualResourceScanForActiveTab(host: BrowserMediaDiscoveryHost): Promise<void> {
    const tabId = host.resolveActiveTabId();
    await this.runManualResourceScan({
      tabId: tabId,
      pageUrl: host.resolvePageUrlForTab(tabId),
      pageTitle: host.resolvePageTitleForTab(tabId),
      privacyMode: host.resolvePrivacyModeForTab(tabId),
      controller: this.resolveControllerForTab(tabId),
      runtime: host.buildRuntimeContext()
    }, host);
  }

  async runTakeoverLaunchProbe(
    input: BrowserMediaDiscoveryLaunchProbeInput,
    host: BrowserMediaDiscoveryHost
  ): Promise<void> {
    if (!this.probePolicy.shouldRunManualMediaVideoProbe(
      this.buildProbePolicyContext(input, 'takeover_launch')
    ) || input.controller === undefined) {
      return;
    }
    const evidenceCapture = this.captureMediaEvidence(input.tabId);
    try {
      await this.requestArkWebMediaAssistantSnapshot(input, host, 'takeover_launch', evidenceCapture);
      const report = await this.mediaProbeBridge.runDeepProbe({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        privacyMode: input.privacyMode,
        controller: input.controller,
        intent: 'user_intent',
        replacedGenericDeepProbeStrategyIds: this.resolveReplacedGenericDeepProbeStrategyIds(
          evidenceCapture,
          input.pageUrl
        )
      });
      this.ingestSignals(input.tabId, report.signals, host, evidenceCapture);
      this.runProfileAcquisition(
        input.tabId,
        input.pageUrl,
        input.controller,
        evidenceCapture,
        host,
        (): boolean => host.resolvePageUrlForTab(input.tabId) === input.pageUrl
      );
      await this.runTakeoverLaunchProfileAcquisition(
        input,
        host
      );
    } catch (_error) {
    }
  }

  private shouldRunScheduledProfileAcquisition(
    tabId: string,
    pageUrl: string,
    host: BrowserMediaDiscoveryHost
  ): boolean {
    if (!this.probePolicy.shouldRunVideoPageEndProbes(this.buildRuntimePolicyContext(
      host.buildRuntimeContext(),
      'scheduled_page_end'
    ))) {
      return false;
    }
    if (host.resolvePageUrlForTab(tabId) !== pageUrl) {
      return false;
    }
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(tabId);
    return resolution !== undefined && resolution.isProfileApplied() &&
      resolution.getAcquisitionCapability()?.getScheduler() !== undefined &&
      this.sameMediaEvidenceScope(resolution.getScope(), this.captureMediaEvidence(tabId).scope);
  }

  refreshMediaDiscoverySurface(input: BrowserMediaDiscoverySurfaceInput, host: BrowserMediaDiscoveryHost): void {
    this.cancelSurfaceRefresh(input.tabId);
    const surfaceInput = this.buildSurfaceInput(input);
    const snapshot = this.projectLegacyMediaSnapshot(surfaceInput.tabId);
    const projectionSummary = this.buildProjectionSummary(surfaceInput.tabId);
    const resolution = this.surfaceCoordinator.build(
      surfaceInput,
      snapshot
    );
    const signature = JSON.stringify(resolution.state) ?? '';
    if (this.publishedSurfaceTabId === surfaceInput.tabId && this.publishedSurfaceSignature === signature) {
      if (resolution.clearDomScanState) {
        this.clearResourceDomScanState();
      }
      return;
    }
    this.publishedSurfaceTabId = surfaceInput.tabId;
    this.publishedSurfaceSignature = signature;
    host.applyMediaDiscoverySurfaceState(resolution.state);
    this.logMediaSurface(input, resolution.state.videoMediaCount,
      resolution.state.resourceTabCounts.all, projectionSummary);
    if (resolution.clearDomScanState) {
      this.clearResourceDomScanState();
    }
  }

  refreshActiveMediaDiscoverySurface(host: BrowserMediaDiscoveryHost): void {
    this.refreshMediaDiscoverySurface({
      tabId: host.resolveActiveTabId(),
      runtime: host.buildRuntimeContext()
    }, host);
  }

  private requestMediaDiscoverySurfaceRefresh(tabId: string, host: BrowserMediaDiscoveryHost): void {
    if (!host.isActiveTab(tabId)) {
      return;
    }
    this.cancelSurfaceRefresh(tabId);
    const delayMs = Math.max(
      0,
      Math.floor(host.resolveInteractionQuietDelayMs(MEDIA_DISCOVERY_SURFACE_REFRESH_COALESCE_MS))
    );
    if (delayMs <= 0) {
      this.refreshMediaDiscoverySurface({
        tabId: tabId,
        runtime: host.buildRuntimeContext()
      }, host);
      return;
    }
    const timerId = setTimeout(() => {
      this.surfaceRefreshTimerByTab.delete(tabId);
      if (!host.isActiveTab(tabId)) {
        return;
      }
      const remainingQuietDelayMs = Math.max(0, Math.floor(host.resolveInteractionQuietDelayMs(0)));
      if (remainingQuietDelayMs > 0) {
        this.requestMediaDiscoverySurfaceRefresh(tabId, host);
        return;
      }
      this.refreshMediaDiscoverySurface({
        tabId: tabId,
        runtime: host.buildRuntimeContext()
      }, host);
    }, delayMs);
    this.surfaceRefreshTimerByTab.set(tabId, timerId);
  }

  private cancelSurfaceRefresh(tabId: string): void {
    const timerId = this.surfaceRefreshTimerByTab.get(tabId);
    if (timerId !== undefined) {
      clearTimeout(timerId);
      this.surfaceRefreshTimerByTab.delete(tabId);
    }
  }

  private clearSurfacePublicationForTab(tabId: string): void {
    this.cancelSurfaceRefresh(tabId);
    if (this.publishedSurfaceTabId === tabId) {
      this.publishedSurfaceTabId = '';
      this.publishedSurfaceSignature = '';
    }
  }

  resolveMediaResourceAction(
    input: BrowserMediaDiscoverySurfaceInput,
    candidateId: string,
    action: MediaActionHint
  ): BrowserMediaResourceActionResolution {
    const normalizedCandidateId = candidateId.trim();
    if (normalizedCandidateId.length <= 0) {
      return {
        kind: 'none',
        candidateSummary: 'missing'
      };
    }
    if (action === 'parse_manifest') {
      const resolution = this.resolveHlsManifestTarget(input, normalizedCandidateId);
      return {
        kind: 'parse_manifest',
        state: resolution.state,
        hlsTarget: resolution.target,
        candidateSummary: resolution.candidateSummary
      };
    }
    if (action === 'download') {
      const resolution = this.resolveDownloadCandidate(input, normalizedCandidateId);
      return {
        kind: 'download',
        state: resolution.state,
        downloadRequest: this.buildResourceDownloadPromptRequest(resolution.candidate),
        candidateSummary: resolution.candidateSummary
      };
    }
    if (action === 'copy') {
      return this.resolveMediaResourceCopyAction(input, normalizedCandidateId);
    }
    return {
      kind: 'none',
      candidateSummary: 'unsupported'
    };
  }

  resolveActivePlaybackDownload(
    input: BrowserMediaDiscoverySurfaceInput,
    playbackTargetId: string
  ): BrowserActivePlaybackDownloadResolution {
    const normalizedTargetId = playbackTargetId.trim();
    const sessionEvidence = this.projectSessionEvidence(input.tabId, Date.now());
    const target = this.findPlaybackTarget(sessionEvidence, normalizedTargetId);
    if (target === undefined || !target.currentRoute) {
      return this.rejectActivePlaybackDownload(
        'missing_target',
        '当前网页视频会话已经失效。'
      );
    }
    const locatorIdentities = this.collectLatestPlaybackLocatorIdentities(target);
    if (locatorIdentities.length <= 0) {
      return this.rejectActivePlaybackDownload(
        'missing_locator',
        '当前视频使用 blob/MSE 或没有可直接下载的地址，暂不支持下载。'
      );
    }
    const candidates = this.findCandidatesByLocatorIdentities(input.tabId, locatorIdentities);
    if (candidates.length <= 0) {
      return this.rejectActivePlaybackDownload(
        'missing_resource',
        '当前视频使用 blob/MSE，或尚未嗅探到可下载地址。'
      );
    }
    const supportedCandidates: MediaCandidate[] = [];
    for (let i = 0; i < candidates.length; i += 1) {
      if (this.isSupportedActivePlaybackDownloadCandidate(candidates[i])) {
        supportedCandidates.push(candidates[i]);
      }
    }
    if (supportedCandidates.length <= 0) {
      return this.rejectActivePlaybackDownload(
        'unsupported_resource',
        this.resolveUnsupportedActivePlaybackMessage(candidates)
      );
    }
    if (supportedCandidates.length > 1) {
      return this.rejectActivePlaybackDownload(
        'ambiguous_resource',
        '当前视频匹配到多个资源，暂时无法确定要下载哪一个。'
      );
    }
    const resolution = this.resolveMediaResourceAction(input, supportedCandidates[0].id, 'download');
    if (resolution.downloadRequest === undefined) {
      return {
        reason: 'unsupported_resource',
        state: resolution.state,
        message: '当前视频资源暂时不能创建下载任务。'
      };
    }
    return {
      reason: 'ready',
      state: resolution.state,
      downloadRequest: resolution.downloadRequest,
      message: ''
    };
  }

  resolveActivePlaybackCastMedia(
    tabId: string,
    playbackTargetId: string
  ): BrowserActivePlaybackCastMediaResolution {
    const normalizedTabId = tabId.trim();
    const normalizedTargetId = playbackTargetId.trim();
    const sessionEvidence = this.projectSessionEvidence(normalizedTabId, Date.now());
    const target = this.findPlaybackTarget(sessionEvidence, normalizedTargetId);
    if (target === undefined || !target.currentRoute) {
      return this.rejectActivePlaybackCastMedia('missing_target');
    }
    const locatorIdentities = this.collectLatestPlaybackLocatorIdentities(target);
    if (locatorIdentities.length <= 0) {
      return this.rejectActivePlaybackCastMedia('missing_locator');
    }
    const candidates = this.findCandidatesByLocatorIdentities(normalizedTabId, locatorIdentities);
    if (candidates.length <= 0) {
      return this.rejectActivePlaybackCastMedia('missing_resource');
    }
    const supportedCandidates: MediaCandidate[] = [];
    let webContextBlockedCandidateCount = 0;
    for (let i: number = 0; i < candidates.length; i += 1) {
      const candidate = candidates[i];
      if (!this.isSupportedActivePlaybackCastResource(candidate)) {
        continue;
      }
      const requestContext = this.castRequestContextPolicy.assess(candidate.authContext?.requestHeaders);
      if (requestContext.requiresWebRequestContext) {
        webContextBlockedCandidateCount += 1;
      } else {
        supportedCandidates.push(candidate);
      }
    }
    if (supportedCandidates.length <= 0) {
      const reason: BrowserActivePlaybackCastMediaReason = webContextBlockedCandidateCount > 0 ?
        'web_context_required' : 'unsupported_resource';
      hilog.info(
        MEDIA_DISCOVERY_LOG_DOMAIN,
        MEDIA_DISCOVERY_LOG_TAG,
        'cast_media_rejected reason=%{public}s candidates=%{public}d context_blocked=%{public}d',
        reason,
        candidates.length,
        webContextBlockedCandidateCount
      );
      return this.rejectActivePlaybackCastMedia(reason);
    }
    if (supportedCandidates.length > 1) {
      return this.rejectActivePlaybackCastMedia('ambiguous_resource');
    }
    const candidate = supportedCandidates[0];
    const requestContext = this.castRequestContextPolicy.assess(candidate.authContext?.requestHeaders);
    return {
      reason: 'ready',
      mediaUri: candidate.url.trim(),
      mediaFormat: candidate.playbackMetadata?.mimeType?.trim() ?? candidate.kind,
      requestHeaderCount: requestContext.requestHeaderCount
    };
  }

  resolveHlsManifestTarget(
    input: BrowserMediaDiscoverySurfaceInput,
    candidateId: string
  ): BrowserMediaDiscoveryHlsManifestTargetResolveResult {
    const surfaceInput = this.buildSurfaceInput(input);
    const targetResolution: BrowserMediaDiscoveryHlsManifestTargetResolution =
      this.surfaceCoordinator.buildHlsManifestTarget(
        surfaceInput,
        this.projectLegacyMediaSnapshot(surfaceInput.tabId),
        candidateId
      );
    if (targetResolution.clearDomScanState) {
      this.clearResourceDomScanState();
    }
    return {
      state: targetResolution.state,
      target: targetResolution.target,
      candidateSummary: targetResolution.summary
    };
  }

  resolveDownloadCandidate(
    input: BrowserMediaDiscoverySurfaceInput,
    candidateId: string
  ): BrowserMediaDiscoveryDownloadCandidateResolveResult {
    const surfaceInput = this.buildSurfaceInput(input);
    const candidateResolution: BrowserMediaDiscoveryDownloadActionCandidateResolution =
      this.surfaceCoordinator.buildDownloadActionCandidate(
        surfaceInput,
        this.projectLegacyMediaSnapshot(surfaceInput.tabId),
        candidateId
      );
    if (candidateResolution.clearDomScanState) {
      this.clearResourceDomScanState();
    }
    return {
      state: candidateResolution.state,
      candidate: candidateResolution.candidate,
      candidateSummary: candidateResolution.summary
    };
  }

  private findPlaybackTarget(
    evidence: MediaSessionEvidenceProjection | undefined,
    playbackTargetId: string
  ): MediaSessionPlaybackTargetEvidence | undefined {
    if (evidence === undefined || playbackTargetId.length <= 0) {
      return undefined;
    }
    for (let i = 0; i < evidence.targets.length; i += 1) {
      if (evidence.targets[i].playbackTargetId === playbackTargetId) {
        return evidence.targets[i];
      }
    }
    return undefined;
  }

  private collectLatestPlaybackLocatorIdentities(target: MediaSessionPlaybackTargetEvidence): string[] {
    let latestObservedAt = 0;
    for (let i = 0; i < target.occurrences.length; i += 1) {
      const occurrence = target.occurrences[i];
      if (occurrence.currentRoute && occurrence.sourceLocators.length > 0) {
        latestObservedAt = Math.max(latestObservedAt, occurrence.observedAt);
      }
    }
    const identities: string[] = [];
    for (let i = 0; i < target.occurrences.length; i += 1) {
      const occurrence = target.occurrences[i];
      if (!occurrence.currentRoute || occurrence.observedAt !== latestObservedAt) {
        continue;
      }
      for (let locatorIndex = 0; locatorIndex < occurrence.sourceLocators.length; locatorIndex += 1) {
        const identity = occurrence.sourceLocators[locatorIndex].identity;
        if (identity.length > 0 && identities.indexOf(identity) < 0) {
          identities.push(identity);
        }
      }
    }
    return identities;
  }

  private findCandidatesByLocatorIdentities(tabId: string, locatorIdentities: string[]): MediaCandidate[] {
    const snapshot = this.projectLegacyMediaSnapshot(tabId);
    const candidates: MediaCandidate[] = [];
    for (let i = 0; i < snapshot.records.length; i += 1) {
      const candidate = snapshot.records[i].candidate;
      const locator = this.locatorIdentityService.resolve(candidate.url);
      if (candidate.tabId === tabId && locator !== undefined &&
        locatorIdentities.indexOf(locator.identity) >= 0) {
        candidates.push(candidate);
      }
    }
    return candidates;
  }

  private isSupportedActivePlaybackDownloadCandidate(candidate: MediaCandidate): boolean {
    if (!this.isHttpOrHttpsUrl(candidate.url) || this.hasPairedAdaptiveAcquisition(candidate) ||
      candidate.kind === 'dash' ||
      candidate.playabilityState === 'protected' || candidate.playabilityState === 'expired' ||
      candidate.playabilityState === 'requires_po_token' || candidate.playabilityState === 'signature_failed' ||
      candidate.playabilityState === 'format_unavailable' || candidate.downloadabilityState === 'copy_only' ||
      candidate.downloadabilityState === 'unsupported' || candidate.downloadabilityState === 'expired') {
      return false;
    }
    if (this.isHlsDownloadCandidate(candidate)) {
      return true;
    }
    return candidate.family === 'video';
  }

  private isSupportedActivePlaybackCastResource(candidate: MediaCandidate): boolean {
    if (!this.isHttpOrHttpsUrl(candidate.url) || this.hasPairedAdaptiveAcquisition(candidate) ||
      candidate.kind === 'dash' ||
      candidate.playabilityState === 'protected' || candidate.playabilityState === 'expired' ||
      candidate.playabilityState === 'requires_po_token' || candidate.playabilityState === 'signature_failed' ||
      candidate.playabilityState === 'format_unavailable' || candidate.downloadabilityState === 'unsupported' ||
      candidate.downloadabilityState === 'expired') {
      return false;
    }
    return candidate.kind === 'hls' || candidate.family === 'video';
  }

  private rejectActivePlaybackCastMedia(
    reason: BrowserActivePlaybackCastMediaReason
  ): BrowserActivePlaybackCastMediaResolution {
    return {
      reason: reason,
      mediaFormat: '',
      requestHeaderCount: 0
    };
  }

  private isHlsDownloadCandidate(candidate: MediaCandidate): boolean {
    const normalizedUrl = candidate.url.trim().toLowerCase();
    const mimeType = candidate.playbackMetadata?.mimeType?.trim().toLowerCase() ?? '';
    return candidate.kind === 'hls' || normalizedUrl.indexOf('.m3u8') >= 0 ||
      normalizedUrl.indexOf('/m3u8/') >= 0 || normalizedUrl.endsWith('.m3u') ||
      mimeType.indexOf('mpegurl') >= 0 || mimeType.indexOf('m3u8') >= 0;
  }

  private isHttpOrHttpsUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private resolveUnsupportedActivePlaybackMessage(candidates: MediaCandidate[]): string {
    for (let i = 0; i < candidates.length; i += 1) {
      if (candidates[i].playabilityState === 'protected') {
        return '当前视频受加密或 DRM 保护，无法下载。';
      }
    }
    for (let i = 0; i < candidates.length; i += 1) {
      if (this.hasPairedAdaptiveAcquisition(candidates[i])) {
        return '当前视频使用分离的音视频流，暂不支持直接下载。';
      }
      if (candidates[i].kind === 'dash') {
        return '当前视频使用 DASH 分片，暂不支持直接下载。';
      }
    }
    return '当前视频资源暂不支持下载。';
  }

  private rejectActivePlaybackDownload(
    reason: BrowserActivePlaybackDownloadReason,
    message: string
  ): BrowserActivePlaybackDownloadResolution {
    return {
      reason: reason,
      message: message
    };
  }

  private resolveMediaResourceCopyAction(
    input: BrowserMediaDiscoverySurfaceInput,
    candidateId: string
  ): BrowserMediaResourceActionResolution {
    const surfaceInput = this.buildSurfaceInput(input);
    const resolution = this.surfaceCoordinator.build(
      surfaceInput,
      this.projectLegacyMediaSnapshot(surfaceInput.tabId)
    );
    if (resolution.clearDomScanState) {
      this.clearResourceDomScanState();
    }
    const items = resolution.state.resourceListItems;
    for (let index = 0; index < items.length; index += 1) {
      if (items[index].id === candidateId) {
        return {
          kind: 'copy',
          state: resolution.state,
          copyUrl: items[index].url,
          candidateSummary: items[index].kind + '/' + items[index].family + '/' + items[index].sourceHost
        };
      }
    }
    return {
      kind: 'copy',
      state: resolution.state,
      candidateSummary: 'missing'
    };
  }

  private buildResourceDownloadPromptRequest(
    candidate: MediaDownloadCandidate | undefined
  ): ManualDownloadRequestInput | undefined {
    if (candidate === undefined) {
      return undefined;
    }
    const trimmedUrl = candidate.url.trim();
    if (trimmedUrl.length <= 0) {
      return undefined;
    }
    return {
      url: trimmedUrl,
      sourceHost: candidate.sourceHost.length > 0 ? candidate.sourceHost : undefined,
      suggestedFileName: candidate.displayName.length > 0 ? candidate.displayName : undefined,
      totalBytes: candidate.kind === 'hls' ? candidate.estimatedTotalBytes : candidate.totalBytes,
      userAgent: candidate.userAgent,
      referer: candidate.referer ?? candidate.pageUrl,
      mimeType: candidate.mimeType,
      contentDisposition: candidate.contentDisposition,
      headers: this.buildResourceDownloadHeaders(candidate)
    };
  }

  private buildResourceDownloadHeaders(candidate: MediaDownloadCandidate): Record<string, string> | undefined {
    const headers: Record<string, string> = {};
    const sourceHeaders = candidate.requestHeaders;
    if (sourceHeaders !== undefined) {
      Object.keys(sourceHeaders).forEach((key: string) => {
        const normalizedKey = key.trim();
        const normalizedValue = sourceHeaders[key]?.trim() ?? '';
        if (normalizedKey.length > 0 && normalizedValue.length > 0) {
          headers[normalizedKey] = normalizedValue;
        }
      });
    }
    this.putResourceDownloadHeader(headers, 'Referer', candidate.referer ?? candidate.pageUrl);
    this.putResourceDownloadHeader(headers, 'User-Agent', candidate.userAgent);
    this.putResourceDownloadHeader(headers, 'Origin', candidate.originUrl);
    return Object.keys(headers).length > 0 ? headers : undefined;
  }

  private putResourceDownloadHeader(headers: Record<string, string>, name: string, value: string | undefined): void {
    const normalizedValue = value?.trim() ?? '';
    if (normalizedValue.length <= 0 || this.hasResourceDownloadHeader(headers, name)) {
      return;
    }
    headers[name] = normalizedValue;
  }

  private hasResourceDownloadHeader(headers: Record<string, string>, name: string): boolean {
    const target = name.trim().toLowerCase();
    return Object.keys(headers).some((key: string) => key.trim().toLowerCase() === target);
  }

  private buildSurfaceInput(input: BrowserMediaDiscoverySurfaceInput): BrowserMediaDiscoverySurfaceBuildInput {
    const tabId = input.tabId;
    const videoTakeoverEnabled = input.runtime.webVideoTakeoverEnabled;
    return {
      fullAppServiceMode: input.runtime.fullAppServiceMode,
      tabId: tabId,
      videoTakeoverEnabled: videoTakeoverEnabled,
      resourcePanelOpen: input.resourcePanelOpen ?? (input.runtime.mediaResourcesPanelOpen === true),
      resourceScanInProgress: this.resourceDomScanState.inProgress && this.resourceDomScanState.tabId === tabId
    };
  }

  private readRequestHeader(request: WebResourceRequest, name: string): string | undefined {
    try {
      const headers = request.getRequestHeader();
      if (headers === undefined || headers === null) {
        return undefined;
      }
      const lowerName = name.toLowerCase();
      for (let i = 0; i < headers.length; i++) {
        const headerName = headers[i].headerKey ?? '';
        if (headerName.toLowerCase() !== lowerName) {
          continue;
        }
        const value = headers[i].headerValue;
        return value !== undefined && value.length > 0 ? value : undefined;
      }
      return undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private logMediaSurface(
    input: BrowserMediaDiscoverySurfaceInput,
    videoCount: number,
    resourceCount: number,
    projectionSummary: BrowserMediaDiscoveryProjectionSummary
  ): void {
    if (input.runtime.privateMode) {
      return;
    }
    const resourcePanelOpen = input.resourcePanelOpen ?? (input.runtime.mediaResourcesPanelOpen === true);
    if (resourceCount <= 0 && videoCount <= 0 && !resourcePanelOpen) {
      return;
    }
    hilog.info(
      MEDIA_DISCOVERY_LOG_DOMAIN,
      MEDIA_DISCOVERY_LOG_TAG,
      'media surface tab=%{public}s enabled=%{public}s panel=%{public}s video=%{public}d resource=%{public}d mediaCandidates=%{public}d mediaVideo=%{public}d mediaResource=%{public}d',
      input.tabId,
      input.runtime.webVideoTakeoverEnabled ? 'true' : 'false',
      resourcePanelOpen ? 'true' : 'false',
      videoCount,
      resourceCount,
      projectionSummary.mediaCandidateCount,
      projectionSummary.projectedVideoCount,
      projectionSummary.projectedResourceCount
    );
  }

  private buildProjectionSummary(tabId: string): BrowserMediaDiscoveryProjectionSummary {
    if (tabId.length <= 0) {
      return {
        mediaCandidateCount: 0,
        projectedVideoCount: 0,
        projectedResourceCount: 0
      };
    }
    const snapshot = this.projectLegacyMediaSnapshot(tabId);
    let projectedVideoCount = 0;
    let projectedResourceCount = 0;
    for (let i = 0; i < snapshot.records.length; i++) {
      const candidate = snapshot.records[i].candidate;
      if (this.isVideoMediaForPolicy(candidate)) {
        projectedVideoCount += 1;
      }
      if (this.isProjectedMediaResourceForSummary(candidate)) {
        projectedResourceCount += 1;
      }
    }
    return {
      mediaCandidateCount: snapshot.records.length,
      projectedVideoCount: projectedVideoCount,
      projectedResourceCount: projectedResourceCount
    };
  }

  private isProjectedMediaResourceForSummary(candidate: MediaCandidate): boolean {
    if (candidate.url.trim().length <= 0) {
      return false;
    }
    return candidate.family !== 'unknown' || candidate.kind !== 'unknown' || candidate.actionHints.length > 0;
  }

  private async requestArkWebMediaAssistantSnapshot(
    input: BrowserMediaDiscoveryPageInput,
    host: BrowserMediaDiscoveryHost,
    reason: string,
    capturedEvidence?: BrowserMediaEvidenceCapture
  ): Promise<void> {
    if (input.controller === undefined || !this.arkWebMediaAssistantSignalSource.isSupported()) {
      return;
    }
    const evidenceCapture = capturedEvidence ?? this.captureMediaEvidence(input.tabId);
    try {
      this.arkWebMediaAssistantSignalSource.attach({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        controller: input.controller
      });
      const signals = await this.arkWebMediaAssistantSignalSource.requestSnapshot({
        tabId: input.tabId,
        pageUrl: input.pageUrl,
        pageTitle: input.pageTitle,
        reason: reason
      });
      this.ingestSignals(input.tabId, signals, host, evidenceCapture);
    } catch (_error) {
    }
  }

  private ingestSignals(
    tabId: string,
    signals: MediaSignal[],
    host?: BrowserMediaDiscoveryHost,
    capturedEvidence?: BrowserMediaEvidenceCapture
  ): void {
    if (tabId.length <= 0) {
      return;
    }
    if (signals.length <= 0) {
      return;
    }
    const evidenceCapture = capturedEvidence ?? this.captureMediaEvidence(tabId);
    const effectiveSignals = this.filterSuppressedHeuristicSignals(signals, evidenceCapture);
    if (effectiveSignals.length <= 0) {
      return;
    }
    const receipt = evidenceCapture.ingress.observe({
      scope: evidenceCapture.scope,
      producer: 'legacy_signal_adapter',
      observedAt: Date.now(),
      signals: effectiveSignals
    });
    if (receipt.disposition !== 'committed' ||
      this.mediaEvidenceIngressByTab.get(tabId) !== evidenceCapture.ingress) {
      return;
    }
    if (receipt.changes.validationWork) {
      this.scheduleValidationForTab(tabId, host);
    }
    if (host !== undefined && receipt.changes.resourceSurface) {
      this.requestMediaDiscoverySurfaceRefresh(tabId, host);
    }
  }

  private runProfileSelectorProbe(
    input: BrowserMediaDiscoveryPageInput,
    host: BrowserMediaDiscoveryHost
  ): void {
    if (input.controller === undefined) {
      return;
    }
    const evidenceCapture = this.captureMediaEvidence(input.tabId);
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(input.tabId);
    if (resolution === undefined || !resolution.isProfileApplied() ||
      !this.sameMediaEvidenceScope(resolution.getScope(), evidenceCapture.scope) ||
      host.resolvePageUrlForTab(input.tabId) !== input.pageUrl) {
      return;
    }
    const profileAttribution = resolution.getDiagnosticAttribution()?.profileKey ?? '';
    const plans = resolution.getSelectorPlans();
    if (profileAttribution.length <= 0 || plans.length <= 0) {
      return;
    }
    void this.mediaProbeBridge.runVideoCompatibilitySelectorProbe(
      input.controller,
      input.pageUrl,
      profileAttribution,
      plans
    ).then((observations: MediaCompatibilitySelectorEvidenceObservation[]): void => {
      if (host.resolvePageUrlForTab(input.tabId) !== input.pageUrl ||
        this.mediaEvidenceIngressByTab.get(input.tabId) !== evidenceCapture.ingress ||
        !this.sameMediaEvidenceScope(this.captureMediaEvidence(input.tabId).scope, evidenceCapture.scope)) {
        return;
      }
      this.ingestProfileSelectorEvidence(evidenceCapture, observations);
    }).catch((_error: Error): void => {});
  }

  private ingestProfileSelectorEvidence(
    evidenceCapture: BrowserMediaEvidenceCapture,
    observations: MediaCompatibilitySelectorEvidenceObservation[]
  ): void {
    if (observations.length <= 0 || this.mediaEvidenceIngressByTab.get(evidenceCapture.tabId) !== evidenceCapture.ingress) {
      return;
    }
    evidenceCapture.ingress.observe({
      scope: evidenceCapture.scope,
      producer: 'profile_selector',
      observedAt: Date.now(),
      signals: [],
      selectorEvidence: observations
    });
  }

  /**
   * A Profile-selected Acquisition Recipe adds only attributed resource observations. The generic engine still
   * owns the fallback path and all Session, Route, Reachability, and Entry Eligibility authority.
   */
  private runProfileAcquisition(
    tabId: string,
    pageUrl: string,
    controller: webview.WebviewController,
    evidenceCapture: BrowserMediaEvidenceCapture,
    host: BrowserMediaDiscoveryHost,
    isScheduledProbeCurrent: () => boolean
  ): void {
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(tabId);
    const capability = resolution?.getAcquisitionCapability();
    if (resolution === undefined || !resolution.isProfileApplied() ||
      capability === undefined ||
      capability.getScheduler() !== undefined ||
      !this.sameMediaEvidenceScope(resolution.getScope(), evidenceCapture.scope) ||
      host.resolvePageUrlForTab(tabId) !== pageUrl) {
      return;
    }
    const profileAttribution = resolution.getDiagnosticAttribution()?.profileKey ?? '';
    if (profileAttribution.length <= 0) {
      return;
    }
    const lease = new VideoCompatibilityProfileAcquisitionLease(
      evidenceCapture.scope,
      pageUrl,
      profileAttribution
    );
    void capability.acquire(
      controller,
      pageUrl,
      Date.now(),
      host.resolvePrivacyModeForTab(tabId)
    ).then((report: VideoCompatibilityAcquisitionReport | undefined): void => {
      if (report === undefined || !this.isCurrentProfileAcquisition(
        tabId,
        evidenceCapture,
        lease,
        host,
        isScheduledProbeCurrent
      )) {
        return;
      }
      const projected = this.mediaProbeBridge.projectProfileAcquisitionReport({
        tabId: tabId,
        pageUrl: pageUrl,
        pageTitle: host.resolvePageTitleForTab(tabId),
        privacyMode: host.resolvePrivacyModeForTab(tabId),
        controller: controller,
        report: report,
        profileAttribution: profileAttribution
      });
      this.ingestSignals(tabId, projected.signals, host, evidenceCapture);
    }).catch((_error: Error): void => {});
  }

  private async runTakeoverLaunchProfileAcquisition(
    input: BrowserMediaDiscoveryLaunchProbeInput,
    host: BrowserMediaDiscoveryHost
  ): Promise<void> {
    if (!this.shouldRunScheduledProfileAcquisition(input.tabId, input.pageUrl, host)) {
      return;
    }
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(input.tabId);
    const scheduler = resolution?.getAcquisitionCapability()?.getScheduler();
    if (resolution === undefined || !resolution.isProfileApplied() || scheduler === undefined) {
      return;
    }
    await scheduler.runTakeoverProbe({
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      privacyMode: input.privacyMode,
      controller: input.controller
    }, this.buildProfileAcquisitionSchedulerHost(host));
  }

  private scheduleProfileAcquisition(
    input: BrowserMediaDiscoveryPageInput,
    host: BrowserMediaDiscoveryHost,
    reason: string
  ): void {
    this.scheduleProfileAcquisitionForTab(
      input.tabId,
      input.pageUrl,
      host,
      reason,
      input.controller
    );
  }

  private scheduleProfileAcquisitionForTab(
    tabId: string,
    pageUrl: string,
    host: BrowserMediaDiscoveryHost,
    reason: string,
    controllerOverride?: webview.WebviewController
  ): void {
    if (!this.shouldRunScheduledProfileAcquisition(tabId, pageUrl, host)) {
      return;
    }
    const controller = controllerOverride ?? this.resolveControllerForTab(tabId);
    if (controller === undefined) {
      return;
    }
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(tabId);
    const scheduler: VideoCompatibilityProfileAcquisitionScheduler | undefined =
      resolution?.getAcquisitionCapability()?.getScheduler();
    if (resolution === undefined || !resolution.isProfileApplied() || scheduler === undefined) {
      return;
    }
    const input: VideoCompatibilityProfileAcquisitionProbeInput = {
      tabId: tabId,
      pageUrl: pageUrl,
      privacyMode: host.resolvePrivacyModeForTab(tabId),
      controller: controller
    };
    const schedulerHost = this.buildProfileAcquisitionSchedulerHost(host);
    if (reason === 'history_api_url_change') {
      scheduler.scheduleSpaRouteProbe(input, schedulerHost);
      return;
    }
    scheduler.schedulePageProbe(input, schedulerHost);
  }

  private observeProfileAcquisitionIntercept(
    input: BrowserMediaDiscoveryInterceptInput,
    host: BrowserMediaDiscoveryHost
  ): void {
    const controller = input.controller ?? this.resolveControllerForTab(input.tabId);
    if (controller === undefined) {
      return;
    }
    if (!this.shouldRunScheduledProfileAcquisition(input.tabId, input.pageUrl, host)) {
      return;
    }
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(input.tabId);
    const scheduler: VideoCompatibilityProfileAcquisitionScheduler | undefined =
      resolution?.getAcquisitionCapability()?.getScheduler();
    if (resolution === undefined || !resolution.isProfileApplied() || scheduler === undefined) {
      return;
    }
    let requestUrl = '';
    try {
      requestUrl = input.request.getRequestUrl();
    } catch (_error) {
      return;
    }
    const schedulerInput: VideoCompatibilityProfileAcquisitionInterceptInput = {
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      requestUrl: requestUrl,
      referer: this.readRequestHeader(input.request, 'Referer'),
      userAgent: this.readRequestHeader(input.request, 'User-Agent'),
      originUrl: this.readRequestHeader(input.request, 'Origin')
    };
    const trigger = scheduler.observeIntercept(schedulerInput);
    if (trigger === undefined) {
      return;
    }
    if (!this.shouldRunScheduledProfileAcquisition(input.tabId, trigger.pageUrl, host)) {
      return;
    }
    scheduler.schedulePageProbe({
      tabId: input.tabId,
      pageUrl: trigger.pageUrl,
      privacyMode: input.privacyMode,
      controller: controller,
      delayedProbeDelayMs: trigger.delayedProbeDelayMs
    }, this.buildProfileAcquisitionSchedulerHost(host));
  }

  private buildProfileAcquisitionSchedulerHost(
    host: BrowserMediaDiscoveryHost
  ): VideoCompatibilityProfileAcquisitionProbeHost {
    return {
      shouldRunDelayedProbe: (tabId: string, pageUrl: string, _expectedMediaId: string): boolean =>
        this.shouldRunScheduledProfileAcquisition(tabId, pageUrl, host),
      onReport: (input: VideoCompatibilityProfileAcquisitionProbeInput,
        report: VideoCompatibilityAcquisitionReport): void => {
        this.acceptScheduledProfileAcquisitionReport(input, report, host);
      },
      onProbeSettled: (tabId: string): void => {
        this.requestMediaDiscoverySurfaceRefresh(tabId, host);
      }
    };
  }

  private acceptScheduledProfileAcquisitionReport(
    input: VideoCompatibilityProfileAcquisitionProbeInput,
    report: VideoCompatibilityAcquisitionReport,
    host: BrowserMediaDiscoveryHost
  ): void {
    if (input.controller === undefined ||
      !this.shouldRunScheduledProfileAcquisition(input.tabId, input.pageUrl, host)) {
      return;
    }
    const evidenceCapture = this.captureMediaEvidence(input.tabId);
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(input.tabId);
    const profileAttribution = resolution?.getDiagnosticAttribution()?.profileKey ?? '';
    if (resolution === undefined || !resolution.isProfileApplied() || profileAttribution.length <= 0 ||
      resolution.getAcquisitionCapability()?.getScheduler() === undefined ||
      !this.sameMediaEvidenceScope(resolution.getScope(), evidenceCapture.scope) ||
      host.resolvePageUrlForTab(input.tabId) !== input.pageUrl) {
      return;
    }
    const lease = new VideoCompatibilityProfileAcquisitionLease(
      evidenceCapture.scope,
      input.pageUrl,
      profileAttribution
    );
    if (!this.isCurrentProfileAcquisition(
      input.tabId,
      evidenceCapture,
      lease,
      host,
      (): boolean => this.shouldRunScheduledProfileAcquisition(input.tabId, input.pageUrl, host)
    )) {
      return;
    }
    const projected = this.mediaProbeBridge.projectProfileAcquisitionReport({
      tabId: input.tabId,
      pageUrl: input.pageUrl,
      pageTitle: host.resolvePageTitleForTab(input.tabId),
      privacyMode: input.privacyMode,
      controller: input.controller,
      report: report,
      profileAttribution: profileAttribution
    });
    this.ingestSignals(input.tabId, projected.signals, host, evidenceCapture);
  }

  private clearProfileAcquisitionScheduler(tabId: string): void {
    this.videoCompatibilityProfileCatalog.getCurrentResolution(tabId)?.getAcquisitionCapability()?.getScheduler()?.clearTab(tabId);
  }

  private isCurrentProfileAcquisition(
    tabId: string,
    evidenceCapture: BrowserMediaEvidenceCapture,
    lease: VideoCompatibilityProfileAcquisitionLease,
    host: BrowserMediaDiscoveryHost,
    isScheduledProbeCurrent: () => boolean
  ): boolean {
    if (!isScheduledProbeCurrent() ||
      this.mediaEvidenceIngressByTab.get(tabId) !== evidenceCapture.ingress ||
      !this.sameMediaEvidenceScope(this.captureMediaEvidence(tabId).scope, evidenceCapture.scope)) {
      return false;
    }
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(tabId);
    return resolution !== undefined && resolution.isProfileApplied() &&
      resolution.getAcquisitionCapability() !== undefined &&
      this.sameMediaEvidenceScope(resolution.getScope(), evidenceCapture.scope) &&
      lease.isCurrent(
        resolution.getScope(),
        host.resolvePageUrlForTab(tabId),
        resolution.getDiagnosticAttribution()?.profileKey ?? ''
      );
  }

  private resolveReplacedGenericDeepProbeStrategyIds(
    evidenceCapture: BrowserMediaEvidenceCapture,
    pageUrl: string
  ): VideoCompatibilityReplacedGenericDeepProbeStrategyId[] {
    const resolution = this.videoCompatibilityProfileCatalog.resolve({
      scope: evidenceCapture.scope,
      pageUrl: pageUrl
    });
    if (!resolution.isProfileApplied() ||
      !this.sameMediaEvidenceScope(resolution.getScope(), evidenceCapture.scope)) {
      return [];
    }
    return resolution.getAcquisitionCapability()?.getReplacedGenericDeepProbeStrategyIds() ?? [];
  }

  private filterSuppressedHeuristicSignals(
    signals: MediaSignal[],
    evidenceCapture: BrowserMediaEvidenceCapture
  ): MediaSignal[] {
    if (signals.length <= 0) {
      return [];
    }
    const resolution = this.videoCompatibilityProfileCatalog.resolve({
      scope: evidenceCapture.scope,
      pageUrl: signals[0].pageUrl
    });
    if (!resolution.isProfileApplied()) {
      return signals;
    }
    const filtered: MediaSignal[] = [];
    for (let index = 0; index < signals.length; index += 1) {
      const signal = signals[index];
      const suppressionSource = this.resolveSuppressionSource(signal);
      if (suppressionSource !== undefined && resolution.isHeuristicSuppressed(suppressionSource)) {
        continue;
      }
      filtered.push(signal);
    }
    return filtered;
  }

  private resolveSuppressionSource(signal: MediaSignal): VideoCompatibilityHeuristicSource | undefined {
    if (signal.signalKind === 'dom_probe' && this.hasWeakHeuristicEvidence(signal)) {
      return 'generic_dom_probe';
    }
    if (signal.signalKind === 'deep_probe' && this.hasWeakHeuristicEvidence(signal)) {
      return 'generic_deep_probe';
    }
    return undefined;
  }

  private hasWeakHeuristicEvidence(signal: MediaSignal): boolean {
    for (let index = 0; index < signal.evidence.length; index += 1) {
      const evidence = signal.evidence[index];
      if ((evidence.kind === 'resource_evidence' && evidence.value === 'weak_text_match') ||
        (evidence.kind === 'dom_signal' &&
          (evidence.value === 'script_text' || evidence.value === 'location' || evidence.value === 'text_match'))) {
        return true;
      }
    }
    return false;
  }

  private sameMediaEvidenceScope(
    left: MediaEvidenceScope,
    right: MediaEvidenceScope
  ): boolean {
    return left.tabId === right.tabId && left.generationId === right.generationId &&
      left.routeEpochId === right.routeEpochId;
  }

  private ingestSemanticEvidence(
    evidenceCapture: BrowserMediaEvidenceCapture,
    producer: MediaEvidenceProducerKind,
    observedAt: number,
    observations: MediaEvidenceSemanticObservation[]
  ): boolean {
    if (evidenceCapture.tabId.length <= 0 || observations.length <= 0 ||
      this.mediaEvidenceIngressByTab.get(evidenceCapture.tabId) !== evidenceCapture.ingress) {
      return false;
    }
    const receipt = evidenceCapture.ingress.observe({
      scope: evidenceCapture.scope,
      producer: producer,
      observedAt: observedAt,
      signals: [],
      observations: observations
    });
    return receipt.disposition === 'committed' && receipt.changes.sessionEvidence &&
      this.mediaEvidenceIngressByTab.get(evidenceCapture.tabId) === evidenceCapture.ingress;
  }

  private nonNegativeFinite(value: number): number {
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  private scheduleValidationForTab(tabId: string, host?: BrowserMediaDiscoveryHost): void {
    const now = Date.now();
    const evidenceCapture = this.captureMediaEvidence(tabId);
    const targets = evidenceCapture.ingress.compatibilityReader().listValidationTargets(now);
    if (targets.length <= 0) {
      return;
    }
    const generation = this.resolveValidationGeneration(tabId);
    for (let i = 0; i < targets.length; i++) {
      const candidate = targets[i];
      if (!this.validationService.shouldValidate(candidate, now)) {
        continue;
      }
      const fingerprint = this.validationService.buildFingerprint(candidate);
      const jobKey = tabId + ':' + candidate.id + ':' + fingerprint;
      if (this.validationJobsByKey.get(jobKey) === true) {
        continue;
      }
      if (!evidenceCapture.ingress.markValidationInProgress(
        evidenceCapture.scope,
        candidate.id,
        fingerprint,
        now
      )) {
        continue;
      }
      this.validationJobsByKey.set(jobKey, true);
      void this.validationService.validate(candidate)
        .then((result: MediaCandidateValidationResult) => {
          this.finishValidationJob(jobKey, tabId, generation, evidenceCapture, result, host);
        })
        .catch((error: Error) => {
          this.finishValidationError(
            jobKey,
            tabId,
            generation,
            evidenceCapture,
            candidate,
            fingerprint,
            error,
            host
          );
        });
    }
  }

  private finishValidationJob(
    jobKey: string,
    tabId: string,
    generation: number,
    evidenceCapture: BrowserMediaEvidenceCapture,
    result: MediaCandidateValidationResult,
    host?: BrowserMediaDiscoveryHost
  ): void {
    this.validationJobsByKey.delete(jobKey);
    if (generation !== this.resolveValidationGeneration(tabId)) {
      return;
    }
    if (this.mediaEvidenceIngressByTab.get(tabId) !== evidenceCapture.ingress ||
      !evidenceCapture.ingress.applyValidationResult(evidenceCapture.scope, result)) {
      return;
    }
    this.refreshSurfaceAfterValidation(tabId, host);
  }

  private finishValidationError(
    jobKey: string,
    tabId: string,
    generation: number,
    evidenceCapture: BrowserMediaEvidenceCapture,
    candidate: MediaCandidate,
    fingerprint: string,
    error: Error,
    host?: BrowserMediaDiscoveryHost
  ): void {
    this.validationJobsByKey.delete(jobKey);
    if (generation !== this.resolveValidationGeneration(tabId)) {
      return;
    }
    const message = this.stringifyValidationError(error);
    const result = this.validationService.buildUnexpectedFailure(candidate, fingerprint, message);
    if (this.mediaEvidenceIngressByTab.get(tabId) !== evidenceCapture.ingress ||
      !evidenceCapture.ingress.applyValidationResult(evidenceCapture.scope, result)) {
      return;
    }
    this.refreshSurfaceAfterValidation(tabId, host);
  }

  private refreshSurfaceAfterValidation(tabId: string, host?: BrowserMediaDiscoveryHost): void {
    if (host !== undefined) {
      this.requestMediaDiscoverySurfaceRefresh(tabId, host);
    }
  }

  private ensureMediaEvidenceIngress(tabId: string): MediaEvidenceGenerationIngress {
    const existing = this.mediaEvidenceIngressByTab.get(tabId);
    if (existing !== undefined) {
      return existing;
    }
    const now = Date.now();
    const ingress = this.mediaEvidenceGraph.beginGeneration({
      tabId: tabId,
      navigationKey: 'lazy:' + tabId + ':' + now.toString(),
      pageUrl: '',
      pageTitle: '',
      privacyMode: 'regular',
      startedAt: now
    });
    this.mediaEvidenceIngressByTab.set(tabId, ingress);
    return ingress;
  }

  private captureMediaEvidence(tabId: string): BrowserMediaEvidenceCapture {
    const ingress = this.ensureMediaEvidenceIngress(tabId);
    const capture: BrowserMediaEvidenceCapture = {
      tabId: tabId,
      ingress: ingress,
      scope: ingress.currentScope(),
      capturedAt: Date.now()
    };
    return capture;
  }

  private projectLegacyMediaSnapshot(tabId: string): MediaDiscoveryTabSnapshot {
    if (tabId.trim().length <= 0) {
      const emptySnapshot: MediaDiscoveryTabSnapshot = {
        tabId: tabId,
        records: []
      };
      return emptySnapshot;
    }
    return this.ensureMediaEvidenceIngress(tabId).compatibilityReader().projectResourceSnapshot();
  }

  private closeMediaEvidenceGeneration(
    tabId: string,
    reason: MediaEvidenceGenerationCloseReason
  ): void {
    const ingress = this.mediaEvidenceIngressByTab.get(tabId);
    if (ingress !== undefined) {
      ingress.close({
        reason: reason,
        closedAt: Date.now()
      });
      this.mediaEvidenceIngressByTab.delete(tabId);
    }
  }

  private bumpValidationGeneration(tabId: string): void {
    if (tabId.length <= 0) {
      return;
    }
    this.validationGenerationByTab.set(tabId, this.resolveValidationGeneration(tabId) + 1);
  }

  private resolveValidationGeneration(tabId: string): number {
    return this.validationGenerationByTab.get(tabId) ?? 0;
  }

  private stringifyValidationError(error: Error): string {
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    try {
      const serialized = JSON.stringify(error);
      return serialized.length > 0 ? serialized : '未知错误';
    } catch (_stringifyError) {
      return '未知错误';
    }
  }

  private clearSignalSourcesForTab(tabId: string): void {
    this.arkWebMediaAssistantSignalSource.clearTab(tabId);
  }

  private shouldSkipResourceDomScan(tabId: string, pageUrl: string, now: number): boolean {
    if (this.resourceDomScanState.inProgress &&
      this.resourceDomScanState.tabId === tabId &&
      this.resourceDomScanState.pageUrl === pageUrl) {
      return true;
    }
    return this.resourceDomScanState.tabId === tabId &&
      this.resourceDomScanState.pageUrl === pageUrl &&
      now - this.resourceDomScanState.startedAt < RESOURCE_DOM_SCAN_MIN_INTERVAL_MS;
  }

  private beginResourceDomScan(tabId: string, pageUrl: string, now: number): void {
    this.resourceDomScanState = {
      inProgress: true,
      tabId: tabId,
      pageUrl: pageUrl,
      startedAt: now
    };
  }

  private finishResourceDomScanIfCurrent(tabId: string, pageUrl: string): void {
    if (this.resourceDomScanState.tabId !== tabId || this.resourceDomScanState.pageUrl !== pageUrl) {
      return;
    }
    this.resourceDomScanState = {
      inProgress: false,
      tabId: this.resourceDomScanState.tabId,
      pageUrl: this.resourceDomScanState.pageUrl,
      startedAt: this.resourceDomScanState.startedAt
    };
  }

  private clearResourceDomScanState(): void {
    this.resourceDomScanState = {
      inProgress: false,
      tabId: '',
      pageUrl: '',
      startedAt: 0
    };
  }

  private clearResourceDomScanStateForTab(tabId: string): void {
    if (this.resourceDomScanState.tabId === tabId) {
      this.clearResourceDomScanState();
    }
  }

  private scheduleDeepProbes(input: BrowserMediaDiscoveryPageInput, host: BrowserMediaDiscoveryHost): void {
    const plan = this.probePolicy.buildVideoPageEndDeepProbePlan(
      this.buildProbePolicyContext(input, 'page_end')
    );
    if (!plan.enabled) {
      return;
    }
    const schedulerHost: BrowserMediaProbeSchedulerHost = {
      isActiveTab: (tabId: string): boolean => host.isActiveTab(tabId),
      shouldRun: (tabId: string, url: string): boolean => this.shouldRunScheduledDeepProbe(tabId, url, host),
      resolveInteractionQuietDelayMs: (_tabId: string): number => host.resolveInteractionQuietDelayMs(0),
      runDeepProbe: (
        tabId: string,
        url: string,
        pageTitle: string,
        isCurrent: () => boolean
      ): Promise<void> => {
        return this.runScheduledDeepProbe(tabId, url, pageTitle, host, isCurrent);
      }
    };
    this.probeScheduler.scheduleDeepProbes({
      tabId: input.tabId,
      url: input.pageUrl,
      pageTitle: input.pageTitle,
      plan: plan
    }, schedulerHost);
  }

  private schedulePageEndDomProbe(input: BrowserMediaDiscoveryPageInput, host: BrowserMediaDiscoveryHost): void {
    const schedulerHost: BrowserMediaInteractionQuietTaskHost = {
      isActiveTab: (tabId: string): boolean => host.isActiveTab(tabId),
      shouldRun: (tabId: string, url: string): boolean => this.shouldRunPageEndDomProbe(tabId, url, host),
      resolveInteractionQuietDelayMs: (_tabId: string): number => host.resolveInteractionQuietDelayMs(0),
      runTask: (tabId: string, url: string, isCurrent: () => boolean): Promise<void> =>
        this.runPageEndDomProbe(tabId, url, host, isCurrent)
    };
    this.probeScheduler.scheduleInteractionQuietTask({
      tabId: input.tabId,
      url: input.pageUrl,
      taskKey: 'page_end_dom_probe'
    }, schedulerHost);
  }

  private scheduleAsyncDeepProbeFollowup(
    tabId: string,
    url: string,
    pageTitle: string,
    host: BrowserMediaDiscoveryHost
  ): void {
    const schedulerHost: BrowserMediaInteractionQuietTaskHost = {
      isActiveTab: (candidateTabId: string): boolean => host.isActiveTab(candidateTabId),
      shouldRun: (candidateTabId: string, candidateUrl: string): boolean =>
        this.shouldRunScheduledDeepProbe(candidateTabId, candidateUrl, host),
      resolveInteractionQuietDelayMs: (_candidateTabId: string): number => host.resolveInteractionQuietDelayMs(0),
      runTask: (
        candidateTabId: string,
        candidateUrl: string,
        isCurrent: () => boolean
      ): Promise<void> => this.runScheduledDeepProbe(
        candidateTabId,
        candidateUrl,
        pageTitle,
        host,
        isCurrent
      )
    };
    this.probeScheduler.scheduleInteractionQuietTask({
      tabId: tabId,
      url: url,
      taskKey: 'deep_probe_async_followup',
      delayMs: MEDIA_DEEP_PROBE_ASYNC_FOLLOWUP_DELAY_MS
    }, schedulerHost);
  }

  private shouldRunPageEndDomProbe(tabId: string, url: string, host: BrowserMediaDiscoveryHost): boolean {
    if (host.resolvePageUrlForTab(tabId) !== url) {
      return false;
    }
    return this.probePolicy.shouldRunVideoPageEndProbes(this.buildRuntimePolicyContext(
      host.buildRuntimeContext(),
      'scheduled_page_end'
    ));
  }

  private runPageEndDomProbe(
    tabId: string,
    url: string,
    host: BrowserMediaDiscoveryHost,
    isCurrent: () => boolean
  ): Promise<void> {
    const controller = this.resolveControllerForTab(tabId);
    if (controller === undefined) {
      return Promise.resolve();
    }
    const evidenceCapture = this.captureMediaEvidence(tabId);
    const pageUrl = host.resolvePageUrlForTab(tabId) || url;
    return this.mediaProbeBridge.runVideoDomScan({
      tabId: tabId,
      pageUrl: pageUrl,
      pageTitle: host.resolvePageTitleForTab(tabId),
      privacyMode: host.resolvePrivacyModeForTab(tabId),
      controller: controller
    }).then((report) => {
      if (!isCurrent() || !this.shouldRunPageEndDomProbe(tabId, pageUrl, host)) {
        return;
      }
      this.ingestSignals(tabId, report.signals, host, evidenceCapture);
    }).catch((_error: Error) => {
      if (!isCurrent()) {
        return;
      }
    });
  }

  private shouldRunScheduledDeepProbe(tabId: string, url: string, host: BrowserMediaDiscoveryHost): boolean {
    const pageUrl = host.resolvePageUrlForTab(tabId) || url;
    const runtime = host.buildRuntimeContext();
    const counts = this.buildVideoMediaCounts(tabId);
    return this.probePolicy.buildVideoPageEndDeepProbePlan({
      fullAppServiceMode: runtime.fullAppServiceMode,
      webVideoTakeoverEnabled: runtime.webVideoTakeoverEnabled,
      mediaResourcesPanelOpen: runtime.mediaResourcesPanelOpen,
      pageUrl: pageUrl,
      tabActive: host.isActiveTab(tabId),
      userIntent: 'scheduled_page_end',
      visibleVideoMediaCount: counts.visibleVideoMediaCount,
      videoMediaCount: counts.videoMediaCount
    }).enabled;
  }

  private async runScheduledDeepProbe(
    tabId: string,
    url: string,
    pageTitle: string,
    host: BrowserMediaDiscoveryHost,
    isCurrent: () => boolean
  ): Promise<void> {
    const deepController = this.resolveControllerForTab(tabId);
    if (deepController === undefined) {
      return;
    }
    const evidenceCapture = this.captureMediaEvidence(tabId);
    const pageUrl = host.resolvePageUrlForTab(tabId) || url;
    const resolvedTitle = host.resolvePageTitleForTab(tabId);
    try {
      const report = await this.mediaProbeBridge.runDeepProbe({
        tabId: tabId,
        pageUrl: pageUrl,
        pageTitle: resolvedTitle.length > 0 ? resolvedTitle : pageTitle,
        privacyMode: host.resolvePrivacyModeForTab(tabId),
        controller: deepController,
        intent: 'scheduled',
        replacedGenericDeepProbeStrategyIds: this.resolveReplacedGenericDeepProbeStrategyIds(
          evidenceCapture,
          pageUrl
        )
      });
      if (!isCurrent() || !this.shouldRunScheduledDeepProbe(tabId, pageUrl, host)) {
        return;
      }
      if (report.pendingAsyncWork) {
        this.scheduleAsyncDeepProbeFollowup(tabId, pageUrl, resolvedTitle, host);
      }
      this.ingestSignals(tabId, report.signals, host, evidenceCapture);
      this.runProfileAcquisition(
        tabId,
        pageUrl,
        deepController,
        evidenceCapture,
        host,
        isCurrent
      );
    } catch (_error) {
      if (!isCurrent()) {
        return;
      }
    }
  }

  private resolveControllerForTab(tabId: string): webview.WebviewController | undefined {
    return this.runtimeLifecyclePort.resolveController(tabId);
  }

  private buildProbePolicyContext(
    input: BrowserMediaDiscoveryPageInput,
    userIntent: MediaProbeUserIntent,
    privateModeOverride?: boolean
  ): MediaProbePolicyContext {
    const counts = this.buildVideoMediaCounts(input.tabId);
    return {
      fullAppServiceMode: input.runtime.fullAppServiceMode,
      webVideoTakeoverEnabled: input.runtime.webVideoTakeoverEnabled,
      mediaResourcesPanelOpen: input.runtime.mediaResourcesPanelOpen,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      privateMode: privateModeOverride ?? (input.privacyMode === 'private'),
      userIntent: userIntent,
      visibleVideoMediaCount: counts.visibleVideoMediaCount,
      videoMediaCount: counts.videoMediaCount
    };
  }

  private buildVideoMediaCounts(tabId: string): BrowserMediaDiscoveryVideoMediaCounts {
    const snapshot = this.projectLegacyMediaSnapshot(tabId);
    let videoMediaCount = 0;
    let visibleVideoMediaCount = 0;
    for (let i = 0; i < snapshot.records.length; i++) {
      const candidate = snapshot.records[i].candidate;
      if (!this.isVideoMediaForPolicy(candidate)) {
        continue;
      }
      videoMediaCount += 1;
      if (this.isVisibleVideoMediaForPolicy(candidate)) {
        visibleVideoMediaCount += 1;
      }
    }
    return {
      visibleVideoMediaCount: visibleVideoMediaCount,
      videoMediaCount: videoMediaCount
    };
  }

  private isVideoMediaForPolicy(candidate: MediaCandidate): boolean {
    return candidate.family === 'video' ||
      candidate.family === 'manifest' ||
      candidate.kind === 'hls' ||
      candidate.kind === 'dash' ||
      candidate.kind === 'mp4' ||
      candidate.kind === 'webm' ||
      this.hasVideoAcquisition(candidate);
  }

  private isVisibleVideoMediaForPolicy(candidate: MediaCandidate): boolean {
    return candidate.confidence >= 70 && this.isPresentableVideoCandidate(candidate);
  }

  private isPresentableVideoCandidate(candidate: MediaCandidate): boolean {
    return candidate.kind === 'hls' ||
      candidate.kind === 'dash' ||
      candidate.kind === 'mp4' ||
      candidate.kind === 'webm' ||
      this.hasVideoAcquisition(candidate);
  }

  private hasPairedAdaptiveAcquisition(candidate: MediaCandidate): boolean {
    return candidate.acquisition?.mode === 'paired_adaptive';
  }

  private hasVideoAcquisition(candidate: MediaCandidate): boolean {
    const acquisition = candidate.acquisition;
    return acquisition !== undefined &&
      (acquisition.primaryTrack.role === 'combined' || acquisition.primaryTrack.role === 'video');
  }

  private buildRuntimePolicyContext(
    runtime: BrowserMediaDiscoveryRuntimeContext,
    userIntent: MediaProbeUserIntent
  ): MediaProbePolicyContext {
    return {
      fullAppServiceMode: runtime.fullAppServiceMode,
      webVideoTakeoverEnabled: runtime.webVideoTakeoverEnabled,
      mediaResourcesPanelOpen: runtime.mediaResourcesPanelOpen,
      userIntent: userIntent
    };
  }

}

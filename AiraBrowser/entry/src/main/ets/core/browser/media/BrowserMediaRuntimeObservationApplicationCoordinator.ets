import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserTabBackgroundSessionSyncCoordinator } from '../../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import {
  MediaVideoFrameProbeAdaptResult,
  MediaVideoFrameProbeEvidenceAdapter
} from '../../../services/media/MediaVideoFrameProbeEvidenceAdapter';
import {
  BrowserArkWebMediaFramePlaybackInput,
  BrowserArkWebMediaObservationResult,
  BrowserArkWebMediaPlaybackSignalResult,
  BrowserArkWebMediaRuntimeEvidence,
  BrowserArkWebMediaRuntimeEvidenceCapture,
  BrowserArkWebMediaRectSnapshot,
  BrowserArkWebMediaTakeoverCoordinator
} from './BrowserArkWebMediaTakeoverCoordinator';
import {
  BrowserMediaDiscoveryCoordinator,
  BrowserMediaEvidenceCapture
} from './BrowserMediaDiscoveryCoordinator';
import { BrowserMediaFrameRuntimeCoordinator } from './BrowserMediaFrameRuntimeCoordinator';
import { MediaSessionResolutionRuntimeService } from
  '../../../services/media/MediaSessionResolutionRuntimeService';
import {
  sharedVideoCompatibilityProfileCatalog,
  VideoCompatibilityProfileCatalog
} from '../../../services/media/VideoCompatibilityProfileCatalog';
import {
  MediaResolvedVideoAssistantSession,
  MediaSessionResolutionSnapshot
} from '../../../features/mediaDiscovery/MediaSessionResolutionModels';

const MEDIA_FRAME_RUNTIME_LOG_DOMAIN: number = 0x3900;
const MEDIA_FRAME_RUNTIME_LOG_TAG: string = 'AiraMediaFrameRuntime';
const DIRECT_LAYOUT_REVALIDATION_DELAY_MS: number = 280;

interface BrowserMediaPageBehaviorVideoEventPayload {
  eventName?: string;
}

interface BrowserMediaPageBehaviorPayload {
  videoEvent?: BrowserMediaPageBehaviorVideoEventPayload;
}

interface BrowserMediaDirectLayoutRevalidationState {
  generation: number;
  timerId: number;
}

export interface BrowserMediaRuntimeObservationApplicationHost {
  resolvePageUrl: (tabId: string) => string;
  resolvePageTitle: (tabId: string) => string;
  resolvePrivateMode: (tabId: string) => boolean;
  resolveWebActionToolbarEnabled: (tabId: string) => boolean;
  requestWebActionToolbarFullscreen: (tabId: string, payloadJson: string) => void;
  invalidateTakeoverPresentation: () => void;
}

export class BrowserMediaRuntimeObservationApplicationCoordinator {
  private readonly mediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator;
  private readonly mediaTakeoverCoordinator: BrowserArkWebMediaTakeoverCoordinator;
  private readonly backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  private readonly mediaFrameRuntimeCoordinator: BrowserMediaFrameRuntimeCoordinator;
  private readonly host: BrowserMediaRuntimeObservationApplicationHost;
  private readonly frameProbeEvidenceAdapter: MediaVideoFrameProbeEvidenceAdapter =
    new MediaVideoFrameProbeEvidenceAdapter();
  private readonly sessionResolutionRuntimeService: MediaSessionResolutionRuntimeService =
    new MediaSessionResolutionRuntimeService();
  private readonly videoCompatibilityProfileCatalog: VideoCompatibilityProfileCatalog;
  private evidenceCaptureByTabId: Map<string, BrowserMediaEvidenceCapture> = new Map();
  private directLayoutRevalidationByTabId: Map<string, BrowserMediaDirectLayoutRevalidationState> = new Map();

  constructor(
    mediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator,
    mediaTakeoverCoordinator: BrowserArkWebMediaTakeoverCoordinator,
    backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator,
    mediaFrameRuntimeCoordinator: BrowserMediaFrameRuntimeCoordinator,
    host: BrowserMediaRuntimeObservationApplicationHost,
    videoCompatibilityProfileCatalog: VideoCompatibilityProfileCatalog = sharedVideoCompatibilityProfileCatalog
  ) {
    this.mediaDiscoveryCoordinator = mediaDiscoveryCoordinator;
    this.mediaTakeoverCoordinator = mediaTakeoverCoordinator;
    this.backgroundSessionSyncCoordinator = backgroundSessionSyncCoordinator;
    this.mediaFrameRuntimeCoordinator = mediaFrameRuntimeCoordinator;
    this.host = host;
    this.videoCompatibilityProfileCatalog = videoCompatibilityProfileCatalog;
    this.mediaFrameRuntimeCoordinator.bindNativeActionHost({
      requestFullscreen: (tabId: string, payloadJson: string): void => {
        this.host.requestWebActionToolbarFullscreen(tabId, payloadJson);
      }
    });
    this.mediaTakeoverCoordinator.bindRuntimeEvidencePublisher({
      capture: (tabId: string): BrowserArkWebMediaRuntimeEvidenceCapture | undefined =>
        this.captureRuntimeEvidence(tabId),
      resolveSnapshot: (tabId: string): MediaSessionResolutionSnapshot | undefined =>
        this.sessionResolutionRuntimeService.getSnapshot(tabId),
      resolveCastMedia: (tabId: string, playbackTargetId: string) =>
        this.mediaDiscoveryCoordinator.resolveActivePlaybackCastMedia(tabId, playbackTargetId)
    });
  }

  beginDocument(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.cancelDirectLayoutRevalidation(normalizedTabId);
    this.sessionResolutionRuntimeService.clearTab(normalizedTabId);
    try {
      this.mediaFrameRuntimeCoordinator.beginDocument(normalizedTabId, this.host.resolvePrivateMode(normalizedTabId));
    } catch (_error) {
    }
    try {
      const capture = this.mediaDiscoveryCoordinator.captureSemanticEvidence(normalizedTabId);
      if (capture !== undefined) {
        this.evidenceCaptureByTabId.set(normalizedTabId, capture);
        this.activateProfileResolution(capture, this.host.resolvePageUrl(normalizedTabId));
      }
    } catch (_error) {
    }
  }

  clearTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    this.cancelDirectLayoutRevalidation(normalizedTabId);
    this.evidenceCaptureByTabId.delete(normalizedTabId);
    this.videoCompatibilityProfileCatalog.clearTab(normalizedTabId);
    this.sessionResolutionRuntimeService.clearTab(normalizedTabId);
    try {
      this.mediaFrameRuntimeCoordinator.clearTab(normalizedTabId);
    } catch (_error) {
    }
  }

  advanceRoute(
    tabId: string,
    pageUrl: string,
    pageTitle: string,
    transitionKey: string,
    observedAt: number
  ): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.cancelDirectLayoutRevalidation(normalizedTabId);
    try {
      const currentCapture = this.evidenceCaptureByTabId.get(normalizedTabId) ??
        this.mediaDiscoveryCoordinator.captureSemanticEvidence(normalizedTabId);
      if (currentCapture === undefined) {
        return;
      }
      const nextCapture = this.mediaDiscoveryCoordinator.advanceSemanticEvidenceRoute({
        capture: currentCapture,
        pageUrl: pageUrl,
        pageTitle: pageTitle,
        transitionKey: transitionKey,
        observedAt: observedAt
      });
      if (nextCapture !== undefined) {
        this.evidenceCaptureByTabId.set(normalizedTabId, nextCapture);
        this.activateProfileResolution(nextCapture, pageUrl);
        this.refreshSessionResolution(normalizedTabId, Date.now());
        // SPA 换视频(如 B站换集)推进路由后,旧证据失效、会话关联刷新,
        // 必须主动通知界面重算按钮状态,否则按钮会停留在旧视频状态或不再出现。
        this.host.invalidateTakeoverPresentation();
      }
    } catch (_error) {
    }
  }

  handleNativeMediaPlayerObserved(tabId: string, mediaInfo: webview.MediaInfo): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    const result: BrowserArkWebMediaObservationResult = this.mediaTakeoverCoordinator.observe({
      tabId: normalizedTabId,
      pageUrl: this.host.resolvePageUrl(normalizedTabId),
      pageTitle: this.host.resolvePageTitle(normalizedTabId),
      suppressDiagnostics: this.host.resolvePrivateMode(normalizedTabId),
      mediaInfo: mediaInfo
    });
    let evidenceChanged = false;
    const capture = this.evidenceCaptureByTabId.get(normalizedTabId);
    if (capture !== undefined) {
      try {
        evidenceChanged = this.mediaDiscoveryCoordinator.observeArkWebMediaInfoEvidence(capture, mediaInfo);
      } catch (_error) {
        evidenceChanged = false;
      }
    }
    if (result.accepted || evidenceChanged) {
      this.refreshSessionResolution(normalizedTabId, Date.now());
    }
    if (result.accepted && result.changed) {
      this.host.invalidateTakeoverPresentation();
    }
  }

  handlePageBehaviorSignal(tabId: string, payloadJson: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    const isFrameProbePayload = this.frameProbeEvidenceAdapter.isProbePayload(payloadJson);
    if (isFrameProbePayload) {
      const frameProbe = this.frameProbeEvidenceAdapter.adapt(payloadJson, Date.now());
      if (frameProbe !== undefined) {
        this.handleFrameProbeSignal(normalizedTabId, frameProbe);
      }
      return;
    }
    this.backgroundSessionSyncCoordinator.handlePageBehaviorSignal(normalizedTabId, payloadJson);
    const takeoverResult = this.mediaTakeoverCoordinator.observePageBehaviorSignal(normalizedTabId, payloadJson);
    const capture = this.evidenceCaptureByTabId.get(normalizedTabId);
    let evidenceChanged = false;
    try {
      evidenceChanged = capture !== undefined &&
        this.mediaDiscoveryCoordinator.observePageBehaviorEvidence(capture, payloadJson);
    } catch (_error) {
      evidenceChanged = false;
    }
    const snapshot = evidenceChanged ?
      this.refreshSessionResolution(normalizedTabId, Date.now()) :
      this.sessionResolutionRuntimeService.getSnapshot(normalizedTabId);
    if (takeoverResult.changed || evidenceChanged) {
      this.host.invalidateTakeoverPresentation();
    }
    const directSession = this.resolveActiveSession(snapshot);
    const directBinding = directSession?.playbackTargetBinding;
    const forceLayoutRevalidation = this.isDirectLayoutRevalidationPayload(payloadJson);
    if (directSession !== undefined && directSession.playbackState === 'playing' &&
      directBinding?.transport === 'document_direct' && directBinding.runtimeId.length > 0) {
      void this.mediaTakeoverCoordinator.verifyDocumentDirectReachability(
        normalizedTabId,
        directSession.sessionId,
        directBinding.runtimeId,
        forceLayoutRevalidation
      ).then((result) => {
        this.commitWebLiveReachabilityResult(normalizedTabId, capture, result);
        if (result.changed) {
          this.host.invalidateTakeoverPresentation();
        }
      }).catch((_error: Error): void => {});
      if (forceLayoutRevalidation && capture !== undefined) {
        this.scheduleDirectLayoutRevalidation(
          normalizedTabId,
          directSession.sessionId,
          directBinding.runtimeId,
          capture
        );
      }
    }
  }

  private isDirectLayoutRevalidationPayload(payloadJson: string): boolean {
    try {
      const payload = JSON.parse(payloadJson) as BrowserMediaPageBehaviorPayload;
      const eventName = payload.videoEvent?.eventName?.trim().toLowerCase() ?? '';
      return eventName === 'resize' || eventName.indexOf('geometry_') === 0 ||
        eventName.indexOf('fullscreen') >= 0;
    } catch (_error) {
      return false;
    }
  }

  private scheduleDirectLayoutRevalidation(
    tabId: string,
    sessionId: string,
    runtimeId: string,
    capture: BrowserMediaEvidenceCapture
  ): void {
    const previous = this.directLayoutRevalidationByTabId.get(tabId);
    if (previous !== undefined && previous.timerId > 0) {
      clearTimeout(previous.timerId);
    }
    const generation = (previous?.generation ?? 0) + 1;
    const timerId = setTimeout((): void => {
      const current = this.directLayoutRevalidationByTabId.get(tabId);
      if (current === undefined || current.generation !== generation ||
        this.evidenceCaptureByTabId.get(tabId) !== capture) {
        return;
      }
      current.timerId = 0;
      void this.mediaTakeoverCoordinator.verifyDocumentDirectReachability(
        tabId,
        sessionId,
        runtimeId,
        true
      ).then((result) => {
        const latest = this.directLayoutRevalidationByTabId.get(tabId);
        if (latest === undefined || latest.generation !== generation ||
          this.evidenceCaptureByTabId.get(tabId) !== capture) {
          return;
        }
        this.directLayoutRevalidationByTabId.delete(tabId);
        this.commitWebLiveReachabilityResult(tabId, capture, result);
        if (result.changed) {
          this.host.invalidateTakeoverPresentation();
        }
      }).catch((_error: Error): void => {
        const latest = this.directLayoutRevalidationByTabId.get(tabId);
        if (latest !== undefined && latest.generation === generation) {
          this.directLayoutRevalidationByTabId.delete(tabId);
        }
      });
    }, DIRECT_LAYOUT_REVALIDATION_DELAY_MS);
    this.directLayoutRevalidationByTabId.set(tabId, {
      generation: generation,
      timerId: timerId
    });
  }

  private cancelDirectLayoutRevalidation(tabId: string): void {
    const state = this.directLayoutRevalidationByTabId.get(tabId);
    if (state !== undefined && state.timerId > 0) {
      clearTimeout(state.timerId);
    }
    this.directLayoutRevalidationByTabId.delete(tabId);
  }

  private handleFrameProbeSignal(tabId: string, event: MediaVideoFrameProbeAdaptResult): void {
    if (event.kind === 'bootstrap') {
      this.logFrameProbeBootstrap(tabId, event);
      return;
    }
    if (!this.mediaFrameRuntimeCoordinator.acceptsProbeChannel(tabId, event.channelId)) {
      this.logFrameProbeRejected(tabId, event, 'channel_mismatch');
      return;
    }
    const capture = this.evidenceCaptureByTabId.get(tabId);
    if (event.kind === 'ready' && capture !== undefined &&
      !this.mediaFrameRuntimeCoordinator.acceptReadyFrame(
        tabId,
        event.frameRuntimeId,
        event.frameControlKey
      )) {
      this.logFrameProbeRejected(tabId, event, 'ready_duplicate_or_budget');
      return;
    }
    if (event.kind !== 'ready' &&
      !this.mediaFrameRuntimeCoordinator.hasReadyFrame(tabId, event.frameRuntimeId)) {
      this.logFrameProbeRejected(tabId, event, 'frame_not_ready');
      return;
    }
    if (event.kind === 'frame_ended') {
      this.mediaFrameRuntimeCoordinator.endReadyFrame(tabId, event.frameRuntimeId);
      if (this.mediaTakeoverCoordinator.handleFrameRuntimeEnded(tabId, event.frameRuntimeId)) {
        this.host.invalidateTakeoverPresentation();
      }
    }
    this.logFrameProbe(tabId, event);
    if (capture === undefined) {
      return;
    }
    try {
      if (this.mediaDiscoveryCoordinator.observeFrameRuntimeEvidence(
        capture,
        event.observedAt,
        event.observations
      )) {
        this.refreshSessionResolution(tabId, Date.now());
        this.host.invalidateTakeoverPresentation();
        this.applyFramePlaybackSignal(tabId, event, capture);
      }
    } catch (_error) {
    }
  }

  private logFrameProbe(tabId: string, event: MediaVideoFrameProbeAdaptResult): void {
    if (this.host.resolvePrivateMode(tabId)) {
      return;
    }
    if (event.kind === 'ready') {
      hilog.info(
        MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
        MEDIA_FRAME_RUNTIME_LOG_TAG,
        'media_frame_probe_ready tab=%{public}s frameType=%{public}s frameRuntime=yes bridgeReady=yes locator=%{public}s',
        tabId,
        event.frameType,
        event.safeFrameLocator
      );
      return;
    }
    if (event.kind === 'frame_ended') {
      hilog.info(
        MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
        MEDIA_FRAME_RUNTIME_LOG_TAG,
        'media_frame_probe_ended tab=%{public}s frameType=%{public}s frameRuntime=yes locator=%{public}s',
        tabId,
        event.frameType,
        event.safeFrameLocator
      );
      return;
    }
    hilog.info(
      MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
      MEDIA_FRAME_RUNTIME_LOG_TAG,
      'media_frame_video_event tab=%{public}s frameType=%{public}s event=%{public}s frameRuntime=yes runtime=%{public}s sourceKind=%{public}s locator=%{public}s',
      tabId,
      event.frameType,
      event.eventName,
      event.hasVideoRuntime ? 'yes' : 'no',
      event.sourceKind,
      event.safeFrameLocator
    );
  }

  private logFrameProbeBootstrap(tabId: string, event: MediaVideoFrameProbeAdaptResult): void {
    if (this.host.resolvePrivateMode(tabId)) {
      return;
    }
    hilog.info(
      MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
      MEDIA_FRAME_RUNTIME_LOG_TAG,
      'media_frame_probe_bootstrap tab=%{public}s frameType=%{public}s reason=%{public}s',
      tabId,
      event.frameType,
      event.reason
    );
  }

  private logFrameProbeRejected(
    tabId: string,
    event: MediaVideoFrameProbeAdaptResult,
    reason: string
  ): void {
    if (this.host.resolvePrivateMode(tabId)) {
      return;
    }
    hilog.info(
      MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
      MEDIA_FRAME_RUNTIME_LOG_TAG,
      'media_frame_probe_rejected tab=%{public}s frameType=%{public}s kind=%{public}s reason=%{public}s',
      tabId,
      event.frameType,
      event.kind,
      reason
    );
  }

  private applyFramePlaybackSignal(
    tabId: string,
    event: MediaVideoFrameProbeAdaptResult,
    capture: BrowserMediaEvidenceCapture
  ): void {
    const video = event.video;
    if (event.frameType !== 'child_document' || video === undefined || event.targetKey.length <= 0) {
      return;
    }
    const rect: BrowserArkWebMediaRectSnapshot | undefined = video.rect === undefined ? undefined : {
      x: video.rect.x,
      y: video.rect.y,
      width: video.rect.width,
      height: video.rect.height
    };
    const input: BrowserArkWebMediaFramePlaybackInput = {
      tabId: tabId,
      frameType: event.frameType,
      frameRuntimeId: event.frameRuntimeId,
      targetKey: event.targetKey,
      eventName: video.eventName,
      runtimeId: video.runtimeId,
      elementId: video.elementId,
      source: video.source,
      muted: video.muted,
      paused: video.paused,
      ended: video.ended,
      seeking: video.seeking,
      readyState: video.readyState,
      networkState: video.networkState,
      visible: video.visible,
      rect: rect,
      viewportWidth: video.viewportWidth,
      viewportHeight: video.viewportHeight,
      videoWidth: video.videoWidth,
      videoHeight: video.videoHeight,
      currentTime: video.currentTime,
      duration: video.duration,
      observedAt: event.observedAt
    };
    void this.mediaTakeoverCoordinator.observeFramePlaybackSignal(input).then((result) => {
      this.commitWebLiveReachabilityResult(tabId, capture, result);
      if (result.changed) {
        this.host.invalidateTakeoverPresentation();
      }
    }).catch((_error: Error): void => {});
  }

  private commitWebLiveReachabilityResult(
    tabId: string,
    capture: BrowserMediaEvidenceCapture | undefined,
    result: BrowserArkWebMediaPlaybackSignalResult
  ): void {
    const evidence = result.reachabilityEvidence;
    const targetKey = evidence?.targetKey.trim() ?? '';
    if (capture === undefined || evidence === undefined || targetKey.length <= 0) {
      return;
    }
    this.commitRuntimeEvidence(tabId, capture, evidence);
  }

  private captureRuntimeEvidence(
    tabId: string
  ): BrowserArkWebMediaRuntimeEvidenceCapture | undefined {
    const normalizedTabId = tabId.trim();
    const capture = this.evidenceCaptureByTabId.get(normalizedTabId);
    if (normalizedTabId.length <= 0 || capture === undefined) {
      return undefined;
    }
    return {
      isCurrent: (): boolean => this.evidenceCaptureByTabId.get(normalizedTabId) === capture,
      commit: (evidence: BrowserArkWebMediaRuntimeEvidence): boolean =>
        this.commitRuntimeEvidence(normalizedTabId, capture, evidence)
    };
  }

  private activateProfileResolution(
    capture: BrowserMediaEvidenceCapture,
    pageUrl: string
  ): void {
    try {
      const currentCapture = this.evidenceCaptureByTabId.get(capture.tabId);
      if (currentCapture !== capture) {
        return;
      }
      this.videoCompatibilityProfileCatalog.activateRoute({
        scope: capture.scope,
        pageUrl: pageUrl
      }, currentCapture.scope);
    } catch (_error) {
    }
  }

  private commitRuntimeEvidence(
    tabId: string,
    capture: BrowserMediaEvidenceCapture,
    evidence: BrowserArkWebMediaRuntimeEvidence
  ): boolean {
    const targetKey = evidence.targetKey.trim();
    if (targetKey.length <= 0) {
      return false;
    }
    try {
      const changed = evidence.kind === 'web_live_reachability' ?
        this.mediaDiscoveryCoordinator.observeWebLiveReachabilityEvidence(
          capture,
          targetKey,
          evidence.state,
          evidence.observedAt,
          evidence.expiresAt
        ) :
        this.mediaDiscoveryCoordinator.observeWebLivePlaybackEvidence(
          capture,
          targetKey,
          evidence.event,
          evidence.observedAt,
          evidence.currentTimeSeconds,
          evidence.durationSeconds
        );
      if (changed) {
        this.refreshSessionResolution(tabId, evidence.observedAt);
      }
      return changed;
    } catch (_error) {
      return false;
    }
  }

  private refreshSessionResolution(
    tabId: string,
    now: number
  ): MediaSessionResolutionSnapshot | undefined {
    try {
      const evidence = this.mediaDiscoveryCoordinator.projectSessionEvidence(tabId, now);
      if (evidence !== undefined) {
        const snapshot = this.sessionResolutionRuntimeService.resolve({
          tabId: tabId,
          evidence: evidence,
          now: now
        });
        if (this.mediaTakeoverCoordinator.handleSessionResolutionChanged(tabId)) {
          this.host.invalidateTakeoverPresentation();
        }
        this.scheduleWebActionToolbar(tabId, snapshot);
        return snapshot;
      }
    } catch (_error) {
    }
    this.sessionResolutionRuntimeService.clearTab(tabId);
    if (this.mediaTakeoverCoordinator.handleSessionResolutionChanged(tabId)) {
      this.host.invalidateTakeoverPresentation();
    }
    return undefined;
  }

  private scheduleWebActionToolbar(
    tabId: string,
    snapshot: MediaSessionResolutionSnapshot | undefined
  ): void {
    const session = this.resolveActiveSession(snapshot);
    if (session === undefined || session.playbackState !== 'playing' ||
      !this.host.resolveWebActionToolbarEnabled(tabId)) {
      return;
    }
    void this.mediaTakeoverCoordinator.ensureWebActionToolbar(tabId, true).catch((_error: Error): void => {});
  }

  private resolveActiveSession(
    snapshot: MediaSessionResolutionSnapshot | undefined
  ): MediaResolvedVideoAssistantSession | undefined {
    const activeSessionId = snapshot?.activeSessionId ?? '';
    if (snapshot === undefined || snapshot.outcome !== 'active' || activeSessionId.length <= 0) {
      return undefined;
    }
    const sessions = snapshot.getSessions();
    for (let i: number = 0; i < sessions.length; i += 1) {
      if (sessions[i].sessionId === activeSessionId) {
        return sessions[i];
      }
    }
    return undefined;
  }
}

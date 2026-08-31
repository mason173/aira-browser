import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  createInactiveVideoAssistantState,
  VideoAssistantLoadingReason,
  VideoAssistantPlaybackStatus,
  VideoAssistantState
} from '../../../features/videoAssistant/VideoAssistantModels';
import {
  MediaResolvedPlaybackTargetTransport,
  MediaResolvedVideoAssistantSession,
  MediaSessionResolutionSnapshot
} from '../../../features/mediaDiscovery/MediaSessionResolutionModels';
import {
  WebVideoLiveCommand,
  WebVideoLiveCommandResult,
  WebVideoLivePresentationMode,
  WebVideoLiveSessionTarget,
  WebVideoPresentationService
} from '../../../services/video/WebVideoPresentationService';
import { BrowserRuntimeLifecyclePort } from '../../../services/web/BrowserRuntimeLifecyclePort';
import {
  MediaEvidenceScope,
  MediaFrameDocumentType
} from '../../../features/mediaDiscovery/MediaEvidenceGraphModels';
import {
  VideoAssistantCastMediaItem,
  VideoAssistantCastSessionService
} from '../../../services/video/VideoAssistantCastSessionService';
import {
  MediaCastRequestContextPolicy,
  MediaCastRequestContextReason
} from '../../../services/media/MediaCastRequestContextPolicy';
import {
  sharedVideoCompatibilityProfileCatalog,
  VideoCompatibilityProfileCatalog
} from '../../../services/media/VideoCompatibilityProfileCatalog';
import { WEB_VIDEO_ACTION_TOOLBAR_PROTOCOL } from '../../../services/video/WebVideoRuntimeProtocol';

const ARKWEB_MEDIA_LOG_DOMAIN: number = 0x0000;
const ARKWEB_MEDIA_LOG_TAG: string = 'ArkWebMediaAssistant';
const VIDEO_ASSISTANT_LIVE_ROUTE_ENABLED: boolean = true;
const WEB_LIVE_REACHABILITY_TTL_MS: number = 20000;
const WEB_LIVE_STABLE_CONFIRMATION_DELAY_MS: number = 200;
const WEB_LIVE_LAUNCH_LEASE_MS: number = 10000;
const FRAME_WEB_LIVE_REACHABILITY_RENEW_MARGIN_MS: number = 5000;
const ARKWEB_MEDIA_VISIBILITY_GRACE_MS: number = 1500;
const WEB_VIDEO_ACTION_TOOLBAR_REQUEST_MAX_LENGTH: number = 2048;

export type BrowserArkWebMediaLaunchRoute = 'web_live';
export type BrowserArkWebMediaWebLiveCommand = WebVideoLiveCommand;

export interface BrowserArkWebMediaAssistantPlayerAction {
  type: 'cast' | 'close' | 'download' | 'rotate' | 'web_live_command';
  landscape?: boolean;
  command?: BrowserArkWebMediaWebLiveCommand;
}

export interface BrowserArkWebMediaRectSnapshot {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface BrowserArkWebMediaTakeoverVideoEventPayload {
  eventName?: string;
  runtimeId?: string;
  paused?: boolean;
  ended?: boolean;
  seeking?: boolean;
  readyState?: number;
  networkState?: number;
}

interface BrowserArkWebMediaTakeoverPageBehaviorPayload {
  isVideoPlaying?: boolean;
  videoEvent?: BrowserArkWebMediaTakeoverVideoEventPayload;
}

interface BrowserArkWebMediaActionToolbarRequest {
  protocol?: string;
  action?: string;
  runtimeId?: string;
  frameRuntimeId?: string;
}

export interface BrowserArkWebMediaObservationInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  suppressDiagnostics: boolean;
  mediaInfo: webview.MediaInfo;
}

export interface BrowserArkWebMediaObservationResult {
  accepted: boolean;
  changed: boolean;
  reason: string;
}

export interface BrowserArkWebMediaFramePlaybackInput {
  tabId: string;
  frameType: MediaFrameDocumentType;
  frameRuntimeId: string;
  targetKey: string;
  eventName: string;
  runtimeId: string;
  elementId: string;
  source: string;
  muted?: boolean;
  paused?: boolean;
  ended?: boolean;
  seeking?: boolean;
  readyState: number;
  networkState: number;
  visible?: boolean;
  rect?: BrowserArkWebMediaRectSnapshot;
  viewportWidth: number;
  viewportHeight: number;
  videoWidth: number;
  videoHeight: number;
  currentTime: number;
  duration: number;
  observedAt: number;
}

export interface BrowserArkWebMediaPlaybackSignalResult {
  accepted: boolean;
  changed: boolean;
  reason: string;
  reachabilityEvidence?: BrowserArkWebMediaReachabilityEvidence;
}

export interface BrowserArkWebMediaReachabilityEvidence {
  kind: 'web_live_reachability';
  targetKey: string;
  state: 'reachable' | 'unreachable';
  observedAt: number;
  expiresAt: number;
}

export interface BrowserArkWebMediaPlaybackEvidence {
  kind: 'playback';
  targetKey: string;
  event: 'snapshot' | 'playing' | 'paused' | 'ended';
  observedAt: number;
  currentTimeSeconds: number;
  durationSeconds: number;
}

export type BrowserArkWebMediaRuntimeEvidence =
  | BrowserArkWebMediaReachabilityEvidence
  | BrowserArkWebMediaPlaybackEvidence;

export interface BrowserArkWebMediaRuntimeEvidenceCapture {
  isCurrent: () => boolean;
  commit: (evidence: BrowserArkWebMediaRuntimeEvidence) => boolean;
}

export interface BrowserArkWebMediaRuntimeEvidencePublisher {
  capture: (tabId: string) => BrowserArkWebMediaRuntimeEvidenceCapture | undefined;
  resolveSnapshot: (tabId: string) => MediaSessionResolutionSnapshot | undefined;
  resolveCastMedia: (
    tabId: string,
    playbackTargetId: string
  ) => BrowserArkWebMediaCastMediaResolution;
}

export type BrowserArkWebMediaCastMediaReason =
  'ready' |
  'missing_target' |
  'missing_locator' |
  'missing_resource' |
  'ambiguous_resource' |
  'web_context_required' |
  'unsupported_resource';

export interface BrowserArkWebMediaCastMediaResolution {
  reason: BrowserArkWebMediaCastMediaReason;
  mediaUri?: string;
  mediaFormat: string;
  requestHeaderCount: number;
}

// Retained for the architecture-guarded legacy host component. The browser
// shell no longer mounts that ArkUI button; webpage actions use the DOM toolbar.
export interface BrowserArkWebMediaButtonState {
  visible: boolean;
  sourceCount: number;
  controllable: boolean;
  webLiveAvailable: boolean;
  busy: boolean;
  x: number;
  y: number;
}

export interface BrowserArkWebMediaLaunchPlan {
  accepted: boolean;
  route?: BrowserArkWebMediaLaunchRoute;
  sessionId?: string;
  reason: string;
  message: string;
  liveTarget?: WebVideoLiveSessionTarget;
  reachabilityTargetKey?: string;
  launchLease?: BrowserArkWebMediaLaunchLease;
}

export interface BrowserArkWebMediaLaunchLease {
  readonly leaseId: string;
  readonly tabId: string;
  readonly generationId: string;
  readonly routeEpochId: string;
  readonly sessionId: string;
  readonly targetKey: string;
  readonly transport: MediaResolvedPlaybackTargetTransport;
  readonly runtimeId: string;
  readonly frameRuntimeId: string;
  readonly elementId: string;
  readonly issuedAt: number;
  readonly expiresAt: number;
}

export interface BrowserArkWebMediaLaunchInput {
  activeTabId: string;
  webLiveRouteEnabled: boolean;
  controller?: webview.WebviewController;
  preferWebFullscreen?: boolean;
}

export interface BrowserArkWebMediaLaunchResult {
  plan: BrowserArkWebMediaLaunchPlan;
  started: boolean;
  webResult?: WebVideoLiveCommandResult;
}

export interface BrowserArkWebMediaLaunchHost {
  showToast: (message: string) => void;
  invalidatePresentation: () => void;
  prepareWebVideoFullscreen: (tabId: string) => Promise<void>;
  cancelWebVideoFullscreenPreparation: (tabId: string) => void;
  enterWebVideoFullscreen: (tabId: string, videoWidth: number, videoHeight: number) => Promise<boolean>;
  enterWebLiveFullscreen: (tabId: string, videoWidth: number, videoHeight: number) => Promise<boolean>;
  exitWebLiveFullscreen: (tabId: string) => void;
  onStarted: (route: BrowserArkWebMediaLaunchRoute) => void;
}

export type BrowserArkWebMediaAssistantOrientation = 'landscape' | 'portrait';

export interface BrowserArkWebMediaAssistantPlayerHost {
  applyOrientation: (orientation: BrowserArkWebMediaAssistantOrientation, reason: string) => Promise<void>;
  exitWebLiveFullscreen: (tabId: string) => Promise<void>;
  invalidatePresentation: () => void;
  requestDownload: (tabId: string, playbackTargetId: string) => Promise<void>;
  showToast: (message: string) => void;
}

interface BrowserArkWebMediaDownloadInteraction {
  readonly interactionId: string;
  readonly tabId: string;
  readonly generationId: string;
  readonly routeEpochId: string;
  readonly sessionId: string;
  readonly playbackTargetId: string;
  readonly targetKey: string;
  readonly session: MediaResolvedVideoAssistantSession;
  readonly evidenceCapture: BrowserArkWebMediaRuntimeEvidenceCapture;
}

interface BrowserArkWebMediaPageMetadata {
  pageUrl: string;
  pageTitle: string;
  posterUrl: string;
  primarySource: string;
  primarySourceFormat: string;
  requestHeaderCount: number;
  requiresWebRequestContext: boolean;
  requestContextReason: MediaCastRequestContextReason;
  sourceCount: number;
}

interface BrowserArkWebMediaActivePlaybackSignalInput {
  tabId: string;
  transport: MediaResolvedPlaybackTargetTransport;
  frameRuntimeId: string;
  runtimeId: string;
  eventName: string;
  paused?: boolean;
  ended?: boolean;
  seeking?: boolean;
  readyState: number;
  networkState: number;
}

/**
 * Consumes the immutable Session Resolution authority and owns only Takeover Route,
 * Entry Eligibility, Web presentation, and player interaction.
 */
export class BrowserArkWebMediaTakeoverCoordinator {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly webVideoPresentationService: WebVideoPresentationService;
  private readonly castSessionService: VideoAssistantCastSessionService;
  private readonly videoCompatibilityProfileCatalog: VideoCompatibilityProfileCatalog;
  private readonly castRequestContextPolicy: MediaCastRequestContextPolicy = new MediaCastRequestContextPolicy();
  private runtimeEvidencePublisher?: BrowserArkWebMediaRuntimeEvidencePublisher = undefined;
  private metadataByTabId: Map<string, BrowserArkWebMediaPageMetadata> = new Map();
  private lastVisibleAtBySessionId: Map<string, number> = new Map();
  private frameReachabilityInFlightByTab: Map<string, string> = new Map();
  private directReachabilityInFlightByTab: Map<string, string> = new Map();
  private launchInFlightByTab: Map<string, boolean> = new Map();
  private launchLeaseByTab: Map<string, BrowserArkWebMediaLaunchLease> = new Map();
  private actionToolbarTargetByTab: Map<string, string> = new Map();
  private actionToolbarInstallInFlightByTab: Map<string, string> = new Map();
  private nextLaunchLeaseSequence: number = 1;
  private activeWebLiveTabId: string = '';
  private activeWebLiveSessionId: string = '';
  private activeWebLiveGenerationId: string = '';
  private activeWebLiveRouteEpochId: string = '';
  private activeWebLiveTarget?: WebVideoLiveSessionTarget = undefined;
  private activeWebLiveExitFullscreen?: (tabId: string) => void = undefined;
  private activeWebLiveStartedAt: number = 0;
  private activeWebLiveLoadingReason: VideoAssistantLoadingReason = '';
  private activeWebLiveErrorMessage: string = '';
  private activeDownloadInteraction?: BrowserArkWebMediaDownloadInteraction = undefined;
  private nextDownloadInteractionSequence: number = 1;
  private webLiveExitInFlight: boolean = false;
  private webLiveOrientationInFlight: boolean = false;
  private webLiveOrientationRequestId: number = 0;

  constructor(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    webVideoPresentationService: WebVideoPresentationService = new WebVideoPresentationService(),
    castSessionService: VideoAssistantCastSessionService = new VideoAssistantCastSessionService(),
    videoCompatibilityProfileCatalog: VideoCompatibilityProfileCatalog = sharedVideoCompatibilityProfileCatalog
  ) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.webVideoPresentationService = webVideoPresentationService;
    this.castSessionService = castSessionService;
    this.videoCompatibilityProfileCatalog = videoCompatibilityProfileCatalog;
  }

  bindRuntimeEvidencePublisher(publisher: BrowserArkWebMediaRuntimeEvidencePublisher): void {
    this.runtimeEvidencePublisher = publisher;
  }

  beginNavigation(tabId: string): boolean {
    return this.clearTabRuntime(tabId, false);
  }

  clearTab(tabId: string): boolean {
    return this.clearTabRuntime(tabId, true);
  }

  private clearTabRuntime(tabId: string, removeMetadata: boolean): boolean {
    const normalizedTabId = tabId.trim();
    const webLiveWasActive = normalizedTabId === this.activeWebLiveTabId;
    if (webLiveWasActive) {
      this.restoreActiveWebLivePresentation();
    }
    if (removeMetadata) {
      this.metadataByTabId.delete(normalizedTabId);
    }
    this.frameReachabilityInFlightByTab.delete(normalizedTabId);
    this.directReachabilityInFlightByTab.delete(normalizedTabId);
    this.launchInFlightByTab.delete(normalizedTabId);
    this.launchLeaseByTab.delete(normalizedTabId);
    this.actionToolbarTargetByTab.delete(normalizedTabId);
    this.actionToolbarInstallInFlightByTab.delete(normalizedTabId);
    this.clearVisibilityForTab(normalizedTabId);
    this.clearWebLiveAssistantForTab(normalizedTabId);
    return webLiveWasActive;
  }

  getAssistantPlayerState(_renderRevision: number = 0): VideoAssistantState {
    return this.buildWebLiveAssistantPlayerState();
  }

  isWebLiveAssistantActive(_renderRevision: number = 0): boolean {
    return this.hasWebLiveAssistantRegistration() && this.resolveActiveWebLiveSession() !== undefined;
  }

  handleSessionResolutionChanged(tabId: string): boolean {
    if (!this.hasWebLiveAssistantRegistration() || this.activeWebLiveTabId !== tabId.trim() ||
      this.resolveActiveWebLiveSession() !== undefined) {
      return false;
    }
    this.restoreActiveWebLivePresentation();
    try {
      this.activeWebLiveExitFullscreen?.(this.activeWebLiveTabId);
    } catch (_error) {
    }
    this.clearWebLiveAssistant();
    return true;
  }

  handleWebFullscreenExited(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (!this.isWebLiveAssistantActive() || this.activeWebLiveTabId !== normalizedTabId) {
      return;
    }
    const target = this.activeWebLiveTarget;
    if (target !== undefined) {
      void this.restoreWebLivePresentation(normalizedTabId, target);
    }
    this.clearWebLiveAssistant();
  }

  isWebLiveAssistantTransitionPending(_renderRevision: number = 0): boolean {
    return this.webLiveExitInFlight || this.webLiveOrientationInFlight;
  }

  handleAssistantPlayerAction(
    action: BrowserArkWebMediaAssistantPlayerAction,
    host: BrowserArkWebMediaAssistantPlayerHost
  ): void {
    if (action.type === 'close') {
      void this.closeAssistantPlayer(host);
      return;
    }
    if (action.type === 'rotate') {
      if (action.landscape !== undefined) {
        void this.requestAssistantOrientation(action.landscape ? 'landscape' : 'portrait', host);
      }
      return;
    }
    if (action.type === 'cast') {
      void this.requestAssistantCast(host);
      return;
    }
    if (action.type === 'download') {
      const session = this.resolveActiveWebLiveSession();
      if (session === undefined) {
        host.showToast('当前网页视频会话已经失效。');
        return;
      }
      if (this.activeDownloadInteraction !== undefined) {
        host.showToast('正在处理当前视频下载。');
        return;
      }
      void this.requestAssistantDownload(session, host);
      return;
    }
    if (action.command !== undefined) {
      void this.executeWebLiveCommand(action.command, host);
    }
  }

  async handleAssistantBack(
    _landscape: boolean,
    host: BrowserArkWebMediaAssistantPlayerHost
  ): Promise<void> {
    if (!this.isWebLiveAssistantTransitionPending()) {
      await this.closeAssistantPlayer(host);
    }
  }

  observe(input: BrowserArkWebMediaObservationInput): BrowserArkWebMediaObservationResult {
    const tabId = input.tabId.trim();
    if (tabId.length <= 0) {
      return this.buildRejectedObservation('missing_tab');
    }
    if (input.mediaInfo.mediaType !== webview.MediaType.VIDEO) {
      return this.buildRejectedObservation('not_video');
    }
    const metadata = this.buildPageMetadata(input);
    const previous = this.metadataByTabId.get(tabId);
    const changed = previous === undefined || !this.sameMetadata(previous, metadata);
    this.metadataByTabId.set(tabId, metadata);
    if (!input.suppressDiagnostics) {
      hilog.info(
        ARKWEB_MEDIA_LOG_DOMAIN,
        ARKWEB_MEDIA_LOG_TAG,
        'observed tab=%{public}s sources=%{public}d muted=%{public}s',
        tabId,
        metadata.sourceCount,
        input.mediaInfo.muted ? 'yes' : 'no'
      );
    }
    return {
      accepted: true,
      changed: changed,
      reason: changed ? 'video_metadata_updated' : 'video_metadata_unchanged'
    };
  }

  observePageBehaviorSignal(tabId: string, payloadJson: string): BrowserArkWebMediaPlaybackSignalResult {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return this.buildRejectedPlaybackSignal('missing_tab');
    }
    try {
      const payload = JSON.parse(payloadJson) as BrowserArkWebMediaTakeoverPageBehaviorPayload;
      if (typeof payload.isVideoPlaying !== 'boolean') {
        return this.buildRejectedPlaybackSignal('invalid_payload');
      }
      const videoEvent = payload.videoEvent;
      const changed = videoEvent === undefined ? false : this.applyActiveWebLivePlaybackSignal({
        tabId: normalizedTabId,
        transport: 'document_direct',
        frameRuntimeId: '',
        runtimeId: videoEvent.runtimeId?.trim() ?? '',
        eventName: videoEvent.eventName?.trim() ?? '',
        paused: videoEvent.paused,
        ended: videoEvent.ended,
        seeking: videoEvent.seeking,
        readyState: this.boundedInteger(videoEvent.readyState, 0, 4),
        networkState: this.boundedInteger(videoEvent.networkState, 0, 3)
      });
      return {
        accepted: true,
        changed: changed,
        reason: changed ? 'takeover_readiness_updated' : 'evidence_owned_playback_signal'
      };
    } catch (_error) {
      return this.buildRejectedPlaybackSignal('invalid_payload');
    }
  }

  async verifyDocumentDirectReachability(
    tabId: string,
    sessionId: string,
    runtimeId: string,
    forceRevalidation: boolean = false
  ): Promise<BrowserArkWebMediaPlaybackSignalResult> {
    const normalizedTabId = tabId.trim();
    const normalizedSessionId = sessionId.trim();
    const normalizedRuntimeId = runtimeId.trim();
    const session = this.resolveActiveSession(normalizedTabId);
    if (session === undefined || session.sessionId !== normalizedSessionId ||
      session.playbackTargetBinding?.transport !== 'document_direct' ||
      session.playbackTargetBinding.runtimeId !== normalizedRuntimeId) {
      return this.buildRejectedPlaybackSignal('direct_target_stale');
    }
    const now = Date.now();
    if (!forceRevalidation && session.webLiveReachability === 'reachable' &&
      session.webLiveReachabilityExpiresAt > now) {
      return {
        accepted: true,
        changed: false,
        reason: 'direct_target_reachability_current'
      };
    }
    if (this.directReachabilityInFlightByTab.has(normalizedTabId)) {
      return this.buildRejectedPlaybackSignal('direct_reachability_in_flight');
    }
    const reachabilityKey = session.sessionId + ':' + normalizedRuntimeId;
    this.directReachabilityInFlightByTab.set(normalizedTabId, reachabilityKey);
    const target = this.buildWebLiveTarget(normalizedTabId, session);
    if (target === undefined) {
      this.directReachabilityInFlightByTab.delete(normalizedTabId);
      return this.buildRejectedPlaybackSignal('direct_target_missing');
    }
    try {
      const controller = this.runtimeLifecyclePort.resolveController(normalizedTabId);
      const requiresStableConfirmation = session.webLiveReachability !== 'reachable' ||
        session.webLiveReachabilityExpiresAt <= now;
      const result = requiresStableConfirmation ?
        await this.probeLiveTargetWithStableConfirmation(normalizedTabId, session, target, controller) :
        await this.webVideoPresentationService.probeLiveTarget(controller, target);
      const current = this.resolveActiveSession(normalizedTabId);
      const stillCurrent = current !== undefined && current.sessionId === session.sessionId &&
        current.targetKey === session.targetKey && current.playbackState === 'playing' &&
        this.sessionMatchesLiveTarget(current, target);
      if (!result.ok || !stillCurrent) {
        return {
          accepted: false,
          changed: stillCurrent,
          reason: result.ok ? 'direct_target_stale' : result.reason,
          reachabilityEvidence: stillCurrent ?
            this.buildReachabilityEvidence(session.targetKey, 'unreachable') : undefined
        };
      }
      const expiresAt = Date.now() + WEB_LIVE_REACHABILITY_TTL_MS;
      return {
        accepted: true,
        changed: true,
        reason: 'direct_target_reachable',
        reachabilityEvidence: this.buildReachabilityEvidence(session.targetKey, 'reachable', expiresAt)
      };
    } finally {
      if (this.directReachabilityInFlightByTab.get(normalizedTabId) === reachabilityKey) {
        this.directReachabilityInFlightByTab.delete(normalizedTabId);
      }
    }
  }

  async observeFramePlaybackSignal(
    input: BrowserArkWebMediaFramePlaybackInput
  ): Promise<BrowserArkWebMediaPlaybackSignalResult> {
    const tabId = input.tabId.trim();
    const targetKey = input.targetKey.trim();
    if (input.frameType !== 'child_document') {
      return this.buildRejectedPlaybackSignal('frame_proxy_requires_child_document');
    }
    if (tabId.length <= 0 || targetKey.length <= 0 || input.frameRuntimeId.trim().length <= 0 ||
      input.runtimeId.trim().length <= 0) {
      return this.buildRejectedPlaybackSignal('frame_target_missing');
    }
    const readinessChanged = this.applyActiveWebLivePlaybackSignal({
      tabId: tabId,
      transport: 'frame_proxy',
      frameRuntimeId: input.frameRuntimeId.trim(),
      runtimeId: input.runtimeId.trim(),
      eventName: input.eventName,
      paused: input.paused,
      ended: input.ended,
      seeking: input.seeking,
      readyState: input.readyState,
      networkState: input.networkState
    });
    const targetEnded = input.ended === true || input.eventName === 'ended' ||
      input.eventName === 'emptied' || input.eventName === 'abort';
    const session = targetEnded ? this.resolveSessionByTargetKey(tabId, targetKey) :
      this.resolveActiveSession(tabId);
    if (session === undefined || session.targetKey !== targetKey ||
      session.playbackTargetBinding?.transport !== 'frame_proxy' ||
      session.playbackTargetBinding.frameRuntimeId !== input.frameRuntimeId.trim() ||
      session.playbackTargetBinding.runtimeId !== input.runtimeId.trim()) {
      if (readinessChanged) {
        return {
          accepted: true,
          changed: true,
          reason: 'frame_takeover_readiness_updated'
        };
      }
      return this.buildRejectedPlaybackSignal('frame_session_not_active');
    }
    if (session.playbackState !== 'playing') {
      if (targetEnded || session.playbackState === 'ended') {
        this.invalidateActiveFrameWebLiveTarget(tabId, input.frameRuntimeId, input.runtimeId);
        return {
        accepted: true,
        changed: true,
        reason: 'frame_target_ended',
        reachabilityEvidence: this.buildReachabilityEvidence(targetKey, 'unreachable')
        };
      }
      if (readinessChanged) {
        return {
          accepted: true,
          changed: true,
          reason: 'frame_takeover_readiness_updated'
        };
      }
      return this.buildRejectedPlaybackSignal('frame_target_not_playing');
    }
    const now = Date.now();
    const forceRevalidation = this.isLayoutRevalidationEvent(input.eventName);
    if (!forceRevalidation && session.webLiveReachability === 'reachable' &&
      session.webLiveReachabilityExpiresAt > now + FRAME_WEB_LIVE_REACHABILITY_RENEW_MARGIN_MS) {
      return {
        accepted: true,
        changed: readinessChanged,
        reason: readinessChanged ? 'frame_takeover_readiness_updated' : 'frame_target_reachability_current'
      };
    }
    if (this.frameReachabilityInFlightByTab.has(tabId)) {
      if (readinessChanged) {
        return {
          accepted: true,
          changed: true,
          reason: 'frame_takeover_readiness_updated'
        };
      }
      return this.buildRejectedPlaybackSignal('frame_reachability_in_flight');
    }
    this.frameReachabilityInFlightByTab.set(tabId, targetKey);
    const target: WebVideoLiveSessionTarget = {
      runtimeId: input.runtimeId.trim(),
      elementId: input.elementId.trim(),
      source: '',
      tabId: tabId,
      frameRuntimeId: input.frameRuntimeId.trim(),
      transport: 'frame_proxy'
    };
    try {
      const controller = this.runtimeLifecyclePort.resolveController(tabId);
      const requiresStableConfirmation = session.webLiveReachability !== 'reachable' ||
        session.webLiveReachabilityExpiresAt <= now;
      const result = requiresStableConfirmation ?
        await this.probeLiveTargetWithStableConfirmation(tabId, session, target, controller) :
        await this.webVideoPresentationService.probeLiveTarget(controller, target);
      const current = this.resolveActiveSession(tabId);
      const stillCurrent = current !== undefined && current.sessionId === session.sessionId &&
        current.targetKey === targetKey && current.playbackState === 'playing' &&
        this.sessionMatchesLiveTarget(current, target);
      if (!result.ok || !stillCurrent) {
        return {
          accepted: false,
          changed: stillCurrent || readinessChanged,
          reason: result.ok ? 'frame_target_stale' : result.reason,
          reachabilityEvidence: stillCurrent ?
            this.buildReachabilityEvidence(targetKey, 'unreachable') : undefined
        };
      }
      const expiresAt = Date.now() + WEB_LIVE_REACHABILITY_TTL_MS;
      return {
        accepted: true,
        changed: true,
        reason: 'frame_target_reachable',
        reachabilityEvidence: this.buildReachabilityEvidence(targetKey, 'reachable', expiresAt)
      };
    } finally {
      if (this.frameReachabilityInFlightByTab.get(tabId) === targetKey) {
        this.frameReachabilityInFlightByTab.delete(tabId);
      }
    }
  }

  handleFrameRuntimeEnded(tabId: string, frameRuntimeId: string): boolean {
    return this.invalidateActiveFrameWebLiveTarget(tabId, frameRuntimeId);
  }

  async ensureWebActionToolbar(tabId: string, webLiveRouteEnabled: boolean): Promise<boolean> {
    const normalizedTabId = tabId.trim();
    const session = this.resolveActiveSession(normalizedTabId);
    if (session === undefined || session.playbackState !== 'playing' || this.isWebLiveAssistantActive() ||
      !this.isSessionEffectivelyVisible(session, Date.now()) ||
      !this.isWebLiveRouteEligible(normalizedTabId, session, webLiveRouteEnabled)) {
      return false;
    }
    const target = this.buildWebLiveTarget(normalizedTabId, session);
    if (target === undefined) {
      return false;
    }
    const targetKey = session.targetKey;
    if (this.actionToolbarTargetByTab.get(normalizedTabId) === targetKey) {
      return true;
    }
    if (this.actionToolbarInstallInFlightByTab.has(normalizedTabId)) {
      return false;
    }
    this.actionToolbarInstallInFlightByTab.set(normalizedTabId, targetKey);
    try {
      const result = await this.webVideoPresentationService.installActionToolbar(
        this.runtimeLifecyclePort.resolveController(normalizedTabId),
        target
      );
      const current = this.resolveActiveSession(normalizedTabId);
      const stillCurrent = current !== undefined && current.targetKey === targetKey &&
        current.playbackState === 'playing' && this.sessionMatchesLiveTarget(current, target);
      if (!result.ok || !stillCurrent) {
        return false;
      }
      this.actionToolbarTargetByTab.set(normalizedTabId, targetKey);
      return true;
    } finally {
      if (this.actionToolbarInstallInFlightByTab.get(normalizedTabId) === targetKey) {
        this.actionToolbarInstallInFlightByTab.delete(normalizedTabId);
      }
    }
  }

  async launchFromWebActionToolbar(
    tabId: string,
    payloadJson: string,
    webLiveRouteEnabled: boolean,
    host: BrowserArkWebMediaLaunchHost
  ): Promise<boolean> {
    const normalizedTabId = tabId.trim();
    const request = this.parseWebActionToolbarRequest(payloadJson);
    const session = this.resolveActiveSession(normalizedTabId);
    const binding = session?.playbackTargetBinding;
    if (request === undefined || session === undefined || binding === undefined ||
      request.runtimeId !== binding.runtimeId || request.frameRuntimeId !== binding.frameRuntimeId ||
      session.playbackState !== 'playing' || !this.runtimeLifecyclePort.isActiveWebTab(normalizedTabId)) {
      return false;
    }
    await host.prepareWebVideoFullscreen(normalizedTabId);
    let launchResult: BrowserArkWebMediaLaunchResult;
    try {
      launchResult = await this.launch({
        activeTabId: normalizedTabId,
        webLiveRouteEnabled: webLiveRouteEnabled,
        preferWebFullscreen: true
      }, host);
    } finally {
      host.cancelWebVideoFullscreenPreparation(normalizedTabId);
    }
    return launchResult.started;
  }

  beginLaunch(tabId: string, webLiveRouteEnabled: boolean): BrowserArkWebMediaLaunchPlan {
    const normalizedTabId = tabId.trim();
    if (this.launchInFlightByTab.get(normalizedTabId) === true) {
      return this.buildRejectedLaunch('launch_in_flight', '正在准备接管，请稍候。');
    }
    const session = this.resolveActiveSession(normalizedTabId);
    if (session === undefined || session.playbackState !== 'playing') {
      return this.buildRejectedLaunch('session_missing', 'ArkWeb 当前没有识别到正在播放的视频。');
    }
    const liveTarget = this.buildWebLiveTarget(normalizedTabId, session);
    if (liveTarget === undefined || !this.isWebLiveRouteEligible(normalizedTabId, session, webLiveRouteEnabled)) {
      return this.buildRejectedLaunch(
        'web_live_unavailable',
        '已识别到网页视频，但当前页面没有提供可控制的真实视频会话。'
      );
    }
    const launchLease = this.createLaunchLease(normalizedTabId, session, liveTarget);
    if (launchLease === undefined) {
      return this.buildRejectedLaunch('launch_authority_unavailable', '网页视频会话已经变化，请重新播放后再试。');
    }
    this.launchInFlightByTab.set(normalizedTabId, true);
    this.launchLeaseByTab.set(normalizedTabId, launchLease);
    return {
      accepted: true,
      route: 'web_live',
      sessionId: session.sessionId,
      reason: 'web_live_ready',
      message: '',
      liveTarget: liveTarget,
      reachabilityTargetKey: session.targetKey,
      launchLease: launchLease
    };
  }

  finishLaunch(tabId: string, leaseId: string = ''): void {
    const normalizedTabId = tabId.trim();
    const currentLease = this.launchLeaseByTab.get(normalizedTabId);
    if (leaseId.length > 0 && currentLease !== undefined && currentLease.leaseId !== leaseId) {
      return;
    }
    this.launchLeaseByTab.delete(normalizedTabId);
    this.launchInFlightByTab.delete(normalizedTabId);
  }

  async launch(
    input: BrowserArkWebMediaLaunchInput,
    host: BrowserArkWebMediaLaunchHost
  ): Promise<BrowserArkWebMediaLaunchResult> {
    const plan = this.beginLaunch(input.activeTabId, input.webLiveRouteEnabled);
    host.invalidatePresentation();
    if (!plan.accepted || plan.liveTarget === undefined || plan.sessionId === undefined ||
      plan.launchLease === undefined) {
      if (plan.message.length > 0) {
        host.showToast(plan.message);
      }
      return { plan: plan, started: false };
    }
    const liveTarget = plan.liveTarget;
    const evidenceCapture = this.runtimeEvidencePublisher?.capture(input.activeTabId);
    try {
      if (evidenceCapture === undefined || !evidenceCapture.isCurrent() ||
        !this.isLaunchPlanCurrent(input.activeTabId, plan)) {
        return { plan: plan, started: false };
      }
      const probeController = input.controller ?? this.runtimeLifecyclePort.resolveController(input.activeTabId);
      const freshReachability = input.preferWebFullscreen === true ?
        await this.probeWebFullscreenWithConfirmation(probeController, plan.liveTarget) :
        await this.webVideoPresentationService.probeLiveTarget(probeController, plan.liveTarget);
      const freshSessionCurrent = evidenceCapture.isCurrent() &&
        this.isLaunchPlanCurrent(input.activeTabId, plan);
      if (!freshReachability.ok || !freshSessionCurrent) {
        if (freshSessionCurrent) {
          this.publishLaunchReachability(plan, evidenceCapture, 'unreachable');
        }
        host.invalidatePresentation();
        host.showToast(freshReachability.userVisibleMessage.length > 0 ?
          freshReachability.userVisibleMessage : '网页视频会话已经变化，请重新播放后再试。');
        return { plan: plan, started: false, webResult: freshReachability };
      }
      if (!this.publishLaunchReachability(plan, evidenceCapture, 'reachable')) {
        return { plan: plan, started: false, webResult: freshReachability };
      }
      if (!this.isLaunchPlanCurrent(input.activeTabId, plan)) {
        return { plan: plan, started: false, webResult: freshReachability };
      }
      if (input.preferWebFullscreen === true && freshReachability.fullscreenActive) {
        const webFullscreenSession = this.resolveActiveSession(input.activeTabId);
        if (webFullscreenSession !== undefined && webFullscreenSession.sessionId === plan.sessionId &&
          this.sessionMatchesLiveTarget(webFullscreenSession, plan.liveTarget) &&
          webFullscreenSession.playbackState !== 'ended' &&
          this.runtimeLifecyclePort.isActiveWebTab(input.activeTabId)) {
          let webFullscreenStarted = false;
          try {
            webFullscreenStarted = await host.enterWebVideoFullscreen(
              input.activeTabId,
              this.resolveVideoWidth(webFullscreenSession),
              this.resolveVideoHeight(webFullscreenSession)
            );
          } catch (_error) {
            webFullscreenStarted = false;
          }
          if (webFullscreenStarted) {
            const confirmedWebSession = this.resolveActiveSession(input.activeTabId);
            const webSessionStillValid = evidenceCapture.isCurrent() && confirmedWebSession !== undefined &&
              confirmedWebSession.sessionId === webFullscreenSession.sessionId &&
              this.sessionMatchesLiveTarget(confirmedWebSession, plan.liveTarget) &&
              confirmedWebSession.playbackState !== 'ended' &&
              this.runtimeLifecyclePort.isActiveWebTab(input.activeTabId);
            if (webSessionStillValid) {
              this.activateWebLiveAssistant(
                input.activeTabId,
                plan.sessionId,
                plan.liveTarget,
                host.exitWebLiveFullscreen,
                freshReachability
              );
              host.onStarted('web_live');
              return { plan: plan, started: true, webResult: freshReachability };
            }
            host.exitWebLiveFullscreen(input.activeTabId);
          }
        }
      }
      if (input.preferWebFullscreen === true) {
        host.cancelWebVideoFullscreenPreparation(input.activeTabId);
      }
      const presentationResult = await this.webVideoPresentationService.executeLiveCommand(
        probeController,
        plan.liveTarget,
        { action: 'enter_live_presentation' }
      );
      if (!presentationResult.ok) {
        if (evidenceCapture.isCurrent() && this.isLaunchPlanCurrent(input.activeTabId, plan)) {
          this.publishLaunchReachability(plan, evidenceCapture, 'unreachable');
        }
        await this.restoreWebLivePresentation(input.activeTabId, plan.liveTarget);
        if (presentationResult.userVisibleMessage.length > 0) {
          host.showToast(presentationResult.userVisibleMessage);
        }
        return { plan: plan, started: false, webResult: presentationResult };
      }
      const session = this.resolveActiveSession(input.activeTabId);
      if (!evidenceCapture.isCurrent() || session === undefined || session.sessionId !== plan.sessionId ||
        !this.sessionMatchesLiveTarget(session, plan.liveTarget) || session.playbackState === 'ended' ||
        !this.runtimeLifecyclePort.isActiveWebTab(input.activeTabId)) {
        await this.restoreWebLivePresentation(input.activeTabId, plan.liveTarget);
        host.showToast('网页视频所在标签页已经变化，已取消接管。');
        return { plan: plan, started: false, webResult: presentationResult };
      }
      let fullscreenStarted = false;
      try {
        fullscreenStarted = await host.enterWebLiveFullscreen(
          input.activeTabId,
          this.resolveVideoWidth(session),
          this.resolveVideoHeight(session)
        );
      } catch (_error) {
        fullscreenStarted = false;
      }
      const confirmed = this.resolveActiveSession(input.activeTabId);
      const sessionStillValid = evidenceCapture.isCurrent() && confirmed !== undefined &&
        confirmed.sessionId === session.sessionId &&
        this.sessionMatchesLiveTarget(confirmed, plan.liveTarget) && confirmed.playbackState !== 'ended' &&
        this.runtimeLifecyclePort.isActiveWebTab(input.activeTabId);
      if (!fullscreenStarted || !sessionStillValid) {
        await this.restoreWebLivePresentation(input.activeTabId, plan.liveTarget);
        if (fullscreenStarted) {
          host.exitWebLiveFullscreen(input.activeTabId);
        }
        host.showToast(fullscreenStarted ?
          '网页视频所在标签页已经切换，已取消接管。' : '当前页面不能进入视频接管全屏。');
        return { plan: plan, started: false, webResult: presentationResult };
      }
      this.activateWebLiveAssistant(
        input.activeTabId,
        plan.sessionId,
        plan.liveTarget,
        host.exitWebLiveFullscreen,
        presentationResult
      );
      host.onStarted('web_live');
      return { plan: plan, started: true, webResult: presentationResult };
    } finally {
      this.finishLaunch(input.activeTabId, plan.launchLease.leaseId);
      host.invalidatePresentation();
    }
  }

  private resolveActiveSession(tabId: string): MediaResolvedVideoAssistantSession | undefined {
    const snapshot = this.runtimeEvidencePublisher?.resolveSnapshot(tabId.trim());
    return this.resolveActiveSessionFromSnapshot(snapshot);
  }

  private parseWebActionToolbarRequest(payloadJson: string): BrowserArkWebMediaActionToolbarRequest | undefined {
    if (payloadJson.length <= 0 || payloadJson.length > WEB_VIDEO_ACTION_TOOLBAR_REQUEST_MAX_LENGTH) {
      return undefined;
    }
    try {
      const request = JSON.parse(payloadJson) as BrowserArkWebMediaActionToolbarRequest;
      const runtimeId = request.runtimeId?.trim() ?? '';
      const frameRuntimeId = request.frameRuntimeId?.trim() ?? '';
      if (request.protocol !== WEB_VIDEO_ACTION_TOOLBAR_PROTOCOL || request.action !== 'fullscreen' ||
        runtimeId.length <= 0 || runtimeId.length > 256 || frameRuntimeId.length > 256) {
        return undefined;
      }
      return {
        protocol: request.protocol,
        action: request.action,
        runtimeId: runtimeId,
        frameRuntimeId: frameRuntimeId
      };
    } catch (_error) {
      return undefined;
    }
  }

  private resolveActiveSessionFromSnapshot(
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

  private resolveSessionByTargetKey(
    tabId: string,
    targetKey: string
  ): MediaResolvedVideoAssistantSession | undefined {
    const snapshot = this.runtimeEvidencePublisher?.resolveSnapshot(tabId.trim());
    if (snapshot === undefined) {
      return undefined;
    }
    const sessions = snapshot.getSessions();
    let matched: MediaResolvedVideoAssistantSession | undefined = undefined;
    for (let i: number = 0; i < sessions.length; i += 1) {
      if (sessions[i].targetKey === targetKey) {
        if (matched !== undefined) {
          return undefined;
        }
        matched = sessions[i];
      }
    }
    return matched;
  }

  private isLaunchPlanCurrent(tabId: string, plan: BrowserArkWebMediaLaunchPlan): boolean {
    const normalizedTabId = tabId.trim();
    const lease = plan.launchLease;
    const currentLease = this.launchLeaseByTab.get(normalizedTabId);
    if (lease === undefined || currentLease === undefined || currentLease.leaseId !== lease.leaseId ||
      lease.tabId !== normalizedTabId || Date.now() > lease.expiresAt ||
      !this.runtimeLifecyclePort.isActiveWebTab(normalizedTabId)) {
      return false;
    }
    const snapshot = this.runtimeEvidencePublisher?.resolveSnapshot(normalizedTabId);
    const scope = snapshot?.getScope();
    if (scope === undefined || scope.generationId !== lease.generationId ||
      scope.routeEpochId !== lease.routeEpochId) {
      return false;
    }
    const session = this.resolveActiveSessionFromSnapshot(snapshot);
    return session !== undefined && plan.sessionId === lease.sessionId && plan.liveTarget !== undefined &&
      session.sessionId === lease.sessionId && session.targetKey === lease.targetKey &&
      session.playbackState === 'playing' && this.sessionMatchesLiveTarget(session, plan.liveTarget) &&
      this.sessionMatchesLaunchLease(session, lease);
  }

  private createLaunchLease(
    tabId: string,
    session: MediaResolvedVideoAssistantSession,
    target: WebVideoLiveSessionTarget
  ): BrowserArkWebMediaLaunchLease | undefined {
    const snapshot = this.runtimeEvidencePublisher?.resolveSnapshot(tabId);
    const scope = snapshot?.getScope();
    const current = this.resolveActiveSessionFromSnapshot(snapshot);
    if (scope === undefined || current === undefined || current.sessionId !== session.sessionId ||
      current.targetKey !== session.targetKey || !this.sessionMatchesLiveTarget(current, target) ||
      !this.runtimeLifecyclePort.isActiveWebTab(tabId)) {
      return undefined;
    }
    const binding = current.playbackTargetBinding;
    if (binding === undefined) {
      return undefined;
    }
    const issuedAt = Date.now();
    const leaseId = tabId + ':' + issuedAt.toString() + ':' + this.nextLaunchLeaseSequence.toString();
    this.nextLaunchLeaseSequence += 1;
    return {
      leaseId: leaseId,
      tabId: tabId,
      generationId: scope.generationId,
      routeEpochId: scope.routeEpochId,
      sessionId: current.sessionId,
      targetKey: current.targetKey,
      transport: binding.transport,
      runtimeId: binding.runtimeId,
      frameRuntimeId: binding.frameRuntimeId,
      elementId: binding.elementId,
      issuedAt: issuedAt,
      expiresAt: issuedAt + WEB_LIVE_LAUNCH_LEASE_MS
    };
  }

  private sessionMatchesLaunchLease(
    session: MediaResolvedVideoAssistantSession,
    lease: BrowserArkWebMediaLaunchLease
  ): boolean {
    const binding = session.playbackTargetBinding;
    return binding !== undefined && binding.transport === lease.transport &&
      binding.runtimeId === lease.runtimeId && binding.frameRuntimeId === lease.frameRuntimeId &&
      binding.elementId === lease.elementId;
  }

  private async probeLiveTargetWithStableConfirmation(
    tabId: string,
    session: MediaResolvedVideoAssistantSession,
    target: WebVideoLiveSessionTarget,
    controller: webview.WebviewController | undefined
  ): Promise<WebVideoLiveCommandResult> {
    const firstResult = await this.webVideoPresentationService.probeLiveTarget(controller, target);
    if (!firstResult.ok || !this.isSessionTargetCurrent(tabId, session, target)) {
      return firstResult;
    }
    await this.delay(WEB_LIVE_STABLE_CONFIRMATION_DELAY_MS);
    if (!this.isSessionTargetCurrent(tabId, session, target)) {
      return firstResult;
    }
    return this.webVideoPresentationService.probeLiveTarget(controller, target);
  }

  private async probeWebFullscreenWithConfirmation(
    controller: webview.WebviewController | undefined,
    target: WebVideoLiveSessionTarget
  ): Promise<WebVideoLiveCommandResult> {
    let latest = await this.webVideoPresentationService.probeLiveTarget(controller, target);
    if (!latest.ok || latest.fullscreenActive) {
      return latest;
    }
    for (let attempt = 0; attempt < 8; attempt += 1) {
      await this.delay(80);
      latest = await this.webVideoPresentationService.probeLiveTarget(controller, target);
      if (!latest.ok || latest.fullscreenActive) {
        return latest;
      }
    }
    return latest;
  }

  private isSessionTargetCurrent(
    tabId: string,
    expected: MediaResolvedVideoAssistantSession,
    target: WebVideoLiveSessionTarget
  ): boolean {
    const current = this.resolveActiveSession(tabId);
    return current !== undefined && current.sessionId === expected.sessionId &&
      current.targetKey === expected.targetKey && current.playbackState === 'playing' &&
      this.sessionMatchesLiveTarget(current, target);
  }

  private isLayoutRevalidationEvent(eventName: string): boolean {
    const normalized = eventName.trim().toLowerCase();
    return normalized === 'resize' || normalized.indexOf('geometry_') === 0 ||
      normalized.indexOf('fullscreen') >= 0;
  }

  private isWebLiveRouteEligible(
    tabId: string,
    session: MediaResolvedVideoAssistantSession,
    webLiveRouteEnabled: boolean
  ): boolean {
    return VIDEO_ASSISTANT_LIVE_ROUTE_ENABLED && webLiveRouteEnabled &&
      session.playbackTargetBinding !== undefined &&
      session.playbackTargetBinding.runtimeId.length > 0 &&
      session.webLiveReachability === 'reachable' &&
      session.webLiveReachabilityExpiresAt > Date.now() &&
      this.runtimeLifecyclePort.resolveController(tabId) !== undefined;
  }

  private buildWebLiveTarget(
    tabId: string,
    session: MediaResolvedVideoAssistantSession
  ): WebVideoLiveSessionTarget | undefined {
    const binding = session.playbackTargetBinding;
    if (binding === undefined || binding.runtimeId.length <= 0) {
      return undefined;
    }
    return {
      runtimeId: binding.runtimeId,
      elementId: binding.elementId,
      source: '',
      tabId: tabId,
      frameRuntimeId: binding.frameRuntimeId,
      transport: binding.transport,
      presentationMode: this.resolveWebLivePresentationMode(tabId)
    };
  }

  private resolveWebLivePresentationMode(tabId: string): WebVideoLivePresentationMode {
    const snapshot = this.runtimeEvidencePublisher?.resolveSnapshot(tabId);
    const scope = snapshot?.getScope();
    if (scope === undefined) {
      return 'viewport_promoted';
    }
    const resolution = this.videoCompatibilityProfileCatalog.getCurrentResolution(tabId);
    if (resolution === undefined || !resolution.isProfileApplied() ||
      !this.sameProfileScope(resolution.getScope(), scope)) {
      return 'viewport_promoted';
    }
    return resolution.getPresentationMode() ?? 'viewport_promoted';
  }

  private sameProfileScope(
    left: MediaEvidenceScope,
    right: MediaEvidenceScope
  ): boolean {
    return left.tabId === right.tabId && left.generationId === right.generationId &&
      left.routeEpochId === right.routeEpochId;
  }

  private sessionMatchesLiveTarget(
    session: MediaResolvedVideoAssistantSession,
    target: WebVideoLiveSessionTarget
  ): boolean {
    const binding = session.playbackTargetBinding;
    return binding !== undefined && binding.runtimeId === target.runtimeId &&
      binding.transport === (target.transport ?? 'document_direct') &&
      binding.frameRuntimeId === (target.frameRuntimeId?.trim() ?? '');
  }

  private buildReachabilityEvidence(
    targetKey: string,
    state: 'reachable' | 'unreachable',
    expiresAt: number = 0
  ): BrowserArkWebMediaReachabilityEvidence {
    const observedAt = Date.now();
    return {
      kind: 'web_live_reachability',
      targetKey: targetKey,
      state: state,
      observedAt: observedAt,
      expiresAt: state === 'reachable' ? expiresAt : observedAt
    };
  }

  private publishLaunchReachability(
    plan: BrowserArkWebMediaLaunchPlan,
    capture: BrowserArkWebMediaRuntimeEvidenceCapture,
    state: 'reachable' | 'unreachable'
  ): boolean {
    const targetKey = plan.reachabilityTargetKey?.trim() ?? '';
    if (targetKey.length <= 0 || !capture.isCurrent()) {
      return false;
    }
    const expiresAt = state === 'reachable' ? Date.now() + WEB_LIVE_REACHABILITY_TTL_MS : 0;
    return capture.commit(this.buildReachabilityEvidence(targetKey, state, expiresAt));
  }

  private buildWebLiveCommandPlaybackEvidence(
    targetKey: string,
    command: BrowserArkWebMediaWebLiveCommand,
    result: WebVideoLiveCommandResult,
    observedAt: number
  ): BrowserArkWebMediaPlaybackEvidence | undefined {
    if (targetKey.length <= 0) {
      return undefined;
    }
    let event: 'snapshot' | 'playing' | 'paused' | 'ended' = 'snapshot';
    if (result.ended) {
      event = 'ended';
    } else if (command.action === 'toggle' && result.reason === 'pause_applied') {
      event = 'paused';
    } else if (command.action === 'toggle' && result.paused === false) {
      event = 'playing';
    }
    return {
      kind: 'playback',
      targetKey: targetKey,
      event: event,
      observedAt: observedAt,
      currentTimeSeconds: Math.max(0, result.currentTime),
      durationSeconds: Math.max(0, result.duration)
    };
  }

  private async executeWebLiveCommand(
    command: BrowserArkWebMediaWebLiveCommand,
    host: BrowserArkWebMediaAssistantPlayerHost
  ): Promise<boolean> {
    const session = this.resolveActiveWebLiveSession();
    const target = this.activeWebLiveTarget;
    if (session === undefined || target === undefined) {
      host.showToast('当前网页视频会话已经失效。');
      return false;
    }
    const capture = this.runtimeEvidencePublisher?.capture(this.activeWebLiveTabId);
    if (capture === undefined || !capture.isCurrent()) {
      return false;
    }
    if (command.action === 'seek' && this.setActiveWebLiveLoadingReason('seeking')) {
      host.invalidatePresentation();
    }
    const result = await this.webVideoPresentationService.executeLiveCommand(
      this.runtimeLifecyclePort.resolveController(this.activeWebLiveTabId),
      target,
      command
    );
    if (!result.ok) {
      if (command.action === 'seek' && this.setActiveWebLiveLoadingReason('')) {
        host.invalidatePresentation();
      }
      if (result.userVisibleMessage.length > 0) {
        host.showToast(result.userVisibleMessage);
      }
      return false;
    }
    const current = this.resolveActiveWebLiveSession();
    if (!capture.isCurrent() || current === undefined || current.sessionId !== session.sessionId ||
      current.targetKey !== session.targetKey || !this.sessionMatchesLiveTarget(current, target)) {
      if (command.action === 'seek' && this.setActiveWebLiveLoadingReason('')) {
        host.invalidatePresentation();
      }
      return false;
    }
    const readinessChanged = this.applyWebLiveCommandReadiness(command, result);
    const evidence = this.buildWebLiveCommandPlaybackEvidence(
      session.targetKey,
      command,
      result,
      Date.now()
    );
    if ((evidence !== undefined && capture.commit(evidence)) || readinessChanged) {
      host.invalidatePresentation();
    }
    return true;
  }

  private async requestAssistantCast(host: BrowserArkWebMediaAssistantPlayerHost): Promise<void> {
    const session = this.resolveActiveWebLiveSession();
    const metadata = this.metadataByTabId.get(this.activeWebLiveTabId);
    if (session === undefined || metadata === undefined) {
      host.showToast('当前网页视频会话已经失效。');
      return;
    }
    const sessionKey = this.activeWebLiveSessionId;
    const resolvedCastMedia = this.runtimeEvidencePublisher?.resolveCastMedia(
      this.activeWebLiveTabId,
      session.playbackTargetId
    );
    if (resolvedCastMedia?.reason === 'missing_target') {
      host.showToast('当前网页视频会话已经失效。');
      return;
    }
    if (resolvedCastMedia?.reason === 'ambiguous_resource') {
      host.showToast('当前视频匹配到多个投放地址，暂时无法确定要投放哪一个。');
      return;
    }
    if (resolvedCastMedia?.reason === 'web_context_required') {
      hilog.info(
        ARKWEB_MEDIA_LOG_DOMAIN,
        ARKWEB_MEDIA_LOG_TAG,
        'cast_media_rejected reason=%{public}s',
        'web_context_required'
      );
      host.showToast('当前视频依赖网页登录或鉴权信息，投放设备无法直接读取。');
      return;
    }
    if (resolvedCastMedia?.reason === 'unsupported_resource') {
      host.showToast('当前视频资源需要网页环境或使用了不支持的格式，暂时无法投放。');
      return;
    }
    if (resolvedCastMedia?.reason === 'ready' && resolvedCastMedia.mediaUri === undefined) {
      host.showToast('当前视频没有可供投放设备直接读取的地址。');
      return;
    }
    const resolvedMediaReady = resolvedCastMedia?.reason === 'ready' &&
      resolvedCastMedia.mediaUri !== undefined;
    if (!resolvedMediaReady && metadata.requiresWebRequestContext) {
      hilog.info(
        ARKWEB_MEDIA_LOG_DOMAIN,
        ARKWEB_MEDIA_LOG_TAG,
        'cast_media_rejected reason=%{public}s',
        metadata.requestContextReason
      );
      host.showToast('当前视频依赖网页登录或鉴权信息，投放设备无法直接读取。');
      return;
    }
    const item: VideoAssistantCastMediaItem = {
      sessionKey: sessionKey,
      title: metadata.pageTitle,
      pageUrl: metadata.pageUrl,
      mediaUri: resolvedMediaReady ? resolvedCastMedia?.mediaUri ?? '' : metadata.primarySource,
      mediaFormat: resolvedMediaReady ? resolvedCastMedia?.mediaFormat ?? '' : metadata.primarySourceFormat,
      posterUrl: metadata.posterUrl,
      durationSeconds: Math.max(0, session.durationSeconds),
      positionSeconds: Math.max(0, session.currentTimeSeconds),
      requiresWebRequestContext: resolvedMediaReady ? false : metadata.requiresWebRequestContext,
      requestHeaderCount: resolvedMediaReady ?
        resolvedCastMedia?.requestHeaderCount ?? 0 : metadata.requestHeaderCount
    };
    const result = await this.castSessionService.requestCast(item, {
      isCurrent: (): boolean => this.isCastRequestCurrent(sessionKey),
      isPlaying: (): boolean => this.isAssistantLocalPlaybackPlaying(sessionKey),
      pause: (): Promise<boolean> => this.setAssistantLocalPlayback(false, host),
      resume: (): Promise<boolean> => this.setAssistantLocalPlayback(true, host),
      showMessage: (message: string): void => {
        if (this.isCastRequestCurrent(sessionKey)) {
          host.showToast(message);
        }
      }
    });
    if (!result.opened && result.message.length > 0 && this.isCastRequestCurrent(sessionKey)) {
      host.showToast(result.message);
    }
  }

  private isCastRequestCurrent(sessionKey: string): boolean {
    const current = this.resolveActiveWebLiveSession();
    return current !== undefined && this.activeWebLiveSessionId === sessionKey &&
      current.sessionId === sessionKey;
  }

  private isAssistantLocalPlaybackPlaying(sessionKey: string): boolean {
    const current = this.resolveActiveWebLiveSession();
    return current !== undefined && this.activeWebLiveSessionId === sessionKey &&
      current.sessionId === sessionKey && current.playbackState === 'playing';
  }

  private async setAssistantLocalPlayback(
    playing: boolean,
    host: BrowserArkWebMediaAssistantPlayerHost
  ): Promise<boolean> {
    const session = this.resolveActiveWebLiveSession();
    if (session === undefined) {
      return false;
    }
    const currentlyPlaying = session.playbackState === 'playing';
    if (currentlyPlaying === playing) {
      return true;
    }
    return this.executeWebLiveCommand({ action: 'toggle' }, host);
  }

  private async requestAssistantDownload(
    session: MediaResolvedVideoAssistantSession,
    host: BrowserArkWebMediaAssistantPlayerHost
  ): Promise<void> {
    const interaction = this.beginDownloadInteraction(session);
    if (interaction === undefined) {
      host.showToast('当前网页视频会话已经失效。');
      return;
    }
    try {
      await host.requestDownload(interaction.tabId, interaction.playbackTargetId);
    } catch (_error) {
      host.showToast('当前视频下载请求失败。');
    } finally {
      try {
        await this.refreshDownloadInteractionEvidence(interaction);
      } catch (_error) {
      } finally {
        this.endDownloadInteraction(interaction.interactionId);
        host.invalidatePresentation();
      }
    }
  }

  private beginDownloadInteraction(
    session: MediaResolvedVideoAssistantSession
  ): BrowserArkWebMediaDownloadInteraction | undefined {
    const tabId = this.activeWebLiveTabId;
    const snapshot = this.runtimeEvidencePublisher?.resolveSnapshot(tabId);
    const scope = snapshot?.getScope();
    const evidenceCapture = this.runtimeEvidencePublisher?.capture(tabId);
    if (snapshot === undefined || scope === undefined || evidenceCapture === undefined || !evidenceCapture.isCurrent() ||
      scope.generationId !== this.activeWebLiveGenerationId || scope.routeEpochId !== this.activeWebLiveRouteEpochId ||
      session.sessionId !== this.activeWebLiveSessionId || session.playbackTargetId.trim().length <= 0) {
      return undefined;
    }
    const sequence = this.nextDownloadInteractionSequence;
    this.nextDownloadInteractionSequence += 1;
    const interaction: BrowserArkWebMediaDownloadInteraction = {
      interactionId: `media-takeover-download-${Date.now()}-${sequence}`,
      tabId: tabId,
      generationId: scope.generationId,
      routeEpochId: scope.routeEpochId,
      sessionId: session.sessionId,
      playbackTargetId: session.playbackTargetId,
      targetKey: session.targetKey,
      session: session,
      evidenceCapture: evidenceCapture
    };
    this.activeDownloadInteraction = interaction;
    return interaction;
  }

  private async refreshDownloadInteractionEvidence(
    interaction: BrowserArkWebMediaDownloadInteraction
  ): Promise<void> {
    const target = this.activeWebLiveTarget;
    if (!this.isDownloadInteractionCurrent(interaction) || target === undefined) {
      return;
    }
    const result = await this.webVideoPresentationService.executeLiveCommand(
      this.runtimeLifecyclePort.resolveController(interaction.tabId),
      target,
      { action: 'read_state' }
    );
    if (!result.ok || !this.isDownloadInteractionCurrent(interaction)) {
      return;
    }
    const observedAt = Date.now();
    interaction.evidenceCapture.commit(
      this.buildReachabilityEvidence(
        interaction.targetKey,
        'reachable',
        observedAt + WEB_LIVE_REACHABILITY_TTL_MS
      )
    );
    interaction.evidenceCapture.commit({
      kind: 'playback',
      targetKey: interaction.targetKey,
      event: result.ended ? 'ended' : result.paused ? 'paused' : 'playing',
      observedAt: observedAt,
      currentTimeSeconds: Math.max(0, result.currentTime),
      durationSeconds: Math.max(0, result.duration)
    });
  }

  private endDownloadInteraction(interactionId: string): void {
    if (this.activeDownloadInteraction?.interactionId === interactionId) {
      this.activeDownloadInteraction = undefined;
    }
  }

  private async closeAssistantPlayer(
    host?: BrowserArkWebMediaAssistantPlayerHost
  ): Promise<VideoAssistantState> {
    if (!this.isWebLiveAssistantActive()) {
      host?.invalidatePresentation();
      return createInactiveVideoAssistantState();
    }
    const tabId = this.activeWebLiveTabId;
    const target = this.activeWebLiveTarget;
    if (this.webLiveExitInFlight || target === undefined) {
      return this.buildWebLiveAssistantPlayerState();
    }
    this.webLiveExitInFlight = true;
    this.webLiveOrientationInFlight = false;
    this.webLiveOrientationRequestId += 1;
    host?.invalidatePresentation();
    try {
      await this.restoreWebLivePresentation(tabId, target);
      if (host !== undefined) {
        await host.exitWebLiveFullscreen(tabId);
      }
    } finally {
      this.clearWebLiveAssistant();
      this.webLiveExitInFlight = false;
      host?.invalidatePresentation();
    }
    return createInactiveVideoAssistantState();
  }

  private async requestAssistantOrientation(
    orientation: BrowserArkWebMediaAssistantOrientation,
    host: BrowserArkWebMediaAssistantPlayerHost
  ): Promise<void> {
    const requestId = ++this.webLiveOrientationRequestId;
    const refreshWebLivePresentation = this.isWebLiveAssistantActive();
    if (refreshWebLivePresentation) {
      this.webLiveOrientationInFlight = true;
      host.invalidatePresentation();
    }
    try {
      await host.applyOrientation(orientation, 'assistant_video_manual_rotate');
    } catch (_error) {
      host.showToast('视频方向切换失败。');
    } finally {
      if (requestId === this.webLiveOrientationRequestId) {
        this.webLiveOrientationInFlight = false;
        host.invalidatePresentation();
      }
    }
  }

  private activateWebLiveAssistant(
    tabId: string,
    sessionId: string,
    target: WebVideoLiveSessionTarget,
    exitFullscreen: (tabId: string) => void,
    presentationResult: WebVideoLiveCommandResult
  ): void {
    const scope = this.runtimeEvidencePublisher?.resolveSnapshot(tabId.trim())?.getScope();
    this.activeWebLiveTabId = tabId.trim();
    this.activeWebLiveSessionId = sessionId.trim();
    this.activeWebLiveGenerationId = scope?.generationId ?? '';
    this.activeWebLiveRouteEpochId = scope?.routeEpochId ?? '';
    this.activeWebLiveTarget = target;
    this.activeWebLiveExitFullscreen = exitFullscreen;
    this.activeWebLiveStartedAt = Date.now();
    this.activeWebLiveLoadingReason = '';
    this.activeWebLiveErrorMessage = '';
    this.applyWebLiveReadinessSnapshot(presentationResult, 'preparing');
  }

  private clearWebLiveAssistantForTab(tabId: string): void {
    if (tabId.trim() === this.activeWebLiveTabId) {
      this.clearWebLiveAssistant();
    }
  }

  private clearWebLiveAssistant(): void {
    void this.castSessionService.release();
    this.activeWebLiveTabId = '';
    this.activeWebLiveSessionId = '';
    this.activeWebLiveGenerationId = '';
    this.activeWebLiveRouteEpochId = '';
    this.activeWebLiveTarget = undefined;
    this.activeWebLiveExitFullscreen = undefined;
    this.activeWebLiveStartedAt = 0;
    this.activeWebLiveLoadingReason = '';
    this.activeWebLiveErrorMessage = '';
    this.activeDownloadInteraction = undefined;
    this.webLiveExitInFlight = false;
    this.webLiveOrientationInFlight = false;
    this.webLiveOrientationRequestId += 1;
  }

  private restoreActiveWebLivePresentation(): void {
    if (this.activeWebLiveTarget !== undefined && this.activeWebLiveTabId.length > 0) {
      void this.restoreWebLivePresentation(this.activeWebLiveTabId, this.activeWebLiveTarget);
    }
  }

  private restoreWebLivePresentation(
    tabId: string,
    target: WebVideoLiveSessionTarget
  ): Promise<WebVideoLiveCommandResult> {
    return this.webVideoPresentationService.executeLiveCommand(
      this.runtimeLifecyclePort.resolveController(tabId),
      target,
      { action: 'restore_presentation' }
    );
  }

  private resolveActiveWebLiveSession(): MediaResolvedVideoAssistantSession | undefined {
    if (!this.hasWebLiveAssistantRegistration()) {
      return undefined;
    }
    const snapshot = this.runtimeEvidencePublisher?.resolveSnapshot(this.activeWebLiveTabId);
    const scope = snapshot?.getScope();
    if (snapshot === undefined || scope === undefined || scope.generationId !== this.activeWebLiveGenerationId ||
      scope.routeEpochId !== this.activeWebLiveRouteEpochId) {
      return this.resolveDownloadInteractionSession(snapshot);
    }
    if (snapshot.outcome === 'ambiguous') {
      return this.resolveDownloadInteractionSession(snapshot);
    }
    if (snapshot.outcome === 'active' && snapshot.activeSessionId !== this.activeWebLiveSessionId) {
      return undefined;
    }
    const sessions = snapshot.getSessions();
    for (let i: number = 0; i < sessions.length; i += 1) {
      if (sessions[i].sessionId === this.activeWebLiveSessionId) {
        if (snapshot.outcome === 'active') {
          return sessions[i];
        }
        return sessions[i].playbackState === 'paused' || sessions[i].playbackState === 'ended' ?
          sessions[i] : undefined;
      }
    }
    return this.resolveDownloadInteractionSession(snapshot);
  }

  private resolveDownloadInteractionSession(
    snapshot: MediaSessionResolutionSnapshot | undefined
  ): MediaResolvedVideoAssistantSession | undefined {
    const interaction = this.activeDownloadInteraction;
    if (interaction === undefined || !this.isDownloadInteractionCurrent(interaction)) {
      return undefined;
    }
    if (snapshot !== undefined) {
      const scope = snapshot.getScope();
      if (scope.generationId !== interaction.generationId || scope.routeEpochId !== interaction.routeEpochId ||
        (snapshot.outcome === 'active' && snapshot.activeSessionId !== interaction.sessionId)) {
        return undefined;
      }
      const sessions = snapshot.getSessions();
      for (let i: number = 0; i < sessions.length; i += 1) {
        if (sessions[i].sessionId === interaction.sessionId) {
          return sessions[i].playbackTargetId === interaction.playbackTargetId &&
            sessions[i].targetKey === interaction.targetKey ? sessions[i] : undefined;
        }
      }
    }
    return interaction.session;
  }

  private isDownloadInteractionCurrent(interaction: BrowserArkWebMediaDownloadInteraction): boolean {
    if (this.activeDownloadInteraction?.interactionId !== interaction.interactionId ||
      this.activeWebLiveTabId !== interaction.tabId || this.activeWebLiveSessionId !== interaction.sessionId ||
      this.activeWebLiveGenerationId !== interaction.generationId ||
      this.activeWebLiveRouteEpochId !== interaction.routeEpochId) {
      return false;
    }
    try {
      return interaction.evidenceCapture.isCurrent();
    } catch (_error) {
      return false;
    }
  }

  private hasWebLiveAssistantRegistration(): boolean {
    return this.activeWebLiveTabId.length > 0 && this.activeWebLiveSessionId.length > 0 &&
      this.activeWebLiveTarget !== undefined;
  }

  private applyWebLiveCommandReadiness(
    command: BrowserArkWebMediaWebLiveCommand,
    result: WebVideoLiveCommandResult
  ): boolean {
    if (command.action !== 'seek' && command.action !== 'toggle') {
      return false;
    }
    if (result.errorCode > 0) {
      return this.applyWebLiveReadinessSnapshot(result, command.action === 'seek' ? 'seeking' : 'buffering');
    }
    let changed = this.setActiveWebLiveErrorMessage('');
    if (command.action === 'seek') {
      changed = this.setActiveWebLiveLoadingReason(
        this.resolveCommandLoadingReason(result, 'seeking')
      ) || changed;
      return changed;
    }
    if (result.reason === 'pause_applied' || result.paused || result.ended) {
      changed = this.setActiveWebLiveLoadingReason('') || changed;
      return changed;
    }
    changed = this.setActiveWebLiveLoadingReason(
      this.resolveCommandLoadingReason(result, 'buffering')
    ) || changed;
    return changed;
  }

  private applyWebLiveReadinessSnapshot(
    result: WebVideoLiveCommandResult,
    fallback: VideoAssistantLoadingReason
  ): boolean {
    if (result.errorCode > 0) {
      let changed = this.setActiveWebLiveLoadingReason('');
      changed = this.setActiveWebLiveErrorMessage('视频播放失败。') || changed;
      return changed;
    }
    let changed = this.setActiveWebLiveErrorMessage('');
    changed = this.setActiveWebLiveLoadingReason(this.resolveCommandLoadingReason(result, fallback)) || changed;
    return changed;
  }

  private resolveCommandLoadingReason(
    result: WebVideoLiveCommandResult,
    fallback: VideoAssistantLoadingReason
  ): VideoAssistantLoadingReason {
    if (result.ended) {
      return '';
    }
    if (result.seeking) {
      return fallback === 'preparing' ? 'preparing' : 'seeking';
    }
    const minimumReadyState = result.paused ? 2 : 3;
    return result.readyState >= minimumReadyState ? '' : fallback;
  }

  private applyActiveWebLivePlaybackSignal(input: BrowserArkWebMediaActivePlaybackSignalInput): boolean {
    const target = this.activeWebLiveTarget;
    const targetTransport = target?.transport ?? 'document_direct';
    if (!this.hasWebLiveAssistantRegistration() || target === undefined ||
      input.tabId.trim() !== this.activeWebLiveTabId || input.transport !== targetTransport ||
      input.runtimeId.trim() !== target.runtimeId ||
      (targetTransport === 'frame_proxy' && input.frameRuntimeId.trim() !== (target.frameRuntimeId?.trim() ?? ''))) {
      return false;
    }
    const eventName = input.eventName.trim().toLowerCase();
    if (eventName.length <= 0) {
      return false;
    }
    if (eventName === 'error') {
      let changed = this.setActiveWebLiveLoadingReason('');
      changed = this.setActiveWebLiveErrorMessage('视频播放失败。') || changed;
      return changed;
    }
    if (eventName === 'pause' || eventName === 'ended' || eventName === 'emptied' || eventName === 'abort') {
      return this.setActiveWebLiveLoadingReason('');
    }
    if (eventName === 'seeking' || input.seeking === true) {
      let changed = this.setActiveWebLiveErrorMessage('');
      changed = this.setActiveWebLiveLoadingReason('seeking') || changed;
      return changed;
    }
    if (eventName === 'waiting' ||
      ((eventName === 'stalled' || eventName === 'loadstart') && input.readyState < 3 &&
        input.networkState === 2)) {
      if (input.paused === true || input.ended === true) {
        return this.setActiveWebLiveLoadingReason('');
      }
      let changed = this.setActiveWebLiveErrorMessage('');
      changed = this.setActiveWebLiveLoadingReason('buffering') || changed;
      return changed;
    }
    if (eventName === 'playing') {
      let changed = this.setActiveWebLiveErrorMessage('');
      changed = this.setActiveWebLiveLoadingReason('') || changed;
      return changed;
    }
    if (eventName === 'canplay' || eventName === 'canplaythrough' || eventName === 'seeked' ||
      eventName === 'loadedmetadata') {
      const minimumReadyState = input.paused === true ? 2 : 3;
      if (input.readyState >= minimumReadyState) {
        return this.setActiveWebLiveLoadingReason('');
      }
      return false;
    }
    return false;
  }

  private setActiveWebLiveLoadingReason(reason: VideoAssistantLoadingReason): boolean {
    if (this.activeWebLiveLoadingReason === reason) {
      return false;
    }
    this.activeWebLiveLoadingReason = reason;
    return true;
  }

  private setActiveWebLiveErrorMessage(message: string): boolean {
    if (this.activeWebLiveErrorMessage === message) {
      return false;
    }
    this.activeWebLiveErrorMessage = message;
    return true;
  }

  private boundedInteger(value: number | undefined, minimum: number, maximum: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return minimum;
    }
    return Math.max(minimum, Math.min(maximum, Math.floor(value)));
  }

  private buildWebLiveAssistantPlayerState(): VideoAssistantState {
    const session = this.resolveActiveWebLiveSession();
    if (session === undefined) {
      return createInactiveVideoAssistantState();
    }
    const metadata = this.metadataByTabId.get(this.activeWebLiveTabId);
    const playbackStatus: VideoAssistantPlaybackStatus = this.activeWebLiveErrorMessage.length > 0 ? 'error' :
      session.playbackState === 'playing' ? 'playing' :
        session.playbackState === 'paused' ? 'paused' :
          session.playbackState === 'ended' ? 'ended' : 'ready';
    return {
      active: true,
      item: {
        id: 'web-live:' + session.sessionId,
        tabId: this.activeWebLiveTabId,
        title: metadata?.pageTitle ?? '网页视频',
        pageUrl: metadata?.pageUrl ?? '',
        url: this.activeWebLiveTarget?.source ?? '',
        posterUrl: metadata?.posterUrl ?? '',
        width: this.resolveVideoWidth(session),
        height: this.resolveVideoHeight(session)
      },
      playbackStatus: playbackStatus,
      loadingReason: playbackStatus === 'error' ? '' : this.activeWebLiveLoadingReason,
      positionSeconds: Math.max(0, session.currentTimeSeconds),
      durationSeconds: Math.max(0, session.durationSeconds),
      errorMessage: this.activeWebLiveErrorMessage,
      fullscreen: true,
      startedAtMs: this.activeWebLiveStartedAt
    };
  }

  private invalidateActiveFrameWebLiveTarget(
    tabId: string,
    frameRuntimeId: string,
    runtimeId: string = ''
  ): boolean {
    const target = this.activeWebLiveTarget;
    if (target === undefined || this.activeWebLiveTabId !== tabId.trim() ||
      (target.transport ?? 'document_direct') !== 'frame_proxy' ||
      (target.frameRuntimeId?.trim() ?? '') !== frameRuntimeId.trim() ||
      (runtimeId.trim().length > 0 && target.runtimeId !== runtimeId.trim())) {
      return false;
    }
    void this.restoreWebLivePresentation(tabId.trim(), target);
    try {
      this.activeWebLiveExitFullscreen?.(tabId.trim());
    } catch (_error) {
    }
    this.clearWebLiveAssistant();
    return true;
  }

  private isSessionEffectivelyVisible(session: MediaResolvedVideoAssistantSession, now: number): boolean {
    if (session.geometry?.visible === true) {
      this.lastVisibleAtBySessionId.set(session.sessionId, now);
      return true;
    }
    const lastVisibleAt = this.lastVisibleAtBySessionId.get(session.sessionId) ?? 0;
    return lastVisibleAt > 0 && now - lastVisibleAt <= ARKWEB_MEDIA_VISIBILITY_GRACE_MS;
  }

  private resolveVideoWidth(session: MediaResolvedVideoAssistantSession): number {
    const geometry = session.geometry;
    return Math.max(0, Math.floor(geometry?.videoWidth ?? geometry?.width ?? 0));
  }

  private resolveVideoHeight(session: MediaResolvedVideoAssistantSession): number {
    const geometry = session.geometry;
    return Math.max(0, Math.floor(geometry?.videoHeight ?? geometry?.height ?? 0));
  }

  private buildPageMetadata(input: BrowserArkWebMediaObservationInput): BrowserArkWebMediaPageMetadata {
    let primarySource = '';
    let primarySourceFormat = '';
    for (let i: number = 0; i < input.mediaInfo.mediaSrcList.length; i += 1) {
      const sourceInfo = input.mediaInfo.mediaSrcList[i];
      const source = sourceInfo.source.trim();
      if (primarySource.length <= 0 && source.length > 0 && sourceInfo.type === webview.SourceType.URL) {
        primarySource = source;
        primarySourceFormat = sourceInfo.format.trim();
      }
    }
    const requestContext = this.castRequestContextPolicy.assess(input.mediaInfo.headers);
    return {
      pageUrl: input.pageUrl.trim(),
      pageTitle: input.pageTitle.trim(),
      posterUrl: input.mediaInfo.posterUrl.trim(),
      primarySource: primarySource,
      primarySourceFormat: primarySourceFormat,
      requestHeaderCount: requestContext.requestHeaderCount,
      requiresWebRequestContext: requestContext.requiresWebRequestContext,
      requestContextReason: requestContext.reason,
      sourceCount: input.mediaInfo.mediaSrcList.length
    };
  }

  private sameMetadata(left: BrowserArkWebMediaPageMetadata, right: BrowserArkWebMediaPageMetadata): boolean {
    return left.pageUrl === right.pageUrl && left.pageTitle === right.pageTitle &&
      left.posterUrl === right.posterUrl && left.primarySource === right.primarySource &&
      left.primarySourceFormat === right.primarySourceFormat &&
      left.requestHeaderCount === right.requestHeaderCount &&
      left.requiresWebRequestContext === right.requiresWebRequestContext &&
      left.requestContextReason === right.requestContextReason &&
      left.sourceCount === right.sourceCount;
  }

  private clearVisibilityForTab(tabId: string): void {
    const prefix = 'video-session:';
    const keysToDelete: string[] = [];
    this.lastVisibleAtBySessionId.forEach((_value: number, key: string): void => {
      if (key.indexOf(prefix) === 0 && key.indexOf(tabId) >= 0) {
        keysToDelete.push(key);
      }
    });
    for (let i: number = 0; i < keysToDelete.length; i += 1) {
      this.lastVisibleAtBySessionId.delete(keysToDelete[i]);
    }
  }

  private delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, Math.max(0, delayMs));
    });
  }

  private buildRejectedObservation(reason: string): BrowserArkWebMediaObservationResult {
    return { accepted: false, changed: false, reason: reason };
  }

  private buildRejectedPlaybackSignal(reason: string): BrowserArkWebMediaPlaybackSignalResult {
    return { accepted: false, changed: false, reason: reason };
  }

  private buildRejectedLaunch(reason: string, message: string): BrowserArkWebMediaLaunchPlan {
    return { accepted: false, reason: reason, message: message };
  }
}

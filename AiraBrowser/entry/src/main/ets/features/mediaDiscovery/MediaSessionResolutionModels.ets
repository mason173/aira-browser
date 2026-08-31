import {
  MediaEvidenceQuality,
  MediaEvidenceScope,
  MediaPlaybackGeometryObservation,
  MediaPlaybackTargetTransport,
  MediaWebLiveReachabilityEvidenceState
} from './MediaEvidenceGraphModels';

export type MediaSessionResolutionOutcome = 'inactive' | 'active' | 'ambiguous';

export type MediaResolvedPlaybackState = 'playing' | 'paused' | 'ended' | 'observed' | 'unknown';

export type MediaResolvedPlaybackTargetTransport = MediaPlaybackTargetTransport;

export interface MediaResolvedPlaybackTargetBinding {
  readonly transport: MediaResolvedPlaybackTargetTransport;
  readonly runtimeId: string;
  readonly frameRuntimeId: string;
  readonly elementId: string;
}

export type MediaSessionResolutionReason =
  | 'no_current_playback_target'
  | 'no_current_playback_occurrence'
  | 'no_current_playing_session'
  | 'target_identity_ambiguous'
  | 'equally_authoritative_playing_sessions'
  | 'single_authoritative_playing_session'
  | 'strongest_playing_session'
  | 'active_session_continued';

export interface MediaResolvedVideoAssistantSession {
  readonly sessionId: string;
  readonly playbackTargetId: string;
  readonly targetKey: string;
  readonly playbackState: MediaResolvedPlaybackState;
  readonly webLiveReachability: MediaWebLiveReachabilityEvidenceState;
  readonly webLiveReachabilityObservedAt: number;
  readonly webLiveReachabilityExpiresAt: number;
  readonly evidenceQuality: MediaEvidenceQuality;
  readonly observedAt: number;
  readonly currentTimeSeconds: number;
  readonly durationSeconds: number;
  readonly playbackTargetBinding?: MediaResolvedPlaybackTargetBinding;
  readonly geometry?: MediaPlaybackGeometryObservation;
  readonly muted?: boolean;
}

export interface MediaSessionResolutionSnapshot {
  readonly evidenceRevision: number;
  readonly resolvedAt: number;
  readonly outcome: MediaSessionResolutionOutcome;
  readonly activeSessionId?: string;
  getScope(): MediaEvidenceScope;
  getSessions(): MediaResolvedVideoAssistantSession[];
  getReasons(): MediaSessionResolutionReason[];
}

/**
 * Owns defensive copies so callers can never mutate the published resolution.
 * ArkTS callers receive ordinary arrays, but every read returns a detached copy.
 */
export class ImmutableMediaSessionResolutionSnapshot implements MediaSessionResolutionSnapshot {
  readonly evidenceRevision: number;
  readonly resolvedAt: number;
  readonly outcome: MediaSessionResolutionOutcome;
  readonly activeSessionId?: string;

  private readonly scopeValue: MediaEvidenceScope;
  private readonly sessionValues: MediaResolvedVideoAssistantSession[];
  private readonly reasonValues: MediaSessionResolutionReason[];

  constructor(
    scope: MediaEvidenceScope,
    evidenceRevision: number,
    resolvedAt: number,
    outcome: MediaSessionResolutionOutcome,
    sessions: MediaResolvedVideoAssistantSession[],
    activeSessionId: string | undefined,
    reasons: MediaSessionResolutionReason[]
  ) {
    this.scopeValue = this.copyScope(scope);
    this.evidenceRevision = evidenceRevision;
    this.resolvedAt = resolvedAt;
    this.outcome = outcome;
    this.sessionValues = this.copySessions(sessions);
    this.activeSessionId = activeSessionId;
    this.reasonValues = this.copyReasons(reasons);
  }

  getScope(): MediaEvidenceScope {
    return this.copyScope(this.scopeValue);
  }

  getSessions(): MediaResolvedVideoAssistantSession[] {
    return this.copySessions(this.sessionValues);
  }

  getReasons(): MediaSessionResolutionReason[] {
    return this.copyReasons(this.reasonValues);
  }

  private copyScope(scope: MediaEvidenceScope): MediaEvidenceScope {
    return {
      tabId: scope.tabId,
      generationId: scope.generationId,
      routeEpochId: scope.routeEpochId
    };
  }

  private copySessions(sessions: MediaResolvedVideoAssistantSession[]): MediaResolvedVideoAssistantSession[] {
    const copies: MediaResolvedVideoAssistantSession[] = [];
    for (let i: number = 0; i < sessions.length; i += 1) {
      copies.push({
        sessionId: sessions[i].sessionId,
        playbackTargetId: sessions[i].playbackTargetId,
        targetKey: sessions[i].targetKey,
        playbackState: sessions[i].playbackState,
        webLiveReachability: sessions[i].webLiveReachability,
        webLiveReachabilityObservedAt: sessions[i].webLiveReachabilityObservedAt,
        webLiveReachabilityExpiresAt: sessions[i].webLiveReachabilityExpiresAt,
        evidenceQuality: sessions[i].evidenceQuality,
        observedAt: sessions[i].observedAt,
        currentTimeSeconds: sessions[i].currentTimeSeconds,
        durationSeconds: sessions[i].durationSeconds,
        playbackTargetBinding: this.copyPlaybackTargetBinding(sessions[i].playbackTargetBinding),
        geometry: this.copyGeometry(sessions[i].geometry),
        muted: sessions[i].muted
      });
    }
    return copies;
  }

  private copyPlaybackTargetBinding(
    binding: MediaResolvedPlaybackTargetBinding | undefined
  ): MediaResolvedPlaybackTargetBinding | undefined {
    if (binding === undefined) {
      return undefined;
    }
    return {
      transport: binding.transport,
      runtimeId: binding.runtimeId,
      frameRuntimeId: binding.frameRuntimeId,
      elementId: binding.elementId
    };
  }

  private copyGeometry(
    geometry: MediaPlaybackGeometryObservation | undefined
  ): MediaPlaybackGeometryObservation | undefined {
    if (geometry === undefined) {
      return undefined;
    }
    return {
      x: geometry.x,
      y: geometry.y,
      width: geometry.width,
      height: geometry.height,
      viewportWidth: geometry.viewportWidth,
      viewportHeight: geometry.viewportHeight,
      visible: geometry.visible,
      videoWidth: geometry.videoWidth,
      videoHeight: geometry.videoHeight
    };
  }

  private copyReasons(reasons: MediaSessionResolutionReason[]): MediaSessionResolutionReason[] {
    const copies: MediaSessionResolutionReason[] = [];
    for (let i: number = 0; i < reasons.length; i += 1) {
      copies.push(reasons[i]);
    }
    return copies;
  }
}

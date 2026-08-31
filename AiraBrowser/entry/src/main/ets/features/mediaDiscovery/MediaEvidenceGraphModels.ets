import { BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { MediaDiscoveryTabSnapshot } from '../../services/media/MediaDiscoveryStore';
import { MediaCandidate } from './MediaCandidateModels';
import { MediaCandidateValidationResult } from './MediaCandidateValidationModels';
import { MediaSignal } from './MediaSignalModels';

export type MediaEvidenceGenerationId = string;
export type MediaRouteEpochId = string;

export interface MediaEvidenceScope {
  readonly tabId: string;
  readonly generationId: MediaEvidenceGenerationId;
  readonly routeEpochId: MediaRouteEpochId;
}

export interface MediaEvidenceGenerationStart {
  tabId: string;
  navigationKey: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  startedAt: number;
}

export interface MediaRouteEpochAdvance {
  currentScope: MediaEvidenceScope;
  routeTransitionKey: string;
  pageUrl: string;
  pageTitle: string;
  observedAt: number;
}

export type MediaEvidenceGenerationCloseReason =
  | 'superseded_navigation'
  | 'navigation_failed'
  | 'runtime_destroyed'
  | 'tab_closed'
  | 'private_session_ended';

export interface MediaEvidenceGenerationClose {
  reason: MediaEvidenceGenerationCloseReason;
  closedAt: number;
}

export type MediaEvidenceProducerKind =
  | 'legacy_signal_adapter'
  | 'network_request'
  | 'dom_runtime'
  | 'playback_event'
  | 'arkweb_media_info'
  | 'web_live_reachability'
  | 'profile_selector'
  | 'validation';

export type MediaEvidenceQuality = 'direct' | 'derived' | 'heuristic';

export type MediaFrameDocumentType = 'main_document' | 'child_document' | 'unknown_document';

export type MediaFrameDocumentLifecycle = 'observed' | 'ended';

export interface MediaFrameDocumentObservation {
  kind: 'frame_document';
  frameDocumentKey: string;
  frameType: MediaFrameDocumentType;
  lifecycle: MediaFrameDocumentLifecycle;
  documentUrl?: string;
  parentFrameDocumentKey?: string;
  quality: MediaEvidenceQuality;
}

export type MediaPlaybackObservationEvent =
  | 'snapshot'
  | 'playing'
  | 'paused'
  | 'ended'
  | 'source_changed'
  | 'geometry_changed'
  | 'heartbeat';

export interface MediaPlaybackGeometryObservation {
  x: number;
  y: number;
  width: number;
  height: number;
  viewportWidth: number;
  viewportHeight: number;
  visible: boolean;
  videoWidth: number;
  videoHeight: number;
}

export interface MediaPlaybackTargetObservation {
  kind: 'playback_target';
  targetKey?: string;
  targetIdentityQuality: MediaPlaybackTargetIdentityQuality;
  frameDocumentKey?: string;
  event: MediaPlaybackObservationEvent;
  sourceLocators: string[];
  elementId?: string;
  muted?: boolean;
  currentTimeSeconds?: number;
  durationSeconds?: number;
  geometry?: MediaPlaybackGeometryObservation;
  quality: MediaEvidenceQuality;
}

export type MediaPlaybackTargetIdentityQuality = 'stable' | 'ambiguous' | 'unattached';

export type MediaPlaybackTargetTransport = 'document_direct' | 'frame_proxy';

export interface MediaPlaybackTargetKeyIdentity {
  transport: MediaPlaybackTargetTransport;
  runtimeId: string;
  frameRuntimeId: string;
}

export function resolveDomMediaPlaybackTargetKey(runtimeId: string): string {
  const normalizedRuntimeId = runtimeId.trim();
  return normalizedRuntimeId.length > 0 ? 'dom:' + normalizedRuntimeId : '';
}

export function resolveFrameMediaDocumentKey(frameRuntimeId: string): string {
  const normalizedFrameRuntimeId = frameRuntimeId.trim();
  return normalizedFrameRuntimeId.length > 0 ? 'frame:' + normalizedFrameRuntimeId : '';
}

export function resolveFrameMediaPlaybackTargetKey(frameRuntimeId: string, runtimeId: string): string {
  const frameDocumentKey = resolveFrameMediaDocumentKey(frameRuntimeId);
  const normalizedRuntimeId = runtimeId.trim();
  if (frameDocumentKey.length <= 0 || normalizedRuntimeId.length <= 0) {
    return '';
  }
  return frameDocumentKey + ':video:' + normalizedRuntimeId;
}

export function resolveMediaPlaybackTargetKeyIdentity(
  targetKey: string
): MediaPlaybackTargetKeyIdentity | undefined {
  const normalizedTargetKey = targetKey.trim();
  if (normalizedTargetKey.indexOf('dom:') === 0) {
    const runtimeId = normalizedTargetKey.substring(4).trim();
    if (runtimeId.length <= 0) {
      return undefined;
    }
    return {
      transport: 'document_direct',
      runtimeId: runtimeId,
      frameRuntimeId: ''
    };
  }
  if (normalizedTargetKey.indexOf('frame:') !== 0) {
    return undefined;
  }
  const videoSeparator = normalizedTargetKey.indexOf(':video:', 6);
  if (videoSeparator <= 6) {
    return undefined;
  }
  const frameRuntimeId = normalizedTargetKey.substring(6, videoSeparator).trim();
  const runtimeId = normalizedTargetKey.substring(videoSeparator + 7).trim();
  if (frameRuntimeId.length <= 0 || runtimeId.length <= 0) {
    return undefined;
  }
  return {
    transport: 'frame_proxy',
    runtimeId: runtimeId,
    frameRuntimeId: frameRuntimeId
  };
}

export interface MediaWebLiveReachabilityObservation {
  kind: 'web_live_reachability';
  targetKey: string;
  state: 'reachable' | 'unreachable';
  expiresAt: number;
  commandProtocolVersion: number;
  restoreProtocolVersion: number;
  quality: 'direct';
}

export interface MediaCompatibilitySelectorEvidenceObservation {
  kind: 'profile_selector';
  profileAttribution: string;
  evidenceKind: 'structured' | 'heuristic';
  mediaStructure: 'video' | 'audio';
  attribute: 'presence' | 'source' | 'poster' | 'dimensions';
  frameScope: 'top_document';
  originScope: 'top_origin';
  matchedCount: number;
  qualityGateMatchCount: number;
  attributeMatchCount: number;
}

export type MediaEvidenceSemanticObservation =
  | MediaFrameDocumentObservation
  | MediaPlaybackTargetObservation
  | MediaWebLiveReachabilityObservation;

export interface MediaEvidenceObservationBatch {
  scope: MediaEvidenceScope;
  producer: MediaEvidenceProducerKind;
  observedAt: number;
  signals: MediaSignal[];
  observations?: MediaEvidenceSemanticObservation[];
  selectorEvidence?: MediaCompatibilitySelectorEvidenceObservation[];
}

export type MediaEvidenceCommitDisposition =
  | 'committed'
  | 'accepted_historical'
  | 'duplicate'
  | 'rejected';

export interface MediaEvidenceProjectionChanges {
  resourceSurface: boolean;
  validationWork: boolean;
  sessionEvidence: boolean;
  diagnostics: boolean;
}

export interface MediaEvidenceCommitReceipt {
  disposition: MediaEvidenceCommitDisposition;
  scope: MediaEvidenceScope;
  revision: number;
  acceptedCount: number;
  rejectedCount: number;
  changes: MediaEvidenceProjectionChanges;
}

export interface MediaPlaybackOccurrenceEvidence {
  occurrenceId: string;
  targetKeyHint?: string;
  event: MediaPlaybackObservationEvent;
  observedAt: number;
  routeEpochId: MediaRouteEpochId;
  currentRoute: boolean;
  producer: MediaEvidenceProducerKind;
  quality: MediaEvidenceQuality;
  sourceLocators: MediaSanitizedLocatorEvidence[];
  muted?: boolean;
  currentTimeSeconds?: number;
  durationSeconds?: number;
  geometry?: MediaPlaybackGeometryObservation;
}

export interface MediaSanitizedLocatorEvidence {
  identity: string;
  safeLocator: string;
  hasQuery: boolean;
}

export type MediaWebLiveReachabilityEvidenceState = 'unknown' | 'reachable' | 'unreachable' | 'expired';

export interface MediaSessionFrameDocumentClaimEvidence {
  claimId: string;
  observedAt: number;
  routeEpochId: MediaRouteEpochId;
  currentRoute: boolean;
  producer: MediaEvidenceProducerKind;
  quality: MediaEvidenceQuality;
  frameType: MediaFrameDocumentType;
  lifecycle: MediaFrameDocumentLifecycle;
  documentLocator?: MediaSanitizedLocatorEvidence;
  parentFrameDocumentKey?: string;
}

export interface MediaSessionFrameDocumentEvidence {
  frameDocumentId: string;
  frameDocumentKey: string;
  claims: MediaSessionFrameDocumentClaimEvidence[];
  currentRoute: boolean;
  hasEndedClaim: boolean;
  ambiguityReasons: string[];
}

export interface MediaSessionPlaybackTargetEvidence {
  playbackTargetId: string;
  targetKey: string;
  targetIdentityQuality: MediaPlaybackTargetIdentityQuality;
  frameDocuments: MediaSessionFrameDocumentEvidence[];
  elementId?: string;
  firstObservedAt: number;
  lastObservedAt: number;
  currentRoute: boolean;
  fresh: boolean;
  occurrences: MediaPlaybackOccurrenceEvidence[];
  webLiveReachability: MediaWebLiveReachabilityEvidenceState;
  webLiveReachabilityObservedAt: number;
  webLiveReachabilityExpiresAt: number;
  ambiguityReasons: string[];
}

export interface MediaSessionEvidenceProjection {
  scope: MediaEvidenceScope;
  revision: number;
  targets: MediaSessionPlaybackTargetEvidence[];
  unattachedOccurrences: MediaPlaybackOccurrenceEvidence[];
}

/**
 * Temporary compatibility reader for the parity slice.
 * The returned snapshot is a projection, not the graph's raw topology.
 */
export interface MediaEvidenceCompatibilityReader {
  readonly scope: MediaEvidenceScope;
  projectResourceSnapshot(): MediaDiscoveryTabSnapshot;
  listValidationTargets(now: number): MediaCandidate[];
  projectSessionEvidence(now: number): MediaSessionEvidenceProjection;
  projectProfileSelectorEvidence(): MediaCompatibilitySelectorEvidenceObservation[];
}

export interface MediaEvidenceGenerationIngress {
  readonly generationId: MediaEvidenceGenerationId;
  currentScope(): MediaEvidenceScope;
  advanceRouteEpoch(input: MediaRouteEpochAdvance): MediaEvidenceScope;
  observe(input: MediaEvidenceObservationBatch): MediaEvidenceCommitReceipt;
  markValidationInProgress(
    scope: MediaEvidenceScope,
    candidateId: string,
    fingerprint: string,
    now: number
  ): boolean;
  applyValidationResult(scope: MediaEvidenceScope, result: MediaCandidateValidationResult): boolean;
  compatibilityReader(): MediaEvidenceCompatibilityReader;
  close(input: MediaEvidenceGenerationClose): void;
}

export interface MediaEvidenceGraphReader {
  reader(scope: MediaEvidenceScope): MediaEvidenceCompatibilityReader;
}

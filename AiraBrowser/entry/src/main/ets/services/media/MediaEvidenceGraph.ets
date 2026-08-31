import { MediaCandidateValidationResult } from '../../features/mediaDiscovery/MediaCandidateValidationModels';
import {
  MediaEvidenceCommitReceipt,
  MediaEvidenceCompatibilityReader,
  MediaEvidenceGenerationClose,
  MediaEvidenceGenerationIngress,
  MediaEvidenceGenerationStart,
  MediaEvidenceGraphReader,
  MediaEvidenceObservationBatch,
  MediaEvidenceProjectionChanges,
  MediaEvidenceProducerKind,
  MediaEvidenceQuality,
  MediaEvidenceSemanticObservation,
  MediaEvidenceScope,
  MediaEvidenceGenerationId,
  MediaCompatibilitySelectorEvidenceObservation,
  MediaFrameDocumentObservation,
  MediaFrameDocumentType,
  MediaPlaybackGeometryObservation,
  MediaPlaybackObservationEvent,
  MediaPlaybackOccurrenceEvidence,
  MediaPlaybackTargetIdentityQuality,
  MediaPlaybackTargetObservation,
  MediaRouteEpochAdvance,
  MediaSanitizedLocatorEvidence,
  MediaSessionFrameDocumentClaimEvidence,
  MediaSessionFrameDocumentEvidence,
  MediaSessionEvidenceProjection,
  MediaSessionPlaybackTargetEvidence,
  MediaWebLiveReachabilityEvidenceState,
  MediaWebLiveReachabilityObservation
} from '../../features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaSignalBatch } from '../../features/mediaDiscovery/MediaSignalModels';
import {
  MediaDiscoveryStore,
  MediaDiscoveryTabSnapshot
} from './MediaDiscoveryStore';
import {
  MediaEvidenceLocatorIdentity,
  MediaEvidenceLocatorIdentityService
} from './MediaEvidenceLocatorIdentityService';

const MAX_RETAINED_GENERATIONS_PER_TAB: number = 2;
const MAX_FRAME_DOCUMENTS_PER_GENERATION: number = 48;
const MAX_FRAME_DOCUMENT_CLAIMS_PER_GENERATION: number = 128;
const MAX_PLAYBACK_TARGETS_PER_GENERATION: number = 96;
const MAX_PLAYBACK_OCCURRENCES_PER_GENERATION: number = 256;
const MAX_PROFILE_SELECTOR_EVIDENCE_PER_GENERATION: number = 64;
const PLAYBACK_HEARTBEAT_WINDOW_MS: number = 5000;
const PLAYBACK_EVIDENCE_FRESHNESS_MS: number = 30000;

type MediaSanitizedLocatorState = MediaEvidenceLocatorIdentity;

interface MediaFrameDocumentClaimState {
  claimId: string;
  observedAt: number;
  routeEpochId: string;
  producer: MediaEvidenceProducerKind;
  quality: MediaEvidenceQuality;
  frameType: MediaFrameDocumentType;
  lifecycle: 'observed' | 'ended';
  documentLocator?: MediaSanitizedLocatorState;
  parentFrameDocumentKey?: string;
}

interface MediaFrameDocumentState {
  frameDocumentId: string;
  frameDocumentKey: string;
  firstObservedAt: number;
  lastObservedAt: number;
  claims: MediaFrameDocumentClaimState[];
}

interface MediaPlaybackTargetState {
  playbackTargetId: string;
  targetKey: string;
  targetIdentityQuality: MediaPlaybackTargetIdentityQuality;
  frameDocumentKeys: string[];
  elementId?: string;
  firstObservedAt: number;
  lastObservedAt: number;
  lastHeartbeatAt: number;
  webLiveReachability: 'unknown' | 'reachable' | 'unreachable';
  webLiveReachabilityObservedAt: number;
  webLiveReachabilityExpiresAt: number;
}

interface MediaPlaybackOccurrenceState {
  occurrenceId: string;
  playbackTargetId?: string;
  targetKeyHint?: string;
  event: MediaPlaybackObservationEvent;
  observedAt: number;
  routeEpochId: string;
  producer: MediaEvidenceProducerKind;
  quality: MediaEvidenceQuality;
  sourceLocators: MediaSanitizedLocatorState[];
  muted?: boolean;
  currentTimeSeconds?: number;
  durationSeconds?: number;
  geometry?: MediaPlaybackGeometryObservation;
}

interface MediaEvidenceGenerationState {
  scope: MediaEvidenceScope;
  navigationKey: string;
  pageUrl: string;
  pageTitle: string;
  closed: boolean;
  closedAt: number;
  revision: number;
  store: MediaDiscoveryStore;
  frameDocumentsByKey: Map<string, MediaFrameDocumentState>;
  playbackTargetsByKey: Map<string, MediaPlaybackTargetState>;
  playbackOccurrences: MediaPlaybackOccurrenceState[];
  profileSelectorEvidence: MediaCompatibilitySelectorEvidenceObservation[];
  frameDocumentClaimCount: number;
}

export class MediaEvidenceGraph implements MediaEvidenceGraphReader {
  private locatorIdentityService: MediaEvidenceLocatorIdentityService = new MediaEvidenceLocatorIdentityService();
  private generationsByTab: Map<string, MediaEvidenceGenerationState[]> = new Map();
  private nextGenerationSequence: number = 1;
  private nextRouteEpochSequence: number = 1;
  private nextFrameDocumentSequence: number = 1;
  private nextFrameDocumentClaimSequence: number = 1;
  private nextPlaybackTargetSequence: number = 1;
  private nextPlaybackOccurrenceSequence: number = 1;

  beginGeneration(input: MediaEvidenceGenerationStart): MediaEvidenceGenerationIngress {
    const tabId = input.tabId.trim();
    if (tabId.length <= 0) {
      throw new Error('media_evidence_graph_tab_required');
    }
    const generations = this.generationsByTab.get(tabId) ?? [];
    const current = this.findCurrentGeneration(generations);
    if (current !== undefined) {
      this.closeState(current, input.startedAt);
    }
    const generationId = this.allocateGenerationId(tabId);
    const routeEpochId = this.allocateRouteEpochId(generationId);
    const state: MediaEvidenceGenerationState = {
      scope: {
        tabId: tabId,
        generationId: generationId,
        routeEpochId: routeEpochId
      },
      navigationKey: input.navigationKey,
      pageUrl: input.pageUrl,
      pageTitle: input.pageTitle,
      closed: false,
      closedAt: 0,
      revision: 0,
      store: new MediaDiscoveryStore(),
      frameDocumentsByKey: new Map(),
      playbackTargetsByKey: new Map(),
      playbackOccurrences: [],
      profileSelectorEvidence: [],
      frameDocumentClaimCount: 0
    };
    generations.push(state);
    this.trimRetainedGenerations(generations);
    this.generationsByTab.set(tabId, generations);
    return new MediaEvidenceGenerationIngressImpl(this, state.scope);
  }

  reader(scope: MediaEvidenceScope): MediaEvidenceCompatibilityReader {
    const state = this.findGeneration(scope);
    if (state === undefined || state.closed || !this.sameScope(state.scope, scope)) {
      return new EmptyMediaEvidenceCompatibilityReader(scope);
    }
    return new MediaEvidenceCompatibilityReaderImpl(state);
  }

  closeTab(tabId: string): void {
    this.generationsByTab.delete(tabId.trim());
  }

  advanceRouteEpoch(input: MediaRouteEpochAdvance): MediaEvidenceScope {
    const state = this.findGeneration(input.currentScope);
    if (state === undefined) {
      return input.currentScope;
    }
    if (state.closed || !this.sameScope(state.scope, input.currentScope)) {
      return state.scope;
    }
    const nextScope: MediaEvidenceScope = {
      tabId: state.scope.tabId,
      generationId: state.scope.generationId,
      routeEpochId: this.allocateRouteEpochId(state.scope.generationId)
    };
    state.scope = nextScope;
    state.pageUrl = input.pageUrl;
    state.pageTitle = input.pageTitle;
    // Resource candidates are route-scoped observations. A semantic SPA transition keeps the
    // document generation alive but must not expose resources acquired for the previous route.
    state.store.clearTab(state.scope.tabId);
    // A selector observation is a route-scoped compatibility hint, not generation-wide state.
    // Keeping it after an SPA route transition would let diagnostics attribute the new route
    // to the prior route's Profile result.
    state.profileSelectorEvidence = [];
    state.revision += 1;
    return nextScope;
  }

  observe(input: MediaEvidenceObservationBatch): MediaEvidenceCommitReceipt {
    const state = this.findGeneration(input.scope);
    const semanticObservations = input.observations ?? [];
    const selectorEvidence = input.selectorEvidence ?? [];
    const inputCount = input.signals.length + semanticObservations.length + selectorEvidence.length;
    if (state === undefined) {
      return {
        disposition: 'rejected',
        scope: input.scope,
        revision: 0,
        acceptedCount: 0,
        rejectedCount: inputCount,
        changes: this.emptyChanges()
      };
    }
    if (state.closed || !this.sameScope(state.scope, input.scope)) {
      return {
        disposition: 'rejected',
        scope: input.scope,
        revision: state.revision,
        acceptedCount: 0,
        rejectedCount: inputCount,
        changes: this.emptyChanges()
      };
    }
    if (inputCount <= 0) {
      return {
        disposition: 'committed',
        scope: input.scope,
        revision: state.revision,
        acceptedCount: 0,
        rejectedCount: 0,
        changes: this.emptyChanges()
      };
    }
    let resourceSurfaceChanged = false;
    let validationWorkChanged = false;
    if (input.signals.length > 0) {
      const batch: MediaSignalBatch = {
        tabId: state.scope.tabId,
        signals: input.signals
      };
      const nextSummary = state.store.ingestSignals(batch);
      resourceSurfaceChanged = nextSummary.presentationRelevantChange;
      validationWorkChanged = nextSummary.validationRelevantChange;
    }
    const semanticAcceptedCount = this.ingestSemanticObservations(
      state,
      input.producer,
      input.observedAt,
      semanticObservations
    );
    const selectorAcceptedCount = this.ingestSelectorEvidence(state, selectorEvidence);
    state.revision += 1;
    return {
      disposition: 'committed',
      scope: input.scope,
      revision: state.revision,
      acceptedCount: input.signals.length + semanticAcceptedCount + selectorAcceptedCount,
      rejectedCount: semanticObservations.length - semanticAcceptedCount +
        selectorEvidence.length - selectorAcceptedCount,
      changes: {
        resourceSurface: resourceSurfaceChanged,
        validationWork: validationWorkChanged,
        sessionEvidence: resourceSurfaceChanged || semanticAcceptedCount > 0,
        diagnostics: true
      }
    };
  }

  markValidationInProgress(
    scope: MediaEvidenceScope,
    candidateId: string,
    fingerprint: string,
    now: number
  ): boolean {
    const state = this.findGeneration(scope);
    if (state === undefined || state.closed || !this.sameScope(state.scope, scope)) {
      return false;
    }
    return state.store.markValidationInProgress(state.scope.tabId, candidateId, fingerprint, now);
  }

  applyValidationResult(
    scope: MediaEvidenceScope,
    result: MediaCandidateValidationResult
  ): boolean {
    const state = this.findGeneration(scope);
    if (state === undefined || state.closed || !this.sameScope(state.scope, scope)) {
      return false;
    }
    if (result.tabId !== state.scope.tabId) {
      return false;
    }
    const applied = state.store.applyValidationResult(result);
    if (applied) {
      state.revision += 1;
    }
    return applied;
  }

  closeGeneration(scope: MediaEvidenceScope, input: MediaEvidenceGenerationClose): void {
    const state = this.findGeneration(scope);
    if (state !== undefined) {
      this.closeState(state, input.closedAt);
    }
  }

  private closeState(state: MediaEvidenceGenerationState, closedAt: number): void {
    if (state.closed) {
      return;
    }
    state.closed = true;
    state.closedAt = closedAt;
    state.revision += 1;
    state.store.clearTab(state.scope.tabId);
    state.frameDocumentsByKey.clear();
    state.playbackTargetsByKey.clear();
    state.playbackOccurrences = [];
    state.profileSelectorEvidence = [];
    state.frameDocumentClaimCount = 0;
  }

  private ingestSemanticObservations(
    state: MediaEvidenceGenerationState,
    producer: MediaEvidenceProducerKind,
    observedAt: number,
    observations: MediaEvidenceSemanticObservation[]
  ): number {
    let acceptedCount = 0;
    for (let i = 0; i < observations.length; i++) {
      const observation = observations[i];
      if (observation.kind === 'frame_document') {
        if (this.observeFrameDocument(state, observation, producer, observedAt)) {
          acceptedCount += 1;
        }
        continue;
      }
      if (observation.kind === 'web_live_reachability') {
        if (this.observeWebLiveReachability(state, observation, observedAt)) {
          acceptedCount += 1;
        }
        continue;
      }
      if (this.observePlaybackTarget(state, observation, producer, observedAt)) {
        acceptedCount += 1;
      }
    }
    return acceptedCount;
  }

  private ingestSelectorEvidence(
    state: MediaEvidenceGenerationState,
    evidence: MediaCompatibilitySelectorEvidenceObservation[]
  ): number {
    let acceptedCount = 0;
    for (let index = 0; index < evidence.length; index += 1) {
      const candidate = evidence[index];
      if (!this.isValidSelectorEvidence(candidate)) {
        continue;
      }
      if (this.hasEquivalentSelectorEvidence(state.profileSelectorEvidence, candidate)) {
        acceptedCount += 1;
        continue;
      }
      if (state.profileSelectorEvidence.length >= MAX_PROFILE_SELECTOR_EVIDENCE_PER_GENERATION) {
        continue;
      }
      state.profileSelectorEvidence.push({
        kind: 'profile_selector',
        profileAttribution: candidate.profileAttribution.trim(),
        evidenceKind: candidate.evidenceKind,
        mediaStructure: candidate.mediaStructure,
        attribute: candidate.attribute,
        frameScope: 'top_document',
        originScope: 'top_origin',
        matchedCount: Math.min(32, Math.max(0, Math.floor(candidate.matchedCount))),
        qualityGateMatchCount: Math.min(32, Math.max(0, Math.floor(candidate.qualityGateMatchCount))),
        attributeMatchCount: Math.min(32, Math.max(0, Math.floor(candidate.attributeMatchCount)))
      });
      acceptedCount += 1;
    }
    return acceptedCount;
  }

  private isValidSelectorEvidence(
    evidence: MediaCompatibilitySelectorEvidenceObservation
  ): boolean {
    const attribution = evidence.profileAttribution.trim();
    if (attribution.length <= 0 || attribution.length > 96 ||
      !this.isSafeAttribution(attribution)) {
      return false;
    }
    if (evidence.kind !== 'profile_selector' ||
      (evidence.evidenceKind !== 'structured' && evidence.evidenceKind !== 'heuristic') ||
      (evidence.mediaStructure !== 'video' && evidence.mediaStructure !== 'audio') ||
      (evidence.attribute !== 'presence' && evidence.attribute !== 'source' &&
        evidence.attribute !== 'poster' && evidence.attribute !== 'dimensions') ||
      evidence.frameScope !== 'top_document' || evidence.originScope !== 'top_origin') {
      return false;
    }
    return Number.isFinite(evidence.matchedCount) && Number.isFinite(evidence.qualityGateMatchCount) &&
      Number.isFinite(evidence.attributeMatchCount) && evidence.matchedCount > 0 &&
      evidence.qualityGateMatchCount > 0 && evidence.attributeMatchCount >= 0 &&
      evidence.matchedCount <= 32 && evidence.qualityGateMatchCount <= evidence.matchedCount &&
      evidence.attributeMatchCount <= evidence.qualityGateMatchCount;
  }

  private isSafeAttribution(value: string): boolean {
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const alpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      const numeric = code >= 48 && code <= 57;
      const character = value.charAt(index);
      if (!alpha && !numeric && character !== '.' && character !== '-' && character !== '_' && character !== ':') {
        return false;
      }
    }
    return true;
  }

  private hasEquivalentSelectorEvidence(
    existing: MediaCompatibilitySelectorEvidenceObservation[],
    candidate: MediaCompatibilitySelectorEvidenceObservation
  ): boolean {
    for (let index = 0; index < existing.length; index += 1) {
      const value = existing[index];
      if (value.profileAttribution === candidate.profileAttribution &&
        value.evidenceKind === candidate.evidenceKind && value.mediaStructure === candidate.mediaStructure &&
        value.attribute === candidate.attribute && value.matchedCount === candidate.matchedCount &&
        value.qualityGateMatchCount === candidate.qualityGateMatchCount &&
        value.attributeMatchCount === candidate.attributeMatchCount) {
        return true;
      }
    }
    return false;
  }

  private observeFrameDocument(
    state: MediaEvidenceGenerationState,
    observation: MediaFrameDocumentObservation,
    producer: MediaEvidenceProducerKind,
    observedAt: number
  ): boolean {
    const frameDocumentKey = this.boundedKey(observation.frameDocumentKey);
    if (frameDocumentKey.length <= 0) {
      return false;
    }
    let frameDocument = state.frameDocumentsByKey.get(frameDocumentKey);
    if (frameDocument === undefined) {
      if (state.frameDocumentsByKey.size >= MAX_FRAME_DOCUMENTS_PER_GENERATION) {
        return false;
      }
      frameDocument = {
        frameDocumentId: this.allocateFrameDocumentId(state.scope.generationId),
        frameDocumentKey: frameDocumentKey,
        firstObservedAt: observedAt,
        lastObservedAt: observedAt,
        claims: []
      };
      state.frameDocumentsByKey.set(frameDocumentKey, frameDocument);
    }
    frameDocument.lastObservedAt = Math.max(frameDocument.lastObservedAt, observedAt);
    const documentLocator = this.locatorIdentityService.resolve(observation.documentUrl);
    const parentFrameDocumentKey = this.optionalBoundedKey(observation.parentFrameDocumentKey);
    if (this.hasEquivalentFrameClaim(
      frameDocument,
      state.scope.routeEpochId,
      producer,
      observation,
      documentLocator,
      parentFrameDocumentKey
    )) {
      return true;
    }
    if (state.frameDocumentClaimCount >= MAX_FRAME_DOCUMENT_CLAIMS_PER_GENERATION) {
      return false;
    }
    const claim: MediaFrameDocumentClaimState = {
      claimId: this.allocateFrameDocumentClaimId(state.scope.generationId),
      observedAt: observedAt,
      routeEpochId: state.scope.routeEpochId,
      producer: producer,
      quality: observation.quality,
      frameType: observation.frameType,
      lifecycle: observation.lifecycle,
      documentLocator: documentLocator,
      parentFrameDocumentKey: parentFrameDocumentKey
    };
    frameDocument.claims.push(claim);
    state.frameDocumentClaimCount += 1;
    return true;
  }

  private hasEquivalentFrameClaim(
    frameDocument: MediaFrameDocumentState,
    routeEpochId: string,
    producer: MediaEvidenceProducerKind,
    observation: MediaFrameDocumentObservation,
    documentLocator: MediaSanitizedLocatorState | undefined,
    parentFrameDocumentKey: string | undefined
  ): boolean {
    for (let i = 0; i < frameDocument.claims.length; i++) {
      const claim = frameDocument.claims[i];
      if (claim.routeEpochId === routeEpochId && claim.producer === producer &&
        claim.quality === observation.quality && claim.frameType === observation.frameType &&
        claim.lifecycle === observation.lifecycle &&
        (claim.documentLocator?.identity ?? '') === (documentLocator?.identity ?? '') &&
        (claim.parentFrameDocumentKey ?? '') === (parentFrameDocumentKey ?? '')) {
        return true;
      }
    }
    return false;
  }

  private observePlaybackTarget(
    state: MediaEvidenceGenerationState,
    observation: MediaPlaybackTargetObservation,
    producer: MediaEvidenceProducerKind,
    observedAt: number
  ): boolean {
    const targetKey = this.boundedKey(observation.targetKey ?? '');
    if (observation.targetIdentityQuality === 'unattached' || targetKey.length <= 0) {
      const occurrence = this.buildPlaybackOccurrence(
        state,
        undefined,
        observation,
        producer,
        observedAt
      );
      state.playbackOccurrences.push(occurrence);
      this.trimPlaybackOccurrences(state.playbackOccurrences);
      return true;
    }
    const storageKey = observation.targetIdentityQuality + ':' + targetKey;
    let target = state.playbackTargetsByKey.get(storageKey);
    if (target === undefined) {
      if (state.playbackTargetsByKey.size >= MAX_PLAYBACK_TARGETS_PER_GENERATION) {
        return false;
      }
      target = {
        playbackTargetId: this.allocatePlaybackTargetId(state.scope.generationId),
        targetKey: targetKey,
        targetIdentityQuality: observation.targetIdentityQuality,
        frameDocumentKeys: [],
        elementId: this.optionalBoundedKey(observation.elementId),
        firstObservedAt: observedAt,
        lastObservedAt: observedAt,
        lastHeartbeatAt: 0,
        webLiveReachability: 'unknown',
        webLiveReachabilityObservedAt: 0,
        webLiveReachabilityExpiresAt: 0
      };
      state.playbackTargetsByKey.set(storageKey, target);
    }
    target.lastObservedAt = observedAt;
    if ((target.elementId ?? '').length <= 0) {
      target.elementId = this.optionalBoundedKey(observation.elementId);
    }
    const frameDocumentKey = this.optionalBoundedKey(observation.frameDocumentKey);
    if (frameDocumentKey !== undefined && target.frameDocumentKeys.indexOf(frameDocumentKey) < 0) {
      target.frameDocumentKeys.push(frameDocumentKey);
    }
    if (observation.event === 'heartbeat' &&
      observedAt - target.lastHeartbeatAt < PLAYBACK_HEARTBEAT_WINDOW_MS) {
      return true;
    }
    if (observation.event === 'heartbeat') {
      target.lastHeartbeatAt = observedAt;
    }
    const occurrence = this.buildPlaybackOccurrence(
      state,
      target.playbackTargetId,
      observation,
      producer,
      observedAt
    );
    state.playbackOccurrences.push(occurrence);
    this.trimPlaybackOccurrences(state.playbackOccurrences);
    return true;
  }

  private observeWebLiveReachability(
    state: MediaEvidenceGenerationState,
    observation: MediaWebLiveReachabilityObservation,
    observedAt: number
  ): boolean {
    const targetKey = this.boundedKey(observation.targetKey);
    const target = state.playbackTargetsByKey.get('stable:' + targetKey);
    if (target === undefined || targetKey.length <= 0 || observation.quality !== 'direct') {
      return false;
    }
    if (observation.state === 'reachable' && observation.expiresAt <= observedAt) {
      return false;
    }
    if (observation.commandProtocolVersion <= 0 || observation.restoreProtocolVersion <= 0) {
      return false;
    }
    target.webLiveReachability = observation.state;
    target.webLiveReachabilityObservedAt = observedAt;
    target.webLiveReachabilityExpiresAt = observation.state === 'reachable' ? observation.expiresAt : observedAt;
    return true;
  }

  private buildPlaybackOccurrence(
    state: MediaEvidenceGenerationState,
    playbackTargetId: string | undefined,
    observation: MediaPlaybackTargetObservation,
    producer: MediaEvidenceProducerKind,
    observedAt: number
  ): MediaPlaybackOccurrenceState {
    const occurrence: MediaPlaybackOccurrenceState = {
      occurrenceId: this.allocatePlaybackOccurrenceId(state.scope.generationId),
      playbackTargetId: playbackTargetId,
      targetKeyHint: this.optionalBoundedKey(observation.targetKey),
      event: observation.event,
      observedAt: observedAt,
      routeEpochId: state.scope.routeEpochId,
      producer: producer,
      quality: observation.quality,
      sourceLocators: this.sanitizeLocators(observation.sourceLocators),
      muted: observation.muted,
      currentTimeSeconds: observation.currentTimeSeconds,
      durationSeconds: observation.durationSeconds,
      geometry: this.copyGeometry(observation.geometry)
    };
    return occurrence;
  }

  private trimPlaybackOccurrences(occurrences: MediaPlaybackOccurrenceState[]): void {
    while (occurrences.length > MAX_PLAYBACK_OCCURRENCES_PER_GENERATION) {
      const heartbeatIndex = this.findOldestOccurrenceIndex(occurrences, 'heartbeat');
      if (heartbeatIndex >= 0) {
        occurrences.splice(heartbeatIndex, 1);
        continue;
      }
      const geometryIndex = this.findOldestOccurrenceIndex(occurrences, 'geometry_changed');
      if (geometryIndex >= 0) {
        occurrences.splice(geometryIndex, 1);
        continue;
      }
      const snapshotIndex = this.findOldestOccurrenceIndex(occurrences, 'snapshot');
      if (snapshotIndex >= 0) {
        occurrences.splice(snapshotIndex, 1);
        continue;
      }
      occurrences.shift();
    }
  }

  private findOldestOccurrenceIndex(
    occurrences: MediaPlaybackOccurrenceState[],
    event: MediaPlaybackObservationEvent
  ): number {
    for (let i = 0; i < occurrences.length; i++) {
      if (occurrences[i].event === event) {
        return i;
      }
    }
    return -1;
  }

  private copyGeometry(
    geometry: MediaPlaybackGeometryObservation | undefined
  ): MediaPlaybackGeometryObservation | undefined {
    if (geometry === undefined) {
      return undefined;
    }
    const copy: MediaPlaybackGeometryObservation = {
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
    return copy;
  }

  private sanitizeLocators(locators: string[]): MediaSanitizedLocatorState[] {
    const copies: MediaSanitizedLocatorState[] = [];
    const limit = Math.min(locators.length, 8);
    for (let i = 0; i < limit; i++) {
      const locator = this.locatorIdentityService.resolve(locators[i]);
      if (locator !== undefined && !this.containsLocatorIdentity(copies, locator.identity)) {
        copies.push(locator);
      }
    }
    return copies;
  }

  private containsLocatorIdentity(locators: MediaSanitizedLocatorState[], identity: string): boolean {
    for (let i = 0; i < locators.length; i++) {
      if (locators[i].identity === identity) {
        return true;
      }
    }
    return false;
  }

  private boundedKey(value: string): string {
    const trimmed = value.trim();
    return trimmed.length <= 256 ? trimmed : trimmed.substring(0, 256);
  }

  private optionalBoundedKey(value: string | undefined): string | undefined {
    const bounded = this.boundedKey(value ?? '');
    return bounded.length > 0 ? bounded : undefined;
  }

  private findGeneration(scope: MediaEvidenceScope): MediaEvidenceGenerationState | undefined {
    const generations = this.generationsByTab.get(scope.tabId.trim());
    if (generations === undefined) {
      return undefined;
    }
    for (let i = 0; i < generations.length; i++) {
      if (generations[i].scope.generationId === scope.generationId) {
        return generations[i];
      }
    }
    return undefined;
  }

  private findCurrentGeneration(
    generations: MediaEvidenceGenerationState[]
  ): MediaEvidenceGenerationState | undefined {
    for (let i = generations.length - 1; i >= 0; i--) {
      if (!generations[i].closed) {
        return generations[i];
      }
    }
    return undefined;
  }

  private trimRetainedGenerations(generations: MediaEvidenceGenerationState[]): void {
    while (generations.length > MAX_RETAINED_GENERATIONS_PER_TAB) {
      generations.shift();
    }
  }

  private sameScope(
    left: MediaEvidenceScope,
    right: MediaEvidenceScope
  ): boolean {
    return left.tabId === right.tabId && left.generationId === right.generationId &&
      left.routeEpochId === right.routeEpochId;
  }

  private allocateGenerationId(tabId: string): MediaEvidenceGenerationId {
    const id = tabId + ':generation:' + this.nextGenerationSequence.toString();
    this.nextGenerationSequence += 1;
    return id;
  }

  private allocateRouteEpochId(generationId: string): string {
    const id = generationId + ':route:' + this.nextRouteEpochSequence.toString();
    this.nextRouteEpochSequence += 1;
    return id;
  }

  private allocateFrameDocumentId(generationId: string): string {
    const id = generationId + ':frame:' + this.nextFrameDocumentSequence.toString();
    this.nextFrameDocumentSequence += 1;
    return id;
  }

  private allocateFrameDocumentClaimId(generationId: string): string {
    const id = generationId + ':frame-claim:' + this.nextFrameDocumentClaimSequence.toString();
    this.nextFrameDocumentClaimSequence += 1;
    return id;
  }

  private allocatePlaybackTargetId(generationId: string): string {
    const id = generationId + ':target:' + this.nextPlaybackTargetSequence.toString();
    this.nextPlaybackTargetSequence += 1;
    return id;
  }

  private allocatePlaybackOccurrenceId(generationId: string): string {
    const id = generationId + ':occurrence:' + this.nextPlaybackOccurrenceSequence.toString();
    this.nextPlaybackOccurrenceSequence += 1;
    return id;
  }

  private emptyChanges(): MediaEvidenceProjectionChanges {
    return {
      resourceSurface: false,
      validationWork: false,
      sessionEvidence: false,
      diagnostics: false
    };
  }
}

class MediaEvidenceGenerationIngressImpl implements MediaEvidenceGenerationIngress {
  readonly generationId: MediaEvidenceGenerationId;
  private graph: MediaEvidenceGraph;
  private scope: MediaEvidenceScope;

  constructor(graph: MediaEvidenceGraph, scope: MediaEvidenceScope) {
    this.graph = graph;
    this.scope = scope;
    this.generationId = scope.generationId;
  }

  currentScope(): MediaEvidenceScope {
    return this.scope;
  }

  advanceRouteEpoch(input: MediaRouteEpochAdvance): MediaEvidenceScope {
    if (input.currentScope.tabId !== this.scope.tabId ||
      input.currentScope.generationId !== this.generationId) {
      return this.scope;
    }
    const nextScope = this.graph.advanceRouteEpoch(input);
    this.scope = nextScope;
    return nextScope;
  }

  observe(input: MediaEvidenceObservationBatch): MediaEvidenceCommitReceipt {
    if (input.scope.tabId !== this.scope.tabId || input.scope.generationId !== this.generationId) {
      return this.rejectedReceipt(input.signals.length + (input.observations?.length ?? 0) +
        (input.selectorEvidence?.length ?? 0));
    }
    return this.graph.observe(input);
  }

  private rejectedReceipt(rejectedCount: number): MediaEvidenceCommitReceipt {
    return {
      disposition: 'rejected',
      scope: this.scope,
      revision: 0,
      acceptedCount: 0,
      rejectedCount: rejectedCount,
      changes: {
        resourceSurface: false,
        validationWork: false,
        sessionEvidence: false,
        diagnostics: false
      }
    };
  }

  markValidationInProgress(
    scope: MediaEvidenceScope,
    candidateId: string,
    fingerprint: string,
    now: number
  ): boolean {
    if (scope.tabId !== this.scope.tabId || scope.generationId !== this.generationId) {
      return false;
    }
    return this.graph.markValidationInProgress(scope, candidateId, fingerprint, now);
  }

  applyValidationResult(scope: MediaEvidenceScope, result: MediaCandidateValidationResult): boolean {
    if (scope.tabId !== this.scope.tabId || scope.generationId !== this.generationId) {
      return false;
    }
    return this.graph.applyValidationResult(scope, result);
  }

  compatibilityReader(): MediaEvidenceCompatibilityReader {
    return this.graph.reader(this.scope);
  }

  close(input: MediaEvidenceGenerationClose): void {
    this.graph.closeGeneration(this.scope, input);
  }
}

class MediaEvidenceCompatibilityReaderImpl implements MediaEvidenceCompatibilityReader {
  readonly scope: MediaEvidenceScope;
  private state: MediaEvidenceGenerationState;

  constructor(state: MediaEvidenceGenerationState) {
    this.state = state;
    this.scope = state.scope;
  }

  projectResourceSnapshot(): MediaDiscoveryTabSnapshot {
    return this.state.store.getTabSnapshot(this.state.scope.tabId);
  }

  listValidationTargets(now: number) {
    return this.state.store.listValidationTargets(this.state.scope.tabId, now);
  }

  projectSessionEvidence(now: number): MediaSessionEvidenceProjection {
    const targets: MediaSessionPlaybackTargetEvidence[] = [];
    this.state.playbackTargetsByKey.forEach((target: MediaPlaybackTargetState): void => {
      const occurrences = this.buildTargetOccurrences(target.playbackTargetId);
      const frameDocuments = this.buildFrameDocuments(target.frameDocumentKeys);
      const currentRoute = this.hasCurrentRouteOccurrence(occurrences);
      const fresh = now - target.lastObservedAt <= PLAYBACK_EVIDENCE_FRESHNESS_MS;
      const webLiveReachability = this.resolveWebLiveReachability(target, frameDocuments, now);
      const ambiguityReasons = this.buildAmbiguityReasons(
        target,
        frameDocuments,
        occurrences,
        fresh,
        webLiveReachability
      );
      const targetEvidence: MediaSessionPlaybackTargetEvidence = {
        playbackTargetId: target.playbackTargetId,
        targetKey: target.targetKey,
        targetIdentityQuality: target.targetIdentityQuality,
        frameDocuments: frameDocuments,
        elementId: target.elementId,
        firstObservedAt: target.firstObservedAt,
        lastObservedAt: target.lastObservedAt,
        currentRoute: currentRoute,
        fresh: fresh,
        occurrences: occurrences,
        webLiveReachability: webLiveReachability,
        webLiveReachabilityObservedAt: target.webLiveReachabilityObservedAt,
        webLiveReachabilityExpiresAt: target.webLiveReachabilityExpiresAt,
        ambiguityReasons: ambiguityReasons
      };
      targets.push(targetEvidence);
    });
    const projection: MediaSessionEvidenceProjection = {
      scope: this.state.scope,
      revision: this.state.revision,
      targets: targets,
      unattachedOccurrences: this.buildUnattachedOccurrences()
    };
    return projection;
  }

  projectProfileSelectorEvidence(): MediaCompatibilitySelectorEvidenceObservation[] {
    return this.state.profileSelectorEvidence.map(
      (evidence: MediaCompatibilitySelectorEvidenceObservation): MediaCompatibilitySelectorEvidenceObservation => ({
        kind: 'profile_selector',
        profileAttribution: evidence.profileAttribution,
        evidenceKind: evidence.evidenceKind,
        mediaStructure: evidence.mediaStructure,
        attribute: evidence.attribute,
        frameScope: evidence.frameScope,
        originScope: evidence.originScope,
        matchedCount: evidence.matchedCount,
        qualityGateMatchCount: evidence.qualityGateMatchCount,
        attributeMatchCount: evidence.attributeMatchCount
      })
    );
  }

  private resolveWebLiveReachability(
    target: MediaPlaybackTargetState,
    frameDocuments: MediaSessionFrameDocumentEvidence[],
    now: number
  ): MediaWebLiveReachabilityEvidenceState {
    if (target.webLiveReachability === 'unknown') {
      return 'unknown';
    }
    if (target.webLiveReachability === 'unreachable') {
      return 'unreachable';
    }
    for (let i = 0; i < frameDocuments.length; i++) {
      if (frameDocuments[i].hasEndedClaim) {
        return 'expired';
      }
    }
    if (target.webLiveReachabilityExpiresAt <= now) {
      return 'expired';
    }
    return 'reachable';
  }

  private buildTargetOccurrences(playbackTargetId: string): MediaPlaybackOccurrenceEvidence[] {
    const occurrences: MediaPlaybackOccurrenceEvidence[] = [];
    for (let i = 0; i < this.state.playbackOccurrences.length; i++) {
      const occurrence = this.state.playbackOccurrences[i];
      if (occurrence.playbackTargetId !== playbackTargetId) {
        continue;
      }
      occurrences.push(this.buildOccurrenceEvidence(occurrence));
    }
    return occurrences;
  }

  private buildUnattachedOccurrences(): MediaPlaybackOccurrenceEvidence[] {
    const occurrences: MediaPlaybackOccurrenceEvidence[] = [];
    for (let i = 0; i < this.state.playbackOccurrences.length; i++) {
      const occurrence = this.state.playbackOccurrences[i];
      if (occurrence.playbackTargetId !== undefined) {
        continue;
      }
      occurrences.push(this.buildOccurrenceEvidence(occurrence));
    }
    return occurrences;
  }

  private buildOccurrenceEvidence(
    occurrence: MediaPlaybackOccurrenceState
  ): MediaPlaybackOccurrenceEvidence {
    const evidence: MediaPlaybackOccurrenceEvidence = {
      occurrenceId: occurrence.occurrenceId,
      targetKeyHint: occurrence.targetKeyHint,
      event: occurrence.event,
      observedAt: occurrence.observedAt,
      routeEpochId: occurrence.routeEpochId,
      currentRoute: occurrence.routeEpochId === this.state.scope.routeEpochId,
      producer: occurrence.producer,
      quality: occurrence.quality,
      sourceLocators: this.copyLocatorEvidence(occurrence.sourceLocators),
      muted: occurrence.muted,
      currentTimeSeconds: occurrence.currentTimeSeconds,
      durationSeconds: occurrence.durationSeconds,
      geometry: this.copyGeometry(occurrence.geometry)
    };
    return evidence;
  }

  private buildFrameDocuments(frameDocumentKeys: string[]): MediaSessionFrameDocumentEvidence[] {
    const frames: MediaSessionFrameDocumentEvidence[] = [];
    for (let i = 0; i < frameDocumentKeys.length; i++) {
      const frame = this.state.frameDocumentsByKey.get(frameDocumentKeys[i]);
      if (frame === undefined) {
        continue;
      }
      const claims = this.buildFrameDocumentClaims(frame.claims);
      const ambiguityReasons = this.buildFrameAmbiguityReasons(claims);
      const evidence: MediaSessionFrameDocumentEvidence = {
        frameDocumentId: frame.frameDocumentId,
        frameDocumentKey: frame.frameDocumentKey,
        claims: claims,
        currentRoute: this.hasCurrentRouteFrameClaim(claims),
        hasEndedClaim: this.hasEndedFrameClaim(claims),
        ambiguityReasons: ambiguityReasons
      };
      frames.push(evidence);
    }
    return frames;
  }

  private buildFrameDocumentClaims(
    claims: MediaFrameDocumentClaimState[]
  ): MediaSessionFrameDocumentClaimEvidence[] {
    const evidence: MediaSessionFrameDocumentClaimEvidence[] = [];
    for (let i = 0; i < claims.length; i++) {
      const claim = claims[i];
      const claimEvidence: MediaSessionFrameDocumentClaimEvidence = {
        claimId: claim.claimId,
        observedAt: claim.observedAt,
        routeEpochId: claim.routeEpochId,
        currentRoute: claim.routeEpochId === this.state.scope.routeEpochId,
        producer: claim.producer,
        quality: claim.quality,
        frameType: claim.frameType,
        lifecycle: claim.lifecycle,
        documentLocator: this.copyOptionalLocatorEvidence(claim.documentLocator),
        parentFrameDocumentKey: claim.parentFrameDocumentKey
      };
      evidence.push(claimEvidence);
    }
    return evidence;
  }

  private buildFrameAmbiguityReasons(claims: MediaSessionFrameDocumentClaimEvidence[]): string[] {
    const reasons: string[] = [];
    if (!this.hasCurrentRouteFrameClaim(claims)) {
      reasons.push('frame_route_historical_only');
    }
    let hasDirectClaim = false;
    const claimSignatures: string[] = [];
    for (let i = 0; i < claims.length; i++) {
      const claim = claims[i];
      if (claim.quality === 'direct') {
        hasDirectClaim = true;
      }
      const signature = claim.frameType + ':' + (claim.documentLocator?.identity ?? '') + ':' +
        (claim.parentFrameDocumentKey ?? '');
      if (claimSignatures.indexOf(signature) < 0) {
        claimSignatures.push(signature);
      }
    }
    if (!hasDirectClaim) {
      reasons.push('frame_identity_heuristic');
    }
    if (claimSignatures.length > 1) {
      reasons.push('competing_frame_claims');
    }
    return reasons;
  }

  private buildAmbiguityReasons(
    target: MediaPlaybackTargetState,
    frames: MediaSessionFrameDocumentEvidence[],
    occurrences: MediaPlaybackOccurrenceEvidence[],
    fresh: boolean,
    webLiveReachability: MediaWebLiveReachabilityEvidenceState
  ): string[] {
    const reasons: string[] = [];
    if (target.targetIdentityQuality !== 'stable') {
      reasons.push('target_identity_ambiguous');
    }
    if (frames.length <= 0) {
      reasons.push('frame_document_unknown');
    } else if (frames.length > 1) {
      reasons.push('frame_document_ambiguous');
    }
    if (!this.hasCurrentRouteOccurrence(occurrences)) {
      reasons.push('route_epoch_historical_only');
    }
    if (!fresh) {
      reasons.push('playback_evidence_stale');
    }
    const sourceLocators: string[] = [];
    for (let occurrenceIndex = 0; occurrenceIndex < occurrences.length; occurrenceIndex++) {
      const occurrenceLocators = occurrences[occurrenceIndex].sourceLocators;
      for (let locatorIndex = 0; locatorIndex < occurrenceLocators.length; locatorIndex++) {
        const locator = occurrenceLocators[locatorIndex].identity;
        if (sourceLocators.indexOf(locator) < 0) {
          sourceLocators.push(locator);
        }
      }
    }
    if (sourceLocators.length <= 0) {
      reasons.push('resource_identity_unknown');
    } else if (sourceLocators.length > 1) {
      reasons.push('competing_resource_locators');
    }
    if (webLiveReachability === 'unknown') {
      reasons.push('web_live_reachability_unknown');
    } else if (webLiveReachability === 'unreachable') {
      reasons.push('web_live_reachability_unreachable');
    } else if (webLiveReachability === 'expired') {
      reasons.push('web_live_reachability_expired');
    }
    return reasons;
  }

  private hasCurrentRouteOccurrence(occurrences: MediaPlaybackOccurrenceEvidence[]): boolean {
    for (let i = 0; i < occurrences.length; i++) {
      if (occurrences[i].currentRoute) {
        return true;
      }
    }
    return false;
  }

  private hasCurrentRouteFrameClaim(claims: MediaSessionFrameDocumentClaimEvidence[]): boolean {
    for (let i = 0; i < claims.length; i++) {
      if (claims[i].currentRoute) {
        return true;
      }
    }
    return false;
  }

  private hasEndedFrameClaim(claims: MediaSessionFrameDocumentClaimEvidence[]): boolean {
    for (let i = 0; i < claims.length; i++) {
      if (claims[i].lifecycle === 'ended') {
        return true;
      }
    }
    return false;
  }

  private copyLocatorEvidence(locators: MediaSanitizedLocatorState[]): MediaSanitizedLocatorEvidence[] {
    const copies: MediaSanitizedLocatorEvidence[] = [];
    for (let i = 0; i < locators.length; i++) {
      const locator = locators[i];
      const copy: MediaSanitizedLocatorEvidence = {
        identity: locator.identity,
        safeLocator: locator.safeLocator,
        hasQuery: locator.hasQuery
      };
      copies.push(copy);
    }
    return copies;
  }

  private copyOptionalLocatorEvidence(
    locator: MediaSanitizedLocatorState | undefined
  ): MediaSanitizedLocatorEvidence | undefined {
    if (locator === undefined) {
      return undefined;
    }
    const copy: MediaSanitizedLocatorEvidence = {
      identity: locator.identity,
      safeLocator: locator.safeLocator,
      hasQuery: locator.hasQuery
    };
    return copy;
  }

  private copyGeometry(
    geometry: MediaPlaybackGeometryObservation | undefined
  ): MediaPlaybackGeometryObservation | undefined {
    if (geometry === undefined) {
      return undefined;
    }
    const copy: MediaPlaybackGeometryObservation = {
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
    return copy;
  }
}

class EmptyMediaEvidenceCompatibilityReader implements MediaEvidenceCompatibilityReader {
  readonly scope: MediaEvidenceScope;

  constructor(scope: MediaEvidenceScope) {
    this.scope = scope;
  }

  projectResourceSnapshot(): MediaDiscoveryTabSnapshot {
    return {
      tabId: this.scope.tabId,
      records: []
    };
  }

  listValidationTargets(_now: number) {
    return [];
  }

  projectProfileSelectorEvidence(): MediaCompatibilitySelectorEvidenceObservation[] {
    return [];
  }

  projectSessionEvidence(_now: number): MediaSessionEvidenceProjection {
    const projection: MediaSessionEvidenceProjection = {
      scope: this.scope,
      revision: 0,
      targets: [],
      unattachedOccurrences: []
    };
    return projection;
  }
}

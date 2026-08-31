import {
  MediaEvidenceQuality,
  MediaPlaybackOccurrenceEvidence,
  MediaPlaybackObservationEvent,
  MediaSessionEvidenceProjection,
  MediaSessionPlaybackTargetEvidence,
  resolveFrameMediaDocumentKey,
  resolveMediaPlaybackTargetKeyIdentity
} from '../../features/mediaDiscovery/MediaEvidenceGraphModels';
import {
  ImmutableMediaSessionResolutionSnapshot,
  MediaResolvedPlaybackState,
  MediaResolvedPlaybackTargetBinding,
  MediaResolvedVideoAssistantSession,
  MediaSessionResolutionOutcome,
  MediaSessionResolutionReason,
  MediaSessionResolutionSnapshot
} from '../../features/mediaDiscovery/MediaSessionResolutionModels';

const MEDIA_SESSION_PLAYBACK_EVIDENCE_FRESHNESS_MS: number = 30000;

interface MediaResolvedTargetCandidate {
  session: MediaResolvedVideoAssistantSession;
  ambiguousIdentity: boolean;
}

export class MediaSessionResolutionService {
  resolve(
    evidence: MediaSessionEvidenceProjection,
    now: number,
    previous?: MediaSessionResolutionSnapshot
  ): MediaSessionResolutionSnapshot {
    const currentTargets: MediaSessionPlaybackTargetEvidence[] = this.collectCurrentTargets(evidence.targets);
    if (currentTargets.length <= 0) {
      return this.snapshot(evidence, now, 'inactive', [], undefined, ['no_current_playback_target']);
    }

    const canonicalTargets: MediaSessionPlaybackTargetEvidence[] = this.canonicalizeDirectFrameAliases(
      currentTargets,
      now
    );
    const candidates: MediaResolvedTargetCandidate[] = this.buildCandidates(
      evidence.scope.generationId,
      canonicalTargets,
      now
    );
    const sessions: MediaResolvedVideoAssistantSession[] = this.collectSessions(candidates);
    if (sessions.length <= 0) {
      return this.snapshot(evidence, now, 'inactive', [], undefined, ['no_current_playback_occurrence']);
    }

    const playingCandidates: MediaResolvedTargetCandidate[] = this.collectPlayingCandidates(candidates);
    if (playingCandidates.length <= 0) {
      return this.snapshot(evidence, now, 'inactive', sessions, undefined, ['no_current_playing_session']);
    }

    const strongestPlayingCandidates: MediaResolvedTargetCandidate[] =
      this.collectStrongestPlayingCandidates(playingCandidates);
    if (this.hasAmbiguousIdentity(strongestPlayingCandidates)) {
      return this.snapshot(evidence, now, 'ambiguous', sessions, undefined, ['target_identity_ambiguous']);
    }
    if (strongestPlayingCandidates.length > 1) {
      return this.snapshot(
        evidence,
        now,
        'ambiguous',
        sessions,
        undefined,
        ['equally_authoritative_playing_sessions']
      );
    }

    const activeSessionId: string = strongestPlayingCandidates[0].session.sessionId;
    let reason: MediaSessionResolutionReason = playingCandidates.length === 1 ?
      'single_authoritative_playing_session' : 'strongest_playing_session';
    if (this.continuesPreviousActiveSession(
      evidence,
      previous,
      strongestPlayingCandidates[0]
    )) {
      reason = 'active_session_continued';
    }
    return this.snapshot(evidence, now, 'active', sessions, activeSessionId, [reason]);
  }

  private snapshot(
    evidence: MediaSessionEvidenceProjection,
    now: number,
    outcome: MediaSessionResolutionOutcome,
    sessions: MediaResolvedVideoAssistantSession[],
    activeSessionId: string | undefined,
    reasons: MediaSessionResolutionReason[]
  ): MediaSessionResolutionSnapshot {
    return new ImmutableMediaSessionResolutionSnapshot(
      evidence.scope,
      evidence.revision,
      now,
      outcome,
      sessions,
      activeSessionId,
      reasons
    );
  }

  private buildCandidates(
    generationId: string,
    targets: MediaSessionPlaybackTargetEvidence[],
    now: number
  ): MediaResolvedTargetCandidate[] {
    const candidates: MediaResolvedTargetCandidate[] = [];
    for (let i: number = 0; i < targets.length; i += 1) {
      const occurrence: MediaPlaybackOccurrenceEvidence | undefined =
        this.resolvePlaybackOccurrence(targets[i].occurrences, now);
      if (occurrence !== undefined) {
        const timingOccurrence = this.resolveTimingOccurrence(targets[i].occurrences, now);
        const presentationOccurrence = this.resolvePresentationOccurrence(targets[i].occurrences, now);
        candidates.push({
          session: this.buildSession(
            generationId,
            targets[i],
            occurrence,
            timingOccurrence,
            presentationOccurrence
          ),
          ambiguousIdentity: targets[i].targetIdentityQuality !== 'stable'
        });
      }
    }
    return candidates;
  }

  private canonicalizeDirectFrameAliases(
    targets: MediaSessionPlaybackTargetEvidence[],
    now: number
  ): MediaSessionPlaybackTargetEvidence[] {
    const canonicalTargets: MediaSessionPlaybackTargetEvidence[] = [];
    for (let i: number = 0; i < targets.length; i += 1) {
      const target = targets[i];
      const binding = this.resolvePlaybackTargetBinding(target);
      if (target.targetIdentityQuality !== 'stable' || binding === undefined) {
        canonicalTargets.push(target);
        continue;
      }
      const frameAlias = this.resolveUniqueCurrentFrameAlias(targets, binding.runtimeId, now);
      if (frameAlias === undefined) {
        canonicalTargets.push(target);
        continue;
      }
      if (binding.transport === 'document_direct') {
        continue;
      }
      if (frameAlias.playbackTargetId === target.playbackTargetId) {
        canonicalTargets.push(this.mergeDirectAliasEvidence(target, targets, binding.runtimeId));
        continue;
      }
      canonicalTargets.push(target);
    }
    return canonicalTargets;
  }

  private resolveUniqueCurrentFrameAlias(
    targets: MediaSessionPlaybackTargetEvidence[],
    runtimeId: string,
    now: number
  ): MediaSessionPlaybackTargetEvidence | undefined {
    let matched: MediaSessionPlaybackTargetEvidence | undefined = undefined;
    for (let i: number = 0; i < targets.length; i += 1) {
      const target = targets[i];
      if (target.targetIdentityQuality !== 'stable' ||
        this.resolvePlaybackOccurrence(target.occurrences, now) === undefined) {
        continue;
      }
      const binding = this.resolvePlaybackTargetBinding(target);
      if (binding?.transport !== 'frame_proxy' || binding.runtimeId !== runtimeId) {
        continue;
      }
      if (matched !== undefined) {
        return undefined;
      }
      matched = target;
    }
    return matched;
  }

  private mergeDirectAliasEvidence(
    frameTarget: MediaSessionPlaybackTargetEvidence,
    targets: MediaSessionPlaybackTargetEvidence[],
    runtimeId: string
  ): MediaSessionPlaybackTargetEvidence {
    const occurrences: MediaPlaybackOccurrenceEvidence[] = frameTarget.occurrences.slice();
    let firstObservedAt: number = frameTarget.firstObservedAt;
    let lastObservedAt: number = frameTarget.lastObservedAt;
    let elementId: string | undefined = frameTarget.elementId;
    for (let i: number = 0; i < targets.length; i += 1) {
      const alias = targets[i];
      if (alias.playbackTargetId === frameTarget.playbackTargetId || alias.targetIdentityQuality !== 'stable') {
        continue;
      }
      const binding = this.resolvePlaybackTargetBinding(alias);
      if (binding?.transport !== 'document_direct' || binding.runtimeId !== runtimeId) {
        continue;
      }
      this.appendUniqueOccurrences(occurrences, alias.occurrences);
      firstObservedAt = Math.min(firstObservedAt, alias.firstObservedAt);
      lastObservedAt = Math.max(lastObservedAt, alias.lastObservedAt);
      if ((elementId ?? '').length <= 0 && (alias.elementId ?? '').length > 0) {
        elementId = alias.elementId;
      }
    }
    return {
      playbackTargetId: frameTarget.playbackTargetId,
      targetKey: frameTarget.targetKey,
      targetIdentityQuality: frameTarget.targetIdentityQuality,
      frameDocuments: frameTarget.frameDocuments,
      elementId: elementId,
      firstObservedAt: firstObservedAt,
      lastObservedAt: lastObservedAt,
      currentRoute: frameTarget.currentRoute,
      fresh: frameTarget.fresh,
      occurrences: occurrences,
      webLiveReachability: frameTarget.webLiveReachability,
      webLiveReachabilityObservedAt: frameTarget.webLiveReachabilityObservedAt,
      webLiveReachabilityExpiresAt: frameTarget.webLiveReachabilityExpiresAt,
      ambiguityReasons: frameTarget.ambiguityReasons
    };
  }

  private appendUniqueOccurrences(
    destination: MediaPlaybackOccurrenceEvidence[],
    source: MediaPlaybackOccurrenceEvidence[]
  ): void {
    for (let sourceIndex: number = 0; sourceIndex < source.length; sourceIndex += 1) {
      let duplicate = false;
      for (let destinationIndex: number = 0; destinationIndex < destination.length; destinationIndex += 1) {
        if (destination[destinationIndex].occurrenceId === source[sourceIndex].occurrenceId) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        destination.push(source[sourceIndex]);
      }
    }
  }

  private collectSessions(candidates: MediaResolvedTargetCandidate[]): MediaResolvedVideoAssistantSession[] {
    const sessions: MediaResolvedVideoAssistantSession[] = [];
    for (let i: number = 0; i < candidates.length; i += 1) {
      sessions.push(candidates[i].session);
    }
    return sessions;
  }

  private collectPlayingCandidates(candidates: MediaResolvedTargetCandidate[]): MediaResolvedTargetCandidate[] {
    const playingCandidates: MediaResolvedTargetCandidate[] = [];
    for (let i: number = 0; i < candidates.length; i += 1) {
      if (candidates[i].session.playbackState === 'playing') {
        playingCandidates.push(candidates[i]);
      }
    }
    return playingCandidates;
  }

  private collectStrongestPlayingCandidates(
    candidates: MediaResolvedTargetCandidate[]
  ): MediaResolvedTargetCandidate[] {
    const strongest: MediaResolvedTargetCandidate[] = [];
    let strongestRank: number = 0;
    for (let i: number = 0; i < candidates.length; i += 1) {
      const rank: number = this.qualityRank(candidates[i].session.evidenceQuality);
      if (rank > strongestRank) {
        strongest.length = 0;
        strongest.push(candidates[i]);
        strongestRank = rank;
      } else if (rank === strongestRank) {
        strongest.push(candidates[i]);
      }
    }
    return strongest;
  }

  private hasAmbiguousIdentity(candidates: MediaResolvedTargetCandidate[]): boolean {
    for (let i: number = 0; i < candidates.length; i += 1) {
      if (candidates[i].ambiguousIdentity) {
        return true;
      }
    }
    return false;
  }

  private collectCurrentTargets(targets: MediaSessionPlaybackTargetEvidence[]): MediaSessionPlaybackTargetEvidence[] {
    const currentTargets: MediaSessionPlaybackTargetEvidence[] = [];
    for (let i: number = 0; i < targets.length; i += 1) {
      if (targets[i].currentRoute && targets[i].fresh) {
        currentTargets.push(targets[i]);
      }
    }
    return currentTargets;
  }

  private resolvePlaybackOccurrence(
    occurrences: MediaPlaybackOccurrenceEvidence[],
    now: number
  ): MediaPlaybackOccurrenceEvidence | undefined {
    let stateOccurrence: MediaPlaybackOccurrenceEvidence | undefined = undefined;
    let observationOccurrence: MediaPlaybackOccurrenceEvidence | undefined = undefined;
    for (let i: number = 0; i < occurrences.length; i += 1) {
      const candidate: MediaPlaybackOccurrenceEvidence = occurrences[i];
      if (!this.isCurrentAndFresh(candidate, now)) {
        continue;
      }
      if (this.isPlaybackStateEvent(candidate.event)) {
        if (stateOccurrence === undefined || this.isStrongerOccurrence(candidate, stateOccurrence)) {
          stateOccurrence = candidate;
        }
      } else if (observationOccurrence === undefined ||
        this.isStrongerOccurrence(candidate, observationOccurrence)) {
        observationOccurrence = candidate;
      }
    }
    return stateOccurrence ?? observationOccurrence;
  }

  private isCurrentAndFresh(occurrence: MediaPlaybackOccurrenceEvidence, now: number): boolean {
    const age: number = now - occurrence.observedAt;
    return occurrence.currentRoute && age >= 0 && age <= MEDIA_SESSION_PLAYBACK_EVIDENCE_FRESHNESS_MS;
  }

  private isPlaybackStateEvent(event: MediaPlaybackObservationEvent): boolean {
    return event === 'playing' || event === 'paused' || event === 'ended' || event === 'source_changed';
  }

  private resolveTimingOccurrence(
    occurrences: MediaPlaybackOccurrenceEvidence[],
    now: number
  ): MediaPlaybackOccurrenceEvidence | undefined {
    let timingOccurrence: MediaPlaybackOccurrenceEvidence | undefined = undefined;
    for (let i: number = 0; i < occurrences.length; i += 1) {
      const candidate = occurrences[i];
      if (!this.isCurrentAndFresh(candidate, now) ||
        (candidate.currentTimeSeconds === undefined && candidate.durationSeconds === undefined)) {
        continue;
      }
      if (timingOccurrence === undefined || this.isStrongerOccurrence(candidate, timingOccurrence)) {
        timingOccurrence = candidate;
      }
    }
    return timingOccurrence;
  }

  private resolvePresentationOccurrence(
    occurrences: MediaPlaybackOccurrenceEvidence[],
    now: number
  ): MediaPlaybackOccurrenceEvidence | undefined {
    let presentationOccurrence: MediaPlaybackOccurrenceEvidence | undefined = undefined;
    for (let i: number = 0; i < occurrences.length; i += 1) {
      const candidate = occurrences[i];
      if (!this.isCurrentAndFresh(candidate, now) ||
        (candidate.geometry === undefined && candidate.muted === undefined)) {
        continue;
      }
      if (presentationOccurrence === undefined || this.isStrongerOccurrence(candidate, presentationOccurrence)) {
        presentationOccurrence = candidate;
      }
    }
    return presentationOccurrence;
  }

  private isStrongerOccurrence(
    candidate: MediaPlaybackOccurrenceEvidence,
    current: MediaPlaybackOccurrenceEvidence
  ): boolean {
    const candidateRank: number = this.qualityRank(candidate.quality);
    const currentRank: number = this.qualityRank(current.quality);
    if (candidateRank !== currentRank) {
      return candidateRank > currentRank;
    }
    return candidate.observedAt > current.observedAt;
  }

  private qualityRank(quality: MediaEvidenceQuality): number {
    if (quality === 'direct') {
      return 3;
    }
    if (quality === 'derived') {
      return 2;
    }
    return 1;
  }

  private buildSession(
    generationId: string,
    target: MediaSessionPlaybackTargetEvidence,
    occurrence: MediaPlaybackOccurrenceEvidence,
    timingOccurrence: MediaPlaybackOccurrenceEvidence | undefined,
    presentationOccurrence: MediaPlaybackOccurrenceEvidence | undefined
  ): MediaResolvedVideoAssistantSession {
    return {
      sessionId: 'video-session:' + generationId + ':' + target.playbackTargetId,
      playbackTargetId: target.playbackTargetId,
      targetKey: target.targetKey,
      playbackState: this.resolvePlaybackState(occurrence.event),
      webLiveReachability: target.webLiveReachability,
      webLiveReachabilityObservedAt: target.webLiveReachabilityObservedAt,
      webLiveReachabilityExpiresAt: target.webLiveReachabilityExpiresAt,
      evidenceQuality: occurrence.quality,
      observedAt: occurrence.observedAt,
      currentTimeSeconds: this.resolveNonNegativeTiming(
        timingOccurrence?.currentTimeSeconds ?? occurrence.currentTimeSeconds
      ),
      durationSeconds: this.resolveNonNegativeTiming(
        timingOccurrence?.durationSeconds ?? occurrence.durationSeconds
      ),
      playbackTargetBinding: this.resolvePlaybackTargetBinding(target),
      geometry: presentationOccurrence?.geometry,
      muted: presentationOccurrence?.muted
    };
  }

  private resolvePlaybackTargetBinding(
    target: MediaSessionPlaybackTargetEvidence
  ): MediaResolvedPlaybackTargetBinding | undefined {
    const identity = resolveMediaPlaybackTargetKeyIdentity(target.targetKey);
    if (identity === undefined) {
      return undefined;
    }
    if (identity.transport === 'frame_proxy' && !this.hasUniqueCurrentExecutableFrameDocument(
      target,
      resolveFrameMediaDocumentKey(identity.frameRuntimeId)
    )) {
      return undefined;
    }
    return {
      transport: identity.transport,
      runtimeId: identity.runtimeId,
      frameRuntimeId: identity.frameRuntimeId,
      elementId: target.elementId?.trim() ?? ''
    };
  }

  private hasUniqueCurrentExecutableFrameDocument(
    target: MediaSessionPlaybackTargetEvidence,
    frameDocumentKey: string
  ): boolean {
    if (target.frameDocuments.length !== 1) {
      return false;
    }
    const frameDocument = target.frameDocuments[0];
    if (frameDocument.frameDocumentKey !== frameDocumentKey || !frameDocument.currentRoute ||
      frameDocument.hasEndedClaim || frameDocument.ambiguityReasons.length > 0) {
      return false;
    }
    let currentDirectChildClaimCount: number = 0;
    for (let i: number = 0; i < frameDocument.claims.length; i += 1) {
      const claim = frameDocument.claims[i];
      if (!claim.currentRoute) {
        continue;
      }
      if (claim.quality !== 'direct' || claim.frameType !== 'child_document' || claim.lifecycle !== 'observed') {
        return false;
      }
      currentDirectChildClaimCount += 1;
    }
    return currentDirectChildClaimCount === 1;
  }

  private resolveNonNegativeTiming(value: number | undefined): number {
    return value !== undefined && Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  private resolvePlaybackState(event: MediaPlaybackObservationEvent): MediaResolvedPlaybackState {
    if (event === 'playing') {
      return 'playing';
    }
    if (event === 'paused') {
      return 'paused';
    }
    if (event === 'ended') {
      return 'ended';
    }
    if (event === 'snapshot') {
      return 'observed';
    }
    return 'unknown';
  }

  private continuesPreviousActiveSession(
    evidence: MediaSessionEvidenceProjection,
    previous: MediaSessionResolutionSnapshot | undefined,
    activeCandidate: MediaResolvedTargetCandidate
  ): boolean {
    if (activeCandidate.session.evidenceQuality !== 'direct' || previous === undefined ||
      previous.activeSessionId !== activeCandidate.session.sessionId ||
      evidence.revision <= previous.evidenceRevision) {
      return false;
    }
    const previousScope = previous.getScope();
    return previousScope.tabId === evidence.scope.tabId &&
      previousScope.generationId === evidence.scope.generationId &&
      previousScope.routeEpochId === evidence.scope.routeEpochId;
  }
}

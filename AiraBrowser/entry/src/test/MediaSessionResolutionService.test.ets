import { describe, expect, it } from '@ohos/hypium';
import {
  MediaEvidenceQuality,
  MediaFrameDocumentType,
  MediaPlaybackOccurrenceEvidence,
  MediaPlaybackObservationEvent,
  MediaSessionFrameDocumentEvidence,
  MediaSessionEvidenceProjection,
  MediaSessionPlaybackTargetEvidence
} from '../main/ets/features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaSessionResolutionService } from '../main/ets/services/media/MediaSessionResolutionService';

function occurrence(
  occurrenceId: string,
  event: MediaPlaybackObservationEvent,
  quality: MediaEvidenceQuality,
  observedAt: number,
  routeEpochId: string = 'route-1'
): MediaPlaybackOccurrenceEvidence {
  return {
    occurrenceId: occurrenceId,
    targetKeyHint: 'dom:' + occurrenceId,
    event: event,
    observedAt: observedAt,
    routeEpochId: routeEpochId,
    currentRoute: true,
    producer: quality === 'direct' ? 'playback_event' : 'dom_runtime',
    quality: quality,
    sourceLocators: []
  };
}

function target(
  playbackTargetId: string,
  occurrences: MediaPlaybackOccurrenceEvidence[]
): MediaSessionPlaybackTargetEvidence {
  return {
    playbackTargetId: playbackTargetId,
    targetKey: 'target:' + playbackTargetId,
    targetIdentityQuality: 'stable',
    frameDocuments: [],
    elementId: playbackTargetId,
    firstObservedAt: occurrences[0]?.observedAt ?? 0,
    lastObservedAt: occurrences[occurrences.length - 1]?.observedAt ?? 0,
    currentRoute: true,
    fresh: true,
    occurrences: occurrences,
    webLiveReachability: 'unknown',
    webLiveReachabilityObservedAt: 0,
    webLiveReachabilityExpiresAt: 0,
    ambiguityReasons: []
  };
}

function evidence(targets: MediaSessionPlaybackTargetEvidence[]): MediaSessionEvidenceProjection {
  return {
    scope: {
      tabId: 'tab-video-1',
      generationId: 'generation-1',
      routeEpochId: 'route-1'
    },
    revision: 7,
    targets: targets,
    unattachedOccurrences: []
  };
}

function evidenceAtRevision(
  targets: MediaSessionPlaybackTargetEvidence[],
  revision: number,
  tabId: string = 'tab-video-1',
  generationId: string = 'generation-1',
  routeEpochId: string = 'route-1'
): MediaSessionEvidenceProjection {
  return {
    scope: {
      tabId: tabId,
      generationId: generationId,
      routeEpochId: routeEpochId
    },
    revision: revision,
    targets: targets,
    unattachedOccurrences: []
  };
}

function childFrame(
  frameDocumentKey: string,
  frameType: MediaFrameDocumentType,
  safeDocumentLocator: string = ''
): MediaSessionFrameDocumentEvidence {
  return {
    frameDocumentId: 'frame-document:' + frameDocumentKey,
    frameDocumentKey: frameDocumentKey,
    claims: [{
      claimId: 'claim:' + frameDocumentKey,
      observedAt: 800,
      routeEpochId: 'route-1',
      currentRoute: true,
      producer: 'dom_runtime',
      quality: 'direct',
      frameType: frameType,
      lifecycle: 'observed',
      documentLocator: safeDocumentLocator.length > 0 ? {
        identity: 'document:' + frameDocumentKey,
        safeLocator: safeDocumentLocator,
        hasQuery: false
      } : undefined
    }],
    currentRoute: true,
    hasEndedClaim: false,
    ambiguityReasons: []
  };
}

export default function mediaSessionResolutionServiceTest(): void {
  describe('MediaSessionResolutionService', () => {
    it('publishes no Active Session when current evidence has no playback target', 0, () => {
      const service = new MediaSessionResolutionService();

      const snapshot = service.resolve(evidence([]), 1000);

      expect(snapshot.getScope().generationId).assertEqual('generation-1');
      expect(snapshot.getScope().routeEpochId).assertEqual('route-1');
      expect(snapshot.evidenceRevision).assertEqual(7);
      expect(snapshot.getSessions().length).assertEqual(0);
      expect(snapshot.activeSessionId).assertUndefined();
      expect(snapshot.outcome).assertEqual('inactive');
      expect(snapshot.getReasons().length).assertEqual(1);
      expect(snapshot.getReasons()[0]).assertEqual('no_current_playback_target');
    });

    it('selects the only current directly playing Session as Active', 0, () => {
      const service = new MediaSessionResolutionService();
      const playingTarget = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);

      const snapshot = service.resolve(evidence([playingTarget]), 1000);
      const sessions = snapshot.getSessions();

      expect(snapshot.outcome).assertEqual('active');
      expect(sessions.length).assertEqual(1);
      expect(snapshot.activeSessionId).assertEqual(sessions[0].sessionId);
      expect(sessions[0].playbackTargetId).assertEqual('video-main');
      expect(sessions[0].playbackState).assertEqual('playing');
      expect(sessions[0].webLiveReachability).assertEqual('unknown');
      expect(sessions[0].evidenceQuality).assertEqual('direct');
      expect(snapshot.getReasons()[0]).assertEqual('single_authoritative_playing_session');
    });

    it('projects the executable direct-target facts without granting Takeover Route authority', 0, () => {
      const service = new MediaSessionResolutionService();
      const playing = occurrence('playing-main', 'playing', 'direct', 900);
      playing.muted = true;
      playing.geometry = {
        x: 24,
        y: 80,
        width: 640,
        height: 360,
        viewportWidth: 720,
        viewportHeight: 1280,
        visible: true,
        videoWidth: 1920,
        videoHeight: 1080
      };
      const directTarget = target('video-main', [playing]);
      directTarget.targetKey = 'dom:runtime-main';
      directTarget.elementId = 'video-element-main';
      directTarget.webLiveReachability = 'reachable';
      directTarget.webLiveReachabilityObservedAt = 910;
      directTarget.webLiveReachabilityExpiresAt = 20910;

      const session = service.resolve(evidence([directTarget]), 1000).getSessions()[0];

      expect(session.playbackTargetBinding?.transport).assertEqual('document_direct');
      expect(session.playbackTargetBinding?.runtimeId).assertEqual('runtime-main');
      expect(session.playbackTargetBinding?.frameRuntimeId).assertEqual('');
      expect(session.playbackTargetBinding?.elementId).assertEqual('video-element-main');
      expect(session.geometry?.visible).assertTrue();
      expect(session.geometry?.x).assertEqual(24);
      expect(session.geometry?.viewportHeight).assertEqual(1280);
      expect(session.muted).assertTrue();
      expect(session.webLiveReachabilityExpiresAt).assertEqual(20910);
    });

    it('projects a child-frame playback binding without granting Takeover Route authority', 0, () => {
      const service = new MediaSessionResolutionService();
      const frameTarget = target('video-frame', [
        occurrence('playing-frame', 'playing', 'direct', 900)
      ]);
      frameTarget.targetKey = 'frame:frame:runtime-1:video:frame:runtime-1:video:0';
      frameTarget.elementId = 'video-element-frame';
      frameTarget.frameDocuments = [childFrame('frame:frame:runtime-1', 'child_document')];

      const session = service.resolve(evidence([frameTarget]), 1000).getSessions()[0];

      expect(session.playbackTargetBinding?.transport).assertEqual('frame_proxy');
      expect(session.playbackTargetBinding?.runtimeId).assertEqual('frame:runtime-1:video:0');
      expect(session.playbackTargetBinding?.frameRuntimeId).assertEqual('frame:runtime-1');
      expect(session.playbackTargetBinding?.elementId).assertEqual('video-element-frame');
    });

    it('publishes ambiguity when two current directly playing Sessions compete', 0, () => {
      const service = new MediaSessionResolutionService();
      const first = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      const second = target('video-ad', [occurrence('playing-ad', 'playing', 'direct', 920)]);

      const snapshot = service.resolve(evidence([first, second]), 1000);

      expect(snapshot.outcome).assertEqual('ambiguous');
      expect(snapshot.getSessions().length).assertEqual(2);
      expect(snapshot.activeSessionId).assertUndefined();
      expect(snapshot.getReasons()[0]).assertEqual('equally_authoritative_playing_sessions');
    });

    it('keeps a direct playing Session Active against a heuristic competitor', 0, () => {
      const service = new MediaSessionResolutionService();
      const direct = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      const heuristic = target('video-ad', [occurrence('playing-ad', 'playing', 'heuristic', 950)]);

      const snapshot = service.resolve(evidence([direct, heuristic]), 1000);

      expect(snapshot.outcome).assertEqual('active');
      expect(snapshot.getSessions().length).assertEqual(2);
      expect(snapshot.activeSessionId).assertEqual(snapshot.getSessions()[0].sessionId);
      expect(snapshot.getReasons()[0]).assertEqual('strongest_playing_session');
    });

    it('ignores a playback target that lost current route authority', 0, () => {
      const service = new MediaSessionResolutionService();
      const staleRouteTarget = target('video-old-route', [
        occurrence('playing-old-route', 'playing', 'direct', 900)
      ]);
      staleRouteTarget.currentRoute = false;

      const snapshot = service.resolve(evidence([staleRouteTarget]), 1000);

      expect(snapshot.outcome).assertEqual('inactive');
      expect(snapshot.getSessions().length).assertEqual(0);
      expect(snapshot.activeSessionId).assertUndefined();
      expect(snapshot.getReasons()[0]).assertEqual('no_current_playback_target');
    });

    it('does not revive a Session from a late occurrence without route authority', 0, () => {
      const service = new MediaSessionResolutionService();
      const lateOccurrence = occurrence('playing-late', 'playing', 'direct', 900);
      lateOccurrence.currentRoute = false;
      const currentTarget = target('video-current', [lateOccurrence]);

      const snapshot = service.resolve(evidence([currentTarget]), 1000);

      expect(snapshot.outcome).assertEqual('inactive');
      expect(snapshot.getSessions().length).assertEqual(0);
      expect(snapshot.activeSessionId).assertUndefined();
      expect(snapshot.getReasons()[0]).assertEqual('no_current_playback_occurrence');
    });

    it('preserves a paused Session without making it Active', 0, () => {
      const service = new MediaSessionResolutionService();
      const pausedTarget = target('video-paused', [occurrence('paused-main', 'paused', 'direct', 900)]);

      const snapshot = service.resolve(evidence([pausedTarget]), 1000);
      const sessions = snapshot.getSessions();

      expect(snapshot.outcome).assertEqual('inactive');
      expect(sessions.length).assertEqual(1);
      expect(sessions[0].playbackState).assertEqual('paused');
      expect(snapshot.activeSessionId).assertUndefined();
      expect(snapshot.getReasons()[0]).assertEqual('no_current_playing_session');
    });

    it('fails closed when the strongest playing target has ambiguous identity', 0, () => {
      const service = new MediaSessionResolutionService();
      const ambiguousTarget = target('video-ambiguous', [
        occurrence('playing-ambiguous', 'playing', 'direct', 900)
      ]);
      ambiguousTarget.targetIdentityQuality = 'ambiguous';
      ambiguousTarget.ambiguityReasons = ['target_key_collision'];

      const snapshot = service.resolve(evidence([ambiguousTarget]), 1000);

      expect(snapshot.outcome).assertEqual('ambiguous');
      expect(snapshot.activeSessionId).assertUndefined();
      expect(snapshot.getReasons()[0]).assertEqual('target_identity_ambiguous');
    });

    it('does not confuse projection diagnostics with target identity ambiguity', 0, () => {
      const service = new MediaSessionResolutionService();
      const productionShapedTarget = target('video-main', [
        occurrence('playing-main', 'playing', 'direct', 900)
      ]);
      productionShapedTarget.webLiveReachability = 'expired';
      productionShapedTarget.ambiguityReasons = [
        'frame_document_unknown',
        'resource_identity_unknown',
        'web_live_reachability_expired'
      ];

      const snapshot = service.resolve(evidence([productionShapedTarget]), 1000);

      expect(snapshot.outcome).assertEqual('active');
      expect(snapshot.activeSessionId).assertEqual(snapshot.getSessions()[0].sessionId);
    });

    it('does not let heartbeat evidence manufacture a playing state', 0, () => {
      const service = new MediaSessionResolutionService();
      const heartbeatTarget = target('video-heartbeat', [
        occurrence('heartbeat-main', 'heartbeat', 'direct', 990)
      ]);

      const snapshot = service.resolve(evidence([heartbeatTarget]), 1000);

      expect(snapshot.outcome).assertEqual('inactive');
      expect(snapshot.getSessions()[0].playbackState).assertEqual('unknown');
      expect(snapshot.activeSessionId).assertUndefined();
    });

    it('keeps fresh direct playing state across newer geometry evidence', 0, () => {
      const service = new MediaSessionResolutionService();
      const playingTarget = target('video-main', [
        occurrence('playing-main', 'playing', 'direct', 900),
        occurrence('geometry-main', 'geometry_changed', 'direct', 990)
      ]);

      const snapshot = service.resolve(evidence([playingTarget]), 1000);

      expect(snapshot.outcome).assertEqual('active');
      expect(snapshot.getSessions()[0].playbackState).assertEqual('playing');
      expect(snapshot.getSessions()[0].observedAt).assertEqual(900);
    });

    it('projects newer command timing without letting a snapshot erase playing state', 0, () => {
      const service = new MediaSessionResolutionService();
      const playing = occurrence('playing-main', 'playing', 'direct', 900);
      playing.currentTimeSeconds = 12;
      playing.durationSeconds = 120;
      const commandSnapshot = occurrence('command-main', 'snapshot', 'direct', 990);
      commandSnapshot.currentTimeSeconds = 48;
      commandSnapshot.durationSeconds = 120;

      const snapshot = service.resolve(evidence([
        target('video-main', [playing, commandSnapshot])
      ]), 1000);
      const session = snapshot.getSessions()[0];

      expect(snapshot.outcome).assertEqual('active');
      expect(session.playbackState).assertEqual('playing');
      expect(session.observedAt).assertEqual(900);
      expect(session.currentTimeSeconds).assertEqual(48);
      expect(session.durationSeconds).assertEqual(120);
    });

    it('expires stale playing state even when the target has a fresh heartbeat', 0, () => {
      const service = new MediaSessionResolutionService();
      const playingTarget = target('video-main', [
        occurrence('playing-main', 'playing', 'direct', 1000),
        occurrence('heartbeat-main', 'heartbeat', 'direct', 31900)
      ]);

      const snapshot = service.resolve(evidence([playingTarget]), 32000);

      expect(snapshot.outcome).assertEqual('inactive');
      expect(snapshot.getSessions()[0].playbackState).assertEqual('unknown');
      expect(snapshot.activeSessionId).assertUndefined();
    });

    it('publishes defensive copies instead of mutable Snapshot internals', 0, () => {
      const service = new MediaSessionResolutionService();
      const playing = occurrence('playing-main', 'playing', 'direct', 900);
      playing.geometry = {
        x: 24,
        y: 80,
        width: 640,
        height: 360,
        viewportWidth: 720,
        viewportHeight: 1280,
        visible: true,
        videoWidth: 1920,
        videoHeight: 1080
      };
      const directTarget = target('video-main', [playing]);
      directTarget.targetKey = 'dom:runtime-main';
      const snapshot = service.resolve(evidence([directTarget]), 1000);

      const mutableSessions = snapshot.getSessions();
      const mutableReasons = snapshot.getReasons();
      const firstBinding = mutableSessions[0].playbackTargetBinding;
      const firstGeometry = mutableSessions[0].geometry;
      mutableSessions.length = 0;
      mutableReasons.length = 0;
      if (firstGeometry !== undefined) {
        firstGeometry.x = 999;
      }

      expect(snapshot.getSessions().length).assertEqual(1);
      expect(snapshot.getReasons().length).assertEqual(1);
      expect(snapshot.getScope().tabId).assertEqual('tab-video-1');
      expect(snapshot.getSessions()[0].playbackTargetBinding === firstBinding).assertFalse();
      expect(snapshot.getSessions()[0].geometry === firstGeometry).assertFalse();
      expect(snapshot.getSessions()[0].geometry?.x).assertEqual(24);
    });

    it('marks Active Session Continuity only across newer revisions in the same scope', 0, () => {
      const service = new MediaSessionResolutionService();
      const direct = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      const previous = service.resolve(evidenceAtRevision([direct], 7), 950);
      const weakerCompetitor = target('video-ad', [
        occurrence('playing-ad', 'playing', 'heuristic', 980)
      ]);

      const current = service.resolve(evidenceAtRevision([direct, weakerCompetitor], 8), 1000, previous);

      expect(current.outcome).assertEqual('active');
      expect(current.activeSessionId).assertEqual(previous.activeSessionId);
      expect(current.getReasons()[0]).assertEqual('active_session_continued');
    });

    it('does not claim continuity from heuristic-only playback evidence', 0, () => {
      const service = new MediaSessionResolutionService();
      const heuristic = target('video-main', [
        occurrence('playing-main', 'playing', 'heuristic', 900)
      ]);
      const previous = service.resolve(evidenceAtRevision([heuristic], 7), 950);

      const current = service.resolve(evidenceAtRevision([heuristic], 8), 1000, previous);

      expect(current.outcome).assertEqual('active');
      expect(current.activeSessionId).assertEqual(previous.activeSessionId);
      expect(current.getReasons()[0]).assertEqual('single_authoritative_playing_session');
    });

    it('does not carry Active Session Continuity across a Media Evidence Generation', 0, () => {
      const service = new MediaSessionResolutionService();
      const direct = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      const previous = service.resolve(evidenceAtRevision([direct], 7), 950);

      const current = service.resolve(
        evidenceAtRevision([direct], 8, 'tab-video-1', 'generation-2', 'route-1'),
        1000,
        previous
      );

      expect(current.outcome).assertEqual('active');
      expect(current.activeSessionId === previous.activeSessionId).assertFalse();
      expect(current.getReasons()[0]).assertEqual('single_authoritative_playing_session');
    });

    it('resolves a directly playing child-frame target without treating frame location as authority', 0, () => {
      const service = new MediaSessionResolutionService();
      const frameTarget = target('video-child-frame', [
        occurrence('playing-child-frame', 'playing', 'direct', 900)
      ]);
      frameTarget.frameDocuments = [childFrame('child-frame-1', 'child_document')];

      const snapshot = service.resolve(evidence([frameTarget]), 1000);

      expect(snapshot.outcome).assertEqual('active');
      expect(snapshot.getSessions()[0].playbackTargetId).assertEqual('video-child-frame');
    });

    it('applies the same Session authority to same-origin and cross-origin child frames', 0, () => {
      const service = new MediaSessionResolutionService();
      const sameOriginTarget = target('video-same-origin', [
        occurrence('playing-same-origin', 'playing', 'direct', 900)
      ]);
      sameOriginTarget.frameDocuments = [
        childFrame('same-origin-frame', 'child_document', 'https://page.example/frame')
      ];
      const crossOriginTarget = target('video-cross-origin', [
        occurrence('playing-cross-origin', 'playing', 'direct', 900)
      ]);
      crossOriginTarget.frameDocuments = [
        childFrame('cross-origin-frame', 'child_document', 'https://player.example/frame')
      ];

      const sameOrigin = service.resolve(evidence([sameOriginTarget]), 1000);
      const crossOrigin = service.resolve(evidence([crossOriginTarget]), 1000);

      expect(sameOrigin.outcome).assertEqual('active');
      expect(crossOrigin.outcome).assertEqual('active');
    });

    it('does not let a preload observation compete with direct playback', 0, () => {
      const service = new MediaSessionResolutionService();
      const direct = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      const preload = target('video-preload', [occurrence('snapshot-preload', 'snapshot', 'heuristic', 980)]);

      const snapshot = service.resolve(evidence([direct, preload]), 1000);

      expect(snapshot.outcome).assertEqual('active');
      expect(snapshot.activeSessionId).assertEqual(snapshot.getSessions()[0].sessionId);
      expect(snapshot.getSessions()[1].playbackState).assertEqual('observed');
    });

    it('selects only current-route playback after an SPA episode transition', 0, () => {
      const service = new MediaSessionResolutionService();
      const previousEpisode = target('video-episode-12', [
        occurrence('playing-episode-12', 'playing', 'direct', 900)
      ]);
      previousEpisode.currentRoute = false;
      const currentEpisode = target('video-episode-13', [
        occurrence('playing-episode-13', 'playing', 'direct', 980)
      ]);

      const snapshot = service.resolve(evidenceAtRevision([previousEpisode, currentEpisode], 8), 1000);

      expect(snapshot.outcome).assertEqual('active');
      expect(snapshot.getSessions().length).assertEqual(1);
      expect(snapshot.getSessions()[0].playbackTargetId).assertEqual('video-episode-13');
    });

    it('keeps Reachability outside Session Resolution authority', 0, () => {
      const service = new MediaSessionResolutionService();
      const unreachableTarget = target('video-main', [
        occurrence('playing-main', 'playing', 'direct', 900)
      ]);
      unreachableTarget.webLiveReachability = 'expired';

      const snapshot = service.resolve(evidence([unreachableTarget]), 1000);

      expect(snapshot.outcome).assertEqual('active');
      expect(snapshot.activeSessionId).assertEqual(snapshot.getSessions()[0].sessionId);
      expect(snapshot.getSessions()[0].webLiveReachability).assertEqual('expired');
    });

    it('preserves Session authority while Takeover Route reachability fails and recovers', 0, () => {
      const service = new MediaSessionResolutionService();
      const direct = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      direct.webLiveReachability = 'reachable';
      const reachable = service.resolve(evidenceAtRevision([direct], 7), 950);
      direct.webLiveReachability = 'unreachable';
      const failedRoute = service.resolve(evidenceAtRevision([direct], 8), 975, reachable);
      direct.webLiveReachability = 'reachable';

      const recoveredRoute = service.resolve(evidenceAtRevision([direct], 9), 1000, failedRoute);

      expect(failedRoute.outcome).assertEqual('active');
      expect(failedRoute.getSessions()[0].webLiveReachability).assertEqual('unreachable');
      expect(recoveredRoute.outcome).assertEqual('active');
      expect(recoveredRoute.activeSessionId).assertEqual(reachable.activeSessionId);
      expect(recoveredRoute.getSessions()[0].webLiveReachability).assertEqual('reachable');
    });

    it('does not use a previous Snapshot from another tab for continuity', 0, () => {
      const service = new MediaSessionResolutionService();
      const direct = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      const previous = service.resolve(
        evidenceAtRevision([direct], 7, 'tab-video-other', 'generation-shared', 'route-1'),
        950
      );

      const current = service.resolve(
        evidenceAtRevision([direct], 8, 'tab-video-1', 'generation-shared', 'route-1'),
        1000,
        previous
      );

      expect(current.outcome).assertEqual('active');
      expect(current.getReasons()[0]).assertEqual('single_authoritative_playing_session');
    });

    it('does not carry Active Session Continuity across a Media Route Epoch', 0, () => {
      const service = new MediaSessionResolutionService();
      const previousTarget = target('video-main', [
        occurrence('playing-main-route-1', 'playing', 'direct', 900, 'route-1')
      ]);
      const previous = service.resolve(evidenceAtRevision([previousTarget], 7), 950);
      const currentTarget = target('video-main', [
        occurrence('playing-main-route-2', 'playing', 'direct', 980, 'route-2')
      ]);

      const current = service.resolve(
        evidenceAtRevision([currentTarget], 8, 'tab-video-1', 'generation-1', 'route-2'),
        1000,
        previous
      );

      expect(current.outcome).assertEqual('active');
      expect(current.activeSessionId).assertEqual(previous.activeSessionId);
      expect(current.getReasons()[0]).assertEqual('single_authoritative_playing_session');
    });

    it('lets a newer direct pause end Active Session Continuity', 0, () => {
      const service = new MediaSessionResolutionService();
      const playing = target('video-main', [occurrence('playing-main', 'playing', 'direct', 900)]);
      const previous = service.resolve(evidenceAtRevision([playing], 7), 950);
      const paused = target('video-main', [
        occurrence('playing-main', 'playing', 'direct', 900),
        occurrence('paused-main', 'paused', 'direct', 980)
      ]);

      const current = service.resolve(evidenceAtRevision([paused], 8), 1000, previous);

      expect(current.outcome).assertEqual('inactive');
      expect(current.activeSessionId).assertUndefined();
      expect(current.getSessions()[0].playbackState).assertEqual('paused');
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  MediaPlaybackOccurrenceEvidence,
  MediaSessionEvidenceProjection,
  MediaSessionPlaybackTargetEvidence
} from '../main/ets/features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaSessionResolutionRuntimeService } from
  '../main/ets/services/media/MediaSessionResolutionRuntimeService';
import { MediaSessionResolutionService } from '../main/ets/services/media/MediaSessionResolutionService';
import { MediaSessionResolutionSnapshot } from
  '../main/ets/features/mediaDiscovery/MediaSessionResolutionModels';

class ToggleFailingMediaSessionResolutionService extends MediaSessionResolutionService {
  shouldFail: boolean = false;

  resolve(
    evidence: MediaSessionEvidenceProjection,
    now: number,
    previous?: MediaSessionResolutionSnapshot
  ): MediaSessionResolutionSnapshot {
    if (this.shouldFail) {
      throw new Error('fixture_resolution_failure');
    }
    return super.resolve(evidence, now, previous);
  }
}

function occurrence(id: string, observedAt: number): MediaPlaybackOccurrenceEvidence {
  return {
    occurrenceId: id,
    targetKeyHint: 'dom:runtime-main',
    event: 'playing',
    observedAt: observedAt,
    routeEpochId: 'route-1',
    currentRoute: true,
    producer: 'playback_event',
    quality: 'direct',
    sourceLocators: []
  };
}

function target(): MediaSessionPlaybackTargetEvidence {
  return {
    playbackTargetId: 'video-main',
    targetKey: 'dom:runtime-main',
    targetIdentityQuality: 'stable',
    frameDocuments: [],
    elementId: 'video-main',
    firstObservedAt: 900,
    lastObservedAt: 900,
    currentRoute: true,
    fresh: true,
    occurrences: [occurrence('playing-main', 900)],
    webLiveReachability: 'unknown',
    webLiveReachabilityObservedAt: 0,
    webLiveReachabilityExpiresAt: 0,
    ambiguityReasons: []
  };
}

function evidence(revision: number = 7): MediaSessionEvidenceProjection {
  return {
    scope: {
      tabId: 'tab-video-1',
      generationId: 'generation-1',
      routeEpochId: 'route-1'
    },
    revision: revision,
    targets: [target()],
    unattachedOccurrences: []
  };
}

export default function mediaSessionResolutionRuntimeServiceTest(): void {
  describe('MediaSessionResolutionRuntimeService', () => {
    it('publishes the latest immutable resolution and preserves continuity', 0, () => {
      const runtime = new MediaSessionResolutionRuntimeService();
      const first = runtime.resolve({ tabId: 'tab-video-1', evidence: evidence(7), now: 950 });
      const second = runtime.resolve({ tabId: 'tab-video-1', evidence: evidence(8), now: 1000 });

      expect(first?.outcome).assertEqual('active');
      expect(second?.getReasons()[0]).assertEqual('active_session_continued');
      expect(runtime.getSnapshot('tab-video-1')?.evidenceRevision).assertEqual(8);
    });

    it('fails closed per tab and recovers without stale continuity', 0, () => {
      const resolver = new ToggleFailingMediaSessionResolutionService();
      const runtime = new MediaSessionResolutionRuntimeService(resolver);
      runtime.resolve({ tabId: 'tab-video-1', evidence: evidence(7), now: 950 });
      resolver.shouldFail = true;

      const failed = runtime.resolve({ tabId: 'tab-video-1', evidence: evidence(8), now: 1000 });
      expect(failed).assertUndefined();
      expect(runtime.getSnapshot('tab-video-1')).assertUndefined();

      resolver.shouldFail = false;
      const recovered = runtime.resolve({ tabId: 'tab-video-1', evidence: evidence(9), now: 1050 });
      expect(recovered?.getReasons()[0]).assertEqual('single_authoritative_playing_session');

      runtime.clearTab('tab-video-1');
      expect(runtime.getSnapshot('tab-video-1')).assertUndefined();
    });
  });
}

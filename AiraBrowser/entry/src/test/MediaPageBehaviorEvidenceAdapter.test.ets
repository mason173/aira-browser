import { describe, expect, it } from '@ohos/hypium';
import { MediaPlaybackTargetObservation } from
  '../main/ets/features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaPageBehaviorEvidenceAdapter } from
  '../main/ets/services/media/MediaPageBehaviorEvidenceAdapter';

export default function mediaPageBehaviorEvidenceAdapterTest(): void {
  describe('MediaPageBehaviorEvidenceAdapter', () => {
    it('publishes a direct DOM runtime as a stable playback target', 0, () => {
      const adapter = new MediaPageBehaviorEvidenceAdapter();
      const result = adapter.adapt(
        '{"timestamp":900,"isVideoPlaying":true,"videoEvent":{' +
        '"eventName":"playing","runtimeId":"runtime-main","elementId":"video-main",' +
        '"source":"https://media.example/video.mp4","paused":false,"ended":false}}',
        1000
      );
      const observation = result.observations[0] as MediaPlaybackTargetObservation;

      expect(result.observations.length).assertEqual(1);
      expect(observation.kind).assertEqual('playback_target');
      expect(observation.targetKey).assertEqual('dom:runtime-main');
      expect(observation.targetIdentityQuality).assertEqual('stable');
      expect(observation.event).assertEqual('playing');
      expect(observation.quality).assertEqual('direct');
    });

    it('rejects a page event without a target runtime identity', 0, () => {
      const adapter = new MediaPageBehaviorEvidenceAdapter();
      const result = adapter.adapt(
        '{"timestamp":900,"videoEvent":{"eventName":"playing","elementId":"video-main"}}',
        1000
      );

      expect(result.observations.length).assertEqual(0);
    });
  });
}

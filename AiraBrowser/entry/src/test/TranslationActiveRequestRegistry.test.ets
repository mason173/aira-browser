import { describe, expect, it } from '@ohos/hypium';
import {
  TranslationActiveRequestRegistry,
  TranslationRequestHandle
} from '../main/ets/services/translation/TranslationActiveRequestRegistry';

/**
 * The registry exists because NetStack's `OS_NET_HttpWork` thread has crashed inside `multi_runsingle` and
 * `curl_multi_socket_action` on a translation handle that Aira had already destroyed. These cases pin the two
 * properties that keep a cancelled batch from doing that: abandoning a batch never destroys a handle that may
 * still be in flight, and a handle is destroyed exactly once, on the settle path.
 */

class RecordingRequest {
  destroyCount: number = 0;
}

function handleFor(recording: RecordingRequest): TranslationRequestHandle {
  return new TranslationRequestHandle((): void => {
    recording.destroyCount += 1;
  });
}

export default function translationActiveRequestRegistryTest(): void {
  describe('TranslationActiveRequestRegistry', () => {
    it('never destroys an in-flight handle when a batch is abandoned', 0, () => {
      const registry = new TranslationActiveRequestRegistry();
      const first = new RecordingRequest();
      const second = new RecordingRequest();
      registry.track(handleFor(first));
      registry.track(handleFor(second));

      registry.abandon();

      // Cancelling must not touch handles the NetStack thread may still be driving.
      expect(first.destroyCount).assertEqual(0);
      expect(second.destroyCount).assertEqual(0);
    });

    it('destroys a tracked handle exactly once when it settles', 0, () => {
      const registry = new TranslationActiveRequestRegistry();
      const recording = new RecordingRequest();
      const handle = handleFor(recording);
      registry.track(handle);

      registry.settle(handle);
      registry.settle(handle);

      expect(recording.destroyCount).assertEqual(1);
    });

    it('destroys an abandoned handle once when it settles later', 0, () => {
      const registry = new TranslationActiveRequestRegistry();
      const recording = new RecordingRequest();
      const handle = handleFor(recording);
      registry.track(handle);
      registry.abandon();

      registry.settle(handle);

      expect(recording.destroyCount).assertEqual(1);
    });

    it('destroys only the settled handle and leaves the other batch members alone', 0, () => {
      const registry = new TranslationActiveRequestRegistry();
      const first = new RecordingRequest();
      const second = new RecordingRequest();
      const firstHandle = handleFor(first);
      const secondHandle = handleFor(second);
      registry.track(firstHandle);
      registry.track(secondHandle);

      registry.settle(firstHandle);

      expect(first.destroyCount).assertEqual(1);
      expect(second.destroyCount).assertEqual(0);

      registry.settle(secondHandle);
      expect(second.destroyCount).assertEqual(1);
    });
  });
}

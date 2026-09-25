import { describe, expect, it } from '@ohos/hypium';
import { planArkWebBackgroundTimerCommand } from '../main/ets/core/browser/BrowserArkWebBackgroundTimerPolicy';
import {
  readPictureInPictureBackgroundSignal,
  WEB_VIDEO_PICTURE_IN_PICTURE_ENTER_SOURCE,
  WEB_VIDEO_PICTURE_IN_PICTURE_LEAVE_SOURCE,
  WEB_VIDEO_PICTURE_IN_PICTURE_PAGEHIDE_SOURCE
} from '../main/ets/services/video/WebVideoPictureInPictureBackgroundPolicy';

export default function webVideoPictureInPictureBackgroundPolicyTest(): void {
  describe('WebVideoPictureInPictureBackgroundPolicy', () => {
    it('keeps only an explicit picture-in-picture transition', 0, () => {
      expect(readPictureInPictureBackgroundSignal(
        JSON.stringify({ source: WEB_VIDEO_PICTURE_IN_PICTURE_ENTER_SOURCE })
      )).assertTrue();
      expect(readPictureInPictureBackgroundSignal(
        JSON.stringify({ source: WEB_VIDEO_PICTURE_IN_PICTURE_LEAVE_SOURCE })
      )).assertFalse();
      expect(readPictureInPictureBackgroundSignal(
        JSON.stringify({ source: WEB_VIDEO_PICTURE_IN_PICTURE_PAGEHIDE_SOURCE })
      )).assertFalse();
      expect(readPictureInPictureBackgroundSignal(
        JSON.stringify({ source: 'media_playing', isMediaPlaying: true, isPictureInPicture: true })
      ) === undefined).assertTrue();
      expect(readPictureInPictureBackgroundSignal('not-json') === undefined).assertTrue();
    });

    it('does not pause ArkWeb timers while picture-in-picture holds background playback', 0, () => {
      const background = planArkWebBackgroundTimerCommand(false, ['web_picture_in_picture'], false,
        'process_background');
      expect(background.processBackground).assertTrue();
      expect(background.command).assertEqual('none');

      const resumed = planArkWebBackgroundTimerCommand(true, [], true, 'hold', 'web_picture_in_picture');
      expect(resumed.holds.length).assertEqual(1);
      expect(resumed.command).assertEqual('resume');

      const released = planArkWebBackgroundTimerCommand(true, ['web_picture_in_picture'], false, 'release',
        'web_picture_in_picture');
      expect(released.holds.length).assertEqual(0);
      expect(released.command).assertEqual('pause');

      const foreground = planArkWebBackgroundTimerCommand(true, [], true, 'process_foreground');
      expect(foreground.processBackground).assertFalse();
      expect(foreground.command).assertEqual('resume');
    });
  });
}

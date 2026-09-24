import { describe, expect, it } from '@ohos/hypium';
import {
  MANUAL_FULLSCREEN_ENTER_HINT_ESCAPE,
  MANUAL_FULLSCREEN_ENTER_HINT_SYSTEM_BACK,
  isComputerFullscreenDevice,
  resolveManualFullscreenEnterHint,
  shouldExitFullscreenOnEscape
} from '../main/ets/core/browser/BrowserFullscreenExitHintPolicy';

export default function browserFullscreenExitHintPolicyTest(): void {
  describe('BrowserFullscreenExitHintPolicy', () => {
    it('treats pc and 2-in-1 devices as computers', 0, () => {
      expect(isComputerFullscreenDevice('pc')).assertTrue();
      expect(isComputerFullscreenDevice('desktop')).assertTrue();
      expect(isComputerFullscreenDevice('2in1')).assertTrue();
      expect(isComputerFullscreenDevice('two_in_one')).assertTrue();
      expect(isComputerFullscreenDevice('TWO-IN-ONE')).assertTrue();
      expect(isComputerFullscreenDevice('tablet')).assertFalse();
      expect(isComputerFullscreenDevice('phone')).assertFalse();
      expect(isComputerFullscreenDevice('default')).assertFalse();
      expect(isComputerFullscreenDevice('')).assertFalse();
    });

    it('advertises Esc only on a computer', 0, () => {
      expect(resolveManualFullscreenEnterHint('2in1')).assertEqual(MANUAL_FULLSCREEN_ENTER_HINT_ESCAPE);
      expect(resolveManualFullscreenEnterHint('pc')).assertEqual(MANUAL_FULLSCREEN_ENTER_HINT_ESCAPE);
      expect(resolveManualFullscreenEnterHint('tablet')).assertEqual(MANUAL_FULLSCREEN_ENTER_HINT_SYSTEM_BACK);
      expect(resolveManualFullscreenEnterHint('phone')).assertEqual(MANUAL_FULLSCREEN_ENTER_HINT_SYSTEM_BACK);
    });

    it('consumes a bare Esc press only while fullscreen is active', 0, () => {
      expect(shouldExitFullscreenOnEscape(true, true, true)).assertTrue();
      expect(shouldExitFullscreenOnEscape(true, true, false)).assertFalse();
      expect(shouldExitFullscreenOnEscape(true, false, true)).assertFalse();
      expect(shouldExitFullscreenOnEscape(false, true, true)).assertFalse();
    });
  });
}

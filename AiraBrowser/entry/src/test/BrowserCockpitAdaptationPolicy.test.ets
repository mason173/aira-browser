import { describe, expect, it } from '@ohos/hypium';
import {
  COCKPIT_UNREPORTED_BOTTOM_DOCK_VP,
  COCKPIT_UNREPORTED_TOP_STATUS_BAR_VP,
  resolveCockpitAdaptation
} from '../main/ets/core/browser/BrowserCockpitAdaptationPolicy';
import { COCKPIT_MIN_HIT_TARGET_VP } from '../main/ets/core/browser/BrowserCockpitWindowSpanPolicy';

export default function browserCockpitAdaptationPolicyTest(): void {
  describe('BrowserCockpitAdaptationPolicy', () => {
    it('does not treat a wide phone, tablet, or PC as a cockpit', 0, () => {
      const phone = resolveCockpitAdaptation({
        detectedFormFactor: 'phone',
        windowWidthVp: 1920,
        reportedBottomAvoidVp: 0
      });
      const tablet = resolveCockpitAdaptation({
        detectedFormFactor: 'tablet',
        windowWidthVp: 1280,
        reportedBottomAvoidVp: 28
      });
      const pc = resolveCockpitAdaptation({
        detectedFormFactor: 'pc',
        windowWidthVp: 1440,
        reportedBottomAvoidVp: 0
      });

      expect(phone.active).assertFalse();
      expect(phone.contentTopInsetVp).assertEqual(0);
      expect(phone.floatingChromeBottomLiftVp).assertEqual(0);
      expect(phone.enableFloatNavigationAvoidArea).assertFalse();
      expect(phone.decisionReason).assertEqual('not-cockpit');
      expect(tablet.floatingChromeBottomLiftVp).assertEqual(0);
      expect(pc.floatingChromeBottomLiftVp).assertEqual(0);
    });

    it('keeps cockpit floating chrome above the dock floor, and follows a taller avoid area', 0, () => {
      const unreported = resolveCockpitAdaptation({
        detectedFormFactor: 'car',
        windowWidthVp: 1260,
        reportedBottomAvoidVp: 0
      });
      const partial = resolveCockpitAdaptation({
        detectedFormFactor: 'car',
        windowWidthVp: 480,
        reportedBottomAvoidVp: 20
      });
      const taller = resolveCockpitAdaptation({
        detectedFormFactor: 'car',
        windowWidthVp: 840,
        reportedBottomAvoidVp: 120.2
      });

      expect(unreported.active).assertTrue();
      expect(unreported.span).assertEqual('full');
      expect(unreported.floatingChromeBottomLiftVp).assertEqual(COCKPIT_UNREPORTED_BOTTOM_DOCK_VP);
      expect(unreported.hitTargetFloorVp).assertEqual(COCKPIT_MIN_HIT_TARGET_VP);
      expect(unreported.enableFloatNavigationAvoidArea).assertTrue();
      expect(unreported.decisionReason).assertEqual('dock-floor');
      expect(partial.span).assertEqual('third');
      expect(partial.floatingChromeBottomLiftVp).assertEqual(COCKPIT_UNREPORTED_BOTTOM_DOCK_VP);
      expect(partial.decisionReason).assertEqual('dock-floor');
      expect(taller.floatingChromeBottomLiftVp).assertEqual(121);
      expect(taller.decisionReason).assertEqual('system-avoid-area');
    });

    it('keeps cockpit content below the visible status bar, and follows a taller top avoid area', 0, () => {
      const unreported = resolveCockpitAdaptation({
        detectedFormFactor: 'car',
        windowWidthVp: 1260,
        reportedBottomAvoidVp: 0,
        reportedTopAvoidVp: 0
      });
      const partial = resolveCockpitAdaptation({
        detectedFormFactor: 'car',
        windowWidthVp: 1260,
        reportedBottomAvoidVp: 48,
        reportedTopAvoidVp: 20
      });
      const taller = resolveCockpitAdaptation({
        detectedFormFactor: 'car',
        windowWidthVp: 1260,
        reportedBottomAvoidVp: 48,
        reportedTopAvoidVp: 64.2
      });

      expect(unreported.contentTopInsetVp).assertEqual(COCKPIT_UNREPORTED_TOP_STATUS_BAR_VP);
      expect(partial.contentTopInsetVp).assertEqual(COCKPIT_UNREPORTED_TOP_STATUS_BAR_VP);
      expect(taller.contentTopInsetVp).assertEqual(65);
    });
  });
}

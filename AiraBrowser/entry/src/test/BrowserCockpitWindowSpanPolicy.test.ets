import { describe, expect, it } from '@ohos/hypium';
import {
  COCKPIT_MIN_HIT_TARGET_VP,
  resolveCockpitHitTargetVp,
  resolveCockpitShellFamily,
  resolveCockpitWindowSpan
} from '../main/ets/core/browser/BrowserCockpitWindowSpanPolicy';
import { BrowserDeviceFormFactorCoordinator } from '../main/ets/core/browser/BrowserDeviceFormFactorCoordinator';
import { BrowserTabletInterfaceModePolicy } from '../main/ets/core/browser/BrowserTabletInterfaceModePolicy';
import {
  BrowserShellFamilyAvailability,
  BrowserWindowPresentationProfileCoordinator
} from '../main/ets/core/browser/BrowserWindowPresentationProfile';

export default function browserCockpitWindowSpanPolicyTest(): void {
  describe('BrowserCockpitWindowSpanPolicy', () => {
    it('maps cockpit window width onto the seat full, two-thirds, and one-third spans', 0, () => {
      expect(resolveCockpitWindowSpan(undefined)).assertEqual('full');
      expect(resolveCockpitWindowSpan(0)).assertEqual('full');
      expect(resolveCockpitWindowSpan(480)).assertEqual('third');
      expect(resolveCockpitWindowSpan(599)).assertEqual('third');
      expect(resolveCockpitWindowSpan(600)).assertEqual('two_thirds');
      expect(resolveCockpitWindowSpan(839)).assertEqual('two_thirds');
      expect(resolveCockpitWindowSpan(840)).assertEqual('full');
      expect(resolveCockpitShellFamily()).assertEqual('phone');
    });

    it('keeps a cockpit hit at least the 10.7mm floor', 0, () => {
      expect(resolveCockpitHitTargetVp(40)).assertEqual(COCKPIT_MIN_HIT_TARGET_VP);
      expect(resolveCockpitHitTargetVp(80)).assertEqual(80);
    });

    it('recognizes a native car and never treats the wide center display as a PC', 0, () => {
      const coordinator = new BrowserDeviceFormFactorCoordinator();

      const unmeasured = coordinator.resolveShellEligibility({
        platformDeviceType: 'car',
        windowWidthVp: 0
      });
      const wide = coordinator.resolveShellEligibility({
        platformDeviceType: 'car',
        windowWidthVp: 1920
      });
      const split = coordinator.resolveShellEligibility({
        platformDeviceType: 'cockpit',
        windowWidthVp: 420
      });

      expect(unmeasured.detectedFormFactor).assertEqual('car');
      expect(unmeasured.huaweiPcUiEligible).assertFalse();
      expect(wide.huaweiPcUiEligible).assertFalse();
      expect(split.detectedFormFactor).assertEqual('car');
      expect(split.huaweiPcUiEligible).assertFalse();
    });

    it('locks every cockpit window to the touch shell and ignores a synced desktop preference', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();
      const availability: BrowserShellFamilyAvailability = {
        phoneShellAvailable: true,
        largeScreenShellAvailable: true
      };
      const presentation = new BrowserWindowPresentationProfileCoordinator();

      const third = policy.resolve({
        detectedFormFactor: 'car',
        selectedMode: 'desktop',
        pointerAvailable: true,
        windowWidthVp: 480
      });
      const full = policy.resolve({
        detectedFormFactor: 'car',
        selectedMode: 'touch',
        pointerAvailable: false,
        windowWidthVp: 1280
      });
      const profile = presentation.reconcile({
        platformDeviceType: 'car',
        windowWidthVp: 1280,
        windowHeightVp: 720,
        pointerAvailable: false,
        tabletInterfaceMode: 'touch'
      }, availability, 1);

      expect(third.settingVisible).assertFalse();
      expect(third.shellFamily).assertEqual('phone');
      expect(third.decisionReason).assertEqual('car-touch-locked');
      expect(full.shellFamily).assertEqual('phone');
      expect(full.decisionReason).assertEqual('car-touch-locked');
      expect(profile.detectedFormFactor).assertEqual('car');
      expect(profile.shellFamily).assertEqual('phone');
      expect(profile.uiMode).assertEqual('phone_ui');
      expect(profile.familyLocked).assertTrue();
      expect(profile.decisionReason).assertEqual('car-touch-locked');
    });
  });
}

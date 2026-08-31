import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserShellFamilyAvailability,
  BrowserWindowPresentationProfileCoordinator
} from '../main/ets/core/browser/BrowserWindowPresentationProfile';
import { BrowserTabletInterfaceModePolicy } from '../main/ets/core/browser/BrowserTabletInterfaceModePolicy';

export default function browserTabletInterfaceModePolicyTest(): void {
  describe('BrowserTabletInterfaceModePolicy', () => {
    it('lets phones expose interface mode and choose desktop UI explicitly', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const autoDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false
      });
      const desktopDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'desktop',
        pointerAvailable: false
      });
      const pointerAutoDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: true
      });

      expect(autoDecision.settingVisible).assertTrue();
      expect(autoDecision.shellFamily).assertEqual('phone');
      expect(pointerAutoDecision.settingVisible).assertTrue();
      expect(pointerAutoDecision.shellFamily).assertEqual('phone');
      expect(pointerAutoDecision.decisionReason).assertEqual('phone-auto-touch');
      expect(desktopDecision.settingVisible).assertTrue();
      expect(desktopDecision.shellFamily).assertEqual('large_screen');
      expect(desktopDecision.decisionReason).assertEqual('phone-desktop-override');
    });

    it('keeps computer-class devices locked to desktop UI without a setting entry', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const pcDecision = policy.resolve({
        detectedFormFactor: 'pc',
        selectedMode: 'touch',
        pointerAvailable: false
      });
      const twoInOneDecision = policy.resolve({
        detectedFormFactor: 'two_in_one',
        selectedMode: 'touch',
        pointerAvailable: false
      });

      expect(pcDecision.settingVisible).assertFalse();
      expect(pcDecision.shellFamily).assertEqual('large_screen');
      expect(twoInOneDecision.settingVisible).assertFalse();
      expect(twoInOneDecision.shellFamily).assertEqual('large_screen');
    });

    it('preserves tablet automatic pointer behavior', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const touchDecision = policy.resolve({
        detectedFormFactor: 'tablet',
        selectedMode: 'auto',
        pointerAvailable: false
      });
      const pointerDecision = policy.resolve({
        detectedFormFactor: 'tablet',
        selectedMode: 'auto',
        pointerAvailable: true
      });

      expect(touchDecision.settingVisible).assertTrue();
      expect(touchDecision.shellFamily).assertEqual('phone');
      expect(pointerDecision.settingVisible).assertTrue();
      expect(pointerDecision.shellFamily).assertEqual('large_screen');
    });

    it('marks phone presentation as switchable when desktop mode is selected', 0, () => {
      const coordinator = new BrowserWindowPresentationProfileCoordinator();
      const availability: BrowserShellFamilyAvailability = {
        phoneShellAvailable: true,
        largeScreenShellAvailable: true
      };

      const profile = coordinator.reconcile({
        platformDeviceType: 'phone',
        windowWidthVp: 420,
        windowHeightVp: 860,
        pointerAvailable: false,
        tabletInterfaceMode: 'desktop'
      }, availability, 1);

      expect(profile.shellFamily).assertEqual('large_screen');
      expect(profile.familyLocked).assertFalse();
      expect(profile.decisionReason).assertEqual('phone-desktop-override');
    });

    it('uses stable fold state only for automatic phone presentation', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const expandedDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded'
      });
      const foldedDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: true,
        foldState: 'folded'
      });
      const explicitTouchDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'touch',
        pointerAvailable: false,
        foldState: 'expanded'
      });

      expect(expandedDecision.shellFamily).assertEqual('large_screen');
      expect(expandedDecision.decisionReason).assertEqual('fold-expanded-auto-desktop');
      expect(foldedDecision.shellFamily).assertEqual('phone');
      expect(foldedDecision.decisionReason).assertEqual('folded-auto-touch');
      expect(explicitTouchDecision.shellFamily).assertEqual('phone');
      expect(explicitTouchDecision.decisionReason).assertEqual('phone-touch-override');
    });

    it('keeps the previous automatic heuristic when fold state is unknown', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const decision = policy.resolve({
        detectedFormFactor: 'tablet',
        selectedMode: 'auto',
        pointerAvailable: true,
        foldState: 'unknown'
      });

      expect(decision.shellFamily).assertEqual('large_screen');
      expect(decision.decisionReason).assertEqual('tablet-auto-pointer');
    });
  });
}

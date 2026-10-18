import { describe, expect, it } from '@ohos/hypium';
import {
  resolveWebAppTopSafeAreaInsetVp,
  WebAppTopSafeAreaInsetInput
} from '../main/ets/core/webapps/WebAppTopSafeAreaPolicy';

const STATUS_BAR_VP: number = 24;
const CUTOUT_VP: number = 32;

function buildInput(
  webAppSurfaceActive: boolean,
  topSafeAreaHidden: boolean,
  statusBarVisible: boolean,
  systemTopInsetVp: number,
  cutoutTopInsetVp: number
): WebAppTopSafeAreaInsetInput {
  return {
    webAppSurfaceActive: webAppSurfaceActive,
    topSafeAreaHidden: topSafeAreaHidden,
    statusBarVisible: statusBarVisible,
    systemTopInsetVp: systemTopInsetVp,
    cutoutTopInsetVp: cutoutTopInsetVp
  };
}

export default function webAppTopSafeAreaPolicyTest(): void {
  describe('WebAppTopSafeAreaPolicy', () => {
    it('reserves the reported status bar height for the installed Web App surface', 0, () => {
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(true, false, true, STATUS_BAR_VP, 0)
      )).assertEqual(STATUS_BAR_VP);
    });

    it('lets a taller cutout win over the status bar', 0, () => {
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(true, false, true, STATUS_BAR_VP, CUTOUT_VP)
      )).assertEqual(CUTOUT_VP);
    });

    it('reserves nothing for a browser surface that paints its own chrome', 0, () => {
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(false, false, true, STATUS_BAR_VP, CUTOUT_VP)
      )).assertEqual(0);
    });

    it('reserves nothing for a Web App installed as full screen', 0, () => {
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(true, true, true, STATUS_BAR_VP, CUTOUT_VP)
      )).assertEqual(0);
    });

    it('reserves nothing once the page reclaimed the strip from scroll immersion', 0, () => {
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(true, false, false, STATUS_BAR_VP, CUTOUT_VP)
      )).assertEqual(0);
    });

    it('keeps a missing or invalid avoid area at zero', 0, () => {
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(true, false, true, 0, 0)
      )).assertEqual(0);
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(true, false, true, -12, Number.NaN)
      )).assertEqual(0);
    });

    it('rounds a fractional avoid area up to a whole vp', 0, () => {
      expect(resolveWebAppTopSafeAreaInsetVp(
        buildInput(true, false, true, 23.2, 0)
      )).assertEqual(24);
    });
  });
}

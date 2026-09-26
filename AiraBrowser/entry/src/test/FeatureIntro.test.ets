import { describe, expect, it } from '@ohos/hypium';
import { FeatureIntroViewModel } from '../main/ets/core/onboarding/FeatureIntroViewModel';
import { resolveFeatureIntroLayout } from '../main/ets/core/onboarding/FeatureIntroLayoutPolicy';
import {
  clampFeatureIntroGateDrag,
  featureIntroGateBackdropColor,
  isFeatureIntroGateUnlocked,
  resolveFeatureIntroGateLogoTop,
  resolveFeatureIntroGateTravel
} from '../main/ets/core/onboarding/FeatureIntroGatePolicy';
import {
  resolveFeatureIntroExitDestination,
  resolveInitialOnboardingDestination
} from '../main/ets/core/onboarding/FeatureIntroRoutePolicy';

export default function featureIntroTest(): void {
  describe('FeatureIntroViewModel', () => {
    it('keeps the four first-open slides in order', 0, () => {
      const slides = new FeatureIntroViewModel().slides();

      expect(slides.length).assertEqual(4);
      expect(slides[0].id).assertEqual('ad_block');
      expect(slides[0].title).assertEqual('少一点广告打扰');
      expect(slides[1].id).assertEqual('video_takeover');
      expect(slides[1].title).assertEqual('接管网页视频');
      expect(slides[2].id).assertEqual('user_scripts');
      expect(slides[2].title).assertEqual('支持用户脚本');
      expect(slides[3].id).assertEqual('sync');
      expect(slides[3].title).assertEqual('换一台，接着用');
    });

    it('uses next until the last slide, then enter', 0, () => {
      const viewModel = new FeatureIntroViewModel();

      expect(viewModel.actionLabel(0)).assertEqual('下一步');
      expect(viewModel.actionLabel(2)).assertEqual('下一步');
      expect(viewModel.isLast(2)).assertFalse();
      expect(viewModel.actionLabel(3)).assertEqual('立即体验');
      expect(viewModel.isLast(3)).assertTrue();
      expect(viewModel.gateActionLabel()).assertEqual('向右滑动开始使用');
      expect(viewModel.gateSkipLabel()).assertEqual('跳过');
    });
  });

  describe('featureIntroGate', () => {
    it('uses a black backdrop in dark mode and white otherwise', 0, () => {
      expect(featureIntroGateBackdropColor('dark')).assertEqual('#000000');
      expect(featureIntroGateBackdropColor('light')).assertEqual('#FFFFFF');
    });

    it('unlocks only after the knob travels almost the full track', 0, () => {
      const travel = resolveFeatureIntroGateTravel(320);

      expect(clampFeatureIntroGateDrag(-20, travel)).assertEqual(0);
      expect(clampFeatureIntroGateDrag(travel + 40, travel)).assertEqual(travel);
      expect(isFeatureIntroGateUnlocked(travel * 0.5, travel)).assertFalse();
      expect(isFeatureIntroGateUnlocked(travel * 0.86, travel)).assertTrue();
      expect(isFeatureIntroGateUnlocked(10, 0)).assertFalse();
    });

    it('keeps the logo in the upper middle without covering the slider', 0, () => {
      const phoneTop = resolveFeatureIntroGateLogoTop(844, 36, 108);
      const shortTop = resolveFeatureIntroGateLogoTop(480, 24, 96);

      expect(phoneTop).assertEqual(236);
      expect(shortTop < 480 - 96 - 120).assertTrue();
    });
  });

  describe('resolveFeatureIntroLayout', () => {
    it('keeps a phone slot near 9:8', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 390,
        windowHeightVp: 844,
        topInsetVp: 36,
        bottomInsetVp: 28
      });

      expect(layout.videoHeightVp).assertEqual(347);
      expect(layout.contentMaxWidthVp).assertEqual(430);
      expect(layout.bottomPaddingVp).assertEqual(28);
    });

    it('shrinks the slot on a short window so the copy still fits', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 360,
        windowHeightVp: 520,
        topInsetVp: 24,
        bottomInsetVp: 16
      });

      expect(layout.videoHeightVp).assertEqual(244);
    });

    it('caps the slot on a wide window', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 800,
        windowHeightVp: 1200,
        topInsetVp: 32,
        bottomInsetVp: 24
      });

      expect(layout.videoHeightVp).assertEqual(440);
      expect(layout.horizontalPaddingVp).assertEqual(24);
    });

    it('does not invent a slot from empty measurements', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 0,
        windowHeightVp: -1,
        topInsetVp: 0,
        bottomInsetVp: 0
      });

      expect(layout.videoHeightVp).assertEqual(0);
    });
  });

  describe('resolveInitialOnboardingDestination', () => {
    it('shows the feature intro only before the sync welcome is finished', 0, () => {
      expect(resolveInitialOnboardingDestination(false, false)).assertEqual('feature_intro');
      expect(resolveInitialOnboardingDestination(true, false)).assertEqual('startup_welcome');
      expect(resolveInitialOnboardingDestination(false, true)).assertEqual('browser');
      expect(resolveInitialOnboardingDestination(true, true)).assertEqual('browser');
    });

    it('returns to the sync welcome after the feature intro on a new install', 0, () => {
      expect(resolveFeatureIntroExitDestination(false)).assertEqual('startup_welcome');
      expect(resolveFeatureIntroExitDestination(true)).assertEqual('browser');
    });
  });
}

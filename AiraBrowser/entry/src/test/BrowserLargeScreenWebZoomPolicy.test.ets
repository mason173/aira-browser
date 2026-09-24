import { describe, expect, it } from '@ohos/hypium';
import {
  buildDocumentZoomScript,
  formatDocumentZoomRatio,
  isDocumentZoomApplied,
  normalizeObservedWebZoomPercent,
  resolveCommittedWebZoomPercent,
  resolveBaselinePageScale,
  resolveDesiredPageScale,
  resolveDocumentZoomRatio,
  resolveOwnedDocumentZoomRatio,
  resolvePageScalePercentFromViewport,
  resolveRelativeWebZoomFactor,
  resolveWebZoomPlan,
  shouldUseDocumentZoom
} from '../main/ets/core/browser/BrowserLargeScreenWebZoomPolicy';

export default function browserLargeScreenWebZoomPolicyTest(): void {
  describe('BrowserLargeScreenWebZoomPolicy', () => {
    it('zooms relative to the current page percent', 0, () => {
      expect(resolveRelativeWebZoomFactor(100, 125)).assertEqual(1.25);
      expect(resolveRelativeWebZoomFactor(125, 150)).assertEqual(1.2);
      expect(resolveRelativeWebZoomFactor(125, 100)).assertEqual(0.8);
      expect(resolveRelativeWebZoomFactor(150, 150)).assertEqual(1);
    });

    it('rejects a factor outside the WebviewController zoom range', 0, () => {
      expect(resolveRelativeWebZoomFactor(0, 100)).assertEqual(0);
      expect(resolveRelativeWebZoomFactor(100, 0)).assertEqual(0);
      expect(resolveRelativeWebZoomFactor(0.5, 100)).assertEqual(0);
      expect(resolveRelativeWebZoomFactor(Number.NaN, 100)).assertEqual(0);
    });

    it('compensates document zoom when page scale is already clamped', 0, () => {
      expect(resolveDocumentZoomRatio(100, 67)).assertEqual(0.67);
      expect(resolveDocumentZoomRatio(72, 25)).assertEqual(25 / 72);
      expect(formatDocumentZoomRatio(25 / 72)).assertEqual('0.347222');
      const script = buildDocumentZoomScript(0.67);
      expect(script.indexOf("setProperty('zoom','0.67'") >= 0).assertTrue();
      expect(isDocumentZoomApplied('0.67', 0.67)).assertTrue();
      expect(isDocumentZoomApplied('"0.9"', 0.9)).assertTrue();
      expect(isDocumentZoomApplied('"1.01124"', 1.0112359550561798)).assertTrue();
      expect(isDocumentZoomApplied('67%', 0.67)).assertTrue();
      expect(isDocumentZoomApplied('normal', 0.67)).assertFalse();
      expect(isDocumentZoomApplied('"missing"', 0.67)).assertFalse();
      expect(isDocumentZoomApplied('missing', 0.67)).assertFalse();
    });

    it('treats 100 percent as the page baseline, not absolute page scale', 0, () => {
      expect(shouldUseDocumentZoom(90)).assertTrue();
      expect(shouldUseDocumentZoom(50)).assertTrue();
      expect(shouldUseDocumentZoom(100)).assertFalse();
      expect(shouldUseDocumentZoom(110)).assertFalse();
      expect(resolveBaselinePageScale(0, 72.27)).assertEqual(72.27);
      expect(resolveBaselinePageScale(72.27, 300)).assertEqual(72.27);
      expect(resolveDesiredPageScale(80, 100)).assertEqual(80);
      expect(resolveDesiredPageScale(80, 125)).assertEqual(100);
      expect(resolveDesiredPageScale(80, 90)).assertEqual(80);
      expect(resolveOwnedDocumentZoomRatio(90)).assertEqual(0.9);
      expect(resolveOwnedDocumentZoomRatio(100)).assertEqual(0);
      expect(resolvePageScalePercentFromViewport('0.72')).assertEqual(72);
      expect(resolvePageScalePercentFromViewport('"1.25"')).assertEqual(125);
      expect(resolvePageScalePercentFromViewport('72')).assertEqual(72);
    });

    it('does not raise page scale when the display decreases from the baseline', 0, () => {
      const baseline = 72.27302193641663;
      const plan = resolveWebZoomPlan(baseline, baseline, 90);
      expect(plan.mechanism).assertEqual('document');
      expect(plan.cssRatio).assertEqual(0.9);
      expect(plan.pageScaleTarget).assertEqual(baseline);
      expect(plan.zoomFactor).assertEqual(1);
      expect(plan.clearCss).assertFalse();
      expect(plan.zoomFactor < 90 / baseline).assertTrue();
    });

    it('returns a zoomed-in page to the baseline when reset to 100', 0, () => {
      const baseline = 72.27302193641663;
      const pageScale = 361.36510372161865;
      const plan = resolveWebZoomPlan(baseline, pageScale, 100);
      expect(plan.mechanism).assertEqual('page');
      expect(plan.clearCss).assertTrue();
      expect(plan.cssRatio).assertEqual(0);
      expect(plan.pageScaleTarget).assertEqual(baseline);
      expect(plan.zoomFactor < 1).assertTrue();
      expect(Math.abs(plan.zoomFactor - baseline / pageScale) < 0.000001).assertTrue();
    });

    it('zooms in from the baseline instead of multiplying by an absolute percent', 0, () => {
      const baseline = 72.27302193641663;
      const plan = resolveWebZoomPlan(baseline, baseline, 110);
      expect(plan.mechanism).assertEqual('page');
      expect(plan.cssRatio).assertEqual(0);
      expect(plan.clearCss).assertTrue();
      expect(Math.abs(plan.zoomFactor - 1.1) < 0.000001).assertTrue();
      expect(Math.abs(plan.pageScaleTarget - baseline * 1.1) < 0.000001).assertTrue();
      const next = resolveWebZoomPlan(baseline, plan.pageScaleTarget, 125);
      expect(next.cssRatio).assertEqual(0);
      expect(next.zoomFactor > 1).assertTrue();
      expect(Math.abs(next.pageScaleTarget - baseline * 1.25) < 0.000001).assertTrue();
    });

    it('never emits a css zoom at or above 1', 0, () => {
      expect(resolveWebZoomPlan(72.27, 72.27, 25).cssRatio < 1).assertTrue();
      expect(resolveWebZoomPlan(72.27, 216.82, 300).cssRatio).assertEqual(0);
      expect(resolveWebZoomPlan(72.27, 300, 50).mechanism).assertEqual('document');
      expect(resolveWebZoomPlan(72.27, 300, 50).cssRatio).assertEqual(0.5);
      expect(resolveWebZoomPlan(72.27, 300, 50).pageScaleTarget).assertEqual(72.27);
      expect(resolveWebZoomPlan(72.27, 300, 50).zoomFactor < 1).assertTrue();
      expect(resolveWebZoomPlan(0, 72, 90).zoomFactor).assertEqual(0);
    });

    it('keeps the last confirmed percent when the engine does not report a new scale', 0, () => {
      expect(resolveCommittedWebZoomPercent(72, 0)).assertEqual(72);
      expect(resolveCommittedWebZoomPercent(75, 72.2)).assertEqual(72);
      expect(resolveCommittedWebZoomPercent(100, Number.NaN)).assertEqual(100);
    });

    it('rounds the observed page scale to the displayed percent', 0, () => {
      expect(normalizeObservedWebZoomPercent(109.6)).assertEqual(110);
      expect(normalizeObservedWebZoomPercent(110.4)).assertEqual(110);
      expect(normalizeObservedWebZoomPercent(100)).assertEqual(100);
      expect(normalizeObservedWebZoomPercent(0)).assertEqual(0);
      expect(normalizeObservedWebZoomPercent(Number.NaN)).assertEqual(0);
    });
  });
}

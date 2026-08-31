import { curves } from '@kit.ArkUI';

export const BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS: number = 180;
export const BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS: number = 220;
export const BROWSER_BOTTOM_PANEL_PEEK_TO_LOW_ANIMATION_DURATION_MS: number = 320;
export const BROWSER_BOTTOM_PANEL_COLLAPSE_TO_PEEK_ANIMATION_DURATION_MS: number = 170;
export const BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_DURATION_MS: number = 110;
export const BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_BARRIER_MS: number =
  BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_DURATION_MS + 16;
export const BROWSER_SEARCH_BACKDROP_FULL_PROGRESS_DISTANCE: number = 180;
export const BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_REVEAL_DISTANCE: number = 120;

export function resolveBrowserBottomPanelMotionCurve(): ICurve {
  return curves.springMotion(0.5, 0.72);
}

export function resolveBrowserBottomPanelMiddleSnapCurve(): ICurve {
  return curves.springMotion(0.38, 0.78);
}

export function resolveBrowserBottomPanelFastExitCurve(): Curve {
  return Curve.FastOutSlowIn;
}

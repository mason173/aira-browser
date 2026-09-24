/**
 * Native cockpit window spans. HarmonyOS seat design requires a car app to
 * keep working at full, two-thirds, and one-third window sizes. Those sizes
 * use the same width breakpoints as tablet, foldable, and phone portrait
 * layouts: under 600vp, 600–840vp, and 840vp and wider.
 *
 * Span is only a window-size fact. A cockpit is a touch display, even when the
 * center screen is wider than a tablet, so it never promotes into the PC shell.
 */
export type BrowserCockpitWindowSpan = 'third' | 'two_thirds' | 'full';

export const COCKPIT_THIRD_MAX_WIDTH_VP: number = 600;
export const COCKPIT_FULL_MIN_WIDTH_VP: number = 840;

/** 10.7mm at the vp definition of 160dpi. Cockpit hits must not be smaller. */
export const COCKPIT_MIN_HIT_TARGET_VP: number = 68;
/** 15.4mm, the seat-design recommended hit size. */
export const COCKPIT_RECOMMENDED_HIT_TARGET_VP: number = 97;
export const COCKPIT_MIN_BODY_TEXT_FP: number = 15;
export const COCKPIT_MIN_TEXT_FP: number = 9;
export const COCKPIT_MIN_ICON_VP: number = 18;

export function isCockpitPlatformDeviceType(platformDeviceType: string): boolean {
  const normalized = platformDeviceType.trim().toLowerCase();
  return normalized === 'car' || normalized === 'cockpit';
}

export function resolveCockpitWindowSpan(windowWidthVp: number | undefined): BrowserCockpitWindowSpan {
  const width = windowWidthVp ?? 0;
  if (!Number.isFinite(width) || width <= 0 || width >= COCKPIT_FULL_MIN_WIDTH_VP) {
    return 'full';
  }
  if (width < COCKPIT_THIRD_MAX_WIDTH_VP) {
    return 'third';
  }
  return 'two_thirds';
}

/** Cockpit interaction is the touch shell at every window span. */
export function resolveCockpitShellFamily(): 'phone' {
  return 'phone';
}

export function resolveCockpitHitTargetVp(visualSizeVp: number): number {
  const visual = Number.isFinite(visualSizeVp) && visualSizeVp > 0 ? visualSizeVp : 0;
  return Math.max(visual, COCKPIT_MIN_HIT_TARGET_VP);
}

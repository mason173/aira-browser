/**
 * Top clearance for the chrome-less installed Web App surface.
 *
 * An installed Web App mounts no browser chrome at all: no tab strip, no address row, no
 * toolbar rows, and no quick-search row (the quick-search coordinator already suppresses
 * that row while a Web App session is active). Its top edge is therefore the window's own
 * system safe area and nothing else.
 *
 * This is why the reserve must NOT be read from the browser chrome frame: the split and
 * dock frames describe rows that this surface never paints, so their address block and
 * quick-search height would stack empty strips above the page, and the large-screen shell's
 * zero reserve would leave the page under the status bar once that shell's chrome is gone.
 * The only inputs are the avoid-area geometry the window reports through
 * `window.getWindowAvoidArea(TYPE_SYSTEM / TYPE_CUTOUT)` (kept live by
 * `on('avoidAreaChange')` and converted px -> vp) and whether the status bar is shown over
 * the page.
 *
 * A Web App installed with `defaultFullscreen` hides the status bar, and a page that has
 * scrolled into top immersion reclaims the strip; both reserve nothing.
 */

export interface WebAppTopSafeAreaInsetInput {
  /** The shell is presenting the chrome-less installed Web App surface. */
  webAppSurfaceActive: boolean;
  /** The Web App ships full screen, so the status bar is hidden for it. */
  topSafeAreaHidden: boolean;
  /** The status bar strip is currently shown over the page. */
  statusBarVisible: boolean;
  /** `getWindowAvoidArea(TYPE_SYSTEM).topRect.height`, already converted to vp. */
  systemTopInsetVp: number;
  /** `getWindowAvoidArea(TYPE_CUTOUT).topRect.height`, already converted to vp. */
  cutoutTopInsetVp: number;
}

export function resolveWebAppTopSafeAreaInsetVp(input: WebAppTopSafeAreaInsetInput): number {
  if (!input.webAppSurfaceActive || input.topSafeAreaHidden || !input.statusBarVisible) {
    return 0;
  }
  return Math.max(normalizeInsetVp(input.systemTopInsetVp), normalizeInsetVp(input.cutoutTopInsetVp));
}

function normalizeInsetVp(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.ceil(value);
}

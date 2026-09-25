/**
 * Device-local PC vertical-tabs chrome.
 *
 * Pinned open occupies layout and pushes the page. Collapsed is an icon rail;
 * hovering that rail expands an overlay that does not move the page. The
 * collapse control is the only action that pins the sidebar into the layout.
 * Both flags stay out of Personalization Sync, same as the desktop bookmark bar.
 */

export const BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP: number = 248;
export const BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP: number = 56;
export const BROWSER_LARGE_SCREEN_VERTICAL_TABS_TOOLBAR_HEIGHT_VP: number = 48;

/** Absent or true keeps the draft default: a collapsed icon rail. */
export function isBrowserLargeScreenVerticalTabsCollapsed(
  collapsed: boolean | undefined
): boolean {
  return collapsed !== false;
}

export function resolveBrowserLargeScreenVerticalTabsToolbarHeightVp(
  titleBarHeightVp: number
): number {
  const normalized = Number.isFinite(titleBarHeightVp) && titleBarHeightVp > 0 ? titleBarHeightVp : 0;
  return Math.max(BROWSER_LARGE_SCREEN_VERTICAL_TABS_TOOLBAR_HEIGHT_VP, normalized);
}

export function resolveBrowserLargeScreenVerticalTabsLayoutWidthVp(
  enabled: boolean,
  collapsed: boolean | undefined
): number {
  if (!enabled) {
    return 0;
  }
  return isBrowserLargeScreenVerticalTabsCollapsed(collapsed)
    ? BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP
    : BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP;
}

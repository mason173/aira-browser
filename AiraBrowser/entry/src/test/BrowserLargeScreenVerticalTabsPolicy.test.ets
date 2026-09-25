import { describe, expect, it } from '@ohos/hypium';
import {
  BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP,
  BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP,
  isBrowserLargeScreenVerticalTabsCollapsed,
  resolveBrowserLargeScreenVerticalTabsLayoutWidthVp,
  resolveBrowserLargeScreenVerticalTabsToolbarHeightVp
} from '../main/ets/core/browser/BrowserLargeScreenVerticalTabsPolicy';

export default function browserLargeScreenVerticalTabsPolicyTest(): void {
  describe('BrowserLargeScreenVerticalTabsPolicy', () => {
    it('keeps the first vertical-tabs state collapsed and only pinned open pushes the page', 0, () => {
      expect(isBrowserLargeScreenVerticalTabsCollapsed(undefined)).assertTrue();
      expect(isBrowserLargeScreenVerticalTabsCollapsed(true)).assertTrue();
      expect(isBrowserLargeScreenVerticalTabsCollapsed(false)).assertFalse();
      expect(resolveBrowserLargeScreenVerticalTabsLayoutWidthVp(false, false)).assertEqual(0);
      expect(resolveBrowserLargeScreenVerticalTabsLayoutWidthVp(true, undefined))
        .assertEqual(BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP);
      expect(resolveBrowserLargeScreenVerticalTabsLayoutWidthVp(true, true))
        .assertEqual(BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP);
      expect(resolveBrowserLargeScreenVerticalTabsLayoutWidthVp(true, false))
        .assertEqual(BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP);
    });

    it('gives the address row at least the navigation toolbar height when it becomes the title bar', 0, () => {
      expect(resolveBrowserLargeScreenVerticalTabsToolbarHeightVp(0)).assertEqual(48);
      expect(resolveBrowserLargeScreenVerticalTabsToolbarHeightVp(40)).assertEqual(48);
      expect(resolveBrowserLargeScreenVerticalTabsToolbarHeightVp(56)).assertEqual(56);
      expect(resolveBrowserLargeScreenVerticalTabsToolbarHeightVp(Number.NaN)).assertEqual(48);
    });
  });
}

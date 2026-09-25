import { describe, expect, it } from '@ohos/hypium';
import { normalizeBrowserHomePageStyle } from '../main/ets/common/models/HomePagePresentationSettingsModels';
import {
  applyCenteredHomeShortcutLayout,
  centeredHomeSearchCenterOffset,
  CENTERED_HOME_ICON_CORNER_RADIUS_RATIO,
  CENTERED_HOME_SEARCH_CENTER_LIFT_VP,
  resolveCenteredHomeFrame
} from '../main/ets/features/newtab/CenteredHomeShortcutLayoutPolicy';
import { HomeResponsiveLayoutState } from '../main/ets/features/newtab/HomeResponsiveLayoutViewModel';

function classicLayout(): HomeResponsiveLayoutState {
  return {
    widthBreakpoint: 'sm',
    aspectBreakpoint: 'regular',
    centerContentVertically: false,
    useSharedSectionWidth: false,
    shortcutGridTopInset: 18,
    shortcutGridWidth: 360,
    recentlyClosedColumns: 1,
    recentlyClosedColumnGap: 8,
    recentlyClosedRowGap: 8,
    contentHorizontalPadding: 8,
    contentTopPadding: 12,
    bottomSpacerExtra: 0,
    sectionVerticalGap: 14,
    shortcutMetrics: {
      columns: 5,
      rowGap: 16,
      columnGap: 6,
      targetTileSize: 52,
      minimumTileSize: 44,
      fallbackColumnWidth: 72,
      titleTopGap: 4,
      titleBlockHeight: 18
    }
  };
}

export default function centeredHomeShortcutLayoutPolicyTest(): void {
  describe('CenteredHomeShortcutLayoutPolicy', () => {
    it('keeps unknown homepage styles on the classic frame', 0, () => {
      expect(normalizeBrowserHomePageStyle(undefined)).assertEqual('classic');
      expect(normalizeBrowserHomePageStyle('')).assertEqual('classic');
      expect(normalizeBrowserHomePageStyle('split')).assertEqual('classic');
      expect(normalizeBrowserHomePageStyle('centered')).assertEqual('centered');
    });

    it('shrinks the same shortcut grid without rewriting its column count', 0, () => {
      const source = classicLayout();
      const centered = applyCenteredHomeShortcutLayout(source);
      expect(centered.shortcutMetrics.columns).assertEqual(source.shortcutMetrics.columns);
      expect(centered.shortcutMetrics.targetTileSize < source.shortcutMetrics.targetTileSize).assertTrue();
      expect(centered.shortcutMetrics.targetTileSize >= 40).assertTrue();
      expect(centered.shortcutMetrics.columnGap >= source.shortcutMetrics.columnGap).assertTrue();
      expect(centered.contentTopPadding).assertEqual(source.contentTopPadding);
      expect(centered.recentlyClosedColumns).assertEqual(source.recentlyClosedColumns);
      expect(CENTERED_HOME_ICON_CORNER_RADIUS_RATIO).assertEqual(0.5);
    });

    it('pins the search field slightly above the vertical center of the screen', 0, () => {
      const frame = resolveCenteredHomeFrame({
        viewportHeight: 844,
        topSafeInset: 47,
        bottomChromeReserve: 112
      });
      expect(frame.headerTop + centeredHomeSearchCenterOffset())
        .assertEqual(422 - CENTERED_HOME_SEARCH_CENTER_LIFT_VP);
      expect(CENTERED_HOME_SEARCH_CENTER_LIFT_VP > 0).assertTrue();
      expect(frame.headerTop > 47).assertTrue();
      expect(frame.iconRegionHeight > 0).assertTrue();
    });

    it('keeps the fixed header below the status bar on a short screen', 0, () => {
      const frame = resolveCenteredHomeFrame({
        viewportHeight: 240,
        topSafeInset: 40,
        bottomChromeReserve: 80
      });
      expect(frame.headerTop >= 40).assertTrue();
      expect(frame.iconRegionHeight >= 0).assertTrue();
    });
  });
}

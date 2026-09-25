import { HomeResponsiveLayoutState } from './HomeResponsiveLayoutViewModel';
import { HomeShortcutLayoutMetrics } from '../../services/shortcuts/HomeShortcutLogicService';

/**
 * Presentation-only metrics for the centered homepage.
 *
 * The style reuses the compact column count, then draws each tile smaller. It does not write the
 * user's compact-layout or icon-radius settings; those stay owned by the classic homepage.
 */
const CENTERED_HOME_TILE_SCALE: number = 0.78;
const CENTERED_HOME_MINIMUM_TILE_SIZE: number = 40;
const CENTERED_HOME_COLUMN_GAP: number = 10;
export const CENTERED_HOME_ICON_CORNER_RADIUS_RATIO: number = 0.5;
export const CENTERED_HOME_WORDMARK_WIDTH: number = 176;
export const CENTERED_HOME_WORDMARK_HEIGHT: number = 53;
export const CENTERED_HOME_WORDMARK_SEARCH_GAP: number = 32;
export const CENTERED_HOME_SEARCH_HEIGHT: number = 48;
export const CENTERED_HOME_HEADER_BOTTOM_GAP: number = 28;
/** Pulls the pinned search a little above the screen center. */
export const CENTERED_HOME_SEARCH_CENTER_LIFT_VP: number = 40;

export interface CenteredHomeFrameInput {
  viewportHeight: number;
  topSafeInset: number;
  bottomChromeReserve: number;
}

export interface CenteredHomeFrame {
  headerTop: number;
  iconRegionHeight: number;
}

/** Distance from the top of the fixed header to the vertical center of the search field. */
export function centeredHomeSearchCenterOffset(): number {
  return CENTERED_HOME_WORDMARK_HEIGHT +
    CENTERED_HOME_WORDMARK_SEARCH_GAP +
    CENTERED_HOME_SEARCH_HEIGHT / 2;
}

export function centeredHomeHeaderBlockHeight(): number {
  return CENTERED_HOME_WORDMARK_HEIGHT +
    CENTERED_HOME_WORDMARK_SEARCH_GAP +
    CENTERED_HOME_SEARCH_HEIGHT +
    CENTERED_HOME_HEADER_BOTTOM_GAP;
}

/**
 * Pins the search field to the vertical center of the screen.
 * The wordmark stays above it. Only the icon region below is allowed to scroll.
 */
export function resolveCenteredHomeFrame(input: CenteredHomeFrameInput): CenteredHomeFrame {
  const viewportHeight = Math.max(0, input.viewportHeight);
  const topSafeInset = Math.max(0, input.topSafeInset);
  const bottomReserve = Math.max(0, input.bottomChromeReserve);
  const headerHeight = centeredHomeHeaderBlockHeight();
  if (viewportHeight <= 0) {
    return { headerTop: topSafeInset, iconRegionHeight: 0 };
  }
  const unclampedHeaderTop = viewportHeight / 2 -
    CENTERED_HOME_SEARCH_CENTER_LIFT_VP -
    centeredHomeSearchCenterOffset();
  const maxHeaderTop = viewportHeight - bottomReserve - headerHeight;
  const headerTop = maxHeaderTop > topSafeInset ?
    Math.min(Math.max(unclampedHeaderTop, topSafeInset), maxHeaderTop) :
    topSafeInset;
  return {
    headerTop: headerTop,
    iconRegionHeight: Math.max(0, viewportHeight - headerTop - headerHeight - bottomReserve)
  };
}

export function applyCenteredHomeShortcutLayout(
  state: HomeResponsiveLayoutState
): HomeResponsiveLayoutState {
  return {
    widthBreakpoint: state.widthBreakpoint,
    aspectBreakpoint: state.aspectBreakpoint,
    centerContentVertically: state.centerContentVertically,
    useSharedSectionWidth: state.useSharedSectionWidth,
    shortcutGridTopInset: 8,
    shortcutGridWidth: state.shortcutGridWidth,
    recentlyClosedColumns: state.recentlyClosedColumns,
    recentlyClosedColumnGap: state.recentlyClosedColumnGap,
    recentlyClosedRowGap: state.recentlyClosedRowGap,
    contentHorizontalPadding: state.contentHorizontalPadding,
    contentTopPadding: state.contentTopPadding,
    bottomSpacerExtra: state.bottomSpacerExtra,
    sectionVerticalGap: Math.max(18, state.sectionVerticalGap),
    shortcutMetrics: scaleCenteredShortcutMetrics(state.shortcutMetrics)
  };
}

function scaleCenteredShortcutMetrics(metrics: HomeShortcutLayoutMetrics): HomeShortcutLayoutMetrics {
  const targetTileSize = Math.max(
    CENTERED_HOME_MINIMUM_TILE_SIZE,
    Math.round(metrics.targetTileSize * CENTERED_HOME_TILE_SCALE)
  );
  return {
    columns: metrics.columns,
    rowGap: Math.max(14, metrics.rowGap - 2),
    columnGap: Math.max(metrics.columnGap, CENTERED_HOME_COLUMN_GAP),
    targetTileSize: targetTileSize,
    minimumTileSize: Math.min(metrics.minimumTileSize, targetTileSize),
    fallbackColumnWidth: Math.max(56, Math.round(metrics.fallbackColumnWidth * CENTERED_HOME_TILE_SCALE)),
    titleTopGap: metrics.titleTopGap,
    titleBlockHeight: metrics.titleBlockHeight
  };
}

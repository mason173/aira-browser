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
/**
 * Large-screen content rails are much wider than a phone. The centered search
 * field stops growing past this width and stays centered under the wordmark.
 */
export const CENTERED_HOME_LARGE_SCREEN_SEARCH_MAX_WIDTH: number = 560;
/** Shared by the centered-home field and the search-page field so one can fly into the other. */
export const CENTERED_HOME_SEARCH_GEOMETRY_ID: string = 'aira.centered-home.search';
/**
 * Same flag as the shell state, published into AppStorage so the home field and the
 * top pill swap in one frame. A @Prop chain reaches the home field a few frames late,
 * and the shared-element flight has no destination.
 */
export const CENTERED_HOME_SEARCH_GEOMETRY_OPEN_KEY: string = 'aira.centered-home.search.geometry-open';
/** Lets the field finish moving before the keyboard covers it. */
export const CENTERED_HOME_SEARCH_GEOMETRY_FOCUS_DELAY_MS: number = 280;
/**
 * Search-page chrome (engine icon, cancel, solid fill) fades out on the way home,
 * and finishes before the box lands.
 */
export const CENTERED_HOME_SEARCH_CHROME_FADE_MS: number = 200;

export interface CenteredHomeFrameInput {
  viewportHeight: number;
  topSafeInset: number;
  bottomChromeReserve: number;
  /** Drawn wordmark height. Defaults to the shipped height when the caller does not resize it. */
  logoHeightVp?: number;
}

export interface CenteredHomeFrame {
  headerTop: number;
  iconRegionHeight: number;
}

/**
 * Phone search uses the full content width. On a large screen the same field
 * is capped, and a narrow window still shrinks it to the space it actually has.
 */
/**
 * An incomplete shortcut row grows outward from the middle only on the PC shell.
 * Touch mode packs that row from the leading edge, left to right.
 */
export function shouldCenterCenteredHomePartialRows(largeScreenShell: boolean): boolean {
  return largeScreenShell;
}

export function resolveCenteredHomeSearchFieldWidth(largeScreen: boolean, availableWidth: number): number {
  const available = Math.max(0, availableWidth);
  if (!largeScreen) {
    return available;
  }
  return Math.min(available, CENTERED_HOME_LARGE_SCREEN_SEARCH_MAX_WIDTH);
}

/** Distance from the top of the fixed header to the vertical center of the search field. */
export function centeredHomeSearchCenterOffset(logoHeightVp?: number): number {
  return resolveCenteredLogoHeight(logoHeightVp) +
    CENTERED_HOME_WORDMARK_SEARCH_GAP +
    CENTERED_HOME_SEARCH_HEIGHT / 2;
}

export function centeredHomeHeaderBlockHeight(logoHeightVp?: number): number {
  return resolveCenteredLogoHeight(logoHeightVp) +
    CENTERED_HOME_WORDMARK_SEARCH_GAP +
    CENTERED_HOME_SEARCH_HEIGHT +
    CENTERED_HOME_HEADER_BOTTOM_GAP;
}

function resolveCenteredLogoHeight(logoHeightVp: number | undefined): number {
  return typeof logoHeightVp === 'number' && Number.isFinite(logoHeightVp) && logoHeightVp > 0 ?
    logoHeightVp : CENTERED_HOME_WORDMARK_HEIGHT;
}

/**
 * Pins the search field to the vertical center of the screen.
 * The wordmark stays above it. Only the icon region below is allowed to scroll.
 */
export function resolveCenteredHomeFrame(input: CenteredHomeFrameInput): CenteredHomeFrame {
  const viewportHeight = Math.max(0, input.viewportHeight);
  const topSafeInset = Math.max(0, input.topSafeInset);
  const bottomReserve = Math.max(0, input.bottomChromeReserve);
  const logoHeight = resolveCenteredLogoHeight(input.logoHeightVp);
  const headerHeight = centeredHomeHeaderBlockHeight(logoHeight);
  if (viewportHeight <= 0) {
    return { headerTop: topSafeInset, iconRegionHeight: 0 };
  }
  const unclampedHeaderTop = viewportHeight / 2 -
    CENTERED_HOME_SEARCH_CENTER_LIFT_VP -
    centeredHomeSearchCenterOffset(logoHeight);
  const maxHeaderTop = viewportHeight - bottomReserve - headerHeight;
  const headerTop = maxHeaderTop > topSafeInset ?
    Math.min(Math.max(unclampedHeaderTop, topSafeInset), maxHeaderTop) :
    topSafeInset;
  return {
    headerTop: headerTop,
    iconRegionHeight: Math.max(0, viewportHeight - headerTop - headerHeight - bottomReserve)
  };
}

/**
 * Height of the centered frame used to place the search field.
 *
 * A measurement larger than the window (a px reading, or a height captured while another
 * homepage or sheet was covering the page) pushes the icon region below the clipped frame.
 * The add tile sits on the last row of that region, so it is the first thing to disappear.
 */
export function resolveMeasuredCenteredSurfaceHeight(measuredHeight: number, viewportHeight: number): number {
  const measured = Number.isFinite(measuredHeight) && measuredHeight > 0 ? measuredHeight : 0;
  const viewport = Number.isFinite(viewportHeight) && viewportHeight > 0 ? viewportHeight : 0;
  if (measured <= 0) {
    return viewport;
  }
  if (viewport <= 0) {
    return measured;
  }
  return Math.min(measured, viewport);
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

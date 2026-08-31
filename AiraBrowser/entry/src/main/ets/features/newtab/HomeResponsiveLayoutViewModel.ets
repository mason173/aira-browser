import { BrowserHomeShortcutLayoutDensity } from '../../common/models/BrowserModels';
import { HomeShortcutLayoutMetrics } from '../../services/shortcuts/HomeShortcutLogicService';
import {
  AppWindowAspectClass,
  AppWindowResponsiveLayoutService,
  AppWindowWidthClass
} from '../../services/layout/AppWindowResponsiveLayoutService';
import { HOME_RECENTLY_CLOSED_MINIMUM_CELL_WIDTH } from './HomeRecentlyClosedLayoutViewModel';

const HOME_SECTION_VERTICAL_GAP: number = 14;
const HOME_WIDE_SECTION_VERTICAL_GAP: number = 10;
const HOME_SHORTCUT_DEFAULT_COLUMNS: number = 4;
const HOME_SHORTCUT_DEFAULT_ROW_GAP: number = 20;
const HOME_SHORTCUT_DEFAULT_TARGET_TILE_SIZE: number = 65;
const HOME_SHORTCUT_DEFAULT_MINIMUM_TILE_SIZE: number = 50;
const HOME_SHORTCUT_FALLBACK_COLUMN_WIDTH: number = 88;
const HOME_SHORTCUT_COMPACT_COLUMN_GAP: number = 6;
const HOME_SHORTCUT_DEFAULT_TITLE_BLOCK_HEIGHT: number = 18;
const HOME_SHORTCUT_DEFAULT_TITLE_TOP_GAP: number = 4;
const HOME_SHARED_LARGE_SCREEN_TARGET_TILE_SIZE: number = 60;
const HOME_LARGE_SCREEN_LG_TARGET_TILE_SIZE: number = 58;
const HOME_LARGE_SCREEN_MD_TARGET_TILE_SIZE: number = 56;
const HOME_LARGE_SCREEN_SM_TARGET_TILE_SIZE: number = 52;
const HOME_SHARED_LARGE_SCREEN_MINIMUM_TILE_SIZE: number = 52;
const HOME_LARGE_SCREEN_LG_MINIMUM_TILE_SIZE: number = 50;
const HOME_LARGE_SCREEN_MD_MINIMUM_TILE_SIZE: number = 48;
const HOME_LARGE_SCREEN_SM_MINIMUM_TILE_SIZE: number = 44;
const HOME_LARGE_SCREEN_MAX_SHORTCUT_COLUMNS: number = 12;
const HOME_SHARED_CONTENT_SIDE_INSET: number = 10;

export type HomeWindowWidthBreakpoint = AppWindowWidthClass;
export type HomeWindowAspectBreakpoint = AppWindowAspectClass;
export type HomeResponsiveLayoutFamily = 'phone' | 'large_screen';

export interface HomeResponsiveLayoutInput {
  shellFamily: HomeResponsiveLayoutFamily;
  viewportWidth: number;
  viewportHeight: number;
  topSafeInsetVp?: number;
  bottomSafeInsetVp?: number;
  leftSafeInsetVp?: number;
  rightSafeInsetVp?: number;
}

export interface HomeResponsiveLayoutState {
  widthBreakpoint: HomeWindowWidthBreakpoint;
  aspectBreakpoint: HomeWindowAspectBreakpoint;
  centerContentVertically: boolean;
  useSharedSectionWidth: boolean;
  shortcutGridTopInset: number;
  shortcutGridWidth: number;
  recentlyClosedColumns: number;
  recentlyClosedColumnGap: number;
  recentlyClosedRowGap: number;
  contentHorizontalPadding: number;
  contentTopPadding: number;
  bottomSpacerExtra: number;
  sectionVerticalGap: number;
  shortcutMetrics: HomeShortcutLayoutMetrics;
}

export class HomeResponsiveLayoutViewModel {
  private readonly responsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  buildState(
    input: HomeResponsiveLayoutInput,
    shortcutLayoutDensity: BrowserHomeShortcutLayoutDensity = 'standard'
  ): HomeResponsiveLayoutState {
    const width = Math.max(0, input.viewportWidth);
    const height = Math.max(0, input.viewportHeight);
    const topSafeInset = Math.max(0, Math.ceil(input.topSafeInsetVp ?? 0));
    const bottomSafeInset = Math.max(0, Math.ceil(input.bottomSafeInsetVp ?? 0));
    const leftSafeInset = Math.max(0, Math.ceil(input.leftSafeInsetVp ?? 0));
    const rightSafeInset = Math.max(0, Math.ceil(input.rightSafeInsetVp ?? 0));
    const widthBreakpoint = this.responsiveLayoutService.resolveWidthClass(width);
    const aspectBreakpoint = this.responsiveLayoutService.resolveAspectClass(width, height);
    const wide = aspectBreakpoint === 'wide';
    // Large-Screen is a shell decision, while width classes describe geometry.
    // Once the shell is desktop-like, all Home sections must use one horizontal rail
    // even when an unfolded foldable falls into the md width class.
    const useSharedSectionWidth = this.resolveSharedSectionWidth(input.shellFamily, widthBreakpoint);
    const shortcutMetrics = shortcutLayoutDensity === 'compact'
      ? this.buildShortcutMetrics(widthBreakpoint, aspectBreakpoint, input.shellFamily, 'compact')
      : this.buildShortcutMetrics(widthBreakpoint, aspectBreakpoint, input.shellFamily, 'standard');
    const contentHorizontalPadding = this.resolveContentHorizontalPadding(
      useSharedSectionWidth,
      widthBreakpoint,
      width,
      wide,
      leftSafeInset,
      rightSafeInset
    );
    return {
      widthBreakpoint,
      aspectBreakpoint,
      centerContentVertically: input.shellFamily === 'large_screen',
      useSharedSectionWidth: useSharedSectionWidth,
      shortcutGridTopInset: wide ? 8 : 10,
      shortcutGridWidth: Math.max(1, width - contentHorizontalPadding * 2),
      recentlyClosedColumns: this.resolveRecentlyClosedColumns(widthBreakpoint),
      recentlyClosedColumnGap: this.resolveRecentlyClosedColumnGap(widthBreakpoint),
      recentlyClosedRowGap: this.resolveRecentlyClosedRowGap(widthBreakpoint),
      contentHorizontalPadding: contentHorizontalPadding,
      contentTopPadding: this.resolveContentTopPadding(wide, topSafeInset),
      bottomSpacerExtra: this.resolveBottomSpacerExtra(wide, bottomSafeInset),
      sectionVerticalGap: wide ? HOME_WIDE_SECTION_VERTICAL_GAP : HOME_SECTION_VERTICAL_GAP,
      shortcutMetrics: shortcutMetrics
    };
  }

  private resolveContentHorizontalPadding(
    useSharedSectionWidth: boolean,
    widthBreakpoint: HomeWindowWidthBreakpoint,
    viewportWidth: number,
    wide: boolean,
    leftSafeInset: number,
    rightSafeInset: number
  ): number {
    const basePadding = wide
      ? Math.max(20, Math.max(leftSafeInset, rightSafeInset) + 20)
      : 8;
    if (!useSharedSectionWidth) {
      return basePadding;
    }
    const centeredContentWidth = this.resolveSharedContentWidth(widthBreakpoint);
    return Math.max(basePadding, Math.ceil((viewportWidth - centeredContentWidth) / 2));
  }

  private resolveSharedSectionWidth(
    shellFamily: HomeResponsiveLayoutFamily,
    widthBreakpoint: HomeWindowWidthBreakpoint
  ): boolean {
    return shellFamily === 'large_screen' ||
      this.responsiveLayoutService.isAtLeastWidthClass(widthBreakpoint, 'lg');
  }

  private resolveSharedContentWidth(widthBreakpoint: HomeWindowWidthBreakpoint): number {
    const shortcutWidth = this.resolveStandardShortcutColumns(widthBreakpoint) * HOME_SHORTCUT_FALLBACK_COLUMN_WIDTH +
      HOME_SHARED_CONTENT_SIDE_INSET * 2;
    const recentlyClosedColumns = this.resolveRecentlyClosedColumns(widthBreakpoint);
    const recentlyClosedWidth = recentlyClosedColumns * HOME_RECENTLY_CLOSED_MINIMUM_CELL_WIDTH +
      Math.max(0, recentlyClosedColumns - 1) * this.resolveRecentlyClosedColumnGap(widthBreakpoint) +
      HOME_SHARED_CONTENT_SIDE_INSET * 2;
    return Math.max(shortcutWidth, recentlyClosedWidth);
  }

  private resolveContentTopPadding(wide: boolean, topSafeInset: number): number {
    return topSafeInset + (wide ? 18 : 8);
  }

  private resolveBottomSpacerExtra(wide: boolean, bottomSafeInset: number): number {
    return bottomSafeInset + (wide ? 12 : 16);
  }

  private buildShortcutMetrics(
    widthBreakpoint: HomeWindowWidthBreakpoint,
    aspectBreakpoint: HomeWindowAspectBreakpoint,
    shellFamily: HomeResponsiveLayoutFamily,
    density: BrowserHomeShortcutLayoutDensity
  ): HomeShortcutLayoutMetrics {
    const wide = aspectBreakpoint === 'wide';
    const standardColumns = this.resolveStandardShortcutColumns(widthBreakpoint);
    const compactColumns = standardColumns + 1;
    const columns = density === 'compact'
      ? Math.min(HOME_LARGE_SCREEN_MAX_SHORTCUT_COLUMNS, compactColumns)
      : standardColumns;
    const densityScale = density === 'compact' ? Math.sqrt(standardColumns / columns) : 1;
    const standardRowGap = this.resolveShortcutRowGap(widthBreakpoint, wide);
    const useSharedLargeScreenTileSize =
      this.responsiveLayoutService.isAtLeastWidthClass(widthBreakpoint, 'lg');
    const standardTargetTileSize = useSharedLargeScreenTileSize
      ? HOME_SHARED_LARGE_SCREEN_TARGET_TILE_SIZE
      : shellFamily === 'large_screen'
        ? this.resolveLargeScreenShortcutTargetTileSize(widthBreakpoint)
        : this.resolveShortcutTargetTileSize(widthBreakpoint, wide);
    const standardMinimumTileSize = useSharedLargeScreenTileSize
      ? HOME_SHARED_LARGE_SCREEN_MINIMUM_TILE_SIZE
      : shellFamily === 'large_screen'
        ? this.resolveLargeScreenShortcutMinimumTileSize(widthBreakpoint)
        : this.resolveShortcutMinimumTileSize(widthBreakpoint, wide);
    const standardTitleTopGap = wide ? 6 : HOME_SHORTCUT_DEFAULT_TITLE_TOP_GAP;
    return {
      columns: columns,
      rowGap: density === 'compact' ? Math.max(12, standardRowGap - 4) : standardRowGap,
      columnGap: density === 'compact' ? HOME_SHORTCUT_COMPACT_COLUMN_GAP : 0,
      targetTileSize: Math.round(standardTargetTileSize * densityScale),
      minimumTileSize: Math.round(standardMinimumTileSize * densityScale),
      fallbackColumnWidth: Math.round(HOME_SHORTCUT_FALLBACK_COLUMN_WIDTH * densityScale),
      titleTopGap: density === 'compact' ? Math.max(3, standardTitleTopGap - 1) : standardTitleTopGap,
      titleBlockHeight: wide ? 26 : HOME_SHORTCUT_DEFAULT_TITLE_BLOCK_HEIGHT
    };
  }

  private resolveStandardShortcutColumns(widthBreakpoint: HomeWindowWidthBreakpoint): number {
    if (widthBreakpoint === 'xxl') {
      return HOME_LARGE_SCREEN_MAX_SHORTCUT_COLUMNS;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 8;
    }
    if (widthBreakpoint === 'md') {
      return 6;
    }
    return HOME_SHORTCUT_DEFAULT_COLUMNS;
  }

  private resolveShortcutTargetTileSize(
    widthBreakpoint: HomeWindowWidthBreakpoint,
    wide: boolean
  ): number {
    if (widthBreakpoint === 'xxl') {
      return 84;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return wide ? 78 : 76;
    }
    if (wide) {
      return 44;
    }
    return HOME_SHORTCUT_DEFAULT_TARGET_TILE_SIZE;
  }

  private resolveLargeScreenShortcutTargetTileSize(widthBreakpoint: HomeWindowWidthBreakpoint): number {
    if (widthBreakpoint === 'xxl') {
      return HOME_SHARED_LARGE_SCREEN_TARGET_TILE_SIZE;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return HOME_LARGE_SCREEN_LG_TARGET_TILE_SIZE;
    }
    if (widthBreakpoint === 'md') {
      return HOME_LARGE_SCREEN_MD_TARGET_TILE_SIZE;
    }
    return HOME_LARGE_SCREEN_SM_TARGET_TILE_SIZE;
  }

  private resolveShortcutMinimumTileSize(
    widthBreakpoint: HomeWindowWidthBreakpoint,
    wide: boolean
  ): number {
    if (widthBreakpoint === 'xxl') {
      return 64;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 58;
    }
    if (wide) {
      return 36;
    }
    return HOME_SHORTCUT_DEFAULT_MINIMUM_TILE_SIZE;
  }

  private resolveLargeScreenShortcutMinimumTileSize(widthBreakpoint: HomeWindowWidthBreakpoint): number {
    if (widthBreakpoint === 'xxl') {
      return HOME_SHARED_LARGE_SCREEN_MINIMUM_TILE_SIZE;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return HOME_LARGE_SCREEN_LG_MINIMUM_TILE_SIZE;
    }
    if (widthBreakpoint === 'md') {
      return HOME_LARGE_SCREEN_MD_MINIMUM_TILE_SIZE;
    }
    return HOME_LARGE_SCREEN_SM_MINIMUM_TILE_SIZE;
  }

  private resolveShortcutRowGap(widthBreakpoint: HomeWindowWidthBreakpoint, wide: boolean): number {
    if (widthBreakpoint === 'xxl') {
      return 22;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 20;
    }
    if (wide) {
      return 16;
    }
    return HOME_SHORTCUT_DEFAULT_ROW_GAP;
  }

  private resolveRecentlyClosedColumns(widthBreakpoint: HomeWindowWidthBreakpoint): number {
    if (widthBreakpoint === 'xxl') {
      return 4;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 3;
    }
    if (widthBreakpoint === 'md') {
      return 2;
    }
    return 1;
  }

  private resolveRecentlyClosedColumnGap(widthBreakpoint: HomeWindowWidthBreakpoint): number {
    if (widthBreakpoint === 'xxl') {
      return 14;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 12;
    }
    if (widthBreakpoint === 'md') {
      return 10;
    }
    return 0;
  }

  private resolveRecentlyClosedRowGap(widthBreakpoint: HomeWindowWidthBreakpoint): number {
    return widthBreakpoint === 'xs' || widthBreakpoint === 'sm' ? 0 : 8;
  }
}

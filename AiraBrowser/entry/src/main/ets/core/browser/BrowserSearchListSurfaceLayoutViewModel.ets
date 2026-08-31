import {
  BrowserBottomPanelAspectBreakpoint,
  BrowserBottomPanelHeightBreakpoint,
  BrowserBottomPanelWidthBreakpoint
} from './BrowserBottomPanelResponsiveViewModel';

const BROWSER_SEARCH_LIST_CONTENT_VERTICAL_PADDING: number = 12;
const BROWSER_SEARCH_LIST_SCROLL_CLIP_SAFETY_GAP: number = 8;
const BROWSER_SEARCH_LIST_MULTI_COLUMN_GAP: number = 24;
const BROWSER_SEARCH_LIST_EXTERNAL_XS_COLUMN_LIMIT: number = 4;
const BROWSER_SEARCH_LIST_EXTERNAL_SM_COLUMN_LIMIT: number = 5;
const BROWSER_SEARCH_LIST_EXTERNAL_MD_COLUMN_LIMIT: number = 8;
const BROWSER_SEARCH_LIST_EXTERNAL_LG_COLUMN_LIMIT: number = 10;
const BROWSER_SEARCH_LIST_EXTERNAL_XL_COLUMN_LIMIT: number = 12;

export const BROWSER_SEARCH_LIST_DEFAULT_ROW_HEIGHT: number = 54;
export const BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT: number = 36;
export const BROWSER_SEARCH_LIST_EXTERNAL_STRIP_HEIGHT: number = 66;
export const BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH: number = 48;
export const BROWSER_SEARCH_LIST_EXTERNAL_ACTION_SIZE: number = 42;
export const BROWSER_SEARCH_LIST_EXTERNAL_ITEM_CENTER_PITCH: number = 74;

export interface BrowserSearchListSurfaceHostLayout {
  surfaceWidth: number;
  contentHorizontalPadding: number;
  widthBreakpoint: BrowserBottomPanelWidthBreakpoint;
  heightBreakpoint: BrowserBottomPanelHeightBreakpoint;
  aspectBreakpoint: BrowserBottomPanelAspectBreakpoint;
}

export interface BrowserSearchListSurfaceLayoutState {
  contentHorizontalPadding: number;
  contentVerticalPadding: number;
  scrollClipSafetyGap: number;
  rowHeight: number;
  rowContentFrameHeight: number;
  columns: number;
  columnGap: number;
  rowGap: number;
  externalStripHeight: number;
  externalItemWidth: number;
  externalActionSize: number;
  externalColumnGap: number;
  externalPageSize: number;
}

export class BrowserSearchListSurfaceLayoutViewModel {
  buildState(host: BrowserSearchListSurfaceHostLayout): BrowserSearchListSurfaceLayoutState {
    const wideCompact = host.aspectBreakpoint === 'wide' && host.heightBreakpoint === 'compact';
    const contentHorizontalPadding = Math.max(0, host.contentHorizontalPadding);
    const externalColumnGap = BROWSER_SEARCH_LIST_EXTERNAL_ITEM_CENTER_PITCH -
      BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH;
    return {
      contentHorizontalPadding: contentHorizontalPadding,
      contentVerticalPadding: BROWSER_SEARCH_LIST_CONTENT_VERTICAL_PADDING,
      scrollClipSafetyGap: BROWSER_SEARCH_LIST_SCROLL_CLIP_SAFETY_GAP,
      rowHeight: BROWSER_SEARCH_LIST_DEFAULT_ROW_HEIGHT,
      rowContentFrameHeight: BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT,
      columns: this.resolveColumns(host.widthBreakpoint, wideCompact),
      columnGap: this.resolveColumnGap(host.widthBreakpoint, wideCompact),
      rowGap: this.resolveRowGap(host.widthBreakpoint, wideCompact),
      externalStripHeight: BROWSER_SEARCH_LIST_EXTERNAL_STRIP_HEIGHT,
      externalItemWidth: BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH,
      externalActionSize: BROWSER_SEARCH_LIST_EXTERNAL_ACTION_SIZE,
      externalColumnGap: externalColumnGap,
      externalPageSize: this.resolveExternalPageSize(
        host.surfaceWidth,
        contentHorizontalPadding,
        host.widthBreakpoint
      )
    };
  }

  private resolveExternalPageSize(
    surfaceWidth: number,
    contentHorizontalPadding: number,
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint
  ): number {
    const columnLimit = this.resolveExternalColumnLimit(widthBreakpoint);
    const contentWidth = Math.max(0, surfaceWidth - contentHorizontalPadding * 2);
    if (contentWidth <= 0) {
      return columnLimit;
    }
    const fittedColumns = Math.floor(contentWidth / BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH);
    return Math.max(BROWSER_SEARCH_LIST_EXTERNAL_XS_COLUMN_LIMIT, Math.min(columnLimit, fittedColumns));
  }

  private resolveExternalColumnLimit(widthBreakpoint: BrowserBottomPanelWidthBreakpoint): number {
    if (widthBreakpoint === 'xl') {
      return BROWSER_SEARCH_LIST_EXTERNAL_XL_COLUMN_LIMIT;
    }
    if (widthBreakpoint === 'lg') {
      return BROWSER_SEARCH_LIST_EXTERNAL_LG_COLUMN_LIMIT;
    }
    if (widthBreakpoint === 'md') {
      return BROWSER_SEARCH_LIST_EXTERNAL_MD_COLUMN_LIMIT;
    }
    if (widthBreakpoint === 'xs') {
      return BROWSER_SEARCH_LIST_EXTERNAL_XS_COLUMN_LIMIT;
    }
    return BROWSER_SEARCH_LIST_EXTERNAL_SM_COLUMN_LIMIT;
  }

  private resolveColumns(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 3;
    }
    if (widthBreakpoint === 'md' || wideCompact) {
      return 2;
    }
    return 1;
  }

  private resolveColumnGap(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    const columns = this.resolveColumns(widthBreakpoint, wideCompact);
    return columns > 1 ? BROWSER_SEARCH_LIST_MULTI_COLUMN_GAP : 0;
  }

  private resolveRowGap(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    return (widthBreakpoint === 'xs' || widthBreakpoint === 'sm') && !wideCompact ? 2 : 8;
  }
}

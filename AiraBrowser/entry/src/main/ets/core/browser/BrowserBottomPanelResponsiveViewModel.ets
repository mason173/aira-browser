import {
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HEADER_HORIZONTAL_PADDING,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HORIZONTAL_INSET,
  BROWSER_BOTTOM_ADDRESS_PANEL_PHONE_HEADER_HORIZONTAL_PADDING,
  BROWSER_BOTTOM_ADDRESS_PANEL_PHONE_HORIZONTAL_INSET,
  BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT,
  BROWSER_BOTTOM_CHROME_OUTER_GAP,
  BROWSER_BOTTOM_CHROME_OUTER_SIZE,
  BROWSER_BOTTOM_CHROME_PHONE_OUTER_GAP,
  BROWSER_BOTTOM_CHROME_PHONE_OUTER_SIZE,
  BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE,
  BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
  BROWSER_BOTTOM_QUICK_ACTION_CARD_HEIGHT
} from './BrowserBottomAddressPanelMetrics';
import {
  AppWindowResponsiveLayoutService
} from '../../services/layout/AppWindowResponsiveLayoutService';

const WEB_BOTTOM_PANEL_HIGH_MIN_VIEWPORT_RATIO: number = 0.70;
const WEB_BOTTOM_QUICK_ACTION_DEFAULT_ROWS: number = 2;
const WEB_BOTTOM_QUICK_ACTION_MIN_ITEM_WIDTH: number = 92;
const WEB_BOTTOM_QUICK_ACTION_MAX_COLUMNS: number = 8;
const WEB_BOTTOM_PANEL_WIDE_COMPACT_MAX_HEIGHT: number = 340;
const WEB_BOTTOM_PANEL_REGULAR_MAX_HEIGHT: number = 620;
const WEB_BOTTOM_PANEL_EXPANDED_MAX_HEIGHT: number = 680;
const WEB_BOTTOM_PANEL_TABLET_MAX_HEIGHT: number = 640;

export type BrowserBottomPanelWidthBreakpoint = 'xs' | 'sm' | 'md' | 'lg' | 'xl';
export type BrowserBottomPanelHeightBreakpoint = 'compact' | 'regular' | 'expanded';
export type BrowserBottomPanelAspectBreakpoint = 'wide' | 'regular' | 'tall';

export interface BrowserBottomPanelResponsiveInput {
  viewportWidth: number;
  viewportHeight: number;
}

export interface BrowserBottomPanelResponsiveState {
  widthBreakpoint: BrowserBottomPanelWidthBreakpoint;
  heightBreakpoint: BrowserBottomPanelHeightBreakpoint;
  aspectBreakpoint: BrowserBottomPanelAspectBreakpoint;
  expandedTopInset: number;
  minViewportRatio: number;
  panelMaxHeight: number;
  panelWidth: number;
  panelOffsetX: number;
  floatingHeaderHorizontalPadding: number;
  restingChromeOuterSize: number;
  restingChromeOuterGap: number;
  contentMaxWidth: number;
  contentHorizontalPadding: number;
  quickActionLimit: number;
  quickActionColumns: number;
  quickActionColumnGap: number;
  quickActionOuterInset: number;
  expandedChromeWidth: number;
  quickActionTopGap: number;
  quickActionCardHeight: number;
  quickActionRowGap: number;
  secondaryActionColumns: number;
  secondaryActionColumnGap: number;
  secondaryActionRowGap: number;
  secondaryActionRowHeight: number;
  secondaryActionListTopGap: number;
}

export interface BrowserBottomPanelHeightInput {
  viewportHeight: number;
  addressFocused: boolean;
  state: BrowserBottomPanelResponsiveState;
}

export class BrowserBottomPanelResponsiveViewModel {
  private readonly appWindowResponsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  buildState(input: BrowserBottomPanelResponsiveInput): BrowserBottomPanelResponsiveState {
    const width = Math.max(0, input.viewportWidth);
    const height = Math.max(0, input.viewportHeight);
    const widthBreakpoint = this.resolveWidthBreakpoint(width);
    const heightBreakpoint = this.resolveHeightBreakpoint(height);
    const aspectBreakpoint = this.appWindowResponsiveLayoutService.resolveAspectClass(width, height);
    const compactHeight = heightBreakpoint === 'compact';
    const wideCompact = aspectBreakpoint === 'wide' && compactHeight;
    const panelWidth = this.resolvePanelWidth(width, widthBreakpoint, aspectBreakpoint, wideCompact);
    const contentMaxWidth = this.resolveContentMaxWidth(widthBreakpoint, wideCompact);
    const quickActionColumns = this.resolveQuickActionColumns(
      width,
      widthBreakpoint,
      aspectBreakpoint,
      wideCompact
    );
    const quickActionColumnGap = this.resolveQuickActionColumnGap(widthBreakpoint, wideCompact);
    const quickActionOuterInset = this.resolveQuickActionOuterInset(
      panelWidth,
      contentMaxWidth,
      quickActionColumns,
      quickActionColumnGap
    );
    return {
      widthBreakpoint,
      heightBreakpoint,
      aspectBreakpoint,
      expandedTopInset: this.resolveExpandedTopInset(widthBreakpoint, heightBreakpoint, wideCompact),
      minViewportRatio: this.resolveMinViewportRatio(widthBreakpoint, heightBreakpoint, wideCompact),
      panelMaxHeight: this.resolvePanelMaxHeight(widthBreakpoint, heightBreakpoint, wideCompact),
      panelWidth,
      panelOffsetX: panelWidth > 0 ? Math.max(0, (width - panelWidth) / 2) : 0,
      floatingHeaderHorizontalPadding: this.resolveFloatingHeaderHorizontalPadding(widthBreakpoint),
      restingChromeOuterSize: this.resolveRestingChromeOuterSize(widthBreakpoint),
      restingChromeOuterGap: this.resolveRestingChromeOuterGap(widthBreakpoint),
      contentMaxWidth,
      contentHorizontalPadding: this.resolveContentHorizontalPadding(widthBreakpoint, compactHeight),
      quickActionLimit: quickActionColumns * WEB_BOTTOM_QUICK_ACTION_DEFAULT_ROWS,
      quickActionColumns,
      quickActionColumnGap,
      quickActionOuterInset,
      expandedChromeWidth: this.resolveExpandedChromeWidth(
        panelWidth,
        widthBreakpoint,
        quickActionOuterInset
      ),
      quickActionTopGap: wideCompact ? 10 : 12,
      quickActionCardHeight: this.resolveQuickActionCardHeight(widthBreakpoint, wideCompact),
      quickActionRowGap: wideCompact ? 14 : 18,
      secondaryActionColumns: this.resolveSecondaryActionColumns(widthBreakpoint, wideCompact),
      secondaryActionColumnGap: this.resolveGridColumnGap(widthBreakpoint, wideCompact),
      secondaryActionRowGap: this.resolveSecondaryActionRowGap(widthBreakpoint, wideCompact),
      secondaryActionRowHeight: wideCompact ? 42 : 46,
      secondaryActionListTopGap: wideCompact ? 12 : 16
    };
  }

  buildLayoutRenderKey(state: BrowserBottomPanelResponsiveState): string {
    return `${state.widthBreakpoint}:` +
      `panel=${Math.round(state.panelWidth)}:` +
      `offset=${Math.round(state.panelOffsetX)}:` +
      `headerPad=${Math.round(state.floatingHeaderHorizontalPadding)}:` +
      `chromeOuter=${Math.round(state.restingChromeOuterSize)}:` +
      `chromeGap=${Math.round(state.restingChromeOuterGap)}:` +
      `content=${Math.round(state.contentMaxWidth)}:` +
      `quick=${Math.round(state.quickActionColumns)}x${Math.round(state.quickActionLimit)}:` +
      `quickGap=${Math.round(state.quickActionColumnGap)}:` +
      `quickInset=${Math.round(state.quickActionOuterInset)}:` +
      `expandedChrome=${Math.round(state.expandedChromeWidth)}:` +
      `secondary=${Math.round(state.secondaryActionColumns)}`;
  }

  resolveBrowserPanelHeight(input: BrowserBottomPanelHeightInput): number {
    const viewportHeight = Math.max(0, input.viewportHeight);
    if (viewportHeight <= 0) {
      return 560;
    }
    const highViewportRatio = input.addressFocused ?
      0.93 :
      Math.min(WEB_BOTTOM_PANEL_HIGH_MIN_VIEWPORT_RATIO, input.state.minViewportRatio);
    const uncappedHeight = Math.max(
      BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT,
      viewportHeight * highViewportRatio,
      viewportHeight - input.state.expandedTopInset
    );
    const maxHeight = Math.max(BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT, input.state.panelMaxHeight);
    return Math.max(BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT, Math.min(uncappedHeight, maxHeight));
  }

  resolveWebPanelHeight(input: BrowserBottomPanelHeightInput): number {
    return this.resolveBrowserPanelHeight(input);
  }

  private resolveWidthBreakpoint(width: number): BrowserBottomPanelWidthBreakpoint {
    const widthClass = this.appWindowResponsiveLayoutService.resolveWidthClass(width);
    return widthClass === 'xxl' ? 'xl' : widthClass;
  }

  private resolveHeightBreakpoint(height: number): BrowserBottomPanelHeightBreakpoint {
    if (height > 0 && height < 520) {
      return 'compact';
    }
    if (height < 800) {
      return 'regular';
    }
    return 'expanded';
  }

  private resolveExpandedTopInset(
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    heightBreakpoint: BrowserBottomPanelHeightBreakpoint,
    wideCompact: boolean
  ): number {
    if (wideCompact) {
      return 64;
    }
    if (widthBreakpoint === 'xl') {
      return heightBreakpoint === 'expanded' ? 152 : 136;
    }
    if (widthBreakpoint === 'lg') {
      return heightBreakpoint === 'expanded' ? 144 : 128;
    }
    return heightBreakpoint === 'compact' ? 96 : 128;
  }

  private resolveMinViewportRatio(
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    heightBreakpoint: BrowserBottomPanelHeightBreakpoint,
    wideCompact: boolean
  ): number {
    if (wideCompact) {
      return 0.94;
    }
    if (heightBreakpoint === 'compact') {
      return 0.88;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 0.74;
    }
    return 0.82;
  }

  private resolvePanelMaxHeight(
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    heightBreakpoint: BrowserBottomPanelHeightBreakpoint,
    wideCompact: boolean
  ): number {
    if (wideCompact || heightBreakpoint === 'compact') {
      return WEB_BOTTOM_PANEL_WIDE_COMPACT_MAX_HEIGHT;
    }
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return WEB_BOTTOM_PANEL_TABLET_MAX_HEIGHT;
    }
    if (heightBreakpoint === 'expanded') {
      return WEB_BOTTOM_PANEL_EXPANDED_MAX_HEIGHT;
    }
    return WEB_BOTTOM_PANEL_REGULAR_MAX_HEIGHT;
  }

  private resolveContentMaxWidth(
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    wideCompact: boolean = false
  ): number {
    if (wideCompact) {
      return 760;
    }
    if (widthBreakpoint === 'xl') {
      return 960;
    }
    if (widthBreakpoint === 'lg') {
      return 840;
    }
    if (widthBreakpoint === 'md') {
      return 720;
    }
    return 0;
  }

  private resolvePanelWidth(
    width: number,
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    aspectBreakpoint: BrowserBottomPanelAspectBreakpoint,
    wideCompact: boolean = false
  ): number {
    const floatingWidth = this.resolveFloatingPanelWidth(width, widthBreakpoint);
    const maxWidth = this.resolveContentMaxWidth(widthBreakpoint, wideCompact);
    if (maxWidth > 0) {
      return Math.min(floatingWidth, maxWidth);
    }
    if (aspectBreakpoint !== 'wide') {
      return floatingWidth;
    }
    return Math.min(floatingWidth, 640);
  }

  private resolveFloatingPanelWidth(
    width: number,
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint
  ): number {
    if (width <= 0) {
      return 0;
    }
    const horizontalInset = this.isPhoneWidthBreakpoint(widthBreakpoint) ?
      BROWSER_BOTTOM_ADDRESS_PANEL_PHONE_HORIZONTAL_INSET :
      BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HORIZONTAL_INSET;
    return Math.max(1, width - horizontalInset * 2);
  }

  private resolveFloatingHeaderHorizontalPadding(widthBreakpoint: BrowserBottomPanelWidthBreakpoint): number {
    return this.isPhoneWidthBreakpoint(widthBreakpoint) ?
      BROWSER_BOTTOM_ADDRESS_PANEL_PHONE_HEADER_HORIZONTAL_PADDING :
      BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HEADER_HORIZONTAL_PADDING;
  }

  private resolveRestingChromeOuterSize(widthBreakpoint: BrowserBottomPanelWidthBreakpoint): number {
    return this.isPhoneWidthBreakpoint(widthBreakpoint) ?
      BROWSER_BOTTOM_CHROME_PHONE_OUTER_SIZE : BROWSER_BOTTOM_CHROME_OUTER_SIZE;
  }

  private resolveRestingChromeOuterGap(widthBreakpoint: BrowserBottomPanelWidthBreakpoint): number {
    return this.isPhoneWidthBreakpoint(widthBreakpoint) ?
      BROWSER_BOTTOM_CHROME_PHONE_OUTER_GAP : BROWSER_BOTTOM_CHROME_OUTER_GAP;
  }

  private resolveExpandedChromeWidth(
    panelWidth: number,
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    quickActionOuterInset: number
  ): number {
    if (this.isPhoneWidthBreakpoint(widthBreakpoint)) {
      return Math.max(0, panelWidth);
    }
    return Math.max(0, panelWidth - quickActionOuterInset * 2);
  }

  private isPhoneWidthBreakpoint(widthBreakpoint: BrowserBottomPanelWidthBreakpoint): boolean {
    return widthBreakpoint === 'xs' || widthBreakpoint === 'sm';
  }

  private resolveContentHorizontalPadding(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, compactHeight: boolean): number {
    if (widthBreakpoint === 'xl' || widthBreakpoint === 'lg') {
      return 16;
    }
    if (widthBreakpoint === 'md') {
      return compactHeight ? 10 : 12;
    }
    return compactHeight ? 6 : 0;
  }

  private resolveQuickActionColumns(
    width: number,
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    aspectBreakpoint: BrowserBottomPanelAspectBreakpoint,
    wideCompact: boolean
  ): number {
    if ((widthBreakpoint === 'xs' || widthBreakpoint === 'sm') && aspectBreakpoint !== 'wide') {
      return 4;
    }
    const availableWidth = this.resolveQuickActionContentWidth(width, widthBreakpoint, aspectBreakpoint, wideCompact);
    if (availableWidth <= 0) {
      return 4;
    }
    const gap = this.resolveQuickActionColumnGap(widthBreakpoint, wideCompact);
    const columns = Math.floor((availableWidth + gap) / (WEB_BOTTOM_QUICK_ACTION_MIN_ITEM_WIDTH + gap));
    return Math.max(4, Math.min(WEB_BOTTOM_QUICK_ACTION_MAX_COLUMNS, columns));
  }

  private resolveQuickActionContentWidth(
    width: number,
    widthBreakpoint: BrowserBottomPanelWidthBreakpoint,
    aspectBreakpoint: BrowserBottomPanelAspectBreakpoint,
    wideCompact: boolean
  ): number {
    const panelWidth = this.resolvePanelWidth(width, widthBreakpoint, aspectBreakpoint, wideCompact);
    const contentWidth = panelWidth > 0 ? panelWidth : width;
    return Math.max(0, contentWidth - this.resolveContentHorizontalPadding(widthBreakpoint, wideCompact) * 2);
  }

  private resolveQuickActionCardHeight(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    void widthBreakpoint;
    void wideCompact;
    return BROWSER_BOTTOM_QUICK_ACTION_CARD_HEIGHT;
  }

  private resolveQuickActionOuterInset(
    panelWidth: number,
    contentMaxWidth: number,
    columnCount: number,
    columnGap: number
  ): number {
    const layoutWidth = Math.max(0, panelWidth);
    if (layoutWidth <= 0) {
      return 0;
    }
    const columns = Math.max(1, Math.floor(columnCount));
    const contentWidth = contentMaxWidth > 0 ? Math.min(layoutWidth, contentMaxWidth) : layoutWidth;
    const contentOffset = Math.max(0, (layoutWidth - contentWidth) / 2);
    const groupPadding = BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING;
    const gridWidth = Math.max(0, contentWidth - groupPadding * 2);
    const totalGapWidth = Math.max(0, columnGap) * Math.max(0, columns - 1);
    const cellWidth = Math.max(0, (gridWidth - totalGapWidth) / columns);
    const buttonInset = Math.max(0, (cellWidth - BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE) / 2);
    return contentOffset + groupPadding + buttonInset;
  }

  private resolveSecondaryActionColumns(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    if (widthBreakpoint === 'xl') {
      return 3;
    }
    if (widthBreakpoint === 'lg') {
      return 3;
    }
    if (wideCompact) {
      return 2;
    }
    return 1;
  }

  private resolveGridColumnGap(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    if (widthBreakpoint === 'xl') {
      return 14;
    }
    if (widthBreakpoint === 'lg') {
      return 14;
    }
    if (wideCompact) {
      return 10;
    }
    return 0;
  }

  private resolveQuickActionColumnGap(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    if (wideCompact) {
      return 10;
    }
    switch (widthBreakpoint) {
      case 'xl':
      case 'lg':
      case 'md':
      case 'xs':
      case 'sm':
      default:
        return 12;
    }
  }

  private resolveSecondaryActionRowGap(widthBreakpoint: BrowserBottomPanelWidthBreakpoint, wideCompact: boolean): number {
    return (widthBreakpoint === 'xs' || widthBreakpoint === 'sm') && !wideCompact ? 0 : 8;
  }

}

export const DEFAULT_BROWSER_BOTTOM_PANEL_RESPONSIVE_STATE: BrowserBottomPanelResponsiveState =
  new BrowserBottomPanelResponsiveViewModel().buildState({
    viewportWidth: 360,
    viewportHeight: 800
  });

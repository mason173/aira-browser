import { BROWSER_TAB_PREVIEW_CARD_HEIGHT_RATIO } from './BrowserTabPreviewMetrics';
import { BrowserTabsOverviewLayoutStyle } from '../../common/models/BrowserModels';
import {
  AppWindowResponsiveFacts,
  AppWindowResponsiveLayoutService
} from '../../services/layout/AppWindowResponsiveLayoutService';
import {
  BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT,
  BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP
} from './BrowserTabsOverviewVisualTokens';

export interface BrowserTabsOverviewLayoutInput {
  gridWidth: number;
  sheetWidth: number;
  sheetHeight: number;
  layoutStyle?: BrowserTabsOverviewLayoutStyle | string;
}

export interface BrowserTabsOverviewHorizontalCardFrameInput {
  maxWidth: number;
  maxHeight: number;
  snapshotWidth: number;
  snapshotHeight: number;
}

export interface BrowserTabsOverviewHorizontalCardFrame {
  width: number;
  height: number;
}

export interface BrowserTabsOverviewLayoutState {
  layoutStyle: BrowserTabsOverviewLayoutStyle;
  columnCount: number;
  columnsTemplate: string;
  gridGap: number;
  cardWidth: number;
  previewHeight: number;
  identityHeaderHeight: number;
  identityPreviewGap: number;
  itemHeight: number;
  horizontalContentInset: number;
}

interface BrowserTabsOverviewLayoutBaseState {
  layoutStyle: BrowserTabsOverviewLayoutStyle;
  columnCount: number;
  columnsTemplate: string;
  gridGap: number;
  cardWidth: number;
  previewHeight: number;
  horizontalContentInset: number;
}

const TAB_OVERVIEW_LAYOUT_MIN_CARD_WIDTH: number = 132;
const TAB_OVERVIEW_LAYOUT_MIN_PREVIEW_HEIGHT: number = 118;
const TAB_OVERVIEW_LAYOUT_MAX_PORTRAIT_PREVIEW_HEIGHT: number = 360;
const TAB_OVERVIEW_LAYOUT_PHONE_LANDSCAPE_PREVIEW_RATIO: number = 0.58;
const TAB_OVERVIEW_LAYOUT_TABLET_LANDSCAPE_PREVIEW_RATIO: number = 0.62;
const TAB_OVERVIEW_LAYOUT_PORTRAIT_PREVIEW_RATIO: number = BROWSER_TAB_PREVIEW_CARD_HEIGHT_RATIO;
const TAB_OVERVIEW_LAYOUT_PREVIEW_HEIGHT_MULTIPLIER: number = 1.08;
const TAB_OVERVIEW_LAYOUT_GRID_GAP: number = 16;
const TAB_OVERVIEW_LAYOUT_TOP_PADDING: number = 16;
const TAB_OVERVIEW_LAYOUT_TOP_SAFE_GAP: number = 10;
const TAB_OVERVIEW_HORIZONTAL_CARDS_GAP: number = 18;
const TAB_OVERVIEW_HORIZONTAL_CARDS_PHONE_WIDTH_RATIO: number = 0.82;
const TAB_OVERVIEW_HORIZONTAL_CARDS_LANDSCAPE_WIDTH_RATIO: number = 0.56;
const TAB_OVERVIEW_HORIZONTAL_CARDS_MAX_WIDTH: number = 520;
const TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_WIDTH: number = 220;
const TAB_OVERVIEW_HORIZONTAL_CARDS_VIEWPORT_HEIGHT_RATIO: number = 0.66;
const TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_HEIGHT: number = 180;

export class BrowserTabsOverviewLayoutViewModel {
  private readonly responsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  buildState(input: BrowserTabsOverviewLayoutInput): BrowserTabsOverviewLayoutState {
    const layoutStyle = this.normalizeLayoutStyle(input.layoutStyle);
    const usableWidth = this.resolveUsableWidth(input);
    if (layoutStyle === 'horizontal_cards') {
      return this.buildHorizontalCardsState(input, usableWidth);
    }
    const responsiveFacts = this.resolveResponsiveFacts(input);
    const columnCount = this.resolveColumnCount(responsiveFacts);
    const cardWidth = this.resolveCardWidth(usableWidth, columnCount);
    const previewHeight = this.resolvePreviewHeight(input, cardWidth);
    return this.buildLayoutState({
      layoutStyle: 'grid',
      columnCount: columnCount,
      columnsTemplate: this.buildColumnsTemplate(columnCount),
      gridGap: TAB_OVERVIEW_LAYOUT_GRID_GAP,
      cardWidth: cardWidth,
      previewHeight: previewHeight,
      horizontalContentInset: 0
    });
  }

  private buildHorizontalCardsState(
    input: BrowserTabsOverviewLayoutInput,
    usableWidth: number
  ): BrowserTabsOverviewLayoutState {
    const cardWidth = this.resolveHorizontalCardWidth(input, usableWidth);
    return this.buildLayoutState({
      layoutStyle: 'horizontal_cards',
      columnCount: 1,
      columnsTemplate: '1fr',
      gridGap: TAB_OVERVIEW_HORIZONTAL_CARDS_GAP,
      cardWidth: cardWidth,
      previewHeight: this.resolveHorizontalPreviewHeight(input),
      horizontalContentInset: Math.max(0, (usableWidth - cardWidth) / 2)
    });
  }

  private buildLayoutState(base: BrowserTabsOverviewLayoutBaseState): BrowserTabsOverviewLayoutState {
    return {
      layoutStyle: base.layoutStyle,
      columnCount: base.columnCount,
      columnsTemplate: base.columnsTemplate,
      gridGap: base.gridGap,
      cardWidth: base.cardWidth,
      previewHeight: base.previewHeight,
      identityHeaderHeight: BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT,
      identityPreviewGap: BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP,
      itemHeight: base.previewHeight + BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT +
        BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP,
      horizontalContentInset: base.horizontalContentInset
    };
  }

  resolveTopPadding(topSafeInsetVp: number): number {
    return Math.max(TAB_OVERVIEW_LAYOUT_TOP_PADDING, topSafeInsetVp + TAB_OVERVIEW_LAYOUT_TOP_SAFE_GAP);
  }

  resolveHorizontalCardFrame(
    input: BrowserTabsOverviewHorizontalCardFrameInput
  ): BrowserTabsOverviewHorizontalCardFrame {
    const maxWidth = Math.max(1, input.maxWidth);
    const maxHeight = Math.max(1, input.maxHeight);
    const snapshotWidth = Math.max(1, input.snapshotWidth);
    const snapshotHeight = Math.max(1, input.snapshotHeight);
    const scale = Math.min(maxWidth / snapshotWidth, maxHeight / snapshotHeight);
    return {
      width: Math.max(1, snapshotWidth * scale),
      height: Math.max(1, snapshotHeight * scale)
    };
  }

  private resolveColumnCount(facts: AppWindowResponsiveFacts): number {
    if (facts.orientation === 'landscape' &&
      this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'md')) {
      return 3;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'lg')) {
      return 4;
    }
    return 2;
  }

  private resolveUsableWidth(input: BrowserTabsOverviewLayoutInput): number {
    if (input.gridWidth > 0) {
      return input.gridWidth;
    }
    return Math.max(1, input.sheetWidth - 32);
  }

  private resolveCardWidth(usableWidth: number, columnCount: number): number {
    const safeColumnCount = Math.max(1, columnCount);
    const totalGap = TAB_OVERVIEW_LAYOUT_GRID_GAP * Math.max(0, safeColumnCount - 1);
    return Math.max(TAB_OVERVIEW_LAYOUT_MIN_CARD_WIDTH, (Math.max(1, usableWidth) - totalGap) / safeColumnCount);
  }

  private resolvePreviewHeight(input: BrowserTabsOverviewLayoutInput, cardWidth: number): number {
    const width = Math.max(0, input.sheetWidth);
    const height = Math.max(0, input.sheetHeight);
    const ratio = this.resolvePreviewRatio(width, height) * TAB_OVERVIEW_LAYOUT_PREVIEW_HEIGHT_MULTIPLIER;
    const maxHeight = this.resolvePreviewMaxHeight(width, height);
    return Math.round(Math.max(
      TAB_OVERVIEW_LAYOUT_MIN_PREVIEW_HEIGHT,
      Math.min(maxHeight, cardWidth * ratio)
    ));
  }

  private resolvePreviewRatio(width: number, height: number): number {
    const facts = this.responsiveLayoutService.resolve({
      viewportWidth: width,
      viewportHeight: height
    });
    if (facts.orientation === 'landscape' &&
      this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'lg')) {
      return TAB_OVERVIEW_LAYOUT_TABLET_LANDSCAPE_PREVIEW_RATIO;
    }
    if (facts.orientation === 'landscape' &&
      this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'md')) {
      return TAB_OVERVIEW_LAYOUT_PHONE_LANDSCAPE_PREVIEW_RATIO;
    }
    return TAB_OVERVIEW_LAYOUT_PORTRAIT_PREVIEW_RATIO;
  }

  private resolvePreviewMaxHeight(width: number, height: number): number {
    if (width > height && height > 0) {
      return Math.max(TAB_OVERVIEW_LAYOUT_MIN_PREVIEW_HEIGHT, height * 0.42);
    }
    return TAB_OVERVIEW_LAYOUT_MAX_PORTRAIT_PREVIEW_HEIGHT;
  }

  private resolveHorizontalCardWidth(input: BrowserTabsOverviewLayoutInput, usableWidth: number): number {
    const landscape = input.sheetWidth > input.sheetHeight;
    const ratio = landscape ?
      TAB_OVERVIEW_HORIZONTAL_CARDS_LANDSCAPE_WIDTH_RATIO :
      TAB_OVERVIEW_HORIZONTAL_CARDS_PHONE_WIDTH_RATIO;
    return Math.round(Math.max(
      TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_WIDTH,
      Math.min(TAB_OVERVIEW_HORIZONTAL_CARDS_MAX_WIDTH, Math.max(1, usableWidth) * ratio)
    ));
  }

  private resolveHorizontalPreviewHeight(input: BrowserTabsOverviewLayoutInput): number {
    return Math.round(Math.max(
      TAB_OVERVIEW_HORIZONTAL_CARDS_MIN_HEIGHT,
      Math.max(1, input.sheetHeight) * TAB_OVERVIEW_HORIZONTAL_CARDS_VIEWPORT_HEIGHT_RATIO
    ));
  }

  private normalizeLayoutStyle(style: BrowserTabsOverviewLayoutStyle | string | undefined): BrowserTabsOverviewLayoutStyle {
    return style === 'horizontal_cards' ? 'horizontal_cards' : 'grid';
  }

  private buildColumnsTemplate(columnCount: number): string {
    const columns: string[] = [];
    for (let index = 0; index < Math.max(1, columnCount); index += 1) {
      columns.push('1fr');
    }
    return columns.join(' ');
  }

  private resolveResponsiveFacts(input: BrowserTabsOverviewLayoutInput): AppWindowResponsiveFacts {
    return this.responsiveLayoutService.resolve({
      viewportWidth: input.sheetWidth,
      viewportHeight: input.sheetHeight
    });
  }
}

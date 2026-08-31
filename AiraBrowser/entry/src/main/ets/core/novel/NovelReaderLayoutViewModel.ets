import {
  AppWindowResponsiveFacts,
  AppWindowResponsiveLayoutService,
  AppWindowWidthClass
} from '../../services/layout/AppWindowResponsiveLayoutService';

export type NovelReaderLayoutMode = 'compact' | 'bounded' | 'expanded';

export interface NovelReaderLayoutInput {
  viewportWidth: number;
  viewportHeight: number;
}

export interface NovelReaderLayoutState {
  readonly mode: NovelReaderLayoutMode;
  readonly viewportWidth: number;
  readonly viewportHeight: number;
  readonly bookSurfaceWidth: number;
  readonly bookInfoPaneWidth: number;
  readonly bookCatalogPaneWidth: number;
  readonly bookPaneGap: number;
  readonly readerContentWidth: number;
  readonly readerPagedContentWidth: number;
  readonly readerChromeWidth: number;
  readonly readerChromeControlWidth: number;
  readonly readerPagedColumnCount: number;
  readonly readerPagedColumnGap: number;
  readonly readerContentTopInset: number;
  readonly readerContentBottomInset: number;
}

interface NovelReaderModeGeometry {
  readonly outerInset: number;
  readonly bookMaxWidth?: number;
  readonly bookInfoPaneWidth?: number;
  readonly bookPaneGap: number;
  readonly readerContentMaxWidth?: number;
  readonly readerChromeMaxWidth?: number;
}

const NOVEL_BOUNDED_OUTER_INSET: number = 32;
const NOVEL_EXPANDED_OUTER_INSET: number = 48;
const NOVEL_BOUNDED_BOOK_MAX_WIDTH: number = 720;
const NOVEL_EXPANDED_BOOK_MAX_WIDTH: number = 1180;
const NOVEL_EXPANDED_BOOK_INFO_PANE_WIDTH: number = 360;
const NOVEL_EXPANDED_BOOK_PANE_GAP: number = 36;
const NOVEL_BOUNDED_READER_MAX_WIDTH: number = 720;
const NOVEL_EXPANDED_READER_MAX_WIDTH: number = 840;
const NOVEL_BOUNDED_READER_CHROME_MAX_WIDTH: number = 760;
const NOVEL_EXPANDED_READER_CHROME_MAX_WIDTH: number = 880;
const NOVEL_READER_SPREAD_MIN_WIDTH_CLASS: AppWindowWidthClass = 'lg';
const NOVEL_READER_SPREAD_SIDE_INSET: number = 16;
const NOVEL_READER_SPREAD_MAX_WIDTH: number = 1200;
const NOVEL_READER_SPREAD_COLUMN_GAP: number = 24;
const NOVEL_READER_SPREAD_MIN_COLUMN_WIDTH: number = 360;
const NOVEL_READER_CONTENT_TOP_INSET: number = 20;
const NOVEL_READER_CONTENT_BOTTOM_INSET: number = 0;
const NOVEL_COMPACT_GEOMETRY: NovelReaderModeGeometry = {
  outerInset: 0,
  bookPaneGap: 0
};
const NOVEL_BOUNDED_GEOMETRY: NovelReaderModeGeometry = {
  outerInset: NOVEL_BOUNDED_OUTER_INSET,
  bookMaxWidth: NOVEL_BOUNDED_BOOK_MAX_WIDTH,
  bookPaneGap: 0,
  readerContentMaxWidth: NOVEL_BOUNDED_READER_MAX_WIDTH,
  readerChromeMaxWidth: NOVEL_BOUNDED_READER_CHROME_MAX_WIDTH
};
const NOVEL_EXPANDED_GEOMETRY: NovelReaderModeGeometry = {
  outerInset: NOVEL_EXPANDED_OUTER_INSET,
  bookMaxWidth: NOVEL_EXPANDED_BOOK_MAX_WIDTH,
  bookInfoPaneWidth: NOVEL_EXPANDED_BOOK_INFO_PANE_WIDTH,
  bookPaneGap: NOVEL_EXPANDED_BOOK_PANE_GAP,
  readerContentMaxWidth: NOVEL_EXPANDED_READER_MAX_WIDTH,
  readerChromeMaxWidth: NOVEL_EXPANDED_READER_CHROME_MAX_WIDTH
};

/** Maps canonical app-window facts to Novel-specific presentation geometry. */
export class NovelReaderLayoutViewModel {
  private readonly responsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  buildState(input: NovelReaderLayoutInput): NovelReaderLayoutState {
    const facts = this.responsiveLayoutService.resolve({
      viewportWidth: input.viewportWidth,
      viewportHeight: input.viewportHeight
    });
    const mode = this.resolveMode(facts);
    const geometry = this.resolveGeometry(mode);
    const availableWidth = Math.max(1, facts.width - geometry.outerInset * 2);
    const bookSurfaceWidth = this.resolveConstrainedWidth(
      facts.width,
      availableWidth,
      geometry.bookMaxWidth
    );
    const bookInfoPaneWidth = Math.min(geometry.bookInfoPaneWidth ?? bookSurfaceWidth, bookSurfaceWidth);
    const bookPaneGap = geometry.bookPaneGap;
    const bookCatalogPaneWidth = Math.max(1, bookSurfaceWidth - bookInfoPaneWidth - bookPaneGap);
    const readerSpreadWidth = this.resolveReaderSpreadWidth(facts);
    const readerPagedColumnCount = this.resolveReaderPagedColumnCount(facts, readerSpreadWidth);
    const readerContentWidth = this.resolveConstrainedWidth(
      facts.width,
      availableWidth,
      geometry.readerContentMaxWidth
    );
    const readerChromeWidth = this.resolveConstrainedWidth(
      facts.width,
      availableWidth,
      geometry.readerChromeMaxWidth
    );
    return {
      mode: mode,
      viewportWidth: facts.width,
      viewportHeight: facts.height,
      bookSurfaceWidth: bookSurfaceWidth,
      bookInfoPaneWidth: bookInfoPaneWidth,
      bookCatalogPaneWidth: bookCatalogPaneWidth,
      bookPaneGap: bookPaneGap,
      readerContentWidth: readerContentWidth,
      readerPagedContentWidth: readerPagedColumnCount > 1 ? readerSpreadWidth : readerContentWidth,
      readerChromeWidth: readerChromeWidth,
      readerChromeControlWidth: readerPagedColumnCount > 1 ? readerSpreadWidth : readerChromeWidth,
      readerPagedColumnCount: readerPagedColumnCount,
      readerPagedColumnGap: readerPagedColumnCount > 1 ? NOVEL_READER_SPREAD_COLUMN_GAP : 0,
      readerContentTopInset: NOVEL_READER_CONTENT_TOP_INSET,
      readerContentBottomInset: NOVEL_READER_CONTENT_BOTTOM_INSET
    };
  }

  private resolveMode(facts: AppWindowResponsiveFacts): NovelReaderLayoutMode {
    if ((facts.widthClass === 'xl' || facts.widthClass === 'xxl') && facts.aspectClass !== 'tall') {
      return 'expanded';
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(facts.widthClass, 'md')) {
      return 'bounded';
    }
    return 'compact';
  }

  private resolveGeometry(mode: NovelReaderLayoutMode): NovelReaderModeGeometry {
    if (mode === 'expanded') {
      return NOVEL_EXPANDED_GEOMETRY;
    }
    if (mode === 'bounded') {
      return NOVEL_BOUNDED_GEOMETRY;
    }
    return NOVEL_COMPACT_GEOMETRY;
  }

  private resolveReaderSpreadWidth(facts: AppWindowResponsiveFacts): number {
    return Math.min(
      Math.max(1, facts.width - NOVEL_READER_SPREAD_SIDE_INSET * 2),
      NOVEL_READER_SPREAD_MAX_WIDTH
    );
  }

  private resolveReaderPagedColumnCount(facts: AppWindowResponsiveFacts, spreadWidth: number): number {
    if (!this.responsiveLayoutService.isAtLeastWidthClass(
      facts.widthClass,
      NOVEL_READER_SPREAD_MIN_WIDTH_CLASS
    ) || facts.aspectClass === 'tall') {
      return 1;
    }
    const columnWidth = (spreadWidth - NOVEL_READER_SPREAD_COLUMN_GAP) / 2;
    return columnWidth >= NOVEL_READER_SPREAD_MIN_COLUMN_WIDTH ? 2 : 1;
  }

  private resolveConstrainedWidth(
    viewportWidth: number,
    availableWidth: number,
    maximumWidth?: number
  ): number {
    if (maximumWidth !== undefined) {
      return Math.min(availableWidth, maximumWidth);
    }
    return viewportWidth;
  }
}

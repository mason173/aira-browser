export type NovelBookshelfLayoutMode = 'phone' | 'large_screen';

export interface NovelBookshelfLayoutInput {
  layoutMode: NovelBookshelfLayoutMode;
  contentWidth: number;
}

export interface NovelBookshelfLayoutState {
  columnsTemplate: string;
  horizontalPadding: number;
  columnGap: number;
  rowGap: number;
  contentMaxWidth: number;
  categoryControlMaxWidth: number;
}

const NOVEL_BOOKSHELF_PHONE_COLUMNS: number = 3;
const NOVEL_BOOKSHELF_PHONE_HORIZONTAL_PADDING: number = 16;
const NOVEL_BOOKSHELF_PHONE_COLUMN_GAP: number = 12;
const NOVEL_BOOKSHELF_PHONE_ROW_GAP: number = 20;
const NOVEL_BOOKSHELF_LARGE_SCREEN_MIN_COLUMNS: number = 2;
const NOVEL_BOOKSHELF_LARGE_SCREEN_MAX_COLUMNS: number = 6;
const NOVEL_BOOKSHELF_LARGE_SCREEN_TARGET_CARD_WIDTH: number = 170;
const NOVEL_BOOKSHELF_LARGE_SCREEN_HORIZONTAL_PADDING: number = 32;
const NOVEL_BOOKSHELF_LARGE_SCREEN_COLUMN_GAP: number = 20;
const NOVEL_BOOKSHELF_LARGE_SCREEN_ROW_GAP: number = 28;
const NOVEL_BOOKSHELF_LARGE_SCREEN_CONTENT_MAX_WIDTH: number = 1240;
const NOVEL_BOOKSHELF_LARGE_SCREEN_CATEGORY_CONTROL_MAX_WIDTH: number = 420;

/** Keeps bookshelf cards at a book-cover scale instead of stretching a fixed three-column grid on PC. */
export class NovelBookshelfLayoutViewModel {
  buildState(input: NovelBookshelfLayoutInput): NovelBookshelfLayoutState {
    if (input.layoutMode !== 'large_screen') {
      return {
        columnsTemplate: this.buildColumnsTemplate(NOVEL_BOOKSHELF_PHONE_COLUMNS),
        horizontalPadding: NOVEL_BOOKSHELF_PHONE_HORIZONTAL_PADDING,
        columnGap: NOVEL_BOOKSHELF_PHONE_COLUMN_GAP,
        rowGap: NOVEL_BOOKSHELF_PHONE_ROW_GAP,
        contentMaxWidth: 0,
        categoryControlMaxWidth: 0
      };
    }
    const contentWidth = Math.min(
      NOVEL_BOOKSHELF_LARGE_SCREEN_CONTENT_MAX_WIDTH,
      Math.max(1, input.contentWidth)
    );
    const availableGridWidth = Math.max(
      1,
      contentWidth - NOVEL_BOOKSHELF_LARGE_SCREEN_HORIZONTAL_PADDING * 2
    );
    const preferredColumnSlotWidth = NOVEL_BOOKSHELF_LARGE_SCREEN_TARGET_CARD_WIDTH +
      NOVEL_BOOKSHELF_LARGE_SCREEN_COLUMN_GAP;
    const responsiveColumnCount = Math.round(
      (availableGridWidth + NOVEL_BOOKSHELF_LARGE_SCREEN_COLUMN_GAP) / preferredColumnSlotWidth
    );
    const columnCount = Math.max(
      NOVEL_BOOKSHELF_LARGE_SCREEN_MIN_COLUMNS,
      Math.min(NOVEL_BOOKSHELF_LARGE_SCREEN_MAX_COLUMNS, responsiveColumnCount)
    );
    return {
      columnsTemplate: this.buildColumnsTemplate(columnCount),
      horizontalPadding: NOVEL_BOOKSHELF_LARGE_SCREEN_HORIZONTAL_PADDING,
      columnGap: NOVEL_BOOKSHELF_LARGE_SCREEN_COLUMN_GAP,
      rowGap: NOVEL_BOOKSHELF_LARGE_SCREEN_ROW_GAP,
      contentMaxWidth: NOVEL_BOOKSHELF_LARGE_SCREEN_CONTENT_MAX_WIDTH,
      categoryControlMaxWidth: NOVEL_BOOKSHELF_LARGE_SCREEN_CATEGORY_CONTROL_MAX_WIDTH
    };
  }

  private buildColumnsTemplate(columnCount: number): string {
    const columns: string[] = [];
    for (let index = 0; index < Math.max(1, Math.floor(columnCount)); index += 1) {
      columns.push('1fr');
    }
    return columns.join(' ');
  }
}

import { SearchSuggestion } from '../../../common/models/BrowserModels';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  resolveBrowserBottomNeutralPrimaryColor,
  resolveBrowserBottomNeutralSecondaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import {
  BROWSER_SEARCH_LIST_DEFAULT_ROW_HEIGHT,
  BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT
} from '../../../core/browser/BrowserSearchListSurfaceLayoutViewModel';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';

const SUGGESTION_ROW_GAP: number = 12;
const SUGGESTION_MULTI_COLUMN_CARD_HORIZONTAL_PADDING: number = 16;
const SUGGESTION_MULTI_COLUMN_TITLE_SIZE: number = 15;
const SUGGESTION_TRAILING_ICON_SIZE: number = 18;
const SUGGESTION_DELETE_BUTTON_SIZE: number = 36;
const SUGGESTION_DELETE_ICON_SIZE: number = 18;
const CURRENT_SUGGESTION_CARD_RADIUS: number = 18;
const CURRENT_SUGGESTION_CARD_HORIZONTAL_PADDING: number = SUGGESTION_MULTI_COLUMN_CARD_HORIZONTAL_PADDING;
const CURRENT_SUGGESTION_CARD_VERTICAL_PADDING: number = 8;
const CURRENT_SUGGESTION_TITLE_ROW_HEIGHT: number = 28;
const CURRENT_SUGGESTION_ACTION_ROW_HEIGHT: number = 28;
const CURRENT_SUGGESTION_ACTION_BUTTON_RADIUS: number = CURRENT_SUGGESTION_ACTION_ROW_HEIGHT / 2;
const CURRENT_SUGGESTION_ACTION_ICON_SIZE: number = 18;
const CURRENT_SUGGESTION_ACTION_TEXT_SIZE: number = 14;
const CURRENT_SUGGESTION_ACTION_BUTTON_GAP: number = 4;
const CURRENT_SUGGESTION_ACTION_CONTENT_GAP: number = 5;
const CURRENT_SUGGESTION_CARD_HEIGHT: number =
  CURRENT_SUGGESTION_TITLE_ROW_HEIGHT + CURRENT_SUGGESTION_ACTION_BUTTON_GAP + CURRENT_SUGGESTION_ACTION_ROW_HEIGHT +
    CURRENT_SUGGESTION_CARD_VERTICAL_PADDING * 2;

interface BrowserSearchSuggestionVisualRow {
  key: string;
  suggestion?: SearchSuggestion;
}

interface BrowserSearchSuggestionVisualGridRow {
  rowIndex: number;
  key: string;
  rows: BrowserSearchSuggestionVisualRow[];
  fullSpan: boolean;
}

export type SearchSuggestionsPanelLayoutMode = 'bottomUp' | 'topDown';

@Component
export struct BrowserSearchSuggestionsPanel {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @Prop
  suggestions: SearchSuggestion[] = [];
  @Prop
  currentPageSuggestion: SearchSuggestion | undefined = undefined;
  @Prop
  horizontalPadding: number = 20;
  @Prop
  columns: number = 1;
  @Prop
  columnGap: number = 0;
  @Prop
  rowGap: number = SUGGESTION_ROW_GAP;
  @Prop
  regularRowHeight: number = BROWSER_SEARCH_LIST_DEFAULT_ROW_HEIGHT;
  @Prop
  regularRowContentFrameHeight: number = BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT;
  @Prop
  layoutMode: SearchSuggestionsPanelLayoutMode = 'topDown';
  @Prop
  scrollEnabled: boolean = true;
  @Prop
  cardBackgroundColor: ResourceColor | undefined = undefined;
  @Prop
  pressedBackgroundColor: ResourceColor | undefined = undefined;
  @Prop
  useNativeStateEffect: boolean = false;
  regularCardHorizontalPadding: number = SUGGESTION_MULTI_COLUMN_CARD_HORIZONTAL_PADDING;
  @Prop
  blankAreaBackEnabled: boolean = false;
  @Prop
  currentTabSuggestionRefId: string = '';
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onCurrentSuggestionShare: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onCurrentSuggestionCopy: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onCurrentSuggestionEdit: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onBlankAreaBack: () => void = () => {};

  build() {
    if (this.layoutMode === 'topDown') {
      if (this.scrollEnabled) {
        this.buildScrollableSuggestionList('100%')
      } else {
        this.buildSuggestionList()
      }
    } else {
      Stack({ alignContent: Alignment.BottomStart }) {
        this.buildBlankAreaBackTarget()

        Stack({ alignContent: Alignment.BottomStart }) {
          if (this.scrollEnabled) {
            this.buildScrollableSuggestionList('100%', this.resolvePinnedCurrentSuggestionBottomPadding())
          } else {
            this.buildSuggestionList(this.resolvePinnedCurrentSuggestionBottomPadding())
          }
          if (this.currentPageSuggestion !== undefined) {
            this.buildPinnedCurrentSuggestionCard(this.currentPageSuggestion)
          }
        }
        .width('100%')
        .height(this.resolveBottomUpContentHeight())
        .constraintSize({ maxHeight: '100%' })
        .hitTestBehavior(HitTestMode.Default)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private buildScrollableSuggestionList(height: string | number, bottomPadding: number = 0) {
    Scroll() {
      this.buildSuggestionList(bottomPadding)
    }
    .width('100%')
    .height(height)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildSuggestionList(bottomPadding: number = 0) {
    Column({ space: this.resolveRowGap() }) {
      ForEach(this.buildVisualGridRows(), (gridRow: BrowserSearchSuggestionVisualGridRow) => {
        this.buildSuggestionGroup(gridRow)
      }, (gridRow: BrowserSearchSuggestionVisualGridRow) => gridRow.key)
    }
    .width('100%')
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding, bottom: bottomPadding })
  }

  @Builder
  private buildBlankAreaBackTarget() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .hitTestBehavior(this.blankAreaBackEnabled ? HitTestMode.Block : HitTestMode.None)
      .focusable(false)
      .accessibilityText('收起搜索')
      .onClick(() => {
        if (this.blankAreaBackEnabled) {
          this.onBlankAreaBack();
        }
      })
  }

  @Builder
  private buildSuggestionGroup(group: BrowserSearchSuggestionVisualGridRow) {
    if (group.fullSpan) {
      Column() {
        if (group.rows.length > 0 && group.rows[0].suggestion !== undefined) {
          this.buildSuggestionCard(group.rows[0])
        }
      }
      .width('100%')
      .constraintSize({ minWidth: 0 })
    } else {
      Row({ space: this.columnGap }) {
        ForEach(group.rows, (row: BrowserSearchSuggestionVisualRow) => {
          Column() {
            if (row.suggestion !== undefined) {
              this.buildSuggestionCard(row)
            } else {
              Blank()
                .width('100%')
                .height(this.resolveRegularRowHeight())
            }
          }
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
        }, (row: BrowserSearchSuggestionVisualRow) => row.key)

        ForEach(this.resolvePlaceholderIndexes(group.rows.length), (placeholderIndex: number) => {
          Blank()
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
        }, (placeholderIndex: number) => `${group.rowIndex}-${placeholderIndex}`)
      }
      .width('100%')
    }
  }

  @Builder
  private buildSuggestionCard(row: BrowserSearchSuggestionVisualRow) {
    BrowserSearchSuggestionCard({
      suggestion: row.suggestion as SearchSuggestion,
      cardBackgroundColor: this.resolveCardBackgroundColor(),
      pressedBackgroundColor: this.resolvePressedBackgroundColor(),
      useNativeStateEffect: this.useNativeStateEffect,
      horizontalPadding: this.regularCardHorizontalPadding,
      currentTabSuggestionRefId: this.currentTabSuggestionRefId,
      rowHeight: this.resolveRegularRowHeight(),
      rowContentFrameHeight: this.resolveRegularRowContentFrameHeight(),
      compactContent: this.resolveColumnCount() > 1,
      onOpenSuggestion: (suggestion: SearchSuggestion) => {
        this.onOpenSuggestion(suggestion);
      },
      onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => {
        this.onDeleteHistorySuggestion(suggestion);
      },
      onCurrentSuggestionShare: (suggestion: SearchSuggestion) => {
        this.onCurrentSuggestionShare(suggestion);
      },
      onCurrentSuggestionCopy: (suggestion: SearchSuggestion) => {
        this.onCurrentSuggestionCopy(suggestion);
      },
      onCurrentSuggestionEdit: (suggestion: SearchSuggestion) => {
        this.onCurrentSuggestionEdit(suggestion);
      }
    })
  }

  @Builder
  private buildPinnedCurrentSuggestionCard(suggestion: SearchSuggestion) {
    Column() {
      BrowserSearchSuggestionCard({
        suggestion: suggestion,
        cardBackgroundColor: this.resolveCardBackgroundColor(),
        pressedBackgroundColor: this.resolvePressedBackgroundColor(),
        useNativeStateEffect: this.useNativeStateEffect,
        currentTabSuggestionRefId: this.currentTabSuggestionRefId,
        onOpenSuggestion: (nextSuggestion: SearchSuggestion) => {
          this.onOpenSuggestion(nextSuggestion);
        },
        onDeleteHistorySuggestion: (nextSuggestion: SearchSuggestion) => {
          this.onDeleteHistorySuggestion(nextSuggestion);
        },
        onCurrentSuggestionShare: (nextSuggestion: SearchSuggestion) => {
          this.onCurrentSuggestionShare(nextSuggestion);
        },
        onCurrentSuggestionCopy: (nextSuggestion: SearchSuggestion) => {
          this.onCurrentSuggestionCopy(nextSuggestion);
        },
        onCurrentSuggestionEdit: (nextSuggestion: SearchSuggestion) => {
          this.onCurrentSuggestionEdit(nextSuggestion);
        }
      })
    }
    .width('100%')
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
  }

  private resolveCardBackgroundColor(): ResourceColor {
    return this.cardBackgroundColor === undefined ? this.storedControlBackgroundColor : this.cardBackgroundColor;
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    return this.pressedBackgroundColor === undefined ? this.storedPressedBackgroundColor : this.pressedBackgroundColor;
  }

  private buildVisualRows(): BrowserSearchSuggestionVisualRow[] {
    const rows: BrowserSearchSuggestionVisualRow[] = [];
    if (this.layoutMode === 'topDown') {
      for (let index = 0; index < this.suggestions.length; index += 1) {
        this.appendRegularSuggestionRow(rows, this.suggestions[index]);
      }
      return rows;
    }
    for (let index = this.suggestions.length - 1; index >= 0; index -= 1) {
      this.appendRegularSuggestionRow(rows, this.suggestions[index]);
    }
    return rows;
  }

  private buildVisualGridRows(): BrowserSearchSuggestionVisualGridRow[] {
    const visualRows = this.buildVisualRows();
    const columns = this.resolveColumnCount();
    const gridRows: BrowserSearchSuggestionVisualGridRow[] = [];
    let pendingRows: BrowserSearchSuggestionVisualRow[] = [];
    for (let index = 0; index < visualRows.length; index += 1) {
      const row = visualRows[index];
      if (this.isCurrentTabVisualRow(row)) {
        this.appendRegularVisualGridRows(gridRows, pendingRows, columns);
        pendingRows = [];
        gridRows.push({
          rowIndex: gridRows.length,
          key: this.buildVisualGridRowKey([row], true),
          rows: [row],
          fullSpan: true
        });
        continue;
      }
      pendingRows.push(row);
      if (pendingRows.length >= columns) {
        this.appendRegularVisualGridRows(gridRows, pendingRows, columns);
        pendingRows = [];
      }
    }
    this.appendRegularVisualGridRows(gridRows, pendingRows, columns);
    return gridRows;
  }

  private appendRegularVisualGridRows(
    gridRows: BrowserSearchSuggestionVisualGridRow[],
    visualRows: BrowserSearchSuggestionVisualRow[],
    columns: number
  ): void {
    for (let index = 0; index < visualRows.length; index += columns) {
      const rows = visualRows.slice(index, index + columns);
      gridRows.push({
        rowIndex: gridRows.length,
        key: this.buildVisualGridRowKey(rows, false),
        rows: rows,
        fullSpan: false
      });
    }
  }

  private resolveColumnCount(): number {
    return Math.max(1, Math.floor(this.columns));
  }

  private buildVisualGridRowKey(rows: BrowserSearchSuggestionVisualRow[], fullSpan: boolean): string {
    const rowKeys = rows.map((row: BrowserSearchSuggestionVisualRow): string => row.key).join('::');
    return `${fullSpan ? 'full' : 'grid'}::${rowKeys}`;
  }

  private resolveRowGap(): number {
    return Math.max(0, Math.floor(this.rowGap));
  }

  private resolveRegularRowHeight(): number {
    return Math.max(1, Math.floor(this.regularRowHeight));
  }

  private resolveRegularRowContentFrameHeight(): number {
    return Math.max(1, Math.min(
      this.resolveRegularRowHeight(),
      Math.floor(this.regularRowContentFrameHeight)
    ));
  }

  private resolvePlaceholderIndexes(rowLength: number): number[] {
    const placeholderCount = Math.max(0, this.resolveColumnCount() - rowLength);
    const indexes: number[] = [];
    for (let index = 0; index < placeholderCount; index += 1) {
      indexes.push(index);
    }
    return indexes;
  }

  private appendSuggestionRow(rows: BrowserSearchSuggestionVisualRow[], suggestion: SearchSuggestion): void {
    rows.push({
      key: `item::${suggestion.source}::${suggestion.id}`,
      suggestion: suggestion
    });
  }

  private appendRegularSuggestionRow(rows: BrowserSearchSuggestionVisualRow[], suggestion: SearchSuggestion): void {
    if (this.isCurrentTabSuggestion(suggestion)) {
      return;
    }
    this.appendSuggestionRow(rows, suggestion);
  }

  private isCurrentTabVisualRow(row: BrowserSearchSuggestionVisualRow): boolean {
    if (row.suggestion === undefined) {
      return false;
    }
    return this.isCurrentTabSuggestion(row.suggestion);
  }

  private isCurrentTabSuggestion(suggestion: SearchSuggestion): boolean {
    return suggestion.source === 'tabs' &&
      this.currentTabSuggestionRefId.length > 0 &&
      suggestion.refId === this.currentTabSuggestionRefId;
  }

  private resolvePinnedCurrentSuggestionBottomPadding(): number {
    if (this.currentPageSuggestion === undefined) {
      return 0;
    }
    return CURRENT_SUGGESTION_CARD_HEIGHT +
      (this.buildVisualGridRows().length > 0 ? this.resolveRowGap() : 0);
  }

  private resolveBottomUpContentHeight(): number {
    const gridRowCount = this.buildVisualGridRows().length;
    let height = gridRowCount * this.resolveRegularRowHeight() +
      Math.max(0, gridRowCount - 1) * this.resolveRowGap();
    if (this.currentPageSuggestion !== undefined) {
      height += CURRENT_SUGGESTION_CARD_HEIGHT;
      if (gridRowCount > 0) {
        height += this.resolveRowGap();
      }
    }
    return height;
  }

}

@Component
struct BrowserSearchSuggestionCard {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @State
  private pressed: boolean = false;
  @Prop
  suggestion: SearchSuggestion = {
    id: '',
    title: '',
    source: '',
    target: ''
  };
  @Prop
  cardBackgroundColor: ResourceColor = '';
  @Prop
  pressedBackgroundColor: ResourceColor = '';
  @Prop
  useNativeStateEffect: boolean = false;
  horizontalPadding: number = SUGGESTION_MULTI_COLUMN_CARD_HORIZONTAL_PADDING;
  @Prop
  currentTabSuggestionRefId: string = '';
  @Prop rowHeight: number = BROWSER_SEARCH_LIST_DEFAULT_ROW_HEIGHT;
  @Prop rowContentFrameHeight: number = BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT;
  @Prop compactContent: boolean = false;
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onCurrentSuggestionShare: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onCurrentSuggestionCopy: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onCurrentSuggestionEdit: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};

  build() {
    if (this.isCurrentTabSuggestion()) {
      this.buildCurrentTabSuggestionCard()
    } else {
      this.buildDefaultSuggestionCard()
    }
  }

  @Builder
  private buildDefaultSuggestionCard() {
    Row({ space: this.compactContent ? 12 : 4 }) {
      if (this.compactContent) {
        this.buildCompactSuggestionOpenButton()
        this.buildCompactTrailingActionRegion()
      } else {
        this.buildExpandedSuggestionOpenButton()
        if (this.canDeleteHistorySuggestion()) {
          this.buildDeleteHistorySuggestionButton()
        }
      }
    }
    .width('100%')
    .height(this.rowHeight)
    .padding({
      left: this.horizontalPadding,
      right: this.horizontalPadding
    })
    .alignItems(VerticalAlign.Bottom)
    .backgroundColor(this.resolveBackgroundColor())
    .borderRadius(Math.max(1, this.rowHeight) / 2)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
  }

  @Builder
  private buildExpandedSuggestionOpenButton() {
    Button() {
      Stack({ alignContent: Alignment.BottomStart }) {
        this.buildExpandedSuggestionMainRow()
      }
      .width('100%')
      .height(this.rowHeight)
    }
    .layoutWeight(1)
    .height(this.rowHeight)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(false)
    .onClick(() => {
      this.onOpenSuggestion(this.suggestion);
    })
  }

  @Builder
  private buildCompactSuggestionOpenButton() {
    Button() {
      Stack({ alignContent: Alignment.BottomStart }) {
        this.buildCompactSuggestionMainRow()
      }
      .width('100%')
      .height(this.rowHeight)
    }
    .layoutWeight(1)
    .constraintSize({ minWidth: 0 })
    .height(this.rowHeight)
    .padding(0)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(false)
    .onClick(() => {
      this.onOpenSuggestion(this.suggestion);
    })
  }

  @Builder
  private buildCompactTrailingActionRegion() {
    Row({ space: 4 }) {
      this.buildTrailingIcon()
      if (this.canDeleteHistorySuggestion()) {
        this.buildDeleteHistorySuggestionButton()
      }
    }
    .width(SUGGESTION_TRAILING_ICON_SIZE +
      (this.canDeleteHistorySuggestion() ? 4 + SUGGESTION_DELETE_BUTTON_SIZE : 0))
    .height(this.resolveRowContentFrameHeight())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildDeleteHistorySuggestionButton() {
    Button() {
      Row() {
        AiraIcon({
          airaIconId: 'browser.tabs.delete',
          iconSize: SUGGESTION_DELETE_ICON_SIZE,
          iconColor: this.resolveSecondaryTextColor()
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(this.compactContent ? FlexAlign.Start : FlexAlign.End)
      .alignItems(VerticalAlign.Center)
    }
    .width(SUGGESTION_DELETE_BUTTON_SIZE)
    .height(this.resolveRowContentFrameHeight())
    .padding(0)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(this.resolveRowContentFrameHeight() / 2)
    .stateEffect(true)
    .focusable(false)
    .focusOnTouch(false)
    .accessibilityText('删除搜索记录')
    .onClick(() => {
      this.onDeleteHistorySuggestion(this.suggestion);
    })
  }

  @Builder
  private buildCurrentTabSuggestionCard() {
    Column() {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: CURRENT_SUGGESTION_CARD_HEIGHT,
        surfaceRadius: CURRENT_SUGGESTION_CARD_RADIUS,
        tintColor: resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        this.buildCurrentTabSuggestionCardContent()
      }
    }
    .width('100%')
    .height(CURRENT_SUGGESTION_CARD_HEIGHT)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
  }

  @Builder
  private buildCurrentTabSuggestionCardContent() {
    Column({ space: CURRENT_SUGGESTION_ACTION_BUTTON_GAP }) {
      this.buildCurrentSuggestionOpenButton()
      this.buildCurrentSuggestionActionRow()
    }
    .width('100%')
    .height(CURRENT_SUGGESTION_CARD_HEIGHT)
    .padding({
      left: CURRENT_SUGGESTION_CARD_HORIZONTAL_PADDING,
      right: CURRENT_SUGGESTION_CARD_HORIZONTAL_PADDING,
      top: CURRENT_SUGGESTION_CARD_VERTICAL_PADDING,
      bottom: CURRENT_SUGGESTION_CARD_VERTICAL_PADDING
    })
  }

  @Builder
  private buildCurrentSuggestionOpenButton() {
    Button() {
      this.buildCurrentSuggestionTitleRow()
    }
    .width('100%')
    .height(CURRENT_SUGGESTION_TITLE_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(false)
    .onClick(() => {
      this.onOpenSuggestion(this.suggestion);
    })
  }

  @Builder
  private buildCurrentSuggestionActionRow() {
    Row({ space: CURRENT_SUGGESTION_ACTION_BUTTON_GAP }) {
      this.buildCurrentSuggestionImageAction(
        'browser.toolbar.shareDocument',
        '分享',
        () => {
          this.onCurrentSuggestionShare(this.suggestion);
        }
      )
      this.buildCurrentSuggestionImageAction(
        'site.permission.clipboard',
        '复制',
        () => {
          this.onCurrentSuggestionCopy(this.suggestion);
        }
      )
      this.buildCurrentSuggestionImageAction(
        'browser.toolbar.edit',
        '编辑',
        () => {
          this.onCurrentSuggestionEdit(this.suggestion);
        }
      )
    }
    .width('100%')
    .height(CURRENT_SUGGESTION_ACTION_ROW_HEIGHT)
  }

  @Builder
  private buildCurrentSuggestionTitleRow() {
    Row({ space: 12 }) {
      Column() {
        Text(this.suggestion.title)
          .fontSize(SUGGESTION_MULTI_COLUMN_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolvePrimaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.buildTrailingIcon()
    }
    .width('100%')
    .height(CURRENT_SUGGESTION_TITLE_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildExpandedSuggestionMainRow() {
    Row({ space: 12 }) {
      Column() {
        Text(this.suggestion.title)
          .fontSize(SUGGESTION_MULTI_COLUMN_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolvePrimaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.buildTrailingIcon()
    }
    .width('100%')
    .height(this.resolveRowContentFrameHeight())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildCompactSuggestionMainRow() {
    Row() {
      Column() {
        Text(this.suggestion.title)
          .width('100%')
          .fontSize(SUGGESTION_MULTI_COLUMN_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolvePrimaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.resolveRowContentFrameHeight())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildCurrentSuggestionImageAction(iconId: AiraRenderableIconId, label: string, action: () => void) {
    Button() {
      Row({ space: CURRENT_SUGGESTION_ACTION_CONTENT_GAP }) {
        AiraIcon({
          airaIconId: iconId,
          iconSize: CURRENT_SUGGESTION_ACTION_ICON_SIZE,
          iconColor: this.resolvePrimaryTextColor()
        })

        Text(label)
          .fontSize(CURRENT_SUGGESTION_ACTION_TEXT_SIZE)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.resolvePrimaryTextColor())
          .maxLines(1)
      }
      .width('100%')
      .height(CURRENT_SUGGESTION_ACTION_ROW_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .height(CURRENT_SUGGESTION_ACTION_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(CURRENT_SUGGESTION_ACTION_BUTTON_RADIUS)
    .stateEffect(true)
    .focusable(false)
    .focusOnTouch(false)
    .accessibilityText(label)
    .onClick(() => {
      action();
    })
  }

  @Builder
  private buildTrailingIcon() {
    if (this.suggestion.source === 'history' || this.suggestion.source === 'search_history') {
      AiraIcon({
        airaIconId: 'membership.inviteRecordClock',
        iconSize: SUGGESTION_TRAILING_ICON_SIZE,
        iconColor: this.resolveSecondaryTextColor()
      })
    } else {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.resolveSecondaryTextColor()])
    }
  }

  private isCurrentTabSuggestion(): boolean {
    return this.suggestion.source === 'tabs' &&
      this.currentTabSuggestionRefId.length > 0 &&
      this.suggestion.refId === this.currentTabSuggestionRefId;
  }

  private canDeleteHistorySuggestion(): boolean {
    return this.suggestion.source === 'search_history' &&
      this.suggestion.refId !== undefined && this.suggestion.refId.trim().length > 0;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode);
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return resolveBrowserBottomNeutralSecondaryColor(this.storedResolvedThemeMode);
  }

  private resolveRowContentFrameHeight(): number {
    return Math.max(1, Math.min(this.rowHeight, Math.floor(this.rowContentFrameHeight)));
  }

  private updatePressed(type: TouchType): void {
    if (this.useNativeStateEffect) {
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.useNativeStateEffect) {
      return this.cardBackgroundColor;
    }
    return this.pressed ? this.pressedBackgroundColor : this.cardBackgroundColor;
  }

}

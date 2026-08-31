import {
  NOVEL_CATALOG_RANGE_SIZE,
  NovelReaderCatalogEntry
} from '../../../features/novel/NovelReaderModels';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { AiraIcon } from '../common/AiraIcon';
import {
  BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS,
  BrowserSheetActionButton
} from './BrowserModalBottomSheet';

const NOVEL_CATALOG_IMMERSIVE_CONTENT_TOP_PADDING: number = 146;

@Component
export struct NovelReaderCatalogSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#1A18202B';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#667085';
  @Prop bookTitle: string = '';
  @Prop bookAuthor: string = '';
  @Prop sourceHost: string = '';
  @Prop currentChapterUrl: string = '';
  @Prop catalog: NovelReaderCatalogEntry[] = [];
  @Prop catalogLoadingMore: boolean = false;
  @Prop catalogLoadingRangeStart: number = -1;
  @Prop catalogLoadingRangeEnd: number = -1;
  @Prop catalogHasMore: boolean = false;
  @Prop catalogTotalHint: number = 0;
  @Prop catalogRangeExtentHint: number = 0;
  @Prop catalogSupportsRandomAccess: boolean = false;
  onSelectChapter: (chapterId: string) => void = (_chapterId: string): void => {};
  onLoadRange: (startOrdinal: number, endOrdinal: number) => void =
    (_startOrdinal: number, _endOrdinal: number): void => {};
  @State private expandedCatalogRangeStarts: number[] = [0];
  private catalogScroller: Scroller = new Scroller();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.catalog.length === 0 && !this.catalogHasMore) {
        Column() {
          Text('没有找到章节目录')
            .fontSize(14)
            .fontColor(this.storedSecondaryTextColor)
        }
        .width('100%')
        .height('100%')
        .padding({ top: NOVEL_CATALOG_IMMERSIVE_CONTENT_TOP_PADDING })
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.catalogScroller }) {
          ForEach(this.resolveCatalogRangeStarts(), (startOrdinal: number) => {
            ListItemGroup({ header: this.buildCatalogRangeHeader(startOrdinal) }) {
              if (this.isCatalogRangeExpanded(startOrdinal)) {
                ForEach(this.entriesForCatalogRange(startOrdinal), (entry: NovelReaderCatalogEntry) => {
                  ListItem() {
                    Text(entry.title)
                      .fontSize(15)
                      .fontWeight(entry.url === this.currentChapterUrl ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(entry.url === this.currentChapterUrl
                        ? this.storedAccentColor
                        : this.storedPrimaryTextColor)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .padding({ top: 14, bottom: 14, left: 12 })
                  }
                  .onClick(() => {
                    this.onSelectChapter(entry.id);
                  })
                }, (entry: NovelReaderCatalogEntry): string => entry.id)
                if (this.isCatalogRangeLoading(startOrdinal)) {
                  ListItem() {
                    Row() {
                      LoadingProgress()
                        .width(24)
                        .height(24)
                        .color(this.storedAccentColor)
                    }
                    .width('100%')
                    .height(52)
                    .justifyContent(FlexAlign.Center)
                  }
                }
              }
            }
            .width('100%')
          }, (startOrdinal: number): string => `catalog-range-${startOrdinal}`)
        }
        .width('100%')
        .height('100%')
        .padding({
          left: APP_STANDARD_HORIZONTAL_PADDING,
          right: APP_STANDARD_HORIZONTAL_PADDING,
          top: NOVEL_CATALOG_IMMERSIVE_CONTENT_TOP_PADDING
        })
        .divider({ strokeWidth: 0.5, color: this.storedDividerColor })
        .linearGradientBlur(BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS, {
          fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
          direction: GradientDirection.Bottom
        })
      }

      Column() {
        Column({ space: 6 }) {
          Text(this.bookTitle.length > 0 ? this.bookTitle : '本书')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(this.resolveSubtitle())
            .fontSize(13)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding({
          left: APP_STANDARD_HORIZONTAL_PADDING,
          right: APP_STANDARD_HORIZONTAL_PADDING,
          top: 20,
          bottom: 12
        })

        Row() {
          Blank()
          BrowserSheetActionButton({
            label: '去当前',
            fillAvailableWidth: false,
            buttonWidth: 88,
            buttonHeight: 36,
            fontSize: 13,
            onAction: () => {
              this.scrollToCurrent();
            }
          })
        }
        .width('100%')
        .height(40)
        .padding({ left: APP_STANDARD_HORIZONTAL_PADDING, right: APP_STANDARD_HORIZONTAL_PADDING })

        Divider().color(this.storedDividerColor)
      }
      .width('100%')
      .zIndex(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedSurfaceColor)
  }

  private resolveSubtitle(): string {
    const identity: string = this.bookAuthor.length > 0 ? this.bookAuthor : this.sourceHost;
    const count: string = this.catalogTotalHint > this.catalog.length
      ? `已载入 ${this.catalog.length} / 共 ${this.catalogTotalHint} 章`
      : this.catalogHasMore && this.catalogTotalHint === 0
        ? `已载入 ${this.catalog.length} 章`
        : `共 ${this.catalog.length} 章`;
    if (identity.length > 0) {
      return `${identity} · ${count}`;
    }
    return count;
  }

  @Builder
  private buildCatalogRangeHeader(startOrdinal: number) {
    Row({ space: 10 }) {
      Text(`${startOrdinal + 1}-${this.resolveCatalogRangeEnd(startOrdinal) + 1}`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .layoutWeight(1)
      if (this.isCatalogRangeLoading(startOrdinal)) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.storedAccentColor)
      } else {
        AiraIcon({
          airaIconId: 'browser.toolbar.expandHint',
          iconSize: 14,
          iconColor: this.storedSecondaryTextColor
        })
          .rotate({ angle: this.isCatalogRangeExpanded(startOrdinal) ? 180 : 0 })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 2, right: 2 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.isCatalogRangeExpanded(startOrdinal) ? '折叠章节范围' : '展开章节范围')
    .onClick((): void => {
      this.toggleCatalogRange(startOrdinal);
    })
  }

  private toggleCatalogRange(startOrdinal: number): void {
    if (this.isCatalogRangeExpanded(startOrdinal)) {
      this.expandedCatalogRangeStarts = this.expandedCatalogRangeStarts.filter(
        (value: number): boolean => value !== startOrdinal
      );
      return;
    }
    this.expandedCatalogRangeStarts = this.expandedCatalogRangeStarts.concat([startOrdinal]);
    const endOrdinal: number = this.resolveCatalogRangeEnd(startOrdinal);
    this.onLoadRange(startOrdinal, endOrdinal);
  }

  private resolveCatalogRangeStarts(): number[] {
    const starts: number[] = [];
    const highestOrdinal: number = this.resolveHighestCatalogOrdinal();
    let groupCount: number = Math.max(1, Math.ceil(Math.max(
      this.catalogTotalHint,
      this.catalogRangeExtentHint,
      highestOrdinal + 1
    ) / NOVEL_CATALOG_RANGE_SIZE));
    if (!this.catalogSupportsRandomAccess && this.catalogHasMore) {
      const nextSequentialGroup: number = Math.floor((highestOrdinal + 1) / NOVEL_CATALOG_RANGE_SIZE);
      groupCount = Math.max(groupCount, nextSequentialGroup + 1);
    }
    for (let index: number = 0; index < groupCount; index += 1) {
      starts.push(index * NOVEL_CATALOG_RANGE_SIZE);
    }
    return starts;
  }

  private entriesForCatalogRange(startOrdinal: number): NovelReaderCatalogEntry[] {
    const endOrdinal: number = this.resolveCatalogRangeEnd(startOrdinal);
    return this.catalog.filter((entry: NovelReaderCatalogEntry): boolean =>
      entry.ordinal >= startOrdinal && entry.ordinal <= endOrdinal);
  }

  private resolveCatalogRangeEnd(startOrdinal: number): number {
    const defaultEnd: number = startOrdinal + NOVEL_CATALOG_RANGE_SIZE - 1;
    return this.catalogTotalHint > 0 ? Math.min(defaultEnd, this.catalogTotalHint - 1) : defaultEnd;
  }

  private resolveHighestCatalogOrdinal(): number {
    let highest: number = -1;
    for (let index: number = 0; index < this.catalog.length; index += 1) {
      highest = Math.max(highest, this.catalog[index].ordinal);
    }
    return highest;
  }

  private isCatalogRangeExpanded(startOrdinal: number): boolean {
    return this.expandedCatalogRangeStarts.indexOf(startOrdinal) >= 0;
  }

  private isCatalogRangeLoading(startOrdinal: number): boolean {
    return this.catalogLoadingMore && this.catalogLoadingRangeStart === startOrdinal &&
      this.catalogLoadingRangeEnd >= startOrdinal;
  }

  private scrollToCurrent(): void {
    for (let i = 0; i < this.catalog.length; i++) {
      if (this.catalog[i].url === this.currentChapterUrl) {
        const startOrdinal: number = Math.floor(this.catalog[i].ordinal / NOVEL_CATALOG_RANGE_SIZE) *
          NOVEL_CATALOG_RANGE_SIZE;
        if (!this.isCatalogRangeExpanded(startOrdinal)) {
          this.expandedCatalogRangeStarts = this.expandedCatalogRangeStarts.concat([startOrdinal]);
        }
        const starts: number[] = this.resolveCatalogRangeStarts();
        this.catalogScroller.scrollToIndex(Math.max(0, starts.indexOf(startOrdinal)), true, ScrollAlign.START);
        return;
      }
    }
  }
}

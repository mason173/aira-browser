import { HistoryDetailRow } from '../../../features/history/HistoryViewModel';
import {
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE,
  resolveBrowserSheetHeaderBlurRadius,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
  browserSheetHeaderBlurModifier
} from '../browser/BrowserModalBottomSheet';

@Component
export struct HistoryVisitDetailsSheet {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop rows: HistoryDetailRow[] = [];
  copyLink: () => void = () => {};
  onClose: () => void = () => {};
  @State private sheetHeaderBlurRadius: number = 0;
  @State private sheetScrollOffset: number = 0;

  build() {
    BrowserBottomSheetSurface({
      maxWidth: 560,
      fullHeight: true,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0
    }) {
      BrowserImmersiveSheetLayout({
        footerVisible: true,
        closeVisible: true,
        closeAccessibilityLabel: '关闭历史详情',
        onClose: (): void => {
          this.onClose();
        },
        scrollContent: () => {
          this.buildScrollContent()
        },
        header: () => {
          this.buildHeader()
        },
        footer: () => {
          this.buildFooter()
        }
      })
    }
  }

  @Builder
  private buildScrollContent() {
    Scroll(this.sheetBlurScroller) {
      Column({ space: 14 }) {
        ForEach(this.rows, (row: HistoryDetailRow) => {
          this.buildDetailRow(row);
        })
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
    .attributeModifier(browserSheetHeaderBlurModifier(this.sheetHeaderBlurRadius))
    .onAppear(() => {
      this.resetSheetHeaderBlur();
    })
    .onDidScroll((_xOffset: number, yOffset: number) => {
      this.noteSheetScrollOffset(this.sheetBlurScroller.currentOffset().yOffset);
    })
  }

  @Builder
  private buildHeader() {
    BrowserFeatureSheetHeader({
      title: '历史详情',
      titleColor: this.storedPrimaryTextColor
    })
  }

  private sheetBlurScroller: Scroller = new Scroller();

  private noteSheetScrollOffset(offset: number): void {
    if (!Number.isFinite(offset)) {
      return;
    }
    const next = Math.max(0, offset);
    if (next === this.sheetScrollOffset) {
      return;
    }
    this.sheetScrollOffset = next;
    this.sheetHeaderBlurRadius = resolveBrowserSheetHeaderBlurRadius(next);
  }

  private resetSheetHeaderBlur(): void {
    this.sheetScrollOffset = 0;
    this.sheetHeaderBlurRadius = 0;
  }

  @Builder
  private buildFooter() {
    Row({ space: 12 }) {
      BrowserSheetActionButton({
        label: '复制链接',
        onAction: () => {
          this.copyLink();
        }
      })

      BrowserSheetActionButton({
        label: '完成',
        onAction: () => {
          this.onClose();
        }
      })
    }
    .width('100%')
  }

  @Builder
  private buildDetailRow(row: HistoryDetailRow) {
    Column({ space: 6 }) {
      Text(row.label)
        .width('100%')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)

      Text(row.value)
        .width('100%')
        .fontSize(16)
        .lineHeight(24)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Start)
        .wordBreak(WordBreak.BREAK_ALL)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 2, bottom: 2 })
  }
}

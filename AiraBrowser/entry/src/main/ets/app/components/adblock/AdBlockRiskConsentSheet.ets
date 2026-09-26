import { AdBlockRiskConsentSheetState } from '../../../core/adblock/AdBlockRiskConsentViewModel';
import {
  DESKTOP_DIALOG_PADDING_VP,
  DESKTOP_DIALOG_TITLE_FONT_SIZE_FP
} from '../../../core/browser/BrowserDialogPresentationTokens';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
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
const AD_BLOCK_RISK_SHEET_MAX_WIDTH: number = 540;
const AD_BLOCK_RISK_BODY_MAX_HEIGHT: number = 420;
@Component
export struct AdBlockRiskConsentSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: AdBlockRiskConsentSheetState = {
    title: '',
    intro: '',
    riskItems: [],
    confirmation: '',
    primaryActionLabel: '',
    secondaryActionLabel: ''
  };
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAccept: () => void = () => {};
  onDecline: () => void = () => {};
  @State private sheetHeaderBlurRadius: number = 0;
  @State private sheetScrollOffset: number = 0;

  build() {
    BrowserBottomSheetSurface({
      maxWidth: AD_BLOCK_RISK_SHEET_MAX_WIDTH,
      fullHeight: this.layoutMode === 'phone',
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet',
      horizontalPadding: this.layoutMode === 'phone' ? 0 : DESKTOP_DIALOG_PADDING_VP,
      topPadding: this.layoutMode === 'phone' ? 0 : DESKTOP_DIALOG_PADDING_VP,
      bottomPadding: this.layoutMode === 'phone' ? 0 : DESKTOP_DIALOG_PADDING_VP
    }) {
      if (this.layoutMode === 'phone') {
        this.buildImmersivePhoneLayout()
      } else {
        this.buildLargeScreenLayout()
      }
    }
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      footerVisible: true,
            closeVisible: true,
      closeAccessibilityLabel: '关闭广告拦截风险提示',
      onClose: (): void => {
        this.onDecline();
      },
      scrollContent: () => {
        this.buildPhoneScrollContent()
      },
      header: () => {
        this.buildPhoneHeader()
      },
      footer: () => {
        this.buildActions()
      }
    })
  }

  @Builder
  private buildPhoneScrollContent() {
    Scroll(this.sheetBlurScroller) {
      Column() {
        this.buildRiskContent()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE
      })
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
  private buildPhoneHeader() {
    BrowserFeatureSheetHeader({
      title: this.state.title,
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
  private buildLargeScreenLayout() {
    Column({ space: 18 }) {
      this.buildHeader()

      Scroll() {
        this.buildRiskContent()
      }
      .width('100%')
      .constraintSize({ maxHeight: AD_BLOCK_RISK_BODY_MAX_HEIGHT })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })

      this.buildActions()
    }
    .width('100%')
  }

  @Builder
  private buildHeader() {
    Text(this.state.title)
      .width('100%')
      .fontSize(DESKTOP_DIALOG_TITLE_FONT_SIZE_FP)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.storedPrimaryTextColor)
      .textAlign(TextAlign.Start)
  }

  @Builder
  private buildRiskContent() {
    Column({ space: 14 }) {
      Text(this.state.intro)
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontColor(this.storedPrimaryTextColor)

      Column({ space: 12 }) {
        ForEach(this.state.riskItems, (item: string, index: number) => {
          this.buildRiskItem(item, index)
        }, (item: string) => item)
      }
      .width('100%')

      Text(this.state.confirmation)
        .width('100%')
        .fontSize(14)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width('100%')
  }

  @Builder
  private buildActions() {
    // The phone footer hosts this builder inside its own Row, so the stack lives here:
    // a stacked action keeps width 100%, and two of those laid out side by side by the
    // caller would overflow the sheet.
    Row({ space: 12 }) {
      BrowserSheetActionButton({
        label: this.state.primaryActionLabel,
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        onAction: () => {
          this.onAccept();
        }
      })

      BrowserSheetActionButton({
        label: this.state.secondaryActionLabel,
        onAction: () => {
          this.onDecline();
        }
      })
    }
    .width('100%')
  }

  @Builder
  private buildRiskItem(item: string, index: number) {
    Row({ space: 10 }) {
      Text(`${index + 1}`)
        .width(22)
        .height(22)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.storedControlBackgroundColor)
        .borderRadius(11)

      Text(item)
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

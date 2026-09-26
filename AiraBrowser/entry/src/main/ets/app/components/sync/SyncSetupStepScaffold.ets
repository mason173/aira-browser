import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { BrowserLargeScreenModalHeader } from '../browser/BrowserLargeScreenModalHeader';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE,
  resolveBrowserSheetHeaderBlurRadius,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
} from '../browser/BrowserModalBottomSheet';
import { BROWSER_LARGE_SCREEN_MODAL_HEADER_HEIGHT_VP } from '../../../core/browser/BrowserModalPresentationTokens';

const SYNC_SETUP_LARGE_SCREEN_SUMMARY_BLOCK_VP: number = 92;
const SYNC_SETUP_LARGE_SCREEN_SUBMIT_BUTTON_VP: number = 44;
const SYNC_SETUP_LARGE_SCREEN_MIN_SCROLL_VP: number = 120;

export type SyncSetupStepLayoutMode = 'phone' | 'large_screen';

@Component
export struct SyncSetupStepScaffold {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop showBackButton: boolean = false;
  @Prop layoutMode: SyncSetupStepLayoutMode = 'phone';
  @Prop maxHeightVp: number = 0;
  @Prop showSubmitButton: boolean = false;
  @Prop submitLabel: string = '';
  @Prop isBusy: boolean = false;
  @Prop canSubmit: boolean = true;
  onBack: () => void = () => {};
  onClose: () => void = () => {};
  onSubmit: () => void = () => {};
  onContentHeight: (heightVp: number) => void = (_heightVp: number) => {};
  @BuilderParam content: () => void = this.emptyContent;
  @State private sheetHeaderBlurRadius: number = 0;
  @State private sheetScrollOffset: number = 0;

  build() {
    if (this.layoutMode === 'large_screen') {
      this.buildLargeScreenLayout()
    } else {
      this.buildImmersivePhoneLayout()
    }
  }

  @Builder
  private buildLargeScreenLayout() {
    Column({ space: 0 }) {
      BrowserLargeScreenModalHeader({
        title: this.title,
        dialogMode: true,
        showBackButton: this.showBackButton,
        onBack: this.onBack,
        onClose: this.onClose
      })
      this.buildSummary()

      Scroll() {
        Column({ space: 12 }) {
          this.content()
        }
        .width('100%')
        .padding({
          left: APP_STANDARD_HORIZONTAL_PADDING,
          right: APP_STANDARD_HORIZONTAL_PADDING,
          bottom: 12
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .flexShrink(1)
      .constraintSize({ minHeight: 0, maxHeight: this.resolveLargeScreenScrollMaxHeightVp() })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .align(Alignment.Top)

      if (this.showSubmitButton) {
        this.buildSubmitFooter()
      }
    }
    .width('100%')
    .constraintSize({ maxHeight: this.resolveLargeScreenColumnMaxHeightVp() })
    .backgroundColor(Color.Transparent)
    .onAreaChange((_oldArea: Area, area: Area) => {
      const heightVp = Number(area.height);
      if (Number.isFinite(heightVp) && heightVp > 0) {
        this.onContentHeight(heightVp);
      }
    })
  }

  private resolveLargeScreenColumnMaxHeightVp(): number {
    if (!Number.isFinite(this.maxHeightVp) || this.maxHeightVp <= 0) {
      return 4000;
    }
    return this.maxHeightVp;
  }

  private resolveLargeScreenScrollMaxHeightVp(): number {
    if (!Number.isFinite(this.maxHeightVp) || this.maxHeightVp <= 0) {
      return 4000;
    }
    let chromeVp = BROWSER_LARGE_SCREEN_MODAL_HEADER_HEIGHT_VP + SYNC_SETUP_LARGE_SCREEN_SUMMARY_BLOCK_VP;
    if (this.showSubmitButton) {
      chromeVp += SYNC_SETUP_LARGE_SCREEN_SUBMIT_BUTTON_VP + BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING;
    }
    return Math.max(SYNC_SETUP_LARGE_SCREEN_MIN_SCROLL_VP, this.maxHeightVp - chromeVp);
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      footerVisible: this.showSubmitButton,
      topBlurRadius: this.sheetHeaderBlurRadius,
      closeVisible: true,
      closeAccessibilityLabel: '关闭',
      onClose: (): void => {
        this.onClose();
      },
      scrollContent: () => {
        this.buildPhoneScrollContent()
      },
      header: () => {
        this.buildPhoneHeader()
      },
      footer: () => {
        this.buildSubmitButton()
      }
    })
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedControlBackgroundColor)
  }

  @Builder
  private buildPhoneScrollContent() {
    Scroll() {
      Column({ space: 12 }) {
        this.buildSummaryText()
        this.content()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: APP_STANDARD_HORIZONTAL_PADDING,
        right: APP_STANDARD_HORIZONTAL_PADDING,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: this.showSubmitButton
          ? BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE
          : BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
    .onAppear(() => {
      this.resetSheetHeaderBlur();
    })
    .onDidScroll((delta: number) => {
      this.noteSheetScrollDelta(delta);
    })
  }

  @Builder
  private buildPhoneHeader() {
    BrowserFeatureSheetHeader({
      title: this.title,
      titleColor: this.storedPrimaryTextColor,
      showLeadingButton: this.showBackButton,
      leadingAccessibilityLabel: '返回',
      onLeadingAction: (): void => {
        if (this.showBackButton) {
          this.onBack();
        }
      }
    })
  }

  private noteSheetScrollDelta(delta: number): void {
    if (!Number.isFinite(delta)) {
      return;
    }
    this.sheetScrollOffset = Math.max(0, this.sheetScrollOffset + delta);
    this.sheetHeaderBlurRadius = resolveBrowserSheetHeaderBlurRadius(this.sheetScrollOffset);
  }

  private resetSheetHeaderBlur(): void {
    this.sheetScrollOffset = 0;
    this.sheetHeaderBlurRadius = 0;
  }

  @Builder
  private buildSummary() {
    Column() {
      this.buildSummaryText()
    }
    .width('100%')
    .padding({
      left: APP_STANDARD_HORIZONTAL_PADDING,
      right: APP_STANDARD_HORIZONTAL_PADDING,
      top: 16,
      bottom: 16
    })
  }

  @Builder
  private buildSummaryText() {
    Text(this.summary)
      .width('100%')
      .fontSize(14)
      .lineHeight(20)
      .fontColor(this.storedSecondaryTextColor)
      .textAlign(TextAlign.Start)
      .maxLines(3)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private buildSubmitFooter() {
    Column() {
      this.buildSubmitButton()
    }
    .width('100%')
    .padding({
      left: APP_STANDARD_HORIZONTAL_PADDING,
      right: APP_STANDARD_HORIZONTAL_PADDING,
      bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
    })
  }

  @Builder
  private buildSubmitButton() {
    BrowserSheetActionButton({
      label: this.submitLabel,
      emphasis: 'primary',
      actionEnabled: !this.isBusy && this.canSubmit,
      accentColor: this.storedAccentColor,
      fillAvailableWidth: false,
      buttonWidth: '100%',
      buttonHeight: 44,
      fontSize: 15,
      onAction: () => {
        this.onSubmit();
      }
    })
  }

  @Builder
  private emptyContent() {
  }
}

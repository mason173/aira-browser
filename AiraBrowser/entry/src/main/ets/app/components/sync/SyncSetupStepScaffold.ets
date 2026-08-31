import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { SettingsScrollBody } from '../settings/SettingsLayout';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { BrowserLargeScreenModalHeader } from '../browser/BrowserLargeScreenModalHeader';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
} from '../browser/BrowserModalBottomSheet';

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
  @Prop showSubmitButton: boolean = false;
  @Prop submitLabel: string = '';
  @Prop isBusy: boolean = false;
  @Prop canSubmit: boolean = true;
  onBack: () => void = () => {};
  onClose: () => void = () => {};
  onSubmit: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;

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

      Column() {
        SettingsScrollBody({
          contentSpace: 12,
          topPadding: 0,
          bottomPadding: 12,
          clipContent: true
        }) {
          this.content()
        }
      }
      .layoutWeight(1)

      if (this.showSubmitButton) {
        this.buildSubmitFooter()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      footerVisible: this.showSubmitButton,
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
  }

  @Builder
  private buildPhoneHeader() {
    BrowserFeatureSheetHeader({
      title: this.title,
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: this.showBackButton ? '返回' : '关闭',
      onLeadingAction: () => {
        if (this.showBackButton) {
          this.onBack();
        } else {
          this.onClose();
        }
      }
    })
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

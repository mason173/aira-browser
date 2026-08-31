import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { TranslationLanguageOptionView } from '../../../core/translation/WebpageTranslationSettingsViewModel';
import { WebpageTranslationTargetLanguageAction } from '../../../core/translation/WebpageTranslationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout
} from '../browser/BrowserModalBottomSheet';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  TRANSLATION_TARGET_LANGUAGE_OVERLAY_ANIMATION_DURATION_MS,
  TRANSLATION_TARGET_LANGUAGE_OVERLAY_ENTER_OFFSET_Y,
  TRANSLATION_TARGET_LANGUAGE_OVERLAY_SHEET_HEIGHT
} from '../browser/BrowserShellPresentationTokens';
import {
  SettingsOptionRow,
  SettingsRowPosition
} from '../settings/SettingsRows';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';

const WEBPAGE_TRANSLATION_LANGUAGE_SHEET_MAX_WIDTH: number = 520;
const WEBPAGE_TRANSLATION_LANGUAGE_RADIO_GROUP: string = 'webpage-translation-target-language';

@Component
export struct WebpageTranslationTargetLanguageSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop selectedLanguage: string = 'zh-CN';
  @Prop helperText: string = '';
  @Prop options: TranslationLanguageOptionView[] = [];
  @Prop fullHeight: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onSelectTargetLanguage: (languageCode: string) => void = (_languageCode: string) => {};
  onClose: () => void = () => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: this.fullHeight,
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet',
      maxWidth: WEBPAGE_TRANSLATION_LANGUAGE_SHEET_MAX_WIDTH,
      horizontalPadding: this.shouldUseImmersivePhoneLayout() ? 0 : 16,
      topPadding: this.shouldUseImmersivePhoneLayout() ? 0 : 26,
      bottomPadding: this.shouldUseImmersivePhoneLayout() ? 0 : 24,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      if (this.shouldUseImmersivePhoneLayout()) {
        this.buildImmersivePhoneLayout()
      } else {
        this.buildRegularLayout()
      }
    }
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      scrollContent: () => {
        this.buildImmersivePhoneList()
      },
      header: () => {
        this.buildImmersivePhoneHeader()
      }
    })
  }

  @Builder
  private buildImmersivePhoneList() {
      List({ space: 0 }) {
        if (this.helperText.trim().length > 0) {
          ListItem() {
            Text(this.helperText)
              .width('100%')
              .fontSize(13)
              .lineHeight(18)
              .fontColor(this.storedSecondaryTextColor)
              .padding({ left: 16, right: 16, bottom: 16 })
          }
        }

        ListItem() {
          Column() {
            this.buildLanguageGroup()
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }

        ListItem() {
          Column() {
            Blank()
          }
          .width('100%')
          .height(BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .clip(false)
  }

  @Builder
  private buildImmersivePhoneHeader() {
    BrowserFeatureSheetHeader({
      title: '目标语言',
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: '关闭目标语言',
      onLeadingAction: () => {
        this.onClose();
      }
    })
  }

  @Builder
  private buildRegularLayout() {
    Column({ space: 16 }) {
      if (this.layoutMode === 'phone') {
        Text('目标语言')
          .width('100%')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
      }

      if (this.helperText.trim().length > 0) {
        Text(this.helperText)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(this.storedSecondaryTextColor)
      }

      if (this.fullHeight) {
        List({ space: 0 }) {
          ListItem() {
            this.buildLanguageGroup()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        this.buildLanguageGroup()
      }
    }
    .width('100%')
    .height(this.fullHeight ? '100%' : '')
  }

  @Builder
  private buildLanguageGroup() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      ForEach(this.options, (option: TranslationLanguageOptionView, index: number) => {
        this.buildTargetLanguageRow(option, index, this.options.length)
        if (index < this.options.length - 1) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
      }, (option: TranslationLanguageOptionView) => option.code)
    }
  }

  @Builder
  private buildTargetLanguageRow(option: TranslationLanguageOptionView, index: number, total: number) {
    SettingsOptionRow({
      title: option.label,
      helperText: option.helperText,
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: this.selectedLanguage === option.code,
      isEnabled: true,
      radioGroup: WEBPAGE_TRANSLATION_LANGUAGE_RADIO_GROUP,
      radioValue: option.code,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      selectedIndicatorColor: this.storedAccentColor,
      onAction: () => {
        this.onSelectTargetLanguage(option.code);
      }
    })
  }

  private resolveRowPosition(index: number, total: number): SettingsRowPosition {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === total - 1) {
      return 'last';
    }
    return 'middle';
  }

  private shouldUseImmersivePhoneLayout(): boolean {
    return this.layoutMode === 'phone' && this.fullHeight;
  }
}

@Component
export struct WebpageTranslationTargetLanguageOverlay {
  @Prop visible: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @Prop selectedLanguage: string = 'zh-CN';
  @Prop helperText: string = '';
  @Prop options: TranslationLanguageOptionView[] = [];
  onAction: (action: WebpageTranslationTargetLanguageAction) => void =
    (_action: WebpageTranslationTargetLanguageAction) => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: this.layoutMode,
      title: '目标语言',
      phoneSheetHeight: TRANSLATION_TARGET_LANGUAGE_OVERLAY_SHEET_HEIGHT,
      phoneEnterOffsetY: TRANSLATION_TARGET_LANGUAGE_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: TRANSLATION_TARGET_LANGUAGE_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      desktopWidth: '68%',
      desktopHeight: '68%',
      desktopMinWidth: 500,
      desktopMaxWidth: 620,
      desktopMinHeight: 400,
      desktopMaxHeight: 560,
      onDismiss: () => {
        this.onAction({ type: 'dismiss' });
      }
    }) {
      WebpageTranslationTargetLanguageSheet({
        selectedLanguage: this.selectedLanguage,
        helperText: this.helperText,
        options: this.options,
        fullHeight: true,
        layoutMode: this.layoutMode,
        onClose: () => {
          this.onAction({ type: 'dismiss' });
        },
        onSelectTargetLanguage: (languageCode: string) => {
          this.onAction({ type: 'select', languageCode: languageCode });
        }
      })
    }
  }
}

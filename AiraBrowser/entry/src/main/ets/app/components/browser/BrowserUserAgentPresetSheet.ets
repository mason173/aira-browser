import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserUserAgentMode,
  BrowserUserAgentPresetId
} from '../../../common/models/BrowserModels';
import {
  BrowserCustomUserAgentOptionView,
  BrowserUserAgentOptionView
} from '../../../core/settings/BrowserUserAgentSettingsViewModel';
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
} from './BrowserModalBottomSheet';
import {
  SettingsOptionRow,
  SettingsRowPosition
} from '../settings/SettingsRows';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSectionTitle
} from '../settings/SettingsLayout';

const BROWSER_USER_AGENT_PRESET_SHEET_MAX_WIDTH: number = 560;
const BROWSER_USER_AGENT_PRESET_RADIO_GROUP: string = 'browser-user-agent-preset';
@Component
export struct BrowserUserAgentPresetSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop selectedPresetId: BrowserUserAgentPresetId = '';
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @Prop selectedMode: BrowserUserAgentMode = 'mobile';
  @Prop mobileOptions: BrowserUserAgentOptionView[] = [];
  @Prop desktopOptions: BrowserUserAgentOptionView[] = [];
  @Prop customOptions: BrowserCustomUserAgentOptionView[] = [];
  onBack: () => void = () => {};
  onSelectPreset: (presetId: BrowserUserAgentPresetId) => void = (_presetId: BrowserUserAgentPresetId) => {};
  onSelectCustomUserAgent: (recordId: string) => void = (_recordId: string) => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet',
      contentJustifyContent: FlexAlign.Start,
      maxWidth: BROWSER_USER_AGENT_PRESET_SHEET_MAX_WIDTH,
      horizontalPadding: this.layoutMode === 'phone' ? 0 : 16,
      topPadding: this.layoutMode === 'phone' ? 0 : 26,
      bottomPadding: this.layoutMode === 'phone' ? 0 : 24,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      if (this.layoutMode === 'phone') {
        BrowserImmersiveSheetLayout({
          scrollContent: () => {
            this.buildScrollContent(true)
          },
          header: () => {
            this.buildHeader()
          }
        })
      } else {
        this.buildScrollContent(false)
      }
    }
  }

  @Builder
  private buildHeader() {
    BrowserFeatureSheetHeader({
      title: '网页标识',
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: '返回网站版本',
      onLeadingAction: () => {
        this.onBack();
      }
    })
  }

  @Builder
  private buildScrollContent(immersive: boolean) {
    Scroll() {
      Column({ space: 14 }) {
        this.buildOptionGroup('移动端网页', this.mobileOptions)
        this.buildOptionGroup('桌面端网页', this.desktopOptions)
        this.buildCustomOptionGroup()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: immersive ? 16 : 0,
        right: immersive ? 16 : 0,
        top: immersive ? BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET : 0,
        bottom: immersive ? BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING : 0
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildOptionGroup(title: string, options: BrowserUserAgentOptionView[]) {
    Column({ space: 8 }) {
      SettingsSectionTitle({
        title: title,
        secondaryTextColor: this.storedSecondaryTextColor
      })

      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(options, (option: BrowserUserAgentOptionView, index: number) => {
          this.buildOptionRow(option, index, options.length)
          if (index < options.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: BrowserUserAgentOptionView) => `${option.mode}:${option.id}:${this.isSelected(option) ? 'selected' : 'idle'}`)
      }
    }
    .width('100%')
  }

  @Builder
  private buildCustomOptionGroup() {
    if (this.customOptions.length > 0) {
      Column({ space: 8 }) {
        SettingsSectionTitle({
          title: '自定义 UA',
          secondaryTextColor: this.storedSecondaryTextColor
        })

        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          ForEach(this.customOptions, (option: BrowserCustomUserAgentOptionView, index: number) => {
            this.buildCustomOptionRow(option, index, this.customOptions.length)
            if (index < this.customOptions.length - 1) {
              SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            }
          }, (option: BrowserCustomUserAgentOptionView) => `${option.mode}:${option.id}:${this.isCustomSelected(option) ? 'selected' : 'idle'}`)
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildCustomOptionRow(option: BrowserCustomUserAgentOptionView, index: number, total: number) {
    SettingsOptionRow({
      title: option.title,
      helperText: option.subtitle,
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: this.isCustomSelected(option),
      isEnabled: true,
      radioGroup: BROWSER_USER_AGENT_PRESET_RADIO_GROUP,
      radioValue: `${option.mode}:${option.id}`,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      selectedIndicatorColor: this.storedAccentColor,
      onAction: (): void => {
        this.selectCustomOption(option);
      }
    })
  }

  @Builder
  private buildOptionRow(option: BrowserUserAgentOptionView, index: number, total: number) {
    SettingsOptionRow({
      title: option.title,
      helperText: option.subtitle,
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: this.isSelected(option),
      isEnabled: true,
      radioGroup: BROWSER_USER_AGENT_PRESET_RADIO_GROUP,
      radioValue: `${option.mode}:${option.id}`,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      selectedIndicatorColor: this.storedAccentColor,
      onAction: (): void => {
        this.selectOption(option);
      }
    })
  }

  private isSelected(option: BrowserUserAgentOptionView): boolean {
    return this.selectedMode === option.mode && this.selectedPresetId === option.id;
  }

  private isCustomSelected(option: BrowserCustomUserAgentOptionView): boolean {
    return this.selectedMode === 'custom' && this.selectedPresetId === option.id;
  }

  private selectOption(option: BrowserUserAgentOptionView): void {
    if (this.isSelected(option)) {
      return;
    }
    this.onSelectPreset(option.id);
  }

  private selectCustomOption(option: BrowserCustomUserAgentOptionView): void {
    if (this.isCustomSelected(option)) {
      return;
    }
    this.onSelectCustomUserAgent(option.id);
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

}

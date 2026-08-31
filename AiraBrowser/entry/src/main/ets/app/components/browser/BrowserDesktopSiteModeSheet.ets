import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserDesktopSiteModeOptionState,
  BrowserDesktopSiteModeSheetState
} from '../../../core/browser/BrowserDesktopSiteModeSheetViewModel';
import { BrowserDesktopSiteMode } from '../../../services/web/BrowserUserAgentService';
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
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton
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

const BROWSER_DESKTOP_SITE_MODE_SHEET_MAX_WIDTH: number = 520;
const BROWSER_DESKTOP_SITE_MODE_RADIO_GROUP: string = 'browser-desktop-site-mode';
@Component
export struct BrowserDesktopSiteModeSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: BrowserDesktopSiteModeSheetState = {
    options: [],
    defaultUserAgentSummary: 'Aira默认'
  };
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onClose: () => void = () => {};
  onSelectMode: (mode: BrowserDesktopSiteMode) => void = (_mode: BrowserDesktopSiteMode) => {};
  onOpenDefaultUserAgent: () => void = () => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet',
      maxWidth: BROWSER_DESKTOP_SITE_MODE_SHEET_MAX_WIDTH,
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
      title: '网站版本',
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: '关闭网站版本',
      onLeadingAction: () => {
        this.onClose();
      }
    })
  }

  @Builder
  private buildScrollContent(immersive: boolean) {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 8 }) {
          SettingsSectionTitle({
            title: '当前站点',
            secondaryTextColor: this.storedSecondaryTextColor
          })

          SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            ForEach(this.state.options, (option: BrowserDesktopSiteModeOptionState, index: number) => {
              this.buildModeRow(option, index, this.state.options.length)
              if (index < this.state.options.length - 1) {
                SettingsGroupDivider({ dividerColor: this.storedDividerColor })
              }
            }, (option: BrowserDesktopSiteModeOptionState) =>
              `${option.mode}:${option.isSelected ? 'selected' : 'idle'}`)
          }
        }
        .width('100%')

        Row() {
          BrowserSheetActionButton({
            label: '默认网页标识：' + this.state.defaultUserAgentSummary,
            onAction: () => {
              this.onOpenDefaultUserAgent();
            }
          })
        }
        .width('100%')
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
  private buildModeRow(option: BrowserDesktopSiteModeOptionState, index: number, total: number) {
    SettingsOptionRow({
      title: option.title,
      helperText: option.helperText,
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: option.isSelected,
      isEnabled: true,
      radioGroup: BROWSER_DESKTOP_SITE_MODE_RADIO_GROUP,
      radioValue: option.mode,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      selectedIndicatorColor: this.storedAccentColor,
      onAction: (): void => {
        this.onSelectMode(option.mode);
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
}

import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppProxyQuickSheetState } from '../../../core/settings/AppProxyQuickSheetCoordinator';
import { AppProxyProfileListItemState } from '../../../core/settings/AppProxySettingsViewModel';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';
import {
  SettingsGroupCard,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsOptionRow,
  SettingsSwitchRow
} from './SettingsRows';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';

@Component
export struct AppProxyQuickSheetContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: AppProxyQuickSheetState = {
    globalEnabled: false,
    hasProfiles: false,
    profiles: [],
    switchingGlobalEnabled: false,
    switchingProfileId: '',
    toolbarActive: false
  };
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onClose?: () => void;
  onToggleGlobalEnabled?: (enabled: boolean) => void;
  onSelectProfile?: (profileId: string) => void;
  onOpenSettings?: () => void;

  build() {
    if (this.layoutMode === 'large_screen') {
      CenteredDialogSurface({ fillHeight: true }) {
        this.buildLargeScreenContent()
      }
    } else {
      BrowserBottomSheetSurface({
        fullHeight: true,
        contentJustifyContent: FlexAlign.Start,
        horizontalPadding: 0,
        topPadding: 0,
        bottomPadding: 0,
        surfaceColor: this.storedPageBackgroundColor
      }) {
        BrowserImmersiveSheetLayout({
          scrollContent: () => {
            this.buildScrollContent(true)
          },
          header: () => {
            this.buildHeader()
          }
        })
      }
    }
  }

  @Builder
  private buildLargeScreenContent() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      presentation: 'flat_content',
      contentJustifyContent: FlexAlign.Start,
      horizontalPadding: 16,
      topPadding: 26,
      bottomPadding: 24,
      surfaceColor: Color.Transparent
    }) {
      this.buildScrollContent(false)
    }
  }

  @Builder
  private buildHeader() {
    BrowserFeatureSheetHeader({
      title: '应用内代理',
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: '关闭应用内代理',
      onLeadingAction: () => {
        this.onClose?.();
      }
    })
  }

  @Builder
  private buildScrollContent(immersive: boolean) {
    Scroll() {
      Column({ space: 18 }) {
        this.buildGlobalSwitchSection()
        this.buildProfilesSection()
        this.buildSettingsAction()
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
  private buildGlobalSwitchSection() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      SettingsSwitchRow({
        title: '启用应用内代理',
        checked: this.state.globalEnabled,
        rowPosition: 'single',
        isEnabled: this.state.hasProfiles && !this.state.switchingGlobalEnabled,
        onChange: (value: boolean) => {
          this.onToggleGlobalEnabled?.(value);
        }
      })
    }
  }

  @Builder
  private buildProfilesSection() {
    SettingsSection({
      title: '代理配置',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 10 }) {
        if (this.state.profiles.length <= 0) {
          SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            SettingsOptionRow({
              title: '暂无代理',
              helperText: '',
              rowPosition: 'single',
              isSelected: false,
              isEnabled: false,
              radioGroup: 'app-proxy-quick-sheet-profiles',
              radioValue: 'empty'
            })
          }
        } else {
          ForEach(this.state.profiles, (item: AppProxyProfileListItemState) => {
            SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
              SettingsOptionRow({
                title: item.title,
                helperText: '',
                rowPosition: 'single',
                isSelected: item.isActive,
                isEnabled: item.canSelect && this.isProfileEnabled(item.id),
                radioGroup: 'app-proxy-quick-sheet-profiles',
                radioValue: item.id,
                selectedIndicatorColor: this.storedAccentColor,
                onAction: () => {
                  this.onSelectProfile?.(item.id);
                }
              })
            }
          }, (item: AppProxyProfileListItemState) =>
            `${item.id}:${item.isActive ? 'selected' : 'idle'}:${item.canSelect && this.isProfileEnabled(item.id) ? 'enabled' : 'disabled'}`)
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildSettingsAction() {
    Row() {
      BrowserSheetActionButton({
        label: '代理设置',
        onAction: () => {
          this.onOpenSettings?.();
        }
      })
    }
    .width('100%')
  }

  private isProfileEnabled(profileId: string): boolean {
    return this.state.switchingProfileId.length <= 0 || this.state.switchingProfileId === profileId;
  }
}

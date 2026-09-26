import { DESKTOP_DIALOG_PADDING_VP } from '../../../core/browser/BrowserDialogPresentationTokens';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppProxyQuickSheetState } from '../../../core/settings/AppProxyQuickSheetCoordinator';
import { AppProxyProfileListItemState } from '../../../core/settings/AppProxySettingsViewModel';
import { BrowserLargeScreenModalHeader } from '../browser/BrowserLargeScreenModalHeader';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  resolveBrowserSheetHeaderBlurRadius,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
  browserSheetHeaderBlurModifier
} from '../browser/BrowserModalBottomSheet';
import {
  SettingsGroupCard,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsOptionRow,
  SettingsSwitchRow
} from './SettingsRows';

@Component
export struct AppProxyQuickSheetContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#ECEDEF';
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
  @State private sheetHeaderBlurRadius: number = 0;
  @State private sheetScrollOffset: number = 0;

  build() {
    if (this.layoutMode === 'large_screen') {
      this.buildLargeScreenDialog()
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
          closeVisible: true,
          closeAccessibilityLabel: '关闭应用内代理',
          onClose: (): void => {
            this.onClose?.();
          },
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
  private buildLargeScreenDialog() {
    Column() {
      BrowserLargeScreenModalHeader({
        title: '应用内代理',
        dialogMode: true,
        onClose: (): void => {
          this.onClose?.();
        }
      })

      Column() {
        this.buildScrollContent(false)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: DESKTOP_DIALOG_PADDING_VP,
        right: DESKTOP_DIALOG_PADDING_VP,
        top: 4,
        bottom: DESKTOP_DIALOG_PADDING_VP
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildHeader() {
    BrowserFeatureSheetHeader({
      title: '应用内代理',
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
  private buildScrollContent(immersive: boolean) {
    Scroll(this.sheetBlurScroller) {
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
    .clip(!immersive)
    .attributeModifier(browserSheetHeaderBlurModifier(immersive ? this.sheetHeaderBlurRadius : 0))
    .onAppear(() => {
      this.resetSheetHeaderBlur();
    })
    .onDidScroll((_xOffset: number, yOffset: number) => {
      this.noteSheetScrollOffset(this.sheetBlurScroller.currentOffset().yOffset);
    })
  }

  @Builder
  private buildGlobalSwitchSection() {
    SettingsGroupCard({ surfaceColor: this.resolveGroupSurfaceColor() }) {
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
          SettingsGroupCard({ surfaceColor: this.resolveGroupSurfaceColor() }) {
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
            SettingsGroupCard({ surfaceColor: this.resolveGroupSurfaceColor() }) {
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

  private resolveGroupSurfaceColor(): ResourceColor {
    return this.layoutMode === 'large_screen' ?
      this.storedControlBackgroundColor : this.storedSurfaceBackgroundColor;
  }

  private isProfileEnabled(profileId: string): boolean {
    return this.state.switchingProfileId.length <= 0 || this.state.switchingProfileId === profileId;
  }
}

import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  PasswordSettingsViewState
} from '../../../core/password/PasswordSettingsViewModel';
import {
  SettingsStaticValueRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from '../settings/SettingsTargetReveal';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct PasswordSettingsScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: PasswordSettingsViewState = {
    officialVaultEnabled: true,
    regularAutofillEnabled: true,
    regularSavePromptEnabled: true,
    privateAutofillEnabled: true,
    regularSummary: '',
    privateSummary: ''
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop pageBackground: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop controlBackground: ResourceColor | undefined = undefined;
  @Prop pressedBackground: ResourceColor | undefined = undefined;
  @Prop accentColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = this.storedPrimaryTextColor;
  @Prop secondaryTextColor: ResourceColor = this.storedSecondaryTextColor;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  onOfficialVaultChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onRegularAutofillChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onRegularSavePromptChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onPrivateAutofillChange: (enabled: boolean) => void = (_enabled: boolean) => {};

  build() {
    SettingsHdsScaffold({
      title: '密码',
      backIconKind: 'back',
      pageBackground: this.resolvePageBackground(),
      headerButtonBackground: this.resolveControlBackground(),
      primaryTextColor: this.resolvePrimaryTextColor(),
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      onBack: () => {
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        SettingsScrollBody({
          contentSpace: 18,
          topPadding: 16,
          bottomPadding: 32,
          scroller: this.settingsScroller
        }) {
          PasswordSettingsContent({
            state: this.state,
            surfaceBackground: this.resolveSurfaceBackground(),
            controlBackground: this.resolveControlBackground(),
            pressedBackground: this.resolvePressedBackground(),
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            accentColor: this.resolveAccentColor(),
            revealTargetId: this.revealTargetId,
            revealRevision: this.revealRevision,
            scroller: this.settingsScroller,
            onOfficialVaultChange: (enabled: boolean) => {
              this.onOfficialVaultChange(enabled);
            },
            onRegularAutofillChange: (enabled: boolean) => {
              this.onRegularAutofillChange(enabled);
            },
            onRegularSavePromptChange: (enabled: boolean) => {
              this.onRegularSavePromptChange(enabled);
            },
            onPrivateAutofillChange: (enabled: boolean) => {
              this.onPrivateAutofillChange(enabled);
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolvePageBackground())
    }
  }

  private resolveAccentColor(): ResourceColor {
    return `${this.accentColor}`.length > 0 ? this.accentColor : this.storedAccentColor;
  }

  private resolvePageBackground(): ResourceColor {
    return this.pageBackground === undefined ? this.storedPageBackgroundColor : this.pageBackground;
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolveControlBackground(): ResourceColor {
    return this.controlBackground === undefined ? this.storedPressedBackgroundColor : this.controlBackground;
  }

  private resolvePressedBackground(): ResourceColor {
    return this.pressedBackground === undefined ? this.storedPressedBackgroundColor : this.pressedBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }
}

@Component
export struct PasswordSettingsContent {
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: PasswordSettingsViewState = {
    officialVaultEnabled: true,
    regularAutofillEnabled: true,
    regularSavePromptEnabled: true,
    privateAutofillEnabled: true,
    regularSummary: '',
    privateSummary: ''
  };
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop controlBackground: ResourceColor | undefined = undefined;
  @Prop pressedBackground: ResourceColor | undefined = undefined;
  @Prop primaryTextColor: ResourceColor = this.storedPrimaryTextColor;
  @Prop secondaryTextColor: ResourceColor = this.storedSecondaryTextColor;
  @Prop accentColor: ResourceColor = '';
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRevealRequest') revealTargetId: string = '';
  @Prop @Watch('handleRevealRequest') revealRevision: number = 0;
  scroller?: Scroller;
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );
  onOfficialVaultChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onRegularAutofillChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onRegularSavePromptChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onPrivateAutofillChange: (enabled: boolean) => void = (_enabled: boolean) => {};

  aboutToAppear(): void {
    this.revealController.bindScroller(this.scroller);
    this.handleRevealRequest();
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    Column({ space: 18 }) {
      this.buildProviderSection()
      this.buildRegularControlsSection()
      this.buildRegularSummarySection()
      this.buildPrivateControlsSection()
      this.buildPrivateSummarySection()
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.revealController.rememberContentArea(newArea);
    })
  }

  @Builder
  private buildProviderSection() {
    SettingsSection({
      title: '官方能力',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'password_official_vault',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '网页密码保险箱',
            desktopPresentation: this.desktopPresentation,
            description: '使用系统密码能力',
            checked: this.state.officialVaultEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'single',
            onChange: (enabled: boolean) => {
              this.onOfficialVaultChange(enabled);
            }
          })
        }
      }
    }
  }

  @Builder
  private buildRegularControlsSection() {
    SettingsSection({
      title: '普通标签页',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'password_regular_autofill',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '自动填充已有密码',
            desktopPresentation: this.desktopPresentation,
            description: '由系统验证后填充',
            checked: this.state.regularAutofillEnabled,
            rowPosition: 'first',
            isEnabled: this.state.officialVaultEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            onChange: (enabled: boolean) => {
              this.onRegularAutofillChange(enabled);
            }
          })
        }
        this.buildDivider()
        SettingsTargetRevealRegion({
          targetId: 'password_save_prompt',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '提示保存新密码',
            desktopPresentation: this.desktopPresentation,
            description: '登录后询问保存',
            checked: this.state.regularSavePromptEnabled,
            rowPosition: 'last',
            isEnabled: this.state.officialVaultEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            onChange: (enabled: boolean) => {
              this.onRegularSavePromptChange(enabled);
            }
          })
        }
      }
    }
  }

  @Builder
  private buildRegularSummarySection() {
    SettingsSection({
      title: '普通标签页规则',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsStaticValueRow({
          title: '当前规则',
          desktopPresentation: this.desktopPresentation,
          value: '',
          description: this.state.regularSummary,
          rowPosition: 'single',
          isEnabled: this.state.officialVaultEnabled,
          primaryTextColor: this.resolvePrimaryTextColor(),
          secondaryTextColor: this.resolveSecondaryTextColor()
        })
      }
    }
  }

  @Builder
  private buildPrivateControlsSection() {
    SettingsSection({
      title: '私密标签页',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'password_private_autofill',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '一次性填充已有密码',
            desktopPresentation: this.desktopPresentation,
            description: '不保存新密码',
            checked: this.state.privateAutofillEnabled,
            rowPosition: 'single',
            isEnabled: this.state.officialVaultEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            onChange: (enabled: boolean) => {
              this.onPrivateAutofillChange(enabled);
            }
          })
        }
      }
    }
  }

  @Builder
  private buildPrivateSummarySection() {
    SettingsSection({
      title: '私密标签页规则',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsStaticValueRow({
          title: '保存新密码',
          desktopPresentation: this.desktopPresentation,
          value: '始终关闭',
          description: this.state.privateSummary,
          rowPosition: 'single',
          isEnabled: this.state.officialVaultEnabled,
          primaryTextColor: this.resolvePrimaryTextColor(),
          secondaryTextColor: this.resolveSecondaryTextColor()
        })
      }
    }
  }

  @Builder
  private buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(this.resolveControlBackground())
      .margin({ left: 16, right: 16 })
  }

  private handleRevealRequest(): void {
    this.revealController.request(this.revealTargetId, this.revealRevision);
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolveControlBackground(): ResourceColor {
    return this.controlBackground === undefined ? this.storedPressedBackgroundColor : this.controlBackground;
  }

  private resolvePressedBackground(): ResourceColor {
    return this.pressedBackground === undefined ? this.storedPressedBackgroundColor : this.pressedBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }
}

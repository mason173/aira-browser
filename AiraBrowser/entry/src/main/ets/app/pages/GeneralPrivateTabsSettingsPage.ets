import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserGeneralSettings,
  BrowserPrivateTabRestorePolicy
} from '../../common/models/BrowserModels';
import {
  GeneralPrivateTabsSettingsState,
  GeneralPrivateTabsSettingsViewModel
} from '../../core/settings/GeneralPrivateTabsSettingsViewModel';
import { sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
import { SettingsOptionRow, SettingsSwitchRow } from '../components/settings/SettingsRows';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { createCenteredDialogMaterial } from '../components/common/CenteredDialogSurface';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../components/settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { AlwaysPrivateModeConfirmationDialog } from '../components/settings/AlwaysPrivateModeConfirmationDialog';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { SettingsDetailInteractionCoordinator } from '../../core/settings/SettingsDetailInteractionCoordinator';

@Entry
@Component
struct GeneralPrivateTabsSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: GeneralPrivateTabsSettingsViewModel = new GeneralPrivateTabsSettingsViewModel();
  private interactionCoordinator: SettingsDetailInteractionCoordinator =
    new SettingsDetailInteractionCoordinator(sharedPreferencesRepository);
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private generalSettings: BrowserGeneralSettings = sharedPreferencesRepository.getPreferences().general;
  @State private state: GeneralPrivateTabsSettingsState = this.viewModel.buildState(
    sharedPreferencesRepository.getPreferences().general
  );
  @State private alwaysPrivateConfirmationAccepted: boolean = false;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  private alwaysPrivateConfirmationDialogController: CustomDialogController = new CustomDialogController({
    builder: AlwaysPrivateModeConfirmationDialog({
      accepted: $alwaysPrivateConfirmationAccepted,
      onCancel: () => {
        this.alwaysPrivateConfirmationAccepted = false;
      },
      onConfirm: () => {
        this.alwaysPrivateConfirmationAccepted = false;
        this.updateAlwaysUsePrivateModeConfirmed(true);
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });

  aboutToAppear(): void {
    this.syncBoundaryRouteState();
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '私密标签页恢复',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({ topPadding: 16, bottomPadding: 32 }) {
          this.buildAlwaysPrivateSection()
          this.buildRestoreSection()
          this.buildDataSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildAlwaysPrivateSection() {
    SettingsSection({
      title: '模式默认值',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '始终保持隐私模式',
          checked: this.state.alwaysUsePrivateMode,
          rowPosition: 'single',
          onChange: (checked: boolean) => {
            this.updateAlwaysUsePrivateMode(checked);
          }
        })
      }

      Text('开启后，每次重新启动 Aira 都会回到隐私模式；本次使用中仍可临时切换到普通模式。')
        .width('100%')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
        .padding({ left: 6, right: 6 })
    }
  }

  @Builder
  private buildDataSection() {
    SettingsSection({
      title: '关闭后清除',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '保留 Cookie',
          checked: this.state.preserveCookiesOnClose,
          rowPosition: 'single',
          onChange: (checked: boolean) => {
            this.updatePreserveCookiesOnClose(checked);
          }
        })
      }

      Text(this.state.preserveCookiesOnClose
        ? '关闭全部隐私标签页后会清除本次私密会话数据，但保留 Cookie 登录状态。'
        : '关闭全部隐私标签页后会清除本次私密会话数据和 Cookie。')
        .width('100%')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
        .padding({ left: 6, right: 6 })
    }
  }

  @Builder
  private buildRestoreSection() {
    SettingsSection({
      title: '恢复策略',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsOptionRow({
          title: '关闭后不恢复',
          helperText: '私密标签页关闭后不进入下次启动恢复',
          rowPosition: 'first',
          isSelected: this.state.restorePolicy === 'never_restore',
          selectedIndicatorColor: this.storedAccentColor,
          onAction: () => {
            this.updatePolicy('never_restore');
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsOptionRow({
          title: '允许恢复',
          helperText: '保留私密标签页会降低隐私边界，请谨慎开启',
          rowPosition: 'last',
          isSelected: this.state.restorePolicy === 'restore_private_tabs',
          selectedIndicatorColor: this.storedAccentColor,
          onAction: () => {
            this.updatePolicy('restore_private_tabs');
          }
        })
      }
    }
  }

  private refreshState(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    this.generalSettings = preferences.general;
    this.state = this.viewModel.buildState(this.generalSettings);
  }

  private updatePolicy(policy: BrowserPrivateTabRestorePolicy): void {
    if (this.state.restorePolicy === policy) {
      return;
    }
    const previousSettings = this.generalSettings;
    const nextSettings = this.viewModel.buildGeneralSettingsWithRestorePolicy(this.generalSettings, policy);
    this.generalSettings = nextSettings;
    this.state = this.viewModel.buildState(this.generalSettings);
    this.interactionCoordinator.commitGeneralSettings({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    }, nextSettings)
      .then((settings: BrowserGeneralSettings) => {
        this.generalSettings = settings;
        this.state = this.viewModel.buildState(this.generalSettings);
      })
      .catch((_error: Error) => {
        this.generalSettings = previousSettings;
        this.state = this.viewModel.buildState(this.generalSettings);
      });
  }

  private updateAlwaysUsePrivateMode(enabled: boolean): void {
    if (this.state.alwaysUsePrivateMode === enabled) {
      return;
    }
    if (enabled) {
      this.alwaysPrivateConfirmationAccepted = false;
      this.alwaysPrivateConfirmationDialogController.open();
      return;
    }
    this.updateAlwaysUsePrivateModeConfirmed(false);
  }

  private updateAlwaysUsePrivateModeConfirmed(enabled: boolean): void {
    if (this.state.alwaysUsePrivateMode === enabled) {
      return;
    }
    const previousSettings = this.generalSettings;
    const nextSettings = this.viewModel.buildGeneralSettingsWithAlwaysUsePrivateMode(this.generalSettings, enabled);
    this.generalSettings = nextSettings;
    this.state = this.viewModel.buildState(this.generalSettings);
    this.interactionCoordinator.commitGeneralSettings({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    }, nextSettings)
      .then((settings: BrowserGeneralSettings) => {
        this.generalSettings = settings;
        this.state = this.viewModel.buildState(this.generalSettings);
      })
      .catch((_error: Error) => {
        this.generalSettings = previousSettings;
        this.state = this.viewModel.buildState(this.generalSettings);
      });
  }

  private updatePreserveCookiesOnClose(enabled: boolean): void {
    if (this.state.preserveCookiesOnClose === enabled) {
      return;
    }
    const previousSettings = this.generalSettings;
    const nextSettings = this.viewModel.buildGeneralSettingsWithPreserveCookiesOnClose(this.generalSettings, enabled);
    this.generalSettings = nextSettings;
    this.state = this.viewModel.buildState(this.generalSettings);
    this.interactionCoordinator.commitGeneralSettings({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    }, nextSettings)
      .then((settings: BrowserGeneralSettings) => {
        this.generalSettings = settings;
        this.state = this.viewModel.buildState(this.generalSettings);
      })
      .catch((_error: Error) => {
        this.generalSettings = previousSettings;
        this.state = this.viewModel.buildState(this.generalSettings);
      });
  }

  private syncBoundaryRouteState(): void {
    const boundary = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundary.dataScope;
    this.privacyMode = boundary.privacyMode;
    this.boundarySource = boundary.boundarySource;
  }

}

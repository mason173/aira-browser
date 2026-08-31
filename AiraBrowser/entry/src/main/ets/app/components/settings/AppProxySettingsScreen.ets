import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import promptAction from '@ohos.promptAction';
import {
  BrowserDataBoundaryInput,
  BrowserExperimentSettings
} from '../../../common/models/BrowserModels';
import { BrowserBoundaryRouteState, readBrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import {
  AppProxyProfileListItemState,
  AppProxySettingsPageState,
  AppProxySettingsViewModel
} from '../../../core/settings/AppProxySettingsViewModel';
import {
  AppProxySettingsCoordinator,
  AppProxySettingsCoordinatorState,
  AppProxySettingsMutationResult
} from '../../../core/settings/AppProxySettingsCoordinator';
import {
  sharedArkWebAppProxyService,
  sharedBrowserProxyRuntimeRefreshCoordinator,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsOptionRow,
  SettingsStaticValueRow,
  SettingsSwitchRow
} from './SettingsRows';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { AppProxyProfileEditHost } from './AppProxyProfileEditHost';
import { SettingsDesktopWorkspaceHeader } from './SettingsDesktopWorkspaceHeader';

export type AppProxySettingsPresentationMode = 'page' | 'native_tab';

@Component
export struct AppProxySettingsScreen {
  @Prop presentationMode: AppProxySettingsPresentationMode = 'page';
  @Prop settingsWorkspacePresentation: boolean = false;
  @Prop embeddedDataScope: string = '';
  @Prop embeddedPrivacyMode: string = '';
  @Prop embeddedBoundarySource: string = '';
  @Prop @Watch('refreshState') refreshRevision: number = 0;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: AppProxySettingsViewModel = new AppProxySettingsViewModel();
  private coordinator: AppProxySettingsCoordinator = new AppProxySettingsCoordinator(
    sharedPreferencesRepository,
    sharedArkWebAppProxyService,
    this.viewModel,
    (): void => {
      sharedBrowserProxyRuntimeRefreshCoordinator.requestRefresh();
    }
  );
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private experiments: BrowserExperimentSettings = sharedPreferencesRepository.getPreferences().experiments;
  @State private pageState: AppProxySettingsPageState =
    new AppProxySettingsViewModel().buildPageState(sharedPreferencesRepository.getPreferences().experiments);
  @State private switchingProfileId: string = '';
  @State private appProxyDeepView: string = 'main';
  @State private editingProfileId: string = '';
  onWorkspaceBack?: () => void;

  aboutToAppear(): void {
    this.refreshState();
  }

  build() {
    if (this.presentationMode === 'native_tab' && this.appProxyDeepView === 'profile_edit') {
      AppProxyProfileEditHost({
        profileId: this.editingProfileId,
        embedded: true,
        desktopPresentation: this.settingsWorkspacePresentation,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        onBack: () => {
          this.appProxyDeepView = 'main';
          this.refreshState();
        }
      })
        .width('100%')
        .height('100%')
    } else {
      this.buildMainContent()
    }
  }

  @Builder
  private buildMainContent() {
    Column() {
      if (this.settingsWorkspacePresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '应用内代理',
          showBackButton: true,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          onBack: () => {
            this.onWorkspaceBack?.();
          }
        })
      }

      SettingsHdsScaffold({
        title: '应用内代理',
        backIconKind: 'back',
        showBackButton: this.presentationMode !== 'native_tab',
        showTitleBar: !this.settingsWorkspacePresentation,
        useTopSafeInset: this.presentationMode !== 'native_tab',
        desktopPresentation: this.settingsWorkspacePresentation,
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsPresentationScrollBody({
          desktopPresentation: this.settingsWorkspacePresentation,
          topPadding: 16,
          bottomPadding: 22
        }) {
          Column({ space: 16 }) {
            this.buildGlobalSwitchSection()
            this.buildCurrentProfileSection()
            this.buildAddProxyButton()
            this.buildProfilesSection()
            SettingsFooterText({
              text: this.viewModel.buildCapabilityNote(this.experiments),
              secondaryTextColor: this.storedSecondaryTextColor
            })
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildGlobalSwitchSection() {
    SettingsSection({
      title: '总开关',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.settingsWorkspacePresentation
      }) {
        SettingsSwitchRow({
          title: '启用应用内代理',
          desktopPresentation: this.settingsWorkspacePresentation,
          checked: this.pageState.globalEnabled,
          rowPosition: 'single',
          onChange: (value: boolean) => {
            void this.toggleGlobalEnabled(value);
          }
        })
      }
      SettingsFooterText({
        text: '关闭时，只会记住你选中的代理配置，不会应用到网页请求。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildCurrentProfileSection() {
    SettingsSection({
      title: '当前选择',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.settingsWorkspacePresentation
      }) {
        SettingsStaticValueRow({
          title: '代理配置',
          desktopPresentation: this.settingsWorkspacePresentation,
          value: this.pageState.activeProfileName,
          rowPosition: 'first'
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsStaticValueRow({
          title: '代理地址',
          desktopPresentation: this.settingsWorkspacePresentation,
          value: this.pageState.activeSummary,
          rowPosition: 'last'
        })
      }
    }
  }

  @Builder
  private buildAddProxyButton() {
    SettingsActionButton({
      title: '添加代理',
      variant: 'filled',
      accentColor: this.storedAccentColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      onAction: () => {
        this.openProfileEdit('');
      }
    })
  }

  @Builder
  private buildProfilesSection() {
    SettingsSection({
      title: '已保存的代理',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      if (this.pageState.profileItems.length <= 0) {
        SettingsGroupCard({
          surfaceColor: this.storedSurfaceBackgroundColor,
          desktopPresentation: this.settingsWorkspacePresentation
        }) {
          SettingsNavigationRow({
            title: '暂无代理',
            desktopPresentation: this.settingsWorkspacePresentation,
            value: '去添加',
            rowPosition: 'single',
            onAction: () => {
              this.openProfileEdit('');
            }
          })
        }
      } else {
        Column({ space: 12 }) {
          ForEach(this.pageState.profileItems, (item: AppProxyProfileListItemState) => {
            this.buildProfileCard(item)
          })
        }
        .width('100%')
      }
    }
  }

  private refreshState(): void {
    const boundaryState: BrowserBoundaryRouteState = this.presentationMode === 'native_tab'
      ? {
        dataScope: this.embeddedDataScope,
        privacyMode: this.embeddedPrivacyMode,
        boundarySource: this.embeddedBoundarySource
      }
      : readBrowserBoundaryRouteState({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.applyCoordinatorState(this.coordinator.buildState());
    this.switchingProfileId = '';
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildDataBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private openProfileEdit(profileId: string): void {
    if (this.presentationMode === 'native_tab') {
      this.editingProfileId = profileId;
      this.appProxyDeepView = 'profile_edit';
      return;
    }
    this.navigationCoordinator.openAppProxyProfileEdit(
      this.buildBoundaryState(),
      profileId.length > 0 ? profileId : undefined
    );
  }

  private async selectProfile(profileId: string): Promise<void> {
    if (this.switchingProfileId.length > 0 || this.experiments.appProxyActiveProfileId === profileId) {
      return;
    }
    this.switchingProfileId = profileId;
    const result = await this.coordinator.selectProfile(profileId, this.buildDataBoundaryInput());
    this.applyMutationResult(result);
    this.switchingProfileId = '';
  }

  private async toggleGlobalEnabled(enabled: boolean): Promise<void> {
    this.applyMutationResult(await this.coordinator.setGlobalEnabled(enabled, this.buildDataBoundaryInput()));
  }

  @Builder
  private buildProfileCard(item: AppProxyProfileListItemState) {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.settingsWorkspacePresentation
    }) {
      SettingsOptionRow({
        title: item.title,
        desktopPresentation: this.settingsWorkspacePresentation,
        helperText: '',
        rowPosition: 'single',
        isSelected: item.isActive,
        isEnabled: item.canSelect && (this.switchingProfileId.length <= 0 || this.switchingProfileId === item.id),
        radioGroup: 'app-proxy-profiles',
        radioValue: item.id,
        selectedIndicatorColor: this.storedAccentColor,
        trailingActionIcon: $r('sys.symbol.chevron_right'),
        isTrailingActionEnabled: true,
        onAction: () => {
          void this.selectProfile(item.id);
        },
        onTrailingAction: () => {
          this.openProfileEdit(item.id);
        }
      })
    }
  }

  private applyMutationResult(result: AppProxySettingsMutationResult): void {
    this.applyCoordinatorState(result.state);
    if (result.message.length > 0) {
      this.showToast(result.message);
    }
  }

  private applyCoordinatorState(state: AppProxySettingsCoordinatorState): void {
    this.experiments = state.experiments;
    this.pageState = state.pageState;
  }

  private showToast(message: string): void {
    promptAction.showToast({
      message: message,
      duration: 1800
    });
  }
}

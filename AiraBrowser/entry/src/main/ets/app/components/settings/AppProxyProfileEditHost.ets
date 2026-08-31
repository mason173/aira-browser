import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserAppProxyScheme,
  BrowserDataBoundaryInput,
  BrowserExperimentSettings
} from '../../../common/models/BrowserModels';
import {
  AppProxyProfileDraft,
  AppProxySettingsViewModel
} from '../../../core/settings/AppProxySettingsViewModel';
import { AppProxySettingsCoordinator } from '../../../core/settings/AppProxySettingsCoordinator';
import { BrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import {
  sharedArkWebAppProxyService,
  sharedBrowserProxyRuntimeRefreshCoordinator,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsTextField
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
import { AppProxyProtocolSettingsHost } from './AppProxyProtocolSettingsHost';
import { SettingsDesktopWorkspaceHeader } from './SettingsDesktopWorkspaceHeader';

const APP_PROXY_PROTOCOL_SELECTION_KEY: string = 'app_proxy_protocol_selection';
const APP_PROXY_PROTOCOL_SELECTION_REVISION_KEY: string = 'app_proxy_protocol_selection_revision';
const APP_PROXY_EDIT_LOG_DOMAIN: number = 0x0000;
const APP_PROXY_EDIT_LOG_TAG: string = 'AppProxyEdit';

/**
 * 代理资料编辑页的共享主体：手机端由 AppProxyProfileEditPage 全屏承载，大屏端由应用内代理面板
 * 就地承载。协议选择通过 AppStorage（选中方案 + 修订号）回传：手机端在薄壳 onPageShow 触发
 * pageShowRevision 后应用；大屏端在协议子视图 onBack 里直接应用。保存/删除/返回统一走 onBack。
 */
@Component
export struct AppProxyProfileEditHost {
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
  @Prop profileId: string = '';
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  @Prop @Watch('onPageShowRevisionChanged') pageShowRevision: number = 0;
  onBack?: () => void;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @StorageLink(APP_PROXY_PROTOCOL_SELECTION_REVISION_KEY)
  private protocolSelectionRevision: number = 0;
  @State private experiments: BrowserExperimentSettings = sharedPreferencesRepository.getPreferences().experiments;
  @State private draft: AppProxyProfileDraft = new AppProxySettingsViewModel().buildDraftForCreate();
  @State private saving: boolean = false;
  @State private deleting: boolean = false;
  @State private deepView: string = 'main';
  private pendingProtocolSelectionBaseRevision: number = -1;

  aboutToAppear(): void {
    this.refreshState();
  }

  build() {
    if (this.embedded && this.deepView === 'protocol') {
      AppProxyProtocolSettingsHost({
        embedded: true,
        desktopPresentation: this.desktopPresentation,
        profileId: this.profileId,
        onBack: () => {
          this.applyPendingProtocolSelection();
          this.deepView = 'main';
        }
      })
        .width('100%')
        .height('100%')
    } else {
      this.buildEditContent()
    }
  }

  @Builder
  private buildEditContent() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: this.profileId.length > 0 ? '代理设置' : '添加代理',
          showBackButton: true,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          onBack: () => {
            this.handleBack();
          }
        })
      }

      SettingsHdsScaffold({
        title: this.profileId.length > 0 ? '代理设置' : '添加代理',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        showBackButton: !this.desktopPresentation,
        showTitleBar: !this.desktopPresentation,
        useTopSafeInset: !this.embedded,
        desktopPresentation: this.desktopPresentation,
        onBack: () => {
          this.handleBack();
        }
      }) {
        SettingsPresentationScrollBody({
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 28
        }) {
          Column({ space: 16 }) {
            this.buildBasicSection()
            this.buildServerSection()
            this.buildAuthSection()
            this.buildBypassSection()
            this.buildActionSection()
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
  private buildBasicSection() {
    SettingsSection({
      title: '',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 16 }) {
        SettingsTextField({
          desktopPresentation: this.desktopPresentation,
          label: '代理名称',
          text: this.draft.name,
          placeholder: '例如：公司代理 / 家里 NAS',
          maxLength: 80,
          isEnabled: !this.saving && !this.deleting,
          controlBackgroundColor: this.storedSurfaceBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onChange: (value: string) => {
            this.draft = this.viewModel.updateDraftName(this.draft, value);
          }
        })
        SettingsGroupCard({
          surfaceColor: this.storedSurfaceBackgroundColor,
          desktopPresentation: this.desktopPresentation
        }) {
        SettingsNavigationRow({
          title: '代理协议',
          desktopPresentation: this.desktopPresentation,
            value: this.viewModel.resolveSchemeLabel(this.draft.scheme),
            rowPosition: 'single',
            isEnabled: !this.saving && !this.deleting,
            onAction: () => {
              this.openProtocolSettings();
            }
          })
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildServerSection() {
    SettingsSection({
      title: '',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 16 }) {
        SettingsTextField({
          desktopPresentation: this.desktopPresentation,
          label: '地址',
          text: this.draft.host,
          placeholder: 'proxy.example.com',
          inputType: InputType.URL,
          maxLength: 180,
          isEnabled: !this.saving && !this.deleting,
          controlBackgroundColor: this.storedSurfaceBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onChange: (value: string) => {
            this.draft = this.viewModel.updateDraftHost(this.draft, value);
          }
        })
        SettingsTextField({
          desktopPresentation: this.desktopPresentation,
          label: '端口',
          text: this.draft.portText,
          placeholder: '7890',
          inputType: InputType.Number,
          maxLength: 5,
          isEnabled: !this.saving && !this.deleting,
          controlBackgroundColor: this.storedSurfaceBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onChange: (value: string) => {
            this.draft = this.viewModel.updateDraftPortText(this.draft, this.filterPort(value));
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  private buildAuthSection() {
    SettingsSection({
      title: '',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 16 }) {
        SettingsTextField({
          desktopPresentation: this.desktopPresentation,
          label: '用户名',
          text: this.draft.username,
          placeholder: '可选',
          maxLength: 180,
          isEnabled: !this.saving && !this.deleting,
          controlBackgroundColor: this.storedSurfaceBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onChange: (value: string) => {
            this.draft = this.viewModel.updateDraftUsername(this.draft, value);
          }
        })
        SettingsTextField({
          desktopPresentation: this.desktopPresentation,
          label: '密码',
          text: this.draft.password,
          placeholder: '可选',
          secure: true,
          maxLength: 256,
          isEnabled: !this.saving && !this.deleting,
          controlBackgroundColor: this.storedSurfaceBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onChange: (value: string) => {
            this.draft = this.viewModel.updateDraftPassword(this.draft, value);
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  private buildBypassSection() {
    SettingsSection({
      title: '',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsTextField({
        desktopPresentation: this.desktopPresentation,
        label: '不走代理的主机',
        text: this.draft.bypassHosts,
        placeholder: 'localhost,127.0.0.1,*.local',
        maxLength: 500,
        isEnabled: !this.saving && !this.deleting,
        controlBackgroundColor: this.storedSurfaceBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        onChange: (value: string) => {
          this.draft = this.viewModel.updateDraftBypassHosts(this.draft, value);
        }
      })
      SettingsFooterText({
        text: '使用英文逗号分隔。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildActionSection() {
    SettingsSection({
      title: '',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 10 }) {
        SettingsActionButton({
          title: this.saving ? '保存中...' : '保存代理',
          variant: 'filled',
          isEnabled: !this.saving && !this.deleting,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            void this.saveProfile();
          }
        })
        if (this.profileId.length > 0) {
          SettingsActionButton({
            title: this.deleting ? '删除中...' : '删除代理',
            emphasis: 'danger',
            isEnabled: !this.saving && !this.deleting,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onAction: () => {
              this.confirmDeleteProfile();
            }
          })
        }
      }
      .width('100%')
    }
  }

  private refreshState(): void {
    const latest = sharedPreferencesRepository.getPreferences().experiments;
    this.experiments = latest;
    this.draft = this.profileId.length > 0
      ? this.viewModel.buildDraftForEdit(latest, this.profileId)
      : this.viewModel.buildDraftForCreate();
  }

  private onPageShowRevisionChanged(): void {
    if (this.embedded) {
      return;
    }
    if (this.pendingProtocolSelectionBaseRevision >= 0) {
      this.applyPendingProtocolSelection();
    }
  }

  private applyPendingProtocolSelection(): void {
    const shouldApply = this.protocolSelectionRevision > this.pendingProtocolSelectionBaseRevision;
    this.pendingProtocolSelectionBaseRevision = -1;
    if (!shouldApply) {
      return;
    }
    const selectedScheme = AppStorage.get<string>(APP_PROXY_PROTOCOL_SELECTION_KEY) ?? '';
    if (selectedScheme === 'http' || selectedScheme === 'https' || selectedScheme === 'socks5') {
      this.draft = this.viewModel.updateDraftScheme(this.draft, selectedScheme as BrowserAppProxyScheme);
    }
  }

  private async saveProfile(): Promise<void> {
    const validation = this.viewModel.validate(this.draft);
    if (!validation.valid) {
      this.showToast(validation.message);
      return;
    }
    this.saving = true;
    try {
      const result = await this.coordinator.saveProfile(this.draft, this.buildDataBoundaryInput());
      this.experiments = result.state.experiments;
      if (!result.success) {
        this.showToast(result.message);
        return;
      }
      hilog.info(
        APP_PROXY_EDIT_LOG_DOMAIN,
        APP_PROXY_EDIT_LOG_TAG,
        'proxy saved draftId=%{public}s activeId=%{public}s enabled=%{public}s host=%{public}s port=%{public}d user=%{public}s updatedAt=%{public}s profileCount=%{public}d',
        this.draft.id.length > 0 ? this.draft.id : 'new',
        result.state.experiments.appProxyActiveProfileId,
        result.state.experiments.appProxyEnabled ? '1' : '0',
        result.state.experiments.appProxy.host,
        result.state.experiments.appProxy.port,
        this.maskText(result.state.experiments.appProxy.username),
        String(result.state.experiments.appProxy.updatedAt),
        result.state.experiments.appProxyProfiles.length
      );
      this.showToast(result.message);
      this.handleBack();
    } catch (_error) {
      this.showToast('保存代理失败。');
    } finally {
      this.saving = false;
    }
  }

  private async deleteProfile(): Promise<void> {
    if (this.profileId.length <= 0) {
      return;
    }
    this.deleting = true;
    try {
      const result = await this.coordinator.deleteProfile(this.profileId, this.buildDataBoundaryInput());
      this.experiments = result.state.experiments;
      this.showToast(result.message);
      if (result.success) {
        this.handleBack();
      }
    } catch (_error) {
      this.showToast('删除代理失败。');
    } finally {
      this.deleting = false;
    }
  }

  private confirmDeleteProfile(): void {
    const profileName = this.draft.name.trim().length > 0 ? this.draft.name.trim() : '这个代理';
    showCenteredAlertDialog({
      title: '删除代理',
      message: `确定删除“${profileName}”吗？删除后不会再用于应用内代理。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          void this.deleteProfile();
        }
      }
    });
  }

  private openProtocolSettings(): void {
    if (this.saving || this.deleting) {
      return;
    }
    AppStorage.setOrCreate(APP_PROXY_PROTOCOL_SELECTION_KEY, this.draft.scheme);
    this.pendingProtocolSelectionBaseRevision = this.protocolSelectionRevision;
    if (this.embedded) {
      this.deepView = 'protocol';
      return;
    }
    this.navigationCoordinator.openAppProxyProtocolSettings(
      this.buildBoundaryState(),
      this.profileId.length > 0 ? this.profileId : undefined
    );
  }

  private filterPort(value: string): string {
    let result = '';
    for (let index = 0; index < value.length; index += 1) {
      const char = value.charAt(index);
      if (char >= '0' && char <= '9') {
        result += char;
      }
    }
    return result.slice(0, 5);
  }

  private handleBack(): void {
    if (this.onBack !== undefined) {
      this.onBack();
      return;
    }
    router.back();
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

  private showToast(message: string): void {
    promptAction.showToast({
      message: message,
      duration: 1800
    });
  }

  private maskText(value: string): string {
    const normalized = value.trim();
    if (normalized.length <= 0) {
      return 'empty';
    }
    return `${normalized.substring(0, 1)}***(${normalized.length})`;
  }
}

import {
  AiraBookmarkConflictResolution,
  AiraSyncProviderKind
} from '../../common/models/AiraSyncModels';
import {
  createCenteredDialogMaterial,
  showCenteredAlertDialog
} from '../components/common/CenteredDialogSurface';
import router from '@ohos.router';
import {
  WEB_DAV_PROVIDER_ENDPOINT_KEY,
  WEB_DAV_PROVIDER_SELECTION_REVISION_KEY,
  WEB_DAV_PROVIDER_SELECTION_KEY,
  WEB_DAV_TARGET_ROLE_KEY,
  WebdavProviderCatalog,
  WebdavProviderTemplate
} from '../../core/sync/WebdavProviderCatalog';
import {
  SYNC_SETTINGS_REFRESH_REVISION_KEY,
  SyncSettingsRefreshSignal
} from '../../core/sync/SyncSettingsRefreshSignal';
import {
  SyncWebdavConfigLifecycleStage,
  SyncWebdavConfigViewModel,
  SyncWebdavConfigViewState,
  SyncWebdavProviderRole
} from '../../core/sync/SyncWebdavConfigViewModel';
import {
  SYNC_OPERATION_PROGRESS_TIMING,
  SyncOperationProgressTipsState,
  SyncOperationProgressViewModel
} from '../../core/sync/SyncOperationProgressViewModel';
import {
  SyncFailureDetailItem,
  SyncFailurePresentationService
} from '../../core/sync/SyncFailurePresentationService';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import {
  sharedPreferencesRepository,
  sharedSyncExperienceCoordinator
} from '../bootstrap/BrowserAppRuntime';
import {
  SyncExperienceActionOutcome,
  SyncExperienceWebdavActivationOutcome,
  SyncExperienceWebdavConfigurationParams,
  SyncExperienceWebdavConfigurationState,
  SyncExperienceWebdavTargetRole
} from '../../core/sync/SyncExperienceCoordinator';
import { EntitlementDecision } from '../../common/models/MembershipModels';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsScrollBody
} from '../components/settings/SettingsLayout';
import {
  SettingsActionButton
} from '../components/settings/SettingsRows';
import { SyncFailureDialog } from '../components/sync/SyncFailureDialog';
import { HuaweiLoginSheetContent } from '../components/account/HuaweiLoginSheetContent';
import {
  SyncOperationProgressDialog
} from '../components/sync/SyncOperationProgressDialog';
import { SyncResultDialog } from '../components/sync/SyncResultDialog';
import { SyncFormField } from '../components/sync/SyncFormFields';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';

@Entry
@Component
struct SyncWebdavConfigPage {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F6F8FB';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private providerCatalog: WebdavProviderCatalog = new WebdavProviderCatalog();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private syncFailurePresentationService: SyncFailurePresentationService = new SyncFailurePresentationService();
  private syncWebdavConfigViewModel: SyncWebdavConfigViewModel = new SyncWebdavConfigViewModel();
  private syncOperationProgressViewModel: SyncOperationProgressViewModel = new SyncOperationProgressViewModel();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential
      ) => {
        this.handleHuaweiLoginPanelResult(error, response);
      });

  @StorageLink(SYNC_SETTINGS_REFRESH_REVISION_KEY) @Watch('refreshSettingsFromSignal')
  private syncSettingsRefreshRevision: number = 0;
  @StorageLink(WEB_DAV_PROVIDER_SELECTION_KEY) providerId: string = 'custom';
  @StorageLink(WEB_DAV_PROVIDER_ENDPOINT_KEY) endpoint: string = '';
  @StorageLink(WEB_DAV_PROVIDER_SELECTION_REVISION_KEY) providerSelectionRevision: number = 0;
  @State private username: string = '';
  @State private password: string = '';
  @State private syncTargetRole: SyncExperienceWebdavTargetRole = 'active';
  private webdavProviderRole: SyncWebdavProviderRole = 'inactive';
  private bookmarkDomainEnabled: boolean = false;
  private activateExperienceAfterSave: boolean = false;
  @State private webdavActionRenderVersion: number = 0;
  @State private webdavOperation: SyncWebdavConfigLifecycleStage | '' = '';
  @State private webdavViewState: SyncWebdavConfigViewState = {
    stage: 'empty',
    isConfigured: false,
    isEnabled: false,
    isBusy: false,
    primaryActionTitle: '启用 WebDAV 同步',
    primaryActionEnabled: true,
    showDisableAction: false,
    disableActionEnabled: true,
    statusText: '未配置',
    renderKey: 'empty|off|empty'
  };
  @State private syncFloatingTitle: string = '';
  @State private syncFloatingSubtitle: string = '';
  @State private syncFloatingProgress: number = 0;
  @State private syncFloatingInProgress: boolean = false;
  @State private syncProgressDetailsText: string = '';
  @State private syncProgressDetailOpacity: number = 1;
  @State private syncFailureDialogTitle: string = '';
  @State private syncFailureDialogSummary: string = '';
  @State private syncFailureDialogDetails: SyncFailureDetailItem[] = [];
  @State private syncResultDialogTitle: string = '';
  @State private syncResultDialogMessage: string = '';
  @State private showHuaweiLoginPanel: boolean = false;
  private syncFailureDiagnosticsText: string = '';
  private syncFailureDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncFailureDialog({
      title: $syncFailureDialogTitle,
      summary: $syncFailureDialogSummary,
      details: $syncFailureDialogDetails,
      copyDetails: () => {
        this.copyCurrentSyncFailureDiagnostics();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });
  private syncResultDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncResultDialog({
      title: $syncResultDialogTitle,
      message: $syncResultDialogMessage
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });
  private syncProgressDialogOpen: boolean = false;
  private syncProgressTipTimer: number = -1;
  private syncProgressVisualTimer: number = -1;
  private syncProgressTimeoutTimer: number = -1;
  private syncProgressStartTime: number = 0;
  private syncProgressTargetProgress: number = SYNC_OPERATION_PROGRESS_TIMING.inProgressTarget;
  private syncProgressFinishTimer: number = -1;
  private syncProgressCompletionTimer: number = -1;
  private syncProgressTipsState: SyncOperationProgressTipsState = { tips: [], index: 0, activeTip: '' };
  private syncProgressDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncOperationProgressDialog({
      inProgress: $syncFloatingInProgress,
      title: $syncFloatingTitle,
      subtitle: $syncFloatingSubtitle,
      progress: $syncFloatingProgress,
      details: $syncProgressDetailsText,
      detailOpacity: $syncProgressDetailOpacity
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      if (!this.syncFloatingInProgress) {
        dismissDialogAction.dismiss();
      }
    }
  });

  aboutToAppear(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.refreshSyncTargetRole();
    this.loadSettings();
    sharedSyncExperienceCoordinator.loadWebdavConfigurationState()
      .then((state: SyncExperienceWebdavConfigurationState) => {
        this.applyWebdavConfigurationState(state);
      })
      .catch((_error: Error) => undefined);
  }

  aboutToDisappear(): void {
    this.stopSyncProgressTimers();
  }

  onPageShow(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.refreshSyncTargetRole();
    this.applySharedProviderSelection();
    this.refreshWebdavActivationState();
  }

  onBackPress(): boolean {
    return this.syncProgressDialogOpen && this.syncFloatingInProgress;
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: this.syncWebdavConfigViewModel.resolvePageTitle(this.syncTargetRole),
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({
          contentSpace: 18,
          topPadding: 8,
          bottomPadding: 28
        }) {
          this.buildProviderSection()
          this.buildRemoteLocationSection()
          this.buildAccountCredentialSection()
          this.buildActionSection()
          this.buildDisableSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .bindSheet($$this.showHuaweiLoginPanel, this.buildHuaweiLoginSheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true,
      onDisappear: () => {
        this.showHuaweiLoginPanel = false;
      }
    })
  }

  @Builder
  private buildHuaweiLoginSheet() {
    HuaweiLoginSheetContent({
      controller: this.huaweiLoginButtonController,
      onOpenUserAgreement: () => {
        this.showHuaweiLoginPanel = false;
        this.navigationCoordinator.openLegalWebDocument(
          'user_service_agreement',
          {
            dataScope: 'profile_persistent',
            privacyMode: 'regular',
            boundarySource: 'sync_webdav_login'
          }
        );
      },
      onOpenPrivacyPolicy: () => {
        this.showHuaweiLoginPanel = false;
        this.navigationCoordinator.openPrivacyStatement({
          dataScope: 'profile_persistent',
          privacyMode: 'regular',
          boundarySource: 'sync_webdav_login'
        });
      }
    })
  }

  @Builder
  private buildProviderSection() {
    Column() {
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Text('WebDAV 服务商')
            .layoutWeight(1)
            .fontSize(16)
            .fontColor(this.storedPrimaryTextColor)
          Text(this.resolveProvider().name)
            .fontSize(15)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.storedSecondaryTextColor])
        }
        .width('100%')
        .padding({ left: 18, right: 16, top: 14, bottom: 14 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.openProviderPicker();
        })
      }
      .width('100%')
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(18)
      .clip(true)
    }
    .width('100%')
  }

  @Builder
  private buildRemoteLocationSection() {
    Column({ space: 16 }) {
      this.buildEndpointInput()
    }
    .width('100%')
  }

  @Builder
  private buildAccountCredentialSection() {
    Column({ space: 16 }) {
      SyncFormField({
        label: '用户名',
        placeholder: 'WebDAV 用户名',
        text: $username,
        onChange: (_value: string) => {
          this.syncWebdavAccountStorage();
          this.rebuildWebdavViewState();
        }
      })
      SyncFormField({
        label: '密码',
        placeholder: 'WebDAV 密码',
        text: $password,
        secure: true,
        onChange: (_value: string) => {
          this.syncWebdavAccountStorage();
          this.rebuildWebdavViewState();
        }
      })
    }
    .width('100%')
  }

  @Builder
  private buildActionSection() {
    Button(this.syncWebdavConfigViewModel.resolveDisplayedPrimaryActionTitle(
      this.syncTargetRole,
      this.webdavViewState.primaryActionTitle,
      this.webdavViewState.isBusy
    ))
      .width('100%')
      .height(48)
      .type(ButtonType.Normal)
      .enabled(this.webdavViewState.primaryActionEnabled)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedOnPrimaryColor)
      .backgroundColor(this.storedAccentColor)
      .borderRadius(24)
      .stateEffect(true)
      .onClick(() => {
        this.saveConfig();
      })
      .id(`webdav-primary-action-${this.webdavActionRenderVersion}-${this.webdavViewState.renderKey}`)
      .width('100%')
  }

  @Builder
  private buildDisableSection() {
    if (this.webdavViewState.showDisableAction) {
      SettingsActionButton({
        title: this.syncTargetRole === 'additional_backup' ? '关闭 WebDAV 额外备份' : '关闭 WebDAV 同步',
        emphasis: 'danger',
        isEnabled: this.webdavViewState.disableActionEnabled,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          this.confirmDeactivateWebdavSync();
        }
      })
      .id(`webdav-disable-action-${this.webdavActionRenderVersion}`)
    }
  }

  @Builder
  private buildEndpointInput() {
    Column() {
      SyncFormField({
        label: 'WebDAV 地址',
        placeholder: 'https://example.com/dav/',
        text: $endpoint,
        inputType: InputType.URL,
        onChange: (value: string) => {
          this.endpoint = value;
          this.providerId = this.providerCatalog.resolveProviderForEndpoint(value).id;
          AppStorage.setOrCreate(WEB_DAV_PROVIDER_SELECTION_KEY, this.providerId);
          AppStorage.setOrCreate(WEB_DAV_PROVIDER_ENDPOINT_KEY, this.endpoint);
          this.rebuildWebdavViewState();
        }
      })
    }
    .id(`webdav-endpoint-${this.providerSelectionRevision}-${this.providerId}-${this.endpoint}`)
  }

  private loadSettings(): void {
    this.applyWebdavConfigurationState(sharedSyncExperienceCoordinator.readWebdavConfigurationState());
  }

  private applyWebdavConfigurationState(state: SyncExperienceWebdavConfigurationState): void {
    this.endpoint = state.endpoint;
    this.username = state.username;
    this.password = state.password;
    this.webdavProviderRole = state.providerRole;
    this.bookmarkDomainEnabled = state.bookmarkDomainEnabled;
    this.providerId = this.providerCatalog.resolveProviderForEndpoint(this.endpoint).id;
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_SELECTION_KEY, this.providerId);
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_ENDPOINT_KEY, this.endpoint);
    this.applySharedProviderSelection();
  }

  private refreshSyncTargetRole(): void {
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    const storedRole = AppStorage.get<string>(WEB_DAV_TARGET_ROLE_KEY);
    this.syncTargetRole = this.syncWebdavConfigViewModel.resolveTargetRole(params, storedRole);
    AppStorage.setOrCreate(WEB_DAV_TARGET_ROLE_KEY, this.syncTargetRole);
    this.activateExperienceAfterSave = this.syncTargetRole === 'active' &&
      params?.syncActivateExperience === 'true';
  }

  private applySharedProviderSelection(): void {
    const selected = AppStorage.get<string>(WEB_DAV_PROVIDER_SELECTION_KEY) ?? this.providerId;
    const provider = this.providerCatalog.resolveProvider(selected);
    this.providerId = provider.id;
    const sharedEndpoint = AppStorage.get<string>(WEB_DAV_PROVIDER_ENDPOINT_KEY) ?? this.endpoint;
    this.endpoint = this.providerCatalog.resolveProviderEndpoint(provider.id, sharedEndpoint);
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_ENDPOINT_KEY, this.endpoint);
    this.rebuildWebdavViewState();
  }

  private syncWebdavAccountStorage(): void {
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_ENDPOINT_KEY, this.endpoint);
  }

  private refreshSettingsFromSignal(): void {
    this.refreshWebdavActivationState();
  }

  private refreshWebdavActivationState(): void {
    const state = sharedSyncExperienceCoordinator.readWebdavConfigurationState();
    this.webdavProviderRole = state.providerRole;
    this.bookmarkDomainEnabled = state.bookmarkDomainEnabled;
    this.rebuildWebdavViewState();
  }

  private rebuildWebdavViewState(): void {
    const nextState = this.syncWebdavConfigViewModel.buildState({
      providerRole: this.webdavProviderRole,
      bookmarkDomainEnabled: this.bookmarkDomainEnabled,
      formEndpoint: this.endpoint,
      formUsername: this.username,
      formPassword: this.password,
      operation: this.webdavOperation,
      targetRole: this.syncTargetRole
    });
    if (nextState.renderKey !== this.webdavViewState.renderKey ||
      nextState.primaryActionTitle !== this.webdavViewState.primaryActionTitle) {
      this.webdavActionRenderVersion += 1;
    }
    this.webdavViewState = nextState;
  }

  private resolveProvider(): WebdavProviderTemplate {
    return this.providerCatalog.resolveProvider(this.providerId);
  }

  private openProviderPicker(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_SELECTION_KEY, this.providerId);
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_ENDPOINT_KEY, this.endpoint);
    AppStorage.setOrCreate(WEB_DAV_TARGET_ROLE_KEY, this.syncTargetRole);
    this.navigationCoordinator.openSyncWebdavProvider();
  }

  private saveConfig(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (this.webdavViewState.isBusy) {
      return;
    }
    void this.saveConfigThroughCoordinator();
  }

  private async saveConfigThroughCoordinator(): Promise<void> {
    const shouldActivate = this.syncWebdavConfigViewModel.shouldActivateOnSave(this.syncTargetRole);
    const isBackup = this.syncTargetRole === 'additional_backup';
    this.webdavOperation = this.webdavViewState.isEnabled ? 'syncing' : 'enabling';
    const progressTitle = isBackup
      ? (this.webdavViewState.isEnabled ? '正在更新 WebDAV 备份' : '正在开启 WebDAV 额外备份')
      : (this.webdavViewState.isEnabled ? '正在同步 WebDAV' : '正在启用 WebDAV 同步');
    const progressFirstTip = isBackup
      ? '正在保存配置，并用本机内容覆盖 WebDAV'
      : (this.webdavViewState.isEnabled ? '正在准备本机和云端数据' : '正在保存配置并检查连接');
    this.rebuildWebdavViewState();
    if (shouldActivate || this.syncTargetRole === 'additional_backup') {
      this.beginSyncFloatingOperation(progressTitle, progressFirstTip);
    }
    const configuration: SyncExperienceWebdavConfigurationParams = {
      endpoint: this.endpoint,
      username: this.username,
      password: this.password
    };
    if (this.activateExperienceAfterSave && this.syncTargetRole === 'active') {
      this.updateSyncFloatingStep('正在开启同步', '正在保存配置并开启书签和全部常用设置', 72);
      sharedSyncExperienceCoordinator.configureWebdavAndActivate(configuration)
        .then((outcome: SyncExperienceActionOutcome) => {
          this.renderExperienceActivationOutcome(outcome);
        })
        .catch((error: Error) => {
          this.completeSyncProgressDialog();
          this.showSyncFailureDialog('开启同步', 'WebDAV', error);
        })
        .finally(() => {
          this.webdavOperation = '';
          this.rebuildWebdavViewState();
        });
      return;
    }
    sharedSyncExperienceCoordinator.saveWebdavConfiguration(this.syncTargetRole, {
      endpoint: configuration.endpoint,
      username: configuration.username,
      password: configuration.password
    })
      .then((outcome: SyncExperienceWebdavActivationOutcome) => {
        if (shouldActivate || this.syncTargetRole === 'additional_backup') {
          this.updateSyncFloatingStep(
            progressTitle,
            isBackup ? '正在覆盖写入 WebDAV 额外备份' : '正在处理 WebDAV 同步状态',
            72
          );
        }
        this.renderWebdavActivationOutcome(outcome);
      })
      .catch((error: Error) => {
        this.completeSyncProgressDialog();
        this.showSyncFailureDialog(
          isBackup
            ? (this.webdavViewState.isEnabled ? 'WebDAV 额外备份' : '开启 WebDAV 额外备份')
            : (this.webdavViewState.isEnabled ? 'WebDAV 同步' : '启用 WebDAV 同步'),
          'WebDAV',
          error
        );
      })
      .finally(() => {
        this.webdavOperation = '';
        this.rebuildWebdavViewState();
      });
  }

  private confirmDeactivateWebdavSync(): void {
    if (this.webdavViewState.isBusy) {
      return;
    }
    showCenteredAlertDialog({
      title: this.syncTargetRole === 'additional_backup' ? '关闭 WebDAV 额外备份吗' : '关闭 WebDAV 同步吗',
      message: this.syncTargetRole === 'additional_backup'
        ? '关闭后会停止向 WebDAV 覆盖写入额外副本，当前同步方式和已填写的 WebDAV 配置都不会删除。'
        : '关闭后会停止通过 WebDAV 同步书签，本机书签和已填写的 WebDAV 配置不会删除。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '关闭',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deactivateWebdavSync();
        }
      }
    });
  }

  private deactivateWebdavSync(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.webdavOperation = 'disabling';
    this.rebuildWebdavViewState();
    sharedSyncExperienceCoordinator.deactivateWebdav()
      .then((outcome: SyncExperienceWebdavActivationOutcome) => {
        this.syncSettingsRefreshSignal.bump();
        this.rebuildWebdavViewState();
        if (outcome.type === 'failed') {
          this.showDialog(outcome.title, outcome.message);
          return;
        }
        this.showDialog(outcome.title, outcome.message);
      })
      .catch((_error: Error) => {
        this.showDialog(
          '关闭失败',
          this.syncTargetRole === 'additional_backup'
            ? '暂时没能关闭 WebDAV 额外备份，请稍后再试。'
            : '暂时没能关闭 WebDAV 同步，请检查网络后再试。'
        );
      })
      .finally(() => {
        this.webdavOperation = '';
        this.rebuildWebdavViewState();
      });
  }

  private showMembershipDialog(title: string, decision: EntitlementDecision): void {
    if (decision.primaryAction === 'login') {
      this.showHuaweiLoginPanel = true;
      return;
    }
    const primaryLabel = decision.primaryAction === 'open_pro' ? '查看 Aira Pro' : '查看权益';
    showCenteredAlertDialog({
      title: decision.title.length > 0 ? decision.title : title,
      message: decision.message,
      autoCancel: true,
      primaryButton: {
        value: '稍后',
        action: () => {}
      },
      secondaryButton: {
        value: primaryLabel,
        action: () => {
          this.navigationCoordinator.openAiraPro({
            dataScope: 'profile_persistent',
            privacyMode: 'regular',
            boundarySource: 'sync_webdav_config'
          });
        }
      }
    });
  }

  private handleHuaweiLoginPanelResult(
    error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential
  ): void {
    if (error !== undefined) {
      if (error.code !== 1001502012) {
        this.showToast(error.message.length > 0 ? error.message : '华为账号登录失败');
      }
      return;
    }
    if (response.authorizationCode.trim().length <= 0 && response.openID.trim().length <= 0) {
      this.showToast('华为账号登录未完成');
      return;
    }
    this.showHuaweiLoginPanel = false;
    this.signInHuaweiAccount();
  }

  private signInHuaweiAccount(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (this.webdavViewState.isBusy || this.webdavOperation.length > 0) {
      return;
    }
    this.webdavOperation = 'enabling';
    this.rebuildWebdavViewState();
    sharedSyncExperienceCoordinator.signInHuaweiAccountForSync()
      .then((outcome: SyncExperienceWebdavActivationOutcome) => {
        if (outcome.type === 'failed') {
          this.showToast(outcome.message.length > 0 ? outcome.message : outcome.title);
          return;
        }
        this.syncSettingsRefreshSignal.bump();
        this.showToast(outcome.title);
      })
      .catch((_error: Error) => {
        this.showToast('华为账号登录失败');
      })
      .finally(() => {
        this.webdavOperation = '';
        this.rebuildWebdavViewState();
      });
  }

  private renderWebdavActivationOutcome(outcome: SyncExperienceWebdavActivationOutcome): void {
    this.syncSettingsRefreshSignal.bump();
    if (outcome.type === 'additional-backup-enabled') {
      this.finishSyncFloatingOperation(outcome.title, outcome.message, () => {
        this.navigationCoordinator.back();
      });
      return;
    }
    if (outcome.type === 'activation-completed') {
      this.finishSyncFloatingOperation(outcome.title, outcome.message, () => {
        this.showDialog(outcome.title, outcome.message);
        this.navigationCoordinator.back();
      });
      return;
    }
    this.completeSyncProgressDialog();
    if (outcome.type === 'configuration-saved') {
      this.navigationCoordinator.back();
      return;
    }
    if (outcome.type === 'failed') {
      if (outcome.membershipDecision !== undefined) {
        this.showMembershipDialog(outcome.title, outcome.membershipDecision);
        return;
      }
      this.showSyncFailureDialog(outcome.title, 'WebDAV', new Error(outcome.message));
      return;
    }
    this.showDialog(outcome.title, outcome.message);
    this.navigationCoordinator.back();
  }

  private renderExperienceActivationOutcome(outcome: SyncExperienceActionOutcome): void {
    this.syncSettingsRefreshSignal.bump();
    if (outcome.type === 'completed') {
      this.finishSyncFloatingOperation(outcome.title, outcome.message, () => {
        this.navigationCoordinator.back();
      });
      return;
    }
    this.completeSyncProgressDialog();
    if (outcome.type === 'membership-required' && outcome.membershipDecision !== undefined) {
      this.showMembershipDialog(outcome.title, outcome.membershipDecision);
      return;
    }
    if (outcome.type === 'blocked' && outcome.requiresBookmarkResolution === true) {
      if (outcome.remoteKind === undefined) {
        this.showDialog(outcome.title, outcome.message);
        return;
      }
      const conflictRemoteKind = outcome.remoteKind;
      showCenteredAlertDialog({
        title: outcome.title,
        message: outcome.message,
        autoCancel: true,
        primaryButton: {
          value: '以云端为准',
          action: () => {
            this.resolveExperienceBookmarkConflicts(conflictRemoteKind, 'prefer-remote');
          }
        },
        secondaryButton: {
          value: '以本机为准',
          action: () => {
            this.resolveExperienceBookmarkConflicts(conflictRemoteKind, 'prefer-local');
          }
        }
      });
      return;
    }
    if (outcome.type === 'failed') {
      this.showSyncFailureDialog(outcome.title, 'WebDAV', new Error(outcome.message));
      return;
    }
    this.showDialog(outcome.title, outcome.message);
  }

  private resolveExperienceBookmarkConflicts(
    remoteKind: AiraSyncProviderKind,
    resolution: AiraBookmarkConflictResolution
  ): void {
    this.beginSyncFloatingOperation('正在处理书签冲突', '正在按你的选择合并并保存书签');
    sharedSyncExperienceCoordinator.resolveBookmarkConflicts(remoteKind, resolution)
      .then((outcome: SyncExperienceActionOutcome): void => {
        this.renderExperienceActivationOutcome(outcome);
      })
      .catch((error: Error): void => {
        this.completeSyncProgressDialog();
        this.showSyncFailureDialog('书签冲突处理失败', 'WebDAV', error);
      });
  }

  private beginSyncFloatingOperation(title: string, subtitle: string): void {
    this.stopSyncProgressTimers();
    this.syncFloatingTitle = title;
    this.syncFloatingSubtitle = subtitle;
    this.syncFloatingProgress = 0;
    this.syncProgressTargetProgress = SYNC_OPERATION_PROGRESS_TIMING.inProgressTarget;
    this.syncProgressStartTime = Date.now();
    this.syncFloatingInProgress = true;
    this.beginSyncProgressTips(title, subtitle);
    this.startSyncProgressVisualTimer();
    this.startSyncProgressTimeoutTimer();
    this.openSyncProgressDialog();
  }

  private updateSyncFloatingStep(title: string, subtitle: string, progress: number): void {
    if (!this.syncProgressDialogOpen) {
      return;
    }
    this.syncFloatingTitle = title;
    this.syncFloatingSubtitle = subtitle;
    this.syncProgressTargetProgress = Math.max(this.syncProgressTargetProgress, progress);
    this.appendSyncProgressTip(subtitle);
    this.showSyncProgressTip(subtitle);
  }

  private finishSyncFloatingOperation(title: string, subtitle: string, afterClose?: () => void): void {
    if (!this.syncProgressDialogOpen) {
      if (afterClose !== undefined) {
        afterClose();
      }
      return;
    }
    this.completeSyncProgressWithRamp(title, subtitle, afterClose);
  }

  private completeSyncProgressDialog(): void {
    if (!this.syncProgressDialogOpen) {
      this.syncFloatingInProgress = false;
      this.stopSyncProgressTimers();
      return;
    }
    this.syncFloatingInProgress = false;
    this.stopSyncProgressTimers();
    this.closeSyncProgressDialog();
  }

  private beginSyncProgressTips(title: string, firstTip: string): void {
    this.syncProgressTipsState = this.syncOperationProgressViewModel.buildInitialTips(title, firstTip);
    this.showSyncProgressTip(this.syncProgressTipsState.activeTip);
    this.syncProgressTipTimer = setInterval(() => {
      this.advanceSyncProgressTip();
    }, SYNC_OPERATION_PROGRESS_TIMING.tipIntervalMs);
  }

  private appendSyncProgressTip(tip: string): void {
    this.syncProgressTipsState = this.syncOperationProgressViewModel.appendTip(this.syncProgressTipsState, tip);
  }

  private advanceSyncProgressTip(): void {
    if (!this.syncFloatingInProgress || this.syncProgressTipsState.tips.length === 0) {
      return;
    }
    this.syncProgressTipsState = this.syncOperationProgressViewModel.advanceTip(this.syncProgressTipsState);
    this.showSyncProgressTip(this.syncProgressTipsState.activeTip);
  }

  private showSyncProgressTip(tip: string): void {
    this.syncProgressDetailOpacity = 0.22;
    setTimeout(() => {
      this.syncProgressDetailsText = tip;
      this.syncProgressDetailOpacity = 1;
    }, 80);
  }

  private startSyncProgressVisualTimer(): void {
    this.syncProgressVisualTimer = setInterval(() => {
      if (!this.syncFloatingInProgress) {
        return;
      }
      this.syncFloatingProgress = this.syncOperationProgressViewModel.resolveVisualProgress(
        this.syncFloatingProgress,
        this.syncProgressTargetProgress,
        Date.now() - this.syncProgressStartTime
      );
    }, SYNC_OPERATION_PROGRESS_TIMING.visualIntervalMs);
  }

  private startSyncProgressTimeoutTimer(): void {
    this.syncProgressTimeoutTimer = setTimeout(() => {
      if (!this.syncFloatingInProgress) {
        return;
      }
      const message = this.syncOperationProgressViewModel.resolveTimeoutMessage(this.syncFloatingTitle);
      this.completeSyncProgressDialog();
      this.webdavOperation = '';
      this.rebuildWebdavViewState();
      this.showDialog('操作超时', message);
    }, SYNC_OPERATION_PROGRESS_TIMING.timeoutMs);
  }

  private completeSyncProgressWithRamp(title: string, subtitle: string, afterClose?: () => void): void {
    this.stopSyncProgressActiveTimers();
    this.syncFloatingSubtitle = '正在完成处理';
    this.showSyncProgressTip('正在完成处理');
    this.syncProgressCompletionTimer = setInterval(() => {
      const nextProgress = Math.min(100, this.syncFloatingProgress + 4);
      this.syncFloatingProgress = nextProgress;
      if (nextProgress < 100) {
        return;
      }
      if (this.syncProgressCompletionTimer >= 0) {
        clearInterval(this.syncProgressCompletionTimer);
        this.syncProgressCompletionTimer = -1;
      }
      this.syncFloatingTitle = title;
      this.syncFloatingSubtitle = subtitle;
      this.showSyncProgressTip(subtitle);
      this.syncFloatingInProgress = false;
      this.syncProgressFinishTimer = setTimeout(() => {
        this.completeSyncProgressDialog();
        if (afterClose !== undefined) {
          afterClose();
        }
      }, SYNC_OPERATION_PROGRESS_TIMING.successVisibleMs);
    }, SYNC_OPERATION_PROGRESS_TIMING.finishIntervalMs);
  }

  private stopSyncProgressActiveTimers(): void {
    if (this.syncProgressTipTimer >= 0) {
      clearInterval(this.syncProgressTipTimer);
      this.syncProgressTipTimer = -1;
    }
    if (this.syncProgressVisualTimer >= 0) {
      clearInterval(this.syncProgressVisualTimer);
      this.syncProgressVisualTimer = -1;
    }
    if (this.syncProgressTimeoutTimer >= 0) {
      clearTimeout(this.syncProgressTimeoutTimer);
      this.syncProgressTimeoutTimer = -1;
    }
  }

  private stopSyncProgressTimers(): void {
    this.stopSyncProgressActiveTimers();
    if (this.syncProgressFinishTimer >= 0) {
      clearTimeout(this.syncProgressFinishTimer);
      this.syncProgressFinishTimer = -1;
    }
    if (this.syncProgressCompletionTimer >= 0) {
      clearInterval(this.syncProgressCompletionTimer);
      this.syncProgressCompletionTimer = -1;
    }
  }

  private openSyncProgressDialog(): void {
    if (this.syncProgressDialogOpen) {
      return;
    }
    this.syncProgressDialogOpen = true;
    this.syncProgressDialogController.open();
  }

  private closeSyncProgressDialog(): void {
    if (!this.syncProgressDialogOpen) {
      return;
    }
    this.syncProgressDialogOpen = false;
    this.syncProgressDialogController.close();
  }

  private showDialog(title: string, message: string): void {
    this.syncResultDialogTitle = title;
    this.syncResultDialogMessage = message;
    this.syncResultDialogController.open();
  }

  private showSyncFailureDialog(operationName: string, serviceName: string, error: Error): void {
    const presentation = this.syncFailurePresentationService.build({
      serviceName: serviceName,
      operationName: operationName,
      errorMessage: this.stringifyError(error)
    });
    this.syncFailureDialogTitle = presentation.title;
    this.syncFailureDialogSummary = presentation.summary;
    this.syncFailureDialogDetails = presentation.details;
    this.syncFailureDiagnosticsText = presentation.diagnostics;
    this.syncFailureDialogController.open();
  }

  private copyCurrentSyncFailureDiagnostics(): void {
    if (this.syncFailureDiagnosticsText.length === 0) {
      this.showToast('当前没有可复制的错误详情。');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.syncFailureDiagnosticsText);
      pasteboard.getSystemPasteboard().setData(data)
        .then(() => {
          this.showToast('错误详情已复制。');
        })
        .catch((_error: Error) => {
          this.showToast('复制失败，请稍后重试。');
        });
    } catch (_error) {
      this.showToast('复制失败，请稍后重试。');
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}

import router from '@ohos.router';
import {
  createCenteredDialogMaterial,
  showCenteredAlertDialog
} from '../common/CenteredDialogSurface';
import {
  AiraBookmarkConflictResolution,
  AiraSyncProviderKind
} from '../../../common/models/AiraSyncModels';
import { PersonalizationSyncContentId } from '../../../common/models/PersonalizationSyncModels';
import { EntitlementDecision } from '../../../common/models/MembershipModels';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import {
  SyncExperienceActionOutcome
} from '../../../core/sync/SyncExperienceCoordinator';
import { SyncFirstActivationItemsState } from '../../../core/sync/SyncFirstActivationItemsCoordinator';
import {
  SyncOperationProgressController,
  SyncOperationProgressUiState
} from '../../../core/sync/SyncOperationProgressController';
import {
  createDefaultSyncExperienceViewState,
  SyncExperiencePreActiveStatusKind,
  SyncExperienceViewState
} from '../../../core/sync/SyncExperienceViewModel';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import {
  sharedPreferencesRepository,
  sharedSyncExperienceCoordinator,
  sharedClientUpdatePolicyService,
  sharedAiraCloudBookmarkV4BootstrapRuntime
} from '../../bootstrap/BrowserAppRuntime';
import { SyncExperienceScreen } from './SyncExperienceScreen';
import { SyncAdditionalBackupHost } from './SyncAdditionalBackupHost';
import { SyncOperationProgressDialog } from './SyncOperationProgressDialog';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { SystemSettingsLaunchService } from '../../../services/system/SystemSettingsLaunchService';
import { AppRuntimeContext } from '../../runtime/AppRuntimeContext';
import { SYNC_SETTINGS_REFRESH_REVISION_KEY } from '../../../core/sync/SyncSettingsRefreshSignal';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';

const DEFAULT_SYNC_EXPERIENCE_STATE: SyncExperienceViewState = createDefaultSyncExperienceViewState();

@Component
export struct SyncExperienceHost {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string =
    DEFAULT_THEME_PALETTE.light.onAccent;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private systemSettingsLaunchService: SystemSettingsLaunchService = new SystemSettingsLaunchService();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  @StorageLink(SYNC_SETTINGS_REFRESH_REVISION_KEY) @Watch('refreshState')
  private syncSettingsRefreshRevision: number = 0;
  @State private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };
  @State private state: SyncExperienceViewState = DEFAULT_SYNC_EXPERIENCE_STATE;
  @State private isBusy: boolean = false;
  @State private isSyncing: boolean = false;
  @State private airaCloudRecoveryAvailable: boolean = false;
  @State private preActiveStatusKind: SyncExperiencePreActiveStatusKind = 'initial-loading';
  @State private activeSheetVisible: boolean = false;
  @State private desktopGuideNavigationActive: boolean = false;
  @State private syncProgressTitle: string = '';
  @State private syncProgressSubtitle: string = '';
  @State private syncProgressValue: number = 0;
  @State private syncProgressInProgress: boolean = false;
  @State private syncProgressDetailsText: string = '';
  @State private syncProgressDetailOpacity: number = 1;
  private stateRefreshRevision: number = 0;
  private setupSelectionCommitted: boolean = false;
  private syncProgressDialogOpen: boolean = false;
  private syncProgressDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncOperationProgressDialog({
      inProgress: $syncProgressInProgress,
      title: $syncProgressTitle,
      subtitle: $syncProgressSubtitle,
      progress: $syncProgressValue,
      details: $syncProgressDetailsText,
      detailOpacity: $syncProgressDetailOpacity
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      if (!this.syncProgressInProgress) {
        dismissDialogAction.dismiss();
      }
    }
  });
  private syncProgressController: SyncOperationProgressController = new SyncOperationProgressController(
    (state: SyncOperationProgressUiState): void => {
      this.syncProgressTitle = state.title;
      this.syncProgressSubtitle = state.subtitle;
      this.syncProgressValue = state.progress;
      this.syncProgressInProgress = state.inProgress;
      this.syncProgressDetailsText = state.details;
      this.syncProgressDetailOpacity = state.detailOpacity;
    },
    (): boolean => this.syncProgressDialogOpen,
    (): void => {
      this.openSyncProgressDialog();
    },
    (): void => {
      this.closeSyncProgressDialog();
    },
    (title: string, subtitle: string): void => {
      this.showDialog(title, subtitle);
    }
  );
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop useLargeScreenSelectionDialog: boolean = false;
  @Prop desktopPresentation: boolean = false;
  onExit?: () => void;
  onOpenAiraPro?: () => void;
  @State private syncWorkspaceView: 'overview' | 'additional_backup' = 'overview';

  aboutToAppear(): void {
    this.refreshState(true);
  }

  onPageShow(): void {
    if (this.desktopGuideNavigationActive) {
      this.desktopGuideNavigationActive = false;
      this.activeSheetVisible = true;
    }
    this.refreshState(true);
  }

  aboutToDisappear(): void {
    this.syncProgressController.dispose();
  }

  onBackPress(): boolean {
    return this.isBusy;
  }

  build() {
    Column() {
      if (this.desktopPresentation && this.syncWorkspaceView === 'additional_backup') {
        SyncAdditionalBackupHost({
          mode: 'overview',
          desktopPresentation: true,
          dataScope: this.boundary.dataScope,
          privacyMode: this.boundary.privacyMode,
          boundarySource: 'sync_experience_backup',
          onBack: () => {
            this.syncWorkspaceView = 'overview';
            this.refreshState(true);
          },
          onOpenAiraPro: () => {
            this.onOpenAiraPro?.();
          }
        })
          .width('100%')
          .height('100%')
      } else {
        SyncExperienceScreen({
        state: this.state,
        isBusy: this.isBusy,
        isSyncing: this.isSyncing,
        airaCloudRecoveryAvailable: this.airaCloudRecoveryAvailable,
        preActiveStatusKind: this.preActiveStatusKind,
        isPrivateSession: this.boundary.privacyMode === 'private',
        activeSheetVisible: $activeSheetVisible,
        showBackButton: this.showBackButton,
        showTitleBar: this.showTitleBar,
        useTopSafeInset: this.useTopSafeInset,
        contentKind: this.contentKind,
        desktopPresentation: this.desktopPresentation,
        useLargeScreenSelectionDialog: this.useLargeScreenSelectionDialog,
        desktopGuideNavigationActive: this.desktopGuideNavigationActive,
        onBack: () => {
          this.exitSyncExperience();
        },
        onGoalSelected: (
          remoteKind: AiraSyncProviderKind,
          firstActivationItems?: SyncFirstActivationItemsState
        ) => {
          this.submitGoalSelection(remoteKind, firstActivationItems);
        },
        onSetupDismissed: () => {
          this.exitSyncExperience();
        },
        onBookmarkSelected: (enabled: boolean) => {
          this.changeBookmarkSelection(enabled);
        },
        onHistorySelected: (enabled: boolean) => {
          this.changeHistorySelection(enabled);
        },
        onPersonalizationItemSelected: (id: PersonalizationSyncContentId, enabled: boolean) => {
          this.changePersonalizationItemSelection(id, enabled);
        },
        onSyncNow: () => {
          this.syncNow();
        },
        onRetryStateLoad: () => {
          this.retryStateLoad();
        },
        onOpenAdditionalBackup: () => {
          if (this.desktopPresentation) {
            this.syncWorkspaceView = 'additional_backup';
            return;
          }
          this.navigationCoordinator.openSyncAdditionalBackup(this.buildBoundary('sync_experience_backup'));
        },
        onOpenAiraPro: () => {
          if (this.desktopPresentation && this.onOpenAiraPro !== undefined) {
            this.onOpenAiraPro();
            return;
          }
          this.navigationCoordinator.openAiraPro(this.buildBoundary('sync_experience_membership'));
        },
        onOpenAdvanced: () => {
          this.navigationCoordinator.openSyncAdvancedSettings(this.buildBoundary('sync_experience'));
        },
        onRestoreAiraCloudUpgradeBackup: () => {
          this.confirmRestoreAiraCloudUpgradeBackup();
        },
        onOpenDesktopGuide: (restoreSheet: boolean) => {
          this.desktopGuideNavigationActive = restoreSheet;
          this.navigationCoordinator.openSyncDesktopBookmarkGuide(
            this.buildBoundary('sync_experience_desktop_guide')
          );
        },
        onConfigureWebdav: (
          firstActivationItems?: SyncFirstActivationItemsState
        ) => {
          this.openWebdavConfiguration(firstActivationItems);
        }
      })
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  private refreshState(openRequiredSetup: boolean = false): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      this.navigationCoordinator.back();
      return;
    }
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.boundary = readBrowserBoundaryRouteState({
      dataScope: params?.dataScope ?? this.boundary.dataScope,
      privacyMode: params?.privacyMode ?? this.boundary.privacyMode,
      boundarySource: params?.boundarySource ?? this.boundary.boundarySource
    });
    const refreshRevision = ++this.stateRefreshRevision;
    const mayOpenRequiredSetup = openRequiredSetup && !this.setupSelectionCommitted && !this.isBusy;
    sharedSyncExperienceCoordinator.load()
      .then((state: SyncExperienceViewState) => {
        if (refreshRevision !== this.stateRefreshRevision) {
          return;
        }
        this.state = state;
        this.airaCloudRecoveryAvailable = state.airaCloudActive &&
          sharedAiraCloudBookmarkV4BootstrapRuntime.hasRecoveryPoint();
        if (state.hasConfiguredSync || !this.isBusy) {
          this.preActiveStatusKind = 'inactive';
        }
        if (mayOpenRequiredSetup && !this.setupSelectionCommitted && !this.isBusy && !state.hasConfiguredSync) {
          this.activeSheetVisible = true;
        }
      })
      .catch((_error: Error) => {
        if (refreshRevision !== this.stateRefreshRevision) {
          return;
        }
        this.preActiveStatusKind = this.preActiveStatusKind === 'huawei-activating'
          ? 'huawei-load-failed'
          : 'load-failed';
        if (mayOpenRequiredSetup && !this.setupSelectionCommitted && !this.isBusy) {
          this.activeSheetVisible = true;
        }
      });
  }

  private confirmRestoreAiraCloudUpgradeBackup(): void {
    if (this.isBusy || this.boundary.privacyMode === 'private' || !this.airaCloudRecoveryAvailable) {
      return;
    }
    showCenteredAlertDialog({
      title: '恢复升级前书签',
      message: '当前本机书签会被升级前的恢复点替换，随后将关闭 Aira 云书签同步。此操作不会修改云端书签。',
      autoCancel: true,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '恢复',
        action: (): void => this.restoreAiraCloudUpgradeBackup()
      }
    });
  }

  private restoreAiraCloudUpgradeBackup(): void {
    if (this.isBusy || this.boundary.privacyMode === 'private') {
      return;
    }
    this.isBusy = true;
    sharedAiraCloudBookmarkV4BootstrapRuntime.restoreBackupAndDisable()
      .then((): void => {
        const state = sharedAiraCloudBookmarkV4BootstrapRuntime.getViewState();
        if (state.visible && state.status === 'failed') {
          this.showDialog('恢复失败', state.errorMessage.length > 0 ? state.errorMessage : '请稍后重试。');
          return;
        }
        this.showDialog('已恢复升级前书签', 'Aira 云书签同步已关闭，云端数据没有被修改。');
      })
      .catch((error: Error): void => {
        this.showDialog('恢复失败', error.message.length > 0 ? error.message : '请稍后重试。');
      })
      .finally((): void => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private submitGoalSelection(
    remoteKind: AiraSyncProviderKind,
    firstActivationItems?: SyncFirstActivationItemsState
  ): void {
    if (!this.state.hasActiveProvider && firstActivationItems !== undefined) {
      this.setupSelectionCommitted = true;
      this.stateRefreshRevision += 1;
      this.activeSheetVisible = false;
    }
    this.changeGoal(remoteKind, false, firstActivationItems);
  }

  private openWebdavConfiguration(
    firstActivationItems?: SyncFirstActivationItemsState
  ): void {
    if (firstActivationItems === undefined) {
      this.navigationCoordinator.openSyncWebdavConfig(
        this.buildBoundary('sync_experience_webdav_provider'),
        'active'
      );
      return;
    }
    if (this.isBusy || this.boundary.privacyMode === 'private') {
      return;
    }
    this.setupSelectionCommitted = true;
    this.stateRefreshRevision += 1;
    this.activeSheetVisible = false;
    this.isBusy = true;
    sharedSyncExperienceCoordinator.requestFirstActivationWebdavConfiguration(firstActivationItems)
      .then((outcome: SyncExperienceActionOutcome) => {
        this.renderOutcome(outcome);
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private exitSyncExperience(): void {
    if (this.onExit !== undefined) {
      this.onExit();
      return;
    }
    this.navigationCoordinator.back();
  }

  private changeGoal(
    remoteKind: AiraSyncProviderKind,
    confirmed: boolean,
    firstActivationItems?: SyncFirstActivationItemsState
  ): void {
    if (this.isBusy || this.boundary.privacyMode === 'private') {
      return;
    }
    if (remoteKind === 'self_hosted' && this.state.hasActiveProvider &&
      this.state.goalOptions.some((option): boolean => option.id === 'self_hosted' && option.isSelected)) {
      this.navigationCoordinator.openSyncPersonalServerConfig(
        this.buildBoundary('sync_experience_personal_server')
      );
      return;
    }
    this.isBusy = true;
    const firstHuaweiActivation = remoteKind === 'huawei_space' &&
      !this.state.hasActiveProvider && firstActivationItems !== undefined;
    if (firstHuaweiActivation) {
      this.preActiveStatusKind = 'huawei-activating';
    }
    const silentHuaweiInitialization = remoteKind === 'huawei_space' && !this.state.hasActiveProvider;
    if (!silentHuaweiInitialization) {
      this.syncProgressController.begin(
        this.state.hasActiveProvider ? '正在更改同步方式' : '正在开启同步',
        this.state.hasActiveProvider ? '正在读取、合并并保存同步数据' : '正在读取已有同步状态并准备内容'
      );
    }
    sharedSyncExperienceCoordinator.requestGoalChange(remoteKind, confirmed, firstActivationItems)
      .then((outcome: SyncExperienceActionOutcome) => {
        if (silentHuaweiInitialization) {
          if (outcome.type !== 'completed') {
            this.renderOutcome(outcome);
          }
          return;
        }
        this.completeProgressOutcome(outcome);
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private retryStateLoad(): void {
    if (this.isBusy) {
      return;
    }
    this.preActiveStatusKind = this.preActiveStatusKind === 'huawei-load-failed'
      ? 'huawei-activating'
      : 'initial-loading';
    this.refreshState();
  }

  private syncNow(): void {
    if (this.isBusy || this.boundary.privacyMode === 'private') {
      return;
    }
    this.isBusy = true;
    this.isSyncing = true;
    this.syncProgressController.begin('正在同步', '正在整理书签、历史记录、主页收藏、小说书架和常用设置');
    sharedSyncExperienceCoordinator.syncNow()
      .then((outcome: SyncExperienceActionOutcome) => {
        this.completeProgressOutcome(outcome);
      })
      .finally(() => {
        this.isSyncing = false;
        this.isBusy = false;
        this.refreshState();
      });
  }

  private changeBookmarkSelection(enabled: boolean): void {
    if (this.isBusy || this.boundary.privacyMode === 'private') {
      return;
    }
    this.isBusy = true;
    const silentHuaweiInitialization = enabled && this.state.huaweiSpaceActive;
    if (!silentHuaweiInitialization) {
      this.syncProgressController.begin(
        enabled ? '正在开启书签同步' : '正在暂停书签同步',
        enabled ? '正在读取并合并已有书签' : '正在保存当前书签同步状态'
      );
    }
    sharedSyncExperienceCoordinator.setBookmarkSelected(enabled)
      .then((outcome: SyncExperienceActionOutcome) => {
        if (silentHuaweiInitialization) {
          if (outcome.type !== 'completed') {
            this.renderOutcome(outcome);
          }
          return;
        }
        this.completeProgressOutcome(outcome);
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private changeHistorySelection(enabled: boolean): void {
    if (this.isBusy || this.boundary.privacyMode === 'private' || !this.state.historySupported) {
      return;
    }
    this.isBusy = true;
    if (enabled) {
      this.syncProgressController.begin(
        '正在开启历史记录同步',
        `正在合并本机与${this.state.historyProviderLabel}历史记录`
      );
    }
    sharedSyncExperienceCoordinator.setHistorySelected(enabled)
      .then((outcome: SyncExperienceActionOutcome) => {
        if (enabled) {
          this.completeProgressOutcome(outcome);
        } else if (outcome.type !== 'completed') {
          this.renderOutcome(outcome);
        }
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private changePersonalizationItemSelection(id: PersonalizationSyncContentId, enabled: boolean): void {
    if (this.isBusy || this.boundary.privacyMode === 'private') {
      return;
    }
    const changesHiddenDomain = this.state.masterEnabled && (
      (enabled && !this.state.personalizationSelected) ||
      (!enabled && this.state.personalizationSelected && this.state.enabledPersonalizationItemCount === 1)
    );
    this.isBusy = true;
    if (changesHiddenDomain) {
      this.syncProgressController.begin(
        enabled ? '正在开启这项同步' : '正在保存同步内容',
        enabled ? '正在读取并合并已有主页收藏、小说书架和常用设置' : '正在暂停最后一项同步内容'
      );
    }
    sharedSyncExperienceCoordinator.setPersonalizationItemSelected(id, enabled)
      .then((outcome: SyncExperienceActionOutcome) => {
        if (changesHiddenDomain) {
          this.completeProgressOutcome(outcome);
        } else if (outcome.type !== 'completed') {
          this.renderOutcome(outcome);
        }
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private completeProgressOutcome(outcome: SyncExperienceActionOutcome): void {
    if (outcome.type === 'completed') {
      this.syncProgressController.finish(outcome.title, outcome.message, undefined, false);
      return;
    }
    this.syncProgressController.fail(outcome.title, outcome.message);
    this.renderOutcome(outcome);
  }

  private renderOutcome(outcome: SyncExperienceActionOutcome): void {
    if (outcome.type === 'confirmation-required' && outcome.remoteKind !== undefined) {
      showCenteredAlertDialog({
        title: outcome.title,
        message: outcome.message,
        autoCancel: true,
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: {
          value: '更改',
          action: () => {
            this.changeGoal(outcome.remoteKind as AiraSyncProviderKind, true);
          }
        }
      });
      return;
    }
    if (outcome.type === 'configuration-required') {
      if (outcome.remoteKind === 'webdav') {
        this.navigationCoordinator.openSyncWebdavConfig(
          this.buildBoundary('sync_experience_goal'),
          'active',
          outcome.enableDefaultContent === true
        );
        return;
      }
      if (outcome.remoteKind === 'self_hosted') {
        this.navigationCoordinator.openSyncPersonalServerConfig(
          this.buildBoundary('sync_experience_goal'),
          outcome.enableDefaultContent === true
        );
        return;
      }
      this.showDialog(outcome.title, outcome.message);
      return;
    }
    if (outcome.type === 'membership-required' && outcome.membershipDecision !== undefined) {
      this.showMembershipDecision(outcome.membershipDecision);
      return;
    }
    if (outcome.type === 'failed') {
      this.showFailureRecoveryDialog(outcome);
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
            this.resolveBookmarkConflicts(conflictRemoteKind, 'prefer-remote');
          }
        },
        secondaryButton: {
          value: '以本机为准',
          action: () => {
            this.resolveBookmarkConflicts(conflictRemoteKind, 'prefer-local');
          }
        }
      });
      return;
    }
    this.showDialog(outcome.title, outcome.message);
  }

  private showFailureRecoveryDialog(outcome: SyncExperienceActionOutcome): void {
    if (outcome.bookmarkFailure?.code === 'BKM-PROTOCOL-UPDATE-001') {
      showCenteredAlertDialog({
        title: '需要升级后才能同步',
        message: 'Aira 云书签同步已经切换到新协议。请升级 App 后再同步；本机书签和其他同步方式不会被删除。',
        autoCancel: false,
        buttonDirection: DialogButtonDirection.VERTICAL,
        buttons: [
          {
            value: '前往升级',
            primary: true,
            fontColor: this.storedOnAccentColor,
            backgroundColor: this.storedAccentColor,
            action: (): void => {
              sharedClientUpdatePolicyService.deferCurrentRequirement();
              if (!AppRuntimeContext.hasUIAbilityContext()) {
                this.showDialog('无法打开升级页面', '请稍后在应用市场搜索 Aira。');
                return;
              }
              this.systemSettingsLaunchService.openAppGalleryDetailPage(
                AppRuntimeContext.getUIAbilityContext()
              ).then((result): void => {
                if (!result.success) {
                  this.showDialog('无法打开升级页面', `${result.message} 请稍后在应用市场搜索 Aira。`);
                }
              });
            }
          },
          {
            value: '更换同步方式',
            action: (): void => {
              sharedClientUpdatePolicyService.deferCurrentRequirement();
              this.activeSheetVisible = true;
            }
          },
          {
            value: '继续使用本地功能',
            action: (): void => {
              sharedClientUpdatePolicyService.deferCurrentRequirement();
            }
          }
        ]
      });
      return;
    }
    if (outcome.retryAction === 'sync' && outcome.remoteKind !== undefined) {
      showCenteredAlertDialog({
        title: outcome.title.length > 0 ? outcome.title : '同步失败',
        message: outcome.message,
        autoCancel: true,
        buttonDirection: DialogButtonDirection.VERTICAL,
        buttons: [
          {
            value: '再次同步',
            primary: true,
            fontColor: this.storedOnAccentColor,
            backgroundColor: this.storedAccentColor,
            action: () => {
              this.syncNow();
            }
          },
          {
            value: '更换同步方式',
            fontColor: this.storedAccentColor,
            action: () => {
              this.activeSheetVisible = true;
            }
          },
          { value: '知道了', action: () => {} }
        ]
      });
      return;
    }
    if (outcome.retryAction === 'sync') {
      showCenteredAlertDialog({
        title: outcome.title.length > 0 ? outcome.title : '同步失败',
        message: outcome.message,
        autoCancel: true,
        buttonDirection: DialogButtonDirection.VERTICAL,
        buttons: [
          {
            value: '再次同步',
            primary: true,
            fontColor: this.storedOnAccentColor,
            backgroundColor: this.storedAccentColor,
            action: () => {
              this.syncNow();
            }
          },
          { value: '知道了', action: () => {} }
        ]
      });
      return;
    }
    if (outcome.remoteKind !== undefined) {
      showCenteredAlertDialog({
        title: outcome.title.length > 0 ? outcome.title : '同步失败',
        message: outcome.message,
        autoCancel: true,
        buttonDirection: DialogButtonDirection.VERTICAL,
        buttons: [
          {
            value: '更换同步方式',
            primary: true,
            fontColor: this.storedOnAccentColor,
            backgroundColor: this.storedAccentColor,
            action: () => {
              this.activeSheetVisible = true;
            }
          },
          { value: '知道了', action: () => {} }
        ]
      });
      return;
    }
    this.showDialog(outcome.title, outcome.message);
  }

  private resolveBookmarkConflicts(
    remoteKind: AiraSyncProviderKind,
    resolution: AiraBookmarkConflictResolution
  ): void {
    if (this.isBusy || this.boundary.privacyMode === 'private') {
      return;
    }
    this.isBusy = true;
    this.syncProgressController.begin('正在处理书签冲突', '正在按你的选择合并并保存书签');
    sharedSyncExperienceCoordinator.resolveBookmarkConflicts(remoteKind, resolution)
      .then((outcome: SyncExperienceActionOutcome) => {
        this.completeProgressOutcome(outcome);
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private showMembershipDecision(decision: EntitlementDecision): void {
    const isCrossSystemBookmarkUpgrade = decision.featureKey === 'cloud_sync' &&
      decision.primaryAction === 'open_pro';
    if (isCrossSystemBookmarkUpgrade) {
      showCenteredAlertDialog({
        title: 'Aira 云书签同步需要 Pro',
        message: 'Aira 官方托管的跨系统书签同步需要 Pro。你也可以免费使用个人服务器、华为云空间或 WebDAV。',
        autoCancel: true,
        buttonDirection: DialogButtonDirection.VERTICAL,
        buttons: [
          {
            value: '查看 Aira Pro',
            primary: true,
            fontColor: this.storedOnAccentColor,
            backgroundColor: this.storedAccentColor,
            action: () => {
              this.navigationCoordinator.openAiraPro(this.buildBoundary('sync_experience_membership'));
            }
          },
          {
            value: '选择其他同步方式',
            fontColor: this.storedAccentColor,
            action: () => {
              this.activeSheetVisible = true;
            }
          }
        ]
      });
      return;
    }
    showCenteredAlertDialog({
      title: decision.title.length > 0 ? decision.title : '需要 Aira Pro',
      message: decision.message,
      autoCancel: true,
      primaryButton: { value: '稍后', action: () => {} },
      secondaryButton: {
        value: decision.primaryAction === 'open_pro' ? '查看 Aira Pro' : '查看权益',
        action: () => {
          this.navigationCoordinator.openAiraPro(this.buildBoundary('sync_experience_membership'));
        }
      }
    });
  }

  private showDialog(title: string, message: string): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      confirm: { value: '知道了', action: () => {} }
    });
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

  private buildBoundary(source: string): BrowserBoundaryRouteState {
    return {
      dataScope: this.boundary.dataScope,
      privacyMode: this.boundary.privacyMode,
      boundarySource: source
    };
  }
}

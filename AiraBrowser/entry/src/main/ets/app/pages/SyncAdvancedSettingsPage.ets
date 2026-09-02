import router from '@ohos.router';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  AiraBookmarkConflictResolution,
  AiraSyncRemoteKind
} from '../../common/models/AiraSyncModels';
import {
  sharedMembershipFeature,
  sharedPreferencesRepository,
  sharedSyncExperienceCoordinator
} from '../bootstrap/BrowserAppRuntime';
import {
  AiraFeatureKey
} from '../../common/constants/MembershipFeatureKeys';
import { EntitlementDecision } from '../../common/models/MembershipModels';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import {
  BrowserPrivateBoundaryNavigationService,
  BrowserPrivateSyncBoundaryAction,
  BrowserPrivateSyncBoundaryPlan
} from '../../core/browser/BrowserPrivateBoundaryNavigationService';
import {
  SYNC_OPERATION_PROGRESS_TIMING,
  SyncOperationProgressTipsState,
  SyncOperationProgressViewModel
} from '../../core/sync/SyncOperationProgressViewModel';
import {
  SyncAdvancedProviderActionState,
  SyncAdvancedSettingsViewModel,
  SyncAdvancedStatusViewState
} from '../../core/sync/SyncAdvancedSettingsViewModel';
import {
  SyncExperienceAdvancedMergeOutcome,
  SyncExperienceAdvancedProviderReadiness,
  SyncExperienceAdvancedRemoteSummaryOutcome,
  SyncExperienceAdvancedState,
  SyncExperienceProviderSelectionPresentation
} from '../../core/sync/SyncExperienceCoordinator';
import {
  SyncAdvancedOperationsSection,
  SyncAdvancedProviderSelectionSection
} from '../components/sync/SyncAdvancedSettingsSections';
import {
  SyncFailureDetailItem,
  SyncFailurePresentationService
} from '../../core/sync/SyncFailurePresentationService';
import {
  SyncOperationProgressDialog
} from '../components/sync/SyncOperationProgressDialog';
import {
  SettingsStaticValueRow
} from '../components/settings/SettingsRows';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsScrollBody,
  SettingsSection
} from '../components/settings/SettingsLayout';
import { SyncFailureDialog } from '../components/sync/SyncFailureDialog';
import { SyncResultDialog } from '../components/sync/SyncResultDialog';
import { SyncMasterControlSection } from '../components/sync/SyncMasterControlSection';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { SYNC_SETTINGS_REFRESH_REVISION_KEY } from '../../core/sync/SyncSettingsRefreshSignal';

@Entry
@Component
struct SyncAdvancedSettingsPage {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F6F8FB';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageLink(SYNC_SETTINGS_REFRESH_REVISION_KEY) @Watch('refreshStatusFromSignal')
  private syncSettingsRefreshRevision: number = 0;
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();
  private syncAdvancedSettingsViewModel: SyncAdvancedSettingsViewModel = new SyncAdvancedSettingsViewModel();
  private syncOperationProgressViewModel: SyncOperationProgressViewModel = new SyncOperationProgressViewModel();
  private syncFailurePresentationService: SyncFailurePresentationService = new SyncFailurePresentationService();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);

  @State private isBusy: boolean = false;
  @State private isSessionEphemeral: boolean = false;
  @State private baselineText: string = '正在读取...';
  @State private localText: string = '正在读取...';
  @State private remoteText: string = '尚未检查';
  @State private lastSyncText: string = '暂无';
  @State private providerText: string = '正在读取...';
  @State private mergeActionLabel: string = '立即合并同步';
  @State private providerActionState: SyncAdvancedProviderActionState = {
    showHuaweiCloud: false,
    showHuaweiSpace: false,
    showWebdav: false,
    mergeRequiresPro: false
  };
  @State private activeRemoteKind: AiraSyncRemoteKind = 'none';
  private activeSyncServiceKey: AiraFeatureKey = '' as AiraFeatureKey;
  private activeSyncServiceName: string = '同步服务';
  private activeSyncReady: boolean = false;
  private activeSyncMissingConfigurationMessage: string = '请先开启华为云空间同步、Aira 云同步或 WebDAV。';
  private providerReadiness: SyncExperienceAdvancedProviderReadiness[] = [];
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
    customStyle: true
  });
  private syncResultDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncResultDialog({
      title: $syncResultDialogTitle,
      message: $syncResultDialogMessage
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: true
  });
  private syncProgressDialogOpen: boolean = false;
  private syncProgressTipTimer: number = -1;
  private syncProgressVisualTimer: number = -1;
  private syncProgressTimeoutTimer: number = -1;
  private syncProgressTimeoutMs: number = SYNC_OPERATION_PROGRESS_TIMING.timeoutMs;
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
    customStyle: true,
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
    this.isSessionEphemeral = this.privateBoundaryNavigationService.isSessionEphemeralRoute(
      router.getParams() as Record<string, string | undefined> | undefined
    );
    this.refreshStatus();
  }

  aboutToDisappear(): void {
    this.stopSyncProgressTimers();
  }

  onBackPress(): boolean {
    return this.syncProgressDialogOpen && this.syncFloatingInProgress;
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '高级同步选项',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: this.isSessionEphemeral,
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({
          contentSpace: 16,
          topPadding: 8,
          bottomPadding: 28
        }) {
          SyncMasterControlSection({
            isPrivateSession: this.isSessionEphemeral,
            pageBusy: this.isBusy
          })
          this.buildStatusSection()
          this.buildCloudCheckSection()
          this.buildProviderSelectionSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildStatusSection() {
    SettingsSection({ title: '当前状态' }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsStaticValueRow({
          title: '启用方式',
          value: this.providerText,
          rowPosition: 'first'
        })
        this.buildDivider()
        SettingsStaticValueRow({
          title: '同步起点',
          value: this.baselineText,
          rowPosition: 'middle'
        })
        this.buildDivider()
        SettingsStaticValueRow({
          title: '本机数据',
          value: this.localText,
          rowPosition: 'middle'
        })
        this.buildDivider()
        SettingsStaticValueRow({
          title: '远端数据',
          value: this.remoteText,
          rowPosition: 'middle'
        })
        this.buildDivider()
        SettingsStaticValueRow({
          title: '最近同步',
          value: this.lastSyncText,
          rowPosition: 'last'
        })
      }
    }
  }

  @Builder
  private buildCloudCheckSection() {
    SyncAdvancedOperationsSection({
      mergeActionLabel: this.mergeActionLabel,
      actionState: this.resolveProviderActionState(),
      isBusy: this.isBusy,
      isPrivateSession: this.isSessionEphemeral,
      accentColor: this.storedAccentColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      onMerge: () => {
        this.mergeRemoteData();
      },
      onCheckProvider: (remoteKind: AiraSyncRemoteKind) => {
        this.readProviderSummary(remoteKind);
      },
      onPushProvider: (remoteKind: AiraSyncRemoteKind) => {
        this.confirmPushLocalSnapshot(remoteKind);
      },
      onPullProvider: (remoteKind: AiraSyncRemoteKind) => {
        this.confirmPullRemoteSnapshot(remoteKind);
      }
    })
  }

  @Builder
  private buildProviderSelectionSection() {
    SyncAdvancedProviderSelectionSection({
      actionState: this.resolveProviderActionState(),
      activeRemoteKind: this.activeRemoteKind,
      isBusy: this.isBusy,
      isPrivateSession: this.isSessionEphemeral,
      accentColor: this.storedAccentColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      onSelectProvider: (remoteKind: AiraSyncRemoteKind) => {
        this.confirmSelectProvider(remoteKind);
      }
    })
  }

  @Builder
  private buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(this.storedDividerColor)
      .margin({ left: 16, right: 16 })
  }

  private refreshStatus(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    const isPrivateSession = this.isSessionEphemeral;
    this.applyAdvancedState(sharedSyncExperienceCoordinator.readAdvancedState(isPrivateSession));
    if (isPrivateSession) {
      return;
    }
    sharedSyncExperienceCoordinator.loadAdvancedState(false)
      .then((state: SyncExperienceAdvancedState) => {
        this.applyAdvancedState(state);
      })
      .catch((_error: Error) => {
      });
  }

  private applyStatusViewState(state: SyncAdvancedStatusViewState): void {
    this.providerText = state.providerText;
    this.baselineText = state.baselineText;
    this.localText = state.localText;
    this.remoteText = state.remoteText;
    this.lastSyncText = state.lastSyncText;
  }

  private applyAdvancedState(state: SyncExperienceAdvancedState): void {
    this.applyStatusViewState(state.status);
    this.providerActionState = state.providerActions;
    this.mergeActionLabel = state.mergeActionLabel;
    this.activeRemoteKind = state.activeRemoteKind;
    this.activeSyncServiceKey = state.activeSyncServiceKey;
    this.activeSyncServiceName = state.activeSyncServiceName;
    this.activeSyncReady = state.activeSyncReady;
    this.activeSyncMissingConfigurationMessage = state.activeSyncMissingConfigurationMessage;
    this.providerReadiness = state.providerReadiness;
  }

  private refreshStatusFromSignal(): void {
    this.refreshStatus();
  }

  private resolveProviderActionState(): SyncAdvancedProviderActionState {
    return this.providerActionState;
  }

  private async readProviderSummary(remoteKind: AiraSyncRemoteKind): Promise<void> {
    if (this.isBusy || !this.guardSyncBoundary('read_webdav_remote')) {
      return;
    }
    const title = this.syncAdvancedSettingsViewModel.resolveProviderCheckActionLabel(remoteKind);
    if (!this.guardProviderSyncReady(remoteKind, title)) {
      return;
    }
    if (!await this.ensureProviderSyncAccess(remoteKind, title)) {
      return;
    }
    this.isBusy = true;
    this.beginSyncFloatingOperation(
      title,
      `正在读取${this.resolveProviderShortLabel(remoteKind)}同步状态`,
      this.resolveProviderOperationTimeoutMs(remoteKind)
    );
    this.updateSyncFloatingStep(title, `正在连接${this.resolveProviderShortLabel(remoteKind)}`, 28);
    sharedSyncExperienceCoordinator.readAdvancedRemoteSummary(remoteKind)
      .then((outcome: SyncExperienceAdvancedRemoteSummaryOutcome) => {
        this.remoteText = this.syncAdvancedSettingsViewModel.updateRemoteSummaryText(
          outcome.summary
        );
        this.updateSyncFloatingStep(title, '正在更新状态显示', 72);
        this.finishSyncFloatingOperation('远端数据已更新', `${this.resolveProviderShortLabel(remoteKind)}状态已经刷新`);
      })
      .catch((error: Error) => {
        this.finishSyncFloatingOperation('检查失败', '请稍后再试');
        this.showSyncFailureDialog(title, this.resolveProviderServiceName(remoteKind), error);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  private confirmPushLocalSnapshot(remoteKind: AiraSyncRemoteKind): void {
    const title = `本机覆盖${this.resolveProviderShortLabel(remoteKind)}`;
    if (!this.guardSyncBoundary('push_webdav') || !this.guardProviderSyncReady(remoteKind, title)) {
      return;
    }
    AlertDialog.show({
      title: `${title}？`,
      message: `会把当前本机完整书签快照写入${this.resolveProviderServiceName(remoteKind)}，远端现有内容可能被替换。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '覆盖',
        action: () => {
          this.forceBookmarkAuthority(remoteKind, 'prefer-local');
        }
      }
    });
  }

  private confirmPullRemoteSnapshot(remoteKind: AiraSyncRemoteKind): void {
    const title = `${this.resolveProviderShortLabel(remoteKind)}覆盖本机`;
    if (!this.guardSyncBoundary('pull_webdav') || !this.guardProviderSyncReady(remoteKind, title)) {
      return;
    }
    AlertDialog.show({
      title: `${title}？`,
      message: `会用${this.resolveProviderServiceName(remoteKind)}的完整书签快照覆盖本机，云端删除记录也会在本机生效。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '覆盖',
        action: () => {
          this.forceBookmarkAuthority(remoteKind, 'prefer-remote');
        }
      }
    });
  }

  private async forceBookmarkAuthority(
    remoteKind: AiraSyncRemoteKind,
    resolution: AiraBookmarkConflictResolution
  ): Promise<void> {
    if (remoteKind === 'none' || this.isBusy) {
      return;
    }
    const title = resolution === 'prefer-remote'
      ? `${this.resolveProviderShortLabel(remoteKind)}覆盖本机`
      : `本机覆盖${this.resolveProviderShortLabel(remoteKind)}`;
    const boundaryAction = resolution === 'prefer-remote' ? 'pull_webdav' : 'push_webdav';
    if (!this.guardSyncBoundary(boundaryAction) || !this.guardProviderSyncReady(remoteKind, title)) {
      return;
    }
    if (!await this.ensureProviderSyncAccess(remoteKind, title)) {
      return;
    }
    this.isBusy = true;
    this.beginSyncFloatingOperation(
      title,
      resolution === 'prefer-remote'
        ? `正在读取${this.resolveProviderShortLabel(remoteKind)}数据`
        : `正在准备${this.resolveProviderShortLabel(remoteKind)}空间`,
      this.resolveProviderOperationTimeoutMs(remoteKind)
    );
    this.updateSyncFloatingStep(
      title,
      resolution === 'prefer-remote'
        ? '正在更新本机书签'
        : `正在保存本机书签到${this.resolveProviderShortLabel(remoteKind)}`,
      48
    );
    sharedSyncExperienceCoordinator.forceAdvancedBookmarkAuthority(remoteKind, resolution)
      .then((outcome: SyncExperienceAdvancedMergeOutcome) => {
        if (outcome.result.blocked) {
          this.finishSyncFloatingOperation('覆盖未完成', '请先查看同步状态', 100);
          this.showDialog(outcome.dialogTitle, outcome.message);
          return;
        }
        this.updateSyncFloatingStep(title, '正在确认同步结果', 84);
        this.finishSyncFloatingOperation(outcome.completionTitle, outcome.completionSubtitle);
        this.recordProviderSyncUsageIfNeeded(remoteKind);
        this.showDialog(outcome.dialogTitle, outcome.message);
        this.refreshStatus();
      })
      .catch((error: Error) => {
        this.finishSyncFloatingOperation('覆盖失败', '请检查网络或同步设置');
        this.showSyncFailureDialog(title, this.resolveProviderServiceName(remoteKind), error);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  private async mergeRemoteData(): Promise<void> {
    if (this.isBusy || !this.guardSyncBoundary('merge_webdav')) {
      return;
    }
    if (!this.guardActiveSyncReady('立即合并同步')) {
      return;
    }
    if (!await this.ensureActiveSyncAccess('立即合并同步')) {
      return;
    }
    this.isBusy = true;
    this.beginSyncFloatingOperation(
      '正在同步',
      '正在准备本机和云端数据',
      this.resolveProviderOperationTimeoutMs(this.resolveActiveRemoteKind())
    );
    this.updateSyncFloatingStep('正在同步', '正在比较本机和云端变化', 34);
    const activeRemoteKind = this.resolveActiveRemoteKind();
    sharedSyncExperienceCoordinator.mergeAdvancedActiveBookmarks(activeRemoteKind)
      .then((outcome: SyncExperienceAdvancedMergeOutcome) => {
        if (outcome.result.blocked) {
          this.finishSyncFloatingOperation('同步需要确认', '请先查看需要处理的内容', 100);
          this.showDialog('同步已停止', outcome.message);
          return;
        }
        this.updateSyncFloatingStep('正在同步', '正在整理同步结果', 82);
        this.finishSyncFloatingOperation(
          outcome.completionTitle,
          outcome.completionSubtitle
        );
        this.recordCloudSyncUsageIfNeeded();
        this.showDialog(outcome.dialogTitle, outcome.message);
        this.refreshStatus();
      })
      .catch((error: Error) => {
        this.finishSyncFloatingOperation('同步失败', '请稍后再试');
        this.showSyncFailureDialog('立即合并同步', this.resolveActiveSyncServiceName(), error);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  private confirmSelectProvider(remoteKind: AiraSyncRemoteKind): void {
    if (remoteKind === 'none') {
      return;
    }
    const targetName = this.resolveProviderServiceName(remoteKind);
    showCenteredAlertDialog({
      title: `改用${targetName}？`,
      message: `会先分别合并本机与${targetName}中的书签和已开启常用设置，完成后只修改当前设备的同步方式。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '合并并更改',
        action: () => {
          this.selectProvider(remoteKind);
        }
      }
    });
  }

  private selectProvider(remoteKind: AiraSyncRemoteKind): void {
    if (remoteKind === 'none' || this.isBusy || !this.guardSyncBoundary('merge_webdav')) {
      return;
    }
    this.isBusy = true;
    this.beginSyncFloatingOperation(
      '正在更改同步方式',
      `正在合并${this.resolveProviderServiceName(remoteKind)}数据`,
      this.resolveProviderOperationTimeoutMs(remoteKind)
    );
    sharedSyncExperienceCoordinator.selectAdvancedProvider(remoteKind)
      .then((presentation: SyncExperienceProviderSelectionPresentation) => {
        this.finishSyncFloatingOperation(presentation.completionTitle, presentation.completionSubtitle);
        if (presentation.type === 'blocked') {
          this.showDialog(presentation.dialogTitle, presentation.message);
          return;
        }
        if (presentation.type === 'selected') {
          this.showDialog(presentation.dialogTitle, presentation.message);
          this.refreshStatus();
          return;
        }
        if (presentation.type === 'membership-required' && presentation.membershipDecision !== undefined) {
          this.showSyncMembershipDialog(presentation.dialogTitle, presentation.membershipDecision);
          return;
        }
        this.showSyncFailureDialog(
          presentation.dialogTitle,
          presentation.providerLabel,
          new Error(presentation.message)
        );
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  private guardSyncBoundary(action: BrowserPrivateSyncBoundaryAction): boolean {
    const plan: BrowserPrivateSyncBoundaryPlan = this.privateBoundaryNavigationService.buildSyncBoundaryPlan(
      action,
      this.isSessionEphemeral ? 'session_ephemeral' : 'profile_persistent',
      this.isSessionEphemeral ? 'private' : 'regular'
    );
    if (plan.allowed) {
      return true;
    }
    this.showDialog('私密会话已隔离', plan.helperText);
    return false;
  }

  private async ensureActiveSyncAccess(title: string): Promise<boolean> {
    const featureKey = this.resolveActiveSyncServiceKey();
    return this.ensureFeatureAccess(featureKey, title);
  }

  private async ensureProviderSyncAccess(remoteKind: AiraSyncRemoteKind, title: string): Promise<boolean> {
    const featureKey = this.resolveProviderSyncServiceKey(remoteKind);
    return this.ensureFeatureAccess(featureKey, title);
  }

  private async ensureFeatureAccess(featureKey: AiraFeatureKey, title: string): Promise<boolean> {
    if (featureKey.length <= 0) {
      return true;
    }
    const decision = await sharedMembershipFeature.canUse(featureKey, {
      dataScope: this.isSessionEphemeral ? 'session_ephemeral' : 'profile_persistent',
      privacyMode: this.isSessionEphemeral ? 'private' : 'regular',
      loggedIn: true
    });
    if (decision.allowed) {
      return true;
    }
    this.showSyncMembershipDialog(title, decision);
    return false;
  }

  private showSyncMembershipDialog(title: string, decision: EntitlementDecision): void {
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
          this.navigationCoordinator.openAiraPro(this.buildBoundaryState('sync_advanced_settings'));
        }
      }
    });
  }

  private recordCloudSyncUsageIfNeeded(): void {
    const featureKey = this.resolveActiveSyncServiceKey();
    if (featureKey.length <= 0) {
      return;
    }
    void sharedMembershipFeature.recordUsage(featureKey);
  }

  private resolveActiveSyncServiceKey(): AiraFeatureKey {
    return this.activeSyncServiceKey;
  }

  private recordProviderSyncUsageIfNeeded(remoteKind: AiraSyncRemoteKind): void {
    const featureKey = this.resolveProviderSyncServiceKey(remoteKind);
    if (featureKey.length <= 0) {
      return;
    }
    void sharedMembershipFeature.recordUsage(featureKey);
  }

  private resolveProviderSyncServiceKey(remoteKind: AiraSyncRemoteKind): AiraFeatureKey {
    return this.syncAdvancedSettingsViewModel.resolveProviderSyncServiceKey(remoteKind);
  }

  private guardActiveSyncReady(title: string): boolean {
    if (this.activeSyncReady) {
      return true;
    }
    if (this.activeRemoteKind === 'none') {
      this.showDialog(title, '请先开启华为云空间同步、Aira 云同步或 WebDAV。');
      return false;
    }
    showCenteredAlertDialog({
      title: title,
      message: this.activeSyncMissingConfigurationMessage,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '去填写',
        action: () => {
          this.openActiveSyncConfigPage(this.activeRemoteKind);
        }
      }
    });
    return false;
  }

  private guardProviderSyncReady(remoteKind: AiraSyncRemoteKind, title: string): boolean {
    const readiness = this.resolveProviderReadiness(remoteKind);
    if (readiness !== undefined && readiness.ready) {
      return true;
    }
    showCenteredAlertDialog({
      title: title,
      message: readiness?.missingConfigurationMessage ?? '请先启用这个同步方式。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '去设置',
        action: () => {
          this.openActiveSyncConfigPage(remoteKind);
        }
      }
    });
    return false;
  }

  private resolveActiveRemoteKind(): AiraSyncRemoteKind {
    return this.activeRemoteKind;
  }

  private resolveActiveSyncServiceName(): string {
    return this.activeSyncServiceName;
  }

  private resolveProviderReadiness(
    remoteKind: AiraSyncRemoteKind
  ): SyncExperienceAdvancedProviderReadiness | undefined {
    return this.providerReadiness.find((value: SyncExperienceAdvancedProviderReadiness): boolean => {
      return value.remoteKind === remoteKind;
    });
  }

  private resolveProviderServiceName(remoteKind: AiraSyncRemoteKind): string {
    return this.syncAdvancedSettingsViewModel.resolveProviderServiceName(remoteKind);
  }

  private resolveProviderShortLabel(remoteKind: AiraSyncRemoteKind): string {
    return this.syncAdvancedSettingsViewModel.resolveProviderShortLabel(remoteKind);
  }

  private resolveProviderOperationTimeoutMs(remoteKind: AiraSyncRemoteKind): number {
    return this.syncAdvancedSettingsViewModel.resolveProviderOperationTimeoutMs(remoteKind);
  }

  private openWebdavConfigPage(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.navigationCoordinator.openSyncWebdavConfig(this.buildBoundaryState('sync_advanced_settings'));
  }

  private openActiveSyncConfigPage(remoteKind: AiraSyncRemoteKind): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (remoteKind === 'aira_cloud') {
      this.navigationCoordinator.openSyncSettings(this.buildBoundaryState('sync_advanced_settings'));
      return;
    }
    if (remoteKind === 'huawei_space') {
      this.navigationCoordinator.openSyncSettings(this.buildBoundaryState('sync_advanced_settings'));
      return;
    }
    this.openWebdavConfigPage();
  }

  private buildBoundaryState(boundarySource: string): BrowserBoundaryRouteState {
    return {
      dataScope: this.isSessionEphemeral ? 'session_ephemeral' : 'profile_persistent',
      privacyMode: this.isSessionEphemeral ? 'private' : 'regular',
      boundarySource: boundarySource
    };
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

  private beginSyncFloatingOperation(
    title: string,
    subtitle: string,
    timeoutMs: number = SYNC_OPERATION_PROGRESS_TIMING.timeoutMs
  ): void {
    this.stopSyncProgressTimers();
    this.syncFloatingTitle = title;
    this.syncFloatingSubtitle = subtitle;
    this.syncFloatingProgress = 0;
    this.syncProgressTimeoutMs = timeoutMs;
    this.syncProgressTargetProgress = SYNC_OPERATION_PROGRESS_TIMING.inProgressTarget;
    this.syncProgressStartTime = Date.now();
    this.syncFloatingInProgress = true;
    this.beginSyncProgressTips(title, subtitle);
    this.startSyncProgressVisualTimer();
    this.startSyncProgressTimeoutTimer();
    this.openSyncProgressDialog();
  }

  private updateSyncFloatingStep(title: string, subtitle: string, progress: number): void {
    this.syncFloatingTitle = title;
    this.syncFloatingSubtitle = subtitle;
    this.syncProgressTargetProgress = Math.max(this.syncProgressTargetProgress, progress);
    this.appendSyncProgressTip(subtitle);
    this.showSyncProgressTip(subtitle);
  }

  private finishSyncFloatingOperation(title: string, subtitle: string, progress: number = 100): void {
    if (!this.syncProgressDialogOpen) {
      return;
    }
    if (this.shouldAnimateProgressCompletion(title, progress)) {
      this.completeSyncProgressWithRamp(title, subtitle);
      return;
    }
    this.syncFloatingTitle = title;
    this.syncFloatingSubtitle = subtitle;
    this.syncFloatingProgress = progress;
    this.showSyncProgressTip(subtitle);
    const remainingMs = Math.max(0, SYNC_OPERATION_PROGRESS_TIMING.minVisibleMs -
    (Date.now() - this.syncProgressStartTime));
    if (remainingMs > 0) {
      this.syncProgressFinishTimer = setTimeout(() => {
        this.completeSyncProgressDialog();
      }, remainingMs);
      return;
    }
    this.completeSyncProgressDialog();
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
      this.isBusy = false;
      this.showDialog('操作超时', message);
    }, this.syncProgressTimeoutMs);
  }

  private completeSyncProgressDialog(): void {
    this.syncFloatingInProgress = false;
    this.stopSyncProgressTimers();
    this.closeSyncProgressDialog();
  }

  private completeSyncProgressWithRamp(title: string, subtitle: string): void {
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
      }, SYNC_OPERATION_PROGRESS_TIMING.successVisibleMs);
    }, SYNC_OPERATION_PROGRESS_TIMING.finishIntervalMs);
  }

  private shouldAnimateProgressCompletion(title: string, progress: number): boolean {
    if (progress < 100) {
      return false;
    }
    return title.indexOf('失败') < 0 &&
      title.indexOf('取消') < 0 &&
      title.indexOf('需要确认') < 0;
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

  private stringifyError(error: Error): string {
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    const serialized = JSON.stringify(error);
    return serialized.length > 0 ? serialized : '未知错误';
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}

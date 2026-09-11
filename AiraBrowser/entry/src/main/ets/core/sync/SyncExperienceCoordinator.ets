import { EntitlementDecision } from '../../common/models/MembershipModels';
import { AiraCloudBookmarkV4BootstrapTransitionDomain } from
  '../../common/models/AiraCloudBookmarkV4BootstrapModels';
import {
  AIRA_FEATURE_CLOUD_SYNC,
  AiraFeatureKey
} from '../../common/constants/MembershipFeatureKeys';
import {
  AiraAdditionalBackupIntervalDays,
  AiraBookmarkConflictResolution,
  AiraBookmarkMergeSyncResult,
  AiraBookmarkSyncFailure,
  AiraSyncDomainRuntimeState,
  AiraSyncProviderKind,
  AiraSyncRemoteKind,
  AiraSyncSettings,
  resolveAiraHuaweiAccountIdentity,
  resolveAiraPersonalServerConfig,
  resolveAiraSyncDomainRuntimeState
} from '../../common/models/AiraSyncModels';
import {
  PERSONALIZATION_SYNC_ITEM_IDS,
  PersonalizationSyncConfig,
  PersonalizationSyncContentId,
  PersonalizationSyncItemId,
  PersonalizationSyncRunResult
} from '../../common/models/PersonalizationSyncModels';
import { NovelBookshelfSyncSelectionState } from '../../common/models/NovelBookshelfSyncModels';
import { PersonalizationSyncConfigStore } from '../../data/sync/PersonalizationSyncConfigStore';
import {
  HuaweiSpaceBookmarkUpgradeStore
} from '../../data/sync/HuaweiSpaceBookmarkUpgradeStore';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  SyncExperiencePersistedState,
  SyncExperienceStateStore
} from '../../data/sync/SyncExperienceStateStore';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import {
  HistorySyncService,
  resolveHistorySyncProviderKind
} from '../../services/sync/HistorySyncService';
import { SyncService } from '../../services/sync/SyncService';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';
import {
  SyncExperienceAutomaticRuntime,
  SyncExperienceRuntimeRunResult
} from './SyncExperienceAutomaticRuntime';
import { SyncBookmarkDomain } from './SyncBookmarkDomain';
import {
  SyncExperienceViewModel,
  SyncExperienceViewState
} from './SyncExperienceViewModel';
import { SyncPersonalizationDomain } from './SyncPersonalizationDomain';
import {
  SyncExperienceProviderOperations,
  SyncExperienceProviderOutcome,
  SyncWebdavActivationOutcome,
  SyncWebdavConfigurationParams
} from './SyncExperienceProviderOperations';
import { SyncActivationResult } from './SyncActivationModels';
import {
  SyncAdditionalBackupViewModel,
  SyncAdditionalBackupViewState
} from './SyncAdditionalBackupViewModel';
import { SyncSettingsCenterViewModel } from './SyncSettingsCenterViewModel';
import {
  SyncAdvancedProviderActionState,
  SyncAdvancedSettingsViewModel,
  SyncAdvancedStatusViewState
} from './SyncAdvancedSettingsViewModel';
import {
  SyncAdvancedMergeOutcome,
  SyncAdvancedRemoteSummaryOutcome,
  SyncAdvancedStatusOverview,
  SyncExperienceAdvancedOperations,
  SyncProviderSelectionPresentation
} from './SyncExperienceAdvancedOperations';
import {
  SyncFirstActivationItemState,
  SyncFirstActivationItemsState
} from './SyncFirstActivationItemsCoordinator';
import { SyncWebdavProviderRole } from './SyncWebdavConfigViewModel';
import { SyncFailurePresentationService } from './SyncFailurePresentationService';

export type SyncExperienceActionOutcomeType =
  | 'completed'
  | 'confirmation-required'
  | 'configuration-required'
  | 'membership-required'
  | 'blocked'
  | 'failed';

export type SyncExperienceRetryAction = 'sync' | 'reload';

export interface SyncExperienceActionOutcome {
  type: SyncExperienceActionOutcomeType;
  title: string;
  message: string;
  remoteKind?: AiraSyncProviderKind;
  membershipDecision?: EntitlementDecision;
  enableDefaultContent?: boolean;
  requiresBookmarkResolution?: boolean;
  bookmarkFailure?: AiraBookmarkSyncFailure;
  personalizationConfig?: PersonalizationSyncConfig;
  retryAction?: SyncExperienceRetryAction;
}

export interface SyncExperienceHuaweiSpaceBookmarkUpgradePromptState {
  required: boolean;
  shouldPresent: boolean;
}

export type SyncAdditionalBackupActionOutcomeType = 'completed' | 'blocked' | 'failed';

export interface SyncAdditionalBackupActionOutcome {
  type: SyncAdditionalBackupActionOutcomeType;
  title: string;
  message: string;
  requiresOptions?: boolean;
}

export type SyncExperienceProviderSelectionOutcome = SyncExperienceProviderOutcome;

export type SyncExperienceWebdavActivationOutcome = SyncWebdavActivationOutcome;
export type SyncExperienceWebdavConfigurationParams = SyncWebdavConfigurationParams;
export type SyncExperienceWebdavTargetRole = 'active' | 'additional_backup';

export interface SyncExperienceWebdavConfigurationState {
  endpoint: string;
  username: string;
  password: string;
  providerRole: SyncWebdavProviderRole;
  bookmarkDomainEnabled: boolean;
}

export type SyncExperienceAdvancedMergeOutcome = SyncAdvancedMergeOutcome;
export type SyncExperienceAdvancedRemoteSummaryOutcome = SyncAdvancedRemoteSummaryOutcome;
export type SyncExperienceProviderSelectionPresentation = SyncProviderSelectionPresentation;

export interface SyncExperienceAdvancedProviderReadiness {
  remoteKind: AiraSyncProviderKind;
  ready: boolean;
  missingConfigurationMessage: string;
}

export interface SyncExperienceAdvancedState {
  status: SyncAdvancedStatusViewState;
  providerActions: SyncAdvancedProviderActionState;
  mergeActionLabel: string;
  activeRemoteKind: AiraSyncRemoteKind;
  activeSyncServiceKey: AiraFeatureKey;
  activeSyncServiceName: string;
  activeSyncReady: boolean;
  activeSyncMissingConfigurationMessage: string;
  providerReadiness: SyncExperienceAdvancedProviderReadiness[];
}

interface SyncExperienceDomainIssue {
  domain: 'bookmark' | 'personalization' | 'history';
  type: 'blocked' | 'failed';
  message?: string;
  failure?: AiraBookmarkSyncFailure;
}

interface SyncExperienceContext {
  settings: AiraSyncSettings;
  activeProvider: AiraSyncRemoteKind;
  experienceState: SyncExperiencePersistedState;
}

export class SyncExperienceCoordinator implements AiraCloudBookmarkV4BootstrapTransitionDomain {
  private syncFailurePresentationService: SyncFailurePresentationService = new SyncFailurePresentationService();
  private syncService: SyncService;
  private syncConfigStore: AiraSyncConfigStore;
  private personalizationConfigStore: PersonalizationSyncConfigStore;
  private experienceStateStore: SyncExperienceStateStore;
  private providerOperations: SyncExperienceProviderOperations;
  private personalizationDomain: SyncPersonalizationDomain;
  private bookmarkDomain: SyncBookmarkDomain;
  private historySyncService: HistorySyncService;
  private automaticRuntime: SyncExperienceAutomaticRuntime;
  private advancedOperations: SyncExperienceAdvancedOperations;
  private membershipFeature: MembershipFeature;
  private huaweiSpaceBookmarkUpgradeStore: HuaweiSpaceBookmarkUpgradeStore;
  private huaweiSpaceBookmarkUpgradePreparationPromise?: Promise<void>;
  private pendingGoalChangePromise?: Promise<SyncExperienceActionOutcome>;
  private viewModel: SyncExperienceViewModel = new SyncExperienceViewModel();
  private additionalBackupViewModel: SyncAdditionalBackupViewModel = new SyncAdditionalBackupViewModel();
  private settingsCenterViewModel: SyncSettingsCenterViewModel = new SyncSettingsCenterViewModel();
  private advancedViewModel: SyncAdvancedSettingsViewModel = new SyncAdvancedSettingsViewModel();

  constructor(
    syncService: SyncService,
    syncConfigStore: AiraSyncConfigStore,
    personalizationConfigStore: PersonalizationSyncConfigStore,
    experienceStateStore: SyncExperienceStateStore,
    providerOperations: SyncExperienceProviderOperations,
    personalizationDomain: SyncPersonalizationDomain,
    bookmarkDomain: SyncBookmarkDomain,
    historySyncService: HistorySyncService,
    automaticRuntime: SyncExperienceAutomaticRuntime,
    advancedOperations: SyncExperienceAdvancedOperations,
    membershipFeature: MembershipFeature,
    huaweiSpaceBookmarkUpgradeStore: HuaweiSpaceBookmarkUpgradeStore =
      new HuaweiSpaceBookmarkUpgradeStore()
  ) {
    this.syncService = syncService;
    this.syncConfigStore = syncConfigStore;
    this.personalizationConfigStore = personalizationConfigStore;
    this.experienceStateStore = experienceStateStore;
    this.providerOperations = providerOperations;
    this.personalizationDomain = personalizationDomain;
    this.bookmarkDomain = bookmarkDomain;
    this.historySyncService = historySyncService;
    this.automaticRuntime = automaticRuntime;
    this.advancedOperations = advancedOperations;
    this.membershipFeature = membershipFeature;
    this.huaweiSpaceBookmarkUpgradeStore = huaweiSpaceBookmarkUpgradeStore;
  }

  async load(): Promise<SyncExperienceViewState> {
    await this.awaitPendingGoalChange();
    await this.prepareHuaweiSpaceBookmarkUpgrade();
    await this.completeHuaweiSpaceBookmarkUpgradeIfNeeded(
      this.syncService.getAiraSyncSettings().remoteKind
    );
    const settings = this.syncService.getAiraSyncSettings();
    const activeProvider = settings.remoteKind;
    const values = await Promise.all([
      this.personalizationConfigStore.initialize(),
      this.reconcileHistoryAccountBinding(settings),
      this.personalizationDomain.initializeNovelBookshelfSelection()
    ]);
    const experienceState = values[1];
    return this.viewModel.buildState({
      settings: settings,
      personalizationConfig: values[0],
      experienceState: experienceState,
      novelBookshelfSyncEnabled: values[2].enabled,
      airaCloudEligible: this.membershipFeature.getState().plan === 'pro',
      isSyncing: this.automaticRuntime.isRunning(),
      huaweiSpaceBookmarkUpgradeRequired: this.isHuaweiSpaceBookmarkUpgradeRequired(settings)
    });
  }

  runLocalBackupImport<T>(operation: () => Promise<T>): Promise<T> {
    return this.automaticRuntime.runProviderTransition(operation);
  }

  runAiraCloudBookmarkV4Bootstrap<T>(operation: () => Promise<T>): Promise<T> {
    return this.automaticRuntime.runProviderTransition(operation);
  }

  async prepareHuaweiSpaceBookmarkUpgrade(): Promise<SyncExperienceHuaweiSpaceBookmarkUpgradePromptState> {
    if (this.huaweiSpaceBookmarkUpgradePreparationPromise === undefined) {
      this.huaweiSpaceBookmarkUpgradePreparationPromise = this.runHuaweiSpaceBookmarkUpgradePreparation()
        .catch((error: Error) => {
          this.huaweiSpaceBookmarkUpgradePreparationPromise = undefined;
          throw error;
        });
    }
    await this.huaweiSpaceBookmarkUpgradePreparationPromise;
    return {
      required: this.huaweiSpaceBookmarkUpgradeStore.isCurrentVersionRequired(),
      shouldPresent: this.huaweiSpaceBookmarkUpgradeStore.shouldPresentCurrentVersion()
    };
  }

  async acknowledgeHuaweiSpaceBookmarkUpgradePrompt(): Promise<void> {
    await this.huaweiSpaceBookmarkUpgradeStore.markPrompted();
  }

  bindPreferenceChanges(preferencesRepository: PreferencesRepository): void {
    this.automaticRuntime.bindPreferenceChanges(preferencesRepository);
  }

  markSyncRepositoriesReady(): void {
    this.automaticRuntime.markRepositoriesReady();
  }

  notifyAppContentReady(): void {
    AiraSyncJankProbe.mark('content_ready_requested');
    this.runAfterHuaweiSpaceBookmarkUpgradePreparation((): void => {
      this.automaticRuntime.notifyAppContentReady();
    });
  }

  notifyAppForeground(): void {
    this.runAfterHuaweiSpaceBookmarkUpgradePreparation((): void => {
      this.automaticRuntime.notifyAppForeground();
    });
  }

  notifyAppBackground(): void {
    this.automaticRuntime.notifyAppBackground();
  }

  notifyBookmarkSurfaceForeground(): void {
    this.automaticRuntime.scheduleBookmarkPeriodicSync();
  }

  recordBookmarkMutation(changedAt: number): Promise<void> {
    return this.automaticRuntime.recordBookmarkMutation(changedAt);
  }

  runPendingBookmarksOnForeground(): void {
    this.runAfterHuaweiSpaceBookmarkUpgradePreparation((): void => {
      this.automaticRuntime.runPendingBookmarksOnForeground();
    });
  }

  notifyPersonalizationLocalSettingsChanged(): void {
    this.automaticRuntime.notifyPersonalizationLocalSettingsChanged();
  }

  notifyHomeShortcutsChanged(): void {
    this.automaticRuntime.notifyHomeShortcutsChanged();
  }

  notifyMembershipStateChanged(): void {
    this.automaticRuntime.notifyMembershipStateChanged();
  }

  async reconcileHistoryAccountLifecycle(): Promise<SyncExperiencePersistedState> {
    this.automaticRuntime.cancelHistoryAutomaticSync();
    const settings = await this.syncService.initializeAiraSyncSettings();
    const accountUid = this.resolveHistoryAccountUid(settings);
    await this.historySyncService.cancelForIdentityChange(accountUid);
    const state = await this.reconcileHistoryAccountBinding(settings);
    await this.historySyncService.detachRemoteProjectionsExcept(accountUid);
    await this.automaticRuntime.notifyAccountChanged();
    return state;
  }

  private async reconcileHistoryAccountBinding(
    currentSettings?: AiraSyncSettings
  ): Promise<SyncExperiencePersistedState> {
    const settings = currentSettings ?? await this.syncService.initializeAiraSyncSettings();
    const initializedState = await this.experienceStateStore.initialize(
      settings.bookmarkSyncEnabled === true,
      settings.personalizationSyncEnabled === true,
      settings.remoteKind !== 'none'
    );
    const state = await this.clearHistorySelectionForWebdav(settings.remoteKind, initializedState);
    if (!state.historySelected) {
      return state;
    }
    const accountUid = this.resolveHistoryAccountUid(settings);
    const boundAccountUid = state.historyAccountUid.trim();
    if (boundAccountUid.length > 0 && boundAccountUid !== accountUid) {
      const cleared = await this.experienceStateStore.setHistorySelected(false);
      this.automaticRuntime.cancelHistoryAutomaticSync();
      return cleared;
    }
    if (boundAccountUid.length <= 0 && accountUid.length > 0 &&
      resolveHistorySyncProviderKind(settings.remoteKind) !== undefined) {
      return this.experienceStateStore.setHistorySelected(true, accountUid);
    }
    return state;
  }

  requestGoalChange(
    remoteKind: AiraSyncProviderKind,
    confirmed: boolean = false,
    firstActivationItems?: SyncFirstActivationItemsState
  ): Promise<SyncExperienceActionOutcome> {
    const operation = this.executeGoalChange(remoteKind, confirmed, firstActivationItems);
    return this.trackGoalChange(operation);
  }

  private async executeGoalChange(
    remoteKind: AiraSyncProviderKind,
    confirmed: boolean,
    firstActivationItems?: SyncFirstActivationItemsState
  ): Promise<SyncExperienceActionOutcome> {
    try {
      const context = await this.loadContext();
      let providerSwitchMessage = '';
      const hasNoActiveProvider = context.activeProvider === 'none';
      const needsInitialDomainActivation = hasNoActiveProvider ||
        (context.settings.bookmarkSyncEnabled !== true && context.settings.personalizationSyncEnabled !== true &&
          !context.experienceState.suspended);
      if (needsInitialDomainActivation && firstActivationItems !== undefined) {
        await this.persistFirstActivationItems(firstActivationItems);
      }
      const firstActivationSelection = this.experienceStateStore.getState();
      if (needsInitialDomainActivation && !firstActivationSelection.bookmarkSelected &&
        !firstActivationSelection.personalizationSelected && !firstActivationSelection.historySelected) {
        return {
          type: 'blocked',
          title: '请选择同步内容',
          message: '至少开启书签、历史记录、主页收藏、小说书架或一项常用设置后再继续。'
        };
      }
      if (needsInitialDomainActivation && remoteKind === 'webdav' &&
        !firstActivationSelection.bookmarkSelected && !firstActivationSelection.personalizationSelected) {
        return {
          type: 'blocked',
          title: '请选择 WebDAV 支持的同步内容',
          message: 'WebDAV 不同步历史记录，请至少选择书签、主页收藏、小说书架或一项常用设置。'
        };
      }
      if (remoteKind === 'webdav' && context.settings.webdav.endpoint.trim().length <= 0) {
        return {
          type: 'configuration-required',
          title: '配置 WebDAV',
          message: '请先填写 WebDAV 服务器信息。',
          remoteKind: 'webdav',
          enableDefaultContent: needsInitialDomainActivation
        };
      }
      if (remoteKind === 'self_hosted') {
        const selfHosted = resolveAiraPersonalServerConfig(context.settings);
        if (selfHosted.baseUrl.trim().length <= 0 || selfHosted.instanceId.trim().length <= 0 ||
          selfHosted.credentialId.trim().length <= 0 || selfHosted.deviceToken.trim().length <= 0) {
          return {
            type: 'configuration-required',
            title: '连接个人服务器',
            message: '请先填写服务器地址并使用一次性配对码连接。',
            remoteKind: 'self_hosted',
            enableDefaultContent: needsInitialDomainActivation
          };
        }
      }
      if (!hasNoActiveProvider && context.activeProvider !== remoteKind && !confirmed) {
        return {
          type: 'confirmation-required',
          title: '更改同步方式？',
          message: `将改为“${this.viewModel.resolveGoalLabel(remoteKind)}”。现有数据会安全合并；当前同步方式不会自动变成备份。需要备份时请单独开启。`,
          remoteKind: remoteKind
        };
      }
      const requestOutcome = await this.providerOperations.requestProviderSelection(remoteKind);
      const requestResult = this.mapProviderSelectionRequestOutcome(requestOutcome);
      if (requestResult !== undefined) {
        if (requestResult.type === 'configuration-required') {
          requestResult.enableDefaultContent = needsInitialDomainActivation;
        }
        return requestResult;
      }
      if (requestOutcome.type === 'no-action' && !needsInitialDomainActivation) {
        return {
          type: 'completed',
          title: '同步方式未更改',
          message: `当前正在使用“${this.viewModel.resolveGoalLabel(remoteKind, context.settings)}”。`,
          remoteKind: remoteKind
        };
      }
      if (hasNoActiveProvider && needsInitialDomainActivation) {
        return this.activateFirstSelection(remoteKind, firstActivationSelection);
      }
      if (requestOutcome.type === 'provider-selection-confirmation-required') {
        const switchOutcome = await this.providerOperations.selectProvider(remoteKind);
        const switchResult = this.mapProviderSelectionCompletionOutcome(switchOutcome);
        if (switchResult !== undefined) {
          return switchResult;
        }
        providerSwitchMessage = switchOutcome.message;
      }
      if (needsInitialDomainActivation) {
        const activationOutcome = await this.activateFirstSelection(
          remoteKind,
          firstActivationSelection
        );
        if (providerSwitchMessage.length > 0 && activationOutcome.type === 'completed') {
          activationOutcome.message = `${providerSwitchMessage}\n${activationOutcome.message}`;
        }
        return activationOutcome;
      }
      if (!this.isHuaweiBookmarkInitializationPending(this.syncService.getAiraSyncSettings())) {
        await this.refreshBookmarkRemoteStatus(remoteKind);
      }
      return {
        type: 'completed',
        title: '同步方式已更改',
        message: providerSwitchMessage.length > 0
          ? providerSwitchMessage
          : `现在会在“${this.viewModel.resolveGoalLabel(remoteKind)}”保持数据一致。`,
        remoteKind: remoteKind
      };
    } catch (error) {
      return this.failure('更改同步方式失败', error as Error, remoteKind);
    }
  }

  private trackGoalChange(
    operation: Promise<SyncExperienceActionOutcome>
  ): Promise<SyncExperienceActionOutcome> {
    this.pendingGoalChangePromise = operation;
    operation.then(
      (): void => {
        this.clearPendingGoalChange(operation);
      },
      (): void => {
        this.clearPendingGoalChange(operation);
      }
    );
    return operation;
  }

  private async awaitPendingGoalChange(): Promise<void> {
    const operation = this.pendingGoalChangePromise;
    if (operation === undefined) {
      return;
    }
    try {
      await operation;
    } catch (_error) {
    }
  }

  private clearPendingGoalChange(operation: Promise<SyncExperienceActionOutcome>): void {
    if (this.pendingGoalChangePromise === operation) {
      this.pendingGoalChangePromise = undefined;
    }
  }

  async completeConfiguredGoal(remoteKind: AiraSyncProviderKind): Promise<SyncExperienceActionOutcome> {
    try {
      return await this.requestGoalChange(remoteKind, true);
    } catch (error) {
      return this.failure('同步未完全开启', error as Error, remoteKind);
    }
  }

  async requestFirstActivationWebdavConfiguration(
    firstActivationItems: SyncFirstActivationItemsState
  ): Promise<SyncExperienceActionOutcome> {
    try {
      const context = await this.loadContext();
      if (context.activeProvider !== 'none') {
        return {
          type: 'blocked',
          title: '同步状态已更新',
          message: '当前设备已经选择了同步方式，请返回同步页面确认后再编辑 WebDAV 配置。',
          remoteKind: 'webdav'
        };
      }
      await this.persistFirstActivationItems(firstActivationItems);
      const selection = this.experienceStateStore.getState();
      if (!selection.bookmarkSelected && !selection.personalizationSelected && !selection.historySelected) {
        return {
          type: 'blocked',
          title: '请选择同步内容',
          message: '至少开启书签、历史记录、主页收藏、小说书架或一项常用设置后再继续。',
          remoteKind: 'webdav'
        };
      }
      return {
        type: 'configuration-required',
        title: '配置 WebDAV',
        message: '请先填写 WebDAV 服务器信息。',
        remoteKind: 'webdav',
        enableDefaultContent: true
      };
    } catch (error) {
      return this.failure('WebDAV 同步未开启', this.normalizeError(error), 'webdav');
    }
  }

  async configureWebdavAndActivate(
    params: SyncWebdavConfigurationParams
  ): Promise<SyncExperienceActionOutcome> {
    try {
      const configurationOutcome = await this.providerOperations.saveWebdavConfiguration('active', params, true);
      if (configurationOutcome.type === 'configuration-saved') {
        return await this.completeConfiguredGoal('webdav');
      }
      if (configurationOutcome.membershipDecision !== undefined) {
        return {
          type: 'membership-required',
          title: configurationOutcome.title,
          message: configurationOutcome.message,
          remoteKind: 'webdav',
          membershipDecision: configurationOutcome.membershipDecision
        };
      }
      return {
        type: configurationOutcome.type === 'activation-blocked' ? 'blocked' : 'failed',
        title: configurationOutcome.title,
        message: configurationOutcome.message,
        remoteKind: 'webdav'
      };
    } catch (error) {
      return this.failure('WebDAV 同步未开启', this.normalizeError(error), 'webdav');
    }
  }

  readWebdavConfigurationState(): SyncExperienceWebdavConfigurationState {
    return this.buildWebdavConfigurationState(this.syncConfigStore.getSettings());
  }

  async loadWebdavConfigurationState(): Promise<SyncExperienceWebdavConfigurationState> {
    return this.buildWebdavConfigurationState(await this.syncConfigStore.initialize());
  }

  async saveWebdavConfiguration(
    role: SyncExperienceWebdavTargetRole,
    params: SyncExperienceWebdavConfigurationParams
  ): Promise<SyncExperienceWebdavActivationOutcome> {
    return this.providerOperations.saveWebdavConfiguration(role, params);
  }

  async deactivateWebdav(): Promise<SyncExperienceWebdavActivationOutcome> {
    return this.providerOperations.deactivateWebdav();
  }

  async signInHuaweiAccountForSync(): Promise<SyncExperienceWebdavActivationOutcome> {
    return this.providerOperations.signInHuaweiAccountForSync();
  }

  async signInHuaweiAccount(): Promise<SyncActivationResult> {
    return this.providerOperations.signInHuaweiAccount();
  }

  async refreshHuaweiAccountIdentity(): Promise<SyncActivationResult> {
    return this.providerOperations.refreshHuaweiAccountIdentity();
  }

  async clearHuaweiAccountIdentity(): Promise<void> {
    return this.providerOperations.clearHuaweiAccountIdentity();
  }

  async deactivateForAppServiceMode(): Promise<void> {
    try {
      await this.providerOperations.deactivateCurrentSync();
    } catch (error) {
      throw this.normalizeError(error as Object);
    }
  }

  readAdvancedState(isPrivateSession: boolean = false): SyncExperienceAdvancedState {
    return this.buildAdvancedState(this.syncConfigStore.getSettings(), undefined, isPrivateSession);
  }

  async loadAdvancedState(isPrivateSession: boolean = false): Promise<SyncExperienceAdvancedState> {
    const settings = await this.syncConfigStore.initialize();
    if (isPrivateSession) {
      return this.buildAdvancedState(settings, undefined, true);
    }
    const enabledKinds = this.advancedViewModel.resolveEnabledRemoteKinds(settings);
    const overview = await this.advancedOperations.loadStatusOverview(enabledKinds);
    return this.buildAdvancedState(this.syncConfigStore.getSettings(), overview, false);
  }

  async readAdvancedRemoteSummary(
    remoteKind: AiraSyncRemoteKind
  ): Promise<SyncExperienceAdvancedRemoteSummaryOutcome> {
    return this.advancedOperations.readRemoteSummary(remoteKind);
  }

  async mergeAdvancedActiveBookmarks(
    remoteKind: AiraSyncRemoteKind
  ): Promise<SyncExperienceAdvancedMergeOutcome> {
    const runResult = await this.automaticRuntime.runManualBookmarkMaintenance();
    const bookmarkOutcome = runResult.bookmark;
    if (bookmarkOutcome === undefined) {
      throw new Error('书签同步尚未开启。');
    }
    if (bookmarkOutcome.result === undefined) {
      throw new Error(this.syncFailurePresentationService.buildBookmarkFailureMessage({
        remoteKind: remoteKind,
        operationName: '书签同步',
        failure: bookmarkOutcome.failure
      }));
    }
    return this.advancedOperations.presentActiveBookmarkMerge(remoteKind, bookmarkOutcome.result);
  }

  async forceAdvancedBookmarkAuthority(
    remoteKind: AiraSyncProviderKind,
    resolution: AiraBookmarkConflictResolution
  ): Promise<SyncExperienceAdvancedMergeOutcome> {
    return this.automaticRuntime.runProviderTransition(() => {
      return this.advancedOperations.forceBookmarkAuthority(remoteKind, resolution);
    });
  }

  async selectAdvancedProvider(
    remoteKind: AiraSyncRemoteKind
  ): Promise<SyncExperienceProviderSelectionPresentation> {
    return this.advancedOperations.selectProvider(remoteKind);
  }

  async setMasterEnabled(enabled: boolean): Promise<SyncExperienceActionOutcome> {
    try {
      const context = await this.loadContext();
      if (enabled && context.activeProvider === 'none') {
        return {
          type: 'configuration-required',
          title: '请选择同步方式',
          message: '先选择希望数据出现在哪些设备上。'
        };
      }
      return enabled
        ? await this.resumeExperience(context.experienceState)
        : await this.suspendExperience(context.settings, context.experienceState);
    } catch (error) {
      return this.failure(enabled ? '恢复同步失败' : '暂停同步失败', error as Error);
    }
  }

  async setBookmarkSelected(selected: boolean): Promise<SyncExperienceActionOutcome> {
    try {
      const context = await this.loadContext();
      if (context.experienceState.suspended || context.activeProvider === 'none') {
        await this.experienceStateStore.setBookmarkSelected(selected);
        return {
          type: 'completed',
          title: selected ? '已选择书签' : '已暂停书签',
          message: context.experienceState.suspended
            ? '重新开启同步后会按此选择恢复。'
            : '开启同步后会按此选择同步。'
        };
      }
      const outcome = await this.providerOperations.setBookmarkDomainEnabled(selected);
      if (outcome.type === 'bookmark-domain-enabled' || outcome.type === 'bookmark-domain-disabled') {
        if (selected) {
          await this.completeHuaweiSpaceBookmarkUpgradeIfNeeded(context.activeProvider);
          if (!this.isHuaweiBookmarkInitializationPending(this.syncService.getAiraSyncSettings())) {
            await this.refreshBookmarkRemoteStatus(context.activeProvider);
          }
        }
        await this.experienceStateStore.setBookmarkSelected(selected);
        return {
          type: 'completed',
          title: selected ? '书签同步已开启' : '书签同步已暂停',
          message: outcome.message
        };
      }
      return this.mapProviderSelectionFailure(outcome);
    } catch (error) {
      const activeProvider = this.syncService.getAiraSyncSettings().remoteKind;
      return {
        type: 'failed',
        title: selected ? '书签同步未开启' : '书签同步未关闭',
        message: this.syncFailurePresentationService.buildBookmarkFailureMessage({
          remoteKind: activeProvider,
          operationName: selected ? '开启书签同步' : '暂停书签同步',
          failure: this.syncService.resolveBookmarkSyncFailure(error as Error)
        })
      };
    }
  }

  async setHistorySelected(selected: boolean): Promise<SyncExperienceActionOutcome> {
    try {
      const context = await this.loadContext();
      if (!selected) {
        await this.experienceStateStore.setHistorySelected(false);
        this.automaticRuntime.cancelHistoryAutomaticSync();
        return {
          type: 'completed',
          title: '历史记录同步已暂停',
          message: `本机和${this.resolveHistoryProviderLabel(context.activeProvider)}` +
            '已有历史记录都已保留。'
        };
      }
      if (context.activeProvider === 'none') {
        return {
          type: 'configuration-required',
          title: '请先选择同步方式',
          message: '历史记录会跟随当前同步方式。'
        };
      }
      if (context.activeProvider === 'webdav') {
        return {
          type: 'blocked',
          title: 'WebDAV 不支持历史记录同步',
          message: '本机历史记录已保留。切换到 Aira 云或华为云空间后，可以重新开启历史记录同步。'
        };
      }
      const accountUid = this.resolveHistoryAccountUid(context.settings);
      if (accountUid.length <= 0) {
        return {
          type: 'configuration-required',
          title: context.activeProvider === 'self_hosted' ? '请先连接个人服务器' : '请先登录华为账号',
          message: '历史记录按当前选择的同步位置在设备之间保持一致。',
          remoteKind: context.activeProvider === 'self_hosted' ? 'self_hosted' : undefined
        };
      }
      if (context.activeProvider === 'aira_cloud') {
        const decision = await this.membershipFeature.canUse(AIRA_FEATURE_CLOUD_SYNC, {
          dataScope: 'profile_persistent',
          privacyMode: 'regular',
          loggedIn: true
        });
        if (!decision.allowed) {
          return {
            type: 'membership-required',
            title: decision.title.length > 0 ? decision.title : 'Aira 云同步需要 Aira Pro',
            message: decision.message,
            membershipDecision: decision
          };
        }
      }
      await this.experienceStateStore.setHistorySelected(true, accountUid);
      if (context.experienceState.suspended) {
        return {
          type: 'completed',
          title: '已选择历史记录',
          message: '重新开启同步后会自动继续。'
        };
      }
      const result = await this.automaticRuntime.runHistoryNow();
      if (!result.ok) {
        return {
          type: 'failed',
          title: '历史记录同步未完成',
          message: result.message
        };
      }
      this.automaticRuntime.notifyHistoryProviderChanged();
      return {
        type: 'completed',
        title: '历史记录同步已开启',
        message: result.message
      };
    } catch (error) {
      return this.failure('历史记录同步设置失败', this.normalizeError(error));
    }
  }

  private resolveHistoryProviderLabel(provider: AiraSyncRemoteKind): string {
    if (provider === 'huawei_space') {
      return '华为云空间';
    }
    if (provider === 'aira_cloud') {
      return 'Aira 云';
    }
    if (provider === 'self_hosted') {
      return '个人服务器';
    }
    return '云端';
  }

  async setPersonalizationItemSelected(
    id: PersonalizationSyncContentId,
    selected: boolean
  ): Promise<SyncExperienceActionOutcome> {
    let previousConfig: PersonalizationSyncConfig | undefined = undefined;
    let previousBookshelfSelection: NovelBookshelfSyncSelectionState | undefined = undefined;
    try {
      const context = await this.loadContext();
      previousConfig = await this.personalizationConfigStore.initialize();
      previousBookshelfSelection = await this.personalizationDomain.initializeNovelBookshelfSelection();
      const activeExperience = context.activeProvider !== 'none' && !context.experienceState.suspended;
      const domainEnabled = context.settings.personalizationSyncEnabled === true;
      const hadSelectedItems = activeExperience && !domainEnabled
        ? false
        : this.hasEnabledPersonalizationContent(previousConfig, previousBookshelfSelection.enabled);
      if (activeExperience && !domainEnabled && selected) {
        await this.clearRetainedPersonalizationSelections(
          previousConfig,
          previousBookshelfSelection.enabled,
          id
        );
      }
      const updateOutcome = await this.personalizationDomain.updateItemEnabled(id, selected);
      if (!updateOutcome.ok) {
        throw new Error(updateOutcome.message);
      }
      const hasSelectedItems = this.hasEnabledPersonalizationContent(
        updateOutcome.config,
        updateOutcome.novelBookshelfSelection.enabled
      );
      if (!activeExperience) {
        await this.experienceStateStore.setPersonalizationSelected(hasSelectedItems);
        return {
          type: 'completed',
          title: '同步内容已保存',
          message: context.experienceState.suspended
            ? '重新开启同步后会按当前选择恢复。'
            : '选择同步方式后会按当前选择同步。',
          personalizationConfig: updateOutcome.config
        };
      }
      if (!hadSelectedItems && hasSelectedItems) {
        const result = await this.enablePersonalizationDomain();
        if (!result.ok) {
          throw new Error(result.message);
        }
      } else if (hadSelectedItems && !hasSelectedItems) {
        await this.disablePersonalizationDomain();
      }
      await this.experienceStateStore.setPersonalizationSelected(hasSelectedItems);
      if (selected) {
        this.automaticRuntime.notifyPersonalizationLocalSettingsChanged();
      }
      return {
        type: 'completed',
        title: selected ? '同步内容已开启' : '同步内容已关闭',
        message: hasSelectedItems
          ? '已保存选择，并会自动保持一致。'
          : '主页收藏、小说书架和所有常用设置同步均已暂停，已有数据不会删除。',
        personalizationConfig: updateOutcome.config
      };
    } catch (_error) {
      let restored: boolean = true;
      if (previousConfig !== undefined && previousBookshelfSelection !== undefined) {
        await this.personalizationDomain.restoreContentSelection(
          previousConfig,
          previousBookshelfSelection.enabled
        ).catch((_restoreError: Error): void => {
          restored = false;
        });
      }
      if (!restored) {
        return {
          type: 'failed',
          title: '同步选择状态待确认',
          message: '同步内容没有完成更改，本机选择状态也未能完整恢复。请重新进入同步页面确认后再试。',
          personalizationConfig: this.personalizationConfigStore.getConfig()
        };
      }
      return this.personalizationContentFailure(
        selected ? '同步内容未开启' : '同步内容未关闭',
        this.personalizationConfigStore.getConfig()
      );
    }
  }

  async syncNow(): Promise<SyncExperienceActionOutcome> {
    try {
      await this.prepareHuaweiSpaceBookmarkUpgrade();
      const settings = this.syncService.getAiraSyncSettings();
      if (this.isHuaweiSpaceBookmarkUpgradeRequired(settings)) {
        return this.setBookmarkSelected(true);
      }
      return this.runEnabledDomains('sync');
    } catch (error) {
      return this.failure('立即同步失败', error as Error, undefined, undefined, 'sync');
    }
  }

  async backupNow(): Promise<SyncExperienceActionOutcome> {
    return this.runEnabledDomains('backup');
  }

  async loadAdditionalBackup(isPrivateSession: boolean = false): Promise<SyncAdditionalBackupViewState> {
    const settings = await this.syncConfigStore.initialize();
    const centerState = this.settingsCenterViewModel.buildState({
      settings: settings,
      hasCloudConfig: settings.huaweiCloud.uid.trim().length > 0,
      hasHuaweiSpaceConfig: settings.huaweiSpace.uid.trim().length > 0,
      hasWebdavConfig: settings.webdav.endpoint.trim().length > 0 && settings.webdav.username.trim().length > 0,
      huaweiSpaceReadiness: settings.huaweiSpace.uid.trim().length > 0 ? 'ready' : 'needs_account',
      isPrivateSession: isPrivateSession
    });
    return this.additionalBackupViewModel.buildState(settings, centerState.additionalBackupProviderCards);
  }

  async setAdditionalBackupEnabled(enabled: boolean): Promise<SyncAdditionalBackupActionOutcome> {
    try {
      const settings = await this.syncConfigStore.initialize();
      const backupKinds = settings.additionalBackupRemoteKinds ?? [];
      if (enabled && backupKinds.length <= 0) {
        return {
          type: 'blocked',
          title: '请先设置 WebDAV 备份',
          message: '额外备份只会覆盖写入你的 WebDAV，请先填写并开启后再试。',
          requiresOptions: true
        };
      }
      await this.syncConfigStore.setAdditionalBackupEnabled(enabled);
      return {
        type: 'completed',
        title: enabled ? '额外备份已开启' : '额外备份已暂停',
        message: enabled ? '后续会按设定频率更新额外副本。' : '备份位置和已有数据都已保留。'
      };
    } catch (error) {
      return this.additionalBackupFailure('额外备份设置失败', error as Error);
    }
  }

  async setAdditionalBackupIntervalDays(
    days: AiraAdditionalBackupIntervalDays
  ): Promise<SyncAdditionalBackupActionOutcome> {
    try {
      await this.syncConfigStore.setAdditionalBackupIntervalDays(days);
      const intervalLabel = days === 1 ? '每天一次' : `每 ${days} 天一次`;
      return {
        type: 'completed',
        title: '备份频率已更新',
        message: `额外备份将按${intervalLabel}执行。`
      };
    } catch (error) {
      return this.additionalBackupFailure('备份频率未更新', error as Error);
    }
  }

  async setAdditionalBackupProviderEnabled(
    remoteKind: AiraSyncProviderKind,
    enabled: boolean
  ): Promise<SyncExperienceProviderSelectionOutcome> {
    const outcome = await this.providerOperations.setAdditionalBackupEnabled(remoteKind, enabled);
    if (enabled && outcome.type === 'additional-backup-enabled') {
      await this.completeHuaweiSpaceBookmarkUpgradeIfNeeded(remoteKind);
    }
    if (outcome.type === 'additional-backup-disabled') {
      const settings = this.syncConfigStore.getSettings();
      if ((settings.additionalBackupRemoteKinds ?? []).length <= 0) {
        await this.syncConfigStore.setAdditionalBackupEnabled(false);
      }
    }
    return outcome;
  }

  async runAdditionalBackupNow(): Promise<SyncAdditionalBackupActionOutcome> {
    try {
      const settings = await this.syncConfigStore.initialize();
      const readiness = this.validateAdditionalBackupNow(settings);
      if (readiness !== undefined) {
        return readiness;
      }
      const outcome = await this.backupNow();
      return {
        type: outcome.type === 'completed' ? 'completed' : outcome.type === 'blocked' ? 'blocked' : 'failed',
        title: outcome.title,
        message: outcome.message
      };
    } catch (error) {
      return this.additionalBackupFailure('立即备份失败', error as Error);
    }
  }

  private async runEnabledDomains(mode: 'sync' | 'backup'): Promise<SyncExperienceActionOutcome> {
    try {
      const context = await this.loadContext();
      const isBackup = mode === 'backup';
      if (!isBackup && context.experienceState.suspended) {
        return {
          type: 'blocked',
          title: '同步已暂停',
          message: '重新开启同步后再试。'
        };
      }
      const messages: string[] = [];
      const issues: SyncExperienceDomainIssue[] = [];
      const runResult: SyncExperienceRuntimeRunResult = await this.automaticRuntime.runManual(mode);
      if (context.settings.bookmarkSyncEnabled === true && runResult.bookmark !== undefined) {
        const bookmarkOutcome = runResult.bookmark;
        if (bookmarkOutcome.type === 'failed' || bookmarkOutcome.type === 'blocked') {
          issues.push({
            domain: 'bookmark',
            type: bookmarkOutcome.type,
            message: bookmarkOutcome.message,
            failure: bookmarkOutcome.failure
          });
        } else {
          messages.push(isBackup ? '当前同步方式的书签已备份。' : '书签已完成。');
        }
      }
      if (context.settings.personalizationSyncEnabled === true && runResult.personalization !== undefined) {
        const personalizationOutcome = runResult.personalization;
        if (personalizationOutcome.type === 'failed') {
          issues.push({
            domain: 'personalization',
            type: 'failed',
            message: personalizationOutcome.message
          });
        } else {
          messages.push(isBackup ? '当前同步方式的主页收藏、小说书架和常用设置已备份。' : '主页收藏、小说书架和常用设置已完成。');
        }
      }
      if (!isBackup && context.experienceState.historySelected && runResult.history !== undefined) {
        if (!runResult.history.ok) {
          issues.push({
            domain: 'history',
            type: 'failed',
            message: runResult.history.message
          });
        } else {
          messages.push('历史记录已完成。');
        }
      }
      if (issues.length > 0) {
        const issueMessages = issues.map((issue: SyncExperienceDomainIssue): string => {
          return this.buildDomainIssueMessage(issue, isBackup, context.activeProvider);
        });
        return {
          type: issues.some((issue: SyncExperienceDomainIssue): boolean => issue.type === 'failed')
            ? 'failed'
            : 'blocked',
          title: isBackup ? '部分备份需要处理' : '部分内容需要处理',
          message: issueMessages.concat(messages).join(' '),
          remoteKind: context.activeProvider === 'none' ? undefined : context.activeProvider,
          retryAction: isBackup ? undefined : 'sync',
          requiresBookmarkResolution: issues.some((issue: SyncExperienceDomainIssue): boolean => {
            return issue.domain === 'bookmark' && issue.type === 'blocked';
          })
        };
      }
      if (isBackup) {
        const backupFailureMessages = this.resolveAdditionalBackupFailureMessages(
          this.syncConfigStore.getSettings()
        );
        if (backupFailureMessages.length > 0) {
          return {
            type: 'failed',
            title: '部分备份需要处理',
            message: backupFailureMessages.concat(messages).join(' '),
            remoteKind: context.activeProvider === 'none' ? undefined : context.activeProvider
          };
        }
      }
      return {
        type: 'completed',
        title: isBackup ? '备份完成' : '同步完成',
        message: messages.length > 0
          ? messages.join(' ')
          : isBackup ? '当前没有需要备份的内容。' : '当前没有需要同步的内容。'
      };
    } catch (error) {
      return this.failure(
        mode === 'backup' ? '立即备份失败' : '立即同步失败',
        error as Error,
        undefined,
        undefined,
        mode === 'backup' ? undefined : 'sync'
      );
    }
  }

  private buildDomainIssueMessage(
    issue: SyncExperienceDomainIssue,
    isBackup: boolean,
    activeProvider: AiraSyncRemoteKind
  ): string {
    if (issue.domain === 'bookmark') {
      return this.syncFailurePresentationService.buildBookmarkFailureMessage({
        remoteKind: activeProvider,
        operationName: isBackup ? '书签备份' : '书签同步',
        failure: issue.failure
      });
    }
    if (issue.domain === 'history') {
      return issue.message !== undefined && issue.message.length > 0
        ? `历史记录暂时没有完成同步：${issue.message}`
        : '历史记录暂时没有完成同步。';
    }
    const baseMessage = isBackup
      ? '主页收藏、小说书架和常用设置备份未完成。'
      : '主页收藏、小说书架和常用设置暂时没有完成同步。';
    if (activeProvider !== 'huawei_space') {
      return baseMessage;
    }
    const guidance = this.syncFailurePresentationService
      .buildHuaweiSpacePersonalizationSystemUpdateGuidance(issue.message ?? '');
    return guidance.length > 0 ? `${baseMessage}${guidance}` : baseMessage;
  }

  async resolveBookmarkConflicts(
    remoteKind: AiraSyncProviderKind,
    resolution: AiraBookmarkConflictResolution
  ): Promise<SyncExperienceActionOutcome> {
    try {
      let completesFirstActivation = false;
      const result = await this.automaticRuntime.runProviderTransition(
        async (): Promise<AiraBookmarkMergeSyncResult> => {
          const beforeResolution = this.syncService.getAiraSyncSettings();
          completesFirstActivation = beforeResolution.remoteKind === 'none' &&
            beforeResolution.bookmarkSyncEnabled !== true &&
            beforeResolution.personalizationSyncEnabled !== true;
          return this.syncService.resolveAiraBookmarkConflicts(remoteKind, resolution);
        }
      );
      if (result.blocked) {
        return {
          type: 'blocked',
          title: '书签仍需处理',
          message: result.summary,
          remoteKind: remoteKind,
          requiresBookmarkResolution: true
        };
      }
      await this.refreshBookmarkRemoteStatus(remoteKind);
      const settings = this.syncService.getAiraSyncSettings();
      if (settings.remoteKind !== remoteKind) {
        const selection = await this.providerOperations.selectProvider(remoteKind);
        const selectionFailure = this.mapProviderSelectionCompletionOutcome(selection);
        if (selectionFailure !== undefined) {
          return selectionFailure;
        }
      }
      const activationSelection = this.experienceStateStore.getState();
      const currentSettings = this.syncService.getAiraSyncSettings();
      if (currentSettings.remoteKind === remoteKind && currentSettings.bookmarkSyncEnabled !== true &&
        activationSelection.bookmarkSelected) {
        await this.syncService.setBookmarkSyncEnabled(true);
        this.automaticRuntime.scheduleBookmarkPeriodicSync();
      }
      await this.completeHuaweiSpaceBookmarkUpgradeIfNeeded(remoteKind);
      if (completesFirstActivation) {
        if (activationSelection.personalizationSelected) {
          const personalizationResult = await this.enablePersonalizationDomain();
          if (!personalizationResult.ok) {
            return this.firstActivationFailure(
              '同步未完全开启',
              personalizationResult.message,
              remoteKind
            );
          }
        }
        await this.experienceStateStore.setSelections(
          activationSelection.bookmarkSelected,
          activationSelection.personalizationSelected,
          false
        );
      }
      return {
        type: 'completed',
        title: '书签冲突已处理',
        message: result.summary.length > 0 ? result.summary : '书签已按你的选择完成同步。',
        remoteKind: remoteKind
      };
    } catch (error) {
      const bookmarkFailure = this.syncService.resolveBookmarkSyncFailure(error as Error);
      return this.failure(
        '书签冲突处理失败',
        new Error(this.syncFailurePresentationService.buildBookmarkFailureMessage({
          remoteKind: remoteKind,
          operationName: '处理书签冲突',
          failure: bookmarkFailure
        })),
        remoteKind,
        bookmarkFailure
      );
    }
  }

  private async activateFirstSelection(
    remoteKind: AiraSyncProviderKind,
    selection: SyncExperiencePersistedState
  ): Promise<SyncExperienceActionOutcome> {
    try {
      const providerSelection = await this.providerOperations.selectProvider(remoteKind, {
        bookmarks: false,
        personalization: false,
        history: false
      });
      const providerSelectionFailure = this.mapProviderSelectionCompletionOutcome(providerSelection);
      if (providerSelectionFailure !== undefined) {
        return providerSelectionFailure;
      }
      const failures: string[] = [];
      let bookmarkBlockedOutcome: SyncExperienceProviderOutcome | undefined = undefined;
      let completedDomainCount = 0;
      if (selection.bookmarkSelected) {
        const bookmarkOutcome = await this.providerOperations.setBookmarkDomainEnabled(true);
        if (bookmarkOutcome.type === 'bookmark-domain-enabled') {
          completedDomainCount += 1;
        } else if (bookmarkOutcome.type === 'bookmark-domain-blocked') {
          bookmarkBlockedOutcome = bookmarkOutcome;
        } else {
          failures.push(this.buildProviderBookmarkFailureMessage(bookmarkOutcome, '开启书签同步'));
        }
      }
      if (selection.personalizationSelected) {
        const personalizationResult = await this.enablePersonalizationDomain();
        if (personalizationResult.ok) {
          completedDomainCount += 1;
        } else {
          failures.push(`主页收藏、小说书架和常用设置：${personalizationResult.message}`);
        }
      }
      if (selection.historySelected && remoteKind !== 'webdav') {
        const historyOutcome = await this.setHistorySelected(true);
        if (historyOutcome.type === 'completed') {
          completedDomainCount += 1;
        } else {
          failures.push(`历史记录：${historyOutcome.message}`);
        }
      }
      if (selection.bookmarkSelected) {
        if (!this.isHuaweiBookmarkInitializationPending(this.syncService.getAiraSyncSettings())) {
          await this.refreshBookmarkRemoteStatus(remoteKind);
        }
      }
      const historySelected = remoteKind !== 'webdav' && selection.historySelected;
      await this.experienceStateStore.setSelections(
        selection.bookmarkSelected,
        selection.personalizationSelected,
        false,
        historySelected
      );
      if (bookmarkBlockedOutcome !== undefined) {
        const successMessage = completedDomainCount > 0
          ? '其他已成功开启的内容会继续自动同步。'
          : '';
        return {
          type: 'blocked',
          title: '书签需要处理',
          message: [bookmarkBlockedOutcome.message, successMessage].filter((value: string): boolean => {
            return value.length > 0;
          }).join('\n'),
          remoteKind: remoteKind,
          requiresBookmarkResolution: true
        };
      }
      if (failures.length > 0) {
        return {
          type: 'failed',
          title: '同步未完全开启',
          message: completedDomainCount > 0
            ? `${failures.join('；')}。已成功开启的内容会继续自动同步，可单独重试其余内容。`
            : failures.join('；'),
          remoteKind: remoteKind
        };
      }
      return {
        type: 'completed',
        title: '同步已开启',
        message: this.buildFirstActivationSuccessMessage(selection, remoteKind),
        remoteKind: remoteKind
      };
    } catch (error) {
      return this.firstActivationFailure(
        '同步未完全开启',
        this.normalizeError(error).message,
        remoteKind
      );
    }
  }

  private async runHuaweiSpaceBookmarkUpgradePreparation(): Promise<void> {
    const startedAt = Date.now();
    AiraSyncJankProbe.mark('upgrade_prep_start');
    const settings = await this.syncService.initializeAiraSyncSettings();
    const huaweiBookmarkSelected = settings.remoteKind === 'huawei_space';
    const affectedLegacySelection = huaweiBookmarkSelected && settings.bookmarkSyncEnabled === true &&
      settings.huaweiSpace.uid.trim().length > 0;
    const upgradeState = await this.huaweiSpaceBookmarkUpgradeStore.prepareCurrentVersion(
      affectedLegacySelection
    );
    if (upgradeState.requiredVersion <= 0) {
      AiraSyncJankProbe.end('upgrade_prep', startedAt);
      return;
    }
    await this.automaticRuntime.runProviderTransition(async (): Promise<void> => {
      await this.syncConfigStore.prepareHuaweiSpaceBookmarkReenable();
      if (settings.remoteKind === 'huawei_space') {
        this.automaticRuntime.cancelBookmarkAutomaticSync();
      }
    });
    AiraSyncJankProbe.endExtra('upgrade_prep', startedAt, 'reenable');
  }

  private runAfterHuaweiSpaceBookmarkUpgradePreparation(action: () => void): void {
    void this.prepareHuaweiSpaceBookmarkUpgrade()
      .then((): void => {
        action();
      })
      .catch((_error: Error): void => {
        action();
      });
  }

  private isHuaweiSpaceBookmarkUpgradeRequired(settings: AiraSyncSettings): boolean {
    return settings.remoteKind === 'huawei_space' &&
      this.huaweiSpaceBookmarkUpgradeStore.isCurrentVersionRequired();
  }

  private async completeHuaweiSpaceBookmarkUpgradeIfNeeded(remoteKind: AiraSyncRemoteKind): Promise<void> {
    if (remoteKind !== 'huawei_space' ||
      !this.huaweiSpaceBookmarkUpgradeStore.isCurrentVersionRequired()) {
      return;
    }
    const settings = this.syncService.getAiraSyncSettings();
    const activeHuaweiBookmark = settings.remoteKind === 'huawei_space' &&
      settings.bookmarkSyncEnabled === true;
    if (!activeHuaweiBookmark) {
      return;
    }
    const bookmarkRuntime = resolveAiraSyncDomainRuntimeState(settings, 'huawei_space', 'bookmark');
    if ((settings.pendingBookmarkSyncAt ?? 0) > 0 || bookmarkRuntime.lastSuccessAt <= 0 || bookmarkRuntime.blocked) {
      return;
    }
    await this.huaweiSpaceBookmarkUpgradeStore.markCompleted();
  }

  private isHuaweiBookmarkInitializationPending(settings: AiraSyncSettings): boolean {
    if (settings.remoteKind !== 'huawei_space' || settings.bookmarkSyncEnabled !== true ||
      (settings.pendingBookmarkSyncAt ?? 0) <= 0) {
      return false;
    }
    return resolveAiraSyncDomainRuntimeState(settings, 'huawei_space', 'bookmark').lastSuccessAt <= 0;
  }

  private async persistFirstActivationItems(state: SyncFirstActivationItemsState): Promise<void> {
    await this.personalizationConfigStore.initialize();
    const bookmarkSelected = state.items.some((item: SyncFirstActivationItemState): boolean => {
      return item.id === 'bookmarks' && item.enabled;
    });
    const historySelected = state.items.some((item: SyncFirstActivationItemState): boolean => {
      return item.id === 'history' && item.enabled;
    });
    let personalizationSelected = false;
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id: PersonalizationSyncItemId = PERSONALIZATION_SYNC_ITEM_IDS[index];
      const item = state.items.find((value: SyncFirstActivationItemState): boolean => value.id === id);
      const enabled = item?.enabled !== false;
      personalizationSelected = personalizationSelected || enabled;
      await this.personalizationConfigStore.setItemEnabled(id, enabled, enabled ? 0 : Date.now());
    }
    const bookshelfItem = state.items.find((value: SyncFirstActivationItemState): boolean => {
      return value.id === 'novel_bookshelf';
    });
    const bookshelfEnabled = bookshelfItem?.enabled !== false;
    const bookshelfOutcome = await this.personalizationDomain.updateItemEnabled(
      'novel_bookshelf',
      bookshelfEnabled
    );
    if (!bookshelfOutcome.ok) {
      throw new Error(bookshelfOutcome.message);
    }
    personalizationSelected = personalizationSelected || bookshelfEnabled;
    await this.experienceStateStore.setSelections(
      bookmarkSelected,
      personalizationSelected,
      false,
      historySelected
    );
  }

  private async refreshBookmarkRemoteStatus(remoteKind: AiraSyncProviderKind): Promise<void> {
    await this.bookmarkDomain.refreshRemoteStatus(remoteKind).catch((_error: Error): void => {
    });
  }

  private buildFirstActivationSuccessMessage(
    selection: SyncExperiencePersistedState,
    remoteKind: AiraSyncProviderKind
  ): string {
    if (selection.historySelected && remoteKind !== 'webdav') {
      return '历史记录和已选择的其他内容会自动在设备之间保持一致。';
    }
    if (selection.bookmarkSelected && selection.personalizationSelected) {
      return '书签、主页收藏、小说书架和已选择的常用设置会自动保持一致。';
    }
    return selection.bookmarkSelected
      ? '书签会自动在所选范围内保持一致。'
      : '主页收藏、小说书架和已选择的常用设置会自动在所选范围内保持一致。';
  }

  private firstActivationFailure(
    title: string,
    message: string,
    remoteKind: AiraSyncProviderKind
  ): SyncExperienceActionOutcome {
    return {
      type: 'failed',
      title: title,
      message: message,
      remoteKind: remoteKind
    };
  }

  private async loadContext(): Promise<SyncExperienceContext> {
    const settings = await this.syncService.initializeAiraSyncSettings();
    const activeProvider = settings.remoteKind;
    const experienceState = await this.reconcileHistoryAccountBinding(settings);
    return {
      settings: settings,
      activeProvider: activeProvider,
      experienceState: experienceState
    };
  }

  private async clearHistorySelectionForWebdav(
    activeProvider: AiraSyncRemoteKind,
    state: SyncExperiencePersistedState
  ): Promise<SyncExperiencePersistedState> {
    if (activeProvider !== 'webdav' || !state.historySelected) {
      return state;
    }
    await this.automaticRuntime.clearHistorySelectionForWebdav();
    return this.experienceStateStore.getState();
  }

  private resolveHistoryAccountUid(settings: AiraSyncSettings): string {
    if (settings.remoteKind === 'self_hosted') {
      return resolveAiraPersonalServerConfig(settings).instanceId.trim();
    }
    return resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid.trim();
  }

  private async enablePersonalizationDomain(): Promise<PersonalizationSyncRunResult> {
    return this.automaticRuntime.runProviderTransition(async (): Promise<PersonalizationSyncRunResult> => {
      const result = await this.personalizationDomain.enableDomain();
      if (result.ok) {
        this.automaticRuntime.notifyPersonalizationLocalSettingsChanged();
      }
      return result;
    });
  }

  private async disablePersonalizationDomain(): Promise<void> {
    await this.automaticRuntime.runProviderTransition(async (): Promise<void> => {
      await this.personalizationDomain.disableDomain();
      this.automaticRuntime.cancelPersonalizationAutomaticSync();
    });
  }

  private async suspendExperience(
    settings: AiraSyncSettings,
    previousState: SyncExperiencePersistedState
  ): Promise<SyncExperienceActionOutcome> {
    const bookmarkSelected = settings.bookmarkSyncEnabled === true ? true : previousState.bookmarkSelected;
    const personalizationSelected = settings.personalizationSyncEnabled === true
      ? true
      : previousState.personalizationSelected;
    const historySelected = previousState.historySelected;
    await this.experienceStateStore.setSelections(
      bookmarkSelected,
      personalizationSelected,
      previousState.suspended,
      historySelected
    );
    const failures: string[] = [];
    if (settings.personalizationSyncEnabled === true) {
      try {
        await this.disablePersonalizationDomain();
      } catch (error) {
        failures.push(`主页收藏、小说书架和常用设置暂停失败：${this.normalizeError(error as Error).message}`);
      }
    }
    if (settings.bookmarkSyncEnabled === true) {
      try {
        const outcome = await this.providerOperations.setBookmarkDomainEnabled(false);
        if (outcome.type !== 'bookmark-domain-disabled') {
          failures.push(`书签暂停失败：${outcome.message}`);
        }
      } catch (error) {
        failures.push(`书签暂停失败：${this.normalizeError(error as Error).message}`);
      }
    }
    this.automaticRuntime.cancelHistoryAutomaticSync();
    if (failures.length > 0) {
      await this.experienceStateStore.setSelections(
        bookmarkSelected,
        personalizationSelected,
        false,
        historySelected
      );
      return {
        type: 'failed',
        title: '同步未完全暂停',
        message: `${failures.join('；')}。已暂停的内容保持暂停，未完成的内容不会影响另一项。`
      };
    }
    await this.experienceStateStore.suspend(bookmarkSelected, personalizationSelected, historySelected);
    return {
      type: 'completed',
      title: '同步已暂停',
      message: '本机和云端数据、账号及同步方式都已保留。'
    };
  }

  private async resumeExperience(
    experienceState: SyncExperiencePersistedState
  ): Promise<SyncExperienceActionOutcome> {
    let current = this.syncService.getAiraSyncSettings();
    const historySelected = experienceState.historySelected &&
      (current.remoteKind === 'aira_cloud' || current.remoteKind === 'huawei_space' ||
        current.remoteKind === 'self_hosted');
    if (!experienceState.bookmarkSelected && !experienceState.personalizationSelected &&
      !historySelected) {
      return {
        type: 'blocked',
        title: '请选择同步内容',
        message: '请在下方开启书签、历史记录、主页收藏、小说书架或一项常用设置。'
      };
    }
    const failures: string[] = [];
    let resumedDomainCount: number = 0;
    if (experienceState.bookmarkSelected && current.remoteKind !== 'none') {
      if (current.bookmarkSyncEnabled === true) {
        resumedDomainCount += 1;
      } else {
        try {
          const outcome = await this.providerOperations.setBookmarkDomainEnabled(true);
          if (outcome.type !== 'bookmark-domain-enabled') {
            failures.push(this.buildProviderBookmarkFailureMessage(outcome, '恢复书签同步'));
          } else {
            resumedDomainCount += 1;
          }
        } catch (error) {
          failures.push(this.syncFailurePresentationService.buildBookmarkFailureMessage({
            remoteKind: current.remoteKind,
            operationName: '恢复书签同步',
            failure: this.syncService.resolveBookmarkSyncFailure(error as Error)
          }));
        }
      }
    }
    current = this.syncService.getAiraSyncSettings();
    if (experienceState.personalizationSelected && current.remoteKind !== 'none') {
      if (current.personalizationSyncEnabled === true) {
        resumedDomainCount += 1;
      } else {
        try {
          const result = await this.enablePersonalizationDomain();
          if (!result.ok) {
            failures.push(`主页收藏、小说书架和常用设置恢复失败：${result.message}`);
          } else {
            resumedDomainCount += 1;
          }
        } catch (error) {
          failures.push(`主页收藏、小说书架和常用设置恢复失败：${this.normalizeError(error as Error).message}`);
        }
      }
    }
    if (historySelected) {
      try {
        const historyOutcome = await this.setHistorySelected(true);
        if (historyOutcome.type === 'completed') {
          resumedDomainCount += 1;
        } else {
          failures.push(`历史记录恢复失败：${historyOutcome.message}`);
        }
      } catch (error) {
        failures.push(`历史记录恢复失败：${this.normalizeError(error as Error).message}`);
      }
    }
    if (resumedDomainCount > 0) {
      await this.experienceStateStore.resume();
      await this.automaticRuntime.notifyAccountChanged();
    }
    if (failures.length > 0) {
      return {
        type: 'failed',
        title: '同步未完全恢复',
        message: resumedDomainCount > 0
          ? `${failures.join('；')}。已恢复的内容会继续同步，另一项可单独重试。`
          : `${failures.join('；')}。当前仍保持暂停，可稍后重试。`
      };
    }
    return {
      type: 'completed',
      title: '同步已恢复',
      message: '已按暂停前的内容选择继续同步。'
    };
  }

  private mapProviderSelectionRequestOutcome(outcome: SyncExperienceProviderOutcome): SyncExperienceActionOutcome | undefined {
    if (outcome.type === 'configuration-required') {
      return {
        type: 'configuration-required',
        title: outcome.title,
        message: outcome.message,
        remoteKind: outcome.remoteKind
      };
    }
    if (outcome.type === 'membership-required') {
      return {
        type: 'membership-required',
        title: outcome.title,
        message: outcome.message,
        remoteKind: outcome.remoteKind,
        membershipDecision: outcome.membershipDecision
      };
    }
    if (outcome.type === 'provider-selection-blocked') {
      return {
        type: 'blocked',
        title: outcome.title,
        message: outcome.message,
        remoteKind: outcome.remoteKind,
        requiresBookmarkResolution: this.requiresBookmarkResolution(outcome)
      };
    }
    if (outcome.type === 'failed') {
      if (outcome.bookmarkFailure !== undefined) {
        return {
          type: 'failed',
          title: outcome.title,
          message: this.buildProviderBookmarkFailureMessage(outcome, '书签同步'),
          remoteKind: outcome.remoteKind
        };
      }
      return this.failure(outcome.title, new Error(outcome.message), outcome.remoteKind);
    }
    return undefined;
  }

  private mapProviderSelectionCompletionOutcome(outcome: SyncExperienceProviderOutcome): SyncExperienceActionOutcome | undefined {
    if (outcome.type === 'provider-selected') {
      return undefined;
    }
    return this.mapProviderSelectionRequestOutcome(outcome) ?? this.mapProviderSelectionFailure(outcome);
  }

  private mapProviderSelectionFailure(outcome: SyncExperienceProviderOutcome): SyncExperienceActionOutcome {
    if (outcome.type === 'membership-required') {
      return {
        type: 'membership-required',
        title: outcome.title,
        message: outcome.message,
        remoteKind: outcome.remoteKind,
        membershipDecision: outcome.membershipDecision
      };
    }
    if (outcome.type === 'bookmark-domain-blocked' || outcome.type === 'provider-selection-blocked') {
      return {
        type: 'blocked',
        title: outcome.title,
        message: outcome.message,
        remoteKind: outcome.remoteKind,
        requiresBookmarkResolution: this.requiresBookmarkResolution(outcome)
      };
    }
    if (outcome.bookmarkFailure !== undefined) {
      return {
        type: 'failed',
        title: outcome.title,
        message: this.buildProviderBookmarkFailureMessage(outcome, '书签同步'),
        remoteKind: outcome.remoteKind
      };
    }
    return this.failure(outcome.title, new Error(outcome.message), outcome.remoteKind);
  }

  private buildProviderBookmarkFailureMessage(
    outcome: SyncExperienceProviderOutcome,
    operationName: string
  ): string {
    if (outcome.bookmarkFailure === undefined) {
      return outcome.message;
    }
    return this.syncFailurePresentationService.buildBookmarkFailureMessage({
      remoteKind: outcome.remoteKind,
      operationName: operationName,
      failure: outcome.bookmarkFailure
    });
  }

  private hasEnabledPersonalizationContent(
    config: PersonalizationSyncConfig,
    novelBookshelfEnabled: boolean
  ): boolean {
    return novelBookshelfEnabled || config.items.some((item): boolean => item.enabled);
  }

  private async clearRetainedPersonalizationSelections(
    config: PersonalizationSyncConfig,
    novelBookshelfEnabled: boolean,
    selectedId: PersonalizationSyncContentId
  ): Promise<void> {
    for (let index = 0; index < config.items.length; index += 1) {
      const item = config.items[index];
      if (item.id === selectedId || !item.enabled) {
        continue;
      }
      const outcome = await this.personalizationDomain.updateItemEnabled(item.id, false);
      if (!outcome.ok) {
        throw new Error(outcome.message);
      }
    }
    if (selectedId !== 'novel_bookshelf' && novelBookshelfEnabled) {
      const outcome = await this.personalizationDomain.updateItemEnabled('novel_bookshelf', false);
      if (!outcome.ok) {
        throw new Error(outcome.message);
      }
    }
  }

  private personalizationContentFailure(
    title: string,
    config: PersonalizationSyncConfig
  ): SyncExperienceActionOutcome {
    return {
      type: 'failed',
      title: title,
      message: '这项常用设置暂时没有更改，本机和云端已有数据都已保留。请稍后再试。',
      personalizationConfig: config
    };
  }

  private buildAdvancedState(
    settings: AiraSyncSettings,
    overview: SyncAdvancedStatusOverview | undefined,
    isPrivateSession: boolean
  ): SyncExperienceAdvancedState {
    const enabledKinds = this.advancedViewModel.resolveEnabledRemoteKinds(settings);
    const activeRemoteKind = settings.remoteKind;
    const status = isPrivateSession
      ? this.advancedViewModel.buildPrivateStatus()
      : this.advancedViewModel.buildStatus(
        settings,
        overview?.baselines ?? [],
        (remoteKind: AiraSyncRemoteKind): string => this.syncService.resolveAiraProviderIdForKind(remoteKind),
        overview?.localCounts
      );
    return {
      status: status,
      providerActions: this.advancedViewModel.buildProviderActions(settings),
      mergeActionLabel: this.advancedViewModel.resolveMergeActionLabel(),
      activeRemoteKind: activeRemoteKind,
      activeSyncServiceKey: this.advancedViewModel.resolveActiveSyncServiceKey(settings, activeRemoteKind),
      activeSyncServiceName: this.advancedViewModel.resolveActiveSyncServiceName(settings, activeRemoteKind),
      activeSyncReady: enabledKinds.length > 0,
      activeSyncMissingConfigurationMessage: this.resolveAdvancedMissingConfigurationMessage(
        settings,
        activeRemoteKind
      ),
      providerReadiness: [
        this.buildAdvancedProviderReadiness(settings, 'aira_cloud'),
        this.buildAdvancedProviderReadiness(settings, 'huawei_space'),
        this.buildAdvancedProviderReadiness(settings, 'webdav')
      ]
    };
  }

  private buildAdvancedProviderReadiness(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncProviderKind
  ): SyncExperienceAdvancedProviderReadiness {
    return {
      remoteKind: remoteKind,
      ready: this.advancedViewModel.isProviderSyncReady(settings, remoteKind),
      missingConfigurationMessage: this.resolveAdvancedMissingConfigurationMessage(settings, remoteKind)
    };
  }

  private resolveAdvancedMissingConfigurationMessage(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncRemoteKind
  ): string {
    if (remoteKind === 'aira_cloud') {
      return '请先回到同步设置启用 Aira 云同步。';
    }
    if (remoteKind === 'huawei_space') {
      return '请先回到同步设置启用华为云空间同步。';
    }
    if (remoteKind === 'webdav') {
      return settings.webdav.endpoint.trim().length > 0 && settings.webdav.username.trim().length > 0
        ? '请启用已保存的 WebDAV 配置。'
        : '请先填写 WebDAV 服务器和账号。';
    }
    return '请先开启华为云空间同步、Aira 云同步或 WebDAV。';
  }

  private buildWebdavConfigurationState(
    settings: AiraSyncSettings
  ): SyncExperienceWebdavConfigurationState {
    let providerRole: SyncWebdavProviderRole = 'inactive';
    if (settings.remoteKind === 'webdav') {
      providerRole = 'active';
    } else if ((settings.additionalBackupRemoteKinds ?? []).indexOf('webdav') >= 0) {
      providerRole = 'additional_backup';
    }
    return {
      endpoint: settings.webdav.endpoint,
      username: settings.webdav.username,
      password: settings.webdav.password,
      providerRole: providerRole,
      bookmarkDomainEnabled: providerRole === 'active' && settings.bookmarkSyncEnabled === true
    };
  }

  private validateAdditionalBackupNow(
    settings: AiraSyncSettings
  ): SyncAdditionalBackupActionOutcome | undefined {
    if (settings.additionalBackupEnabled !== true) {
      return {
        type: 'blocked',
        title: '额外备份未开启',
        message: '请先开启额外备份。'
      };
    }
    if ((settings.additionalBackupRemoteKinds ?? []).length <= 0) {
      return {
        type: 'blocked',
        title: '请先设置 WebDAV 备份',
        message: '额外备份只会覆盖写入你的 WebDAV，请先填写并开启后再试。',
        requiresOptions: true
      };
    }
    if (settings.bookmarkSyncEnabled !== true && settings.personalizationSyncEnabled !== true) {
      return {
        type: 'blocked',
        title: '没有可备份的内容',
        message: '请先在同步主页开启书签、主页收藏、小说书架或常用设置。'
      };
    }
    return undefined;
  }

  private resolveAdditionalBackupFailureMessages(settings: AiraSyncSettings): string[] {
    if (settings.additionalBackupEnabled !== true) {
      return [];
    }
    const messages: string[] = [];
    const backupKinds = settings.additionalBackupRemoteKinds ?? [];
    for (let index = 0; index < backupKinds.length; index += 1) {
      const remoteKind = backupKinds[index];
      const providerLabel = this.providerOperations.resolveProviderLabel(remoteKind);
      if (settings.bookmarkSyncEnabled === true && this.isAdditionalBackupDomainUnhealthy(
        resolveAiraSyncDomainRuntimeState(settings, remoteKind, 'bookmark_backup')
      )) {
        const runtime = resolveAiraSyncDomainRuntimeState(settings, remoteKind, 'bookmark_backup');
        messages.push(this.syncFailurePresentationService.buildBookmarkFailureMessage({
          remoteKind: remoteKind,
          operationName: `${providerLabel}额外书签副本`,
          failure: this.resolveRuntimeBookmarkFailure(runtime)
        }));
      }
      if (settings.personalizationSyncEnabled === true && this.isAdditionalBackupDomainUnhealthy(
        resolveAiraSyncDomainRuntimeState(settings, remoteKind, 'personalization_backup')
      )) {
        messages.push(`${providerLabel}的主页收藏、小说书架和常用设置额外副本未完成。`);
      }
    }
    return messages;
  }

  private isAdditionalBackupDomainUnhealthy(state: AiraSyncDomainRuntimeState): boolean {
    return state.health === 'degraded' || state.health === 'unavailable';
  }

  private resolveRuntimeBookmarkFailure(state: AiraSyncDomainRuntimeState): AiraBookmarkSyncFailure | undefined {
    if (state.failureCode.length <= 0 || state.failureStage === '' || state.failureDetail.length <= 0) {
      return undefined;
    }
    return {
      code: state.failureCode,
      stage: state.failureStage,
      safeDetail: state.failureDetail
    };
  }

  private additionalBackupFailure(title: string, error: Error): SyncAdditionalBackupActionOutcome {
    return {
      type: 'failed',
      title: title,
      message: error.message.length > 0
        ? '请稍后再试；如果问题持续，请返回同步页面重新读取状态。'
        : '当前操作未完成，请稍后再试。'
    };
  }

  private failure(
    title: string,
    error: Error,
    remoteKind?: AiraSyncProviderKind,
    bookmarkFailure?: AiraBookmarkSyncFailure,
    retryAction?: SyncExperienceRetryAction
  ): SyncExperienceActionOutcome {
    return {
      type: 'failed',
      title: title,
      message: error.message.length > 0 ? error.message : JSON.stringify(error),
      remoteKind: remoteKind,
      bookmarkFailure: bookmarkFailure,
      retryAction: retryAction
    };
  }

  private normalizeError(error: Object): Error {
    if (error instanceof Error) {
      return error;
    }
    return new Error(JSON.stringify(error));
  }

  private requiresBookmarkResolution(outcome: SyncExperienceProviderOutcome): boolean {
    return outcome.bookmarkResult !== undefined &&
      (outcome.bookmarkResult.blocked || outcome.bookmarkResult.conflictCount > 0);
  }
}

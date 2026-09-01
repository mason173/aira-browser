import {
  AiraSyncProviderKind,
  AiraBookmarkSyncFailure,
  AiraSyncDomainRuntimeState,
  AiraSyncProviderRuntimeState,
  AiraSyncRemoteKind,
  AiraSyncSettings,
  resolveAiraSyncActiveProviderLastSuccessAt
} from '../../common/models/AiraSyncModels';
import { PersonalizationSyncConfig } from '../../common/models/PersonalizationSyncModels';
import { SyncExperiencePersistedState } from '../../data/sync/SyncExperienceStateStore';
import {
  PersonalizationSyncItemState,
  PersonalizationSyncSettingsViewModel
} from './PersonalizationSyncSettingsViewModel';
import { WebdavProviderCatalog } from './WebdavProviderCatalog';
import { SyncFailurePresentationService } from './SyncFailurePresentationService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export type SyncExperienceStatusKind = 'setup' | 'normal' | 'initializing' | 'syncing' | 'attention' | 'paused';
export type SyncExperiencePreActiveStatusKind =
  'initial-loading' | 'huawei-activating' | 'load-failed' | 'huawei-load-failed' | 'inactive';

interface SyncExperienceGoalDescriptor {
  id: AiraSyncProviderKind;
  title: string;
  description: string;
  requiresPro: boolean;
}

const SYNC_EXPERIENCE_GOALS: SyncExperienceGoalDescriptor[] = [
  {
    id: 'aira_cloud',
    title: '手机与电脑之间',
    description: '通过浏览器插件在手机、Windows 和 Mac 之间跨系统同步。',
    requiresPro: true
  },
  {
    id: 'huawei_space',
    title: '华为云空间',
    description: '使用你自己的华为云空间，在华为设备上的 Aira 之间同步书签、历史记录、主页收藏、小说书架和常用设置；数据不经过 Aira 云服务器。',
    requiresPro: false
  },
  {
    id: 'webdav',
    title: '使用自己的服务器',
    description: '连接你自己的 WebDAV 服务，保存并同步书签、主页收藏、小说书架和常用设置。',
    requiresPro: false
  },
  {
    id: 'self_hosted',
    title: '个人服务器',
    description: '连接你部署的 Aira 个人服务器，在自己的设备之间同步书签、历史记录、主页收藏、小说书架和常用设置。',
    requiresPro: false
  }
];

function resolveDistributionSyncExperienceGoals(): SyncExperienceGoalDescriptor[] {
  if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
    return SYNC_EXPERIENCE_GOALS;
  }
  const goals: SyncExperienceGoalDescriptor[] = [];
  SYNC_EXPERIENCE_GOALS.forEach((goal: SyncExperienceGoalDescriptor): void => {
    if (goal.id === 'self_hosted') {
      goals.push(goal);
    }
  });
  SYNC_EXPERIENCE_GOALS.forEach((goal: SyncExperienceGoalDescriptor): void => {
    if (goal.id === 'webdav') {
      goals.push(goal);
    }
  });
  return goals;
}

function resolveDistributionGoalTitle(goal: SyncExperienceGoalDescriptor): string {
  if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()) {
    if (goal.id === 'self_hosted') {
      return '使用自己的服务器';
    }
    if (goal.id === 'webdav') {
      return 'WebDAV';
    }
  }
  return goal.title;
}

export interface SyncExperienceGoalOption {
  id: AiraSyncProviderKind;
  title: string;
  description: string;
  isSelected: boolean;
  requiresPro: boolean;
}

export interface SyncExperienceViewState {
  hasActiveProvider: boolean;
  hasConfiguredSync: boolean;
  masterEnabled: boolean;
  suspended: boolean;
  bookmarkSelected: boolean;
  personalizationSelected: boolean;
  historySelected: boolean;
  historySupported: boolean;
  historyProviderLabel: string;
  statusKind: SyncExperienceStatusKind;
  statusTitle: string;
  statusMessage: string;
  goalLabel: string;
  lastSyncLabel: string;
  enabledPersonalizationItemCount: number;
  canSyncNow: boolean;
  requiresAiraProAction: boolean;
  additionalBackupSummary: string;
  huaweiSpaceBookmarkUpgradeRequired: boolean;
  airaCloudActive: boolean;
  huaweiSpaceActive: boolean;
  huaweiBookmarkInitializing: boolean;
  goalOptions: SyncExperienceGoalOption[];
  personalizationItems: PersonalizationSyncItemState[];
}

export interface SyncExperienceViewModelInput {
  settings: AiraSyncSettings;
  experienceState: SyncExperiencePersistedState;
  personalizationConfig: PersonalizationSyncConfig;
  novelBookshelfSyncEnabled: boolean;
  airaCloudEligible: boolean;
  isSyncing: boolean;
  huaweiSpaceBookmarkUpgradeRequired: boolean;
}

interface SyncExperienceContentSelection {
  bookmarkSelected: boolean;
  personalizationSelected: boolean;
  historySelected: boolean;
}

export function createDefaultSyncExperienceViewState(): SyncExperienceViewState {
  const personalizationItems = new PersonalizationSyncSettingsViewModel().buildDefaultState().items;
  return {
    hasActiveProvider: false,
    hasConfiguredSync: false,
    masterEnabled: false,
    suspended: false,
    bookmarkSelected: true,
    personalizationSelected: true,
    historySelected: true,
    historySupported: true,
    historyProviderLabel: AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') ? 'Aira 云' : '尚未选择',
    statusKind: 'setup',
    statusTitle: '同步尚未开启',
    statusMessage: '先选择同步内容，再选择希望数据出现在哪些设备上。',
    goalLabel: '尚未选择',
    lastSyncLabel: '尚未完成同步',
    enabledPersonalizationItemCount: personalizationItems.filter(
      (item: PersonalizationSyncItemState): boolean => item.enabled
    ).length,
    canSyncNow: false,
    requiresAiraProAction: false,
    additionalBackupSummary: '未设置',
    huaweiSpaceBookmarkUpgradeRequired: false,
    airaCloudActive: false,
    huaweiSpaceActive: false,
    huaweiBookmarkInitializing: false,
    goalOptions: resolveDistributionSyncExperienceGoals().filter((goal: SyncExperienceGoalDescriptor): boolean => {
      return goal.id !== 'aira_cloud' || AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud');
    }).map((goal: SyncExperienceGoalDescriptor): SyncExperienceGoalOption => {
      return {
        id: goal.id,
        title: resolveDistributionGoalTitle(goal),
        description: goal.description,
        isSelected: false,
        requiresPro: goal.requiresPro
      };
    }),
    personalizationItems: personalizationItems
  };
}

export class SyncExperienceViewModel {
  private syncFailurePresentationService: SyncFailurePresentationService = new SyncFailurePresentationService();
  private personalizationViewModel: PersonalizationSyncSettingsViewModel = new PersonalizationSyncSettingsViewModel();
  private webdavProviderCatalog: WebdavProviderCatalog = new WebdavProviderCatalog();

  buildState(input: SyncExperienceViewModelInput): SyncExperienceViewState {
    const activeProvider = this.resolveAvailableProvider(input.settings.remoteKind);
    const hasActiveProvider = this.isProviderKind(activeProvider);
    const personalizationItems = this.buildPersonalizationItems(input, hasActiveProvider);
    const enabledPersonalizationItemCount = personalizationItems.filter(
      (item: PersonalizationSyncItemState): boolean => item.enabled
    ).length;
    const contentSelection = this.resolveContentSelection(input, hasActiveProvider);
    const hasEnabledContent = contentSelection.bookmarkSelected || contentSelection.personalizationSelected ||
      contentSelection.historySelected;
    const hasConfiguredSync = hasActiveProvider;
    const masterEnabled = hasConfiguredSync && !input.experienceState.suspended;
    const huaweiBookmarkInitializing = this.isHuaweiBookmarkInitializing(input.settings);
    const statusKind = this.resolveStatusKind(input, activeProvider, hasConfiguredSync, hasEnabledContent);
    return {
      hasActiveProvider: hasActiveProvider,
      hasConfiguredSync: hasConfiguredSync,
      masterEnabled: masterEnabled,
      suspended: input.experienceState.suspended,
      bookmarkSelected: contentSelection.bookmarkSelected,
      personalizationSelected: contentSelection.personalizationSelected,
      historySelected: input.experienceState.historySelected,
      historySupported: activeProvider !== 'webdav',
      historyProviderLabel: this.resolveHistoryProviderLabel(activeProvider),
      statusKind: statusKind,
      statusTitle: this.resolveStatusTitle(statusKind, hasConfiguredSync),
      statusMessage: this.resolveStatusMessage(
        statusKind,
        input,
        activeProvider,
        contentSelection
      ),
      goalLabel: this.resolveGoalLabel(activeProvider, input.settings),
      lastSyncLabel: this.formatLastSyncLabel(Math.max(
        resolveAiraSyncActiveProviderLastSuccessAt(input.settings),
        input.personalizationConfig.lastSyncAt
      )),
      enabledPersonalizationItemCount: enabledPersonalizationItemCount,
      canSyncNow: masterEnabled && hasEnabledContent && statusKind !== 'paused' && statusKind !== 'syncing',
      requiresAiraProAction: activeProvider === 'aira_cloud' && !input.airaCloudEligible,
      additionalBackupSummary: this.resolveAdditionalBackupSummary(input.settings),
      huaweiSpaceBookmarkUpgradeRequired: input.huaweiSpaceBookmarkUpgradeRequired,
      airaCloudActive: activeProvider === 'aira_cloud',
      huaweiSpaceActive: activeProvider === 'huawei_space',
      huaweiBookmarkInitializing: huaweiBookmarkInitializing,
      goalOptions: this.buildGoalOptions(activeProvider, input.settings),
      personalizationItems: personalizationItems
    };
  }

  resolveGoalLabel(remoteKind: AiraSyncRemoteKind, settings?: AiraSyncSettings): string {
    if (remoteKind === 'huawei_space') {
      if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
        return '尚未选择';
      }
      return '华为云空间';
    }
    if (remoteKind === 'aira_cloud') {
      if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
        return '尚未选择';
      }
      return '手机与电脑之间';
    }
    if (remoteKind === 'webdav') {
      return this.resolveWebdavProviderLabel(settings);
    }
    if (remoteKind === 'self_hosted') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity() ? '使用自己的服务器' : '个人服务器';
    }
    return '尚未选择';
  }

  private resolveHistoryProviderLabel(provider: AiraSyncRemoteKind): string {
    if (provider === 'huawei_space') {
      if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
        return '尚未选择';
      }
      return '华为云空间';
    }
    if (provider === 'aira_cloud' && !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return '尚未选择';
    }
    if (provider === 'self_hosted') {
      return '个人服务器';
    }
    return 'Aira 云';
  }

  private resolveStatusKind(
    input: SyncExperienceViewModelInput,
    activeProvider: AiraSyncRemoteKind,
    hasConfiguredSync: boolean,
    hasEnabledContent: boolean
  ): SyncExperienceStatusKind {
    if (!hasConfiguredSync) {
      return 'setup';
    }
    if (input.experienceState.suspended) {
      return 'paused';
    }
    if (activeProvider === 'huawei_space' && input.huaweiSpaceBookmarkUpgradeRequired) {
      return 'attention';
    }
    if (!hasEnabledContent) {
      return 'setup';
    }
    if (activeProvider === 'aira_cloud' && !input.airaCloudEligible) {
      return 'attention';
    }
    if (this.isHuaweiBookmarkInitializing(input.settings)) {
      return 'initializing';
    }
    if (input.isSyncing) {
      return 'syncing';
    }
    if (this.bookmarkNeedsAttention(input, activeProvider) ||
      this.personalizationNeedsAttention(input, activeProvider)) {
      return 'attention';
    }
    if (this.hasAdditionalBackupAttention(input.settings)) {
      return 'attention';
    }
    return 'normal';
  }

  private resolveStatusTitle(kind: SyncExperienceStatusKind, hasConfiguredSync: boolean): string {
    if (kind === 'setup') {
      return hasConfiguredSync ? '请选择同步内容' : '同步尚未开启';
    }
    if (kind === 'attention') {
      return '部分内容需要处理';
    }
    if (kind === 'paused') {
      return '已暂停';
    }
    if (kind === 'syncing') {
      return '正在同步';
    }
    if (kind === 'initializing') {
      return '正在初始化书签';
    }
    return '同步正常';
  }

  private resolveStatusMessage(
    kind: SyncExperienceStatusKind,
    input: SyncExperienceViewModelInput,
    activeProvider: AiraSyncRemoteKind,
    contentSelection: SyncExperienceContentSelection
  ): string {
    if (kind === 'setup') {
      if (activeProvider === 'none') {
        return '先选择同步内容，再选择希望数据出现在哪些设备上。';
      }
      if (!contentSelection.bookmarkSelected && !contentSelection.personalizationSelected &&
        !contentSelection.historySelected) {
        if (activeProvider === 'webdav') {
          return '同步方式仍然开启，请在下方选择书签、主页收藏、小说书架或常用设置。';
        }
        return '同步方式仍然开启，请在下方选择书签、历史记录、主页收藏、小说书架或常用设置。';
      }
      return '同步方式已保存，重新开启后会按当前内容选择继续同步。';
    }
    if (kind === 'paused') {
      return '本机和云端数据都已保留，重新开启后会安全恢复。';
    }
    if (kind === 'attention') {
      if (activeProvider === 'huawei_space' && input.huaweiSpaceBookmarkUpgradeRequired) {
        return '华为云空间书签同步已升级，请重新开启书签同步。本机书签和其他同步内容不受影响。';
      }
      if (activeProvider === 'aira_cloud' && !input.airaCloudEligible) {
        return '手机与电脑之间的同步需要恢复 Aira Pro，或更改同步方式。';
      }
      const bookmarkNeedsAttention = this.bookmarkNeedsAttention(input, activeProvider);
      const personalizationNeedsAttention = this.personalizationNeedsAttention(input, activeProvider);
      const systemUpdateGuidance = this.resolveHuaweiSpacePersonalizationSystemUpdateGuidance(
        input,
        activeProvider
      );
      if (bookmarkNeedsAttention && personalizationNeedsAttention) {
        const bookmarkMessage = this.resolveBookmarkFailureMessage(input, activeProvider);
        const message = `${bookmarkMessage} 主页收藏、小说书架或常用设置也暂时没有完成同步。`;
        return systemUpdateGuidance.length > 0 ? `${message}${systemUpdateGuidance}` : message;
      }
      if (bookmarkNeedsAttention) {
        return `${this.resolveBookmarkFailureMessage(input, activeProvider)} ` +
          '主页收藏、小说书架和常用设置不受影响。';
      }
      if (personalizationNeedsAttention) {
        const message = '主页收藏、小说书架或常用设置暂时没有完成同步，书签不受影响。';
        return systemUpdateGuidance.length > 0 ? `${message}${systemUpdateGuidance}` : message;
      }
      if (this.hasAdditionalBackupAttention(input.settings)) {
        return '一个或多个额外备份位置暂时没有完成，当前同步方式不受影响。';
      }
      return '部分内容暂时没有完成同步，可重试后继续。';
    }
    if (kind === 'syncing') {
      return contentSelection.historySelected
        ? '正在同步历史记录和已选择的其他内容。'
        : '正在安全同步书签、主页收藏、小说书架和常用设置。';
    }
    if (kind === 'initializing') {
      return '正在从华为云空间拉取并确认完整书签，完成后会自动保持同步。';
    }
    return contentSelection.historySelected
      ? '历史记录和已选择的其他内容会自动保持一致。'
      : '书签、主页收藏、小说书架和常用设置会自动保持一致。';
  }

  private resolveContentSelection(
    input: SyncExperienceViewModelInput,
    hasActiveProvider: boolean
  ): SyncExperienceContentSelection {
    const historySelected = input.experienceState.historySelected && input.settings.remoteKind !== 'webdav';
    if (!hasActiveProvider || input.experienceState.suspended) {
      return {
        bookmarkSelected: input.experienceState.bookmarkSelected,
        personalizationSelected: input.experienceState.personalizationSelected,
        historySelected: historySelected
      };
    }
    return {
      bookmarkSelected: input.settings.bookmarkSyncEnabled === true,
      personalizationSelected: input.settings.personalizationSyncEnabled === true &&
        (input.personalizationConfig.items.some((item): boolean => item.enabled) || input.novelBookshelfSyncEnabled),
      historySelected: historySelected
    };
  }

  private buildPersonalizationItems(
    input: SyncExperienceViewModelInput,
    hasActiveProvider: boolean
  ): PersonalizationSyncItemState[] {
    const items = this.personalizationViewModel.buildDefaultState(
      input.personalizationConfig,
      input.novelBookshelfSyncEnabled
    ).items;
    const hiddenDomainPaused = hasActiveProvider && !input.experienceState.suspended &&
      input.settings.personalizationSyncEnabled !== true;
    if (!hiddenDomainPaused) {
      return items;
    }
    return items.map((item: PersonalizationSyncItemState): PersonalizationSyncItemState => {
      return {
        id: item.id,
        title: item.title,
        summary: item.summary,
        enabled: false
      };
    });
  }

  private buildGoalOptions(
    activeProvider: AiraSyncRemoteKind,
    settings: AiraSyncSettings
  ): SyncExperienceGoalOption[] {
    return resolveDistributionSyncExperienceGoals().filter((goal: SyncExperienceGoalDescriptor): boolean => {
      return this.isProviderAvailable(goal.id);
    }).map((goal: SyncExperienceGoalDescriptor): SyncExperienceGoalOption => {
      return {
        id: goal.id,
        title: this.resolveGoalOptionTitle(goal, settings),
        description: goal.description,
        isSelected: activeProvider === goal.id,
        requiresPro: goal.requiresPro
      };
    });
  }

  private resolveWebdavProviderLabel(settings?: AiraSyncSettings): string {
    const endpoint = settings?.webdav.endpoint.trim() ?? '';
    if (endpoint.length <= 0) {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity() ? 'WebDAV' : '使用自己的服务器';
    }
    return this.webdavProviderCatalog.resolveProviderForEndpoint(endpoint).name;
  }

  private resolveGoalOptionTitle(
    goal: SyncExperienceGoalDescriptor,
    settings: AiraSyncSettings
  ): string {
    if (goal.id === 'webdav' && AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
      return this.resolveWebdavProviderLabel(settings);
    }
    return resolveDistributionGoalTitle(goal);
  }

  private resolveAdditionalBackupSummary(settings: AiraSyncSettings): string {
    const count = (settings.additionalBackupRemoteKinds ?? []).length;
    if (count <= 0) {
      return '未设置';
    }
    if (settings.additionalBackupEnabled !== true) {
      return `${count} 个位置 · 已暂停`;
    }
    const days = settings.additionalBackupIntervalDays === 1 || settings.additionalBackupIntervalDays === 3
      ? settings.additionalBackupIntervalDays
      : 7;
    const intervalLabel = days === 1 ? '每天一次' : `每 ${days} 天一次`;
    return `${count} 个位置 · ${intervalLabel}`;
  }

  private findRuntimeState(
    settings: AiraSyncSettings,
    activeProvider: AiraSyncRemoteKind
  ): AiraSyncProviderRuntimeState | undefined {
    return (settings.providerStates ?? []).find((state: AiraSyncProviderRuntimeState): boolean => {
      return state.remoteKind === activeProvider;
    });
  }

  private bookmarkNeedsAttention(
    input: SyncExperienceViewModelInput,
    activeProvider: AiraSyncRemoteKind
  ): boolean {
    if (input.settings.bookmarkSyncEnabled !== true) {
      return false;
    }
    const state = this.findRuntimeState(input.settings, activeProvider);
    return state !== undefined && this.isRuntimeUnhealthy(state.bookmark);
  }

  private resolveBookmarkFailureMessage(
    input: SyncExperienceViewModelInput,
    activeProvider: AiraSyncRemoteKind
  ): string {
    const state = this.findRuntimeState(input.settings, activeProvider);
    return this.syncFailurePresentationService.buildBookmarkFailureMessage({
      remoteKind: activeProvider,
      operationName: '书签同步',
      failure: state === undefined ? undefined : this.resolveRuntimeBookmarkFailure(state.bookmark)
    });
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

  private personalizationNeedsAttention(
    input: SyncExperienceViewModelInput,
    activeProvider: AiraSyncRemoteKind
  ): boolean {
    if (input.settings.personalizationSyncEnabled !== true) {
      return false;
    }
    const state = this.findRuntimeState(input.settings, activeProvider);
    return state !== undefined && this.isRuntimeUnhealthy(state.personalization);
  }

  private resolveHuaweiSpacePersonalizationSystemUpdateGuidance(
    input: SyncExperienceViewModelInput,
    activeProvider: AiraSyncRemoteKind
  ): string {
    if (activeProvider !== 'huawei_space') {
      return '';
    }
    const state = this.findRuntimeState(input.settings, activeProvider);
    if (state === undefined) {
      return '';
    }
    return this.syncFailurePresentationService
      .buildHuaweiSpacePersonalizationSystemUpdateGuidance(state.personalization.lastError);
  }

  private isRuntimeUnhealthy(state: AiraSyncDomainRuntimeState): boolean {
    return state.health === 'degraded' || state.health === 'unavailable';
  }

  private isHuaweiBookmarkInitializing(settings: AiraSyncSettings): boolean {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space') ||
      settings.remoteKind !== 'huawei_space' || settings.bookmarkSyncEnabled !== true ||
      (settings.pendingBookmarkSyncAt ?? 0) <= 0) {
      return false;
    }
    const state = this.findRuntimeState(settings, 'huawei_space');
    return state === undefined || (!state.bookmark.blocked && state.bookmark.lastSuccessAt <= 0);
  }

  private hasAdditionalBackupAttention(settings: AiraSyncSettings): boolean {
    if (settings.additionalBackupEnabled !== true) {
      return false;
    }
    const backupKinds = settings.additionalBackupRemoteKinds ?? [];
    return backupKinds.some((remoteKind: AiraSyncProviderKind): boolean => {
      const state = this.findRuntimeState(settings, remoteKind);
      return state !== undefined && (
        this.isRuntimeUnhealthy(state.bookmarkBackup) ||
        this.isRuntimeUnhealthy(state.personalizationBackup)
      );
    });
  }

  private isProviderKind(remoteKind: AiraSyncRemoteKind): boolean {
    return this.isProviderAvailable(remoteKind);
  }

  private resolveAvailableProvider(remoteKind: AiraSyncRemoteKind): AiraSyncRemoteKind {
    if (!this.isProviderAvailable(remoteKind)) {
      return 'none';
    }
    return remoteKind;
  }

  private isProviderAvailable(remoteKind: AiraSyncRemoteKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud');
    }
    if (remoteKind === 'huawei_space') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space');
    }
    return remoteKind === 'webdav' || remoteKind === 'self_hosted';
  }

  private formatLastSyncLabel(timestamp: number): string {
    if (timestamp <= 0) {
      return '尚未完成同步';
    }
    const date = new Date(timestamp);
    const now = new Date();
    const time = `${this.padTwoDigits(date.getHours())}:${this.padTwoDigits(date.getMinutes())}`;
    if (date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate()) {
      return `今天 ${time}`;
    }
    return `${date.getMonth() + 1}月${date.getDate()}日 ${time}`;
  }

  private padTwoDigits(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}

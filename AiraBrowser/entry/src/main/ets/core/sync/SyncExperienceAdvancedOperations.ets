import {
  AiraBookmarkOverview,
  AiraBookmarkMergeSyncResult,
  AiraSyncBaselineRecord,
  AiraSyncRemoteKind
} from '../../common/models/AiraSyncModels';
import { EntitlementDecision } from '../../common/models/MembershipModels';
import {
  AiraLocalBookmarkOverviewCacheRepository
} from '../../data/sync/AiraLocalBookmarkOverviewCacheRepository';
import { SyncService } from '../../services/sync/SyncService';
import {
  BookmarkLocalOverviewCounts,
  BookmarkLocalOverviewViewModel
} from '../bookmarks/BookmarkLocalOverviewViewModel';
import { SyncRemoteStatusCoordinator } from './SyncRemoteStatusCoordinator';
import {
  SyncExperienceProviderOperations,
  SyncExperienceProviderOutcome
} from './SyncExperienceProviderOperations';

export interface SyncAdvancedRemoteSummaryOutcome {
  summary: string;
}

export interface SyncAdvancedMergeOutcome {
  result: AiraBookmarkMergeSyncResult;
  completionTitle: string;
  completionSubtitle: string;
  dialogTitle: string;
  message: string;
}

export interface SyncAdvancedStatusOverview {
  localCounts: BookmarkLocalOverviewCounts;
  baselines: AiraSyncBaselineRecord[];
}

export type SyncProviderSelectionPresentationType =
  | 'selected'
  | 'blocked'
  | 'membership-required'
  | 'failed';

export interface SyncProviderSelectionPresentation {
  type: SyncProviderSelectionPresentationType;
  providerLabel: string;
  completionTitle: string;
  completionSubtitle: string;
  dialogTitle: string;
  message: string;
  membershipDecision?: EntitlementDecision;
}

export class SyncExperienceAdvancedOperations {
  private syncService: SyncService;
  private remoteStatusCoordinator: SyncRemoteStatusCoordinator;
  private localOverviewCacheRepository: AiraLocalBookmarkOverviewCacheRepository;
  private providerOperations: SyncExperienceProviderOperations;
  private localOverviewViewModel: BookmarkLocalOverviewViewModel = new BookmarkLocalOverviewViewModel();

  constructor(
    syncService: SyncService,
    remoteStatusCoordinator: SyncRemoteStatusCoordinator,
    localOverviewCacheRepository: AiraLocalBookmarkOverviewCacheRepository,
    providerOperations: SyncExperienceProviderOperations
  ) {
    this.syncService = syncService;
    this.remoteStatusCoordinator = remoteStatusCoordinator;
    this.localOverviewCacheRepository = localOverviewCacheRepository;
    this.providerOperations = providerOperations;
  }

  async selectProvider(remoteKind: AiraSyncRemoteKind): Promise<SyncProviderSelectionPresentation> {
    if (remoteKind === 'none') {
      throw new Error('请先选择同步来源。');
    }
    const outcome = await this.providerOperations.selectProvider(remoteKind);
    if (outcome.type === 'provider-selected') {
      await this.readRemoteSummary(remoteKind).catch((_error: Error): void => {
      });
    }
    return this.presentProviderSelection(outcome);
  }

  async readRemoteSummary(remoteKind: AiraSyncRemoteKind): Promise<SyncAdvancedRemoteSummaryOutcome> {
    if (remoteKind === 'none') {
      throw new Error('请先选择同步来源。');
    }
    const result = await this.remoteStatusCoordinator.readAndCache(remoteKind);
    return {
      summary: result.summary
    };
  }

  async loadStatusOverview(enabledKinds: AiraSyncRemoteKind[]): Promise<SyncAdvancedStatusOverview> {
    const values = await Promise.all([
      this.loadLocalBookmarkCounts(),
      this.readEnabledBaselines(enabledKinds),
      this.refreshEnabledRemoteSummaries(enabledKinds)
    ]);
    return {
      localCounts: values[0],
      baselines: values[1]
    };
  }

  async presentActiveBookmarkMerge(
    remoteKind: AiraSyncRemoteKind,
    result: AiraBookmarkMergeSyncResult
  ): Promise<SyncAdvancedMergeOutcome> {
    return {
      result: result,
      completionTitle: this.resolveMergeCompletionTitle(result, remoteKind),
      completionSubtitle: this.resolveMergeCompletionSubtitle(result, remoteKind),
      dialogTitle: this.resolveMergeDialogTitle(result, remoteKind),
      message: this.buildMergeResultMessage(result, remoteKind)
    };
  }

  readEnabledBaselines(enabledKinds: AiraSyncRemoteKind[]): Promise<AiraSyncBaselineRecord[]> {
    const tasks: Promise<AiraSyncBaselineRecord | undefined>[] = [];
    enabledKinds.forEach((remoteKind: AiraSyncRemoteKind): void => {
      tasks.push(this.syncService.readAiraSyncBaselineForKind(remoteKind));
    });
    return Promise.all(tasks).then((records: (AiraSyncBaselineRecord | undefined)[]): AiraSyncBaselineRecord[] => {
      const result: AiraSyncBaselineRecord[] = [];
      records.forEach((record: AiraSyncBaselineRecord | undefined): void => {
        if (record !== undefined) {
          result.push(record);
        }
      });
      return result;
    });
  }

  private async refreshEnabledRemoteSummaries(enabledKinds: AiraSyncRemoteKind[]): Promise<void> {
    const tasks: Promise<void>[] = [];
    enabledKinds.forEach((remoteKind: AiraSyncRemoteKind): void => {
      if (remoteKind === 'none') {
        return;
      }
      tasks.push(this.remoteStatusCoordinator.readAndCache(remoteKind)
        .then((): void => undefined)
        .catch((_error: Error): void => undefined));
    });
    await Promise.all(tasks);
  }

  private presentProviderSelection(outcome: SyncExperienceProviderOutcome): SyncProviderSelectionPresentation {
    if (outcome.type === 'provider-selection-blocked') {
      return {
        type: 'blocked',
        providerLabel: outcome.providerLabel,
        completionTitle: '切换未完成',
        completionSubtitle: '请先处理同步冲突或重试',
        dialogTitle: '切换未完成',
        message: outcome.message
      };
    }
    if (outcome.type === 'provider-selected') {
      return {
        type: 'selected',
        providerLabel: outcome.providerLabel,
        completionTitle: '同步方式已更改',
        completionSubtitle: `当前设备已改用${outcome.providerLabel}`,
        dialogTitle: '切换完成',
        message: outcome.message
      };
    }
    if (outcome.type === 'membership-required' && outcome.membershipDecision !== undefined) {
      return {
        type: 'membership-required',
        providerLabel: outcome.providerLabel,
        completionTitle: '切换失败',
        completionSubtitle: '需要会员权限',
        dialogTitle: '更改同步方式',
        message: outcome.message,
        membershipDecision: outcome.membershipDecision
      };
    }
    return {
      type: 'failed',
      providerLabel: outcome.providerLabel,
      completionTitle: '切换失败',
      completionSubtitle: '请稍后再试',
      dialogTitle: outcome.title.length > 0 ? outcome.title : '更改同步方式',
      message: outcome.message
    };
  }

  private async loadLocalBookmarkCounts(): Promise<BookmarkLocalOverviewCounts> {
    return this.localOverviewViewModel.loadCurrentCounts(
      this.localOverviewCacheRepository,
      (): Promise<AiraBookmarkOverview> => {
        return this.syncService.buildFreshAiraBookmarkOverview();
      }
    );
  }

  private resolveMergeCompletionTitle(result: AiraBookmarkMergeSyncResult, remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'huawei_space' && result.merged) {
      return '已保存到同步库';
    }
    return result.merged ? '同步完成' : '已经是最新';
  }

  private resolveMergeCompletionSubtitle(result: AiraBookmarkMergeSyncResult, remoteKind: AiraSyncRemoteKind): string {
    if (!result.merged) {
      return '暂时没有新的变化';
    }
    if (remoteKind === 'huawei_space') {
      return '系统云空间同步会继续在后台处理';
    }
    return '本机和云端已经保持一致';
  }

  private resolveMergeDialogTitle(result: AiraBookmarkMergeSyncResult, remoteKind: AiraSyncRemoteKind): string {
    if (!result.merged) {
      return '无需同步';
    }
    return remoteKind === 'huawei_space' ? '已保存到同步库' : '同步成功';
  }

  private buildMergeResultMessage(result: AiraBookmarkMergeSyncResult, remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'huawei_space') {
      return this.simplifyHuaweiSpaceMergeSummary(result);
    }
    return this.simplifyMergeSummary(result);
  }

  private simplifyMergeSummary(result: AiraBookmarkMergeSyncResult): string {
    if (result.blocked) {
      return result.conflictCount > 0
        ? `发现 ${result.conflictCount} 个书签在本机和云端都改过，请选择保留哪一边。`
        : '同步需要你确认后才能继续。';
    }
    if (!result.merged) {
      return '本机和云端已经一致，没有需要同步的变化。';
    }
    if (result.localChangeCount > 0 && result.remoteChangeCount > 0) {
      return '本机和云端的书签已合并完成。';
    }
    if (result.localChangeCount > 0) {
      return '本机新增或修改的书签已保存到云端。';
    }
    if (result.remoteChangeCount > 0) {
      return '云端新增或修改的书签已同步到本机。';
    }
    return '书签同步已完成。';
  }

  private simplifyHuaweiSpaceMergeSummary(result: AiraBookmarkMergeSyncResult): string {
    if (result.blocked) {
      return result.conflictCount > 0
        ? `发现 ${result.conflictCount} 个书签在本机和同步库都改过，请选择保留哪一边。`
        : '同步需要你确认后才能继续。';
    }
    if (!result.merged) {
      return '本机和华为云空间同步库没有新的书签变化，系统云空间同步会继续在后台处理。';
    }
    if (result.localChangeCount > 0 && result.remoteChangeCount > 0) {
      return '本机和华为云空间同步库的书签已合并完成，等待系统云空间同步。';
    }
    if (result.localChangeCount > 0) {
      return '本机新增或修改的书签已保存到华为云空间同步库，等待系统云空间同步。';
    }
    if (result.remoteChangeCount > 0) {
      return '华为云空间同步库中的书签已同步到本机。';
    }
    return '华为云空间同步库已确认，系统云空间同步会继续在后台处理。';
  }
}

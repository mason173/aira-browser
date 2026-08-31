import { AIRA_FEATURE_CLOUD_SYNC } from '../../common/constants/MembershipFeatureKeys';
import {
  AiraBookmarkMergeSyncResult,
  AiraSyncProviderKind,
  AiraSyncRemoteKind,
  AiraSyncSettings,
  AiraSyncStatusSummary
} from '../../common/models/AiraSyncModels';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { SyncService } from '../../services/sync/SyncService';
import { SyncRemoteStatusCoordinator } from './SyncRemoteStatusCoordinator';

export type SyncBookmarkDomainRunOutcomeType =
  | 'completed'
  | 'blocked'
  | 'failed';

export interface SyncBookmarkDomainRunOutcome {
  type: SyncBookmarkDomainRunOutcomeType;
  title: string;
  message: string;
  result?: AiraBookmarkMergeSyncResult;
}

export type SyncBookmarkDomainProgressHandler = () => void;
export type SyncBookmarkDomainRunIntent = 'enabled-domain' | 'configured-provider-maintenance';

export class SyncBookmarkDomain {
  private syncService: SyncService;
  private membershipFeature: MembershipFeature;
  private remoteStatusCoordinator: SyncRemoteStatusCoordinator;

  constructor(
    syncService: SyncService,
    membershipFeature: MembershipFeature,
    remoteStatusCoordinator: SyncRemoteStatusCoordinator
  ) {
    this.syncService = syncService;
    this.membershipFeature = membershipFeature;
    this.remoteStatusCoordinator = remoteStatusCoordinator;
  }

  async runImmediateSync(
    onMergeStarted?: SyncBookmarkDomainProgressHandler,
    forceBackupWrites: boolean = false,
    intent: SyncBookmarkDomainRunIntent = 'enabled-domain',
    automatic: boolean = false
  ): Promise<SyncBookmarkDomainRunOutcome> {
    const remoteKind = this.resolveActiveProvider(this.syncService.getAiraSyncSettings());
    if (onMergeStarted !== undefined) {
      onMergeStarted();
    }
    try {
      const result = await this.syncService.mergeActiveAiraBookmarks(
        forceBackupWrites,
        intent === 'configured-provider-maintenance'
      );
      if (result.blocked) {
        return {
          type: 'blocked',
          title: '同步需要处理',
          message: result.summary,
          result: result
        };
      }
      if (remoteKind === 'aira_cloud' && this.shouldRecordCloudUsage(result, automatic)) {
        await this.membershipFeature.recordUsage(AIRA_FEATURE_CLOUD_SYNC).catch((_error: Error): void => {
        });
      }
      return {
        type: 'completed',
        title: result.merged ? '同步完成' : '已经是最新',
        message: result.summary,
        result: result
      };
    } catch (error) {
      return {
        type: 'failed',
        title: '立即同步失败',
        message: this.stringifyError(error as Error)
      };
    }
  }

  async refreshRemoteStatus(
    remoteKind: AiraSyncProviderKind,
    fallbackCommitId?: string
  ): Promise<AiraSyncStatusSummary> {
    return (await this.remoteStatusCoordinator.readAndCache(remoteKind, fallbackCommitId)).status;
  }

  private shouldRecordCloudUsage(result: AiraBookmarkMergeSyncResult, automatic: boolean): boolean {
    return !automatic || result.merged || result.localChangeCount > 0 || result.remoteChangeCount > 0;
  }

  private resolveActiveProvider(settings: AiraSyncSettings): AiraSyncProviderKind | undefined {
    const remoteKind: AiraSyncRemoteKind = settings.remoteKind;
    if (remoteKind === 'aira_cloud' || remoteKind === 'huawei_space' || remoteKind === 'webdav' ||
      remoteKind === 'self_hosted') {
      return remoteKind;
    }
    return undefined;
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}

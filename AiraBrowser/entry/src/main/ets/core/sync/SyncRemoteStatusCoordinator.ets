import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AIRA_SYNC_DEFAULT_ROOT,
  AiraSyncProviderKind,
  AiraSyncRemoteHead,
  AiraSyncSettings,
  AiraSyncStatusSummary,
  buildAiraHuaweiSpaceRemoteStatusProviderKey,
  buildAiraPersonalServerRemoteStatusProviderKey,
  buildAiraWebdavRemoteStatusProviderKey
} from '../../common/models/AiraSyncModels';
import { SyncService } from '../../services/sync/SyncService';

const REMOTE_STATUS_LOG_DOMAIN: number = 0x0000;
const REMOTE_STATUS_LOG_TAG: string = 'AiraSyncRemoteStatus';

export interface SyncRemoteStatusResult {
  status: AiraSyncStatusSummary;
  summary: string;
}

export class SyncRemoteStatusCoordinator {
  private static readTail: Promise<void> = Promise.resolve();
  private syncService: SyncService;

  constructor(syncService: SyncService) {
    this.syncService = syncService;
  }

  readAndCache(
    remoteKind: AiraSyncProviderKind,
    fallbackCommitId?: string
  ): Promise<SyncRemoteStatusResult> {
    const operation = SyncRemoteStatusCoordinator.readTail.then(
      (): Promise<SyncRemoteStatusResult> => this.readAndCacheNow(remoteKind, fallbackCommitId),
      (): Promise<SyncRemoteStatusResult> => this.readAndCacheNow(remoteKind, fallbackCommitId)
    );
    SyncRemoteStatusCoordinator.readTail = operation.then(
      (): void => undefined,
      (): void => undefined
    );
    return operation;
  }

  private async readAndCacheNow(
    remoteKind: AiraSyncProviderKind,
    fallbackCommitId?: string
  ): Promise<SyncRemoteStatusResult> {
    const initialSettings = this.syncService.getAiraSyncSettings();
    const expectedProviderKey = this.resolveProviderKey(
      initialSettings,
      remoteKind
    );
    if (this.isHuaweiBookmarkInitializationPending(initialSettings, remoteKind)) {
      return this.saveHuaweiBookmarkInitializationStatus(
        expectedProviderKey,
        fallbackCommitId ?? initialSettings.huaweiSpace.remoteStatusCache?.commitId ?? ''
      );
    }
    let status: AiraSyncStatusSummary;
    try {
      status = fallbackCommitId === undefined
        ? await this.syncService.readRemoteSummary(remoteKind)
        : await this.readSummaryWithFallback(remoteKind, fallbackCommitId);
    } catch (error) {
      const message = this.stringifyError(error as Error);
      hilog.warn(
        REMOTE_STATUS_LOG_DOMAIN,
        REMOTE_STATUS_LOG_TAG,
        'remote summary read failed provider=%{public}s reason=%{public}s',
        remoteKind,
        message
      );
      await this.saveUnavailableCache(
        remoteKind,
        expectedProviderKey,
        fallbackCommitId
      ).catch((_cacheError: Error): void => undefined);
      throw new Error(message);
    }
    const useCompletionFallback = fallbackCommitId !== undefined;
    const summary = useCompletionFallback
      ? this.buildRemoteSummary(status)
      : `${status.localBookmarkFolders} 个文件夹，${status.localBookmarkItems} 个书签`;
    const settings = this.syncService.getAiraSyncSettings();
    if (this.resolveProviderKey(settings, remoteKind) !== expectedProviderKey) {
      throw new Error('同步方式已更改，本次远端状态结果已丢弃。');
    }
    await this.syncService.saveAiraRemoteStatusCacheForKind(remoteKind, {
      providerKey: expectedProviderKey,
      summary: summary,
      bookmarkFolders: useCompletionFallback
        ? this.normalizeCacheCount(status.localBookmarkFolders)
        : status.localBookmarkFolders,
      bookmarkItems: useCompletionFallback
        ? this.normalizeCacheCount(status.localBookmarkItems)
        : status.localBookmarkItems,
      commitId: status.baselineCommitId.length > 0 ? status.baselineCommitId : (fallbackCommitId ?? ''),
      checkedAt: Date.now()
    });
    return { status: status, summary: summary };
  }

  private async saveHuaweiBookmarkInitializationStatus(
    expectedProviderKey: string,
    fallbackCommitId: string
  ): Promise<SyncRemoteStatusResult> {
    const summary = '华为云空间书签正在后台初始化，等待云端确认';
    const status = this.buildUnavailableSummary('huawei_space', fallbackCommitId, summary);
    const settings = this.syncService.getAiraSyncSettings();
    if (this.resolveProviderKey(settings, 'huawei_space') !== expectedProviderKey ||
      !this.isHuaweiBookmarkInitializationPending(settings, 'huawei_space')) {
      throw new Error('同步状态已更改，本次初始化状态结果已丢弃。');
    }
    await this.syncService.saveAiraRemoteStatusCacheForKind('huawei_space', {
      providerKey: expectedProviderKey,
      summary: summary,
      bookmarkFolders: 0,
      bookmarkItems: 0,
      commitId: fallbackCommitId,
      checkedAt: Date.now()
    });
    return { status: status, summary: summary };
  }

  private isHuaweiBookmarkInitializationPending(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncProviderKind
  ): boolean {
    return remoteKind === 'huawei_space' && settings.remoteKind === 'huawei_space' &&
      settings.bookmarkSyncEnabled === true && (settings.pendingBookmarkSyncAt ?? 0) > 0;
  }

  private async readSummaryWithFallback(
    remoteKind: AiraSyncProviderKind,
    fallbackCommitId: string
  ): Promise<AiraSyncStatusSummary> {
    try {
      const status = await this.syncService.readRemoteSummary(remoteKind);
      if (remoteKind === 'huawei_space' && fallbackCommitId.trim().length > 0 &&
        status.baselineCommitId.trim().length <= 0) {
        return this.buildUnavailableSummary(
          remoteKind,
          fallbackCommitId,
          '华为云空间状态正在等待系统云同步确认'
        );
      }
      return status;
    } catch (summaryError) {
      try {
        const head = await this.readRemoteHead(remoteKind);
        if (head !== undefined) {
          return this.buildHeadSummary(remoteKind, head);
        }
      } catch (headError) {
        hilog.warn(
          REMOTE_STATUS_LOG_DOMAIN,
          REMOTE_STATUS_LOG_TAG,
          'remote summary fallback failed provider=%{public}s summary=%{public}s head=%{public}s',
          remoteKind,
          this.stringifyError(summaryError as Error),
          this.stringifyError(headError as Error)
        );
      }
      return this.buildUnavailableSummary(remoteKind, fallbackCommitId, '远端数据读取失败');
    }
  }

  private async readRemoteHead(remoteKind: AiraSyncProviderKind): Promise<AiraSyncRemoteHead | undefined> {
    if (remoteKind === 'aira_cloud') {
      return this.syncService.readAiraCloudRemoteHead();
    }
    if (remoteKind === 'huawei_space') {
      return this.syncService.readHuaweiSpaceRemoteHead();
    }
    return undefined;
  }

  private async saveUnavailableCache(
    remoteKind: AiraSyncProviderKind,
    expectedProviderKey: string,
    fallbackCommitId?: string
  ): Promise<void> {
    const settings = this.syncService.getAiraSyncSettings();
    if (this.resolveProviderKey(settings, remoteKind) !== expectedProviderKey) {
      return;
    }
    await this.syncService.saveAiraRemoteStatusCacheForKind(remoteKind, {
      providerKey: expectedProviderKey,
      summary: '远端数据读取失败',
      bookmarkFolders: 0,
      bookmarkItems: 0,
      commitId: fallbackCommitId ?? '',
      checkedAt: Date.now()
    });
  }

  private buildUnavailableSummary(
    remoteKind: AiraSyncProviderKind,
    fallbackCommitId: string,
    summary: string
  ): AiraSyncStatusSummary {
    return {
      providerId: this.resolveProviderKey(this.syncService.getAiraSyncSettings(), remoteKind),
      enabled: true,
      remoteKind: remoteKind,
      rootPath: AIRA_SYNC_DEFAULT_ROOT,
      baselineCommitId: fallbackCommitId,
      lastSuccessAt: Date.now(),
      localBookmarkFolders: -1,
      localBookmarkItems: -1,
      summary: summary
    };
  }

  private buildHeadSummary(remoteKind: AiraSyncProviderKind, head: AiraSyncRemoteHead): AiraSyncStatusSummary {
    const settings = this.syncService.getAiraSyncSettings();
    if (head.commitId === null) {
      return {
        providerId: this.resolveProviderKey(settings, remoteKind),
        enabled: true,
        remoteKind: remoteKind,
        rootPath: AIRA_SYNC_DEFAULT_ROOT,
        baselineCommitId: '',
        lastSuccessAt: Date.now(),
        localBookmarkFolders: 0,
        localBookmarkItems: 0,
        summary: '远端还没有书签同步状态。'
      };
    }
    if (head.hasBookmarkSummary) {
      return {
        providerId: this.resolveProviderKey(settings, remoteKind),
        enabled: true,
        remoteKind: remoteKind,
        rootPath: AIRA_SYNC_DEFAULT_ROOT,
        baselineCommitId: head.commitId,
        lastSuccessAt: Date.now(),
        localBookmarkFolders: head.bookmarkFolders,
        localBookmarkItems: head.bookmarkItems,
        summary: `${head.bookmarkFolders} 个文件夹，${head.bookmarkItems} 个书签`
      };
    }
    return {
      providerId: this.resolveProviderKey(settings, remoteKind),
      enabled: true,
      remoteKind: remoteKind,
      rootPath: AIRA_SYNC_DEFAULT_ROOT,
      baselineCommitId: head.commitId,
      lastSuccessAt: Date.now(),
      localBookmarkFolders: -1,
      localBookmarkItems: -1,
      summary: '远端摘要暂不可用'
    };
  }

  private buildRemoteSummary(status: AiraSyncStatusSummary): string {
    if (status.localBookmarkFolders < 0 || status.localBookmarkItems < 0) {
      return status.summary;
    }
    return `${status.localBookmarkFolders} 个文件夹，${status.localBookmarkItems} 个书签`;
  }

  private normalizeCacheCount(value: number): number {
    return value >= 0 ? value : 0;
  }

  private resolveProviderKey(settings: AiraSyncSettings, remoteKind: AiraSyncProviderKind): string {
    if (remoteKind === 'aira_cloud') {
      return `aira_cloud|${settings.huaweiCloud.uid.trim()}|${AIRA_SYNC_DEFAULT_ROOT}`;
    }
    if (remoteKind === 'huawei_space') {
      return buildAiraHuaweiSpaceRemoteStatusProviderKey(
        settings.huaweiSpace.uid,
        settings.huaweiSpace.databaseName,
        AIRA_SYNC_DEFAULT_ROOT
      );
    }
    if (remoteKind === 'self_hosted') {
      const config = settings.selfHosted;
      if (config === undefined) {
        return 'none';
      }
      return buildAiraPersonalServerRemoteStatusProviderKey(config.instanceId, config.baseUrl);
    }
    return buildAiraWebdavRemoteStatusProviderKey(
      settings.webdav.endpoint,
      settings.webdav.username,
      AIRA_SYNC_DEFAULT_ROOT
    );
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}

import {
  AIRA_FEATURE_CLOUD_SYNC,
  AIRA_FEATURE_WEBDAV_SYNC,
  AiraFeatureKey
} from '../../common/constants/MembershipFeatureKeys';
import {
  AIRA_SYNC_DEFAULT_ROOT,
  AiraSyncBaselineRecord,
  AiraSyncRemoteKind,
  AiraSyncSettings,
  buildAiraHuaweiSpaceRemoteStatusProviderKey,
  buildAiraWebdavRemoteStatusProviderKey,
  isAiraSyncProviderEnabled,
  resolveAiraSyncProviderRuntimeState
} from '../../common/models/AiraSyncModels';
import {
  AIRA_CLOUD_BOOKMARK_API_LARGE_PAYLOAD_TIMEOUT_MS
} from '../../services/sync/AiraCloudBookmarkRemoteStore';
import {
  SYNC_OPERATION_PROGRESS_TIMING
} from './SyncOperationProgressViewModel';
import { BookmarkLocalOverviewCounts } from '../bookmarks/BookmarkLocalOverviewViewModel';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export interface SyncAdvancedStatusViewState {
  providerText: string;
  baselineText: string;
  localText: string;
  remoteText: string;
  lastSyncText: string;
}

export interface SyncAdvancedProviderActionState {
  showHuaweiCloud: boolean;
  showHuaweiSpace: boolean;
  showWebdav: boolean;
  mergeRequiresPro: boolean;
}

export type SyncAdvancedProviderIdResolver = (remoteKind: AiraSyncRemoteKind) => string;

export class SyncAdvancedSettingsViewModel {
  buildPrivateStatus(): SyncAdvancedStatusViewState {
    return {
      providerText: '私密会话',
      baselineText: '不可用',
      localText: '私密会话不读取',
      remoteText: '不可用',
      lastSyncText: '私密会话不读取'
    };
  }

  buildStatus(
    settings: AiraSyncSettings,
    baselines: AiraSyncBaselineRecord[],
    providerIdResolver: SyncAdvancedProviderIdResolver,
    localCounts?: BookmarkLocalOverviewCounts
  ): SyncAdvancedStatusViewState {
    const enabledKinds = this.resolveEnabledRemoteKinds(settings);
    return {
      providerText: this.buildEnabledProviderSummary(enabledKinds),
      baselineText: this.buildBaselineSummary(baselines, enabledKinds, providerIdResolver),
      localText: localCounts === undefined
        ? '正在读取...'
        : this.formatBookmarkCounts(localCounts.bookmarkFolderCount, localCounts.bookmarkItemCount),
      remoteText: this.buildCachedRemoteSummary(settings, enabledKinds),
      lastSyncText: this.buildLastSyncSummary(settings, enabledKinds)
    };
  }

  buildProviderActions(settings: AiraSyncSettings): SyncAdvancedProviderActionState {
    return {
      showHuaweiCloud: AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') &&
        this.isProviderConfigured(settings, 'aira_cloud'),
      showHuaweiSpace: AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space') &&
        this.isProviderConfigured(settings, 'huawei_space'),
      showWebdav: this.isProviderConfigured(settings, 'webdav'),
      mergeRequiresPro: this.resolveEnabledRemoteKinds(settings).indexOf('aira_cloud') >= 0
    };
  }

  resolveEnabledRemoteKinds(settings: AiraSyncSettings): AiraSyncRemoteKind[] {
    if (this.isRemoteKindEnabled(settings, settings.remoteKind)) {
      return [settings.remoteKind];
    }
    if (this.isRemoteKindEnabled(settings, 'huawei_space')) {
      return ['huawei_space'];
    }
    if (this.isRemoteKindEnabled(settings, 'webdav')) {
      return ['webdav'];
    }
    if (this.isRemoteKindEnabled(settings, 'aira_cloud')) {
      return ['aira_cloud'];
    }
    return [];
  }

  isProviderSyncReady(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') &&
        isAiraSyncProviderEnabled(settings, remoteKind) &&
        settings.huaweiCloud.uid.trim().length > 0;
    }
    if (remoteKind === 'huawei_space') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space') &&
        isAiraSyncProviderEnabled(settings, remoteKind) &&
        settings.huaweiSpace.uid.trim().length > 0;
    }
    if (remoteKind === 'webdav') {
      return isAiraSyncProviderEnabled(settings, remoteKind) &&
        settings.webdav.endpoint.trim().length > 0 &&
        settings.webdav.username.trim().length > 0;
    }
    if (remoteKind === 'self_hosted') {
      const config = settings.selfHosted;
      return isAiraSyncProviderEnabled(settings, remoteKind) && config !== undefined &&
        config.instanceId.trim().length > 0 && config.deviceToken.trim().length > 0;
    }
    return false;
  }

  resolveActiveSyncServiceKey(settings: AiraSyncSettings, fallbackRemoteKind: AiraSyncRemoteKind): AiraFeatureKey {
    const enabledKinds = this.resolveEnabledRemoteKinds(settings);
    const remoteKind = enabledKinds.length === 1 ? enabledKinds[0] : fallbackRemoteKind;
    return this.resolveProviderSyncServiceKey(remoteKind);
  }

  resolveProviderSyncServiceKey(remoteKind: AiraSyncRemoteKind): AiraFeatureKey {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')
        ? AIRA_FEATURE_CLOUD_SYNC
        : '' as AiraFeatureKey;
    }
    if (remoteKind === 'webdav') {
      return AIRA_FEATURE_WEBDAV_SYNC;
    }
    if (remoteKind === 'huawei_space') {
      return '' as AiraFeatureKey;
    }
    return '' as AiraFeatureKey;
  }

  resolveActiveSyncServiceName(settings: AiraSyncSettings, fallbackRemoteKind: AiraSyncRemoteKind): string {
    const enabledKinds = this.resolveEnabledRemoteKinds(settings);
    const remoteKind = enabledKinds.length === 1 ? enabledKinds[0] : fallbackRemoteKind;
    return this.resolveProviderServiceName(remoteKind);
  }

  resolveProviderServiceName(remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'aira_cloud') {
      return 'Aira 云同步';
    }
    if (remoteKind === 'huawei_space') {
      return '华为云空间同步';
    }
    if (remoteKind === 'webdav') {
      return 'WebDAV';
    }
    if (remoteKind === 'self_hosted') {
      return '个人服务器';
    }
    return '同步服务';
  }

  resolveProviderShortLabel(remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'aira_cloud') {
      return 'Aira 云端';
    }
    if (remoteKind === 'huawei_space') {
      return '云空间';
    }
    if (remoteKind === 'webdav') {
      return 'WebDAV';
    }
    if (remoteKind === 'self_hosted') {
      return '个人服务器';
    }
    return '远端';
  }

  resolveProviderCheckActionLabel(remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'huawei_space') {
      return '检查华为云空间数据';
    }
    return `检查${this.resolveProviderShortLabel(remoteKind)}数据`;
  }

  resolveProviderOperationTimeoutMs(remoteKind: AiraSyncRemoteKind): number {
    return remoteKind === 'aira_cloud'
      ? AIRA_CLOUD_BOOKMARK_API_LARGE_PAYLOAD_TIMEOUT_MS
      : SYNC_OPERATION_PROGRESS_TIMING.timeoutMs;
  }

  resolveMergeActionLabel(): string {
    return '立即合并同步';
  }

  updateRemoteSummaryText(summary: string): string {
    return summary;
  }

  resolveRemoteStatusProviderKey(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'aira_cloud') {
      if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
        return 'none';
      }
      return `aira_cloud|${settings.huaweiCloud.uid.trim()}|${AIRA_SYNC_DEFAULT_ROOT}`;
    }
    if (remoteKind === 'huawei_space') {
      return buildAiraHuaweiSpaceRemoteStatusProviderKey(
        settings.huaweiSpace.uid,
        settings.huaweiSpace.databaseName,
        AIRA_SYNC_DEFAULT_ROOT
      );
    }
    if (remoteKind === 'webdav') {
      return buildAiraWebdavRemoteStatusProviderKey(
        settings.webdav.endpoint,
        settings.webdav.username,
        AIRA_SYNC_DEFAULT_ROOT
      );
    }
    if (remoteKind === 'self_hosted') {
      const config = settings.selfHosted;
      if (config === undefined) {
        return 'none';
      }
      return `self_hosted|${config.instanceId.trim()}|${config.baseUrl.trim().replace(/\/+$/, '')}`;
    }
    return 'none';
  }

  private isProviderConfigured(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') &&
        settings.huaweiCloud.uid.trim().length > 0;
    }
    if (remoteKind === 'huawei_space') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space') &&
        settings.huaweiSpace.uid.trim().length > 0;
    }
    if (remoteKind === 'webdav') {
      return settings.webdav.endpoint.trim().length > 0 &&
        settings.webdav.username.trim().length > 0;
    }
    if (remoteKind === 'self_hosted') {
      const config = settings.selfHosted;
      return config !== undefined && config.baseUrl.trim().length > 0 &&
        config.instanceId.trim().length > 0 && config.deviceToken.trim().length > 0;
    }
    return false;
  }

  private buildEnabledProviderSummary(enabledKinds: AiraSyncRemoteKind[]): string {
    if (enabledKinds.length <= 0) {
      return '未启用';
    }
    return this.resolveProviderServiceName(enabledKinds[0]);
  }

  private buildCachedRemoteSummary(settings: AiraSyncSettings, enabledKinds: AiraSyncRemoteKind[]): string {
    if (enabledKinds.length <= 0) {
      return '未启用';
    }
    return this.resolveProviderCachedSummary(settings, enabledKinds[0]);
  }

  private resolveProviderCachedSummary(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): string {
    const cache = remoteKind === 'aira_cloud'
      ? settings.huaweiCloud.remoteStatusCache
      : (remoteKind === 'huawei_space'
        ? settings.huaweiSpace.remoteStatusCache
        : (remoteKind === 'webdav'
          ? settings.webdav.remoteStatusCache
          : (remoteKind === 'self_hosted' ? (settings.selfHosted?.remoteStatusCache ?? null) : null)));
    if (cache === null || cache.providerKey !== this.resolveRemoteStatusProviderKey(settings, remoteKind)) {
      return '尚未检查';
    }
    return cache.summary;
  }

  private formatBookmarkCounts(folderCount: number, itemCount: number): string {
    return `${Math.max(0, folderCount)} 个文件夹，${Math.max(0, itemCount)} 个书签`;
  }

  private buildBaselineSummary(
    records: AiraSyncBaselineRecord[],
    enabledKinds: AiraSyncRemoteKind[],
    providerIdResolver: SyncAdvancedProviderIdResolver
  ): string {
    if (enabledKinds.length <= 0) {
      return '未启用';
    }
    const parts: string[] = [];
    enabledKinds.forEach((remoteKind: AiraSyncRemoteKind) => {
      const providerId = providerIdResolver(remoteKind);
      const hasBaseline = records.some((record: AiraSyncBaselineRecord) => record.providerId === providerId);
      parts.push(`${this.resolveProviderShortLabel(remoteKind)} ${hasBaseline ? '已建立' : '未建立'}`);
    });
    return parts.join(' / ');
  }

  private buildLastSyncSummary(settings: AiraSyncSettings, enabledKinds: AiraSyncRemoteKind[]): string {
    if (enabledKinds.length <= 0) {
      return '暂无';
    }
    const timestamp = this.resolveProviderLastSuccessAt(settings, enabledKinds[0]);
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '暂无';
  }

  private isRemoteKindEnabled(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): boolean {
    return remoteKind !== 'none' && this.isProviderAvailable(remoteKind) &&
      isAiraSyncProviderEnabled(settings, remoteKind);
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

  private resolveProviderLastSuccessAt(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): number {
    if (remoteKind === 'none') {
      return 0;
    }
    const state = resolveAiraSyncProviderRuntimeState(settings, remoteKind);
    return Math.max(state.bookmark.lastSuccessAt, state.personalization.lastSuccessAt);
  }
}

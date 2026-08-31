import { webview } from '@kit.ArkWeb';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode,
  resolveBrowserDataScopeForPrivacyMode
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  HistoryRepository,
  RecentlyClosedTabRepository
} from '../../data/repositories/BrowserRepositories';
import {
  SiteDataClearResult,
  SiteDataClearSelection,
  SiteDataControlService
} from '../../services/web/SiteDataControlService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import {
  BrowserHttpsFirstNavigationService,
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';

export interface SettingsSiteDataClearBoundary {
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

export interface SettingsSiteDataClearState {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  title: string;
  message: string;
  confirmLabel: string;
}

export type SettingsBrowsingDataClearItemId =
  'history' |
  'recently_closed' |
  'cookies' |
  'cache' |
  'site_storage' |
  'site_permissions';

export type SettingsBrowsingDataClearTimeRangeId =
  'last_hour' |
  'last_day' |
  'last_7_days' |
  'all';

export interface SettingsBrowsingDataClearItemState {
  id: SettingsBrowsingDataClearItemId;
  title: string;
  summary: string;
  isEnabled: boolean;
  defaultSelected: boolean;
}

export interface SettingsBrowsingDataClearTimeRangeState {
  id: SettingsBrowsingDataClearTimeRangeId;
  title: string;
}

export interface SettingsBrowsingDataClearDialogState {
  title: string;
  message: string;
  confirmLabel: string;
  timeRangeTitle: string;
  dataTypesTitle: string;
  showTimeRange: boolean;
  defaultTimeRangeId: SettingsBrowsingDataClearTimeRangeId;
  ranges: SettingsBrowsingDataClearTimeRangeState[];
  items: SettingsBrowsingDataClearItemState[];
}

export interface SettingsBrowsingDataClearRequest {
  rangeId: SettingsBrowsingDataClearTimeRangeId;
  selectedItemIds: SettingsBrowsingDataClearItemId[];
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

interface BrowsingDataTimeRange {
  id: SettingsBrowsingDataClearTimeRangeId;
  startAt: number;
  endAt: number;
}

export class SettingsSiteDataClearCoordinator {
  private siteDataControlService: SiteDataControlService;
  private sitePolicyService?: SitePolicyService;
  private recentlyClosedTabRepository?: RecentlyClosedTabRepository;
  private historyRepository?: HistoryRepository;
  private httpsFirstNavigationService: BrowserHttpsFirstNavigationService;

  constructor(
    preferencesRepository: PreferencesRepository,
    sitePolicyService?: SitePolicyService,
    recentlyClosedTabRepository?: RecentlyClosedTabRepository,
    historyRepository?: HistoryRepository,
    httpsFirstNavigationService: BrowserHttpsFirstNavigationService = sharedBrowserHttpsFirstNavigationService
  ) {
    this.siteDataControlService = new SiteDataControlService(preferencesRepository);
    this.sitePolicyService = sitePolicyService;
    this.recentlyClosedTabRepository = recentlyClosedTabRepository;
    this.historyRepository = historyRepository;
    this.httpsFirstNavigationService = httpsFirstNavigationService;
  }

  buildState(boundary: SettingsSiteDataClearBoundary): SettingsSiteDataClearState {
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    return {
      profileId: normalizeBrowserProfileId(boundary.profileId ?? DEFAULT_BROWSER_PROFILE_ID),
      privacyMode: privacyMode,
      dataScope: dataScope,
      title: dataScope === 'session_ephemeral' ? '清除本次私密数据' : '清除全部浏览数据',
      message: dataScope === 'session_ephemeral'
        ? '清除本次私密数据，不影响常规资料。'
        : '清除数据、Cookie、缓存和站点权限。',
      confirmLabel: '清除'
    };
  }

  buildDialogState(boundary: SettingsSiteDataClearBoundary): SettingsBrowsingDataClearDialogState {
    const state = this.buildState(boundary);
    const isSessionEphemeral = state.dataScope === 'session_ephemeral';
    return {
      title: '清除浏览数据',
      message: isSessionEphemeral
        ? '仅清除本次私密会话数据，不影响常规浏览资料。'
        : '时间范围适用于历史记录和最近关闭；Cookie、缓存、站点存储按系统 Web 能力清除全部。',
      confirmLabel: '清除',
      timeRangeTitle: '时间范围',
      dataTypesTitle: '数据类型',
      showTimeRange: !isSessionEphemeral,
      defaultTimeRangeId: 'all',
      ranges: [
        { id: 'last_hour', title: '最近 1 小时' },
        { id: 'last_day', title: '最近 24 小时' },
        { id: 'last_7_days', title: '最近 7 天' },
        { id: 'all', title: '全部时间' }
      ],
      items: isSessionEphemeral ? this.buildPrivateClearItems() : this.buildPersistentClearItems()
    };
  }

  async clearSelected(request: SettingsBrowsingDataClearRequest): Promise<SiteDataClearResult> {
    if (!this.isBoundaryConsistent(request.privacyMode, request.dataScope)) {
      return {
        hasError: true,
        message: '浏览数据范围不一致，未执行清理。'
      };
    }
    const state = this.buildState({
      profileId: request.profileId,
      privacyMode: request.privacyMode,
      dataScope: request.dataScope
    });
    const selectedItemIds = this.normalizeSelectedItemIds(request.selectedItemIds, state.dataScope);
    if (selectedItemIds.length === 0) {
      return {
        hasError: true,
        message: '请选择要清除的数据。'
      };
    }

    const failureMessages: string[] = [];
    const selectedSet = new Set<SettingsBrowsingDataClearItemId>(selectedItemIds);
    const timeRange = this.buildTimeRange(request.rangeId);

    if (state.dataScope === 'profile_persistent' && selectedSet.has('history')) {
      try {
        if (timeRange.id === 'all') {
          await this.historyRepository?.clearVisits();
        } else {
          await this.historyRepository?.deleteVisitsInRange(timeRange.startAt, timeRange.endAt);
        }
      } catch (error) {
        failureMessages.push(`历史记录：${JSON.stringify(error)}`);
      }
    }

    if (state.dataScope === 'profile_persistent' && selectedSet.has('recently_closed')) {
      try {
        if (timeRange.id === 'all') {
          await this.recentlyClosedTabRepository?.clearRecords(undefined, state.profileId);
        } else {
          await this.recentlyClosedTabRepository?.deleteRecordsInRange(
            timeRange.startAt,
            timeRange.endAt,
            undefined,
            state.profileId
          );
        }
      } catch (error) {
        failureMessages.push(`最近关闭：${JSON.stringify(error)}`);
      }
    }

    const siteSelection = this.buildSiteDataSelection(selectedSet, state.dataScope);
    if (this.hasSiteDataSelection(siteSelection)) {
      const siteResult = await this.siteDataControlService.clearSelectedSiteData(
        siteSelection,
        false,
        undefined as webview.WebviewController | undefined,
        state.profileId,
        state.privacyMode,
        state.dataScope
      );
      if (siteResult.hasError) {
        const siteFailureMessages = siteResult.failureMessages ?? [];
        if (siteFailureMessages.length > 0) {
          siteFailureMessages.forEach((message: string) => failureMessages.push(message));
        } else {
          failureMessages.push(siteResult.message);
        }
      }
    }

    if (state.dataScope === 'session_ephemeral' && selectedSet.has('site_permissions')) {
      const cleanupResult = this.sitePolicyService?.clearSessionSitePermissionSettings(state.profileId);
      if (cleanupResult === undefined) {
        failureMessages.push('临时权限：清除失败');
      }
    }
    if (state.dataScope === 'profile_persistent' && selectedSet.has('site_permissions')) {
      this.sitePolicyService?.clearPermissionSessionGrants({
        profileId: state.profileId,
        dataScope: state.dataScope
      });
    }
    if (selectedSet.has('site_permissions')) {
      try {
        await this.httpsFirstNavigationService.clearSiteDecisions({
          profileId: state.profileId,
          privacyMode: state.privacyMode,
          dataScope: state.dataScope
        });
      } catch (error) {
        failureMessages.push(`HTTP 兼容访问决定：${JSON.stringify(error)}`);
      }
    }

    if (failureMessages.length > 0) {
      return {
        hasError: true,
        message: `部分浏览数据清除失败：${failureMessages.join('；')}`
      };
    }
    return {
      hasError: false,
      message: '所选浏览数据已清除。'
    };
  }

  private buildPersistentClearItems(): SettingsBrowsingDataClearItemState[] {
    return [
      {
        id: 'history',
        title: '历史记录',
        summary: '地址栏建议和历史页面中的访问记录',
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'recently_closed',
        title: '最近关闭',
        summary: '主页和标签页恢复使用的最近关闭记录',
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'cookies',
        title: 'Cookie',
        summary: '网站登录状态和会话 Cookie',
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'cache',
        title: '缓存',
        summary: '网页资源缓存',
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_storage',
        title: '站点存储',
        summary: '网站保存的本地数据',
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_permissions',
        title: '站点权限',
        summary: '已保存的相机、麦克风、位置等权限',
        isEnabled: true,
        defaultSelected: true
      }
    ];
  }

  private buildPrivateClearItems(): SettingsBrowsingDataClearItemState[] {
    return [
      {
        id: 'cookies',
        title: '本次私密 Cookie',
        summary: '清除本次私密会话中的全部 Cookie',
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_storage',
        title: '本次私密站点存储',
        summary: '清除本次私密会话中的站点数据',
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_permissions',
        title: '本次临时权限',
        summary: '清除本次私密会话授权',
        isEnabled: true,
        defaultSelected: true
      }
    ];
  }

  private normalizeSelectedItemIds(
    selectedItemIds: SettingsBrowsingDataClearItemId[],
    dataScope: BrowserDataScope
  ): SettingsBrowsingDataClearItemId[] {
    const allowedIds = new Set<SettingsBrowsingDataClearItemId>(
      (dataScope === 'session_ephemeral' ? this.buildPrivateClearItems() : this.buildPersistentClearItems())
        .map((item: SettingsBrowsingDataClearItemState) => item.id)
    );
    return Array.from(new Set<SettingsBrowsingDataClearItemId>(selectedItemIds))
      .filter((id: SettingsBrowsingDataClearItemId) => allowedIds.has(id));
  }

  private buildSiteDataSelection(
    selectedSet: Set<SettingsBrowsingDataClearItemId>,
    dataScope: BrowserDataScope
  ): SiteDataClearSelection {
    const isSessionEphemeral = dataScope === 'session_ephemeral';
    return {
      clearWebStorage: selectedSet.has('site_storage'),
      clearCookies: selectedSet.has('cookies'),
      clearCache: !isSessionEphemeral && selectedSet.has('cache'),
      clearProfilePermissions: !isSessionEphemeral && selectedSet.has('site_permissions')
    };
  }

  private hasSiteDataSelection(selection: SiteDataClearSelection): boolean {
    return selection.clearWebStorage ||
      selection.clearCookies ||
      selection.clearCache ||
      selection.clearProfilePermissions;
  }

  private buildTimeRange(rangeId: SettingsBrowsingDataClearTimeRangeId): BrowsingDataTimeRange {
    const now = Date.now();
    if (rangeId === 'last_hour') {
      return {
        id: 'last_hour',
        startAt: now - 60 * 60 * 1000,
        endAt: now
      };
    }
    if (rangeId === 'last_day') {
      return {
        id: 'last_day',
        startAt: now - 24 * 60 * 60 * 1000,
        endAt: now
      };
    }
    if (rangeId === 'last_7_days') {
      return {
        id: 'last_7_days',
        startAt: now - 7 * 24 * 60 * 60 * 1000,
        endAt: now
      };
    }
    return {
      id: 'all',
      startAt: 0,
      endAt: now
    };
  }

  private isBoundaryConsistent(
    privacyModeInput?: BrowserSessionPrivacyMode | string,
    dataScopeInput?: BrowserDataScope | string
  ): boolean {
    const privacyMode = normalizeBrowserSessionPrivacyMode(privacyModeInput);
    const dataScope = normalizeBrowserDataScope(dataScopeInput, privacyMode);
    return dataScope === resolveBrowserDataScopeForPrivacyMode(privacyMode);
  }
}

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
import { RegularSessionCookieSnapshotRepository } from '../../data/browser/RegularSessionCookieSnapshotRepository';
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
import { resolveAppResourceText } from '../resources/AppResourceText';

export interface SettingsSiteDataClearBoundary {
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

export interface SettingsSiteDataClearState {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  title: ResourceStr;
  message: ResourceStr;
  confirmLabel: ResourceStr;
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
  title: ResourceStr;
  summary: ResourceStr;
  isEnabled: boolean;
  defaultSelected: boolean;
}

export interface SettingsBrowsingDataClearTimeRangeState {
  id: SettingsBrowsingDataClearTimeRangeId;
  title: ResourceStr;
}

export interface SettingsBrowsingDataClearDialogState {
  title: ResourceStr;
  message: ResourceStr;
  confirmLabel: ResourceStr;
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
    this.siteDataControlService = new SiteDataControlService(
      preferencesRepository,
      undefined,
      new RegularSessionCookieSnapshotRepository()
    );
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
      title: dataScope === 'session_ephemeral'
        ? $r('app.string.settings_privacy_protection_clear_private')
        : $r('app.string.settings_privacy_protection_clear_all_title'),
      message: dataScope === 'session_ephemeral'
        ? $r('app.string.settings_privacy_protection_clear_private_message')
        : $r('app.string.settings_privacy_protection_clear_all_message'),
      confirmLabel: $r('app.string.settings_privacy_protection_clear_confirm')
    };
  }

  buildDialogState(boundary: SettingsSiteDataClearBoundary): SettingsBrowsingDataClearDialogState {
    const state = this.buildState(boundary);
    const isSessionEphemeral = state.dataScope === 'session_ephemeral';
    return {
      title: $r('app.string.settings_privacy_protection_clear_dialog_title'),
      message: isSessionEphemeral
        ? $r('app.string.settings_privacy_protection_clear_dialog_private_message')
        : $r('app.string.settings_privacy_protection_clear_dialog_message'),
      confirmLabel: $r('app.string.settings_privacy_protection_clear_confirm'),
      timeRangeTitle: '时间范围',
      dataTypesTitle: '数据类型',
      showTimeRange: !isSessionEphemeral,
      defaultTimeRangeId: 'all',
      ranges: [
        { id: 'last_hour', title: $r('app.string.settings_privacy_protection_range_last_hour') },
        { id: 'last_day', title: $r('app.string.settings_privacy_protection_range_last_day') },
        { id: 'last_7_days', title: $r('app.string.settings_privacy_protection_range_last_7_days') },
        { id: 'all', title: $r('app.string.settings_privacy_protection_range_all') }
      ],
      items: isSessionEphemeral ? this.buildPrivateClearItems() : this.buildPersistentClearItems()
    };
  }

  async clearSelected(request: SettingsBrowsingDataClearRequest): Promise<SiteDataClearResult> {
    if (!this.isBoundaryConsistent(request.privacyMode, request.dataScope)) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.settings_privacy_protection_clear_range_mismatch'))
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
        message: resolveAppResourceText($r('app.string.settings_privacy_protection_clear_nothing_selected'))
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
        failureMessages.push(resolveAppResourceText(
          $r('app.string.settings_privacy_protection_item_history')) + '：' + JSON.stringify(error));
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
        failureMessages.push(resolveAppResourceText(
          $r('app.string.settings_privacy_protection_item_recently_closed')) + '：' + JSON.stringify(error));
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
        failureMessages.push(resolveAppResourceText(
          $r('app.string.settings_privacy_protection_clear_temp_permission_failed')));
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
        failureMessages.push(resolveAppResourceText(
          $r('app.string.settings_privacy_protection_clear_https_label')) + '：' + JSON.stringify(error));
      }
    }

    if (failureMessages.length > 0) {
      return {
        hasError: true,
        message: resolveAppResourceText(
          $r('app.string.settings_privacy_protection_clear_partial_failed'),
          failureMessages.join('；')
        )
      };
    }
    return {
      hasError: false,
      message: resolveAppResourceText($r('app.string.settings_privacy_protection_clear_done'))
    };
  }

  private buildPersistentClearItems(): SettingsBrowsingDataClearItemState[] {
    return [
      {
        id: 'history',
        title: $r('app.string.settings_privacy_protection_item_history'),
        summary: $r('app.string.settings_privacy_protection_item_history_summary'),
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'recently_closed',
        title: $r('app.string.settings_privacy_protection_item_recently_closed'),
        summary: $r('app.string.settings_privacy_protection_item_recently_closed_summary'),
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'cookies',
        title: $r('app.string.settings_privacy_protection_item_cookies'),
        summary: $r('app.string.settings_privacy_protection_item_cookies_summary'),
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'cache',
        title: $r('app.string.settings_privacy_protection_item_cache'),
        summary: $r('app.string.settings_privacy_protection_item_cache_summary'),
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_storage',
        title: $r('app.string.settings_privacy_protection_item_site_storage'),
        summary: $r('app.string.settings_privacy_protection_item_site_storage_summary'),
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_permissions',
        title: $r('app.string.settings_privacy_protection_item_site_permissions'),
        summary: $r('app.string.settings_privacy_protection_item_site_permissions_summary'),
        isEnabled: true,
        defaultSelected: true
      }
    ];
  }

  private buildPrivateClearItems(): SettingsBrowsingDataClearItemState[] {
    return [
      {
        id: 'cookies',
        title: $r('app.string.settings_privacy_protection_item_private_cookies'),
        summary: $r('app.string.settings_privacy_protection_item_private_cookies_summary'),
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_storage',
        title: $r('app.string.settings_privacy_protection_item_private_storage'),
        summary: $r('app.string.settings_privacy_protection_item_private_storage_summary'),
        isEnabled: true,
        defaultSelected: true
      },
      {
        id: 'site_permissions',
        title: $r('app.string.settings_privacy_protection_item_private_permissions'),
        summary: $r('app.string.settings_privacy_protection_item_private_permissions_summary'),
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

import {
  BrowserDataScope,
  BrowserProfileId,
  TabRestoreReason,
  TabRuntimeState,
  WebSessionRestoreType,
  buildBrowserDataBoundary,
  buildBrowserDataBoundaryFromTabLike
} from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserDownloadNavigationStateCoordinator } from './BrowserDownloadNavigationStateCoordinator';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { SiteIconService } from '../../services/siteicons/SiteIconService';

export interface BrowserRecentlyClosedTabRecord {
  id: string;
  originalTabId: string;
  closedAt: number;
  windowId: string;
  siteIconUri?: string;
  tab: BrowserTabState;
}

interface BrowserRecentlyClosedTabsUpdateResult {
  records: BrowserRecentlyClosedTabRecord[];
  recorded: boolean;
  reason: string;
  summaryLine: string;
}

interface BrowserRecentlyClosedIconUpdateResult {
  records: BrowserRecentlyClosedTabRecord[];
  updated: boolean;
}

export interface BrowserRestoreRecentlyClosedTabResult {
  tabs: BrowserTabState[];
  activeTabId: string;
  restored: boolean;
  restoredTabId: string;
  remainingRecords: BrowserRecentlyClosedTabRecord[];
  summaryLine: string;
}

const DEFAULT_RECENTLY_CLOSED_LIMIT = 12;
export const DEFAULT_RECENTLY_CLOSED_PERSISTED_LIMIT: number = 25;
const DEFAULT_BROWSER_PROFILE_ID: BrowserProfileId = 'profile-main';
const TRANSIENT_LOADING_TITLE = '页面加载中';

export class BrowserRecentlyClosedTabsService {
  private downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private siteIconService: SiteIconService = new SiteIconService();

  constructor(
    downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService()
  ) {
    this.downloadNavigationStateCoordinator = downloadNavigationStateCoordinator;
    this.privacyEffectPolicy = privacyEffectPolicy;
  }

  recordClosedTab(
    records: BrowserRecentlyClosedTabRecord[],
    tab: BrowserTabState | undefined,
    windowId: string = '',
    limit: number = DEFAULT_RECENTLY_CLOSED_PERSISTED_LIMIT,
    siteIconUri: string = ''
  ): BrowserRecentlyClosedTabsUpdateResult {
    const closedAt = Date.now();
    if (tab === undefined) {
      return this.buildUpdateResult(records, false, 'tab_missing', closedAt);
    }
    if (!this.shouldRecordClosedTab(tab)) {
      return this.buildUpdateResult(records, false, this.resolveSkipReason(tab), closedAt);
    }
    const nextRecord: BrowserRecentlyClosedTabRecord = {
      id: `closed-${tab.id}-${closedAt}`,
      originalTabId: tab.id,
      closedAt: closedAt,
      windowId: windowId.trim(),
      siteIconUri: this.resolveSiteIconUri(tab, siteIconUri),
      tab: this.cloneClosedTab(tab, 'suspended', tab.id)
    };
    const retainedRecords = records
      .concat([nextRecord])
      .sort((left: BrowserRecentlyClosedTabRecord, right: BrowserRecentlyClosedTabRecord) => {
        return this.compareNewestFirst(left, right);
      })
      .slice(0, this.normalizeLimit(limit));
    return this.buildUpdateResult(retainedRecords, true, 'recorded', closedAt);
  }

  updateRecordSiteIcon(
    records: BrowserRecentlyClosedTabRecord[],
    recordId: string,
    siteIconUri: string
  ): BrowserRecentlyClosedIconUpdateResult {
    const normalizedIconUri = this.normalizeSiteIconUri(siteIconUri);
    const normalizedRecordId = recordId.trim();
    if (normalizedRecordId.length === 0 || normalizedIconUri === undefined) {
      return this.buildIconUpdateResult(records, false);
    }
    const existingRecord = records.find((record: BrowserRecentlyClosedTabRecord) => record.id === normalizedRecordId);
    if (existingRecord === undefined) {
      return this.buildIconUpdateResult(records, false);
    }
    const existingIconUri = this.normalizeSiteIconUri(existingRecord.siteIconUri ?? '');
    if (existingIconUri === normalizedIconUri) {
      return this.buildIconUpdateResult(records, false);
    }
    if (existingIconUri !== undefined) {
      return this.buildIconUpdateResult(records, false);
    }
    const nextRecords = records.map((record: BrowserRecentlyClosedTabRecord): BrowserRecentlyClosedTabRecord => {
      if (record.id !== normalizedRecordId) {
        return record;
      }
      return {
        id: record.id,
        originalTabId: record.originalTabId,
        closedAt: record.closedAt,
        windowId: record.windowId,
        siteIconUri: normalizedIconUri,
        tab: record.tab
      };
    });
    return this.buildIconUpdateResult(nextRecords, true);
  }

  restoreLatest(
    tabs: BrowserTabState[],
    activeTabId: string,
    records: BrowserRecentlyClosedTabRecord[]
  ): BrowserRestoreRecentlyClosedTabResult {
    const restorableRecords = this.filterRestorableRecords(records);
    const latest = restorableRecords.slice().sort((left: BrowserRecentlyClosedTabRecord, right: BrowserRecentlyClosedTabRecord) => {
      return this.compareNewestFirst(left, right);
    })[0];
    if (latest === undefined) {
      return {
        tabs: tabs.slice(),
        activeTabId: activeTabId,
        restored: false,
        restoredTabId: '',
        remainingRecords: restorableRecords,
        summaryLine: 'recentlyClosedRestore restored=0 reason=empty'
      };
    }
    return this.restoreByRecordId(tabs, activeTabId, restorableRecords, latest.id);
  }

  restoreByRecordId(
    tabs: BrowserTabState[],
    activeTabId: string,
    records: BrowserRecentlyClosedTabRecord[],
    recordId: string
  ): BrowserRestoreRecentlyClosedTabResult {
    const restorableRecords = this.filterRestorableRecords(records);
    const record = restorableRecords.find((item: BrowserRecentlyClosedTabRecord) => item.id === recordId);
    if (record === undefined) {
      return {
        tabs: tabs.slice(),
        activeTabId: activeTabId,
        restored: false,
        restoredTabId: '',
        remainingRecords: restorableRecords,
        summaryLine: `recentlyClosedRestore restored=0 reason=missing record=${recordId}`
      };
    }
    const restoredTab = this.cloneClosedTab(
      record.tab,
      this.resolveRestoredRuntimeState(record.tab),
      this.buildRestoredTabId(record, tabs)
    );
    const nextTabs = this.deactivateCurrentActiveTab(tabs, activeTabId).concat([restoredTab]);
    return {
      tabs: nextTabs,
      activeTabId: restoredTab.id,
      restored: true,
      restoredTabId: restoredTab.id,
      remainingRecords: restorableRecords.filter((item: BrowserRecentlyClosedTabRecord) => item.id !== record.id),
      summaryLine: `recentlyClosedRestore restored=1 tab=${restoredTab.id} original=${record.originalTabId}`
    };
  }

  private shouldRecordClosedTab(tab: BrowserTabState): boolean {
    const boundary = buildBrowserDataBoundaryFromTabLike({
      id: tab.id,
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    });
    return !tab.isHome &&
      this.privacyEffectPolicy.shouldWritePersistentDataForBoundary('recently_closed_tab', boundary) &&
      this.resolveRestorableUrl(tab).length > 0;
  }

  private resolveSkipReason(tab: BrowserTabState): string {
    if (tab.isHome) {
      return 'home_tab';
    }
    const policy = this.privacyEffectPolicy.resolveDataPolicyForBoundary('recently_closed_tab', buildBrowserDataBoundary({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.id
    }));
    if (!policy.persistentWriteAllowed) {
      return `data_scope_${this.formatDataScope(policy.boundary.dataScope)}`;
    }
    return 'empty_url';
  }

  private filterRestorableRecords(records: BrowserRecentlyClosedTabRecord[]): BrowserRecentlyClosedTabRecord[] {
    return records.filter((record: BrowserRecentlyClosedTabRecord) => {
      return this.shouldRecordClosedTab(record.tab);
    });
  }

  private buildUpdateResult(
    records: BrowserRecentlyClosedTabRecord[],
    recorded: boolean,
    reason: string,
    timestamp: number
  ): BrowserRecentlyClosedTabsUpdateResult {
    return {
      records: records.slice(),
      recorded: recorded,
      reason: reason,
      summaryLine: `recentlyClosedRecord recorded=${recorded ? 1 : 0} reason=${reason} total=${records.length}` +
        ` icons=${this.countRecordsWithSiteIcon(records)} latestIcon=${this.hasLatestRecordSiteIcon(records) ? 1 : 0}` +
        ` at=${timestamp}`
    };
  }

  private buildIconUpdateResult(
    records: BrowserRecentlyClosedTabRecord[],
    updated: boolean
  ): BrowserRecentlyClosedIconUpdateResult {
    return {
      records: records.slice(),
      updated: updated
    };
  }

  private countRecordsWithSiteIcon(records: BrowserRecentlyClosedTabRecord[]): number {
    return records.filter((record: BrowserRecentlyClosedTabRecord) => {
      return (record.siteIconUri ?? '').trim().length > 0;
    }).length;
  }

  private hasLatestRecordSiteIcon(records: BrowserRecentlyClosedTabRecord[]): boolean {
    if (records.length <= 0) {
      return false;
    }
    return (records[0].siteIconUri ?? '').trim().length > 0;
  }

  private cloneClosedTab(tab: BrowserTabState, runtimeState: TabRuntimeState, tabId: string): BrowserTabState {
    const url = this.resolveRestorableUrl(tab);
    const restorableTitle = this.resolveRestorableTitle(tab, url);
    return {
      id: tabId,
      profileId: tab.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      title: restorableTitle,
      url: url,
      isHome: false,
      lastActiveAt: Date.now(),
      pendingUrl: url,
      navigationHistory: this.resolveNavigationHistory(tab, url),
      navigationIndex: this.resolveNavigationIndex(tab, url),
      runtimeState: runtimeState,
      lastError: '',
      lastRestoreReason: this.resolveRestoreReason(tab.lastRestoreReason, runtimeState),
      lastDiscardReason: tab.lastDiscardReason,
      lastCrashReason: '',
      lastLoadedAt: tab.lastLoadedAt,
      webStatePath: tab.webStatePath,
      webStateUpdatedAt: tab.webStateUpdatedAt,
      scrollOffsetY: tab.scrollOffsetY,
      lastGoodUrl: url,
      lastGoodTitle: restorableTitle,
      lastRestorableUrl: url,
      lastRestorableTitle: restorableTitle,
      lastRestoreType: this.resolveRestoreType(tab.webStatePath),
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      launchContext: {
        sourceType: tab.launchContext.sourceType,
        sourceId: tab.launchContext.sourceId,
        sourceUrl: tab.launchContext.sourceUrl,
        key: tab.launchContext.key
      },
      openerTabId: tab.openerTabId,
      openSource: tab.openSource,
      openedByNewWindow: tab.openedByNewWindow,
      pinned: tab.pinned,
      muted: tab.muted,
      audible: false
    };
  }

  private resolveNavigationHistory(tab: BrowserTabState, url: string): string[] {
    const history = tab.navigationHistory
      .filter((item: string) => {
        return item.trim().length > 0 &&
          !this.downloadNavigationStateCoordinator.shouldTreatAsNonRestorableNavigation(item);
      })
      .slice();
    return history.length > 0 ? history : [url];
  }

  private resolveNavigationIndex(tab: BrowserTabState, url: string): number {
    const history = this.resolveNavigationHistory(tab, url);
    if (tab.navigationIndex >= 0 && tab.navigationIndex < history.length) {
      return tab.navigationIndex;
    }
    return history.length - 1;
  }

  private resolveRestoredRuntimeState(tab: BrowserTabState): TabRuntimeState {
    return tab.webStatePath.length > 0 ? 'restoring' : 'loading';
  }

  private resolveRestoreReason(currentReason: TabRestoreReason | '', runtimeState: TabRuntimeState): TabRestoreReason | '' {
    if (runtimeState === 'active' || runtimeState === 'loading' || runtimeState === 'restoring') {
      return 'tab_switch';
    }
    return currentReason;
  }

  private resolveRestoreType(snapshotPath: string): WebSessionRestoreType {
    return snapshotPath.length > 0 ? 'snapshot_restore' : 'reload';
  }

  private resolveRestorableUrl(tab: BrowserTabState): string {
    return this.downloadNavigationStateCoordinator.resolveRestorableNavigation(tab).url;
  }

  private resolveRestorableTitle(tab: BrowserTabState, url: string): string {
    const resolution = this.downloadNavigationStateCoordinator.resolveRestorableNavigation(tab);
    const title = this.normalizePersistableTitle(resolution.title);
    if (title.length > 0) {
      return title;
    }
    const lastRestorableTitle = this.resolveMatchingTitle(tab.lastRestorableUrl, tab.lastRestorableTitle, url);
    if (lastRestorableTitle.length > 0) {
      return lastRestorableTitle;
    }
    const lastGoodTitle = this.resolveMatchingTitle(tab.lastGoodUrl, tab.lastGoodTitle, url);
    if (lastGoodTitle.length > 0) {
      return lastGoodTitle;
    }
    const fallbackTitle = this.normalizePersistableTitle(tab.title);
    return fallbackTitle.length > 0 ? fallbackTitle : url;
  }

  private resolveMatchingTitle(candidateUrl: string, candidateTitle: string, targetUrl: string): string {
    if (this.normalizeNavigationTarget(candidateUrl) !== this.normalizeNavigationTarget(targetUrl)) {
      return '';
    }
    return this.normalizePersistableTitle(candidateTitle);
  }

  private normalizePersistableTitle(title: string): string {
    const trimmed = title.trim();
    if (trimmed.length <= 0 || trimmed === TRANSIENT_LOADING_TITLE) {
      return '';
    }
    return trimmed;
  }

  private normalizeNavigationTarget(url: string): string {
    const trimmed = url.trim().toLowerCase();
    if (trimmed.length <= 0) {
      return '';
    }
    const hashIndex = trimmed.indexOf('#');
    const withoutHash = hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
    return withoutHash.endsWith('/') ? withoutHash.substring(0, withoutHash.length - 1) : withoutHash;
  }

  private deactivateCurrentActiveTab(tabs: BrowserTabState[], activeTabId: string): BrowserTabState[] {
    return tabs.map((tab: BrowserTabState) => {
      if (tab.id !== activeTabId) {
        return tab;
      }
      return {
        id: tab.id,
        profileId: tab.profileId,
        title: tab.title,
        url: tab.url,
        isHome: tab.isHome,
        lastActiveAt: Date.now(),
        pendingUrl: tab.pendingUrl,
        navigationHistory: tab.navigationHistory.slice(),
        navigationIndex: tab.navigationIndex,
        runtimeState: tab.isHome ? 'background' : 'background-hot',
        lastError: tab.lastError,
        lastRestoreReason: tab.lastRestoreReason,
        lastDiscardReason: tab.lastDiscardReason,
        lastCrashReason: tab.lastCrashReason,
        lastLoadedAt: tab.lastLoadedAt,
        webStatePath: tab.webStatePath,
        webStateUpdatedAt: tab.webStateUpdatedAt,
        scrollOffsetY: tab.scrollOffsetY,
        lastGoodUrl: tab.lastGoodUrl,
        lastGoodTitle: tab.lastGoodTitle,
        lastRestorableUrl: tab.lastRestorableUrl,
        lastRestorableTitle: tab.lastRestorableTitle,
        lastRestoreType: tab.lastRestoreType,
        privacyMode: tab.privacyMode,
        dataScope: tab.dataScope,
        launchContext: {
          sourceType: tab.launchContext.sourceType,
          sourceId: tab.launchContext.sourceId,
          sourceUrl: tab.launchContext.sourceUrl,
          key: tab.launchContext.key
        },
        openerTabId: tab.openerTabId,
        openSource: tab.openSource,
        openedByNewWindow: tab.openedByNewWindow,
        pinned: tab.pinned,
        muted: tab.muted,
        audible: tab.audible
      };
    });
  }

  private buildRestoredTabId(record: BrowserRecentlyClosedTabRecord, tabs: BrowserTabState[]): string {
    const baseId = `${record.originalTabId}-restored`;
    if (!tabs.some((tab: BrowserTabState) => tab.id === baseId)) {
      return baseId;
    }
    return `${baseId}-${Date.now()}`;
  }

  private normalizeLimit(limit: number): number {
    return Math.max(1, Math.min(50, Math.round(limit)));
  }

  private normalizeSiteIconUri(siteIconUri: string): string | undefined {
    const normalized = siteIconUri.trim();
    return normalized.length > 0 ? normalized : undefined;
  }

  private resolveSiteIconUri(tab: BrowserTabState, preferredSiteIconUri: string): string | undefined {
    const normalizedPreferred = this.normalizeSiteIconUri(preferredSiteIconUri);
    if (normalizedPreferred !== undefined) {
      return normalizedPreferred;
    }
    const urlCandidates = [
      this.resolveRestorableUrl(tab),
      tab.url,
      tab.lastGoodUrl,
      tab.pendingUrl
    ];
    for (let index = 0; index < urlCandidates.length; index += 1) {
      const uri = this.siteIconService.peekUri(urlCandidates[index]);
      if (uri.length > 0) {
        return uri;
      }
    }
    return undefined;
  }

  private compareNewestFirst(left: BrowserRecentlyClosedTabRecord, right: BrowserRecentlyClosedTabRecord): number {
    if (right.closedAt !== left.closedAt) {
      return right.closedAt - left.closedAt;
    }
    return right.id.localeCompare(left.id);
  }

  private formatDataScope(dataScope: BrowserDataScope): string {
    return dataScope === 'session_ephemeral' ? 'session_ephemeral' : 'profile_persistent';
  }
}

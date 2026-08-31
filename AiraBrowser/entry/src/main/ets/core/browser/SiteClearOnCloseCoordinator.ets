import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  TabRecord
} from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserRecentlyClosedApplicationCoordinator } from './BrowserRecentlyClosedApplicationCoordinator';
import {
  SiteClearOnCloseExitResult,
  SiteClearOnCloseFilterResult,
  SiteClearOnCloseLifecycleService,
  SiteClearOnCloseRecordsCleanupResult
} from '../../services/web/SiteClearOnCloseLifecycleService';

export interface SiteClearOnCloseCoordinatorHost {
  deleteHistoryByHost: (host: string) => Promise<number>;
  invalidateHistoryCaches: () => void;
  persistPendingRecords: (records: TabRecord[]) => Promise<void>;
}

export class SiteClearOnCloseCoordinator {
  private lifecycleService: SiteClearOnCloseLifecycleService;
  private recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;

  constructor(
    lifecycleService: SiteClearOnCloseLifecycleService,
    recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator
  ) {
    this.lifecycleService = lifecycleService;
    this.recentlyClosedApplicationCoordinator = recentlyClosedApplicationCoordinator;
  }

  shouldSkipHistoryVisit(
    url: string,
    profileId: BrowserProfileId,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): boolean {
    return this.lifecycleService.shouldSkipHistoryVisit(url, profileId, privacyMode, dataScope);
  }

  shouldSkipRecentlyClosed(tab: BrowserTabState | undefined): boolean {
    return this.lifecycleService.shouldSkipRecentlyClosed(tab);
  }

  handleExplicitSiteExit(
    tab: BrowserTabState | undefined,
    host: SiteClearOnCloseCoordinatorHost
  ): SiteClearOnCloseExitResult {
    const result = this.lifecycleService.handleExplicitSiteExit(tab);
    if (!result.matched || result.match === undefined || result.clearResult === undefined) {
      return result;
    }
    this.deleteHistoryAndRecentlyClosedForHost(result.match.host, host);
    return result;
  }

  filterPersistableTabRecords(records: TabRecord[]): SiteClearOnCloseFilterResult {
    return this.lifecycleService.filterPersistableTabRecords(records);
  }

  persistPendingRecords(
    records: TabRecord[],
    host: SiteClearOnCloseCoordinatorHost
  ): void {
    void host.persistPendingRecords(records).catch((_error: Error) => {});
  }

  cleanupRecordsForStartup(
    records: TabRecord[],
    host: SiteClearOnCloseCoordinatorHost
  ): SiteClearOnCloseRecordsCleanupResult {
    const cleanupResult = this.lifecycleService.cleanupMatchedRecords(records);
    if (cleanupResult.matchedCount <= 0) {
      return cleanupResult;
    }
    cleanupResult.hosts.forEach((hostName: string) => {
      this.deleteHistoryAndRecentlyClosedForHost(hostName, host);
    });
    return cleanupResult;
  }

  private deleteHistoryAndRecentlyClosedForHost(
    targetHost: string,
    host: SiteClearOnCloseCoordinatorHost
  ): void {
    this.deleteHistoryForHost(targetHost, host);
    this.deleteRecentlyClosedForHost(targetHost);
  }

  private deleteHistoryForHost(
    targetHost: string,
    host: SiteClearOnCloseCoordinatorHost
  ): void {
    if (targetHost.length === 0) {
      return;
    }
    host.deleteHistoryByHost(targetHost)
      .then((removed: number) => {
        if (removed > 0) {
          host.invalidateHistoryCaches();
        }
      })
      .catch((_error: Error) => {});
  }

  private deleteRecentlyClosedForHost(
    targetHost: string
  ): void {
    if (targetHost.length === 0) {
      return;
    }
    this.recentlyClosedApplicationCoordinator.removeRecordsForHost(targetHost);
  }
}

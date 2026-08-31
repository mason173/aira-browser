import {
  BrowserProfileId,
  TabRecord
} from '../../common/models/BrowserModels';
import {
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import { DocumentViewerService } from '../../services/viewer/DocumentViewerService';
import {
  sharedPreferencesRepository,
  sharedTabSessionRepository
} from '../../app/bootstrap/BrowserAppRuntime';
import { BrowserTabSessionRuntime } from '../../app/runtime/BrowserTabSessionRuntime';
import { resolveBrowserTabSessionProfileId } from '../../app/runtime/BrowserWindowRuntime';
import {
  BrowserDocumentViewerSessionFilterResult,
  BrowserTabSessionRecordFilterCoordinator
} from './BrowserTabSessionRecordFilterCoordinator';
import { BrowserTabSessionRestoreService } from './BrowserTabSessionRestoreService';
import { BrowserDownloadNavigationStateCoordinator } from './BrowserDownloadNavigationStateCoordinator';
import {
  SiteClearOnCloseCoordinator,
  SiteClearOnCloseCoordinatorHost
} from './SiteClearOnCloseCoordinator';
import {
  sharedCrossDeviceTabPresenceCoordinator
} from '../deviceTabs/CrossDeviceTabPresenceCoordinator';

export interface BrowserTabSessionPersistenceDependencies {
  tabManager: BrowserTabManagerPort;
  documentViewerService: DocumentViewerService;
  downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  siteClearOnCloseCoordinator: SiteClearOnCloseCoordinator;
  siteClearOnCloseHost: SiteClearOnCloseCoordinatorHost;
}

export interface BrowserTabSessionPersistenceHost {
  isRestoringTabs: () => boolean;
  getTabs: () => BrowserTabState[];
  getActiveTabId: () => string;
  getCurrentWindowId: () => string;
  getCurrentTabSessionProfileId: () => BrowserProfileId;
}

export class BrowserTabSessionPersistenceCoordinator {
  private readonly dependencies: BrowserTabSessionPersistenceDependencies;
  private readonly host: BrowserTabSessionPersistenceHost;
  private restoreService: BrowserTabSessionRestoreService = new BrowserTabSessionRestoreService();
  private recordFilterCoordinator: BrowserTabSessionRecordFilterCoordinator =
    new BrowserTabSessionRecordFilterCoordinator();

  constructor(
    dependencies: BrowserTabSessionPersistenceDependencies,
    host: BrowserTabSessionPersistenceHost
  ) {
    this.dependencies = dependencies;
    this.host = host;
  }

  persist(): void {
    void this.persistAndWait().catch((_error: Error) => {
    });
  }

  async persistAndWait(): Promise<void> {
    const host = this.host;
    if (host.isRestoringTabs()) {
      return;
    }
    const activeTabId = host.getActiveTabId();
    const records = this.dependencies.tabManager.serializeTabs(host.getTabs(), activeTabId)
      .map((record: TabRecord): TabRecord => {
        return this.dependencies.downloadNavigationStateCoordinator.sanitizePersistedRecord(record).record;
      });
    const siteClearFilter = this.dependencies.siteClearOnCloseCoordinator.filterPersistableTabRecords(records);
    this.dependencies.siteClearOnCloseCoordinator.persistPendingRecords(
      siteClearFilter.removedRecords,
      this.dependencies.siteClearOnCloseHost
    );
    const persistableRecords = this.filterDocumentViewerRecords(siteClearFilter.records);
    sharedCrossDeviceTabPresenceCoordinator.reconcileWindowRecords(
      host.getCurrentWindowId(),
      persistableRecords
    );
    const generalSettings = sharedPreferencesRepository.getPreferences().general;
    const tabSessionOptions = this.restoreService.buildOptions(
      generalSettings.tabAutoClosePolicy,
      generalSettings.privateTabRestorePolicy
    );
    const persistencePreparation = this.restoreService.prepareRecordsForPersistence(
      persistableRecords,
      tabSessionOptions
    );
    const tabSessionProfileId = host.getCurrentTabSessionProfileId();
    BrowserTabSessionRuntime.remember(
      host.getCurrentWindowId(),
      tabSessionProfileId,
      persistencePreparation.records
    );
    const recordsByProfileId: Record<string, TabRecord[]> = {};
    persistencePreparation.records.forEach((record: TabRecord) => {
      const profileId = resolveBrowserTabSessionProfileId(record.profileId);
      const scopedRecords = recordsByProfileId[profileId] ?? [];
      scopedRecords.push(record);
      recordsByProfileId[profileId] = scopedRecords;
    });
    if (recordsByProfileId[tabSessionProfileId] === undefined) {
      recordsByProfileId[tabSessionProfileId] = [];
    }
    const replaceOperations = Object.keys(recordsByProfileId).map((profileId: string) => {
      return sharedTabSessionRepository.replaceTabs(recordsByProfileId[profileId], host.getCurrentWindowId(), profileId, {
        allowPrivateTabs: tabSessionOptions.persistPrivateTabs
      });
    });
    await Promise.all(replaceOperations);
  }

  private filterDocumentViewerRecords(records: TabRecord[]): TabRecord[] {
    const host = this.host;
    const result: BrowserDocumentViewerSessionFilterResult =
      this.recordFilterCoordinator.filterDocumentViewerRecords(
        records,
        this.dependencies.documentViewerService,
        this.dependencies.tabManager,
        host.getCurrentTabSessionProfileId()
      );
    return result.records;
  }
}

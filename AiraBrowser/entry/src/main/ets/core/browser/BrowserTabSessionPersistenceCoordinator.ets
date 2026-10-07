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
import { AiraTabSessionProbe } from '../../common/debug/AiraTabSessionProbe';

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
  private persistQueue: Promise<void> = Promise.resolve();

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
    const operation = this.persistQueue.then(() => this.persistLatestSnapshot());
    // Keep the queue usable after an individual write fails. A later lifecycle
    // callback must still be able to flush the current tab list.
    this.persistQueue = operation.then(() => undefined, () => undefined);
    return operation;
  }

  private async persistLatestSnapshot(): Promise<void> {
    const host = this.host;
    if (host.isRestoringTabs()) {
      const skippedTabs = host.getTabs();
      AiraTabSessionProbe.logPersistSkip(
        host.getCurrentWindowId(),
        `is_restoring_tabs tabs=${skippedTabs.length} active=${host.getActiveTabId().length > 0 ? 1 : 0}`
      );
      return;
    }
    const currentWindowId = host.getCurrentWindowId();
    const activeTabId = host.getActiveTabId();
    const tabs = host.getTabs();
    const records = this.dependencies.tabManager.serializeTabs(tabs, activeTabId)
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
      currentWindowId,
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
    AiraTabSessionProbe.logPersistBegin(
      currentWindowId,
      tabSessionProfileId,
      tabs.length,
      records.length,
      persistencePreparation.droppedEphemeralCount,
      persistencePreparation.droppedAutoClosedCount,
      tabSessionOptions.persistPrivateTabs === true
    );
    if (persistencePreparation.records.length === 0 && tabs.length > 0) {
      AiraTabSessionProbe.logPersistSkip(
        currentWindowId,
        `all_records_dropped tabs=${tabs.length} ephemeral=${persistencePreparation.droppedEphemeralCount} ` +
          `autoclose=${persistencePreparation.droppedAutoClosedCount}`
      );
    }
    // Fail closed on an empty write that no policy explains. The shell can still hold tabs after
    // its window session is torn down, at which point the injected tab manager serializes to an
    // empty list (its binding is disconnected) even though `tabs` is non-empty. Writing that empty
    // set would delete the persisted tabs, so an unexplained zero is never a valid snapshot to
    // save. A policy-driven empty write (auto-close / ephemeral drop, e.g. 'on_app_exit') still
    // falls through, because those tabs are meant to be gone.
    const policyDroppedCount = persistencePreparation.droppedEphemeralCount +
      persistencePreparation.droppedAutoClosedCount;
    if (persistencePreparation.records.length === 0 && policyDroppedCount === 0) {
      AiraTabSessionProbe.logPersistSkip(
        currentWindowId,
        `unexplained_empty_write tabs=${tabs.length} serialized=${records.length}`
      );
      return;
    }
    BrowserTabSessionRuntime.remember(
      currentWindowId,
      tabSessionProfileId,
      persistencePreparation.records
    );
    AiraTabSessionProbe.logRuntimeSnapshot(
      'persist_remember',
      currentWindowId,
      tabSessionProfileId,
      persistencePreparation.records.length
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
      const submittedRecords = recordsByProfileId[profileId];
      return sharedTabSessionRepository.replaceTabs(submittedRecords, currentWindowId, profileId, {
        allowPrivateTabs: tabSessionOptions.persistPrivateTabs
      })
        .then((written: TabRecord[]) => {
          AiraTabSessionProbe.logPersistWrite(profileId, submittedRecords.length, written.length, 'ok', '');
        })
        .catch((error: Error) => {
          AiraTabSessionProbe.logPersistWrite(
            profileId,
            submittedRecords.length,
            0,
            'failed',
            `error=${AiraTabSessionProbe.describeError(error)}`
          );
          throw error;
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

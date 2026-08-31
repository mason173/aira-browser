import {
  BrowserProfileId,
  TabRecord
} from '../../common/models/BrowserModels';
import {
  BrowserCreateTabOptions,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import { DocumentViewerService } from '../../services/viewer/DocumentViewerService';

export interface BrowserDocumentViewerSessionFilterResult {
  records: TabRecord[];
  removedCount: number;
}

export class BrowserTabSessionRecordFilterCoordinator {
  filterDocumentViewerRecords(
    records: TabRecord[],
    documentViewerService: DocumentViewerService,
    tabManager: BrowserTabManagerPort,
    emptyStateOptions: BrowserCreateTabOptions | BrowserProfileId
  ): BrowserDocumentViewerSessionFilterResult {
    const filteredRecords = records.filter((record: TabRecord) => {
      return !documentViewerService.isDocumentViewerTabRecord(record);
    });
    const removedCount = records.length - filteredRecords.length;
    if (records.length > 0 && filteredRecords.length <= 0) {
      return {
        records: [this.createBootstrapTabRecord(tabManager, emptyStateOptions)],
        removedCount: removedCount
      };
    }
    if (filteredRecords.length > 0 && !filteredRecords.some((record: TabRecord) => record.isActive)) {
      filteredRecords[0].isActive = true;
    }
    return {
      records: filteredRecords,
      removedCount: removedCount
    };
  }

  private createBootstrapTabRecord(
    tabManager: BrowserTabManagerPort,
    emptyStateOptions: BrowserCreateTabOptions | BrowserProfileId
  ): TabRecord {
    const bootstrapRecord = tabManager.createBootstrapTab(this.normalizeEmptyStateOptions(emptyStateOptions));
    bootstrapRecord.isActive = true;
    return bootstrapRecord;
  }

  private normalizeEmptyStateOptions(emptyStateOptions: BrowserCreateTabOptions | BrowserProfileId): BrowserCreateTabOptions {
    if (typeof emptyStateOptions === 'string') {
      return {
        profileId: emptyStateOptions,
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
    }
    return emptyStateOptions;
  }
}

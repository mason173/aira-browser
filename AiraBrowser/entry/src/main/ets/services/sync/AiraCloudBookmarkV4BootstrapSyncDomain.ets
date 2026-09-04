import { AiraCloudBookmarkV4BootstrapDomain } from '../../core/sync/AiraCloudBookmarkV4BootstrapCoordinator';
import { SyncService } from './SyncService';

export class AiraCloudBookmarkV4BootstrapSyncDomain implements AiraCloudBookmarkV4BootstrapDomain {
  private readonly syncService: SyncService;

  constructor(syncService: SyncService) {
    this.syncService = syncService;
  }

  readRemoteCommitId(uid: string = ''): Promise<string> {
    return this.syncService.readAiraCloudBookmarkV4BootstrapCommitId(uid);
  }

  replaceLocalFromRemote(uid: string = ''): Promise<string> {
    return this.syncService.replaceLocalBookmarksFromAiraCloudV4(uid);
  }

  async disableAiraCloudBookmarks(): Promise<void> {
    await this.syncService.disableAiraCloudBookmarkSync();
  }
}

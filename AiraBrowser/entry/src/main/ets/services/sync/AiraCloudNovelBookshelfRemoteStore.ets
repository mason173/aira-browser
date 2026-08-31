import {
  NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT
} from '../../common/constants/SyncFlowErrorCodes';
import { AIRA_HOSTED_API_BASE_URL } from '../../common/config/AiraDistributionCapabilityOwner';
import {
  NovelBookshelfSyncRemoteState,
  NovelBookshelfSyncRemoteStore,
  NovelBookshelfSyncSnapshot,
  NovelBookshelfSyncWriteResult
} from '../../common/models/NovelBookshelfSyncModels';
import {
  AiraCloudConditionalSnapshotRemoteStore
} from './AiraCloudConditionalSnapshotRemoteStore';

export const AIRA_CLOUD_NOVEL_BOOKSHELF_SYNC_API_ENDPOINT: string =
  AIRA_HOSTED_API_BASE_URL + '/sync/v2/personalization/novel-bookshelf';

export class AiraCloudNovelBookshelfRemoteStore implements NovelBookshelfSyncRemoteStore {
  private readonly store: AiraCloudConditionalSnapshotRemoteStore<NovelBookshelfSyncSnapshot>;

  constructor(uid: string) {
    this.store = new AiraCloudConditionalSnapshotRemoteStore<NovelBookshelfSyncSnapshot>(
      AIRA_CLOUD_NOVEL_BOOKSHELF_SYNC_API_ENDPOINT,
      uid,
      {
        serviceLabel: 'Aira 小说书架同步服务',
        conflictResponseCode: 'novel_bookshelf_sync_write_conflict',
        conflictErrorMessage: NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT,
        missingUidMessage: '请先使用华为账号后再同步小说书架。'
      }
    );
  }

  async readState(): Promise<NovelBookshelfSyncRemoteState> {
    return this.store.readState();
  }

  async writeSnapshot(
    deviceId: string,
    snapshot: NovelBookshelfSyncSnapshot,
    expectedRevision: string
  ): Promise<NovelBookshelfSyncWriteResult> {
    return this.store.writeSnapshot(deviceId, snapshot, expectedRevision);
  }
}

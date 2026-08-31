import { common } from '@kit.AbilityKit';
import {
  NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT
} from '../../common/constants/SyncFlowErrorCodes';
import {
  NovelBookshelfSyncRemoteState,
  NovelBookshelfSyncRemoteStore,
  NovelBookshelfSyncSnapshot,
  NovelBookshelfSyncWriteResult
} from '../../common/models/NovelBookshelfSyncModels';
import { AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME } from '../../services/sync/AiraSyncConfigStore';
import { NovelBookshelfSyncSnapshotService } from '../../services/sync/NovelBookshelfSyncSnapshotService';
import {
  HuaweiSpaceConditionalSnapshotStore
} from './HuaweiSpaceConditionalSnapshotStore';
import {
  HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE
} from './HuaweiSpaceRdbStoreOwner';

export class HuaweiSpaceNovelBookshelfSyncStore implements NovelBookshelfSyncRemoteStore {
  private readonly snapshotService: NovelBookshelfSyncSnapshotService =
    new NovelBookshelfSyncSnapshotService();
  private readonly store: HuaweiSpaceConditionalSnapshotStore<NovelBookshelfSyncSnapshot>;

  constructor(
    uid: string,
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME,
    context?: common.ApplicationContext | common.UIAbilityContext
  ) {
    this.store = new HuaweiSpaceConditionalSnapshotStore<NovelBookshelfSyncSnapshot>(
      uid,
      {
        tableName: HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE,
        operationLabel: '小说书架同步',
        logTag: 'NovelShelfSyncDiag',
        writeConflictError: NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT,
        parse: (snapshotJson: string): NovelBookshelfSyncSnapshot => {
          return this.snapshotService.validate(
            JSON.parse(snapshotJson) as NovelBookshelfSyncSnapshot,
            '华为云空间'
          );
        }
      },
      databaseName,
      context
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
    return {
      revision: await this.store.writeSnapshot(deviceId, snapshot, expectedRevision)
    };
  }
}

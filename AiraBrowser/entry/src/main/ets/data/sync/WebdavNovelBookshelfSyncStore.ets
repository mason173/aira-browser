import {
  NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT
} from '../../common/constants/SyncFlowErrorCodes';
import { AiraSyncWebdavConfig } from '../../common/models/AiraSyncModels';
import {
  NovelBookshelfSyncRemoteState,
  NovelBookshelfSyncRemoteStore,
  NovelBookshelfSyncSnapshot,
  NovelBookshelfSyncWriteResult
} from '../../common/models/NovelBookshelfSyncModels';
import { NovelBookshelfSyncSnapshotService } from '../../services/sync/NovelBookshelfSyncSnapshotService';
import { WebdavConditionalJsonSnapshotStore } from './WebdavConditionalJsonSnapshotStore';

const NOVEL_BOOKSHELF_WEBDAV_ROOT: string = 'aira/g2/personalization';
const NOVEL_BOOKSHELF_WEBDAV_FILE: string = `${NOVEL_BOOKSHELF_WEBDAV_ROOT}/novel-bookshelf.json`;

export class WebdavNovelBookshelfSyncStore implements NovelBookshelfSyncRemoteStore {
  private readonly snapshotService: NovelBookshelfSyncSnapshotService =
    new NovelBookshelfSyncSnapshotService();
  private readonly store: WebdavConditionalJsonSnapshotStore<NovelBookshelfSyncSnapshot>;

  constructor(config: AiraSyncWebdavConfig) {
    this.store = new WebdavConditionalJsonSnapshotStore<NovelBookshelfSyncSnapshot>(config, {
      rootPath: NOVEL_BOOKSHELF_WEBDAV_ROOT,
      filePath: NOVEL_BOOKSHELF_WEBDAV_FILE,
      sourceLabel: 'WebDAV ',
      operationLabel: '小说书架同步',
      writeConflictError: NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT,
      parse: (payload: string, sourceLabel: string): NovelBookshelfSyncSnapshot => {
        let snapshot: NovelBookshelfSyncSnapshot;
        try {
          snapshot = JSON.parse(payload) as NovelBookshelfSyncSnapshot;
        } catch (_error) {
          throw new Error(`${sourceLabel}小说书架同步快照无法解析。`);
        }
        return this.snapshotService.validate(snapshot, sourceLabel);
      }
    });
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

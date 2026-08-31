import { PERSONALIZATION_SYNC_WRITE_CONFLICT } from '../../common/constants/SyncFlowErrorCodes';
import { AiraSyncWebdavConfig } from '../../common/models/AiraSyncModels';
import {
  PersonalizationSyncRemoteStore,
  PersonalizationSyncRemoteState,
  PersonalizationSyncSnapshot,
  PersonalizationSyncWriteResult
} from '../../common/models/PersonalizationSyncModels';
import { PersonalizationSyncSnapshotValidationService } from '../../services/sync/PersonalizationSyncSnapshotValidationService';
import { WebdavConditionalJsonSnapshotStore } from './WebdavConditionalJsonSnapshotStore';

const PERSONALIZATION_WEBDAV_ROOT: string = 'aira/g2/personalization';
const PERSONALIZATION_WEBDAV_FILE: string = `${PERSONALIZATION_WEBDAV_ROOT}/snapshot.json`;

export class WebdavPersonalizationSyncStore implements PersonalizationSyncRemoteStore {
  private readonly snapshotValidationService: PersonalizationSyncSnapshotValidationService =
    new PersonalizationSyncSnapshotValidationService();
  private readonly store: WebdavConditionalJsonSnapshotStore<PersonalizationSyncSnapshot>;

  constructor(config: AiraSyncWebdavConfig) {
    this.store = new WebdavConditionalJsonSnapshotStore<PersonalizationSyncSnapshot>(config, {
      rootPath: PERSONALIZATION_WEBDAV_ROOT,
      filePath: PERSONALIZATION_WEBDAV_FILE,
      sourceLabel: 'WebDAV ',
      operationLabel: '个性化同步',
      writeConflictError: PERSONALIZATION_SYNC_WRITE_CONFLICT,
      parse: (payload: string, sourceLabel: string): PersonalizationSyncSnapshot => {
        let snapshot: PersonalizationSyncSnapshot;
        try {
          snapshot = JSON.parse(payload) as PersonalizationSyncSnapshot;
        } catch (_error) {
          throw new Error(`${sourceLabel}个性化同步快照无法解析。`);
        }
        return this.snapshotValidationService.validate(snapshot, sourceLabel);
      }
    });
  }

  async readState(): Promise<PersonalizationSyncRemoteState> {
    return this.store.readState();
  }

  async writeSnapshot(
    deviceId: string,
    snapshot: PersonalizationSyncSnapshot,
    expectedRevision: string
  ): Promise<PersonalizationSyncWriteResult> {
    return {
      revision: await this.store.writeSnapshot(deviceId, snapshot, expectedRevision)
    };
  }
}

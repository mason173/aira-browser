import { common } from '@kit.AbilityKit';
import { PERSONALIZATION_SYNC_WRITE_CONFLICT } from '../../common/constants/SyncFlowErrorCodes';
import {
  PersonalizationSyncRemoteStore,
  PersonalizationSyncRemoteState,
  PersonalizationSyncSnapshot,
  PersonalizationSyncWriteResult
} from '../../common/models/PersonalizationSyncModels';
import { AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME } from '../../services/sync/AiraSyncConfigStore';
import { HuaweiSpaceConditionalSnapshotStore } from './HuaweiSpaceConditionalSnapshotStore';
import { HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE } from './HuaweiSpaceRdbStoreOwner';

export class HuaweiSpacePersonalizationSyncStore implements PersonalizationSyncRemoteStore {
  private readonly store: HuaweiSpaceConditionalSnapshotStore<PersonalizationSyncSnapshot>;

  constructor(
    uid: string,
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME,
    context?: common.ApplicationContext | common.UIAbilityContext
  ) {
    this.store = new HuaweiSpaceConditionalSnapshotStore<PersonalizationSyncSnapshot>(
      uid,
      {
        tableName: HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE,
        operationLabel: '个性化同步',
        logTag: 'PersonalSyncDiag',
        writeConflictError: PERSONALIZATION_SYNC_WRITE_CONFLICT,
        parse: (snapshotJson: string): PersonalizationSyncSnapshot => {
          return JSON.parse(snapshotJson) as PersonalizationSyncSnapshot;
        }
      },
      databaseName,
      context
    );
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

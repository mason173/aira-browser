import { PERSONALIZATION_SYNC_WRITE_CONFLICT } from '../../common/constants/SyncFlowErrorCodes';
import { AIRA_HOSTED_API_BASE_URL } from '../../common/config/AiraDistributionCapabilityOwner';
import {
  PersonalizationSyncRemoteStore,
  PersonalizationSyncRemoteState,
  PersonalizationSyncSnapshot,
  PersonalizationSyncWriteResult
} from '../../common/models/PersonalizationSyncModels';
import { AiraCloudConditionalSnapshotRemoteStore } from './AiraCloudConditionalSnapshotRemoteStore';

export const AIRA_CLOUD_PERSONALIZATION_SYNC_API_ENDPOINT: string =
  AIRA_HOSTED_API_BASE_URL + '/sync/v2/personalization';

export class AiraCloudPersonalizationRemoteStore implements PersonalizationSyncRemoteStore {
  private readonly store: AiraCloudConditionalSnapshotRemoteStore<PersonalizationSyncSnapshot>;

  constructor(uid: string) {
    this.store = new AiraCloudConditionalSnapshotRemoteStore<PersonalizationSyncSnapshot>(
      AIRA_CLOUD_PERSONALIZATION_SYNC_API_ENDPOINT,
      uid,
      {
        serviceLabel: 'Aira 个性化同步服务',
        conflictResponseCode: 'personalization_sync_write_conflict',
        conflictErrorMessage: PERSONALIZATION_SYNC_WRITE_CONFLICT,
        missingUidMessage: '请先使用华为账号后再同步个性化设置。'
      }
    );
  }

  readState(): Promise<PersonalizationSyncRemoteState> {
    return this.store.readState();
  }

  writeSnapshot(
    deviceId: string,
    snapshot: PersonalizationSyncSnapshot,
    expectedRevision: string
  ): Promise<PersonalizationSyncWriteResult> {
    return this.store.writeSnapshot(deviceId, snapshot, expectedRevision);
  }
}

export function createAiraCloudPersonalizationRemoteStore(uid: string): AiraCloudPersonalizationRemoteStore {
  return new AiraCloudPersonalizationRemoteStore(uid);
}

import { describe, expect, it } from '@ohos/hypium';
import {
  AiraCloudBookmarkV4BootstrapRecord
} from '../main/ets/common/models/AiraCloudBookmarkV4BootstrapModels';
import {
  AiraCloudBookmarkV4BootstrapViewModelService
} from '../main/ets/core/sync/AiraCloudBookmarkV4BootstrapViewModelService';

function record(status: 'running' | 'failed' | 'completed'): AiraCloudBookmarkV4BootstrapRecord {
  return {
    uid: 'uid-a',
    protocol: 'aira-cloud-bookmarks-v4',
    status: status,
    phase: status === 'running' ? 'creating_backup' : status,
    backupId: status === 'failed' ? 'backup-1' : '',
    backupSha256: status === 'failed' ? 'sha256' : '',
    remoteCommitId: '',
    errorMessage: status === 'failed' ? '网络不可用' : '',
    updatedAt: 100,
    completedAt: status === 'completed' ? 100 : 0
  };
}

export default function airaCloudBookmarkV4BootstrapViewModelTest(): void {
  describe('AiraCloudBookmarkV4BootstrapViewModelService', () => {
    const service = new AiraCloudBookmarkV4BootstrapViewModelService();

    it('maps a required migration to a blocking start surface', 0, () => {
      const state = service.required('uid-a');

      expect(state.visible).assertTrue();
      expect(state.status).assertEqual('required');
      expect(state.primaryAction).assertEqual('start');
    });

    it('keeps running non-dismissible and failed retryable', 0, () => {
      const running = service.fromRecord(record('running'));
      const failed = service.fromRecord(record('failed'));

      expect(running.visible).assertTrue();
      expect(running.primaryAction).assertEqual('none');
      expect(failed.visible).assertTrue();
      expect(failed.primaryAction).assertEqual('retry');
      expect(failed.recoveryAvailable).assertTrue();
    });

    it('hides the migration surface after completion', 0, () => {
      const state = service.fromRecord(record('completed'));

      expect(state.visible).assertFalse();
      expect(state.status).assertEqual('hidden');
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  AiraCloudBookmarkV4BootstrapRecord
} from '../main/ets/common/models/AiraCloudBookmarkV4BootstrapModels';
import {
  AiraCloudBookmarkV4BootstrapStateAdapter,
  AiraCloudBookmarkV4BootstrapStateStore
} from '../main/ets/data/sync/AiraCloudBookmarkV4BootstrapStateStore';

class InMemoryBootstrapStateAdapter implements AiraCloudBookmarkV4BootstrapStateAdapter {
  value: string = '';

  read(): Promise<string> {
    return Promise.resolve(this.value);
  }

  write(value: string): Promise<void> {
    this.value = value;
    return Promise.resolve();
  }
}

function record(uid: string, status: 'completed' | 'failed'): AiraCloudBookmarkV4BootstrapRecord {
  return {
    uid: uid,
    protocol: 'aira-cloud-bookmarks-v4',
    status: status,
    phase: status,
    backupId: `backup-${uid}`,
    backupSha256: 'sha256',
    remoteCommitId: 'commit-1',
    errorMessage: status === 'failed' ? 'network' : '',
    updatedAt: 200,
    completedAt: status === 'completed' ? 200 : 0
  };
}

export default function airaCloudBookmarkV4BootstrapStateStoreTest(): void {
  describe('AiraCloudBookmarkV4BootstrapStateStore', () => {
    it('persists independent completion state for each Aira account', 0, async () => {
      const adapter = new InMemoryBootstrapStateAdapter();
      const firstStore = new AiraCloudBookmarkV4BootstrapStateStore(adapter);
      await firstStore.save(record('uid-a', 'completed'));
      await firstStore.save(record('uid-b', 'failed'));

      const reloadedStore = new AiraCloudBookmarkV4BootstrapStateStore(adapter);
      const first = await reloadedStore.load('uid-a');
      const second = await reloadedStore.load('uid-b');

      expect(first?.status ?? '').assertEqual('completed');
      expect(first?.backupId ?? '').assertEqual('backup-uid-a');
      expect(second?.status ?? '').assertEqual('failed');
      expect(second?.errorMessage ?? '').assertEqual('network');
    });

    it('ignores corrupt state instead of resolving the bootstrap gate', 0, async () => {
      const adapter = new InMemoryBootstrapStateAdapter();
      adapter.value = '{not-json';
      const store = new AiraCloudBookmarkV4BootstrapStateStore(adapter);

      const loaded = await store.load('uid-a');

      expect(loaded).assertUndefined();
    });

    it('does not report an empty recovery protection set when state is corrupt', 0, async () => {
      const adapter = new InMemoryBootstrapStateAdapter();
      adapter.value = '{not-json';
      const store = new AiraCloudBookmarkV4BootstrapStateStore(adapter);
      let rejected = false;

      try {
        await store.listProtectedRecoveryPointIds();
      } catch (_error) {
        rejected = true;
      }

      expect(rejected).assertTrue();
    });
  });
}

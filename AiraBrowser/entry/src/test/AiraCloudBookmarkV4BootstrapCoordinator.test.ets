import { describe, expect, it } from '@ohos/hypium';
import {
  AiraCloudBookmarkV4BootstrapCoordinator
} from '../main/ets/core/sync/AiraCloudBookmarkV4BootstrapCoordinator';
import {
  AiraCloudBookmarkV4BootstrapDomain,
  AiraCloudBookmarkV4BootstrapRecord,
  AiraCloudBookmarkV4BootstrapRecoveryDomain,
  AiraCloudBookmarkV4BootstrapStateDomain,
  AiraCloudBookmarkV4BootstrapTransitionDomain,
  AiraCloudBookmarkV4RecoveryPoint
} from '../main/ets/common/models/AiraCloudBookmarkV4BootstrapModels';

class FixtureBootstrapStateDomain implements AiraCloudBookmarkV4BootstrapStateDomain {
  records: AiraCloudBookmarkV4BootstrapRecord[] = [];

  load(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord | undefined> {
    return Promise.resolve(this.records.find((record: AiraCloudBookmarkV4BootstrapRecord): boolean => {
      return record.uid === uid;
    }));
  }

  save(record: AiraCloudBookmarkV4BootstrapRecord): Promise<void> {
    this.records = this.records.filter((candidate: AiraCloudBookmarkV4BootstrapRecord): boolean => {
      return candidate.uid !== record.uid;
    });
    this.records.push(record);
    return Promise.resolve();
  }
}

class FixtureRecoveryDomain implements AiraCloudBookmarkV4BootstrapRecoveryDomain {
  operations: string[];

  constructor(operations: string[]) {
    this.operations = operations;
  }

  async createRecoveryPoint(uid: string, remoteCommitId: string): Promise<AiraCloudBookmarkV4RecoveryPoint> {
    this.operations.push('backup');
    return {
      backupId: 'backup-1',
      uid: uid,
      protocol: 'aira-cloud-bookmarks-v4',
      reason: 'aira_cloud_v4_bootstrap',
      status: 'ready',
      fileName: 'backup-1.aira-backup',
      sha256: 'sha256',
      byteLength: 10,
      remoteCommitId: remoteCommitId,
      createdAt: 100
    };
  }

  verifyRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void> {
    this.operations.push(`verify:${uid}:${backupId}:${backupSha256}`);
    return Promise.resolve();
  }

  restoreRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void> {
    this.operations.push(`restore:${uid}:${backupId}:${backupSha256}`);
    return Promise.resolve();
  }
}

class FixtureBootstrapDomain implements AiraCloudBookmarkV4BootstrapDomain {
  operations: string[];
  fail: boolean = false;

  constructor(operations: string[]) {
    this.operations = operations;
  }

  async readAiraCloudBookmarkV4BootstrapCommitId(): Promise<string> {
    this.operations.push('read-head');
    return 'commit-7';
  }

  async replaceLocalBookmarksFromAiraCloudV4(): Promise<string> {
    this.operations.push('replace');
    if (this.fail) {
      throw new Error('remote-read-failed');
    }
    return 'commit-7';
  }

  disableAiraCloudBookmarkSync(): Promise<void> {
    this.operations.push('disable');
    return Promise.resolve();
  }
}

class FixtureBootstrapTransitionDomain implements AiraCloudBookmarkV4BootstrapTransitionDomain {
  private readonly operations?: string[];

  constructor(operations?: string[]) {
    this.operations = operations;
  }

  async runAiraCloudBookmarkV4Bootstrap<T>(operation: () => Promise<T>): Promise<T> {
    this.operations?.push('transition-start');
    try {
      return await operation();
    } finally {
      this.operations?.push('transition-end');
    }
  }
}

export default function airaCloudBookmarkV4BootstrapCoordinatorTest(): void {
  describe('AiraCloudBookmarkV4BootstrapCoordinator', () => {
    it('creates a verified recovery point before replacing local bookmarks and completing', 0, async () => {
      const operations: string[] = [];
      const state = new FixtureBootstrapStateDomain();
      const coordinator = new AiraCloudBookmarkV4BootstrapCoordinator(
        new FixtureBootstrapDomain(operations),
        new FixtureRecoveryDomain(operations),
        state,
        new FixtureBootstrapTransitionDomain(),
        (): number => 200
      );

      const result = await coordinator.run('uid-a');

      expect(JSON.stringify(operations)).assertEqual(JSON.stringify(['read-head', 'backup', 'replace']));
      expect(result.status).assertEqual('completed');
      expect(result.backupId).assertEqual('backup-1');
      expect(result.remoteCommitId).assertEqual('commit-7');
    });

    it('runs the complete bootstrap inside the Sync Experience transition barrier', 0, async () => {
      const operations: string[] = [];
      const state = new FixtureBootstrapStateDomain();
      const coordinator = new AiraCloudBookmarkV4BootstrapCoordinator(
        new FixtureBootstrapDomain(operations),
        new FixtureRecoveryDomain(operations),
        state,
        new FixtureBootstrapTransitionDomain(operations)
      );

      const result = await coordinator.run('uid-a');

      expect(JSON.stringify(operations)).assertEqual(JSON.stringify([
        'transition-start',
        'read-head',
        'backup',
        'replace',
        'transition-end'
      ]));
      expect(result.status).assertEqual('completed');
    });

    it('keeps a retryable failed state and never disables sync automatically', 0, async () => {
      const operations: string[] = [];
      const state = new FixtureBootstrapStateDomain();
      const domain = new FixtureBootstrapDomain(operations);
      domain.fail = true;
      const coordinator = new AiraCloudBookmarkV4BootstrapCoordinator(
        domain,
        new FixtureRecoveryDomain(operations),
        state,
        new FixtureBootstrapTransitionDomain(),
        (): number => 200
      );

      const result = await coordinator.run('uid-a');

      expect(result.status).assertEqual('failed');
      expect(result.backupId).assertEqual('backup-1');
      expect(JSON.stringify(operations)).assertEqual(JSON.stringify([
        'read-head',
        'backup',
        'replace',
        'restore:uid-a:backup-1:sha256'
      ]));
      expect(operations.indexOf('disable')).assertEqual(-1);
    });

    it('reuses the original verified recovery point when a failed bootstrap is retried', 0, async () => {
      const operations: string[] = [];
      const state = new FixtureBootstrapStateDomain();
      await state.save({
        uid: 'uid-a',
        protocol: 'aira-cloud-bookmarks-v4',
        status: 'failed',
        phase: 'failed',
        backupId: 'backup-1',
        backupSha256: 'sha256',
        remoteCommitId: 'commit-7',
        errorMessage: 'completion-write-failed',
        updatedAt: 100,
        completedAt: 0
      });
      const coordinator = new AiraCloudBookmarkV4BootstrapCoordinator(
        new FixtureBootstrapDomain(operations),
        new FixtureRecoveryDomain(operations),
        state,
        new FixtureBootstrapTransitionDomain(),
        (): number => 200
      );

      const result = await coordinator.run('uid-a');

      expect(JSON.stringify(operations)).assertEqual(JSON.stringify([
        'read-head',
        'verify:uid-a:backup-1:sha256',
        'replace'
      ]));
      expect(result.status).assertEqual('completed');
      expect(result.backupId).assertEqual('backup-1');
      expect(result.backupSha256).assertEqual('sha256');
    });

    it('opts out by preserving local data and disabling only Aira Cloud bookmarks', 0, async () => {
      const operations: string[] = [];
      const state = new FixtureBootstrapStateDomain();
      const coordinator = new AiraCloudBookmarkV4BootstrapCoordinator(
        new FixtureBootstrapDomain(operations),
        new FixtureRecoveryDomain(operations),
        state,
        new FixtureBootstrapTransitionDomain(),
        (): number => 200
      );

      const result = await coordinator.keepLocalAndDisable('uid-a');

      expect(JSON.stringify(operations)).assertEqual(JSON.stringify(['disable']));
      expect(result.status).assertEqual('opted_out');
    });

    it('restores the verified pre-upgrade bookmarks before disabling Aira Cloud bookmarks', 0, async () => {
      const operations: string[] = [];
      const state = new FixtureBootstrapStateDomain();
      await state.save({
        uid: 'uid-a',
        protocol: 'aira-cloud-bookmarks-v4',
        status: 'failed',
        phase: 'failed',
        backupId: 'backup-1',
        backupSha256: 'sha256',
        remoteCommitId: 'commit-7',
        errorMessage: 'apply-failed',
        updatedAt: 100,
        completedAt: 0
      });
      const coordinator = new AiraCloudBookmarkV4BootstrapCoordinator(
        new FixtureBootstrapDomain(operations),
        new FixtureRecoveryDomain(operations),
        state,
        new FixtureBootstrapTransitionDomain(),
        (): number => 200
      );

      const result = await coordinator.restoreBackupAndDisable('uid-a');

      expect(JSON.stringify(operations)).assertEqual(
        JSON.stringify(['restore:uid-a:backup-1:sha256', 'disable'])
      );
      expect(result.status).assertEqual('opted_out');
      expect(result.backupId).assertEqual('backup-1');
      expect(result.errorMessage).assertEqual('');
    });
  });
}

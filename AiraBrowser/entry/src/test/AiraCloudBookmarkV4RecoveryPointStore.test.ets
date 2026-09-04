import { describe, expect, it } from '@ohos/hypium';
import {
  AiraCloudBookmarkV4RecoveryFileAdapter,
  AiraCloudBookmarkV4RecoveryPointStore
} from '../main/ets/data/sync/AiraCloudBookmarkV4RecoveryPointStore';

class MemoryRecoveryFile {
  name: string;
  bytes: Uint8Array;

  constructor(name: string, bytes: Uint8Array) {
    this.name = name;
    this.bytes = bytes;
  }
}

class InMemoryRecoveryFileAdapter implements AiraCloudBookmarkV4RecoveryFileAdapter {
  files: MemoryRecoveryFile[] = [];
  operations: string[] = [];

  ensureDirectory(): Promise<void> {
    this.operations.push('mkdir');
    return Promise.resolve();
  }

  writeAndSync(fileName: string, bytes: Uint8Array): Promise<void> {
    this.operations.push(`write-sync:${fileName}`);
    this.replace(fileName, bytes);
    return Promise.resolve();
  }

  rename(sourceName: string, targetName: string): Promise<void> {
    this.operations.push(`rename:${sourceName}:${targetName}`);
    const source = this.find(sourceName);
    if (source === undefined) {
      return Promise.reject(new Error('missing-source'));
    }
    this.removeNow(targetName);
    source.name = targetName;
    return Promise.resolve();
  }

  read(fileName: string): Promise<Uint8Array> {
    this.operations.push(`read:${fileName}`);
    const file = this.find(fileName);
    if (file === undefined) {
      return Promise.reject(new Error('missing-file'));
    }
    return Promise.resolve(this.clone(file.bytes));
  }

  list(): Promise<string[]> {
    return Promise.resolve(this.files.map((file: MemoryRecoveryFile): string => file.name));
  }

  remove(fileName: string): Promise<void> {
    this.removeNow(fileName);
    return Promise.resolve();
  }

  corrupt(fileName: string): void {
    this.replace(fileName, new Uint8Array([1, 2, 3]));
  }

  private find(name: string): MemoryRecoveryFile | undefined {
    return this.files.find((file: MemoryRecoveryFile): boolean => file.name === name);
  }

  private replace(name: string, bytes: Uint8Array): void {
    this.removeNow(name);
    this.files.push(new MemoryRecoveryFile(name, this.clone(bytes)));
  }

  private removeNow(name: string): void {
    this.files = this.files.filter((file: MemoryRecoveryFile): boolean => file.name !== name);
  }

  private clone(bytes: Uint8Array): Uint8Array {
    return new Uint8Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  }
}

export default function airaCloudBookmarkV4RecoveryPointStoreTest(): void {
  describe('AiraCloudBookmarkV4RecoveryPointStore', () => {
    it('atomically writes and verifies a recoverable Aira backup', 0, async () => {
      const adapter = new InMemoryRecoveryFileAdapter();
      const store = new AiraCloudBookmarkV4RecoveryPointStore(adapter, (): number => 1000,
        (): string => 'backup-1');

      const point = await store.create({
        uid: 'uid-a',
        payload: '{"format":"aira-backup"}',
        remoteCommitId: 'cloud-commit-7'
      });
      const restored = await store.readVerifiedPayload(point.backupId);

      expect(point.fileName).assertEqual('backup-1.aira-backup');
      expect(point.sha256).assertEqual('44c2e038ca248622a9cb176ce870d041e591b02d50bfd1037ecc977a9c299ffe');
      expect(point.remoteCommitId).assertEqual('cloud-commit-7');
      expect(restored).assertEqual('{"format":"aira-backup"}');
      expect(adapter.operations[1]).assertEqual('write-sync:backup-1.aira-backup.tmp');
      expect(adapter.operations[2]).assertEqual('rename:backup-1.aira-backup.tmp:backup-1.aira-backup');
      expect(adapter.operations[3]).assertEqual('read:backup-1.aira-backup');
    });

    it('rejects a recovery point whose backup bytes no longer match metadata', 0, async () => {
      const adapter = new InMemoryRecoveryFileAdapter();
      const store = new AiraCloudBookmarkV4RecoveryPointStore(adapter, (): number => 1000,
        (): string => 'backup-2');
      const point = await store.create({
        uid: 'uid-a',
        payload: '{"format":"aira-backup"}',
        remoteCommitId: 'cloud-commit-7'
      });
      adapter.corrupt(point.fileName);

      let rejected: boolean = false;
      try {
        await store.readVerifiedPayload(point.backupId);
      } catch (_error) {
        rejected = true;
      }

      expect(rejected).assertTrue();
    });

    it('retains at least the three newest recovery points after thirty days', 0, async () => {
      const adapter = new InMemoryRecoveryFileAdapter();
      let now: number = 0;
      let sequence: number = 0;
      const store = new AiraCloudBookmarkV4RecoveryPointStore(
        adapter,
        (): number => now,
        (): string => `backup-${sequence += 1}`
      );
      for (let index: number = 0; index < 5; index += 1) {
        now = index * 31 * 24 * 60 * 60 * 1000;
        await store.create({ uid: 'uid-a', payload: `payload-${index}`, remoteCommitId: `commit-${index}` });
      }

      const metadataFiles = adapter.files.filter((file: MemoryRecoveryFile): boolean => {
        return file.name.endsWith('.meta.json');
      });

      expect(metadataFiles.length).assertEqual(3);
    });
  });
}

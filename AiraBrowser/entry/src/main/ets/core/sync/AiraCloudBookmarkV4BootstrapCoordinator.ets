import {
  AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
  AiraCloudBookmarkV4BootstrapRecord,
  AiraCloudBookmarkV4BootstrapStateDomain,
  AiraCloudBookmarkV4RecoveryPoint
} from '../../common/models/AiraCloudBookmarkV4BootstrapModels';

export interface AiraCloudBookmarkV4BootstrapDomain {
  readRemoteCommitId(uid?: string): Promise<string>;
  replaceLocalFromRemote(uid?: string): Promise<string>;
  disableAiraCloudBookmarks(): Promise<void>;
}

export interface AiraCloudBookmarkV4BootstrapRecoveryDomain {
  createRecoveryPoint(uid: string, remoteCommitId: string): Promise<AiraCloudBookmarkV4RecoveryPoint>;
  verifyRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void>;
  restoreRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void>;
}

export class AiraCloudBookmarkV4BootstrapCoordinator {
  private readonly domain: AiraCloudBookmarkV4BootstrapDomain;
  private readonly recoveryDomain: AiraCloudBookmarkV4BootstrapRecoveryDomain;
  private readonly stateDomain: AiraCloudBookmarkV4BootstrapStateDomain;
  private readonly nowProvider: () => number;
  private operationTail: Promise<void> = Promise.resolve();

  constructor(
    domain: AiraCloudBookmarkV4BootstrapDomain,
    recoveryDomain: AiraCloudBookmarkV4BootstrapRecoveryDomain,
    stateDomain: AiraCloudBookmarkV4BootstrapStateDomain,
    nowProvider: () => number = (): number => Date.now()
  ) {
    this.domain = domain;
    this.recoveryDomain = recoveryDomain;
    this.stateDomain = stateDomain;
    this.nowProvider = nowProvider;
  }

  run(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    return this.enqueue((): Promise<AiraCloudBookmarkV4BootstrapRecord> => this.runNow(uid));
  }

  keepLocalAndDisable(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    return this.enqueue(async (): Promise<AiraCloudBookmarkV4BootstrapRecord> => {
      const normalizedUid = this.requireUid(uid);
      await this.domain.disableAiraCloudBookmarks();
      const previous = await this.stateDomain.load(normalizedUid);
      const record = this.buildRecord(normalizedUid, 'opted_out', 'opted_out', previous);
      record.completedAt = this.nowProvider();
      await this.stateDomain.save(record);
      return record;
    });
  }

  restoreBackupAndDisable(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    return this.enqueue(async (): Promise<AiraCloudBookmarkV4BootstrapRecord> => {
      const normalizedUid = this.requireUid(uid);
      let current = await this.stateDomain.load(normalizedUid);
      if (current === undefined || current.backupId.length === 0 || current.backupSha256.length === 0) {
        throw new Error('没有可用于恢复的升级前书签备份。');
      }
      current.status = 'running';
      current.phase = 'replacing_local';
      current.errorMessage = '';
      current.updatedAt = this.nowProvider();
      await this.stateDomain.save(current);
      try {
        await this.recoveryDomain.restoreRecoveryPoint(
          normalizedUid,
          current.backupId,
          current.backupSha256
        );
        await this.domain.disableAiraCloudBookmarks();
        current.status = 'opted_out';
        current.phase = 'opted_out';
        current.errorMessage = '';
        current.updatedAt = this.nowProvider();
        current.completedAt = current.updatedAt;
        await this.stateDomain.save(current);
        return current;
      } catch (error) {
        current.status = 'failed';
        current.phase = 'failed';
        current.errorMessage = error instanceof Error ? error.message : JSON.stringify(error);
        current.updatedAt = this.nowProvider();
        current.completedAt = 0;
        await this.stateDomain.save(current);
        return current;
      }
    });
  }

  private async runNow(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    const normalizedUid = this.requireUid(uid);
    let current = await this.stateDomain.load(normalizedUid);
    if (current?.status === 'completed' || current?.status === 'opted_out') {
      return current;
    }
    current = this.buildRecord(normalizedUid, 'running', 'reading_remote', current);
    await this.stateDomain.save(current);
    try {
      const remoteCommitId = await this.domain.readRemoteCommitId(normalizedUid);
      if (remoteCommitId.trim().length === 0) {
        throw new Error('Aira 云端没有可用于初始化的完整书签快照。');
      }
      current.phase = 'creating_backup';
      current.remoteCommitId = remoteCommitId;
      current.updatedAt = this.nowProvider();
      await this.stateDomain.save(current);
      if (current.backupId.length > 0 && current.backupSha256.length > 0) {
        await this.recoveryDomain.verifyRecoveryPoint(
          normalizedUid,
          current.backupId,
          current.backupSha256
        );
      } else {
        const recoveryPoint = await this.recoveryDomain.createRecoveryPoint(normalizedUid, remoteCommitId);
        current.backupId = recoveryPoint.backupId;
        current.backupSha256 = recoveryPoint.sha256;
      }
      current.phase = 'reading_remote';
      current.updatedAt = this.nowProvider();
      await this.stateDomain.save(current);

      const completedCommitId = await this.domain.replaceLocalFromRemote(normalizedUid);
      if (completedCommitId.trim().length === 0) {
        throw new Error('Aira 云书签初始化缺少已确认的云端提交。');
      }
      current.status = 'completed';
      current.phase = 'completed';
      current.remoteCommitId = completedCommitId;
      current.errorMessage = '';
      current.updatedAt = this.nowProvider();
      current.completedAt = current.updatedAt;
      await this.stateDomain.save(current);
      return current;
    } catch (error) {
      current.status = 'failed';
      current.phase = 'failed';
      current.errorMessage = error instanceof Error ? error.message : JSON.stringify(error);
      current.updatedAt = this.nowProvider();
      current.completedAt = 0;
      await this.stateDomain.save(current);
      return current;
    }
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.operationTail.then(operation, operation);
    this.operationTail = next.then((): void => {}, (_error: Error): void => {});
    return next;
  }

  private requireUid(uid: string): string {
    const normalized = uid.trim();
    if (normalized.length === 0) {
      throw new Error('Aira 云书签初始化缺少账号标识。');
    }
    return normalized;
  }

  private buildRecord(
    uid: string,
    status: 'running' | 'opted_out',
    phase: 'reading_remote' | 'opted_out',
    previous?: AiraCloudBookmarkV4BootstrapRecord
  ): AiraCloudBookmarkV4BootstrapRecord {
    return {
      uid: uid,
      protocol: AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
      status: status,
      phase: phase,
      backupId: previous?.backupId ?? '',
      backupSha256: previous?.backupSha256 ?? '',
      remoteCommitId: previous?.remoteCommitId ?? '',
      errorMessage: '',
      updatedAt: this.nowProvider(),
      completedAt: 0
    };
  }
}

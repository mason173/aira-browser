import {
  AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID,
  AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
  AiraCloudBookmarkV4BootstrapDomain,
  AiraCloudBookmarkV4BootstrapRecord,
  AiraCloudBookmarkV4BootstrapRecoveryDomain,
  AiraCloudBookmarkV4BootstrapStateDomain,
  AiraCloudBookmarkV4BootstrapTransitionDomain
} from '../../common/models/AiraCloudBookmarkV4BootstrapModels';

export class AiraCloudBookmarkV4BootstrapCoordinator {
  private readonly domain: AiraCloudBookmarkV4BootstrapDomain;
  private readonly recoveryDomain: AiraCloudBookmarkV4BootstrapRecoveryDomain;
  private readonly stateDomain: AiraCloudBookmarkV4BootstrapStateDomain;
  private readonly transitionDomain: AiraCloudBookmarkV4BootstrapTransitionDomain;
  private readonly nowProvider: () => number;

  constructor(
    domain: AiraCloudBookmarkV4BootstrapDomain,
    recoveryDomain: AiraCloudBookmarkV4BootstrapRecoveryDomain,
    stateDomain: AiraCloudBookmarkV4BootstrapStateDomain,
    transitionDomain: AiraCloudBookmarkV4BootstrapTransitionDomain,
    nowProvider: () => number = (): number => Date.now()
  ) {
    this.domain = domain;
    this.recoveryDomain = recoveryDomain;
    this.stateDomain = stateDomain;
    this.transitionDomain = transitionDomain;
    this.nowProvider = nowProvider;
  }

  run(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    return this.transitionDomain.runAiraCloudBookmarkV4Bootstrap(
      (): Promise<AiraCloudBookmarkV4BootstrapRecord> => this.runNow(uid)
    );
  }

  keepLocalAndDisable(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    return this.transitionDomain.runAiraCloudBookmarkV4Bootstrap(
      async (): Promise<AiraCloudBookmarkV4BootstrapRecord> => {
        const normalizedUid = this.requireUid(uid);
        await this.domain.disableAiraCloudBookmarkSync();
        const previous = await this.stateDomain.load(normalizedUid);
        const record = this.buildRecord(normalizedUid, 'opted_out', 'opted_out', previous);
        record.completedAt = this.nowProvider();
        await this.stateDomain.save(record);
        return record;
      }
    );
  }

  restoreBackupAndDisable(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    return this.transitionDomain.runAiraCloudBookmarkV4Bootstrap(
      async (): Promise<AiraCloudBookmarkV4BootstrapRecord> => {
        const normalizedUid = this.requireUid(uid);
        let current = await this.stateDomain.load(normalizedUid);
        if (current === undefined || current.cutoverId !== AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID ||
          current.backupId.length === 0 || current.backupSha256.length === 0) {
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
          await this.domain.disableAiraCloudBookmarkSync();
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
      }
    );
  }

  private async runNow(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord> {
    const normalizedUid = this.requireUid(uid);
    let current = await this.stateDomain.load(normalizedUid);
    if (current !== undefined && current.cutoverId === AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID &&
      (current.status === 'completed' || current.status === 'opted_out')) {
      return current;
    }
    current = this.buildRecord(normalizedUid, 'running', 'reading_remote', current);
    await this.stateDomain.save(current);
    try {
      const remoteCommitId = await this.domain.readAiraCloudBookmarkV4BootstrapCommitId(normalizedUid);
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

      const completedCommitId = await this.domain.replaceLocalBookmarksFromAiraCloudV4(
        normalizedUid,
        remoteCommitId
      );
      if (completedCommitId.trim().length === 0) {
        throw new Error('Aira 云书签初始化缺少已确认的云端提交。');
      }
      if (completedCommitId.trim() !== remoteCommitId.trim()) {
        throw new Error('Aira 云端书签在备份期间发生变化，请重新开始 V4 初始化。');
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
      const failureMessage = error instanceof Error ? error.message : JSON.stringify(error);
      let recoveryFailureMessage = '';
      if (current.backupId.length > 0 && current.backupSha256.length > 0) {
        try {
          await this.recoveryDomain.restoreRecoveryPoint(
            normalizedUid,
            current.backupId,
            current.backupSha256
          );
        } catch (recoveryError) {
          recoveryFailureMessage = recoveryError instanceof Error
            ? recoveryError.message
            : JSON.stringify(recoveryError);
        }
      }
      current.status = 'failed';
      current.phase = 'failed';
      current.errorMessage = recoveryFailureMessage.length > 0
        ? `${failureMessage}；自动恢复升级前书签失败：${recoveryFailureMessage}`
        : failureMessage;
      current.updatedAt = this.nowProvider();
      current.completedAt = 0;
      await this.stateDomain.save(current);
      return current;
    }
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
    const sameCutover = previous?.cutoverId === AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID;
    return {
      uid: uid,
      protocol: AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
      cutoverId: AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID,
      status: status,
      phase: phase,
      backupId: sameCutover ? previous?.backupId ?? '' : '',
      backupSha256: sameCutover ? previous?.backupSha256 ?? '' : '',
      remoteCommitId: sameCutover ? previous?.remoteCommitId ?? '' : '',
      errorMessage: '',
      updatedAt: this.nowProvider(),
      completedAt: 0
    };
  }
}

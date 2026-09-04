import { AiraCloudBookmarkV4RecoveryPoint } from '../../common/models/AiraCloudBookmarkV4BootstrapModels';
import { AiraCloudBookmarkV4BootstrapRecoveryDomain } from '../../core/sync/AiraCloudBookmarkV4BootstrapCoordinator';
import { AiraCloudBookmarkV4RecoveryPointStore } from '../../data/sync/AiraCloudBookmarkV4RecoveryPointStore';
import { LocalBackupSelection } from '../../features/backup/LocalBackupModels';
import { LocalBackupService } from '../backup/LocalBackupService';

const BOOKMARK_RECOVERY_SELECTION: LocalBackupSelection = {
  bookmarks: true,
  history: false,
  personalization: false,
  userScripts: false,
  userScriptValues: false
};

export class AiraCloudBookmarkV4RecoveryService implements AiraCloudBookmarkV4BootstrapRecoveryDomain {
  private readonly localBackupService: LocalBackupService;
  private readonly recoveryPointStore: AiraCloudBookmarkV4RecoveryPointStore;

  constructor(
    localBackupService: LocalBackupService,
    recoveryPointStore: AiraCloudBookmarkV4RecoveryPointStore =
      new AiraCloudBookmarkV4RecoveryPointStore()
  ) {
    this.localBackupService = localBackupService;
    this.recoveryPointStore = recoveryPointStore;
  }

  async createRecoveryPoint(uid: string, remoteCommitId: string): Promise<AiraCloudBookmarkV4RecoveryPoint> {
    const payload = await this.localBackupService.buildExportPayload(BOOKMARK_RECOVERY_SELECTION);
    const inspection = this.localBackupService.inspectPayload(payload);
    if (inspection.document.sections.bookmarks === undefined) {
      throw new Error('升级前书签备份未包含书签数据。');
    }
    const point = await this.recoveryPointStore.create({
      uid: uid,
      payload: payload,
      remoteCommitId: remoteCommitId
    });
    const verifiedPayload = await this.recoveryPointStore.readVerifiedPayload(point.backupId);
    const verifiedInspection = this.localBackupService.inspectPayload(verifiedPayload);
    if (verifiedInspection.document.sections.bookmarks === undefined) {
      throw new Error('升级前书签备份读取校验失败。');
    }
    return point;
  }

  async verifyRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void> {
    const payload = await this.recoveryPointStore.readVerifiedPayload(backupId, uid, backupSha256);
    const inspection = this.localBackupService.inspectPayload(payload);
    if (inspection.document.sections.bookmarks === undefined) {
      throw new Error('升级前书签备份未包含书签数据。');
    }
  }

  async restoreRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void> {
    const payload = await this.recoveryPointStore.readVerifiedPayload(backupId, uid, backupSha256);
    const inspection = this.localBackupService.inspectPayload(payload);
    if (inspection.document.sections.bookmarks === undefined) {
      throw new Error('升级前书签备份未包含书签数据。');
    }
    await this.localBackupService.restoreBookmarkDocumentExactly(inspection.document);
  }
}

export const AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL: string = 'aira-cloud-bookmarks-v4';
// Bump this deliberately when the hosted V4 cutover is re-opened. A completed
// record from another environment or release must never suppress this gate.
export const AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID: string = 'bookmarks-v4-cutover-20260903';

export type AiraCloudBookmarkV4BootstrapStatus =
  | 'required'
  | 'running'
  | 'failed'
  | 'completed'
  | 'opted_out';

export type AiraCloudBookmarkV4BootstrapPhase =
  | 'required'
  | 'creating_backup'
  | 'reading_remote'
  | 'replacing_local'
  | 'verifying_local'
  | 'completed'
  | 'opted_out'
  | 'failed';

export interface AiraCloudBookmarkV4BootstrapRecord {
  uid: string;
  protocol: string;
  cutoverId: string;
  status: AiraCloudBookmarkV4BootstrapStatus;
  phase: AiraCloudBookmarkV4BootstrapPhase;
  backupId: string;
  backupSha256: string;
  remoteCommitId: string;
  errorMessage: string;
  updatedAt: number;
  completedAt: number;
}

export interface AiraCloudBookmarkV4BootstrapStateDomain {
  load(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord | undefined>;
  save(record: AiraCloudBookmarkV4BootstrapRecord): Promise<void>;
}

export type AiraCloudBookmarkV4BootstrapEligibilityReason =
  | 'required'
  | 'not_active_aira_cloud'
  | 'not_entitled'
  | 'account_mismatch'
  | 'not_legacy_initialized'
  | 'provider_switch_in_progress'
  | 'provider_switch_activation'
  | 'completed'
  | 'opted_out';

export function shouldAcknowledgeNativeAiraCloudBookmarkV4Activation(
  writtenRemoteKind: string,
  activeRemoteKind: string,
  bookmarkGenerationInitializedAt: number,
  initializeBookmarkGeneration: boolean
): boolean {
  if (initializeBookmarkGeneration !== true || writtenRemoteKind !== 'aira_cloud') {
    return false;
  }
  if (bookmarkGenerationInitializedAt <= 0) {
    return true;
  }
  return activeRemoteKind !== 'aira_cloud';
}

export interface AiraCloudBookmarkV4BootstrapEligibility {
  required: boolean;
  uid: string;
  reason: AiraCloudBookmarkV4BootstrapEligibilityReason;
}

export interface AiraCloudBookmarkV4RecoveryPointCreateRequest {
  uid: string;
  payload: string;
  remoteCommitId: string;
}

export interface AiraCloudBookmarkV4RecoveryPoint {
  backupId: string;
  uid: string;
  protocol: string;
  reason: 'aira_cloud_v4_bootstrap';
  status: 'ready';
  fileName: string;
  sha256: string;
  byteLength: number;
  remoteCommitId: string;
  createdAt: number;
}

export interface AiraCloudBookmarkV4BootstrapDomain {
  readAiraCloudBookmarkV4BootstrapCommitId(uid: string): Promise<string>;
  replaceLocalBookmarksFromAiraCloudV4(uid: string, expectedCommitId: string): Promise<string>;
  disableAiraCloudBookmarkSync(): Promise<void>;
}

export interface AiraCloudBookmarkV4BootstrapRecoveryDomain {
  createRecoveryPoint(uid: string, remoteCommitId: string): Promise<AiraCloudBookmarkV4RecoveryPoint>;
  verifyRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void>;
  restoreRecoveryPoint(uid: string, backupId: string, backupSha256: string): Promise<void>;
}

export interface AiraCloudBookmarkV4BootstrapTransitionDomain {
  runAiraCloudBookmarkV4Bootstrap<T>(operation: () => Promise<T>): Promise<T>;
}

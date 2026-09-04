export const AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL: string = 'aira-cloud-bookmarks-v4';

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
  | 'already_v4_initialized'
  | 'provider_switch_in_progress'
  | 'completed'
  | 'opted_out';

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

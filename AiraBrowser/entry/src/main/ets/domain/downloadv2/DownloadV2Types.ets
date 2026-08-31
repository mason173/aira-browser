import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { DownloadV2SegmentPlanSnapshot } from './DownloadV2SegmentTypes';

export type DownloadV2Status =
  'created' |
  'awaiting_confirmation' |
  'queued' |
  'running' |
  'paused' |
  'completed' |
  'failed' |
  'canceled' |
  'removed';

export type DownloadV2FailureCode =
  'none' |
  'network' |
  'server' |
  'file_system' |
  'permission' |
  'context_lost' |
  'unsupported' |
  'canceled' |
  'unknown';

export type DownloadV2ResumeCapability =
  'none' |
  'retry_only' |
  'live_resume';

export type DownloadV2Driver =
  'libcurl';

export type DownloadV2ResumeMode =
  'none' |
  'platform_live_resume';

export type DownloadV2LifecycleAction =
  'confirm' |
  'start';

export type DownloadV2ManagementAction =
  'pause' |
  'resume' |
  'retry' |
  'cancel' |
  'remove_record' |
  'save_to_system' |
  'open_file' |
  'open_location';

export type DownloadV2Action = DownloadV2LifecycleAction | DownloadV2ManagementAction;

export interface DownloadV2TaskBoundary {
  windowId?: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface DownloadV2RequestContext {
  url: string;
  originalUrl?: string;
  method: string;
  sourcePageUrl?: string;
  sourceHost?: string;
  userAgent?: string;
  referer?: string;
  mimeType?: string;
  contentDisposition?: string;
  headers?: Record<string, string>;
}

export interface DownloadV2Failure {
  code: DownloadV2FailureCode;
  sourceCode?: number;
  message: string;
  retriable: boolean;
}

export interface DownloadV2ProgressSnapshot {
  totalBytes: number;
  receivedBytes: number;
  speedBytesPerSecond: number;
}

export interface DownloadV2PersistenceSnapshot {
  tempFilePath?: string;
  finalFileUri?: string;
  finalDisplayPath?: string;
  partialFilePath?: string;
  finalFilePath?: string;
  writtenBytes?: number;
  etag?: string;
  lastModified?: string;
  acceptRanges?: string;
  contentRange?: string;
  validatorCapturedAt?: number;
  downloadDriver?: DownloadV2Driver;
  resumeMode?: DownloadV2ResumeMode;
  needsFullRestart?: boolean;
  restartReason?: string;
  segmentPlan?: DownloadV2SegmentPlanSnapshot;
}

export interface DownloadV2RuntimeSnapshot {
  platformTaskId?: string;
  platformTaskToken?: string;
  resumeCapability: DownloadV2ResumeCapability;
}

export interface DownloadV2TaskTiming {
  createdAt: number;
  updatedAt: number;
  confirmedAt?: number;
  startedAt?: number;
  completedAt?: number;
  failedAt?: number;
  canceledAt?: number;
  removedAt?: number;
}

export interface DownloadV2ActionPermissionSet {
  status: DownloadV2Status;
  allowedActions: DownloadV2Action[];
}

interface DownloadV2ActionsByStatus {
  created: DownloadV2Action[];
  awaiting_confirmation: DownloadV2Action[];
  queued: DownloadV2Action[];
  running: DownloadV2Action[];
  paused: DownloadV2Action[];
  completed: DownloadV2Action[];
  failed: DownloadV2Action[];
  canceled: DownloadV2Action[];
  removed: DownloadV2Action[];
}

const DOWNLOAD_V2_ACTIONS_BY_STATUS: DownloadV2ActionsByStatus = {
  created: ['confirm', 'remove_record'],
  awaiting_confirmation: ['confirm', 'cancel', 'remove_record'],
  queued: ['start', 'cancel', 'remove_record'],
  running: ['pause', 'cancel'],
  paused: ['resume', 'cancel', 'remove_record'],
  completed: ['save_to_system', 'open_file', 'open_location', 'remove_record'],
  failed: ['retry', 'remove_record'],
  canceled: ['remove_record'],
  removed: []
};

export function getDownloadV2ActionPermissionSet(status: DownloadV2Status): DownloadV2ActionPermissionSet {
  let actions: DownloadV2Action[] = [];
  switch (status) {
    case 'created':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.created.slice();
      break;
    case 'awaiting_confirmation':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.awaiting_confirmation.slice();
      break;
    case 'queued':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.queued.slice();
      break;
    case 'running':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.running.slice();
      break;
    case 'paused':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.paused.slice();
      break;
    case 'completed':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.completed.slice();
      break;
    case 'failed':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.failed.slice();
      break;
    case 'canceled':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.canceled.slice();
      break;
    case 'removed':
      actions = DOWNLOAD_V2_ACTIONS_BY_STATUS.removed.slice();
      break;
  }
  return {
    status: status,
    allowedActions: actions
  };
}

export function isDownloadV2TerminalStatus(status: DownloadV2Status): boolean {
  return status === 'completed' || status === 'failed' || status === 'canceled' || status === 'removed';
}

export function isDownloadV2ActiveStatus(status: DownloadV2Status): boolean {
  return status === 'queued' || status === 'running' || status === 'paused';
}

export function buildDownloadV2EmptyFailure(): DownloadV2Failure {
  return {
    code: 'none',
    message: '',
    retriable: false
  };
}

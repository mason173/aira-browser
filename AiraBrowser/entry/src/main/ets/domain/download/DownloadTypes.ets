import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { DownloadV2Status } from '../downloadv2/DownloadV2Types';

export interface DownloadTaskBoundary {
  windowId?: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  sourcePageUrl?: string;
}

export interface DownloadTaskBoundaryMatchFacts {
  windowId?: string;
  profileId?: string;
  privacyMode?: string;
  dataScope?: string;
}

export function matchesDownloadTaskBoundary(
  taskBoundary: DownloadTaskBoundaryMatchFacts,
  expectedBoundary: DownloadTaskBoundaryMatchFacts
): boolean {
  const expectedWindowId = expectedBoundary.windowId?.trim() ?? '';
  const taskWindowId = taskBoundary.windowId?.trim() ?? '';
  const requiresExactWindow = expectedBoundary.privacyMode === 'private' ||
    expectedBoundary.dataScope === 'session_ephemeral';
  if (expectedWindowId.length > 0) {
    if (requiresExactWindow && taskWindowId !== expectedWindowId) {
      return false;
    }
    if (!requiresExactWindow && taskWindowId.length > 0 && taskWindowId !== expectedWindowId) {
      return false;
    }
  }
  if (expectedBoundary.profileId !== undefined && taskBoundary.profileId !== expectedBoundary.profileId) {
    return false;
  }
  if (expectedBoundary.privacyMode !== undefined && taskBoundary.privacyMode !== expectedBoundary.privacyMode) {
    return false;
  }
  if (expectedBoundary.dataScope !== undefined && taskBoundary.dataScope !== expectedBoundary.dataScope) {
    return false;
  }
  return true;
}

export type DownloadQueryGroup =
  'in_progress' |
  'completed' |
  'failed' |
  'paused' |
  'pending' |
  'canceled' |
  'removed' |
  'all';

export type DownloadActionBlockReason =
  'allowed' |
  'missing_task' |
  'empty_file_name' |
  'boundary_mismatch' |
  'status_not_allowed' |
  'risk_blocked' |
  'not_supported';

export type DownloadRiskDecision =
  'allow' |
  'confirm' |
  'block';

export type DownloadRiskPromptKind =
  'none' |
  'review_source' |
  'review_file_type' |
  'blocked';

export interface DownloadRiskPrompt {
  decision: DownloadRiskDecision;
  kind: DownloadRiskPromptKind;
  title: string;
  message: string;
  confirmActionLabel: string;
  cancelActionLabel: string;
}

export function getDownloadV2QueryGroup(status: DownloadV2Status): DownloadQueryGroup {
  switch (status) {
    case 'created':
    case 'awaiting_confirmation':
    case 'queued':
      return 'pending';
    case 'running':
      return 'in_progress';
    case 'paused':
      return 'paused';
    case 'completed':
      return 'completed';
    case 'failed':
      return 'failed';
    case 'canceled':
      return 'canceled';
    case 'removed':
      return 'removed';
    default:
      return 'all';
  }
}

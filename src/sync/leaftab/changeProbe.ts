import { LeafTabSyncExtensionStorageBaselineStore } from './baseline';
import type { LeafTabSyncRemoteStore } from './remoteStore';
import type { LeafTabSyncRemoteKind } from './source';

export type LeafTabBookmarkSyncChangeProbeStatus =
  | 'unchanged'
  | 'changed'
  | 'unknown'
  | 'unconfigured';

export interface LeafTabBookmarkSyncChangeProbeResult {
  status: LeafTabBookmarkSyncChangeProbeStatus;
  canSkipSync: boolean;
  hasLocalChanges: boolean;
  hasRemoteChanges: boolean;
  provider: LeafTabSyncRemoteKind;
  baselineCommitId: string | null;
  remoteCommitId: string | null;
  summary: string;
}

export interface ProbeLeafTabBookmarkSyncChangesParams {
  provider: LeafTabSyncRemoteKind;
  baselineStorageKey: string;
  createRemoteStore: () => LeafTabSyncRemoteStore;
  hasPendingLocalChanges: () => boolean | Promise<boolean>;
  hasPendingLocalOperationOutbox?: () => boolean | Promise<boolean>;
}

const getBaselineCommitId = async (baselineStorageKey: string): Promise<string | null | undefined> => {
  const baseline = await new LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey).load();
  if (!baseline) return undefined;
  return typeof baseline.commitId === 'string' && baseline.commitId.length > 0
    ? baseline.commitId
    : null;
};

const readRemoteCommitId = async (store: LeafTabSyncRemoteStore): Promise<string | null> => {
  if (store.readCommitId) {
    return store.readCommitId();
  }
  if (store.readHead) {
    const head = await store.readHead();
    return head.commitId;
  }
  throw new Error('Remote store cannot read lightweight sync head');
};

const createProbeResult = (
  status: LeafTabBookmarkSyncChangeProbeStatus,
  canSkipSync: boolean,
  hasLocalChanges: boolean,
  hasRemoteChanges: boolean,
  provider: LeafTabSyncRemoteKind,
  baselineCommitId: string | null,
  remoteCommitId: string | null,
  summary: string,
): LeafTabBookmarkSyncChangeProbeResult => ({
  status,
  canSkipSync,
  hasLocalChanges,
  hasRemoteChanges,
  provider,
  baselineCommitId,
  remoteCommitId,
  summary,
});

export const probeLeafTabBookmarkSyncChanges = async (
  params: ProbeLeafTabBookmarkSyncChangesParams,
): Promise<LeafTabBookmarkSyncChangeProbeResult> => {
  const hasDirtyMarker = await params.hasPendingLocalChanges();
  const hasOutbox = params.hasPendingLocalOperationOutbox
    ? await params.hasPendingLocalOperationOutbox()
    : false;
  if (hasDirtyMarker || hasOutbox) {
    return createProbeResult(
      'changed',
      false,
      true,
      false,
      params.provider,
      null,
      null,
      hasOutbox ? '本机已有待上传的书签操作。' : '本机已有待同步的书签变更。',
    );
  }

  let baselineCommitId: string | null | undefined;
  let remoteCommitId: string | null;
  try {
    baselineCommitId = await getBaselineCommitId(params.baselineStorageKey);
    remoteCommitId = await readRemoteCommitId(params.createRemoteStore());
  } catch (error) {
    return createProbeResult(
      'unknown',
      false,
      false,
      false,
      params.provider,
      null,
      null,
      String((error as Error)?.message || error || '轻量同步状态读取失败。'),
    );
  }

  if (baselineCommitId === undefined) {
    return createProbeResult(
      'changed',
      false,
      false,
      remoteCommitId !== null,
      params.provider,
      null,
      remoteCommitId,
      remoteCommitId ? '还没有本地同步基线，需要同步一次。' : '还没有本地同步基线，需要确认初次同步状态。',
    );
  }

  if (baselineCommitId === remoteCommitId) {
    return createProbeResult(
      'unchanged',
      true,
      false,
      false,
      params.provider,
      baselineCommitId,
      remoteCommitId,
      '本机和云端没有新的书签变更。',
    );
  }

  return createProbeResult(
    'changed',
    false,
    false,
    true,
    params.provider,
    baselineCommitId,
    remoteCommitId,
    '云端书签状态已变化，需要同步。',
  );
};

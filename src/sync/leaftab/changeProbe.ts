import {
  getLeafTabSyncBaselineSnapshot,
  LeafTabSyncExtensionStorageBaselineStore,
} from './baseline';
import type { LeafTabSyncRemoteStore } from './remoteStore';
import type { LeafTabSyncRemoteKind } from './source';
import { countLeafTabLiveBookmarkEntities } from './snapshot';

export type LeafTabBookmarkSyncChangeProbeStatus =
  | 'unchanged'
  | 'changed'
  | 'unknown'
  | 'unconfigured';

export interface LeafTabBookmarkSyncChangeProbeResult {
  status: LeafTabBookmarkSyncChangeProbeStatus;
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
  readLocalSummary?: () => Promise<{
    bookmarkFolders: number;
    bookmarkItems: number;
  }>;
}

const getBaselineProbeState = async (baselineStorageKey: string) => {
  const baseline = await new LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey).load();
  if (!baseline) return undefined;
  const snapshot = getLeafTabSyncBaselineSnapshot(baseline);
  return {
    commitId: typeof baseline.commitId === 'string' && baseline.commitId.length > 0
      ? baseline.commitId
      : null,
    summary: snapshot ? countLeafTabLiveBookmarkEntities(snapshot) : null,
  };
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
  hasLocalChanges: boolean,
  hasRemoteChanges: boolean,
  provider: LeafTabSyncRemoteKind,
  baselineCommitId: string | null,
  remoteCommitId: string | null,
  summary: string,
): LeafTabBookmarkSyncChangeProbeResult => ({
  status,
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
      true,
      false,
      params.provider,
      null,
      null,
      hasOutbox ? '本机已有待上传的书签操作。' : '本机已有待同步的书签变更。',
    );
  }

  let baselineState: Awaited<ReturnType<typeof getBaselineProbeState>>;
  let remoteCommitId: string | null;
  try {
    baselineState = await getBaselineProbeState(params.baselineStorageKey);
    remoteCommitId = await readRemoteCommitId(params.createRemoteStore());
  } catch (error) {
    return createProbeResult(
      'unknown',
      false,
      false,
      params.provider,
      null,
      null,
      String((error as Error)?.message || error || '轻量同步状态读取失败。'),
    );
  }
  const baselineCommitId = baselineState?.commitId;

  if (baselineCommitId === undefined) {
    return createProbeResult(
      'changed',
      false,
      remoteCommitId !== null,
      params.provider,
      null,
      remoteCommitId,
      remoteCommitId ? '还没有本地同步基线，需要同步一次。' : '还没有本地同步基线，需要确认初次同步状态。',
    );
  }

  if (baselineCommitId === remoteCommitId) {
    if (params.readLocalSummary && baselineState?.summary) {
      try {
        const localSummary = await params.readLocalSummary();
        if (localSummary.bookmarkFolders !== baselineState.summary.bookmarkFolders ||
          localSummary.bookmarkItems !== baselineState.summary.bookmarkItems) {
          return createProbeResult(
            'changed',
            true,
            false,
            params.provider,
            baselineCommitId,
            remoteCommitId,
            '本机书签数量与同步基线不一致，需要重新核对。',
          );
        }
      } catch (error) {
        return createProbeResult(
          'unknown',
          false,
          false,
          params.provider,
          baselineCommitId,
          remoteCommitId,
          String((error as Error)?.message || error || '本机书签数量读取失败。'),
        );
      }
    }
    return createProbeResult(
      'unchanged',
      false,
      false,
      params.provider,
      baselineCommitId,
      remoteCommitId,
      '轻量检查未发现变化，仍需由完整同步确认本机快照。',
    );
  }

  return createProbeResult(
    'changed',
    false,
    true,
    params.provider,
    baselineCommitId,
    remoteCommitId,
    '云端书签状态已变化，需要同步。',
  );
};

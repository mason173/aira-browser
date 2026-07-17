import { createLeafTabSyncBaseline, type LeafTabSyncBaselineStore, getLeafTabSyncBaselineSnapshot } from './baseline';
import {
  mergeLeafTabSyncSnapshot,
  mergeLeafTabSyncSnapshotWithoutBaseline,
  type LeafTabSyncConflictResolution,
  type LeafTabSyncMergeResult,
} from './merge';
import type { LeafTabSyncSnapshot } from './schema';
import { countLeafTabLiveBookmarkEntities } from './snapshot';
import { formatLeafTabSyncSummaryText, summarizeLeafTabSyncMerge, type LeafTabSyncChangeSummary } from './summary';
import type { LeafTabSyncRemoteState, LeafTabSyncRemoteStore } from './remoteStore';

export interface LeafTabSyncDataSummary {
  bookmarkFolders: number;
  bookmarkItems: number;
  tombstones: number;
}

export interface LeafTabSyncAnalysis {
  hasBaseline: boolean;
  localSummary: LeafTabSyncDataSummary;
  remoteSummary: LeafTabSyncDataSummary;
  remoteCommitId: string | null;
}

export interface LeafTabSyncEngineResult {
  kind: 'noop' | 'push' | 'pull' | 'merge' | 'conflict';
  remoteCommitId: string | null;
  snapshot: LeafTabSyncSnapshot;
  snapshotSummary: LeafTabSyncDataSummary;
  mergeResult?: LeafTabSyncMergeResult;
  summary?: LeafTabSyncChangeSummary;
  summaryText?: string;
}

export interface LeafTabSyncEngineProgress {
  stage:
    | 'reading-state'
    | 'merging'
    | 'confirming-remote'
    | 'rechecking-remote'
    | 'uploading-remote'
    | 'applying-local'
    | 'finalizing'
    | 'completed';
  progress: number;
  message: string;
}

export interface LeafTabSyncEngineConfig {
  deviceId: string;
  remoteStore: LeafTabSyncRemoteStore;
  baselineStore: LeafTabSyncBaselineStore;
  buildLocalSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  readPendingLocalChanges?: () => Promise<number>;
  clearPendingLocalChanges?: (expectedChangedAt: number) => Promise<void> | void;
  createEmptySnapshot: () => LeafTabSyncSnapshot;
}

export interface LeafTabSyncEngineRunOptions {
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
  conflictResolution?: LeafTabSyncConflictResolution;
}

export interface LeafTabSyncEngineAnalyzeOptions {
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
}

const summarizeSnapshot = (snapshot: LeafTabSyncSnapshot | null): LeafTabSyncDataSummary => {
  return countLeafTabLiveBookmarkEntities(snapshot);
};

const sameSnapshotContent = (
  left: LeafTabSyncSnapshot | null,
  right: LeafTabSyncSnapshot | null,
) => {
  if (!left && !right) return true;
  if (!left || !right) return false;
  const comparableMeta = (snapshot: LeafTabSyncSnapshot) => {
    const { deviceId: _deviceId, generatedAt: _generatedAt, ...preservedMeta } = snapshot.meta;
    return preservedMeta;
  };
  return JSON.stringify({
    meta: comparableMeta(left),
    bookmarkFolders: left.bookmarkFolders,
    bookmarkItems: left.bookmarkItems,
    bookmarkOrders: left.bookmarkOrders,
    tombstones: left.tombstones,
    appPrivateBookmarks: left.appPrivateBookmarks,
  }) === JSON.stringify({
    meta: comparableMeta(right),
    bookmarkFolders: right.bookmarkFolders,
    bookmarkItems: right.bookmarkItems,
    bookmarkOrders: right.bookmarkOrders,
    tombstones: right.tombstones,
    appPrivateBookmarks: right.appPrivateBookmarks,
  });
};

const cloneSnapshot = (snapshot: LeafTabSyncSnapshot) => {
  return JSON.parse(JSON.stringify(snapshot)) as LeafTabSyncSnapshot;
};

const createSyncResult = (
  result: Omit<LeafTabSyncEngineResult, 'snapshotSummary'>,
): LeafTabSyncEngineResult => ({
  ...result,
  snapshotSummary: summarizeSnapshot(result.snapshot),
});

const createConcurrentConflictSummaryText = (conflictCount: number) => (
  conflictCount > 1
    ? `检测到 ${conflictCount} 处双向修改冲突，请先选择保留本机还是当前同步方式的数据。`
    : '检测到 1 处双向修改冲突，请先选择保留本机还是当前同步方式的数据。'
);

const reportProgress = (
  onProgress: ((progress: LeafTabSyncEngineProgress) => void) | undefined,
  progress: LeafTabSyncEngineProgress,
) => {
  onProgress?.({
    ...progress,
    progress: Math.max(0, Math.min(100, Math.round(progress.progress))),
  });
};

export class LeafTabSyncEngine {
  private readonly config: LeafTabSyncEngineConfig;

  constructor(config: LeafTabSyncEngineConfig) {
    this.config = config;
  }

  private resolveRemoteCommitId(state: LeafTabSyncRemoteState): string | null {
    return state.commitId;
  }

  private async persistCompletedState(
    snapshot: LeafTabSyncSnapshot,
    commitId: string | null,
    completedPendingLocalChangedAt: number,
  ): Promise<void> {
    await this.config.baselineStore.save(createLeafTabSyncBaseline({
      snapshot,
      commitId,
    }));
    await this.config.clearPendingLocalChanges?.(completedPendingLocalChangedAt);
  }

  async analyze(options?: LeafTabSyncEngineAnalyzeOptions): Promise<LeafTabSyncAnalysis> {
    reportProgress(options?.onProgress, {
      stage: 'reading-state',
      progress: 10,
      message: '正在读取本机与远端状态',
    });
    const [baseline, localSnapshot, remoteState] = await Promise.all([
      this.config.baselineStore.load(),
      this.config.buildLocalSnapshot(),
      this.config.remoteStore.readState(),
    ]);
    const result: LeafTabSyncAnalysis = {
      hasBaseline: Boolean(baseline?.snapshot || baseline?.commitId),
      localSummary: summarizeSnapshot(localSnapshot),
      remoteSummary: summarizeSnapshot(remoteState.snapshot),
      remoteCommitId: this.resolveRemoteCommitId(remoteState),
    };
    reportProgress(options?.onProgress, {
      stage: 'completed',
      progress: 100,
      message: '同步状态分析完成',
    });
    return result;
  }

  async sync(
    runOptions?: LeafTabSyncEngineRunOptions,
  ): Promise<LeafTabSyncEngineResult> {
    reportProgress(runOptions?.onProgress, {
      stage: 'reading-state',
      progress: 8,
      message: '正在读取本机与远端数据',
    });
    const completedPendingLocalChangedAt = await this.config.readPendingLocalChanges?.() || 0;
    const [baseline, localSnapshotValue, remoteState] = await Promise.all([
      this.config.baselineStore.load(),
      this.config.buildLocalSnapshot(),
      this.config.remoteStore.readState(),
    ]);
    const localSnapshot = localSnapshotValue;
    const baseSnapshot =
      getLeafTabSyncBaselineSnapshot(baseline) || this.config.createEmptySnapshot();
    const hasBaseline = Boolean(baseline?.snapshot || baseline?.commitId);
    const remoteCommitId = this.resolveRemoteCommitId(remoteState);

    if (!remoteState.snapshot && remoteCommitId) {
      throw new Error('当前同步位置返回了不完整的书签快照，已停止写入以避免覆盖远端数据。');
    }

    if (!hasBaseline && !remoteState.snapshot) {
      reportProgress(runOptions?.onProgress, {
        stage: 'uploading-remote',
        progress: 72,
        message: '正在写入远端数据',
      });
      const writeResult = await this.config.remoteStore.writeState({
        snapshot: localSnapshot,
        deviceId: this.config.deviceId,
        parentCommitId: null,
      });
      await this.persistCompletedState(
        localSnapshot,
        writeResult.commitId,
        completedPendingLocalChangedAt,
      );
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: 'push',
        remoteCommitId: writeResult.commitId,
        snapshot: localSnapshot,
        summaryText: '远端为空，已用本地快照建立首次同步状态',
      });
    }

    const remoteSnapshot = remoteState.snapshot || this.config.createEmptySnapshot();
    if (!hasBaseline && sameSnapshotContent(localSnapshot, remoteSnapshot)) {
      reportProgress(runOptions?.onProgress, {
        stage: 'finalizing',
        progress: 92,
        message: '正在收尾同步结果',
      });
      await this.persistCompletedState(remoteSnapshot, remoteCommitId, completedPendingLocalChangedAt);
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: 'noop',
        remoteCommitId,
        snapshot: remoteSnapshot,
        summaryText: '本机和当前同步位置内容一致，已建立同步基线',
      });
    }

    const localMatchesBaseline = sameSnapshotContent(localSnapshot, baseSnapshot);
    const remoteMatchesBaseline = sameSnapshotContent(remoteSnapshot, baseSnapshot);
    if (!runOptions?.conflictResolution && hasBaseline && localMatchesBaseline && remoteMatchesBaseline) {
      reportProgress(runOptions?.onProgress, {
        stage: 'finalizing',
        progress: 92,
        message: '未检测到变更，正在结束同步',
      });
      await this.persistCompletedState(
        baseSnapshot,
        remoteCommitId || baseline?.commitId || null,
        completedPendingLocalChangedAt,
      );
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: 'noop',
        remoteCommitId: remoteCommitId || baseline?.commitId || null,
        snapshot: baseSnapshot,
        summaryText: '本地与远端均无新增变更',
      });
    }

    reportProgress(runOptions?.onProgress, {
      stage: 'merging',
      progress: 30,
      message: '正在合并本机与远端差异',
    });
    const mergeResult = hasBaseline
      ? mergeLeafTabSyncSnapshot(
          baseSnapshot,
          localSnapshot,
          remoteSnapshot,
          {
            deviceId: this.config.deviceId,
            conflictResolution: runOptions?.conflictResolution,
          },
        )
      : mergeLeafTabSyncSnapshotWithoutBaseline(
          localSnapshot,
          remoteSnapshot,
          { deviceId: this.config.deviceId },
        );
    const finalSnapshot = mergeResult.snapshot;
    const summary = summarizeLeafTabSyncMerge(baseSnapshot, mergeResult);
    const summaryText = formatLeafTabSyncSummaryText(summary);

    if (mergeResult.conflicts.length > 0) {
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '检测到同步冲突，等待处理',
      });
      return createSyncResult({
        kind: 'conflict',
        remoteCommitId,
        snapshot: localSnapshot,
        mergeResult,
        summary,
        summaryText: createConcurrentConflictSummaryText(mergeResult.conflicts.length),
      });
    }

    const remoteNeedsWrite = !sameSnapshotContent(remoteSnapshot, finalSnapshot);
    const localNeedsApply = !sameSnapshotContent(localSnapshot, finalSnapshot);
    let committedId = remoteCommitId;

    if (remoteNeedsWrite) {
      reportProgress(runOptions?.onProgress, {
        stage: 'uploading-remote',
        progress: 72,
        message: '正在写入远端数据',
      });
      const writeResult = await this.config.remoteStore.writeState({
        snapshot: finalSnapshot,
        deviceId: this.config.deviceId,
        parentCommitId: remoteCommitId,
      });
      committedId = writeResult.commitId;
    }

    if (localNeedsApply) {
      reportProgress(runOptions?.onProgress, {
        stage: 'applying-local',
        progress: 86,
        message: '正在将最新结果写入本地',
      });
      await this.config.applyLocalSnapshot(cloneSnapshot(finalSnapshot));
    }

    reportProgress(runOptions?.onProgress, {
      stage: 'finalizing',
      progress: 94,
      message: '正在收尾同步结果',
    });
    await this.persistCompletedState(finalSnapshot, committedId, completedPendingLocalChangedAt);
    reportProgress(runOptions?.onProgress, {
      stage: 'completed',
      progress: 100,
      message: '同步完成',
    });

    const kind: LeafTabSyncEngineResult['kind'] = remoteNeedsWrite
      ? (localNeedsApply ? 'merge' : 'push')
      : (localNeedsApply ? 'pull' : 'noop');
    return createSyncResult({
      kind,
      remoteCommitId: committedId,
      snapshot: finalSnapshot,
      mergeResult,
      summary,
      summaryText,
    });
  }
}

import { createLeafTabSyncBaseline, type LeafTabSyncBaselineStore } from './baseline';
import {
  mergeLeafTabSyncSnapshot,
  mergeLeafTabSyncSnapshotWithoutBaseline,
  type LeafTabSyncConflictResolution,
  type LeafTabSyncMergeIntent,
  type LeafTabSyncMergeResult,
} from './merge';
import type { LeafTabSyncSnapshot } from './schema';
import type { LeafTabSyncHistoryDescriptor } from './schema';
import { countLeafTabLiveBookmarkEntities } from './snapshot';
import { formatLeafTabSyncSummaryText, summarizeLeafTabSyncMerge, type LeafTabSyncChangeSummary } from './summary';
import type { LeafTabSyncRemoteState, LeafTabSyncRemoteStore } from './remoteStore';
import type { LeafTabSyncTombstoneLifecycle } from './historyLifecycle';

export interface LeafTabSyncDataSummary {
  bookmarkFolders: number;
  bookmarkItems: number;
  tombstones: number;
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
  historyLifecycle: LeafTabSyncTombstoneLifecycle;
  buildLocalSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  verifyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  readPendingLocalChanges?: () => Promise<number>;
  clearPendingLocalChanges?: (expectedChangedAt: number) => Promise<void> | void;
  createEmptySnapshot: () => LeafTabSyncSnapshot;
}

export interface LeafTabSyncEngineRunOptions {
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
  conflictResolution?: LeafTabSyncConflictResolution;
  mergeIntent?: LeafTabSyncMergeIntent;
}

const summarizeSnapshot = (snapshot: LeafTabSyncSnapshot | null): LeafTabSyncDataSummary => {
  return countLeafTabLiveBookmarkEntities(snapshot);
};

const stableSnapshotValue = (value: unknown): unknown => {
  if (Array.isArray(value)) {
    return value.map(stableSnapshotValue);
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value as Record<string, unknown>)
        .sort()
        .map((key) => [key, stableSnapshotValue((value as Record<string, unknown>)[key])]),
    );
  }
  return value;
};

const stableSnapshotJson = (value: unknown): string => JSON.stringify(stableSnapshotValue(value));

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
  return stableSnapshotJson({
    meta: comparableMeta(left),
    bookmarkFolders: left.bookmarkFolders,
    bookmarkItems: left.bookmarkItems,
    bookmarkOrders: left.bookmarkOrders,
    tombstones: left.tombstones,
    appPrivateBookmarks: left.appPrivateBookmarks,
  }) === stableSnapshotJson({
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

const REMOTE_CONFIRMATION_RETRY_DELAYS_MS = [250, 750] as const;

const waitForRemoteConfirmationRetry = (delayMs: number) => new Promise<void>((resolve) => {
  globalThis.setTimeout(resolve, delayMs);
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

  private async confirmRemoteCommit(
    expectedCommitId: string,
    expectedSnapshot: LeafTabSyncSnapshot,
    expectedHistory: LeafTabSyncHistoryDescriptor,
  ): Promise<void> {
    let lastReadError: unknown;
    for (let attempt = 0; attempt <= REMOTE_CONFIRMATION_RETRY_DELAYS_MS.length; attempt += 1) {
      try {
        const confirmed = await this.config.remoteStore.readState();
        const matches = confirmed.commitId === expectedCommitId
          && Boolean(confirmed.history)
          && this.config.historyLifecycle.sameHistory(confirmed.history!, expectedHistory)
          && sameSnapshotContent(confirmed.snapshot, expectedSnapshot);
        if (matches) return;
      } catch (error) {
        lastReadError = error;
      }

      if (attempt < REMOTE_CONFIRMATION_RETRY_DELAYS_MS.length) {
        await waitForRemoteConfirmationRetry(REMOTE_CONFIRMATION_RETRY_DELAYS_MS[attempt]);
      }
    }

    if (lastReadError) {
      throw lastReadError;
    }
    throw new Error('当前同步位置未能确认完整的书签提交（远端回读与本次提交不一致，本次写入可能已经成功，请勿重复操作）。');
  }

  private async persistCompletedState(
    existingBaseline: Awaited<ReturnType<LeafTabSyncBaselineStore['load']>>,
    snapshot: LeafTabSyncSnapshot,
    history: LeafTabSyncHistoryDescriptor,
    commitId: string | null,
    completedPendingLocalChangedAt: number,
  ): Promise<void> {
    const baselineMatches = Boolean(
      existingBaseline?.snapshot
      && existingBaseline.commitId === commitId
      && existingBaseline.history
      && this.config.historyLifecycle.sameHistory(existingBaseline.history, history)
      && sameSnapshotContent(existingBaseline.snapshot, snapshot),
    );
    if (!baselineMatches) {
      await this.config.baselineStore.save(createLeafTabSyncBaseline({
        snapshot,
        history,
        commitId,
      }));
    }
    await this.config.historyLifecycle.confirm(history);
    await this.config.clearPendingLocalChanges?.(completedPendingLocalChangedAt);
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
    if (Boolean(remoteState.snapshot) !== Boolean(remoteState.commitId)
      || Boolean(remoteState.snapshot) !== Boolean(remoteState.history)) {
      throw new Error('当前同步位置返回了不完整的书签快照，已停止写入以避免覆盖远端数据。');
    }
    const historyPlan = await this.config.historyLifecycle.planMerge(
      baseline,
      localSnapshotValue,
      remoteState,
      this.config.deviceId,
    );
    const localSnapshot = historyPlan.localSnapshot;
    const baseSnapshot = historyPlan.baselineSnapshot || this.config.createEmptySnapshot();
    const hasBaseline = Boolean(historyPlan.baselineSnapshot);
    const remoteCommitId = this.resolveRemoteCommitId(remoteState);

    if (!hasBaseline && !historyPlan.remoteSnapshot) {
      reportProgress(runOptions?.onProgress, {
        stage: 'uploading-remote',
        progress: 72,
        message: '正在写入远端数据',
      });
      const writeResult = await this.config.remoteStore.writeState({
        snapshot: localSnapshot,
        history: historyPlan.history,
        deviceId: this.config.deviceId,
        parentCommitId: null,
      });
      await this.confirmRemoteCommit(writeResult.commitId, localSnapshot, historyPlan.history);
      await this.persistCompletedState(
        baseline,
        localSnapshot,
        historyPlan.history,
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

    const remoteSnapshot = historyPlan.remoteSnapshot || this.config.createEmptySnapshot();
    if (!hasBaseline
      && !historyPlan.requiresRemoteHistoryWrite
      && sameSnapshotContent(localSnapshot, remoteSnapshot)) {
      reportProgress(runOptions?.onProgress, {
        stage: 'finalizing',
        progress: 92,
        message: '正在收尾同步结果',
      });
      await this.persistCompletedState(
        baseline,
        remoteSnapshot,
        historyPlan.history,
        remoteCommitId,
        completedPendingLocalChangedAt,
      );
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
        baseline,
        baseSnapshot,
        historyPlan.history,
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
            mergeIntent: runOptions?.mergeIntent,
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

    const remoteNeedsWrite = historyPlan.requiresRemoteHistoryWrite
      || !sameSnapshotContent(remoteSnapshot, finalSnapshot);
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
        history: historyPlan.history,
        deviceId: this.config.deviceId,
        parentCommitId: remoteCommitId,
      });
      committedId = writeResult.commitId;
      await this.confirmRemoteCommit(committedId, finalSnapshot, historyPlan.history);
    }

    if (localNeedsApply) {
      reportProgress(runOptions?.onProgress, {
        stage: 'applying-local',
        progress: 86,
        message: '正在将最新结果写入本地',
      });
      await this.config.applyLocalSnapshot(cloneSnapshot(finalSnapshot));
      await this.config.verifyLocalSnapshot(cloneSnapshot(finalSnapshot));
    }

    reportProgress(runOptions?.onProgress, {
      stage: 'finalizing',
      progress: 94,
      message: '正在收尾同步结果',
    });
    await this.persistCompletedState(
      baseline,
      finalSnapshot,
      historyPlan.history,
      committedId,
      completedPendingLocalChangedAt,
    );
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

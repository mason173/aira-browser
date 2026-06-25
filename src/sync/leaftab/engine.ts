import { createLeafTabSyncBaseline, type LeafTabSyncBaselineStore, getLeafTabSyncBaselineSnapshot } from './baseline';
import { mergeLeafTabSyncSnapshot, type LeafTabSyncMergeResult } from './merge';
import { createLeafTabSyncCommitFile, createLeafTabSyncHeadFile, type LeafTabSyncSnapshot } from './schema';
import { countLeafTabLiveBookmarkEntities } from './snapshot';
import { formatLeafTabSyncSummaryText, summarizeLeafTabSyncMerge, type LeafTabSyncChangeSummary } from './summary';
import type {
  LeafTabSyncOperation,
  LeafTabSyncRemoteHead,
  LeafTabSyncRemoteState,
  LeafTabSyncRemoteStore,
} from './remoteStore';
import { applyLeafTabSyncOperations, buildLeafTabSyncOperations } from './operationLog';

export type LeafTabSyncInitialChoice = 'push-local' | 'pull-remote' | 'merge';
export type LeafTabSyncRunMode = 'auto' | LeafTabSyncInitialChoice;

export interface LeafTabSyncDataSummary {
  bookmarkFolders: number;
  bookmarkItems: number;
  tombstones: number;
}

export interface LeafTabSyncAnalysis {
  hasBaseline: boolean;
  localSummary: LeafTabSyncDataSummary;
  remoteSummary: LeafTabSyncDataSummary;
  requiresInitialChoice: boolean;
  suggestedInitialChoice: LeafTabSyncInitialChoice | null;
  remoteCommitId: string | null;
}

export interface LeafTabSyncEngineResult {
  kind: 'noop' | 'push' | 'pull' | 'merge' | 'conflict';
  remoteCommitId: string | null;
  snapshot: LeafTabSyncSnapshot;
  snapshotSummary: LeafTabSyncDataSummary;
  initialChoiceAnalysis?: LeafTabSyncAnalysis;
  mergeResult?: LeafTabSyncMergeResult;
  summary?: LeafTabSyncChangeSummary;
  summaryText?: string;
}

export interface LeafTabSyncEngineProgress {
  stage:
    | 'reading-state'
    | 'merging'
    | 'acquiring-lock'
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
  hasPendingLocalChanges?: () => boolean;
  clearPendingLocalChanges?: () => void;
  buildPendingLocalOperations?: (baseSnapshot: LeafTabSyncSnapshot) => Promise<LeafTabSyncOperation[] | null>;
  clearPendingLocalOperations?: () => Promise<void> | void;
  createEmptySnapshot: () => LeafTabSyncSnapshot;
  rootPath?: string;
}

export interface LeafTabSyncEngineRunOptions {
  localSnapshotOverride?: LeafTabSyncSnapshot;
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
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
  return JSON.stringify({
    bookmarkFolders: left.bookmarkFolders,
    bookmarkItems: left.bookmarkItems,
    bookmarkOrders: left.bookmarkOrders,
    tombstones: left.tombstones,
  }) === JSON.stringify({
    bookmarkFolders: right.bookmarkFolders,
    bookmarkItems: right.bookmarkItems,
    bookmarkOrders: right.bookmarkOrders,
    tombstones: right.tombstones,
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
    ? `检测到 ${conflictCount} 处双向修改冲突，请先选择保留本机还是主同步源数据。`
    : '检测到 1 处双向修改冲突，请先选择保留本机还是主同步源数据。'
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

const emptyRemoteState = (): LeafTabSyncRemoteState => ({
  head: null,
  commit: null,
  snapshot: null,
});

const createRemoteStateFromSnapshot = (
  snapshot: LeafTabSyncSnapshot,
  commitId: string | null,
  parentCommitId: string | null,
  deviceId: string,
  createdAt: string,
): LeafTabSyncRemoteState => {
  if (!commitId) {
    return {
      head: null,
      commit: null,
      snapshot,
    };
  }
  const commit = createLeafTabSyncCommitFile({
    deviceId: deviceId || snapshot.meta.deviceId,
    createdAt: createdAt || snapshot.meta.generatedAt,
    parentCommitId,
    snapshot,
  });
  return {
    head: createLeafTabSyncHeadFile(commitId, createdAt || snapshot.meta.generatedAt),
    commit: {
      ...commit,
      id: commitId,
      parentCommitId,
    },
    snapshot,
  };
};

export class LeafTabSyncEngine {
  private readonly config: LeafTabSyncEngineConfig;

  constructor(config: LeafTabSyncEngineConfig) {
    this.config = config;
  }

  private async readRemoteHeadSafely(): Promise<LeafTabSyncRemoteHead | undefined> {
    if (!this.config.remoteStore.readHead) {
      return undefined;
    }
    try {
      return await this.config.remoteStore.readHead();
    } catch {
      return undefined;
    }
  }

  private async tryReadIncrementalRemoteState(params: {
    baselineCommitId: string | null | undefined;
    baselineSnapshot: LeafTabSyncSnapshot | null;
    remoteCommitId: string | null;
  }): Promise<LeafTabSyncRemoteState | null> {
    if (!this.config.remoteStore.readOperations ||
      !params.baselineSnapshot ||
      !params.baselineCommitId ||
      !params.remoteCommitId ||
      params.remoteCommitId === params.baselineCommitId) {
      return null;
    }
    try {
      const result = await this.config.remoteStore.readOperations({
        sinceCommitId: params.baselineCommitId,
      });
      if (!result.supportsIncremental || result.commitId !== params.remoteCommitId) {
        return null;
      }
      const snapshot = applyLeafTabSyncOperations(
        params.baselineSnapshot,
        result.operations,
        result.deviceId || this.config.deviceId,
        result.createdAt || new Date().toISOString(),
      );
      return createRemoteStateFromSnapshot(
        snapshot,
        result.commitId,
        params.baselineCommitId,
        result.deviceId || this.config.deviceId,
        result.createdAt || snapshot.meta.generatedAt,
      );
    } catch {
      return null;
    }
  }

  private async clearPendingLocalState(): Promise<void> {
    this.config.clearPendingLocalChanges?.();
    await this.config.clearPendingLocalOperations?.();
  }

  private async writeLocalChanges(params: {
    localSnapshot: LeafTabSyncSnapshot;
    baseSnapshot: LeafTabSyncSnapshot;
    parentCommitId: string;
  }) {
    if (this.config.remoteStore.writeOperations) {
      const operations = buildLeafTabSyncOperations(params.baseSnapshot, params.localSnapshot);
      if (operations.length > 0) {
        try {
          return await this.config.remoteStore.writeOperations({
            snapshot: params.localSnapshot,
            operations,
            previousSnapshot: params.baseSnapshot,
            deviceId: this.config.deviceId,
            parentCommitId: params.parentCommitId,
            createdAt: params.localSnapshot.meta.generatedAt,
          });
        } catch {
          // Fall back to the full snapshot path. The parent commit is still checked there.
        }
      }
    }
    return this.config.remoteStore.writeState({
      snapshot: params.localSnapshot,
      previousSnapshot: params.baseSnapshot,
      deviceId: this.config.deviceId,
      parentCommitId: params.parentCommitId,
    });
  }

  private async tryWritePendingLocalOperations(params: {
    baseSnapshot: LeafTabSyncSnapshot;
    parentCommitId: string;
    onProgress?: (progress: LeafTabSyncEngineProgress) => void;
  }): Promise<LeafTabSyncEngineResult | null> {
    if (!this.config.remoteStore.writeOperations || !this.config.buildPendingLocalOperations) {
      return null;
    }
    const operations = await this.config.buildPendingLocalOperations(params.baseSnapshot);
    if (!operations || operations.length <= 0) {
      return null;
    }
    const generatedAt = new Date().toISOString();
    const snapshot = applyLeafTabSyncOperations(
      params.baseSnapshot,
      operations,
      this.config.deviceId,
      generatedAt,
    );
    reportProgress(params.onProgress, {
      stage: 'uploading-remote',
      progress: 72,
      message: '正在上传本地书签操作',
    });
    let writeResult;
    try {
      writeResult = await this.config.remoteStore.writeOperations({
        snapshot,
        operations,
        previousSnapshot: params.baseSnapshot,
        deviceId: this.config.deviceId,
        parentCommitId: params.parentCommitId,
        createdAt: generatedAt,
      });
    } catch {
      return null;
    }
    await this.config.baselineStore.save(createLeafTabSyncBaseline({
      snapshot,
      commitId: writeResult.commit.id,
      rootPath: this.config.rootPath,
    }));
    await this.clearPendingLocalState();
    reportProgress(params.onProgress, {
      stage: 'completed',
      progress: 100,
      message: '同步完成',
    });
    return createSyncResult({
      kind: 'push',
      remoteCommitId: writeResult.commit.id,
      snapshot,
      summaryText: `同步完成：已上传 ${operations.length} 条本机书签操作。`,
    });
  }

  async analyze(options?: LeafTabSyncEngineAnalyzeOptions): Promise<LeafTabSyncAnalysis> {
    reportProgress(options?.onProgress, {
      stage: 'reading-state',
      progress: 10,
      message: '正在读取本机与远端状态',
    });
    const [baseline, localSnapshot, remoteHead] = await Promise.all([
      this.config.baselineStore.load(),
      this.config.buildLocalSnapshot(),
      this.readRemoteHeadSafely(),
    ]);

    const hasBaseline = Boolean(baseline?.snapshot || baseline?.commitId);
    const baselineSnapshot = getLeafTabSyncBaselineSnapshot(baseline);
    let remoteState: LeafTabSyncRemoteState | null = null;
    let remoteSnapshot: LeafTabSyncSnapshot | null = null;
    const remoteHeadSummary = remoteHead?.summary || remoteHead?.commit?.summary;
    let remoteSummary = remoteHeadSummary
      ? {
          bookmarkFolders: remoteHeadSummary.bookmarkFolders,
          bookmarkItems: remoteHeadSummary.bookmarkItems,
          tombstones: remoteHeadSummary.tombstones,
        }
      : summarizeSnapshot(null);

    const remoteCommitId = remoteHead?.commitId ?? null;
    const canUseBaselineAsRemote =
      remoteCommitId !== null &&
      baselineSnapshot !== null &&
      baseline?.commitId === remoteCommitId;

    if (canUseBaselineAsRemote) {
      remoteSnapshot = baselineSnapshot;
      remoteSummary = summarizeSnapshot(remoteSnapshot);
    } else if (remoteHead === undefined || !hasBaseline || (!remoteHeadSummary && remoteCommitId !== null)) {
      remoteState = await this.config.remoteStore.readState();
      remoteSnapshot = remoteState.snapshot;
      remoteSummary = summarizeSnapshot(remoteSnapshot);
    }

    const requiresInitialChoice = !hasBaseline && remoteSnapshot !== null &&
      !sameSnapshotContent(localSnapshot, remoteSnapshot);
    const suggestedInitialChoice: LeafTabSyncInitialChoice | null = requiresInitialChoice ? 'merge' : null;
    const result: LeafTabSyncAnalysis = {
      hasBaseline,
      localSummary: summarizeSnapshot(localSnapshot),
      remoteSummary,
      requiresInitialChoice,
      suggestedInitialChoice,
      remoteCommitId: remoteState?.commit?.id || remoteCommitId,
    };
    reportProgress(options?.onProgress, {
      stage: 'completed',
      progress: 100,
      message: '同步状态分析完成',
    });
    return result;
  }

  async sync(
    mode: LeafTabSyncRunMode = 'auto',
    runOptions?: LeafTabSyncEngineRunOptions,
  ): Promise<LeafTabSyncEngineResult> {
    reportProgress(runOptions?.onProgress, {
      stage: 'reading-state',
      progress: 8,
      message: '正在读取本机与远端数据',
    });
    const [baseline, remoteHead] = await Promise.all([
      this.config.baselineStore.load(),
      this.readRemoteHeadSafely(),
    ]);

    const baseSnapshot =
      getLeafTabSyncBaselineSnapshot(baseline) || this.config.createEmptySnapshot();
    const hasBaseline = Boolean(baseline?.snapshot || baseline?.commitId);
    const hasPendingLocalChanges = this.config.hasPendingLocalChanges?.() === true;
    let localSnapshotCache: LeafTabSyncSnapshot | null = null;
    const getLocalSnapshot = async () => {
      if (localSnapshotCache) {
        return localSnapshotCache;
      }
      localSnapshotCache = runOptions?.localSnapshotOverride
        ? cloneSnapshot(runOptions.localSnapshotOverride)
        : await this.config.buildLocalSnapshot();
      return localSnapshotCache;
    };
    let remoteState: LeafTabSyncRemoteState = emptyRemoteState();
    let remoteSnapshot: LeafTabSyncSnapshot = this.config.createEmptySnapshot();
    const remoteCommitId = remoteHead?.commitId ?? null;

    if (mode === 'auto' && hasBaseline && baseline?.commitId && remoteCommitId === baseline.commitId) {
      if (!hasPendingLocalChanges) {
        reportProgress(runOptions?.onProgress, {
          stage: 'finalizing',
          progress: 92,
          message: '未检测到变更，正在结束同步',
        });
        await this.config.baselineStore.save(createLeafTabSyncBaseline({
          snapshot: baseSnapshot,
          commitId: baseline.commitId,
          rootPath: this.config.rootPath,
        }));
        reportProgress(runOptions?.onProgress, {
          stage: 'completed',
          progress: 100,
          message: '同步完成',
        });
        return createSyncResult({
          kind: 'noop',
          remoteCommitId: baseline.commitId,
          snapshot: baseSnapshot,
          summaryText: '本地与远端均无新增变更',
        });
      }

      if (!runOptions?.localSnapshotOverride) {
        reportProgress(runOptions?.onProgress, {
          stage: 'acquiring-lock',
          progress: 34,
          message: '正在锁定同步位置',
        });
        await this.config.remoteStore.acquireLock(this.config.deviceId);
        try {
          reportProgress(runOptions?.onProgress, {
            stage: 'rechecking-remote',
            progress: 52,
            message: '正在确认远端最新状态',
          });
          const latestHead = await this.readRemoteHeadSafely();
          if (latestHead?.commitId === baseline.commitId) {
            const operationResult = await this.tryWritePendingLocalOperations({
              baseSnapshot,
              parentCommitId: baseline.commitId,
              onProgress: runOptions?.onProgress,
            });
            if (operationResult) {
              return operationResult;
            }
          }
        } finally {
          await this.config.remoteStore.releaseLock();
        }
      }

      const localSnapshot = await getLocalSnapshot();
      const localMatchesBaseline = sameSnapshotContent(localSnapshot, baseSnapshot);
      if (localMatchesBaseline) {
        reportProgress(runOptions?.onProgress, {
          stage: 'finalizing',
          progress: 92,
          message: '未检测到变更，正在结束同步',
        });
        await this.config.baselineStore.save(createLeafTabSyncBaseline({
          snapshot: baseSnapshot,
          commitId: baseline.commitId,
          rootPath: this.config.rootPath,
        }));
        reportProgress(runOptions?.onProgress, {
          stage: 'completed',
          progress: 100,
          message: '同步完成',
        });
        return createSyncResult({
          kind: 'noop',
          remoteCommitId: baseline.commitId,
          snapshot: baseSnapshot,
          summaryText: '本地与远端均无新增变更',
        });
      }

      if (hasPendingLocalChanges) {
        reportProgress(runOptions?.onProgress, {
          stage: 'acquiring-lock',
          progress: 34,
          message: '正在锁定同步位置',
        });
        await this.config.remoteStore.acquireLock(this.config.deviceId);
        try {
          reportProgress(runOptions?.onProgress, {
            stage: 'rechecking-remote',
            progress: 52,
            message: '正在确认远端最新状态',
          });
          const latestHead = await this.readRemoteHeadSafely();
          if (latestHead?.commitId === baseline.commitId) {
            reportProgress(runOptions?.onProgress, {
              stage: 'uploading-remote',
              progress: 72,
              message: '正在上传本地变更',
            });
            const writeResult = await this.writeLocalChanges({
              localSnapshot,
              baseSnapshot,
              parentCommitId: baseline.commitId,
            });
            await this.config.baselineStore.save(createLeafTabSyncBaseline({
              snapshot: localSnapshot,
              commitId: writeResult.commit.id,
              rootPath: this.config.rootPath,
            }));
            await this.clearPendingLocalState();
            await this.config.clearPendingLocalOperations?.();
            reportProgress(runOptions?.onProgress, {
              stage: 'completed',
              progress: 100,
              message: '同步完成',
            });
            return createSyncResult({
              kind: 'push',
              remoteCommitId: writeResult.commit.id,
              snapshot: localSnapshot,
              summaryText: '同步完成：远端没有新的变化，已上传本地变化。',
            });
          }
        } finally {
          await this.config.remoteStore.releaseLock();
        }
      }
    }

    if (mode === 'auto' && !hasBaseline && remoteHead !== undefined && remoteCommitId === null) {
      const localSnapshot = await getLocalSnapshot();
      reportProgress(runOptions?.onProgress, {
        stage: 'acquiring-lock',
        progress: 34,
        message: '正在锁定同步位置',
      });
      await this.config.remoteStore.acquireLock(this.config.deviceId);
      try {
        reportProgress(runOptions?.onProgress, {
          stage: 'rechecking-remote',
          progress: 52,
          message: '正在确认远端最新状态',
        });
        const latestHead = await this.readRemoteHeadSafely();
        if (latestHead?.commitId) {
          remoteState = await this.config.remoteStore.readState();
        } else {
          reportProgress(runOptions?.onProgress, {
            stage: 'uploading-remote',
            progress: 72,
            message: '正在写入远端数据',
          });
          const writeResult = await this.config.remoteStore.writeState({
            snapshot: localSnapshot,
            previousSnapshot: null,
            deviceId: this.config.deviceId,
            parentCommitId: null,
          });
          await this.config.baselineStore.save(createLeafTabSyncBaseline({
            snapshot: localSnapshot,
            commitId: writeResult.commit.id,
            rootPath: this.config.rootPath,
          }));
          await this.clearPendingLocalState();
          reportProgress(runOptions?.onProgress, {
            stage: 'completed',
            progress: 100,
            message: '同步完成',
          });
          return createSyncResult({
            kind: 'push',
            remoteCommitId: writeResult.commit.id,
            snapshot: localSnapshot,
            summaryText: '远端为空，已用本地快照建立首次同步状态',
          });
        }
      } finally {
        await this.config.remoteStore.releaseLock();
      }
    }

    if (!remoteState.snapshot && mode === 'auto' && hasBaseline && remoteHead !== undefined && remoteCommitId !== null) {
      remoteState = await this.tryReadIncrementalRemoteState({
        baselineCommitId: baseline?.commitId,
        baselineSnapshot: baseSnapshot,
        remoteCommitId,
      }) || remoteState;
    }

    if (!remoteState.snapshot && (remoteHead === undefined || remoteCommitId !== null || mode !== 'auto')) {
      remoteState = await this.config.remoteStore.readState();
    }
    remoteSnapshot = remoteState.snapshot || this.config.createEmptySnapshot();
    const remoteMatchesBaseline = sameSnapshotContent(remoteSnapshot, baseSnapshot);

    if (mode === 'auto' && hasBaseline && !hasPendingLocalChanges) {
      const authoritativeSnapshot = remoteMatchesBaseline ? baseSnapshot : remoteSnapshot;
      const authoritativeCommitId = remoteMatchesBaseline
        ? (baseline?.commitId || remoteState.commit?.id || remoteCommitId || null)
        : (remoteState.commit?.id || remoteCommitId || null);

      if (!remoteMatchesBaseline) {
        reportProgress(runOptions?.onProgress, {
          stage: 'applying-local',
          progress: 70,
          message: remoteMatchesBaseline
            ? '正在按主同步源基线恢复本机数据'
            : '主同步源已有更新，正在写入本机',
        });
        await this.config.applyLocalSnapshot(cloneSnapshot(authoritativeSnapshot));
      }

      reportProgress(runOptions?.onProgress, {
        stage: 'finalizing',
        progress: 92,
        message: '正在收尾同步结果',
      });
      await this.config.baselineStore.save(createLeafTabSyncBaseline({
        snapshot: authoritativeSnapshot,
        commitId: authoritativeCommitId,
        rootPath: this.config.rootPath,
      }));
      await this.clearPendingLocalState();
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: remoteMatchesBaseline ? 'noop' : 'pull',
        remoteCommitId: authoritativeCommitId,
        snapshot: authoritativeSnapshot,
        summaryText: remoteMatchesBaseline
          ? '本地与远端均无新增变更'
          : '主同步源已有更新，本机没有待同步变更，已优先使用远端数据。',
      });
    }

    const localSnapshot = await getLocalSnapshot();
    const localMatchesBaseline = sameSnapshotContent(localSnapshot, baseSnapshot);

    if (mode === 'auto' && !hasBaseline) {
      if (remoteState.snapshot) {
        if (!sameSnapshotContent(localSnapshot, remoteSnapshot)) {
          reportProgress(runOptions?.onProgress, {
            stage: 'completed',
            progress: 100,
            message: '需要选择首次同步方式',
          });
          return createSyncResult({
            kind: 'conflict',
            remoteCommitId: remoteState.commit?.id || null,
            snapshot: localSnapshot,
            initialChoiceAnalysis: {
              hasBaseline,
              localSummary: summarizeSnapshot(localSnapshot),
              remoteSummary: summarizeSnapshot(remoteSnapshot),
              requiresInitialChoice: true,
              suggestedInitialChoice: 'merge',
              remoteCommitId: remoteState.commit?.id || null,
            },
            summaryText: '本机和远端都有书签数据，请先选择首次同步方式',
          });
        }
        reportProgress(runOptions?.onProgress, {
          stage: 'finalizing',
          progress: 92,
          message: '正在收尾同步结果',
        });
        await this.config.baselineStore.save(createLeafTabSyncBaseline({
          snapshot: remoteSnapshot,
          commitId: remoteState.commit?.id || null,
          rootPath: this.config.rootPath,
        }));
        await this.clearPendingLocalState();
        reportProgress(runOptions?.onProgress, {
          stage: 'completed',
          progress: 100,
          message: '同步完成',
        });
        return createSyncResult({
          kind: sameSnapshotContent(localSnapshot, remoteSnapshot) ? 'noop' : 'pull',
          remoteCommitId: remoteState.commit?.id || null,
          snapshot: remoteSnapshot,
          summaryText: '尚未建立基线，已优先使用远端快照',
        });
      }

      reportProgress(runOptions?.onProgress, {
        stage: 'acquiring-lock',
        progress: 34,
        message: '正在锁定同步位置',
      });
      await this.config.remoteStore.acquireLock(this.config.deviceId);
      try {
        reportProgress(runOptions?.onProgress, {
          stage: 'rechecking-remote',
          progress: 52,
          message: '正在重新确认远端最新状态',
        });
        const latestRemote = await this.config.remoteStore.readState();
        if (latestRemote.snapshot) {
          reportProgress(runOptions?.onProgress, {
            stage: 'applying-local',
            progress: 70,
            message: '正在用远端数据建立本机同步基线',
          });
          await this.config.applyLocalSnapshot(latestRemote.snapshot);
          await this.config.baselineStore.save(createLeafTabSyncBaseline({
            snapshot: latestRemote.snapshot,
            commitId: latestRemote.commit?.id || null,
            rootPath: this.config.rootPath,
          }));
          reportProgress(runOptions?.onProgress, {
            stage: 'completed',
            progress: 100,
            message: '同步完成',
          });
          return createSyncResult({
            kind: 'pull',
            remoteCommitId: latestRemote.commit?.id || null,
            snapshot: latestRemote.snapshot,
            summaryText: '尚未建立基线，已优先使用远端快照',
          });
        }

        reportProgress(runOptions?.onProgress, {
          stage: 'uploading-remote',
          progress: 72,
          message: '正在写入远端数据',
        });
        const writeResult = await this.config.remoteStore.writeState({
          snapshot: localSnapshot,
          previousSnapshot: null,
          deviceId: this.config.deviceId,
          parentCommitId: null,
        });
        await this.config.baselineStore.save(createLeafTabSyncBaseline({
          snapshot: localSnapshot,
          commitId: writeResult.commit.id,
          rootPath: this.config.rootPath,
        }));
        await this.clearPendingLocalState();
        reportProgress(runOptions?.onProgress, {
          stage: 'completed',
          progress: 100,
          message: '同步完成',
        });
        return createSyncResult({
          kind: 'push',
          remoteCommitId: writeResult.commit.id,
          snapshot: localSnapshot,
          summaryText: '远端为空，已用本地快照建立首次同步状态',
        });
      } finally {
        await this.config.remoteStore.releaseLock();
      }
    }

    if (mode === 'auto' && hasBaseline && localMatchesBaseline && remoteMatchesBaseline) {
      reportProgress(runOptions?.onProgress, {
        stage: 'finalizing',
        progress: 92,
        message: '未检测到变更，正在结束同步',
      });
      await this.config.baselineStore.save(createLeafTabSyncBaseline({
        snapshot: baseSnapshot,
        commitId: remoteState.commit?.id || baseline?.commitId || null,
        rootPath: this.config.rootPath,
      }));
      await this.clearPendingLocalState();
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: 'noop',
        remoteCommitId: remoteState.commit?.id || baseline?.commitId || null,
        snapshot: baseSnapshot,
        summaryText: '本地与远端均无新增变更',
      });
    }

    if (mode === 'push-local') {
      reportProgress(runOptions?.onProgress, {
        stage: 'acquiring-lock',
        progress: 34,
        message: '正在锁定同步位置',
      });
      await this.config.remoteStore.acquireLock(this.config.deviceId);
      try {
        reportProgress(runOptions?.onProgress, {
          stage: 'rechecking-remote',
          progress: 52,
          message: '正在重新确认远端最新状态',
        });
        const latestRemote = await this.config.remoteStore.readState();
        const latestRemoteSnapshot = latestRemote.snapshot || this.config.createEmptySnapshot();

        if (sameSnapshotContent(latestRemoteSnapshot, localSnapshot)) {
          reportProgress(runOptions?.onProgress, {
            stage: 'finalizing',
            progress: 92,
            message: '正在收尾同步结果',
          });
          await this.config.baselineStore.save(createLeafTabSyncBaseline({
            snapshot: localSnapshot,
            commitId: latestRemote.commit?.id || null,
            rootPath: this.config.rootPath,
          }));
          await this.clearPendingLocalState();
          reportProgress(runOptions?.onProgress, {
            stage: 'completed',
            progress: 100,
            message: '同步完成',
          });
          return createSyncResult({
            kind: 'noop',
            remoteCommitId: latestRemote.commit?.id || null,
            snapshot: localSnapshot,
            summaryText: '远端数据已经和本地一致',
          });
        }

        reportProgress(runOptions?.onProgress, {
          stage: 'uploading-remote',
          progress: 68,
          message: '正在写入远端数据',
        });
        const writeResult = await this.config.remoteStore.writeState({
          snapshot: localSnapshot,
          previousSnapshot: latestRemote.snapshot,
          deviceId: this.config.deviceId,
          parentCommitId: latestRemote.commit?.id || null,
        });
        reportProgress(runOptions?.onProgress, {
          stage: 'finalizing',
          progress: 92,
          message: '正在收尾同步结果',
        });
        await this.config.baselineStore.save(createLeafTabSyncBaseline({
          snapshot: localSnapshot,
          commitId: writeResult.commit.id,
          rootPath: this.config.rootPath,
        }));
        await this.clearPendingLocalState();
        reportProgress(runOptions?.onProgress, {
          stage: 'completed',
          progress: 100,
          message: '同步完成',
        });
        return createSyncResult({
          kind: 'push',
          remoteCommitId: writeResult.commit.id,
          snapshot: localSnapshot,
          summaryText: '已将本地数据写入远端',
        });
      } finally {
        await this.config.remoteStore.releaseLock();
      }
    }

    if (mode === 'pull-remote') {
      if (!sameSnapshotContent(localSnapshot, remoteSnapshot)) {
        reportProgress(runOptions?.onProgress, {
          stage: 'applying-local',
          progress: 62,
          message: '正在将远端数据写入本地',
        });
        await this.config.applyLocalSnapshot(remoteSnapshot);
      }
      reportProgress(runOptions?.onProgress, {
        stage: 'finalizing',
        progress: 92,
        message: '正在收尾同步结果',
      });
      await this.config.baselineStore.save(createLeafTabSyncBaseline({
        snapshot: remoteSnapshot,
        commitId: remoteState.commit?.id || null,
        rootPath: this.config.rootPath,
      }));
      await this.clearPendingLocalState();
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: sameSnapshotContent(localSnapshot, remoteSnapshot) ? 'noop' : 'pull',
        remoteCommitId: remoteState.commit?.id || null,
        snapshot: remoteSnapshot,
        summaryText: sameSnapshotContent(localSnapshot, remoteSnapshot)
          ? '本地与远端数据已经一致'
          : '已从远端拉取同步数据',
      });
    }

    reportProgress(runOptions?.onProgress, {
      stage: 'merging',
      progress: 24,
      message: '正在合并本机与远端差异',
    });
    const mergeResult = mergeLeafTabSyncSnapshot(
      baseSnapshot,
      localSnapshot,
      remoteSnapshot,
      {
        deviceId: this.config.deviceId,
      },
    );

    let finalMergeResult = mergeResult;
    let finalSnapshot = mergeResult.snapshot;
    let finalSummary = summarizeLeafTabSyncMerge(baseSnapshot, finalMergeResult);
    let finalSummaryText = formatLeafTabSyncSummaryText(finalSummary);

    if (finalMergeResult.conflicts.length > 0) {
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '检测到同步冲突，等待处理',
      });
      return createSyncResult({
        kind: 'conflict',
        remoteCommitId: remoteState.commit?.id || remoteCommitId || null,
        snapshot: localSnapshot,
        mergeResult: finalMergeResult,
        summary: finalSummary,
        summaryText: createConcurrentConflictSummaryText(finalMergeResult.conflicts.length),
      });
    }

    if (!sameSnapshotContent(remoteSnapshot, finalSnapshot)) {
      reportProgress(runOptions?.onProgress, {
        stage: 'acquiring-lock',
        progress: 40,
        message: '正在锁定同步位置',
      });
      await this.config.remoteStore.acquireLock(this.config.deviceId);
      try {
        reportProgress(runOptions?.onProgress, {
          stage: 'rechecking-remote',
          progress: 54,
          message: '正在重新确认远端最新状态',
        });
        const latestRemote = await this.config.remoteStore.readState();
        const latestRemoteSnapshot = latestRemote.snapshot || this.config.createEmptySnapshot();
        if (!sameSnapshotContent(latestRemoteSnapshot, remoteSnapshot)) {
          finalMergeResult = mergeLeafTabSyncSnapshot(
            baseSnapshot,
            localSnapshot,
            latestRemoteSnapshot,
            { deviceId: this.config.deviceId },
          );
          finalSnapshot = finalMergeResult.snapshot;
          finalSummary = summarizeLeafTabSyncMerge(baseSnapshot, finalMergeResult);
          finalSummaryText = formatLeafTabSyncSummaryText(finalSummary);
          if (finalMergeResult.conflicts.length > 0) {
            reportProgress(runOptions?.onProgress, {
              stage: 'completed',
              progress: 100,
              message: '检测到同步冲突，等待处理',
            });
            return createSyncResult({
              kind: 'conflict',
              remoteCommitId: latestRemote.commit?.id || null,
              snapshot: localSnapshot,
              mergeResult: finalMergeResult,
              summary: finalSummary,
              summaryText: createConcurrentConflictSummaryText(finalMergeResult.conflicts.length),
            });
          }
        }

        if (!sameSnapshotContent(latestRemoteSnapshot, finalSnapshot)) {
          reportProgress(runOptions?.onProgress, {
            stage: 'uploading-remote',
            progress: 72,
            message: '正在写入远端数据',
          });
          const writeResult = await this.config.remoteStore.writeState({
            snapshot: finalSnapshot,
            previousSnapshot: latestRemote.snapshot,
            deviceId: this.config.deviceId,
            parentCommitId: latestRemote.commit?.id || null,
          });
          await this.config.baselineStore.save(createLeafTabSyncBaseline({
            snapshot: finalSnapshot,
            commitId: writeResult.commit.id,
            rootPath: this.config.rootPath,
          }));
          await this.clearPendingLocalState();

          if (!sameSnapshotContent(localSnapshot, finalSnapshot)) {
            reportProgress(runOptions?.onProgress, {
              stage: 'applying-local',
              progress: 88,
              message: '正在将最新结果写入本地',
            });
            await this.config.applyLocalSnapshot(cloneSnapshot(finalSnapshot));
          }

          reportProgress(runOptions?.onProgress, {
            stage: 'completed',
            progress: 100,
            message: '同步完成',
          });
          return createSyncResult({
            kind: sameSnapshotContent(localSnapshot, finalSnapshot) ? 'push' : 'merge',
            remoteCommitId: writeResult.commit.id,
            snapshot: finalSnapshot,
            mergeResult: finalMergeResult,
            summary: finalSummary,
            summaryText: finalSummaryText,
          });
        }

        await this.config.baselineStore.save(createLeafTabSyncBaseline({
          snapshot: finalSnapshot,
          commitId: latestRemote.commit?.id || null,
          rootPath: this.config.rootPath,
        }));
        await this.clearPendingLocalState();

        if (!sameSnapshotContent(localSnapshot, finalSnapshot)) {
          reportProgress(runOptions?.onProgress, {
            stage: 'applying-local',
            progress: 86,
            message: '正在将远端数据写入本地',
          });
          await this.config.applyLocalSnapshot(cloneSnapshot(finalSnapshot));
          reportProgress(runOptions?.onProgress, {
            stage: 'completed',
            progress: 100,
            message: '同步完成',
          });
          return createSyncResult({
            kind: 'pull',
            remoteCommitId: latestRemote.commit?.id || null,
            snapshot: finalSnapshot,
            mergeResult: finalMergeResult,
            summary: finalSummary,
            summaryText: finalSummaryText,
          });
        }

        reportProgress(runOptions?.onProgress, {
          stage: 'completed',
          progress: 100,
          message: '同步完成',
        });
        return createSyncResult({
          kind: 'noop',
          remoteCommitId: latestRemote.commit?.id || null,
          snapshot: finalSnapshot,
          mergeResult: finalMergeResult,
          summary: finalSummary,
          summaryText: finalSummaryText,
        });
      } finally {
        await this.config.remoteStore.releaseLock();
      }
    }

    if (sameSnapshotContent(localSnapshot, finalSnapshot)) {
      reportProgress(runOptions?.onProgress, {
        stage: 'finalizing',
        progress: 92,
        message: '正在收尾同步结果',
      });
      await this.config.baselineStore.save(createLeafTabSyncBaseline({
        snapshot: finalSnapshot,
        commitId: remoteState.commit?.id || null,
        rootPath: this.config.rootPath,
      }));
      await this.clearPendingLocalState();
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: 'noop',
        remoteCommitId: remoteState.commit?.id || null,
        snapshot: finalSnapshot,
        mergeResult: finalMergeResult,
        summary: finalSummary,
        summaryText: finalSummaryText,
      });
    }

    reportProgress(runOptions?.onProgress, {
      stage: 'applying-local',
      progress: 84,
      message: '正在将远端数据写入本地',
    });
    await this.config.applyLocalSnapshot(cloneSnapshot(finalSnapshot));
    reportProgress(runOptions?.onProgress, {
      stage: 'finalizing',
      progress: 94,
      message: '正在收尾同步结果',
    });
    await this.config.baselineStore.save(createLeafTabSyncBaseline({
      snapshot: finalSnapshot,
      commitId: remoteState.commit?.id || null,
      rootPath: this.config.rootPath,
    }));
    await this.clearPendingLocalState();

    reportProgress(runOptions?.onProgress, {
      stage: 'completed',
      progress: 100,
      message: '同步完成',
    });

    return createSyncResult({
      kind: 'pull',
      remoteCommitId: remoteState.commit?.id || null,
      snapshot: finalSnapshot,
      mergeResult: finalMergeResult,
      summary: finalSummary,
      summaryText: finalSummaryText,
    });
  }
}

import { createLeafTabSyncBaseline, type LeafTabSyncBaselineStore } from './baseline';
import {
  mergeLeafTabSyncSnapshot,
  mergeLeafTabSyncSnapshotWithoutBaseline,
  type LeafTabSyncConflictResolution,
  type LeafTabSyncMergeIntent,
  type LeafTabSyncMergeResult,
} from './merge';
import type {
  LeafTabSyncBaseline,
  LeafTabSyncBookmarkFolderEntity,
  LeafTabSyncBookmarkItemEntity,
  LeafTabSyncSnapshot,
} from './schema';
import { createLeafTabSyncTombstoneKey, validateCanonicalLeafTabSyncSnapshot, type LeafTabSyncHistoryDescriptor } from './schema';
import { buildComputerOverwriteSnapshot, countLeafTabLiveBookmarkEntities, deduplicateFirstJoinBookmarks, isComputerOverwriteActor, materializeRemoteOverwrite, reconcileNativeBookmarkRoots } from './snapshot';
import { canonicalizeSnapshotBookmarkUrls } from './chromeBookmarkUrl';
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
  // First-join only: adopt the remote's identity for content-identical local
  // entities so a device with no baseline converges instead of duplicating.
  adoptLocalIdentity?: (remoteSnapshot: LeafTabSyncSnapshot) => Promise<LeafTabSyncSnapshot | null>;
}

export type BookmarkOverwriteDirection = 'computer-to-remote' | 'remote-to-computer';

export interface LeafTabSyncEngineRunOptions {
  overwrite?: BookmarkOverwriteDirection;
  beforeOverwrite?: (direction: BookmarkOverwriteDirection) => Promise<void>;
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

const canonicalizeBookmarkDataSet = (
  value: NonNullable<LeafTabSyncSnapshot['appPrivateBookmarks']> | LeafTabSyncSnapshot,
) => {
  const dataSet = {
    bookmarkFolders: value.bookmarkFolders,
    bookmarkItems: value.bookmarkItems,
    bookmarkOrders: value.bookmarkOrders,
    tombstones: value.tombstones,
  };
  return {
    bookmarkFolders: Object.fromEntries(
      Object.values(dataSet.bookmarkFolders)
        .slice()
        .sort((left, right) => left.id.localeCompare(right.id))
        .map((entry) => [entry.id, entry]),
    ),
    bookmarkItems: Object.fromEntries(
      Object.values(dataSet.bookmarkItems)
        .slice()
        .sort((left, right) => left.id.localeCompare(right.id))
        .map((entry) => [entry.id, entry]),
    ),
    bookmarkOrders: Object.fromEntries(
      Object.values(dataSet.bookmarkOrders)
        .slice()
        .sort((left, right) => String(left.parentId ?? '').localeCompare(String(right.parentId ?? '')))
        .map((entry) => [entry.parentId === null ? '__root__' : entry.parentId, entry]),
    ),
    tombstones: Object.fromEntries(
      Object.values(dataSet.tombstones)
        .slice()
        .sort((left, right) => `${left.type}|${left.id}`.localeCompare(`${right.type}|${right.id}`))
        .map((entry) => [`${entry.type}|${entry.id}`, entry]),
    ),
  };
};

const sameSnapshotContent = (
  left: LeafTabSyncSnapshot | null,
  right: LeafTabSyncSnapshot | null,
) => {
  if (!left && !right) return true;
  if (!left || !right) return false;
  return stableSnapshotJson({
    meta: { version: left.meta.version },
    ...canonicalizeBookmarkDataSet(left),
    appPrivateBookmarks: left.appPrivateBookmarks
      ? canonicalizeBookmarkDataSet(left.appPrivateBookmarks)
      : undefined,
  }) === stableSnapshotJson({
    meta: { version: right.meta.version },
    ...canonicalizeBookmarkDataSet(right),
    appPrivateBookmarks: right.appPrivateBookmarks
      ? canonicalizeBookmarkDataSet(right.appPrivateBookmarks)
      : undefined,
  });
};

const sameMaterializedBookmarkContent = (
  left: LeafTabSyncSnapshot | null,
  right: LeafTabSyncSnapshot | null,
) => {
  if (!left && !right) return true;
  if (!left || !right) return false;
  return stableSnapshotJson({
    meta: { version: left.meta.version },
    ...canonicalizeBookmarkDataSet(left),
  }) === stableSnapshotJson({
    meta: { version: right.meta.version },
    ...canonicalizeBookmarkDataSet(right),
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

// Local apply/verify is the only step that can fail deterministically on a poisoned
// local tree while the remote write keeps succeeding; auto-sync must be able to tell
// that failure class apart (2026-10 conflict-dialog loop, uid 2029059012955225536).
export class LeafTabSyncLocalApplyVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LeafTabSyncLocalApplyVerificationError';
  }
}

const RUNAWAY_DELETION_MIN_ENTITIES = 50;
const RUNAWAY_DELETION_RATIO = 0.5;
const RUNAWAY_DUPLICATE_CREATION_LIMIT = 50;

const createRunawayContentKey = (
  entity: LeafTabSyncBookmarkFolderEntity | LeafTabSyncBookmarkItemEntity,
) => `${entity.type}|${entity.parentId || '__root__'}|${entity.title}|${
  entity.type === 'bookmark-item' ? entity.url : ''
}`;

// Steady-state runaway protection: one full-sync round silently deleting most of the
// account, or exploding duplicate-content creations, is the signature of a sick identity
// layer rather than user edits (the 2026-10 incident grew 400+ duplicates this way).
// Abort before any local apply or remote write so the failure cannot spread to other
// devices. First joins have no baseline and legitimately create a complete tree.
const evaluateLeafTabSyncRunawayGuard = (
  baseSnapshot: LeafTabSyncSnapshot,
  nextSnapshot: LeafTabSyncSnapshot,
  remoteSnapshot: LeafTabSyncSnapshot,
): string | null => {
  const baseEntities = [
    ...Object.values(baseSnapshot.bookmarkFolders),
    ...Object.values(baseSnapshot.bookmarkItems),
  ];
  const nextIds = new Set([
    ...Object.keys(nextSnapshot.bookmarkFolders),
    ...Object.keys(nextSnapshot.bookmarkItems),
  ]);
  // Count removals introduced by this merge. An already committed remote deletion
  // must still reach paired devices, including those with unrelated local edits.
  const deletions = baseEntities.filter(entity =>
    !nextIds.has(entity.id) && !isComputerOverwriteActor(
      remoteSnapshot.tombstones[createLeafTabSyncTombstoneKey(entity.type, entity.id)]?.deletedBy,
    ),
  ).length;
  if (deletions > RUNAWAY_DELETION_MIN_ENTITIES
    && deletions > baseEntities.length * RUNAWAY_DELETION_RATIO) {
    return `本轮同步将删除 ${deletions} 条书签（超过现有书签的一半），已自动中止以保护数据。如确需批量删除，请分批操作后再同步。`;
  }

  const baseIds = new Set(baseEntities.map((entity) => entity.id));
  const nextEntities = [
    ...Object.values(nextSnapshot.bookmarkFolders),
    ...Object.values(nextSnapshot.bookmarkItems),
  ];
  const nextContentCounts = new Map<string, number>();
  nextEntities.forEach((entity) => {
    const key = createRunawayContentKey(entity);
    nextContentCounts.set(key, (nextContentCounts.get(key) || 0) + 1);
  });
  const duplicateCreations = nextEntities.filter(entity => {
    if (baseIds.has(entity.id)) return false;
    const key = createRunawayContentKey(entity);
    const committed = remoteSnapshot.bookmarkFolders[entity.id] || remoteSnapshot.bookmarkItems[entity.id];
    const authorized = committed && isComputerOverwriteActor(committed.updatedBy) && createRunawayContentKey(committed) === key;
    return (nextContentCounts.get(key) || 0) > 1 && !authorized;
  }).length;
  if (duplicateCreations > RUNAWAY_DUPLICATE_CREATION_LIMIT) {
    return `本轮同步将新增 ${duplicateCreations} 条内容完全相同的重复书签，已自动中止。请先清理本机重复书签后再同步。`;
  }
  return null;
};

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
  ): Promise<{
    snapshot: LeafTabSyncSnapshot;
    history: LeafTabSyncHistoryDescriptor;
    commitId: string;
  }> {
    let lastReadError: unknown;
    for (let attempt = 0; attempt <= REMOTE_CONFIRMATION_RETRY_DELAYS_MS.length; attempt += 1) {
      try {
        const confirmed = await this.config.remoteStore.readState();
        if (
          confirmed.commitId === expectedCommitId
          && confirmed.snapshot
          && confirmed.history
        ) {
          return {
            snapshot: confirmed.snapshot,
            history: confirmed.history,
            commitId: confirmed.commitId,
          };
        }
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

  private async overwriteBookmarks(
    direction: BookmarkOverwriteDirection,
    options: LeafTabSyncEngineRunOptions,
    baseline: LeafTabSyncBaseline | null,
    local: LeafTabSyncSnapshot,
    initialRemote: LeafTabSyncRemoteState,
    pendingLocalChange: number,
  ): Promise<LeafTabSyncEngineResult> {
    const push = direction === 'computer-to-remote';
    if (!local.bookmarkOrders.__root__?.ids.length) {
      throw new Error('未读取到电脑的书签根目录，请重新授权或重试覆盖。');
    }
    let remote = initialRemote;
    let armed = false;
    const beforeMutation = async () => {
      if (armed) return;
      await options.beforeOverwrite?.(direction);
      armed = true;
    };
    for (let attempt = 1; ; attempt++) {
      const plan = await this.config.historyLifecycle.planMerge(baseline, local, remote, this.config.deviceId);
      if (!push && !plan.remoteSnapshot) throw new Error('当前同步来源还没有书签快照，无法覆盖电脑。');
      const source = push
        ? canonicalizeSnapshotBookmarkUrls(buildComputerOverwriteSnapshot(plan.localSnapshot, plan.remoteSnapshot, this.config.deviceId))
        : plan.remoteSnapshot!;
      const target = validateCanonicalLeafTabSyncSnapshot(source);
      const browserTarget = push ? local : materializeRemoteOverwrite(target, local);
      if (push) await this.config.verifyLocalSnapshot(local);
      let commitId = remote.commitId;
      const needsWrite = plan.requiresRemoteHistoryWrite || (push && !sameSnapshotContent(remote.snapshot, target));
      let confirmed: Awaited<ReturnType<LeafTabSyncEngine['confirmRemoteCommit']>>;
      try {
        if (needsWrite) {
          await beforeMutation();
          reportProgress(options.onProgress, { stage: 'uploading-remote', progress: 55, message: '正在提交书签快照' });
          const write = await this.config.remoteStore.writeState({
            snapshot: target, history: plan.history, deviceId: this.config.deviceId,
            parentCommitId: commitId, createdAt: new Date().toISOString(),
          });
          commitId = write.commitId;
        }
        if (!commitId) throw new Error('未能确认覆盖使用的远端书签版本。');
        confirmed = await this.confirmRemoteCommit(commitId);
      } catch (error) {
        // Retry only against a newly observed complete head. Never send a blind replacement.
        if (attempt >= 3) throw error;
        const latest = await this.config.remoteStore.readState();
        if (!latest.commitId || !latest.history || !latest.snapshot || latest.commitId === remote.commitId) throw error;
        remote = latest;
        continue;
      }
      if (!sameSnapshotContent(confirmed.snapshot, target) ||
        !this.config.historyLifecycle.sameHistory(confirmed.history, plan.history)) {
        throw new Error('覆盖结果与所选书签快照不一致，请重新执行覆盖。');
      }
      reportProgress(options.onProgress, { stage: 'applying-local', progress: 85, message: '正在核对电脑书签' });
      if (!push && !sameMaterializedBookmarkContent(local, browserTarget)) {
        await beforeMutation();
        await this.config.applyLocalSnapshot(cloneSnapshot(browserTarget));
      }
      await this.config.verifyLocalSnapshot(browserTarget);
      await this.persistCompletedState(baseline, confirmed.snapshot, confirmed.history, confirmed.commitId, pendingLocalChange);
      return createSyncResult({
        kind: push ? 'push' : 'pull', remoteCommitId: confirmed.commitId, snapshot: confirmed.snapshot,
        summaryText: push ? '电脑书签已覆盖当前同步来源' : '当前同步来源的书签已覆盖电脑',
      });
    }
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
    if (runOptions?.overwrite) {
      return this.overwriteBookmarks(runOptions.overwrite, runOptions, baseline, localSnapshotValue,
        remoteState, completedPendingLocalChangedAt);
    }
    const historyPlan = await this.config.historyLifecycle.planMerge(
      baseline,
      baseline?.snapshot ? reconcileNativeBookmarkRoots(localSnapshotValue, baseline.snapshot) : localSnapshotValue,
      remoteState,
      this.config.deviceId,
    );
    let localSnapshot = historyPlan.localSnapshot;
    const baseSnapshot = historyPlan.baselineSnapshot || this.config.createEmptySnapshot();
    const hasBaseline = Boolean(historyPlan.baselineSnapshot);
    const remoteCommitId = this.resolveRemoteCommitId(remoteState);

    const prepareFirstJoin = (snapshot: LeafTabSyncSnapshot) =>
      !baseline?.snapshot && runOptions?.mergeIntent !== 'provider-switch'
        ? deduplicateFirstJoinBookmarks(snapshot, this.config.deviceId)
        : snapshot;

    // A device joining an account it has never synced has no baseline and its own
    // installation-scoped IDs, so it would otherwise union the same bookmark twice.
    // Adoption renames local identity onto the remote's before the merge; it never
    // merges or drops an entity, and it leaves the remote unchanged.
    if (!hasBaseline && historyPlan.remoteSnapshot && this.config.adoptLocalIdentity) {
      const adoptedLocalSnapshot = await this.config.adoptLocalIdentity(historyPlan.remoteSnapshot);
      if (adoptedLocalSnapshot) {
        localSnapshot = adoptedLocalSnapshot;
      }
    }

    if (!hasBaseline && !historyPlan.remoteSnapshot) {
      reportProgress(runOptions?.onProgress, {
        stage: 'uploading-remote',
        progress: 72,
        message: '正在写入远端数据',
      });
      const writeResult = await this.config.remoteStore.writeState({
        snapshot: canonicalizeSnapshotBookmarkUrls(prepareFirstJoin(localSnapshot)),
        history: historyPlan.history,
        deviceId: this.config.deviceId,
        parentCommitId: null,
      });
      const confirmed = await this.confirmRemoteCommit(writeResult.commitId);
      if (!sameMaterializedBookmarkContent(localSnapshot, confirmed.snapshot)) {
        reportProgress(runOptions?.onProgress, {
          stage: 'applying-local',
          progress: 86,
          message: '正在将最新结果写入本地',
        });
        try {
          await this.config.applyLocalSnapshot(cloneSnapshot(confirmed.snapshot));
          await this.config.verifyLocalSnapshot(cloneSnapshot(confirmed.snapshot));
        } catch (error) {
          throw new LeafTabSyncLocalApplyVerificationError(
            error instanceof Error ? error.message : String(error),
          );
        }
      }
      await this.persistCompletedState(
        baseline,
        confirmed.snapshot,
        confirmed.history,
        confirmed.commitId,
        completedPendingLocalChangedAt,
      );
      reportProgress(runOptions?.onProgress, {
        stage: 'completed',
        progress: 100,
        message: '同步完成',
      });
      return createSyncResult({
        kind: 'push',
        remoteCommitId: confirmed.commitId,
        snapshot: confirmed.snapshot,
        summaryText: '远端为空，已用本地快照建立首次同步状态',
      });
    }

    const remoteSnapshot = historyPlan.remoteSnapshot || this.config.createEmptySnapshot();
    if (!hasBaseline
      && !historyPlan.requiresRemoteHistoryWrite
      && sameMaterializedBookmarkContent(localSnapshot, remoteSnapshot)
      && prepareFirstJoin(localSnapshot) === localSnapshot) {
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
          {
            deviceId: this.config.deviceId,
            conflictResolution: runOptions?.conflictResolution,
            mergeIntent: runOptions?.mergeIntent,
          },
        );
    if (mergeResult.conflicts.length === 0) {
      mergeResult.snapshot = prepareFirstJoin(mergeResult.snapshot);
    }
    const finalSnapshot = canonicalizeSnapshotBookmarkUrls(mergeResult.snapshot);
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

    if (hasBaseline) {
      const runawayGuardError = evaluateLeafTabSyncRunawayGuard(baseSnapshot, finalSnapshot, remoteSnapshot);
      if (runawayGuardError) {
        throw new Error(runawayGuardError);
      }
    }

    const remoteNeedsWrite = historyPlan.requiresRemoteHistoryWrite
      || !sameSnapshotContent(remoteSnapshot, finalSnapshot);
    let committedSnapshot = finalSnapshot;
    let committedHistory = historyPlan.history;
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
      const confirmed = await this.confirmRemoteCommit(writeResult.commitId);
      committedId = confirmed.commitId;
      committedSnapshot = confirmed.snapshot;
      committedHistory = confirmed.history;
    }

    if (!sameMaterializedBookmarkContent(localSnapshot, committedSnapshot)) {
      reportProgress(runOptions?.onProgress, {
        stage: 'applying-local',
        progress: 86,
        message: '正在将最新结果写入本地',
      });
      try {
        const browserTarget = localSnapshotValue.bookmarkFolders.browser_root_toolbar || localSnapshotValue.bookmarkFolders.browser_root_other
          ? materializeRemoteOverwrite(committedSnapshot, localSnapshotValue)
          : committedSnapshot;
        await this.config.applyLocalSnapshot(cloneSnapshot(browserTarget));
        await this.config.verifyLocalSnapshot(cloneSnapshot(browserTarget));
      } catch (error) {
        throw new LeafTabSyncLocalApplyVerificationError(
          error instanceof Error ? error.message : String(error),
        );
      }
    }

    reportProgress(runOptions?.onProgress, {
      stage: 'finalizing',
      progress: 94,
      message: '正在收尾同步结果',
    });
    await this.persistCompletedState(
      baseline,
      committedSnapshot,
      committedHistory,
      committedId,
      completedPendingLocalChangedAt,
    );
    reportProgress(runOptions?.onProgress, {
      stage: 'completed',
      progress: 100,
      message: '同步完成',
    });

    const localNeedsApply = !sameMaterializedBookmarkContent(localSnapshot, committedSnapshot);
    const kind: LeafTabSyncEngineResult['kind'] = remoteNeedsWrite
      ? (localNeedsApply ? 'merge' : 'push')
      : (localNeedsApply ? 'pull' : 'noop');
    return createSyncResult({
      kind,
      remoteCommitId: committedId,
      snapshot: committedSnapshot,
      mergeResult,
      summary,
      summaryText,
    });
  }
}

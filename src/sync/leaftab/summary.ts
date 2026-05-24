import type { LeafTabSyncMergeResult, LeafTabSyncMergeSource } from './merge';
import type { LeafTabSyncSnapshot } from './schema';

export interface LeafTabSyncChangeSummary {
  bookmarkFoldersAdded: number;
  bookmarkFoldersUpdated: number;
  bookmarkFoldersDeleted: number;
  bookmarkItemsAdded: number;
  bookmarkItemsUpdated: number;
  bookmarkItemsDeleted: number;
  ordersMerged: number;
  conflicts: number;
}

const createEmptySummary = (): LeafTabSyncChangeSummary => ({
  bookmarkFoldersAdded: 0,
  bookmarkFoldersUpdated: 0,
  bookmarkFoldersDeleted: 0,
  bookmarkItemsAdded: 0,
  bookmarkItemsUpdated: 0,
  bookmarkItemsDeleted: 0,
  ordersMerged: 0,
  conflicts: 0,
});

const isSame = (left: unknown, right: unknown) => {
  return JSON.stringify(left) === JSON.stringify(right);
};

export const summarizeLeafTabSyncMerge = (
  baseSnapshot: LeafTabSyncSnapshot,
  mergeResult: LeafTabSyncMergeResult,
): LeafTabSyncChangeSummary => {
  const summary = createEmptySummary();
  const finalSnapshot = mergeResult.snapshot;

  const bookmarkFolderIds = new Set([
    ...Object.keys(baseSnapshot.bookmarkFolders),
    ...Object.keys(finalSnapshot.bookmarkFolders),
  ]);
  bookmarkFolderIds.forEach((id) => {
    const baseEntity = baseSnapshot.bookmarkFolders[id];
    const finalEntity = finalSnapshot.bookmarkFolders[id];
    if (!baseEntity && finalEntity) {
      summary.bookmarkFoldersAdded += 1;
      return;
    }
    if (baseEntity && !finalEntity) {
      summary.bookmarkFoldersDeleted += 1;
      return;
    }
    if (baseEntity && finalEntity && !isSame(baseEntity, finalEntity)) {
      summary.bookmarkFoldersUpdated += 1;
    }
  });

  const bookmarkItemIds = new Set([
    ...Object.keys(baseSnapshot.bookmarkItems),
    ...Object.keys(finalSnapshot.bookmarkItems),
  ]);
  bookmarkItemIds.forEach((id) => {
    const baseEntity = baseSnapshot.bookmarkItems[id];
    const finalEntity = finalSnapshot.bookmarkItems[id];
    if (!baseEntity && finalEntity) {
      summary.bookmarkItemsAdded += 1;
      return;
    }
    if (baseEntity && !finalEntity) {
      summary.bookmarkItemsDeleted += 1;
      return;
    }
    if (baseEntity && finalEntity && !isSame(baseEntity, finalEntity)) {
      summary.bookmarkItemsUpdated += 1;
    }
  });

  summary.ordersMerged = Object.values(mergeResult.orderSources).filter(
    (source: LeafTabSyncMergeSource) => source === 'merged',
  ).length;
  summary.conflicts = mergeResult.conflicts.length;

  return summary;
};

export const formatLeafTabSyncSummaryText = (summary: LeafTabSyncChangeSummary) => {
  const parts: string[] = [];
  if (summary.bookmarkFoldersAdded) parts.push(`新增 ${summary.bookmarkFoldersAdded} 个书签文件夹`);
  if (summary.bookmarkFoldersUpdated) parts.push(`更新 ${summary.bookmarkFoldersUpdated} 个书签文件夹`);
  if (summary.bookmarkFoldersDeleted) parts.push(`删除 ${summary.bookmarkFoldersDeleted} 个书签文件夹`);
  if (summary.bookmarkItemsAdded) parts.push(`新增 ${summary.bookmarkItemsAdded} 个书签`);
  if (summary.bookmarkItemsUpdated) parts.push(`更新 ${summary.bookmarkItemsUpdated} 个书签`);
  if (summary.bookmarkItemsDeleted) parts.push(`删除 ${summary.bookmarkItemsDeleted} 个书签`);
  if (summary.ordersMerged) parts.push(`合并 ${summary.ordersMerged} 处排序`);
  if (summary.conflicts) parts.push(`${summary.conflicts} 处冲突待处理`);
  return parts.length ? parts.join('，') : '未检测到变更';
};

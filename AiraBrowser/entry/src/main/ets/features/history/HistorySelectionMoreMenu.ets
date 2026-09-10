import { HistoryViewMode } from './HistoryViewModel';

export type HistorySelectionMoreActionId =
  'copy_links' | 'add_bookmarks' | 'remove_bookmarks' | 'share_links' | 'delete_selected_sites';

export interface HistorySelectionMoreMenuItem {
  id: HistorySelectionMoreActionId;
  title: string;
}

export interface HistorySelectionMoreMenuPlan {
  emptySelectionMessage: string;
  selectedCount: number;
  items: HistorySelectionMoreMenuItem[];
}

export const HISTORY_SELECTION_MORE_EMPTY_MESSAGE: string = '请先选择历史记录。';

export function planHistorySelectionMoreMenu(
  viewMode: HistoryViewMode,
  selectedCount: number,
  includeRemoveBookmarks: boolean = false
): HistorySelectionMoreMenuPlan {
  const items: HistorySelectionMoreMenuItem[] = [];
  if (viewMode === 'sites') {
    items.push({
      id: 'delete_selected_sites',
      title: '删除所选站点历史'
    });
  } else {
    items.push({
      id: 'copy_links',
      title: '批量复制链接'
    });
    items.push({
      id: 'add_bookmarks',
      title: '批量添加到书签'
    });
    if (includeRemoveBookmarks) {
      items.push({
        id: 'remove_bookmarks',
        title: '批量取消书签'
      });
    }
    items.push({
      id: 'share_links',
      title: '批量分享链接'
    });
  }
  return {
    emptySelectionMessage: HISTORY_SELECTION_MORE_EMPTY_MESSAGE,
    selectedCount: selectedCount,
    items: items
  };
}

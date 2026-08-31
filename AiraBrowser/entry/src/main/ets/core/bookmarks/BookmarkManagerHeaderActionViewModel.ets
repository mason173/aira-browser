export interface BookmarkManagerHeaderActionView {
  label: string;
  icon: Resource;
  enabled?: boolean;
  action: () => void;
}

export interface BookmarkManagerHeaderActionContext {
  isSelectionMode: boolean;
  isSearchMode: boolean;
  hasCurrentFolder: boolean;
  canEnterSelectionMode: boolean;
  isTransferBusy: boolean;
}

export interface BookmarkManagerHeaderActionHandlers {
  openSearch: () => void;
  createFolder: () => void;
  enterSelectionMode: () => void;
  importBookmarks: () => void;
  exportBookmarks: () => void;
}

export class BookmarkManagerHeaderActionViewModel {
  buildActions(
    context: BookmarkManagerHeaderActionContext,
    handlers: BookmarkManagerHeaderActionHandlers
  ): BookmarkManagerHeaderActionView[] {
    if (context.isSelectionMode || context.isSearchMode) {
      return [];
    }
    const actions: BookmarkManagerHeaderActionView[] = [
      {
        label: '搜索',
        icon: $r('sys.symbol.magnifyingglass'),
        action: handlers.openSearch
      }
    ];
    if (context.hasCurrentFolder) {
      actions.push({
        label: '新建文件夹',
        icon: $r('sys.symbol.folder_badge_plus'),
        action: handlers.createFolder
      });
    }
    if (context.canEnterSelectionMode) {
      actions.push({
        label: '编辑',
        icon: $r('sys.symbol.checkmark_circle_fill'),
        action: handlers.enterSelectionMode
      });
    }
    actions.push(
      {
        label: '导入',
        icon: $r('sys.symbol.arrow_down'),
        enabled: !context.isTransferBusy,
        action: handlers.importBookmarks
      },
      {
        label: '导出',
        icon: $r('sys.symbol.arrow_up'),
        enabled: !context.isTransferBusy,
        action: handlers.exportBookmarks
      }
    );
    return actions;
  }
}

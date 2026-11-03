import { BookmarkSortMode } from '../../common/models/BookmarkSortModels';
import { buildBookmarkSortOptions, resolveBookmarkSortLabel } from './BookmarkSortViewModel';

export interface BookmarkManagerHeaderActionView {
  label: ResourceStr;
  icon?: Resource;
  labelInfo?: ResourceStr;
  selected?: boolean;
  options?: BookmarkManagerHeaderActionView[];
  enabled?: boolean;
  action: () => void;
}

export interface BookmarkManagerHeaderActionContext {
  isSelectionMode: boolean;
  isSearchMode: boolean;
  hasCurrentFolder: boolean;
  canEnterSelectionMode: boolean;
  isTransferBusy: boolean;
  sortMode: BookmarkSortMode;
}

export interface BookmarkManagerHeaderActionHandlers {
  openSearch: () => void;
  createFolder: () => void;
  enterSelectionMode: () => void;
  importBookmarks: () => void;
  exportBookmarks: () => void;
  selectSortMode: (mode: BookmarkSortMode) => void;
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
        label: $r('app.string.settings_sync_search'),
        icon: $r('sys.symbol.magnifyingglass'),
        action: handlers.openSearch
      }
    ];
    if (context.hasCurrentFolder) {
      actions.push({
        label: $r('app.string.bookmark_new_folder'),
        icon: $r('sys.symbol.folder_badge_plus'),
        action: handlers.createFolder
      });
    }
    actions.push({
      label: $r('app.string.bookmark_sort_order'),
      labelInfo: resolveBookmarkSortLabel(context.sortMode),
      options: buildBookmarkSortOptions(context.sortMode, handlers.selectSortMode),
      action: (): void => {}
    });
    if (context.canEnterSelectionMode) {
      actions.push({
        label: $r('app.string.ui_multi_select'),
        icon: $r('sys.symbol.checkmark_circle_fill'),
        action: handlers.enterSelectionMode
      });
    }
    actions.push(
      {
        label: $r('app.string.ui_import'),
        icon: $r('sys.symbol.arrow_down'),
        enabled: !context.isTransferBusy,
        action: handlers.importBookmarks
      },
      {
        label: $r('app.string.ui_export'),
        icon: $r('sys.symbol.arrow_up'),
        enabled: !context.isTransferBusy,
        action: handlers.exportBookmarks
      }
    );
    return actions;
  }
}

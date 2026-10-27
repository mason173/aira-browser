import { BookmarkAddDraft, createBookmarkAddDraft } from '../../../core/bookmarks/BookmarkAddDraft';
import { BrowserBookmarkFolderSelectionAction } from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { BookmarkAddForm } from '../bookmarks/BookmarkAddForm';
import { BookmarkFolderOptionView } from '../../../core/browser/BookmarkFolderSelectionViewModel';
import {
  BookmarkMoveFolderSelectionResult,
  BookmarkMoveFolderSelectionSheet
} from '../bookmarks/BookmarkMoveFolderSelectionSheet';
import {
  BrowserModalBottomOverlay,
  BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS,
  BROWSER_MODAL_BOTTOM_SHEET_ENTER_OFFSET_Y,
  BROWSER_MODAL_BOTTOM_SHEET_Z_INDEX
} from '../browser/BrowserModalBottomSheet';

const HISTORY_BOOKMARK_FOLDER_OVERLAY_SHEET_HEIGHT: Length = '88%';

@Component
export struct HistoryBookmarkFolderSelectionOverlay {
  @Prop visible: boolean = false;
  @Prop editSingleBookmark: boolean = false;
  @Prop draft: BookmarkAddDraft = createBookmarkAddDraft();
  @Prop sessionVersion: number = 0;
  onAction: (action: BrowserBookmarkFolderSelectionAction) => void = (_action: BrowserBookmarkFolderSelectionAction) => {};
  @Prop sheetVisible: boolean = false;
  @Prop options: BookmarkFolderOptionView[] = [];
  @Prop isPreparing: boolean = false;
  @Prop rootTitle: ResourceStr = $r('app.string.history_add_bookmark_sheet');
  @Prop message: string = '';
  onDismiss: () => void = () => {};
  onFolderOpened: (folderId: string) => void = (_folderId: string) => {};
  onConfirm: (result: BookmarkMoveFolderSelectionResult) => void = (_result: BookmarkMoveFolderSelectionResult) => {};

  build() {
    if (this.visible) {
      BrowserModalBottomOverlay({
        tier: 'm',
        visible: this.sheetVisible,
        sheetHeight: this.editSingleBookmark && !this.draft.choosingFolder ? '68%' : HISTORY_BOOKMARK_FOLDER_OVERLAY_SHEET_HEIGHT,
        enterOffsetY: BROWSER_MODAL_BOTTOM_SHEET_ENTER_OFFSET_Y,
        animationDurationMs: BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS,
        zIndexValue: BROWSER_MODAL_BOTTOM_SHEET_Z_INDEX,
        dismissOnOutsideTap: !this.draft.saving,
        onDismiss: () => {
          this.onDismiss();
        }
      }) {
        if (this.editSingleBookmark) {
          BookmarkAddForm({
            draft: this.draft,
            options: this.options,
            isPreparing: this.isPreparing,
            sessionVersion: this.sessionVersion,
            showAddToHome: false,
            onAction: this.onAction
          })
        } else {
          BookmarkMoveFolderSelectionSheet({
            options: this.options,
            isPreparing: this.isPreparing,
            rootTitle: this.rootTitle,
            preparingTitle: $r('app.string.bookmark_preparing_folders'),
            rootEmptyTitle: $r('app.string.bookmark_no_save_folder'),
            leafEmptyTitle: $r('app.string.bookmark_no_child_folder'),
            confirmLabel: $r('app.string.bookmark_add_here'),
            message: this.message,
            onDismiss: () => {
              this.onDismiss();
            },
            onFolderOpened: (folderId: string) => {
              this.onFolderOpened(folderId);
            },
            onConfirm: (result: BookmarkMoveFolderSelectionResult) => {
              this.onConfirm(result);
            }
          })
        }
      }
    }
  }
}

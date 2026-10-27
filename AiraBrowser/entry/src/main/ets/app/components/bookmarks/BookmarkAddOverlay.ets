import { createBookmarkAddDraft } from '../../../core/bookmarks/BookmarkAddDraft';
import { BrowserBookmarkActionSessionSnapshot, BrowserBookmarkFolderSelectionAction } from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import {
  BOOKMARK_FOLDER_OVERLAY_ANIMATION_DURATION_MS,
  BOOKMARK_FOLDER_OVERLAY_ENTER_OFFSET_Y,
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX
} from '../browser/BrowserShellPresentationTokens';
import { BookmarkAddForm } from './BookmarkAddForm';

@Component
export struct BookmarkAddOverlay {
  @Prop visible: boolean = false;
  @Prop snapshot: BrowserBookmarkActionSessionSnapshot = {
    actionVersion: 0,
    sessionVersion: 0,
    active: false,
    draft: createBookmarkAddDraft(),
    scope: 'regular',
    addToHome: false,
    preparing: false,
    options: []
  };
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: BrowserBookmarkFolderSelectionAction) => void = (_action: BrowserBookmarkFolderSelectionAction) => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: this.layoutMode,
      showDesktopHeader: false,
      dismissOnOutsideTap: !this.snapshot.draft.saving,
      phoneSheetHeight: this.snapshot.draft.choosingFolder ? '88%' : '68%',
      phoneEnterOffsetY: BOOKMARK_FOLDER_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: BOOKMARK_FOLDER_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      tier: 'm',
      onDismiss: () => { this.onAction({ type: 'dismiss' }); }
    }) {
      BookmarkAddForm({
        draft: this.snapshot.draft,
        options: this.snapshot.options,
        isPreparing: this.snapshot.preparing,
        sessionVersion: this.snapshot.sessionVersion,
        layoutMode: this.layoutMode,
        showAddToHome: this.snapshot.scope === 'regular',
        addToHome: this.snapshot.addToHome,
        title: this.snapshot.scope === 'private' ? $r('app.string.bookmark_popover_add_private') : $r('app.string.history_add_bookmark'),
        onAction: this.onAction
      })
    }
  }
}

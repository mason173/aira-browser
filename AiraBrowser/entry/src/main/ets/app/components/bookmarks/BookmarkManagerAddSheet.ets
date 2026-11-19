import { BookmarkStorageScope } from '../../../common/models/BrowserModels';
import { BookmarkAddDraft, createBookmarkAddDraft } from '../../../core/bookmarks/BookmarkAddDraft';
import { BookmarkAddFormCoordinator } from '../../../core/bookmarks/BookmarkAddFormCoordinator';
import { BrowserBookmarkFolderSelectionAction } from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { BookmarkFolderOptionView } from '../../../core/browser/BookmarkFolderSelectionViewModel';
import { resolveBookmarkNodeDisplayTitle } from '../../../core/resources/HistoryBookmarkDisplayText';
import { BookmarkManagementFeature } from '../../../features/bookmarks/BookmarkManagementFeature';
import { sharedBookmarkFolderSelectionPreparationCoordinator } from '../../bootstrap/BrowserAppRuntime';
import { applyDesktopDialogSheetChrome } from '../common/DesktopDialogSheetChrome';
import { BookmarkAddForm } from './BookmarkAddForm';

@Component
export struct BookmarkManagerAddSheet {
  @Link @Watch('startSession') initialFolderId: string;
  @Prop scope: BookmarkStorageScope = 'regular';
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @Require feature: BookmarkManagementFeature;
  onSaved: () => void = () => {};
  @State private draft: BookmarkAddDraft = createBookmarkAddDraft();
  @State private options: BookmarkFolderOptionView[] = [];
  @State private preparing: boolean = false;
  @State private folderMessage: ResourceStr = '';
  private session: number = 0;

  private coordinator: BookmarkAddFormCoordinator = new BookmarkAddFormCoordinator({
    applyDraft: (draft: BookmarkAddDraft): void => { this.draft = draft; },
    resolveFolders: (): BookmarkFolderOptionView[] => this.options,
    hasBookmark: (url: string): boolean => this.feature.hasBookmarkForUrl(url),
    isFolderAvailable: (folderId: string): boolean => this.feature.findSaveFolder(folderId) !== undefined,
    dismiss: (): void => { this.initialFolderId = ''; },
    beginSave: (title: string, url: string, folderId: string) =>
      this.feature.beginCreateBookmarkIfMissing({ type: 'bookmark', title: title, url: url, parentId: folderId }),
    onSaved: (): void => {
      this.initialFolderId = '';
      this.showToast(this.scope === 'private' ? $r('app.string.bottom_panel_bookmark_added_private') :
        $r('app.string.bottom_panel_bookmark_added'));
      this.onSaved();
    },
    onSyncPreparationFailed: (): void => this.showToast($r('app.string.bookmark_add_saved_sync_pending'))
  });

  aboutToAppear(): void {
    this.startSession();
  }

  aboutToDisappear(): void {
    this.session += 1;
    this.coordinator.cancel();
  }

  private startSession(): void {
    this.session += 1;
    this.options = [];
    this.preparing = false;
    this.folderMessage = '';
    if (this.initialFolderId.length > 0) {
      this.coordinator.beginManual(this.initialFolderId);
    } else {
      this.coordinator.cancel();
    }
  }

  build() {
    Column()
      .width(0)
      .height(0)
      .bindSheet(this.initialFolderId.length > 0, this.buildForm(), applyDesktopDialogSheetChrome({
        preferType: SheetType.BOTTOM,
        height: this.draft.choosingFolder ? '88%' : '68%',
        keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
        dragBar: false,
        showClose: false,
        onWillDismiss: (action: DismissSheetAction): void => {
          if (this.draft.saving) {
            return;
          }
          if (action.reason === DismissReason.PRESS_BACK && this.draft.choosingFolder) {
            this.coordinator.handleAction({ type: 'back' });
            return;
          }
          this.initialFolderId = '';
          action.dismiss();
        }
      }, 'm', this.layoutMode === 'large_screen', true))
  }

  @Builder
  private buildForm() {
    BookmarkAddForm({
      manualEntry: true,
      title: this.scope === 'private' ? $r('app.string.bookmark_popover_add_private') : $r('app.string.bookmark_add_title'),
      draft: this.draft,
      currentFolderTitle: this.resolveCurrentFolderTitle(),
      options: this.options,
      isPreparing: this.preparing,
      folderPickerMessage: this.folderMessage,
      showAddToHome: false,
      layoutMode: this.layoutMode,
      onAction: (action: BrowserBookmarkFolderSelectionAction): void => {
        this.coordinator.handleAction(action);
        if (action.type === 'set_folder_picker' && this.draft.choosingFolder && !this.preparing) {
          void this.loadFolders();
        }
      }
    })
  }

  private resolveCurrentFolderTitle(): ResourceStr {
    if (this.initialFolderId.length === 0) {
      return '';
    }
    const folder = this.feature.findSaveFolder(this.draft.folderId);
    return folder === undefined ? '' : resolveBookmarkNodeDisplayTitle(folder.id, folder.title);
  }

  private async loadFolders(): Promise<void> {
    const session = this.session;
    this.preparing = true;
    this.folderMessage = '';
    try {
      this.options = sharedBookmarkFolderSelectionPreparationCoordinator.getResponsiveOptions(this.scope);
      const options = await sharedBookmarkFolderSelectionPreparationCoordinator.prepare(this.scope);
      if (session === this.session) {
        this.options = options;
      }
    } catch (error) {
      if (session === this.session) {
        this.folderMessage = $r('app.string.bookmark_folder_load_failed_detail', (error as Error).message);
      }
    } finally {
      if (session === this.session) {
        this.preparing = false;
      }
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_error) {
      // A window closing after the local commit can no longer display feedback.
    }
  }
}

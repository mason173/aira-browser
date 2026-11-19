import { BookmarkCreateNodeOperation } from '../../services/bookmarks/BookmarkMutationService';
import { BookmarkAddDraft, cloneBookmarkAddDraft, createBookmarkAddDraft, isBookmarkAddDraftValid, validateBookmarkAddDraft } from './BookmarkAddDraft';
import { BrowserBookmarkFolderSelectionAction } from '../browser/BrowserBookmarkActionCoordinator';
import { BookmarkFolderOptionView } from '../browser/BookmarkFolderSelectionViewModel';

export interface BookmarkAddFormShell {
  applyDraft: (draft: BookmarkAddDraft) => void;
  resolveFolders: () => BookmarkFolderOptionView[];
  hasBookmark: (url: string) => boolean;
  isFolderAvailable: (folderId: string) => boolean;
  previewFolder?: (folderId: string) => void;
  dismiss: () => void;
  beginSave: (title: string, url: string, folderId: string) => BookmarkCreateNodeOperation;
  refreshBookmarks?: () => void;
  onSyncPreparationFailed: () => void;
  onSaved: () => void;
}

/** Owns the editable draft for single-item additions from history and the bookmark manager. */
export class BookmarkAddFormCoordinator {
  private draft: BookmarkAddDraft = createBookmarkAddDraft();
  private generation: number = 0;
  private active: boolean = false;
  private manualEntry: boolean = false;
  private shell: BookmarkAddFormShell;

  constructor(shell: BookmarkAddFormShell) {
    this.shell = shell;
  }

  begin(title: string, url: string): void {
    this.generation += 1;
    this.active = true;
    this.manualEntry = false;
    this.draft = createBookmarkAddDraft(title, url);
    this.refreshFolders();
  }

  beginManual(folderId: string): void {
    this.generation += 1;
    this.active = true;
    this.manualEntry = true;
    this.draft = createBookmarkAddDraft('', '', folderId);
    this.emit();
  }

  cancel(): void {
    this.generation += 1;
    this.active = false;
  }

  refreshFolders(): void {
    const folders = this.shell.resolveFolders();
    if (!folders.some((folder: BookmarkFolderOptionView) => folder.id === this.draft.folderId)) {
      this.draft.folderId = folders.length > 0 ? folders[0].id : '';
    }
    this.emit();
  }

  handleAction(action: BrowserBookmarkFolderSelectionAction): void {
    if (!this.active || this.draft.saving) {
      return;
    }
    if (action.type === 'set_folder_picker' || (action.type === 'back' && this.draft.choosingFolder)) {
      this.draft.choosingFolder = action.type === 'set_folder_picker' && action.selected === true;
      this.emit();
      return;
    }
    if (action.type === 'edit_title') {
      this.draft.title = action.value ?? this.draft.title;
      this.draft.titleError = '';
    } else if (action.type === 'edit_url') {
      this.draft.url = action.value ?? this.draft.url;
      this.draft.urlError = '';
    } else if (action.type === 'select_folder') {
      if (this.shell.resolveFolders().some((folder: BookmarkFolderOptionView) => folder.id === action.folderId)) {
        this.draft.folderId = action.folderId ?? '';
      }
    } else if (action.type === 'preview_folder') {
      this.shell.previewFolder?.(action.folderId ?? '');
      return;
    } else if (action.type === 'dismiss' || action.type === 'back') {
      this.cancel();
      this.shell.dismiss();
      return;
    } else if (action.type === 'confirm_add') {
      void this.save();
      return;
    }
    this.draft.saveError = '';
    this.emit();
  }

  private async save(): Promise<void> {
    const validated = validateBookmarkAddDraft(this.draft, this.manualEntry);
    this.draft.titleError = validated.titleError;
    this.draft.urlError = validated.urlError;
    this.draft.saveError = '';
    if (!this.shell.isFolderAvailable(this.draft.folderId)) {
      this.draft.saveError = $r('app.string.bookmark_add_choose_folder');
    }
    if (isBookmarkAddDraftValid(validated) && this.shell.hasBookmark(validated.url)) {
      if (this.manualEntry) {
        this.draft.urlError = $r('app.string.bookmark_url_already_saved');
      } else {
        this.draft.saveError = $r('app.string.history_already_bookmarked');
      }
    }
    if (!isBookmarkAddDraftValid(this.draft) || this.draft.saveError !== '') {
      this.emit();
      return;
    }
    const generation = this.generation;
    this.draft.saving = true;
    this.emit();
    try {
      const operation = this.shell.beginSave(validated.title, validated.url, validated.folderId);
      let localCommitted = false;
      void operation.completion.catch((_error: Error): void => {
        if (localCommitted) {
          this.shell.onSyncPreparationFailed();
        }
      });
      await operation.localCommit;
      localCommitted = true;
      if (generation === this.generation && this.active) {
        this.draft.saving = false;
        this.active = false;
        this.emit();
        this.shell.onSaved();
      }
      if (this.shell.refreshBookmarks !== undefined) {
        setTimeout((): void => { this.shell.refreshBookmarks?.(); }, 0);
      }
    } catch (_error) {
      if (generation === this.generation && this.active) {
        this.draft.saving = false;
        this.draft.saveError = $r('app.string.bottom_panel_bookmark_add_failed');
        this.emit();
      }
    }
  }

  private emit(): void {
    this.shell.applyDraft(cloneBookmarkAddDraft(this.draft));
  }
}

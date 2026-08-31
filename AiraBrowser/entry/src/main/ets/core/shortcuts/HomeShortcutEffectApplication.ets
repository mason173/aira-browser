import { HomeShortcutEditDraft } from '../../features/newtab/HomeShortcutTypes';
import {
  HomeShortcutApplicationEffect,
  HomeShortcutDeleteConfirmation,
  HomeShortcutEffectApplication
} from './HomeShortcutStateCoordinator';
import { HomeShortcutSelectionState } from './HomeShortcutSelectionCoordinator';

export interface HomeShortcutConfirmationPresentation {
  title: string;
  message: string;
  cancelLabel: string;
  confirmLabel: string;
  onConfirm: () => void;
}

export interface HomeShortcutInformationPresentation {
  title: string;
  message: string;
  confirmLabel: string;
}

export interface HomeShortcutEffectApplicationShell {
  dismissContextMenu: () => void;
  openEditDialog: (draft: HomeShortcutEditDraft) => void;
  showToast: (message: string) => void;
  publishHelper: (message: string) => void;
  presentBoundaryBlock: (summaryLine: string, helperText: string) => void;
  publishSelectionSnapshot: (snapshot: HomeShortcutSelectionState) => void;
  openSelectionSheet: () => void;
  closeSelectionSheet: () => void;
}

export class HomeShortcutFixedEffectApplication implements HomeShortcutEffectApplication {
  private readonly confirmDialog: (presentation: HomeShortcutConfirmationPresentation) => void;
  private readonly informDialog: (presentation: HomeShortcutInformationPresentation) => void;
  private readonly shell: HomeShortcutEffectApplicationShell;

  constructor(
    confirmDialog: (presentation: HomeShortcutConfirmationPresentation) => void,
    informDialog: (presentation: HomeShortcutInformationPresentation) => void,
    shell: HomeShortcutEffectApplicationShell
  ) {
    this.confirmDialog = confirmDialog;
    this.informDialog = informDialog;
    this.shell = shell;
  }

  apply(
    effect: HomeShortcutApplicationEffect,
    confirmDelete: (confirmation: HomeShortcutDeleteConfirmation) => void
  ): void {
    switch (effect.type) {
      case 'dismiss_context_menu':
        this.shell.dismissContextMenu();
        return;
      case 'open_edit_dialog':
        this.shell.openEditDialog(effect.draft);
        return;
      case 'confirm_delete':
        this.confirmDialog({
          title: '删除快捷方式',
          message: `确定删除“${effect.confirmation.title}”吗？`,
          cancelLabel: '取消',
          confirmLabel: '删除',
          onConfirm: (): void => confirmDelete(effect.confirmation)
        });
        return;
      case 'show_toast':
        this.shell.showToast(effect.message);
        return;
      case 'show_dialog':
        this.informDialog({
          title: effect.title,
          message: effect.message,
          confirmLabel: '知道了'
        });
        return;
      case 'set_helper_message':
        this.shell.publishHelper(effect.message);
        return;
      case 'present_boundary_block':
        this.shell.presentBoundaryBlock(effect.summaryLine, effect.helperText);
        return;
      case 'publish_selection_snapshot':
        this.shell.publishSelectionSnapshot(effect.snapshot);
        return;
      case 'open_selection_sheet':
        this.shell.openSelectionSheet();
        return;
      case 'close_selection_sheet':
        this.shell.closeSelectionSheet();
        return;
    }
  }
}

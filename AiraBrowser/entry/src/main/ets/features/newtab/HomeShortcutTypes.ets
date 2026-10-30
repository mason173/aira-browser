import { HomeShortcutFolderCommand } from '../../services/shortcuts/HomeShortcutFolderService';
import { image } from '@kit.ImageKit';
import { HomeShortcutMoveRequest } from '../../services/shortcuts/HomeShortcutLogicService';

export interface HomeShortcutIconState {
  id: string;
  path: string;
  backgroundColor: string;
  pixelMap?: image.PixelMap;
  revision?: number;
}

export type HomeShortcutContextActionId =
  'rename_folder' |
  'toggle_folder_size' |
  'dissolve_folder' |
  'move_out' |
  'open' |
  'open_new_tab' |
  'open_background_tab' |
  'copy_link' |
  'edit' |
  'move_top' |
  'move_bottom' |
  'delete';

export interface HomeShortcutContextAction {
  id: HomeShortcutContextActionId;
  title: string;
  role: 'normal' | 'destructive';
}

export interface HomeShortcutEditDraft {
  shortcutId: string;
  title: string;
  url: string;
  iconPath: string;
}

export type HomeShortcutItemActionId =
  HomeShortcutContextActionId |
  'move_up' |
  'move_down' |
  'remove' |
  'confirm_delete';

export interface HomeShortcutItemUserAction {
  type: 'shortcut_action';
  shortcutId: string;
  actionId: HomeShortcutItemActionId;
}

export interface HomeShortcutConfirmEditUserAction {
  type: 'confirm_edit_shortcut';
  draft: HomeShortcutEditDraft;
}

export interface HomeShortcutMoveUserAction {
  type: 'move_shortcut';
  request: HomeShortcutMoveRequest;
}

export interface HomeShortcutReorderUserAction {
  type: 'reorder_shortcuts';
  orderedShortcutIds: string[];
}

export interface HomeShortcutFolderUserAction {
  type: 'folder_mutation';
  command: HomeShortcutFolderCommand;
}

export type HomeShortcutUserAction =
  HomeShortcutFolderUserAction |
  HomeShortcutItemUserAction |
  HomeShortcutConfirmEditUserAction |
  HomeShortcutMoveUserAction |
  HomeShortcutReorderUserAction;

export type HomeShortcutActionDispatchResult =
  'accepted' |
  'unchanged' |
  'invalid_request' |
  'not_allowed' |
  'not_found';

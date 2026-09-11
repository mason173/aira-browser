import {
  BookmarkNode,
  BookmarkStorageScope
} from '../../common/models/BrowserModels';
import { isBookmarkRootNodeId } from '../../data/repositories/BookmarkRepositoryCore';

export interface BookmarkRecordActionView {
  id: BookmarkRecordActionId;
  title: string;
  role: 'normal' | 'destructive';
}

export type BookmarkRecordActionId =
  'enter_edit_mode' |
  'add_to_home' |
  'remove_from_home' |
  'share' |
  'open_current_tab' |
  'open_new_tab' |
  'open_background_tab' |
  'edit_bookmark' |
  'edit_folder' |
  'move' |
  'delete';

export interface BookmarkRecordActionContext {
  scope: BookmarkStorageScope;
  canSelect: boolean;
  isAddedToHome: boolean;
}

export class BookmarkRecordActionViewModel {
  buildActions(node: BookmarkNode, context: BookmarkRecordActionContext): BookmarkRecordActionView[] {
    if (node.type === 'folder') {
      if (isBookmarkRootNodeId(node.id)) {
        return [];
      }
      const actions: BookmarkRecordActionView[] = [
        { id: 'edit_folder', title: '编辑文件夹', role: 'normal' },
        { id: 'move', title: '移动', role: 'normal' }
      ];
      if (context.canSelect) {
        actions.unshift({ id: 'enter_edit_mode', title: '多选', role: 'normal' });
      }
      actions.push({ id: 'delete', title: '删除', role: 'destructive' });
      return actions;
    }

    const actions: BookmarkRecordActionView[] = [
      { id: 'share', title: '分享', role: 'normal' },
      { id: 'open_current_tab', title: '打开', role: 'normal' },
      { id: 'open_new_tab', title: '新标签页打开', role: 'normal' },
      { id: 'open_background_tab', title: '后台打开', role: 'normal' },
      { id: 'edit_bookmark', title: '编辑书签', role: 'normal' },
      { id: 'move', title: '移动', role: 'normal' },
      { id: 'delete', title: '删除', role: 'destructive' }
    ];
    if (context.scope === 'regular') {
      actions.unshift({
        id: context.isAddedToHome ? 'remove_from_home' : 'add_to_home',
        title: context.isAddedToHome ? '从主页移除' : '添加到主页',
        role: 'normal'
      });
    }
    if (context.canSelect) {
      actions.unshift({ id: 'enter_edit_mode', title: '多选', role: 'normal' });
    }
    return actions;
  }
}

import { BookmarkNode, DesktopBookmarkBarVisibility } from '../../common/models/BrowserModels';
import { isBookmarkRootNodeId } from '../../data/repositories/BookmarkRepositoryCore';

/**
 * Menu entry ids for the Large-Screen bookmark bar context menus. The ids are the contract between
 * the pure menu model and the ArkUI surface, so the surface only renders groups and dispatches ids.
 */
export type BrowserDesktopBookmarkBarMenuItemId =
  'open_new_tab' |
  'open_new_window' |
  'open_private_window' |
  'rename_node' |
  'cut_node' |
  'copy_node' |
  'paste_node' |
  'delete_node' |
  'add_bookmark' |
  'add_folder' |
  'open_manager' |
  'bar_visibility_always' |
  'bar_visibility_never' |
  'bar_visibility_new_tab_only';

export interface BrowserDesktopBookmarkBarMenuItem {
  id: BrowserDesktopBookmarkBarMenuItemId;
  label: string;
  enabled: boolean;
  checked: boolean;
}

export interface BrowserDesktopBookmarkBarMenuInput {
  node: BookmarkNode;
  barVisibility: DesktopBookmarkBarVisibility;
  /** Whether the in-app bookmark clipboard holds a node that can be pasted. */
  hasClipboardContent: boolean;
}

/** The bar's empty area has no node, so its menu only offers bar-wide commands. */
export interface BrowserDesktopBookmarkBarBlankMenuInput {
  barVisibility: DesktopBookmarkBarVisibility;
}

export interface BrowserDesktopBookmarkBarMenuModel {
  groups: BrowserDesktopBookmarkBarMenuItem[][];
}

interface BrowserDesktopBookmarkBarVisibilityEntry {
  id: BrowserDesktopBookmarkBarMenuItemId;
  label: string;
  visibility: DesktopBookmarkBarVisibility;
}

const OPEN_NEW_TAB_LABEL: string = '在新标签页中打开';
const OPEN_NEW_WINDOW_LABEL: string = '在新窗口中打开';
const OPEN_PRIVATE_WINDOW_LABEL: string = '在隐私窗口中打开';
const RENAME_LABEL: string = '重命名...';
const CUT_LABEL: string = '剪切';
const COPY_LABEL: string = '复制';
const PASTE_LABEL: string = '粘贴';
const DELETE_LABEL: string = '删除';
const ADD_BOOKMARK_LABEL: string = '添加网页...';
const ADD_FOLDER_LABEL: string = '添加文件夹...';
const OPEN_MANAGER_LABEL: string = '打开书签管理器';

const VISIBILITY_ENTRIES: BrowserDesktopBookmarkBarVisibilityEntry[] = [
  { id: 'bar_visibility_never', label: '一律隐藏', visibility: 'never' },
  { id: 'bar_visibility_always', label: '一律显示', visibility: 'always' },
  { id: 'bar_visibility_new_tab_only', label: '仅在“新标签页”页面上显示', visibility: 'new_tab_only' }
];

/** Maps a visibility menu entry back to the stored policy it selects. */
export function resolveDesktopBookmarkBarVisibilityForMenuItem(
  id: BrowserDesktopBookmarkBarMenuItemId
): DesktopBookmarkBarVisibility | undefined {
  const entry = VISIBILITY_ENTRIES.find(
    (candidate: BrowserDesktopBookmarkBarVisibilityEntry): boolean => candidate.id === id
  );
  return entry?.visibility;
}

/**
 * Builds the bookmark bar context menu. A folder owns its own contents, so "add" targets the
 * folder itself; a bookmark adds next to its siblings inside the parent folder.
 */
export function buildDesktopBookmarkBarMenuModel(
  input: BrowserDesktopBookmarkBarMenuInput
): BrowserDesktopBookmarkBarMenuModel {
  const node = input.node;
  const isFolder = node.type === 'folder';
  const mutable = !isBookmarkRootNodeId(node.id);
  const groups: BrowserDesktopBookmarkBarMenuItem[][] = [];

  if (isFolder) {
    groups.push(buildVisibilityGroup(input.barVisibility));
    groups.push([buildItem('rename_node', RENAME_LABEL, mutable)]);
    groups.push([buildItem('delete_node', DELETE_LABEL, mutable)]);
    groups.push([
      buildItem('add_bookmark', ADD_BOOKMARK_LABEL, true),
      buildItem('add_folder', ADD_FOLDER_LABEL, true)
    ]);
    return { groups: groups };
  }

  groups.push([
    buildItem('open_new_tab', OPEN_NEW_TAB_LABEL, true),
    buildItem('open_new_window', OPEN_NEW_WINDOW_LABEL, true),
    buildItem('open_private_window', OPEN_PRIVATE_WINDOW_LABEL, true)
  ]);
  groups.push([
    buildItem('cut_node', CUT_LABEL, mutable),
    buildItem('copy_node', COPY_LABEL, true),
    buildItem('paste_node', PASTE_LABEL, input.hasClipboardContent)
  ]);
  groups.push([buildItem('delete_node', DELETE_LABEL, mutable)]);
  groups.push([
    buildItem('add_bookmark', ADD_BOOKMARK_LABEL, true),
    buildItem('add_folder', ADD_FOLDER_LABEL, true)
  ]);
  groups.push([buildItem('open_manager', OPEN_MANAGER_LABEL, true)]);
  groups.push(buildVisibilityGroup(input.barVisibility));
  return { groups: groups };
}

/**
 * Builds the empty-area menu of the bar. It carries no node, so it only offers bar-wide commands:
 * the show-hide policy, adding into the bar root, and the bookmark manager.
 */
export function buildDesktopBookmarkBarBlankMenuModel(
  input: BrowserDesktopBookmarkBarBlankMenuInput
): BrowserDesktopBookmarkBarMenuModel {
  return {
    groups: [
      buildVisibilityGroup(input.barVisibility),
      [
        buildItem('add_bookmark', ADD_BOOKMARK_LABEL, true),
        buildItem('add_folder', ADD_FOLDER_LABEL, true)
      ],
      [buildItem('open_manager', OPEN_MANAGER_LABEL, true)]
    ]
  };
}

function buildVisibilityGroup(
  barVisibility: DesktopBookmarkBarVisibility
): BrowserDesktopBookmarkBarMenuItem[] {
  return VISIBILITY_ENTRIES.map(
    (entry: BrowserDesktopBookmarkBarVisibilityEntry): BrowserDesktopBookmarkBarMenuItem => {
      return {
        id: entry.id,
        label: entry.label,
        enabled: true,
        checked: entry.visibility === barVisibility
      };
    }
  );
}

function buildItem(
  id: BrowserDesktopBookmarkBarMenuItemId,
  label: string,
  enabled: boolean
): BrowserDesktopBookmarkBarMenuItem {
  return {
    id: id,
    label: label,
    enabled: enabled,
    checked: false
  };
}

import { describe, expect, it } from '@ohos/hypium';
import {
  BookmarkNode,
  BrowserAppearanceSettings,
  DesktopBookmarkBarVisibility,
  SyncMetadata
} from '../main/ets/common/models/BrowserModels';
import {
  BrowserDesktopBookmarkBarMenuItem,
  buildDesktopBookmarkBarBlankMenuModel,
  buildDesktopBookmarkBarMenuModel,
  resolveDesktopBookmarkBarVisibilityForMenuItem
} from '../main/ets/core/browser/BrowserDesktopBookmarkBarMenuModel';
import {
  buildDesktopBookmarkBarVisibilitySettings,
  buildToggledDesktopBookmarkBarSettings,
  isDesktopBookmarkBarPainted,
  isDesktopBookmarkBarVisible,
  resolveDesktopBookmarkBarVisibility
} from '../main/ets/core/browser/DesktopBookmarkBarVisibility';

function bookmarkNode(id: string, type: 'folder' | 'bookmark', title: string, url: string = ''): BookmarkNode {
  const sync: SyncMetadata = {
    state: 'local_only',
    source: 'local',
    lastModifiedAt: 1,
    lastModifiedBy: 'test',
    deviceId: 'device'
  };
  return {
    id: id,
    type: type,
    title: title,
    url: url,
    position: 0,
    createdAt: 1,
    updatedAt: 1,
    sync: sync
  };
}

function appearance(
  showDesktopBookmarkBar: boolean,
  visibility?: DesktopBookmarkBarVisibility
): BrowserAppearanceSettings {
  const settings: BrowserAppearanceSettings = {
    bottomToolbarScrollBehavior: 'fixed',
    globalImmersionEnabled: false,
    alwaysTopImmersionEnabled: false,
    forceDarkWebContentEnabled: false,
    blurPrivateTabPreviews: false,
    showHomeRecentlyClosed: true,
    showHomeShortcuts: true,
    homeRecentlyClosedLimit: 8,
    homeShortcutLayoutDensity: 'standard',
    homeShortcutIconSizeRatio: 1,
    siteIconCornerRadiusRatio: 0.3,
    themePaletteId: 'default',
    tabsOverviewLayoutStyle: 'grid',
    tabsOverviewCloseButtonAlwaysVisible: false,
    showDesktopBookmarkBar: showDesktopBookmarkBar
  };
  if (visibility !== undefined) {
    settings.desktopBookmarkBarVisibility = visibility;
  }
  return settings;
}

function menuIds(groups: BrowserDesktopBookmarkBarMenuItem[][]): string {
  const ids: string[] = [];
  groups.forEach((group: BrowserDesktopBookmarkBarMenuItem[]): void => {
    group.forEach((item: BrowserDesktopBookmarkBarMenuItem): void => {
      ids.push(item.id);
    });
  });
  return ids.join(',');
}

function findItem(
  groups: BrowserDesktopBookmarkBarMenuItem[][],
  id: string
): BrowserDesktopBookmarkBarMenuItem | undefined {
  for (let groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
    const group = groups[groupIndex];
    for (let itemIndex = 0; itemIndex < group.length; itemIndex += 1) {
      if (group[itemIndex].id === id) {
        return group[itemIndex];
      }
    }
  }
  return undefined;
}

export default function browserDesktopBookmarkBarMenuModelTest(): void {
  describe('BrowserDesktopBookmarkBarMenuModel', () => {
    it('gives a folder the show-hide policy, rename, delete, and add entries', 0, () => {
      const model = buildDesktopBookmarkBarMenuModel({
        node: bookmarkNode('folder', 'folder', '设计'),
        barVisibility: 'always',
        hasClipboardContent: false
      });

      expect(model.groups.length).assertEqual(4);
      expect(menuIds(model.groups)).assertEqual(
        'bar_visibility_never,bar_visibility_always,bar_visibility_new_tab_only,' +
          'rename_node,delete_node,add_bookmark,add_folder'
      );
      expect(findItem(model.groups, 'bar_visibility_always')?.checked).assertTrue();
      expect(findItem(model.groups, 'bar_visibility_never')?.checked).assertFalse();
      expect(findItem(model.groups, 'rename_node')?.label).assertEqual('重命名...');
      expect(findItem(model.groups, 'add_bookmark')?.label).assertEqual('添加网页...');
      expect(findItem(model.groups, 'add_folder')?.label).assertEqual('添加文件夹...');
      expect(findItem(model.groups, 'open_new_tab')).assertUndefined();
    });

    it('gives a bookmark the open entries, clipboard group, and the manager entry', 0, () => {
      const model = buildDesktopBookmarkBarMenuModel({
        node: bookmarkNode('page', 'bookmark', 'Aira', 'https://aira.example'),
        barVisibility: 'new_tab_only',
        hasClipboardContent: false
      });

      expect(menuIds(model.groups)).assertEqual(
        'open_new_tab,open_new_window,open_private_window,' +
          'cut_node,copy_node,paste_node,' +
          'delete_node,' +
          'add_bookmark,add_folder,' +
          'open_manager,' +
          'bar_visibility_never,bar_visibility_always,bar_visibility_new_tab_only'
      );
      expect(findItem(model.groups, 'open_new_tab')?.label).assertEqual('在新标签页中打开');
      expect(findItem(model.groups, 'open_new_window')?.label).assertEqual('在新窗口中打开');
      expect(findItem(model.groups, 'open_private_window')?.label).assertEqual('在隐私窗口中打开');
      expect(findItem(model.groups, 'open_manager')?.label).assertEqual('打开书签管理器');
      expect(findItem(model.groups, 'bar_visibility_new_tab_only')?.checked).assertTrue();
      expect(findItem(model.groups, 'bar_visibility_never')?.checked).assertFalse();
      expect(findItem(model.groups, 'paste_node')?.enabled).assertFalse();
    });

    it('enables paste only while the bookmark clipboard holds something', 0, () => {
      const model = buildDesktopBookmarkBarMenuModel({
        node: bookmarkNode('page', 'bookmark', 'Aira', 'https://aira.example'),
        barVisibility: 'always',
        hasClipboardContent: true
      });

      expect(findItem(model.groups, 'paste_node')?.enabled).assertTrue();
      expect(findItem(model.groups, 'cut_node')?.enabled).assertTrue();
      expect(findItem(model.groups, 'copy_node')?.enabled).assertTrue();
    });

    it('gives the bar empty area only bar-wide commands', 0, () => {
      const model = buildDesktopBookmarkBarBlankMenuModel({ barVisibility: 'never' });

      expect(menuIds(model.groups)).assertEqual(
        'bar_visibility_never,bar_visibility_always,bar_visibility_new_tab_only,' +
          'add_bookmark,add_folder,' +
          'open_manager'
      );
      expect(findItem(model.groups, 'bar_visibility_never')?.checked).assertTrue();
      expect(findItem(model.groups, 'rename_node')).assertUndefined();
      expect(findItem(model.groups, 'delete_node')).assertUndefined();
      expect(findItem(model.groups, 'paste_node')).assertUndefined();
      expect(findItem(model.groups, 'open_new_tab')).assertUndefined();
    });

    it('maps visibility entries back to the stored policy', 0, () => {
      expect(resolveDesktopBookmarkBarVisibilityForMenuItem('bar_visibility_never')).assertEqual('never');
      expect(resolveDesktopBookmarkBarVisibilityForMenuItem('bar_visibility_always')).assertEqual('always');
      expect(resolveDesktopBookmarkBarVisibilityForMenuItem('bar_visibility_new_tab_only'))
        .assertEqual('new_tab_only');
      expect(resolveDesktopBookmarkBarVisibilityForMenuItem('delete_node')).assertUndefined();
    });
  });

  describe('DesktopBookmarkBarVisibility', () => {
    it('migrates the legacy two-state switch and keeps the new state authoritative', 0, () => {
      expect(resolveDesktopBookmarkBarVisibility(appearance(true))).assertEqual('always');
      expect(resolveDesktopBookmarkBarVisibility(appearance(false))).assertEqual('never');
      expect(resolveDesktopBookmarkBarVisibility(appearance(false, 'new_tab_only'))).assertEqual('new_tab_only');
      expect(resolveDesktopBookmarkBarVisibility(appearance(true, 'never'))).assertEqual('never');
    });

    it('paints the bar per policy and surface', 0, () => {
      expect(isDesktopBookmarkBarPainted('always', false)).assertTrue();
      expect(isDesktopBookmarkBarPainted('never', true)).assertFalse();
      expect(isDesktopBookmarkBarPainted('new_tab_only', true)).assertTrue();
      expect(isDesktopBookmarkBarPainted('new_tab_only', false)).assertFalse();
      expect(isDesktopBookmarkBarPainted(undefined, false)).assertTrue();
      expect(isDesktopBookmarkBarPainted('unexpected', true)).assertTrue();
    });

    it('keeps the legacy switch as the projection of the three-state policy', 0, () => {
      const hidden = buildDesktopBookmarkBarVisibilitySettings(appearance(true), 'never');
      expect(hidden.desktopBookmarkBarVisibility).assertEqual('never');
      expect(hidden.showDesktopBookmarkBar).assertFalse();
      expect(isDesktopBookmarkBarVisible(hidden)).assertFalse();

      const newTabOnly = buildDesktopBookmarkBarVisibilitySettings(hidden, 'new_tab_only');
      expect(newTabOnly.desktopBookmarkBarVisibility).assertEqual('new_tab_only');
      expect(newTabOnly.showDesktopBookmarkBar).assertTrue();
      expect(isDesktopBookmarkBarVisible(newTabOnly)).assertTrue();

      const toggledBack = buildToggledDesktopBookmarkBarSettings(newTabOnly);
      expect(toggledBack.desktopBookmarkBarVisibility).assertEqual('never');
      expect(buildToggledDesktopBookmarkBarSettings(toggledBack).desktopBookmarkBarVisibility)
        .assertEqual('always');
    });
  });
}

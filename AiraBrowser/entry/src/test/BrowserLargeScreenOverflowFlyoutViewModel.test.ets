import { describe, expect, it } from '@ohos/hypium';
import { BookmarkNode, BrowserAppearanceSettings, HistoryVisit, SyncMetadata } from '../main/ets/common/models/BrowserModels';
import {
  alignDesktopSubmenuTop,
  desktopSubmenuRowTop
} from '../main/ets/core/browser/BrowserDesktopMenuPresentationTokens';
import {
  appendOtherBookmarksFolder,
  BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_EMPTY_MESSAGE,
  BrowserLargeScreenOverflowBookmarkItem,
  BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_PRIVATE_MESSAGE,
  BROWSER_LARGE_SCREEN_OVERFLOW_OTHER_BOOKMARKS_TITLE,
  projectOverflowBookmarkItems,
  projectOverflowHistoryItems,
  resolveOverflowBookmarkOtherRootId,
  resolveOverflowBookmarkToolbarRootId,
  resolveOverflowHistoryEmptyMessage
} from '../main/ets/core/browser/BrowserLargeScreenOverflowFlyoutViewModel';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../main/ets/data/repositories/BookmarkRepositoryCore';
import {
  buildToggledDesktopBookmarkBarSettings,
  isDesktopBookmarkBarVisible
} from '../main/ets/core/browser/DesktopBookmarkBarVisibility';

function historyVisit(id: string, title: string, url: string, dataScope: string = ''): HistoryVisit {
  const visit: HistoryVisit = {
    id: id,
    title: title,
    url: url,
    visitedAt: 1,
    dayBucketLabel: '',
    source: 'local',
    deviceId: 'device',
    sessionId: 'session'
  };
  if (dataScope === 'session_ephemeral') {
    visit.dataScope = 'session_ephemeral';
  }
  return visit;
}

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

function appearance(showDesktopBookmarkBar: boolean): BrowserAppearanceSettings {
  return {
    bottomToolbarScrollBehavior: 'fixed',
    toolbarChromeStyle: 'floating',
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
}

export default function browserLargeScreenOverflowFlyoutViewModelTest(): void {
  describe('BrowserLargeScreenOverflowFlyoutViewModel', () => {
    it('projects recent history and skips private or empty visits', 0, () => {
      const visits: HistoryVisit[] = [
        historyVisit('1', 'Aira', 'https://aira.example'),
        historyVisit('2', '', 'https://empty-title.example'),
        historyVisit('3', 'Hidden', 'https://private.example', 'session_ephemeral'),
        historyVisit('4', 'Blank', '')
      ];

      const items = projectOverflowHistoryItems(visits, false, 10);
      expect(items.length).assertEqual(2);
      expect(items[0].title).assertEqual('Aira');
      expect(items[1].title).assertEqual('https://empty-title.example');
      expect(projectOverflowHistoryItems(visits, true, 10).length).assertEqual(0);
      expect(resolveOverflowHistoryEmptyMessage(true, true))
        .assertEqual(BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_PRIVATE_MESSAGE);
      expect(resolveOverflowHistoryEmptyMessage(false, true))
        .assertEqual(BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_EMPTY_MESSAGE);
    });

    it('aligns a nested bookmark menu to the hovered row instead of the column top', 0, () => {
      const headerLeadingVp = 6 + 44 * 2 + 8.5;
      const importedRowTop = desktopSubmenuRowTop(0, headerLeadingVp, 4, 0);
      const firstRowTop = desktopSubmenuRowTop(0, headerLeadingVp, 0, 0);

      expect(importedRowTop).assertEqual(278.5);
      expect(alignDesktopSubmenuTop(importedRowTop, 100, 520)).assertEqual(278.5);
      expect(firstRowTop).assertEqual(102.5);
      expect(alignDesktopSubmenuTop(480, 200, 520)).assertEqual(320);
      expect(desktopSubmenuRowTop(278.5, 6, 0, 0)).assertEqual(284.5);
    });

    it('projects bookmark folders before bookmarks and appends other bookmarks', 0, () => {
      const deleted = bookmarkNode('gone', 'bookmark', 'Gone', 'https://gone.example');
      deleted.sync.deletedAt = 2;
      const items = projectOverflowBookmarkItems([
        bookmarkNode('page', 'bookmark', 'Page', 'https://page.example'),
        bookmarkNode('folder', 'folder', 'Folder'),
        bookmarkNode('empty', 'bookmark', 'No url'),
        deleted
      ]);
      const withOther = appendOtherBookmarksFolder(items, BOOKMARK_OTHER_ROOT_ID, 2);

      expect(items.map((item: BrowserLargeScreenOverflowBookmarkItem): string => item.id).join(','))
        .assertEqual('folder,page');
      expect(items[0].folder).assertTrue();
      expect(withOther[withOther.length - 1].id).assertEqual(BOOKMARK_OTHER_ROOT_ID);
      expect(withOther[withOther.length - 1].title).assertEqual(BROWSER_LARGE_SCREEN_OVERFLOW_OTHER_BOOKMARKS_TITLE);
      expect(appendOtherBookmarksFolder(items, BOOKMARK_OTHER_ROOT_ID, 0).length).assertEqual(items.length);
      expect(resolveOverflowBookmarkToolbarRootId('regular')).assertEqual(BOOKMARK_TOOLBAR_ROOT_ID);
      expect(resolveOverflowBookmarkToolbarRootId('private')).assertEqual(PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID);
      expect(resolveOverflowBookmarkOtherRootId('private')).assertEqual(PRIVATE_BOOKMARK_OTHER_ROOT_ID);
    });

    it('toggles only the desktop bookmark bar flag', 0, () => {
      const current = appearance(true);
      const hidden = buildToggledDesktopBookmarkBarSettings(current);
      const shown = buildToggledDesktopBookmarkBarSettings(hidden);

      expect(isDesktopBookmarkBarVisible(current)).assertTrue();
      expect(isDesktopBookmarkBarVisible(hidden)).assertFalse();
      expect(isDesktopBookmarkBarVisible(shown)).assertTrue();
      expect(hidden.themePaletteId).assertEqual(current.themePaletteId);
      expect(hidden.globalImmersionEnabled).assertEqual(current.globalImmersionEnabled);
    });
  });
}

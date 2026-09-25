/**
 * Right-click menu for the empty area of the PC tab strip, plus the close-all plan
 * that leaves exactly one homepage tab.
 *
 * Vertical tabs toggles the device-local sidebar. The checkmark follows the current
 * mode; the shell intent owns the preference write.
 */

export type BrowserLargeScreenTabStripBlankMenuItemId =
  'new_tab' |
  'restore_latest_recently_closed' |
  'vertical_tabs' |
  'close_all_tabs';

export type BrowserLargeScreenTabStripBlankMenuActionKind =
  'new_tab' |
  'restore_latest_recently_closed' |
  'toggle_vertical_tabs' |
  'close_all_tabs' |
  'none';

export interface BrowserLargeScreenTabStripBlankMenuItem {
  id: BrowserLargeScreenTabStripBlankMenuItemId;
  label: string;
  shortcut: string;
  enabled: boolean;
  checked: boolean;
  actionKind: BrowserLargeScreenTabStripBlankMenuActionKind;
}

export interface BrowserLargeScreenTabStripBlankMenuModel {
  groups: BrowserLargeScreenTabStripBlankMenuItem[][];
}

export interface BrowserLargeScreenTabStripCloseAllTabFact {
  id: string;
  url: string;
  isHome: boolean;
}

export interface BrowserLargeScreenTabStripCloseAllPlan {
  /** False when the window already contains only the homepage tab. */
  createHomepage: boolean;
  /** Tab ids that existed before the replacement homepage was created. */
  closeTabIds: string[];
}

const NEW_TAB_LABEL: string = '新建标签页';
const RESTORE_LATEST_LABEL: string = '重新打开关闭的标签页';
const VERTICAL_TABS_LABEL: string = '垂直标签页';
const CLOSE_ALL_LABEL: string = '关闭所有的标签页';
const NEW_TAB_SHORTCUT: string = 'Ctrl + T';
const RESTORE_LATEST_SHORTCUT: string = 'Ctrl + Shift + T';

export function buildBrowserLargeScreenTabStripBlankMenuModel(
  recentlyClosedCount: number,
  verticalTabsEnabled: boolean = false
): BrowserLargeScreenTabStripBlankMenuModel {
  const canRestoreLatest = normalizeCount(recentlyClosedCount) > 0;
  return {
    groups: [
      [
        menuItem('new_tab', NEW_TAB_LABEL, NEW_TAB_SHORTCUT, true, false, 'new_tab'),
        menuItem(
          'restore_latest_recently_closed',
          RESTORE_LATEST_LABEL,
          RESTORE_LATEST_SHORTCUT,
          canRestoreLatest,
          false,
          'restore_latest_recently_closed'
        ),
        menuItem(
          'vertical_tabs',
          VERTICAL_TABS_LABEL,
          '',
          true,
          verticalTabsEnabled,
          'toggle_vertical_tabs'
        )
      ],
      [
        menuItem('close_all_tabs', CLOSE_ALL_LABEL, '', true, false, 'close_all_tabs')
      ]
    ]
  };
}

/**
 * Close-all is "create a homepage, then close every tab that was already open",
 * so the window ends on one homepage tab. A window that is already only that
 * homepage does not create a replacement or record the homepage as closed.
 */
export function planBrowserLargeScreenTabStripCloseAll(
  tabs: BrowserLargeScreenTabStripCloseAllTabFact[],
  homeUrl: string
): BrowserLargeScreenTabStripCloseAllPlan {
  const normalizedHomeUrl = homeUrl.trim();
  const onlyTab = tabs.length === 1 ? tabs[0] : undefined;
  if (onlyTab !== undefined && isHomepageTab(onlyTab, normalizedHomeUrl)) {
    return {
      createHomepage: false,
      closeTabIds: []
    };
  }
  return {
    createHomepage: true,
    closeTabIds: uniqueTabIds(tabs)
  };
}

function menuItem(
  id: BrowserLargeScreenTabStripBlankMenuItemId,
  label: string,
  shortcut: string,
  enabled: boolean,
  checked: boolean,
  actionKind: BrowserLargeScreenTabStripBlankMenuActionKind
): BrowserLargeScreenTabStripBlankMenuItem {
  return {
    id: id,
    label: label,
    shortcut: shortcut,
    enabled: enabled,
    checked: checked,
    actionKind: actionKind
  };
}

function isHomepageTab(
  tab: BrowserLargeScreenTabStripCloseAllTabFact,
  homeUrl: string
): boolean {
  return homeUrl.length > 0 && tab.isHome && tab.url.trim() === homeUrl;
}

function uniqueTabIds(tabs: BrowserLargeScreenTabStripCloseAllTabFact[]): string[] {
  const seen: Record<string, boolean> = {};
  const ids: string[] = [];
  tabs.forEach((tab: BrowserLargeScreenTabStripCloseAllTabFact): void => {
    const tabId = tab.id.trim();
    if (tabId.length <= 0 || seen[tabId] === true) {
      return;
    }
    seen[tabId] = true;
    ids.push(tabId);
  });
  return ids;
}

function normalizeCount(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.floor(value);
}

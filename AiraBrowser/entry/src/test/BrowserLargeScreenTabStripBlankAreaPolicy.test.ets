import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserLargeScreenTabStripBlankMenuItem,
  BrowserLargeScreenTabStripBlankMenuModel,
  BrowserLargeScreenTabStripCloseAllTabFact,
  buildBrowserLargeScreenTabStripBlankMenuModel,
  planBrowserLargeScreenTabStripCloseAll
} from '../main/ets/core/browser/BrowserLargeScreenTabStripBlankAreaPolicy';

const HOME_URL: string = 'aira://home';

export default function browserLargeScreenTabStripBlankAreaPolicyTest(): void {
  describe('BrowserLargeScreenTabStripBlankAreaPolicy', () => {
    it('lists the blank-area commands in order and toggles vertical tabs', 0, () => {
      const model = buildBrowserLargeScreenTabStripBlankMenuModel(2);
      expect(flattenIds(model)).assertEqual(
        'new_tab,restore_latest_recently_closed,vertical_tabs,close_all_tabs'
      );
      expect(findItem(model, 'new_tab')?.label).assertEqual('新建标签页');
      expect(findItem(model, 'new_tab')?.shortcut).assertEqual('Ctrl + T');
      expect(findItem(model, 'new_tab')?.actionKind).assertEqual('new_tab');
      expect(findItem(model, 'restore_latest_recently_closed')?.label).assertEqual('重新打开关闭的标签页');
      expect(findItem(model, 'restore_latest_recently_closed')?.shortcut).assertEqual('Ctrl + Shift + T');
      expect(findItem(model, 'restore_latest_recently_closed')?.enabled).assertTrue();
      expect(findItem(model, 'vertical_tabs')?.label).assertEqual('垂直标签页');
      expect(findItem(model, 'vertical_tabs')?.enabled).assertTrue();
      expect(findItem(model, 'vertical_tabs')?.checked).assertFalse();
      expect(findItem(model, 'vertical_tabs')?.actionKind).assertEqual('toggle_vertical_tabs');
      expect(findItem(buildBrowserLargeScreenTabStripBlankMenuModel(2, true), 'vertical_tabs')?.checked)
        .assertTrue();
      expect(findItem(model, 'close_all_tabs')?.label).assertEqual('关闭所有的标签页');
      expect(findItem(model, 'close_all_tabs')?.actionKind).assertEqual('close_all_tabs');
      expect(model.groups.length).assertEqual(2);
      expect(model.groups[1].map((item: BrowserLargeScreenTabStripBlankMenuItem): string => item.id).join(','))
        .assertEqual('close_all_tabs');
    });

    it('disables reopen when there is no closed tab to restore', 0, () => {
      expect(findItem(buildBrowserLargeScreenTabStripBlankMenuModel(0), 'restore_latest_recently_closed')?.enabled)
        .assertFalse();
      expect(findItem(buildBrowserLargeScreenTabStripBlankMenuModel(-1), 'restore_latest_recently_closed')?.enabled)
        .assertFalse();
      expect(findItem(buildBrowserLargeScreenTabStripBlankMenuModel(Number.NaN), 'restore_latest_recently_closed')?.enabled)
        .assertFalse();
    });

    it('leaves a lone homepage untouched and otherwise closes every existing tab after creating one', 0, () => {
      const alreadyHome = planBrowserLargeScreenTabStripCloseAll(
        [tab('home', HOME_URL, true)],
        HOME_URL
      );
      expect(alreadyHome.createHomepage).assertFalse();
      expect(alreadyHome.closeTabIds.length).assertEqual(0);

      const webOnly = planBrowserLargeScreenTabStripCloseAll(
        [tab('web-a', 'https://example.com/a', false), tab('web-b', 'https://example.com/b', false)],
        HOME_URL
      );
      expect(webOnly.createHomepage).assertTrue();
      expect(webOnly.closeTabIds.join(',')).assertEqual('web-a,web-b');

      const mixed = planBrowserLargeScreenTabStripCloseAll(
        [tab('home', HOME_URL, true), tab('settings', 'aira://settings', true), tab('web', 'https://example.com', false)],
        HOME_URL
      );
      expect(mixed.createHomepage).assertTrue();
      expect(mixed.closeTabIds.join(',')).assertEqual('home,settings,web');
    });

    it('does not treat a native tab or a blank id as the homepage to keep', 0, () => {
      const nativeOnly = planBrowserLargeScreenTabStripCloseAll(
        [tab('settings', 'aira://settings', true), tab(' ', 'aira://settings', true)],
        HOME_URL
      );
      expect(nativeOnly.createHomepage).assertTrue();
      expect(nativeOnly.closeTabIds.join(',')).assertEqual('settings');

      const emptyWindow = planBrowserLargeScreenTabStripCloseAll([], HOME_URL);
      expect(emptyWindow.createHomepage).assertTrue();
      expect(emptyWindow.closeTabIds.length).assertEqual(0);
    });
  });
}

function tab(id: string, url: string, isHome: boolean): BrowserLargeScreenTabStripCloseAllTabFact {
  return {
    id: id,
    url: url,
    isHome: isHome
  };
}

function findItem(
  model: BrowserLargeScreenTabStripBlankMenuModel,
  id: string
): BrowserLargeScreenTabStripBlankMenuItem | undefined {
  let found: BrowserLargeScreenTabStripBlankMenuItem | undefined = undefined;
  model.groups.forEach((group: BrowserLargeScreenTabStripBlankMenuItem[]): void => {
    group.forEach((item: BrowserLargeScreenTabStripBlankMenuItem): void => {
      if (item.id === id) {
        found = item;
      }
    });
  });
  return found;
}

function flattenIds(model: BrowserLargeScreenTabStripBlankMenuModel): string {
  const ids: string[] = [];
  model.groups.forEach((group: BrowserLargeScreenTabStripBlankMenuItem[]): void => {
    group.forEach((item: BrowserLargeScreenTabStripBlankMenuItem): void => {
      ids.push(item.id);
    });
  });
  return ids.join(',');
}

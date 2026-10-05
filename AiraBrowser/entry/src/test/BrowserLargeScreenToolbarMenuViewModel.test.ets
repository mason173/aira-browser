import { describe, expect, it } from '@ohos/hypium';
import { BrowserBottomAddressPanelAction } from '../main/ets/core/browser/BrowserBottomAddressPanelViewModel';
import { BrowserBottomPanelActionId } from '../main/ets/core/browser/BrowserBottomPanelActionCatalog';
import { resourceStrKey } from '../main/ets/core/browser/BrowserBottomPanelText';
import {
  BROWSER_LARGE_SCREEN_PRIVACY_MODE_TITLE,
  BROWSER_LARGE_SCREEN_SCRIPT_MANAGEMENT_TITLE,
  BROWSER_LARGE_SCREEN_WEB_ZOOM_TITLE,
  BrowserLargeScreenToolbarMenuEntry,
  BrowserLargeScreenToolbarMenuPageToolGroup,
  BrowserLargeScreenToolbarMenuPlan,
  BrowserLargeScreenToolbarMenuSection,
  projectBrowserLargeScreenPointerToolbarMenu,
  resolveBrowserLargeScreenOverflowMenuHeight
} from '../main/ets/core/browser/BrowserLargeScreenToolbarMenuViewModel';

function menuAction(
  id: BrowserBottomPanelActionId,
  title: string,
  selected: boolean = false
): BrowserBottomAddressPanelAction {
  return {
    id: id,
    title: title,
    icon: $r('sys.symbol.house'),
    enabled: true,
    disabledMessage: '',
    selected: selected
  };
}

function desktopActions(): BrowserBottomAddressPanelAction[] {
  return [
    menuAction('print', '打印网页'),
    menuAction('scanQr', '扫一扫'),
    menuAction('appProxySettings', '代理设置'),
    menuAction('settings', '设置'),
    menuAction('newPrivateTab', '退出隐私模式', true),
    menuAction('novel', '我的书架'),
    menuAction('downloads', '下载管理'),
    menuAction('openBookmarks', '书签'),
    menuAction('history', '历史记录'),
    menuAction('copyLink', '复制链接'),
    menuAction('share', '分享网页'),
    menuAction('find', '查找网页'),
    menuAction('textZoom', '网页文字大小'),
    menuAction('reader', '阅读模式'),
    menuAction('translate', '翻译网页'),
    menuAction('video', '资源嗅探'),
    menuAction('offline', '保存网页'),
    menuAction('scripts', '用户脚本'),
    menuAction('elementInspection', '审查元素'),
    menuAction('manualElementHide', '标记广告'),
    menuAction('userAgent', '网站版本'),
    menuAction('addToDesktop', '安装网页'),
    menuAction('themeMode', '外观模式'),
    menuAction('reportSite', '举报网站'),
    menuAction('savedPages', '我的网页'),
    menuAction('bookmark', '添加书签'),
    menuAction('home', '主页'),
    menuAction('sendToDesktop', '推送')
  ];
}

function sectionIds(plan: BrowserLargeScreenToolbarMenuPlan): string[] {
  return plan.sections.map((section: BrowserLargeScreenToolbarMenuSection): string => section.id);
}

function entryIds(entries: BrowserLargeScreenToolbarMenuEntry[]): string[] {
  return entries.map((entry: BrowserLargeScreenToolbarMenuEntry): string => entry.action.id);
}

function section(
  plan: BrowserLargeScreenToolbarMenuPlan,
  id: string
): BrowserLargeScreenToolbarMenuSection | undefined {
  return plan.sections.find((item: BrowserLargeScreenToolbarMenuSection): boolean => item.id === id);
}

function entriesOf(plan: BrowserLargeScreenToolbarMenuPlan, id: string): BrowserLargeScreenToolbarMenuEntry[] {
  const found = section(plan, id);
  if (found === undefined) {
    return [];
  }
  return found.items;
}

function pageToolGroups(plan: BrowserLargeScreenToolbarMenuPlan): BrowserLargeScreenToolbarMenuPageToolGroup[] {
  const found = section(plan, 'page');
  if (found === undefined) {
    return [];
  }
  return found.pageTools;
}

function containsAction(plan: BrowserLargeScreenToolbarMenuPlan, actionId: string): boolean {
  for (let index = 0; index < plan.sections.length; index += 1) {
    const current = plan.sections[index];
    if (entryIds(current.items).indexOf(actionId) >= 0) {
      return true;
    }
    for (let groupIndex = 0; groupIndex < current.pageTools.length; groupIndex += 1) {
      if (entryIds(current.pageTools[groupIndex].items).indexOf(actionId) >= 0) {
        return true;
      }
    }
  }
  return false;
}

export default function browserLargeScreenToolbarMenuViewModelTest(): void {
  describe('BrowserLargeScreenToolbarMenuViewModel', () => {
    it('keeps a fixed grouped menu instead of phone toolbar order', 0, () => {
      const plan = projectBrowserLargeScreenPointerToolbarMenu(desktopActions(), true);

      expect(sectionIds(plan).join(',')).assertEqual('destinations,page,zoom,preferences');
      expect(entryIds(entriesOf(plan, 'destinations')).join(','))
        .assertEqual('history,openBookmarks,downloads,novel');
      expect(entryIds(entriesOf(plan, 'page')).join(',')).assertEqual('copyLink,share,print');
      expect(entryIds(entriesOf(plan, 'zoom')).join(',')).assertEqual('textZoom');
      expect(entryIds(entriesOf(plan, 'preferences')).join(','))
        .assertEqual('scanQr,appProxySettings,newPrivateTab,settings');
      expect(containsAction(plan, 'bookmark')).assertFalse();
      expect(containsAction(plan, 'home')).assertFalse();
      expect(containsAction(plan, 'sendToDesktop')).assertFalse();
    });

    it('keeps the desktop settings row when the phone toolbar no longer carries it', 0, () => {
      const phoneActions = desktopActions().filter((action: BrowserBottomAddressPanelAction): boolean =>
        action.id !== 'settings');
      const plan = projectBrowserLargeScreenPointerToolbarMenu(phoneActions, true);
      const preferences = entriesOf(plan, 'preferences');
      const settings = preferences.find((entry: BrowserLargeScreenToolbarMenuEntry): boolean =>
        entry.action.id === 'settings');

      expect(entryIds(preferences).join(',')).assertEqual('scanQr,appProxySettings,newPrivateTab,settings');
      expect(resourceStrKey(settings?.action.title)).assertEqual(
        resourceStrKey($r('app.string.bottom_panel_action_settings'))
      );
      expect(settings?.action.airaIconId).assertEqual('browser.shortcut.settings');
      expect(settings?.action.enabled).assertTrue();
      expect(settings?.showsSelection).assertFalse();
      expect(settings?.activation).assertEqual('browser_action');
    });

    it('keeps page tools in the same menu when there is no web page', 0, () => {
      const plan = projectBrowserLargeScreenPointerToolbarMenu(desktopActions(), false);

      expect(sectionIds(plan).join(',')).assertEqual('destinations,page,zoom,preferences');
      expect(containsAction(plan, 'copyLink')).assertTrue();
      expect(containsAction(plan, 'scripts')).assertTrue();
      expect(containsAction(plan, 'video')).assertTrue();
    });

    it('groups page tools and renames script management', 0, () => {
      const plan = projectBrowserLargeScreenPointerToolbarMenu(desktopActions(), false);
      const groups = pageToolGroups(plan);
      const development = groups.find((group: BrowserLargeScreenToolbarMenuPageToolGroup): boolean =>
        group.id === 'development');
      const zoom = entriesOf(plan, 'zoom').find((entry: BrowserLargeScreenToolbarMenuEntry): boolean =>
        entry.action.id === 'textZoom');
      const scriptManagement = development === undefined ? undefined : development.items[0];

      expect(groups.map((group: BrowserLargeScreenToolbarMenuPageToolGroup): string => group.id).join(','))
        .assertEqual('reading,media,development,more');
      expect(groups.map((group: BrowserLargeScreenToolbarMenuPageToolGroup): string =>
        resourceStrKey(group.title)).join('|'))
        .assertEqual([
          resourceStrKey($r('app.string.bottom_panel_group_reading')),
          resourceStrKey($r('app.string.bottom_panel_group_media')),
          resourceStrKey($r('app.string.bottom_panel_group_development')),
          ''
        ].join('|'));
      expect(entryIds(groups[0].items).join(',')).assertEqual('find,reader,translate');
      expect(entryIds(groups[1].items).join(',')).assertEqual('video,offline');
      expect(entryIds(development === undefined ? [] : development.items).join(','))
        .assertEqual('scripts,elementInspection,manualElementHide,userAgent');
      expect(scriptManagement?.action.title).assertEqual(BROWSER_LARGE_SCREEN_SCRIPT_MANAGEMENT_TITLE);
      expect(scriptManagement?.activation).assertEqual('user_script_management');
      expect(entryIds(groups[3].items).join(',')).assertEqual('addToDesktop,themeMode,reportSite,savedPages');
      expect(zoom?.action.title).assertEqual(BROWSER_LARGE_SCREEN_WEB_ZOOM_TITLE);
      expect(zoom?.action.enabled).assertFalse();
      expect(zoom?.activation).assertEqual('web_zoom');
    });

    it('keeps privacy mode as a checked state instead of an exit command', 0, () => {
      const plan = projectBrowserLargeScreenPointerToolbarMenu(desktopActions(), true);
      const privacy = entriesOf(plan, 'preferences').find((entry: BrowserLargeScreenToolbarMenuEntry): boolean =>
        entry.action.id === 'newPrivateTab');

      expect(privacy?.action.id).assertEqual('newPrivateTab');
      expect(privacy?.action.title).assertEqual(BROWSER_LARGE_SCREEN_PRIVACY_MODE_TITLE);
      expect(privacy?.action.selected).assertTrue();
      expect(privacy?.showsSelection).assertTrue();
    });

    it('caps the menu at the space under the toolbar and scrolls the remainder', 0, () => {
      const plan = projectBrowserLargeScreenPointerToolbarMenu(desktopActions(), true);
      const unconstrained = resolveBrowserLargeScreenOverflowMenuHeight(plan, 0, 0);
      const capped = resolveBrowserLargeScreenOverflowMenuHeight(plan, 420, 80);

      expect(unconstrained.scrollable).assertFalse();
      expect(unconstrained.heightVp).assertEqual(unconstrained.contentHeightVp);
      expect(capped.maxHeightVp).assertEqual(332);
      expect(capped.scrollable).assertTrue();
      expect(capped.heightVp).assertEqual(332);
      expect(capped.contentHeightVp > capped.heightVp).assertTrue();
    });
  });
}

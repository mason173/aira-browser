import { BrowserLaunchPayload } from '../../app/runtime/BrowserWindowRuntime';
import { BrowserCreateTabOptions, BrowserTabState } from '../../core/tabs/TabManager';
import { DesktopWebEntryRecord } from '../../data/webapps/WebAppInstallModels';
import {
  TabReusePolicyService,
  TabReuseMatchReason
} from '../tabs/TabReusePolicyService';

export type DesktopWebEntryLaunchAction = 'invalid' | 'activate_existing_tab' | 'open_launch_url';

export interface DesktopWebEntryLaunchPlan {
  action: DesktopWebEntryLaunchAction;
  targetUrl: string;
  tabId: string;
  options: BrowserCreateTabOptions;
  reuseReason: TabReuseMatchReason;
  message: string;
}

export class DesktopWebEntryLaunchService {
  private tabReusePolicyService: TabReusePolicyService = new TabReusePolicyService();

  buildPlan(
    payload: BrowserLaunchPayload,
    record: DesktopWebEntryRecord | undefined,
    tabs: BrowserTabState[],
    activeTabId: string
  ): DesktopWebEntryLaunchPlan {
    const shortcut = payload.shortcut;
    if (shortcut === undefined) {
      return this.buildInvalidPlan();
    }
    const targetUrl = this.resolveLaunchUrl(record, payload.uri);
    if (targetUrl.length === 0) {
      return this.buildInvalidPlan('这个桌面入口已失效，请重新添加。');
    }
    const launchContext = this.tabReusePolicyService.buildDesktopWebEntryLaunchContext(
      shortcut.shortcutId,
      targetUrl
    );
    const options: BrowserCreateTabOptions = {
      profileId: payload.profileId,
      privacyMode: payload.privacyMode,
      dataScope: payload.dataScope,
      launchContext: launchContext,
      openSource: 'external'
    };
    const entryScopedTabs = this.filterTabsForDesktopEntry(tabs, shortcut.shortcutId);
    const reusable = this.tabReusePolicyService.findReusableTab(entryScopedTabs, {
      targetUrl: targetUrl,
      activeTabId: '',
      boundary: {
        profileId: payload.profileId,
        privacyMode: payload.privacyMode,
        dataScope: payload.dataScope
      },
      launchContext: launchContext
    });
    if (reusable.tab !== undefined) {
      return {
        action: 'activate_existing_tab',
        targetUrl: targetUrl,
        tabId: reusable.tab.id,
        options: options,
        reuseReason: reusable.reason,
        message: '已切回桌面网页。'
      };
    }
    const entryScopedFallback = this.findMostRecentDesktopEntryTab(entryScopedTabs);
    if (entryScopedFallback !== undefined) {
      return {
        action: 'activate_existing_tab',
        targetUrl: targetUrl,
        tabId: entryScopedFallback.id,
        options: options,
        reuseReason: 'launch_source_id',
        message: '已切回桌面网页。'
      };
    }
    return {
      action: 'open_launch_url',
      targetUrl: targetUrl,
      tabId: activeTabId,
      options: options,
      reuseReason: 'none',
      message: payload.action.length > 0 ? '系统已交给Aira打开链接' : '正在打开桌面网页'
    };
  }

  private filterTabsForDesktopEntry(tabs: BrowserTabState[], shortcutId: string): BrowserTabState[] {
    const sourceId = shortcutId.trim();
    if (sourceId.length === 0) {
      return [];
    }
    return tabs.filter((tab: BrowserTabState) => {
      return tab.launchContext.sourceType === 'desktop_web_entry' &&
        tab.launchContext.sourceId === sourceId;
    });
  }

  private resolveLaunchUrl(record: DesktopWebEntryRecord | undefined, payloadUrl: string): string {
    const currentUrl = record?.currentUrl.trim() ?? '';
    if (record?.installState === 'installed' && currentUrl.length > 0) {
      return currentUrl;
    }
    const recordUrl = record?.launchUrl.trim() ?? '';
    if (recordUrl.length > 0) {
      return recordUrl;
    }
    return payloadUrl.trim();
  }

  private findMostRecentDesktopEntryTab(tabs: BrowserTabState[]): BrowserTabState | undefined {
    let selected: BrowserTabState | undefined = undefined;
    tabs.forEach((tab: BrowserTabState) => {
      if (selected === undefined || tab.lastActiveAt > selected.lastActiveAt) {
        selected = tab;
      }
    });
    return selected;
  }

  private buildInvalidPlan(message: string = '这个桌面入口已失效，请重新添加。'): DesktopWebEntryLaunchPlan {
    return {
      action: 'invalid',
      targetUrl: '',
      tabId: '',
      options: {},
      reuseReason: 'none',
      message: message
    };
  }
}

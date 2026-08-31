import { BrowserTabState } from '../tabs/TabManager';
import { BrowserLargeScreenTabProjectionInput } from './BrowserLargeScreenTabStripViewModel';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import { browserNativeTabSceneService } from './BrowserNativeTabSceneService';
import { BrowserTabsOverviewSectionPolicy } from './tabsOverview/BrowserTabsOverviewSectionPolicy';

export interface BrowserLargeScreenTabCapabilityFacts {
  defaultClosable: boolean;
  closableByTabId?: Record<string, boolean>;
  mutedByTabId?: Record<string, boolean>;
}

/**
 * Converts shared tab records into presentation-only facts.
 *
 * The adapter reads tab identity and semantic state but never mutates a tab,
 * creates a Web runtime, or decides retention/restore/discard policy. Close
 * and mute capabilities are supplied explicitly because they belong to their
 * existing action/runtime owners rather than to this projection.
 */
export class BrowserLargeScreenTabSnapshotAdapter {
  private readonly sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();

  project(
    tabs: BrowserTabState[],
    activeTabId: string,
    capabilities: BrowserLargeScreenTabCapabilityFacts
  ): BrowserLargeScreenTabProjectionInput[] {
    const normalizedActiveTabId = activeTabId.trim();
    return tabs.map((tab: BrowserTabState): BrowserLargeScreenTabProjectionInput => {
      return {
        id: tab.id,
        title: this.resolveTitle(tab),
        url: this.resolveSiteIconUrl(tab),
        fallbackIconId: this.resolveFallbackIconId(tab),
        active: tab.id === normalizedActiveTabId,
        closable: this.resolveClosable(tab.id, capabilities),
        loading: tab.runtimeState === 'loading' || tab.runtimeState === 'restoring',
        muted: tab.muted || this.resolveMuted(tab.id, capabilities),
        privateMode: this.sectionPolicy.isPrivateTab(tab),
        reloadable: !tab.isHome,
        pinned: tab.pinned,
        audible: tab.audible
      };
    });
  }

  private resolveTitle(tab: BrowserTabState): string {
    const nativeTitle = browserNativeTabSceneService.resolveCanonicalTitleForTab(tab.url, tab.pendingUrl);
    if (nativeTitle !== undefined) {
      return nativeTitle;
    }
    if (tab.isHome) {
      return tab.privacyMode === 'private' ? '隐私标签页' : '新标签页';
    }
    const title = tab.title.trim();
    return title.length > 0 ? title : tab.url;
  }

  private resolveFallbackIconId(tab: BrowserTabState): AiraRenderableIconId | undefined {
    const nativeScene = browserNativeTabSceneService.resolveSceneForTab(tab.url, tab.pendingUrl);
    if (nativeScene === 'user_scripts') {
      return 'browser.toolbar.userScripts';
    }
    if (nativeScene === 'app_proxy') {
      return 'browser.toolbar.connectionSecurity';
    }
    if (nativeScene === 'saved_pages') {
      return 'browser.toolbar.savedPages';
    }
    if (!tab.isHome) {
      return undefined;
    }
    return tab.privacyMode === 'private' ? 'browser.tabs.privacyMode' : 'browser.toolbar.siteInfo';
  }

  private resolveSiteIconUrl(tab: BrowserTabState): string {
    if (tab.isHome) {
      return '';
    }
    const candidates = [tab.url, tab.lastGoodUrl, tab.pendingUrl];
    return candidates.find((candidate: string): boolean => {
      const normalized = candidate.trim().toLowerCase();
      return normalized.startsWith('https://') || normalized.startsWith('http://');
    })?.trim() ?? '';
  }

  private resolveClosable(tabId: string, capabilities: BrowserLargeScreenTabCapabilityFacts): boolean {
    if (capabilities.closableByTabId !== undefined &&
      capabilities.closableByTabId[tabId] !== undefined) {
      return capabilities.closableByTabId[tabId] === true;
    }
    return capabilities.defaultClosable === true;
  }

  private resolveMuted(tabId: string, capabilities: BrowserLargeScreenTabCapabilityFacts): boolean {
    return capabilities.mutedByTabId !== undefined && capabilities.mutedByTabId[tabId] === true;
  }
}

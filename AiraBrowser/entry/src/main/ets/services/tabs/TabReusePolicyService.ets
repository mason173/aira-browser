import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  TabLaunchContext
} from '../../common/models/BrowserModels';
import { normalizeUrl } from '../../common/utils/UrlUtils';
import { BrowserTabState } from '../../core/tabs/TabManager';

export type TabReuseMatchReason = 'launch_key' | 'launch_source_id' | 'exact_url' | 'site_key' | 'none';

export interface TabReuseBoundary {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface TabReuseRequest {
  targetUrl: string;
  activeTabId: string;
  boundary?: TabReuseBoundary;
  launchContext: TabLaunchContext;
}

export interface TabReuseResult {
  tab?: BrowserTabState;
  reason: TabReuseMatchReason;
}

export class TabReusePolicyService {
  findReusableTab(tabs: BrowserTabState[], request: TabReuseRequest): TabReuseResult {
    const normalizedTarget = this.normalizeComparableUrl(request.targetUrl);
    if (normalizedTarget.length === 0) {
      return {
        reason: 'none'
      };
    }
    const targetSiteKey = this.buildSiteKey(request.targetUrl);
    const candidates: TabReuseResult[] = tabs
      .filter((tab: BrowserTabState) => {
        return tab.id !== request.activeTabId &&
          !tab.isHome &&
          this.isSameBoundary(tab, request.boundary);
      })
      .map((tab: BrowserTabState): TabReuseResult => {
        return {
          tab: tab,
          reason: this.resolveMatchReason(tab, request.launchContext, normalizedTarget, targetSiteKey)
        };
      })
      .filter((result: TabReuseResult) => result.reason !== 'none')
      .sort((left: TabReuseResult, right: TabReuseResult) => {
        const priorityDelta = this.resolveReasonPriority(right.reason) - this.resolveReasonPriority(left.reason);
        if (priorityDelta !== 0) {
          return priorityDelta;
        }
        return (right.tab?.lastActiveAt ?? 0) - (left.tab?.lastActiveAt ?? 0);
      });
    return candidates[0] ?? {
      reason: 'none'
    };
  }

  buildHomeShortcutLaunchContext(shortcutId: string, sourceUrl: string): TabLaunchContext {
    const sourceId = shortcutId.trim();
    const normalizedUrl = normalizeUrl(sourceUrl).trim();
    return {
      sourceType: sourceId.length > 0 ? 'home_shortcut' : '',
      sourceId: sourceId,
      sourceUrl: normalizedUrl,
      key: sourceId.length > 0 ? `home_shortcut:${sourceId}` : ''
    };
  }

  buildDesktopWebEntryLaunchContext(shortcutId: string, sourceUrl: string): TabLaunchContext {
    const sourceId = shortcutId.trim();
    const normalizedUrl = normalizeUrl(sourceUrl).trim();
    return {
      sourceType: sourceId.length > 0 ? 'desktop_web_entry' : '',
      sourceId: sourceId,
      sourceUrl: normalizedUrl,
      key: sourceId.length > 0 ? `desktop_web_entry:${sourceId}` : ''
    };
  }

  buildBoundaryFromActiveTab(tab: BrowserTabState | undefined): TabReuseBoundary | undefined {
    if (tab === undefined) {
      return undefined;
    }
    return {
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    };
  }

  private resolveMatchReason(
    tab: BrowserTabState,
    launchContext: TabLaunchContext,
    normalizedTarget: string,
    targetSiteKey: string
  ): TabReuseMatchReason {
    if (this.isLaunchKeyMatch(tab, launchContext)) {
      return 'launch_key';
    }
    if (this.isLaunchSourceIdMatch(tab, launchContext)) {
      return 'launch_source_id';
    }
    const candidates = this.buildUrlCandidates(tab);
    if (candidates.some((url: string) => this.normalizeComparableUrl(url) === normalizedTarget)) {
      return 'exact_url';
    }
    if (targetSiteKey.length > 0 && candidates.some((url: string) => this.buildSiteKey(url) === targetSiteKey)) {
      return 'site_key';
    }
    return 'none';
  }

  private isLaunchKeyMatch(tab: BrowserTabState, launchContext: TabLaunchContext): boolean {
    return launchContext.sourceType.length > 0 &&
      tab.launchContext.sourceType === launchContext.sourceType &&
      launchContext.key.length > 0 &&
      tab.launchContext.key === launchContext.key;
  }

  private isLaunchSourceIdMatch(tab: BrowserTabState, launchContext: TabLaunchContext): boolean {
    return launchContext.sourceType.length > 0 &&
      tab.launchContext.sourceType === launchContext.sourceType &&
      launchContext.sourceId.length > 0 &&
      tab.launchContext.sourceId === launchContext.sourceId;
  }

  private buildUrlCandidates(tab: BrowserTabState): string[] {
    return [
      tab.url,
      tab.pendingUrl,
      tab.lastGoodUrl,
      tab.launchContext.sourceUrl,
      tab.navigationHistory.length > 0 && tab.navigationIndex >= 0 && tab.navigationIndex < tab.navigationHistory.length
        ? tab.navigationHistory[tab.navigationIndex]
        : ''
    ];
  }

  private resolveReasonPriority(reason: TabReuseMatchReason): number {
    switch (reason) {
      case 'launch_key':
        return 40;
      case 'launch_source_id':
        return 30;
      case 'exact_url':
        return 20;
      case 'site_key':
        return 10;
      default:
        return 0;
    }
  }

  private isSameBoundary(tab: BrowserTabState, boundary: TabReuseBoundary | undefined): boolean {
    if (boundary === undefined) {
      return true;
    }
    return tab.profileId === boundary.profileId &&
      tab.privacyMode === boundary.privacyMode &&
      tab.dataScope === boundary.dataScope;
  }

  private normalizeComparableUrl(url: string): string {
    const normalized = normalizeUrl(url).trim().toLowerCase();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private buildSiteKey(url: string): string {
    const normalized = normalizeUrl(url).trim();
    if (normalized.length === 0) {
      return '';
    }
    const schemeEndIndex = normalized.indexOf('://');
    if (schemeEndIndex <= 0) {
      return '';
    }
    const scheme = normalized.substring(0, schemeEndIndex).toLowerCase();
    const host = this.readHost(normalized.substring(schemeEndIndex + 3));
    const hostKey = this.normalizeHostKey(host);
    if (hostKey.length === 0) {
      return '';
    }
    return `${scheme}://${hostKey}`;
  }

  private readHost(value: string): string {
    let host = value.trim();
    const slashIndex = this.findFirstBoundary(host);
    if (slashIndex >= 0) {
      host = host.substring(0, slashIndex);
    }
    const atIndex = host.lastIndexOf('@');
    if (atIndex >= 0) {
      host = host.substring(atIndex + 1);
    }
    if (host.startsWith('[')) {
      const closingBracketIndex = host.indexOf(']');
      return closingBracketIndex >= 0 ? host.substring(1, closingBracketIndex) : host;
    }
    const colonIndex = host.indexOf(':');
    if (colonIndex >= 0) {
      host = host.substring(0, colonIndex);
    }
    return host;
  }

  private findFirstBoundary(value: string): number {
    let result = -1;
    const indexes: number[] = [
      value.indexOf('/'),
      value.indexOf('?'),
      value.indexOf('#')
    ];
    indexes.forEach((index: number) => {
      if (index >= 0 && (result < 0 || index < result)) {
        result = index;
      }
    });
    return result;
  }

  private normalizeHostKey(hostname: string): string {
    let host = hostname.trim().toLowerCase();
    if (host.startsWith('www.')) {
      host = host.substring(4);
    }
    if (host === 'cn.bing.com') {
      return 'bing.com';
    }
    if (host.endsWith('.zhihu.com')) {
      return 'zhihu.com';
    }
    if (host === 'm.weibo.cn' || host.endsWith('.weibo.cn')) {
      return 'weibo.com';
    }
    return host;
  }
}

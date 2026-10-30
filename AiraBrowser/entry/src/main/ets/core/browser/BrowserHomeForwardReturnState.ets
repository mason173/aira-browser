import { BrowserDataScope, BrowserProfileId, BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { browserNativeTabSceneService } from './BrowserNativeTabSceneService';
import { BrowserRecentlyClosedTabRecord } from './BrowserRecentlyClosedTabsService';

export interface BrowserHomeForwardBoundary {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserHomeForwardTarget {
  tabId: string;
  recordId: string;
}

// Only this home visit's source is eligible. Old recently-closed records must
// never make Forward available on a fresh launch or an unrelated home visit.
export class BrowserHomeForwardReturnState {
  private sourceTabId: string = '';
  private homeTabId?: string;

  remember(tab: BrowserTabState | undefined): void {
    this.sourceTabId = tab !== undefined && this.isReturnableTab(tab) ? tab.id : '';
  }

  retainForHome(tabId: string): void {
    if (this.homeTabId !== tabId) {
      this.sourceTabId = '';
    }
  }

  bindHome(tabId: string): void {
    this.homeTabId = tabId;
  }

  resolve(
    tabs: BrowserTabState[],
    records: BrowserRecentlyClosedTabRecord[],
    boundary: BrowserHomeForwardBoundary,
    homeTabId: string
  ): BrowserHomeForwardTarget | undefined {
    if (this.sourceTabId.length <= 0 || this.homeTabId !== homeTabId) {
      return undefined;
    }
    const liveTab = tabs.find((tab: BrowserTabState) => tab.id === this.sourceTabId);
    if (liveTab !== undefined && this.isReturnableTab(liveTab) && this.matchesBoundary(liveTab, boundary)) {
      return { tabId: liveTab.id, recordId: '' };
    }
    const record = records.find((item: BrowserRecentlyClosedTabRecord) =>
      item.originalTabId === this.sourceTabId && this.matchesBoundary(item.tab, boundary));
    return record === undefined ? undefined : { tabId: '', recordId: record.id };
  }

  isReturnableTab(tab: BrowserTabState): boolean {
    return !tab.isHome || browserNativeTabSceneService.isNativeTabUrl(tab.url);
  }

  private matchesBoundary(tab: BrowserTabState, boundary: BrowserHomeForwardBoundary): boolean {
    return tab.profileId === boundary.profileId && tab.privacyMode === boundary.privacyMode &&
      tab.dataScope === boundary.dataScope;
  }
}

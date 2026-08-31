import { BrowserTabState } from '../../tabs/TabManager';
import { BrowserTabsOverviewSectionPolicy } from './BrowserTabsOverviewSectionPolicy';

export type BrowserTabsOverviewBottomChromeReturnKind = 'tab' | 'home';

export interface BrowserTabsOverviewBottomChromeInput {
  tabs: BrowserTabState[];
  locallyRemovedTabIds: string[];
  entryTabId: string;
  activeTabId: string;
}

export interface BrowserTabsOverviewBottomChromeState {
  regularTabCount: number;
  regularTabsLabel: string;
  returnKind: BrowserTabsOverviewBottomChromeReturnKind;
  returnTabId: string;
}

export class BrowserTabsOverviewBottomChromeViewModel {
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();

  buildState(input: BrowserTabsOverviewBottomChromeInput): BrowserTabsOverviewBottomChromeState {
    const removedTabIds = this.buildRemovedTabIdMap(input.locallyRemovedTabIds);
    const regularTabCount = this.resolveRegularTabCount(input.tabs, removedTabIds);
    const returnTab = this.resolveReturnTab(input, removedTabIds);
    return {
      regularTabCount: regularTabCount,
      regularTabsLabel: `${regularTabCount} 个标签页`,
      returnKind: returnTab === undefined || returnTab.isHome ? 'home' : 'tab',
      returnTabId: returnTab === undefined || returnTab.isHome ? '' : returnTab.id
    };
  }

  private resolveRegularTabCount(tabs: BrowserTabState[], removedTabIds: Record<string, boolean>): number {
    const regularTabs = this.sectionPolicy.resolveTabsForSection(tabs, 'tabs');
    let count = 0;
    for (let index = 0; index < regularTabs.length; index += 1) {
      if (removedTabIds[regularTabs[index].id] !== true) {
        count += 1;
      }
    }
    return count;
  }

  private resolveReturnTab(
    input: BrowserTabsOverviewBottomChromeInput,
    removedTabIds: Record<string, boolean>
  ): BrowserTabState | undefined {
    const entryTab = this.findAvailableTab(input.tabs, input.entryTabId, removedTabIds);
    if (entryTab !== undefined) {
      return entryTab;
    }
    return this.findAvailableTab(input.tabs, input.activeTabId, removedTabIds);
  }

  private findAvailableTab(
    tabs: BrowserTabState[],
    tabId: string,
    removedTabIds: Record<string, boolean>
  ): BrowserTabState | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0 || removedTabIds[normalizedTabId] === true) {
      return undefined;
    }
    for (let index = 0; index < tabs.length; index += 1) {
      if (tabs[index].id === normalizedTabId) {
        return tabs[index];
      }
    }
    return undefined;
  }

  private buildRemovedTabIdMap(tabIds: string[]): Record<string, boolean> {
    const removedTabIds: Record<string, boolean> = {};
    for (let index = 0; index < tabIds.length; index += 1) {
      const tabId = tabIds[index].trim();
      if (tabId.length > 0) {
        removedTabIds[tabId] = true;
      }
    }
    return removedTabIds;
  }
}

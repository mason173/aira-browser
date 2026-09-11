import { BrowserTabState } from '../tabs/TabManager';

export interface BrowserTabsOverviewLocalRemovalState {
  locallyRemovedTabIds: string[];
}

export class BrowserTabsOverviewShadowViewModel {
  buildInitialLocalRemovalState(): BrowserTabsOverviewLocalRemovalState {
    return { locallyRemovedTabIds: [] };
  }

  reconcileLocalRemovalState(
    state: BrowserTabsOverviewLocalRemovalState,
    tabs: BrowserTabState[]
  ): BrowserTabsOverviewLocalRemovalState {
    const activeIds = this.buildActiveTabIdMap(tabs);
    const retainedTabIds = state.locallyRemovedTabIds.filter((tabId: string) => activeIds[tabId] === true);
    // Returning the same object when nothing changed keeps this @State out of the
    // render loop it is called from (tabs change -> reconcile -> re-render).
    if (retainedTabIds.length === state.locallyRemovedTabIds.length) {
      return state;
    }
    return { locallyRemovedTabIds: retainedTabIds };
  }

  markLocalRemoval(
    state: BrowserTabsOverviewLocalRemovalState,
    tabId: string
  ): BrowserTabsOverviewLocalRemovalState {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0 || state.locallyRemovedTabIds.indexOf(normalizedTabId) >= 0) {
      return state;
    }
    return { locallyRemovedTabIds: state.locallyRemovedTabIds.concat([normalizedTabId]) };
  }

  isLocallyRemoved(state: BrowserTabsOverviewLocalRemovalState, tabId: string): boolean {
    return state.locallyRemovedTabIds.indexOf(tabId) >= 0;
  }

  private buildActiveTabIdMap(tabs: BrowserTabState[]): Record<string, boolean> {
    const activeIds: Record<string, boolean> = {};
    tabs.forEach((tab: BrowserTabState) => {
      activeIds[tab.id] = true;
    });
    return activeIds;
  }
}

import { BrowserTabState } from '../tabs/TabManager';
import { BrowserTabsOverviewSectionPolicy } from './tabsOverview/BrowserTabsOverviewSectionPolicy';

export type BrowserTabsOverviewKeyboardMove = 'up' | 'down' | 'left' | 'right';

export interface BrowserTabsOverviewKeyboardMoveInput {
  tabIds: string[];
  currentTabId: string;
  activeTabId: string;
  columnCount: number;
  move: BrowserTabsOverviewKeyboardMove;
}

export interface BrowserTabsOverviewKeyboardScrollRunInput {
  tabId: string;
  isStillSelected: (tabId: string) => boolean;
  scrollSelection: (tabId: string) => void;
}

const KEYBOARD_SELECTION_SCROLL_DELAY_MS: number = 16;

export class BrowserTabsOverviewKeyboardViewModel {
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();

  resolveSectionTabs(tabs: BrowserTabState[], privacySectionActive: boolean): BrowserTabState[] {
    return this.sectionPolicy.resolveTabsForSection(tabs, privacySectionActive ? 'privacy' : 'tabs');
  }

  resolveInitialSelection(tabIds: string[], activeTabId: string): string {
    if (tabIds.length <= 0) {
      return '';
    }
    if (tabIds.indexOf(activeTabId) >= 0) {
      return activeTabId;
    }
    return tabIds[0];
  }

  resolveNumberedTabId(tabIds: string[], digit: number): string {
    if (digit === 9) {
      return tabIds.length > 0 ? tabIds[tabIds.length - 1] : '';
    }
    if (digit < 1 || digit > 8 || digit > tabIds.length) {
      return '';
    }
    return tabIds[digit - 1];
  }

  resolveInitialBrowserTabSelection(tabs: BrowserTabState[], activeTabId: string): string {
    return this.resolveInitialSelection(this.resolveTabIds(tabs), activeTabId);
  }

  resolveNumberedBrowserTabId(tabs: BrowserTabState[], digit: number): string {
    return this.resolveNumberedTabId(this.resolveTabIds(tabs), digit);
  }

  moveSelection(input: BrowserTabsOverviewKeyboardMoveInput): string {
    if (input.tabIds.length <= 0) {
      return '';
    }
    const currentIndex = this.resolveCurrentIndex(input.tabIds, input.currentTabId, input.activeTabId);
    const columnCount = Math.max(1, input.columnCount);
    let targetIndex = currentIndex;
    if (input.move === 'left') {
      targetIndex = Math.max(0, currentIndex - 1);
    } else if (input.move === 'right') {
      targetIndex = Math.min(input.tabIds.length - 1, currentIndex + 1);
    } else if (input.move === 'up') {
      targetIndex = Math.max(0, currentIndex - columnCount);
    } else if (input.move === 'down') {
      targetIndex = Math.min(input.tabIds.length - 1, currentIndex + columnCount);
    }
    return input.tabIds[targetIndex];
  }

  resolveSelectedTabId(tabIds: string[], effectiveSelectedTabId: string, externalSelectedTabId: string): string {
    if (tabIds.indexOf(effectiveSelectedTabId) >= 0) {
      return effectiveSelectedTabId;
    }
    if (tabIds.indexOf(externalSelectedTabId) >= 0) {
      return externalSelectedTabId;
    }
    return '';
  }

  resolveBadgeText(tabIds: string[], tabId: string): string {
    const index = tabIds.indexOf(tabId);
    if (index < 0 || index > 8) {
      return '';
    }
    return `${index + 1}`;
  }

  scheduleSelectionScroll(input: BrowserTabsOverviewKeyboardScrollRunInput): void {
    setTimeout(() => {
      if (!input.isStillSelected(input.tabId)) {
        return;
      }
      input.scrollSelection(input.tabId);
    }, this.getSelectionScrollDelayMs());
  }

  getSelectionScrollDelayMs(): number {
    return KEYBOARD_SELECTION_SCROLL_DELAY_MS;
  }

  private resolveCurrentIndex(tabIds: string[], currentTabId: string, activeTabId: string): number {
    const selectedIndex = tabIds.indexOf(currentTabId);
    if (selectedIndex >= 0) {
      return selectedIndex;
    }
    const activeIndex = tabIds.indexOf(activeTabId);
    if (activeIndex >= 0) {
      return activeIndex;
    }
    return 0;
  }

  private resolveTabIds(tabs: BrowserTabState[]): string[] {
    return tabs.map((tab: BrowserTabState) => tab.id);
  }
}

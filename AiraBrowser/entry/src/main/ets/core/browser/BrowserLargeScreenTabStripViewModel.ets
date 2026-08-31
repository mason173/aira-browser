import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import { BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP } from './BrowserLargeScreenTitleBarTokens';

// Pinned tabs collapse to a fixed icon-only footprint on the leading edge and
// never join the flexible width distribution used for the remaining tabs.
const PINNED_TAB_WIDTH_VP: number = 40;

export type BrowserLargeScreenWindowProfile =
  'compact' |
  'medium' |
  'expanded' |
  'free_window' |
  'subwindow';

export type BrowserLargeScreenInputProfile = 'touch' | 'pointer' | 'keyboard_pointer';

export interface BrowserLargeScreenTabProjectionInput {
  id: string;
  title: string;
  url: string;
  fallbackIconId?: AiraRenderableIconId;
  active: boolean;
  closable: boolean;
  loading: boolean;
  muted: boolean;
  privateMode: boolean;
  reloadable: boolean;
  pinned: boolean;
  audible: boolean;
}

export interface BrowserLargeScreenTabContextMenuPresentation {
  reloadEnabled: boolean;
  duplicateEnabled: boolean;
  pinEnabled: boolean;
  muteEnabled: boolean;
  closeEnabled: boolean;
  closeOthersEnabled: boolean;
  closeRightEnabled: boolean;
}

export interface BrowserLargeScreenTabStripPolicy {
  minimumTabWidthVp: number;
  maximumTabWidthVp: number;
  compactTabWidthVp: number;
  selectedTabExtraWidthVp: number;
  fixedChromeWidthVp: number;
}

export interface BrowserLargeScreenTabStripFacts {
  availableWidthVp: number;
  titleButtonWidthVp: number;
  titleButtonHeightVp: number;
  windowTitleBarIntegrated: boolean;
  windowProfile: BrowserLargeScreenWindowProfile;
  inputProfile: BrowserLargeScreenInputProfile;
  activeTabId: string;
  dragSupported: boolean;
  tabs: BrowserLargeScreenTabProjectionInput[];
  policy: BrowserLargeScreenTabStripPolicy;
}

export interface BrowserLargeScreenTabProjection {
  id: string;
  title: string;
  url: string;
  fallbackIconId?: AiraRenderableIconId;
  active: boolean;
  closable: boolean;
  loading: boolean;
  muted: boolean;
  privateMode: boolean;
  pinned: boolean;
  audible: boolean;
  contextMenu: BrowserLargeScreenTabContextMenuPresentation;
  widthVp: number;
  leftVp: number;
}

export interface BrowserLargeScreenTabStripPresentation {
  allTabs: BrowserLargeScreenTabProjection[];
  visibleTabs: BrowserLargeScreenTabProjection[];
  hiddenTabIds: string[];
  selectedTabId: string;
  overflowVisible: boolean;
  dragEnabled: boolean;
  hoverVisible: boolean;
  newTabVisible: boolean;
  titleBarHeightVp: number;
  titleButtonWidthVp: number;
  windowMoveEnabled: boolean;
  availableWidthVp: number;
  consumedWidthVp: number;
}

interface BrowserLargeScreenTabStripVisibleRange {
  start: number;
  end: number;
}

/**
 * Owns the non-visual resource calculation for the Large-Screen tab strip.
 *
 * The interface accepts shaped tab facts and a window resource budget. It
 * never receives TabManager, Web controllers, or discard/restore commands;
 * callers get a copied presentation snapshot that can be rendered by any
 * Shell adapter.
 */
export class BrowserLargeScreenTabStripViewModel {
  resolvePresentation(facts: BrowserLargeScreenTabStripFacts): BrowserLargeScreenTabStripPresentation {
    const normalizedPolicy = this.normalizePolicy(facts.policy);
    const tabs = this.normalizeTabs(facts.tabs, facts.activeTabId);
    const availableWidthVp = this.resolveAvailableWidth(facts, normalizedPolicy);
    const minimumTabWidthVp = this.resolveMinimumTabWidth(facts.windowProfile, normalizedPolicy);
    const visibleCount = this.resolveVisibleCount(tabs.length, availableWidthVp, minimumTabWidthVp);
    const activeIndex = this.resolveActiveIndex(tabs, facts.activeTabId);
    const visibleRange = this.resolveVisibleRange(tabs.length, visibleCount, activeIndex);
    const visibleTabs = tabs.slice(visibleRange.start, visibleRange.end);
    const hiddenTabIds = this.resolveHiddenTabIds(tabs, visibleRange.start, visibleRange.end);
    const tabWidths = this.resolveTabWidths(visibleTabs, availableWidthVp, normalizedPolicy, minimumTabWidthVp);
    const projectedTabs = this.buildProjectedTabs(visibleTabs, tabWidths, tabs);
    const allTabs = this.buildProjectedTabs(this.resolveBoundaryTabs(tabs, facts.activeTabId), [], tabs);
    const consumedWidthVp = this.resolveConsumedWidth(projectedTabs);

    return {
      allTabs: allTabs,
      visibleTabs: projectedTabs,
      hiddenTabIds: hiddenTabIds,
      selectedTabId: this.resolveSelectedTabId(tabs, facts.activeTabId),
      // The Chrome-style tab list now owns the stable leading entry.
      overflowVisible: false,
      dragEnabled: facts.dragSupported && tabs.length > 1,
      // Keep regular-tab close buttons stable in the desktop strip instead of
      // reserving them for the active or pointer-hovered tab.
      hoverVisible: false,
      newTabVisible: availableWidthVp >= minimumTabWidthVp,
      titleBarHeightVp: this.resolveTitleBarHeight(facts),
      titleButtonWidthVp: facts.windowTitleBarIntegrated
        ? this.normalizeNonNegativeDimension(facts.titleButtonWidthVp)
        : 0,
      windowMoveEnabled: facts.windowTitleBarIntegrated === true,
      availableWidthVp: availableWidthVp,
      consumedWidthVp: consumedWidthVp
    };
  }

  private resolveBoundaryTabs(
    tabs: BrowserLargeScreenTabProjectionInput[],
    activeTabId: string
  ): BrowserLargeScreenTabProjectionInput[] {
    const activeTab = tabs.find((tab: BrowserLargeScreenTabProjectionInput): boolean => tab.id === activeTabId) ??
      tabs.find((tab: BrowserLargeScreenTabProjectionInput): boolean => tab.active) ?? tabs[0];
    if (activeTab === undefined) {
      return [];
    }
    return tabs.filter((tab: BrowserLargeScreenTabProjectionInput): boolean => {
      return tab.privateMode === activeTab.privateMode;
    });
  }

  private normalizePolicy(policy: BrowserLargeScreenTabStripPolicy): BrowserLargeScreenTabStripPolicy {
    const minimumTabWidthVp = this.normalizePositiveDimension(policy.minimumTabWidthVp, 1);
    const maximumTabWidthVp = Math.max(
      minimumTabWidthVp,
      this.normalizePositiveDimension(policy.maximumTabWidthVp, minimumTabWidthVp)
    );
    return {
      minimumTabWidthVp: minimumTabWidthVp,
      maximumTabWidthVp: maximumTabWidthVp,
      compactTabWidthVp: Math.max(
        minimumTabWidthVp,
        Math.min(maximumTabWidthVp, this.normalizePositiveDimension(policy.compactTabWidthVp, minimumTabWidthVp))
      ),
      selectedTabExtraWidthVp: this.normalizeNonNegativeDimension(policy.selectedTabExtraWidthVp),
      fixedChromeWidthVp: this.normalizeNonNegativeDimension(policy.fixedChromeWidthVp)
    };
  }

  private normalizeTabs(
    tabs: BrowserLargeScreenTabProjectionInput[],
    activeTabId: string
  ): BrowserLargeScreenTabProjectionInput[] {
    const seenTabIds: Record<string, boolean> = {};
    const normalizedActiveTabId = activeTabId.trim();
    const candidates: BrowserLargeScreenTabProjectionInput[] = [];
    tabs.forEach((tab: BrowserLargeScreenTabProjectionInput): void => {
      const id = tab.id.trim();
      if (id.length === 0 || seenTabIds[id] === true) {
        return;
      }
      seenTabIds[id] = true;
      candidates.push({
        id: id,
        title: tab.title,
        url: tab.url.trim(),
        fallbackIconId: tab.fallbackIconId,
        active: tab.active === true,
        closable: tab.closable === true,
        loading: tab.loading === true,
        muted: tab.muted === true,
        privateMode: tab.privateMode === true,
        reloadable: tab.reloadable === true,
        pinned: tab.pinned === true,
        audible: tab.audible === true
      });
    });
    const requestedTabExists = candidates.some((tab: BrowserLargeScreenTabProjectionInput): boolean => {
      return tab.id === normalizedActiveTabId;
    });
    const fallbackActiveTab = candidates.find((tab: BrowserLargeScreenTabProjectionInput): boolean => {
      return tab.active;
    });
    const selectedTabId = requestedTabExists
      ? normalizedActiveTabId
      : fallbackActiveTab?.id ?? candidates[0]?.id ?? '';
    return candidates.map((tab: BrowserLargeScreenTabProjectionInput): BrowserLargeScreenTabProjectionInput => {
      return {
        id: tab.id,
        title: tab.title,
        url: tab.url,
        fallbackIconId: tab.fallbackIconId,
        active: selectedTabId.length > 0 && tab.id === selectedTabId,
        closable: tab.closable,
        loading: tab.loading,
        muted: tab.muted,
        privateMode: tab.privateMode,
        reloadable: tab.reloadable,
        pinned: tab.pinned,
        audible: tab.audible
      };
    });
  }

  private resolveAvailableWidth(
    facts: BrowserLargeScreenTabStripFacts,
    policy: BrowserLargeScreenTabStripPolicy
  ): number {
    const windowWidthVp = this.normalizeNonNegativeDimension(facts.availableWidthVp);
    const titleButtonWidthVp = facts.windowTitleBarIntegrated
      ? this.normalizeNonNegativeDimension(facts.titleButtonWidthVp)
      : 0;
    return Math.max(0, windowWidthVp - titleButtonWidthVp - policy.fixedChromeWidthVp);
  }

  private resolveTitleBarHeight(facts: BrowserLargeScreenTabStripFacts): number {
    if (!facts.windowTitleBarIntegrated) {
      return BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP;
    }
    return Math.max(
      BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP,
      this.normalizeNonNegativeDimension(facts.titleButtonHeightVp)
    );
  }

  private resolveMinimumTabWidth(
    windowProfile: BrowserLargeScreenWindowProfile,
    policy: BrowserLargeScreenTabStripPolicy
  ): number {
    if (windowProfile === 'compact' || windowProfile === 'free_window' || windowProfile === 'subwindow') {
      return policy.compactTabWidthVp;
    }
    return policy.minimumTabWidthVp;
  }

  private resolveVisibleCount(tabCount: number, availableWidthVp: number, minimumTabWidthVp: number): number {
    if (tabCount <= 0 || availableWidthVp < minimumTabWidthVp) {
      return 0;
    }
    return Math.min(tabCount, Math.max(1, Math.floor(availableWidthVp / minimumTabWidthVp)));
  }

  private resolveActiveIndex(tabs: BrowserLargeScreenTabProjectionInput[], activeTabId: string): number {
    const normalizedActiveTabId = activeTabId.trim();
    const explicitIndex = tabs.findIndex((tab: BrowserLargeScreenTabProjectionInput): boolean => {
      return tab.id === normalizedActiveTabId || tab.active;
    });
    return explicitIndex < 0 ? 0 : explicitIndex;
  }

  private resolveVisibleRange(
    tabCount: number,
    visibleCount: number,
    activeIndex: number
  ): BrowserLargeScreenTabStripVisibleRange {
    if (visibleCount <= 0 || tabCount <= 0) {
      return { start: 0, end: 0 };
    }
    const maximumStart = Math.max(0, tabCount - visibleCount);
    const start = Math.max(0, Math.min(maximumStart, activeIndex - visibleCount + 1));
    return { start: start, end: start + visibleCount };
  }

  private resolveHiddenTabIds(
    tabs: BrowserLargeScreenTabProjectionInput[],
    start: number,
    end: number
  ): string[] {
    const hiddenTabIds: string[] = [];
    tabs.forEach((tab: BrowserLargeScreenTabProjectionInput, index: number): void => {
      if (index < start || index >= end) {
        hiddenTabIds.push(tab.id);
      }
    });
    return hiddenTabIds;
  }

  private resolveTabWidths(
    tabs: BrowserLargeScreenTabProjectionInput[],
    availableWidthVp: number,
    policy: BrowserLargeScreenTabStripPolicy,
    minimumTabWidthVp: number
  ): number[] {
    if (tabs.length === 0 || availableWidthVp <= 0) {
      return [];
    }
    const pinnedWidthVp = Math.max(1, Math.min(PINNED_TAB_WIDTH_VP, availableWidthVp));
    const pinnedCount = tabs.filter((tab: BrowserLargeScreenTabProjectionInput): boolean => tab.pinned).length;
    const flexibleCount = tabs.length - pinnedCount;
    const flexibleWidthBudgetVp = Math.max(0, availableWidthVp - pinnedCount * pinnedWidthVp);
    if (flexibleCount <= 0) {
      return tabs.map((): number => pinnedWidthVp);
    }
    const baseWidthVp = Math.max(
      minimumTabWidthVp,
      Math.min(policy.maximumTabWidthVp, Math.floor(flexibleWidthBudgetVp / flexibleCount))
    );
    const activeIndex = tabs.findIndex(
      (tab: BrowserLargeScreenTabProjectionInput): boolean => tab.active && !tab.pinned
    );
    if (activeIndex < 0 || flexibleCount === 1 || policy.selectedTabExtraWidthVp <= 0) {
      return tabs.map((tab: BrowserLargeScreenTabProjectionInput): number =>
        tab.pinned ? pinnedWidthVp : baseWidthVp);
    }

    const selectedWidthVp = Math.min(
      policy.maximumTabWidthVp,
      baseWidthVp + Math.min(
        policy.selectedTabExtraWidthVp,
        Math.max(0, flexibleWidthBudgetVp - baseWidthVp - (flexibleCount - 1) * minimumTabWidthVp)
      )
    );
    const remainingFlexibleCount = flexibleCount - 1;
    const remainingWidthVp = Math.max(0, flexibleWidthBudgetVp - selectedWidthVp);
    const normalWidthVp = remainingFlexibleCount <= 0
      ? 0
      : Math.max(minimumTabWidthVp, Math.min(policy.maximumTabWidthVp,
        Math.floor(remainingWidthVp / remainingFlexibleCount)));
    return tabs.map((tab: BrowserLargeScreenTabProjectionInput, index: number): number => {
      if (tab.pinned) {
        return pinnedWidthVp;
      }
      return index === activeIndex ? selectedWidthVp : normalWidthVp;
    });
  }

  private buildProjectedTabs(
    tabs: BrowserLargeScreenTabProjectionInput[],
    widths: number[],
    allTabs: BrowserLargeScreenTabProjectionInput[]
  ): BrowserLargeScreenTabProjection[] {
    const projectedTabs: BrowserLargeScreenTabProjection[] = [];
    let leftVp = 0;
    tabs.forEach((tab: BrowserLargeScreenTabProjectionInput, index: number): void => {
      const widthVp = widths[index] ?? 0;
      projectedTabs.push({
        id: tab.id,
        title: tab.title,
        url: tab.url,
        fallbackIconId: tab.fallbackIconId,
        active: tab.active,
        closable: tab.closable,
        loading: tab.loading,
        muted: tab.muted,
        privateMode: tab.privateMode,
        pinned: tab.pinned,
        audible: tab.audible,
        contextMenu: this.resolveContextMenuPresentation(tab, allTabs),
        widthVp: widthVp,
        leftVp: leftVp
      });
      leftVp += widthVp;
    });
    return projectedTabs;
  }

  private resolveContextMenuPresentation(
    tab: BrowserLargeScreenTabProjectionInput,
    allTabs: BrowserLargeScreenTabProjectionInput[]
  ): BrowserLargeScreenTabContextMenuPresentation {
    const targetIndex = allTabs.findIndex((candidate: BrowserLargeScreenTabProjectionInput): boolean => {
      return candidate.id === tab.id;
    });
    return {
      reloadEnabled: tab.reloadable,
      duplicateEnabled: true,
      // Pin applies to any tab (persisted via TabRecord.isPinned); mute targets
      // real web pages whose ArkWeb runtime can be silenced. Home/native scenes
      // are not reloadable and therefore cannot be muted.
      pinEnabled: true,
      muteEnabled: tab.reloadable,
      closeEnabled: tab.closable,
      closeOthersEnabled: allTabs.some((candidate: BrowserLargeScreenTabProjectionInput): boolean => {
        return candidate.id !== tab.id && candidate.closable;
      }),
      closeRightEnabled: targetIndex >= 0 && allTabs
        .slice(targetIndex + 1)
        .some((candidate: BrowserLargeScreenTabProjectionInput): boolean => candidate.closable)
    };
  }

  private resolveSelectedTabId(tabs: BrowserLargeScreenTabProjectionInput[], activeTabId: string): string {
    const normalizedActiveTabId = activeTabId.trim();
    if (tabs.some((tab: BrowserLargeScreenTabProjectionInput): boolean => tab.id === normalizedActiveTabId)) {
      return normalizedActiveTabId;
    }
    const activeTab = tabs.find((tab: BrowserLargeScreenTabProjectionInput): boolean => tab.active);
    return activeTab?.id ?? '';
  }

  private resolveConsumedWidth(tabs: BrowserLargeScreenTabProjection[]): number {
    if (tabs.length === 0) {
      return 0;
    }
    const lastTab = tabs[tabs.length - 1];
    return lastTab.leftVp + lastTab.widthVp;
  }

  private normalizePositiveDimension(value: number, fallback: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return fallback;
    }
    return Math.max(1, Math.round(value));
  }

  private normalizeNonNegativeDimension(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }
}

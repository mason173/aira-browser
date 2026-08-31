export type BrowserHostedWebHiddenSlotKind =
  'background-hot' |
  'desktop-web-entry-parked';

export interface BrowserHostedWebHiddenSlot {
  tabId: string;
  kind: BrowserHostedWebHiddenSlotKind;
}

export interface BrowserHostedWebOwnershipSnapshot {
  backgroundHotTabIds: string[];
  parkedDesktopWebEntryTabIds: string[];
  pendingForegroundAttachTabIds: string[];
  hiddenSlots: BrowserHostedWebHiddenSlot[];
}

export interface BrowserHostedWebMarkResult {
  snapshot: BrowserHostedWebOwnershipSnapshot;
  overflowTabIds: string[];
}

export interface BrowserHostedWebReleaseResult {
  snapshot: BrowserHostedWebOwnershipSnapshot;
  released: boolean;
}

export interface BrowserHostedWebForegroundAttachStartResult {
  snapshot: BrowserHostedWebOwnershipSnapshot;
  shouldScheduleFinish: boolean;
}

export interface BrowserHostedWebForegroundAttachFinishInput {
  tabId: string;
  activeTabId: string;
  showHomePage: boolean;
  showTabsSheet: boolean;
}

export interface BrowserHostedWebForegroundAttachFinishResult {
  snapshot: BrowserHostedWebOwnershipSnapshot;
  shouldAttachForeground: boolean;
}

export class BrowserHostedWebOwnershipCoordinator {
  private backgroundHotTabIds: string[] = [];
  private parkedDesktopWebEntryTabIds: string[] = [];
  private pendingForegroundAttachTabIds: string[] = [];

  getSnapshot(): BrowserHostedWebOwnershipSnapshot {
    return {
      backgroundHotTabIds: this.backgroundHotTabIds,
      parkedDesktopWebEntryTabIds: this.parkedDesktopWebEntryTabIds,
      pendingForegroundAttachTabIds: this.pendingForegroundAttachTabIds,
      hiddenSlots: this.buildHiddenSlots()
    };
  }

  isBackgroundHot(tabId: string): boolean {
    return this.backgroundHotTabIds.includes(tabId);
  }

  isParked(tabId: string): boolean {
    return this.parkedDesktopWebEntryTabIds.includes(tabId);
  }

  isPendingForegroundAttach(tabId: string): boolean {
    return this.pendingForegroundAttachTabIds.includes(tabId);
  }

  canHostActive(tabId: string): boolean {
    return !this.isBackgroundHot(tabId) &&
      !this.isParked(tabId) &&
      !this.isPendingForegroundAttach(tabId);
  }

  markBackgroundHot(tabId: string, maxCount: number): BrowserHostedWebMarkResult {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return {
        snapshot: this.getSnapshot(),
        overflowTabIds: []
      };
    }
    const nextTabIds = this.backgroundHotTabIds
      .filter((item: string) => item !== normalizedTabId)
      .concat([normalizedTabId]);
    const overflowTabIds = this.resolveOverflow(nextTabIds, maxCount);
    this.backgroundHotTabIds = nextTabIds
      .slice(Math.max(0, nextTabIds.length - maxCount))
      .filter((item: string) => !overflowTabIds.includes(item));
    return {
      snapshot: this.getSnapshot(),
      overflowTabIds: overflowTabIds
    };
  }

  releaseBackgroundHot(tabId: string): BrowserHostedWebReleaseResult {
    const normalizedTabId = tabId.trim();
    const released = normalizedTabId.length > 0 && this.backgroundHotTabIds.includes(normalizedTabId);
    if (released) {
      this.backgroundHotTabIds = this.backgroundHotTabIds.filter((item: string) => item !== normalizedTabId);
    }
    return {
      snapshot: this.getSnapshot(),
      released: released
    };
  }

  markParkedDesktopWebEntry(tabId: string, maxCount: number): BrowserHostedWebMarkResult {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return {
        snapshot: this.getSnapshot(),
        overflowTabIds: []
      };
    }
    const nextTabIds = this.parkedDesktopWebEntryTabIds
      .filter((item: string) => item !== normalizedTabId)
      .concat([normalizedTabId]);
    const overflowTabIds = this.resolveOverflow(nextTabIds, maxCount);
    this.parkedDesktopWebEntryTabIds = nextTabIds
      .slice(Math.max(0, nextTabIds.length - maxCount))
      .filter((item: string) => !overflowTabIds.includes(item));
    return {
      snapshot: this.getSnapshot(),
      overflowTabIds: overflowTabIds
    };
  }

  releaseParkedDesktopWebEntry(tabId: string): BrowserHostedWebReleaseResult {
    const normalizedTabId = tabId.trim();
    const released = normalizedTabId.length > 0 && this.parkedDesktopWebEntryTabIds.includes(normalizedTabId);
    if (released) {
      this.parkedDesktopWebEntryTabIds = this.parkedDesktopWebEntryTabIds
        .filter((item: string) => item !== normalizedTabId);
    }
    return {
      snapshot: this.getSnapshot(),
      released: released
    };
  }

  clearBackgroundHotTabs(): BrowserHostedWebOwnershipSnapshot {
    this.backgroundHotTabIds = [];
    return this.getSnapshot();
  }

  beginForegroundAttach(tabId: string): BrowserHostedWebForegroundAttachStartResult {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return {
        snapshot: this.getSnapshot(),
        shouldScheduleFinish: false
      };
    }
    const alreadyPending = this.pendingForegroundAttachTabIds.includes(normalizedTabId);
    if (!alreadyPending) {
      this.pendingForegroundAttachTabIds = this.pendingForegroundAttachTabIds.concat([normalizedTabId]);
    }
    return {
      snapshot: this.getSnapshot(),
      shouldScheduleFinish: !alreadyPending
    };
  }

  finishForegroundAttach(
    input: BrowserHostedWebForegroundAttachFinishInput
  ): BrowserHostedWebForegroundAttachFinishResult {
    const normalizedTabId = input.tabId.trim();
    if (normalizedTabId.length === 0) {
      return {
        snapshot: this.getSnapshot(),
        shouldAttachForeground: false
      };
    }
    this.pendingForegroundAttachTabIds = this.pendingForegroundAttachTabIds
      .filter((item: string) => item !== normalizedTabId);
    return {
      snapshot: this.getSnapshot(),
      shouldAttachForeground: normalizedTabId === input.activeTabId && !input.showHomePage && !input.showTabsSheet
    };
  }

  clearParkedDesktopWebEntries(): BrowserHostedWebOwnershipSnapshot {
    this.parkedDesktopWebEntryTabIds = [];
    return this.getSnapshot();
  }

  private buildHiddenSlots(): BrowserHostedWebHiddenSlot[] {
    const backgroundSlots = this.backgroundHotTabIds.map((tabId: string): BrowserHostedWebHiddenSlot => {
      return {
        tabId: tabId,
        kind: 'background-hot'
      };
    });
    const parkedSlots = this.parkedDesktopWebEntryTabIds.map((tabId: string): BrowserHostedWebHiddenSlot => {
      return {
        tabId: tabId,
        kind: 'desktop-web-entry-parked'
      };
    });
    return backgroundSlots.concat(parkedSlots);
  }

  private resolveOverflow(tabIds: string[], maxCount: number): string[] {
    return tabIds.slice(0, Math.max(0, tabIds.length - Math.max(0, maxCount)));
  }
}

interface BrowserTabsOverviewPendingDismiss {
  tabId: string;
  timer: number;
  ready: boolean;
}

/** Accepted closes belong to the session, even if a flying card is recycled or hidden. */
export class BrowserTabsOverviewDismissCoordinator {
  private pending: BrowserTabsOverviewPendingDismiss[] = [];
  private draining: boolean = false;
  private waiters: Array<() => void> = [];
  private closeTab: (tabId: string) => Promise<void>;
  private onError: (tabId: string) => void;

  constructor(closeTab: (tabId: string) => Promise<void>, onError: (tabId: string) => void) {
    this.closeTab = closeTab;
    this.onError = onError;
  }

  hasPending(): boolean {
    return this.pending.length > 0;
  }

  accept(tabId: string, delayMs: number): void {
    if (tabId.length <= 0 || this.pending.some((item) => item.tabId === tabId)) {
      return;
    }
    const entry: BrowserTabsOverviewPendingDismiss = { tabId: tabId, timer: -1, ready: false };
    this.pending.push(entry);
    entry.timer = setTimeout(() => this.complete(tabId), Math.max(0, delayMs));
  }

  complete(tabId: string): boolean {
    const entry = this.pending.find((item) => item.tabId === tabId);
    if (entry === undefined) {
      return false;
    }
    this.markReady(entry);
    void this.drain();
    return true;
  }

  /** Navigation waits for real removal, not just the disappearance of the local card. */
  flush(): Promise<void> {
    if (!this.hasPending()) {
      return Promise.resolve();
    }
    this.pending.forEach((entry) => this.markReady(entry));
    const completion = new Promise<void>((resolve) => this.waiters.push(resolve));
    void this.drain();
    return completion;
  }

  private markReady(entry: BrowserTabsOverviewPendingDismiss): void {
    if (entry.timer >= 0) {
      clearTimeout(entry.timer);
      entry.timer = -1;
    }
    entry.ready = true;
  }

  private async drain(): Promise<void> {
    if (this.draining) {
      return;
    }
    this.draining = true;
    try {
      // A foreground close can await runtime cleanup. Serial execution prevents the next close
      // from building a tab-list mutation against that same, soon-to-be-stale list.
      while (this.pending.length > 0 && this.pending[0].ready) {
        const entry = this.pending[0];
        try {
          await this.closeTab(entry.tabId);
        } catch (_error) {
          this.onError(entry.tabId);
        } finally {
          this.pending.shift();
        }
      }
    } finally {
      this.draining = false;
      if (!this.hasPending()) {
        const waiters = this.waiters;
        this.waiters = [];
        waiters.forEach((resolve) => resolve());
      }
    }
  }
}

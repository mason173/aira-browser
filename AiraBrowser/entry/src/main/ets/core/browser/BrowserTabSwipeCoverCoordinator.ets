import { BrowserTabPreviewLease, BrowserTabPreviewState } from './BrowserTabPreviewCoordinator';

export interface BrowserTabSwipeCoverHost {
  acquire: (tabId: string) => BrowserTabPreviewLease | undefined;
  afterFrame: (callback: () => void) => void;
}

interface BrowserTabSwipeCoverEntry {
  tabId: string;
  lease?: BrowserTabPreviewLease;
  released: boolean;
}

/** Holds one immutable image selection per neighbor until its Image node has left the render tree. */
export class BrowserTabSwipeCoverCoordinator {
  private readonly host: BrowserTabSwipeCoverHost;
  private readonly entries: Map<string, BrowserTabSwipeCoverEntry> = new Map();
  private readonly retiring: Set<BrowserTabSwipeCoverEntry> = new Set();
  private disposed: boolean = false;

  constructor(host: BrowserTabSwipeCoverHost) {
    this.host = host;
  }

  pin(tabId: string): void {
    if (this.disposed || this.entries.has(tabId)) {
      return;
    }
    this.entries.set(tabId, { tabId: tabId, lease: this.host.acquire(tabId), released: false });
  }

  resolve(tabId: string): BrowserTabPreviewState | undefined {
    const entry = this.entries.get(tabId);
    if (entry === undefined || this.disposed) {
      return undefined;
    }
    // Cache notifications may fill a missing cover, but must never replace or clear a displayed one.
    if (entry.lease === undefined) {
      entry.lease = this.host.acquire(tabId);
    }
    return entry.lease?.state;
  }

  unpin(tabId: string): void {
    const entry = this.entries.get(tabId);
    if (entry === undefined) {
      return;
    }
    this.entries.delete(tabId);
    this.retiring.add(entry);
    // The same snapshot serves the gallery and swipe; only this reader lease is released here.
    this.host.afterFrame(() => {
      if (!entry.released) {
        this.host.afterFrame(() => this.releaseEntry(entry));
      }
    });
  }

  /** Call when the shell's image consumers are being destroyed. Late frame callbacks are idempotent. */
  dispose(): void {
    this.disposed = true;
    this.entries.forEach((entry: BrowserTabSwipeCoverEntry): void => {
      this.releaseEntry(entry);
    });
    this.entries.clear();
    this.retiring.forEach((entry: BrowserTabSwipeCoverEntry): void => this.releaseEntry(entry));
    this.retiring.clear();
  }

  private releaseEntry(entry: BrowserTabSwipeCoverEntry): void {
    if (entry.released) {
      return;
    }
    entry.released = true;
    this.retiring.delete(entry);
    entry.lease?.release();
  }
}

export type BrowserProxyRuntimeRefreshListener = () => void;

export class BrowserProxyRuntimeRefreshCoordinator {
  private pendingGeneration: number = 0;
  private consumedGeneration: number = 0;
  private listenerSequence: number = 0;
  private listeners: Record<string, BrowserProxyRuntimeRefreshListener | undefined> = {};

  requestRefresh(): void {
    this.pendingGeneration += 1;
    this.notifyListeners();
  }

  consumePendingRefresh(): boolean {
    if (this.pendingGeneration <= this.consumedGeneration) {
      return false;
    }
    this.consumedGeneration = this.pendingGeneration;
    return true;
  }

  subscribe(listener: BrowserProxyRuntimeRefreshListener): string {
    this.listenerSequence += 1;
    const key = `browser-proxy-runtime-refresh-${this.listenerSequence}`;
    this.listeners[key] = listener;
    return key;
  }

  unsubscribe(key: string): void {
    this.listeners[key] = undefined;
  }

  private notifyListeners(): void {
    Object.keys(this.listeners).forEach((key: string) => {
      const listener = this.listeners[key];
      if (listener !== undefined) {
        listener();
      }
    });
  }
}

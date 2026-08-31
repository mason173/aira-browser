export type BrowserWindowSessionLifetimeListener = (foreground: boolean) => void;

class BrowserWindowSessionLifetimeSignal {
  private readonly foregroundByWindowId: Map<string, boolean> = new Map();
  private readonly listenersByWindowId: Map<string, BrowserWindowSessionLifetimeListener[]> = new Map();

  reconcile(windowId: string, foreground: boolean): void {
    const normalizedWindowId = windowId.trim();
    if (normalizedWindowId.length === 0) {
      return;
    }
    const previous = this.foregroundByWindowId.get(normalizedWindowId);
    this.foregroundByWindowId.set(normalizedWindowId, foreground);
    if (previous === foreground) {
      return;
    }
    const listeners = this.listenersByWindowId.get(normalizedWindowId) ?? [];
    listeners.forEach((listener: BrowserWindowSessionLifetimeListener): void => {
      listener(foreground);
    });
  }

  subscribe(windowId: string, listener: BrowserWindowSessionLifetimeListener): void {
    const normalizedWindowId = windowId.trim();
    if (normalizedWindowId.length === 0) {
      return;
    }
    const listeners = this.listenersByWindowId.get(normalizedWindowId) ?? [];
    const listenerAdded = !listeners.includes(listener);
    if (listenerAdded) {
      listeners.push(listener);
      this.listenersByWindowId.set(normalizedWindowId, listeners);
    }
    const foreground = this.foregroundByWindowId.get(normalizedWindowId);
    if (listenerAdded && foreground !== undefined) {
      listener(foreground);
    }
  }

  unsubscribe(windowId: string, listener: BrowserWindowSessionLifetimeListener): void {
    const normalizedWindowId = windowId.trim();
    const listeners = this.listenersByWindowId.get(normalizedWindowId) ?? [];
    const nextListeners = listeners.filter((candidate: BrowserWindowSessionLifetimeListener): boolean => {
      return candidate !== listener;
    });
    if (nextListeners.length === 0) {
      this.listenersByWindowId.delete(normalizedWindowId);
    } else {
      this.listenersByWindowId.set(normalizedWindowId, nextListeners);
    }
  }

  clear(windowId: string): void {
    const normalizedWindowId = windowId.trim();
    this.foregroundByWindowId.delete(normalizedWindowId);
    this.listenersByWindowId.delete(normalizedWindowId);
  }
}

export const sharedBrowserWindowSessionLifetimeSignal: BrowserWindowSessionLifetimeSignal =
  new BrowserWindowSessionLifetimeSignal();

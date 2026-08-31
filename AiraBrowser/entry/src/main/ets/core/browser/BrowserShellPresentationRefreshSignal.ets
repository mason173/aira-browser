export const BROWSER_SHELL_PRESENTATION_REVISION_STORAGE_KEY: string =
  'browser_shell_presentation_revision';

export type BrowserShellPresentationRefreshListener = () => void;

export class BrowserShellPresentationRefreshSignal {
  private static listenerSerial: number = 0;
  private static listeners: Record<string, BrowserShellPresentationRefreshListener | undefined> = {};

  static subscribe(listener: BrowserShellPresentationRefreshListener): string {
    BrowserShellPresentationRefreshSignal.listenerSerial += 1;
    const key = `browser-shell-presentation-refresh-${BrowserShellPresentationRefreshSignal.listenerSerial}`;
    BrowserShellPresentationRefreshSignal.listeners[key] = listener;
    return key;
  }

  static unsubscribe(key: string): void {
    BrowserShellPresentationRefreshSignal.listeners[key] = undefined;
  }

  static publish(): number {
    const previous = Number(AppStorage.get(BROWSER_SHELL_PRESENTATION_REVISION_STORAGE_KEY) ?? 0);
    const next = Number.isFinite(previous) ? previous + 1 : 1;
    if (AppStorage.has(BROWSER_SHELL_PRESENTATION_REVISION_STORAGE_KEY)) {
      AppStorage.set(BROWSER_SHELL_PRESENTATION_REVISION_STORAGE_KEY, next);
    } else {
      AppStorage.setOrCreate(BROWSER_SHELL_PRESENTATION_REVISION_STORAGE_KEY, next);
    }
    Object.keys(BrowserShellPresentationRefreshSignal.listeners).forEach((key: string): void => {
      try {
        BrowserShellPresentationRefreshSignal.listeners[key]?.();
      } catch (_error) {
      }
    });
    return next;
  }
}

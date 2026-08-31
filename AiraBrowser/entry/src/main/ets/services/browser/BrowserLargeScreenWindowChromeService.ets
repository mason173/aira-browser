import { window } from '@kit.ArkUI';

interface BrowserLargeScreenWindowChromeBinding {
  leaseId: string;
  mainWindow: window.Window;
  integrated: boolean;
  onIntegrationChange?: () => void;
}

/**
 * Native Window executor for the Large-Screen browser title bar.
 *
 * Presentation policy remains in BrowserLargeScreenPresentationViewModel.
 * This service only binds concrete main windows, hides/restores their system
 * title text region, and starts system window movement from a synchronous
 * ArkUI TouchType.Down callback.
 */
export class BrowserLargeScreenWindowChromeService {
  private bindings: Record<string, BrowserLargeScreenWindowChromeBinding | undefined> = {};
  private nextLeaseRevision: number = 0;

  registerWindow(windowId: string, mainWindow: window.Window, onIntegrationChange?: () => void): void {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    const existing = this.bindings[normalizedWindowId];
    if (existing !== undefined && existing.mainWindow === mainWindow) {
      existing.onIntegrationChange = onIntegrationChange;
      return;
    }
    this.bindings[normalizedWindowId] = {
      leaseId: this.createLeaseId(),
      mainWindow: mainWindow,
      integrated: false,
      onIntegrationChange: onIntegrationChange
    };
  }

  rebindWindow(previousWindowId: string, nextWindowId: string, mainWindow: window.Window): void {
    const normalizedPreviousWindowId = this.normalizeWindowId(previousWindowId);
    const normalizedNextWindowId = this.normalizeWindowId(nextWindowId);
    const binding = this.bindings[normalizedPreviousWindowId];
    if (normalizedPreviousWindowId === normalizedNextWindowId) {
      if (binding !== undefined) {
        binding.mainWindow = mainWindow;
      } else {
        this.registerWindow(normalizedNextWindowId, mainWindow);
      }
      return;
    }
    if (binding === undefined) {
      this.registerWindow(normalizedNextWindowId, mainWindow);
      return;
    }
    this.bindings = this.filterBindings(normalizedPreviousWindowId);
    binding.mainWindow = mainWindow;
    this.bindings[normalizedNextWindowId] = binding;
  }

  unregisterWindow(windowId: string): void {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    this.bindings = this.filterBindings(normalizedWindowId);
  }

  activate(windowId: string): string {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    const binding = this.bindings[normalizedWindowId];
    if (binding === undefined) {
      return '';
    }
    if (binding.integrated) {
      return binding.leaseId;
    }
    try {
      binding.mainWindow.setWindowDecorVisible(false);
      binding.integrated = true;
      this.notifyIntegrationChanged(binding);
      return binding.leaseId;
    } catch (_error) {
      binding.integrated = false;
      return '';
    }
  }

  restoreLease(leaseId: string): void {
    const binding = this.resolveBindingByLeaseId(leaseId);
    if (binding === undefined || !binding.integrated) {
      return;
    }
    try {
      binding.mainWindow.setWindowDecorVisible(true);
    } catch (_error) {
      return;
    }
    binding.integrated = false;
    this.notifyIntegrationChanged(binding);
  }

  isIntegrated(windowId: string): boolean {
    return this.bindings[this.normalizeWindowId(windowId)]?.integrated === true;
  }

  startMovingLease(leaseId: string): void {
    const binding = this.resolveBindingByLeaseId(leaseId);
    if (binding === undefined || !binding.integrated) {
      return;
    }
    void binding.mainWindow.startMoving().catch((): void => {
      // Unsupported/transient window states must not break title-bar input.
    });
  }

  private normalizeWindowId(windowId: string): string {
    const normalizedWindowId = windowId.trim();
    return normalizedWindowId.length > 0 ? normalizedWindowId : 'window-main';
  }

  private createLeaseId(): string {
    this.nextLeaseRevision += 1;
    return `large-screen-window-chrome-${this.nextLeaseRevision}`;
  }

  private filterBindings(
    excludedWindowId: string
  ): Record<string, BrowserLargeScreenWindowChromeBinding | undefined> {
    const filtered: Record<string, BrowserLargeScreenWindowChromeBinding | undefined> = {};
    Object.keys(this.bindings).forEach((windowId: string): void => {
      if (windowId !== excludedWindowId) {
        filtered[windowId] = this.bindings[windowId];
      }
    });
    return filtered;
  }

  private resolveBindingByLeaseId(leaseId: string): BrowserLargeScreenWindowChromeBinding | undefined {
    const normalizedLeaseId = leaseId.trim();
    if (normalizedLeaseId.length === 0) {
      return undefined;
    }
    const windowIds = Object.keys(this.bindings);
    for (let index = 0; index < windowIds.length; index += 1) {
      const binding = this.bindings[windowIds[index]];
      if (binding?.leaseId === normalizedLeaseId) {
        return binding;
      }
    }
    return undefined;
  }

  private notifyIntegrationChanged(binding: BrowserLargeScreenWindowChromeBinding): void {
    try {
      binding.onIntegrationChange?.();
    } catch (_error) {
    }
  }
}

export const sharedBrowserLargeScreenWindowChromeService: BrowserLargeScreenWindowChromeService =
  new BrowserLargeScreenWindowChromeService();

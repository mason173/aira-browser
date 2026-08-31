import { display, window } from '@kit.ArkUI';
import { inputDevice } from '@kit.InputKit';
import { BrowserFoldPresentationState } from '../../common/models/BrowserDevicePresentationModels';
import { BrowserFoldPresentationStateReader } from './BrowserFoldPresentationStateReader';

export const BROWSER_WINDOW_DISPLAY_VIEWPORT_WIDTH_STORAGE_KEY: string =
  'browser_window_display_viewport_width_vp';
export const BROWSER_WINDOW_DISPLAY_VIEWPORT_HEIGHT_STORAGE_KEY: string =
  'browser_window_display_viewport_height_vp';
export interface BrowserWindowDisplayViewport {
  width: number;
  height: number;
}

export class BrowserWindowDisplayViewportCoordinator {
  private listening: boolean = false;
  private foldStatusListening: boolean = false;
  private foldDisplayModeListening: boolean = false;
  private inputDeviceListening: boolean = false;
  private mainWindow?: window.Window = undefined;
  private foldState: BrowserFoldPresentationState = 'unknown';
  private readonly foldStateReader: BrowserFoldPresentationStateReader =
    new BrowserFoldPresentationStateReader();
  private presentationProfileCallback?: (mainWindow: window.Window) => void;
  private pendingSyncTimers: number[] = [];
  private displayChangeCallback: (displayId: number) => void = (_displayId: number): void => {
    this.scheduleSync();
  };
  private windowSizeChangeCallback: (size: window.Size) => void = (_size: window.Size): void => {
    this.scheduleSync();
  };
  private titleButtonRectChangeCallback: (rect: window.TitleButtonRect) => void =
    (_rect: window.TitleButtonRect): void => {
      this.scheduleSync();
    };
  private avoidAreaChangeCallback: (options: window.AvoidAreaOptions) => void =
    (_options: window.AvoidAreaOptions): void => {
      this.scheduleSync();
    };
  private freeWindowModeChangeCallback: (isFreeWindowMode: boolean) => void =
    (_isFreeWindowMode: boolean): void => {
      this.scheduleSync();
    };
  private inputDeviceChangeCallback: (listener: inputDevice.DeviceListener) => void =
    (_listener: inputDevice.DeviceListener): void => {
      this.scheduleSync();
    };
  private foldStatusChangeCallback: (status: display.FoldStatus) => void =
    (status: display.FoldStatus): void => {
      const nextState = this.foldStateReader.resolveStableState(status);
      if (nextState !== undefined) {
        this.foldState = nextState;
      }
      // A half-folded transition can change the window geometry without
      // changing the stable Shell decision. Reconcile facts in either case.
      this.scheduleSync();
    };
  private foldDisplayModeChangeCallback: (mode: display.FoldDisplayMode) => void =
    (_mode: display.FoldDisplayMode): void => {
      // Some foldable emulators publish display-mode changes before (or
      // instead of) a fold-status callback. Re-read the stable status through
      // the same owner without treating display mode as folded/expanded.
      this.scheduleSync();
    };

  bind(
    mainWindow: window.Window,
    presentationProfileCallback?: (mainWindow: window.Window) => void
  ): void {
    this.unbind();
    this.mainWindow = mainWindow;
    this.presentationProfileCallback = presentationProfileCallback;
    this.foldState = this.readInitialFoldState();
    this.syncStorage();
    try {
      display.on('change', this.displayChangeCallback);
      this.listening = true;
    } catch (_error) {
      this.listening = false;
    }
    try {
      display.on('foldStatusChange', this.foldStatusChangeCallback);
      this.foldStatusListening = true;
    } catch (_error) {
      this.foldStatusListening = false;
    }
    try {
      display.on('foldDisplayModeChange', this.foldDisplayModeChangeCallback);
      this.foldDisplayModeListening = true;
    } catch (_error) {
      this.foldDisplayModeListening = false;
    }
    try {
      mainWindow.on('windowSizeChange', this.windowSizeChangeCallback);
    } catch (_error) {
    }
    try {
      mainWindow.on('windowTitleButtonRectChange', this.titleButtonRectChangeCallback);
    } catch (_error) {
    }
    try {
      mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
    } catch (_error) {
    }
    try {
      mainWindow.on('freeWindowModeChange', this.freeWindowModeChangeCallback);
    } catch (_error) {
    }
    try {
      inputDevice.on('change', this.inputDeviceChangeCallback);
      this.inputDeviceListening = true;
    } catch (_error) {
      this.inputDeviceListening = false;
    }
  }

  unbind(): void {
    this.cancelPendingSync();
    if (this.listening) {
      try {
        display.off('change', this.displayChangeCallback);
      } catch (_error) {
      }
    }
    if (this.foldStatusListening) {
      try {
        display.off('foldStatusChange', this.foldStatusChangeCallback);
      } catch (_error) {
      }
    }
    if (this.foldDisplayModeListening) {
      try {
        display.off('foldDisplayModeChange', this.foldDisplayModeChangeCallback);
      } catch (_error) {
      }
    }
    if (this.mainWindow !== undefined) {
      try {
        this.mainWindow.off('windowSizeChange', this.windowSizeChangeCallback);
      } catch (_error) {
      }
      try {
        this.mainWindow.off('windowTitleButtonRectChange', this.titleButtonRectChangeCallback);
      } catch (_error) {
      }
      try {
        this.mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      } catch (_error) {
      }
      try {
        this.mainWindow.off('freeWindowModeChange', this.freeWindowModeChangeCallback);
      } catch (_error) {
      }
    }
    if (this.inputDeviceListening) {
      try {
        inputDevice.off('change', this.inputDeviceChangeCallback);
      } catch (_error) {
      }
    }
    this.listening = false;
    this.foldStatusListening = false;
    this.foldDisplayModeListening = false;
    this.inputDeviceListening = false;
    this.mainWindow = undefined;
    this.presentationProfileCallback = undefined;
    this.foldState = 'unknown';
  }

  getFoldPresentationState(): BrowserFoldPresentationState {
    return this.foldState;
  }

  scheduleSync(): void {
    this.cancelPendingSync();
    const delaysMs: number[] = [0, 40, 120];
    for (let index = 0; index < delaysMs.length; index += 1) {
      const timer = setTimeout(() => {
        this.syncStorage();
      }, delaysMs[index]);
      this.pendingSyncTimers.push(timer);
    }
  }

  syncStorage(): BrowserWindowDisplayViewport {
    // Refresh from the platform on every existing viewport sync so a
    // foreground/window-size pass also repairs a missed fold callback.
    this.refreshFoldState();
    const viewport = this.readDisplayViewport();
    this.writeNumber(BROWSER_WINDOW_DISPLAY_VIEWPORT_WIDTH_STORAGE_KEY, viewport.width);
    this.writeNumber(BROWSER_WINDOW_DISPLAY_VIEWPORT_HEIGHT_STORAGE_KEY, viewport.height);
    this.publishPresentationProfileInput();
    return viewport;
  }

  private publishPresentationProfileInput(): void {
    const callback = this.presentationProfileCallback;
    const mainWindow = this.mainWindow;
    if (callback === undefined || mainWindow === undefined) {
      return;
    }
    try {
      callback(mainWindow);
    } catch (_error) {
      // A transient WindowStage read failure must not interrupt viewport sync.
    }
  }

  private readDisplayViewport(): BrowserWindowDisplayViewport {
    try {
      const currentDisplay = display.getDefaultDisplaySync();
      const densityPixels = this.normalizePositiveNumber(currentDisplay.densityPixels, 1);
      return {
        width: Math.max(1, Math.round(this.normalizePositiveNumber(currentDisplay.width, 1) / densityPixels)),
        height: Math.max(1, Math.round(this.normalizePositiveNumber(currentDisplay.height, 1) / densityPixels))
      };
    } catch (_error) {
      return { width: 0, height: 0 };
    }
  }

  private readInitialFoldState(): BrowserFoldPresentationState {
    try {
      return this.foldStateReader.read().state;
    } catch (_error) {
      return 'unknown';
    }
  }

  private refreshFoldState(): void {
    try {
      const facts = this.foldStateReader.read();
      if (!facts.capabilityConfirmed || facts.state === 'unknown') {
        return;
      }
      this.foldState = facts.state;
    } catch (_error) {
    }
  }

  private writeNumber(key: string, value: number): void {
    const normalizedValue = Math.max(0, Math.round(value));
    if (AppStorage.has(key)) {
      AppStorage.set(key, normalizedValue);
      return;
    }
    AppStorage.setOrCreate(key, normalizedValue);
  }

  private normalizePositiveNumber(value: number, fallback: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return fallback;
    }
    return value;
  }

  private cancelPendingSync(): void {
    for (let index = 0; index < this.pendingSyncTimers.length; index += 1) {
      clearTimeout(this.pendingSyncTimers[index]);
    }
    this.pendingSyncTimers = [];
  }
}

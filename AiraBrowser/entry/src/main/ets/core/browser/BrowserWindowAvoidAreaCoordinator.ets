import { display, window } from '@kit.ArkUI';

function pxToVp(px: number): number {
  try {
    return Math.max(0, Math.ceil(px / display.getDefaultDisplaySync().densityPixels));
  } catch (_error) {
    return Math.max(0, Math.ceil(px));
  }
}

function resolveWindowTopAvoidAreaGeometryInsetVp(
  mainWindow: window.Window,
  type: window.AvoidAreaType
): number {
  try {
    return pxToVp(mainWindow.getWindowAvoidArea(type).topRect.height);
  } catch (_error) {
    return 0;
  }
}

export function resolveWindowTopAvoidAreaInsetVp(
  mainWindow: window.Window,
  type: window.AvoidAreaType
): number {
  try {
    const area = mainWindow.getWindowAvoidArea(type);
    if (!area.visible) {
      return 0;
    }
    return pxToVp(area.topRect.top + area.topRect.height);
  } catch (_error) {
    return 0;
  }
}

export function resolveWindowTopSafeInsetVp(mainWindow: window.Window): number {
  return Math.max(
    resolveWindowTopAvoidAreaInsetVp(mainWindow, window.AvoidAreaType.TYPE_SYSTEM),
    resolveWindowTopAvoidAreaInsetVp(mainWindow, window.AvoidAreaType.TYPE_CUTOUT)
  );
}

export const BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY: string = 'browser_window_safe_top_inset_vp';
export const BROWSER_WINDOW_SAFE_SYSTEM_TOP_INSET_STORAGE_KEY: string = 'browser_window_safe_system_top_inset_vp';
export const BROWSER_WINDOW_SAFE_CUTOUT_TOP_INSET_STORAGE_KEY: string = 'browser_window_safe_cutout_top_inset_vp';
export const BROWSER_WINDOW_SAFE_BOTTOM_INSET_STORAGE_KEY: string = 'browser_window_safe_bottom_inset_vp';
export const BROWSER_WINDOW_SAFE_LEFT_INSET_STORAGE_KEY: string = 'browser_window_safe_left_inset_vp';
export const BROWSER_WINDOW_SAFE_RIGHT_INSET_STORAGE_KEY: string = 'browser_window_safe_right_inset_vp';
export const BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY: string = 'browser_window_keyboard_inset_vp';

export interface BrowserWindowAvoidAreaInsets {
  topInsetVp: number;
  bottomInsetVp: number;
  leftInsetVp: number;
  rightInsetVp: number;
}

export interface BrowserWindowWebTopGeometryInsets {
  systemTopInsetVp: number;
  cutoutTopInsetVp: number;
}

export interface BrowserWindowAvoidAreaSyncResult {
  previousInsets: BrowserWindowAvoidAreaInsets;
  nextInsets: BrowserWindowAvoidAreaInsets;
  changed: boolean;
}

export interface BrowserWindowSafeInsetSettleSyncInput {
  webPageVisible: boolean;
  tabsSheetVisible: boolean;
  fullScreenModeEnabled: boolean;
  webStatusBarVisible: boolean;
}

export interface BrowserWindowSafeInsetSettleSyncHost {
  resolveInput: () => BrowserWindowSafeInsetSettleSyncInput;
  refreshSystemBars: (source: string) => Promise<void>;
  runSync: (source: string) => void;
  logSync: (source: string) => void;
}

export interface BrowserWindowKeyboardInsetSyncHost {
  isKeyboardInsetSyncActive: () => boolean;
  shouldConfirmKeyboardHidden?: () => boolean;
  resolveWindow: () => Promise<window.Window>;
  resolveStorage: () => LocalStorage | undefined;
  applyKeyboardInset: (insetVp: number) => void;
  handleKeyboardHidden: () => void;
}

export interface BrowserWindowFullscreenInsetRestoreHost {
  resolveWindow: () => Promise<window.Window>;
  resolveStorage: () => LocalStorage | undefined;
  applyRestoredInsets: (insets: BrowserWindowAvoidAreaInsets) => void;
}

interface BrowserWindowKeyboardInsetSessionResolution {
  insetVp: number;
  shouldApplyInset: boolean;
  keyboardHiddenConfirmed: boolean;
}

const BROWSER_WINDOW_FULLSCREEN_INSET_RESTORE_DELAY_MS: number = 420;
const BROWSER_WINDOW_KEYBOARD_INSET_SYNC_DELAYS_MS: number[] = [0, 40, 80, 140, 240, 400, 650, 1000, 1400];
const BROWSER_WINDOW_KEYBOARD_INSET_MONITOR_INTERVAL_MS: number = 220;
const BROWSER_WINDOW_KEYBOARD_INSET_HIDDEN_CONFIRM_READS: number = 2;

export class BrowserWindowAvoidAreaCoordinator {
  private safeInsetSettleSyncTimer: number = -1;
  private safeInsetSettleSyncGeneration: number = 0;
  private fullscreenInsetRestoreTimer: number = -1;
  private fullscreenInsetRestoreGeneration: number = 0;
  private fullscreenRestoreInsets?: BrowserWindowAvoidAreaInsets = undefined;
  private keyboardInsetSyncTimers: number[] = [];
  private keyboardInsetSyncGeneration: number = 0;
  private keyboardInsetMonitorTimer: number = -1;
  private stableKeyboardInsetVp: number = 0;
  private keyboardInsetZeroReadCount: number = 0;
  private keyboardInsetWasVisible: boolean = false;
  private keyboardInsetSessionActive: boolean = false;

  syncStorage(mainWindow: window.Window, storage: LocalStorage | undefined): BrowserWindowAvoidAreaInsets {
    const webTopGeometryInsets = this.readWebTopGeometryInsets(mainWindow);
    const nextInsets = this.resolveInsets(mainWindow, webTopGeometryInsets);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY, nextInsets.topInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_SYSTEM_TOP_INSET_STORAGE_KEY,
      webTopGeometryInsets.systemTopInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_CUTOUT_TOP_INSET_STORAGE_KEY,
      webTopGeometryInsets.cutoutTopInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_BOTTOM_INSET_STORAGE_KEY, nextInsets.bottomInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_LEFT_INSET_STORAGE_KEY, nextInsets.leftInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_RIGHT_INSET_STORAGE_KEY, nextInsets.rightInsetVp);
    this.writeStableKeyboardInset(storage, this.resolveKeyboardInsetVp(mainWindow));
    return nextInsets;
  }

  syncKeyboardInset(mainWindow: window.Window, storage: LocalStorage | undefined): number {
    const keyboardInsetVp = this.resolveStableKeyboardInsetForStorage(this.resolveKeyboardInsetVp(mainWindow));
    this.writeInset(storage, BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY, keyboardInsetVp);
    return keyboardInsetVp;
  }

  syncStorageWithResult(mainWindow: window.Window, storage: LocalStorage | undefined): BrowserWindowAvoidAreaSyncResult {
    const previousInsets = this.readStorage(storage);
    const nextInsets = this.syncStorage(mainWindow, storage);
    return {
      previousInsets: previousInsets,
      nextInsets: nextInsets,
      changed: !this.areInsetsEqual(previousInsets, nextInsets)
    };
  }

  syncStorageWithMinimum(
    mainWindow: window.Window,
    storage: LocalStorage | undefined,
    minimumInsets: BrowserWindowAvoidAreaInsets
  ): BrowserWindowAvoidAreaInsets {
    const webTopGeometryInsets = this.readWebTopGeometryInsets(mainWindow);
    const currentInsets = this.resolveInsets(mainWindow, webTopGeometryInsets);
    const nextInsets: BrowserWindowAvoidAreaInsets = {
      topInsetVp: Math.max(currentInsets.topInsetVp, minimumInsets.topInsetVp),
      bottomInsetVp: Math.max(currentInsets.bottomInsetVp, minimumInsets.bottomInsetVp),
      leftInsetVp: Math.max(currentInsets.leftInsetVp, minimumInsets.leftInsetVp),
      rightInsetVp: Math.max(currentInsets.rightInsetVp, minimumInsets.rightInsetVp)
    };
    this.writeInset(storage, BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY, nextInsets.topInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_SYSTEM_TOP_INSET_STORAGE_KEY,
      Math.max(webTopGeometryInsets.systemTopInsetVp, minimumInsets.topInsetVp));
    this.writeInset(storage, BROWSER_WINDOW_SAFE_CUTOUT_TOP_INSET_STORAGE_KEY,
      webTopGeometryInsets.cutoutTopInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_BOTTOM_INSET_STORAGE_KEY, nextInsets.bottomInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_LEFT_INSET_STORAGE_KEY, nextInsets.leftInsetVp);
    this.writeInset(storage, BROWSER_WINDOW_SAFE_RIGHT_INSET_STORAGE_KEY, nextInsets.rightInsetVp);
    return nextInsets;
  }

  bind(mainWindow: window.Window, storage: LocalStorage | undefined): void {
    if (storage === undefined) {
      return;
    }
    try {
      mainWindow.on('avoidAreaChange', (options: window.AvoidAreaOptions) => {
        this.syncStorage(mainWindow, storage);
        if (options.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.writeStableKeyboardInset(storage, this.resolveKeyboardInsetVpFromArea(options.area));
        }
      });
    } catch (_error) {
    }
  }

  scheduleSafeInsetSettleSync(
    source: string,
    host: BrowserWindowSafeInsetSettleSyncHost,
    delayMs: number,
    systemBarRefreshSettleDelayMs: number
  ): void {
    this.cancelSafeInsetSettleSync();
    if (!this.shouldRunSafeInsetSettleSync(host.resolveInput())) {
      return;
    }
    const generation = ++this.safeInsetSettleSyncGeneration;
    this.safeInsetSettleSyncTimer = setTimeout(() => {
      this.safeInsetSettleSyncTimer = -1;
      if (generation !== this.safeInsetSettleSyncGeneration ||
        !this.shouldRunSafeInsetSettleSync(host.resolveInput())) {
        return;
      }
      host.logSync(source);
      host.refreshSystemBars(source)
        .catch((_error: Error) => {
        })
        .then(() => {
          if (generation !== this.safeInsetSettleSyncGeneration ||
            !this.shouldRunSafeInsetSettleSync(host.resolveInput())) {
            return;
          }
          this.safeInsetSettleSyncTimer = setTimeout(() => {
            this.safeInsetSettleSyncTimer = -1;
            if (generation !== this.safeInsetSettleSyncGeneration ||
              !this.shouldRunSafeInsetSettleSync(host.resolveInput())) {
              return;
            }
            host.runSync(source);
          }, Math.max(0, Math.ceil(systemBarRefreshSettleDelayMs)));
        });
    }, Math.max(0, Math.ceil(delayMs)));
  }

  cancelSafeInsetSettleSync(): void {
    this.safeInsetSettleSyncGeneration += 1;
    if (this.safeInsetSettleSyncTimer >= 0) {
      clearTimeout(this.safeInsetSettleSyncTimer);
      this.safeInsetSettleSyncTimer = -1;
    }
  }

  captureFullscreenRestoreInsets(storage: LocalStorage | undefined): void {
    this.fullscreenRestoreInsets = this.readStorage(storage);
  }

  scheduleFullscreenInsetRestore(host: BrowserWindowFullscreenInsetRestoreHost): void {
    this.cancelFullscreenInsetRestore();
    const restoreInsets = this.fullscreenRestoreInsets;
    if (restoreInsets === undefined) {
      return;
    }
    const generation = ++this.fullscreenInsetRestoreGeneration;
    this.fullscreenInsetRestoreTimer = setTimeout(() => {
      if (generation !== this.fullscreenInsetRestoreGeneration) {
        return;
      }
      this.fullscreenInsetRestoreTimer = -1;
      host.resolveWindow()
        .then((mainWindow: window.Window) => {
          const restoredInsets = this.syncStorageWithMinimum(
            mainWindow,
            host.resolveStorage(),
            restoreInsets
          );
          host.applyRestoredInsets(restoredInsets);
          this.fullscreenRestoreInsets = undefined;
        })
        .catch((_error: Error) => {
        });
    }, BROWSER_WINDOW_FULLSCREEN_INSET_RESTORE_DELAY_MS);
  }

  cancelFullscreenInsetRestore(): void {
    this.fullscreenInsetRestoreGeneration += 1;
    if (this.fullscreenInsetRestoreTimer >= 0) {
      clearTimeout(this.fullscreenInsetRestoreTimer);
      this.fullscreenInsetRestoreTimer = -1;
    }
  }

  scheduleKeyboardInsetSync(host: BrowserWindowKeyboardInsetSyncHost): void {
    this.cancelKeyboardInsetSync();
    this.stableKeyboardInsetVp = 0;
    this.keyboardInsetZeroReadCount = 0;
    this.keyboardInsetWasVisible = false;
    this.keyboardInsetSessionActive = true;
    const generation = ++this.keyboardInsetSyncGeneration;
    for (let index = 0; index < BROWSER_WINDOW_KEYBOARD_INSET_SYNC_DELAYS_MS.length; index += 1) {
      const delayMs = BROWSER_WINDOW_KEYBOARD_INSET_SYNC_DELAYS_MS[index];
      const timer = setTimeout(() => {
        this.removeKeyboardInsetSyncTimer(timer);
        this.runKeyboardInsetSync(generation, host, false);
      }, delayMs);
      this.keyboardInsetSyncTimers.push(timer);
    }
    const lastWarmupDelayMs =
      BROWSER_WINDOW_KEYBOARD_INSET_SYNC_DELAYS_MS[BROWSER_WINDOW_KEYBOARD_INSET_SYNC_DELAYS_MS.length - 1];
    this.scheduleKeyboardInsetMonitor(
      generation,
      host,
      lastWarmupDelayMs + BROWSER_WINDOW_KEYBOARD_INSET_MONITOR_INTERVAL_MS
    );
  }

  cancelKeyboardInsetSync(): void {
    this.keyboardInsetSyncGeneration += 1;
    for (let index = 0; index < this.keyboardInsetSyncTimers.length; index += 1) {
      clearTimeout(this.keyboardInsetSyncTimers[index]);
    }
    this.keyboardInsetSyncTimers = [];
    if (this.keyboardInsetMonitorTimer >= 0) {
      clearTimeout(this.keyboardInsetMonitorTimer);
      this.keyboardInsetMonitorTimer = -1;
    }
    this.stableKeyboardInsetVp = 0;
    this.keyboardInsetZeroReadCount = 0;
    this.keyboardInsetWasVisible = false;
    this.keyboardInsetSessionActive = false;
  }

  readStorage(storage: LocalStorage | undefined): BrowserWindowAvoidAreaInsets {
    return {
      topInsetVp: this.readInset(storage, BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY),
      bottomInsetVp: this.readInset(storage, BROWSER_WINDOW_SAFE_BOTTOM_INSET_STORAGE_KEY),
      leftInsetVp: this.readInset(storage, BROWSER_WINDOW_SAFE_LEFT_INSET_STORAGE_KEY),
      rightInsetVp: this.readInset(storage, BROWSER_WINDOW_SAFE_RIGHT_INSET_STORAGE_KEY)
    };
  }

  readStoredWebTopGeometryInsets(storage: LocalStorage | undefined): BrowserWindowWebTopGeometryInsets {
    const fallbackTopInset = this.readInset(storage, BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY);
    return {
      systemTopInsetVp: this.readInsetWithFallback(
        storage,
        BROWSER_WINDOW_SAFE_SYSTEM_TOP_INSET_STORAGE_KEY,
        fallbackTopInset
      ),
      cutoutTopInsetVp: this.readInset(storage, BROWSER_WINDOW_SAFE_CUTOUT_TOP_INSET_STORAGE_KEY)
    };
  }

  readKeyboardInset(storage: LocalStorage | undefined): number {
    return this.readInset(storage, BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY);
  }

  readWebTopGeometryInsets(mainWindow: window.Window): BrowserWindowWebTopGeometryInsets {
    return {
      systemTopInsetVp: this.resolveTopInsetVp(mainWindow, window.AvoidAreaType.TYPE_SYSTEM),
      cutoutTopInsetVp: this.resolveTopInsetVp(mainWindow, window.AvoidAreaType.TYPE_CUTOUT)
    };
  }

  private resolveInsets(
    mainWindow: window.Window,
    webTopGeometryInsets: BrowserWindowWebTopGeometryInsets
  ): BrowserWindowAvoidAreaInsets {
    return {
      topInsetVp: Math.max(
        webTopGeometryInsets.systemTopInsetVp,
        webTopGeometryInsets.cutoutTopInsetVp
      ),
      bottomInsetVp: Math.max(
        this.resolveBottomInsetVp(mainWindow, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR),
        this.resolveBottomInsetVp(mainWindow, window.AvoidAreaType.TYPE_SYSTEM)
      ),
      leftInsetVp: Math.max(
        this.resolveLeftInsetVp(mainWindow, window.AvoidAreaType.TYPE_SYSTEM),
        this.resolveLeftInsetVp(mainWindow, window.AvoidAreaType.TYPE_CUTOUT),
        this.resolveLeftInsetVp(mainWindow, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      ),
      rightInsetVp: Math.max(
        this.resolveRightInsetVp(mainWindow, window.AvoidAreaType.TYPE_SYSTEM),
        this.resolveRightInsetVp(mainWindow, window.AvoidAreaType.TYPE_CUTOUT),
        this.resolveRightInsetVp(mainWindow, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      )
    };
  }

  private resolveTopInsetVp(mainWindow: window.Window, type: window.AvoidAreaType): number {
    return resolveWindowTopAvoidAreaGeometryInsetVp(mainWindow, type);
  }

  private resolveBottomInsetVp(mainWindow: window.Window, type: window.AvoidAreaType): number {
    try {
      return this.pxToVp(mainWindow.getWindowAvoidArea(type).bottomRect.height);
    } catch (_error) {
      return 0;
    }
  }

  private resolveLeftInsetVp(mainWindow: window.Window, type: window.AvoidAreaType): number {
    try {
      return this.pxToVp(mainWindow.getWindowAvoidArea(type).leftRect.width);
    } catch (_error) {
      return 0;
    }
  }

  private resolveRightInsetVp(mainWindow: window.Window, type: window.AvoidAreaType): number {
    try {
      return this.pxToVp(mainWindow.getWindowAvoidArea(type).rightRect.width);
    } catch (_error) {
      return 0;
    }
  }

  private resolveKeyboardInsetVp(mainWindow: window.Window): number {
    try {
      return this.resolveKeyboardInsetVpFromArea(mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD));
    } catch (_error) {
      return 0;
    }
  }

  private resolveKeyboardInsetVpFromArea(area: window.AvoidArea): number {
    if (!area.visible) {
      return 0;
    }
    return Math.max(
      this.pxToVp(area.bottomRect.height),
      this.pxToVp(area.topRect.height),
      this.pxToVp(area.leftRect.width),
      this.pxToVp(area.rightRect.width)
    );
  }

  private writeStableKeyboardInset(storage: LocalStorage | undefined, rawInsetVp: number): void {
    this.writeInset(
      storage,
      BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY,
      this.resolveStableKeyboardInsetForStorage(rawInsetVp)
    );
  }

  private resolveStableKeyboardInsetForStorage(rawInsetVp: number): number {
    const keyboardInsetVp = Math.max(0, Math.ceil(rawInsetVp));
    if (keyboardInsetVp > 0) {
      return keyboardInsetVp;
    }
    if (this.keyboardInsetSessionActive && this.stableKeyboardInsetVp > 0) {
      return this.stableKeyboardInsetVp;
    }
    return 0;
  }

  private runKeyboardInsetSync(
    generation: number,
    host: BrowserWindowKeyboardInsetSyncHost,
    shouldContinueMonitoring: boolean
  ): void {
    if (generation !== this.keyboardInsetSyncGeneration || !this.shouldRunKeyboardInsetSync(host)) {
      return;
    }
    host.resolveWindow()
      .then((mainWindow: window.Window) => {
        if (generation !== this.keyboardInsetSyncGeneration || !this.shouldRunKeyboardInsetSync(host)) {
          return;
        }
        const storage = host.resolveStorage();
        const resolution = this.resolveKeyboardInsetForSession(this.resolveKeyboardInsetVp(mainWindow));
        if (resolution.keyboardHiddenConfirmed) {
          if (!this.shouldConfirmKeyboardHidden(host)) {
            this.rejectKeyboardHiddenCandidate();
            this.writeStableKeyboardInset(storage, this.stableKeyboardInsetVp);
            this.scheduleNextKeyboardInsetMonitor(generation, host, true);
            return;
          }
          this.acceptKeyboardHidden();
          this.writeInset(storage, BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY, resolution.insetVp);
          if (resolution.shouldApplyInset) {
            host.applyKeyboardInset(resolution.insetVp);
          }
          host.handleKeyboardHidden();
          return;
        }
        this.writeInset(storage, BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY, resolution.insetVp);
        if (resolution.shouldApplyInset) {
          host.applyKeyboardInset(resolution.insetVp);
        }
        this.scheduleNextKeyboardInsetMonitor(generation, host, shouldContinueMonitoring);
      })
      .catch((_error: Error) => {
        if (generation !== this.keyboardInsetSyncGeneration || !this.shouldRunKeyboardInsetSync(host)) {
          return;
        }
        const storage = host.resolveStorage();
        const resolution = this.resolveKeyboardInsetForSession(this.readKeyboardInset(storage));
        if (resolution.keyboardHiddenConfirmed) {
          if (!this.shouldConfirmKeyboardHidden(host)) {
            this.rejectKeyboardHiddenCandidate();
            this.writeStableKeyboardInset(storage, this.stableKeyboardInsetVp);
            this.scheduleNextKeyboardInsetMonitor(generation, host, true);
            return;
          }
          this.acceptKeyboardHidden();
          this.writeInset(storage, BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY, resolution.insetVp);
          if (resolution.shouldApplyInset) {
            host.applyKeyboardInset(resolution.insetVp);
          }
          host.handleKeyboardHidden();
          return;
        }
        this.writeInset(storage, BROWSER_WINDOW_KEYBOARD_INSET_STORAGE_KEY, resolution.insetVp);
        if (resolution.shouldApplyInset) {
          host.applyKeyboardInset(resolution.insetVp);
        }
        this.scheduleNextKeyboardInsetMonitor(generation, host, shouldContinueMonitoring);
      });
  }

  private resolveKeyboardInsetForSession(rawInsetVp: number): BrowserWindowKeyboardInsetSessionResolution {
    const keyboardInsetVp = Math.max(0, Math.ceil(rawInsetVp));
    if (keyboardInsetVp > 0) {
      this.keyboardInsetZeroReadCount = 0;
      this.stableKeyboardInsetVp = keyboardInsetVp;
      this.keyboardInsetWasVisible = true;
      return {
        insetVp: keyboardInsetVp,
        shouldApplyInset: true,
        keyboardHiddenConfirmed: false
      };
    }
    if (this.stableKeyboardInsetVp <= 0) {
      this.keyboardInsetZeroReadCount = 0;
      return {
        insetVp: 0,
        shouldApplyInset: true,
        keyboardHiddenConfirmed: false
      };
    }
    this.keyboardInsetZeroReadCount += 1;
    if (this.keyboardInsetZeroReadCount < BROWSER_WINDOW_KEYBOARD_INSET_HIDDEN_CONFIRM_READS) {
      return {
        insetVp: this.stableKeyboardInsetVp,
        shouldApplyInset: false,
        keyboardHiddenConfirmed: false
      };
    }
    const keyboardHiddenConfirmed = this.keyboardInsetWasVisible;
    return {
      insetVp: 0,
      shouldApplyInset: true,
      keyboardHiddenConfirmed: keyboardHiddenConfirmed
    };
  }

  private shouldConfirmKeyboardHidden(host: BrowserWindowKeyboardInsetSyncHost): boolean {
    if (host.shouldConfirmKeyboardHidden === undefined) {
      return true;
    }
    return host.shouldConfirmKeyboardHidden();
  }

  private acceptKeyboardHidden(): void {
    this.stableKeyboardInsetVp = 0;
    this.keyboardInsetZeroReadCount = 0;
    this.keyboardInsetWasVisible = false;
    this.keyboardInsetSessionActive = false;
  }

  private rejectKeyboardHiddenCandidate(): void {
    this.keyboardInsetZeroReadCount = 0;
  }

  private scheduleKeyboardInsetMonitor(
    generation: number,
    host: BrowserWindowKeyboardInsetSyncHost,
    delayMs: number
  ): void {
    if (this.keyboardInsetMonitorTimer >= 0) {
      clearTimeout(this.keyboardInsetMonitorTimer);
      this.keyboardInsetMonitorTimer = -1;
    }
    this.keyboardInsetMonitorTimer = setTimeout(() => {
      this.keyboardInsetMonitorTimer = -1;
      this.runKeyboardInsetSync(generation, host, true);
    }, Math.max(0, Math.ceil(delayMs)));
  }

  private scheduleNextKeyboardInsetMonitor(
    generation: number,
    host: BrowserWindowKeyboardInsetSyncHost,
    shouldContinueMonitoring: boolean
  ): void {
    if (!shouldContinueMonitoring ||
      generation !== this.keyboardInsetSyncGeneration ||
      !this.shouldRunKeyboardInsetSync(host)) {
      return;
    }
    this.scheduleKeyboardInsetMonitor(generation, host, BROWSER_WINDOW_KEYBOARD_INSET_MONITOR_INTERVAL_MS);
  }

  private shouldRunKeyboardInsetSync(host: BrowserWindowKeyboardInsetSyncHost): boolean {
    return host.isKeyboardInsetSyncActive() || this.keyboardInsetWasVisible || this.stableKeyboardInsetVp > 0;
  }

  private removeKeyboardInsetSyncTimer(timer: number): void {
    const nextTimers: number[] = [];
    for (let index = 0; index < this.keyboardInsetSyncTimers.length; index += 1) {
      if (this.keyboardInsetSyncTimers[index] !== timer) {
        nextTimers.push(this.keyboardInsetSyncTimers[index]);
      }
    }
    this.keyboardInsetSyncTimers = nextTimers;
  }

  private pxToVp(px: number): number {
    try {
      return Math.max(0, Math.ceil(px / display.getDefaultDisplaySync().densityPixels));
    } catch (_error) {
      return Math.max(0, Math.ceil(px));
    }
  }

  private writeInset(storage: LocalStorage | undefined, key: string, value: number): void {
    if (storage === undefined) {
      return;
    }
    const normalizedValue = Math.max(0, Math.ceil(value));
    if (storage.has(key)) {
      storage.set(key, normalizedValue);
      return;
    }
    storage.setOrCreate(key, normalizedValue);
  }

  private readInset(storage: LocalStorage | undefined, key: string): number {
    if (storage === undefined) {
      return 0;
    }
    const rawValue = storage.get<number>(key);
    if (rawValue === undefined) {
      return 0;
    }
    return Math.max(0, Math.ceil(Number(rawValue)));
  }

  private readInsetWithFallback(storage: LocalStorage | undefined, key: string, fallbackValue: number): number {
    if (storage === undefined) {
      return Math.max(0, Math.ceil(fallbackValue));
    }
    const rawValue = storage.get<number>(key);
    if (rawValue === undefined) {
      return Math.max(0, Math.ceil(fallbackValue));
    }
    return Math.max(0, Math.ceil(Number(rawValue)));
  }

  private shouldRunSafeInsetSettleSync(input: BrowserWindowSafeInsetSettleSyncInput): boolean {
    return input.webPageVisible &&
      !input.tabsSheetVisible &&
      !input.fullScreenModeEnabled &&
      input.webStatusBarVisible;
  }

  private areInsetsEqual(first: BrowserWindowAvoidAreaInsets, second: BrowserWindowAvoidAreaInsets): boolean {
    return first.topInsetVp === second.topInsetVp &&
      first.bottomInsetVp === second.bottomInsetVp &&
      first.leftInsetVp === second.leftInsetVp &&
      first.rightInsetVp === second.rightInsetVp;
  }
}

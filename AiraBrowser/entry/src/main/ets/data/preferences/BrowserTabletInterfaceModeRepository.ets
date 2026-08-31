import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { BrowserTabletInterfaceMode } from '../../common/models/BrowserDevicePresentationModels';

const PREFERENCES_NAME: string = 'aira_browser_device_presentation';
const TABLET_INTERFACE_MODE_KEY: string = 'tablet_interface_mode';

export type BrowserTabletInterfaceModeChangeListener = (mode: BrowserTabletInterfaceMode) => void;

export class BrowserTabletInterfaceModeRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private mode: BrowserTabletInterfaceMode = 'auto';
  private listenerSerial: number = 0;
  private listeners: Record<string, BrowserTabletInterfaceModeChangeListener | undefined> = {};

  async initialize(): Promise<BrowserTabletInterfaceMode> {
    const store = await this.getStore();
    this.mode = this.normalizeMode(String(store.getSync(TABLET_INTERFACE_MODE_KEY, 'auto')));
    return this.mode;
  }

  getMode(): BrowserTabletInterfaceMode {
    return this.mode;
  }

  async setMode(mode: BrowserTabletInterfaceMode): Promise<BrowserTabletInterfaceMode> {
    const normalizedMode = this.normalizeMode(mode);
    if (normalizedMode === this.mode) {
      return this.mode;
    }
    const store = await this.getStore();
    store.putSync(TABLET_INTERFACE_MODE_KEY, normalizedMode);
    await store.flush();
    this.mode = normalizedMode;
    this.publish();
    return this.mode;
  }

  subscribe(listener: BrowserTabletInterfaceModeChangeListener): string {
    this.listenerSerial += 1;
    const key = `tablet-interface-mode-${this.listenerSerial}`;
    this.listeners[key] = listener;
    return key;
  }

  unsubscribe(key: string): void {
    this.listeners[key] = undefined;
  }

  private publish(): void {
    Object.keys(this.listeners).forEach((key: string): void => {
      this.listeners[key]?.(this.mode);
    });
  }

  private normalizeMode(value: string): BrowserTabletInterfaceMode {
    if (value === 'touch' || value === 'desktop') {
      return value;
    }
    return 'auto';
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences): preferences.Preferences => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

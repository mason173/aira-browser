import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { BrowserWebLayerGeometrySnapshot } from '../../core/browser/BrowserWebLayerGeometryCache';

const WEB_LAYER_GEOMETRY_PREFERENCES_NAME: string = 'aira_browser_web_layer_geometry';
const WEB_LAYER_GEOMETRY_KEY: string = 'last_web_layer_geometry';

export class BrowserWebLayerGeometryStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async readSnapshot(): Promise<BrowserWebLayerGeometrySnapshot | undefined> {
    const store = await this.getStore();
    const rawValue = store.getSync(WEB_LAYER_GEOMETRY_KEY, '');
    return this.parseSnapshot(String(rawValue));
  }

  async writeSnapshot(snapshot: BrowserWebLayerGeometrySnapshot): Promise<void> {
    const store = await this.getStore();
    store.putSync(WEB_LAYER_GEOMETRY_KEY, JSON.stringify(snapshot));
    store.flushSync();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        WEB_LAYER_GEOMETRY_PREFERENCES_NAME
      ).then((store: preferences.Preferences) => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private parseSnapshot(rawValue: string): BrowserWebLayerGeometrySnapshot | undefined {
    if (rawValue.trim().length <= 0) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(rawValue) as BrowserWebLayerGeometrySnapshot;
      if (!this.isFiniteNumber(parsed.rootWidth) || !this.isFiniteNumber(parsed.rootHeight) ||
        !this.isFiniteNumber(parsed.webLeft) || !this.isFiniteNumber(parsed.webTop) ||
        !this.isFiniteNumber(parsed.webWidth) || !this.isFiniteNumber(parsed.webHeight) ||
        !this.isFiniteNumber(parsed.layoutTop) || !this.isFiniteNumber(parsed.visualTop) ||
        !this.isFiniteNumber(parsed.capturedAt)) {
        return undefined;
      }
      return parsed;
    } catch (_error) {
      return undefined;
    }
  }

  private isFiniteNumber(value: number): boolean {
    return Number.isFinite(Number(value));
  }
}

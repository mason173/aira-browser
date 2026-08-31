import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { ReaderModeBrightnessMode } from '../../common/models/BrowserModels';
import { ReadingSurfaceAppearance } from '../../features/reading/ReadingSurfaceModels';

const PREFERENCES_NAME: string = 'aira_browser_preferences';
const PREFERENCES_KEY: string = 'reading_surface_appearance';

export class ReadingAppearancePreferencesRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private cachedAppearance?: ReadingSurfaceAppearance;

  async load(defaultValue: ReadingSurfaceAppearance): Promise<ReadingSurfaceAppearance> {
    const store: preferences.Preferences = await this.getStore();
    const rawValue: string = String(store.getSync(PREFERENCES_KEY, ''));
    if (rawValue.length === 0) {
      await this.save(defaultValue);
      return this.resolveCached(defaultValue);
    }
    try {
      const parsed: ReadingSurfaceAppearance = JSON.parse(rawValue) as ReadingSurfaceAppearance;
      this.cachedAppearance = this.normalize(parsed, defaultValue);
      return this.copy(this.cachedAppearance);
    } catch (_error) {
      await this.save(defaultValue);
      return this.resolveCached(defaultValue);
    }
  }

  async save(value: ReadingSurfaceAppearance): Promise<void> {
    this.cachedAppearance = this.normalize(value, value);
    const store: preferences.Preferences = await this.getStore();
    store.putSync(PREFERENCES_KEY, JSON.stringify(this.cachedAppearance));
    await store.flush();
  }

  resolveCached(defaultValue: ReadingSurfaceAppearance): ReadingSurfaceAppearance {
    if (this.cachedAppearance === undefined) {
      return this.normalize(defaultValue, defaultValue);
    }
    return this.copy(this.cachedAppearance);
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        PREFERENCES_NAME
      ).then((store: preferences.Preferences): preferences.Preferences => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private normalize(
    value: ReadingSurfaceAppearance,
    fallback: ReadingSurfaceAppearance
  ): ReadingSurfaceAppearance {
    const fontSize: number = Number.isFinite(value.fontSize) ? value.fontSize : fallback.fontSize;
    const brightness: number = Number.isFinite(value.brightnessPercent)
      ? value.brightnessPercent
      : fallback.brightnessPercent;
    return {
      fontSize: Math.max(15, Math.min(26, Math.round(fontSize))),
      theme: this.normalizeTheme(value.theme, fallback.theme),
      lineHeight: value.lineHeight === 'compact' || value.lineHeight === 'comfortable' ||
        value.lineHeight === 'loose' ? value.lineHeight : fallback.lineHeight,
      pageWidth: value.pageWidth === 'narrow' || value.pageWidth === 'standard' || value.pageWidth === 'wide'
        ? value.pageWidth
        : fallback.pageWidth,
      brightnessMode: this.normalizeBrightnessMode(value.brightnessMode),
      brightnessPercent: Math.max(20, Math.min(100, Math.round(brightness)))
    };
  }

  private normalizeBrightnessMode(value: ReaderModeBrightnessMode | string | undefined): ReaderModeBrightnessMode {
    return value === 'manual' ? 'manual' : 'system';
  }

  private normalizeTheme(value: string, fallback: string): 'light' | 'paper' | 'sepia' | 'sage' |
    'charcoal' | 'dark' | 'system' {
    if (value === 'light' || value === 'paper' || value === 'sepia' || value === 'sage' ||
      value === 'charcoal' || value === 'dark' || value === 'system') {
      return value;
    }
    if (fallback === 'light' || fallback === 'paper' || fallback === 'sepia' || fallback === 'sage' ||
      fallback === 'charcoal' || fallback === 'dark') {
      return fallback;
    }
    return 'system';
  }

  private copy(value: ReadingSurfaceAppearance): ReadingSurfaceAppearance {
    return {
      fontSize: value.fontSize,
      theme: value.theme,
      lineHeight: value.lineHeight,
      pageWidth: value.pageWidth,
      brightnessMode: value.brightnessMode,
      brightnessPercent: value.brightnessPercent
    };
  }
}

export const sharedReadingAppearancePreferencesRepository: ReadingAppearancePreferencesRepository =
  new ReadingAppearancePreferencesRepository();

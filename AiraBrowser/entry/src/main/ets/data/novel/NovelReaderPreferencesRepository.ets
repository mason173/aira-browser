import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  NovelReaderPreferences,
  NovelReaderPreferencesPort
} from '../../features/novel/NovelReaderModels';
import { ReadingSurfaceAppearance } from '../../features/reading/ReadingSurfaceModels';
import {
  sharedReadingAppearancePreferencesRepository
} from '../reading/ReadingAppearancePreferencesRepository';

const PREFERENCES_NAME: string = 'aira_novel_reader_preferences';
const PREFERENCES_KEY: string = 'reader_preferences';

interface NovelReaderBehaviorPreferencesRecord {
  pageMode: string;
  autoReadingEnabled: boolean;
  autoReadingSpeed: number;
  volumeKeyPagingEnabled: boolean;
  systemStatusBarVisible: boolean;
  chapterNameVisible: boolean;
  pageNumberVisible: boolean;
}

export class NovelReaderPreferencesRepository implements NovelReaderPreferencesPort {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async load(defaultValue: NovelReaderPreferences): Promise<NovelReaderPreferences> {
    const store = await this.getStore();
    const rawValue = String(store.getSync(PREFERENCES_KEY, ''));
    let storedPreferences: NovelReaderPreferences = this.copyPreferences(defaultValue);
    try {
      if (rawValue.length > 0) {
        storedPreferences = this.mergeStoredPreferences(
          JSON.parse(rawValue) as NovelReaderPreferences,
          defaultValue
        );
      }
    } catch (_error) {
      storedPreferences = this.copyPreferences(defaultValue);
    }
    const appearance: ReadingSurfaceAppearance = await sharedReadingAppearancePreferencesRepository.load(
      this.buildReadingAppearance(storedPreferences)
    );
    return this.mergeReadingAppearance(storedPreferences, appearance);
  }

  async save(value: NovelReaderPreferences): Promise<void> {
    const store = await this.getStore();
    const behavior: NovelReaderBehaviorPreferencesRecord = {
      pageMode: value.pageMode,
      autoReadingEnabled: value.autoReadingEnabled,
      autoReadingSpeed: value.autoReadingSpeed,
      volumeKeyPagingEnabled: value.volumeKeyPagingEnabled,
      systemStatusBarVisible: value.systemStatusBarVisible,
      chapterNameVisible: value.chapterNameVisible,
      pageNumberVisible: value.pageNumberVisible
    };
    store.putSync(PREFERENCES_KEY, JSON.stringify(behavior));
    await sharedReadingAppearancePreferencesRepository.save(this.buildReadingAppearance(value));
    await store.flush();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getUIAbilityContext(),
        PREFERENCES_NAME
      ).then((store: preferences.Preferences): preferences.Preferences => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private copyPreferences(value: NovelReaderPreferences): NovelReaderPreferences {
    return {
      fontSize: value.fontSize,
      theme: value.theme,
      lineHeight: value.lineHeight,
      pageWidth: value.pageWidth,
      brightnessMode: value.brightnessMode,
      brightnessPercent: value.brightnessPercent,
      pageMode: value.pageMode,
      autoReadingEnabled: value.autoReadingEnabled,
      autoReadingSpeed: value.autoReadingSpeed,
      volumeKeyPagingEnabled: value.volumeKeyPagingEnabled,
      systemStatusBarVisible: value.systemStatusBarVisible,
      chapterNameVisible: value.chapterNameVisible,
      pageNumberVisible: value.pageNumberVisible
    };
  }

  private mergeStoredPreferences(
    stored: NovelReaderPreferences,
    fallback: NovelReaderPreferences
  ): NovelReaderPreferences {
    return {
      fontSize: Number.isFinite(stored.fontSize) ? stored.fontSize : fallback.fontSize,
      theme: stored.theme ?? fallback.theme,
      lineHeight: stored.lineHeight ?? fallback.lineHeight,
      pageWidth: stored.pageWidth ?? fallback.pageWidth,
      brightnessMode: stored.brightnessMode === 'manual' ? 'manual' : 'system',
      brightnessPercent: Number.isFinite(stored.brightnessPercent)
        ? stored.brightnessPercent
        : fallback.brightnessPercent,
      pageMode: stored.pageMode ?? fallback.pageMode,
      autoReadingEnabled: typeof stored.autoReadingEnabled === 'boolean'
        ? stored.autoReadingEnabled
        : fallback.autoReadingEnabled,
      autoReadingSpeed: Number.isFinite(stored.autoReadingSpeed)
        ? stored.autoReadingSpeed
        : fallback.autoReadingSpeed,
      volumeKeyPagingEnabled: typeof stored.volumeKeyPagingEnabled === 'boolean'
        ? stored.volumeKeyPagingEnabled
        : fallback.volumeKeyPagingEnabled,
      systemStatusBarVisible: typeof stored.systemStatusBarVisible === 'boolean'
        ? stored.systemStatusBarVisible
        : fallback.systemStatusBarVisible,
      chapterNameVisible: typeof stored.chapterNameVisible === 'boolean'
        ? stored.chapterNameVisible
        : fallback.chapterNameVisible,
      pageNumberVisible: typeof stored.pageNumberVisible === 'boolean'
        ? stored.pageNumberVisible
        : fallback.pageNumberVisible
    };
  }

  private buildReadingAppearance(preferences: NovelReaderPreferences): ReadingSurfaceAppearance {
    return {
      fontSize: preferences.fontSize,
      theme: preferences.theme,
      lineHeight: preferences.lineHeight,
      pageWidth: preferences.pageWidth,
      brightnessMode: preferences.brightnessMode,
      brightnessPercent: preferences.brightnessPercent
    };
  }

  private mergeReadingAppearance(
    preferences: NovelReaderPreferences,
    appearance: ReadingSurfaceAppearance
  ): NovelReaderPreferences {
    const merged: NovelReaderPreferences = this.copyPreferences(preferences);
    merged.fontSize = appearance.fontSize;
    merged.theme = appearance.theme;
    merged.lineHeight = appearance.lineHeight;
    merged.pageWidth = appearance.pageWidth;
    merged.brightnessMode = appearance.brightnessMode;
    merged.brightnessPercent = appearance.brightnessPercent;
    return merged;
  }
}

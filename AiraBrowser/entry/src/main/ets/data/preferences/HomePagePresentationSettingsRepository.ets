import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY
} from '../../common/constants/HomePagePresentationStorageKeys';
import { HomePagePresentationSettings } from '../../common/models/HomePagePresentationSettingsModels';
import {
  PersonalizationSettingsChangeOrigin,
  PersonalizationSettingsLocalChangeHandler
} from '../../common/models/PersonalizationSyncModels';

const PREFERENCES_NAME: string = 'aira_home_page_presentation';
const SETTINGS_KEY: string = 'settings_v1';

export const DEFAULT_HOME_PAGE_PRESENTATION_SETTINGS: HomePagePresentationSettings = {
  showFavoritesTitle: true,
  showShortcutNames: true,
  showRecentlyClosedTitle: true,
  showSettingsButton: true
};

export class HomePagePresentationSettingsRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: HomePagePresentationSettings = this.copySettings(DEFAULT_HOME_PAGE_PRESENTATION_SETTINGS);
  private localChangeHandler?: PersonalizationSettingsLocalChangeHandler;

  setLocalChangeHandler(handler?: PersonalizationSettingsLocalChangeHandler): void {
    this.localChangeHandler = handler;
  }

  async initialize(): Promise<HomePagePresentationSettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(SETTINGS_KEY, ''));
    this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
    this.publishSettings();
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings, 'system');
    }
    return this.getSettings();
  }

  getSettings(): HomePagePresentationSettings {
    return this.copySettings(this.settings);
  }

  async updateSettings(
    settings: HomePagePresentationSettings,
    origin: PersonalizationSettingsChangeOrigin = 'local'
  ): Promise<HomePagePresentationSettings> {
    return this.persistSettings(settings, origin);
  }

  private async persistSettings(
    settings: HomePagePresentationSettings,
    origin: PersonalizationSettingsChangeOrigin
  ): Promise<HomePagePresentationSettings> {
    const previous = this.getSettings();
    this.settings = this.normalizeSettings(settings);
    const store = await this.getStore();
    store.putSync(SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    this.publishSettings();
    if (origin === 'local' && !this.isSameSettings(previous, this.settings)) {
      this.localChangeHandler?.();
    }
    return this.getSettings();
  }

  private isSameSettings(
    left: HomePagePresentationSettings,
    right: HomePagePresentationSettings
  ): boolean {
    return left.showFavoritesTitle === right.showFavoritesTitle &&
      left.showShortcutNames === right.showShortcutNames &&
      left.showRecentlyClosedTitle === right.showRecentlyClosedTitle &&
      left.showSettingsButton === right.showSettingsButton;
  }

  private publishSettings(): void {
    AppStorage.setOrCreate(
      HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY,
      this.settings.showFavoritesTitle
    );
    AppStorage.setOrCreate(
      HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY,
      this.settings.showShortcutNames
    );
    AppStorage.setOrCreate(
      HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
      this.settings.showRecentlyClosedTitle
    );
    AppStorage.setOrCreate(
      HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY,
      this.settings.showSettingsButton
    );
  }

  private parseSettings(value: string): HomePagePresentationSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as HomePagePresentationSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeSettings(
    settings: HomePagePresentationSettings | undefined
  ): HomePagePresentationSettings {
    return {
      showFavoritesTitle: typeof settings?.showFavoritesTitle === 'boolean'
        ? settings.showFavoritesTitle
        : DEFAULT_HOME_PAGE_PRESENTATION_SETTINGS.showFavoritesTitle,
      showShortcutNames: typeof settings?.showShortcutNames === 'boolean'
        ? settings.showShortcutNames
        : DEFAULT_HOME_PAGE_PRESENTATION_SETTINGS.showShortcutNames,
      showRecentlyClosedTitle: typeof settings?.showRecentlyClosedTitle === 'boolean'
        ? settings.showRecentlyClosedTitle
        : DEFAULT_HOME_PAGE_PRESENTATION_SETTINGS.showRecentlyClosedTitle,
      showSettingsButton: typeof settings?.showSettingsButton === 'boolean'
        ? settings.showSettingsButton
        : DEFAULT_HOME_PAGE_PRESENTATION_SETTINGS.showSettingsButton
    };
  }

  private copySettings(settings: HomePagePresentationSettings): HomePagePresentationSettings {
    return {
      showFavoritesTitle: settings.showFavoritesTitle,
      showShortcutNames: settings.showShortcutNames,
      showRecentlyClosedTitle: settings.showRecentlyClosedTitle,
      showSettingsButton: settings.showSettingsButton
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  DEFAULT_WALLPAPER_BING_STATE,
  DEFAULT_WALLPAPER_SETTINGS,
  HomeWallpaperForegroundTone,
  WallpaperAsset,
  WallpaperAssetMediaType,
  WallpaperAssetSource,
  WallpaperBingState,
  WallpaperMode,
  WallpaperRepositorySnapshot,
  WallpaperSettings
} from '../../common/models/WallpaperModels';
import {
  PersonalizationSettingsChangeOrigin,
  PersonalizationSettingsLocalChangeHandler
} from '../../common/models/PersonalizationSyncModels';
import {
  BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION,
  BrowserHomepageBackdropAppearanceState,
  cloneBrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';

const PREFERENCES_NAME: string = 'aira_browser_wallpaper';
const WALLPAPER_SETTINGS_KEY: string = 'wallpaper_settings';
const WALLPAPER_ASSETS_KEY: string = 'wallpaper_assets';
const MAX_ASSET_METADATA_COUNT: number = 120;

export class WallpaperRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: WallpaperSettings = this.cloneSettings(DEFAULT_WALLPAPER_SETTINGS);
  private assets: WallpaperAsset[] = [];
  private localChangeHandler?: PersonalizationSettingsLocalChangeHandler;

  setLocalChangeHandler(handler?: PersonalizationSettingsLocalChangeHandler): void {
    this.localChangeHandler = handler;
  }

  async initialize(): Promise<WallpaperRepositorySnapshot> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(WALLPAPER_SETTINGS_KEY, ''));
    const rawAssets = String(store.getSync(WALLPAPER_ASSETS_KEY, ''));
    this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
    this.assets = this.normalizeAssets(this.parseAssets(rawAssets));
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings, 'system');
    }
    if (rawAssets.trim().length === 0) {
      await this.persistAssets(this.assets);
    }
    return this.getSnapshot();
  }

  getSnapshot(): WallpaperRepositorySnapshot {
    return {
      settings: this.getSettings(),
      assets: this.listAssets()
    };
  }

  getSettings(): WallpaperSettings {
    return this.cloneSettings(this.settings);
  }

  async saveSettings(
    settings: WallpaperSettings,
    origin: PersonalizationSettingsChangeOrigin = 'local'
  ): Promise<WallpaperSettings> {
    return this.persistSettings(this.normalizeSettings(settings), origin);
  }

  async updateSettings(
    partialSettings: Partial<WallpaperSettings>,
    origin: PersonalizationSettingsChangeOrigin = 'local'
  ): Promise<WallpaperSettings> {
    const nextSettings: WallpaperSettings = this.normalizeSettings({
      mode: partialSettings.mode ?? this.settings.mode,
      bingWallpaperId: partialSettings.bingWallpaperId ?? this.settings.bingWallpaperId,
      customWallpaperId: partialSettings.customWallpaperId ?? this.settings.customWallpaperId,
      bing: partialSettings.bing ?? this.settings.bing,
      updatedAt: Date.now()
    });
    return this.persistSettings(nextSettings, origin);
  }

  listAssets(): WallpaperAsset[] {
    return this.assets.map((asset: WallpaperAsset) => this.cloneAsset(asset));
  }

  async commitBingAppearance(
    asset: WallpaperAsset,
    bingState: WallpaperBingState,
    nowMs: number = Date.now()
  ): Promise<WallpaperRepositorySnapshot> {
    const normalizedAsset = this.normalizeAsset(asset);
    if (normalizedAsset.id.length === 0 || normalizedAsset.source !== 'bing') {
      throw new Error('wallpaper-bing-asset-invalid');
    }
    const nextAssets = this.capAssets(this.assets
      .filter((item: WallpaperAsset) => item.source !== 'bing' && item.id !== normalizedAsset.id)
      .concat(normalizedAsset));
    const nextSettings = this.normalizeSettings({
      mode: this.settings.mode,
      bingWallpaperId: normalizedAsset.id,
      customWallpaperId: this.settings.customWallpaperId,
      bing: bingState,
      updatedAt: nowMs
    });
    return this.persistSnapshot(nextSettings, nextAssets);
  }

  async commitCustomAppearance(
    asset: WallpaperAsset,
    nowMs: number = Date.now()
  ): Promise<WallpaperRepositorySnapshot> {
    const normalizedAsset = this.normalizeAsset(asset);
    if (normalizedAsset.id.length === 0 || normalizedAsset.source !== 'custom') {
      throw new Error('wallpaper-custom-asset-invalid');
    }
    const nextAssets = this.capAssets(this.assets
      .filter((item: WallpaperAsset) => item.source !== 'custom' && item.id !== normalizedAsset.id)
      .concat(normalizedAsset));
    const nextSettings = this.normalizeSettings({
      mode: 'custom',
      bingWallpaperId: this.settings.bingWallpaperId,
      customWallpaperId: normalizedAsset.id,
      bing: this.settings.bing,
      updatedAt: nowMs
    });
    return this.persistSnapshot(nextSettings, nextAssets);
  }

  async removeAsset(assetId: string): Promise<WallpaperAsset[]> {
    const normalizedId = assetId.trim();
    if (normalizedId.length === 0) {
      return this.listAssets();
    }
    return this.persistAssets(this.assets.filter((item: WallpaperAsset) => item.id !== normalizedId));
  }

  private normalizeSettings(value: WallpaperSettings | undefined): WallpaperSettings {
    return {
      mode: this.normalizeMode(value?.mode),
      bingWallpaperId: this.normalizeString(value?.bingWallpaperId, DEFAULT_WALLPAPER_SETTINGS.bingWallpaperId),
      customWallpaperId: this.normalizeString(
        value?.customWallpaperId,
        DEFAULT_WALLPAPER_SETTINGS.customWallpaperId
      ),
      bing: this.normalizeBingState(value?.bing),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizeBingState(value: WallpaperBingState | undefined): WallpaperBingState {
    return {
      currentAssetId: this.normalizeString(value?.currentAssetId, DEFAULT_WALLPAPER_BING_STATE.currentAssetId),
      market: this.normalizeString(value?.market, DEFAULT_WALLPAPER_BING_STATE.market),
      lastRefreshDay: this.normalizeString(value?.lastRefreshDay, DEFAULT_WALLPAPER_BING_STATE.lastRefreshDay),
      lastRefreshAt: this.normalizeTimestamp(value?.lastRefreshAt),
      manualRefreshAvailableAt: this.normalizeTimestamp(value?.manualRefreshAvailableAt),
      failureReason: this.normalizeString(value?.failureReason, DEFAULT_WALLPAPER_BING_STATE.failureReason)
    };
  }

  private normalizeAssets(values: WallpaperAsset[] | undefined): WallpaperAsset[] {
    const results: WallpaperAsset[] = [];
    (values ?? []).forEach((value: WallpaperAsset) => {
      if (!this.hasForegroundTone(value?.foregroundTone)) {
        return;
      }
      const asset = this.normalizeAsset(value);
      if (asset.id.length > 0) {
        results.push(asset);
      }
    });
    return this.capAssets(results);
  }

  private normalizeAsset(value: WallpaperAsset): WallpaperAsset {
    return {
      id: this.normalizeString(value?.id, ''),
      source: this.normalizeAssetSource(value?.source),
      mediaType: this.normalizeMediaType(value?.mediaType),
      originalPath: this.normalizeString(value?.originalPath, ''),
      displayPath: this.normalizeString(value?.displayPath, ''),
      thumbPath: this.normalizeString(value?.thumbPath, ''),
      contentSignature: this.normalizeString(value?.contentSignature, ''),
      foregroundTone: this.normalizeForegroundTone(value?.foregroundTone),
      foregroundToneContentSignature: this.normalizeString(value?.foregroundToneContentSignature, ''),
      foregroundToneCropSignature: this.normalizeString(value?.foregroundToneCropSignature, ''),
      foregroundToneSampleSignature: this.normalizeString(value?.foregroundToneSampleSignature, ''),
      foregroundToneAlgorithmVersion: this.normalizeInteger(value?.foregroundToneAlgorithmVersion, 0),
      appearanceLight: this.normalizeAppearanceState(value?.appearanceLight),
      appearanceDark: this.normalizeAppearanceState(value?.appearanceDark),
      width: this.normalizeInteger(value?.width, 0),
      height: this.normalizeInteger(value?.height, 0),
      mimeType: this.normalizeString(value?.mimeType, ''),
      byteSize: this.normalizeInteger(value?.byteSize, 0),
      title: this.normalizeString(value?.title, ''),
      attribution: this.normalizeString(value?.attribution, ''),
      createdAt: this.normalizeTimestamp(value?.createdAt),
      updatedAt: this.normalizeTimestamp(value?.updatedAt),
      isFavorite: typeof value?.isFavorite === 'boolean' ? value.isFavorite : false
    };
  }

  private capAssets(values: WallpaperAsset[]): WallpaperAsset[] {
    const deduped: WallpaperAsset[] = [];
    values.forEach((asset: WallpaperAsset) => {
      if (deduped.some((item: WallpaperAsset) => item.id === asset.id)) {
        return;
      }
      deduped.push(this.cloneAsset(asset));
    });
    if (deduped.length <= MAX_ASSET_METADATA_COUNT) {
      return deduped;
    }
    const favorites = deduped.filter((asset: WallpaperAsset) => asset.isFavorite);
    const ordinary = deduped
      .filter((asset: WallpaperAsset) => !asset.isFavorite)
      .sort((left: WallpaperAsset, right: WallpaperAsset) => right.updatedAt - left.updatedAt);
    return favorites.concat(ordinary).slice(0, MAX_ASSET_METADATA_COUNT);
  }

  private parseSettings(value: string): WallpaperSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as WallpaperSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private parseAssets(value: string): WallpaperAsset[] | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as WallpaperAsset[];
    } catch (_error) {
      return undefined;
    }
  }

  private async persistSettings(
    settings: WallpaperSettings,
    origin: PersonalizationSettingsChangeOrigin
  ): Promise<WallpaperSettings> {
    const previousMode = this.settings.mode;
    this.settings = this.cloneSettings(settings);
    const store = await this.getStore();
    store.putSync(WALLPAPER_SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    if (origin === 'local' && previousMode !== this.settings.mode) {
      this.localChangeHandler?.();
    }
    return this.getSettings();
  }

  private async persistAssets(assets: WallpaperAsset[]): Promise<WallpaperAsset[]> {
    this.assets = assets.map((asset: WallpaperAsset) => this.cloneAsset(asset));
    const store = await this.getStore();
    store.putSync(WALLPAPER_ASSETS_KEY, JSON.stringify(this.assets));
    store.flushSync();
    return this.listAssets();
  }

  private async persistSnapshot(
    settings: WallpaperSettings,
    assets: WallpaperAsset[],
    origin: PersonalizationSettingsChangeOrigin = 'local'
  ): Promise<WallpaperRepositorySnapshot> {
    const previousSettings = this.cloneSettings(this.settings);
    const previousAssets = this.assets.map((asset: WallpaperAsset) => this.cloneAsset(asset));
    const nextSettings = this.cloneSettings(settings);
    const nextAssets = assets.map((asset: WallpaperAsset) => this.cloneAsset(asset));
    const store = await this.getStore();
    try {
      store.putSync(WALLPAPER_SETTINGS_KEY, JSON.stringify(nextSettings));
      store.putSync(WALLPAPER_ASSETS_KEY, JSON.stringify(nextAssets));
      store.flushSync();
      this.settings = nextSettings;
      this.assets = nextAssets;
      if (origin === 'local' && previousSettings.mode !== nextSettings.mode) {
        this.localChangeHandler?.();
      }
      return this.getSnapshot();
    } catch (_error) {
      this.settings = previousSettings;
      this.assets = previousAssets;
      try {
        store.putSync(WALLPAPER_SETTINGS_KEY, JSON.stringify(previousSettings));
        store.putSync(WALLPAPER_ASSETS_KEY, JSON.stringify(previousAssets));
        store.flushSync();
      } catch (_restoreError) {
      }
      throw new Error('wallpaper-snapshot-persist-failed');
    }
  }

  private cloneSettings(settings: WallpaperSettings): WallpaperSettings {
    return {
      mode: settings.mode,
      bingWallpaperId: settings.bingWallpaperId,
      customWallpaperId: settings.customWallpaperId,
      bing: {
        currentAssetId: settings.bing.currentAssetId,
        market: settings.bing.market,
        lastRefreshDay: settings.bing.lastRefreshDay,
        lastRefreshAt: settings.bing.lastRefreshAt,
        manualRefreshAvailableAt: settings.bing.manualRefreshAvailableAt,
        failureReason: settings.bing.failureReason
      },
      updatedAt: settings.updatedAt
    };
  }

  private cloneAsset(asset: WallpaperAsset): WallpaperAsset {
    return {
      id: asset.id,
      source: asset.source,
      mediaType: asset.mediaType,
      originalPath: asset.originalPath,
      displayPath: asset.displayPath,
      thumbPath: asset.thumbPath,
      contentSignature: asset.contentSignature,
      foregroundTone: asset.foregroundTone,
      foregroundToneContentSignature: asset.foregroundToneContentSignature,
      foregroundToneCropSignature: asset.foregroundToneCropSignature,
      foregroundToneSampleSignature: asset.foregroundToneSampleSignature,
      foregroundToneAlgorithmVersion: asset.foregroundToneAlgorithmVersion,
      appearanceLight: this.cloneAppearanceState(asset.appearanceLight),
      appearanceDark: this.cloneAppearanceState(asset.appearanceDark),
      width: asset.width,
      height: asset.height,
      mimeType: asset.mimeType,
      byteSize: asset.byteSize,
      title: asset.title,
      attribution: asset.attribution,
      createdAt: asset.createdAt,
      updatedAt: asset.updatedAt,
      isFavorite: asset.isFavorite
    };
  }

  private normalizeMode(value: WallpaperMode | undefined): WallpaperMode {
    if (value === 'theme' || value === 'bing' || value === 'custom') {
      return value;
    }
    return DEFAULT_WALLPAPER_SETTINGS.mode;
  }

  private normalizeAssetSource(value: WallpaperAssetSource | undefined): WallpaperAssetSource {
    if (value === 'bing' || value === 'custom') {
      return value;
    }
    return 'builtin';
  }

  private normalizeMediaType(value: WallpaperAssetMediaType | undefined): WallpaperAssetMediaType {
    return 'image';
  }

  private normalizeForegroundTone(value: HomeWallpaperForegroundTone | undefined): HomeWallpaperForegroundTone {
    if (value === 'darkText' || value === 'lightText') {
      return value;
    }
    return 'lightText';
  }

  private hasForegroundTone(value: HomeWallpaperForegroundTone | undefined): boolean {
    return value === 'darkText' || value === 'lightText';
  }

  private normalizeString(value: string | undefined, fallback: string): string {
    if (typeof value !== 'string') {
      return fallback;
    }
    const normalizedValue = value.trim();
    return normalizedValue.length > 0 ? normalizedValue : fallback;
  }

  private normalizeAppearanceState(
    state: BrowserHomepageBackdropAppearanceState | undefined
  ): BrowserHomepageBackdropAppearanceState | undefined {
    const sourceKey = this.normalizeString(state?.sourceKey, '');
    const snapshotSignature = this.normalizeString(state?.snapshotSignature, '');
    if (state === undefined || !state.available ||
      state.algorithmVersion !== BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION ||
      sourceKey.length <= 0 ||
      snapshotSignature.length <= 0) {
      return undefined;
    }
    const normalized = cloneBrowserHomepageBackdropAppearanceState(state);
    normalized.sourceKey = sourceKey;
    normalized.snapshotSignature = snapshotSignature;
    normalized.algorithmVersion = BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION;
    normalized.resolvedThemeMode = normalized.resolvedThemeMode === 'dark' ? 'dark' : 'light';
    normalized.toolbarForegroundTone = normalized.toolbarForegroundTone === 'light' ? 'light' : 'dark';
    normalized.toolbarLabelTextColor = this.normalizeString(normalized.toolbarLabelTextColor, '');
    normalized.toolbarPrimaryTextColor = this.normalizeString(normalized.toolbarPrimaryTextColor, '');
    normalized.toolbarSecondaryTextColor = this.normalizeString(normalized.toolbarSecondaryTextColor, '');
    normalized.updatedAt = this.normalizeTimestamp(normalized.updatedAt);
    normalized.volatileOnly = false;
    return normalized;
  }

  private cloneAppearanceState(
    state: BrowserHomepageBackdropAppearanceState | undefined
  ): BrowserHomepageBackdropAppearanceState | undefined {
    return state === undefined ? undefined : cloneBrowserHomepageBackdropAppearanceState(state);
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeInteger(value: number | undefined, fallback: number): number {
    return typeof value === 'number' && isFinite(value) ? Math.floor(value) : fallback;
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

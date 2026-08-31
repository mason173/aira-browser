import {
  BrowserPreferences,
  BrowserResolvedThemeMode
} from '../../common/models/BrowserModels';
import {
  CustomHomepageItem,
  CustomHomepageSettings,
  resolveCustomHomepageForceDarkWebContent,
  resolveCustomHomepageHideToolbarOnScroll,
  resolveCustomHomepageSystemEntryButtonVisibility,
  resolveCustomHomepageSystemSearchVisibility
} from '../../common/models/CustomHomepageModels';
import { WallpaperRepositorySnapshot } from '../../common/models/WallpaperModels';
import {
  BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION,
  BrowserHomepageBackdropAppearanceEffectInput,
  BrowserHomepageBackdropAppearanceSource,
  BrowserHomepageBackdropAppearanceSourceKind,
  BrowserHomepageBackdropAppearanceState,
  DEFAULT_BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_STATE,
  cloneBrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';

export interface BrowserHomepageBackdropAppearanceSourceInput {
  customHomepageSettings: CustomHomepageSettings;
  wallpaperSnapshot: WallpaperRepositorySnapshot;
  preferences: BrowserPreferences;
  resolvedThemeMode: BrowserResolvedThemeMode;
  privateMode: boolean;
}

export interface BrowserHomepageBackdropAppearanceEffectBuildInput {
  resolvedThemeMode: BrowserResolvedThemeMode;
  tintColor: ResourceColor;
  tintOpacity: number;
}

export interface BrowserHomepageBackdropAppearanceSyncInput {
  source: BrowserHomepageBackdropAppearanceSource;
  effect: BrowserHomepageBackdropAppearanceEffectInput;
}

export interface BrowserHomepageBackdropAppearanceCurrentSyncInput {
  source: BrowserHomepageBackdropAppearanceSourceInput;
  effect: BrowserHomepageBackdropAppearanceEffectBuildInput;
}

export class BrowserHomepageBackdropAppearanceCoordinator {
  private state: BrowserHomepageBackdropAppearanceState =
    cloneBrowserHomepageBackdropAppearanceState(DEFAULT_BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_STATE);

  constructor() {}

  getState(): BrowserHomepageBackdropAppearanceState {
    return cloneBrowserHomepageBackdropAppearanceState(this.state);
  }

  buildStateRenderKey(state: BrowserHomepageBackdropAppearanceState): string {
    return [
      state.available ? '1' : '0',
      state.sourceKey,
      state.snapshotSignature,
      state.resolvedThemeMode,
      state.toolbarSurfaceColor,
      state.toolbarForegroundTone,
      state.toolbarLabelTextColor,
      state.toolbarPrimaryTextColor,
      state.toolbarSecondaryTextColor,
      state.toolbarPressedOverlayColor,
      state.toolbarOutlineColor
    ].join('|');
  }

  buildSource(input: BrowserHomepageBackdropAppearanceSourceInput): BrowserHomepageBackdropAppearanceSource {
    const selectedItem = this.resolveSelectedCustomHomepageItem(input.customHomepageSettings);
    if (input.customHomepageSettings.mode === 'custom_html' && selectedItem !== undefined) {
      return this.buildCustomHomepageSource(input, selectedItem);
    }
    return this.buildSystemHomepageSource(input);
  }

  buildEffect(input: BrowserHomepageBackdropAppearanceEffectBuildInput): BrowserHomepageBackdropAppearanceEffectInput {
    const tintColor = `${input.tintColor}`.trim();
    const tintOpacity = this.clamp01(input.tintOpacity);
    return {
      resolvedThemeMode: input.resolvedThemeMode,
      tintColor: tintColor.length > 0 ? tintColor : '#000000',
      tintOpacity: tintOpacity,
      effectSignature: `snapshot-effect:v1:${input.resolvedThemeMode}:${tintColor}:${Math.round(tintOpacity * 1000)}`
    };
  }

  async syncCurrent(input: BrowserHomepageBackdropAppearanceCurrentSyncInput):
    Promise<BrowserHomepageBackdropAppearanceState> {
    return this.sync({
      source: this.buildSource(input.source),
      effect: this.buildEffect(input.effect)
    });
  }

  async sync(input: BrowserHomepageBackdropAppearanceSyncInput):
    Promise<BrowserHomepageBackdropAppearanceState> {
    const sourceKey = this.buildSourceKey(input.source, input.effect);
    if (this.state.available && this.state.sourceKey === sourceKey) {
      return this.getState();
    }
    const stored = this.buildStateFromStoredAppearance(input.source, input.effect, sourceKey);
    if (stored !== undefined) {
      this.state = stored;
      return this.getState();
    }
    if (this.state.available && this.state.sourceKey === sourceKey &&
      this.state.resolvedThemeMode === input.effect.resolvedThemeMode) {
      return this.getState();
    }
    this.state = this.buildUnavailableState(sourceKey, input.effect.resolvedThemeMode, input.source.privateMode);
    return this.getState();
  }

  buildSourceKey(
    source: BrowserHomepageBackdropAppearanceSource,
    effect: BrowserHomepageBackdropAppearanceEffectInput
  ): string {
    return [
      'homepageAppearance',
      `v${BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION}`,
      effect.resolvedThemeMode,
      source.privateMode ? 'private' : 'regular',
      source.kind,
      this.hashString(source.id),
      this.hashString(source.version),
      this.hashString(effect.effectSignature)
    ].join(':');
  }

  private buildSystemHomepageSource(
    input: BrowserHomepageBackdropAppearanceSourceInput
  ): BrowserHomepageBackdropAppearanceSource {
    const wallpaperSettings = input.wallpaperSnapshot.settings;
    const version = [
      `wallpaperEnabled=${input.preferences.wallpaperEnabled ? '1' : '0'}`,
      `wallpaperMode=${wallpaperSettings.mode}`,
      `bingId=${wallpaperSettings.bingWallpaperId}`,
      `bingCurrent=${wallpaperSettings.bing.currentAssetId}`,
      `customId=${wallpaperSettings.customWallpaperId}`,
      `wallpaperUpdated=${wallpaperSettings.updatedAt}`,
      `homeLayout=${input.preferences.homeLayout}`,
      `shortcuts=${input.preferences.appearance.showHomeShortcuts ? '1' : '0'}`,
      `recent=${input.preferences.appearance.showHomeRecentlyClosed ? '1' : '0'}`,
      `search=${input.customHomepageSettings.systemHomepageShowSystemSearchBar ? '1' : '0'}`,
      `palette=${input.preferences.appearance.themePaletteId}`
    ].join('|');
    return {
      kind: 'system_home',
      id: 'system',
      version: version,
      privateMode: input.privateMode,
      storedAppearance: this.resolveSystemHomepageStoredAppearance(input)
    };
  }

  private buildCustomHomepageSource(
    input: BrowserHomepageBackdropAppearanceSourceInput,
    selectedItem: CustomHomepageItem
  ): BrowserHomepageBackdropAppearanceSource {
    const isRemote = selectedItem.kind === 'remote_url';
    const sourceKind: BrowserHomepageBackdropAppearanceSourceKind = isRemote ?
      'custom_url_home' :
      'custom_imported_home';
    const idSeed = isRemote ?
      this.normalizeString(selectedItem.remoteUrl).toLowerCase() :
      `${selectedItem.id}|${selectedItem.identityKey}|${selectedItem.filePath}`;
    const version = [
      `settings=${input.customHomepageSettings.updatedAt}`,
      `item=${selectedItem.updatedAt}`,
      `imported=${selectedItem.importedAt}`,
      `kind=${selectedItem.kind}`,
      `search=${resolveCustomHomepageSystemSearchVisibility(input.customHomepageSettings) ? '1' : '0'}`,
      `entry=${resolveCustomHomepageSystemEntryButtonVisibility(input.customHomepageSettings) ? '1' : '0'}`,
      `forceDark=${resolveCustomHomepageForceDarkWebContent(input.customHomepageSettings) ? '1' : '0'}`,
      `scrollHide=${resolveCustomHomepageHideToolbarOnScroll(input.customHomepageSettings) ? '1' : '0'}`,
      `theme=${input.resolvedThemeMode}`,
      `palette=${input.preferences.appearance.themePaletteId}`,
      `url=${this.normalizeString(selectedItem.remoteUrl)}`
    ].join('|');
    const storedAppearance = this.resolveCustomHomepageStoredAppearance(input, selectedItem);
    return {
      kind: sourceKind,
      id: idSeed.length > 0 ? idSeed : selectedItem.id,
      version: version,
      privateMode: input.privateMode,
      storedAppearance: storedAppearance
    };
  }

  private resolveSystemHomepageStoredAppearance(
    input: BrowserHomepageBackdropAppearanceSourceInput
  ): BrowserHomepageBackdropAppearanceState | undefined {
    const settings = input.wallpaperSnapshot.settings;
    if (!input.preferences.wallpaperEnabled || settings.mode === 'theme') {
      return undefined;
    }
    const selectedAssetId = settings.mode === 'custom' ?
      settings.customWallpaperId :
      (settings.bingWallpaperId.length > 0 ? settings.bingWallpaperId : settings.bing.currentAssetId);
    const expectedSource = settings.mode === 'custom' ? 'custom' : 'bing';
    const asset = input.wallpaperSnapshot.assets.find((candidate) => {
      return candidate.id === selectedAssetId && candidate.source === expectedSource;
    });
    if (asset === undefined) {
      return undefined;
    }
    return input.resolvedThemeMode === 'dark' ?
      (asset.appearanceDark ?? asset.appearanceLight) :
      (asset.appearanceLight ?? asset.appearanceDark);
  }

  private resolveCustomHomepageStoredAppearance(
    input: BrowserHomepageBackdropAppearanceSourceInput,
    selectedItem: CustomHomepageItem
  ): BrowserHomepageBackdropAppearanceState | undefined {
    if (selectedItem.kind === 'zip_package') {
      if (input.resolvedThemeMode === 'dark') {
        if (!this.hasTrustedImportedDarkAppearance(selectedItem)) {
          return undefined;
        }
        return selectedItem.appearanceDark;
      }
      return selectedItem.appearanceLight;
    }
    if (input.resolvedThemeMode === 'dark' &&
      (selectedItem.kind !== 'remote_url' || resolveCustomHomepageForceDarkWebContent(
        input.customHomepageSettings
      ))) {
      return selectedItem.appearanceDark ?? selectedItem.appearanceLight;
    }
    return selectedItem.appearanceLight ?? selectedItem.appearanceDark;
  }

  private hasTrustedImportedDarkAppearance(selectedItem: CustomHomepageItem): boolean {
    const appearance = selectedItem.appearanceDark;
    if (appearance === undefined) {
      return false;
    }
    if (selectedItem.hasDarkAppearanceEvidence !== undefined) {
      return selectedItem.hasDarkAppearanceEvidence;
    }
    const lightPreviewUri = this.normalizeString(selectedItem.previewLightUri);
    const darkPreviewUri = this.normalizeString(selectedItem.previewDarkUri);
    return lightPreviewUri.length === 0 || darkPreviewUri.length === 0 || lightPreviewUri !== darkPreviewUri;
  }

  private buildStateFromStoredAppearance(
    source: BrowserHomepageBackdropAppearanceSource,
    effect: BrowserHomepageBackdropAppearanceEffectInput,
    sourceKey: string
  ): BrowserHomepageBackdropAppearanceState | undefined {
    const stored = source.storedAppearance;
    if (stored === undefined || !stored.available ||
      stored.algorithmVersion !== BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION) {
      return undefined;
    }
    const next = cloneBrowserHomepageBackdropAppearanceState(stored);
    next.sourceKey = sourceKey;
    next.algorithmVersion = BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION;
    next.resolvedThemeMode = effect.resolvedThemeMode;
    next.volatileOnly = source.privateMode;
    if (next.toolbarLabelTextColor.trim().length <= 0) {
      next.toolbarLabelTextColor = next.toolbarPrimaryTextColor;
    }
    return next;
  }

  private resolveSelectedCustomHomepageItem(settings: CustomHomepageSettings): CustomHomepageItem | undefined {
    if (settings.mode !== 'custom_html' || settings.selectedItemId.trim().length <= 0) {
      return undefined;
    }
    return settings.items.find((item: CustomHomepageItem): boolean => {
      return item.id === settings.selectedItemId;
    });
  }

  private buildUnavailableState(
    sourceKey: string,
    resolvedThemeMode: BrowserResolvedThemeMode,
    volatileOnly: boolean
  ): BrowserHomepageBackdropAppearanceState {
    return {
      available: false,
      sourceKey: sourceKey,
      snapshotSignature: '',
      algorithmVersion: BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION,
      resolvedThemeMode: resolvedThemeMode,
      toolbarSurfaceColor: '',
      toolbarForegroundTone: 'dark',
      toolbarLabelTextColor: '',
      toolbarPrimaryTextColor: '',
      toolbarSecondaryTextColor: '',
      toolbarPressedOverlayColor: '',
      toolbarOutlineColor: '',
      updatedAt: 0,
      volatileOnly: volatileOnly
    };
  }

  private normalizeString(value: string | undefined): string {
    return typeof value === 'string' ? value.trim() : '';
  }

  private hashString(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash = hash ^ value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  private clamp01(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }
}

import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperForegroundTone,
  HomeWallpaperPresentationKind,
  HomeWallpaperPresentationState,
  WallpaperAsset,
  WallpaperMode,
  WallpaperRepositorySnapshot,
  WallpaperSettings,
  cloneHomeWallpaperPresentationState
} from '../../common/models/WallpaperModels';
import { HOME_IMAGE_WALLPAPER_MASK_OPACITY } from './HomeWallpaperAnalysisPolicy';


interface WallpaperPresentationContentState {
  kind: HomeWallpaperPresentationKind;
  mode: WallpaperMode;
  foregroundTone: HomeWallpaperForegroundTone;
  imagePath: string;
  assetId: string;
  updatedAt: number;
}

export class WallpaperPresentationService {
  buildPresentationState(
    snapshot: WallpaperRepositorySnapshot,
    nowMs: number = Date.now()
  ): HomeWallpaperPresentationState {
    const settings = snapshot.settings;
    switch (settings.mode) {
      case 'bing':
        return this.buildBingPresentationState(settings, snapshot.assets);
      case 'custom':
        return this.buildCustomPresentationState(settings, snapshot.assets);
      case 'theme':
      default:
        return this.buildDefaultPresentationState();
    }
  }

  buildDefaultPresentationState(): HomeWallpaperPresentationState {
    return this.clonePresentationState(DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE);
  }

  private buildBingPresentationState(
    settings: WallpaperSettings,
    assets: WallpaperAsset[]
  ): HomeWallpaperPresentationState {
    const selectedAssetId = settings.bingWallpaperId.length > 0
      ? settings.bingWallpaperId
      : settings.bing.currentAssetId;
    const bingAssets = this.filterUsableImageAssets(assets, 'bing');
    const asset = this.findAsset(bingAssets, selectedAssetId);
    if (asset === undefined) {
      return this.buildDefaultPresentationState();
    }
    return this.withSharedSettings(settings, {
      kind: 'image',
      mode: 'bing',
      foregroundTone: asset.foregroundTone,
      imagePath: asset.displayPath,
      assetId: asset.id,
      updatedAt: this.resolveContentUpdatedAt(asset.updatedAt, settings.updatedAt)
    });
  }

  private buildCustomPresentationState(
    settings: WallpaperSettings,
    assets: WallpaperAsset[]
  ): HomeWallpaperPresentationState {
    const customAssets = this.filterUsableImageAssets(assets, 'custom');
    const asset = this.findAsset(customAssets, settings.customWallpaperId);
    if (asset === undefined) {
      return this.buildDefaultPresentationState();
    }
    return this.withSharedSettings(settings, {
      kind: 'image',
      mode: 'custom',
      foregroundTone: asset.foregroundTone,
      imagePath: asset.displayPath,
      assetId: asset.id,
      updatedAt: this.resolveContentUpdatedAt(asset.updatedAt, settings.updatedAt)
    });
  }

  private filterUsableImageAssets(assets: WallpaperAsset[], source: string): WallpaperAsset[] {
    const results: WallpaperAsset[] = [];
    assets.forEach((asset: WallpaperAsset) => {
      if (asset.source === source && asset.mediaType === 'image' && asset.displayPath.length > 0) {
        results.push(asset);
      }
    });
    return results;
  }

  private findAsset(assets: WallpaperAsset[], assetId: string): WallpaperAsset | undefined {
    const normalizedAssetId = assetId.trim();
    let fallback: WallpaperAsset | undefined = undefined;
    assets.forEach((asset: WallpaperAsset) => {
      if (fallback === undefined) {
        fallback = asset;
      }
    });
    const asset = assets.find((item: WallpaperAsset) => item.id === normalizedAssetId);
    return asset === undefined ? fallback : asset;
  }

  private withSharedSettings(
    settings: WallpaperSettings,
    state: WallpaperPresentationContentState
  ): HomeWallpaperPresentationState {
    return {
      kind: state.kind,
      mode: state.mode,
      foregroundTone: state.foregroundTone,
      imagePath: state.imagePath,
      maskOpacity: state.kind === 'image' ? HOME_IMAGE_WALLPAPER_MASK_OPACITY : 0,
      assetId: state.assetId,
      updatedAt: this.resolveContentUpdatedAt(state.updatedAt, settings.updatedAt)
    };
  }

  private resolveContentUpdatedAt(primary: number, fallback: number): number {
    const primaryValue = this.normalizeTimestamp(primary);
    if (primaryValue > 0) {
      return primaryValue;
    }
    return this.normalizeTimestamp(fallback);
  }

  private normalizeTimestamp(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.floor(value);
  }

  private clonePresentationState(state: HomeWallpaperPresentationState): HomeWallpaperPresentationState {
    return cloneHomeWallpaperPresentationState(state);
  }

}

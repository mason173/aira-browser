import {
  WallpaperAsset,
  WallpaperAssetSource,
  WallpaperMode,
  WallpaperRepositorySnapshot,
  WallpaperSettings
} from '../../common/models/WallpaperModels';

export type WallpaperImageMode = 'bing' | 'custom';
export type WallpaperBingPreviewStatus = 'idle' | 'loading' | 'ready' | 'error';

export interface WallpaperModeOptionViewState {
  id: WallpaperMode;
  title: string;
  summary: string;
  isSelected: boolean;
  isEnabled: boolean;
}

export interface WallpaperImageOptionViewState {
  id: WallpaperImageMode;
  title: string;
  previewPath: string;
  isSelected: boolean;
  isEmpty: boolean;
  isEnabled: boolean;
}

export interface WallpaperSettingsViewState {
  mode: WallpaperMode;
  modeTitle: string;
  themeOption: WallpaperModeOptionViewState;
  imageOptions: WallpaperImageOptionViewState[];
  bingPreviewStatus: WallpaperBingPreviewStatus;
  bingPreviewStatusText: string;
  bingRetryVisible: boolean;
  footerText: string;
}

export class WallpaperSettingsViewModel {
  buildState(
    snapshot: WallpaperRepositorySnapshot,
    bingPreviewStatus: WallpaperBingPreviewStatus = 'idle'
  ): WallpaperSettingsViewState {
    const settings = snapshot.settings;
    const hasBingPreview = this.findImageAsset('bing', snapshot) !== undefined;
    const bingPreviewStatusText = this.buildBingPreviewStatusText(bingPreviewStatus, hasBingPreview);
    const bingRetryVisible = bingPreviewStatus === 'error';
    const footerText = '必应壁纸每天自动检查更新，仅用于 Aira 原生主页；自定义主页和隐私主页不会显示。';
    return {
      mode: settings.mode,
      modeTitle: this.getModeTitle(settings.mode),
      themeOption: this.buildModeOption(
        'theme',
        settings,
        true,
        '首页背景跟随当前主题色，保持中性灰阶'
      ),
      imageOptions: this.buildImageOptions(snapshot),
      bingPreviewStatus: bingPreviewStatus,
      bingPreviewStatusText: bingPreviewStatusText,
      bingRetryVisible: bingRetryVisible,
      footerText: footerText
    };
  }

  buildSettingsWithMode(settings: WallpaperSettings, mode: WallpaperMode): WallpaperSettings {
    return {
      mode: mode,
      bingWallpaperId: settings.bingWallpaperId,
      customWallpaperId: settings.customWallpaperId,
      bing: settings.bing,
      updatedAt: Date.now()
    };
  }

  private buildImageOptions(snapshot: WallpaperRepositorySnapshot): WallpaperImageOptionViewState[] {
    return [
      this.buildImageOption('bing', snapshot),
      this.buildImageOption('custom', snapshot)
    ];
  }

  private buildImageOption(
    mode: WallpaperImageMode,
    snapshot: WallpaperRepositorySnapshot
  ): WallpaperImageOptionViewState {
    const asset = this.findImageAsset(mode, snapshot);
    const previewPath = this.resolvePreviewPath(asset);
    return {
      id: mode,
      title: this.getModeTitle(mode),
      previewPath: previewPath,
      isSelected: snapshot.settings.mode === mode,
      isEmpty: previewPath.trim().length <= 0,
      isEnabled: true
    };
  }

  private findImageAsset(
    mode: WallpaperImageMode,
    snapshot: WallpaperRepositorySnapshot
  ): WallpaperAsset | undefined {
    const source: WallpaperAssetSource = mode;
    const selectedId = mode === 'bing' ?
      (snapshot.settings.bingWallpaperId.trim().length > 0 ?
        snapshot.settings.bingWallpaperId : snapshot.settings.bing.currentAssetId) :
      snapshot.settings.customWallpaperId;
    if (mode === 'custom' && selectedId.trim().length <= 0) {
      return undefined;
    }
    const selected = snapshot.assets.find((asset: WallpaperAsset) => {
      return asset.source === source && asset.id === selectedId && this.resolvePreviewPath(asset).length > 0;
    });
    if (selected !== undefined || mode === 'custom') {
      return selected;
    }
    return snapshot.assets.find((asset: WallpaperAsset) => {
      return asset.source === source && this.resolvePreviewPath(asset).length > 0;
    });
  }

  private resolvePreviewPath(asset: WallpaperAsset | undefined): string {
    if (asset === undefined) {
      return '';
    }
    if (asset.thumbPath.trim().length > 0) {
      return asset.thumbPath;
    }
    return asset.displayPath.trim();
  }

  private buildModeOption(
    mode: WallpaperMode,
    settings: WallpaperSettings,
    enabled: boolean,
    summary: string
  ): WallpaperModeOptionViewState {
    return {
      id: mode,
      title: this.getModeTitle(mode),
      summary: summary,
      isSelected: settings.mode === mode,
      isEnabled: enabled
    };
  }

  private getModeTitle(mode: WallpaperMode): string {
    switch (mode) {
      case 'theme':
        return '跟随主题色';
      case 'bing':
        return '必应壁纸';
      case 'custom':
        return '自定义壁纸';
      default:
        return '跟随主题色';
    }
  }

  private buildBingPreviewStatusText(
    status: WallpaperBingPreviewStatus,
    hasBingPreview: boolean
  ): string {
    if (status === 'loading') {
      return hasBingPreview ? '正在检查必应每日壁纸更新…' : '正在获取必应每日壁纸…';
    }
    if (status === 'error') {
      return hasBingPreview ? '今日壁纸更新失败，正在继续使用缓存。' : '必应壁纸加载失败，请检查网络后重试。';
    }
    return '';
  }

}

import { BrowserHomepageBackdropAppearanceState } from './BackdropAppearanceModels';

export type WallpaperMode = 'theme' | 'bing' | 'custom';

export type WallpaperAssetSource = 'bing' | 'custom' | 'builtin';

export type WallpaperAssetMediaType = 'image';

export type HomeWallpaperPresentationKind = 'default' | 'image';

export type HomeWallpaperForegroundTone = 'lightText' | 'darkText';

export const HOME_WALLPAPER_FOREGROUND_ALGORITHM_VERSION: number = 4;

export interface HomeWallpaperVisibleCropInput {
  viewportWidth: number;
  viewportHeight: number;
  maskOpacity: number;
}

export interface HomeWallpaperForegroundAnalysis {
  foregroundTone: HomeWallpaperForegroundTone;
  contentSignature: string;
  cropSignature: string;
  sampleSignature: string;
  algorithmVersion: number;
}

export interface WallpaperAsset {
  id: string;
  source: WallpaperAssetSource;
  mediaType: WallpaperAssetMediaType;
  originalPath: string;
  displayPath: string;
  thumbPath: string;
  contentSignature: string;
  foregroundTone: HomeWallpaperForegroundTone;
  foregroundToneContentSignature: string;
  foregroundToneCropSignature: string;
  foregroundToneSampleSignature: string;
  foregroundToneAlgorithmVersion: number;
  appearanceLight?: BrowserHomepageBackdropAppearanceState;
  appearanceDark?: BrowserHomepageBackdropAppearanceState;
  width: number;
  height: number;
  mimeType: string;
  byteSize: number;
  title: string;
  attribution: string;
  createdAt: number;
  updatedAt: number;
  isFavorite: boolean;
}

export interface WallpaperBingState {
  currentAssetId: string;
  market: string;
  lastRefreshDay: string;
  lastRefreshAt: number;
  manualRefreshAvailableAt: number;
  failureReason: string;
}

export interface WallpaperSettings {
  mode: WallpaperMode;
  bingWallpaperId: string;
  customWallpaperId: string;
  bing: WallpaperBingState;
  updatedAt: number;
}

export interface HomeWallpaperPresentationState {
  kind: HomeWallpaperPresentationKind;
  mode: WallpaperMode;
  foregroundTone: HomeWallpaperForegroundTone;
  imagePath: string;
  maskOpacity: number;
  assetId: string;
  updatedAt: number;
}

export interface WallpaperRepositorySnapshot {
  settings: WallpaperSettings;
  assets: WallpaperAsset[];
}

export const DEFAULT_WALLPAPER_BING_STATE: WallpaperBingState = {
  currentAssetId: '',
  market: 'zh-CN',
  lastRefreshDay: '',
  lastRefreshAt: 0,
  manualRefreshAvailableAt: 0,
  failureReason: ''
};

export const DEFAULT_WALLPAPER_SETTINGS: WallpaperSettings = {
  mode: 'theme',
  bingWallpaperId: '',
  customWallpaperId: '',
  bing: DEFAULT_WALLPAPER_BING_STATE,
  updatedAt: 0
};

export const DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE: HomeWallpaperPresentationState = {
  kind: 'default',
  mode: DEFAULT_WALLPAPER_SETTINGS.mode,
  foregroundTone: 'darkText',
  imagePath: '',
  maskOpacity: 0,
  assetId: '',
  updatedAt: 0
};

export function cloneHomeWallpaperPresentationState(
  state: HomeWallpaperPresentationState
): HomeWallpaperPresentationState {
  return {
    kind: state.kind,
    mode: state.mode,
    foregroundTone: state.foregroundTone,
    imagePath: state.imagePath,
    maskOpacity: state.maskOpacity,
    assetId: state.assetId,
    updatedAt: state.updatedAt
  };
}

export function isSameHomeWallpaperPresentationState(
  left: HomeWallpaperPresentationState,
  right: HomeWallpaperPresentationState
): boolean {
  return left.kind === right.kind &&
    left.mode === right.mode &&
    left.foregroundTone === right.foregroundTone &&
    left.imagePath === right.imagePath &&
    left.maskOpacity === right.maskOpacity &&
    left.assetId === right.assetId &&
    left.updatedAt === right.updatedAt;
}

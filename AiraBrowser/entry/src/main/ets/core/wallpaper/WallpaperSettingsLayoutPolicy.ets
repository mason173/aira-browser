export type WallpaperSettingsLayoutMode = 'compact' | 'regularPortrait' | 'regularLandscape';
export type WallpaperSettingsSelectionAxis = 'vertical' | 'horizontal';
export type WallpaperSettingsCustomActionPlacement = 'center' | 'end';

export interface WallpaperSettingsLayoutInput {
  containerWidth: number;
  containerHeight: number;
}

export interface WallpaperSettingsLayoutState {
  mode: WallpaperSettingsLayoutMode;
  groupMaxWidth: number;
  cardGap: number;
  previewAspectRatio: number;
  selectionAxis: WallpaperSettingsSelectionAxis;
  customActionPlacement: WallpaperSettingsCustomActionPlacement;
}

const WALLPAPER_SETTINGS_REGULAR_MIN_WIDTH: number = 600;
const WALLPAPER_SETTINGS_PORTRAIT_GROUP_MAX_WIDTH: number = 656;
const WALLPAPER_SETTINGS_LANDSCAPE_GROUP_MAX_WIDTH: number = 820;
const WALLPAPER_SETTINGS_COMPACT_CARD_GAP: number = 12;
const WALLPAPER_SETTINGS_PORTRAIT_CARD_GAP: number = 16;
const WALLPAPER_SETTINGS_LANDSCAPE_CARD_GAP: number = 20;
const WALLPAPER_SETTINGS_COMPACT_PREVIEW_ASPECT_RATIO: number = 9 / 16;
const WALLPAPER_SETTINGS_PORTRAIT_PREVIEW_ASPECT_RATIO: number = 3 / 4;
const WALLPAPER_SETTINGS_LANDSCAPE_MIN_PREVIEW_ASPECT_RATIO: number = 4 / 3;
const WALLPAPER_SETTINGS_LANDSCAPE_MAX_PREVIEW_ASPECT_RATIO: number = 16 / 10;

export class WallpaperSettingsLayoutPolicy {
  resolve(input: WallpaperSettingsLayoutInput): WallpaperSettingsLayoutState {
    const containerWidth = Math.max(1, input.containerWidth);
    const containerHeight = Math.max(1, input.containerHeight);
    const mode = this.resolveMode(containerWidth, containerHeight);
    return {
      mode,
      groupMaxWidth: this.resolveGroupMaxWidth(mode, containerWidth),
      cardGap: this.resolveCardGap(mode),
      previewAspectRatio: this.resolvePreviewAspectRatio(mode, containerWidth, containerHeight),
      selectionAxis: mode === 'compact' ? 'vertical' : 'horizontal',
      customActionPlacement: mode === 'regularLandscape' ? 'end' : 'center'
    };
  }

  buildRenderKey(state: WallpaperSettingsLayoutState): string {
    return [
      state.mode,
      Math.round(state.groupMaxWidth),
      Math.round(state.cardGap),
      Math.round(state.previewAspectRatio * 1000),
      state.selectionAxis,
      state.customActionPlacement
    ].join(':');
  }

  private resolveMode(containerWidth: number, containerHeight: number): WallpaperSettingsLayoutMode {
    if (containerWidth < WALLPAPER_SETTINGS_REGULAR_MIN_WIDTH) {
      return 'compact';
    }
    return containerHeight >= containerWidth ? 'regularPortrait' : 'regularLandscape';
  }

  private resolveGroupMaxWidth(mode: WallpaperSettingsLayoutMode, containerWidth: number): number {
    if (mode === 'regularLandscape') {
      return WALLPAPER_SETTINGS_LANDSCAPE_GROUP_MAX_WIDTH;
    }
    if (mode === 'regularPortrait') {
      return WALLPAPER_SETTINGS_PORTRAIT_GROUP_MAX_WIDTH;
    }
    return containerWidth;
  }

  private resolveCardGap(mode: WallpaperSettingsLayoutMode): number {
    if (mode === 'regularLandscape') {
      return WALLPAPER_SETTINGS_LANDSCAPE_CARD_GAP;
    }
    if (mode === 'regularPortrait') {
      return WALLPAPER_SETTINGS_PORTRAIT_CARD_GAP;
    }
    return WALLPAPER_SETTINGS_COMPACT_CARD_GAP;
  }

  private resolvePreviewAspectRatio(
    mode: WallpaperSettingsLayoutMode,
    containerWidth: number,
    containerHeight: number
  ): number {
    if (mode === 'regularLandscape') {
      return Math.min(
        WALLPAPER_SETTINGS_LANDSCAPE_MAX_PREVIEW_ASPECT_RATIO,
        Math.max(
          WALLPAPER_SETTINGS_LANDSCAPE_MIN_PREVIEW_ASPECT_RATIO,
          containerWidth / containerHeight
        )
      );
    }
    if (mode === 'regularPortrait') {
      return WALLPAPER_SETTINGS_PORTRAIT_PREVIEW_ASPECT_RATIO;
    }
    return WALLPAPER_SETTINGS_COMPACT_PREVIEW_ASPECT_RATIO;
  }
}

import {
  HomeWallpaperPresentationState
} from '../../common/models/WallpaperModels';

export interface HomeWallpaperInteractionColorState {
  pressedBackgroundColor: ResourceColor;
  pressedBackdropBlurRadius: number;
}

const HOME_IMAGE_PRESSED_LIGHT_OVERLAY: string = '#18FFFFFF';
const HOME_IMAGE_PRESSED_DARK_OVERLAY: string = '#12000000';

export class HomeWallpaperInteractionColorViewModel {
  resolveInteractionColors(
    wallpaperState: HomeWallpaperPresentationState,
    themedPressedBackgroundColor: ResourceColor
  ): HomeWallpaperInteractionColorState {
    if (wallpaperState.kind === 'image') {
      return {
        pressedBackgroundColor: wallpaperState.foregroundTone === 'darkText'
          ? HOME_IMAGE_PRESSED_DARK_OVERLAY
          : HOME_IMAGE_PRESSED_LIGHT_OVERLAY,
        pressedBackdropBlurRadius: 0
      };
    }
    return {
      pressedBackgroundColor: themedPressedBackgroundColor,
      pressedBackdropBlurRadius: 0
    };
  }
}

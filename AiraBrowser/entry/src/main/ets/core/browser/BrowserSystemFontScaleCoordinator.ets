import { Configuration } from '@kit.AbilityKit';
import {
  BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT,
  BrowserWebTextZoomViewModel
} from './BrowserWebTextZoomViewModel';

export const BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY: string = 'browserSystemFontSizeScale';

export class BrowserSystemFontScaleCoordinator {
  private currentScale: number = BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT;
  private textZoomViewModel: BrowserWebTextZoomViewModel = new BrowserWebTextZoomViewModel();

  syncInitial(config: Configuration): number {
    return this.syncScale(config.fontSizeScale);
  }

  handleConfigurationUpdate(config: Configuration): boolean {
    const previousScale = this.currentScale;
    this.syncScale(config.fontSizeScale);
    return previousScale !== this.currentScale;
  }

  private syncScale(scale: number | undefined): number {
    this.currentScale = this.textZoomViewModel.normalizeSystemFontSizeScale(
      scale ?? BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT
    );
    AppStorage.setOrCreate(BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY, this.currentScale);
    return this.currentScale;
  }
}

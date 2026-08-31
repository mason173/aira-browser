import { window, display } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { BrowserDeviceFormFactorInput } from '../../core/browser/BrowserDeviceFormFactorCoordinator';

const LARGE_SCREEN_PROFILES_ENABLED: boolean = false;
const LARGE_SCREEN_SHELL_AVAILABLE: boolean = false;
const DESKTOP_WINDOW_HOST_AVAILABLE: boolean = false;
const DESKTOP_POPUP_WINDOW_HOST_AVAILABLE: boolean = false;

export class BrowserDeviceFormFactorInputService {
  async resolveWindowOpenInput(): Promise<BrowserDeviceFormFactorInput> {
    return {
      platformDeviceType: this.resolvePlatformDeviceType(),
      windowWidthVp: await this.resolveCurrentWindowWidthVp(),
      largeScreenProfilesEnabled: LARGE_SCREEN_PROFILES_ENABLED,
      largeScreenShellAvailable: LARGE_SCREEN_SHELL_AVAILABLE,
      desktopWindowHostAvailable: DESKTOP_WINDOW_HOST_AVAILABLE,
      desktopPopupWindowHostAvailable: DESKTOP_POPUP_WINDOW_HOST_AVAILABLE
    };
  }

  private resolvePlatformDeviceType(): string {
    try {
      return deviceInfo.deviceType.trim();
    } catch (_error) {
      return '';
    }
  }

  private async resolveCurrentWindowWidthVp(): Promise<number | undefined> {
    if (!AppRuntimeContext.hasUIAbilityContext()) {
      return undefined;
    }
    try {
      const mainWindow = await window.getLastWindow(AppRuntimeContext.getUIAbilityContext());
      const properties = mainWindow.getWindowProperties();
      const drawableWidthPx = this.normalizePositiveNumber(properties.drawableRect.width);
      const windowWidthPx = this.normalizePositiveNumber(properties.windowRect.width);
      return this.pxToVp(drawableWidthPx > 0 ? drawableWidthPx : windowWidthPx);
    } catch (_error) {
      return undefined;
    }
  }

  private pxToVp(valuePx: number): number | undefined {
    if (valuePx <= 0) {
      return undefined;
    }
    const densityPixels = this.resolveDensityPixels();
    if (densityPixels <= 0) {
      return undefined;
    }
    return Math.max(1, Math.round(valuePx / densityPixels));
  }

  private resolveDensityPixels(): number {
    try {
      return this.normalizePositiveNumber(display.getDefaultDisplaySync().densityPixels);
    } catch (_error) {
      return 0;
    }
  }

  private normalizePositiveNumber(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return value;
  }
}

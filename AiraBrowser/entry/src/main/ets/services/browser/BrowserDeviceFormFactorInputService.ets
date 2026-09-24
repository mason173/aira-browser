import { deviceInfo } from '@kit.BasicServicesKit';
import { BrowserDeviceFormFactorInput } from '../../core/browser/BrowserDeviceFormFactorCoordinator';

const LARGE_SCREEN_PROFILES_ENABLED: boolean = false;
const LARGE_SCREEN_SHELL_AVAILABLE: boolean = false;
const DESKTOP_WINDOW_HOST_AVAILABLE: boolean = false;
const DESKTOP_POPUP_WINDOW_HOST_AVAILABLE: boolean = false;

export class BrowserDeviceFormFactorInputService {
  // Window width is intentionally omitted. onWindowNew must call setWebController before the
  // callback returns; awaiting the window size lets PC ArkWeb materialize a chromeless popup.
  // Width does not change the open action while the desktop window hosts stay unavailable.
  resolveWindowOpenInputSync(): BrowserDeviceFormFactorInput {
    return {
      platformDeviceType: this.resolvePlatformDeviceType(),
      windowWidthVp: undefined,
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
}

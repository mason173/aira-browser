import { window } from '@kit.ArkUI';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserDeviceFormFactor,
  BrowserDeviceFormFactorCoordinator
} from '../../core/browser/BrowserDeviceFormFactorCoordinator';
import { BrowserWindowPresentationProfileInputService } from '../browser/BrowserWindowPresentationProfileInputService';

export type CustomHomepageShellFamily = 'phone' | 'large_screen';

export interface CustomHomepageNativeEnvironmentState {
  formFactor: BrowserDeviceFormFactor;
  shellFamily: CustomHomepageShellFamily;
}

export interface CustomHomepageWindowViewportState {
  width: number;
  height: number;
}

export class CustomHomepageEnvironmentService {
  private formFactorCoordinator: BrowserDeviceFormFactorCoordinator = new BrowserDeviceFormFactorCoordinator();
  private windowInputService: BrowserWindowPresentationProfileInputService =
    new BrowserWindowPresentationProfileInputService();

  resolveNativeState(): CustomHomepageNativeEnvironmentState {
    // Unified device detection: device type first, then display-width fallback
    // (≥ 840vp ⇒ tablet), via the same resolveShellEligibility the large-screen
    // shell uses. Keeps this in sync with the shell and stops an emulator that
    // reports deviceType "default" from being misclassified as a phone.
    const formFactor = this.formFactorCoordinator.resolveShellEligibility({
      platformDeviceType: this.windowInputService.resolvePlatformDeviceType(),
      windowWidthVp: this.windowInputService.resolveDisplayWidthVp()
    }).detectedFormFactor;
    return {
      formFactor: formFactor,
      shellFamily: formFactor === 'tablet' || formFactor === 'two_in_one' || formFactor === 'pc'
        ? 'large_screen'
        : 'phone'
    };
  }

  async resolveCurrentWindowViewport(): Promise<CustomHomepageWindowViewportState | undefined> {
    if (!AppRuntimeContext.hasUIAbilityContext()) {
      return undefined;
    }
    try {
      const mainWindow = await window.getLastWindow(AppRuntimeContext.getUIAbilityContext());
      const input = this.windowInputService.resolve(mainWindow);
      const width = input.windowWidthVp ?? 0;
      const height = input.windowHeightVp ?? 0;
      if (width <= 0 || height <= 0) {
        return undefined;
      }
      return { width: width, height: height };
    } catch (_error) {
      return undefined;
    }
  }
}

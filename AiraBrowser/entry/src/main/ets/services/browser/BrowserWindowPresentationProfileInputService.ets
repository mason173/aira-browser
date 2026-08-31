import { display, window } from '@kit.ArkUI';
import { inputDevice } from '@kit.InputKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { BrowserWindowPresentationProfileInput } from '../../core/browser/BrowserWindowPresentationProfile';
import {
  BrowserLargeScreenWindowFactsInput,
  BrowserLargeScreenWindowMode
} from '../../core/browser/BrowserLargeScreenWindowFactsViewModel';
import { BrowserWindowAvoidAreaInsets } from '../../core/browser/BrowserWindowAvoidAreaCoordinator';
import { BrowserFoldPresentationStateReader } from '../../core/browser/BrowserFoldPresentationStateReader';

interface BrowserWindowFactsResolution {
  availableWidthVp: number;
  availableHeightVp: number;
  titleButtonWidthVp: number;
  titleButtonHeightVp: number;
  windowMode: BrowserLargeScreenWindowMode;
  dragSupported: boolean;
}

interface BrowserInputFactsResolution {
  pointerAvailable: boolean;
  physicalKeyboardAvailable: boolean;
}

interface BrowserTitleButtonRectFacts {
  right: number;
  top: number;
  width: number;
  height: number;
}

/**
 * Platform adapter for the presentation policy. It reads facts from the
 * concrete WindowStage window; it never decides which Shell Family wins.
 */
export class BrowserWindowPresentationProfileInputService {
  private readonly foldStateReader: BrowserFoldPresentationStateReader =
    new BrowserFoldPresentationStateReader();

  resolve(mainWindow: window.Window): BrowserWindowPresentationProfileInput {
    try {
      const properties = mainWindow.getWindowProperties();
      const rect = properties.windowRect;
      const drawableRect = properties.drawableRect;
      return {
        platformDeviceType: this.resolvePlatformDeviceType(),
        windowWidthVp: this.normalizeDimension(
          drawableRect.width > 0 ? drawableRect.width : rect.width
        ),
        windowHeightVp: this.normalizeDimension(
          drawableRect.height > 0 ? drawableRect.height : rect.height
        )
      };
    } catch (_error) {
      return {
        platformDeviceType: this.resolvePlatformDeviceType(),
        windowWidthVp: 0,
        windowHeightVp: 0
      };
    }
  }

  /**
   * Reads the platform facts consumed by the Large-Screen presentation owner.
   *
   * This is intentionally asynchronous because input-device enumeration is a
   * platform query. The service reports false/empty capabilities when a query
   * is unsupported; it never infers a mouse, keyboard, or drag capability from
   * the device form factor.
   */
  async resolveLargeScreenFacts(
    mainWindow: window.Window,
    avoidAreaInsets: BrowserWindowAvoidAreaInsets,
    windowTitleBarIntegrated: boolean = false
  ): Promise<BrowserLargeScreenWindowFactsInput> {
    const windowFacts = this.resolveWindowFacts(mainWindow);
    const inputFacts = await this.resolveInputFacts();
    return {
      availableWidthVp: windowFacts.availableWidthVp,
      availableHeightVp: windowFacts.availableHeightVp,
      titleButtonWidthVp: windowFacts.titleButtonWidthVp,
      titleButtonHeightVp: windowFacts.titleButtonHeightVp,
      windowTitleBarIntegrated: windowTitleBarIntegrated,
      safeTopInsetVp: avoidAreaInsets.topInsetVp,
      safeBottomInsetVp: avoidAreaInsets.bottomInsetVp,
      safeLeftInsetVp: avoidAreaInsets.leftInsetVp,
      safeRightInsetVp: avoidAreaInsets.rightInsetVp,
      windowMode: windowFacts.windowMode,
      pointerAvailable: inputFacts.pointerAvailable,
      physicalKeyboardAvailable: inputFacts.physicalKeyboardAvailable,
      dragSupported: windowFacts.dragSupported,
      keyboardHintsAvailable: inputFacts.physicalKeyboardAvailable
    };
  }

  private resolveWindowFacts(mainWindow: window.Window): BrowserWindowFactsResolution {
    try {
      const properties = mainWindow.getWindowProperties();
      const drawableRect = properties.drawableRect;
      const rect = properties.windowRect;
      const titleButtonRect = this.resolveTitleButtonRect(mainWindow);
      return {
        availableWidthVp: this.normalizeDimension(
          drawableRect.width > 0 ? drawableRect.width : rect.width
        ),
        availableHeightVp: this.normalizeDimension(
          drawableRect.height > 0 ? drawableRect.height : rect.height
        ),
        // Huawei's free-window adaptation guide treats TitleButtonRect values
        // as vp, unlike drawableRect/windowRect values which are px.
        titleButtonWidthVp: this.normalizeVpDimension(titleButtonRect.width),
        titleButtonHeightVp: this.normalizeVpDimension(titleButtonRect.height),
        windowMode: this.resolveWindowMode(mainWindow, properties.type),
        dragSupported: this.resolveDragSupported(mainWindow)
      };
    } catch (_error) {
      return {
        availableWidthVp: 0,
        availableHeightVp: 0,
        titleButtonWidthVp: 0,
        titleButtonHeightVp: 0,
        windowMode: 'full',
        dragSupported: false
      };
    }
  }

  private resolveTitleButtonRect(mainWindow: window.Window): BrowserTitleButtonRectFacts {
    try {
      const rect = mainWindow.getTitleButtonRect();
      return {
        right: rect.right,
        top: rect.top,
        width: rect.width,
        height: rect.height
      };
    } catch (_error) {
      return { right: 0, top: 0, width: 0, height: 0 };
    }
  }

  private resolveWindowMode(mainWindow: window.Window, windowType: window.WindowType): BrowserLargeScreenWindowMode {
    try {
      if (mainWindow.isInFreeWindowMode()) {
        return 'free_window';
      }
    } catch (_error) {
      // Some devices do not expose free-window state. Keep the conservative
      // main-window classification below instead of inventing a mode.
    }
    if (windowType !== window.WindowType.TYPE_MAIN) {
      return 'subwindow';
    }
    return 'full';
  }

  private resolveDragSupported(mainWindow: window.Window): boolean {
    try {
      return mainWindow.isReceiveDragEventEnabled() === true;
    } catch (_error) {
      return false;
    }
  }

  private async resolveInputFacts(): Promise<BrowserInputFactsResolution> {
    try {
      const deviceIds = await inputDevice.getDeviceList();
      const devices = await Promise.all(deviceIds.map((deviceId: number): Promise<inputDevice.InputDeviceData> => {
        return inputDevice.getDeviceInfo(deviceId);
      }));
      const pointerAvailable = devices.some((device: inputDevice.InputDeviceData): boolean => {
        return device.sources.indexOf('mouse') >= 0 || device.sources.indexOf('touchpad') >= 0;
      });
      const physicalKeyboardAvailable = devices.some((device: inputDevice.InputDeviceData): boolean => {
        return device.sources.indexOf('keyboard') >= 0 && device.isVirtual !== true;
      });
      return {
        pointerAvailable: pointerAvailable,
        physicalKeyboardAvailable: physicalKeyboardAvailable
      };
    } catch (_error) {
      return {
        pointerAvailable: false,
        physicalKeyboardAvailable: false
      };
    }
  }

  resolvePlatformDeviceType(): string {
    try {
      return deviceInfo.deviceType.trim();
    } catch (_error) {
      return '';
    }
  }

  resolveFoldableDevice(): boolean {
    try {
      return this.foldStateReader.read().capabilityConfirmed;
    } catch (_error) {
      return false;
    }
  }

  /**
   * Current display width in vp, read without a window handle. Used as the
   * device-form-factor width fallback when the platform device type is
   * unrecognized (notably emulators, which report "default").
   */
  resolveDisplayWidthVp(): number {
    try {
      return this.normalizeDimension(display.getDefaultDisplaySync().width);
    } catch (_error) {
      return 0;
    }
  }

  private normalizeDimension(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    let densityPixels = 1;
    try {
      const resolvedDensity = display.getDefaultDisplaySync().densityPixels;
      if (Number.isFinite(resolvedDensity) && resolvedDensity > 0) {
        densityPixels = resolvedDensity;
      }
    } catch (_error) {
    }
    return Math.max(1, Math.round(value / densityPixels));
  }

  private normalizeVpDimension(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.max(1, Math.round(value));
  }
}

export type BrowserDeviceFormFactor =
  'phone' |
  'tablet' |
  'two_in_one' |
  'pc' |
  'unknown';

export type BrowserDeviceUiMode =
  'phone_ui' |
  'pc_ui';

export type BrowserWindowOpenSurface =
  'mobile_managed_tab' |
  'desktop_recent_window_tab' |
  'desktop_popup_window';

export interface BrowserDeviceFormFactorInput {
  platformDeviceType?: string;
  windowWidthVp?: number;
  largeScreenProfilesEnabled?: boolean;
  largeScreenShellAvailable?: boolean;
  desktopWindowHostAvailable?: boolean;
  desktopPopupWindowHostAvailable?: boolean;
}

export interface BrowserDeviceFormFactorProfile {
  detectedFormFactor: BrowserDeviceFormFactor;
  effectiveFormFactor: BrowserDeviceFormFactor;
  uiMode: BrowserDeviceUiMode;
  huaweiPcUiEligible: boolean;
  largeScreenProfilesEnabled: boolean;
  largeScreenProfilesActive: boolean;
  largeScreenShellAvailable: boolean;
  desktopWindowHostAvailable: boolean;
  desktopPopupWindowHostAvailable: boolean;
  supportsDesktopTabStrip: boolean;
  supportsMultipleBrowserWindows: boolean;
  supportsDetachedPopupWindow: boolean;
  preferRecentDesktopWindowForOrdinaryTabs: boolean;
  preferPopupWindowForAlerts: boolean;
  defaultWindowOpenSurface: BrowserWindowOpenSurface;
  alertWindowOpenSurface: BrowserWindowOpenSurface;
  summaryLine: string;
}

export interface BrowserShellEligibilityInput {
  platformDeviceType?: string;
  windowWidthVp?: number;
}

export interface BrowserShellEligibility {
  detectedFormFactor: BrowserDeviceFormFactor;
  huaweiPcUiEligible: boolean;
}

const DEFAULT_LARGE_SCREEN_PROFILES_ENABLED: boolean = false;
const LARGE_SCREEN_WIDTH_VP: number = 840;

export class BrowserDeviceFormFactorCoordinator {
  // Device-type-only classification with NO width fallback. Kept private on
  // purpose: callers must go through resolveShellEligibility /
  // resolveWindowOpenProfile (which add the ≥840vp width fallback) so device
  // detection stays unified and emulators reporting "default" are not
  // misclassified as phones.
  private resolvePlatformFormFactor(platformDeviceType: string): BrowserDeviceFormFactor {
    return this.normalizePlatformDeviceType(platformDeviceType);
  }

  /**
   * Resolves only the device/window facts needed by the Browser Shell Family
   * policy. Window-open capability decisions stay behind resolveWindowOpenProfile().
   */
  resolveShellEligibility(input: BrowserShellEligibilityInput = {}): BrowserShellEligibility {
    const detectedFormFactor = this.resolveDetectedFormFactor(
      input.platformDeviceType ?? '',
      input.windowWidthVp
    );
    return {
      detectedFormFactor: detectedFormFactor,
      huaweiPcUiEligible: this.isHuaweiPcUiEligible(detectedFormFactor, input.windowWidthVp)
    };
  }

  resolveWindowOpenProfile(input: BrowserDeviceFormFactorInput = {}): BrowserDeviceFormFactorProfile {
    const detectedFormFactor = this.resolveDetectedFormFactor(
      input.platformDeviceType ?? '',
      input.windowWidthVp
    );
    const huaweiPcUiEligible = this.isHuaweiPcUiEligible(detectedFormFactor, input.windowWidthVp);
    // Huawei maps tablet/2in1 into PC UI; keep Aira's large-screen branch dormant until the shell exists.
    const largeScreenProfilesEnabled = input.largeScreenProfilesEnabled ?? DEFAULT_LARGE_SCREEN_PROFILES_ENABLED;
    const largeScreenShellAvailable = input.largeScreenShellAvailable === true;
    const desktopWindowHostAvailable = input.desktopWindowHostAvailable === true;
    const desktopPopupWindowHostAvailable = input.desktopPopupWindowHostAvailable === true;
    const largeScreenProfilesActive = largeScreenProfilesEnabled && largeScreenShellAvailable && huaweiPcUiEligible;
    const effectiveFormFactor: BrowserDeviceFormFactor = largeScreenProfilesActive ? detectedFormFactor : 'phone';
    const uiMode: BrowserDeviceUiMode = largeScreenProfilesActive ? 'pc_ui' : 'phone_ui';
    const supportsDesktopTabStrip: boolean = largeScreenProfilesActive && uiMode === 'pc_ui';
    const supportsMultipleBrowserWindows: boolean = supportsDesktopTabStrip && desktopWindowHostAvailable;
    const supportsDetachedPopupWindow: boolean = supportsDesktopTabStrip && desktopPopupWindowHostAvailable;
    const defaultWindowOpenSurface: BrowserWindowOpenSurface =
      supportsMultipleBrowserWindows ? 'desktop_recent_window_tab' : 'mobile_managed_tab';
    const alertWindowOpenSurface: BrowserWindowOpenSurface =
      supportsDetachedPopupWindow ? 'desktop_popup_window' : defaultWindowOpenSurface;

    return {
      detectedFormFactor: detectedFormFactor,
      effectiveFormFactor: effectiveFormFactor,
      uiMode: uiMode,
      huaweiPcUiEligible: huaweiPcUiEligible,
      largeScreenProfilesEnabled: largeScreenProfilesEnabled,
      largeScreenProfilesActive: largeScreenProfilesActive,
      largeScreenShellAvailable: largeScreenShellAvailable,
      desktopWindowHostAvailable: desktopWindowHostAvailable,
      desktopPopupWindowHostAvailable: desktopPopupWindowHostAvailable,
      supportsDesktopTabStrip: supportsDesktopTabStrip,
      supportsMultipleBrowserWindows: supportsMultipleBrowserWindows,
      supportsDetachedPopupWindow: supportsDetachedPopupWindow,
      preferRecentDesktopWindowForOrdinaryTabs: supportsMultipleBrowserWindows,
      preferPopupWindowForAlerts: supportsDetachedPopupWindow,
      defaultWindowOpenSurface: defaultWindowOpenSurface,
      alertWindowOpenSurface: alertWindowOpenSurface,
      summaryLine: this.buildSummaryLine(
        detectedFormFactor,
        effectiveFormFactor,
        uiMode,
        huaweiPcUiEligible,
        largeScreenProfilesEnabled,
        largeScreenProfilesActive,
        largeScreenShellAvailable,
        desktopWindowHostAvailable,
        desktopPopupWindowHostAvailable,
        defaultWindowOpenSurface,
        alertWindowOpenSurface
      )
    };
  }

  private resolveDetectedFormFactor(platformDeviceType: string, windowWidthVp: number | undefined): BrowserDeviceFormFactor {
    const platformFormFactor = this.resolvePlatformFormFactor(platformDeviceType);
    if (platformFormFactor !== 'unknown') {
      return platformFormFactor;
    }
    const normalizedWindowWidthVp = windowWidthVp ?? 0;
    if (normalizedWindowWidthVp >= LARGE_SCREEN_WIDTH_VP) {
      return 'tablet';
    }
    return 'phone';
  }

  private normalizePlatformDeviceType(platformDeviceType: string): BrowserDeviceFormFactor {
    const normalized = platformDeviceType.trim().toLowerCase();
    if (normalized === 'phone') {
      return 'phone';
    }
    if (normalized === 'tablet') {
      return 'tablet';
    }
    if (normalized === '2in1' || normalized === 'two_in_one' || normalized === 'two-in-one') {
      return 'two_in_one';
    }
    if (normalized === 'pc' || normalized === 'desktop') {
      return 'pc';
    }
    return 'unknown';
  }

  private isHuaweiPcUiEligible(formFactor: BrowserDeviceFormFactor, windowWidthVp: number | undefined): boolean {
    if (formFactor === 'tablet' || formFactor === 'two_in_one' || formFactor === 'pc') {
      return true;
    }
    return (windowWidthVp ?? 0) >= LARGE_SCREEN_WIDTH_VP;
  }

  private buildSummaryLine(
    detectedFormFactor: BrowserDeviceFormFactor,
    effectiveFormFactor: BrowserDeviceFormFactor,
    uiMode: BrowserDeviceUiMode,
    huaweiPcUiEligible: boolean,
    largeScreenProfilesEnabled: boolean,
    largeScreenProfilesActive: boolean,
    largeScreenShellAvailable: boolean,
    desktopWindowHostAvailable: boolean,
    desktopPopupWindowHostAvailable: boolean,
    defaultWindowOpenSurface: BrowserWindowOpenSurface,
    alertWindowOpenSurface: BrowserWindowOpenSurface
  ): string {
    return `detected=${detectedFormFactor} effective=${effectiveFormFactor} ui=${uiMode} ` +
      `pcEligible=${huaweiPcUiEligible} enabled=${largeScreenProfilesEnabled} active=${largeScreenProfilesActive} ` +
      `shell=${largeScreenShellAvailable} windowHost=${desktopWindowHostAvailable} ` +
      `popupHost=${desktopPopupWindowHostAvailable} ` +
      `defaultSurface=${defaultWindowOpenSurface} alertSurface=${alertWindowOpenSurface}`;
  }
}

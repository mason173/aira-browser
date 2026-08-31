import { deviceInfo } from '@kit.BasicServicesKit';

export type BrowserPrivateOpenTarget = 'new_window' | 'current_window_tab';

/**
 * Owns the product boundary between desktop private windows and managed tabs.
 * Large-screen presentation alone is not enough: HarmonyOS tablets use the
 * large-screen shell but intentionally remain single-window for this flow.
 */
export class BrowserPrivateWindowPolicyService {
  resolveTarget(): BrowserPrivateOpenTarget {
    const deviceType = this.resolveDeviceType();
    return this.isDesktopWindowDevice(deviceType) ? 'new_window' : 'current_window_tab';
  }

  private resolveDeviceType(): string {
    try {
      return deviceInfo.deviceType.trim().toLowerCase();
    } catch (_error) {
      return '';
    }
  }

  private isDesktopWindowDevice(deviceType: string): boolean {
    return deviceType === 'pc' ||
      deviceType === 'desktop' ||
      deviceType === '2in1' ||
      deviceType === 'two_in_one' ||
      deviceType === 'two-in-one';
  }
}

import { BrowserDeviceFormFactor } from './BrowserDeviceFormFactorCoordinator';
import { BrowserShellFamily } from './BrowserWindowPresentationProfile';
import { BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT } from './BrowserWebTextZoomViewModel';

/**
 * Which shell families follow the system font size, and by how much.
 *
 * `AppScope/app.json5` publishes `fontSizeScale: followSystem`, so the framework
 * scales the app with the user's system accessibility setting. That is correct
 * for the phone shell. The PC shell is a dense, fixed-height chrome — a tab strip
 * plus two toolbar rows — paired with a desktop-sized viewport, and a system
 * scale up to 3.2x overflows those rows and inflates page text far past what the
 * wider window needs. The PC shell therefore pins BOTH its own UI text and its
 * content text (web pages and reader content) to the app default, and ignores the
 * system setting. A native cockpit keeps following the system scale even on the
 * wide shell, so driving text can stay at the seat-design body size.
 *
 * The distinction that stays intact is explicit user zoom versus the system
 * setting. A user's own web text zoom is a deliberate per-page action and always
 * applies; only the system font size contribution is dropped on PC.
 */
export const BROWSER_FONT_SCALE_PINNED: number = BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT;

export class BrowserShellFontScalePolicy {
  /** Whether this shell honors the system font size at all. */
  followsSystemFontScale(
    shellFamily: BrowserShellFamily,
    formFactor: BrowserDeviceFormFactor = 'unknown'
  ): boolean {
    // A cockpit display is read at a glance while driving. Pinning the large
    // shell to the app default is a PC chrome workaround and would drop the
    // seat-design body-text floor.
    if (formFactor === 'car') {
      return true;
    }
    return shellFamily !== 'large_screen';
  }

  /** Scale for the browser's own ArkUI text. */
  resolveAppUiScale(
    systemScale: number,
    shellFamily: BrowserShellFamily,
    formFactor: BrowserDeviceFormFactor = 'unknown'
  ): number {
    return this.followsSystemFontScale(shellFamily, formFactor) ? this.normalize(systemScale) : BROWSER_FONT_SCALE_PINNED;
  }

  /** Scale for page/reader content (web text zoom and reading-surface metrics). */
  resolveContentScale(
    systemScale: number,
    shellFamily: BrowserShellFamily,
    formFactor: BrowserDeviceFormFactor = 'unknown'
  ): number {
    return this.followsSystemFontScale(shellFamily, formFactor) ? this.normalize(systemScale) : BROWSER_FONT_SCALE_PINNED;
  }

  private normalize(systemScale: number): number {
    return Number.isFinite(systemScale) && systemScale > 0 ? systemScale : BROWSER_FONT_SCALE_PINNED;
  }
}

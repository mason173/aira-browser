import { Configuration, common } from '@kit.AbilityKit';
import {
  BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT,
  BrowserWebTextZoomViewModel
} from './BrowserWebTextZoomViewModel';
import { BrowserDeviceFormFactor } from './BrowserDeviceFormFactorCoordinator';
import { BrowserShellFamily } from './BrowserWindowPresentationProfile';
import {
  BROWSER_FONT_SCALE_PINNED,
  BrowserShellFontScalePolicy
} from './BrowserShellFontScalePolicy';

export const BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY: string = 'browserSystemFontSizeScale';
/**
 * The font scale content should follow on the current shell. Equals the system
 * scale on the phone shell and the app default on the PC shell, so the web text
 * zoom and the reading surface can read one already-shell-aware value.
 */
export const BROWSER_CONTENT_FONT_SIZE_SCALE_STORAGE_KEY: string = 'browserContentFontSizeScale';
export { BROWSER_FONT_SCALE_PINNED };

/**
 * Owns the system font scale and the per-shell-family scales derived from it.
 *
 * The raw system scale is still recorded because it is a platform fact, but the
 * shell decides how much of it reaches the app: the PC shell pins its UI and its
 * content to the app default so the system accessibility setting cannot overflow
 * the dense large-screen chrome or inflate page text. See BrowserShellFontScalePolicy.
 */
export class BrowserSystemFontScaleCoordinator {
  private currentScale: number = BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT;
  private currentShellFamily: BrowserShellFamily = 'phone';
  private currentFormFactor: BrowserDeviceFormFactor = 'unknown';
  private appliedUiScale: number = BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT;
  private appliedUiScaleInitialized: boolean = false;
  private textZoomViewModel: BrowserWebTextZoomViewModel = new BrowserWebTextZoomViewModel();
  private fontScalePolicy: BrowserShellFontScalePolicy = new BrowserShellFontScalePolicy();

  syncInitial(config: Configuration): number {
    return this.syncScale(config.fontSizeScale);
  }

  handleConfigurationUpdate(config: Configuration): boolean {
    const previousScale = this.currentScale;
    this.syncScale(config.fontSizeScale);
    const changed = previousScale !== this.currentScale;
    if (changed) {
      // The framework auto-applies `followSystem` to the app when the system
      // setting changes, so the remembered UI scale is stale: forget it and let
      // the next reconcile re-assert the shell-family pin (a no-op on the phone
      // shell, and the PC shell's default again on large screen).
      this.appliedUiScaleInitialized = false;
    }
    return changed;
  }

  /** System font scale exactly as the platform reports it. */
  resolveSystemScale(): number {
    return this.currentScale;
  }

  /** Scale the current shell's content should follow. */
  resolveContentScale(): number {
    return this.fontScalePolicy.resolveContentScale(this.currentScale, this.currentShellFamily, this.currentFormFactor);
  }

  /** Scale the current shell's native UI text should follow. */
  resolveAppUiScale(): number {
    return this.fontScalePolicy.resolveAppUiScale(
      this.currentScale,
      this.currentShellFamily,
      this.currentFormFactor
    );
  }

  /**
   * Applies the shell-family font policy: pins the native UI scale on the
   * application and publishes the content scale for content consumers. Returns
   * true when the applied native UI scale changed, so callers can skip redundant
   * work. The content scale is republished on every call because a shell-family
   * switch must reach content consumers even when the numeric UI scale is equal.
   */
  applyForShellFamily(
    applicationContext: common.ApplicationContext,
    shellFamily: BrowserShellFamily,
    formFactor: BrowserDeviceFormFactor = 'unknown'
  ): boolean {
    const shellChanged = this.currentShellFamily !== shellFamily || this.currentFormFactor !== formFactor;
    this.currentShellFamily = shellFamily;
    this.currentFormFactor = formFactor;
    const nextUiScale = this.resolveAppUiScale();
    this.publishContentScale();
    if (!shellChanged && this.appliedUiScaleInitialized && this.appliedUiScale === nextUiScale) {
      return false;
    }
    applicationContext.setFontSizeScale(nextUiScale);
    this.appliedUiScale = nextUiScale;
    this.appliedUiScaleInitialized = true;
    return true;
  }

  /** Re-publishes the content scale, skipping an unchanged value so subscribers do not reload. */
  private publishContentScale(): void {
    const nextScale = this.resolveContentScale();
    const currentScale = Number(AppStorage.get(BROWSER_CONTENT_FONT_SIZE_SCALE_STORAGE_KEY));
    if (Number.isFinite(currentScale) && currentScale === nextScale) {
      return;
    }
    AppStorage.setOrCreate(BROWSER_CONTENT_FONT_SIZE_SCALE_STORAGE_KEY, nextScale);
  }

  private syncScale(scale: number | undefined): number {
    this.currentScale = this.textZoomViewModel.normalizeSystemFontSizeScale(
      scale ?? BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT
    );
    AppStorage.setOrCreate(BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY, this.currentScale);
    this.publishContentScale();
    return this.currentScale;
  }
}

export const BROWSER_WEB_TEXT_ZOOM_DEFAULT_RATIO: number = 100;
export const BROWSER_WEB_TEXT_ZOOM_MIN_RATIO: number = 50;
export const BROWSER_WEB_TEXT_ZOOM_MAX_RATIO: number = 200;
export const BROWSER_WEB_EFFECTIVE_TEXT_ZOOM_MAX_RATIO: number = 320;
export const BROWSER_WEB_TEXT_ZOOM_STEP: number = 10;
export const BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT: number = 1;
export const BROWSER_SYSTEM_FONT_SIZE_SCALE_MIN: number = 0.5;
export const BROWSER_SYSTEM_FONT_SIZE_SCALE_MAX: number = 3.2;

export type BrowserWebTextZoomAction = 'decrease' | 'increase' | 'reset';

export interface BrowserWebTextZoomState {
  ratio: number;
  percentLabel: string;
  canDecrease: boolean;
  canIncrease: boolean;
}

export interface BrowserWebTextZoomApplyResult {
  state: BrowserWebTextZoomState;
  changed: boolean;
}

export class BrowserWebTextZoomViewModel {
  buildState(ratio: number): BrowserWebTextZoomState {
    const normalizedRatio = this.normalizeRatio(ratio);
    return {
      ratio: normalizedRatio,
      percentLabel: `${normalizedRatio}%`,
      canDecrease: normalizedRatio > BROWSER_WEB_TEXT_ZOOM_MIN_RATIO,
      canIncrease: normalizedRatio < BROWSER_WEB_TEXT_ZOOM_MAX_RATIO
    };
  }

  buildActionResult(currentRatio: number, action: BrowserWebTextZoomAction): BrowserWebTextZoomApplyResult {
    if (action === 'decrease') {
      return this.buildApplyResult(currentRatio, currentRatio - BROWSER_WEB_TEXT_ZOOM_STEP);
    }
    if (action === 'increase') {
      return this.buildApplyResult(currentRatio, currentRatio + BROWSER_WEB_TEXT_ZOOM_STEP);
    }
    return this.buildApplyResult(currentRatio, BROWSER_WEB_TEXT_ZOOM_DEFAULT_RATIO);
  }

  buildApplyResult(currentRatio: number, requestedRatio: number): BrowserWebTextZoomApplyResult {
    const state = this.buildState(requestedRatio);
    return {
      state: state,
      changed: state.ratio !== this.normalizeRatio(currentRatio)
    };
  }

  resolveEffectiveRatio(userRatio: number, systemFontSizeScale: number): number {
    const normalizedUserRatio = this.normalizeRatio(userRatio);
    const normalizedSystemScale = this.normalizeSystemFontSizeScale(systemFontSizeScale);
    const scaledRatio = Math.round(normalizedUserRatio * normalizedSystemScale);
    return Math.max(
      BROWSER_WEB_TEXT_ZOOM_MIN_RATIO,
      Math.min(BROWSER_WEB_EFFECTIVE_TEXT_ZOOM_MAX_RATIO, scaledRatio)
    );
  }

  normalizeRatio(ratio: number): number {
    if (!Number.isFinite(ratio)) {
      return BROWSER_WEB_TEXT_ZOOM_DEFAULT_RATIO;
    }
    const steppedRatio = Math.round(ratio / BROWSER_WEB_TEXT_ZOOM_STEP) * BROWSER_WEB_TEXT_ZOOM_STEP;
    return Math.max(BROWSER_WEB_TEXT_ZOOM_MIN_RATIO, Math.min(BROWSER_WEB_TEXT_ZOOM_MAX_RATIO, steppedRatio));
  }

  normalizeSystemFontSizeScale(scale: number): number {
    if (!Number.isFinite(scale)) {
      return BROWSER_SYSTEM_FONT_SIZE_SCALE_DEFAULT;
    }
    return Math.max(
      BROWSER_SYSTEM_FONT_SIZE_SCALE_MIN,
      Math.min(BROWSER_SYSTEM_FONT_SIZE_SCALE_MAX, scale)
    );
  }
}

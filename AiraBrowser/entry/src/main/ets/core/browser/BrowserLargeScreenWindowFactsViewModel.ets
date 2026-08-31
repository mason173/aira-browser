import {
  BrowserLargeScreenInputProfile,
  BrowserLargeScreenWindowProfile
} from './BrowserLargeScreenTabStripViewModel';

export type BrowserLargeScreenWindowMode = 'full' | 'free_window' | 'subwindow';

export interface BrowserLargeScreenWindowFactsInput {
  availableWidthVp: number;
  availableHeightVp: number;
  titleButtonWidthVp: number;
  titleButtonHeightVp: number;
  windowTitleBarIntegrated: boolean;
  safeTopInsetVp: number;
  safeBottomInsetVp: number;
  safeLeftInsetVp: number;
  safeRightInsetVp: number;
  windowMode: BrowserLargeScreenWindowMode;
  pointerAvailable: boolean;
  physicalKeyboardAvailable: boolean;
  dragSupported: boolean;
  keyboardHintsAvailable: boolean;
}

export interface BrowserLargeScreenWindowFactsPolicy {
  compactMaxWidthVp: number;
  compactMaxHeightVp: number;
  expandedMinWidthVp: number;
  expandedMinHeightVp: number;
}

export const DEFAULT_BROWSER_LARGE_SCREEN_WINDOW_FACTS_POLICY: BrowserLargeScreenWindowFactsPolicy = {
  compactMaxWidthVp: 720,
  compactMaxHeightVp: 560,
  expandedMinWidthVp: 1200,
  expandedMinHeightVp: 720
};

export interface BrowserLargeScreenWindowFactsSnapshot {
  availableWidthVp: number;
  availableHeightVp: number;
  titleButtonWidthVp: number;
  titleButtonHeightVp: number;
  windowTitleBarIntegrated: boolean;
  safeTopInsetVp: number;
  safeBottomInsetVp: number;
  safeLeftInsetVp: number;
  safeRightInsetVp: number;
  windowProfile: BrowserLargeScreenWindowProfile;
  inputProfile: BrowserLargeScreenInputProfile;
  dragSupported: boolean;
  keyboardHintsAvailable: boolean;
}

/**
 * Resolves the Large-Screen shell's internal window and input facts.
 *
 * The module receives already-read WindowStage/host capabilities. It does
 * not call platform APIs, select the Phone/Large-Screen family, or perform
 * any browser action. Thresholds remain an explicit policy input so device
 * acceptance can tune them without spreading width checks through UI code.
 */
export class BrowserLargeScreenWindowFactsViewModel {
  resolve(
    input: BrowserLargeScreenWindowFactsInput,
    policy: BrowserLargeScreenWindowFactsPolicy
  ): BrowserLargeScreenWindowFactsSnapshot {
    const safeTopInsetVp = this.normalizeNonNegativeDimension(input.safeTopInsetVp);
    const safeBottomInsetVp = this.normalizeNonNegativeDimension(input.safeBottomInsetVp);
    const safeLeftInsetVp = this.normalizeNonNegativeDimension(input.safeLeftInsetVp);
    const safeRightInsetVp = this.normalizeNonNegativeDimension(input.safeRightInsetVp);
    const availableWidthVp = Math.max(
      0,
      this.normalizeNonNegativeDimension(input.availableWidthVp) - safeLeftInsetVp - safeRightInsetVp
    );
    const availableHeightVp = Math.max(
      0,
      this.normalizeNonNegativeDimension(input.availableHeightVp) - safeTopInsetVp - safeBottomInsetVp
    );
    const titleButtonWidthVp = this.normalizeNonNegativeDimension(input.titleButtonWidthVp);
    const titleButtonHeightVp = this.normalizeNonNegativeDimension(input.titleButtonHeightVp);
    const normalizedPolicy = this.normalizePolicy(policy);
    return {
      availableWidthVp: availableWidthVp,
      availableHeightVp: availableHeightVp,
      titleButtonWidthVp: titleButtonWidthVp,
      titleButtonHeightVp: titleButtonHeightVp,
      windowTitleBarIntegrated: input.windowTitleBarIntegrated === true,
      safeTopInsetVp: safeTopInsetVp,
      safeBottomInsetVp: safeBottomInsetVp,
      safeLeftInsetVp: safeLeftInsetVp,
      safeRightInsetVp: safeRightInsetVp,
      windowProfile: this.resolveWindowProfile(
        input.windowMode,
        availableWidthVp,
        availableHeightVp,
        normalizedPolicy
      ),
      inputProfile: this.resolveInputProfile(input.pointerAvailable, input.physicalKeyboardAvailable),
      dragSupported: input.dragSupported === true,
      keyboardHintsAvailable: input.keyboardHintsAvailable === true && input.physicalKeyboardAvailable === true
    };
  }

  private resolveWindowProfile(
    windowMode: BrowserLargeScreenWindowMode,
    widthVp: number,
    heightVp: number,
    policy: BrowserLargeScreenWindowFactsPolicy
  ): BrowserLargeScreenWindowProfile {
    if (windowMode === 'subwindow') {
      return 'subwindow';
    }
    if (windowMode === 'free_window') {
      return 'free_window';
    }
    if (widthVp <= policy.compactMaxWidthVp || heightVp <= policy.compactMaxHeightVp) {
      return 'compact';
    }
    if (widthVp >= policy.expandedMinWidthVp && heightVp >= policy.expandedMinHeightVp) {
      return 'expanded';
    }
    return 'medium';
  }

  private resolveInputProfile(
    pointerAvailable: boolean,
    physicalKeyboardAvailable: boolean
  ): BrowserLargeScreenInputProfile {
    if (pointerAvailable === true && physicalKeyboardAvailable === true) {
      return 'keyboard_pointer';
    }
    if (pointerAvailable === true) {
      return 'pointer';
    }
    return 'touch';
  }

  private normalizePolicy(policy: BrowserLargeScreenWindowFactsPolicy): BrowserLargeScreenWindowFactsPolicy {
    const compactMaxWidthVp = this.normalizePositiveDimension(policy.compactMaxWidthVp, 1);
    const compactMaxHeightVp = this.normalizePositiveDimension(policy.compactMaxHeightVp, 1);
    const expandedMinWidthVp = Math.max(
      compactMaxWidthVp,
      this.normalizePositiveDimension(policy.expandedMinWidthVp, compactMaxWidthVp)
    );
    const expandedMinHeightVp = Math.max(
      compactMaxHeightVp,
      this.normalizePositiveDimension(policy.expandedMinHeightVp, compactMaxHeightVp)
    );
    return {
      compactMaxWidthVp: compactMaxWidthVp,
      compactMaxHeightVp: compactMaxHeightVp,
      expandedMinWidthVp: expandedMinWidthVp,
      expandedMinHeightVp: expandedMinHeightVp
    };
  }

  private normalizePositiveDimension(value: number, fallback: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return fallback;
    }
    return Math.max(1, Math.round(value));
  }

  private normalizeNonNegativeDimension(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }
}

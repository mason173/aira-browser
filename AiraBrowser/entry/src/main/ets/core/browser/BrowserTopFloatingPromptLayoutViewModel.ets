// Desktop notifications should read as compact status cards instead of a
// toolbar-spanning banner. Narrow windows still use their available width.
export const BROWSER_TOP_FLOATING_PROMPT_MAX_WIDTH_VP: number = 480;

export interface BrowserTopFloatingPromptLayoutInput {
  containerWidthVp: number;
  horizontalMarginVp: number;
}

export interface BrowserTopFloatingPromptLayoutState {
  surfaceWidthVp: number;
  surfaceLeftVp: number;
}

/**
 * Owns the responsive width policy for the browser's shared top prompt lane.
 *
 * Narrow containers retain the existing edge margins. Wider desktop
 * containers cap the prompt width and center it without changing the prompt
 * content, actions, queueing, or animation ownership.
 */
export class BrowserTopFloatingPromptLayoutViewModel {
  resolve(input: BrowserTopFloatingPromptLayoutInput): BrowserTopFloatingPromptLayoutState {
    const containerWidthVp = this.normalizeNonNegativeDimension(input.containerWidthVp);
    const horizontalMarginVp = this.normalizeNonNegativeDimension(input.horizontalMarginVp);
    if (containerWidthVp <= 0) {
      return {
        surfaceWidthVp: 0,
        surfaceLeftVp: horizontalMarginVp
      };
    }
    const availableWidthVp = Math.max(1, containerWidthVp - horizontalMarginVp * 2);
    const surfaceWidthVp = Math.min(BROWSER_TOP_FLOATING_PROMPT_MAX_WIDTH_VP, availableWidthVp);
    return {
      surfaceWidthVp: surfaceWidthVp,
      surfaceLeftVp: Math.max(horizontalMarginVp, (containerWidthVp - surfaceWidthVp) / 2)
    };
  }

  private normalizeNonNegativeDimension(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return value;
  }
}

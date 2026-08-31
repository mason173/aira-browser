export interface BrowserViewportState {
  width: number;
  height: number;
}

export interface BrowserStableViewportInput {
  nextWidth: number;
  nextHeight: number;
  currentViewport: BrowserViewportState;
  keepStableOnShrink: boolean;
}

export class BrowserViewportStabilityPolicy {
  buildViewport(width: number, height: number): BrowserViewportState {
    return {
      width: Math.max(1, Math.round(width)),
      height: Math.max(1, Math.round(height))
    };
  }

  resolve(input: BrowserStableViewportInput): BrowserViewportState {
    const nextViewport = this.buildViewport(input.nextWidth, input.nextHeight);
    const currentWidth = Math.max(0, input.currentViewport.width);
    const currentHeight = Math.max(0, input.currentViewport.height);
    if (this.hasOrientationChanged(nextViewport, input.currentViewport)) {
      return nextViewport;
    }
    if (input.keepStableOnShrink && nextViewport.height < currentHeight) {
      return {
        width: currentWidth > 0 ? currentWidth : nextViewport.width,
        height: currentHeight
      };
    }
    return nextViewport;
  }

  hasOrientationChanged(nextViewport: BrowserViewportState, stableViewport: BrowserViewportState): boolean {
    if (nextViewport.width <= 0 || nextViewport.height <= 0 ||
      stableViewport.width <= 0 || stableViewport.height <= 0) {
      return false;
    }
    return this.resolveOrientation(nextViewport) !== this.resolveOrientation(stableViewport);
  }

  private resolveOrientation(viewport: BrowserViewportState): string {
    return viewport.width > viewport.height ? 'landscape' : 'portrait';
  }
}

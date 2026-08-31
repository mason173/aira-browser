export type AppWindowWidthClass = 'xs' | 'sm' | 'md' | 'lg' | 'xl' | 'xxl';
export type AppWindowAspectClass = 'wide' | 'regular' | 'tall';
export type AppWindowOrientation = 'portrait' | 'landscape';

export interface AppWindowViewport {
  width: number;
  height: number;
}

export interface AppWindowViewportInput {
  viewportWidth: number;
  viewportHeight: number;
  displayViewportWidth?: number;
  displayViewportHeight?: number;
}

export interface AppWindowResponsiveFacts extends AppWindowViewport {
  widthClass: AppWindowWidthClass;
  aspectClass: AppWindowAspectClass;
  orientation: AppWindowOrientation;
}

const APP_WINDOW_XS_MAX_WIDTH: number = 360;
const APP_WINDOW_MD_MIN_WIDTH: number = 600;
const APP_WINDOW_LG_MIN_WIDTH: number = 840;
const APP_WINDOW_XL_MIN_WIDTH: number = 1200;
const APP_WINDOW_XXL_MIN_WIDTH: number = 1440;
const APP_WINDOW_WIDE_MAX_ASPECT_RATIO: number = 0.8;
const APP_WINDOW_REGULAR_MAX_ASPECT_RATIO: number = 1.2;
const DISPLAY_VIEWPORT_MATCH_TOLERANCE_VP: number = 8;

/** Owns the canonical app-window viewport and responsive classifications. */
export class AppWindowResponsiveLayoutService {
  resolve(input: AppWindowViewportInput): AppWindowResponsiveFacts {
    const viewport = this.resolveViewport(input);
    return {
      width: viewport.width,
      height: viewport.height,
      widthClass: this.resolveWidthClass(viewport.width),
      aspectClass: this.resolveAspectClass(viewport.width, viewport.height),
      orientation: this.resolveOrientation(viewport.width, viewport.height)
    };
  }

  resolveViewport(input: AppWindowViewportInput): AppWindowViewport {
    const rootViewport = this.buildViewport(input.viewportWidth, input.viewportHeight);
    const displayWidth = Math.max(0, input.displayViewportWidth ?? 0);
    const displayHeight = Math.max(0, input.displayViewportHeight ?? 0);
    if (displayWidth <= 0 || displayHeight <= 0) {
      return rootViewport;
    }
    const displayViewport = this.buildViewport(displayWidth, displayHeight);
    if (this.resolveOrientation(rootViewport.width, rootViewport.height) !==
      this.resolveOrientation(displayViewport.width, displayViewport.height) &&
      this.matchesShapeIgnoringOrientation(rootViewport, displayViewport)) {
      return displayViewport;
    }
    return rootViewport;
  }

  resolveWidthClass(width: number): AppWindowWidthClass {
    const normalizedWidth = Math.max(0, width);
    if (normalizedWidth >= APP_WINDOW_XXL_MIN_WIDTH) {
      return 'xxl';
    }
    if (normalizedWidth >= APP_WINDOW_XL_MIN_WIDTH) {
      return 'xl';
    }
    if (normalizedWidth >= APP_WINDOW_LG_MIN_WIDTH) {
      return 'lg';
    }
    if (normalizedWidth >= APP_WINDOW_MD_MIN_WIDTH) {
      return 'md';
    }
    if (normalizedWidth < APP_WINDOW_XS_MAX_WIDTH) {
      return 'xs';
    }
    return 'sm';
  }

  resolveAspectClass(width: number, height: number): AppWindowAspectClass {
    if (width <= 0 || height <= 0) {
      return 'tall';
    }
    const heightWidthRatio = height / width;
    if (heightWidthRatio < APP_WINDOW_WIDE_MAX_ASPECT_RATIO) {
      return 'wide';
    }
    if (heightWidthRatio < APP_WINDOW_REGULAR_MAX_ASPECT_RATIO) {
      return 'regular';
    }
    return 'tall';
  }

  isAtLeastWidthClass(widthClass: AppWindowWidthClass, minimum: AppWindowWidthClass): boolean {
    return this.resolveWidthClassRank(widthClass) >= this.resolveWidthClassRank(minimum);
  }

  private buildViewport(width: number, height: number): AppWindowViewport {
    return {
      width: Math.max(1, Math.round(width)),
      height: Math.max(1, Math.round(height))
    };
  }

  private resolveOrientation(width: number, height: number): AppWindowOrientation {
    return width > height ? 'landscape' : 'portrait';
  }

  private matchesShapeIgnoringOrientation(
    rootViewport: AppWindowViewport,
    displayViewport: AppWindowViewport
  ): boolean {
    return Math.abs(rootViewport.width - displayViewport.height) <= DISPLAY_VIEWPORT_MATCH_TOLERANCE_VP &&
      Math.abs(rootViewport.height - displayViewport.width) <= DISPLAY_VIEWPORT_MATCH_TOLERANCE_VP;
  }

  private resolveWidthClassRank(widthClass: AppWindowWidthClass): number {
    switch (widthClass) {
      case 'xxl':
        return 5;
      case 'xl':
        return 4;
      case 'lg':
        return 3;
      case 'md':
        return 2;
      case 'sm':
        return 1;
      case 'xs':
      default:
        return 0;
    }
  }
}

import {
  AppWindowResponsiveLayoutService
} from '../../services/layout/AppWindowResponsiveLayoutService';

export interface BrowserSheetResponsiveLayoutInput {
  containerWidth: number;
  explicitMaxWidth: number;
}

export interface BrowserSheetResponsiveLayoutState {
  surfaceMaxWidth: number;
}

const BROWSER_SHEET_MEDIUM_MAX_WIDTH: number = 560;
const BROWSER_SHEET_LARGE_MAX_WIDTH: number = 680;
const BROWSER_SHEET_WIDE_MAX_WIDTH: number = 720;

export class BrowserSheetResponsiveLayoutViewModel {
  private readonly responsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  buildState(input: BrowserSheetResponsiveLayoutInput): BrowserSheetResponsiveLayoutState {
    const explicitMaxWidth = Math.max(0, input.explicitMaxWidth);
    if (explicitMaxWidth > 0) {
      return { surfaceMaxWidth: explicitMaxWidth };
    }
    const width = Math.max(0, input.containerWidth);
    const widthClass = this.responsiveLayoutService.resolveWidthClass(width);
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'xl')) {
      return { surfaceMaxWidth: BROWSER_SHEET_WIDE_MAX_WIDTH };
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'lg')) {
      return { surfaceMaxWidth: BROWSER_SHEET_LARGE_MAX_WIDTH };
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'md')) {
      return { surfaceMaxWidth: BROWSER_SHEET_MEDIUM_MAX_WIDTH };
    }
    return { surfaceMaxWidth: 0 };
  }
}

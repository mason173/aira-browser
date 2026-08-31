import {
  SETTINGS_CANVAS_CONTENT_LARGE_HORIZONTAL_INSET,
  SETTINGS_CANVAS_CONTENT_MEDIUM_HORIZONTAL_INSET,
  SETTINGS_CANVAS_CONTENT_WIDE_HORIZONTAL_INSET,
  SETTINGS_READABLE_CONTENT_MAX_WIDTH,
  SETTINGS_STANDARD_CONTENT_LARGE_HORIZONTAL_INSET,
  SETTINGS_STANDARD_CONTENT_MEDIUM_HORIZONTAL_INSET,
  SETTINGS_STANDARD_CONTENT_WIDE_HORIZONTAL_INSET
} from './SettingsLayoutTokens';
import {
  AppWindowWidthClass,
  AppWindowResponsiveLayoutService
} from '../../services/layout/AppWindowResponsiveLayoutService';

export type SettingsContentKind = 'standard' | 'readable' | 'canvas' | 'unframed';

export interface SettingsContentLayoutInput {
  containerWidth: number;
  kind: SettingsContentKind;
}

export interface SettingsContentLayoutState {
  horizontalInset: number;
  maxWidth: number;
}

export class SettingsContentLayoutPolicy {
  private readonly responsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  resolve(input: SettingsContentLayoutInput): SettingsContentLayoutState {
    if (input.kind === 'unframed') {
      return {
        horizontalInset: 0,
        maxWidth: 0
      };
    }
    const width = Math.max(0, input.containerWidth);
    const widthClass = this.responsiveLayoutService.resolveWidthClass(width);
    const maxWidth = input.kind === 'readable' &&
      this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'lg') ?
      SETTINGS_READABLE_CONTENT_MAX_WIDTH :
      0;
    return {
      horizontalInset: input.kind === 'canvas' ?
        this.resolveCanvasHorizontalInset(widthClass) :
        this.resolveStandardHorizontalInset(widthClass),
      maxWidth: maxWidth
    };
  }

  private resolveStandardHorizontalInset(widthClass: AppWindowWidthClass): number {
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'xl')) {
      return SETTINGS_STANDARD_CONTENT_WIDE_HORIZONTAL_INSET;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'lg')) {
      return SETTINGS_STANDARD_CONTENT_LARGE_HORIZONTAL_INSET;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'md')) {
      return SETTINGS_STANDARD_CONTENT_MEDIUM_HORIZONTAL_INSET;
    }
    return 0;
  }

  private resolveCanvasHorizontalInset(widthClass: AppWindowWidthClass): number {
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'xl')) {
      return SETTINGS_CANVAS_CONTENT_WIDE_HORIZONTAL_INSET;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'lg')) {
      return SETTINGS_CANVAS_CONTENT_LARGE_HORIZONTAL_INSET;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'md')) {
      return SETTINGS_CANVAS_CONTENT_MEDIUM_HORIZONTAL_INSET;
    }
    return 0;
  }
}

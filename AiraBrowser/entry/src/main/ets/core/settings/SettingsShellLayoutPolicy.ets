import { SettingsNavigationShellMode } from './SettingsDestinationNavigationOwner';
import {
  SETTINGS_SHELL_BOTTOM_INSET,
  SETTINGS_SHELL_COMPACT_HORIZONTAL_INSET,
  SETTINGS_SHELL_COMPACT_PANE_GAP,
  SETTINGS_SHELL_COMPACT_SIDEBAR_WIDTH,
  SETTINGS_SHELL_EXTRA_WIDE_SIDEBAR_WIDTH,
  SETTINGS_SHELL_MEDIUM_HORIZONTAL_INSET,
  SETTINGS_SHELL_MEDIUM_SIDEBAR_WIDTH,
  SETTINGS_SHELL_PANE_GAP,
  SETTINGS_SHELL_TWO_PANE_MIN_WIDTH,
  SETTINGS_SHELL_WIDE_BOTTOM_INSET,
  SETTINGS_SHELL_WIDE_HORIZONTAL_INSET,
  SETTINGS_SHELL_WIDE_SIDEBAR_WIDTH,
  SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_MAX_RATIO,
  SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_MAX_WIDTH,
  SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_PREFERRED_RATIO,
  SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_SOFT_MIN_WIDTH
} from './SettingsLayoutTokens';
import {
  AppWindowWidthClass,
  AppWindowResponsiveLayoutService
} from '../../services/layout/AppWindowResponsiveLayoutService';

export interface SettingsShellLayoutInput {
  viewportWidth: number;
  mode?: SettingsNavigationShellMode;
  sidebarSizing?: SettingsSidebarSizingMode;
}

export type SettingsSidebarSizingMode = 'stepped' | 'window_relative';

export interface SettingsShellLayoutState {
  mode: SettingsNavigationShellMode;
  sidebarWidth: number;
  horizontalInset: number;
  paneGap: number;
  bottomInset: number;
}

export const DEFAULT_SETTINGS_TWO_PANE_LAYOUT_STATE: SettingsShellLayoutState = {
  mode: 'twoPane',
  sidebarWidth: SETTINGS_SHELL_MEDIUM_SIDEBAR_WIDTH,
  horizontalInset: SETTINGS_SHELL_MEDIUM_HORIZONTAL_INSET,
  paneGap: SETTINGS_SHELL_PANE_GAP,
  bottomInset: SETTINGS_SHELL_BOTTOM_INSET
};

export class SettingsShellLayoutPolicy {
  private readonly responsiveLayoutService: AppWindowResponsiveLayoutService =
    new AppWindowResponsiveLayoutService();

  resolve(input: SettingsShellLayoutInput): SettingsShellLayoutState {
    const width = Math.max(0, input.viewportWidth);
    const widthClass = this.responsiveLayoutService.resolveWidthClass(width);
    const mode: SettingsNavigationShellMode = input.mode ??
      (width >= SETTINGS_SHELL_TWO_PANE_MIN_WIDTH ? 'twoPane' : 'compact');
    return {
      mode: mode,
      sidebarWidth: this.resolveSidebarWidth(
        width,
        widthClass,
        mode,
        input.sidebarSizing ?? 'stepped'
      ),
      horizontalInset: this.resolveHorizontalInset(width, widthClass, mode),
      paneGap: mode === 'compact' ? SETTINGS_SHELL_COMPACT_PANE_GAP : SETTINGS_SHELL_PANE_GAP,
      bottomInset: this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'xl') ?
        SETTINGS_SHELL_WIDE_BOTTOM_INSET :
        SETTINGS_SHELL_BOTTOM_INSET
    };
  }

  private resolveSidebarWidth(
    width: number,
    widthClass: AppWindowWidthClass,
    mode: SettingsNavigationShellMode,
    sizingMode: SettingsSidebarSizingMode
  ): number {
    if (mode === 'compact') {
      return 0;
    }
    if (sizingMode === 'window_relative') {
      return this.resolveWindowRelativeSidebarWidth(width);
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'xxl')) {
      return SETTINGS_SHELL_EXTRA_WIDE_SIDEBAR_WIDTH;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'xl')) {
      return SETTINGS_SHELL_WIDE_SIDEBAR_WIDTH;
    }
    if (width >= SETTINGS_SHELL_TWO_PANE_MIN_WIDTH) {
      return SETTINGS_SHELL_MEDIUM_SIDEBAR_WIDTH;
    }
    return SETTINGS_SHELL_COMPACT_SIDEBAR_WIDTH;
  }

  private resolveWindowRelativeSidebarWidth(width: number): number {
    const preferredWidth = Math.max(
      SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_SOFT_MIN_WIDTH,
      width * SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_PREFERRED_RATIO
    );
    const viewportCap = Math.max(1, width * SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_MAX_RATIO);
    return Math.max(1, Math.round(Math.min(
      preferredWidth,
      SETTINGS_SHELL_WINDOW_RELATIVE_SIDEBAR_MAX_WIDTH,
      viewportCap
    )));
  }

  private resolveHorizontalInset(
    width: number,
    widthClass: AppWindowWidthClass,
    mode: SettingsNavigationShellMode
  ): number {
    if (mode === 'compact') {
      return 0;
    }
    if (this.responsiveLayoutService.isAtLeastWidthClass(widthClass, 'xl')) {
      return SETTINGS_SHELL_WIDE_HORIZONTAL_INSET;
    }
    if (width >= SETTINGS_SHELL_TWO_PANE_MIN_WIDTH) {
      return SETTINGS_SHELL_MEDIUM_HORIZONTAL_INSET;
    }
    return SETTINGS_SHELL_COMPACT_HORIZONTAL_INSET;
  }
}

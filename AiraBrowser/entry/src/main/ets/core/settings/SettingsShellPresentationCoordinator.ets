import { BrowserShellFamily } from '../browser/BrowserWindowPresentationProfile';
import {
  SettingsNavigationShellMode
} from './SettingsDestinationNavigationOwner';
import {
  SettingsShellLayoutPolicy,
  SettingsShellLayoutState
} from './SettingsShellLayoutPolicy';

export type SettingsPresentationShellFamily = 'phone' | 'large_screen';

export interface SettingsShellPresentationInput {
  viewportWidth: number;
  browserShellFamily?: BrowserShellFamily;
}

export interface SettingsShellPresentationState {
  family: SettingsPresentationShellFamily;
  navigationMode: SettingsNavigationShellMode;
  layoutState: SettingsShellLayoutState;
  decisionReason: string;
}

export const DEFAULT_SETTINGS_PHONE_SHELL_PRESENTATION_STATE: SettingsShellPresentationState = {
  family: 'phone',
  navigationMode: 'compact',
  layoutState: {
    mode: 'compact',
    sidebarWidth: 0,
    horizontalInset: 0,
    paneGap: 0,
    bottomInset: 0
  },
  decisionReason: 'initial-phone-presentation'
};

/** Keeps interaction-shell selection separate from responsive pane geometry. */
export class SettingsShellPresentationCoordinator {
  private readonly layoutPolicy: SettingsShellLayoutPolicy = new SettingsShellLayoutPolicy();

  resolve(input: SettingsShellPresentationInput): SettingsShellPresentationState {
    const family: SettingsPresentationShellFamily =
      input.browserShellFamily === 'large_screen' ? 'large_screen' : 'phone';
    const touchLayoutState = this.layoutPolicy.resolve({
      viewportWidth: input.viewportWidth
    });
    const navigationMode: SettingsNavigationShellMode = family === 'large_screen'
      ? 'twoPane'
      : (touchLayoutState.mode === 'twoPane' ? 'touchTwoPane' : 'compact');
    const layoutState = this.layoutPolicy.resolve({
      viewportWidth: input.viewportWidth,
      mode: navigationMode,
      sidebarSizing: family === 'large_screen' ? 'window_relative' : 'stepped'
    });
    return {
      family: family,
      navigationMode: navigationMode,
      layoutState: layoutState,
      decisionReason: family === 'large_screen'
        ? 'browser-window-session-pc-shell'
        : (navigationMode !== 'compact'
          ? 'touch-viewport-two-pane-presentation'
          : 'touch-viewport-compact-presentation')
    };
  }
}

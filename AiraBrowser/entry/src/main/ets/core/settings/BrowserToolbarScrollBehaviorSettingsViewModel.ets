import {
  BrowserAppearanceSettings,
  BrowserBottomToolbarScrollBehavior,
  BrowserToolbarChromeStyle
} from '../../common/models/BrowserModels';
import {
  isSplitFamilyStyle,
  resolveSplitToolbarScrollBehavior
} from '../browser/BrowserToolbarChromeStylePolicy';

export interface BrowserToolbarScrollBehaviorOptionState {
  behavior: BrowserBottomToolbarScrollBehavior;
  title: ResourceStr;
}

export interface BrowserToolbarScrollBehaviorSettingsState {
  behavior: BrowserBottomToolbarScrollBehavior;
  options: BrowserToolbarScrollBehaviorOptionState[];
  footerText: ResourceStr;
}

const BROWSER_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS: BrowserToolbarScrollBehaviorOptionState[] = [
  { behavior: 'fixed', title: $r('app.string.toolbar_settings_scroll_fixed') },
  { behavior: 'compact', title: $r('app.string.toolbar_settings_scroll_compact') },
  { behavior: 'hidden', title: $r('app.string.toolbar_settings_scroll_hidden') }
];

const SPLIT_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS: BrowserToolbarScrollBehaviorOptionState[] = [
  { behavior: 'fixed', title: $r('app.string.toolbar_settings_scroll_split_fixed') },
  { behavior: 'hidden', title: $r('app.string.toolbar_settings_scroll_split_hidden') }
];

const FLOATING_TOOLBAR_SCROLL_BEHAVIOR_FOOTER: ResourceStr =
  $r('app.string.toolbar_settings_scroll_footer_floating');
const SPLIT_TOOLBAR_SCROLL_BEHAVIOR_FOOTER: ResourceStr =
  $r('app.string.toolbar_settings_scroll_footer_split');

export class BrowserToolbarScrollBehaviorSettingsViewModel {
  buildState(appearance: BrowserAppearanceSettings): BrowserToolbarScrollBehaviorSettingsState {
    return this.buildStateForBehavior(
      appearance.bottomToolbarScrollBehavior,
      appearance.toolbarChromeStyle
    );
  }

  buildStateForBehavior(
    behavior: BrowserBottomToolbarScrollBehavior,
    style: BrowserToolbarChromeStyle = 'floating'
  ): BrowserToolbarScrollBehaviorSettingsState {
    if (isSplitFamilyStyle(style)) {
      return {
        behavior: resolveSplitToolbarScrollBehavior(behavior),
        options: SPLIT_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS.slice(),
        footerText: SPLIT_TOOLBAR_SCROLL_BEHAVIOR_FOOTER
      };
    }
    return {
      behavior: behavior,
      options: BROWSER_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS.slice(),
      footerText: FLOATING_TOOLBAR_SCROLL_BEHAVIOR_FOOTER
    };
  }

  formatBehaviorTitle(
    behavior: BrowserBottomToolbarScrollBehavior,
    style: BrowserToolbarChromeStyle = 'floating'
  ): ResourceStr {
    const splitFamily = isSplitFamilyStyle(style);
    const resolved = splitFamily ? resolveSplitToolbarScrollBehavior(behavior) : behavior;
    const options = splitFamily ?
      SPLIT_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS : BROWSER_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS;
    const option = options.find(
      (item: BrowserToolbarScrollBehaviorOptionState): boolean => item.behavior === resolved
    );
    return option?.title ?? (splitFamily ?
      $r('app.string.toolbar_settings_scroll_split_fixed') :
      $r('app.string.toolbar_settings_scroll_fixed'));
  }
}

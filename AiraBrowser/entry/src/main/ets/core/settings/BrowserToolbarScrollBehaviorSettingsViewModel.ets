import {
  BrowserAppearanceSettings,
  BrowserBottomToolbarScrollBehavior,
  BrowserToolbarChromeStyle
} from '../../common/models/BrowserModels';
import { resolveSplitToolbarScrollBehavior } from '../browser/BrowserToolbarChromeStylePolicy';

export interface BrowserToolbarScrollBehaviorOptionState {
  behavior: BrowserBottomToolbarScrollBehavior;
  title: string;
}

export interface BrowserToolbarScrollBehaviorSettingsState {
  behavior: BrowserBottomToolbarScrollBehavior;
  options: BrowserToolbarScrollBehaviorOptionState[];
  footerText: string;
}

const BROWSER_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS: BrowserToolbarScrollBehaviorOptionState[] = [
  { behavior: 'fixed', title: '始终显示' },
  { behavior: 'compact', title: '收起为胶囊' },
  { behavior: 'hidden', title: '完全隐藏' }
];

const SPLIT_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS: BrowserToolbarScrollBehaviorOptionState[] = [
  { behavior: 'fixed', title: '固定' },
  { behavior: 'hidden', title: '收起地址栏和工具栏' }
];

const FLOATING_TOOLBAR_SCROLL_BEHAVIOR_FOOTER: string =
  '收起为胶囊时只留一排按钮，完全隐藏时工具栏移出屏幕。停止滚动后保持当前状态，向上滚动后恢复。';
const SPLIT_TOOLBAR_SCROLL_BEHAVIOR_FOOTER: string =
  '固定时地址栏和底部工具栏保持显示。收起时会在向下滚动网页时同时隐藏它们，向上滚动后恢复。';

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
    if (style === 'split') {
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
  ): string {
    const resolved = style === 'split' ? resolveSplitToolbarScrollBehavior(behavior) : behavior;
    const options = style === 'split' ?
      SPLIT_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS : BROWSER_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS;
    const option = options.find(
      (item: BrowserToolbarScrollBehaviorOptionState): boolean => item.behavior === resolved
    );
    return option?.title ?? (style === 'split' ? '固定' : '始终显示');
  }
}

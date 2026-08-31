import {
  BrowserAppearanceSettings,
  BrowserBottomToolbarScrollBehavior
} from '../../common/models/BrowserModels';

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
  { behavior: 'compact', title: '滚动时收起' },
  { behavior: 'hidden', title: '滚动时隐藏' }
];

export class BrowserToolbarScrollBehaviorSettingsViewModel {
  buildState(appearance: BrowserAppearanceSettings): BrowserToolbarScrollBehaviorSettingsState {
    return this.buildStateForBehavior(appearance.bottomToolbarScrollBehavior);
  }

  buildStateForBehavior(
    behavior: BrowserBottomToolbarScrollBehavior
  ): BrowserToolbarScrollBehaviorSettingsState {
    return {
      behavior: behavior,
      options: BROWSER_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS.slice(),
      footerText: '收起时工具栏变为胶囊，隐藏时工具栏完全移出屏幕。停止滚动后保持当前状态，向反方向滚动时恢复。'
    };
  }

  formatBehaviorTitle(behavior: BrowserBottomToolbarScrollBehavior): string {
    const option = BROWSER_TOOLBAR_SCROLL_BEHAVIOR_OPTIONS.find(
      (item: BrowserToolbarScrollBehaviorOptionState): boolean => item.behavior === behavior
    );
    return option?.title ?? '滚动时收起';
  }
}

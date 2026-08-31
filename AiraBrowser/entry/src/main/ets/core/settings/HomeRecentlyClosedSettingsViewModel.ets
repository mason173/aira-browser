import { BrowserAppearanceSettings } from '../../common/models/BrowserModels';

export type HomeRecentlyClosedOptionRowPosition = 'single' | 'first' | 'middle' | 'last';

export interface HomeRecentlyClosedOptionState {
  limit: number;
  title: string;
  rowPosition: HomeRecentlyClosedOptionRowPosition;
  isSelected: boolean;
  radioValue: string;
  renderKey: string;
}

export interface HomeRecentlyClosedSettingsState {
  summaryLabel: string;
  options: HomeRecentlyClosedOptionState[];
}

const HIDDEN_OPTION: number = 0;
const DISPLAY_OPTIONS: number[] = [HIDDEN_OPTION, 3, 5, 8, 12, 24];

export class HomeRecentlyClosedSettingsViewModel {
  buildState(settings: BrowserAppearanceSettings): HomeRecentlyClosedSettingsState {
    const selectedLimit = this.resolveSelectedLimit(settings);
    return {
      summaryLabel: this.formatSummaryLabel(settings),
      options: DISPLAY_OPTIONS.map((limit: number, index: number): HomeRecentlyClosedOptionState => {
        const isSelected = limit === selectedLimit;
        return {
          limit: limit,
          title: this.formatOptionTitle(limit),
          rowPosition: this.resolveRowPosition(index, DISPLAY_OPTIONS.length),
          isSelected: isSelected,
          radioValue: `${limit}`,
          renderKey: `${limit}:${isSelected ? '1' : '0'}`
        };
      })
    };
  }

  formatSummaryLabel(settings: BrowserAppearanceSettings): string {
    if (!settings.showHomeRecentlyClosed) {
      return '不显示';
    }
    return this.formatOptionTitle(settings.homeRecentlyClosedLimit);
  }

  buildAppearanceSettingsWithLimit(
    current: BrowserAppearanceSettings,
    limit: number
  ): BrowserAppearanceSettings {
    const showHomeRecentlyClosed = limit !== HIDDEN_OPTION;
    return {
      bottomToolbarScrollBehavior: current.bottomToolbarScrollBehavior,
      globalImmersionEnabled: current.globalImmersionEnabled,
      alwaysTopImmersionEnabled: current.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: current.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: current.blurPrivateTabPreviews,
      showHomeRecentlyClosed: showHomeRecentlyClosed,
      showHomeShortcuts: current.showHomeShortcuts,
      homeRecentlyClosedLimit: showHomeRecentlyClosed ? limit : current.homeRecentlyClosedLimit,
      homeShortcutLayoutDensity: current.homeShortcutLayoutDensity,
      homeShortcutIconSizeRatio: current.homeShortcutIconSizeRatio,
      siteIconCornerRadiusRatio: current.siteIconCornerRadiusRatio,
      themePaletteId: current.themePaletteId,
      tabsOverviewLayoutStyle: current.tabsOverviewLayoutStyle,
      tabsOverviewCloseButtonAlwaysVisible: current.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: current.showDesktopBookmarkBar
    };
  }

  private resolveSelectedLimit(settings: BrowserAppearanceSettings): number {
    return settings.showHomeRecentlyClosed ? settings.homeRecentlyClosedLimit : HIDDEN_OPTION;
  }

  private formatOptionTitle(limit: number): string {
    if (limit === HIDDEN_OPTION) {
      return '不显示';
    }
    return `${limit} 条`;
  }

  private resolveRowPosition(
    index: number,
    count: number
  ): HomeRecentlyClosedOptionRowPosition {
    if (count <= 1) {
      return 'single';
    }
    if (index <= 0) {
      return 'first';
    }
    if (index >= count - 1) {
      return 'last';
    }
    return 'middle';
  }
}

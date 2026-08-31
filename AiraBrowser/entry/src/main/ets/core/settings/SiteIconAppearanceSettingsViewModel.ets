import { BrowserAppearanceSettings } from '../../common/models/BrowserModels';

export const HOME_SHORTCUT_ICON_SIZE_MIN_RATIO: number = 0.45;
export const HOME_SHORTCUT_ICON_SIZE_MAX_RATIO: number = 1;
export const SITE_ICON_CORNER_RADIUS_MIN_RATIO: number = 0.12;
export const SITE_ICON_CORNER_RADIUS_MAX_RATIO: number = 0.5;

export class SiteIconAppearanceSettingsViewModel {
  normalizeIconSizeRatio(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0.54;
    }
    return Math.max(
      HOME_SHORTCUT_ICON_SIZE_MIN_RATIO,
      Math.min(HOME_SHORTCUT_ICON_SIZE_MAX_RATIO, Math.round(value * 100) / 100)
    );
  }

  normalizeCornerRadiusRatio(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0.3;
    }
    return Math.max(
      SITE_ICON_CORNER_RADIUS_MIN_RATIO,
      Math.min(SITE_ICON_CORNER_RADIUS_MAX_RATIO, Math.round(value * 100) / 100)
    );
  }

  ratioToSliderValue(ratio: number): number {
    return Math.round(ratio * 100);
  }

  sliderValueToIconSizeRatio(value: number): number {
    return this.normalizeIconSizeRatio(value / 100);
  }

  sliderValueToCornerRadiusRatio(value: number): number {
    return this.normalizeCornerRadiusRatio(value / 100);
  }

  formatIconSizeLabel(ratio: number): string {
    return `主页图标大小 ${this.ratioToSliderValue(this.normalizeIconSizeRatio(ratio))}%`;
  }

  formatCornerRadiusLabel(ratio: number): string {
    return `图标圆角 ${this.ratioToSliderValue(this.normalizeCornerRadiusRatio(ratio))}%`;
  }

  formatSummaryLabel(iconSizeRatio: number, cornerRadiusRatio: number): string {
    const size = this.ratioToSliderValue(this.normalizeIconSizeRatio(iconSizeRatio));
    const radius = this.ratioToSliderValue(this.normalizeCornerRadiusRatio(cornerRadiusRatio));
    return `大小 ${size}% · 圆角 ${radius}%`;
  }

  resolvePreviewCornerRadius(size: number, cornerRadiusRatio: number): number {
    return Math.round(size * this.normalizeCornerRadiusRatio(cornerRadiusRatio));
  }

  resolvePreviewImageSize(size: number, iconSizeRatio: number): number {
    const padding = this.resolvePreviewContentPadding(size, iconSizeRatio);
    return Math.max(0, size - padding * 2);
  }

  resolvePreviewImageCornerRadius(
    size: number,
    iconSizeRatio: number,
    cornerRadiusRatio: number
  ): number {
    const cornerRadius = this.resolvePreviewCornerRadius(size, cornerRadiusRatio);
    const padding = this.resolvePreviewContentPadding(size, iconSizeRatio);
    return Math.max(0, cornerRadius - padding);
  }

  buildAppearanceSettings(
    current: BrowserAppearanceSettings,
    iconSizeRatio: number,
    cornerRadiusRatio: number
  ): BrowserAppearanceSettings {
    return {
      bottomToolbarScrollBehavior: current.bottomToolbarScrollBehavior,
      globalImmersionEnabled: current.globalImmersionEnabled,
      alwaysTopImmersionEnabled: current.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: current.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: current.blurPrivateTabPreviews,
      showHomeRecentlyClosed: current.showHomeRecentlyClosed,
      showHomeShortcuts: current.showHomeShortcuts,
      homeRecentlyClosedLimit: current.homeRecentlyClosedLimit,
      homeShortcutLayoutDensity: current.homeShortcutLayoutDensity,
      homeShortcutIconSizeRatio: this.normalizeIconSizeRatio(iconSizeRatio),
      siteIconCornerRadiusRatio: this.normalizeCornerRadiusRatio(cornerRadiusRatio),
      themePaletteId: current.themePaletteId,
      tabsOverviewLayoutStyle: current.tabsOverviewLayoutStyle,
      tabsOverviewCloseButtonAlwaysVisible: current.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: current.showDesktopBookmarkBar
    };
  }

  private resolvePreviewContentPadding(size: number, iconSizeRatio: number): number {
    return Math.max(0, Math.round(size * (1 - this.normalizeIconSizeRatio(iconSizeRatio)) / 2));
  }
}
